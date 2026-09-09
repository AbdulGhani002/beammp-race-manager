-- The Stella box against the mock host: a stopped car warning the cars near
-- it, and a driver asking the car in front to let them by. Positions are fed
-- in by hand, because who is where is the whole question.
--
--   lua tools/test_stella.lua

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

local function tick(n) for _ = 1, (n or 1) do M.fire("rm:tick") end end

-- three drivers on one course, each in a car the server can see
local DRIVERS = {
  { pid = 0, name = "Alfa",  ip = "203.0.113.1" },
  { pid = 1, name = "Bravo", ip = "203.0.113.2" },
  { pid = 2, name = "Colt",  ip = "203.0.113.3" },
}
for _, d in ipairs(DRIVERS) do
  M.addPlayer(d.pid, d.name, "700" .. d.pid, false, d.ip)
  M.fire("onPlayerJoining", d.pid)
  M.clientSend(d.pid, "hello", { version = RM.VERSION })
  M.clientSend(d.pid, "name.set", { name = d.name })
  M.fire("onVehicleSpawn", d.pid, d.pid * 10, 'pickup:{"jbm":"pickup"}')
end
tick(1)
RM.console.handle("rm role Alfa owner")

-- a straight course along x, gates every hundred metres
M.clientSend(0, "track.begin",
  { id = "line", name = "Line", kind = "race", level = "utah_sc", circuit = false })
tick(1)
for i = 1, 6 do
  M.advance(1)
  M.clientSend(0, "track.mark", { pos = { x = i * 100, y = 0, z = 0 }, yaw = 0 })
  tick(1)
end
M.clientSend(0, "track.finish")
tick(1)

-- where each car is. the mock keeps one raw sample per vehicle.
local function put(pid, x, y)
  M.raw[pid] = M.raw[pid] or {}
  M.raw[pid][pid * 10] = { vel = { 0, 0, 0 }, ping = 30, pos = { x, y, 0 } }
end

local function agree(pid)
  local t1 = RM.now()
  RM.clock.onPong(pid, { t1 = t1, t2 = t1, t3 = t1 })
end

local function hit(pid, gate)
  M.advance(2)
  agree(pid)
  M.clientSend(pid, "cp.hit", { i = gate, t = RM.now() })
  tick(1)
end

local function racing(pid)
  M.clientSend(pid, "race.arm", { id = "line", mode = "controller", laps = 1 })
  tick(1)
  hit(pid, 1)
end

for _, d in ipairs(DRIVERS) do M.clearOutbox(d.pid) end

-- ================================================================ positions

section("the server knows where a car is")
put(0, 120, 0)
local x, y = RM.stella.posOf(0)
eq(x, 120, "from the same sample the roster reads")
eq(y, 0, "both ways")
eq(RM.stella.posOf(99), nil, "and nothing for somebody who is not here")

-- ================================================================== passing

section("nobody is ahead until somebody is racing")
put(0, 120, 0)
put(1, 250, 0)
eq(select(2, RM.stella.ahead(0)), "not_racing", "asking while parked goes nowhere")

racing(0)
racing(1)
racing(2)
for _, d in ipairs(DRIVERS) do M.clearOutbox(d.pid) end

section("the car in front is the one further round the course, inside the window")
-- Alfa at 120 heading for gate 2 at 200. Bravo at 250, already past gate 2.
put(0, 120, 0)
put(1, 250, 0)
put(2, 900, 0)
hit(1, 2)
eq(RM.race.get(1).nextGate, 3, "Bravo really is through gate 2, so this is progress, not a guess")
local ahead, dist = RM.stella.ahead(0)
eq(ahead, 1, "Bravo is ahead of Alfa")
ok(math.abs(dist - 130) < 0.01, ("and a hundred and thirty metres away, not %s"):format(tostring(dist)))

-- Colt is two gates further on than Bravo, so by progress he is in front,
-- but six hundred and fifty metres off is outside the window
hit(2, 2)
hit(2, 3)
eq(RM.race.get(2).nextGate, 4, "Colt really is through gate 3")
eq(select(2, RM.stella.ahead(1)), "nobody_ahead",
   "Colt is further round but six hundred and fifty metres off, outside the window")

section("a request reaches the car in front and the asker is told it was delivered")
for _, d in ipairs(DRIVERS) do M.clearOutbox(d.pid) end
M.clientSend(0, "stella.pass.request", {})
tick(1)
local alert = M.lastMessage(1, "stella.pass.alert")
ok(alert ~= nil, "Bravo hears about it")
eq(alert and alert.requesterName, "Alfa", "and who is asking")
eq(alert and alert.distanceM, 130, "and how far back they are")
local st = M.lastMessage(0, "stella.pass.status")
eq(st and st.state, "delivered", "Alfa is told it got there")
eq(st and st.aheadName, "Bravo", "and to whom")

section("asking again while it is open is the same request, not a second one")
local id = alert.requestId
M.clearOutbox(0)
M.clientSend(0, "stella.pass.request", {})
tick(1)
eq(M.lastMessage(0, "stella.pass.status").requestId, id, "same id back")
eq(select(2, RM.stella.count()), 1, "still one request")

section("only the car it was sent to can accept it")
M.clearOutbox(2)
M.clientSend(2, "stella.pass.accept", { requestId = id })
tick(1)
eq(M.lastMessage(2, "stella.pass.status").reason, "not_yours", "Colt cannot answer for Bravo")
eq(M.lastMessage(0, "stella.pass.go"), nil, "and Alfa gets no green light from it")

section("accepting gives the asker the green light")
M.clearOutbox(0)
M.clientSend(1, "stella.pass.accept", { requestId = id })
tick(1)
local go = M.lastMessage(0, "stella.pass.go")
ok(go ~= nil, "Alfa is told to go")
eq(go and go.aheadName, "Bravo", "past Bravo")
ok(type(go.expiresAt) == "number", "for a while")

section("and it closes on its own once the green light is up")
M.advance(RM.config.stella.passGoSecs + 1)
tick(RM.config.rosterMs / RM.config.tickMs)
eq(M.lastMessage(0, "stella.pass.status").state, "complete", "Alfa's exchange is over")
eq(M.lastMessage(1, "stella.pass.status").state, "complete", "and so is Bravo's")
eq(select(2, RM.stella.count()), 0, "nothing left open")

section("a request nobody answers expires rather than hanging about")
for _, d in ipairs(DRIVERS) do M.clearOutbox(d.pid) end
M.clientSend(0, "stella.pass.request", {})
tick(1)
M.advance(RM.config.stella.passReplySecs + 1)
tick(RM.config.rosterMs / RM.config.tickMs)
eq(M.lastMessage(0, "stella.pass.status").state, "expired", "the asker is told")
eq(M.lastMessage(1, "stella.pass.status").state, "expired", "and so is the car ahead")

section("with nobody in front the asker is told, not left waiting")
M.clearOutbox(1)
M.clientSend(1, "stella.pass.request", {})
tick(1)
local none = M.lastMessage(1, "stella.pass.status")
eq(none and none.state, "cancelled", "cancelled straight away")
eq(none and none.reason, "nobody_ahead", "with the reason")

-- ================================================================ breakdown

section("a stopped car warns the cars near it, once each way")
for _, d in ipairs(DRIVERS) do M.clearOutbox(d.pid) end
put(1, 250, 0)      -- Bravo stops here
put(0, 120, 0)      -- Alfa is 130 back, inside range
put(2, 900, 0)      -- Colt is far away
M.clientSend(1, "stella.breakdown.set", { active = true, kind = "mechanical" })
tick(1)
local mine = M.lastMessage(1, "stella.breakdown.state")
eq(mine and mine.active, true, "the driver who pressed it is told it took")
tick(RM.config.rosterMs / RM.config.tickMs)
local warn = M.lastMessage(0, "stella.breakdown.alert")
eq(warn and warn.active, true, "Alfa, close behind, is warned")
eq(warn and warn.playerName, "Bravo", "about Bravo")
eq(warn and warn.distanceM, 130, "a hundred and thirty metres off")
eq(M.lastMessage(2, "stella.breakdown.alert"), nil, "Colt, far away, hears nothing")

M.clearOutbox(0)
tick(RM.config.rosterMs / RM.config.tickMs)
eq(M.lastMessage(0, "stella.breakdown.alert"), nil, "and Alfa is not told again every tick")

section("driving out of range clears it, driving in brings it back")
put(0, 1200, 0)
tick(RM.config.rosterMs / RM.config.tickMs)
eq(M.lastMessage(0, "stella.breakdown.alert").active, false, "gone once Alfa is well past")
put(0, 150, 0)
M.clearOutbox(0)
tick(RM.config.rosterMs / RM.config.tickMs)
eq(M.lastMessage(0, "stella.breakdown.alert").active, true, "back when Alfa comes round again")

section("clearing the breakdown clears the warning on everybody it reached")
M.clearOutbox(0)
M.clientSend(1, "stella.breakdown.set", { active = false })
tick(1)
eq(M.lastMessage(0, "stella.breakdown.alert").active, false, "Alfa's warning goes")
eq(M.lastMessage(1, "stella.breakdown.state").active, false, "and Bravo is told it is off")
eq(RM.stella.isBrokenDown(1), false, "nothing is remembered")

section("leaving the server takes the warning with you")
M.clientSend(1, "stella.breakdown.set", { active = true })
tick(RM.config.rosterMs / RM.config.tickMs)
M.clearOutbox(0)
M.fire("onPlayerDisconnect", 1)
M.removePlayer(1)
tick(1)
eq(M.lastMessage(0, "stella.breakdown.alert").active, false,
   "Alfa is not left staring at a warning for a car that is gone")
eq((RM.stella.count()), 0, "and the list is empty")

print("")
print(("%d passed, %d failed"):format(pass, fail))
for _, f in ipairs(failures) do print("  - " .. f) end
os.exit(fail == 0 and 0 or 1)
