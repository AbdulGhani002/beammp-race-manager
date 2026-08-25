local M = {}

-- The client side of a run. It asks to be armed, gets put on the grid, draws
-- the clock, and reports crossings. It decides nothing: the state it shows is
-- the state the server last told it, and the clock on screen is counted
-- locally from a start the server gave it rather than pushed ten times a
-- second down a channel BeamMP is already using for car positions.

local st = {
  state     = "idle",
  track     = nil,
  trackName = nil,
  mode      = "controller",
  laps      = 1,
  lap       = 0,
  gates     = 0,
  next      = 1,
  circuit   = false,
  elapsed   = 0,
  lastSplit = nil,
  penalties = 0,
  penaltyTime = 0,
  waiting   = nil,
  results   = nil,
  why       = nil,
  problem   = nil,
}

local startedLocal = nil
local shownTenths = -1

function M.status() return st end
function M.isRunning() return st.state == "running" end
function M.isArmed()   return st.state == "armed" end
function M.isActive()  return st.state == "armed" or st.state == "running" end

local function push()
  extensions.raceManager_ui.push()
end

------------------------------------------------------------ asked from html

function M.arm(trackId, mode, laps)
  if type(trackId) ~= "string" or trackId == "" then return end
  st.problem = nil
  extensions.raceManager_net.send("race.arm", {
    id   = trackId,
    mode = tostring(mode or "controller"),
    laps = math.floor(tonumber(laps) or 1),
  })
end

function M.endRace()
  if not M.isActive() then return end
  extensions.raceManager_net.send("race.end", {})
end

function M.closeResults()
  st.results = nil
  st.waiting = nil
  st.state = "idle"
  extensions.raceManager_net.send("race.clear", {})
  extensions.raceManager_triggers.stopRace()
  push()
end

-- back on the grid without going through the course list again
function M.restart()
  local id, mode, laps = st.track, st.mode, st.laps
  st.results = nil
  st.waiting = nil
  if id then M.arm(id, mode, laps) end
end

------------------------------------------------------------ from the server

local function teleport(start)
  if type(start) ~= "table" or type(start.pos) ~= "table" then return false end

  local ok, veh = pcall(function() return be:getPlayerVehicle(0) end)
  if not ok or not veh then
    extensions.raceManager_state.notice("Get in a car first")
    return false
  end

  local p = vec3(start.pos.x, start.pos.y, start.pos.z)
  local yaw = tonumber(start.yaw) or 0
  local dir = vec3(math.cos(yaw), math.sin(yaw), 0)

  -- safeTeleport puts the car down on the ground facing the direction it is
  -- given and settles the suspension, which matters because a car dropped in
  -- mid air is still moving when the clock would otherwise start
  local placed = pcall(function()
    spawn.safeTeleport(veh, p, quatFromDir(dir, vec3(0, 0, 1)))
  end)

  if not placed then
    local q = quat(0, 0, math.sin(yaw * 0.5), math.cos(yaw * 0.5))
    placed = pcall(function()
      veh:setPositionRotation(p.x, p.y, p.z, q.x, q.y, q.z, q.w)
    end)
  end

  log(placed and "I" or "W", "raceManager",
    placed and "placed on the grid" or "could not place the car on the grid")
  return placed
end

local function onState(d)
  if type(d) ~= "table" then return end

  local was = st.state
  st.state     = d.state or "idle"
  st.track     = d.track
  st.mode      = d.mode or st.mode
  st.laps      = d.laps or st.laps
  st.lap       = d.lap or 0
  st.gates     = d.gates or 0
  st.next      = d.next or 1
  st.circuit   = d.circuit and true or false
  st.penalties = d.penalties or 0
  st.penaltyTime = d.penaltyTime or 0
  st.waiting   = d.waiting
  st.why       = d.why

  local S = extensions.raceManager_state.get()
  for _, t in ipairs(S.tracks or {}) do
    if t.id == st.track then st.trackName = t.name end
  end

  if st.state == "armed" and was ~= "armed" then
    st.elapsed = 0
    st.lastSplit = nil
    startedLocal = nil
    shownTenths = -1
    extensions.raceManager_net.send("track.get", { id = st.track })
  end

  if st.state == "idle" or st.state == "abandoned" then
    startedLocal = nil
    extensions.raceManager_triggers.stopRace()
  end

  if st.state == "finished" then
    startedLocal = nil
    extensions.raceManager_triggers.stopRace()
  end

  push()
end

-- the course arrives after arming, and that is when the volumes go up
local function onTrackReady(track)
  if not M.isActive() then return end
  if type(track) ~= "table" or track.id ~= st.track then return end
  extensions.raceManager_triggers.startRace(track, st.next)
end

local function onSplit(d)
  if type(d) ~= "table" then return end

  if d.started then
    startedLocal = extensions.raceManager_clock.now()
    st.state = "running"
    st.lap = d.lap or 1
    shownTenths = -1
  end

  st.lastSplit = {
    gate       = d.gate,
    lap        = d.lap,
    split      = d.split,
    lapTime    = d.lapTime,
    lapTimeLap = d.lapTimeLap,
    missed     = d.missed,
  }
  st.lastSplitFor = 5

  if d.penalties then st.penalties = d.penalties end
  if d.penaltyTime then st.penaltyTime = d.penaltyTime end

  if d.lap then st.lap = d.lap end
  if d.lapDone then startedLocal = extensions.raceManager_clock.now() - (d.split or 0) end

  -- the server tells us which gate it wants next, so the highlight can never
  -- drift away from what it is actually scoring
  if d.next then
    st.next = d.next
    extensions.raceManager_triggers.setNextGate(d.next)
  end

  if d.missed and d.missed > 0 then
    extensions.raceManager_state.notice(
      d.missed == 1 and "Missed a checkpoint" or ("Missed " .. d.missed .. " checkpoints"))
  end

  push()
end

local function onResults(d)
  st.results = type(d) == "table" and d or nil
  st.waiting = nil
  startedLocal = nil
  extensions.raceManager_triggers.stopRace()
  push()
end

local function onWaiting(d)
  st.waiting = type(d) == "table" and d.left or nil
  push()
end

local function onResult(d)
  if type(d) ~= "table" then return end
  if d.ok == false then
    st.problem = d.reason
    push()
  end
end

------------------------------------------------------------ per frame

-- one subtraction and one compare while a car is on track, and nothing at all
-- when there is not one. the push only happens when the tenth on screen
-- actually changes, so the interface still redraws ten times a second at most.
local function onUpdate(dt)
  if st.lastSplitFor then
    st.lastSplitFor = st.lastSplitFor - dt
    if st.lastSplitFor <= 0 then
      st.lastSplitFor = nil
      st.lastSplit = nil
      push()
    end
  end

  if not startedLocal then return end

  -- what the run is worth right now, which is the time on the road plus
  -- whatever has been added to it. A penalty that leaves the clock alone reads
  -- as free until the results come up, and by then there is nothing to be done
  -- about it.
  st.elapsed = (extensions.raceManager_clock.now() - startedLocal) + (st.penaltyTime or 0)
  local tenths = math.floor(st.elapsed * 10)
  if tenths ~= shownTenths then
    shownTenths = tenths
    push()
  end
end

function M.onLevelUnloaded()
  if not M.isActive() then return end
  extensions.raceManager_net.send("race.end", {})
  startedLocal = nil
end

local function onExtensionLoaded()
  local net = extensions.raceManager_net
  net.on("race.state",   onState)
  net.on("race.split",   onSplit)
  net.on("race.results", onResults)
  net.on("race.waiting", onWaiting)
  net.on("race.result",  onResult)
  net.on("race.teleport", teleport)
end

M.onExtensionLoaded = onExtensionLoaded
M.onUpdate          = onUpdate
M.onTrackReady      = onTrackReady

return M
