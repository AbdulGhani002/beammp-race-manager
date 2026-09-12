RM = RM or {}
RM.challenges = {}

-- Daily and weekly challenges. From his document: at most three daily and
-- five weekly, admins create, schedule and change them live, time attack
-- style, with XP paid by time bracket. His later note: an admin picks the
-- course, the classes and the laps from the panel, and posts it to the
-- Challenges tab. Teams cannot enter.
--
-- A challenge is a course, a lap count, the classes that may enter, and a
-- ladder of times: beat the first time for the most XP, the second for less,
-- and so on. Your best time on it is kept, and XP is paid for the best rung
-- you reach, once, with the difference paid when you climb higher.
--
-- Times here are wall clock, because a daily is a day on the calendar and
-- not a day of server uptime. The clock is a function so a test can move it.

local STORE  = "challenges"
local list   = {}
local LIMITS = { daily = 3, weekly = 5 }
local LENGTH = { daily = 24 * 3600, weekly = 7 * 24 * 3600 }
local MAX_TIERS = 8
local KEEP_ENDED = 10

RM.challenges.clock = function() return os.time() end

local function now() return RM.challenges.clock() end

-- the state each challenge was last seen in, so going live or ending is
-- told once. seeded when one is made, so its first tick is not a change.
local lastSeen = {}

function RM.challenges.init()
  list = RM.store.load(STORE, {})
end

function RM.challenges.get(id) return list[tostring(id or "")] end
function RM.challenges.all() return list end

local function stateOf(c, at)
  at = at or now()
  if at < (c.startsAt or 0) then return "scheduled" end
  if at >= (c.endsAt or 0) then return "ended" end
  return "live"
end
RM.challenges.stateOf = stateOf

local function save()
  RM.store.markDirty(STORE)
  RM.store.flushNow(STORE)
end

------------------------------------------------------------------ the wire

local function topOf(c, n)
  local rows = {}
  for key, r in pairs(c.results or {}) do
    rows[#rows + 1] = { key = key, name = r.name, best = r.best, tier = r.tier, xp = r.xp,
                        vehicle = r.vehicle, class = r.class }
  end
  table.sort(rows, function(a, b)
    if a.best ~= b.best then return a.best < b.best end
    return (a.name or "") < (b.name or "")
  end)
  for i = 1, #rows do rows[i].pos = i end
  local out = {}
  for i = 1, math.min(n, #rows) do out[i] = rows[i] end
  return out, #rows
end

local function wireOne(c, key, at)
  local top, entered = topOf(c, 5)
  local mine = key and c.results and c.results[key] or nil
  return {
    id = c.id, name = c.name, kind = c.kind,
    track = c.track, trackName = c.trackName, laps = c.laps,
    classes = c.classes, tiers = c.tiers, description = c.description,
    startsAt = c.startsAt, endsAt = c.endsAt,
    state = stateOf(c, at),
    secondsLeft = math.max(0, (c.endsAt or 0) - at),
    startsIn = math.max(0, (c.startsAt or 0) - at),
    mine = mine and { best = mine.best, tier = mine.tier, xp = mine.xp } or nil,
    top = top, entered = entered,
  }
end

-- live first, soonest to end at the top; then what is scheduled; then a few
-- that have ended, newest first, for the board
function RM.challenges.wire(pid)
  local at = now()
  local s = pid and RM.identity.session(pid)
  local key = s and s.key or nil
  local live, later, gone = {}, {}, {}
  for _, c in pairs(list) do
    local st = stateOf(c, at)
    if st == "live" then live[#live + 1] = c
    elseif st == "scheduled" then later[#later + 1] = c
    else gone[#gone + 1] = c end
  end
  table.sort(live, function(a, b) return a.endsAt < b.endsAt end)
  table.sort(later, function(a, b) return a.startsAt < b.startsAt end)
  table.sort(gone, function(a, b) return a.endsAt > b.endsAt end)
  local out = {}
  for _, c in ipairs(live) do out[#out + 1] = wireOne(c, key, at) end
  for _, c in ipairs(later) do out[#out + 1] = wireOne(c, key, at) end
  for i = 1, math.min(KEEP_ENDED, #gone) do out[#out + 1] = wireOne(gone[i], key, at) end
  return out
end

function RM.challenges.sendList(pid)
  RM.bus.queue(pid, "challenges.list", RM.challenges.wire(pid))
end

function RM.challenges.broadcastList()
  for pid in pairs(RM.identity.sessions()) do RM.challenges.sendList(pid) end
end

------------------------------------------------------------------ making one

local function tidyTiers(raw)
  if type(raw) ~= "table" then return nil, "no_tiers" end
  local out = {}
  for _, t in ipairs(raw) do
    local time = tonumber(type(t) == "table" and t.time or nil)
    local xp   = tonumber(type(t) == "table" and t.xp or nil)
    if not time or time <= 0 or not xp or xp < 0 then return nil, "bad_tier" end
    out[#out + 1] = { time = RM.util.round(time, 3), xp = math.floor(xp) }
  end
  if #out == 0 then return nil, "no_tiers" end
  if #out > MAX_TIERS then return nil, "too_many_tiers" end
  table.sort(out, function(a, b) return a.time < b.time end)
  return out
end

local function tidyClasses(raw)
  if raw == nil or raw == "" then return nil end
  if type(raw) ~= "table" then return nil, "bad_classes" end
  local out, seen = {}, {}
  for _, name in ipairs(raw) do
    local c = RM.records and RM.records.isClass(name)
    if not c then return nil, "no_such_class" end
    if not seen[c] then seen[c] = true; out[#out + 1] = c end
  end
  if #out == 0 then return nil end
  return out
end

local function countOpen(kind, exceptId)
  local at, n = now(), 0
  for id, c in pairs(list) do
    if c.kind == kind and id ~= exceptId and stateOf(c, at) ~= "ended" then n = n + 1 end
  end
  return n
end

local function freshId(name)
  local base = RM.util.slug(name)
  if #base < 2 then base = "challenge" end
  local id, n = base, 2
  while list[id] do id = base .. "-" .. n; n = n + 1 end
  return id
end

-- the fields an admin may set, checked the same way whether the challenge is
-- new or being changed
local function readFields(d, into)
  local name = RM.util.tidy(d.name)
  if name == "" then name = into and into.name or "" end
  if #name < 2 or #name > 40 then return false, "bad_name" end

  local kind = d.kind or (into and into.kind) or "daily"
  if not LIMITS[kind] then return false, "bad_kind" end

  local trackId = d.track or (into and into.track)
  local track = RM.tracks.get(type(trackId) == "string" and trackId or "")
  if not track then return false, "no_such_track" end

  local laps = math.floor(tonumber(d.laps) or (into and into.laps) or 1)
  if laps < 1 or laps > 99 then return false, "bad_laps" end
  if not track.circuit and laps > 1 then return false, "not_a_circuit" end

  local classes, cerr
  if d.classes ~= nil then
    classes, cerr = tidyClasses(d.classes)
    if cerr then return false, cerr end
  else
    classes = into and into.classes or nil
  end

  local tiers, terr
  if d.tiers ~= nil then
    tiers, terr = tidyTiers(d.tiers)
    if terr then return false, terr end
  else
    tiers = into and into.tiers or nil
  end
  if not tiers then return false, "no_tiers" end

  -- a few lines from the admin about the challenge, shown under its name
  local description
  if d.description ~= nil then
    description = RM.util.tidy(d.description)
    if #description > 300 then return false, "description_too_long" end
    if description == "" then description = nil end
  else
    description = into and into.description or nil
  end

  local startsAt
  if d.startsAt ~= nil then
    startsAt = math.floor(tonumber(d.startsAt) or 0)
  elseif d.startInHours ~= nil then
    startsAt = now() + math.floor((tonumber(d.startInHours) or 0) * 3600)
  else
    startsAt = into and into.startsAt or now()
  end
  if startsAt < now() - 60 and not (into and into.startsAt == startsAt) then
    startsAt = now()
  end

  return true, {
    name = name, kind = kind, track = track.id, trackName = track.name or track.id,
    laps = laps, classes = classes, tiers = tiers, description = description,
    startsAt = startsAt, endsAt = startsAt + LENGTH[kind],
  }
end

function RM.challenges.create(pid, d)
  if not RM.roles.atLeast(pid, "admin") then return false, "not_allowed" end
  if type(d) ~= "table" then return false, "bad_request" end
  local ok, f = readFields(d, nil)
  if not ok then return false, f end
  if countOpen(f.kind) >= LIMITS[f.kind] then
    return false, "too_many_" .. f.kind
  end
  local c = {
    id = freshId(f.name), name = f.name, kind = f.kind,
    track = f.track, trackName = f.trackName, laps = f.laps,
    classes = f.classes, tiers = f.tiers, description = f.description,
    startsAt = f.startsAt, endsAt = f.endsAt,
    createdBy = RM.identity.displayName(pid), createdAt = now(),
    results = {},
  }
  list[c.id] = c
  lastSeen[c.id] = stateOf(c)
  save()
  RM.info(("%s posted %s challenge %s on %s: %d lap(s), %d tier(s), %s"):format(
    c.createdBy, c.kind, c.id, c.track, c.laps, #c.tiers,
    stateOf(c) == "live" and "live now" or "scheduled"))
  RM.challenges.broadcastList()
  return true, c
end

function RM.challenges.update(pid, d)
  if not RM.roles.atLeast(pid, "admin") then return false, "not_allowed" end
  if type(d) ~= "table" then return false, "bad_request" end
  local c = RM.challenges.get(d.id)
  if not c then return false, "no_such_challenge" end
  local ok, f = readFields(d, c)
  if not ok then return false, f end
  if f.kind ~= c.kind and countOpen(f.kind, c.id) >= LIMITS[f.kind] then
    return false, "too_many_" .. f.kind
  end
  -- a course change throws the times away: they were driven on the old one
  if f.track ~= c.track or f.laps ~= c.laps then c.results = {} end
  c.name, c.kind, c.track, c.trackName = f.name, f.kind, f.track, f.trackName
  c.laps, c.classes, c.tiers = f.laps, f.classes, f.tiers
  c.description = f.description
  c.startsAt, c.endsAt = f.startsAt, f.endsAt
  lastSeen[c.id] = stateOf(c)
  save()
  RM.info(("%s changed challenge %s"):format(RM.identity.displayName(pid), c.id))
  RM.challenges.broadcastList()
  return true, c
end

function RM.challenges.delete(pid, id)
  if not RM.roles.atLeast(pid, "admin") then return false, "not_allowed" end
  local c = RM.challenges.get(id)
  if not c then return false, "no_such_challenge" end
  list[c.id] = nil
  save()
  RM.info(("%s deleted challenge %s"):format(RM.identity.displayName(pid), c.id))
  RM.challenges.broadcastList()
  return true
end

function RM.challenges.endNow(pid, id)
  if not RM.roles.atLeast(pid, "admin") then return false, "not_allowed" end
  local c = RM.challenges.get(id)
  if not c then return false, "no_such_challenge" end
  if stateOf(c) == "ended" then return false, "already_ended" end
  c.endsAt = now()
  lastSeen[c.id] = "ended"
  save()
  RM.info(("%s ended challenge %s"):format(RM.identity.displayName(pid), c.id))
  RM.challenges.broadcastList()
  return true
end

------------------------------------------------------------------ entering

-- whether this driver may arm a run on this challenge, and what the run has
-- to look like. checked at arm time, so a run that started live still counts
-- if the challenge ends while it is on the road.
function RM.challenges.check(pid, id, trackId, laps, class)
  local c = RM.challenges.get(id)
  if not c then return false, "no_such_challenge" end
  if stateOf(c) ~= "live" then return false, "challenge_not_live" end
  if c.track ~= trackId then return false, "wrong_course_for_challenge" end
  if c.laps ~= laps then return false, "wrong_laps_for_challenge" end
  if c.classes then
    local found = false
    for _, name in ipairs(c.classes) do if name == class then found = true end end
    if not found then return false, "class_not_in_challenge" end
  end
  if RM.team and RM.team.forPid(pid) then return false, "teams_cannot_enter" end
  local s = RM.identity.session(pid)
  local rec = s and RM.identity.record(s.key)
  if rec and rec.tracking == false then return false, "tracking_off" end
  if rec and rec.guest then return false, "guests_cannot_enter" end
  return true, c
end

local function tierFor(c, seconds)
  for i, t in ipairs(c.tiers or {}) do
    if seconds <= t.time then return i, t.xp end
  end
  return nil, 0
end
RM.challenges.tierFor = tierFor

-- a finished run on a challenge. the best time is kept, and XP is paid for
-- the best rung reached, once, with the difference on the way up.
function RM.challenges.onFinish(e)
  if type(e) ~= "table" or not e.challenge then return nil end
  local c = RM.challenges.get(e.challenge)
  if not c or not e.key or not RM.util.isNum(e.corrected) then return nil end
  if e.suspect then return { name = c.name, suspect = true } end

  c.results = c.results or {}
  local prev = c.results[e.key]
  local tier, xp = tierFor(c, e.corrected)
  local improved = (not prev) or e.corrected < prev.best
  local paidBefore = prev and prev.xp or 0
  local gained = 0

  if improved then
    local due = math.max(paidBefore, xp)
    gained = due - paidBefore
    c.results[e.key] = {
      name = e.name, best = e.corrected, tier = tier, xp = due,
      at = now(), vehicle = e.vehicle, class = e.class,
    }
    if gained > 0 and RM.xp then RM.xp.give(e.key, gained, "challenge") end
    save()
    RM.challenges.broadcastList()
  end

  local mine = c.results[e.key]
  RM.info(("%s on challenge %s: %.3f, %s, %d xp%s"):format(
    tostring(e.name), c.id, e.corrected,
    tier and ("tier " .. tier) or "outside the ladder", gained,
    improved and "" or " (no improvement)"))
  return {
    name = c.name, tier = tier, xp = xp, gained = gained,
    best = mine and mine.best or e.corrected, improved = improved,
  }
end

------------------------------------------------------------------ the tick

-- a challenge going live or ending is worth telling everybody, once
function RM.challenges.tick()
  local at = now()
  local changed = false
  for id, c in pairs(list) do
    local st = stateOf(c, at)
    if lastSeen[id] and lastSeen[id] ~= st then changed = true end
    lastSeen[id] = st
  end
  for id in pairs(lastSeen) do
    if not list[id] then lastSeen[id] = nil end
  end
  if changed then RM.challenges.broadcastList() end
  return changed
end

function RM.challenges.count()
  local n = 0
  for _ in pairs(list) do n = n + 1 end
  return n
end
