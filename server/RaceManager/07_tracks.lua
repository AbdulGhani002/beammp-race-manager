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
