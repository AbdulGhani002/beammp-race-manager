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

  -- BeamMP hands a guest a fresh name every session, so keying on it makes
  -- every visit a different person: the display name they picked stays locked
  -- to a record they can never reach again. The connection is the only thing
  -- that stays put, and it is hashed so no address reaches the file.
  if RM.config.guestKey == "ip" and type(ids.ip) == "string" and ids.ip ~= "" then
    return "guest:ip:" .. RM.util.hash(ids.ip), true
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
  rec.code = rec.code or RM.identity.makeCode()
  s.name = result
  taken[result:lower()] = s.key

  RM.store.markDirty(STORE)
  RM.store.flushNow(STORE)
  RM.info(("player %d (%s) is now %s"):format(pid, s.key, result))
  return true, result, rec.code
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
      RM.warn(("player %d (%s) has still not said hello: the client mod is either not loading or still downloading"):format(pid, s.key))
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

-- Push a player's own record back to them. The roster carries everyone else's
-- row, but a change to your own role has to reach you even with the player
-- list closed, and it is what unlocks the admin parts of the interface.
function RM.identity.sendMe(pid)
  local s = session[pid]
  if not s then return end
  RM.bus.queue(pid, "me", {
    id     = pid,
    key    = s.key,
    name   = s.name,
    role   = s.role,
    guest  = s.guest,
    ranked = RM.identity.isRanked(pid),
    level  = s.level,
  })
end

-- Move a stored player onto whoever is connected now. Two things need this:
-- a name stranded on a key nobody can reach any more, and a guest whose
-- address changed because their router rebooted. It is deliberately not
-- something a player can do to themselves.
function RM.identity.claim(pid, name)
  local s = session[pid]
  if not s then return false, "no_session" end
  if s.name and s.name ~= "" then return false, "already_named" end

  local oldKey = RM.identity.keyForName(name)
  if not oldKey then return false, "no_such_name" end
  if oldKey == s.key then return false, "already_yours" end
  if RM.identity.pidForKey(oldKey) then return false, "still_connected" end

  local old = players[oldKey]
  local rec = players[s.key]
  if not old then return false, "no_such_name" end
  if not rec then return false, "no_record" end

  rec.name      = old.name
  rec.role      = old.role or "player"
  rec.xp        = old.xp or 0
  rec.level     = old.level or 1
  rec.firstSeen = old.firstSeen or rec.firstSeen

  taken[tostring(old.name):lower()] = s.key
  players[oldKey] = nil

  s.name, s.role, s.level = rec.name, rec.role, rec.level

  RM.store.markDirty(STORE)
  RM.store.flushNow(STORE)
  RM.info(("%s claimed by %s, carrying role %s"):format(rec.name, s.key, rec.role))
  return true, rec.name
end

-- everyone connected who has not picked a name yet
function RM.identity.unnamed()
  local out = {}
  for pid, s in pairs(session) do
    if not s.name or s.name == "" then out[#out + 1] = pid end
  end
  table.sort(out)
  return out
end

-- A code handed out once, when a name is first taken, so a player who comes
-- back unrecognised can get their own name back without an admin being awake.
--
-- That matters more than it sounds. rm claim needs somebody at the host
-- console who can also work out which of twenty connected players you are.
-- Fine for two people testing, useless on a public server.
--
-- Not a password: it is generated rather than chosen, shown once, and only
-- ever used when the connection is not recognised. It is stored in the clear
-- because anyone who can read that file already has the console, and the
-- console can do more than this ever could.

local ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   -- no I O 0 1
local seeded = false

local function makeCode()
  if not seeded then
    math.randomseed(os.time() + math.floor(RM.now() * 1000))
    seeded = true
  end
  local out = {}
  for i = 1, 6 do
    local n = math.random(1, #ALPHABET)
    out[i] = ALPHABET:sub(n, n)
  end
  return table.concat(out)
end

RM.identity.makeCode = makeCode

-- returns ok, name-or-reason
function RM.identity.recover(pid, code)
  local s = session[pid]
  if not s then return false, "no_session" end
  if s.name and s.name ~= "" then return false, "already_named" end

  code = tostring(code or ""):upper():gsub("[^A-Z0-9]", "")
  if #code ~= 6 then return false, "bad_code" end

  local foundKey, found
  for key, rec in pairs(players) do
    if type(rec) == "table" and rec.code == code then
      foundKey, found = key, rec
      break
    end
  end

  if not found then return false, "no_match" end
  if foundKey == s.key then return false, "already_yours" end
  if RM.identity.pidForKey(foundKey) then return false, "still_connected" end

  local rec = players[s.key]
  if not rec then return false, "no_record" end

  rec.name      = found.name
  rec.role      = found.role or "player"
  rec.xp        = found.xp or 0
  rec.level     = found.level or 1
  rec.firstSeen = found.firstSeen or rec.firstSeen
  rec.code      = found.code

  if type(found.name) == "string" and found.name ~= "" then
    taken[found.name:lower()] = s.key
  end
  players[foundKey] = nil

  s.name, s.role, s.level = rec.name, rec.role, rec.level

  RM.store.markDirty(STORE)
  RM.store.flushNow(STORE)
  RM.info(("%s recovered by code onto %s, role %s"):format(rec.name, s.key, rec.role))
  return true, rec.name
end
