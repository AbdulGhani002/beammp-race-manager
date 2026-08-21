RM = RM or {}
RM.roles = {}

-- kick/ban/grant-XP land in phase 5. the ranking and the permission gate are
-- here now because the capture tool is an admin tool.

local ORDER = { player = 1, staff = 2, admin = 3, owner = 4 }

function RM.roles.rank(role) return ORDER[role or "player"] or 1 end

function RM.roles.isValid(role) return ORDER[role] ~= nil end

function RM.roles.atLeast(pid, required)
  local s = RM.identity.session(pid)
  if not s then return false end
  return RM.roles.rank(s.role) >= RM.roles.rank(required)
end

function RM.roles.of(pid)
  local s = RM.identity.session(pid)
  return s and s.role or "player"
end

local function apply(key, newRole)
  local rec = RM.identity.record(key)
  if not rec then return false end
  rec.role = newRole
  RM.identity.markDirty()

  local pid = RM.identity.pidForKey(key)
  if pid then
    local s = RM.identity.session(pid)
    if s then s.role = newRole end
    RM.players.onRoleChanged(pid)
  end
  return true
end

-- nobody can grant a role at or above their own, or touch someone at or above
-- them. one rule, and it covers both directions.
function RM.roles.set(actorPid, targetKey, newRole)
  if not RM.roles.isValid(newRole) then return false, "bad_role" end

  local actor = RM.identity.session(actorPid)
  if not actor then return false, "no_session" end

  local rec = RM.identity.record(targetKey)
  if not rec then return false, "no_such_player" end
  if actor.key == targetKey then return false, "cannot_change_own_role" end

  local actorRank = RM.roles.rank(actor.role)
  if RM.roles.rank(rec.role) >= actorRank then return false, "target_outranks_you" end
  if RM.roles.rank(newRole)  >= actorRank then return false, "cannot_grant_that_high" end

  apply(targetKey, newRole)
  RM.info(("%s set %s to %s"):format(actor.name or actor.key, targetKey, newRole))
  return true, newRole
end

-- the host console is behind the panel login, so a line typed there is the
-- server owner by definition. this is the only path that can mint an owner,
-- which keeps the first player to walk into an empty server from becoming one.
function RM.roles.setFromConsole(targetKey, newRole)
  if not RM.roles.isValid(newRole) then return false, "bad_role" end
  if not RM.identity.record(targetKey) then return false, "no_such_player" end
  apply(targetKey, newRole)
  RM.info(("console set %s to %s"):format(targetKey, newRole))
  return true, newRole
end

-- owners excluded: on a server with one owner that locks administration out
function RM.roles.demoteSelf(pid)
  local s = RM.identity.session(pid)
  if not s then return false, "no_session" end
  if s.role == "player" then return false, "already_player" end
  if s.role == "owner"  then return false, "owner_cannot_self_demote" end
  if not RM.identity.record(s.key) then return false, "no_record" end

  apply(s.key, "player")
  RM.info((s.name or s.key) .. " demoted themselves to player")
  return true, "player"
end

function RM.roles.countOwners()
  local n = 0
  for _, rec in pairs(RM.identity.all() or {}) do
    if type(rec) == "table" and rec.role == "owner" then n = n + 1 end
  end
  return n
end
