RM = RM or {}
RM.mod = {}

-- Kick and ban.
--
-- Both are keyed on the forum id, the same key the display name hangs off, so
-- a ban follows the account rather than a name that can be changed or a
-- session id that is handed out fresh every join.
--
-- A kick removes somebody now. A ban removes them now and turns them away next
-- time. The list is on disk, so a restart does not quietly let everybody back
-- in, which is the whole point of having one.

local STORE = "bans"

local bans = nil   -- key -> { by, why, at }

function RM.mod.init()
  bans = RM.store.load(STORE, {})
end

function RM.mod.all() return bans or {} end

function RM.mod.isBanned(key)
  if not bans or not key then return false end
  return bans[tostring(key)] ~= nil
end

function RM.mod.reasonFor(key)
  local b = bans and key and bans[tostring(key)]
  return b and b.why or nil
end

-- Nobody may act on somebody who outranks them, and nobody may act on
-- themselves. Both of those are how a staff list stays a staff list.
local function may(actorPid, targetKey)
  if not RM.roles.atLeast(actorPid, "admin") then return false, "not_allowed" end

  local s = RM.identity.session(actorPid)
  if s and s.key == targetKey then return false, "not_yourself" end

  local rec = RM.identity.record(targetKey)
  local theirRole = rec and rec.role or "player"
  local mine = RM.roles.rank(RM.roles.of(actorPid))
  if RM.roles.rank(theirRole) >= mine then return false, "outranks_you" end
  return true
end

local function dropNow(key, message)
  local pid = RM.identity.pidForKey(key)
  if not pid then return false end
  pcall(function() MP.DropPlayer(pid, message) end)
  return true
end

function RM.mod.kick(actorPid, targetKey, why)
  local ok, stop = may(actorPid, targetKey)
  if not ok then return false, stop end

  local name = (RM.identity.record(targetKey) or {}).name or targetKey
  local said = why and tostring(why) or "no reason given"
  if not dropNow(targetKey, "Kicked: " .. said) then return false, "not_here" end

  RM.info(("%s kicked %s (%s)"):format(
    RM.identity.displayName(actorPid), tostring(name), said))
  return true, name
end

function RM.mod.ban(actorPid, targetKey, why)
  local ok, stop = may(actorPid, targetKey)
  if not ok then return false, stop end
  if RM.mod.isBanned(targetKey) then return false, "already_banned" end

  local rec = RM.identity.record(targetKey)
  local name = rec and rec.name or targetKey
  local said = why and tostring(why) or "no reason given"

  bans[tostring(targetKey)] = {
    by = (RM.identity.session(actorPid) or {}).key,
    byName = RM.identity.displayName(actorPid),
    name = name,
    why = said,
    at = os.time(),
  }
  RM.store.markDirty(STORE)

  dropNow(targetKey, "Banned: " .. said)
  RM.info(("%s banned %s (%s)"):format(
    RM.identity.displayName(actorPid), tostring(name), said))
  return true, name
end

-- Lifting one is a console job. Somebody who is banned cannot be on the server
-- to be pointed at, so there is nobody in the game who could do it anyway.
function RM.mod.unban(targetKey)
  if not bans then return false, "not_ready" end
  local key = tostring(targetKey or "")
  local b = bans[key]
  if not b then return false, "not_banned" end
  bans[key] = nil
  RM.store.markDirty(STORE)
  RM.info(("ban lifted on %s"):format(b.name or key))
  return true, b.name or key
end

-- The console is behind the panel login, so a line typed there is the server
-- owner by definition and there is no actor to rank against.
function RM.mod.kickFromConsole(targetKey, why)
  local rec = RM.identity.record(targetKey)
  local name = rec and rec.name or targetKey
  local said = why and tostring(why) or "no reason given"
  if not dropNow(targetKey, "Kicked: " .. said) then return false, "not_here" end
  RM.info(("console kicked %s (%s)"):format(tostring(name), said))
  return true, name
end

function RM.mod.banFromConsole(targetKey, why)
  if RM.mod.isBanned(targetKey) then return false, "already_banned" end
  local rec = RM.identity.record(targetKey)
  local name = rec and rec.name or targetKey
  local said = why and tostring(why) or "no reason given"

  bans[tostring(targetKey)] = {
    by = "console", byName = "console", name = name, why = said, at = os.time(),
  }
  RM.store.markDirty(STORE)
  dropNow(targetKey, "Banned: " .. said)
  RM.info(("console banned %s (%s)"):format(tostring(name), said))
  return true, name
end

-- Called as somebody arrives. Returning true means they were turned away.
function RM.mod.turnAway(pid)
  local key = RM.identity.keyFor(pid)
  if not key or not RM.mod.isBanned(key) then return false end
  local why = RM.mod.reasonFor(key) or "no reason given"
  pcall(function() MP.DropPlayer(pid, "Banned: " .. why) end)
  RM.info(("turned away %s, banned: %s"):format(tostring(key), why))
  return true
end

function RM.mod.count()
  local n = 0
  for _ in pairs(bans or {}) do n = n + 1 end
  return n
end
