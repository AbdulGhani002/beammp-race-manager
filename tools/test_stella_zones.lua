-- The speed zone on the Stella, unit and bridge together, the way a race
-- feeds them: a gate to gate zone from the course, and a box zone the
-- server switches on and off. What he saw: the beep and nothing on the
-- screen or the dots.
--
--   lua tools/test_stella_zones.lua

local pass, fail = 0, 0
local function ok(cond, what)
  if cond then pass = pass + 1 else fail = fail + 1 print("  FAIL  " .. what) end
end
local function eq(got, want, what)
  ok(got == want, ("%s (got %s, wanted %s)"):format(what, tostring(got), tostring(want)))
end
local function section(t) print("") print("== " .. t) end

math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local events = {}
guihooks = { trigger = function(name, data) events[#events + 1] = { name = name, data = data } end }
local function lastEvent(name)
  for i = #events, 1, -1 do if events[i].name == name then return events[i].data end end
  return nil
end
local function eventsOf(name, since)
  local out = {}
  for i = (since or 0) + 1, #events do if events[i].name == name then out[#out + 1] = events[i].data end end
  return out
end

local car = { pos = { x = 0, y = 0, z = 0 }, vel = { x = 0, y = 0, z = 0 } }
local function vec(t)
  return { x = t.x, y = t.y, z = t.z,
           length = function(self) return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end }
end
local vehicle = {
  getPosition = function() return vec(car.pos) end,
  getVelocity = function() return vec(car.vel) end,
  getDirectionVector = function() return vec({ x = 1, y = 0, z = 0 }) end,
  getID = function() return 1 end,
}
be = { getPlayerVehicle = function() return vehicle end, getObjectCount = function() return 0 end,
       getObject = function() return nil end, getObjectByID = function() return nil end }

local handlers, notices = {}, {}
local status = { state = "running", next = 2, done = 1, track = "t" }
local course = {
  { i = 1, pos = { x = 0,    y = 0, z = 0 } },
  { i = 2, pos = { x = 300,  y = 0, z = 0 } },
  { i = 3, pos = { x = 600,  y = 0, z = 0 } },
  { i = 4, pos = { x = 900,  y = 0, z = 0 } },
}
local track = { id = "t", name = "Test", checkpoints = course, zones = {} }
local box = nil      -- what nearestSz answers: box, inside, dist, face
extensions = {
  raceManager_net = { on = function(ch, fn) handlers[ch] = fn end, send = function() return true end },
  raceManager_state = { notice = function(t) notices[#notices + 1] = t end, get = function() return { track = track } end },
  raceManager_race = { status = function() return status end },
  raceManager_copilot = { status = function() return { watching = nil } end },
  raceManager_triggers = { nearestSz = function(pos)
    if not box then return nil end
    local inside = math.abs(pos.x - box.pos.x) <= 25
    local dist = inside and 0 or (math.abs(pos.x - box.pos.x) - 25)
    return box, inside, dist, { x = box.pos.x - 25, y = 0, z = 0 }
  end },
}

local S = dofile("client/lua/ge/extensions/raceManager/stellaUnit.lua")
S.onExtensionLoaded()
extensions.raceManager_stellaUnit = S
local B = dofile("client/lua/ge/extensions/raceManager/stella.lua")
B.onExtensionLoaded()
extensions.raceManager_stella = B

local function led() return lastEvent("RmStella_LED") or {} end
local function shown() return lastEvent("RmStella_Update") or {} end
local function drive(x, mps, seconds)
  car.pos = { x = x, y = 0, z = 0 }
  car.vel = { x = mps, y = 0, z = 0 }
  local t = 0
  while t < (seconds or 0.2) - 1e-9 do B.onUpdate(0.1) S.onUpdate(0.1) t = t + 0.1 end
end
local function mph(v) return v / 2.23694 end

section("a gate to gate zone on the course, during a race")
track.zones = { { from = 2, to = 4, mph = 37 } }
drive(50, mph(30))
eq(shown().raceActive, true, "racing")
eq(shown().speedZoneWarning, false, "far from the zone, no warning yet")
eq(led().color, "off", "and nothing lit")
drive(220, mph(30))
eq(shown().speedZoneWarning, true, "eighty metres before gate 2 the warning is up")
eq(shown().speedZoneLimitMph, 37, "with the limit")
eq(led().color, "yellow", "the dots spell it in yellow")
eq(led().pattern, "limit:37", "the limit")
eq(led().flash, true, "flashing")
eq((eventsOf("RmStella_SpeedZone")[#eventsOf("RmStella_SpeedZone")] or {}).event, "advance", "and the screen was told to beep")
status.next, status.done = 3, 2
drive(320, mph(30))
eq(shown().speedZoneActive, true, "through gate 2 the zone is on")
eq(shown().speedZoneWarning, false, "not a warning any more")
eq(led().color, "green", "the gate's green first")
drive(330, mph(30), 2.0)
eq(led().color, "red", "and red dots once its two seconds are up")
eq(led().flash, false, "steady")
drive(400, mph(45), 0.3)
eq(shown().speedExceeding, true, "over the limit")
eq(led().flash, true, "the red flashes")
drive(450, mph(30), 0.3)
eq(led().flash, false, "under it, steady again")
status.next, status.done = 5, 4
drive(950, mph(30))
eq(shown().speedZoneActive, false, "past gate 4 the zone is gone")
eq(led().color, "green", "gate 4's green")
drive(960, mph(30), 2.0)
eq(led().color, "off", "then the dots are out")

section("a box zone the server switches on: the display stays up while the car is in it")
track.zones = {}
status.next, status.done = 2, 1
drive(50, mph(30), 0.3)
eq(led().color, "off", "nothing lit to begin with")
-- the car's own trigger fires, the server says on, and the course's box is found under the car
box = { i = 1, mph = 20, pos = { x = 500, y = 0, z = 0 } }
car.pos = { x = 500, y = 0, z = 0 }
handlers["zone.warn"] = nil
local n0 = #events
-- race.lua hands the server's word to the bridge like this
B.setPairZone({ mph = 20, pair = "1", box = true })
drive(500, mph(15), 1.0)
eq(shown().speedZoneActive, true, "on, and still on a second later")
eq(shown().speedZoneLimitMph, 20, "twenty")
eq(led().color, "red", "red dots")
eq(led().pattern, "limit:20", "spelling twenty")
local zoneEvents = eventsOf("RmStella_SpeedZone", n0)
local enters, exits = 0, 0
for _, e in ipairs(zoneEvents) do
  if e.event == "enter" then enters = enters + 1 elseif e.event == "exit" then exits = exits + 1 end
end
eq(enters, 1, "one beep, not one every tick")
eq(exits, 0, "and no exit while the car is in it")

section("the same box, when the course's boxes are not to hand on this side")
B.setPairZone(nil)
drive(50, mph(30), 0.3)
eq(shown().speedZoneActive, false, "off")
box = nil
n0 = #events
B.setPairZone({ mph = 20, pair = "1", box = true })
drive(50, mph(15), 1.0)
eq(shown().speedZoneActive, true, "the server said on, so it is on, whatever this side can see")
eq(led().color, "red", "red dots")
zoneEvents = eventsOf("RmStella_SpeedZone", n0)
enters, exits = 0, 0
for _, e in ipairs(zoneEvents) do
  if e.event == "enter" then enters = enters + 1 elseif e.event == "exit" then exits = exits + 1 end
end
eq(enters, 1, "one beep")
eq(exits, 0, "and it is not taken down again a tick later")
B.setPairZone(nil)
drive(50, mph(30), 0.3)
eq(shown().speedZoneActive, false, "off when the server says off")
eq(led().color, "off", "dots out")

section("the red button during a race, with a zone on")
box = { i = 1, mph = 20, pos = { x = 500, y = 0, z = 0 } }
car.pos = { x = 500, y = 0, z = 0 }
B.setPairZone({ mph = 20, pair = "1", box = true })
drive(500, mph(15), 0.5)
eq(led().color, "red", "the zone's red")
S.toggleMechanicalBreakdown()
drive(500, mph(0), 0.5)
eq(led().color, "yellow", "the red button's yellow wins")
eq(led().pattern, "triangle", "the triangle")
eq(shown().ledColor, "yellow", "and every update says so")
eq(shown().breakdownActive, true, "shown as stopped")
S.toggleMechanicalBreakdown()
drive(500, mph(15), 0.5)
eq(led().color, "red", "moving again, back to the zone")
B.setPairZone(nil)
box = nil

section("the race ends: the zone goes, and the unit is told once")
status.state = "idle"
drive(50, mph(0), 0.5)
eq(shown().raceActive, false, "idle")
eq(shown().speedZoneActive, false, "no zone")
eq(led().color, "off", "dots out")

print("")
print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
