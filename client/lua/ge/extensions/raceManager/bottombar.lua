local M = {}

-- The bottom bar, reachable from a key as well as the button. Each one asks
-- the server, which decides whether it is allowed, holds the car for as long
-- as the job takes and charges the penalty. The lights are the exception: they
-- are instant, free, and handled here rather than round tripped.

local MPS_TO_MPH = 2.2369363
local STOPPED_MPH = 1.0

local LABEL = {
  reposition = "Reposition",
  spare      = "Spare tire",
  repair     = "Repair",
  fuel       = "Fuel +25%",
  lights     = "Lights",
}

-- which penalty each button carries. the seconds come from the server so the
-- host can change them without anybody reinstalling the mod.
local COSTS = {
  reposition = "recovery",
  spare      = "flatTire",
  repair     = "repair",
}

-- free driving costs nothing. a penalty only exists inside a run, which is
-- the one question the bar has to ask rather than a special case per button.
function M.penaltyFor(which)
  if not extensions.raceManager_race.isRunning() then return nil end
  local key = COSTS[which]
  if not key then return nil end
  local set = extensions.raceManager_state.get().config.penalties
  local seconds = type(set) == "table" and tonumber(set[key]) or nil
  if not seconds or seconds <= 0 then return nil end
  return seconds
end

local function speedMph()
  local ok, veh = pcall(function() return be:getPlayerVehicle(0) end)
  if not ok or not veh then return nil end

  local okVel, vel = pcall(function() return veh:getVelocity() end)
  if not okVel or not vel then return nil end

  return math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z) * MPS_TO_MPH
end

function M.stopped()
  local mph = speedMph()
  if not mph then return false end
  return mph < STOPPED_MPH
end

-- every one of these needs the car stopped, which is the rule for the whole
-- bar and the one thing worth enforcing before the actions exist
local function press(which)
  local label = LABEL[which] or which

  if not speedMph() then
    extensions.raceManager_state.notice("Get in a car first")
    return
  end

  if which ~= "lights" and not M.stopped() then
    extensions.raceManager_state.notice(label .. ": stop the car first")
    return
  end

  if which == "lights" then
    extensions.raceManager_ui.toggleLights()
    return
  end

  if extensions.raceManager_service.busy() then
    extensions.raceManager_state.notice("Wait for the job you started")
    return
  end

  extensions.raceManager_service.ask(which)
end

function M.reposition() press("reposition") end
function M.spareTire()  press("spare") end
function M.repair()     press("repair") end
function M.fuel()       press("fuel") end
function M.lights()     press("lights") end
function M.rerack()     press("rerack") end

-- The rows in the light menu. All of these are the game's own electrics
-- calls: a vehicle without the part just does nothing, same as the game's
-- own key bindings.
local LIGHT_DO = {
  headlights = "electrics.toggle_lights()",
  fog        = "electrics.toggle_fog_lights()",
  hazards    = "electrics.toggle_warn_signal()",
  lightbar   = "if electrics.values.lightbar == 1 then electrics.set_lightbar_signal(0) else electrics.set_lightbar_signal(1) end",
  siren      = "if electrics.values.lightbar == 2 then electrics.set_lightbar_signal(0) else electrics.set_lightbar_signal(2) end",
}

-- horn and flash are held, not toggled, so they let go on their own
local hornFor, flashFor = nil, nil

local function vehicle()
  local ok, v = pcall(function() return be:getPlayerVehicle(0) end)
  if ok and v then return v end
  return nil
end

function M.light(which)
  local v = vehicle()
  if not v then
    extensions.raceManager_state.notice("Get in a car first")
    return
  end

  if which == "horn" then
    v:queueLuaCommand("electrics.horn(true)")
    hornFor = 0.6
    return
  end
  if which == "flash" then
    v:queueLuaCommand("electrics.light_flash_highbeams(true)")
    flashFor = 0.6
    return
  end

  local cmd = LIGHT_DO[which]
  if cmd then v:queueLuaCommand(cmd) end
end

local function onUpdate(dt)
  if not hornFor and not flashFor then return end
  local v = vehicle()
  if not v then hornFor, flashFor = nil, nil return end

  if hornFor then
    hornFor = hornFor - dt
    if hornFor <= 0 then
      hornFor = nil
      v:queueLuaCommand("electrics.horn(false)")
    end
  end
  if flashFor then
    flashFor = flashFor - dt
    if flashFor <= 0 then
      flashFor = nil
      v:queueLuaCommand("electrics.light_flash_highbeams(false)")
    end
  end
end

M.onUpdate = onUpdate

return M
