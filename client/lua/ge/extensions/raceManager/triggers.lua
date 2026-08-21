local M = {}

-- checkpoints are real trigger volumes spawned at runtime from the saved
-- course. the engine does the overlap test in its own code and only wakes lua
-- on a crossing, which is the whole reason we are not polling distances every
-- frame against 29 gates and a full grid.
--
-- nothing is written to the map. the volumes exist only while the mod has a
-- course open, so players do not need a custom map.

local PREFIX = "rm_cp_"

local spawned = {}        -- index -> object name
local course  = nil       -- the course the volumes belong to
local drawing = false     -- markers on screen, only while somebody is looking

local function removeOne(name)
  local ok, obj = pcall(function() return scenetree.findObject(name) end)
  if ok and obj then pcall(function() obj:delete() end) end
end

function M.clear()
  for i = 1, #spawned do removeOne(spawned[i]) end
  spawned = {}
  course = nil
  drawing = false
end

local function spawnGate(cp, index)
  local name = PREFIX .. index
  removeOne(name)

  local okCreate, obj = pcall(function() return createObject("BeamNGTrigger") end)
  if not okCreate or not obj then
    log("E", "raceManager", "could not create a trigger volume")
    return nil
  end

  local size = cp.size or { w = 20, h = 8, d = 3 }

  pcall(function()
    obj:setField("triggerType", 0, "Box")
    obj:setField("triggerMode", 0, "Overlaps")
    obj:setField("triggerTestType", 0, "Race Corners")
    obj:setField("luaFunction", 0, "")
    obj.scale = vec3(size.w * 0.5, size.d * 0.5, size.h * 0.5)
    obj:setPosition(vec3(cp.pos.x, cp.pos.y, cp.pos.z))
  end)

  -- yaw only. a gate leaning with the camber of the road buys nothing and
  -- makes the volume harder to drive through.
  local yaw = tonumber(cp.yaw) or 0
  pcall(function()
    obj:setPosRot(cp.pos.x, cp.pos.y, cp.pos.z,
                  0, 0, math.sin(yaw * 0.5), math.cos(yaw * 0.5))
  end)

  pcall(function()
    obj:registerObject(name)
    scenetree.MissionGroup:addObject(obj.obj or obj)
  end)

  return name
end

-- build the volumes for a course. returns how many actually made it.
function M.build(track)
  M.clear()
  if type(track) ~= "table" or type(track.checkpoints) ~= "table" then return 0 end

  course = track
  local made = 0
  for i = 1, #track.checkpoints do
    local name = spawnGate(track.checkpoints[i], i)
    if name then
      made = made + 1
      spawned[made] = name
    end
  end

  log("I", "raceManager", ("built %d of %d checkpoint volumes for %s")
    :format(made, #track.checkpoints, tostring(track.id)))
  return made
end

-- drive the route and watch them light up. this is how a capture gets checked.
function M.preview(track)
  local made = M.build(track)
  drawing = made > 0
  return made
end

function M.stopPreview()
  drawing = false
end

function M.isDrawing() return drawing end

function M.count() return #spawned end

function M.onLevelLoaded()
  -- volumes belong to the level that is going away, so they never survive it
  spawned = {}
  course = nil
end

local function localVehicleId()
  local ok, id = pcall(function() return be:getPlayerVehicleID(0) end)
  if ok then return id end
  return nil
end

local function onBeamNGTrigger(data)
  if type(data) ~= "table" or not course then return end
  if data.event ~= "enter" then return end

  local index = tostring(data.triggerName or ""):match("^" .. PREFIX .. "(%d+)$")
  if not index then return end

  -- only our own car. everyone else's crossings are their client's business.
  local mine = localVehicleId()
  if mine and data.subjectID and data.subjectID ~= mine then return end

  extensions.raceManager_net.send("cp.hit", {
    track = course.id,
    i     = tonumber(index),
  })
  extensions.raceManager_capture.onGatePassed(tonumber(index))
end

-- only while a course is on screen, which is never during a normal race
local function onPreRender()
  if not drawing or not course then return end
  local cps = course.checkpoints
  for i = 1, #cps do
    local cp = cps[i]
    local size = cp.size or { w = 20, h = 8, d = 3 }
    pcall(function()
      debugDrawer:drawSphere(vec3(cp.pos.x, cp.pos.y, cp.pos.z + 1),
                             math.max(1.0, size.w * 0.15),
                             ColorF(0.1, 0.8, 1.0, 0.35))
      debugDrawer:drawTextAdvanced(vec3(cp.pos.x, cp.pos.y, cp.pos.z + 3),
                                   String(tostring(i)), ColorF(1, 1, 1, 1), true, false,
                                   ColorI(0, 0, 0, 190))
    end)
  end
end

M.onBeamNGTrigger = onBeamNGTrigger
M.onPreRender     = onPreRender

return M
