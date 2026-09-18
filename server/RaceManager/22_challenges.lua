RM = RM or {}
RM.challenges = {}

-- Daily and weekly challenges. From his document: at most three daily and
-- five weekly, admins create, schedule and change them live, time attack
-- style, with XP paid by time bracket. His later note: an admin picks the
-- course, the classes and the laps from the panel, and posts it to the
-- Challenges tab. Teams cannot enter.
--
-- A challenge is a course, a lap count, the classes that may enter, and a
-- ladder of thresholds: beat the first one for the most XP, the second for
-- less, and so on. Your best result on it is kept, and XP is paid for the
-- best rung you reach, once, with the difference paid when you climb higher.
--
-- Times here are wall clock, because a daily is a day on the calendar and
-- not a day of server uptime. The clock is a function so a test can move it.
--
-- Style. A challenge used to only ever mean one thing: lowest lap time. It
-- can now mean five other things too -- top speed, peak g-force, a damage
-- and distance score, a long jump, or distance covered -- all driven on the
-- same course, through the same arm/grid/finish machinery, just scored off
-- what the client reported instead of the clock. "style" says which; the
-- ladder ("tiers") always means the same thing either way -- a row you have
-- to clear -- it is just that for lap time the row is a ceiling (beat this
-- time or better) and for everything else it is a floor (reach this value
-- or better). tidyTiers/tierFor below are the only two places that care
-- about the difference; everything else just calls them.

local STORE  = "challenges"
local list   = {}
local LIMITS = { daily = 3, weekly = 5 }
local LENGTH = { daily = 24 * 3600, weekly = 7 * 24 * 3600 }
local MAX_TIERS = 20
local KEEP_ENDED = 10

-- one place that knows what each style is, what unit its ladder is in, which
-- direction is "better", and a sane ceiling on a single tier's value so a
-- typo (an extra zero) does not sit on the board forever. The admin panel
-- and Bobby both read this table (RM.challenges.styles()) rather than
-- hard-coding the list a second time.
local STYLES = {
  laptime = {
    label = "Lap Time", unit = "time", higherBetter = false,
    maxValue = 24 * 3600, timeLimit = "none", courseRequired = true,
  },
  speed = {
    label = "Top Speed", unit = "mph", higherBetter = true,
    maxValue = 400, timeLimit = "optional", courseRequired = false,
  },
  gforce = {
    label = "G-Force", unit = "g", higherBetter = true,
    maxValue = 50, timeLimit = "required", courseRequired = false,
  },
  damage = {
    label = "Damage & Distance", unit = "score", higherBetter = true,
    maxValue = 1000000, timeLimit = "required", courseRequired = false,
  },
  longjump = {
    label = "Long Jump", unit = "ft", higherBetter = true,
    maxValue = 5000, timeLimit = "required", courseRequired = false,
  },
  distance = {
    label = "Distance", unit = "mi", higherBetter = true,
    maxValue = 5000, timeLimit = "required", courseRequired = false,
  },
}
RM.challenges.STYLES = STYLES

function RM.challenges.styles()
  local out = {}
  for key, meta in pairs(STYLES) do
    out[#out + 1] = {
      key = key, label = meta.label, unit = meta.unit,
      higherBetter = meta.higherBetter, timeLimit = meta.timeLimit,
      maxValue = meta.maxValue, courseRequired = meta.courseRequired,
    }
  end
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end

RM.challenges.clock = function() return os.time() end

local function now() return RM.challenges.clock() end

-- the state each challenge was last seen in, so going live or ending is
-- told once. seeded when one is made, so its first tick is not a change.
local lastSeen = {}

function RM.challenges.init()
  list = RM.store.load(STORE, {})
  RM.challenges.dropOrphans()
end

function RM.challenges.dropForTrack(trackId)
  trackId = tostring(trackId or "")
  if trackId == "" then return 0 end
  local n = 0
  for id, c in pairs(list) do
    if c and c.track == trackId then
      list[id] = nil
      lastSeen[id] = nil
      n = n + 1
    end
  end
  if n > 0 then
    RM.store.markDirty(STORE)
    RM.store.flushNow(STORE)
    RM.challenges.broadcastList()
    if RM.live and RM.live.writeChallenges then RM.live.writeChallenges() end
    RM.info(("dropped %d challenge(s) for deleted course %s"):format(n, trackId))
  end
  return n
end

function RM.challenges.dropOrphans()
  if not RM.tracks or not RM.tracks.get then return 0 end
  local n = 0
  for id, c in pairs(list) do
    if c and c.track and not RM.tracks.get(c.track) then
      list[id] = nil
      lastSeen[id] = nil
      n = n + 1
    end
  end
  if n > 0 then
    RM.store.markDirty(STORE)
    RM.store.flushNow(STORE)
    RM.info(("dropped %d challenge(s) for missing courses"):format(n))
  end
  return n
end

function RM.challenges.get(id) return list[tostring(id or "")] end
function RM.challenges.all() return list end

function RM.challenges.forDriver(key)
  key = tostring(key or "")
  local out = {}
  for _, c in pairs(list) do
    local r = c.results and c.results[key]
    if type(r) == "table" then
      out[#out + 1] = {
        id = c.id, name = c.name, kind = c.kind, style = c.style or "laptime",
        trackName = c.trackName or c.name, best = r.best,
        class = r.class, mode = r.mode, vehicle = r.vehicle,
        tier = r.tier, xp = r.xp, at = r.at,
      }
    end
  end
  -- a mixed bag of styles has nothing sensible to sort "best" by across rows
  -- (45 seconds and 120 mph are not comparable), so this is ordered by when
  -- it was set, newest first, rather than pretending one ordering fits both.
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

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
  local meta = STYLES[c.style or "laptime"] or STYLES.laptime
  local rows = {}
  for key, r in pairs(c.results or {}) do
    rows[#rows + 1] = { key = key, name = r.name, best = r.best, tier = r.tier, xp = r.xp,
                        vehicle = r.vehicle, class = r.class,
                        attempts = (c.attempts and c.attempts[key]) or 0 }
  end
  table.sort(rows, function(a, b)
    if a.best ~= b.best then
      if meta.higherBetter then return a.best > b.best end
      return a.best < b.best
    end
    return (a.name or "") < (b.name or "")
  end)
  for i = 1, #rows do rows[i].pos = i end
  local out = {}
  for i = 1, math.min(n, #rows) do out[i] = rows[i] end
  return out, #rows
end

-- the same driver rows, ranked by how many times each has actually run the
-- challenge rather than by their best result -- who's been grinding it (see
-- the decaying per-attempt XP in RM.challenges.onFinish), not who's
-- fastest. Ties broken by cumulative XP earned, the same total that
-- decaying ladder pays into.
local function grindersOf(c, n)
  local rows = {}
  for key, r in pairs(c.results or {}) do
    local att = (c.attempts and c.attempts[key]) or 0
    if att > 0 then
      rows[#rows + 1] = { key = key, name = r.name, best = r.best, tier = r.tier,
                          xp = r.xp, attempts = att, vehicle = r.vehicle, class = r.class }
    end
  end
  table.sort(rows, function(a, b)
    if a.attempts ~= b.attempts then return a.attempts > b.attempts end
    return (a.xp or 0) > (b.xp or 0)
  end)
  for i = 1, #rows do rows[i].pos = i end
  local out = {}
  for i = 1, math.min(n, #rows) do out[i] = rows[i] end
  return out, #rows
end

local function wireOne(c, key, at)
  local top, entered = topOf(c, 10)
  local grinders = grindersOf(c, 10)
  local mine = key and c.results and c.results[key] or nil
  return {
    id = c.id, name = c.name, kind = c.kind, style = c.style or "laptime",
    track = c.track, trackName = c.trackName, laps = c.laps,
    classes = c.classes, tiers = c.tiers, description = c.description,
    timeLimit = c.timeLimit,
    startsAt = c.startsAt, endsAt = c.endsAt,
    state = stateOf(c, at),
    secondsLeft = math.max(0, (c.endsAt or 0) - at),
    startsIn = math.max(0, (c.startsAt or 0) - at),
    mine = mine and { best = mine.best, tier = mine.tier, xp = mine.xp,
                      attempts = (c.attempts and key and c.attempts[key]) or 0 } or nil,
    top = top, entered = entered, grinders = grinders,
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

-- tiers are always sent as { time = <value>, xp = <n> }. "time" is a name
-- from when this only meant lap time; it is kept rather than renamed so a
-- challenge saved before styles existed reads back exactly as it was
-- written. For every other style the number in that field is just in that
-- style's own unit (mph, g, score, feet, miles), not seconds.
local function tidyTiers(raw, style)
  if type(raw) ~= "table" then return nil, "no_tiers" end
  local meta = STYLES[style] or STYLES.laptime
  local out = {}
  for _, t in ipairs(raw) do
    local val = tonumber(type(t) == "table" and t.time or nil)
    local xp  = tonumber(type(t) == "table" and t.xp or nil)
    if not val or val <= 0 or val > meta.maxValue or not xp or xp < 0 then
      return nil, "bad_tier"
    end
    out[#out + 1] = { time = RM.util.round(val, 3), xp = math.floor(xp) }
  end
  if #out == 0 then return nil, "no_tiers" end
  if #out > MAX_TIERS then return nil, "too_many_tiers" end
  -- sorted so the first tier reached, walking the list in order, is always
  -- the best one: ascending for a time (smallest is fastest), descending for
  -- everything else (largest is the one to beat).
  table.sort(out, function(a, b)
    if meta.higherBetter then return a.time > b.time end
    return a.time < b.time
  end)
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

-- how long a single attempt is allowed to run before it is scored as-is,
-- for the styles that need a clock of their own on top of the lap timer
-- (g-force, damage, long jump and distance are meaningless without one;
-- speed takes it or leaves it; lap time never uses one -- its own finish
-- line ends the attempt).
local function readTimeLimit(d, into, style)
  local rule = (STYLES[style] or STYLES.laptime).timeLimit
  if rule == "none" then return true, nil end

  local raw = d.timeLimit
  if raw == nil then raw = into and into.timeLimit or nil end
  if raw == nil or raw == "" then
    if rule == "required" then return false, "time_limit_required" end
    return true, nil
  end
  local seconds = math.floor(tonumber(raw) or 0)
  if seconds < 5 or seconds > 3600 then return false, "bad_time_limit" end
  return true, seconds
end

-- the fields an admin (or Bobby, on an admin's behalf) may set, checked the
-- same way whether the challenge is new or being changed
local function readFields(d, into)
  local name = RM.util.tidy(d.name)
  if name == "" then name = into and into.name or "" end
  if #name < 2 or #name > 40 then return false, "bad_name" end

  local kind = d.kind or (into and into.kind) or "daily"
  if not LIMITS[kind] then return false, "bad_kind" end

  local style = d.style or (into and into.style) or "laptime"
  if not STYLES[style] then return false, "bad_style" end
  local styleMeta = STYLES[style]

  -- Lap time always races a real course. Every other style is free roam by
  -- default -- no course picked, no grid, the attempt starts the moment it
  -- is armed -- unless the admin explicitly picked one, in which case it
  -- runs like any other course-based challenge and its own finish line (or
  -- the time limit, whichever comes first) ends the attempt.
  local trackRaw = d.track
  if trackRaw == nil then trackRaw = into and into.track end
  local track, laps, classes

  if trackRaw ~= nil and trackRaw ~= "" then
    track = RM.tracks.get(type(trackRaw) == "string" and trackRaw or "")
    if not track then return false, "no_such_track" end
    laps = math.floor(tonumber(d.laps) or (into and into.laps) or 1)
    if laps < 1 or laps > 99 then return false, "bad_laps" end
    if not track.circuit and laps > 1 then return false, "not_a_circuit" end
  elseif styleMeta.courseRequired then
    return false, "no_such_track"
  else
    track, laps = nil, 1
  end

  local cerr
  if d.classes ~= nil then
    classes, cerr = tidyClasses(d.classes)
    if cerr then return false, cerr end
  else
    classes = into and into.classes or nil
  end

  local tiers, terr
  if d.tiers ~= nil then
    tiers, terr = tidyTiers(d.tiers, style)
    if terr then return false, terr end
  else
    tiers = into and into.tiers or nil
  end
  if not tiers then return false, "no_tiers" end

  local okTL, timeLimit = readTimeLimit(d, into, style)
  if not okTL then return false, timeLimit end

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
    name = name, kind = kind, style = style,
    track = track and track.id or nil,
    trackName = track and (track.name or track.id) or nil,
    laps = laps, classes = classes, tiers = tiers, description = description,
    timeLimit = timeLimit,
    startsAt = startsAt, endsAt = startsAt + LENGTH[kind],
  }
end

local function doCreate(f, createdBy)
  local c = {
    id = freshId(f.name), name = f.name, kind = f.kind, style = f.style,
    track = f.track, trackName = f.trackName, laps = f.laps,
    classes = f.classes, tiers = f.tiers, description = f.description,
    timeLimit = f.timeLimit,
    startsAt = f.startsAt, endsAt = f.endsAt,
    createdBy = createdBy, createdAt = now(),
    results = {},
  }
  list[c.id] = c
  lastSeen[c.id] = stateOf(c)
  save()
  RM.info(("%s posted %s %s challenge %s on %s: %d lap(s), %d tier(s), %s"):format(
    tostring(createdBy), c.kind, c.style, c.id, c.track, c.laps, #c.tiers,
    stateOf(c) == "live" and "live now" or "scheduled"))
  RM.challenges.broadcastList()
  return true, c
end

function RM.challenges.create(pid, d)
  if not RM.roles.atLeast(pid, "staff") then return false, "not_allowed" end
  if type(d) ~= "table" then return false, "bad_request" end
  local ok, f = readFields(d, nil)
  if not ok then return false, f end
  if countOpen(f.kind) >= LIMITS[f.kind] then
    return false, "too_many_" .. f.kind
  end
  return doCreate(f, RM.identity.displayName(pid))
end

-- the same validation and creation as the in-game panel, for a request that
-- did not come from a player: there is no pid to check a role against, so
-- the caller (the Discord bridge) is trusted to have gated who may reach
-- this before the request ever got written to disk.
function RM.challenges.createFromDiscord(d, requestedBy)
  if type(d) ~= "table" then return false, "bad_request" end
  local ok, f = readFields(d, nil)
  if not ok then return false, f end
  if countOpen(f.kind) >= LIMITS[f.kind] then
    return false, "too_many_" .. f.kind
  end
  return doCreate(f, RM.util.tidy(tostring(requestedBy or "Discord")):sub(1, 60))
end

function RM.challenges.update(pid, d)
  if not RM.roles.atLeast(pid, "staff") then return false, "not_allowed" end
  if type(d) ~= "table" then return false, "bad_request" end
  local c = RM.challenges.get(d.id)
  if not c then return false, "no_such_challenge" end
  local ok, f = readFields(d, c)
  if not ok then return false, f end
  if f.kind ~= c.kind and countOpen(f.kind, c.id) >= LIMITS[f.kind] then
    return false, "too_many_" .. f.kind
  end
  -- a course change, a lap change, or a style change throws the results
  -- away: they were driven on the old course or scored on a different scale
  if f.track ~= c.track or f.laps ~= c.laps or f.style ~= c.style then
    c.results = {}
  end
  c.name, c.kind, c.style, c.track, c.trackName = f.name, f.kind, f.style, f.track, f.trackName
  c.laps, c.classes, c.tiers = f.laps, f.classes, f.tiers
  c.timeLimit = f.timeLimit
  c.description = f.description
  c.startsAt, c.endsAt = f.startsAt, f.endsAt
  lastSeen[c.id] = stateOf(c)
  save()
  RM.info(("%s changed challenge %s"):format(RM.identity.displayName(pid), c.id))
  RM.challenges.broadcastList()
  return true, c
end

function RM.challenges.delete(pid, id)
  if not RM.roles.atLeast(pid, "staff") then return false, "not_allowed" end
  local c = RM.challenges.get(id)
  if not c then return false, "no_such_challenge" end
  list[c.id] = nil
  save()
  RM.info(("%s deleted challenge %s"):format(RM.identity.displayName(pid), c.id))
  RM.challenges.broadcastList()
  return true
end

function RM.challenges.endNow(pid, id)
  if not RM.roles.atLeast(pid, "staff") then return false, "not_allowed" end
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
  -- a style that must have a time limit but somehow does not (saved before
  -- the rule existed, or edited around it some other way) has no way to
  -- ever finish on its own -- refused up front, loudly, rather than let a
  -- driver play out an attempt that can never be scored and never says why.
  local meta = STYLES[c.style or "laptime"] or STYLES.laptime
  if meta.timeLimit == "required" and not c.timeLimit then
    return false, "challenge_misconfigured"
  end
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
  if rec and rec.guest and not RM.config.guestsRanked then return false, "guests_cannot_enter" end
  return true, c
end

-- shared by both entry points below: the role check (or lack of one) is
-- the only thing that differs between staff launching from in-game and
-- Bobby launching from Discord.
local function doLaunchAll(c, afterArmFn)
  local launched = 0
  local skips = {}
  for pid in pairs(RM.identity.sessions()) do
    local d = { challenge = c.id, mode = "controller" }
    if c.track then
      d.id = c.track
      d.laps = c.laps or 1
    end
    local ok, result = RM.race.arm(pid, d)
    if ok then
      launched = launched + 1
      if type(afterArmFn) == "function" then afterArmFn(pid, result) end
    else
      -- the reason a driver was skipped used to be thrown away right
      -- here, leaving "N skipped" with no way to tell why -- often enough
      -- the answer is as mundane as "already mid a run from testing this
      -- a moment ago", but there was no way to know that without this.
      skips[#skips + 1] = { name = RM.identity.displayName(pid), why = tostring(result) }
    end
  end
  return { launched = launched, skipped = #skips, skips = skips, name = c.name, id = c.id }
end

local function skipSummary(skips)
  if type(skips) ~= "table" or #skips == 0 then return "" end
  local parts = {}
  for i = 1, math.min(#skips, 6) do
    parts[i] = ("%s (%s)"):format(skips[i].name, skips[i].why)
  end
  local more = #skips > 6 and (", +%d more"):format(#skips - 6) or ""
  return " -- skipped: " .. table.concat(parts, ", ") .. more
end

-- staff+ forcing every connected driver into the same challenge attempt at
-- once. afterArmFn is RM.race.afterArm -- the same per-driver
-- follow-through a normal arm gets (heat joining, the start-grid
-- teleport, and so on), run here for each driver RM.race.arm accepts.
function RM.challenges.launchAll(actorPid, challengeId, afterArmFn)
  if not RM.roles.atLeast(actorPid, "staff") then return false, "not_allowed" end
  local c = RM.challenges.get(tostring(challengeId or ""))
  if not c then return false, "no_such_challenge" end
  if stateOf(c) ~= "live" then return false, "challenge_not_live" end

  local info = doLaunchAll(c, afterArmFn)
  RM.info(("%s launched everyone into challenge %s: %d started, %d skipped%s"):format(
    RM.identity.displayName(actorPid), c.id, info.launched, info.skipped,
    skipSummary(info.skips)))
  return true, info
end

-- the same launch, for a request that did not come from a player: there is
-- no pid to check a role against, so the caller (the Discord bridge) is
-- trusted to have gated who may reach this before the request ever got
-- written to disk -- same as RM.challenges.createFromDiscord.
function RM.challenges.launchAllFromDiscord(challengeId, requestedBy, afterArmFn)
  local c = RM.challenges.get(tostring(challengeId or ""))
  if not c then return false, "no_such_challenge" end
  if stateOf(c) ~= "live" then return false, "challenge_not_live" end

  local info = doLaunchAll(c, afterArmFn)
  RM.info(("%s launched everyone into challenge %s from Discord: %d started, %d skipped%s"):format(
    tostring(requestedBy or "Discord"), c.id, info.launched, info.skipped,
    skipSummary(info.skips)))
  return true, info
end

-- the run's own attempt clock, for the styles that carry a time limit: how
-- long a driver on this challenge has been running before it should be cut
-- off and scored on whatever it has so far. Read by RM.race each tick.
function RM.challenges.timeLimitOf(id)
  local c = RM.challenges.get(id)
  return c and c.timeLimit or nil
end

local function tierFor(c, value)
  local meta = STYLES[c.style or "laptime"] or STYLES.laptime
  for i, t in ipairs(c.tiers or {}) do
    if meta.higherBetter then
      if value >= t.time then return i, t.xp end
    else
      if value <= t.time then return i, t.xp end
    end
  end
  return nil, 0
end
RM.challenges.tierFor = tierFor

-- what "the value this run scored" means, per style. e.corrected is the run's
-- clock time (clean time plus penalties) and is always present; e.telemetry
-- is what the client sampled during the run and is only meaningful once a
-- style other than lap time is in play.
--
-- damage's score is deliberately simple and deliberately not hidden: miles
-- covered while wrecked, times one plus the damage taken (obj:getDissipatedEnergy(),
-- the same number the vehicle's own damage meter is built from), so a
-- driver who covers ground on a wrecked car scores higher than one who
-- covers the same ground clean, and higher still than one who takes the
-- same hit but goes nowhere. It is a score, not a real-world unit -- the
-- ladder for this style is tuned against that formula, not against a
-- dollar figure or a percentage.
-- every jump this attempt made, distance and height kept together from the
-- same jump -- plus one still in progress if the attempt ended before it
-- landed (see RM.race.telemetry, 10_race.lua). Returns the list in feet,
-- each with its own combined score, and which index scored best -- never a
-- different jump's distance paired with this one's height.
local function jumpsOf(t)
  if type(t) ~= "table" then return nil, nil end
  local raw = {}
  if type(t.jumps) == "table" then
    for i = 1, #t.jumps do raw[#raw + 1] = t.jumps[i] end
  end
  if type(t.pendingJump) == "table" then raw[#raw + 1] = t.pendingJump end
  if #raw == 0 then return nil, nil end

  local jumps, bestIdx, bestScore = {}, nil, nil
  for i = 1, #raw do
    local distFt = (tonumber(raw[i].distanceM) or 0) * 3.28084
    local heightFt = (tonumber(raw[i].heightM) or 0) * 3.28084
    local scoreFt = distFt + heightFt
    jumps[i] = { distanceFt = distFt, heightFt = heightFt, scoreFt = scoreFt }
    if not bestScore or scoreFt > bestScore then bestScore, bestIdx = scoreFt, i end
  end
  return jumps, bestIdx
end

local function valueFor(c, e)
  local style = c.style or "laptime"
  if style == "laptime" then
    return RM.util.isNum(e.corrected) and e.corrected or nil
  end

  local t = e.telemetry
  if type(t) ~= "table" then return nil end

  if style == "speed" then
    return tonumber(t.peakSpeedMph)
  elseif style == "gforce" then
    return tonumber(t.peakG)
  elseif style == "damage" then
    local dmgStart = tonumber(t.damageStart) or 0
    local dmgNow   = tonumber(t.damageNow) or dmgStart
    local taken    = math.max(0, dmgNow - dmgStart)
    local metres   = math.max(0, tonumber(t.distanceM) or 0)
    return (metres / 1609.344) * (1 + taken / 1000)
  elseif style == "longjump" then
    -- scored on the single best jump of the attempt -- its own distance
    -- and height added together, never a different jump's numbers mixed
    -- in. Every other jump made is still kept (see RM.challenges.onFinish)
    -- and shown on the results screen, just not what decides the tier.
    local jumps, bestIdx = jumpsOf(t)
    if not jumps then return nil end
    return jumps[bestIdx].scoreFt
  elseif style == "distance" then
    local metres = tonumber(t.distanceM)
    return metres and (metres / 1609.344) or nil
  end
  return nil
end
RM.challenges.valueFor = valueFor

-- a finished run on a challenge. the best result is kept, and XP is paid for
-- the best rung reached, once, with the difference on the way up. Every
-- attempt counts toward c.attempts even when it does not improve anything,
-- so the results screen can say "3rd try" and not just "your best so far".
function RM.challenges.onFinish(e)
  if type(e) ~= "table" or not e.challenge then return nil end
  local c = RM.challenges.get(e.challenge)
  if not c or not e.key then return nil end
  local meta = STYLES[c.style or "laptime"] or STYLES.laptime
  if e.suspect then return { name = c.name, style = c.style or "laptime", suspect = true } end

  local value = valueFor(c, e)
  if not RM.util.isNum(value) then return nil end

  c.results = c.results or {}
  c.attempts = c.attempts or {}
  local attemptNo = (c.attempts[e.key] or 0) + 1
  c.attempts[e.key] = attemptNo

  local prev = c.results[e.key]
  local previousBest = prev and prev.best or nil
  local tier, tierXp = tierFor(c, value)
  local improved = (not prev)
    or (meta.higherBetter and value > prev.best)
    or ((not meta.higherBetter) and value < prev.best)

  -- the ladder pays every attempt now, not only a new personal best -- but
  -- less each time this driver comes back to this same challenge: this
  -- attempt's own tier value in full the first time, decayed by
  -- challengeRepeatDecay (default 10% off) each attempt after that,
  -- compounding, until it floors to nothing. From there the challenge
  -- still runs -- for the tier itself and the leaderboard -- just not for
  -- further XP. The decay tracks how many times this driver has run the
  -- challenge, not whether this particular attempt improved on the last;
  -- a great run on attempt 10 still only pays attempt 10's rate.
  local decayRate = tonumber(RM.config.challengeRepeatDecay)
  if not decayRate or decayRate < 0 or decayRate > 1 then decayRate = 0.9 end
  local decay = decayRate ^ (attemptNo - 1)
  local ladderXp = 0
  if tier then
    ladderXp = math.floor((tierXp or 0) * decay + 0.0001)
    if ladderXp < 0 then ladderXp = 0 end
  end

  -- .xp on a challenge's result now tracks the running total this driver
  -- has actually been paid from its ladder across every attempt, not just
  -- the face value of their single best tier -- what a leaderboard should
  -- show once a ladder can be paid out more than once.
  local rec = prev or {}
  rec.xp = (tonumber(rec.xp) or 0) + ladderXp
  if improved then
    rec.name = e.name
    rec.best = RM.util.round(value, 3)
    rec.tier = tier
    rec.at = now()
    rec.vehicle = e.vehicle
    rec.class = e.class
    rec.mode = e.mode
  end
  c.results[e.key] = rec

  if ladderXp > 0 and RM.xp then RM.xp.give(e.key, ladderXp, "challenge") end
  save()
  if improved then RM.challenges.broadcastList() end

  -- a flat bonus for finishing the attempt at all -- the same one a
  -- regular race pays (RM.xp.forRace, 17_xp.lua). Separate from the
  -- ladder above and does not decay: every completed attempt earns this,
  -- ladder paid out or not.
  local completionXp = math.floor(tonumber(RM.config.raceCompletionXp) or 0)
  local completionPaid = 0
  if completionXp > 0 and RM.xp then
    local newTotal = RM.xp.give(e.key, completionXp, "completion")
    if newTotal then completionPaid = completionXp end
  end
  if RM.players and RM.players.markRaceCompleted then
    RM.players.markRaceCompleted(e.key)
  end

  local mine = c.results[e.key]
  if RM.players and RM.players.remember then
    RM.players.remember(e.key, {
      kind = "challenge", name = c.name, trackName = c.trackName or c.name,
      track = c.track, corrected = e.corrected, class = e.class, mode = e.mode,
      vehicle = e.vehicle, at = now(), tier = tier, xp = ladderXp, improved = improved,
    })
  end
  RM.info(("%s on challenge %s (%s): %.3f %s, %s, attempt #%d, %d xp%s"):format(
    tostring(e.name), c.id, c.style or "laptime", value, meta.unit,
    tier and ("tier " .. tier) or "outside the ladder", attemptNo, ladderXp,
    improved and " (new best)" or ""))

  -- the driver's level bar, exactly as it stands after everything above
  -- was paid, so the results screen shows real progress rather than a
  -- number from before this attempt.
  local xpTotal, xpLevel = 0, 1
  if RM.xp then xpTotal, xpLevel = RM.xp.of(e.key) end
  xpTotal = xpTotal or 0
  local xpInto, xpNeed = 0, 750
  if RM.xp and RM.xp.progress then xpInto, xpNeed, xpLevel = RM.xp.progress(xpTotal) end
  local xpPct = 0
  if xpNeed and xpNeed > 0 then xpPct = math.floor((xpInto / xpNeed) * 100 + 0.5) end
  if xpPct < 0 then xpPct = 0 elseif xpPct > 100 then xpPct = 100 end

  -- every jump this attempt made, for the results screen -- which one
  -- scored best is what decided the tier above; the rest are shown too,
  -- so a good jump earlier in the attempt isn't invisible just because a
  -- later one scored higher.
  local jumpsForResult, bestJumpIdx = nil, nil
  if (c.style or "laptime") == "longjump" then
    jumpsForResult, bestJumpIdx = jumpsOf(e.telemetry)
  end

  return {
    name = c.name, style = c.style or "laptime", unit = meta.unit,
    value = RM.util.round(value, 3), tier = tier, xp = tierXp, gained = ladderXp,
    best = mine and mine.best or value, improved = improved,
    previousBest = previousBest, attempts = attemptNo,
    completionXp = completionPaid,
    level = xpLevel, xpTotal = xpTotal, xpInto = math.floor(xpInto + 0.5),
    xpNeed = math.floor(xpNeed + 0.5), xpPct = xpPct,
    jumps = jumpsForResult, bestJumpIdx = bestJumpIdx,
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
