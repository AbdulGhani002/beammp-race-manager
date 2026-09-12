-- The store, against a real folder on disk. A saved file that goes empty
-- between restarts used to be a silent fresh start, and every name, level and
-- record on it was gone. This is the copy that stops that.
--
--   lua tools/test_store.lua

local M = dofile("tools/mock/beammp.lua")

local pass, fail = 0, 0
local failures = {}

local function ok(cond, what)
  if cond then pass = pass + 1
  else
    fail = fail + 1
    failures[#failures + 1] = what
    print("  FAIL  " .. what)
  end
end

local function eq(got, want, what)
  ok(got == want, ("%s (got %s, wanted %s)"):format(what, tostring(got), tostring(want)))
end

local function section(t) print("") print("== " .. t) end

os.execute("cmd /c rmdir /s /q Resources 2>nul")
M.loadPlugin()
M.fire("onInit")

local DIR = "Resources/Server/RaceManager/data"

local function pathOf(name) return DIR .. "/" .. name .. ".json" end

local function put(path, body)
  local f = assert(io.open(path, "wb"))
  f:write(body)
  f:close()
end

local function sizeOf(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local n = #f:read("*a")
  f:close()
  return n
end

-- the plugin caches by name, so a reload means dropping the cache
local function reopen(name, default)
  RM.store.forget(name)
  return RM.store.load(name, default)
end

-- ------------------------------------------------------------------ saving

section("a save leaves the copy from before it")
local s = RM.store.load("thing", {})
s.one = "first"
RM.store.markDirty("thing")
ok(RM.store.flushNow("thing"), "the first save works")
eq(FS.Exists(pathOf("thing") .. ".bak"), false,
   "with nothing before it there is no backup yet")

s.one = "second"
RM.store.markDirty("thing")
ok(RM.store.flushNow("thing"), "the second save works")
ok(FS.Exists(pathOf("thing") .. ".bak"),
   "and now the copy from before it is kept, which is the whole fix")

do
  local f = assert(io.open(pathOf("thing") .. ".bak", "rb"))
  local body = f:read("*a")
  f:close()
  ok(body:find("first"), "the backup holds what was there before the save")
  ok(not body:find("second"), "not what the save wrote")
end

section("and it keeps being replaced, so it is never stale")
s.one = "third"
RM.store.markDirty("thing")
RM.store.flushNow("thing")
do
  local f = assert(io.open(pathOf("thing") .. ".bak", "rb"))
  local body = f:read("*a")
  f:close()
  ok(body:find("second"), "the backup is one save behind, not the first one ever")
end

-- --------------------------------------------------------------- recovering

section("a file that goes empty comes back from the backup")
-- exactly what happened on his server: players.json was zero bytes and the
-- server started from nothing
put(pathOf("thing"), "")
eq(sizeOf(pathOf("thing")), 0, "the saved file is empty")

local back = reopen("thing", {})
eq(back.one, "second", "the store came back from the copy beside it")
ok(RM.store.isDirty("thing"), "and is marked to be written out again")
RM.store.flushNow("thing")
eq(reopen("thing", {}).one, "second", "so the saved file is good again after one save")

section("a file that will not decode does the same")
put(pathOf("thing"), "{ this is not json")
local back2 = reopen("thing", {})
eq(back2.one, "second", "the backup is read rather than starting from nothing")

local kept = false
for f in io.popen('cmd /c dir /b "' .. DIR:gsub("/", "\\") .. '" 2>nul'):lines() do
  if f:find("thing%.json%.corrupt%.") then kept = true end
end
ok(kept, "and the file that would not read is kept rather than written over")

section("a missing file with a backup beside it")
RM.store.flushNow("thing")
os.remove(pathOf("thing"))
eq(reopen("thing", {}).one, "second", "the backup still answers")

section("nothing at all is still a fresh store, not a crash")
RM.store.forget("thing")
os.remove(pathOf("thing"))
os.remove(pathOf("thing") .. ".bak")
local fresh = RM.store.load("thing", { made = "new" })
eq(fresh.made, "new", "the default is used")
ok(RM.store.isDirty("thing"), "and it is written on the next save")

section("a full disk cannot rotate a good file out for a short one")
-- io.open is handed a file that swallows writes and lands short, the way a
-- full disk does: the buffer takes the bytes, the flush loses them, and the
-- file on disk is empty. The store has to notice and keep the old copy.
do
  local store = RM.store.load("full-test", {})
  store.kept = "yes"
  ok(RM.store.flushNow("full-test"), "a normal save works")
  local function slurp(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    return body
  end
  local before = slurp(pathOf("full-test"))

  local realOpen = io.open
  io.open = function(path, mode)
    if mode == "wb" and path:find("full%-test%.json%.tmp$") then
      local real = realOpen(path, "wb")
      real:close()
      return {
        write = function() return true end,
        flush = function() return true end,
        close = function() return true end,
      }
    end
    return realOpen(path, mode)
  end
  store.kept = "no, this one is lost"
  RM.store.markDirty("full-test")
  eq(RM.store.flushNow("full-test"), false, "the short save is refused")
  io.open = realOpen
  local after = slurp(pathOf("full-test"))
  eq(after, before, "and the file on disk is the good one from before")
  eq(slurp(pathOf("full-test") .. ".tmp"), nil, "with no short tmp file left behind")
  eq(RM.store.isDirty("full-test"), true, "and the store is still dirty, to try again")

  -- a write the file refuses outright is refused the same way
  io.open = function(path, mode)
    if mode == "wb" and path:find("full%-test%.json%.tmp$") then
      local real = realOpen(path, "wb")
      real:close()
      return {
        write = function() return nil, "No space left on device" end,
        flush = function() return true end,
        close = function() return true end,
      }
    end
    return realOpen(path, mode)
  end
  eq(RM.store.flushNow("full-test"), false, "a write the disk refuses is refused")
  io.open = realOpen
  eq(slurp(pathOf("full-test")), before, "and the good copy is still there")

  -- and it is said, once, not every time
  local said = 0
  local realWarn = RM.warn
  RM.warn = function() said = said + 1 end
  io.open = function(path, mode)
    if mode == "wb" and path:find("full%-test%.json%.tmp$") then
      local real = realOpen(path, "wb") real:close()
      return { write = function() return nil, "No space left on device" end,
               flush = function() return true end, close = function() return true end }
    end
    return realOpen(path, mode)
  end
  for _ = 1, 12 do RM.store.flushDirty() end
  RM.warn = realWarn
  io.open = realOpen
  eq(said, 2, "said on the first failure and the tenth, not twelve times")
  ok(RM.store.flushNow("full-test"), "and it saves once the disk is back")
  RM.store.forget("full-test")
end

section("a broken backup does not take the store down with it")
RM.store.flushNow("thing")
put(pathOf("thing"), "")
put(pathOf("thing") .. ".bak", "also not json")
local last = reopen("thing", { made = "default again" })
eq(last.made, "default again", "it falls all the way back to the default")

print("")
print(("%d passed, %d failed"):format(pass, fail))
for _, f in ipairs(failures) do print("  - " .. f) end
os.exit(fail == 0 and 0 or 1)
