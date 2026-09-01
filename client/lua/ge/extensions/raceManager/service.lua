local M = {}

-- The game half of the bottom bar. The server says when a job may start and
-- when the hold is up; everything here is the job itself.
--
-- Every call below is one the game already makes somewhere in its own code.

local st = {
  which  = nil,   -- what is being done
  hold   = 0,     -- how long the whole wait is
  endsAt = nil,   -- local clock, for the countdown
  left   = 0,
}

local FUEL_STEP = 0.25

local function playerVehicle()
  local ok, v = pcall(function() return be:getPlayerVehicle(0) end)
  if ok and v then return v end
  return nil
end

local function notice(text)
  extensions.raceManager_state.notice(text)
end

local function report(ok, why)
  extensions.raceManager_net.send("service.done", { which = st.which, ok = ok and true or false, why = why })
end

function M.status() return st end
function M.busy() return st.which ~= nil end

------------------------------------------------------------ asking

-- the car is the only thing that knows whether a tire is down, so it is asked
-- before the request goes out rather than after the wait
local pendingFlat = nil

function M.onFlat(flat)
  local ask = pendingFlat
  pendingFlat = nil
  if not ask then return end
  if not flat then
    notice("Spare tire: nothing is flat")
    return
  end
  extensions.raceManager_net.send("service.use", { which = "spare", flat = true })
end

local function askFlat()
  local v = playerVehicle()
  if not v then notice("Get in a car first") return end
  pendingFlat = true
  v:queueLuaCommand([[
    local flat = false
    for _, w in pairs(wheels.wheels or {}) do
      if w.isTireDeflated then flat = true break end
    end
    obj:queueGameEngineLua("extensions.raceManager_service.onFlat(" .. tostring(flat) .. ")")
  ]])
end

-- electric cars have no tank to fill, and finding that out after a twenty
-- second wait is worse than being told now
local function askFuel()
  local v = playerVehicle()
  if not v then notice("Get in a car first") return end
  local ok = pcall(function()
    core_vehicleBridge.requestValue(v, function(ret)
      local tanks = ret and ret[1]
      local room = false
      for _, tank in ipairs(tanks or {}) do
        if tank.energyType ~= "electricEnergy" and (tank.currentEnergy or 0) < (tank.maxEnergy or 0) then
          room = true
        end
      end
      if not room then
        notice("Fuel: nothing on this car takes any")
        return
      end
      extensions.raceManager_net.send("service.use", { which = "fuel" })
    end, "energyStorage")
  end)
  if not ok then notice("Fuel: could not read the tank") end
end

function M.ask(which)
  if st.which then
    notice("Already busy with " .. st.which)
    return
  end
  if which == "spare" then askFlat() return end
  if which == "fuel" then askFuel() return end
  extensions.raceManager_net.send("service.use", { which = which })
end

------------------------------------------------------------ doing it

local function freeze(v, on)
  pcall(function() core_vehicleBridge.executeAction(v, "setFreeze", on and true or false) end)
end

-- Repair where the car stands. be:resetVehicle put it back at the last place it
-- was stopped, which is the recovery behaviour and not what a repair should do.
-- This pair is the game's own recipe, lifted from recovery.loadHome: the engine
-- reset fixes the physics and kills the velocity, and the flex mesh call puts
-- the bent panels back.
local function repairAll(v)
  return pcall(function()
    v:queueLuaCommand("obj:requestReset(RESET_PHYSICS)")
    v:resetBrokenFlexMesh()
  end)
end

-- a quarter of a tank on the road, the whole tank in the pit
local function addFuel(v, full)
  local share = full and 1.0 or FUEL_STEP
  return pcall(function()
    core_vehicleBridge.requestValue(v, function(ret)
      for _, tank in ipairs((ret and ret[1]) or {}) do
        if tank.energyType ~= "electricEnergy" then
          local max = tank.maxEnergy or 0
          local now = tank.currentEnergy or 0
          local add = math.min(max - now, max * share)
          if add > 0 then
            core_vehicleBridge.executeAction(v, "setEnergyStorageEnergy", tank.name, now + add)
          end
        end
      end
    end, "energyStorage")
  end)
end

-- On its wheels where it stands. No reset, so the damage stays on it, and no
-- course lookup either: there is nothing to drive back to, which is what he
-- asked for. The heading is flattened so it lands level rather than nose down,
-- and it is lifted a little so it does not come back inside the dirt.
local UPRIGHT_LIFT = 0.6

local function atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end

local function putBack(v)
  local okPos, pos = pcall(function() return v:getPosition() end)
  if not okPos or not pos then return false end

  local yaw = 0
  local okDir, dir = pcall(function() return v:getDirectionVector() end)
  if okDir and dir then yaw = atan2(dir.y, dir.x) end

  local fwd = vec3(math.cos(yaw), math.sin(yaw), 0)
  local rot = quatFromDir(fwd, vec3(0, 0, 1))

  return pcall(function()
    v:setPositionRotation(pos.x, pos.y, pos.z + UPRIGHT_LIFT, rot.x, rot.y, rot.z, rot.w)
  end)
end

-- The tire fix. Air back into every flat and the flat flag cleared, which is
-- what the game's own onboard compressors do, and nothing else on the car is
-- touched. A tire that is torn up or on a broken wheel will not come back
-- from air alone, so that case falls back to the full repair and says so.
local SPARE_FIX = [[
  local allFixed = true
  for _, wd in pairs(wheels.wheels or {}) do
    if wd.isTireDeflated then
      if wd.isBroken or not wd.pressureGroupId or not wd.startingPressure then
        allFixed = false
      else
        obj:setGroupPressure(wd.pressureGroupId, wd.startingPressure)
        wd.isTireDeflated = false
      end
    end
  end
  obj:queueGameEngineLua("extensions.raceManager_service.onSpareFixed(" .. tostring(allFixed) .. ")")
]]

-- the vehicle answers on its own frame, so the spare reports back late
function M.onSpareFixed(allFixed)
  if allFixed then
    st.which = "spare"
    report(true, nil)
    st.which = nil
    notice("Spare tire on")
    return
  end

  local v = playerVehicle()
  local ok = v and repairAll(v) or false
  st.which = "spare"
  report(ok and true or false, (not ok) and "repair_failed" or nil)
  st.which = nil
  notice(ok and "That tire was too far gone, so the whole car was repaired"
            or "The tire could not be fixed")
end

local function doJob(which, full)
  local v = playerVehicle()
  if not v then return false, "no_vehicle" end

  if which == "spare" then
    local ok = pcall(function() v:queueLuaCommand(SPARE_FIX) end)
    if not ok then return false, "repair_failed" end
    return "async"
  end

  if which == "repair" then
    local ok = repairAll(v)
    return ok, (not ok) and "repair_failed" or nil
  end
  if which == "fuel" then
    local ok = addFuel(v, full)
    return ok, (not ok) and "no_tank" or nil
  end
  if which == "reposition" then
    local ok = putBack(v)
    return ok, (not ok) and "no_vehicle" or nil
  end
  return false, "no_such_action"
end

------------------------------------------------------------ from the server

local function onHold(d)
  if type(d) ~= "table" then return end

  st.which = tostring(d.which or "")
  st.hold  = tonumber(d.hold) or 0
  st.left  = st.hold
  st.endsAt = st.hold > 0 and (extensions.raceManager_clock.now() + st.hold) or nil

  if st.hold > 0 then
    local v = playerVehicle()
    if v then freeze(v, true) end
    local cost = tonumber(d.penalty)
    notice(cost and ("%s: %ds, and %ds on the clock"):format(st.which, st.hold, cost)
                 or ("%s: %ds"):format(st.which, st.hold))
  end

  extensions.raceManager_ui.push()
end

local function onRun(d)
  local which = type(d) == "table" and tostring(d.which or "") or st.which
  local full = type(d) == "table" and d.full == true
  local v = playerVehicle()
  if v then freeze(v, false) end

  local ok, why = doJob(which, full)

  st.which, st.endsAt, st.hold, st.left = nil, nil, 0, 0

  -- the spare answers from the vehicle's own frame, through onSpareFixed
  if ok ~= "async" then
    st.which = which
    report(ok, why)
    st.which = nil
    if not ok then notice((which or "that") .. " could not be done") end
  end
  extensions.raceManager_ui.push()
end

local WHY = {
  no_such_action  = "That button does nothing yet",
  already_working = "One job at a time",
  no_flat_tire    = "Spare tire is only for a flat",
  no_session      = "The server has not finished recognising you",
  no_vehicle      = "Get in a car first",
  no_tank         = "Nothing on this car takes fuel",
  repair_failed   = "The car could not be reset",
}

local function onFailed(d)
  if type(d) ~= "table" then return end
  local v = playerVehicle()
  if v and st.which then freeze(v, false) end
  st.which, st.endsAt, st.hold, st.left = nil, nil, 0, 0
  notice(WHY[tostring(d.why)] or ("That did not work: " .. tostring(d.why)))
  extensions.raceManager_ui.push()
end

-- a run that ends while a car is held would leave it stuck
function M.release()
  if not st.which then return end
  local v = playerVehicle()
  if v then freeze(v, false) end
  st.which, st.endsAt, st.hold, st.left = nil, nil, 0, 0
  extensions.raceManager_ui.push()
end

local shown = -1

local function onUpdate()
  if not st.endsAt then return end
  local left = st.endsAt - extensions.raceManager_clock.now()
  if left < 0 then left = 0 end
  st.left = left

  -- only when the second on screen changes
  local whole = math.floor(left)
  if whole ~= shown then
    shown = whole
    extensions.raceManager_ui.push()
  end
end

local function onExtensionLoaded()
  local net = extensions.raceManager_net
  net.on("service.hold",   onHold)
  net.on("service.run",    onRun)
  net.on("service.failed", onFailed)
end

M.onExtensionLoaded = onExtensionLoaded
M.onUpdate          = onUpdate

return M
