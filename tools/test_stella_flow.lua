-- The Stella and its bridge run together outside the game, through what a
-- race does to them: a gate crossed, a pass asked for and given, a car
-- stopped, and a copilot working the unit for the driver they are sitting
-- with. These are the things he said were broken.
--
--   lua tools/test_stella_flow.lua

local pass, fail = 0, 0

local function ok(cond, what)
  if cond then pass = pass + 1
  else fail = fail + 1 print("  FAIL  " .. what) end
end

local function eq(got, want, what)
  ok(got == want, ("%s (got %s, wanted %s)"):format(what, tostring(got), tostring(want)))
end

local function section(t) print("") print("== " .. t) end

-- the game, faked: two cars, the ui hook, the network, the race, the copilot
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local events = {}
guihooks = { trigger = function(name, data) events[#events + 1] = { name = name, data = data } end }
local function lastEvent(name)
  for i = #events, 1, -1 do if events[i].name == name then return events[i].data end end
  return nil
end
local function countEvents(name)
  local n = 0
  for i = 1, #events do if events[i].name == name then n = n + 1 end end
  return n
end

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
car(7, 5000, 30)
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
local watching = nil
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
  raceManager_copilot = { status = function() return { watching = watching, gameId = watching and watching.gameId or nil } end },
  raceManager_triggers = { nearestSz = function() return nil end },
}

local S = dofile("client/lua/ge/extensions/bajaStella.lua")
S.onExtensionLoaded()
extensions.bajaStella = S
local B = dofile("client/lua/ge/extensions/raceManager/stella.lua")
B.onExtensionLoaded()
extensions.raceManager_stella = B

local function led() return lastEvent("BajaStella_LED") or {} end
local function shown() return lastEvent("BajaStella_Update") or {} end
local function flag() return (lastEvent("BajaStella_BlueFlag") or {}).state end
-- both units run: the bridge at its own pace, the Stella on the frame
local function run(seconds)
  local t = 0
  while t < seconds - 1e-9 do
    B.onUpdate(0.1)
    S.onUpdate(0.1)
    t = t + 0.1
  end
end

section("idle, the unit is told once and left alone")
run(1.0)
eq(shown().raceActive, false, "idle")
local ledEvents = countEvents("BajaStella_LED")
run(2.0)
eq(countEvents("BajaStella_LED"), ledEvents, "no light is set and cleared while nothing happens")

section("a race is armed, then starts, and the Stella leaves idle")
status.state, status.next, status.done = "armed", 1, 0
run(0.3)
eq(shown().raceActive, true, "the unit shows the race once armed")
eq(shown().vcpIndex, 1, "heading for the start line")
status.state, status.next, status.done = "running", 2, 1
run(0.2)
eq(shown().vcpIndex, 2, "and then the gate to head for")
eq(led().color, "green", "the start line crossed lights green")
run(2.5)
eq(led().color, "off", "and two seconds later the light is out")

section("a gate crossed: green for two seconds, then out again")
status.next, status.done = 3, 2
run(0.2)
eq(led().color, "green", "green on the crossing")
eq(shown().validatedVCPs, 2, "two gates done")
run(1.0)
eq(led().color, "green", "still green a second later")
run(1.5)
eq(led().color, "off", "out after two")
eq(shown().ledColor, "off", "and the unit says so on every update")

section("push to pass: asked, delivered, given, and over")
S.requestBlueFlag()
eq(countSent("stella.pass.request"), 1, "the request goes to the server")
eq(flag(), "requested", "the unit shows it asking")
eq(led().color, "blue", "in blue")
fromServer("stella.pass.status", { state = "delivered", requestId = 5, aheadName = "Bravo" })
eq(flag(), "delivered", "delivered to the car ahead")
eq(lastEvent("BajaStella_BlueFlag").playerName, "Bravo", "with their name")
ok(led().color == "green" or led().color == "blue", "and the light says it is out there")
run(5)
ok(flag() == "delivered" or flag() == "none", "waiting on the answer")
fromServer("stella.pass.go", { requestId = 5, aheadName = "Bravo" })
eq(flag(), "go", "Bravo lets us by")
eq(led().color, "green", "green")
eq((lastEvent("BajaStella_AlertSound") or {}).kind, "passGo", "with the beep")
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
status.next, status.done = 4, 3
run(0.2)
eq(led().color, "green", "green on the crossing")
run(2.5)
eq(flag(), "go", "the pass is still on")
eq(led().color, "green", "so the light is the pass's green, not off")
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
fromServer("stella.pass.alert", { requestId = 9, requesterId = 3, requesterName = "Charlie", distanceM = 120 })
eq(flag(), "incoming", "Charlie is asking")
eq(led().color, "blue", "blue flag")
eq((lastEvent("BajaStella_AlertSound") or {}).kind, "blueFlag", "with the beep")
S.acknowledgeBlueFlag()
eq(flag(), "accepted", "OK accepts")
eq((lastSent("stella.pass.accept") or {}).requestId, 9, "and the server is told which request")
fromServer("stella.pass.status", { state = "accepted", requestId = 9, aheadName = "Alfa" })
eq(flag(), "accepted", "confirmed")
fromServer("stella.pass.status", { state = "complete", requestId = 9, aheadName = "Alfa" })
eq(flag(), "none", "and over")
run(0.2)
eq(led().color, "off", "light out")

section("the red button: stopped, then moving again")
S.toggleMechanicalBreakdown()
eq((lastSent("stella.breakdown.set") or {}).active, true, "the server hears the car is stopped")
fromServer("stella.breakdown.state", { active = true, playerName = "Alfa" })
eq(led().color, "yellow", "yellow triangle")
eq(led().pattern, "triangle", "triangle")
run(0.2)
eq(shown().breakdownActive, true, "shown as stopped")
S.toggleMechanicalBreakdown()
eq((lastSent("stella.breakdown.set") or {}).active, false, "moving again")
fromServer("stella.breakdown.state", { active = false, playerName = "Alfa" })
run(0.2)
eq(led().color, "off", "light out")
fromServer("stella.breakdown.alert", { active = true, playerName = "Delta", distanceM = 90 })
eq(led().color, "yellow", "somebody stopped ahead warns in yellow")
fromServer("stella.breakdown.alert", { active = false, playerName = "Delta" })
run(0.2)
eq(led().color, "off", "and clears when they move")

section("the race ends and the unit goes idle with nothing left lit")
status.state, status.next, status.done = "idle", 1, 0
run(0.3)
eq(shown().raceActive, false, "idle")
eq(led().color, "off", "nothing lit")

section("a copilot: the unit shows the driver's race and their car, and the buttons act for them")
for k in pairs(handlers) do end
watching = { name = "Driver", pid = 3, vid = 0, gameId = 7, found = true }
status.state = "idle"
fromServer("stella.mirror", { state = "running", track = "t", next = 3, done = 2, lap = 1, gates = 4 })
run(0.3)
eq(shown().raceActive, true, "the driver's race is what is shown")
eq(shown().vcpIndex, 3, "their next gate")
eq(shown().validatedVCPs, 2, "their gates done")
eq(shown().speed, 108, "and their car's speed, not the spectator's")
fromServer("stella.mirror", { state = "running", track = "t", next = 4, done = 3, lap = 1, gates = 4 })
run(0.2)
eq(led().color, "green", "their gate crossed lights green here too")
run(2.5)
eq(led().color, "off", "and goes out")
local before = countSent("stella.pass.request")
S.requestBlueFlag()
eq(countSent("stella.pass.request"), before + 1, "push to pass goes up as the driver's")
fromServer("stella.pass.status", { state = "delivered", requestId = 11, aheadName = "Bravo" })
eq(flag(), "delivered", "and the answer lands on the copilot's unit")
fromServer("stella.pass.status", { state = "complete", requestId = 11, aheadName = "Bravo" })
local b4 = countSent("stella.breakdown.set")
S.toggleMechanicalBreakdown()
eq(countSent("stella.breakdown.set"), b4 + 1, "the red button goes up as the driver's")
S.toggleMechanicalBreakdown()

section("!stella runs the unit through everything it can show, two seconds a step, and ends clean")
watching = nil
status.state = "idle"
run(0.3)
extensions.raceManager_race.isActive = function() return false end
ok(B.selfTest(), "starts when there is no race on")
run(0.2)
eq(led().color, "yellow", "one: yellow, straight away") eq(led().pattern, "triangle", "triangle")
ok(notices[#notices]:find("1 of 6", 1, true) ~= nil, "and says so")
run(2.0)
eq(led().color, "blue", "two: blue") eq(led().pattern, "lines", "lines")
run(2.0)
eq(led().color, "green", "three: green") eq(led().pattern, "all", "all the dots")
run(2.0)
eq(shown().speedZoneWarning, true, "four: a zone ahead on the screen")
eq(led().color, "yellow", "yellow") eq(led().pattern, "limit:37", "spelling 37")
run(2.0)
eq(shown().speedZoneActive, true, "five: in the zone on the screen")
eq(led().color, "red", "red") eq(led().flash, false, "steady")
run(2.0)
eq(shown().speedExceeding, true, "six: over the limit on the screen")
eq(led().flash, true, "red flashing")
run(2.0)
eq(shown().speedZoneActive, false, "over: no zone")
eq(led().color, "off", "dots out")
ok(notices[#notices]:find("over", 1, true) ~= nil, "and it says it is over")
extensions.raceManager_race.isActive = function() return true end
eq(B.selfTest(), false, "not during a race")
ok(notices[#notices]:find("not during a race", 1, true) ~= nil, "and says why")
extensions.raceManager_race.isActive = nil

section("the copilot stops watching and the unit goes back to their own idle car")
watching = nil
run(0.3)
eq(shown().raceActive, false, "idle again")
eq(shown().speed, 0, "own car")
eq(led().color, "off", "nothing lit")

print("")
print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
