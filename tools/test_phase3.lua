-- Phase 3: the bottom bar. The hold, the penalty and the order the two happen
-- in, all against the mock host so a sixty second wait costs nothing here.
--
--   lua tools/test_phase3.lua

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

-- one driver and a five gate circuit to run on
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
eq(#RM.tracks.get("loop").checkpoints, 5, "a course to run on")

local HOLD = RM.config.holds
local PEN  = RM.config.penalties

local function startRun()
  RM.race.clear(0)
  RM.service.forget(0)
  RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
  M.advance(5)
  RM.race.gate(0, 1, RM.now())
end

local function use(which, extra)
  M.clearOutbox(0)
  local d = { which = which }
  for k, v in pairs(extra or {}) do d[k] = v end
  M.clientSend(0, "service.use", d)
  tick(1)
  return M.lastMessage(0, "service.hold"), M.lastMessage(0, "service.failed")
end

section("outside a run nothing costs anything")
RM.race.clear(0)
RM.service.forget(0)
local hold = use("repair")
ok(hold ~= nil, "the repair is allowed")
eq(hold.hold, 0, "with no hold")
eq(hold.penalty, nil, "and no penalty")

tick(1)
ok(M.lastMessage(0, "service.run") ~= nil, "and the game is told to do it straight away")

section("inside a run it holds you and charges you")
startRun()
local held = use("repair")
ok(held ~= nil, "the repair is allowed")
near(held.hold, HOLD.repair, 0.01, "the hold is the one from the config")
eq(held.penalty, nil, "and no time on top of it: his rule, the hold is the penalty")
eq(RM.service.busy(0), true, "the job is running")

section("nothing lands on the run: the hold is the whole cost")
near(RM.race.penaltyTotal(RM.race.get(0)), 0, 0.01, "no seconds on the run")

section("one job at a time")
local _, refused = use("fuel")
ok(refused ~= nil, "a second button while one is running is refused")
eq(refused.why, "already_working", "and says why")
near(RM.race.penaltyTotal(RM.race.get(0)), 0, 0.01, "the refusal charges nothing either")

section("the hold ends on its own")
M.clearOutbox(0)
M.advance(HOLD.repair - 1)
tick(1)
eq(M.lastMessage(0, "service.run"), nil, "nothing happens a second early")
M.advance(2)
tick(1)
local run = M.lastMessage(0, "service.run")
ok(run ~= nil, "and the game is told to do the job when it is up")
eq(run.which, "repair", "the right job")
eq(RM.service.busy(0), false, "the hold is over")

section("a job the game could not do gives the seconds back")
startRun()
use("repair")
near(RM.race.penaltyTotal(RM.race.get(0)), 0, 0.01, "nothing charged on the way in")
M.advance(HOLD.repair + 1)
tick(1)
M.clearOutbox(0)
M.clientSend(0, "service.done", { which = "repair", ok = false, why = "no_vehicle" })
tick(1)
near(RM.race.penaltyTotal(RM.race.get(0)), 0, 0.01, "and taken back off when it failed")
local told = M.lastMessage(0, "service.failed")
ok(told ~= nil, "the driver is told")
eq(told.why, "no_vehicle", "with the reason the game gave")

section("a job that worked keeps its charge")
startRun()
use("repair")
M.advance(HOLD.repair + 1)
tick(1)
M.clientSend(0, "service.done", { which = "repair", ok = true })
tick(1)
near(RM.race.penaltyTotal(RM.race.get(0)), 0, 0.01, "and still nothing on the run")

section("the spare is only for a flat")
-- the game can burst a tire and cannot mend one, so a spare is the same job as
-- a repair for half the wait. needing a flat is what stops it replacing repair.
startRun()
local _, noFlat = use("spare")
ok(noFlat ~= nil, "asking with nothing flat is refused")
eq(noFlat.why, "no_flat_tire", "and says so")
near(RM.race.penaltyTotal(RM.race.get(0)), 0, 0.01, "and costs nothing")

local withFlat = use("spare", { flat = true })
ok(withFlat ~= nil, "with a flat it is allowed")
eq(withFlat.penalty, nil, "for its hold alone")

-- outside a run there is nothing to check, because there is nothing to charge
RM.race.clear(0)
RM.service.forget(0)
local freeSpare = use("spare")
ok(freeSpare ~= nil, "and free driving needs no flat at all")

section("a spare comes off the rack whether or not a race is on")
-- His test: press it on an empty server and expect to see a tire go on and a
-- spare come off. Outside a run the count is not kept, but the part still
-- goes, or the button looks like it does nothing.
M.clearOutbox(0)
M.clientSend(0, "service.use", { which = "spare", spares = 2 })
tick(1)
local freeRun = M.lastMessage(0, "service.run")
ok(freeRun ~= nil, "free driving runs the job straight away")
eq(freeRun and freeRun.takes, true, "and tells the game to take one off the rack")
M.clientSend(0, "service.done", { which = "spare", ok = true })
tick(1)
eq(RM.service.spares(0), nil, "with no run there is no count to spend")

section("the rack is what limits a spare change")
-- a car carries what it carries: two on a race truck, one on a UTV, none on
-- plenty of things. the client counts what is bolted on and the run is seeded
-- from that the first time the button is pressed.
local function spareRun(spares)
  M.clearOutbox(0)
  M.clientSend(0, "service.use", { which = "spare", flat = true, spares = spares })
  tick(1)
  local hold = M.lastMessage(0, "service.hold")
  local failed = M.lastMessage(0, "service.failed")
  if not hold then return nil, failed end
  M.advance(HOLD.spareTire + 1)
  tick(1)
  M.clientSend(0, "service.done", { which = "spare", ok = true })
  tick(1)
  return hold, nil
end

startRun()
M.clearOutbox(0)
M.clientSend(0, "service.use", { which = "spare", flat = true, spares = 2 })
tick(1)
M.advance(HOLD.spareTire + 1)
tick(1)
local racedRun = M.lastMessage(0, "service.run")
eq(racedRun and racedRun.takes, true, "in a race the job takes one too")
M.clientSend(0, "service.done", { which = "spare", ok = true })
tick(1)
eq(RM.service.spares(0), 1, "a truck with two spares has one left after a change")
spareRun(2)
eq(RM.service.spares(0), 0, "and none after the second")

local _, empty = spareRun(2)
ok(empty ~= nil, "the third is refused")
eq(empty.why, "no_spares_left", "because the rack is empty")

section("what the car says only seeds the count once")
startRun()
spareRun(1)
eq(RM.service.spares(0), 0, "one spare, one change")
local _, gone = spareRun(9)
ok(gone ~= nil, "claiming nine later does not refill it")
eq(gone.why, "no_spares_left", "the rack is still empty")

section("a car with no rack gets no change at all")
startRun()
local _, none = spareRun(0)
ok(none ~= nil, "nothing on the rack, nothing to fit")
eq(none.why, "no_spares_left", "and says so")

section("a spare the game could not fit costs nothing off the rack")
startRun()
M.clientSend(0, "service.use", { which = "spare", flat = true, spares = 2 })
tick(1)
M.advance(HOLD.spareTire + 1)
tick(1)
M.clientSend(0, "service.done", { which = "spare", ok = false, why = "swap_failed" })
tick(1)
eq(RM.service.spares(0), 2, "the rack is untouched when the job failed")
near(RM.race.penaltyTotal(RM.race.get(0)), 0, 0.01, "and the seconds come back")

section("re-racking is a pit job and fills it again")
startRun()
spareRun(2)
spareRun(2)
eq(RM.service.spares(0), 0, "run dry")

local _, notInPit = use("rerack", { spares = 2 })
ok(notInPit ~= nil, "out on the course it is refused")
eq(notInPit.why, "pit_only", "because it belongs in the pit")

RM.race.setPit(0, true)
local racked = use("rerack", { spares = 2 })
ok(racked ~= nil, "in the pit it is allowed")
eq(racked.penalty, nil, "and costs nothing on the clock")
eq(RM.service.spares(0), 2, "the rack is full again")
M.advance(HOLD.rerack + 1)
tick(1)
M.clientSend(0, "service.done", { which = "rerack", ok = true })
tick(1)
eq(RM.service.spares(0), 2, "and re-racking is not itself a spare change")
RM.race.setPit(0, false)

-- fuel became a pit job on 2026-09-14, his rule: a tank filled out on the
-- course is a shortcut round the pit lane
section("fuel is a pit job, and in the pit it waits but costs nothing")
startRun()
local _, dryOut = use("fuel")
ok(dryOut ~= nil, "out on the course it is refused")
eq(dryOut.why, "pit_only", "because it belongs in the pit")
RM.race.setPit(0, true)
local fuel = use("fuel")
ok(fuel ~= nil, "in the pit it is allowed")
near(fuel.hold, HOLD.fuel, 0.01, "it has a hold")
eq(fuel.penalty, nil, "and no penalty")
near(RM.race.penaltyTotal(RM.race.get(0)), 0, 0.01, "nothing is added to the run")
RM.race.setPit(0, false)

section("reposition")
startRun()
local rep = use("reposition")
ok(rep ~= nil, "reposition is allowed")
near(rep.hold, HOLD.reposition, 0.01, "with the short hold")
near(rep.penalty, PEN.recovery, 0.01, "and the recovery penalty")

section("a button nobody has heard of")
startRun()
local _, nope = use("teleport")
ok(nope ~= nil, "an unknown action is refused")
eq(nope.why, "no_such_action", "and named as such")

section("a run that ends does not leave a car held")
startRun()
use("repair")
eq(RM.service.busy(0), true, "a hold is running")
M.clientSend(0, "race.end", {})
tick(1)
eq(RM.service.busy(0), false, "ending the run clears it")

section("and neither does leaving")
startRun()
use("repair")
eq(RM.service.busy(0), true, "a hold is running")
M.fire("onPlayerDisconnect", 0)
eq(RM.service.busy(0), false, "the hold goes with the player")
eq(RM.service.count(), 0, "and nothing is left behind")

section("the results still add up with a service penalty in them")
M.addPlayer(0, "Driver", "5001", false, "203.0.113.1")
M.fire("onPlayerJoining", 0)
M.clientSend(0, "hello", { version = RM.VERSION })
M.clientSend(0, "name.set", { name = "Driver" })
RM.race.clear(0)
RM.service.forget(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
M.advance(5)
RM.race.gate(0, 1, RM.now())
use("reposition")
M.advance(HOLD.reposition)
tick(1)
M.clientSend(0, "service.done", { which = "reposition", ok = true })
for g = 2, 5 do M.advance(10) RM.race.gate(0, g, RM.now()) end
M.advance(10)
RM.race.gate(0, 1, RM.now())

local r = RM.race.get(0)
eq(r.state, "finished", "the run finishes")
eq(#r.penalties, 1, "one penalty on it")
eq(r.penalties[1].reason, "recovery", "and it is the recovery, the one service that still costs time")
near(r.corrected - r.clean, PEN.recovery, 0.01, "corrected carries it")

local res = RM.race.results(0)
ok(res ~= nil, "results are built")
eq(#res.penalties, 1, "with the penalty listed by reason, not hidden in the total")

print("")
print(("%d passed, %d failed"):format(pass, fail))
for _, f in ipairs(failures) do print("  - " .. f) end
os.exit(fail == 0 and 0 or 1)
