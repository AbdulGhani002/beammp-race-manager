RM = RM or {}
RM.players = {}

-- speed and ping both come out of MP.GetPositionRaw, which BeamMP already has
-- for vehicle sync. the client is not asked for either one: it saves a message
-- in each direction per player, and a value the client supplies is a value a
-- rewritten client can make up.
--
-- three gates on the cost: rows are only sampled while somebody has the list
-- open, a row only goes out when a field on it actually moved, and the whole
-- roster only goes to clients that asked for it.

local roster    = {}
local changed   = {}
local anyChange = false
local subs      = 0

local deltaBuf  = {}   -- reused every tick, encoded before it is cleared

local function rowFor(pid)
  local r = roster[pid]
  if not r then
    r = { id = pid, name = "", level = 1, speed = 0, ping = -1, role = "player", guest = false }
    roster[pid] = r
  end
  return r
end

local function touch(pid)
  changed[pid] = true
  anyChange = true
end

function RM.players.onJoin(pid)
  local s = RM.identity.session(pid)
  if not s then return end
  local r = rowFor(pid)
  r.id, r.name    = pid, RM.identity.displayName(pid)
  r.level, r.role = s.level or 1, s.role or "player"
  r.speed, r.ping = 0, -1
  r.guest = s.guest or false
  touch(pid)
end

function RM.players.onLeave(pid)
  local s = RM.identity.session(pid)
  if s and s.rosterSub then
    subs = subs - 1
    if subs < 0 then subs = 0 end
  end

  roster[pid], changed[pid] = nil, nil

  -- a removal has to land now or every open window keeps a ghost row
  for otherPid, other in pairs(RM.identity.sessions()) do
    if other.rosterSub and otherPid ~= pid then
      RM.bus.queue(otherPid, "roster.drop", pid)
    end
  end
end

function RM.players.onNameChanged(pid)
  local r = roster[pid]
  if not r then return end
  r.name = RM.identity.displayName(pid)
  touch(pid)
end

function RM.players.onRoleChanged(pid)
  local r = roster[pid]
  if not r then return end
  r.role = RM.roles.of(pid)
  touch(pid)
end

function RM.players.setLevel(pid, level)
  local r = roster[pid]
  if not r or r.level == level then return end
  r.level = level
  touch(pid)
end

-- which vehicle to read the speed off. BeamMP has no "currently driving" flag,
-- so the newest one the player touched is the best guess available.
function RM.players.onVehicle(pid, vid)
  local s = RM.identity.session(pid)
  if not s then return end
  s.vehicles = s.vehicles or {}
  s.vehicles[vid] = true
  s.activeVid = vid
end

function RM.players.onVehicleGone(pid, vid)
  local s = RM.identity.session(pid)
  if not s or not s.vehicles then return end
  s.vehicles[vid] = nil
  if s.activeVid == vid then
    s.activeVid = nil
    for other in pairs(s.vehicles) do s.activeVid = other break end
  end
  local r = roster[pid]
  if r and not s.activeVid and r.speed ~= 0 then
    r.speed = 0
    touch(pid)
  end
end

local function sample(pid, s)
  if not s.activeVid then return end
  local raw = MP.GetPositionRaw(pid, s.activeVid)
  if type(raw) ~= "table" then return end

  local r = roster[pid]
  if not r then return end

  local vel = raw.vel
  if type(vel) == "table" then
    local mph = RM.util.mph(vel[1] or vel.x, vel[2] or vel.y, vel[3] or vel.z)
    local v = math.floor(RM.util.clamp(mph, 0, 400) + 0.5)
    if math.abs(v - r.speed) >= RM.config.speedDeltaMph or (v == 0 and r.speed ~= 0) then
      r.speed = v
      s.speed = v
      touch(pid)
    end
  end

  local ping = tonumber(raw.ping)
  if ping then
    local p = math.floor(RM.util.clamp(ping, 0, 5000) + 0.5)
    if math.abs(p - r.ping) >= RM.config.pingDeltaMs or r.ping < 0 then
      r.ping = p
      s.ping = p
      touch(pid)
    end
  end
end

-- called on the roster timer, not every tick, and only while somebody is looking
function RM.players.sample()
  if subs <= 0 then return end
  for pid, s in pairs(RM.identity.sessions()) do
    sample(pid, s)
  end
end

function RM.players.setSubscribed(pid, on)
  local s = RM.identity.session(pid)
  if not s then return end
  on = on and true or false
  if s.rosterSub == on then return end

  s.rosterSub = on
  subs = subs + (on and 1 or -1)
  if subs < 0 then subs = 0 end

  if on then
    local full, n = {}, 0
    for _, r in pairs(roster) do
      n = n + 1
      full[n] = r
    end
    RM.bus.queue(pid, "roster.full", full)
  end
end

function RM.players.tick()
  if not anyChange then return end

  local n = 0
  for pid in pairs(changed) do
    local r = roster[pid]
    if r then
      n = n + 1
      deltaBuf[n] = r
    end
  end

  if n > 0 then
    for pid, s in pairs(RM.identity.sessions()) do
      if s.rosterSub then RM.bus.queue(pid, "roster.delta", deltaBuf) end
    end
  end

  -- the queued payload is encoded during this same tick's flush, so the buffer
  -- is free to be reused on the next one
  for i = n + 1, #deltaBuf do deltaBuf[i] = nil end
  RM.util.clear(changed)
  anyChange = false
end

function RM.players.roster() return roster end

function RM.players.subscriberCount() return subs end
