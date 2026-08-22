local M = {}

-- The bottom bar, reachable from a key as well as the button. What each one
-- does lands in phase 3 with the holds and the penalties. The binding, the
-- stopped check and the wiring are here now so the keys are already in muscle
-- memory by then, and so nobody has to rebind anything later.

local MPS_TO_MPH = 2.2369363
local STOPPED_MPH = 1.0

local PHASE3 = "This arrives in phase 3, with the hold and the penalty"

local LABEL = {
  reposition = "Reposition",
  spare      = "Spare tire",
  repair     = "Repair",
  fuel       = "Fuel +25%",
  lights     = "Lights",
}

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

  extensions.raceManager_state.notice(label .. ": " .. PHASE3)
end

function M.reposition() press("reposition") end
function M.spareTire()  press("spare") end
function M.repair()     press("repair") end
function M.fuel()       press("fuel") end
function M.lights()     press("lights") end

return M
