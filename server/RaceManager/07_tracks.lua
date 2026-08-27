RM = RM or {}
RM.tracks = {}

-- checkpoints are captured by driving. the map file is never touched, so
-- players need no custom map. drafts are keyed on identity and written to
-- disk, so crashing 24 gates into a 29 gate layout costs 0 gates.

local STORE  = "tracks"
local DSTORE = "trackdrafts"

local tracks = nil
local drafts = nil

local DEFAULT_GATE = { w = 20.0, h = 8.0, d = 3.0 }   -- metres
local KINDS = { race = true, qualifying = true, timeattack = true }

function RM.tracks.init()
  tracks = RM.store.load(STORE, {})
  drafts = RM.store.load(DSTORE, {})

  -- courses captured before the gates were squared up carry the old angles and
  -- the old numbering, and both are unracable. Fixing them on load costs one
  -- pass at boot and saves recapturing a thirty gate course by hand.
  for _, track in pairs(tracks) do RM.tracks.squareUp(track) end
  RM.store.markDirty(STORE)
end

local function keyOf(pid)
  local s = RM.identity.session(pid)
  return s and s.key or nil
end

local function readVec(v)
  if type(v) ~= "table" then return nil end
  local x, y, z = v.x or v[1], v.y or v[2], v.z or v[3]
  if not (RM.util.isNum(x) and RM.util.isNum(y) and RM.util.isNum(z)) then return nil end
  if math.abs(x) > 100000 or math.abs(y) > 100000 or math.abs(z) > 100000 then return nil end
  return { x = x, y = y, z = z }
end

local function gateFrom(d)
  return {
    w = RM.util.clamp(tonumber(d and d.w) or DEFAULT_GATE.w, 2.0, 200.0),
    h = RM.util.clamp(tonumber(d and d.h) or DEFAULT_GATE.h, 2.0, 60.0),
    d = RM.util.clamp(tonumber(d and d.d) or DEFAULT_GATE.d, 1.0, 40.0),
  }
end

local function unit(dx, dy)
  local m = math.sqrt(dx * dx + dy * dy)
  if m < 1e-6 then return nil end
  return dx / m, dy / m
end

local function angleGap(a, b)
  local d = (a - b) % (2 * math.pi)
  if d > math.pi then d = d - 2 * math.pi end
  return d
end

-- A gate stores the heading the car had at the moment the key went down. Press
-- it mid corner and the gate faces where the car was pointing rather than
-- lying across the road. Gate 4 of the first test course came out 89 degrees
-- off the racing line, which turned a 20 metre doorway into a 3 metre slot
-- running along the road, and it could not be driven through from any
-- direction.
--
-- Once the whole course exists the line through each gate is known, so the
-- angle is taken from that instead: square to the way in, swung part way
-- toward the way out so a hairpin gate stays open to a car that is already
-- rotating. The captured heading is only kept where there is no line to read.
--
-- The swing is capped, because half of a near switchback is most of a right
-- angle and would put the gate back along the road. This course has one: the
-- corner turns 149 degrees, and splitting it evenly leaves the gate 75 degrees
-- off the way in, which is the fault being fixed rather than a fix for it.
local MOST_SWING = math.pi / 4

local function faceAlongTheLine(cps, circuit)
  local n = #cps
  if n < 2 then return 0 end

  local want = {}
  for i = 1, n do
    local here = cps[i]
    local prev = cps[i - 1] or (circuit and cps[n] or nil)
    local nxt  = cps[i + 1] or (circuit and cps[1] or nil)

    local ix, iy, ox, oy
    if prev then ix, iy = unit(here.pos.x - prev.pos.x, here.pos.y - prev.pos.y) end
    if nxt  then ox, oy = unit(nxt.pos.x - here.pos.x, nxt.pos.y - here.pos.y) end

    if ix and ox then
      local into = math.atan(iy, ix)
      local away = math.atan(oy, ox)
      local swing = angleGap(away, into) * 0.5
      if swing >  MOST_SWING then swing =  MOST_SWING end
      if swing < -MOST_SWING then swing = -MOST_SWING end
      want[i] = into + swing
    elseif ix then want[i] = math.atan(iy, ix)
    elseif ox then want[i] = math.atan(oy, ox) end
  end

  local moved = 0
  for i = 1, n do
    if want[i] then
      if math.abs(angleGap(want[i], cps[i].yaw or 0)) > 0.05 then moved = moved + 1 end
      cps[i].yaw = want[i]
    end
  end
  return moved
end

-- Gate 1 is the gate that was dropped first, and the start line is gate 1.
-- That is what the person capturing the course meant by pressing the button
-- there, and it is what they expect to see when they race it.
--
-- This used to roll the numbering so gate 1 became whichever gate the grid was
-- pointing at, to fix a course whose grid had been left half way round the
-- loop with gate 1 behind the car. That was the wrong half of the fix: the
-- cars are lined up from gate 1 now rather than from the saved grid, which
-- solves it on its own. Rolling on top of that moved somebody's start line
-- eleven gates into their own course.
--
-- The grid is still worth checking, because it says whether the two agree.
local function gridFacesGateOne(track)
  local cps = track.checkpoints
  if #cps < 2 or type(track.start) ~= "table" then return nil end

  local yaw = tonumber(track.start.yaw) or 0
  local dx = cps[1].pos.x - track.start.pos.x
  local dy = cps[1].pos.y - track.start.pos.y
  local m = math.sqrt(dx * dx + dy * dy)
  if m < 0.5 then return nil end

  if ((dx / m) * math.cos(yaw) + (dy / m) * math.sin(yaw)) > 0 then return nil end
  return ("the grid was left facing away from gate 1, %.0fm from it. "):format(m)
      .. "cars are lined up in front of gate 1 regardless"
end

-- Everything above, run over one course. Idempotent: an angle read off the
-- racing line does not move when it is read again, and nothing here renumbers
-- anything.
function RM.tracks.squareUp(track)
  if type(track) ~= "table" or type(track.checkpoints) ~= "table" then return end
  local problem = gridFacesGateOne(track)
  local turned = faceAlongTheLine(track.checkpoints, track.circuit and true or false)

  if turned > 0 then
    RM.info(("%s: squared %d gate%s to the racing line")
      :format(tostring(track.id), turned, turned == 1 and "" or "s"))
  end
  if problem then
    RM.warn(("%s: %s"):format(tostring(track.id), problem))
  end
end

-- Where the cars line up. The saved grid decides which part of a loop the lap
-- starts on, but it is a poor place to put a car down: it was left by driving
-- there and stopping, so it can sit a metre past the gate it is meant to be in
-- front of, and facing away from it. Both courses captured so far do exactly
-- that, and neither can be started by driving forwards.
--
-- Worse, a grid inside the gate volume never fires at all: the car is already
-- through it before the run begins, and there is no crossing left to make.
--
-- So the lineup is taken from gate 1 instead. Square in front of it, back far
-- enough to be clear of the volume, pointing at it. The saved grid keeps the
-- one job it is good at, which is saying where the lap starts.
local GRID_SETBACK = 8.0

function RM.tracks.gridFor(track)
  local cp = track and type(track.checkpoints) == "table" and track.checkpoints[1]
  if not cp then return track and track.start or nil end
  local yaw = tonumber(cp.yaw) or 0
  return {
    pos = {
      x = cp.pos.x - math.cos(yaw) * GRID_SETBACK,
      y = cp.pos.y - math.sin(yaw) * GRID_SETBACK,
      z = cp.pos.z,
    },
    yaw = yaw,
  }
end

function RM.tracks.countTracks()
  local n = 0
  for _ in pairs(tracks) do n = n + 1 end
  return n
end

function RM.tracks.beginCapture(pid, d)
  if not RM.roles.atLeast(pid, "admin") then return false, "not_allowed" end
  if type(d) ~= "table" then return false, "bad_request" end
  local key = keyOf(pid)
  if not key then return false, "no_session" end

  local id = RM.util.slug(d.id or d.name)
  if #id < 2 or #id > 40 then return false, "bad_id" end

  local kind = tostring(d.kind or "race")
  if not KINDS[kind] then return false, "bad_kind" end

  local level = RM.util.tidy(d.level)
  if level == "" then return false, "bad_level" end

  -- replacing a finished layout has to be asked for, not walked into
  if tracks[id] and not d.overwrite then return false, "already_exists" end
  if not tracks[id] and RM.tracks.countTracks() >= RM.config.maxTracks then
    return false, "too_many_tracks"
  end

  local name = RM.util.tidy(d.name)
  drafts[key] = {
    id          = id,
    name        = name ~= "" and name or id,
    kind        = kind,
    level       = level,
    circuit     = d.circuit and true or false,
    checkpoints = {},
    start       = nil,
    createdBy   = key,
    createdAt   = os.time(),
    replaces    = tracks[id] and id or nil,
  }
  RM.store.markDirty(DSTORE)
  RM.info(("%s started capturing %s (%s) on %s"):format(
    RM.identity.displayName(pid), id, kind, level))
  return true, drafts[key]
end

function RM.tracks.mark(pid, d)
  local key = keyOf(pid)
  local draft = key and drafts[key]
  if not draft then return false, "no_draft" end
  if type(d) ~= "table" then return false, "bad_request" end

  local pos = readVec(d.pos)
  if not pos then return false, "bad_pos" end
  if not RM.util.isNum(d.yaw) then return false, "bad_yaw" end

  local n = #draft.checkpoints
  if n >= RM.config.maxCheckpoints then return false, "too_many" end

  -- a held key or a double tap puts two gates on the same spot
  local prev = draft.checkpoints[n]
  if prev then
    local dx, dy = pos.x - prev.pos.x, pos.y - prev.pos.y
    local dz = pos.z - prev.pos.z
    if (dx * dx + dy * dy + dz * dz) < 25 then return false, "too_close" end
  end

  local cp = { i = n + 1, pos = pos, yaw = d.yaw, size = gateFrom(d) }
  draft.checkpoints[cp.i] = cp
  RM.store.markDirty(DSTORE)
  return true, cp
end

function RM.tracks.undo(pid)
  local key = keyOf(pid)
  local draft = key and drafts[key]
  if not draft then return false, "no_draft" end
  local n = #draft.checkpoints
  if n == 0 then return false, "nothing_to_undo" end
  draft.checkpoints[n] = nil
  RM.store.markDirty(DSTORE)
  return true, n - 1
end

-- widen or narrow a gate after the fact. index defaults to the last one, which
-- is what you want while driving the route.
function RM.tracks.setGate(pid, d)
  local key = keyOf(pid)
  local draft = key and drafts[key]
  if not draft then return false, "no_draft" end
  if type(d) ~= "table" then return false, "bad_request" end

  local n = #draft.checkpoints
  local i = tonumber(d.i) or n
  if i < 1 or i > n then return false, "no_such_checkpoint" end

  draft.checkpoints[i].size = gateFrom(d)
  RM.store.markDirty(DSTORE)
  return true, draft.checkpoints[i]
end

function RM.tracks.setStart(pid, d)
  local key = keyOf(pid)
  local draft = key and drafts[key]
  if not draft then return false, "no_draft" end
  local pos = readVec(d and d.pos)
  if not pos then return false, "bad_pos" end
  if not RM.util.isNum(d.yaw) then return false, "bad_yaw" end
  draft.start = { pos = pos, yaw = d.yaw }
  RM.store.markDirty(DSTORE)
  return true, draft.start
end

function RM.tracks.finishCapture(pid)
  local key = keyOf(pid)
  local draft = key and drafts[key]
  if not draft then return false, "no_draft" end
  if #draft.checkpoints < 2 then return false, "need_two_checkpoints" end

  -- the grid sits at the first gate unless it was placed by hand
  if not draft.start then
    draft.start = { pos = draft.checkpoints[1].pos, yaw = draft.checkpoints[1].yaw }
  end

  RM.tracks.squareUp(draft)

  draft.replaces = nil
  draft.savedAt = os.time()
  tracks[draft.id] = draft
  drafts[key] = nil

  RM.store.markDirty(STORE)
  RM.store.markDirty(DSTORE)
  RM.store.flushNow(STORE)
  RM.store.flushNow(DSTORE)
  RM.info(("track %s saved: %d checkpoints on %s"):format(
    draft.id, #draft.checkpoints, draft.level))

  RM.tracks.broadcastList()
  return true, draft
end

function RM.tracks.cancelCapture(pid)
  local key = keyOf(pid)
  if not key or not drafts[key] then return false, "no_draft" end
  drafts[key] = nil
  RM.store.markDirty(DSTORE)
  RM.store.flushNow(DSTORE)
  return true
end

function RM.tracks.draft(pid)
  local key = keyOf(pid)
  return key and drafts[key] or nil
end

function RM.tracks.deleteTrack(pid, id)
  if not RM.roles.atLeast(pid, "admin") then return false, "not_allowed" end
  if type(id) ~= "string" or not tracks[id] then return false, "no_such_track" end
  tracks[id] = nil
  RM.store.markDirty(STORE)
  RM.store.flushNow(STORE)
  RM.info(("track %s deleted by %s"):format(id, RM.identity.displayName(pid)))
  RM.tracks.broadcastList()
  return true
end

function RM.tracks.list() return tracks end

function RM.tracks.get(id) return tracks[id] end

-- the menu only needs the headline. 29 gates times 3 courses is a payload
-- nobody reads, so the checkpoints go out when a course is actually opened.
function RM.tracks.summary()
  local out, n = {}, 0
  for id, t in pairs(tracks) do
    n = n + 1
    out[n] = {
      id = id, name = t.name, kind = t.kind, level = t.level,
      circuit = t.circuit, count = #t.checkpoints,
    }
  end
  return out
end

function RM.tracks.sendList(pid)
  RM.bus.queue(pid, "track.list", RM.tracks.summary())
end

function RM.tracks.broadcastList()
  for pid in pairs(RM.identity.sessions()) do
    RM.tracks.sendList(pid)
  end
end

function RM.tracks.sendTrack(pid, id)
  local t = type(id) == "string" and tracks[id] or nil
  if not t then return false, "no_such_track" end
  RM.bus.queue(pid, "track.full", t)
  return true
end

function RM.tracks.sendDraft(pid)
  local draft = RM.tracks.draft(pid)
  if not draft then return end
  RM.bus.queue(pid, "track.draft", draft)
  RM.info(("%s has an unfinished capture of %s (%d checkpoints)"):format(
    RM.identity.displayName(pid), draft.id, #draft.checkpoints))
end
