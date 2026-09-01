RM = RM or {}
RM.records = {}

-- The books. Per course and per mode: every driver's best corrected run, and
-- the fastest clean lap anyone has driven. A run the server marked as suspect
-- never makes the books, and cut laps were already refused a best lap before
-- the results get here.

local STORE = "records"
local KEEP  = 10

local data = nil

local function load()
  if not data then data = RM.store.load(STORE, { tracks = {} }) end
  return data
end

local function boardFor(trackId, mode)
  local d = load()
  d.tracks[trackId] = d.tracks[trackId] or {}
  local t = d.tracks[trackId]
  t[mode] = t[mode] or { runs = {} }
  return t[mode]
end

-- one finished run. returns what it improved so the results screen can put a
-- badge on the row, or nil when the books did not move.
function RM.records.submit(trackId, e, at)
  if type(e) ~= "table" or e.suspect then return nil end
  if not RM.util.isNum(e.corrected) or not e.key then return nil end

  local b = boardFor(tostring(trackId), tostring(e.mode or "controller"))
  local when = at or os.time()
  local got = {}

  local mine
  for i = 1, #b.runs do
    if b.runs[i].key == e.key then mine = i break end
  end

  local run = {
    key       = e.key,
    name      = e.name,
    corrected = e.corrected,
    clean     = e.clean,
    laps      = type(e.laps) == "table" and #e.laps or 0,
    at        = when,
  }

  if not mine then
    b.runs[#b.runs + 1] = run
    got.personal = true
  elseif e.corrected < b.runs[mine].corrected then
    b.runs[mine] = run
    got.personal = true
  end

  table.sort(b.runs, function(x, y) return x.corrected < y.corrected end)

  -- a personal best that lands on top of the pile is the course record
  if got.personal and b.runs[1].key == e.key then
    got.track = true
  end

  if e.bestLap and RM.util.isNum(e.bestLap.time) then
    if not b.lap or e.bestLap.time < b.lap.time then
      b.lap = { time = e.bestLap.time, name = e.name, key = e.key, at = when }
      got.lap = true
    end
  end

  if not (got.personal or got.lap) then return nil end

  RM.store.markDirty(STORE)
  RM.store.flushNow(STORE)
  return got
end

-- what the records panel shows: the top of each board, the lap record, and
-- where the asker sits when they are not on the part that is sent
function RM.records.wire(trackId, key)
  local d = load()
  local out = { id = tostring(trackId or ""), modes = {} }
  local t = d.tracks[out.id]
  if not t then return out end

  for mode, b in pairs(t) do
    local rows = {}
    for i = 1, math.min(#b.runs, KEEP) do
      local r = b.runs[i]
      rows[i] = { pos = i, name = r.name, corrected = r.corrected,
                  laps = r.laps, at = r.at, me = (r.key == key) or nil }
    end

    local mine
    if key then
      for i = 1, #b.runs do
        if b.runs[i].key == key then
          mine = { pos = i, corrected = b.runs[i].corrected }
          break
        end
      end
    end

    out.modes[mode] = {
      top   = rows,
      total = #b.runs,
      lap   = b.lap and { time = b.lap.time, name = b.lap.name, at = b.lap.at } or nil,
      mine  = mine,
    }
  end
  return out
end

function RM.records.count()
  local d = load()
  local n = 0
  for _ in pairs(d.tracks) do n = n + 1 end
  return n
end
