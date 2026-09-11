-- The Stella in the car, run outside the game: the sequence he described for
-- a speed zone. About 100 m before it the dots spell the limit in flashing
-- yellow, inside they sit red, over the limit they flash red, and past the
-- zone they go out. The bridge that feeds it is run the same way.
--
--   lua tools/test_stella_client.lua

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

-- what the game gives an extension, faked
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local events = {}
guihooks = { trigger = function(name, data) events[#events + 1] = { name = name, data = data } end }

local function lastEvent(name)
  for i = #events, 1, -1 do
    if events[i].name == name then return events[i].data end
  end
  return nil
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
be = {
  getPlayerVehicle = function() return vehicle end,
  getObjectCount = function() return 0 end,
  getObject = function() return nil end,
  getObjectByID = function() return nil end,
}
extensions = {}

local S = dofile("client/lua/ge/extensions/bajaStella.lua")
S.onExtensionLoaded()

local function led() return lastEvent("BajaStella_LED") or {} end
local function tick() S.onUpdate(0.2) end
local function drive(x, mps)
  car.pos = { x = x, y = 0, z = 0 }
  car.vel = { x = mps, y = 0, z = 0 }
  tick()
end

local course = {
  { i = 1, pos = { x = 0,   y = 0, z = 0 } },
  { i = 2, pos = { x = 300, y = 0, z = 0 } },
  { i = 3, pos = { x = 600, y = 0, z = 0 } },
  { i = 4, pos = { x = 900, y = 0, z = 0 } },
}
S.setRaceState({ active = true, started = true })
S.setCourse("Test", course)
S.setNextCheckpoint(1)

local function zone(upcoming)
  return { name = "Zone 1", limitKmh = 37 * 1.609344, limitMph = 37, upcoming = upcoming,
           entryCheckpoint = 2, entryPosition = course[2].pos, warnDistance = 100 }
end

section("a zone still far ahead lights nothing")
S.setSpeedZone(zone(true))
drive(50, 20)
eq(led().color, "off", "three hundred metres out the dots are dark")
eq(lastEvent("BajaStella_SpeedZone"), nil, "and nothing has been said")

section("about a hundred metres before the zone the limit comes up in flashing yellow")
drive(205, 20)
eq(led().color, "yellow", "yellow")
eq(led().flash, true, "flashing")
eq(led().pattern, "limit:37", "spelling the limit he set, in mph")
local adv = lastEvent("BajaStella_SpeedZone")
eq(adv and adv.event, "advance", "the screen is told the zone is ahead")
local up = lastEvent("BajaStella_Update")
eq(up and up.speedZoneWarning, true, "the screen knows it is a warning")
eq(up and up.speedZoneActive, false, "and not the zone itself yet")
eq(up and up.speedZoneLimitMph, 37, "with the limit in mph")

section("inside the zone the number sits steady red")
S.setSpeedZone(zone(false))
drive(320, 15)
eq(led().color, "red", "red")
eq(led().flash, false, "steady")
eq(led().pattern, "limit:37", "still the limit")
local ent = lastEvent("BajaStella_SpeedZone")
eq(ent and ent.event, "enter", "the screen is told the zone began")
up = lastEvent("BajaStella_Update")
eq(up and up.speedZoneActive, true, "the screen knows it is inside")
eq(up and up.speedExceeding, false, "and under the limit at 34 mph")

section("over the limit the red number flashes")
drive(400, 25)
eq(led().color, "red", "red")
eq(led().flash, true, "flashing")
eq(led().pattern, "limit:37", "the limit, not a warning symbol")
local ex = lastEvent("BajaStella_SpeedZone")
eq(ex and ex.event, "exceeded", "the screen is told, so it can sound")
up = lastEvent("BajaStella_Update")
eq(up and up.speedExceeding, true, "and shows it")

section("slowing down under it goes back to steady red")
drive(450, 10)
eq(led().color, "red", "red")
eq(led().flash, false, "steady again")
eq((lastEvent("BajaStella_SpeedZone") or {}).event, "normalized", "the sound stops")

section("past the zone the display goes away")
S.setSpeedZone(nil)
drive(950, 25)
eq(led().color, "off", "dark")
eq((lastEvent("BajaStella_SpeedZone") or {}).event, "exit", "the screen is told it ended")
up = lastEvent("BajaStella_Update")
eq(up and up.speedZoneActive, false, "no zone")
eq(up and up.speedZoneWarning, false, "no warning")

section("a limit given only in km/h still spells mph on the dots")
S.setSpeedZone({ name = "Z", limitKmh = 96.56, upcoming = false, entryCheckpoint = 2 })
eq(led().pattern, "limit:60", "sixty mph")
S.setSpeedZone(nil)

-- ------------------------------------------------------------ the bridge
section("the bridge tells the Stella which zone is ahead, which is on, and when it is over")
local calls = {}
local rec = {}
for _, name in ipairs({ "setCourse", "setTrack", "setRaceState", "setProgress",
                        "setNextCheckpoint", "onVCPCrossed", "setSpeedZone" }) do
  rec[name] = function(...) calls[#calls + 1] = { name = name, args = { ... } } end
end
local status = { state = "running", next = 1, done = 0, track = "t" }
local track = { id = "t", name = "Test", checkpoints = course,
                zones = { { from = 2, to = 4, mph = 37 } } }
extensions.bajaStella = rec
extensions.raceManager_state = { get = function() return { track = track } end }
extensions.raceManager_race = { status = function() return status end }
extensions.raceManager_net = { on = function() end }

local B = dofile("client/lua/ge/extensions/raceManager/stella.lua")
B.onExtensionLoaded()

local function lastZoneCall()
  for i = #calls, 1, -1 do
    if calls[i].name == "setSpeedZone" then return calls[i].args[1], true end
  end
  return nil, false
end

B.onUpdate(0.2)
local z, sent = lastZoneCall()
ok(sent and type(z) == "table", "heading for gate 1, the zone from gate 2 is announced as ahead")
eq(z and z.upcoming, true, "ahead")
eq(z and z.limitMph, 37, "in mph")
eq(z and z.warnDistance, 100, "with the hundred metre warning he asked for")
eq(z and z.entryPosition and z.entryPosition.x, 300, "and where its entry gate stands")

status.next, status.done = 3, 2
B.onUpdate(0.2)
z = lastZoneCall()
eq(z and z.upcoming, false, "past gate 2 and heading for 3, the zone is on")

status.next, status.done = 4, 3
local before = #calls
B.onUpdate(0.2)
local zoneCalls = 0
for i = before + 1, #calls do if calls[i].name == "setSpeedZone" then zoneCalls = zoneCalls + 1 end end
eq(zoneCalls, 0, "heading for gate 4 changes nothing about the zone, only the progress")

status.next, status.done = 5, 4
B.onUpdate(0.2)
z, sent = lastZoneCall()
ok(sent and z == nil, "past gate 4 the zone is taken down")

print("")
if fail > 0 then
  print(("%d passed, %d failed"):format(pass, fail))
  os.exit(1)
end
print(("%d passed, 0 failed"):format(pass))
