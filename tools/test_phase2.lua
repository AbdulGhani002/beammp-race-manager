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
  "06_players", "07_tracks", "08_console", "09_clock", "10_race", "11_results", "12_racelog",
  "99_main",
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

section("cutting the gates at the end of a lap still finishes it")
-- The run that found this missed gate 5 and then crossed the line. The line
-- was read as gate 1 arriving out of turn and thrown away, so nothing ever
-- finished the run: the clock kept going and the only way out was to quit.
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
cross(1, 5)
cross(2, 10)
cross(3, 10)
cross(4, 10)
-- gate 5 is cut, and the next thing the car crosses is the line
local okLine = cross(1, 10)
ok(okLine, "the line closes the lap even though a gate was cut")
eq(RM.race.state(0), "finished", "so the run actually ends")

local run = RM.race.get(0)
eq(#run.penalties, 1, "the cut gate is priced once")
eq(run.penalties[1].gate, 5, "and it is named as gate five")
eq(run.penalties[1].reason, "missed_gate", "for the right reason")
near(run.clean, 40, 0.2, "the time on the road is 40")
near(run.corrected, 40 + RM.config.penalties.missedGate, 0.2,
     "and the time that counts carries the penalty")
ok(run.corrected > run.clean, "which is the whole point: a cut costs time")

section("the clock on screen carries the penalty too")
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
cross(1, 5)
eq(RM.race.wire(0).penaltyTime, 0, "nothing added yet")
cross(3, 10)
do
  local w = RM.race.wire(0)
  eq(w.penalties, 1, "one gate cut")
  near(w.penaltyTime, RM.config.penalties.missedGate, 0.001,
       "and the seconds go out with it, so the clock can show what it cost")
end

section("crossing the line straight back off the grid is not a lap")
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
cross(1, 5)
eq(select(2, cross(1, 2)), "already_crossed",
   "reversing over the start line does not finish a lap and cut four gates")
eq(RM.race.state(0), "running", "the run is still going")

section("the seconds reach the screen, not just the count")
-- The clock carried the count and never the seconds, so 36 cuts sat on screen
-- next to a time that had not moved. The server had it right the whole way:
-- clean 188.962, corrected 1268.962. Only the driver could not see it.
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
cross(1, 5)
local afterCut = select(2, cross(3, 10))
eq(afterCut.penalties, 1, "the split says one gate was cut")
near(afterCut.penaltyTime, RM.config.penalties.missedGate, 0.001,
     "and says what it cost, in the same message")
near(RM.race.wire(0).penaltyTime, RM.config.penalties.missedGate, 0.001,
     "the run state agrees")

section("a run keeps its own copy of the clock offset")
-- The offset between the two clocks is re-estimated every few seconds and the
-- estimate moves. Reading the start of a run in one frame and the end of it in
-- another measures the drift as much as the driving: the log has a seven
-- second run coming back as a 213 second lap, and a lap boundary that made the
-- clock on screen count backwards.
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
cross(1, 5)
local frozen = RM.race.get(0).offset
near(frozen, 30, 0.2, "the run took the offset that was current when it began")

-- the estimate slides two seconds part way round, as it did in the log
RM.identity.session(0).clockOffset = 32
cross(2, 10)
near(RM.race.get(0).splits[1][2], 10, 0.2,
     "the split is still the ten seconds that passed, not the drift")
near(RM.race.get(0).offset, 30, 0.2, "because the run kept its own copy")

cross(3, 10)
near(RM.race.get(0).splits[1][3], 20, 0.2, "and it holds for the rest of the run")

section("a gate too far up the course was brushed, not driven through")
-- baja-1000 puts gate 30 between gates 3 and 4. Driving that stretch clipped
-- it and charged 26 cuts for gates that were still in front of the car. Five
-- gates is not enough course to skip 26 of anything, so the cap is tightened
-- for this section rather than the course being made thirty gates long.
local realCap = RM.config.maxGateSkip
RM.config.maxGateSkip = 1

RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
cross(1, 5)
cross(2, 10)
eq(select(2, cross(5, 10)), "not_this_gate",
   "a gate well past the one expected is a volume brushed in passing")
eq(#RM.race.get(0).penalties, 0, "so nothing is charged for it")
eq(RM.race.get(0).nextGate, 3, "and the run stays where it was")
ok(RM.race.gate(0, 3, RM.now() + 30), "the gate actually in front still counts")

section("but being genuinely that far down the course is not ignored forever")
-- Refusing every far gate meant a run that skipped more than the cap could
-- never take another gate, never finish, and had to be quit. One stray volume
-- fires once; being down there fires gate after gate.
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
cross(1, 5)
eq(select(2, cross(4, 10)), "not_this_gate", "the first far gate is still refused")
eq(RM.race.get(0).nextGate, 2, "and the run has not moved")
ok(cross(5, 12), "the next one in order says it was real")
eq(RM.race.get(0).nextGate, 6, "so the run picks up there, with only the line left")
eq(#RM.race.get(0).penalties, 3, "and gates two to four are charged as cut")

-- one brushed volume on its own still never counts, however many times
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
cross(1, 5)
eq(select(2, cross(4, 10)), "not_this_gate", "a stray gate is refused")
eq(select(2, cross(4, 12)), "not_this_gate", "and the same one again is still refused")
eq(#RM.race.get(0).penalties, 0, "nothing is charged for either")

RM.config.maxGateSkip = realCap
ok(realCap >= 2, "and the real cap still leaves room for a cut corner")

section("a cut gate reached late gets its penalty back")
-- two of these gates are fourteen metres apart and twenty wide, so they can
-- fire in either order
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
cross(1, 5)
cross(2, 10)
cross(4, 10)
eq(#RM.race.get(0).penalties, 1, "gate three is charged as cut")
local back = select(2, cross(3, 1))
ok(back and back.refunded, "then gate three fires late")
eq(#RM.race.get(0).penalties, 0, "and the charge comes off")
near(RM.race.get(0).splits[1][3] or -1, 21, 2, "its split is recorded")
eq(select(2, cross(3, 1)), "already_crossed", "but only once")

section("gates can be refitted to the road without driving the course again")
-- The width is worked out in the game, because the navigation graph that knows
-- how wide a road is lives there. The server only stores what comes back.
do
  local before = RM.tracks.get("loop").checkpoints[1].size.w
  eq(before, 20, "captured at the old fixed width")

  local okFit, res = RM.tracks.refit(0, { id = "loop", widths = { 12.5, 31, 9, 44, 18 } })
  ok(okFit, "an owner may refit a saved course")
  eq(res.changed, 5, "every gate moved")

  local cps = RM.tracks.get("loop").checkpoints
  near(cps[1].size.w, 12.5, 0.01, "a narrow stretch gets a narrow gate")
  near(cps[4].size.w, 44, 0.01, "and a wide one gets a wide gate")
  near(cps[1].size.h, 8, 0.01, "height is left alone")
  near(cps[1].size.d, 3, 0.01, "and so is depth")

  -- when a gate finds no road the table arrives with holes in it, and json
  -- turns a table with holes into one with string keys
  local okSparse = RM.tracks.refit(0, { id = "loop", widths = { ["1"] = 14, ["4"] = 26 } })
  ok(okSparse, "a refit that only found some of the gates still works")
  near(RM.tracks.get("loop").checkpoints[1].size.w, 14, 0.01, "the ones it found are set")
  near(RM.tracks.get("loop").checkpoints[4].size.w, 26, 0.01, "including out of order")
  near(RM.tracks.get("loop").checkpoints[2].size.w, 31, 0.01, "and the rest are left alone")

  eq(select(2, RM.tracks.refit(0, { id = "nope", widths = { 10 } })), "no_such_track",
     "a course that does not exist is refused")
  eq(select(2, RM.tracks.refit(0, { id = "loop" })), "bad_request",
     "and so is a refit with no widths in it")

  -- a width outside what a gate can be is clamped rather than stored
  RM.tracks.refit(0, { id = "loop", widths = { 9999 } })
  ok(RM.tracks.get("loop").checkpoints[1].size.w <= 200,
     "an absurd width is clamped, not written straight through")
end

print("")
print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then
  for _, f in ipairs(failures) do print("  - " .. f) end
  os.exit(1)
end
