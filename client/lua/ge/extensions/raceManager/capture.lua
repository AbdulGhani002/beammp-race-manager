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
  lastError  = nil,
  lastGateAt = nil,
  distance   = 0,
  previewing = false,
}

local acc = 0

local function atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end

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
    st.lastError = "no_vehicle"
    extensions.raceManager_ui.push()
    return
  end
  extensions.raceManager_net.send("track.mark", {
    pos = pos, yaw = yaw,
    w = st.gate.w, h = st.gate.h, d = st.gate.d,
  })
end

function M.undo()
  if not st.active then return end
  extensions.raceManager_net.send("track.undo", {})
end

function M.setGate(w, h, d)
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
    st.lastError = "no_vehicle"
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

-- an unfinished capture came back from the server on reconnect
function M.resume(draft)
  st.active  = true
  st.id      = draft.id
  st.name    = draft.name
  st.kind    = draft.kind
  st.level   = draft.level
  st.circuit = draft.circuit and true or false
  st.count   = #(draft.checkpoints or {})
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
end

function M.onResult(d)
  if type(d) ~= "table" then return end

  if not d.ok then
    st.lastError = d.reason
    extensions.raceManager_ui.push()
    return
  end

  st.lastError = nil
  local a = d.action

  if a == "begin" then
    onBegin(d.data or {})
  elseif a == "mark" then
    onMark(d.data or {})
  elseif a == "undo" then
    st.count = tonumber(d.data) or math.max(0, st.count - 1)
  elseif a == "gate" and type(d.data) == "table" and d.data.size then
    st.gate = { w = d.data.size.w, h = d.data.size.h, d = d.data.size.d }
  elseif a == "finish" then
    st.active = false
    st.count  = 0
    st.lastGateAt = nil
    if type(d.data) == "table" then
      st.previewing = extensions.raceManager_triggers.preview(d.data) > 0
    end
  elseif a == "cancel" or a == "delete" then
    st.active = false
    st.count  = 0
    st.lastGateAt = nil
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
