-- The whole client side of a box zone with nothing faked but the game: the
-- real triggers.lua measuring the car against a real box, telling the
-- server once per change with two metres of slack, and the real unit and
-- bridge showing what that same measurement says.
--
--   lua tools/test_stella_boxes_real.lua

local pass, fail = 0, 0
local function ok(cond, what)
  if cond then pass = pass + 1 else fail = fail + 1 print("  FAIL  " .. what) end
end
local function eq(got, want, what)
  ok(got == want, ("%s (got %s, wanted %s)"):format(what, tostring(got), tostring(want)))
end
local function section(t) print("") print("== " .. t) end

-- the game, faked: only what triggers.lua needs to build and measure
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
ColorF = function() return {} end
ColorI = function() return {} end
String = function(s) return s end
vec3 = function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
quat = function(x, y, z, w)
  return { x = x, y = y, z = z, w = w, toTorqueQuat = function(self) return { x = self.x, y = self.y, z = self.z, w = self.w } end }
end
local made = {}
createObject = function(kind)
  local o = { kind = kind, fields = {} }
  function o:setField(k, _, v) self.fields[k] = v end
  function o:registerObject(name) self.name = name made[name] = self end
  function o:setPosition(p) self.pos = p end
  function o:setScale(s) self.scale = s end
  function o:setRotation(q) self.rot = q end
  return o
end
scenetree = { findObject = function() return nil end }
debugDrawer = setmetatable({}, { __index = function() return function() end end })
core_camera = { getPosition = function() return vec3(0, 0, 0) end }
log = function() end
guihooks = { trigger = function() end }

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
  getPlayerVehicleID = function() return 1 end,
  getObjectCount = function() return 0 end,
  getObject = function() return nil end,
  getObjectByID = function() return nil end,
}

local sent, notices = {}, {}
local function sentOf(ch)
  local out = {}
  for _, m in ipairs(sent) do if m.ch == ch then out[#out + 1] = m.d end end
  return out
end
local status = { state = "running", next = 2, done = 1, track = "t" }
-- a straight course east along x, and one box forty metres long from 480 to
-- 520, twenty wide, with a twenty limit
local course = {
  { i = 1, pos = { x = 0,    y = 0, z = 0 }, yaw = 0 },
  { i = 2, pos = { x = 300,  y = 0, z = 0 }, yaw = 0 },
  { i = 3, pos = { x = 900,  y = 0, z = 0 }, yaw = 0 },
}
local track = {
  id = "t", name = "Test", checkpoints = course, zones = {},
  szGates = { { i = 1, mph = 20, pos = { x = 500, y = 0, z = 0 }, yaw = 0, size = { w = 20, h = 8, d = 40 } } },
}
extensions = {
  raceManager_net = { on = function() end, send = function(ch, d) sent[#sent + 1] = { ch = ch, d = d } return true end },
  raceManager_state = { notice = function(t) notices[#notices + 1] = t end, get = function() return { track = track } end },
  raceManager_race = { status = function() return status end },
  raceManager_clock = { now = function() return 0 end },
  raceManager_capture = { onGatePassed = function() end },
}

local T = dofile("client/lua/ge/extensions/raceManager/triggers.lua")
extensions.raceManager_triggers = T
local S = dofile("client/lua/ge/extensions/raceManager/stellaUnit.lua")
S.onExtensionLoaded()
extensions.raceManager_stellaUnit = S
local B = dofile("client/lua/ge/extensions/raceManager/stella.lua")
B.onExtensionLoaded()
extensions.raceManager_stella = B

local function snap() return S.getSnapshot() end
local function led() local s = snap() return { color = s.ledColor, flash = s.ledFlash, pattern = s.ledPattern } end
-- the car at a place, for a while: the volumes poll every frame, the bridge
-- and the unit on their own clocks
local function drive(x, y, mps, seconds)
  car.pos = { x = x, y = y or 0, z = 0 }
  car.vel = { x = mps or 0, y = 0, z = 0 }
  local t = 0
  while t < (seconds or 0.2) - 1e-9 do
    T.onUpdate()
    B.onUpdate(0.1)
    S.onUpdate(0.1)
    t = t + 0.1
  end
end

section("the race puts the volumes up, the box among them, and the box is where the course says")
local n = T.startRace(track, 2)
eq(n, 3, "three gates built")
local box = made["rm_sz_1"]
ok(box ~= nil, "and the box volume, under its own name")
eq(box and box.fields.triggerMode, "Overlaps", "as a trigger the car overlaps")
ok(box and math.abs(box.pos.x - 500) < 0.01 and math.abs(box.pos.y) < 0.01, "centred where it was marked")
ok(box and math.abs(box.scale.x - 40) < 0.01 and math.abs(box.scale.y - 20) < 0.01,
   ("forty metres along the road, twenty across (%s x %s)"):format(tostring(box and box.scale.x), tostring(box and box.scale.y)))

section("far from the box the poll says nothing and the unit shows nothing")
drive(100, 0, 20, 0.3)
eq(#sentOf("sz.state"), 0, "nothing sent")
local sz = T.szState()
ok(sz ~= nil and sz.inside == false, "measured: out")
ok(sz and math.abs(sz.dist - 380) < 0.01, ("three hundred and eighty metres from the near face (%s)"):format(tostring(sz and sz.dist)))
eq(snap().speedZoneWarning, false, "no warning on the unit")
eq(led().color, "off", "dots dark")

section("two hundred metres from the near face the unit warns; the server is not told, it judges nothing outside")
drive(290, 0, 20, 0.3)
sz = T.szState()
ok(sz and math.abs(sz.dist - 190) < 0.01, ("a hundred and ninety metres out (%s)"):format(tostring(sz and sz.dist)))
eq(snap().speedZoneWarning, true, "warned")
eq(snap().speedZoneLimitMph, 20, "with the box's limit")
eq(led().color, "yellow", "yellow dots")
eq(led().pattern, "limit:20", "spelling twenty")
eq(#sentOf("sz.state"), 0, "and the server has heard nothing: outside is outside")

section("across the near face: one message, in, and the unit goes red")
drive(485, 0, 8, 0.3)
sz = T.szState()
eq(sz and sz.inside, true, "measured: in")
local msgs = sentOf("sz.state")
eq(#msgs, 1, "the server is told once")
eq(msgs[1] and msgs[1].inside, true, "in")
eq(msgs[1] and msgs[1].mph, 20, "at twenty")
eq(msgs[1] and msgs[1].i, 1, "box one")
eq(snap().speedZoneActive, true, "the unit shows the zone on")
eq(led().color, "red", "red dots")
drive(505, 3, 8, 1.0)
eq(#sentOf("sz.state"), 1, "driving about inside it, nothing more is sent")
eq(snap().speedZoneActive, true, "and the zone stays on")

section("the edge: two metres of slack, so a car sat on the line does not flicker")
drive(521, 0, 2, 0.2)
eq(#sentOf("sz.state"), 1, "a metre past the face, still in, nothing sent")
eq(T.szState().inside, true, "measured: still in")
drive(519, 0, 2, 0.2)
drive(521, 0, 2, 0.2)
drive(520.5, 0, 2, 0.2)
eq(#sentOf("sz.state"), 1, "back and forth over the line, nothing sent")
eq(snap().speedZoneActive, true, "and the unit never blinked")

section("clear of the box: one message, out, the beep, and five quiet seconds")
drive(523, 0, 5, 0.2)
msgs = sentOf("sz.state")
eq(#msgs, 2, "the server is told once more")
eq(msgs[2] and msgs[2].inside, false, "out")
eq(T.szState().inside, false, "measured: out")
eq(snap().speedZoneActive, false, "the zone is off the unit")
eq(led().color, "off", "dots dark")
drive(560, 0, 20, 2.0)
eq(snap().speedZoneWarning, false, "forty metres from the far face, two seconds on, no warning: quiet time")
drive(600, 0, 20, 3.2)
eq(snap().speedZoneWarning, true, "past the five seconds, eighty metres from the far face, warned of the box behind")
eq(#sentOf("sz.state"), 2, "and nothing more went to the server")

section("the volume's own voice is ignored: only the poll speaks for a box")
local before = #sent
T.onBeamNGTrigger({ triggerName = "rm_sz_1", event = "enter", subjectID = 1 })
T.onBeamNGTrigger({ triggerName = "rm_sz_1", event = "exit", subjectID = 1 })
eq(#sent, before, "nothing sent for the box's own enter and exit")
T.onBeamNGTrigger({ triggerName = "rm_cp_2", event = "enter", subjectID = 1 })
eq(#sentOf("cp.hit"), 1, "a gate's volume still speaks")
eq(sentOf("cp.hit")[1].i, 2, "for gate two")

section("the race ends: the volumes come down and the poll has nothing to measure")
status.state = "idle"
T.stopRace()
drive(600, 0, 0, 0.3)
eq(T.szState(), nil, "nothing measured")
eq(snap().raceActive, false, "the unit is idle")
eq(led().color, "off", "dots dark")

print("")
print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
