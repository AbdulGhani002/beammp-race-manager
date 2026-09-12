RM = RM or {}
RM.race = {}

-- The race state machine, and the only thing that decides a lap time.
--
--   idle -> armed -> running -> finished
--                          \-> abandoned
--
-- One run per player. Phase 4 turns this into a shared grid, so nothing here
-- assumes there is only one of them.
--
-- Gate 1 is the start and finish line. You arm, you are put at the start, and
-- the run begins when you drive through gate 1. On a circuit, coming back
-- through gate 1 after the last gate completes a lap.

local runs = {}      -- pid -> run
local MODES = { controller = true, wheel = true }

local function allocSplits(laps, gates)
  -- built to its final size here and written into by index. nothing is
  -- created while a car is on track, because allocating in that window is
  -- what makes the collector run mid lap.
  local out = {}
  for lap = 1, laps do
    local row = {}
    for g = 1, gates do row[g] = false end
    out[lap] = row
  end
  return out
end

-- distance between consecutive gates, worked out once so the plausibility
-- check on a crossing costs nothing
local function gateDistances(track)
  local cps = track.checkpoints
  local n = #cps
  local d = {}
  for i = 1, n do
    local a = cps[i].pos
    local b = cps[i % n + 1].pos
    local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
    d[i] = math.sqrt(dx * dx + dy * dy + dz * dz)
  end
  return d
end

function RM.race.get(pid) return runs[pid] end

-- whether anyone is mid run. the speeds are read for the player list, and a
-- run in a speed zone needs them read whether or not anyone has the list open.
function RM.race.anyRunning()
  for _, r in pairs(runs) do
    if r.state == "running" then return true end
  end
  return false
end

function RM.race.state(pid)
  local r = runs[pid]
  return r and r.state or "idle"
end

function RM.race.arm(pid, d)
  if type(d) ~= "table" then return false, "bad_request" end

  local s = RM.identity.session(pid)
  if not s then return false, "no_session" end

  local existing = runs[pid]
  if existing and existing.state == "running" then return false, "already_running" end

  local track = RM.tracks.get(type(d.id) == "string" and d.id or "")
  if not track then return false, "no_such_track" end

  local gates = #track.checkpoints
  if gates < 2 then return false, "course_too_short" end

  local mode = tostring(d.mode or "controller")
  if not MODES[mode] then return false, "bad_mode" end

  local laps = math.floor(tonumber(d.laps) or 1)
  if laps < 1 or laps > 99 then return false, "bad_laps" end
  if not track.circuit and laps > 1 then return false, "not_a_circuit" end

  -- The class is entered, not read off the car, because he allows every
  -- vehicle. Nothing is refused for not naming one: practice runs and anyone
  -- who has not picked yet still race, they just sit outside the class books.
  local class = nil
  if d.class ~= nil and d.class ~= "" then
    class = RM.records and RM.records.isClass(d.class)
    if not class then return false, "no_such_class" end
    if not RM.records.carAllowed(class, RM.players.modelOf(pid)) then
      return false, "wrong_car_for_class"
    end
  end

  -- a run on a challenge has to be the challenge's course, laps and class,
  -- and the driver has to be allowed in
  local challenge = nil
  if d.challenge ~= nil and d.challenge ~= "" then
    local okc, why = RM.challenges.check(pid, d.challenge, track.id, laps, class)
    if not okc then return false, why end
    challenge = tostring(d.challenge)
  end

  runs[pid] = {
    key        = s.key,
    track      = track.id,
    challenge  = challenge,
    kind       = track.kind,
    circuit    = track.circuit and true or false,
    mode       = mode,
    class      = class,
    laps       = laps,
    gates      = gates,
    dist       = gateDistances(track),
    currentLap = 0,
    nextGate   = 1,
    state      = "armed",
    armedAt    = RM.now(),
    startedAt  = nil,
    finishedAt = nil,
    splits     = allocSplits(laps, gates),
    lapStart   = {},
    lapTime    = {},
    missed     = {},
    penalties  = {},
    suspect    = false,
    inPit      = false,
    -- how many spare changes are left. seeded from what is really on the
    -- car's rack the first time the button is pressed, because the server
    -- has no way of knowing what the driver turned up in.
    spares     = nil,
  }

  RM.info(("%s armed %s, %s, %d lap(s)%s%s"):format(
    RM.identity.displayName(pid), track.id, mode, laps,
    class and (", " .. class) or "",
    challenge and (", challenge " .. challenge) or ""))
  return true, runs[pid]
end

function RM.race.abandon(pid, why)
  local r = runs[pid]
  if not r then return false, "no_run" end
  if r.state == "finished" or r.state == "abandoned" then return false, "not_running" end
  r.state = "abandoned"
  r.why = why or "ended"
  RM.info(("%s abandoned %s: %s"):format(RM.identity.displayName(pid), r.track, r.why))
  return true, r
end

function RM.race.clear(pid)
  runs[pid] = nil
end

-- seconds added to the clean time, with a reason a person can argue with
function RM.race.penalty(pid, seconds, reason, gate)
  local r = runs[pid]
  if not r or r.state ~= "running" then return false, "not_running" end
  seconds = tonumber(seconds) or 0
  if seconds <= 0 then return false, "bad_penalty" end

  r.penalties[#r.penalties + 1] = {
    seconds = seconds,
    reason  = tostring(reason or "penalty"),
    gate    = gate,
    lap     = r.currentLap,
    at      = RM.util.round(RM.now() - (r.startedAt or RM.now()), 3),
  }
  return true
end

-- a charge taken back off, for a job the game turned out not to be able to do
function RM.race.dropPenalty(pid, reason, lap)
  local r = runs[pid]
  if not r then return false end
  for i = #r.penalties, 1, -1 do
    local p = r.penalties[i]
    if p.reason == reason and (lap == nil or p.lap == lap) then
      table.remove(r.penalties, i)
      return true
    end
  end
  return false
end

function RM.race.penaltyTotal(r)
  local total = 0
  for i = 1, #r.penalties do total = total + r.penalties[i].seconds end
  return total
end

-- How many of each kind, so the screen can name them. It used to be handed a
-- single count and called every one of them a cut, so pressing Reposition
-- once turned "1 cut" into "2 cut" and a driver who had cut one corner was
-- told he had cut two.
function RM.race.penaltyBy(r)
  local by, any = {}, false
  for i = 1, #r.penalties do
    local why = tostring(r.penalties[i].reason or "penalty")
    by[why] = (by[why] or 0) + 1
    any = true
  end
  return any and by or nil
end

-- every message that carries a penalty count carries the same three things
local function withPenalties(r, msg)
  msg.penalties   = #r.penalties
  msg.penaltyTime = RM.race.penaltyTotal(r)
  msg.penaltyBy   = RM.race.penaltyBy(r)
  return msg
end

-- nextGate runs one past the last gate while a lap waits on the line, which is
-- the state the run is in for the whole drive back to it. Both of these say so
-- plainly rather than leaving the screen to work it out: the bar counted that
-- as no gates done and emptied itself right at the end of the lap.
local function gatesDone(r)
  local n = r.nextGate - 1
  if n < 0 then return 0 end
  if n > r.gates then return r.gates end
  return n
end

local function nextShown(r)
  return r.nextGate > r.gates and 1 or r.nextGate
end

local MPS_PER_MPH = 0.44704

-- nothing on wheels covers this ground in that time, so a stamp claiming it
-- did not happen the way the client says it did
local function implausible(r, fromGate, toGate, seconds)
  if seconds <= 0 then return true end
  local metres = 0
  local g = fromGate
  while g ~= toGate do
    metres = metres + (r.dist[g] or 0)
    g = g % r.gates + 1
  end
  local ceiling = RM.config.maxPlausibleMph * MPS_PER_MPH
  return (metres / seconds) > ceiling
end

local function finish(pid, r, t)
  r.state = "finished"
  r.finishedAt = t
  r.clean = RM.util.round(t - r.startedAt, 3)
  r.corrected = RM.util.round(r.clean + RM.race.penaltyTotal(r), 3)
  RM.info(("%s finished %s: clean %.3f, corrected %.3f%s"):format(
    RM.identity.displayName(pid), r.track, r.clean, r.corrected,
    r.suspect and " (marked)" or ""))
end

-- The offset between the two clocks is re-estimated every few seconds, and
-- the estimate moves: the best of the last eight samples changes as the window
-- slides. Converting the start of a run with one estimate and the end of it
-- with another measures the drift as much as the driving. A seven second run
-- came back as a 213 second lap that way, and a lap boundary made the clock on
-- screen count backwards.
--
-- So a run takes its own copy of the offset the first time it needs one and
-- keeps it. Every stamp in the run is then read in the same frame, and the
-- difference between two of them is the time that actually passed.
function RM.race.stamp(r, pid, clientTime)
  if r.offset == nil then
    local s = RM.identity.session(pid)
    local o = s and s.clockOffset
    r.offset = o or false
    r.slack  = (s and s.clockDelay or 0) + (RM.config.clockTrustMs / 1000)
  end

  local now = RM.now()
  if r.offset == false or not RM.util.isNum(clientTime) then return now, false end

  local t = clientTime - r.offset
  if t > now or t < (now - (r.slack or 2)) then return now, false end
  return t, true
end

-- a gate crossing, stamped by the client and decided here
function RM.race.gate(pid, index, clientTime)
  local r = runs[pid]
  if not r then return false, "no_run" end

  index = math.floor(tonumber(index) or 0)
  if index < 1 or index > r.gates then return false, "no_such_gate" end

  local t, trusted = RM.race.stamp(r, pid, clientTime)
  if not trusted then r.suspect = true end

  -- the run has not begun: only the start line begins it
  if r.state == "armed" then
    if index ~= 1 then return false, "not_the_start" end
    r.state      = "running"
    r.currentLap = 1
    r.startedAt  = t
    r.lastAt     = t
    r.splits[1][1] = 0
    r.lapStart[1] = 0
    r.nextGate   = 2
    return true, { lap = 1, gate = 1, split = 0, started = true, next = 2,
                   done = 1, penalties = 0 }
  end

  if r.state ~= "running" then return false, "not_running" end

  local elapsed = RM.util.round(t - r.startedAt, 3)

  -- times do not go backwards
  if elapsed <= (r.lastSplit or -1) then
    r.suspect = true
    return false, "out_of_order"
  end

  local wrapping = r.circuit and r.nextGate > r.gates

  -- The line can also come up early, because the gates at the end of the lap
  -- were cut. Without this the crossing is read as gate 1 arriving before its
  -- turn and thrown out as already crossed, and then nothing finishes the run
  -- at all: the clock keeps going, the line does nothing however many times it
  -- is crossed, and the only way out is to quit. That is what happened on the
  -- run that missed gate 5.
  --
  -- Crossing the line two gates into a five gate loop is turning round, not
  -- finishing, so the lap has to be mostly done before the line will close it
  -- early. Anyone who has abandoned the course before that has End Race, which
  -- files the run properly rather than leaving it open.
  local doneGates = r.nextGate - 1
  if r.circuit and not wrapping and index == 1 and doneGates * 2 > r.gates then
    local missed = r.missed[r.currentLap] or {}
    for g = r.nextGate, r.gates do
      missed[#missed + 1] = g
      RM.race.penalty(pid, RM.config.penalties.missedGate, "missed_gate", g)
    end
    r.missed[r.currentLap] = missed
    r.nextGate = r.gates + 1
    wrapping = true
  end

  if wrapping then
    -- every gate is done, so the only thing left is the lap line
    if index ~= 1 then return false, "expected_lap_line" end

    if implausible(r, r.gates, 1, t - r.lastAt) then r.suspect = true end

    r.lastSplit = elapsed
    r.lastAt = t

    -- the lap is measured to the line, not to the last gate before it
    r.lapTime[r.currentLap] = RM.util.round(elapsed - (r.lapStart[r.currentLap] or 0), 3)

    if r.currentLap >= r.laps then
      finish(pid, r, t)
      return true, withPenalties(r, { lap = r.currentLap, gate = 1, split = elapsed,
                     lapTime = r.lapTime[r.currentLap], lapTimeLap = r.currentLap,
                     finished = true, next = 0, done = r.gates })
    end

    local doneLap = r.currentLap
    r.currentLap = r.currentLap + 1
    r.splits[r.currentLap][1] = elapsed
    r.lapStart[r.currentLap] = elapsed
    r.nextGate = 2
    return true, withPenalties(r, { lap = r.currentLap, gate = 1, split = elapsed,
                   lapTime = r.lapTime[doneLap], lapTimeLap = doneLap,
                   lapDone = true, next = 2, done = 1 })
  end

  local expected = r.nextGate

  if index < expected then
    -- A gate already charged as missed, turning up late. Two volumes on this
    -- course sit fourteen metres apart and are twenty metres wide, so they can
    -- fire in either order, and the one that lands first charges the other as
    -- a cut. Driving through it afterwards proves it was not cut, so the charge
    -- comes back off.
    local missed = r.missed[r.currentLap]
    for k = 1, (missed and #missed or 0) do
      if missed[k] == index then
        table.remove(missed, k)
        for j = #r.penalties, 1, -1 do
          local pen = r.penalties[j]
          if pen.reason == "missed_gate" and pen.gate == index and pen.lap == r.currentLap then
            table.remove(r.penalties, j)
            break
          end
        end
        r.splits[r.currentLap][index] = elapsed
        RM.info(("%s reached gate %d after all, penalty refunded"):format(
          RM.identity.displayName(pid), index))
        return true, withPenalties(r, { lap = r.currentLap, gate = index,
                       split = elapsed, refunded = true,
                       next = nextShown(r), done = gatesDone(r) })
      end
    end

    -- already have this one for this lap
    return false, "already_crossed"
  end

  -- A gate far up the course is usually not one you drove through, it is one
  -- whose volume sits on the road you are on: this course puts gate 30 between
  -- gates 3 and 4, and taking it charged 26 cuts for gates still ahead.
  --
  -- Refusing it forever is worse though. Miss more than the cap and every gate
  -- left is refused, so the run cannot finish and quitting is the only way out.
  -- A stray volume fires once. Being genuinely that far down the course fires
  -- gate after gate, so the second one in order is taken as real.
  local cap = RM.config.maxGateSkip or 4
  if index - expected > cap then
    if r.strayGate and index > r.strayGate and index - r.strayGate <= cap then
      RM.info(("%s is at gate %d, not %d. picking the run up there"):format(
        RM.identity.displayName(pid), index, expected))
      r.strayGate = nil
    else
      r.strayGate = index
      return false, "not_this_gate"
    end
  else
    r.strayGate = nil
  end

  -- a later gate firing while an earlier one has no split means the earlier
  -- ones were cut or tunnelled through at speed
  if index > expected then
    local missed = r.missed[r.currentLap] or {}
    for g = expected, index - 1 do
      missed[#missed + 1] = g
      RM.race.penalty(pid, RM.config.penalties.missedGate, "missed_gate", g)
    end
    r.missed[r.currentLap] = missed
  end

  if implausible(r, expected - 1 < 1 and r.gates or expected - 1, index, t - r.lastAt) then
    r.suspect = true
  end

  r.splits[r.currentLap][index] = elapsed
  r.lastSplit = elapsed
  r.lastAt = t
  r.nextGate = index + 1

  -- a point to point course ends at its last gate
  if not r.circuit and index == r.gates then
    r.lapTime[r.currentLap] = RM.util.round(elapsed - (r.lapStart[r.currentLap] or 0), 3)
    finish(pid, r, t)
    return true, withPenalties(r, { lap = r.currentLap, gate = index, split = elapsed,
                   lapTime = r.lapTime[r.currentLap], lapTimeLap = r.currentLap,
                   finished = true, next = 0, done = r.gates })
  end

  return true, {
    lap = r.currentLap, gate = index, split = elapsed,
    next = nextShown(r), done = gatesDone(r),
    penalties = #r.penalties,
    penaltyTime = RM.race.penaltyTotal(r),
    missed = index > expected and (index - expected) or nil,
  }
end

-- In the pit nothing is added to your time. The hold still runs and the clock
-- is still going, so a stop costs you the wait and nothing on top.
function RM.race.setPit(pid, inside)
  local r = runs[pid]
  if not r or r.state ~= "running" then return false, "not_running" end
  local was = r.inPit and true or false
  r.inPit = inside and true or false
  if was == r.inPit then return false, "no_change" end
  return true, r.inPit
end

function RM.race.inPit(pid)
  local r = runs[pid]
  return r ~= nil and r.inPit == true
end

-- End Race. stops everything at once, which is what the button promises.
function RM.race.endRace(pid)
  local r = runs[pid]
  if not r then return false, "no_run" end
  if r.state == "running" or r.state == "armed" then
    return RM.race.abandon(pid, "ended by the driver")
  end
  return false, "not_running"
end

function RM.race.onLeave(pid)
  local r = runs[pid]
  if r and (r.state == "running" or r.state == "armed") then
    RM.race.abandon(pid, "left the server")
  end
end

function RM.race.forEach(fn)
  for pid, r in pairs(runs) do fn(pid, r) end
end

function RM.race.isActive(pid)
  local r = runs[pid]
  return r ~= nil and (r.state == "armed" or r.state == "running")
end

-- a run nobody finished would hold the results open for everyone else on the
-- course, so one that has been sitting there too long is ended for them
function RM.race.sweep()
  local now = RM.now()
  local limit = RM.config.raceIdleTimeoutMs / 1000
  local ended = nil
  for pid, r in pairs(runs) do
    if r.state == "armed" or r.state == "running" then
      local since = now - (r.startedAt or r.armedAt or now)
      if since > limit then
        RM.race.abandon(pid, "no lap finished in " .. math.floor(limit / 60) .. " minutes")
        ended = ended or {}
        ended[#ended + 1] = pid
      end
    end
  end
  return ended
end

-- what the interface is allowed to know while a run is going. deliberately
-- not the splits table: the HUD shows the split it was just sent, and the
-- whole picture waits for the results screen.
function RM.race.wire(pid)
  local r = runs[pid]
  if not r then return { state = "idle" } end
  -- the challenge rides on the state so the screen can say so during the run
  return {
    state    = r.state,
    track    = r.track,
    mode     = r.mode,
    laps     = r.laps,
    lap      = r.currentLap,
    gates    = r.gates,
    next     = nextShown(r),
    done     = gatesDone(r),
    circuit  = r.circuit,
    clean    = r.clean,
    corrected = r.corrected,
    penalties = #r.penalties,

    -- the seconds as well as the count, so the clock on screen can carry them.
    -- a penalty that does not move the time reads as free until the results
    -- come up, which is far too late to change how you are driving.
    penaltyTime = RM.race.penaltyTotal(r),

    -- and what they were for, so a reposition is not read out as a cut
    penaltyBy = RM.race.penaltyBy(r),
    challenge = r.challenge,
    inPit    = r.inPit and true or false,
    why      = r.why,

    -- only somebody who is off track is waiting on anyone. waitingOn counts
    -- every live run on the course including this one, so sending it while the
    -- clock is going tells a driver racing alone that they are waiting on
    -- themselves, which is what the screen showed.
    waiting  = (r.state == "finished" or r.state == "abandoned")
               and RM.results and RM.results.waitingOn(r.track) or nil,
  }
end

-- everything about a finished run, built once when it ends
function RM.race.results(pid)
  local r = runs[pid]
  if not r or r.state ~= "finished" then return nil end

  local laps = {}
  for lap = 1, r.currentLap do
    laps[lap] = {
      lap    = lap,
      splits = r.splits[lap],
      missed = r.missed[lap] or {},
      time   = r.lapTime[lap],
      start  = r.lapStart[lap],
    }
  end

  return {
    key       = r.key,
    name      = RM.identity.displayName(pid),
    track     = r.track,
    mode      = r.mode,
    clean     = r.clean,
    corrected = r.corrected,
    penalties = r.penalties,
    laps      = laps,
    suspect   = r.suspect,
  }
end

function RM.race.count()
  local n = 0
  for _ in pairs(runs) do n = n + 1 end
  return n
end
