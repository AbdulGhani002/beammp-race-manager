-- The BeamMP server empties its own ServerConfig.toml when it starts on a
-- full disk, and the next start has no AuthKey. The plugin keeps a copy of
-- the last good file and puts it back. Run against files under the test
-- data folder, never the real one.
--
--   lua tools/test_serverconfig.lua

package.path = "./?.lua;" .. package.path
local M = dofile("tools/mock/beammp.lua")
M.loadPlugin()

local pass, fail = 0, 0
local function ok(cond, what)
  if cond then pass = pass + 1 else fail = fail + 1 print("  FAIL  " .. what) end
end
local function eq(got, want, what)
  ok(got == want, ("%s (got %s, wanted %s)"):format(what, tostring(got), tostring(want)))
end
local function section(t) print("") print("== " .. t) end

local DIR = "Resources/Server/RaceManager/data"
FS.CreateDirectory("Resources") FS.CreateDirectory("Resources/Server")
FS.CreateDirectory("Resources/Server/RaceManager") FS.CreateDirectory(DIR)
local FILE = DIR .. "/_test_ServerConfig.toml"
local COPY = DIR .. "/_test_ServerConfig.toml.bak"
RM.serverconfig.FILE, RM.serverconfig.COPY = FILE, COPY
for _, p in ipairs({ FILE, COPY, FILE .. ".tmp", COPY .. ".tmp" }) do os.remove(p) end

local function put(path, body)
  local f = assert(io.open(path, "wb")) f:write(body) f:close()
end
local function get(path)
  local f = io.open(path, "rb") if not f then return nil end
  local b = f:read("*a") f:close() return b
end
local function errorsSaid() return #M.logs.error + #M.logs.warn end

local GOOD = [[
[General]
Name = "Abdul Dev - Race Manager"
Port = 30199
AuthKey = "not-a-real-key-just-long-enough-to-look-like-one"
Map = "/levels/2026_bap_camsmaps/info.json"
MaxPlayers = 10
]]

section("no such file is not our business")
eq(RM.serverconfig.check(), "absent", "left alone")
eq(get(COPY), nil, "and no copy is made of nothing")

section("a healthy file is copied, and the copy follows every change")
put(FILE, GOOD)
eq(RM.serverconfig.check(), "ok", "healthy")
eq(get(COPY), GOOD, "copied")
eq(get(COPY .. ".bak"), nil, "with no copy of the copy")
local changed = GOOD:gsub("MaxPlayers = 10", "MaxPlayers = 12")
put(FILE, changed)
eq(RM.serverconfig.check(), "ok", "still healthy")
eq(get(COPY), changed, "and the copy is the new one")

section("emptied on a full disk, it is put back from the copy, and said once")
put(FILE, "")
local before = errorsSaid()
eq(RM.serverconfig.check(), "restored", "put back")
eq(get(FILE), changed, "the whole file, key and map and all")
eq(errorsSaid(), before + 1, "said once")
eq(RM.serverconfig.check(), "ok", "healthy again")
eq(errorsSaid(), before + 1, "and nothing more is said")

section("a minute later is when it looks again")
put(FILE, "")
RM.serverconfig.tick(30)
eq(get(FILE), "", "half a minute in it has not looked")
RM.serverconfig.tick(30)
eq(get(FILE), changed, "at the minute it has")

section("empty with nothing to put back is said, once")
os.remove(COPY)
put(FILE, "")
RM.serverconfig.reset()
before = errorsSaid()
eq(RM.serverconfig.check(), "nocopy", "nothing to put back")
eq(errorsSaid(), before + 1, "said")
eq(RM.serverconfig.check(), "nocopy", "still nothing")
eq(errorsSaid(), before + 1, "not said again")
eq(get(FILE), "", "and the empty file is left as it is, not made up")

section("a config typed in with the key still to come is left alone, said once, and not kept as the copy")
put(COPY, GOOD)
put(FILE, GOOD:gsub('AuthKey = "[^"]*"', 'AuthKey = ""'))
RM.serverconfig.reset()
before = errorsSaid()
eq(RM.serverconfig.check(), "nokey", "no key")
eq(errorsSaid(), before + 1, "said")
ok(get(FILE):find('AuthKey = ""', 1, true) ~= nil, "the file is left for the key to be put in")
eq(get(COPY), GOOD, "and the copy is still the good one")
eq(RM.serverconfig.check(), "nokey", "still no key")
eq(errorsSaid(), before + 1, "not said again")
put(FILE, GOOD)
eq(RM.serverconfig.check(), "ok", "the key put in, it is healthy")

section("a short file is an empty one: a key and a map are never this short")
put(COPY, GOOD)
put(FILE, "[General]\n")
eq(RM.serverconfig.check(), "restored", "put back")
eq(get(FILE), GOOD, "from the copy")

for _, p in ipairs({ FILE, COPY, FILE .. ".tmp", COPY .. ".tmp", FILE .. ".bak" }) do os.remove(p) end
print("")
print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
