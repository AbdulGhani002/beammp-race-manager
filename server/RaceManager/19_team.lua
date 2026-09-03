RM = RM or {}
RM.team = {}

-- Two drivers, one car model, one result.
--
-- From his document: invite or request, both sides must be in the same vehicle
-- model, and the team breaks up on its own if the cars stop matching. That last
-- rule is why the model is read off the spawn rather than trusted to anyone's
-- own game.
--
-- Teams live for the session. Nothing here is written to disk, because a team
-- is two people agreeing to race together this evening, not an account.

local teams  = {}   -- id -> { id, model, members = { key, key }, made }
local byKey  = {}   -- key -> team id
local offers = {}   -- key being asked -> { from, kind, at }
local nextId = 1

local OFFER_SECS = 60

local function keyOf(pid)
  local s = RM.identity.session(pid)
  return s and s.key or nil
end

local function nameOf(key)
  local rec = RM.identity.record(key)
  if rec and rec.name then return rec.name end
  local pid = RM.identity.pidForKey(key)
  return pid and RM.identity.displayName(pid) or key
end

function RM.team.of(key) return key and teams[byKey[key]] or nil end
function RM.team.forPid(pid) return RM.team.of(keyOf(pid)) end
function RM.team.count()
  local n = 0
  for _ in pairs(teams) do n = n + 1 end
  return n
end

local function tell(key, event, payload)
  local pid = RM.identity.pidForKey(key)
  if pid then RM.bus.queue(pid, event, payload) end
end

-- everybody in a team hears about it at once, which is most of what a team is
local function push(team)
  if not team then return end
  local wire = RM.team.wire(team.members[1])
  for i = 1, #team.members do
    tell(team.members[i], "team.state", RM.team.wire(team.members[i]))
  end
  return wire
end

function RM.team.wire(key)
  if not key then return { team = nil } end
  local team = RM.team.of(key)
  if not team then
    local o = offers[key]
    return {
      team = nil,
      offer = o and { from = nameOf(o.from), kind = o.kind } or nil,
    }
  end
  local who = {}
  for i = 1, #team.members do
    local k = team.members[i]
    who[#who + 1] = { name = nameOf(k), me = k == key or nil }
  end
  return { team = { id = team.id, model = team.model, members = who } }
end

------------------------------------------------------------------ making one

-- Both have to be in the same car before it can start, because that is the
-- rule the team lives under afterwards. Checking it here saves making a team
-- that falls apart on its first tick.
local function canPair(aPid, bPid)
  local aKey, bKey = keyOf(aPid), keyOf(bPid)
  if not aKey or not bKey then return nil, nil, "no_session" end
  if aKey == bKey then return nil, nil, "not_yourself" end
  if byKey[aKey] then return nil, nil, "already_teamed" end
  if byKey[bKey] then return nil, nil, "they_are_teamed" end

  local aModel = RM.players.modelOf(aPid)
  local bModel = RM.players.modelOf(bPid)
  if not aModel or not bModel then return nil, nil, "no_vehicle" end
  if aModel ~= bModel then return nil, nil, "different_cars" end
  return aKey, bKey, nil
end

-- kind is "invite" (come and drive with me) or "request" (may I drive with you)
function RM.team.offer(pid, targetPid, kind)
  kind = (kind == "request") and "request" or "invite"
  local aKey, bKey, stop = canPair(pid, targetPid)
  if stop then return false, stop end

  offers[bKey] = { from = aKey, kind = kind, at = RM.now() }
  tell(bKey, "team.state", RM.team.wire(bKey))
  RM.info(("%s sent a team %s to %s"):format(nameOf(aKey), kind, nameOf(bKey)))
  return true, kind
end

function RM.team.accept(pid)
  local key = keyOf(pid)
  if not key then return false, "no_session" end
  local o = offers[key]
  if not o then return false, "nothing_to_accept" end
  offers[key] = nil

  local fromPid = RM.identity.pidForKey(o.from)
  if not fromPid then return false, "they_left" end

  -- checked again: cars change while an offer sits there
  local aKey, bKey, stop = canPair(fromPid, pid)
  if stop then
    tell(key, "team.state", RM.team.wire(key))
    return false, stop
  end

  local id = nextId
  nextId = nextId + 1
  local team = {
    id = id,
    model = RM.players.modelOf(pid),
    members = { aKey, bKey },
    made = RM.now(),
  }
  teams[id] = team
  byKey[aKey], byKey[bKey] = id, id
  push(team)
  RM.info(("team %d: %s and %s in a %s"):format(
    id, nameOf(aKey), nameOf(bKey), tostring(team.model)))
  return true, team
end

function RM.team.decline(pid)
  local key = keyOf(pid)
  if not key or not offers[key] then return false, "nothing_to_decline" end
  local from = offers[key].from
  offers[key] = nil
  tell(key, "team.state", RM.team.wire(key))
  tell(from, "team.gone", { why = "declined", who = nameOf(key) })
  return true
end

------------------------------------------------------------------ ending one

local function disband(team, why)
  if not team then return false end
  local members = team.members
  teams[team.id] = nil
  for i = 1, #members do byKey[members[i]] = nil end
  for i = 1, #members do
    tell(members[i], "team.state", { team = nil })
    tell(members[i], "team.gone", { why = why })
  end
  RM.info(("team %d broke up: %s"):format(team.id, tostring(why)))
  return true
end

function RM.team.leave(pid)
  local key = keyOf(pid)
  local team = RM.team.of(key)
  if not team then return false, "no_team" end
  return disband(team, "left"), "left"
end

function RM.team.forget(pid)
  local key = keyOf(pid)
  if not key then return end
  offers[key] = nil
  for k, o in pairs(offers) do
    if o.from == key then offers[k] = nil; tell(k, "team.state", RM.team.wire(k)) end
  end
  local team = RM.team.of(key)
  if team then disband(team, "a driver left the server") end
end

-- The cars have to keep matching. Checked when somebody edits a vehicle and
-- again on the slow tick, because a car can also be swapped by spawning a new
-- one rather than editing the old.
local function stillMatching(team)
  local model = nil
  for i = 1, #team.members do
    local pid = RM.identity.pidForKey(team.members[i])
    if not pid then return false, "a driver left the server" end
    local m = RM.players.modelOf(pid)
    if not m then return false, "a driver has no car" end
    if model == nil then model = m
    elseif m ~= model then return false, "the cars stopped matching" end
  end
  return true, nil, model
end

function RM.team.recheck(pid)
  local team = RM.team.forPid(pid)
  if not team then return end
  local ok, why, model = stillMatching(team)
  if not ok then disband(team, why) return end
  if model and model ~= team.model then
    team.model = model
    push(team)
  end
end

function RM.team.tick()
  for _, team in pairs(teams) do
    local ok, why = stillMatching(team)
    if not ok then disband(team, why) end
  end
  local now = RM.now()
  for key, o in pairs(offers) do
    if now - o.at > OFFER_SECS then
      offers[key] = nil
      tell(key, "team.state", RM.team.wire(key))
    end
  end
end

------------------------------------------------------------------ the result

-- His document says the result is saved for the team rather than per driver.
-- The rows stay, because that is where the splits and the penalties live, and
-- a team standing is worked out beside them: both have to finish, and the
-- team's time is the two corrected times added up, so a team is only as quick
-- as the pair of them.
function RM.team.standings(finished)
  if type(finished) ~= "table" then return nil end

  local seen, out = {}, {}
  for i = 1, #finished do
    local e = finished[i]
    local team = e and e.key and RM.team.of(e.key)
    if team and not seen[team.id] then
      seen[team.id] = true

      local total, names, all = 0, {}, true
      for m = 1, #team.members do
        local mate = nil
        for j = 1, #finished do
          if finished[j].key == team.members[m] then mate = finished[j] break end
        end
        if not mate then all = false break end
        total = total + (tonumber(mate.corrected) or 0)
        names[#names + 1] = mate.name
      end

      if all then
        out[#out + 1] = { id = team.id, model = team.model,
                          drivers = names, total = RM.util.round(total, 3) }
      end
    end
  end

  if #out == 0 then return nil end
  table.sort(out, function(a, b) return a.total < b.total end)
  for i = 1, #out do out[i].pos = i end
  return out
end
