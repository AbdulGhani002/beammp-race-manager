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

-- Which class a car belongs to. His document wants the books sorted by class
-- as well as by controller or wheel. The class list is the one thing the plan
-- asked him for at phase 5 and it has not arrived, so until it does every car
-- sits in one book together and nothing on screen changes. Fill in
-- RM.config.classes and the books split themselves, including runs already on
-- disk, because the car is stored with the run rather than the class.
local ALL = "all"

function RM.records.classOf(vehicle)
  local list = RM.config.classes
  if type(list) ~= "table" or not vehicle then return ALL end
  for className, cars in pairs(list) do
    if type(cars) == "table" then
      for i = 1, #cars do
        if cars[i] == vehicle then return className end
      end
    end
  end
  return ALL
end

-- every class the books on this course have anything in, so the screen only
-- offers a choice when there is one to make
function RM.records.classesOn(trackId)
  local d = load()
  local t = d.tracks[tostring(trackId or "")]
  local seen, out = {}, {}
  if not t then return out end
  for _, b in pairs(t) do
    for i = 1, #b.runs do
      local c = RM.records.classOf(b.runs[i].vehicle)
      if not seen[c] then seen[c] = true; out[#out + 1] = c end
    end
  end
  table.sort(out)
  return out
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
    vehicle   = e.vehicle,
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
function RM.records.wire(trackId, key, class)
  local d = load()
  local out = { id = tostring(trackId or ""), modes = {},
                classes = RM.records.classesOn(trackId) }
  local t = d.tracks[out.id]
  if not t then return out end

  local want = class and tostring(class) or nil
  if want == ALL then want = nil end
  out.class = want

  for mode, b in pairs(t) do
    -- filtered first, then placed, so positions read 1, 2, 3 inside the class
    -- rather than keeping the gaps left by the cars that were filtered out
    local kept = {}
    for i = 1, #b.runs do
      local r = b.runs[i]
      if not want or RM.records.classOf(r.vehicle) == want then
        kept[#kept + 1] = r
      end
    end

    local rows = {}
    for i = 1, math.min(#kept, KEEP) do
      local r = kept[i]
      rows[i] = { pos = i, name = r.name, corrected = r.corrected,
                  laps = r.laps, at = r.at, vehicle = r.vehicle,
                  me = (r.key == key) or nil }
    end

    local mine
    if key then
      for i = 1, #kept do
        if kept[i].key == key then
          mine = { pos = i, corrected = kept[i].corrected }
          break
        end
      end
    end

    out.modes[mode] = {
      top   = rows,
      total = #kept,
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
