local M = {}

-- Two jobs, both while a non-lap-time challenge attempt is running:
--
--  1. Report to the server every NETWORK_INTERVAL seconds. The server
--     decides what any of it is worth (RM.challenges.onFinish, server side,
--     in 22_challenges.lua) -- nothing scored is trusted, only reported,
--     the same split race.lua already has with the clock.
--  2. Keep a live reading, refreshed every frame, for the challenge HUD
--     (M.status(), read fresh into the pushed UI state by ui.lua exactly
--     the way race.lua's own status() already is). This is a real
--     instrument reading -- the same category as the tachometer -- not a
--     value standing in for anything the server decides; the server's own
--     copy of the run is what actually gets scored.
--
--  Speed     veh:getVelocity():length(), the same call bottombar.lua uses
--            for its own reading.
--  G-force   the vehicle's own smoothed accelerometer (accXSmooth/Y/Z),
--            read through core_vehicleBridge exactly the way BeamNG's own
--            "Gravity Force" flowgraph node does, then divided by gravity.
--  Damage    map.getMap().objects[id].damage -- beamstate.damage synced GE
--            side every tick for exactly this kind of reading (it is what
--            already feeds the in-game map and the MP position sync).
--  Long jump a downward raycast against static geometry (castRayStatic),
--            the same primitive the traffic AI uses to find the ground
--            under a car. Height above that point over a threshold counts
--            as airborne; distance and peak height are measured from when
--            it leaves the ground to when it lands. The best distance and
--            the best height reached, independently, across every jump in
--            the attempt are what the server scores (see 22_challenges.lua)
--            so the live "best" shown here tracks the same two numbers,
--            not just the single most recent jump.

local MPS_TO_MPH      = 2.2369363
local M_TO_FT         = 3.28084
local NETWORK_INTERVAL = 1.5   -- how often a sample reaches the server
-- BeamNG's own "is this vehicle on its wheels" check (gameplay/util/
-- groundContact.lua's isOnWheels) raycasts a short 1.5m straight down from
-- just above the vehicle's own bounding-box underside, and calls anything
-- 1.1m or less from there "grounded". Airborne here is judged the same
-- way, with a little hysteresis so ordinary suspension travel and bumps
-- don't flicker the reading -- not against veh:getPosition(), which is
-- some vehicle-specific reference node with no reliable relationship to
-- ground clearance at all, and not against a self-calibrated guess at
-- what "grounded" looks like. That mismatch was the actual reason nothing
-- ever landed on a real distance or height, jump after jump, however many
-- and however high: the airborne/landed edges were being judged against
-- the wrong point on the car entirely.
local GROUND_RAY_LEN  = 1.5
local AIR_ON_M        = 1.3    -- clearance above which it counts as airborne
local AIR_OFF_M       = 0.95   -- clearance below which it counts as landed
local HEIGHT_RAY_LEN  = 500     -- long range: a generous ceiling for measuring an
                                 -- actual jump's height above whatever is below it,
                                 -- however far down that turns out to be
local MAX_JUMP_HEIGHT_M = 200   -- a sanity clamp against a stray total miss (flying
                                 -- out over open water or off the map edge with
                                 -- nothing within range to hit) turning into an
                                 -- absurd score
local JUMP_FLASH_SECONDS = 5    -- how long the HUD keeps showing the last landed jump
local MAX_DISTANCE_PER_FRAME_M = 50  -- a bigger single-frame jump in position is a
                                      -- teleport or a reconnect, not driving

local netAcc = 0
local wasActive = false
local airborne = false
local air = { startPos = nil, peakHeight = 0 }
-- every jump this attempt lands as its own record -- distance and height
-- from the SAME jump, never mixed with a different one's -- so the score
-- is always one real jump's actual result, and the results screen can
-- show every attempt, not only the winner.
local jumpLog = {}
local bestJumpIdx = nil
local lastPos = nil
local bridgeRegistered = nil  -- vehicle id this was last registered against

local bridgeKeys = { "accXSmooth", "accYSmooth", "accZSmooth" }
local bridgeVals = { accXSmooth = 0, accYSmooth = 0, accZSmooth = 0 }

-- the live reading. { active = false } the rest of the time, so the HUD's
-- own check is a single field read.
local live = { active = false }

local function ftFromM(m) return m and (m * M_TO_FT) or nil end

local function resetRunState(style)
  netAcc = 0
  airborne = false
  air.startPos, air.peakHeight = nil, 0
  jumpLog, bestJumpIdx = {}, nil
  lastPos = nil
  bridgeRegistered = nil
  live = { active = true, style = style, peakG = 0 }
end

local function playerVehicle()
  local ok, veh = pcall(function() return be:getPlayerVehicle(0) end)
  if ok and veh then return veh end
  return nil
end

local function playerVehId()
  local ok, id = pcall(function() return be:getPlayerVehicleID(0) end)
  if ok and id and id >= 0 then return id end
  return nil
end

-- the current run's challenge, only when it is a style this module has
-- anything to measure for. nil the rest of the time (a plain race, or a
-- lap-time challenge, both score off the clock and need none of this).
local function activeChallenge()
  local st = extensions.raceManager_race.status()
  if not st or st.state ~= "running" or not st.challenge then return nil end
  local S = extensions.raceManager_state.get()
  for _, c in ipairs(S.challenges or {}) do
    if c.id == st.challenge then
      if c.style and c.style ~= "laptime" then return c end
      return nil
    end
  end
  return nil
end

local function speedMph(veh)
  local ok, vel = pcall(function() return veh:getVelocity() end)
  if not ok or not vel then return nil end
  return vel:length() * MPS_TO_MPH
end

local function gForce(vehId)
  local obj = getObjectByID(vehId)
  if not obj then return nil end
  if bridgeRegistered ~= vehId then
    for _, k in ipairs(bridgeKeys) do
      pcall(core_vehicleBridge.registerValueChangeNotification, obj, k)
    end
    bridgeRegistered = vehId
  end
  for _, k in ipairs(bridgeKeys) do
    local v = core_vehicleBridge.getCachedVehicleData(vehId, k)
    if v then bridgeVals[k] = v end
  end
  local gravity = core_environment.getGravity()
  gravity = math.max(0.01, math.abs(gravity))
  local gx = bridgeVals.accXSmooth / gravity
  local gy = bridgeVals.accYSmooth / gravity
  local gz = (bridgeVals.accZSmooth - gravity) / gravity
  return math.sqrt(gx * gx + gy * gy + gz * gz), gx, gy
end

local function damageOf(vehId)
  -- map.getMap() is the road/navigation graph (nodes, edges) -- a
  -- different structure entirely, and never has an .objects table. The
  -- per-vehicle damage figure lives in map.getTrackedObjects(), synced
  -- from beamstate.damage every tick by each vehicle's own mapmgr
  -- extension (vehicle/mapmgr.lua's sendTracking, called from
  -- vehicle/main.lua every tick regardless of whether the map UI is
  -- open) -- this was reading the wrong table and always returning nil,
  -- which is why damage never factored into a Damage & Distance score.
  local ok, objs = pcall(function() return map.getTrackedObjects() end)
  if not ok or type(objs) ~= "table" then return nil end
  local obj = objs[vehId]
  if not obj then return nil end
  return tonumber(obj.damage)
end

local function vehicleGroundOrigin(vehId)
  -- the vehicle's own bounding box, not veh:getPosition() -- exactly the
  -- reference gameplay/util/groundContact.lua uses for this same question
  -- ("is this vehicle on its wheels"): centered on the box, then dropped
  -- to just above its underside -- roughly the bottom of the frame/engine
  -- bay, not the tires themselves -- so the raycast starts near the actual
  -- underside, not somewhere up in the chassis.
  local ok, cx, cy, cz = pcall(function() return be:getObjectOOBBCenterXYZ(vehId) end)
  if not ok or not cz then return nil end
  local ok2, _, _, hz = pcall(function() return be:getObjectOOBBHalfExtentsXYZ(vehId) end)
  if not ok2 or not hz then return nil end
  return vec3(cx, cy, cz - hz + 0.3)
end

local function rayDownFrom(origin, maxDist)
  if not origin then return nil end
  local ok, dist = pcall(function() return castRayStatic(origin, vec3(0, 0, -1), maxDist) end)
  if not ok or not dist then return nil end
  return dist
end

local function groundClearance(vehId)
  return rayDownFrom(vehicleGroundOrigin(vehId), GROUND_RAY_LEN)
end

-- tracked every frame, independent of the once-every-NETWORK_INTERVAL send
-- below, because a jump can start and land entirely between two of those.
--
-- Height is a continuous reading of how far the vehicle's own underside is
-- above whatever ground is directly beneath it at that instant, peaked
-- over the whole jump -- not a delta from wherever it left the ground.
-- A launch-relative delta reads about right off a flat launch onto a flat
-- landing, but is badly wrong anywhere the ground below isn't at launch
-- height: drive off a tall cliff with no upward arc at all and a
-- launch-relative delta reads as almost no height gained, even while the
-- car is genuinely dozens of feet up -- which is exactly the "recorded
-- from a set height, not from the ground" problem. Distance stays a
-- launch-to-landing delta on purpose: horizontal displacement is exactly
-- what "how far did you jump" means, and only height needed the
-- ground-relative reading instead.
local function trackJump(vehId, pos, dt)
  local origin = vehicleGroundOrigin(vehId)
  local clearance = rayDownFrom(origin, GROUND_RAY_LEN)

  if not airborne then
    if clearance and clearance > AIR_ON_M then
      airborne = true
      air.startPos = pos
      air.peakHeight = 0
    end
    live.airborne = airborne
    return
  end

  -- a long-range reading of the same underside point, taken every frame
  -- while airborne, tracking its peak; capped against a stray total miss
  -- (flying out over open water or off the map edge with nothing within
  -- range to hit) turning into an absurd score
  local heightNow = rayDownFrom(origin, HEIGHT_RAY_LEN)
  if heightNow then
    if heightNow > MAX_JUMP_HEIGHT_M then heightNow = MAX_JUMP_HEIGHT_M end
    if heightNow > air.peakHeight then air.peakHeight = heightNow end
  end
  live.airborne = true
  -- shown on the HUD while still in the air, so the tracker reads live
  -- height and distance throughout the jump, not just a result once it's
  -- over -- the same two numbers that total into the score at landing
  live.heightNowFt = heightNow and ftFromM(heightNow) or nil
  if air.startPos then
    local dxNow = pos.x - air.startPos.x
    local dyNow = pos.y - air.startPos.y
    live.distanceNowFt = ftFromM(math.sqrt(dxNow * dxNow + dyNow * dyNow))
  end

  if clearance and clearance <= AIR_OFF_M then
    airborne = false
    live.airborne = false
    live.heightNowFt, live.distanceNowFt = nil, nil
    if air.startPos then
      local dx = pos.x - air.startPos.x
      local dy = pos.y - air.startPos.y
      local distM = math.sqrt(dx * dx + dy * dy)
      local heightM = math.max(0, air.peakHeight)

      live.lastJump = { distanceFt = ftFromM(distM), heightFt = ftFromM(heightM) }
      live.lastJumpFor = JUMP_FLASH_SECONDS

      -- this jump's own record -- its distance and height together, never
      -- mixed with a different jump's numbers -- and the log goes to the
      -- server in full so the results screen can list every attempt
      local scoreFt = ftFromM(distM) + ftFromM(heightM)
      jumpLog[#jumpLog + 1] = { distanceFt = ftFromM(distM), heightFt = ftFromM(heightM), scoreFt = scoreFt }
      if not bestJumpIdx or scoreFt > jumpLog[bestJumpIdx].scoreFt then bestJumpIdx = #jumpLog end
      live.bestJump = jumpLog[bestJumpIdx]
      live.jumps = jumpLog

      extensions.raceManager_net.send("race.telemetry", {
        jump = { distanceM = distM, heightM = heightM, final = true },
      })
    end
    air.startPos = nil
  end
end

local function onUpdate(dt)
  local c = activeChallenge()
  if not c then
    if wasActive then live = { active = false } end
    wasActive = false
    return
  end
  if not wasActive then resetRunState(c.style) end
  wasActive = true

  if live.lastJumpFor then
    live.lastJumpFor = live.lastJumpFor - dt
    if live.lastJumpFor <= 0 then
      live.lastJumpFor, live.lastJump = nil, nil
    end
  end

  local veh = playerVehicle()
  local vehId = playerVehId()
  if not veh or not vehId then return end

  local pos
  do
    local ok, p = pcall(function() return veh:getPosition() end)
    if ok then pos = p end
  end

  -- live readouts, refreshed every frame regardless of the network throttle
  if c.style == "speed" or c.style == "damage" or c.style == "distance" then
    local mph = speedMph(veh)
    if mph then
      live.speedMph = mph
      if c.style == "speed" then live.peakSpeedMph = math.max(live.peakSpeedMph or 0, mph) end
    end
  end

  if c.style == "gforce" then
    local ok, g, gx, gy = pcall(gForce, vehId)
    if ok and g then
      live.gForce = g
      live.gx, live.gy = gx, gy
      live.peakG = math.max(live.peakG or 0, g)
    end
  end

  if c.style == "damage" then
    local dmg = damageOf(vehId)
    if dmg then
      if not live.damageBaseline then live.damageBaseline = dmg end
      live.damage = dmg
      live.damageTaken = math.max(0, dmg - live.damageBaseline)
    end
  end

  if (c.style == "damage" or c.style == "distance") and pos then
    if lastPos then
      local dx, dy, dz = pos.x - lastPos.x, pos.y - lastPos.y, pos.z - lastPos.z
      local d = math.sqrt(dx * dx + dy * dy + dz * dz)
      if d < MAX_DISTANCE_PER_FRAME_M then
        live.distanceM = (live.distanceM or 0) + d
      end
    end
    lastPos = pos
  end

  if c.style == "longjump" then trackJump(vehId, pos, dt) end

  netAcc = netAcc + dt
  if netAcc < NETWORK_INTERVAL then return end
  netAcc = 0

  local payload = {}
  if live.speedMph and (c.style == "speed" or c.style == "damage" or c.style == "distance") then
    payload.speedMph = live.speedMph
  end
  -- the peak, not the instantaneous reading -- a hard hit is a spike
  -- lasting a fraction of a second, and this send only goes out roughly
  -- every NETWORK_INTERVAL. Sending whatever the current reading happens
  -- to be at that exact instant meant a genuine 15g spike could land
  -- between two sends and never reach the server at all, reporting
  -- whatever the ambient reading had dropped back to by the time the next
  -- one went out. live.peakG already tracks the true peak continuously,
  -- every frame, independent of when the network send fires -- this just
  -- sends that instead of throwing it away for a momentary snapshot.
  if c.style == "gforce" and live.peakG then payload.gForce = live.peakG end
  if c.style == "damage" and live.damage then payload.damage = live.damage end
  if (c.style == "damage" or c.style == "distance") and live.distanceM then
    -- the network sample is the delta since the last one went out; the
    -- server keeps its own running total, the HUD shows this module's own
    payload.distanceDeltaM = live.distanceM - (live.lastSentDistanceM or 0)
    live.lastSentDistanceM = live.distanceM
  end
  -- a jump still in progress, reported early rather than only on landing.
  -- If the attempt's time limit (or Stop attempt) ends the run while still
  -- airborne, the server force-finishes it before a landing ever happens,
  -- and a jump that only ever gets reported on landing would score as
  -- nothing at all -- exactly the one that was probably the attempt's best,
  -- since it's the one still going when time ran out. final=false tells
  -- the server this is only an estimate: it holds it separately and only
  -- commits it as a real jump record if the run ends before an actual
  -- landing (final=true) ever arrives for it -- a landing simply replaces
  -- the estimate rather than adding a second entry for the same jump.
  if c.style == "longjump" and airborne and air.startPos and pos then
    local dx = pos.x - air.startPos.x
    local dy = pos.y - air.startPos.y
    payload.jump = {
      distanceM = math.sqrt(dx * dx + dy * dy),
      heightM = math.max(0, air.peakHeight),
      final = false,
    }
  end
  if next(payload) then
    extensions.raceManager_net.send("race.telemetry", payload)
  end
end

function M.status() return live end

M.onUpdate = onUpdate

return M
