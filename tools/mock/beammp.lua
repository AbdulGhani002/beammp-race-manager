-- Stands in for the BeamMP server host so the plugin can be run and poked at
-- without the game. Only the calls the plugin actually makes are here.
local J = dofile("tools/mock/json.lua")

local M = {
  clock    = 0.0,
  players  = {},          -- pid -> { name, beammp, guest }
  raw      = {},          -- pid -> { vid -> { vel = {..}, ping = n } }
  sent     = {},          -- pid -> list of decoded envelopes
  handlers = {},          -- event name -> global function name
  timers   = {},
  logs     = { info = {}, warn = {}, error = {}, debug = {} },
}

function M.advance(seconds) M.clock = M.clock + seconds end

function M.reset()
  M.clock = 0.0
  M.players, M.raw, M.sent = {}, {}, {}
  M.handlers, M.timers = {}, {}
  M.logs = { info = {}, warn = {}, error = {}, debug = {} }
end

function M.addPlayer(pid, name, beammp, guest, ip)
  M.players[pid] = { name = name, beammp = beammp, guest = guest and true or false,
                     ip = ip or "10.0.0.1" }
end

function M.removePlayer(pid)
  M.players[pid] = nil
  M.raw[pid] = nil
end

function M.setVelocity(pid, vid, vx, vy, vz, ping)
  M.raw[pid] = M.raw[pid] or {}
  M.raw[pid][vid] = { vel = { vx, vy, vz }, ping = ping or 30, pos = { 0, 0, 0 } }
end

-- run a registered event handler by name, the way the host would
function M.fire(event, ...)
  local fname = M.handlers[event]
  if not fname then return nil end
  local fn = _G[fname]
  if not fn then return nil end
  return fn(...)
end

function M.hasHandler(event) return M.handlers[event] ~= nil end

-- everything the client would have received, newest last
function M.outbox(pid)
  return M.sent[pid] or {}
end

function M.clearOutbox(pid)
  if pid then M.sent[pid] = nil else M.sent = {} end
end

-- flatten every queued envelope into channel/payload pairs
function M.messages(pid)
  local out, n = {}, 0
  for _, env in ipairs(M.outbox(pid)) do
    for _, msg in ipairs(env.m or {}) do
      n = n + 1
      out[n] = { c = msg.c, d = msg.d }
    end
  end
  return out
end

function M.lastMessage(pid, channel)
  local found
  for _, m in ipairs(M.messages(pid)) do
    if m.c == channel then found = m.d end
  end
  return found
end

-- the client sending something up the pipe
function M.clientSend(pid, channel, payload)
  return M.fire("rmC2S", pid, J.encode({ t = M.clock, m = { { c = channel, d = payload } } }))
end

function M.clientSendRaw(pid, raw)
  return M.fire("rmC2S", pid, raw)
end

-------------------------------------------------------------------- globals

MP = {
  CallStrategy = { BestEffort = 0, Precise = 1 },
  Settings = {},
}

function MP.CreateTimer()
  local t = { base = M.clock }
  function t:Start() self.base = M.clock end
  function t:GetCurrent() return M.clock - self.base end
  return t
end

function MP.RegisterEvent(event, fname) M.handlers[event] = fname end
function MP.CreateEventTimer(event, ms) M.timers[event] = ms end
function MP.CancelEventTimer(event) M.timers[event] = nil end

function MP.GetPlayerCount()
  local n = 0
  for _ in pairs(M.players) do n = n + 1 end
  return n
end

function MP.GetPlayers()
  local out = {}
  for pid, p in pairs(M.players) do out[pid] = p.name end
  return out
end

function MP.GetPlayerName(pid)
  local p = M.players[pid]
  return p and p.name or nil
end

function MP.IsPlayerGuest(pid)
  local p = M.players[pid]
  return p and p.guest or false
end

function MP.GetPlayerIdentifiers(pid)
  local p = M.players[pid]
  if not p then return {} end
  return { beammp = p.beammp, ip = p.ip or "10.0.0.1" }
end

function MP.GetPositionRaw(pid, vid)
  local byVid = M.raw[pid]
  if not byVid then return nil, "no data" end
  return byVid[vid], ""
end

function MP.TriggerClientEventJson(pid, event, tbl)
  if not M.players[pid] then return false, "not connected" end
  M.sent[pid] = M.sent[pid] or {}
  -- encode then decode so the harness sees exactly what the wire would carry
  local round = J.decode(J.encode(tbl))
  table.insert(M.sent[pid], round)
  return true, ""
end

function MP.TriggerClientEvent(pid, event, data)
  return MP.TriggerClientEventJson(pid, event, { raw = data })
end

function MP.SendChatMessage() return true end
function MP.DropPlayer() return true end
function MP.IsPlayerConnected(pid) return M.players[pid] ~= nil end
function MP.GetStateMemoryUsage() return collectgarbage("count") * 1024 end
function MP.GetLuaMemoryUsage() return collectgarbage("count") * 1024 end

-------------------------------------------------------------------------- Util

Util = {}

function Util.JsonEncode(t) return J.encode(t) end
function Util.JsonDecode(s) return J.decode(s) end
function Util.JsonPrettify(s) return s end
function Util.JsonMinify(s) return s end

local function record(bucket, msg)
  table.insert(M.logs[bucket], msg)
  if M.verbose then print(("[%-5s] %s"):format(bucket, msg)) end
end

function Util.LogInfo(msg)  record("info", msg)  end
function Util.LogWarn(msg)  record("warn", msg)  end
function Util.LogError(msg) record("error", msg) end
function Util.LogDebug(msg) record("debug", msg) end

--------------------------------------------------------------------------- FS

FS = {}

local function shell(cmd) return os.execute(cmd) end

function FS.Exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  -- a directory cannot be opened as a file, so probe for one inside it
  local probe = io.open(path .. "/.probe", "wb")
  if probe then
    probe:close()
    os.remove(path .. "/.probe")
    return true
  end
  return false
end

function FS.CreateDirectory(path)
  local sep = string.char(92)
  os.execute("mkdir " .. string.char(34) .. path:gsub("/", sep) .. string.char(34) .. " 2>nul")
  return FS.Exists(path), ""
end

function FS.Remove(path)
  os.remove(path)
  return true, ""
end

function FS.Rename(a, b)
  local ok = os.rename(a, b)
  return ok and true or false, ok and "" or "rename failed"
end

function FS.Copy(a, b)
  local src = io.open(a, "rb")
  if not src then return false, "no source" end
  local body = src:read("*a")
  src:close()
  local dst = io.open(b, "wb")
  if not dst then return false, "no dest" end
  dst:write(body)
  dst:close()
  return true, ""
end

function FS.IsFile(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

function FS.IsDirectory(path) return FS.Exists(path) and not FS.IsFile(path) end
function FS.ConcatPaths(...) return table.concat({ ... }, "/") end

-- Every test carried its own copy of the file list, so adding a module to the
-- plugin left four of them loading a server without it and failing somewhere
-- unrelated. The directory is the list.
function M.loadPlugin()
  local dir = "server/RaceManager"
  local names = {}

  local pipe = io.popen('dir /b "' .. dir:gsub("/", "\\") .. '\\*.lua" 2>nul')
  if pipe then
    for line in pipe:lines() do
      local name = line:match("^(.-)%.lua%s*$")
      if name then names[#names + 1] = name end
    end
    pipe:close()
  end

  if #names == 0 then error("no plugin files found in " .. dir) end
  table.sort(names)   -- the host loads them alphabetically

  for _, name in ipairs(names) do dofile(dir .. "/" .. name .. ".lua") end
  return names
end

return M
