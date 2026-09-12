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

local heats = {}     -- trackId -> { members = { pid = true }, done = { ... }, at = n }

local function heatFor(trackId)
  local h = heats[trackId]
  if not h then
    h = { members = {}, done = {}, at = RM.now() }
    heats[trackId] = h
  end
  return h
end

function RM.results.join(pid, trackId)
  local h = heatFor(trackId)
  h.members[pid] = true
end

-- how many are still out there. nil rather than 0 so the interface can tell
-- "waiting for two" from "nobody is racing".
--
-- The run has to be on this course, not merely active. Somebody who arms on
-- one course and then arms on another is no longer racing the first, and
-- counting them would leave that heat waiting on a car that is somewhere else.
function RM.results.waitingOn(trackId)
  local h = heats[trackId]
  if not h then return nil end
  local n = 0
  for pid in pairs(h.members) do
    local r = RM.race.get(pid)
    if r and r.track == trackId and (r.state == "armed" or r.state == "running") then
      n = n + 1
    end
  end
  return n > 0 and n or nil
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

  table.sort(finished, function(a, b) return a.corrected < b.corrected end)

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
local function close(trackId)
  local h = heats[trackId]
  if not h then return end

  if #h.done == 0 then
    heats[trackId] = nil
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
  heats[trackId] = nil

  -- one line on disk for their discord bot
  if RM.racelog then RM.racelog.record(payload) end

  RM.info(("results for %s: %d finished, %d out, sent to %d"):format(
    trackId, #payload.finished, #payload.dnf, sent))
end

-- called once for every run that stops, however it stopped
function RM.results.onRunEnded(pid)
  local r = RM.race.get(pid)
  if not r then return end

  local h = heats[r.track]
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
      h.done[#h.done + 1] = entry
    end
  else
    h.done[#h.done + 1] = {
      key   = r.key,
      name  = RM.identity.displayName(pid),
      track = r.track,
      mode  = r.mode,
      dnf   = true,
      why   = r.why or "did not finish",
      lap   = r.currentLap,
    }
  end

  local left = RM.results.waitingOn(r.track)
  if left then
    for other in pairs(h.members) do
      if RM.identity.session(other) and not RM.race.isActive(other) then
        RM.bus.queue(other, "race.waiting", { left = left })
      end
    end
    return
  end

  close(r.track)
end

function RM.results.forget(pid)
  for _, h in pairs(heats) do h.members[pid] = nil end
end

function RM.results.count()
  local n = 0
  for _ in pairs(heats) do n = n + 1 end
  return n
end

function RM.results.heats()
  return heats
end
