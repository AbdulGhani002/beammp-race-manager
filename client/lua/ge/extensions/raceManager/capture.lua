local M = {}

-- You drive the route and press a key at each point. The server keeps the
-- draft, so a crash 24 gates into a 29 gate layout costs nothing.

local st = {
  active     = false,
  id         = nil,
  name       = nil,
  kind       = "race",
  level      = nil,
  circuit    = false,
  count      = 0,
  gate       = { w = 20, h = 8, d = 3 },
  fitWidth   = true,
  lastError  = nil,
  lastGateAt = nil,
  distance   = 0,
  previewing = false,
}

-- the gates dropped so far, kept here so they can be drawn while the capture
-- is still going. the server holds the real copy.
local gates = {}

local function pushDraft()
  extensions.raceManager_triggers.setDraft(gates)
end

local acc = 0

local function atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end

-- A gate has to span the road it is standing on. One fixed width is wrong in
-- both directions: on a wide stretch you can drive round the end of it, and on
-- a narrow one the posts end up planted through the barrier, which is what the
-- boundary complaint was about.
--
-- The navigation graph already carries how wide the road is at every point,
-- and the game sizes its own race waypoints from exactly this, so the gate is
-- sized from it too. A margin is added because the drivable dirt is usually a
-- little wider than the line the ai would take.
local FIT_MIN, FIT_MAX, FIT_MARGIN = 8.0, 60.0, 5.0

local function roadWidthAt(pos)
  if type(map) ~= "table" or type(map.findClosestRoad) ~= "function" then return nil end

  local ok, n1, n2 = pcall(map.findClosestRoad, pos, 80)
  if not ok or not n1 then return nil end

  local okNodes, nodes = pcall(function() return map.getMap().nodes end)
  if not okNodes or type(nodes) ~= "table" then return nil end

  local widest = 0
  for _, id in ipairs({ n1, n2 }) do
    local node = nodes[id]
    local r = node and tonumber(node.radius)
    if r and r > widest then widest = r end
  end
  if widest <= 0 then return nil end

  local w = widest * 2 + FIT_MARGIN
  if w < FIT_MIN then w = FIT_MIN end
  if w > FIT_MAX then w = FIT_MAX end
  return math.floor(w * 10 + 0.5) / 10
end

M.roadWidthAt = roadWidthAt

local function playerVehicle()
  local ok, veh = pcall(function() return be:getPlayerVehicle(0) end)
  if ok and veh then return veh end
  return nil
end

-- where the car is and which way it is pointing. the gate is built square to
-- the car, so the direction you drive through it is the direction it faces.
local function readPose()
  local veh = playerVehicle()
  if not veh then return nil end

  local okPos, pos = pcall(function() return veh:getPosition() end)
  if not okPos or not pos then return nil end

  local yaw = 0
  local okDir, dir = pcall(function() return veh:getDirectionVector() end)
  if okDir and dir then yaw = atan2(dir.y, dir.x) end

  return { x = pos.x, y = pos.y, z = pos.z }, yaw
end

function M.status()
  st.showing = extensions.raceManager_triggers.shownId()
  return st
end

function M.begin(opts)
  opts = type(opts) == "table" and opts or {}
  local S = extensions.raceManager_state.get()

  st.lastError = nil
  extensions.raceManager_net.send("track.begin", {
    id        = opts.id or opts.name,
    name      = opts.name,
    kind      = opts.kind or "race",
    circuit   = opts.circuit and true or false,
    level     = S.level or "unknown",
    overwrite = opts.overwrite and true or false,
  })
end

function M.mark()
  if not st.active then return end
  local pos, yaw = readPose()
  if not pos then
    st.lastError, st.errorFor = "no_vehicle", 6
    extensions.raceManager_ui.push()
    return
  end
  local w = st.gate.w
  if st.fitWidth then w = roadWidthAt(vec3(pos.x, pos.y, pos.z)) or st.gate.w end

  extensions.raceManager_net.send("track.mark", {
    pos = pos, yaw = yaw,
    w = w, h = st.gate.h, d = st.gate.d,
  })
end

-- Resize every gate on a course you are looking at to the road under it, so a
-- course captured before gates were fitted does not have to be driven again.
-- The widths are worked out here because the navigation graph lives in the
-- game; the server only stores what comes back.
function M.refitSaved()
  local S = extensions.raceManager_state.get()
  local track = S and S.track
  if type(track) ~= "table" or type(track.checkpoints) ~= "table" then
    extensions.raceManager_state.notice("Open a course first")
    return
  end

  local widths, fitted = {}, 0
  for i = 1, #track.checkpoints do
    local cp = track.checkpoints[i]
    local w = cp.pos and roadWidthAt(vec3(cp.pos.x, cp.pos.y, cp.pos.z))
    if w then widths[i] = w; fitted = fitted + 1 end
  end

  if fitted == 0 then
    extensions.raceManager_state.notice("No road found under this course to measure")
    return
  end

  extensions.raceManager_net.send("track.refit", { id = track.id, widths = widths })
  extensions.raceManager_state.notice(("Fitting %d of %d gates to the road")
    :format(fitted, #track.checkpoints))
end

function M.undo()
  if not st.active then return end
  extensions.raceManager_net.send("track.undo", {})
end

-- a pit is marked the same way a gate is: stand the car in it and press
function M.markPit()
  if not st.active then return end
  local pos, yaw = readPose()
  if not pos then
    st.lastError, st.errorFor = "no_vehicle", 6
    extensions.raceManager_ui.push()
    return
  end
  local w = st.gate.w
  if st.fitWidth then w = roadWidthAt(vec3(pos.x, pos.y, pos.z)) or st.gate.w end
  extensions.raceManager_net.send("track.pit", {
    pos = pos, yaw = yaw,
    w = w, h = st.gate.h, d = st.gate.d,
  })
end

function M.undoPit()
  if not st.active then return end
  extensions.raceManager_net.send("track.pitundo", {})
end

function M.setGate(w, h, d)
  if tonumber(w) and tonumber(w) ~= st.gate.w then st.fitWidth = false end
  st.gate.w = tonumber(w) or st.gate.w
  st.gate.h = tonumber(h) or st.gate.h
  st.gate.d = tonumber(d) or st.gate.d
  if st.active and st.count > 0 then
    extensions.raceManager_net.send("track.gate", st.gate)
  end
  extensions.raceManager_ui.push()
end

-- the grid. defaults to the first gate if it is never set by hand.
function M.setStart()
  if not st.active then return end
  local pos, yaw = readPose()
  if not pos then
    st.lastError, st.errorFor = "no_vehicle", 6
    extensions.raceManager_ui.push()
    return
  end
  extensions.raceManager_net.send("track.start", { pos = pos, yaw = yaw })
end

function M.finish()
  if not st.active then return end
  extensions.raceManager_net.send("track.finish", {})
end

function M.cancel()
  if not st.active then return end
  extensions.raceManager_net.send("track.cancel", {})
end

function M.deleteTrack(id)
  extensions.raceManager_net.send("track.delete", { id = id })
end

function M.openTrack(id)
  extensions.raceManager_net.send("track.get", { id = id })
end

function M.stopPreview()
  extensions.raceManager_triggers.stopPreview()
  st.previewing = false
  extensions.raceManager_ui.push()
end

-- a saved course was opened with Show, so the hide button has to appear
function M.onPreview()
  st.previewing = extensions.raceManager_triggers.count() > 0
  extensions.raceManager_ui.push()
end

-- an unfinished capture came back from the server on reconnect
function M.resume(draft)
  st.active  = true
  st.pits    = #(draft.pits or {})
  st.id      = draft.id
  st.name    = draft.name
  st.kind    = draft.kind
  st.level   = draft.level
  st.circuit = draft.circuit and true or false
  st.count   = #(draft.checkpoints or {})
  gates = draft.checkpoints or {}
  pushDraft()
  local last = draft.checkpoints and draft.checkpoints[st.count]
  if last then
    st.lastGateAt = last.pos
    if last.size then st.gate = { w = last.size.w, h = last.size.h, d = last.size.d } end
  end
  log("I", "raceManager", ("resumed capture of %s at %d checkpoints")
    :format(tostring(st.id), st.count))
  extensions.raceManager_ui.push()
end

local function onBegin(d)
  gates = {}
  pushDraft()
  st.pits = 0
  st.active     = true
  st.id         = d.id
  st.name       = d.name
  st.kind       = d.kind
  st.level      = d.level
  st.circuit    = d.circuit and true or false
  st.count      = 0
  st.lastGateAt = nil
end

local function onMark(d)
  st.count = d.i or (st.count + 1)
  st.lastGateAt = d.pos
  gates[st.count] = d
  pushDraft()
end

function M.onResult(d)
  if type(d) ~= "table" then return end

  if not d.ok then
    st.lastError, st.errorFor = d.reason, 6
    extensions.raceManager_ui.push()
    return
  end

  st.lastError, st.errorFor = nil, nil
  local a = d.action

  if a == "begin" then
    onBegin(d.data or {})
  elseif a == "mark" then
    onMark(d.data or {})
  elseif a == "pit" then
    st.pits = type(d.data) == "table" and d.data.i or ((st.pits or 0) + 1)
  elseif a == "pitundo" then
    st.pits = tonumber(d.data) or math.max(0, (st.pits or 0) - 1)
  elseif a == "undo" then
    st.count = tonumber(d.data) or math.max(0, st.count - 1)
    for i = st.count + 1, #gates do gates[i] = nil end
    st.lastGateAt = gates[st.count] and gates[st.count].pos or nil
    pushDraft()
  elseif a == "gate" and type(d.data) == "table" and d.data.size then
    st.gate = { w = d.data.size.w, h = d.data.size.h, d = d.data.size.d }
    local i = tonumber(d.data.i) or st.count
    if gates[i] then gates[i].size = d.data.size end
    pushDraft()
  elseif a == "finish" then
    st.active = false
    st.count  = 0
    st.lastGateAt = nil
    gates = {}
    extensions.raceManager_triggers.clearDraft()
    if type(d.data) == "table" then
      st.previewing = extensions.raceManager_triggers.preview(d.data) > 0
    end
  elseif a == "cancel" or a == "delete" then
    st.active = false
    st.count  = 0
    st.lastGateAt = nil
    gates = {}
    extensions.raceManager_triggers.clearDraft()
  end

  extensions.raceManager_ui.push()
end

function M.onGatePassed(i)
  st.lastPassed = i
  extensions.raceManager_ui.push()
end

function M.onLevelUnloaded()
  st.previewing = false
end

-- the only per frame cost in the mod, and it stops at the first line unless
-- you have the capture window open
local function onUpdate(dt)
  -- a refusal from a minute ago is worse than none: it reads as the state of
  -- the thing you just did
  if st.errorFor then
    st.errorFor = st.errorFor - dt
    if st.errorFor <= 0 then
      st.lastError, st.errorFor = nil, nil
      extensions.raceManager_ui.push()
    end
  end

  if not st.active or not st.lastGateAt then return end
  acc = acc + dt
  if acc < 0.2 then return end
  acc = 0

  local pos = readPose()
  if not pos then return end
  local dx = pos.x - st.lastGateAt.x
  local dy = pos.y - st.lastGateAt.y
  local dz = pos.z - st.lastGateAt.z
  local d = math.sqrt(dx * dx + dy * dy + dz * dz)

  if math.abs(d - st.distance) >= 1 then
    st.distance = math.floor(d)
    extensions.raceManager_ui.push()
  end
end

M.onUpdate = onUpdate

return M
