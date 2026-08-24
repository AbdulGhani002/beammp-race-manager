-- Phase 2 against the mock host. The clock is driven by hand, so a run plays
-- through in a test without waiting for real seconds and the timing can be
-- checked to the millisecond.
--
--   lua54 tools/test_phase2.lua

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
  "06_players", "07_tracks", "08_console", "09_clock", "10_race", "99_main",
}

os.execute("cmd /c rmdir /s /q Resources 2>nul")
for _, n in ipairs(FILES) do dofile("server/RaceManager/" .. n .. ".lua") end

local function tick(n) for _ = 1, (n or 1) do M.fire("rm:tick") end end

M.fire("onInit")

-- one owner, and a five gate circuit 100m apart
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
eq(#RM.tracks.get("loop").checkpoints, 5, "a five gate circuit to race on")

section("the clock has to agree before a stamp is worth anything")
-- server at 100, client 30 seconds ahead, 200ms round trip
M.advance(100)
local t1 = RM.now()
M.advance(0.1)
RM.clock.onPong(0, { t1 = t1, t2 = t1 + 30 + 0.1, t3 = t1 + 30 + 0.1 })
M.advance(0.1)
local info = RM.clock.info(0)
ok(info and info.samples == 1, "a probe reply is kept")
near(info and info.offset, 30, 0.15, "and the offset is about the real difference")

local conv, trusted = RM.clock.toServer(0, RM.now() + 30)
ok(trusted, "a stamp inside the window is trusted")
near(conv, RM.now(), 0.3, "and lands about now in server time")

local _, bad = RM.clock.toServer(0, RM.now() + 30 + 60)
eq(bad, false, "a stamp from the future is not")
local _, old = RM.clock.toServer(0, RM.now() + 30 - 60)
eq(old, false, "and neither is one from too far back")

section("arming")
eq(select(2, RM.race.arm(0, { id = "nope", mode = "wheel", laps = 1 })), "no_such_track",
   "cannot arm on a course that does not exist")
eq(select(2, RM.race.arm(0, { id = "loop", mode = "hovercraft", laps = 1 })), "bad_mode",
   "controller or wheel, nothing else")
eq(select(2, RM.race.arm(0, { id = "loop", mode = "wheel", laps = 0 })), "bad_laps",
   "a run is at least one lap")

ok(RM.race.arm(0, { id = "loop", mode = "wheel", laps = 2 }), "armed for two laps")
eq(RM.race.state(0), "armed", "and the state says so")

section("a clean two lap run")
local function cross(gate, after)
  M.advance(after or 10)
  return RM.race.gate(0, gate, RM.now() + 30)
end

eq(select(2, RM.race.gate(0, 3, RM.now() + 30)), "not_the_start",
   "the run only starts at the line")

local okStart, first = cross(1, 5)
ok(okStart and first.started, "crossing the line starts the run")
eq(RM.race.state(0), "running", "and it is running")

for g = 2, 5 do cross(g, 10) end
local okLap, lap = cross(1, 10)
ok(okLap and lap.lapDone, "coming back through the line completes the lap")
eq(lap.lap, 2, "and the second lap has begun")
near(lap.split, 50, 0.2, "the lap took fifty seconds")

for g = 2, 5 do cross(g, 10) end
local okEnd, done = cross(1, 10)
ok(okEnd and done.finished, "the last lap finishes the run")
eq(RM.race.state(0), "finished", "state is finished")

local r = RM.race.get(0)
near(r.clean, 100, 0.3, "two fifty second laps is a hundred seconds")
eq(r.corrected, r.clean, "with no penalties, corrected equals clean")
eq(r.suspect, false, "and nothing about it looked wrong")

section("a cut corner is caught and priced")
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
cross(1, 5)
cross(2, 10)
-- straight to 5, skipping 3 and 4
local okSkip, skipped = cross(5, 10)
ok(okSkip, "a later gate still registers")
eq(skipped.missed, 2, "and says how many were skipped")

local r2 = RM.race.get(0)
eq(#r2.missed[1], 2, "both missing gates are recorded")
eq(r2.missed[1][1], 3, "the first one by number")
eq(r2.missed[1][2], 4, "and the second")
eq(#r2.penalties, 2, "one penalty each")
eq(r2.penalties[1].reason, "missed_gate", "with a reason that can be argued with")
eq(r2.penalties[1].gate, 3, "against the gate it belongs to")
near(RM.race.penaltyTotal(r2), 60, 0.01, "two thirty second penalties")

cross(1, 10)
local done2 = RM.race.get(0)
eq(done2.state, "finished", "the run still finishes")
near(done2.corrected - done2.clean, 60, 0.01, "corrected carries the penalties")

section("the same gate twice, and going backwards")
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
cross(1, 5)
cross(2, 10)
eq(select(2, cross(2, 10)), "already_crossed", "crossing the same gate again is ignored")
eq(select(2, cross(1, 10)), "already_crossed", "and so is going backwards")
eq(#RM.race.get(0).penalties, 0, "neither counts as a miss")

section("a stamp that says the car did the impossible")
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
cross(1, 5)
-- 100 metres in a hundredth of a second is about 22000 mph
M.advance(0.01)
RM.race.gate(0, 2, RM.now() + 30)
eq(RM.race.get(0).suspect, true, "the run is marked")
ok(RM.race.get(0).splits[1][2] ~= false, "but the split is still taken, not dropped")

section("a stamp the clock cannot vouch for")
RM.race.clear(0)
M.addPlayer(1, "Stranger", "5002", false, "203.0.113.9")
M.fire("onPlayerJoining", 1)
M.clientSend(1, "hello", { version = RM.VERSION })
M.clientSend(1, "name.set", { name = "Stranger" })
RM.race.arm(1, { id = "loop", mode = "controller", laps = 1 })
-- never exchanged a probe, so there is no offset to convert with
M.advance(5)
RM.race.gate(1, 1, RM.now())
eq(RM.race.get(1).suspect, true, "with no agreed clock the run is marked")
eq(RM.race.state(1), "running", "but it still runs, nobody is thrown off")
RM.race.clear(1)

section("ending a run")
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
cross(1, 5)
cross(2, 10)
ok(RM.race.endRace(0), "End Race stops it")
eq(RM.race.state(0), "abandoned", "the run is abandoned")
eq(select(2, cross(3, 10)), "not_running", "and nothing counts after that")

section("leaving mid run")
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
cross(1, 5)
M.fire("onPlayerDisconnect", 0)
eq(RM.race.get(0), nil, "the run is gone with the player")

section("results")
M.addPlayer(0, "Driver", "5001", false, "203.0.113.1")
M.fire("onPlayerJoining", 0)
M.clientSend(0, "hello", { version = RM.VERSION })
RM.clock.onPong(0, { t1 = RM.now(), t2 = RM.now() + 30, t3 = RM.now() + 30 })
RM.race.arm(0, { id = "loop", mode = "wheel", laps = 1 })
cross(1, 5)
for g = 2, 5 do cross(g, 10) end
cross(1, 10)

local res = RM.race.results(0)
ok(res ~= nil, "a finished run produces results")
eq(res.name, "Driver", "with the display name")
eq(res.mode, "wheel", "and the mode it was run in")
eq(#res.laps, 1, "one lap")
near(res.laps[1].time, 50, 0.3, "timed at fifty seconds")
eq(res.laps[1].splits[3] ~= false, true, "every gate has a split")
eq(RM.race.results(1), nil, "an unfinished run has no results")

section("nothing is allocated once the car is moving")
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 10 })
collectgarbage()
local before = collectgarbage("count")
cross(1, 5)
for lap = 1, 10 do
  for g = 2, 5 do cross(g, 2) end
  cross(1, 2)
end
local grew = collectgarbage("count") - before
ok(grew < 40, ("ten laps of fifty gates grew the heap by under 40KB (grew %.1f)"):format(grew))
eq(RM.race.state(0), "finished", "and the run finished properly")

section("a lap is measured to the line")
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 3 })
cross(1, 5)
for lap = 1, 3 do
  for g = 2, 5 do cross(g, 10) end
  cross(1, 10)
end
local three = RM.race.results(0)
eq(#three.laps, 3, "three laps recorded")
near(three.laps[1].time, 50, 0.2, "first lap fifty seconds")
near(three.laps[2].time, 50, 0.2, "second the same")
near(three.laps[3].time, 50, 0.2, "and the third")
near(three.clean, 150, 0.3, "so the run is a hundred and fifty")

section("ten drivers at once")
-- the load test that needs no second human. gate count is what scales, so
-- this is what phase 4 will actually look like.
for pid = 10, 19 do
  M.addPlayer(pid, "sim" .. pid, tostring(6000 + pid), false, "198.51.100." .. pid)
  M.fire("onPlayerJoining", pid)
  M.clientSend(pid, "hello", { version = RM.VERSION })
  RM.clock.onPong(pid, { t1 = RM.now(), t2 = RM.now(), t3 = RM.now() })
  RM.race.arm(pid, { id = "loop", mode = "controller", laps = 2 })
end
eq(RM.race.count() >= 10, true, "ten runs armed at once")

collectgarbage()
local heapBefore = collectgarbage("count")
for pid = 10, 19 do RM.race.gate(pid, 1, RM.now()) end
for lap = 1, 2 do
  for g = 2, 5 do
    M.advance(2)
    for pid = 10, 19 do RM.race.gate(pid, g, RM.now()) end
  end
  M.advance(2)
  for pid = 10, 19 do RM.race.gate(pid, 1, RM.now()) end
end
local heapAfter = collectgarbage("count")

local finished = 0
for pid = 10, 19 do
  if RM.race.state(pid) == "finished" then finished = finished + 1 end
end
eq(finished, 10, "all ten finished")
ok(heapAfter - heapBefore < 120,
   ("a hundred crossings across ten drivers grew the heap by under 120KB (grew %.1f)")
   :format(heapAfter - heapBefore))

tick(5)
eq(RM.util.handlerErrorCount(), 0, "no handler raised across any of it")
eq(RM.bus.stats().dropped, 0, "and nothing was dropped from the outbound queue")

for pid = 10, 19 do
  M.fire("onPlayerDisconnect", pid)
  M.removePlayer(pid)
end

section("a rewritten client cannot invent a time")
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
cross(1, 5)
M.advance(10)
-- claiming the crossing happened an hour ago
RM.race.gate(0, 2, RM.now() + 30 - 3600)
eq(RM.race.get(0).suspect, true, "a stamp far outside the window marks the run")
local sp = RM.race.get(0).splits[1][2]
ok(sp and sp > 0 and sp < 60, "and the split falls back to something sane")

RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
cross(1, 5)
eq(select(2, RM.race.gate(0, 99, RM.now() + 30)), "no_such_gate", "a gate that does not exist")
eq(select(2, RM.race.gate(0, -1, RM.now() + 30)), "no_such_gate", "and a negative one")
ok(RM.race.gate(0, 2, "not a number"), "a junk stamp still records, marked")
eq(RM.race.get(0).suspect, true, "and marks the run")

print("")
print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then
  for _, f in ipairs(failures) do print("  - " .. f) end
  os.exit(1)
end
