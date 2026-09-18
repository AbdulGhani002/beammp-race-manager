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
  done      = 0,
  circuit   = false,
  elapsed   = 0,
  lastSplit = nil,
  penalties = 0,
  penaltyTime = 0,
  penaltyBy = nil,
  waiting   = nil,
  results   = nil,
  lastResults = nil,
  board     = {},
  why       = nil,
  problem   = nil,
  lobby     = nil,
  lobbies   = {},
}

local startedLocal = nil
local shownTenths = -1

function M.status() return st end
function M.isRunning() return st.state == "running" end
function M.isArmed()   return st.state == "armed" end
function M.isActive()  return st.state == "armed" or st.state == "running" end
function M.inPit()     return st.inPit and true or false end

-- Stock recover / reset / rewind / last-road / saved-home. During a race
-- those keys must do nothing; the bottom bar and its binds are the only way.
local STOCK_BLOCK = {
  "recover_vehicle", "recover_vehicle_alt", "recover_to_last_road",
  "reset_physics", "reset_all_physics", "reload_vehicle", "reload_all_vehicles",
  "loadHome", "saveHome", "dropPlayerAtCamera", "dropPlayerAtCameraNoReset",
  -- no arcade boost / node grab while a race or challenge is live
  "boost", "vehicleboost", "vehicle_boost", "nitro", "nitrous", "toggleNitrous",
  "toggle_nitrous", "nitrousOxide", "nitrous_oxide",
  "nodegrabber", "nodegrabberGrab", "nodegrabberAction", "nodegrabberRender",
  "nodegrabberStrength", "nodegrabberStrengthChange", "grabber", "grab_node",
}
local stockBlocked = false
local function blockStock(on)
  on = on and true or false
  if stockBlocked == on then return end
  stockBlocked = on
  pcall(function()
    local f = core_input_actionFilter
    if not (f and f.addAction) then return end
    for i = 1, #STOCK_BLOCK do
      local name = STOCK_BLOCK[i]
      local ok = pcall(f.addAction, 0, name, on)
      if not ok then pcall(f.addAction, name, on) end
    end
    local ours = { "rm_reposition", "rm_spare_tire", "rm_repair", "rm_fuel", "rm_lights", "rm_end_race" }
    for i = 1, #ours do
      pcall(f.addAction, 0, ours[i], false)
      pcall(f.addAction, ours[i], false)
    end
  end)
end
M.blockStock = blockStock

function M.onVehicleResetted()
  if not M.isActive() then return end
  if extensions.raceManager_service and extensions.raceManager_service.busy
     and extensions.raceManager_service.busy() then
    return
  end
  -- a stock reset slipped through: put the fuel back if we still have it
  pcall(function()
    if extensions.raceManager_service and extensions.raceManager_service.reapplyFuel then
      extensions.raceManager_service.reapplyFuel()
    end
  end)
end

local function push()
  extensions.raceManager_ui.push()
end

------------------------------------------------------------ asked from html

function M.arm(trackId, mode, laps, class, challenge, official, officialName)
  if type(trackId) ~= "string" or trackId == "" then return end
  st.problem = nil
  local payload = {
    id    = trackId,
    mode  = tostring(mode or "controller"),
    laps  = math.floor(tonumber(laps) or 1),
    class = type(class) == "string" and class ~= "" and class or nil,
    challenge = type(challenge) == "string" and challenge ~= "" and challenge or nil,
  }
  if official then
    payload.official = true
    if type(officialName) == "string" and officialName ~= "" then
      payload.officialName = officialName
    end
  end
  extensions.raceManager_net.send("race.arm", payload)
end

-- A challenge with no course picked: no id to send, no grid to be put on.
-- The server starts the clock the instant it hears this.
function M.armChallenge(challengeId, mode, class)
  if type(challengeId) ~= "string" or challengeId == "" then return end
  st.problem = nil
  extensions.raceManager_net.send("race.arm", {
    challenge = challengeId,
    mode  = tostring(mode or "controller"),
    class = type(class) == "string" and class ~= "" and class or nil,
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

-- the race you make and the ones you can join
function M.createLobby(trackId, mode, laps, open, class, official, officialName)
  if type(trackId) ~= "string" or trackId == "" then return end
  st.problem = nil
  local payload = {
    track = trackId,
    mode  = tostring(mode or "controller"),
    laps  = math.floor(tonumber(laps) or 1),
    open  = open and true or false,
    class = type(class) == "string" and class ~= "" and class or nil,
  }
  if official then
    payload.official = true
    if type(officialName) == "string" and officialName ~= "" then
      payload.officialName = officialName
    end
  end
  extensions.raceManager_net.send("race.create", payload)
end

function M.joinLobby(id)
  st.problem = nil
  extensions.raceManager_net.send("race.join", { id = tostring(id or "") })
end

function M.leaveLobby()
  extensions.raceManager_net.send("race.leave", {})
end

function M.startLobby()
  st.problem = nil
  extensions.raceManager_net.send("race.start", {})
end

function M.inviteLobby(pid)
  extensions.raceManager_net.send("race.invite", { who = math.floor(tonumber(pid) or -1) })
end

-- Team. Two drivers in the same car model, one result. The server owns every
-- rule about it, so these only ask.
function M.teamOffer(pid, kind)
  extensions.raceManager_net.send("team.offer",
    { who = math.floor(tonumber(pid) or -1), kind = tostring(kind or "invite") })
end

function M.teamAccept()  extensions.raceManager_net.send("team.accept", {}) end
function M.teamDecline() extensions.raceManager_net.send("team.decline", {}) end
function M.teamLeave()   extensions.raceManager_net.send("team.leave", {}) end
function M.teamGet()     extensions.raceManager_net.send("team.get", {}) end

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
  st.challenge = d.challenge
  st.mode      = d.mode or st.mode
  st.laps      = d.laps or st.laps
  st.lap       = d.lap or 0
  st.gates     = d.gates or 0
  st.next      = d.next or 1
  st.done      = d.done or 0
  st.circuit   = d.circuit and true or false
  st.penalties = d.penalties or 0
  st.penaltyTime = d.penaltyTime or 0
  st.penaltyBy = d.penaltyBy
  st.inPit     = d.inPit and true or false
  st.waiting   = d.waiting
  st.why       = d.why
  st.board     = type(d.board) == "table" and d.board or {}

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
    -- a message, not a window. it says its piece and goes.
    extensions.raceManager_state.notice(
      ("%s is on. Your clock starts when you cross the start line."):format(
        st.trackName or st.track or "The race"))
  end

  -- a free-roam challenge attempt has no start line to cross, so "running"
  -- arrives straight from idle/finished rather than by way of "armed" and
  -- onSplit's "started" flag -- this is the only signal its clock gets.
  if st.state == "running" and was ~= "running" and not startedLocal then
    startedLocal = extensions.raceManager_clock.now()
    shownTenths = -1
    extensions.raceManager_state.notice("Challenge started. Drive.")
  end

  blockStock(st.state == "armed" or st.state == "running")

  if st.state == "idle" or st.state == "abandoned" then
    startedLocal = nil
    extensions.raceManager_triggers.stopRace()
    extensions.raceManager_service.release()
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
  if d.penalties then st.penaltyBy = d.penaltyBy end

  if d.lap then st.lap = d.lap end
  if d.lapDone then startedLocal = extensions.raceManager_clock.now() - (d.split or 0) end

  -- the server tells us which gate it wants next, so the highlight can never
  -- drift away from what it is actually scoring
  if d.next then
    st.next = d.next
    extensions.raceManager_triggers.setNextGate(d.next)
  end
  if d.done then st.done = d.done end

  if d.missed and d.missed > 0 then
    extensions.raceManager_state.notice(
      d.missed == 1 and "Missed a checkpoint" or ("Missed " .. d.missed .. " checkpoints"))
  end

  -- without this the clock stepping back thirty seconds reads as a bug
  if d.refunded then
    extensions.raceManager_state.notice(
      ("Checkpoint %s counted after all, penalty given back"):format(tostring(d.gate)))
  end

  push()
end

local function onResults(d)
  st.results = type(d) == "table" and d or nil
  if type(d) == "table" then st.lastResults = d end
  st.waiting = nil
  startedLocal = nil
  extensions.raceManager_triggers.stopRace()

  -- the light menu was still sitting over the results screen, and a car held
  -- for a repair when the run ended would never be let go
  extensions.raceManager_state.closeLights()
  extensions.raceManager_service.release()
  push()
end

-- over the limit in a zone. the warning comes before the charge, so there is
-- a moment to lift off before it costs anything.
local function onZoneWarn(d)
  if type(d) ~= "table" then return end
  local zone = type(d.zone) == "table" and d.zone or {}
  local stella = extensions.raceManager_stella
  if stella and type(stella.setPairZone) == "function" and (d.event == "on" or d.event == "off" or zone.box) then
    if d.event == "off" or not zone.mph then
      stella.setPairZone(nil)
    else
      stella.setPairZone({ mph = zone.mph, pair = zone.pair, box = true })
    end
  end
  if d.event == "on" then
    extensions.raceManager_state.notice(("Speed zone on: %d mph"):format(tonumber(zone.mph) or 0))
    return
  end
  if d.event == "off" then
    extensions.raceManager_state.notice("Speed zone off")
    return
  end
  if d.charged then
    local pens = extensions.raceManager_state.get().config.penalties
    local cost = type(pens) == "table" and tonumber(pens.speeding) or 30
    extensions.raceManager_state.notice(
      ("Speeding: +%ds. The limit here is %d mph"):format(
        cost, tonumber(zone.mph) or 0))
  else
    extensions.raceManager_state.notice(
      ("Slow down: %d mph limit here"):format(tonumber(zone.mph) or 0))
  end
end

local function onLobby(d)
  st.lobby = type(d) == "table" and d or nil
  push()
end

local function onLobbies(d)
  st.lobbies = type(d) == "table" and d or {}
  push()
end

local function onWaiting(d)
  local was = st.waiting
  st.waiting = type(d) == "table" and d.left or nil
  if st.waiting and st.waiting ~= was then
    extensions.raceManager_state.notice(
      ("You are in. Waiting on %d %s still on track."):format(
        st.waiting, st.waiting == 1 and "driver" or "drivers"))
  end
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
local function suppressCheatInputs()
  if not M.isActive() then return end
  blockStock(true)
  pcall(function()
    if core_nodegrabber and core_nodegrabber.hide then core_nodegrabber.hide() end
  end)
  pcall(function()
    local veh = be and be.getPlayerVehicle and be:getPlayerVehicle(0)
    if not veh then return end
    veh:queueLuaCommand([[
      if input then
        if input.boost ~= nil then input.boost = 0 end
        if input.nitrous ~= nil then input.nitrous = 0 end
      end
      if electrics and electrics.values then
        electrics.values.boost = 0
        electrics.values.nitrous = 0
        electrics.values.nitro = 0
        electrics.values.n2o = 0
      end
    ]])
  end)
end

local function onUpdate(dt)
  suppressCheatInputs()
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
  net.on("zone.warn",    onZoneWarn)
  net.on("race.lobby",   onLobby)
  net.on("race.lobbies", onLobbies)
  net.on("race.result",  onResult)
  net.on("race.teleport", teleport)
end

M.onExtensionLoaded = onExtensionLoaded
M.onUpdate          = onUpdate
M.onTrackReady      = onTrackReady

return M
