-- The Stella and its bridge run together outside the game, through what a
-- race does to them: a gate crossed, a pass asked for and given, a car
-- stopped, and the test from chat. His unit says nothing on its own, the
-- screen polls it, so the tests read the snapshot the screen would and
-- the sounds it would play.
--
--   lua tools/test_stella_flow.lua

local pass, fail = 0, 0
local function ok(cond, what)
  if cond then pass = pass + 1 else fail = fail + 1 print("  FAIL  " .. what) end
end
local function eq(got, want, what)
  ok(got == want, ("%s (got %s, wanted %s)"):format(what, tostring(got), tostring(want)))
end
local function section(t) print("") print("== " .. t) end

math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local hooked = {}
guihooks = { trigger = function(name, d)
  if name == "RMSI_Update" and type(d) == "table" then
    for _, s in ipairs(d.sounds or {}) do hooked[#hooked + 1] = s end
  end
end }

local function vec(t)
  return { x = t.x, y = t.y, z = t.z,
           length = function(self) return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end }
end
local cars = {}
local function car(id, x, mps)
  cars[id] = cars[id] or {}
  local c = cars[id]
  c.pos = { x = x or 0, y = 0, z = 0 }
  c.vel = { x = mps or 0, y = 0, z = 0 }
  c.obj = c.obj or {
    getPosition = function() return vec(cars[id].pos) end,
    getVelocity = function() return vec(cars[id].vel) end,
    getDirectionVector = function() return vec({ x = 1, y = 0, z = 0 }) end,
    getID = function() return id end,
  }
  return c.obj
end
car(1, 0, 0)
be = {
  getPlayerVehicle = function() return cars[1].obj end,
  getObjectCount = function() return 0 end,
  getObject = function() return nil end,
  getObjectByID = function(_, id) return cars[id] and cars[id].obj or nil end,
}

local handlers, sent, notices = {}, {}, {}
local function lastSent(ch)
  for i = #sent, 1, -1 do if sent[i].ch == ch then return sent[i].d end end
  return nil
end
local function countSent(ch)
  local n = 0
  for i = 1, #sent do if sent[i].ch == ch then n = n + 1 end end
  return n
end
local function fromServer(ch, d)
  ok(handlers[ch] ~= nil, "the bridge listens for " .. ch)
  if handlers[ch] then handlers[ch](d) end
end

local status = { state = "idle", next = 1, done = 0, track = "t" }
local course = {
  { i = 1, pos = { x = 0,    y = 0, z = 0 } },
  { i = 2, pos = { x = 300,  y = 0, z = 0 } },
  { i = 3, pos = { x = 600,  y = 0, z = 0 } },
  { i = 4, pos = { x = 900,  y = 0, z = 0 } },
}
local track = { id = "t", name = "Test", checkpoints = course, zones = {} }
extensions = {
  raceManager_net = {
    on = function(ch, fn) handlers[ch] = fn end,
    send = function(ch, d) sent[#sent + 1] = { ch = ch, d = d } return true end,
  },
  raceManager_state = {
    notice = function(t) notices[#notices + 1] = t end,
    get = function() return { track = track } end,
  },
  raceManager_race = { status = function() return status end },
  raceManager_triggers = { szState = function() return nil end },
}

local S = dofile("client/lua/ge/extensions/raceManager/stellaUnit.lua")
S.onExtensionLoaded()
extensions.raceManager_stellaUnit = S
local B = dofile("client/lua/ge/extensions/raceManager/stella.lua")
B.onExtensionLoaded()
extensions.raceManager_stella = B

local function snap() return S.getSnapshot() end
local function led() local s = snap() return { color = s.ledColor, flash = s.ledFlash, pattern = s.ledPattern } end
local function flag() return snap().blueFlagState end
-- the sounds go out with the hook, every other tick; whatever is still
-- waiting in the unit counts too
local function sounds()
  local out = hooked
  hooked = {}
  for _, s in ipairs(S.drainSounds()) do out[#out + 1] = s end
  return out
end
local function has(list, name) for _, n in ipairs(list) do if n == name then return true end end return false end
-- both run: the bridge at its own pace, the unit on the frame
local function run(seconds)
  local t = 0
  while t < seconds - 1e-9 do
    B.onUpdate(0.1)
    S.onUpdate(0.1)
    t = t + 0.1
  end
end

section("idle, the unit shows an idle car and nothing lit")
run(1.0)
eq(snap().raceActive, false, "idle")
eq(led().color, "off", "nothing lit")
eq(#sounds(), 0, "and nothing to play")

section("the unit tells the screen everything by hook, ten times a second")
local told = {}
local before = guihooks.trigger
guihooks.trigger = function(name, d) before(name, d) if name == "RMSI_Update" then told[#told + 1] = d end end
extensions.raceManager_keys = { pull = (function()
  local q = { "toggle", "flag" }
  return function() return table.remove(q, 1) end
end)() }
run(1.0)
ok(#told >= 9 and #told <= 11, ("ten a second (%d)"):format(#told))
eq(told[1].heading, 90, "with the heading")
eq(told[1].ledColor, "off", "and the light")
local keys = {}
for _, d in ipairs(told) do for _, k in ipairs(d.keys or {}) do keys[#keys + 1] = k end end
eq(table.concat(keys, ","), "toggle,flag", "and the keys pressed, each once")
extensions.raceManager_keys = nil
guihooks.trigger = before

section("a race is armed, then starts, and the Stella leaves idle")
status.state, status.next, status.done = "armed", 1, 0
run(0.3)
eq(snap().raceActive, true, "the unit shows the race once armed")
eq(snap().vcpIndex, 1, "heading for the start line")
status.state, status.next, status.done = "running", 2, 1
run(0.2)
eq(snap().vcpIndex, 2, "and then the gate to head for")
eq(led().color, "green", "the start line crossed lights green")
ok(has(sounds(), "vcp"), "with the gate sound")
run(3.2)
eq(led().color, "off", "and three seconds later the light is out")

section("a gate crossed: green for three seconds, then out again")
status.next, status.done = 3, 2
run(0.2)
eq(led().color, "green", "green on the crossing")
eq(snap().validatedVCPs, 2, "two gates done")
run(1.0)
eq(led().color, "green", "still green a second later")
run(2.5)
eq(led().color, "off", "out after three")

section("the lap line, where the count drops back to one, is a crossing too")
status.next, status.done = 2, 1
run(0.2)
eq(led().color, "green", "green on the line")
run(3.2)
eq(led().color, "off", "and out")

section("push to pass: asked, delivered, given, and over")
S.requestBlueFlag()
eq(countSent("stella.pass.request"), 1, "the request goes to the server")
fromServer("stella.pass.status", { state = "delivered", requestId = 5, aheadName = "Bravo" })
eq(flag(), "delivered", "delivered to the car ahead")
eq(snap().blueFlagPlayer, "Bravo", "with their name")
eq(led().color, "green", "green lines: it is out there")
eq(led().pattern, "lines", "lines")
run(5)
eq(flag(), "delivered", "waiting on the answer, nothing on the unit times out")
fromServer("stella.pass.go", { requestId = 5, aheadName = "Bravo" })
eq(flag(), "go", "Bravo lets us by")
eq(led().color, "green", "green")
eq(led().pattern, "all", "all the dots")
ok(has(sounds(), "beep"), "with the beep")
run(3)
eq(led().color, "green", "still green three seconds in, the pass is on")
fromServer("stella.pass.status", { state = "complete", requestId = 5, aheadName = "Bravo" })
eq(flag(), "none", "over when the server says so")
run(0.2)
eq(led().color, "off", "and the light is out")

section("a gate crossed during the pass goes green and comes back to the pass, not to nothing")
S.requestBlueFlag()
fromServer("stella.pass.status", { state = "delivered", requestId = 6, aheadName = "Bravo" })
fromServer("stella.pass.go", { requestId = 6, aheadName = "Bravo" })
run(0.2)
status.next, status.done = 3, 2
run(0.2)
eq(led().color, "green", "green on the crossing")
eq(led().pattern, "all", "the gate's all dots")
run(3.3)
eq(flag(), "go", "the pass is still on")
eq(led().color, "green", "so the light is the pass's green")
fromServer("stella.pass.status", { state = "complete", requestId = 6, aheadName = "Bravo" })
run(0.2)
eq(led().color, "off", "out once the pass is over")

section("nobody ahead: told, and nothing left lit")
S.requestBlueFlag()
fromServer("stella.pass.status", { state = "cancelled", reason = "nobody_ahead" })
eq(flag(), "none", "no request stands")
run(0.2)
eq(led().color, "off", "nothing lit")
ok(#notices > 0 and notices[#notices]:find("No pass", 1, true) ~= nil, "and the driver is told why")

section("the car ahead: asked, answers with OK, and the answer carries the request")
sounds()
fromServer("stella.pass.alert", { requestId = 9, requesterId = 3, requesterName = "Charlie", distanceM = 120 })
eq(flag(), "incoming", "Charlie is asking")
eq(snap().blueFlagPlayer, "Charlie", "by name")
eq(led().color, "blue", "blue flag")
ok(has(sounds(), "beep"), "with the beep")
S.acknowledgeBlueFlag()
eq(flag(), "accepted", "OK accepts")
eq((lastSent("stella.pass.accept") or {}).requestId, 9, "and the server is told which request")
fromServer("stella.pass.status", { state = "accepted", requestId = 9, aheadName = "Alfa" })
eq(flag(), "accepted", "confirmed")
fromServer("stella.pass.status", { state = "complete", requestId = 9, aheadName = "Alfa" })
eq(flag(), "none", "and over")
run(0.2)
eq(led().color, "off", "light out")
S.acknowledgeBlueFlag()
eq(countSent("stella.pass.accept"), 1, "OK with nobody asking sends nothing")

section("the red button: stopped, then moving again, and a car stopped ahead")
S.requestMechanicalBreakdown()
eq((lastSent("stella.breakdown.set") or {}).active, true, "the server hears the car is stopped")
fromServer("stella.breakdown.state", { active = true, playerName = "Alfa" })
eq(led().color, "yellow", "yellow triangle")
eq(led().pattern, "triangle", "triangle")
run(0.2)
eq(snap().breakdownActive, true, "shown as stopped")
S.requestMechanicalBreakdown()
eq((lastSent("stella.breakdown.set") or {}).active, false, "pressed again, moving again")
fromServer("stella.breakdown.state", { active = false, playerName = "Alfa" })
run(0.2)
eq(led().color, "off", "light out")
fromServer("stella.breakdown.alert", { active = true, playerName = "Delta", distanceM = 90 })
eq(led().color, "red", "somebody stopped ahead warns in red")
eq(led().pattern, "triangle", "with the triangle")
run(0.2)
eq(snap().hazardAhead, true, "and the screen says caution")
fromServer("stella.breakdown.alert", { active = false, playerName = "Delta" })
run(0.2)
eq(led().color, "off", "and clears when they move")

section("the race ends and the unit goes idle with nothing left lit")
status.state, status.next, status.done = "idle", 1, 0
run(0.3)
eq(snap().raceActive, false, "idle")
eq(led().color, "off", "nothing lit")

section("!stella runs the unit through everything it can show, two seconds a step, and ends with a verdict")
extensions.raceManager_race.isActive = function() return false end
ok(B.selfTest(), "starts when there is no race on")
ok(notices[#notices]:find("unit 0.7.15", 1, true) ~= nil, "the unit's version is said first")
run(0.2)
eq(led().color, "yellow", "one: yellow, straight away") eq(led().pattern, "triangle", "triangle")
eq(snap().testStep, 1, "and the snapshot carries the step, for the screen to answer")
B.screenSaw()
ok(notices[#notices]:find("1 of 6", 1, true) ~= nil, "and says so")
run(2.0)
eq(led().color, "blue", "two: blue") eq(led().pattern, "lines", "lines")
eq(snap().testStep, 2, "step two")
run(2.0)
eq(led().color, "green", "three: green") eq(led().pattern, "all", "all the dots")
run(2.0)
eq(snap().speedZoneWarning, true, "four: a zone ahead on the screen")
eq(led().color, "yellow", "yellow") eq(led().pattern, "limit:37", "spelling 37")
run(2.0)
eq(snap().speedZoneActive, true, "five: in the zone on the screen")
eq(led().color, "red", "red") eq(led().flash, false, "steady")
run(2.0)
eq(snap().speedExceeding, true, "six: over the limit on the screen")
eq(led().flash, true, "red flashing")
run(2.0)
eq(snap().speedZoneActive, false, "over: no zone")
eq(led().color, "off", "dots out")
eq(snap().testStep, 0, "and no step in the snapshot")
ok(notices[#notices]:find("Stella test over", 1, true) ~= nil, "and it says it is over")
ok(notices[#notices]:find("ticking 10 a second", 1, true) ~= nil, "with how fast the unit ticked")
ok(notices[#notices]:find("answered 1 of 6", 1, true) ~= nil, "and how often the screen answered")
ok(notices[#notices]:find("did not reach the screen", 1, true) ~= nil, "and what that means")
extensions.raceManager_race.isActive = function() return true end
eq(B.selfTest(), false, "not during a race")
ok(notices[#notices]:find("not during a race", 1, true) ~= nil, "and says why")
extensions.raceManager_race.isActive = nil

print("")
print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
