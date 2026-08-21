RM = RM or {}
RM.bus = {}

-- one event name each way, channels inside. BeamMP shares this pipe with
-- vehicle position sync, so everything is queued and flushed once per tick.
local C2S_EVENT = "rm:c2s"
local S2C_EVENT = "rm:s2c"

local queues   = {}
local channels = {}
local rate     = {}
local stats    = { sent = 0, recv = 0, dropped = 0, refused = 0, flushes = 0 }

local function queueFor(pid)
  local q = queues[pid]
  if not q then
    q = {}
    queues[pid] = q
  end
  return q
end

function RM.bus.queue(pid, channel, payload)
  local q = queueFor(pid)
  local n = #q
  if n >= RM.config.maxBatchMsgs then
    stats.dropped = stats.dropped + 1
    if stats.dropped % 50 == 1 then
      RM.warn(("bus queue full for player %d, dropping '%s' (%d dropped)")
        :format(pid, channel, stats.dropped))
    end
    return false
  end
  local m = RM.util.take()
  m.c, m.d = channel, payload
  q[n + 1] = m
  return true
end

-- sessions rather than MP.GetPlayers(): that call builds a fresh table every
-- time and this runs on a timer
function RM.bus.broadcast(channel, payload)
  for pid in pairs(RM.identity.sessions()) do
    RM.bus.queue(pid, channel, payload)
  end
end

function RM.bus.broadcastExcept(exceptPid, channel, payload)
  for pid in pairs(RM.identity.sessions()) do
    if pid ~= exceptPid then RM.bus.queue(pid, channel, payload) end
  end
end

local function send(pid, env)
  local ok, err = MP.TriggerClientEventJson(pid, S2C_EVENT, env)
  stats.sent = stats.sent + 1
  if not ok then RM.debug("send to", pid, "failed:", err) end
  return ok
end

-- only for one-shots where a 100ms wait would be visible
function RM.bus.sendNow(pid, channel, payload)
  local env  = RM.util.take()
  local list = RM.util.take()
  local m    = RM.util.take()
  m.c, m.d = channel, payload
  list[1]  = m
  env.t, env.m = RM.util.round(RM.now(), 3), list

  local ok = send(pid, env)

  env.m = nil
  RM.util.give(env)
  list[1] = nil
  RM.util.give(list)
  RM.util.give(m)
  return ok
end

function RM.bus.flush()
  local any = false
  for pid, q in pairs(queues) do
    local n = #q
    if n > 0 then
      any = true
      local env = RM.util.take()
      env.t, env.m = RM.util.round(RM.now(), 3), q
      send(pid, env)
      env.m = nil
      RM.util.give(env)
      for i = 1, n do
        RM.util.give(q[i])
        q[i] = nil
      end
    end
  end
  if any then stats.flushes = stats.flushes + 1 end
end

function RM.bus.forget(pid)
  local q = queues[pid]
  if q then
    for i = 1, #q do RM.util.give(q[i]) end
  end
  queues[pid] = nil
  rate[pid]   = nil
end

function RM.bus.on(channel, fn)
  channels[channel] = fn
end

-- the client mod ships to every player as a readable zip, so anything can be
-- put on this pipe. a bucket per player keeps a rewritten client from being
-- able to spend the server's tick budget.
local function allow(pid)
  local b = rate[pid]
  local now = RM.now()
  if not b then
    b = { tokens = RM.config.inboundPerSec, at = now }
    rate[pid] = b
  end
  local refill = (now - b.at) * RM.config.inboundPerSec
  if refill > 0 then
    b.tokens = math.min(RM.config.inboundPerSec, b.tokens + refill)
    b.at = now
  end
  if b.tokens < 1 then
    stats.refused = stats.refused + 1
    if stats.refused % 200 == 1 then
      RM.warn(("player %d is over the inbound rate limit (%d refused)"):format(pid, stats.refused))
    end
    return false
  end
  b.tokens = b.tokens - 1
  return true
end

local function dispatch(pid, raw)
  if type(raw) ~= "string" or #raw == 0 then return end
  local ok, env = pcall(Util.JsonDecode, raw)
  if not ok or type(env) ~= "table" or type(env.m) ~= "table" then
    RM.debug("undecodable message from player", pid)
    return
  end

  local n = #env.m
  if n > RM.config.maxInboundMsgs then n = RM.config.maxInboundMsgs end

  for i = 1, n do
    local msg = env.m[i]
    if type(msg) == "table" and type(msg.c) == "string" then
      local fn = channels[msg.c]
      if fn and allow(pid) then
        stats.recv = stats.recv + 1
        local hok, herr = pcall(fn, pid, msg.d)
        if not hok then
          RM.error(("channel '%s' from player %d: %s"):format(msg.c, pid, tostring(herr)))
        end
      elseif not fn then
        RM.debug("no handler for channel", msg.c)
      end
    end
  end
end

function RM.bus.stats() return stats end

function RM.bus.init()
  RM.handler(C2S_EVENT, dispatch)
end
