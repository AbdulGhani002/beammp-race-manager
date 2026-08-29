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

-- a race has the same volumes up but a different job for them: the debug box
-- stays off and the gate you are being scored on is drawn differently to the
-- other twenty nine
local racing   = false
local nextGate = 1

-- which saved course is on screen. kept across a level change so a course you
-- asked to see is still there when you come back, rather than quietly
-- vanishing and leaving you to wonder whether it ever worked.
local shownId = nil

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

-- The one place a gate's shape is worked out. The volume and the posts you see
-- read it from here, because they used to disagree about both axes.
--
-- The base is sunk a little because a gate is marked from the car, and a car's
-- position sits above the dirt, so a gate drawn from that point floats.
local BASE_SINK = 1.5

-- A gate you meet off square is a narrower hole than its width says. Cross a
-- twenty metre gate at forty nine degrees off its normal and the gap across
-- your path is only twenty times cos, about thirteen metres. That is why the
-- gates down a straight all scored and the one on the corner only counted from
-- the middle. Widening by one over cos puts the gap back to what it should be.
local TURN_STRETCH_MAX = 2.0

function M.angleGap(a, b)
  local d = (a - b) % (2 * math.pi)
  if d > math.pi then d = 2 * math.pi - d end
  return d
end
local angleGap = M.angleGap

function M.turnStretch(turn)
  local c = math.cos(turn)
  local floor = 1 / TURN_STRETCH_MAX
  if not (c == c) or c < floor then c = floor end   -- nan guard, then the cap
  return 1 / c
end

-- worked out once when a course goes up, not per frame per gate
local function fitTurns(cps, circuit)
  local n = #cps
  for i = 1, n do
    local cp = cps[i]
    if type(cp) == "table" then
      local prev
      if i > 1 then prev = cps[i - 1]
      elseif circuit and n > 1 then prev = cps[n] end

      if prev then
        cp.rmStretch = M.turnStretch(angleGap(tonumber(cp.yaw) or 0, tonumber(prev.yaw) or 0))
      else
        cp.rmStretch = 1
      end
    end
  end
end

local function gateBox(cp)
  local w, h, d = gateOf(cp)
  return w * (tonumber(cp.rmStretch) or 1), d, cp.pos.z - BASE_SINK, cp.pos.z + h
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

    -- Overlaps, not Contains. Contains is what the 150 bus stops in the game
    -- use and it wants the whole vehicle inside the volume, which a car five
    -- metres long can never be inside a gate three metres deep. It would never
    -- fire once.
    obj:setField("triggerMode", 0, "Overlaps")

    -- "Bounding box" is what all 152 triggers shipped with the game use. What
    -- was here before was "Race Corners", which appears nowhere in the game's
    -- lua and nowhere in any level: I made it up. An unknown value leaves the
    -- test doing whatever the engine falls back to, which is why driving
    -- through a gate so often did nothing.
    obj:setField("triggerTestType", 0, "Bounding box")

    -- and this is the field that says to call us at all. 167 of the 170
    -- triggers in the game set it and we set none of them.
    obj:setField("luaFunction", 0, "onBeamNGTrigger")

    obj:registerObject(name)

    -- the engine draws the box itself, which is a truer preview than a marker
    -- because it is the exact volume you have to drive through
    obj.debug = visible

    local across, along, bottom, top = gateBox(cp)

    -- the box is centred on its position, so it goes at the middle of the span
    -- and not at its foot. sitting it on cp.pos.z buried half of it and left
    -- the ceiling at four metres under an eight metre gate.
    obj:setPosition(vec3(cp.pos.x, cp.pos.y, (bottom + top) * 0.5))

    -- yaw sends local x along the way you drive, so the width goes in y and the
    -- depth in x. these were swapped, which built a three metre slot twenty
    -- metres long down the middle of the road instead of a gate across it.
    obj:setScale(vec3(along, across, top - bottom))

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
  fitTurns(track.checkpoints, track.circuit)

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
  shownId = type(track) == "table" and track.id or nil
  return M.build(track, true)
end

function M.stopPreview()
  shownId = nil
  M.setVisible(false)
end

-- the volumes a race is scored on. the same ones the preview uses, without
-- the engine debug box, because during a run the gate is drawn by us and a
-- second wireframe on top of it is just noise.
function M.startRace(track, gate)
  racing = true
  nextGate = tonumber(gate) or 1
  local made = M.build(track, false)
  log("I", "raceManager", ("race volumes up: %d gates on %s"):format(made, tostring(track.id)))
  return made
end

function M.stopRace()
  if not racing then return end
  racing = false
  nextGate = 1

  -- a course somebody asked to look at outlives the run they just did
  if shownId and course and shownId == course.id then
    M.setVisible(true)
  else
    M.clear()
  end
end

function M.setNextGate(i)
  nextGate = tonumber(i) or nextGate
end

function M.isRacing() return racing end

function M.shownId() return shownId end

function M.isDrawing() return visible end
function M.count() return #spawned end
function M.courseId() return course and course.id or nil end

function M.onLevelLoaded()
  -- volumes belong to the level that is going away, so they never survive it
  spawned = {}
  course = nil
  visible = false
  racing = false

  -- but the intent to see a course does. ask for it again.
  if shownId then
    extensions.raceManager_net.send("track.get", { id = shownId })
  end
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

  -- stamped here, at the frame the trigger fired, because anything later
  -- carries half a round trip and the server cannot take that back out
  extensions.raceManager_net.send("cp.hit", {
    track = course.id,
    i     = tonumber(index),
    t     = extensions.raceManager_clock.now(),
  })
  extensions.raceManager_capture.onGatePassed(tonumber(index))
end

-- The trigger volume itself only renders inside the world editor, so the gate
-- you see is drawn here: two posts, a top bar and a translucent face across
-- the middle, built from the same width, height and yaw the volume uses. What
-- is on screen is the thing you have to drive through, not a marker near it.
--
-- Preview only. Nothing here runs during a race.

-- A trigger volume only renders inside the world editor, so the gate you see
-- is drawn here: two posts, a top bar and a translucent face, built from the
-- same width, height and yaw the volume uses. What is on screen is the thing
-- you drive through, not a marker near it.
--
-- Two sets get drawn. A saved course is blue. A capture in progress is amber,
-- because you need to see the gates you have already dropped while you are
-- still laying the rest out, and it should be obvious which of the two you are
-- looking at.

-- Badge colours, but read against tan dirt first. Red posts on this map would
-- be nearly invisible, so the posts are white and the face carries the red.
-- A gate you cannot see is a bug, not a style choice.
local SAVED_POST  = ColorF(0.95, 0.94, 0.92, 0.95)
local SAVED_FACE  = ColorF(0.66, 0.11, 0.13, 0.20)
local DRAFT_POST  = ColorF(0.94, 0.71, 0.16, 0.95)
local DRAFT_FACE  = ColorF(0.91, 0.50, 0.12, 0.18)
local LABEL       = ColorF(1, 1, 1, 1)
local SAVED_BG    = ColorI(122, 20, 24, 215)
local DRAFT_BG    = ColorI(150, 85, 12, 215)

-- during a run the gate being scored is yellow and everything else drops back,
-- so at a junction it is obvious which way the course goes without a minimap
local NEXT_POST   = ColorF(0.94, 0.71, 0.16, 1.00)
local NEXT_FACE   = ColorF(0.91, 0.50, 0.12, 0.26)
local NEXT_BG     = ColorI(150, 85, 12, 230)
local REST_POST   = ColorF(0.95, 0.94, 0.92, 0.45)
local REST_FACE   = ColorF(0.66, 0.11, 0.13, 0.08)
local REST_BG     = ColorI(122, 20, 24, 140)

local DRAW_RANGE = 900
local RACE_RANGE = 400
local errLogged = false

local draft = nil

-- the gates dropped so far in a capture. drawn but not built: there is nothing
-- to collide with until the course is saved.
function M.setDraft(checkpoints)
  draft = checkpoints
  if type(draft) == "table" then fitTurns(draft, false) end
end

function M.clearDraft()
  draft = nil
end

local function drawGate(cp, index, post, face, bg)
  -- the same box the volume uses, so what you see is what you drive through
  local across, _, bottom, top = gateBox(cp)
  local yaw = tonumber(cp.yaw) or 0

  -- across the gate is perpendicular to the way you drive through it
  local rx, ry = -math.sin(yaw), math.cos(yaw)
  local half = across * 0.5

  local lx, ly = cp.pos.x + rx * half, cp.pos.y + ry * half
  local mx, my = cp.pos.x - rx * half, cp.pos.y - ry * half

  local l  = vec3(lx, ly, bottom)
  local r  = vec3(mx, my, bottom)
  local lt = vec3(lx, ly, top)
  local rt = vec3(mx, my, top)

  debugDrawer:drawCylinder(l, lt, 0.22, post)
  debugDrawer:drawCylinder(r, rt, 0.22, post)
  debugDrawer:drawCylinder(lt, rt, 0.16, post)
  debugDrawer:drawQuadSolid(l, r, rt, lt, face)

  debugDrawer:drawTextAdvanced(
    vec3(cp.pos.x, cp.pos.y, top + 1.2),
    String(tostring(index)), LABEL, true, false, bg)
end

local function drawSet(cps, eye, post, face, bg)
  for i = 1, #cps do
    local cp = cps[i]
    if cp and cp.pos then
      local near = true
      if eye then
        local dx, dy = cp.pos.x - eye.x, cp.pos.y - eye.y
        near = (dx * dx + dy * dy) < (DRAW_RANGE * DRAW_RANGE)
      end
      if near then drawGate(cp, i, post, face, bg) end
    end
  end
end

-- the gate being scored, drawn on its own so it can be picked out of the rest
-- without walking the whole course twice
local function drawRace(cps, eye)
  for i = 1, #cps do
    local cp = cps[i]
    if cp and cp.pos then
      local isNext = (i == nextGate)
      local near = true
      if eye then
        local dx, dy = cp.pos.x - eye.x, cp.pos.y - eye.y
        local range = isNext and DRAW_RANGE or RACE_RANGE
        near = (dx * dx + dy * dy) < (range * range)
      end
      if near then
        if isNext then
          drawGate(cp, i, NEXT_POST, NEXT_FACE, NEXT_BG)
        else
          drawGate(cp, i, REST_POST, REST_FACE, REST_BG)
        end
      end
    end
  end
end

local function onUpdate()
  local showRace  = racing and course
  local showSaved = (not racing) and visible and course
  local showDraft = draft and #draft > 0
  if not showRace and not showSaved and not showDraft then return end

  local eye
  local okEye, p = pcall(function() return core_camera.getPosition() end)
  if okEye then eye = p end

  local ok, err = pcall(function()
    if showRace  then drawRace(course.checkpoints, eye) end
    if showSaved then drawSet(course.checkpoints, eye, SAVED_POST, SAVED_FACE, SAVED_BG) end
    if showDraft then drawSet(draft, eye, DRAFT_POST, DRAFT_FACE, DRAFT_BG) end
  end)

  if not ok and not errLogged then
    errLogged = true
    log("W", "raceManager", "could not draw the gates: " .. tostring(err))
  end
end

M.onBeamNGTrigger = onBeamNGTrigger
M.onUpdate        = onUpdate

return M
