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
local PIT_PREFIX = "rm_pit_"
local SZ_PREFIX = "rm_sz_"
local DEFAULT_GATE = { w = 20, h = 8, d = 3 }
local DEFAULT_SZ = { w = 20, h = 8, d = 40 }

-- A pit is a place you sit in, not a line you cross. Built to a gate's three
-- metres it fired enter and exit in the same tenth of a second, so driving
-- through one showed "in the pit" for a blink and parking in one showed
-- nothing at all. It is a box you can stop inside.
local DEFAULT_PIT = { w = 20, h = 8, d = 30 }

local spawned = {}
local course  = nil
local visible = false

-- Which pit boxes the car is standing in. A set rather than a flag, because
-- leaving one box while still inside another used to report the car out of
-- the pit, and a course with a pit either end of the lane does that every time.
local inPits = {}
local inSz = {}

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
  -- the boxes are gone, so nobody is standing in one. without this a car that
  -- was in the pit when the course changed stays in it for ever.
  M.pitsForgotten()
  M.szForgotten()
end

local function gateOf(cp, kind)
  local base = DEFAULT_GATE
  if kind == "pit" then base = DEFAULT_PIT
  elseif kind == "sz" then base = DEFAULT_SZ end
  local s = cp.size or base
  return tonumber(s.w) or base.w,
         tonumber(s.h) or base.h,
         -- a pit keeps its long default depth whatever the capture wrote,
         -- because a pit mark carries the gate depth of the capture screen
         -- and three metres is not a place to park. A speed zone box uses
         -- the size captured for it.
         (kind == "pit") and base.d or (tonumber(s.d) or base.d)
end

-- The one place a gate's shape is worked out. The volume and the posts you see
-- read it from here, because they used to disagree about both axes.
--
-- The base is sunk a little because a gate is marked from the car, and a car's
-- position sits above the dirt, so a gate drawn from that point floats.
local BASE_SINK = 1.5

-- A gate is centred on wherever the capture car happened to be driving, and
-- that is rarely the middle of the track. Marked from the left half, a twenty
-- metre gate ends mid road, and everything driven right of centre misses it.
-- On screen that read as gates only counting near the middle. So each side is
-- measured out to the first wall or bank, and the gate is slid and widened to
-- span the whole gap.
-- Past this there is no lane edge worth finding: a ray that reaches this far
-- has left the track, not measured it. Keep it tight, because whatever a probe
-- reports is what the gate is built to.
local PROBE_MAX = 15.0
local PROBE_UP  = 1.2
local SPAN_MOST = 30.0

-- the sums on their own, so they can be tested without a game
function M.fitSpan(w, left, right)
  w = tonumber(w) or 0
  local half = w * 0.5
  local l, r = tonumber(left), tonumber(right)

  -- Neither side found anything, so there is nothing to fit to and the width
  -- the course was marked with stands. Reading a miss as open track is what
  -- put fifty metre gates across the desert.
  if l == nil and r == nil then return w, 0 end

  -- one side measured is still worth having: the gate slides off the wall it
  -- found and keeps its marked half on the side that told us nothing
  l = l or half
  r = r or half

  local across = l + r
  if across < w then
    local add = (w - across) * 0.5
    l, r, across = l + add, r + add, w
  end
  if across > SPAN_MOST then
    local k = SPAN_MOST / across
    l, r, across = l * k, r * k, SPAN_MOST
  end
  return across, (l - r) * 0.5
end

-- The road the game's own ai drives on knows how wide it is and where its
-- middle runs, which is exactly what a gate needs. Rays fired sideways into
-- open desert touch nothing, so they left gates at the width they were marked
-- with and sitting wherever the capture car happened to be. This is the same
-- question hotlapping asks when it sizes its own checkpoints.
local ROAD_MARGIN = 4.0    -- a little past the edge, so clipping it still counts
-- A road width is measured, not guessed at, so it is allowed to be wider than
-- anything a sideways ray is trusted with.
local ROAD_MOST   = 45.0
-- How far off a road's own line the capture car may have been and still be
-- called on it. Further than this is a different road, and sizing a gate to
-- somebody else's road is what put gates across the desert beside the course.
local ROAD_OFF    = 6.0
-- and it has to run roughly the way the gate faces. a road crossing at right
-- angles tells you nothing about how wide the one you are on is.
local ROAD_ALIGN  = 0.5

-- where the road's middle is beside this point, and how wide it is there.
-- nil unless this really is the road the gate was marked on.
local function roadAt(pos, yaw)
  if type(map) ~= "table" or type(map.findClosestRoad) ~= "function" then return nil end
  local ok, n1, n2, dsq = pcall(map.findClosestRoad, pos, 120)
  if not ok or not n1 or not n2 then return nil end

  local okm, m = pcall(map.getMap)
  if not okm or type(m) ~= "table" or type(m.nodes) ~= "table" then return nil end
  local a, b = m.nodes[n1], m.nodes[n2]
  if type(a) ~= "table" or type(b) ~= "table" or not a.pos or not b.pos then return nil end

  local t = 0.5
  local okx, x = pcall(function() return pos:xnormOnLine(a.pos, b.pos) end)
  if okx and type(x) == "number" then t = math.max(0, math.min(1, x)) end

  local ra, rb = tonumber(a.radius) or 0, tonumber(b.radius) or 0
  local half = ra + (rb - ra) * t
  local wide = half * 2

  -- On it, rather than merely near it. dsq is to the road's line, so this asks
  -- whether the capture car was inside the road plus a little.
  if type(dsq) == "number" and dsq > (half + ROAD_OFF) * (half + ROAD_OFF) then
    return nil
  end

  -- and running the same way the gate faces
  local dx, dy = b.pos.x - a.pos.x, b.pos.y - a.pos.y
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 0.01 then return nil end
  local fx, fy = math.cos(tonumber(yaw) or 0), math.sin(tonumber(yaw) or 0)
  if math.abs((dx / len) * fx + (dy / len) * fy) < ROAD_ALIGN then return nil end

  return a.pos.x + (b.pos.x - a.pos.x) * t,
         a.pos.y + (b.pos.y - a.pos.y) * t,
         wide
end

-- The sums for that, on their own so they can be argued with without a game.
--
-- The gate grows around the line the capture car drove and is never slid off
-- it. Sliding it to the road's middle is what put a gate beside the course
-- with the racing line outside it: the capture car was on the course by
-- definition, so whatever else the gate covers, it has to cover that.
function M.fitRoad(w, yaw, gx, gy, cx, cy, roadWide)
  w = tonumber(w) or 0
  yaw = tonumber(yaw) or 0
  local ax, ay = -math.sin(yaw), math.cos(yaw)

  -- everything below is in metres across the gate, with the captured line at
  -- zero and the road's middle at off
  local off  = (cx - gx) * ax + (cy - gy) * ay
  local half = (tonumber(roadWide) or 0) * 0.5 + ROAD_MARGIN

  -- reach both road edges, and the captured line, whichever is further
  local lo = math.min(0, off - half)
  local hi = math.max(0, off + half)

  -- never leave the captured line on the very edge of its own gate
  if -lo < ROAD_MARGIN then lo = -ROAD_MARGIN end
  if  hi < ROAD_MARGIN then hi =  ROAD_MARGIN end

  -- and never narrower than the width the course was marked with
  if hi - lo < w then
    local grow = (w - (hi - lo)) * 0.5
    lo, hi = lo - grow, hi + grow
  end

  -- Too wide to be a gate. Both ends come in together so a gate that was
  -- centred stays centred, and then the whole thing slides if that shaved the
  -- margin off the side the car was actually on.
  local across = hi - lo
  if across > ROAD_MOST then
    local k = ROAD_MOST / across
    lo, hi, across = lo * k, hi * k, ROAD_MOST
    if -lo < ROAD_MARGIN then
      local need = ROAD_MARGIN + lo
      lo, hi = lo - need, hi - need
    elseif hi < ROAD_MARGIN then
      local need = ROAD_MARGIN - hi
      lo, hi = lo + need, hi + need
    end
  end

  return across, (lo + hi) * 0.5
end

-- Static geometry only, so another car cannot shrink a gate. Nil means the ray
-- found nothing, which is not the same as finding open ground far away.
local function probe(pos, dx, dy)
  if type(castRayStatic) ~= "function" then return nil end
  local ok, d = pcall(castRayStatic,
    vec3(pos.x, pos.y, pos.z + PROBE_UP), vec3(dx, dy, 0), PROBE_MAX)
  if ok and type(d) == "number" and d >= 0 and d < PROBE_MAX - 0.01 then return d end
  return nil
end

local function fitSpans(cps, kind)
  for i = 1, #cps do
    local cp = cps[i]
    if type(cp) == "table" and cp.pos then
      local yaw = tonumber(cp.yaw) or 0
      local rx, ry = -math.sin(yaw), math.cos(yaw)
      local w = gateOf(cp, kind)

      -- the road first, because it is the only one of the two that knows
      -- anything out in the open
      local cx, cy, wide = roadAt(cp.pos, yaw)
      if cx then
        cp.rmAcross, cp.rmOff = M.fitRoad(w, yaw, cp.pos.x, cp.pos.y, cx, cy, wide)
      else
        cp.rmAcross, cp.rmOff = M.fitSpan(w,
          probe(cp.pos, rx, ry), probe(cp.pos, -rx, -ry))
      end
    end
  end
end

local function gateBox(cp, kind)
  local w, h, d = gateOf(cp, kind)
  return cp.rmAcross or w, d, cp.pos.z - BASE_SINK, cp.pos.z + h, cp.rmOff or 0
end

-- the shape one volume ends up with, out where it can be argued with. a pit
-- and a gate differ only in how long they are, and that difference is the
-- whole reason parking in a pit used to register nothing.
M.boxOf = gateBox

-- Same numbers drawBox uses. Inside the painted box = inside the zone.
-- dist is to the nearest face, not the centre, so a long box warns on every side.
function M.boxOffset(cp, pos, kind)
  if not (cp and cp.pos and pos) then return nil end
  local across, along, bottom, top, off = gateBox(cp, kind or "sz")
  local yaw = tonumber(cp.yaw) or 0
  local fx, fy = math.cos(yaw), math.sin(yaw)
  local rx, ry = -math.sin(yaw), math.cos(yaw)
  local cx = cp.pos.x + rx * off
  local cy = cp.pos.y + ry * off
  local dx, dy = pos.x - cx, pos.y - cy
  local alongPos = dx * fx + dy * fy
  local acrossPos = dx * rx + dy * ry
  local halfA, halfD = across * 0.5, along * 0.5
  local clampedA = math.max(-halfA, math.min(halfA, acrossPos))
  local clampedD = math.max(-halfD, math.min(halfD, alongPos))
  local ox = math.max(math.abs(acrossPos) - halfA, 0)
  local oy = math.max(math.abs(alongPos) - halfD, 0)
  local inside = ox == 0 and oy == 0
    and (not pos.z or (pos.z >= bottom - 2 and pos.z <= top + 4))
  local dist = math.sqrt(ox * ox + oy * oy)
  local face = {
    x = cx + rx * clampedA + fx * clampedD,
    y = cy + ry * clampedA + fy * clampedD,
    z = cp.pos.z,
  }
  return inside, dist, face
end

-- the capture in progress: gates and speed zone boxes. Declared here, above
-- the first function that reads them; declared lower down they were globals
-- to that function and always nil, so a drafted zone was never found.
local draft = nil
local draftSz = nil

function M.nearestSz(pos)
  local boxes = course and type(course.szGates) == "table" and course.szGates or draftSz
  if type(boxes) ~= "table" or not pos then return nil end
  local best, bestD, bestIn, bestFace
  for i = 1, #boxes do
    local b = boxes[i]
    if b and b.pos then
      local inside, dist, face = M.boxOffset(b, pos, "sz")
      if inside or dist then
        if not bestD or (inside and not bestIn) or (inside == bestIn and dist < bestD) then
          best, bestD, bestIn, bestFace = b, dist or 0, inside, face
        end
      end
    end
  end
  return best, bestIn, bestD, bestFace
end

local function spawnGate(cp, index, prefix, kind)
  local name = (prefix or PREFIX) .. index
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

    -- Our overlay is the preview. Engine debug was a second box on a
    -- different axis and looked like a sheared yellow slab.
    obj.debug = false

    local across, along, bottom, top, off = gateBox(cp, kind)
    local yaw = tonumber(cp.yaw) or 0
    local rx, ry = -math.sin(yaw), math.cos(yaw)

    -- the box is centred on its position: at the middle of the vertical span,
    -- and slid sideways to the middle of the measured gap rather than sitting
    -- on the line the capture car happened to drive
    obj:setPosition(vec3(cp.pos.x + rx * off, cp.pos.y + ry * off, (bottom + top) * 0.5))

    -- yaw sends local x along the way you drive, so the width goes in y and the
    -- depth in x. These were swapped once and built a three metre slot down
    -- the middle of the road instead of a gate across it, and drivers went
    -- through checkpoints that never fired. This pairing is the one that was
    -- driven and seen to fire, so it stays as it is.
    obj:setScale(vec3(along, across, top - bottom))

    -- yaw only. a gate leaning with the camber of the road buys nothing and
    -- makes the volume harder to drive through.
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
  -- log unreadable. the volumes are the gates plus the pits.
  local want = #track.checkpoints
    + #(type(track.pits) == "table" and track.pits or {})
    + #(type(track.szGates) == "table" and track.szGates or {})
  if course and course.id == track.id and #spawned == want then
    M.setVisible(showBoxes and true or false)
    return #spawned
  end

  M.clear()
  course = track
  visible = showBoxes and true or false
  -- Keep the heading and size from capture. Fitting to the road was
  -- twisting the volumes off the preview.

  local made = 0
  for i = 1, #track.checkpoints do
    local name = spawnGate(track.checkpoints[i], i)
    if name then
      made = made + 1
      spawned[made] = name
    end
  end

  -- pits are volumes too, under their own names, so the crossing handler can
  -- tell a pit from a gate without guessing
  local pits = type(track.pits) == "table" and track.pits or {}
  fitSpans(pits, "pit")
  for i = 1, #pits do
    local name = spawnGate(pits[i], i, PIT_PREFIX, "pit")
    if name then spawned[#spawned + 1] = name end
  end

  local boxes = type(track.szGates) == "table" and track.szGates or {}
  for i = 1, #boxes do
    local name = spawnGate(boxes[i], i, SZ_PREFIX, "sz")
    if name then spawned[#spawned + 1] = name end
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

-- Load course data without forcing the Show-gates toggle on.
-- Used when the track arrives for Stella/copilot mirror or other non-UI
-- reasons so checkpoint visibility stays under the user's Hide/Show button.
-- When the gates are currently hidden we only store the course for Stella
-- and later Show; we do not spawn volumes or change shownId.
function M.loadCourse(track)
  if type(track) ~= "table" then return 0 end
  if visible and shownId == track.id then
    -- already showing this course; refresh volumes without forcing visibility
    local made = M.build(track, true)
    M.setVisible(true)
    return made
  end
  if visible then
    -- user has gates on for a different course; switch to this one
    shownId = track.id
    local made = M.build(track, true)
    M.setVisible(true)
    return made
  end
  -- gates are hidden: just keep the data available, leave UI toggle alone
  course = track
  return 0
end

function M.stopPreview()
  shownId = nil
  M.setVisible(false)
end

-- the volumes a race is scored on. same as the preview, but nothing is
-- drawn: live and freeplay stay clean unless Show gates is pressed.
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

  -- a course somebody asked to look at outlives the run they just did,
  -- but do not force the gates visible — leave the Show/Hide toggle alone
  if shownId and course and shownId == course.id then
    -- keep volumes; visibility stays whatever the user last set
  else
    M.clear()
  end
end

function M.setNextGate(i)
  nextGate = tonumber(i) or nextGate
end

-- Where the car belongs if it has to be put back: the leg it is on, from the
-- gate it last passed to the one it is going for. Only while a race is up,
-- because outside one there is no line to be on.
function M.leg()
  if not racing or type(course) ~= "table" then return nil end
  local cps = course.checkpoints
  if type(cps) ~= "table" then return nil end
  local n = #cps
  if n < 2 then return nil end

  local ni = tonumber(nextGate) or 1
  if ni < 1 then ni = 1 end
  if ni > n then ni = n end

  -- before the first gate on a lap the leg behind you is the last one, but
  -- only on a circuit. on a point to point the start is as far back as it goes.
  local pi = ni - 1
  if pi < 1 then pi = course.circuit and n or ni end
  if pi == ni then pi = (ni == 1) and n or (ni - 1) end
  if pi < 1 or pi > n or pi == ni then return nil end

  local a, b = cps[pi], cps[ni]
  if type(a) ~= "table" or type(b) ~= "table" or not a.pos or not b.pos then return nil end
  return a.pos, b.pos
end

-- The nearest point on that leg, and which way it runs. Kept apart from the
-- game so the sums can be checked: putting a car back in the wrong place is
-- worse than leaving it where it rolled.
function M.legPoint(px, py, a, b)
  local abx, aby = b.x - a.x, b.y - a.y
  local len2 = abx * abx + aby * aby
  local t = 0
  if len2 > 0 then
    t = ((px - a.x) * abx + (py - a.y) * aby) / len2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
  end
  local yaw = (math.atan2 or math.atan)(aby, abx)
  return a.x + abx * t, a.y + aby * t, a.z + ((b.z or 0) - (a.z or 0)) * t, yaw, t
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

-- Which pit boxes the car is in, and whether that answer just changed.
-- Returns nil when it did not. This is a set rather than a flag because
-- leaving one box while still inside another used to report the car out of
-- the pit, and a lane with a box at each end does that on every visit.
function M.pitCrossed(id, event)
  local was = next(inPits) ~= nil
  if event == "enter" then inPits[tostring(id)] = true
  else inPits[tostring(id)] = nil end
  local now = next(inPits) ~= nil
  if now == was then return nil end
  return now
end

function M.pitsForgotten()
  inPits = {}
end

function M.szForgotten()
  inSz = {}
end

local function szMphNow()
  local lowest
  for id in pairs(inSz) do
    local g = course and course.szGates and course.szGates[tonumber(id)]
    local mph = g and tonumber(g.mph)
    if mph and (not lowest or mph < lowest) then lowest = mph end
  end
  return lowest
end

function M.szCrossed(id, event)
  local was = next(inSz) ~= nil
  if event == "enter" then inSz[tostring(id)] = true
  else inSz[tostring(id)] = nil end
  local now = next(inSz) ~= nil
  if now == was and not now then return nil end
  return now, szMphNow()
end

local function onBeamNGTrigger(data)
  if type(data) ~= "table" or not course then return end

  -- only our own car. everyone else's crossings are their client's business.
  local mine = localVehicleId()
  if mine and data.subjectID and data.subjectID ~= mine then return end

  local name = tostring(data.triggerName or "")

  -- a pit is a place, so leaving it matters as much as entering
  local pit = name:match("^" .. PIT_PREFIX .. "(%d+)$")
  if pit then
    local now = M.pitCrossed(pit, data.event)
    -- nil means nothing changed, and standing still in a pit re-tests the
    -- overlap often enough that saying so every time would be a flood
    if now ~= nil then
      extensions.raceManager_net.send("pit.state", { inside = now })
    end
    return
  end

  -- a speed zone box: nothing is sent from here. The poll below measures
  -- the car against the box every frame and says in or out once, with a
  -- little slack at the edge. A second voice from the volume, which fires
  -- on the car's corners, had the two disagreeing at every edge.
  if name:match("^" .. SZ_PREFIX .. "(%d+)$") then return end

  if data.event ~= "enter" then return end
  local index = name:match("^" .. PREFIX .. "(%d+)$")
  if not index then return end

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

-- a pit is a different kind of place, so it gets its own colour
local PIT_POST = ColorF(0.20, 0.75, 0.85, 0.95)
local PIT_FACE = ColorF(0.10, 0.55, 0.65, 0.18)
local PIT_BG   = ColorI(12, 95, 110, 215)
local SZ_POST  = ColorF(0.18, 0.92, 0.32, 0.95)
local SZ_FACE  = ColorF(0.12, 0.78, 0.28, 0.16)
local SZ_EDGE  = ColorF(0.20, 1.00, 0.38, 0.90)
local SZ_BG    = ColorI(18, 110, 36, 215)

local DRAW_RANGE = 900
local RACE_RANGE = 400
local errLogged = false

-- the gates dropped so far in a capture. drawn but not built: there is nothing
-- to collide with until the course is saved.
function M.setDraft(checkpoints)
  draft = checkpoints
  if type(draft) == "table" then fitSpans(draft) end
end

function M.setDraftSz(boxes)
  draftSz = boxes
end

function M.clearDraft()
  draft = nil
  draftSz = nil
end

local function drawBox(cp, index, post, face, edge, bg, kind)
  -- full volume: width across the road, depth along the car, height up.
  local across, along, bottom, top, off = gateBox(cp, kind or "sz")
  local yaw = tonumber(cp.yaw) or 0
  local fx, fy = math.cos(yaw), math.sin(yaw)
  local rx, ry = -math.sin(yaw), math.cos(yaw)
  local cx, cy = cp.pos.x + rx * off, cp.pos.y + ry * off
  local ha, hd = across * 0.5, along * 0.5
  local function corner(sa, sd, z)
    return vec3(cx + rx * ha * sa + fx * hd * sd,
                cy + ry * ha * sa + fy * hd * sd, z)
  end
  local lfb, rfb = corner(-1, -1, bottom), corner(1, -1, bottom)
  local lrb, rrb = corner(-1,  1, bottom), corner(1,  1, bottom)
  local lft, rft = corner(-1, -1, top),    corner(1, -1, top)
  local lrt, rrt = corner(-1,  1, top),    corner(1,  1, top)
  local e = edge or post
  local function beam(a, b)
    debugDrawer:drawCylinder(a, b, 0.12, e)
  end
  beam(lfb, rfb); beam(rfb, rrb); beam(rrb, lrb); beam(lrb, lfb)
  beam(lft, rft); beam(rft, rrt); beam(rrt, lrt); beam(lrt, lft)
  beam(lfb, lft); beam(rfb, rft); beam(rrb, rrt); beam(lrb, lrt)
  debugDrawer:drawQuadSolid(lfb, rfb, rft, lft, face)
  debugDrawer:drawQuadSolid(rrb, lrb, lrt, rrt, face)
  debugDrawer:drawQuadSolid(lrb, lfb, lft, lrt, face)
  debugDrawer:drawQuadSolid(rfb, rrb, rrt, rft, face)
  debugDrawer:drawQuadSolid(lft, rft, rrt, lrt, face)
  local label = tostring(index)
  if cp.mph then label = label .. "  " .. tostring(math.floor(cp.mph + 0.5)) .. " mph" end
  debugDrawer:drawTextAdvanced(vec3(cx, cy, top + 1.2), String(label), LABEL, true, false, bg)
end

local function drawBoxSet(list, eye, post, face, edge, bg, kind)
  if type(list) ~= "table" then return end
  for i = 1, #list do
    local cp = list[i]
    if cp and cp.pos then
      local near = true
      if eye then
        local dx, dy = cp.pos.x - eye.x, cp.pos.y - eye.y
        near = (dx * dx + dy * dy) < (DRAW_RANGE * DRAW_RANGE)
      end
      if near then drawBox(cp, cp.i or i, post, face, edge, bg, kind) end
    end
  end
end

local function drawGate(cp, index, post, face, bg)
  -- Same OBB as the trigger: width across the car, depth along it.
  local across, along, bottom, top, off = gateBox(cp)
  local yaw = tonumber(cp.yaw) or 0
  local fx, fy = math.cos(yaw), math.sin(yaw)
  local rx, ry = -math.sin(yaw), math.cos(yaw)
  local cx, cy = cp.pos.x + rx * off, cp.pos.y + ry * off
  local ha, hd = across * 0.5, along * 0.5
  local function corner(sa, sd, z)
    return vec3(cx + rx * ha * sa + fx * hd * sd,
                cy + ry * ha * sa + fy * hd * sd, z)
  end
  local lfb, rfb = corner(-1, -1, bottom), corner(1, -1, bottom)
  local lrb, rrb = corner(-1,  1, bottom), corner(1,  1, bottom)
  local lft, rft = corner(-1, -1, top),    corner(1, -1, top)
  local lrt, rrt = corner(-1,  1, top),    corner(1,  1, top)
  debugDrawer:drawCylinder(lfb, lft, 0.22, post)
  debugDrawer:drawCylinder(rfb, rft, 0.22, post)
  debugDrawer:drawCylinder(lft, rft, 0.16, post)
  debugDrawer:drawQuadSolid(lfb, rfb, rft, lft, face)
  debugDrawer:drawQuadSolid(lrb, rrb, rrt, lrt, face)
  debugDrawer:drawQuadSolid(lfb, lrb, lrt, lft, face)
  debugDrawer:drawQuadSolid(rfb, rrb, rrt, rft, face)
  debugDrawer:drawTextAdvanced(
    vec3(cx, cy, top + 1.2),
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

local lastGeomInside = nil
local lastGeomMph = nil
local szNow = nil

-- The one measure of the car against the boxes. It tells the server in or
-- out once per change, and the Stella bridge reads the same answer, so the
-- unit and the server never disagree about a box. A car that is in stays
-- in until it is two metres clear, so a car sat on the edge of a box does
-- not flicker in and out.
local SZ_SLACK_M = 2
local function pollSzGeometry()
  if not racing or not course or type(course.szGates) ~= "table" or #course.szGates == 0 then
    lastGeomInside, lastGeomMph = nil, nil
    szNow = nil
    return
  end
  local pos
  local ok, veh = pcall(function() return be:getPlayerVehicle(0) end)
  if ok and veh then
    local ok2, p = pcall(function() return veh:getPosition() end)
    if ok2 then pos = p end
  end
  if not pos then return end
  local box, inside, dist, face = M.nearestSz(pos)
  local now = inside and true or false
  if not now and lastGeomInside and box and (tonumber(dist) or math.huge) <= SZ_SLACK_M then now = true end
  szNow = { box = box, inside = now, dist = now and 0 or dist, face = face }
  local mph = now and box and tonumber(box.mph) or nil
  -- out is where every race starts, so the first frame out is no change;
  -- it used to send an out to the server on the first frame of every race
  -- on a course with a box, and the server said "Speed zone off" back
  if now == (lastGeomInside == true) and mph == lastGeomMph then
    lastGeomInside = now
    return
  end
  lastGeomInside, lastGeomMph = now, mph
  extensions.raceManager_net.send("sz.state", {
    inside = now, mph = mph, i = box and box.i or nil,
  })
end

-- the poll's latest answer: the nearest box, whether the car is in it, and
-- how far it is from its nearest face. nil when there is nothing to measure.
function M.szState() return szNow end

local function onUpdate()
  pollSzGeometry()

  -- Live race and freeplay draw nothing. Show gates is `visible`.
  -- Capture still draws the draft you are placing.
  local showSaved = (not racing) and visible and course
  local showDraft = draft and #draft > 0
  local showDraftSz = draftSz and #draftSz > 0
  if not showSaved and not showDraft and not showDraftSz then return end

  local eye
  local okEye, p = pcall(function() return core_camera.getPosition() end)
  if okEye then eye = p end

  local pits = course and type(course.pits) == "table" and course.pits or nil

  local ok, err = pcall(function()
    if showSaved then drawSet(course.checkpoints, eye, SAVED_POST, SAVED_FACE, SAVED_BG) end
    if showSaved and pits and #pits > 0 then
      drawSet(pits, eye, PIT_POST, PIT_FACE, PIT_BG)
    end
    local boxes = course and type(course.szGates) == "table" and course.szGates or nil
    if showSaved and boxes and #boxes > 0 then
      drawBoxSet(boxes, eye, SZ_POST, SZ_FACE, SZ_EDGE, SZ_BG, "sz")
    end
    if showDraft then drawSet(draft, eye, DRAFT_POST, DRAFT_FACE, DRAFT_BG) end
    if showDraftSz then drawBoxSet(draftSz, eye, SZ_POST, SZ_FACE, SZ_EDGE, SZ_BG, "sz") end
  end)

  if not ok and not errLogged then
    errLogged = true
    log("W", "raceManager", "could not draw the gates: " .. tostring(err))
  end
end

M.onBeamNGTrigger = onBeamNGTrigger
M.onUpdate        = onUpdate

return M
