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

local S = dofile("client/lua/ge/extensions/raceManager/stellaUnit.lua")
S.onExtensionLoaded()

-- his unit says nothing on its own: the screen polls it. So the tests read
-- the snapshot the screen would, and the sounds it would play.
local function snap() return S.getSnapshot() end
local function led() local s = snap() return { color = s.ledColor, flash = s.ledFlash, pattern = s.ledPattern } end
-- the sounds go out with the hook, every other tick, and are read off the
-- hooks caught above; whatever is still waiting in the unit counts too
local seenEvents = 0
local function sounds()
  local out = {}
  for i = seenEvents + 1, #events do
    local e = events[i]
    if e.name == "RMSI_Update" and type(e.data) == "table" then
      for _, s in ipairs(e.data.sounds or {}) do out[#out + 1] = s end
    end
  end
  seenEvents = #events
  for _, s in ipairs(S.drainSounds()) do out[#out + 1] = s end
  return out
end
local function has(list, name) for _, n in ipairs(list) do if n == name then return true end end return false end
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
           entryCheckpoint = 2, entryPosition = { x = 300, y = 0, z = 0 }, warnDistance = 200 }
end

section("a zone still far ahead lights nothing")
S.setSpeedZone(zone(true))
sounds()
drive(50, 20)
eq(led().color, "off", "two hundred and fifty metres out the dots are dark")
eq(#sounds(), 0, "and nothing has been said")
eq(snap().speedZoneWarning, false, "and the screen is not told of a zone")

section("about two hundred metres before the zone the limit comes up in flashing yellow")
drive(120, 20)
eq(led().color, "yellow", "yellow")
eq(led().flash, true, "flashing")
eq(led().pattern, "limit:37", "spelling the limit he set, in mph")
ok(has(sounds(), "advance"), "with the warning sound, once")
eq(snap().speedZoneWarning, true, "and the screen is told the zone is ahead")
eq(snap().speedZoneLimitMph, 37, "with the limit in mph")
drive(150, 20)
eq(#sounds(), 0, "closer in, the sound is not played again")

section("inside the zone the number sits steady red")
S.setSpeedZone(zone(false))
drive(320, 15)
eq(led().color, "red", "red")
eq(led().flash, false, "steady")
eq(led().pattern, "limit:37", "still the limit")
ok(has(sounds(), "enter"), "the entry sound")
eq(snap().speedZoneActive, true, "the screen is told the zone is on")
eq(snap().speedZoneWarning, false, "and not ahead any more")

section("over the limit the red number flashes")
drive(400, 25)
eq(led().color, "red", "red")
eq(led().flash, true, "flashing")
eq(led().pattern, "limit:37", "the limit, not a warning symbol")
ok(has(sounds(), "exceed"), "the over the limit sound")
eq(snap().speedExceeding, true, "and the screen is told")

section("slowing down under it goes back to steady red")
drive(450, 10)
eq(led().color, "red", "red")
eq(led().flash, false, "steady again")
eq(snap().speedExceeding, false, "the screen stops the sound")

section("past the zone the display goes away, with the beep he asked for on the way out")
S.setSpeedZone(nil)
tick()
eq(led().color, "off", "dots out")
ok(has(sounds(), "vcp"), "the exit beep")
eq(snap().speedZoneActive, false, "no zone on the screen")

section("a limit given only in km/h still spells mph on the dots")
S.setSpeedZone({ name = "Zone 2", limitKmh = 37 * 1.609344, upcoming = false })
tick()
eq(led().pattern, "limit:37", "thirty seven")
eq(snap().speedZoneLimitMph, 37, "on the screen too")
S.setSpeedZone(nil)
tick()

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
extensions.raceManager_stellaUnit = rec
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
eq(z and z.warnDistance, 200, "with the two hundred metre warning he asked for")
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

section("two zones back to back hand over at the shared gate")
track.zones = { { from = 1, to = 2, mph = 37 }, { from = 2, to = 4, mph = 20 } }
status.next, status.done = 2, 1
B.onUpdate(0.2)
z = lastZoneCall()
eq(z and z.upcoming, false, "past gate 1, the first is on")
eq(z and z.limitMph, 37, "at thirty seven")
status.next, status.done = 3, 2
B.onUpdate(0.2)
z = lastZoneCall()
eq(z and z.upcoming, false, "past gate 2, the second is on")
eq(z and z.limitMph, 20, "at twenty")
status.next, status.done = 5, 4
B.onUpdate(0.2)
z, sent = lastZoneCall()
ok(sent and z == nil, "past gate 4 there is nothing")

section("a zone from the start line comes round again on the next lap, once the quiet time is over")
track.zones = { { from = 1, to = 2, mph = 37 } }
status.next, status.done = 1, 4
B.onUpdate(0.2)
z = lastZoneCall()
ok(z == nil, "for five seconds after leaving the last zone, nothing is warned of")
for _ = 1, 26 do B.onUpdate(0.2) end
z = lastZoneCall()
eq(z and z.upcoming, true, "waiting on the line, the zone from gate 1 is ahead")
eq(z and z.entryPosition and z.entryPosition.x, 0, "with the start line as its entry")

section("the Stella hands over from one zone to the next at a shared gate, without a beep of its own")
sounds()
S.setSpeedZone({ name = "A", limitKmh = 59.5, limitMph = 37, upcoming = false, entryCheckpoint = 1 })
ok(has(sounds(), "enter"), "the first begins with the entry sound")
S.setSpeedZone({ name = "B", limitKmh = 32.2, limitMph = 20, upcoming = false, entryCheckpoint = 2 })
eq(#sounds(), 0, "the second takes over in silence: the gate between them has a sound of its own")
tick()
eq(led().pattern, "limit:20", "and the dots spell the new limit")
S.setSpeedZone(nil)

print("")
if fail > 0 then
  print(("%d passed, %d failed"):format(pass, fail))
  os.exit(1)
end
print(("%d passed, 0 failed"):format(pass))
