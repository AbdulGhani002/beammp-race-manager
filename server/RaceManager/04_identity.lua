RM = RM or {}
RM.identity = {}

-- no passwords, no signup. BeamMP already verified them; identity is that
-- account plus a display name picked once. keyed on the forum id, not the
-- name and not the session id - both of those get reused.

local STORE = "players"

local players = nil   -- key -> record, persisted
local session = {}    -- playerID -> live state, never persisted
local taken   = {}    -- lowercased display name -> key, rebuilt on load

function RM.identity.init()
  players = RM.store.load(STORE, {})
  RM.util.clear(taken)
  for key, rec in pairs(players) do
    if type(rec) == "table" and type(rec.name) == "string" and rec.name ~= "" then
      taken[rec.name:lower()] = key
    end
  end
end

function RM.identity.keyFor(pid)
  local guest = MP.IsPlayerGuest(pid)
  local ids = MP.GetPlayerIdentifiers(pid) or {}

  if not guest and ids.beammp and ids.beammp ~= "" then
    return "beammp:" .. tostring(ids.beammp), false
  end
  return "guest:" .. tostring(MP.GetPlayerName(pid) or pid), true
end

function RM.identity.record(key)
  return players and players[key] or nil
end

function RM.identity.all() return players end

function RM.identity.session(pid) return session[pid] end

function RM.identity.sessions() return session end

function RM.identity.pidForKey(key)
  for pid, s in pairs(session) do
    if s.key == key then return pid end
  end
  return nil
end

-- name, or nil. matches on the display name people actually type.
function RM.identity.keyForName(name)
  local n = RM.util.tidy(name):lower()
  if n == "" then return nil end
  return taken[n]
end

-- returns ok, name-or-reason-code. the client turns codes into text.
function RM.identity.validateName(raw, forKey)
  local name = RM.util.tidy(raw)
  local cfg = RM.config

  if #name < cfg.nameMinLen then return false, "too_short" end
  if #name > cfg.nameMaxLen then return false, "too_long"  end
  if not name:match(cfg.namePattern) then return false, "bad_chars" end

  local owner = taken[name:lower()]
  if owner and owner ~= forKey then return false, "taken" end
  return true, name
end

function RM.identity.setName(pid, raw)
  local s = session[pid]
  if not s then return false, "no_session" end
  if s.name and s.name ~= "" then return false, "already_named" end

  local ok, result = RM.identity.validateName(raw, s.key)
  if not ok then return false, result end

  local rec = players[s.key]
  if not rec then return false, "no_record" end

  rec.name = result
  s.name = result
  taken[result:lower()] = s.key

  RM.store.markDirty(STORE)
  RM.store.flushNow(STORE)
  RM.info(("player %d (%s) is now '%s'"):format(pid, s.key, result))
  return true, result
end

function RM.identity.onJoin(pid)
  local key, guest = RM.identity.keyFor(pid)
  local now = os.time()

  local rec = players[key]
  if not rec then
    rec = { name = nil, role = "player", xp = 0, level = 1,
            firstSeen = now, lastSeen = now, guest = guest }
    players[key] = rec
    RM.info(("new identity %s (beammp name '%s')"):format(key, tostring(MP.GetPlayerName(pid))))
  end
  rec.lastSeen = now
  rec.guest = guest
  RM.store.markDirty(STORE)

  -- the config list wins over whatever is in the store
  for _, ownerKey in ipairs(RM.config.owners) do
    if ownerKey == key then rec.role = "owner" end
  end

  local s = session[pid] or {}
  s.key, s.name, s.role = key, rec.name, rec.role
  s.guest, s.level      = guest, rec.level
  s.speed, s.ping       = 0, -1
  s.joined              = RM.now()
  s.hello               = false
  s.rosterSub           = false
  session[pid] = s

  return s, rec
end

function RM.identity.onLeave(pid)
  local s = session[pid]
  if s then
    local rec = players[s.key]
    if rec then
      rec.lastSeen = os.time()
      RM.store.markDirty(STORE)
    end
    RM.info(("player %d (%s) left"):format(pid, s.name or s.key))
  end
  session[pid] = nil
end

function RM.identity.displayName(pid)
  local s = session[pid]
  if s and s.name and s.name ~= "" then return s.name end
  return MP.GetPlayerName(pid) or ("player " .. tostring(pid))
end

function RM.identity.isRanked(pid)
  local s = session[pid]
  if not s then return false end
  if s.guest and not RM.config.guestsRanked then return false end
  return s.name ~= nil and s.name ~= ""
end

-- someone joined but the client mod never said hello. they are on the server
-- without the interface, so say it once rather than leaving it a mystery.
function RM.identity.checkHello()
  local cutoff = RM.config.helloTimeoutMs / 1000
  local now = RM.now()
  for pid, s in pairs(session) do
    if not s.hello and not s.helloWarned and (now - s.joined) > cutoff then
      s.helloWarned = true
      RM.warn(("player %d (%s) has not loaded the client mod"):format(pid, s.key))
    end
  end
end

function RM.identity.markDirty() RM.store.markDirty(STORE) end

-- Drop a stored player entirely. Guests key on the name BeamMP hands them,
-- which changes between sessions, so testing without a forum account leaves
-- dead display names behind that nothing else can free up.
function RM.identity.forget(key)
  local rec = players[key]
  if not rec then return false, "no_such_player" end
  if RM.identity.pidForKey(key) then return false, "still_connected" end

  if type(rec.name) == "string" and rec.name ~= "" then
    taken[rec.name:lower()] = nil
  end
  players[key] = nil

  RM.store.markDirty(STORE)
  RM.store.flushNow(STORE)
  RM.info(("forgot %s"):format(key))
  return true
end
