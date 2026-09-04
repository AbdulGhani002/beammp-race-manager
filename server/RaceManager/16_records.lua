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

-- Classes. He sent the list on 2026-09-04 and it lives in config.
--
-- A class is entered rather than worked out. He allows every vehicle, and two
-- drivers in the same truck can be running different classes, so the car
-- cannot tell you which book a run belongs in. The driver says when they arm
-- and the run carries it from there.
--
-- The car is still stored with the run, so a class that later gets a cars
-- list can also be recognised from the vehicle. That is what classOf is for,
-- and it is what makes runs already on disk sortable the day he wants it.
local ALL = "all"

-- the list in his order, divisions kept, so the picker reads the way his
-- announcements do
function RM.records.classList()
  local list = RM.config.classes
  if type(list) ~= "table" then return {} end
  local out = {}
  for i = 1, #list do
    local c = list[i]
    if type(c) == "table" and type(c.name) == "string" and c.name ~= "" then
      out[#out + 1] = { name = c.name, division = c.division }
    end
  end
  return out
end

-- the name back if it is really one of his, nil if it is not. everything that
-- takes a class from a client goes through here first.
function RM.records.isClass(name)
  if type(name) ~= "string" or name == "" or name == ALL then return nil end
  local list = RM.config.classes
  if type(list) ~= "table" then return nil end
  for i = 1, #list do
    if type(list[i]) == "table" and list[i].name == name then return list[i].name end
  end
  return nil
end

-- Which cars a class is open to. Empty or missing means anybody, which is
-- every class today because he allows every vehicle for now.
function RM.records.carsFor(name)
  local list = RM.config.classes
  if type(list) ~= "table" then return nil end
  for i = 1, #list do
    local c = list[i]
    if type(c) == "table" and c.name == name then
      if type(c.cars) == "table" and #c.cars > 0 then return c.cars end
      return nil
    end
  end
  return nil
end

function RM.records.carAllowed(className, vehicle)
  local cars = RM.records.carsFor(className)
  if not cars then return true end
  if not vehicle then return false end
  for i = 1, #cars do
    if cars[i] == vehicle then return true end
  end
  return false
end

function RM.records.classOf(vehicle)
  local list = RM.config.classes
  if type(list) ~= "table" or not vehicle then return ALL end
  for i = 1, #list do
    local c = list[i]
    if type(c) == "table" and type(c.cars) == "table" then
      for j = 1, #c.cars do
        if c.cars[j] == vehicle then return c.name end
      end
    end
  end
  return ALL
end

-- What book one run belongs in: what the driver entered, or failing that what
-- the car says, or the one book everybody shares.
function RM.records.classFor(run)
  if type(run) ~= "table" then return ALL end
  local entered = RM.records.isClass(run.class)
  if entered then return entered end
  return RM.records.classOf(run.vehicle)
end

-- every class the books on this course have anything in, so the screen only
-- offers a choice when there is one to make. kept in his order, with anything
-- unentered last.
function RM.records.classesOn(trackId)
  local d = load()
  local t = d.tracks[tostring(trackId or "")]
  local seen, out = {}, {}
  if not t then return out end
  for _, b in pairs(t) do
    for i = 1, #b.runs do
      seen[RM.records.classFor(b.runs[i])] = true
    end
  end
  -- a run nobody entered in a class is not a class, it just lives on the
  -- board everybody shares
  seen[ALL] = nil
  local list = RM.records.classList()
  for i = 1, #list do
    if seen[list[i].name] then
      out[#out + 1] = list[i].name
      seen[list[i].name] = nil
    end
  end
  local rest = {}
  for name in pairs(seen) do rest[#rest + 1] = name end
  table.sort(rest)
  for i = 1, #rest do out[#out + 1] = rest[i] end
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
  local class = RM.records.isClass(e.class)

  -- Your best is kept once per class, not once per course. A Trophy Truck and
  -- a Class 11 car are not the same lap, so a slower run in a second class is
  -- still that class's first entry rather than a run that failed to beat you.
  local mine
  for i = 1, #b.runs do
    if b.runs[i].key == e.key and RM.records.classFor(b.runs[i]) == (class or ALL) then
      mine = i
      break
    end
  end

  local run = {
    key       = e.key,
    name      = e.name,
    corrected = e.corrected,
    clean     = e.clean,
    laps      = type(e.laps) == "table" and #e.laps or 0,
    vehicle   = e.vehicle,
    class     = class,
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

  -- and on top of its own class it is that class's record, which is the one
  -- most people are actually racing for
  if got.personal and class then
    for i = 1, #b.runs do
      if RM.records.classFor(b.runs[i]) == class then
        if b.runs[i].key == e.key then got.class = class end
        break
      end
    end
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
      if not want or RM.records.classFor(r) == want then
        kept[#kept + 1] = r
      end
    end

    local rows = {}
    for i = 1, math.min(#kept, KEEP) do
      local r = kept[i]
      local ran = RM.records.classFor(r)
      rows[i] = { pos = i, name = r.name, corrected = r.corrected,
                  laps = r.laps, at = r.at, vehicle = r.vehicle,
                  class = ran ~= ALL and ran or nil,
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
