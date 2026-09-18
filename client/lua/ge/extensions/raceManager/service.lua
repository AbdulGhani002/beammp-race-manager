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

-- takes one off the rack and rebuilds, which brings every tire back new.
-- In a pit, an empty rack refills first, from what was last remembered
-- full, before taking one -- no separate rerack press needed there first;
-- that is the whole point of driving in rather than fixing it on the course.
local function fitSpare(consume, inPit)
  local cfg = vehicleConfig()
  if not cfg or not cfg.partsTree then return false, "no_config" end
  if consume then
    local took = takeOneSpare(cfg)
    if not took and inPit then
      if fillRack(cfg) then took = takeOneSpare(cfg) end
    end
    if not took then return false, "no_spares_left" end
  end
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
    { which = "spare", flat = true, spares = rackCount(), cap = rackCount0 })
end

local function askFlat()
  local v = playerVehicle()
  if not v then notice("Get in a car first") return end
  -- caught before anything comes off, so the pit knows what to put back
  rememberRack()

  -- The server only wants a flat while a run is going and you are out on the
  -- course. Free driving and the pit both fit a spare without one. Asking the
  -- car first refused presses the server would have allowed, which is what
  -- made the button look dead on an empty server.
  local mustBeFlat = extensions.raceManager_race.isRunning()
                     and not extensions.raceManager_race.inPit()
  if not mustBeFlat then
    extensions.raceManager_net.send("service.use",
      { which = "spare", spares = rackCount(), cap = rackCount0 })
    return
  end

  pendingFlat = true
  -- wheels is not there in every vehicle's frame. reading through it when it
  -- is missing threw inside the car's own lua, the reply never came back, and
  -- the press did nothing at all with nothing on screen to say why.
  v:queueLuaCommand([[
    local flat = false
    local list = (wheels and wheels.wheels) or {}
    for _, w in pairs(list) do
      if w.isTireDeflated or w.isBroken then flat = true break end
    end
    obj:queueGameEngineLua("extensions.raceManager_service.onFlat(" .. tostring(flat) .. ")")
  ]])
end

-- electric cars have no tank to fill, and finding that out after a twenty
-- second wait is worse than being told now
local function askFuel()
  if extensions.raceManager_race.isActive() and not extensions.raceManager_race.inPit() then
    notice("Fuel is only in a pit box")
    return
  end
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

-- filled in below; named here so M.ask can reach it. As a local declared
-- lower down it was nil here and the pcall swallowed the miss, so the fuel
-- level was never kept across a repair.
local captureFuel

function M.ask(which)
  if st.which then
    notice("Already busy with " .. st.which)
    return
  end
  pcall(function()
    if which ~= "fuel" then captureFuel() end
  end)
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

-- A hold locks the gearbox, so the engine revs and the car goes nowhere.
-- That is the one thing here that could leave somebody stuck, so the car
-- that was locked is remembered by id and that car is the one let go, not
-- whichever one the player happens to be in by then.
local frozenId = nil

local function freeze(v, on)
  local ok = pcall(function() core_vehicleBridge.executeAction(v, "setFreeze", on and true or false) end)
  if on then
    local okId, id = pcall(function() return v:getID() end)
    frozenId = (ok and okId) and id or nil
  end
end

local function unfreeze(v)
  local held = nil
  if frozenId then
    local ok, o = pcall(function() return be:getObjectByID(frozenId) end)
    held = ok and o or nil
  end
  if held then freeze(held, false) end
  if v and v ~= held then freeze(v, false) end
  frozenId = nil
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

-- F7: drop the car as it is at the camera. Damage stays. A downward ray
-- from the camera is used so the car lands on the ground instead of in the
-- air or inside a wall when we can see one.
local function dropAtCamera(v)
  local ok = pcall(function()
    if commands and type(commands.dropPlayerAtCameraNoReset) == "function" then
      commands.dropPlayerAtCameraNoReset()
    elseif core_camera and core_camera.dropPlayerAtCameraNoReset then
      core_camera.dropPlayerAtCameraNoReset()
    else
      error("no f7")
    end
  end)
  if ok then return true end

  local cam, fwd
  pcall(function() cam = core_camera.getPosition() end)
  pcall(function() fwd = core_camera.getForward() end)
  if not cam then return false end
  fwd = fwd or vec3(0, 1, 0)
  local dest = vec3(cam.x, cam.y, cam.z)
  pcall(function()
    local from = vec3(cam.x, cam.y, cam.z + 2)
    local to = vec3(cam.x, cam.y, cam.z - 80)
    if castRayDefault then
      local hit = castRayDefault(from, to)
      if hit and hit.pt then dest = vec3(hit.pt.x, hit.pt.y, hit.pt.z + UPRIGHT_LIFT) end
    end
  end)
  local look = vec3(fwd.x or 0, fwd.y or 1, 0)
  if look:length() < 0.1 then look = vec3(0, 1, 0) else look = look:normalized() end
  return pcall(function()
    spawn.safeTeleport(v, dest, quatFromDir(look, vec3(0, 0, 1)), nil, nil, nil, nil, false)
  end)
end

local function repairAll(v)
  return placeHere(v, true)
end

-- whether this job is meant to cost a tire off the rack
local takesSpare = false

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

local pendingFuelRestore = nil
local savedFuel = nil
local fuelRestoreAt = 0
local snapshotTanks, applyTanks

captureFuel = function(v)
  v = v or playerVehicle()
  if not v then return end
  pcall(function()
    core_vehicleBridge.requestValue(v, function(ret)
      local snap = snapshotTanks(ret)
      if #snap > 0 then savedFuel = snap end
    end, "energyStorage")
  end)
end

function M.onFuelSnap(snap)
  if type(snap) == "table" and #snap > 0 then
    savedFuel = snap
  end
end

function M.reapplyFuel()
  applyTanks(playerVehicle(), pendingFuelRestore or savedFuel)
end

snapshotTanks = function(ret)
  local snap = {}
  for _, tank in ipairs((ret and ret[1]) or {}) do
    if type(tank) == "table" and tank.name and tank.energyType ~= "electricEnergy" then
      snap[#snap + 1] = { name = tank.name, energy = tonumber(tank.currentEnergy) or 0 }
    end
  end
  return snap
end

applyTanks = function(v, snap)
  if not v or type(snap) ~= "table" then return end
  for i = 1, #snap do
    local t = snap[i]
    pcall(function()
      core_vehicleBridge.executeAction(v, "setEnergyStorageEnergy", t.name, t.energy)
    end)
  end
end

local function keepFuelAround(v, after)
  if not v then after() return end
  local ok = pcall(function()
    core_vehicleBridge.requestValue(v, function(ret)
      local snap = snapshotTanks(ret)
      after()
      pendingFuelRestore = snap
      fuelRestoreAt = (extensions.raceManager_clock.now() or 0) + 0.25
      applyTanks(playerVehicle() or v, snap)
    end, "energyStorage")
  end)
  if not ok then after() end
end

local function doJob(which, full)
  local v = playerVehicle()
  if not v then return false, "no_vehicle" end

  -- A spare is a part swap and nothing less: one comes off the rack and the
  -- car is rebuilt with fresh tires, which is what he asked for and what the
  -- vehicle selector does. Air alone was tried first, to save the rebuild
  -- for a tire past mending, and on his screen that read as a button that
  -- played its sounds and did nothing.
  if which == "spare" then
    return fitSpare(takesSpare, full)
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
    local ok = dropAtCamera(v)
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

  if st.which ~= "fuel" then captureFuel() end
  if st.hold > 0 then
    local v = playerVehicle()
    if v then unfreeze(nil); freeze(v, true) end
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
  unfreeze(v)

  local ok, why = doJob(which, full)
  if which ~= "fuel" then
    pendingFuelRestore = pendingFuelRestore or savedFuel
    fuelRestoreAt = (extensions.raceManager_clock.now() or 0) + 0.35
  else
    pendingFuelRestore, savedFuel = nil, nil
  end

  st.which, st.endsAt, st.hold, st.left = nil, nil, 0, 0

  st.which = which
  report(ok and true or false, (not ok) and (why or "failed") or nil)
  st.which = nil
  if not ok then
    notice(WHY[tostring(why)] or ((which or "that") .. " could not be done"))
  end
  extensions.raceManager_ui.push()
end

local function onFailed(d)
  if type(d) ~= "table" then return end
  if st.which then unfreeze(playerVehicle()) end
  st.which, st.endsAt, st.hold, st.left = nil, nil, 0, 0
  notice(WHY[tostring(d.why)] or ("That did not work: " .. tostring(d.why)))
  extensions.raceManager_ui.push()
end

-- a run that ends while a car is held would leave it stuck
function M.release()
  if not st.which and not frozenId then return end
  unfreeze(playerVehicle())
  st.which, st.endsAt, st.hold, st.left = nil, nil, 0, 0
  extensions.raceManager_ui.push()
end

-- the level going away takes the cars with it; nothing is held any more
function M.onLevelUnloaded()
  frozenId = nil
  st.which, st.endsAt, st.hold, st.left = nil, nil, 0, 0
end

-- how long past the end of a hold the server gets to say the job may run
-- before the car is let go anyway
local GRACE = 5.0

local shown = -1

local function onUpdate()
  if pendingFuelRestore and (extensions.raceManager_clock.now() or 0) >= fuelRestoreAt then
    applyTanks(playerVehicle(), pendingFuelRestore)
    -- second pass a moment later in case the rebuild finished after the first
    if fuelRestoreAt > 0 and (extensions.raceManager_clock.now() or 0) < fuelRestoreAt + 1.5 then
      fuelRestoreAt = fuelRestoreAt + 0.4
    else
      pendingFuelRestore = nil
    end
  end
  if not st.endsAt then return end
  local left = st.endsAt - extensions.raceManager_clock.now()

  -- The server says when the hold is up and the job may run. If that word
  -- never comes, the car must not stay locked waiting for it.
  if left < -GRACE then
    notice((st.which or "The job") .. " was dropped by the server, so the car is let go")
    M.release()
    return
  end

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
