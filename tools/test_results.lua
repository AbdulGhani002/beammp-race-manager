-- The heat and the results payload, against the mock host. Three drivers on
-- one course, driven through the bus rather than by calling the race module
-- directly, so the wiring is under test as well as the arithmetic.
--
--   lua54 tools/test_results.lua

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

local FILES = {
  "00_config", "01_util", "02_store", "03_bus", "04_identity", "05_roles",
  "06_players", "07_tracks", "08_console", "09_clock", "10_race", "11_results", "12_racelog",
  "99_main",
}

os.execute("cmd /c rmdir /s /q Resources 2>nul")
for _, n in ipairs(FILES) do dofile("server/RaceManager/" .. n .. ".lua") end

local function tick(n) for _ = 1, (n or 1) do M.fire("rm:tick") end end

M.fire("onInit")

-- three drivers, each with their own clock error, because the whole point is
-- that whose clock is wrong should not decide who wins
local DRIVERS = {
  { pid = 0, name = "Alfa",    ip = "203.0.113.1", offset = 30 },
  { pid = 1, name = "Bravo",   ip = "203.0.113.2", offset = -12 },
  { pid = 2, name = "Charlie", ip = "203.0.113.3", offset = 5000 },
}

for _, d in ipairs(DRIVERS) do
  M.addPlayer(d.pid, d.name, "500" .. d.pid, false, d.ip)
  M.fire("onPlayerJoining", d.pid)
  M.clientSend(d.pid, "hello", { version = RM.VERSION })
  M.clientSend(d.pid, "name.set", { name = d.name })
end
tick(1)

RM.console.handle("rm role Alfa owner")

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
eq(#RM.tracks.get("loop").checkpoints, 5, "a five gate circuit to race on")

-- every driver agrees with the server, each from a different starting error
local function agreeClock(d)
  local t1 = RM.now()
  RM.clock.onPong(d.pid, { t1 = t1, t2 = t1 + d.offset, t3 = t1 + d.offset })
end
for _, d in ipairs(DRIVERS) do agreeClock(d) end

local function crossAfter(d, gate, after)
  M.advance(after)
  agreeClock(d)
  M.clientSend(d.pid, "cp.hit", { i = gate, t = RM.now() + d.offset })
  tick(1)
end

section("arming through the bus")
for _, d in ipairs(DRIVERS) do
  M.clearOutbox(d.pid)
  M.clientSend(d.pid, "race.arm", { id = "loop", mode = "controller", laps = 1 })
end
tick(1)

for _, d in ipairs(DRIVERS) do
  local st = M.lastMessage(d.pid, "race.state")
  ok(st and st.state == "armed", d.name .. " is armed")
end
local tp = M.lastMessage(0, "race.teleport")
ok(tp and tp.pos, "and gets put on the grid")

section("a driver still on track is not waiting on anybody")
-- Alfa has started but not finished. waitingOn counts every live run on the
-- course, this one included, so reporting it here told a driver racing alone
-- that they were waiting on themselves while their own clock was running.
crossAfter(DRIVERS[1], 1, 5)
do
  local w = RM.race.wire(DRIVERS[1].pid)
  eq(w.state, "running", "Alfa is on the road")
  eq(w.waiting, nil, "so is told nothing about waiting")
  ok(RM.results.waitingOn("loop") ~= nil, "even though the heat does have cars out")
end

section("results wait for the last car")
-- Alfa: gates ten seconds apart, but quick from four to five
crossAfter(DRIVERS[1], 2, 10)
crossAfter(DRIVERS[1], 3, 10)
crossAfter(DRIVERS[1], 4, 10)
crossAfter(DRIVERS[1], 5, 6)
crossAfter(DRIVERS[1], 1, 10)

eq(RM.race.state(0), "finished", "Alfa is in")
ok(M.lastMessage(0, "race.results") == nil, "and gets nothing yet, two are still out")
local waiting = M.lastMessage(0, "race.waiting")
eq(waiting and waiting.left, 2, "just how many are being waited on")
eq(RM.results.waitingOn("loop"), 2, "which is what the heat says too")

-- Bravo: five seconds a gate slower overall
crossAfter(DRIVERS[2], 1, 5)
for g = 2, 5 do crossAfter(DRIVERS[2], g, 11) end
crossAfter(DRIVERS[2], 1, 11)

eq(RM.race.state(1), "finished", "Bravo is in")
ok(M.lastMessage(0, "race.results") == nil, "still nothing, one is out")
eq(RM.results.waitingOn("loop"), 1, "the heat is down to one")

-- Charlie: quickest on the road, but cuts gate three
crossAfter(DRIVERS[3], 1, 5)
crossAfter(DRIVERS[3], 2, 9)
crossAfter(DRIVERS[3], 4, 9)
crossAfter(DRIVERS[3], 5, 9)
crossAfter(DRIVERS[3], 1, 9)

eq(RM.race.state(2), "finished", "Charlie is in")

section("the payload")
local res = M.lastMessage(0, "race.results")
ok(res ~= nil, "results land the moment the last car is off track")
ok(M.lastMessage(1, "race.results") ~= nil, "everybody in the heat gets them")
ok(M.lastMessage(2, "race.results") ~= nil, "including the one who came in last")
eq(RM.results.waitingOn("loop"), nil, "and the heat is closed")

eq(res.track, "loop", "for the right course")
eq(res.gates, 5, "carrying the gate count")
eq(#res.finished, 3, "three finishers")
eq(#res.dnf, 0, "nobody out")

section("a cut is priced, and the order is by corrected time")
local byName = {}
for _, e in ipairs(res.finished) do byName[e.name] = e end

near(byName.Alfa.clean, 46, 0.3, "Alfa ran a 46")
near(byName.Bravo.clean, 55, 0.3, "Bravo ran a 55")
near(byName.Charlie.clean, 36, 0.3, "Charlie was quickest on the road at 36")

eq(#byName.Charlie.penalties, 1, "but cut one gate")
eq(byName.Charlie.penalties[1].reason, "missed_gate", "and it is named as that")
eq(byName.Charlie.penalties[1].gate, 3, "against gate three")
near(byName.Charlie.corrected, 66, 0.3, "which puts him at 66 corrected")

eq(res.finished[1].name, "Alfa", "so Alfa wins on corrected time")
eq(res.finished[2].name, "Bravo", "Bravo second")
eq(res.finished[3].name, "Charlie", "and the quickest car is last")
eq(res.finished[1].pos, 1, "positions are numbered")

section("the gaps people actually read")
eq(res.finished[1].toLeader, 0, "the leader is level with themselves")
eq(res.finished[1].toAhead, 0, "and has nobody ahead")
near(res.finished[2].toLeader, 9, 0.5, "Bravo is nine off the lead")
near(res.finished[2].toAhead, 9, 0.5, "and nine off the car ahead, which is the leader")
near(res.finished[3].toLeader, 20, 0.6, "Charlie is twenty off the lead")
near(res.finished[3].toAhead, 11, 0.5, "but only eleven off the car ahead")

section("best lap, overall and personal")
ok(res.bestLap ~= nil, "there is an overall best lap")
eq(res.bestLap.name, "Alfa", "and it is the quickest clean lap, not the quickest lap")
near(res.bestLap.time, 46, 0.3, "at 46")
eq(byName.Charlie.bestLap, nil, "Charlie's 36 cut a gate, so it holds no record")
ok(byName.Charlie.laps[1].time > 0, "it is still timed and still shown")
near(byName.Alfa.bestLap.time, 46, 0.3, "Alfa's own best is their only lap")
eq(byName.Alfa.bestLap.lap, 1, "on lap one")

section("sectors are worked out from the absolute splits")
local lap = byName.Alfa.laps[1]
ok(lap.sectors ~= nil, "a lap carries its sectors")
near(lap.sectors[2], 10, 0.2, "gate one to two took ten")
near(lap.sectors[5], 6, 0.2, "four to five was the quick one at six")
near(lap.sectors[6], 10, 0.2, "and the run back to the line is a sector too")
near(byName.Alfa.bestSector.time, 6, 0.2, "so the personal best sector is the six")
eq(byName.Alfa.bestSector.gate, 5, "at gate five")

section("a missed gate leaves a hole rather than a wrong number")
local cl = byName.Charlie.laps[1]
eq(cl.splits[3], false, "the cut gate has no split")
eq(cl.sectors[3], false, "so there is no sector into it")
eq(cl.sectors[4], false, "and none out of it either")
eq(cl.sectors[2] ~= false, true, "the sectors around the hole are still there")
eq(cl.sectors[5] ~= false, true, "on both sides of it")
eq(#cl.missed, 1, "the miss is recorded once")
eq(cl.missed[1], 3, "by gate number")

section("closing the results lets go of the run")
for _, d in ipairs(DRIVERS) do M.clientSend(d.pid, "race.clear", {}) end
tick(1)
eq(RM.race.get(0), nil, "the run is released")
eq(RM.race.state(0), "idle", "and the state is idle again")
eq(RM.results.count(), 0, "no heat is left open")

section("somebody who leaves does not hold up the rest")
for _, d in ipairs(DRIVERS) do
  M.clearOutbox(d.pid)
  M.clientSend(d.pid, "race.arm", { id = "loop", mode = "controller", laps = 1 })
end
tick(1)
crossAfter(DRIVERS[1], 1, 5)
for g = 2, 5 do crossAfter(DRIVERS[1], g, 10) end
crossAfter(DRIVERS[1], 1, 10)
eq(RM.results.waitingOn("loop"), 2, "two still out")

crossAfter(DRIVERS[2], 1, 5)
for g = 2, 5 do crossAfter(DRIVERS[2], g, 10) end
crossAfter(DRIVERS[2], 1, 10)
eq(RM.results.waitingOn("loop"), 1, "one still out")

M.fire("onPlayerDisconnect", 2)
tick(1)
local res2 = M.lastMessage(0, "race.results")
ok(res2 ~= nil, "the results go out when the last one disconnects")
eq(#res2.finished, 2, "two finishers")
eq(#res2.dnf, 1, "and one who did not")
eq(res2.dnf[1].name, "Charlie", "named")
ok(type(res2.dnf[1].why) == "string" and res2.dnf[1].why ~= "", "with a reason")

section("End Race is a did not finish, not a nothing")
M.clientSend(0, "race.clear", {})
M.clientSend(1, "race.clear", {})
tick(1)

M.addPlayer(2, "Charlie", "5002", false, "203.0.113.3")
M.fire("onPlayerJoining", 2)
M.clientSend(2, "hello", { version = RM.VERSION })
tick(1)
agreeClock(DRIVERS[3])

M.clearOutbox(0)
M.clientSend(0, "race.arm", { id = "loop", mode = "controller", laps = 1 })
M.clientSend(2, "race.arm", { id = "loop", mode = "controller", laps = 1 })
tick(1)
crossAfter(DRIVERS[1], 1, 5)
for g = 2, 5 do crossAfter(DRIVERS[1], g, 10) end
crossAfter(DRIVERS[1], 1, 10)

crossAfter(DRIVERS[3], 1, 5)
crossAfter(DRIVERS[3], 2, 10)
M.clientSend(2, "race.end", {})
tick(1)

local res3 = M.lastMessage(0, "race.results")
ok(res3 ~= nil, "ending a run closes the heat")
eq(#res3.finished, 1, "one finisher")
eq(#res3.dnf, 1, "and one who pulled out")

section("a run nobody finishes is swept up")
M.clientSend(0, "race.clear", {})
M.clientSend(2, "race.clear", {})
tick(1)

M.clientSend(0, "race.arm", { id = "loop", mode = "controller", laps = 1 })
tick(1)
crossAfter(DRIVERS[1], 1, 5)
eq(RM.race.state(0), "running", "on track")

M.advance(RM.config.raceIdleTimeoutMs / 1000 + 10)
tick(20)
eq(RM.race.state(0), "idle", "and gone after the idle timeout")

section("arming somewhere else leaves the first heat behind")
M.clientSend(0, "race.clear", {})
tick(1)

M.clientSend(0, "track.begin",
  { id = "second", name = "Second", kind = "race", level = "utah_sc", circuit = true })
tick(1)
for i = 1, 3 do
  M.advance(1)
  M.clientSend(0, "track.mark", { pos = { x = i * 100, y = 500, z = 0 }, yaw = 0 })
  tick(1)
end
M.clientSend(0, "track.finish")
tick(1)

M.clientSend(0, "race.arm", { id = "loop", mode = "controller", laps = 1 })
M.clientSend(1, "race.arm", { id = "loop", mode = "controller", laps = 1 })
tick(1)
eq(RM.results.waitingOn("loop"), 2, "two entered on the first course")

-- Alfa changes their mind before starting and enters the other course
M.clientSend(0, "race.arm", { id = "second", mode = "controller", laps = 1 })
tick(1)
eq(RM.results.waitingOn("loop"), 1, "the first heat is only waiting on the one still in it")

M.clearOutbox(1)
crossAfter(DRIVERS[2], 1, 5)
for g = 2, 5 do crossAfter(DRIVERS[2], g, 10) end
crossAfter(DRIVERS[2], 1, 10)
local lone = M.lastMessage(1, "race.results")
ok(lone ~= nil, "so it closes rather than waiting on somebody who left it")
eq(#lone.finished, 1, "with the one driver who actually ran it")

M.clientSend(0, "race.end", {})
M.clientSend(0, "race.clear", {})
M.clientSend(1, "race.clear", {})
tick(1)

section("one lonely driver still gets a results screen")
M.clearOutbox(0)
M.clientSend(0, "race.arm", { id = "loop", mode = "controller", laps = 1 })
tick(1)
crossAfter(DRIVERS[1], 1, 5)
for g = 2, 5 do crossAfter(DRIVERS[1], g, 10) end
crossAfter(DRIVERS[1], 1, 10)

local solo = M.lastMessage(0, "race.results")
ok(solo ~= nil, "results arrive with nobody else on the course")
eq(#solo.finished, 1, "one finisher")
eq(solo.finished[1].toLeader, 0, "who is their own leader")

section("every finished race leaves one line on disk for their bot")
-- read the file back rather than trust the writer: the shape is a promise to
-- something outside this project
do
  local f = io.open("Resources/Server/RaceManager/data/results.jsonl", "rb")
  ok(f ~= nil, "the log exists once a race has finished")

  local lines = {}
  if f then
    for l in f:lines() do if l ~= "" then lines[#lines + 1] = l end end
    f:close()
  end
  ok(#lines >= 1, "with a line in it")

  local rec = lines[1] and Util.JsonDecode(lines[1])
  ok(type(rec) == "table", "and the line is json a bot can read")
  eq(rec.v, 1, "carrying a schema version, so it can be changed later safely")
  eq(rec.track, "loop", "the course it was run on")
  ok(type(rec.at) == "number" and rec.at > 0, "and when")
  eq(#rec.finished, 3, "everybody who finished")

  local first = rec.finished[1]
  eq(first.pos, 1, "in finishing order")
  eq(first.name, "Alfa", "by name")
  near(first.correctedTotal, 46, 0.3, "with the total corrected time he asked for")
  near(first.rawTotal, 46, 0.3, "the time on the road as well")
  eq(first.penaltySeconds, 0, "a clean run carries no seconds")
  eq(first.penaltyCount, 0, "and no count")

  local cut
  for _, d in ipairs(rec.finished) do if d.name == "Charlie" then cut = d end end
  ok(cut ~= nil, "and the driver who cut a gate is in there")
  near(cut.correctedTotal, 66, 0.3, "with the penalty already inside the total")
  near(cut.rawTotal, 36, 0.3, "and the raw time kept separate")
  eq(cut.penaltySeconds, 30, "the seconds the cut cost")
  eq(cut.penaltyCount, 1, "from one penalty")
  eq(cut.bestLap, nil, "a cut lap still holds no record here either")

  ok(RM.racelog.stats().written >= 1, "and the plugin counts what it wrote")
end

print("")
if fail == 0 then
  print(("%d passed, 0 failed"):format(pass))
else
  print(("%d passed, %d FAILED"):format(pass, fail))
  for _, f in ipairs(failures) do print("  - " .. f) end
  os.exit(1)
end
