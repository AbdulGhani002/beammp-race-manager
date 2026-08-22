local M = {}

-- Checkpoints are real trigger volumes spawned at runtime from the saved
-- course. The engine does the overlap test in its own code and only wakes lua
-- on a crossing, which is the whole reason we are not polling distances every
-- frame against 29 gates and a full grid.
--
-- Nothing is written to the map. The volumes exist only while the mod has a
-- course open, so players do not need a custom map.
--
-- The creation order below matters and is copied from the game's own
-- rectMarker node: loadMode, then the type field, then registerObject, and
-- only then position, scale and rotation. Setting position before the object
-- is registered silently does nothing.

local PREFIX = "rm_cp_"
local DEFAULT_GATE = { w = 20, h = 8, d = 3 }

local spawned = {}
local course  = nil
local visible = false

local function removeOne(name)
  local ok, obj = pcall(function() return scenetree.findObject(name) end)
  if ok and obj then pcall(function() obj:delete() end) end
end

function M.clear()
  for i = 1, #spawned do removeOne(spawned[i]) end
  spawned = {}
  course = nil
  visible = false
end

local function gateOf(cp)
  local s = cp.size or DEFAULT_GATE
  return tonumber(s.w) or DEFAULT_GATE.w,
         tonumber(s.h) or DEFAULT_GATE.h,
         tonumber(s.d) or DEFAULT_GATE.d
end

local function spawnGate(cp, index)
  local name = PREFIX .. index
  removeOne(name)

  local ok, obj = pcall(function() return createObject("BeamNGTrigger") end)
  if not ok or not obj then
    log("E", "raceManager", "could not create trigger " .. name .. ": " .. tostring(obj))
    return nil
  end

  local built, err = pcall(function()
    obj.loadMode = 1
    obj:setField("triggerType", 0, "Box")
    obj:setField("triggerMode", 0, "Overlaps")
    obj:setField("triggerTestType", 0, "Race Corners")
    obj:registerObject(name)

    -- the engine draws the box itself, which is a truer preview than a marker
    -- because it is the exact volume you have to drive through
    obj.debug = visible

    obj:setPosition(vec3(cp.pos.x, cp.pos.y, cp.pos.z))

    local w, h, d = gateOf(cp)
    obj:setScale(vec3(w * 0.5, d * 0.5, h * 0.5))

    -- yaw only. a gate leaning with the camber of the road buys nothing and
    -- makes the volume harder to drive through.
    local yaw = tonumber(cp.yaw) or 0
    local q = quat(0, 0, math.sin(yaw * 0.5), math.cos(yaw * 0.5)):toTorqueQuat()
    obj:setField("rotation", 0, q.x .. " " .. q.y .. " " .. q.z .. " " .. q.w)
  end)

  if not built then
    log("E", "raceManager", "trigger " .. name .. " failed to set up: " .. tostring(err))
    removeOne(name)
    return nil
  end

  return name
end

-- build the volumes for a course. returns how many actually made it.
function M.build(track, showBoxes)
  if type(track) ~= "table" or type(track.checkpoints) ~= "table" then return 0 end

  -- rebuilding the same course on every message is wasted work and makes the
  -- log unreadable
  if course and course.id == track.id and #spawned == #track.checkpoints then
    M.setVisible(showBoxes and true or false)
    return #spawned
  end

  M.clear()
  course = track
  visible = showBoxes and true or false

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

function M.setVisible(on)
  visible = on and true or false
  for i = 1, #spawned do
    local ok, obj = pcall(function() return scenetree.findObject(spawned[i]) end)
    if ok and obj then pcall(function() obj.debug = visible end) end
  end
end

function M.preview(track)
  return M.build(track, true)
end

function M.stopPreview()
  M.setVisible(false)
end

function M.isDrawing() return visible end
function M.count() return #spawned end
function M.courseId() return course and course.id or nil end

function M.onLevelLoaded()
  -- volumes belong to the level that is going away, so they never survive it
  spawned = {}
  course = nil
  visible = false
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

  log("I", "raceManager", "checkpoint " .. index .. " crossed")

  extensions.raceManager_net.send("cp.hit", {
    track = course.id,
    i     = tonumber(index),
  })
  extensions.raceManager_capture.onGatePassed(tonumber(index))
end

-- The trigger volume itself only renders inside the world editor, so the gate
-- you see is drawn here: two posts, a top bar and a translucent face across
-- the middle, built from the same width, height and yaw the volume uses. What
-- is on screen is the thing you have to drive through, not a marker near it.
--
-- Preview only. Nothing here runs during a race.

local POST    = ColorF(0.10, 0.70, 1.00, 0.90)
local FACE    = ColorF(0.10, 0.60, 1.00, 0.13)
local LABEL   = ColorF(1, 1, 1, 1)
local LABELBG = ColorI(10, 90, 130, 200)

local DRAW_RANGE = 900
local errLogged = false

local function drawGate(cp, index)
  local w, h = gateOf(cp)
  local yaw = tonumber(cp.yaw) or 0

  -- across the gate is perpendicular to the way you drive through it
  local rx, ry = -math.sin(yaw), math.cos(yaw)
  local half = w * 0.5

  local lx, ly = cp.pos.x + rx * half, cp.pos.y + ry * half
  local rx2, ry2 = cp.pos.x - rx * half, cp.pos.y - ry * half
  local z = cp.pos.z

  local l  = vec3(lx, ly, z)
  local r  = vec3(rx2, ry2, z)
  local lt = vec3(lx, ly, z + h)
  local rt = vec3(rx2, ry2, z + h)

  debugDrawer:drawCylinder(l, lt, 0.22, POST)
  debugDrawer:drawCylinder(r, rt, 0.22, POST)
  debugDrawer:drawCylinder(lt, rt, 0.16, POST)
  debugDrawer:drawQuadSolid(l, r, rt, lt, FACE)

  debugDrawer:drawTextAdvanced(
    vec3(cp.pos.x, cp.pos.y, z + h + 1.2),
    String(tostring(index)), LABEL, true, false, LABELBG)
end

local function onUpdate()
  if not visible or not course then return end

  local eye
  local okEye, p = pcall(function() return core_camera.getPosition() end)
  if okEye then eye = p end

  local cps = course.checkpoints
  local ok, err = pcall(function()
    for i = 1, #cps do
      local cp = cps[i]
      local near = true
      if eye then
        local dx, dy = cp.pos.x - eye.x, cp.pos.y - eye.y
        near = (dx * dx + dy * dy) < (DRAW_RANGE * DRAW_RANGE)
      end
      if near then drawGate(cp, i) end
    end
  end)

  if not ok and not errLogged then
    errLogged = true
    log("W", "raceManager", "could not draw the gates: " .. tostring(err))
  end
end


M.onBeamNGTrigger = onBeamNGTrigger
M.onUpdate        = onUpdate

return M
