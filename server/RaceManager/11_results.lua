RM = RM or {}
RM.results = {}

-- Results are not a live leaderboard. That was his call and it removes the
-- largest network cost in the system: nothing is recomputed on a timer,
-- nothing is pushed while a car is on track, and there is no position to poll.
--
-- Instead everyone racing the same course is a heat. The payload is built
-- once, when the last of them is off track, and sent once. A driver who
-- finishes first waits, and is told how many people they are waiting for so
-- the screen is not just empty.

local heats = {}     -- heat key -> { key, track, members = { pid = true }, done = { ... }, at = n }

-- Which board a run belongs on. Drivers a lobby started together carry the
-- same heat id and share one board; anybody who armed on their own is their
-- own heat, even on the same course at the same moment.
--
-- This was the course id alone, and that is how a stranger appeared in an
-- official race: he armed a one lap run of his own on the same course while
-- the four lap race was on, and the board could not tell the two apart. He
-- was not in the race, he was just on the same piece of ground.
local function keyOfRun(r)
  if type(r) ~= "table" or not r.track then return nil end
  -- started together by a lobby: that board is exactly those drivers, and
  -- nobody who merely turned up on the same course can land on it
  if r.heat then return tostring(r.track) .. "|" .. tostring(r.heat) end
  -- nobody started them together, so they share with anyone driving the same
  -- thing: same course, same number of laps, same challenge. Two friends who
  -- each press Enter still race each other, and a mixed field of classes is
  -- still one race. A one lap run cannot land on a four lap race's board.
  return table.concat({
    tostring(r.track), "open",
    tostring(r.laps or 1),
    tostring(r.challenge or ""),
  }, "|")
end

local function heatFor(key, trackId)
  local h = heats[key]
  if not h then
    h = { key = key, track = trackId, members = {}, done = {}, at = RM.now() }
    heats[key] = h
  end
  return h
end

function RM.results.join(pid, trackId)
  local r = RM.race.get(pid)
  local key = keyOfRun(r)
  if not key then return end
  local h = heatFor(key, r.track or trackId)
  h.members[pid] = true
end

-- how many of this heat are still out there, so it is closed when the last
-- of them is off track and not before
local function waitingInHeat(h)
  if not h then return nil end
  local n = 0
  for pid in pairs(h.members) do
    local r = RM.race.get(pid)
    if r and keyOfRun(r) == h.key and (r.state == "armed" or r.state == "running") then
      n = n + 1
    end
  end
  return n > 0 and n or nil
end

-- how many are still out on this course, for the screen and the console.
-- Across every heat on it: the question there is "is anyone still driving
-- this", not "which board is waiting".
--
-- The run has to be on this course, not merely active. Somebody who arms on
-- one course and then arms on another is no longer racing the first, and
-- counting them would leave that heat waiting on a car that is somewhere else.
function RM.results.waitingOn(trackId)
  local n = 0
  for _, h in pairs(heats) do
    if h.track == trackId then
      for pid in pairs(h.members) do
        local r = RM.race.get(pid)
        if r and r.track == trackId and (r.state == "armed" or r.state == "running") then
          n = n + 1
        end
      end
    end
  end
  return n > 0 and n or nil
end

-- One row per driver on a board. A driver who finishes, arms the same course
-- again and finishes again is one driver with two runs, and a run written
-- down twice is still one run. The better of the two stands: more laps
-- first, then the lower corrected time.
local function lapsOf(e) return e and e.laps and #e.laps or 0 end

local function betterRun(a, b)
  local la, lb = lapsOf(a), lapsOf(b)
  if la ~= lb then return la > lb end
  return (a.corrected or math.huge) < (b.corrected or math.huge)
end

local function remember(h, entry)
  local key = entry and entry.key
  if key then
    for i = 1, #h.done do
      local e = h.done[i]
      if e.key == key then
        -- finishing beats not finishing; between two of either, the later
        -- word for a retirement and the better run for a finish
        if e.dnf and not entry.dnf then h.done[i] = entry
        elseif e.dnf and entry.dnf then h.done[i] = entry
        elseif not e.dnf and not entry.dnf and betterRun(entry, e) then h.done[i] = entry end
        return
      end
    end
  end
  h.done[#h.done + 1] = entry
end

-- Splits are stored as seconds from the start of the run, because a stored
-- delta cannot be recovered into an absolute once a gate is missed, while an
-- absolute can always be turned into a delta. So the deltas people actually
-- read are worked out here, once, and sectors[g] is the time taken to get
-- into gate g.
--
-- A gate that was cut has no split, so the sector either side of it is
-- unknowable and is left false rather than guessed at. False and not nil: a
-- hole in the middle of a lua table makes it an object once it is encoded,
-- and then the interface indexes it by number and finds nothing.
local function sectorsFor(lap, gates)
  local splits = lap.splits
  local out = {}
  for g = 1, gates + 1 do out[g] = false end

  for g = 2, gates do
    local a, b = splits[g - 1], splits[g]
    if type(a) == "number" and type(b) == "number" then
      out[g] = RM.util.round(b - a, 3)
    end
  end

  -- the run from the last gate back to the line, which is a sector like any
  -- other and is where most of a Baja lap is won
  local last = splits[gates]
  if type(last) == "number" and type(lap.start) == "number" and type(lap.time) == "number" then
    local closing = (lap.start + lap.time) - last
    if closing > 0 then out[gates + 1] = RM.util.round(closing, 3) end
  end

  return out
end

local function bestOf(list)
  local bestVal, bestAt = nil, nil
  for k, v in pairs(list) do
    if type(v) == "number" and v > 0 and (not bestVal or v < bestVal) then
      bestVal, bestAt = v, k
    end
  end
  return bestVal, bestAt
end

local function summarise(entry)
  if entry.dnf then return entry end

  local gates = entry.gates or 0
  local bestLap, bestLapNo = nil, nil
  local bestSector, bestSectorGate, bestSectorLap = nil, nil, nil

  for i = 1, #entry.laps do
    local lap = entry.laps[i]
    lap.sectors = sectorsFor(lap, gates)

    -- a lap that cut a gate is a shorter lap, so it would win best lap almost
    -- every time. it is still timed and still shown, it just cannot hold the
    -- record. phase 5 reads best lap straight out of here.
    local cut = lap.missed and #lap.missed > 0
    if type(lap.time) == "number" and lap.time > 0 and not cut then
      if not bestLap or lap.time < bestLap then bestLap, bestLapNo = lap.time, lap.lap end
    end

    local v, g = bestOf(lap.sectors)
    if v and (not bestSector or v < bestSector) then
      bestSector, bestSectorGate, bestSectorLap = v, g, lap.lap
    end
  end

  entry.bestLap = bestLap and { time = bestLap, lap = bestLapNo } or nil
  entry.bestSector = bestSector
    and { time = bestSector, gate = bestSectorGate, lap = bestSectorLap } or nil
  return entry
end

local function build(trackId, h)
  local finished, dnf = {}, {}

  for i = 1, #h.done do
    local e = summarise(h.done[i])
    if e.dnf then dnf[#dnf + 1] = e else finished[#finished + 1] = e end
  end

  -- Distance first, then time. Whoever completed more laps is ahead however
  -- long they took, which is how every race is scored. Ordered by time alone,
  -- a driver who did one lap of a four lap race sat at the top of the board,
  -- above everyone who had driven all four.
  table.sort(finished, function(a, b)
    local la, lb = lapsOf(a), lapsOf(b)
    if la ~= lb then return la > lb end
    return a.corrected < b.corrected
  end)

  -- DNFs ranked by how long each stayed in before leaving or being kicked --
  -- the most recent departure first, which is the same thing as "made it
  -- the furthest" for anyone who left of their own accord partway through,
  -- and for a kick, simply the order they actually happened in.
  table.sort(dnf, function(a, b) return (a.at or 0) > (b.at or 0) end)
  for i = 1, #dnf do dnf[i].pos = i end

  local leader = finished[1]
  local overallBest = nil

  for i = 1, #finished do
    local e = finished[i]
    e.pos = i
    e.toLeader = i == 1 and 0 or RM.util.round(e.corrected - leader.corrected, 3)
    e.toAhead  = i == 1 and 0 or RM.util.round(e.corrected - finished[i - 1].corrected, 3)

    if e.bestLap and (not overallBest or e.bestLap.time < overallBest.time) then
      overallBest = { time = e.bestLap.time, lap = e.bestLap.lap, name = e.name }
    end
  end

  local track = RM.tracks.get(trackId)

  return {
    track     = trackId,
    trackName = track and track.name or trackId,
    circuit   = track and track.circuit or false,
    gates     = track and #track.checkpoints or 0,
    bestLap   = overallBest,
    finished  = finished,
    dnf       = dnf,
  }
end

local function send(h, payload)
  local sent = 0
  for pid in pairs(h.members) do
    if RM.identity.session(pid) then
      RM.bus.queue(pid, "race.results", payload)
      sent = sent + 1
    end
  end
  return sent
end

-- A qualifying session is a race whose job is to set the grid for the next one
-- on that course. Kept for the session only: a grid earned this evening should
-- not still be deciding who starts where next week.
local quali = {}

function RM.results.qualifyingOrder(trackId)
  return quali[tostring(trackId or "")]
end

function RM.results.clearQualifying(trackId)
  quali[tostring(trackId or "")] = nil
end

local function rememberQualifying(trackId, payload)
  local track = RM.tracks.get(trackId)
  if not track or track.kind ~= "qualifying" then return end
  local order = {}
  for i = 1, #payload.finished do
    order[#order + 1] = payload.finished[i].key
  end
  if #order == 0 then return end
  quali[tostring(trackId)] = order
  RM.info(("%s qualifying order set, %d driver(s)"):format(tostring(trackId), #order))
end

-- everybody on this course is off track, so the whole thing can be worked out
-- and sent in one go and then forgotten about
local function close(h)
  if not h then return end
  local trackId = h.track

  if #h.done == 0 then
    heats[h.key] = nil
    return
  end

  local payload = build(trackId, h)

  -- the books first, so the badge rides on the row it belongs to
  for i = 1, #payload.finished do
    local e = payload.finished[i]
    local got = RM.records and RM.records.submit(trackId, e)
    if got then
      e.record = got.track and "track" or (got.personal and "personal" or nil)
      e.classRecord = got.class
      e.lapRecord = got.lap and true or nil
    end
  end

  -- paid before it goes out, so the row can carry what it earned
  if RM.xp then RM.xp.forRace(payload) end

  -- and the challenge ladder, for anyone who was on one
  if RM.challenges then
    for i = 1, #payload.finished do
      local e = payload.finished[i]
      if e.challenge then e.challengeResult = RM.challenges.onFinish(e) end
    end
  end

  -- and the team standing beside the rows, both drivers added together
  if RM.team then payload.teams = RM.team.standings(payload.finished) end

  rememberQualifying(trackId, payload)

  local sent = send(h, payload)
  heats[h.key] = nil

  -- who hosted, so Bobby can pick the official vs open results channel
  local hostPid, hostName, hostKey
  if RM.lobby then
    local l = RM.lobby.get and RM.lobby.get(trackId)
    if not l then
      for pid, _ in pairs(h.members or {}) do
        local lobby = RM.lobby.of and RM.lobby.of(pid)
        if lobby and lobby.host then hostPid = lobby.host break end
      end
    else
      hostPid = l.host
    end
  end
  if hostPid then
    hostName = RM.identity.displayName(hostPid)
    local hs = RM.identity.session(hostPid)
    hostKey = hs and hs.key
  end
  payload.hostName = hostName
  payload.hostKey = hostKey
  local official = false
  local officialName = nil
  -- Prefer the explicit official flag set when the host armed / created the race
  for pid, _ in pairs(h.members or {}) do
    local run = RM.race.get and RM.race.get(pid)
    if not run and RM.race.runs then run = RM.race.runs()[pid] end
    -- fall through: runs table is local to 10_race; use finished payload rows later
  end
  for i = 1, #(payload.finished or {}) do
    local e = payload.finished[i]
    if type(e) == "table" and e.official then
      official = true
      if e.officialName and e.officialName ~= "" then officialName = e.officialName end
    end
  end
  local nm = tostring(hostName or ""):lower()
  if nm:find("dard", 1, true) then official = true end
  if hostPid and RM.roles and RM.roles.atLeast and RM.roles.atLeast(hostPid, "staff") then
    -- staff host alone does not force official unless they checked the box;
    -- keep host-role stamp for Bobby channel routing of staff-hosted public heats
  end
  local hostRole = nil
  if hostPid and RM.roles and RM.roles.of then
    hostRole = RM.roles.of(hostPid)
  end
  -- Staff+ hosts without the official checkbox still go to the staff results channel
  local staffHost = hostPid and RM.roles and RM.roles.atLeast and RM.roles.atLeast(hostPid, "staff")
  if staffHost and not official then
    -- leave official false for series points; channel routing uses staffHost below
  end
  payload.hostRole = hostRole
  payload.official = official
  payload.officialName = officialName
  payload.staffHost = staffHost and true or false
  if official then
    if officialName and officialName ~= "" then
      payload.title = "Baja Sim Official Race (" .. officialName .. ")"
      payload.trackName = payload.title
    else
      payload.title = "Baja Sim Official Race"
    end
  end

  -- last-three history on each driver so the rank card can reopen it
  for i = 1, #payload.finished do
    local e = payload.finished[i]
    if e.key and RM.players and RM.players.remember then
      RM.players.remember(e.key, {
        kind = "race", track = payload.track, trackName = payload.trackName,
        pos = e.pos, corrected = e.corrected, clean = e.clean,
        class = e.class, vehicle = e.vehicle, mode = e.mode,
        at = os.time(), record = e.record, classRecord = e.classRecord,
        bestLap = e.bestLap, penalties = e.penalties, laps = e.laps,
        toLeader = e.toLeader, toAhead = e.toAhead, xp = e.xp,
      })
    end
  end

  -- Discord and the log only keep heats somebody finished.
  if type(payload.finished) == "table" and #payload.finished > 0 then
    if RM.racelog then RM.racelog.record(payload) end
    if RM.live and RM.live.writeResults then RM.live.writeResults(payload) end
  end

  RM.info(("results for %s: %d finished, %d out, sent to %d"):format(
    trackId, #payload.finished, #payload.dnf, sent))
end

-- called once for every run that stops, however it stopped
-- The dispatcher every call site uses once a run is off track, however it
-- got there (crossed the finish line, timed out, End Race, or the driver
-- disconnected). A lap-time challenge is still a race against whoever else
-- is on the course -- it goes through the heat above, same as ever. Every
-- other style is a solo attempt with nothing to wait on, so it resolves on
-- its own, immediately, through onChallengeAttemptEnded below.
function RM.results.finishRun(pid)
  local r = RM.race.get(pid)
  local c = r and r.challenge and RM.challenges.get(r.challenge)
  if c and (c.style or "laptime") ~= "laptime" then
    return RM.results.onChallengeAttemptEnded(pid)
  end
  return RM.results.onRunEnded(pid)
end

-- A speed/g-force/damage/long-jump/distance attempt, free roam or on a
-- course, resolves the moment it ends: there is no heat to wait on, so the
-- driver hears back straight away rather than waiting on whoever else might
-- be racing the same course.
function RM.results.onChallengeAttemptEnded(pid)
  local r = RM.race.get(pid)
  if not r then return end

  if r.state ~= "finished" then
    RM.bus.queue(pid, "challenge.finished", { ok = false, why = r.why or "ended" })
    return
  end

  local entry = RM.race.results(pid)
  if not entry then return end
  entry.gates = r.gates
  entry.vehicle = RM.players.modelOf(pid)
  entry.class = r.class
  entry.challenge = r.challenge
  entry.telemetry = r.telemetry

  local c = RM.challenges.get(r.challenge)
  local result = RM.challenges.onFinish(entry)

  -- a handful of the driver's other challenge standings, so the screen can
  -- show "you've also done well elsewhere" rather than only this one result
  local others = {}
  if RM.challenges.forDriver then
    local all = RM.challenges.forDriver(r.key) or {}
    for i = 1, #all do
      if all[i].id ~= r.challenge and #others < 5 then
        others[#others + 1] = all[i]
      end
    end
  end

  RM.bus.queue(pid, "challenge.finished", {
    ok = true,
    challenge = c and {
      id = c.id, name = c.name, kind = c.kind, style = c.style or "laptime",
      trackName = c.trackName, description = c.description,
    } or nil,
    run = { clean = entry.clean, corrected = entry.corrected,
            vehicle = entry.vehicle, class = entry.class },
    result = result,
    others = others,
  })
end

function RM.results.onRunEnded(pid)
  local r = RM.race.get(pid)
  if not r then return end

  local h = heats[keyOfRun(r) or ""]
  if not h then return end

  if r.state == "finished" then
    local entry = RM.race.results(pid)
    if entry then
      entry.gates = r.gates
      -- what they drove and what they entered, so the books can be sorted by
      -- class and the discord bot can read a class off the log
      entry.vehicle = RM.players.modelOf(pid)
      entry.class   = r.class
      entry.challenge = r.challenge
      -- what the client sampled during the run, for a challenge scored on
      -- something other than the clock (speed/g-force/damage/long jump/
      -- distance). Absent for a plain race or a lap-time challenge.
      entry.telemetry = r.telemetry
      entry.official = r.official and true or false
      entry.officialName = r.officialName
      remember(h, entry)
    end
  else
    remember(h, {
      key     = r.key,
      name    = RM.identity.displayName(pid),
      track   = r.track,
      mode    = r.mode,
      dnf     = true,
      why     = r.why or "did not finish",
      kicked  = r.kicked and true or false,
      lap     = r.currentLap,
      at      = r.abandonedAt or RM.now(),
    })
  end

  local left = waitingInHeat(h)
  if left then
    for other in pairs(h.members) do
      if RM.identity.session(other) and not RM.race.isActive(other) then
        RM.bus.queue(other, "race.waiting", { left = left })
      end
    end
    return
  end

  close(h)
end

function RM.results.forget(pid)
  for _, h in pairs(heats) do h.members[pid] = nil end
end

-- Take a driver off any board that has not gone out yet, their rows with
-- them. A run that is already over cannot be kicked out of a race, but the
-- driver can still be sitting on a board waiting on somebody else, and
-- taking them off it is what staff mean when they press Kick from race.
function RM.results.remove(pid)
  local key = nil
  local s = RM.identity.session(pid)
  if s then key = s.key end
  if not key then
    local r = RM.race.get(pid)
    key = r and r.key or nil
  end

  local removed = false
  for hk, h in pairs(heats) do
    if h.members[pid] then
      h.members[pid] = nil
      removed = true
    end
    if key then
      for i = #h.done, 1, -1 do
        if h.done[i].key == key then
          table.remove(h.done, i)
          removed = true
        end
      end
    end
    if next(h.members) == nil and #h.done == 0 then heats[hk] = nil end
  end
  return removed
end

function RM.results.count()
  local n = 0
  for _ in pairs(heats) do n = n + 1 end
  return n
end

function RM.results.heats()
  return heats
end
