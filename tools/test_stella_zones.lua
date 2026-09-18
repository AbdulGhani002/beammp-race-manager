-- The speed zones on the Stella, unit and bridge together, the way he set
-- them out: a zone of either kind warns two hundred metres out, is on
-- while the car is in it, and once the car leaves it nothing warns for
-- five seconds, then any zone near by can warn again. A box is measured
-- by the same poll that tells the server the car is in it.
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
local hooked = {}
guihooks = { trigger = function(name, d)
  if name == "RMSI_Update" and type(d) == "table" then
    for _, s in ipairs(d.sounds or {}) do hooked[#hooked + 1] = s end
  end
end }

local car = { pos = { x = 0, y = 0, z = 0 }, vel = { x = 0, y = 0, z = 0 }, dir = { x = 1, y = 0, z = 0 } }
local function vec(t)
  return { x = t.x, y = t.y, z = t.z,
           length = function(self) return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end }
end
local vehicle = {
  getPosition = function() return vec(car.pos) end,
  getVelocity = function() return vec(car.vel) end,
  getDirectionVector = function() return vec(car.dir) end,
  getID = function() return 1 end,
}
be = { getPlayerVehicle = function() return vehicle end, getObjectCount = function() return 0 end,
       getObject = function() return nil end, getObjectByID = function() return nil end }

local notices = {}
local status = { state = "running", next = 2, done = 1, track = "t" }
local course = {
  { i = 1, pos = { x = 0,    y = 0, z = 0 } },
  { i = 2, pos = { x = 300,  y = 0, z = 0 } },
  { i = 3, pos = { x = 600,  y = 0, z = 0 } },
  { i = 4, pos = { x = 900,  y = 0, z = 0 } },
  { i = 5, pos = { x = 1200, y = 0, z = 0 } },
  { i = 6, pos = { x = 1500, y = 0, z = 0 } },
  { i = 7, pos = { x = 1800, y = 0, z = 0 } },
  { i = 8, pos = { x = 2100, y = 0, z = 0 } },
}
local track = { id = "t", name = "Test", checkpoints = course, zones = {} }
-- what the poll in triggers.lua answers: the box, in or out, distance to its face
local szNow = nil
extensions = {
  raceManager_net = { on = function() end, send = function() return true end },
  raceManager_state = { notice = function(t) notices[#notices + 1] = t end, get = function() return { track = track } end },
  raceManager_race = { status = function() return status end },
  raceManager_triggers = { szState = function() return szNow end },
}

local S = dofile("client/lua/ge/extensions/raceManager/stellaUnit.lua")
S.onExtensionLoaded()
extensions.raceManager_stellaUnit = S
local B = dofile("client/lua/ge/extensions/raceManager/stella.lua")
B.onExtensionLoaded()
extensions.raceManager_stella = B

local function snap() return S.getSnapshot() end
local function led() local s = snap() return { color = s.ledColor, flash = s.ledFlash, pattern = s.ledPattern } end
-- the sounds go out with the hook, every other tick; whatever is still
-- waiting in the unit counts too
local function sounds()
  local out = hooked
  hooked = {}
  for _, s in ipairs(S.drainSounds()) do out[#out + 1] = s end
  return out
end
local function has(list, name) for _, n in ipairs(list) do if n == name then return true end end return false end
local function drive(x, mps, seconds)
  car.pos = { x = x, y = 0, z = 0 }
  car.vel = { x = mps, y = 0, z = 0 }
  local t = 0
  while t < (seconds or 0.2) - 1e-9 do B.onUpdate(0.1) S.onUpdate(0.1) t = t + 0.1 end
end
local function mph(v) return v / 2.23694 end
local BOX = { i = 1, mph = 20, pos = { x = 500, y = 0, z = 0 } }
local BOX2 = { i = 2, mph = 30, pos = { x = 900, y = 0, z = 0 } }
-- courses captured by an older build, or edited by hand, spell the limit
-- other ways or leave it off altogether
local BOX3 = { i = 3, limitMph = 45, pos = { x = 1300, y = 0, z = 0 } }
local BOX4 = { i = 4, limitKmh = 40.2336, pos = { x = 1700, y = 0, z = 0 } }
local BOX5 = { i = 5, pos = { x = 2000, y = 0, z = 0 } }
local function box(inside, dist, which)
  which = which or BOX
  szNow = { box = which, inside = inside, dist = inside and 0 or dist,
            face = { x = which.pos.x - 25, y = 0, z = 0 } }
end

section("a gate to gate zone: warned two hundred metres before its first gate")
track.zones = { { from = 2, to = 4, mph = 37 } }
drive(40, mph(30), 0.5)
sounds()
eq(snap().raceActive, true, "racing")
eq(snap().speedZoneWarning, false, "two hundred and sixty metres out, no warning")
eq(led().color, "off", "nothing lit")
drive(120, mph(30))
eq(snap().speedZoneWarning, true, "a hundred and eighty metres out the warning is up")
eq(snap().speedZoneLimitMph, 37, "with the limit")
eq(led().color, "yellow", "the dots spell it in yellow")
eq(led().pattern, "all", "the limit")
eq(led().flash, false, "solid, not flashing")
ok(has(sounds(), "advance"), "and the warning sound plays once")
drive(200, mph(30))
eq(#sounds(), 0, "not again closer in")

section("through its first gate the zone is on")
status.next, status.done = 3, 2
drive(320, mph(30))
eq(snap().speedZoneActive, true, "on")
eq(snap().speedZoneWarning, false, "not a warning any more")
eq(led().color, "green", "the gate's green first")
ok(has(sounds(), "enter"), "the entry sound")
drive(330, mph(30), 3.2)
eq(led().color, "yellow", "and yellow dots once the green is over, holding the limit")
eq(led().flash, false, "steady")
drive(400, mph(45), 0.3)
eq(snap().speedExceeding, true, "over the limit")
eq(led().color, "red", "and red the moment it goes over")
ok(has(sounds(), "exceed"), "with the sound")
drive(450, mph(30), 0.3)
eq(led().flash, false, "under it, steady again")

section("past its last gate the zone goes, with the beep, and nothing warns for five seconds")
track.zones = { { from = 2, to = 4, mph = 37 }, { from = 5, to = 6, mph = 25 } }
status.next, status.done = 5, 4
sounds()
drive(950, mph(30))
eq(snap().speedZoneActive, false, "the zone is gone")
ok(has(sounds(), "vcp"), "with the beep on the way out")
eq(led().color, "green", "gate 4's green")
drive(960, mph(30), 3.2)
eq(led().color, "off", "then the dots are out")
eq(snap().speedZoneWarning, false, "the next zone, though it starts at gate 5, is not warned of yet")
drive(1050, mph(30), 1.5)
eq(snap().speedZoneWarning, false, "not four and a half seconds after leaving either")
drive(1060, mph(30), 1.0)
eq(snap().speedZoneWarning, true, "five seconds after leaving, the next zone is warned of")
eq(led().pattern, "all", "with its limit")
status.next, status.done = 6, 5
drive(1220, mph(20), 3.3)
eq(snap().speedZoneActive, true, "and it is on through its gate")
eq(led().color, "yellow", "yellow, holding it")
status.next, status.done = 7, 6
drive(1520, mph(20), 3.3)
eq(snap().speedZoneActive, false, "off past it")
track.zones = {}
drive(1530, mph(20), 5.2)
eq(led().color, "off", "and the dots are out")

section("a box: warned two hundred metres from its nearest face, on inside, and measured on this side")
sounds()
box(false, 260)
drive(215, mph(30), 0.3)
eq(snap().speedZoneWarning, false, "two hundred and sixty metres from the face, nothing")
eq(led().color, "off", "dots dark")
box(false, 180)
drive(295, mph(30), 0.3)
eq(snap().speedZoneWarning, true, "a hundred and eighty metres from the face, warned")
eq(snap().speedZoneLimitMph, 20, "with the box's limit")
eq(led().color, "yellow", "yellow")
eq(led().pattern, "all", "spelling twenty")
eq(led().flash, false, "solid")
ok(has(sounds(), "advance"), "the warning sound, once")
box(false, 60)
drive(415, mph(30), 0.5)
eq(#sounds(), 0, "and not again nearer")
box(true, 0)
drive(500, mph(15), 0.3)
eq(snap().speedZoneActive, true, "inside, the zone is on")
eq(snap().speedZoneWarning, false, "not ahead")
eq(led().color, "yellow", "yellow dots, holding the limit")
eq(led().pattern, "all", "twenty")
eq(led().flash, false, "steady under the limit")
ok(has(sounds(), "enter"), "the entry sound")
drive(510, mph(15), 1.0)
eq(#sounds(), 0, "one entry sound, not one a tick")
eq(snap().speedZoneActive, true, "still on a second later, nothing took it down")
drive(520, mph(30), 0.3)
eq(snap().speedExceeding, true, "thirty in a twenty is over")
eq(led().color, "red", "red over it")
ok(has(sounds(), "exceed"), "with the sound")
drive(525, mph(15), 0.3)
eq(led().flash, false, "steady again under it")

section("leaving the box: the beep, and the box you just left does not warn again for five seconds")
box(false, 1)
sounds()
drive(526, mph(15), 0.2)
eq(snap().speedZoneActive, false, "out, the zone is gone")
ok(has(sounds(), "vcp"), "with the beep")
eq(led().color, "off", "dots out")
box(false, 30)
drive(555, mph(15), 2.0)
eq(snap().speedZoneWarning, false, "thirty metres from the face, two seconds later, no warning")
eq(#sounds(), 0, "and no sound")
drive(560, mph(15), 3.1)
eq(snap().speedZoneWarning, false, "five seconds on, the box just driven through does not call itself upcoming")
eq(led().color, "off", "dots out")
eq(#sounds(), 0, "and no sound")

-- and it is the box just driven through that is quiet, not every box: a
-- different one near by warns as soon as the five seconds are up
box(false, 150, BOX2)
drive(750, mph(30), 0.3)
eq(snap().speedZoneWarning, true, "a different box within two hundred warns")
eq(led().color, "yellow", "yellow")
eq(led().pattern, "all", "with its own limit")
ok(has(sounds(), "advance"), "and the sound")

box(false, 250)
drive(780, mph(30), 0.3)
eq(snap().speedZoneWarning, false, "driven away, the warning goes")
eq(led().color, "off", "dots out")
eq(#sounds(), 0, "and driving away from a warning is not leaving a zone: no beep")
box(false, 150)
drive(680, mph(30), 0.3)
eq(snap().speedZoneWarning, true, "clear of the first box, back within two hundred, it warns again")
eq(led().pattern, "all", "with its limit")

section("a box takes the unit over a gate zone the car is also in")
track.zones = { { from = 2, to = 4, mph = 37 } }
status.next, status.done = 3, 2
box(false, 300)
drive(320, mph(30), 3.3)
eq(snap().speedZoneLimitMph, 37, "the gate zone's limit")
box(true, 0)
drive(500, mph(15), 0.3)
eq(snap().speedZoneLimitMph, 20, "in the box, the box's limit")
eq(snap().speedZoneActive, true, "on")
box(false, 1)
drive(530, mph(15), 0.3)
eq(snap().speedZoneLimitMph, 37, "out of the box, the gate zone is on again")
eq(snap().speedZoneActive, true, "on")
track.zones = {}
szNow = nil
drive(540, mph(15), 5.3)

section("the red button during a race, with a zone on")
box(true, 0)
drive(500, mph(15), 0.5)
eq(led().color, "yellow", "the zone's yellow")
S.toggleMechanicalBreakdown()
drive(500, mph(0), 0.5)
eq(led().color, "yellow", "the red button's yellow wins")
eq(led().pattern, "triangle", "the triangle")
eq(snap().breakdownActive, true, "shown as stopped")
S.toggleMechanicalBreakdown()
drive(500, mph(15), 0.5)
eq(led().color, "yellow", "moving again, back to the zone")
eq(snap().breakdownActive, false, "not stopped")

section("the race ends: the zone goes, and the quiet time with it")
status.state = "idle"
drive(500, mph(0), 0.5)
eq(snap().raceActive, false, "idle")
eq(snap().speedZoneActive, false, "no zone")
eq(led().color, "off", "dots out")
status.state, status.next, status.done = "running", 2, 1
box(false, 100)
drive(400, mph(30), 0.5)
eq(snap().speedZoneWarning, true, "a new race warns of a box near by at once, the old quiet time is over")
szNow = nil
status.state = "idle"
drive(400, mph(0), 0.3)

section("a pass of your own sits under a zone; a pass to answer sits under a zone the car is in")
status.state, status.next, status.done = "running", 2, 1
track.zones = {}
szNow = nil
drive(100, mph(30), 5.3)
sounds()
S.onRaceManagerPassStatus({ state = "delivered", requestId = 1, aheadName = "Sam" })
drive(100, mph(30), 0.3)
eq(led().color, "green", "delivered: green")
eq(led().pattern, "all", "lines")
box(false, 150)
drive(330, mph(30), 0.3)
eq(led().color, "yellow", "a box ahead: its yellow over the pass")
eq(led().pattern, "all", "spelling the limit")
box(true, 0)
drive(500, mph(15), 0.3)
eq(led().color, "yellow", "in the box: the zone over the pass")
S.onRaceManagerPassAlert({ requesterName = "Sam", requestId = 2 })
drive(500, mph(15), 0.3)
eq(led().color, "yellow", "and a pass to answer waits behind a zone the car is in")
box(false, 1)
drive(530, mph(15), 0.3)
eq(led().color, "blue", "out of it, the pass to answer shows")
eq(led().pattern, "all", "blue lines")
S.onRaceManagerPassStatus({ state = "cancelled" })
drive(540, mph(15), 5.3)
eq(led().color, "off", "cancelled, dots out")

section("a box that spells its limit another way, or carries none, is still a box")
status.state, status.next, status.done = "running", 2, 1
track.zones = {}
szNow = nil
drive(1200, mph(30), 5.3)
sounds()

box(false, 150, BOX3)
drive(1150, mph(30), 0.3)
eq(snap().speedZoneWarning, true, "limitMph is read")
eq(snap().speedZoneLimitMph, 45, "at its own limit")
eq(led().pattern, "all", "and the dots spell it")

box(false, 150, BOX4)
drive(1550, mph(30), 0.3)
eq(snap().speedZoneWarning, true, "a limit in km/h is read")
eq(snap().speedZoneLimitMph, 25, "turned into mph")
eq(led().pattern, "all", "and spelled")

box(true, 0, BOX5)
drive(2000, mph(15), 0.3)
eq(snap().speedZoneActive, true, "a box with no limit at all is still a zone the car is in")
eq(led().color, "yellow", "yellow, holding the limit")
eq(snap().speedZoneLimitMph, 37, "at the same default the server gives a new box")
eq(led().pattern, "all", "and the dots say so rather than going dark")
box(false, 1, BOX5)
drive(2030, mph(15), 0.3)
szNow = nil
drive(2100, mph(15), 5.3)

print("")
print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
