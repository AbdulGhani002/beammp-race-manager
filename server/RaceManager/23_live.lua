RM = RM or {}
RM.live = {}

-- Snapshots Bobby reads over SFTP. Written next to the other data files so a
-- change here does not reload the plugin. Names are the ones drivers typed
-- into Race Manager, not the Guest#### BeamMP hands a guest.

local DIR = "Resources/Server/RaceManager/data"

local function encode(t)
  local ok, body = pcall(Util.JsonEncode, t)
  if ok and type(body) == "string" then return body end
  return nil
end

local function write(name, payload)
  if not FS.Exists(DIR) then FS.CreateDirectory(DIR) end
  local body = encode(payload)
  if not body then return false end
  local path = DIR .. "/" .. name
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "wb")
  if not f then return false end
  f:write(body)
  f:close()
  os.rename(tmp, path)
  return true
end

function RM.live.rosterPayload()
  local players = {}
  for pid, s in pairs(RM.identity.sessions()) do
    local beam = tostring(MP.GetPlayerName(pid) or "")
    local name = RM.identity.displayName(pid)
    players[#players + 1] = {
      pid = pid,
      key = s.key,
      beammp = beam,
      name = name,
      guest = s.guest and true or false,
      role = s.role,
      level = s.level,
      speed = s.speed or 0,
    }
  end
  table.sort(players, function(a, b)
    return tostring(a.name) < tostring(b.name)
  end)
  return { at = os.time(), players = players }
end

function RM.live.writeRoster()
  return write("live_roster.json", RM.live.rosterPayload())
end

function RM.live.writeChallenges()
  if not RM.challenges then return false end
  local list = RM.challenges.wire(nil) or {}
  local daily, weekly = {}, {}
  for i = 1, #list do
    local c = list[i]
    if c.state == "live" or c.state == "scheduled" then
      if c.kind == "daily" then daily[#daily + 1] = c
      elseif c.kind == "weekly" then weekly[#weekly + 1] = c end
    end
  end
  return write("live_challenges.json", {
    at = os.time(), daily = daily, weekly = weekly, all = list,
  })
end

function RM.live.writeResults(payload)
  if type(payload) ~= "table" then return false end
  if type(payload.finished) ~= "table" or #payload.finished < 1 then
    return false
  end
  local hostName = payload.hostName
  local hostKey = payload.hostKey
  return write("live_results.json", {
    at = os.time(),
    v = 1,
    track = payload.track,
    trackName = payload.trackName,
    circuit = payload.circuit and true or false,
    gates = payload.gates,
    hostName = hostName,
    hostKey = hostKey,
    official = payload.official and true or false,
    finished = payload.finished,
    dnf = payload.dnf,
    bestLap = payload.bestLap,
  })
end

function RM.live.writeDrivers()
  local out = {}
  local all = RM.identity.all() or {}
  for key, rec in pairs(all) do
    if type(rec) == "table" and type(rec.name) == "string" and rec.name ~= "" then
      out[#out + 1] = RM.players.profile(key)
    end
  end
  table.sort(out, function(a, b)
    return tostring(a.name or "") < tostring(b.name or "")
  end)
  return write("live_drivers.json", { at = os.time(), drivers = out })
end
