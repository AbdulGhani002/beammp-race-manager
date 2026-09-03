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
  extensions.raceManager_net.send("service.use",
    { which = "spare", flat = true, spares = rackCount() })
end

local function askFlat()
  local v = playerVehicle()
  if not v then notice("Get in a car first") return end
  -- caught before anything comes off, so the pit knows what to put back
  rememberRack()
  pendingFlat = true
  v:queueLuaCommand([[
    local flat = false
    for _, w in pairs(wheels.wheels or {}) do
      if w.isTireDeflated or w.isBroken then flat = true break end
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
  if which == "rerack" then
    extensions.raceManager_net.send("service.use",
      { which = "rerack", spares = rackCount0 >= 0 and rackCount0 or rackCount() })
    return
  end
  extensions.raceManager_net.send("service.use", { which = which })
end

------------------------------------------------------------ doing it

local function freeze(v, on)
  pcall(function() core_vehicleBridge.executeAction(v, "setFreeze", on and true or false) end)
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

------------------------------------------------------------ the spare rack

-- Spare tires are real parts bolted to the car, so the rack is read off the
-- vehicle rather than guessed at. Slot names differ per vehicle
-- (racetruck_sparetire_L, utv_sparetire_14x7, sunburst2_sparetire_R_offroad),
-- so the slot type is matched on shape, and the mounts, holders and covers
-- that live beside them are left alone.
local SPARE_WORDS = { "sparetire", "sparewheel", "spare_tire", "spare_wheel" }
local NOT_A_TIRE  = { "mount", "holder", "cover", "case", "rack", "bracket", "carrier" }

local function isSpareSlot(id)
  id = tostring(id or ""):lower()
  local looks = false
  for i = 1, #SPARE_WORDS do
    if id:find(SPARE_WORDS[i], 1, true) then looks = true break end
  end
  if not looks then return false end
  for i = 1, #NOT_A_TIRE do
    if id:find(NOT_A_TIRE[i], 1, true) then return false end
  end
  return true
end

local function vehicleConfig()
  local ok, data = pcall(function()
    return extensions.core_vehicle_manager.getPlayerVehicleData()
  end)
  if not ok or type(data) ~= "table" then return nil end
  return data.config, tostring(data.model or "")
end

-- A tire slot carries its wheel underneath it, so once a slot matches we stop
-- going down: taking the tire takes the wheel with it.
local function spareSlots(cfg)
  local found = {}
  local function walk(node, depth)
    if type(node) ~= "table" then return end
    for _, child in pairs(node.children or {}) do
      if type(child) == "table" then
        if isSpareSlot(child.id) then
          found[#found + 1] = { node = child, depth = depth,
                                key = tostring(child.path or child.id or "") }
        else
          walk(child, depth + 1)
        end
      end
    end
  end
  walk(cfg and cfg.partsTree, 0)
  table.sort(found, function(a, b)
    if a.depth ~= b.depth then return a.depth < b.depth end
    return a.key < b.key
  end)
  return found
end

local function rackCount()
  local cfg = vehicleConfig()
  if not cfg then return 0 end
  local n = 0
  local slots = spareSlots(cfg)
  for i = 1, #slots do
    if tostring(slots[i].node.chosenPartName or "") ~= "" then n = n + 1 end
  end
  return n
end

-- What was on the rack when it was last seen fullest, so the pit can put it
-- back. Kept per model, because swapping car throws the old rack away.
local rackMemory, rackCount0, rackModel = nil, -1, nil

local function rememberRack()
  local cfg, model = vehicleConfig()
  if not cfg then return end
  if model ~= rackModel then rackMemory, rackCount0, rackModel = nil, -1, model end
  local mem, n = {}, 0
  local slots = spareSlots(cfg)
  for i = 1, #slots do
    local name = tostring(slots[i].node.chosenPartName or "")
    if name ~= "" then mem[slots[i].key] = name; n = n + 1 end
  end
  if n >= rackCount0 then rackMemory, rackCount0 = mem, n end
end

local function takeOneSpare(cfg)
  local slots = spareSlots(cfg)
  for i = 1, #slots do
    if tostring(slots[i].node.chosenPartName or "") ~= "" then
      slots[i].node.chosenPartName = ""
      return true
    end
  end
  return false
end

local function fillRack(cfg)
  if not rackMemory then return false end
  local filled = false
  local slots = spareSlots(cfg)
  for i = 1, #slots do
    local want = rackMemory[slots[i].key]
    if want and tostring(slots[i].node.chosenPartName or "") == "" then
      slots[i].node.chosenPartName = want
      filled = true
    end
  end
  return filled
end

-- Rebuilding the car from its parts is the only thing that puts a destroyed
-- tire back, and it is what the vehicle selector does. It leaves the car
-- exactly where it stands: the game's own editor has a line calling respawn
-- "bad, not resetting the pos/rot", which is the behaviour we want.
local function applyTree(cfg)
  return pcall(function()
    extensions.core_vehicle_partmgmt.setPartsTreeConfig(cfg.partsTree, true)
  end)
end

-- takes one off the rack and rebuilds, which brings every tire back new
local function fitSpare(consume)
  local cfg = vehicleConfig()
  if not cfg or not cfg.partsTree then return false, "no_config" end
  if consume and not takeOneSpare(cfg) then return false, "no_spares_left" end
  local ok = applyTree(cfg)
  return ok, (not ok) and "swap_failed" or nil
end

local function reRack()
  local cfg = vehicleConfig()
  if not cfg or not cfg.partsTree then return false, "no_config" end
  if not fillRack(cfg) then return false, "no_rack" end
  local ok = applyTree(cfg)
  return ok, (not ok) and "swap_failed" or nil
end

local UPRIGHT_LIFT = 0.6

local function atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end

-- Both buttons put the car down where it already stands, through the game's
-- own teleport so it lands somewhere sane. The mend flag is the whole
-- difference: on, the car is rebuilt on the way down; off, the damage comes
-- with it. The engine reset tried before snapped the car back to where it
-- first spawned, because that is what a bare reset means to the engine, and
-- everywhere the game uses one it teleports straight after.
local function placeHere(v, mend)
  local okPos, pos = pcall(function() return v:getPosition() end)
  if not okPos or not pos then return false end

  local yaw = 0
  local okDir, dir = pcall(function() return v:getDirectionVector() end)
  if okDir and dir then yaw = atan2(dir.y, dir.x) end
  local fwd = vec3(math.cos(yaw), math.sin(yaw), 0)

  return pcall(function()
    spawn.safeTeleport(v, vec3(pos.x, pos.y, pos.z + UPRIGHT_LIFT),
      quatFromDir(fwd, vec3(0, 0, 1)), nil, nil, nil, nil, mend and true or false)
  end)
end

local function putBack(v)
  return placeHere(v, false)
end

local function repairAll(v)
  return placeHere(v, true)
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

-- whether this job is meant to cost a tire off the rack
local takesSpare = false

-- The vehicle answers on its own frame, so the spare reports back late.
--
-- Air first. A puncture with the wheel still under it goes back up where it
-- stands and nothing else on the car is touched, which is most racing flats.
-- Only a tire that is past saving takes the other road, because that one has
-- to rebuild the car and would otherwise hand out a free repair every time.
function M.onSpareFixed(allFixed)
  if allFixed then
    st.which = "spare"
    report(true, nil)
    st.which = nil
    notice("Air back in. One off the rack.")
    return
  end

  local ok, why = fitSpare(takesSpare)
  st.which = "spare"
  report(ok and true or false, (not ok) and (why or "swap_failed") or nil)
  st.which = nil
  notice(ok and "That one was past saving, so a spare went on"
            or "No spare would go on")
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
  if which == "rerack" then
    return reRack()
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
  takesSpare = type(d) == "table" and d.takes == true
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
  no_spares_left  = "The rack is empty. Pit and re-rack.",
  pit_only        = "That one is a pit job",
  no_rack         = "This car carries no spares",
  no_config       = "The car's parts could not be read",
  swap_failed     = "The spare would not go on",
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
