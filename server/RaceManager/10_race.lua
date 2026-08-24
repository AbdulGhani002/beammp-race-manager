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

  runs[pid] = {
    key        = s.key,
    track      = track.id,
    kind       = track.kind,
    circuit    = track.circuit and true or false,
    mode       = mode,
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
  }

  RM.info(("%s armed %s, %s, %d lap(s)"):format(
    RM.identity.displayName(pid), track.id, mode, laps))
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

function RM.race.penaltyTotal(r)
  local total = 0
  for i = 1, #r.penalties do total = total + r.penalties[i].seconds end
  return total
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

-- a gate crossing, stamped by the client and decided here
function RM.race.gate(pid, index, clientTime)
  local r = runs[pid]
  if not r then return false, "no_run" end

  index = math.floor(tonumber(index) or 0)
  if index < 1 or index > r.gates then return false, "no_such_gate" end

  local t, trusted = RM.clock.toServer(pid, clientTime)
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
                   penalties = 0 }
  end

  if r.state ~= "running" then return false, "not_running" end

  local elapsed = RM.util.round(t - r.startedAt, 3)

  -- times do not go backwards
  if elapsed <= (r.lastSplit or -1) then
    r.suspect = true
    return false, "out_of_order"
  end

  local wrapping = r.circuit and r.nextGate > r.gates

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
      return true, { lap = r.currentLap, gate = 1, split = elapsed,
                     lapTime = r.lapTime[r.currentLap], lapTimeLap = r.currentLap,
                     finished = true, next = 0, penalties = #r.penalties }
    end

    local doneLap = r.currentLap
    r.currentLap = r.currentLap + 1
    r.splits[r.currentLap][1] = elapsed
    r.lapStart[r.currentLap] = elapsed
    r.nextGate = 2
    return true, { lap = r.currentLap, gate = 1, split = elapsed,
                   lapTime = r.lapTime[doneLap], lapTimeLap = doneLap,
                   lapDone = true, next = 2, penalties = #r.penalties }
  end

  local expected = r.nextGate

  if index < expected then
    -- already have this one for this lap
    return false, "already_crossed"
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
    return true, { lap = r.currentLap, gate = index, split = elapsed,
                   lapTime = r.lapTime[r.currentLap], lapTimeLap = r.currentLap,
                   finished = true, next = 0, penalties = #r.penalties }
  end

  return true, {
    lap = r.currentLap, gate = index, split = elapsed,
    next = r.nextGate > r.gates and 1 or r.nextGate,
    penalties = #r.penalties,
    missed = index > expected and (index - expected) or nil,
  }
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
  return {
    state    = r.state,
    track    = r.track,
    mode     = r.mode,
    laps     = r.laps,
    lap      = r.currentLap,
    gates    = r.gates,
    next     = r.nextGate,
    circuit  = r.circuit,
    clean    = r.clean,
    corrected = r.corrected,
    penalties = #r.penalties,
    why      = r.why,
    waiting  = RM.results and RM.results.waitingOn(r.track) or nil,
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
