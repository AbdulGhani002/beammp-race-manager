-- Phase 6 against the mock host: watching another driver, the challenge
-- board, and the switch that turns XP and challenge tracking off.
--
--   lua tools/test_phase6.lua

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

-- the calendar the challenges run on, under the test's control
local wall = 1000000
RM.challenges.clock = function() return wall end

local DRIVERS = {
  { pid = 0, name = "Alfa",  ip = "203.0.113.1" },
  { pid = 1, name = "Bravo", ip = "203.0.113.2" },
  { pid = 2, name = "Colt",  ip = "203.0.113.3" },
}
for _, d in ipairs(DRIVERS) do
  M.addPlayer(d.pid, d.name, "600" .. d.pid, false, d.ip)
  M.fire("onPlayerJoining", d.pid)
  M.clientSend(d.pid, "hello", { version = RM.VERSION })
  M.clientSend(d.pid, "name.set", { name = d.name })
end
tick(1)
RM.console.handle("rm role Alfa owner")

-- everybody in a car the server can see
for _, d in ipairs(DRIVERS) do
  M.fire("onVehicleSpawn", d.pid, 1, ('pickup:%d-1:{"jbm":"pickup"}'):format(d.pid))
end

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
eq(#RM.tracks.get("loop").checkpoints, 5, "a five gate circuit")

local function agreeClock(pid)
  local t1 = RM.now()
  RM.clock.onPong(pid, { t1 = t1, t2 = t1, t3 = t1 })
end
for _, d in ipairs(DRIVERS) do agreeClock(d.pid) end

local function cross(pid, gate, after)
  M.advance(after)
  agreeClock(pid)
  M.clientSend(pid, "cp.hit", { i = gate, t = RM.now() })
  tick(1)
end

local function state(pid) return M.lastMessage(pid, "copilot.state") end

-- =========================================================== watching
section("a driver invites somebody to watch, and they accept")
M.clearOutbox(0) M.clearOutbox(1)
M.clientSend(0, "copilot.offer", { to = 1, kind = "invite" })
tick(1)
local st = state(1)
ok(st and st.offer and st.offer.kind == "invite", "Bravo is told of the invite")
eq(st and st.offer and st.offer.from, "Alfa", "and who it is from")
M.clientSend(1, "copilot.accept", {})
tick(1)
local watch = M.lastMessage(1, "copilot.watch")
ok(watch ~= nil, "Bravo is told where to look")
eq(watch and watch.pid, 0, "at Alfa")
eq(watch and watch.vid, 1, "in Alfa's car")
eq(watch and watch.name, "Alfa", "by name")
eq(state(1).watching and state(1).watching.name, "Alfa", "Bravo's screen says who")
eq(#state(0).watchers, 1, "Alfa's screen says one watcher")
eq(state(0).watchers[1], "Bravo", "by name")
eq(RM.copilot.count(), 1, "the server counts one")

section("the driver's car changing points the watcher at the new one")
M.clearOutbox(1)
M.fire("onVehicleSpawn", 0, 2, 'racetruck:0-2:{"jbm":"racetruck"}')
tick(1)
local again = M.lastMessage(1, "copilot.watch")
eq(again and again.vid, 2, "the new car")

section("a watcher cannot be asked to watch somebody else meanwhile")
M.clearOutbox(2)
M.clientSend(2, "copilot.offer", { to = 1, kind = "invite" })
tick(1)
eq((M.lastMessage(2, "copilot.failed") or {}).why, "they_are_watching", "Colt is told Bravo is busy")

section("stopping puts the watcher back in their own car")
M.clearOutbox(1) M.clearOutbox(0)
M.clientSend(1, "copilot.stop", {})
tick(1)
ok(M.lastMessage(1, "copilot.release") ~= nil, "Bravo is released")
eq(state(1).watching, nil, "and watches nobody")
eq(#state(0).watchers, 0, "Alfa has no watchers")

section("asking to watch works the other way round, and no is no")
M.clearOutbox(0)
M.clientSend(2, "copilot.offer", { to = 0, kind = "request" })
tick(1)
st = state(0)
ok(st and st.offer and st.offer.kind == "request", "Alfa is asked")
eq(st.offer.from, "Colt", "by Colt")
M.clearOutbox(2)
M.clientSend(0, "copilot.decline", {})
tick(1)
eq((M.lastMessage(2, "copilot.gone") or {}).why, "declined", "Colt hears the no")
eq(state(0).offer, nil, "and the offer is gone")

section("a request accepted makes the asker the watcher")
M.clientSend(2, "copilot.offer", { to = 0, kind = "request" })
tick(1)
M.clearOutbox(2)
M.clientSend(0, "copilot.accept", {})
tick(1)
eq((M.lastMessage(2, "copilot.watch") or {}).pid, 0, "Colt now watches Alfa")

section("the driver can send every watcher home")
M.clearOutbox(2)
M.clientSend(0, "copilot.stop", {})
tick(1)
eq((M.lastMessage(2, "copilot.release") or {}).why, "driver ended it", "Colt is sent back")
eq(RM.copilot.count(), 0, "nobody watches anybody")

section("arming a run ends watching, since your own car is the one that races")
M.clientSend(2, "copilot.offer", { to = 0, kind = "request" })
tick(1)
M.clientSend(0, "copilot.accept", {})
tick(1)
eq(RM.copilot.count(), 1, "Colt is watching")
M.clearOutbox(2)
M.clientSend(2, "race.arm", { id = "loop", mode = "controller", laps = 1 })
tick(1)
eq((M.lastMessage(2, "copilot.release") or {}).why, "you armed a run", "and is released on arming")
eq(RM.copilot.count(), 0, "nobody watching")
M.clientSend(2, "race.end", {})
tick(1)

section("somebody mid run cannot be made a watcher")
M.clientSend(1, "race.arm", { id = "loop", mode = "controller", laps = 1 })
tick(1)
M.clearOutbox(0)
M.clientSend(0, "copilot.offer", { to = 1, kind = "invite" })
tick(1)
eq((M.lastMessage(0, "copilot.failed") or {}).why, "they_are_racing", "Alfa is told Bravo is racing")
M.clearOutbox(1)
M.clientSend(1, "copilot.offer", { to = 0, kind = "request" })
tick(1)
eq((M.lastMessage(1, "copilot.failed") or {}).why, "you_are_racing", "Bravo is told to finish first")
M.clientSend(1, "race.end", {})
tick(1)

section("the driver leaving sends the watcher home")
M.clientSend(0, "copilot.offer", { to = 1, kind = "invite" })
tick(1)
M.clientSend(1, "copilot.accept", {})
tick(1)
eq(RM.copilot.count(), 1, "Bravo watches Alfa")
M.clearOutbox(1)
M.fire("onPlayerDisconnect", 0)
tick(1)
eq((M.lastMessage(1, "copilot.release") or {}).why, "the driver left", "Bravo is released")
eq(RM.copilot.count(), 0, "nobody watching")
-- Alfa comes back
M.addPlayer(0, "Alfa", "6000", false, "203.0.113.1")
M.fire("onPlayerJoining", 0)
M.clientSend(0, "hello", { version = RM.VERSION })
tick(1)
M.fire("onVehicleSpawn", 0, 1, 'pickup:0-1:{"jbm":"pickup"}')
eq(RM.identity.displayName(0), "Alfa", "and is Alfa again")

section("an offer nobody answers goes away on its own")
M.clientSend(0, "copilot.offer", { to = 1, kind = "invite" })
tick(1)
ok(state(1).offer ~= nil, "offered")
M.advance(61)
tick(5)
eq(state(1).offer, nil, "and gone a minute later")

-- =========================================================== challenges
section("an admin posts a daily challenge with a ladder of times")
M.clearOutbox(0)
M.clientSend(0, "challenge.create", {
  name = "Morning loop", kind = "daily", track = "loop", laps = 1,
  tiers = { { time = 60, xp = 100 }, { time = 70, xp = 75 }, { time = 80, xp = 50 } },
})
tick(1)
local made = M.lastMessage(0, "challenge.result")
eq(made and made.ok, true, "it is made")
eq(made and made.id, "morning-loop", "with an id from its name")
local board = M.lastMessage(1, "challenges.list")
ok(board and #board == 1, "everybody gets the board")
eq(board[1].state, "live", "and it is live")
eq(board[1].kind, "daily", "daily")
near(board[1].secondsLeft, 86400, 1, "for a day")
eq(board[1].tiers[1].time, 60, "fastest rung first")
eq(board[1].tiers[3].xp, 50, "slowest rung last")

section("a description rides along, and too long a one is refused")
M.clientSend(0, "challenge.update", { id = "morning-loop", description = "  Three laps of the short loop, trucks welcome.  " })
tick(1)
eq(RM.challenges.get("morning-loop").description, "Three laps of the short loop, trucks welcome.", "kept, tidied")
eq(M.lastMessage(1, "challenges.list")[1].description, "Three laps of the short loop, trucks welcome.", "and on the board")
M.clearOutbox(0)
M.clientSend(0, "challenge.update", { id = "morning-loop", description = string.rep("x", 301) })
tick(1)
eq((M.lastMessage(0, "challenge.result") or {}).reason, "description_too_long", "three hundred letters is the most")
M.clientSend(0, "challenge.update", { id = "morning-loop", description = "" })
tick(1)
eq(RM.challenges.get("morning-loop").description, nil, "and an empty one is none")

section("a player who is not an admin cannot post one")
M.clearOutbox(1)
M.clientSend(1, "challenge.create", { name = "Nope", kind = "daily", track = "loop", laps = 1,
  tiers = { { time = 60, xp = 10 } } })
tick(1)
eq((M.lastMessage(1, "challenge.result") or {}).reason, "not_allowed", "refused")

section("a run on the challenge is scored on the ladder and paid")
M.clientSend(1, "race.arm", { id = "loop", mode = "controller", laps = 1, challenge = "morning-loop" })
tick(1)
eq((M.lastMessage(1, "race.state") or {}).challenge, "morning-loop", "the run knows its challenge")
local before = RM.xp.of(RM.identity.session(1).key)
cross(1, 1, 5)
cross(1, 2, 13)
cross(1, 3, 13)
cross(1, 4, 13)
cross(1, 5, 13)
cross(1, 1, 13)
local res = M.lastMessage(1, "race.results")
ok(res ~= nil, "results come")
local mine = res and res.finished and res.finished[1]
ok(mine and mine.challengeResult, "with the challenge outcome on the row")
eq(mine and mine.challengeResult.tier, 2, "sixty five seconds is the second rung")
eq(mine and mine.challengeResult.xp, 75, "worth seventy five")
eq(mine and mine.challengeResult.gained, 75, "all of it paid, first time on it")
local after = RM.xp.of(RM.identity.session(1).key)
eq(after - before, 75 + mine.xp, "paid on top of the finish")
board = M.lastMessage(1, "challenges.list")
eq(board[1].mine and board[1].mine.tier, 2, "the board shows the rung")
eq(board[1].top[1].name, "Bravo", "and the top of the board")

section("a faster run pays only the difference, a slower one nothing")
before = RM.xp.of(RM.identity.session(1).key)
M.clientSend(1, "race.arm", { id = "loop", mode = "controller", laps = 1, challenge = "morning-loop" })
tick(1)
cross(1, 1, 5)
for g = 2, 5 do cross(1, g, 11) end
cross(1, 1, 11)
res = M.lastMessage(1, "race.results")
mine = res.finished[1]
eq(mine.challengeResult.tier, 1, "fifty five seconds is the top rung")
eq(mine.challengeResult.gained, 25, "the extra twenty five")
after = RM.xp.of(RM.identity.session(1).key)
eq(after - before, 25 + mine.xp, "paid")
before = after
M.clientSend(1, "race.arm", { id = "loop", mode = "controller", laps = 1, challenge = "morning-loop" })
tick(1)
cross(1, 1, 5)
for g = 2, 5 do cross(1, g, 15) end
cross(1, 1, 15)
res = M.lastMessage(1, "race.results")
mine = res.finished[1]
eq(mine.challengeResult.improved, false, "no improvement")
eq(mine.challengeResult.gained, 0, "nothing more")
near(mine.challengeResult.best, 55, 0.01, "the best stays")

section("outside the ladder counts as entered but pays nothing")
M.clientSend(2, "race.arm", { id = "loop", mode = "controller", laps = 1, challenge = "morning-loop" })
tick(1)
cross(2, 1, 5)
for g = 2, 5 do cross(2, g, 30) end
cross(2, 1, 30)
res = M.lastMessage(2, "race.results")
mine = res.finished[1]
eq(mine.challengeResult.tier, nil, "no rung")
eq(mine.challengeResult.gained, 0, "no xp")
board = M.lastMessage(2, "challenges.list")
eq(board[1].entered, 2, "two on the board")
eq(board[1].top[2].name, "Colt", "Colt second")

section("the rules of entry")
M.clearOutbox(1)
M.clientSend(1, "race.arm", { id = "loop", mode = "controller", laps = 2, challenge = "morning-loop" })
tick(1)
eq((M.lastMessage(1, "race.result") or {}).reason, "wrong_laps_for_challenge", "the laps are the challenge's")
M.clientSend(1, "race.arm", { id = "loop", mode = "controller", laps = 1, challenge = "no-such" })
tick(1)
eq((M.lastMessage(1, "race.result") or {}).reason, "no_such_challenge", "a challenge that is not there")

section("a challenge for two classes only lets those classes in")
M.clientSend(0, "challenge.create", {
  name = "Trucks only", kind = "weekly", track = "loop", laps = 1,
  classes = { "Trophy Truck", "Class 1" },
  tiers = { { time = 60, xp = 100 } },
})
tick(1)
eq((M.lastMessage(0, "challenge.result") or {}).ok, true, "posted")
M.clearOutbox(1)
M.clientSend(1, "race.arm", { id = "loop", mode = "controller", laps = 1, challenge = "trucks-only" })
tick(1)
eq((M.lastMessage(1, "race.result") or {}).reason, "class_not_in_challenge", "no class picked, no entry")
M.clientSend(1, "race.arm", { id = "loop", mode = "controller", laps = 1, challenge = "trucks-only", class = "Class 10" })
tick(1)
eq((M.lastMessage(1, "race.result") or {}).reason, "class_not_in_challenge", "the wrong class, no entry")
M.clientSend(1, "race.arm", { id = "loop", mode = "controller", laps = 1, challenge = "trucks-only", class = "Trophy Truck" })
tick(1)
eq((M.lastMessage(1, "race.state") or {}).challenge, "trucks-only", "the right class is in")
M.clientSend(1, "race.end", {})
tick(1)

section("a team cannot enter")
M.clientSend(1, "team.offer", { who = 2, kind = "invite" })
tick(1)
M.clientSend(2, "team.accept", {})
tick(1)
ok(RM.team.forPid(1) ~= nil, "Bravo and Colt are a team")
M.clearOutbox(1)
M.clientSend(1, "race.arm", { id = "loop", mode = "controller", laps = 1, challenge = "morning-loop" })
tick(1)
eq((M.lastMessage(1, "race.result") or {}).reason, "teams_cannot_enter", "refused")
M.clientSend(1, "team.leave", {})
tick(1)

section("the limits: three daily, five weekly, counting what has not ended")
M.clientSend(0, "challenge.create", { name = "Second daily", kind = "daily", track = "loop", laps = 1, tiers = { { time = 60, xp = 10 } } })
M.clientSend(0, "challenge.create", { name = "Third daily", kind = "daily", track = "loop", laps = 1, tiers = { { time = 60, xp = 10 } } })
tick(1)
M.clearOutbox(0)
M.clientSend(0, "challenge.create", { name = "Fourth daily", kind = "daily", track = "loop", laps = 1, tiers = { { time = 60, xp = 10 } } })
tick(1)
eq((M.lastMessage(0, "challenge.result") or {}).reason, "too_many_daily", "a fourth daily is refused")
for i = 2, 5 do
  M.clientSend(0, "challenge.create", { name = "Weekly " .. i, kind = "weekly", track = "loop", laps = 1, tiers = { { time = 60, xp = 10 } } })
end
tick(1)
M.clearOutbox(0)
M.clientSend(0, "challenge.create", { name = "Weekly 6", kind = "weekly", track = "loop", laps = 1, tiers = { { time = 60, xp = 10 } } })
tick(1)
eq((M.lastMessage(0, "challenge.result") or {}).reason, "too_many_weekly", "a sixth weekly is refused")

section("ending one now makes room, and it drops to the bottom of the board")
M.clientSend(0, "challenge.end", { id = "third-daily" })
tick(1)
eq(RM.challenges.stateOf(RM.challenges.get("third-daily")), "ended", "ended")
M.clearOutbox(0)
M.clientSend(0, "challenge.create", { name = "Fourth daily", kind = "daily", track = "loop", laps = 1, tiers = { { time = 60, xp = 10 } } })
tick(1)
eq((M.lastMessage(0, "challenge.result") or {}).ok, true, "now it fits")
board = M.lastMessage(0, "challenges.list")
eq(board[#board].id, "third-daily", "the ended one is last")
eq(board[#board].state, "ended", "and says so")
M.clearOutbox(1)
M.clientSend(1, "race.arm", { id = "loop", mode = "controller", laps = 1, challenge = "third-daily" })
tick(1)
eq((M.lastMessage(1, "race.result") or {}).reason, "challenge_not_live", "and cannot be entered")

section("a scheduled challenge waits for its hour, then goes live on its own")
M.clientSend(0, "challenge.delete", { id = "fourth-daily" })
tick(1)
M.clientSend(0, "challenge.create", { name = "Tonight", kind = "daily", track = "loop", laps = 1,
  startInHours = 2, tiers = { { time = 60, xp = 10 } } })
tick(1)
local c = RM.challenges.get("tonight")
eq(RM.challenges.stateOf(c), "scheduled", "scheduled")
near(c.startsAt - wall, 7200, 1, "two hours out")
M.clearOutbox(2)
M.clientSend(2, "race.arm", { id = "loop", mode = "controller", laps = 1, challenge = "tonight" })
tick(1)
eq((M.lastMessage(2, "race.result") or {}).reason, "challenge_not_live", "not yet")
M.clearOutbox(2)
wall = wall + 7201
tick(5)
eq(RM.challenges.stateOf(c), "live", "live two hours later")
board = M.lastMessage(2, "challenges.list")
ok(board ~= nil, "and everybody was told")
wall = wall + 86400
tick(5)
eq(RM.challenges.stateOf(c), "ended", "and over a day after that")

section("changing a challenge live: new times keep the board, a new course clears it")
M.clientSend(0, "challenge.update", { id = "morning-loop", tiers = { { time = 50, xp = 100 }, { time = 70, xp = 75 } } })
tick(1)
c = RM.challenges.get("morning-loop")
eq(#c.tiers, 2, "two rungs now")
ok(c.results[RM.identity.session(1).key] ~= nil, "Bravo's time is still there")
M.clientSend(0, "challenge.update", { id = "morning-loop", laps = 2 })
tick(1)
eq(c.laps, 2, "two laps now")
eq(next(c.results), nil, "and the board is wiped: those times were one lap")

section("bad ladders are refused")
M.clearOutbox(0)
M.clientSend(0, "challenge.create", { name = "Broken", kind = "weekly", track = "loop", laps = 1, tiers = {} })
tick(1)
eq((M.lastMessage(0, "challenge.result") or {}).reason, "no_tiers", "no rungs")
M.clientSend(0, "challenge.create", { name = "Broken", kind = "weekly", track = "loop", laps = 1, tiers = { { time = 0, xp = 5 } } })
tick(1)
eq((M.lastMessage(0, "challenge.result") or {}).reason, "bad_tier", "a rung with no time")
M.clientSend(0, "challenge.create", { name = "Broken", kind = "weekly", track = "nowhere", laps = 1, tiers = { { time = 60, xp = 5 } } })
tick(1)
eq((M.lastMessage(0, "challenge.result") or {}).reason, "no_such_track", "a course that is not there")

section("a long ladder: twenty rungs go, twenty one do not")
local long = {}
for i = 1, 20 do long[i] = { time = 60 + i, xp = 200 - i } end
M.clearOutbox(0)
M.clientSend(0, "challenge.update", { id = "morning-loop", tiers = long })
tick(1)
eq((M.lastMessage(0, "challenge.result") or {}).ok, true, "twenty rungs are kept")
eq(#RM.challenges.get("morning-loop").tiers, 20, "all twenty")
long[21] = { time = 90, xp = 1 }
M.clientSend(0, "challenge.update", { id = "morning-loop", tiers = long })
tick(1)
eq((M.lastMessage(0, "challenge.result") or {}).reason, "too_many_tiers", "twenty one is refused")

section("the board survives a restart")
RM.store.flushAll()
local reloaded = RM.store.load("challenges")
ok(reloaded and reloaded["morning-loop"], "on disk")

-- =========================================================== tracking
section("tracking off means no XP and no challenges, and the switch is remembered")
-- a live daily to try to enter: every earlier daily has run its day by now
M.clientSend(0, "challenge.create", { name = "Fresh daily", kind = "daily", track = "loop", laps = 1, tiers = { { time = 60, xp = 10 } } })
tick(1)
eq(RM.challenges.stateOf(RM.challenges.get("fresh-daily")), "live", "a live daily to try")
M.clearOutbox(2)
M.clientSend(2, "options.tracking", { on = false })
tick(1)
eq((M.lastMessage(2, "me") or {}).tracking, false, "Colt is told it is off")
before = RM.xp.of(RM.identity.session(2).key)
eq(RM.xp.give(RM.identity.session(2).key, 50, "test"), nil, "no XP goes on")
eq(RM.xp.of(RM.identity.session(2).key), before, "the total is untouched")
M.clearOutbox(2)
M.clientSend(2, "race.arm", { id = "loop", mode = "controller", laps = 1, challenge = "fresh-daily" })
tick(1)
eq((M.lastMessage(2, "race.result") or {}).reason, "tracking_off", "and no challenge can be entered")
M.clientSend(2, "options.tracking", { on = true })
tick(1)
eq((M.lastMessage(2, "me") or {}).tracking, true, "back on")
ok(RM.xp.give(RM.identity.session(2).key, 50, "test") ~= nil, "XP goes on again")

section("!resetui in chat puts that player's interface back, and stays out of the chat")
M.clearOutbox(1)
local swallowed = M.fire("onChatMessage", 1, "Bravo", "!resetui")
eq(swallowed, 1, "the message is swallowed")
tick(1)
ok(M.lastMessage(1, "ui.reset") ~= nil, "and Bravo's game is told to reset")
eq(M.lastMessage(0, "ui.reset"), nil, "nobody else's is")
M.clearOutbox(1)
eq(M.fire("onChatMessage", 1, "Bravo", "hello everyone"), nil, "ordinary chat goes through")
tick(1)
eq(M.lastMessage(1, "ui.reset"), nil, "and resets nothing")
eq(M.fire("onChatMessage", 1, "Bravo", "  !UI "), 1, "!ui, however typed, is the same")
eq(M.fire("onChatMessage", 1, "Bravo", "!restoreui"), 1, "and !restoreui, the word the Options window uses")

section("the console sees the board and the watchers")
local heard = tostring(RM.console.handle("rm challenges")) .. "\n" .. tostring(RM.console.handle("rm watching"))
ok(heard:find("morning%-loop") ~= nil, "the board is listed")
ok(heard:find("nobody is watching") ~= nil, "and nobody is watching")

print("")
if fail > 0 then
  print(("%d passed, %d failed"):format(pass, fail))
  os.exit(1)
end
print(("%d passed, 0 failed"):format(pass))
