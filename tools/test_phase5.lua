-- Phase 5: the record books. Best run per driver per course and mode, the
-- fastest clean lap, and the badges the results screen hangs on a fresh one.
--
--   lua tools/test_phase5.lua

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

local function near(got, want, tol, what)
  ok(type(got) == "number" and math.abs(got - want) <= tol,
     ("%s (got %s, wanted %s +/- %s)"):format(what, tostring(got), tostring(want), tostring(tol)))
end

local function section(t) print("") print("== " .. t) end

os.execute("cmd /c rmdir /s /q Resources 2>nul")
M.loadPlugin()

local function tick(n) for _ = 1, (n or 1) do M.fire("rm:tick") end end

M.fire("onInit")

M.addPlayer(0, "Driver", "5001", false, "203.0.113.1")
M.fire("onPlayerJoining", 0)
M.clientSend(0, "hello", { version = RM.VERSION })
M.clientSend(0, "name.set", { name = "Driver" })
RM.console.handle("rm role Driver owner")

M.clientSend(0, "track.begin",
  { id = "loop", name = "Loop", kind = "race", level = "utah_sc", circuit = true })
tick(1)
for i = 1, 5 do
  M.advance(1)
  M.clientSend(0, "track.mark", { pos = { x = i * 100, y = 0, z = 0 }, yaw = 0 })
  tick(1)
end
M.clientSend(0, "track.finish")
tick(1)

-- the direct road first, because the sums are easier to argue with alone
section("a finished run opens the books")
local entry = {
  key = "beammp:5001", name = "Driver", mode = "controller",
  corrected = 100, clean = 100, laps = { {} }, suspect = false,
  bestLap = { time = 100, lap = 1 },
}
local got = RM.records.submit("loop", entry)
ok(got and got.personal, "the first run is a personal best")
ok(got and got.track, "and the course record, there being nobody else")
ok(got and got.lap, "and the lap record")

section("a better run replaces it and a worse one does not")
got = RM.records.submit("loop", { key = "beammp:5001", name = "Driver",
  mode = "controller", corrected = 90, clean = 90, laps = { {} },
  bestLap = { time = 90, lap = 1 } })
ok(got and got.personal and got.track and got.lap, "faster takes everything")

got = RM.records.submit("loop", { key = "beammp:5001", name = "Driver",
  mode = "controller", corrected = 95, clean = 95, laps = { {} },
  bestLap = { time = 95, lap = 1 } })
eq(got, nil, "slower moves nothing and says so")

local w = RM.records.wire("loop", "beammp:5001")
near(w.modes.controller.top[1].corrected, 90, 0.001, "the board keeps the faster one")
eq(w.modes.controller.total, 1, "one driver, one row")
near(w.modes.controller.lap.time, 90, 0.001, "the lap record stands")

section("a second driver takes the top and the first keeps a row")
got = RM.records.submit("loop", { key = "beammp:5002", name = "Rival",
  mode = "controller", corrected = 80, clean = 80, laps = { {} },
  bestLap = { time = 80, lap = 1 } })
ok(got and got.track, "the rival takes the course record")

w = RM.records.wire("loop", "beammp:5001")
eq(w.modes.controller.total, 2, "two drivers on the board")
eq(w.modes.controller.top[1].name, "Rival", "fastest first")
eq(w.modes.controller.top[2].name, "Driver", "the other row survives")
ok(w.modes.controller.top[2].me, "and the asker's row says it is theirs")
eq(w.modes.controller.mine.pos, 2, "mine says where the asker sits")

section("a personal best that is not the record wears the right badge")
got = RM.records.submit("loop", { key = "beammp:5001", name = "Driver",
  mode = "controller", corrected = 85, clean = 85, laps = { {} } })
ok(got and got.personal, "it is a personal best")
ok(not got.track, "but not the course record, the rival is faster")

section("modes are separate books")
got = RM.records.submit("loop", { key = "beammp:5001", name = "Driver",
  mode = "wheel", corrected = 200, clean = 200, laps = { {} },
  bestLap = { time = 200, lap = 1 } })
ok(got and got.track, "a slow wheel run still opens the wheel book")
w = RM.records.wire("loop")
eq(w.modes.wheel.total, 1, "one wheel row")
eq(w.modes.controller.total, 2, "and the controller book did not move")

section("a marked run never makes the books")
got = RM.records.submit("loop", { key = "beammp:5003", name = "Cheat",
  mode = "controller", corrected = 1, clean = 1, laps = { {} }, suspect = true,
  bestLap = { time = 1, lap = 1 } })
eq(got, nil, "refused")
w = RM.records.wire("loop")
eq(w.modes.controller.top[1].name, "Rival", "the board is unmoved")

section("the whole road: a real race lands in the books with its badge")
RM.clock.onPong(0, { t1 = RM.now(), t2 = RM.now() + 30, t3 = RM.now() + 30 })
M.clientSend(0, "race.arm", { id = "loop", mode = "controller", laps = 1 })
tick(1)
local function cross(gate, after)
  M.advance(after)
  M.clientSend(0, "cp.hit", { i = gate, t = RM.now() + 30 })
  tick(1)
end
cross(1, 5)
for g = 2, 5 do cross(g, 10) end
cross(1, 10)
tick(2)

local results = M.lastMessage(0, "race.results")
ok(results ~= nil, "the results arrive")
local row = results and results.finished and results.finished[1]
ok(row ~= nil, "with a row on them")
eq(row and row.record, "track", "fifty seconds beats the rival's eighty, so it is the course record")

w = RM.records.wire("loop", "beammp:5001")
eq(w.modes.controller.top[1].name, "Driver", "and the books moved with it")
near(w.modes.controller.top[1].corrected, 50, 0.5, "at the new time")

section("the books survive a restart")
local f = io.open("Resources/Server/RaceManager/data/records.json", "rb")
ok(f ~= nil, "the store is on disk")
if f then
  local body = f:read("*a")
  f:close()
  ok(body:find("Rival") ~= nil, "with the rival in it")
end

section("the channel answers")
M.clearOutbox(0)
M.clientSend(0, "records.get", { id = "loop" })
tick(1)
local d = M.lastMessage(0, "records.data")
ok(d ~= nil, "records.data comes back")
eq(d and d.id, "loop", "for the course that was asked about")
ok(d and d.modes and d.modes.controller, "with the controller book in it")

print("")
print(("%d passed, %d failed"):format(pass, fail))
for _, f2 in ipairs(failures) do print("  - " .. f2) end
os.exit(fail == 0 and 0 or 1)
