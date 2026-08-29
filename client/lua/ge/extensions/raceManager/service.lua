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

local function repairAll(v)
  return pcall(function() v:queueLuaCommand("beamstate.reset()") end)
end

local function addFuel(v)
  return pcall(function()
    core_vehicleBridge.requestValue(v, function(ret)
      for _, tank in ipairs((ret and ret[1]) or {}) do
        if tank.energyType ~= "electricEnergy" then
          local max = tank.maxEnergy or 0
          local now = tank.currentEnergy or 0
          local add = math.min(max - now, max * FUEL_STEP)
          if add > 0 then
            core_vehicleBridge.executeAction(v, "setEnergyStorageEnergy", tank.name, now + add)
          end
        end
      end
    end, "energyStorage")
  end)
end

-- back on the course at the last gate that counted, facing the way it faces,
-- which is the same call that puts you on the grid
local function putBack(v)
  local S = extensions.raceManager_state.get()
  local track = S and S.track
  local race = extensions.raceManager_race.status()
  if type(track) ~= "table" or type(track.checkpoints) ~= "table" then return false end

  local n = #track.checkpoints
  if n == 0 then return false end

  local i = (tonumber(race.next) or 1) - 1
  if i < 1 then i = n end
  local cp = track.checkpoints[i]
  if not cp or not cp.pos then return false end

  local yaw = tonumber(cp.yaw) or 0
  local dir = vec3(math.cos(yaw), math.sin(yaw), 0)
  return pcall(function()
    spawn.safeTeleport(v, vec3(cp.pos.x, cp.pos.y, cp.pos.z), quatFromDir(dir, vec3(0, 0, 1)))
  end)
end

local function doJob(which)
  local v = playerVehicle()
  if not v then return false, "no_vehicle" end

  if which == "repair" or which == "spare" then
    local ok = repairAll(v)
    return ok, (not ok) and "repair_failed" or nil
  end
  if which == "fuel" then
    local ok = addFuel(v)
    return ok, (not ok) and "no_tank" or nil
  end
  if which == "reposition" then
    local ok = putBack(v)
    return ok, (not ok) and "nowhere_to_put_it" or nil
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
  local v = playerVehicle()
  if v then freeze(v, false) end

  local ok, why = doJob(which)

  st.which, st.endsAt, st.hold, st.left = nil, nil, 0, 0
  report(ok, why)
  if not ok then notice((which or "that") .. " could not be done") end
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
  nowhere_to_put_it = "No checkpoint to go back to",
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
