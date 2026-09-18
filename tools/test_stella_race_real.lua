-- The whole road, with nothing faked but the game: the real server plugin in
-- the mock host, the real client state, race and trigger modules, the real
-- unit and bridge, and a car driven down a course with a box zone and a
-- gate zone. What the unit's snapshot says at each place is what the
-- screen would show.
--
--   lua tools/test_stella_race_real.lua

local H = dofile("tools/mock/beammp.lua")
local J = dofile("tools/mock/json.lua")

local pass, fail = 0, 0
local function ok(cond, what)
  if cond then pass = pass + 1 else fail = fail + 1 print("  FAIL  " .. what) end
end
local function eq(got, want, what)
  ok(got == want, ("%s (got %s, wanted %s)"):format(what, tostring(got), tostring(want)))
end
local function section(t) print("") print("== " .. t) end

------------------------------------------------------------------ the server
os.execute("cmd /c rmdir /s /q Resources 2>nul")
H.loadPlugin()
H.fire("onInit")
H.addPlayer(0, "Dard", "6001", false, "203.0.113.1")
H.fire("onPlayerJoining", 0)
H.clientSend(0, "hello", { version = RM.VERSION })
H.clientSend(0, "name.set", { name = "Dard" })
RM.console.handle("rm role Dard owner")
H.fire("onVehicleSpawn", 0, 1, "pickup:0-1:{\"jbm\":\"pickup\"}")

-- five gates east along x, a box round x=500 (480 to 520, twenty wide) at
-- thirty seven, and a gate zone from gate four to gate five at thirty seven
H.clientSend(0, "track.begin", { id = "sim", name = "Test", kind = "race", level = "utah_sc", circuit = false })
H.fire("rm:tick")
for i, x in ipairs({ 0, 300, 600, 900, 1200 }) do
  H.advance(1)
  H.clientSend(0, "track.mark", { pos = { x = x, y = 0, z = 0 }, yaw = 0 })
  H.fire("rm:tick")
  if i == 2 then
    H.advance(1)
    H.clientSend(0, "track.sz", { pos = { x = 500, y = 0, z = 0 }, yaw = 0, mph = 37, w = 20, h = 8, d = 40 })
    H.fire("rm:tick")
  end
end
H.clientSend(0, "track.finish")
H.fire("rm:tick")
local saved = RM.tracks.get("sim")
ok(saved ~= nil, "the course is saved")
eq(saved and #saved.checkpoints, 5, "with five gates")
eq(saved and #saved.szGates, 1, "and one box")
eq(saved and saved.szGates[1].mph, 37, "at thirty seven")
ok(select(1, RM.tracks.setZonesDirect("sim", { { from = 4, to = 5, mph = 37 } })), "and a gate zone from four to five")
H.clearOutbox(0)

------------------------------------------------------------------ the game
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
ColorF = function() return {} end
ColorI = function() return {} end
String = function(s) return s end
vec3 = function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
quat = function(x, y, z, w)
  return { x = x, y = y, z = z, w = w, toTorqueQuat = function(self) return { x = self.x, y = self.y, z = self.z, w = self.w } end }
end
createObject = function(kind)
  local o = { kind = kind, fields = {} }
  function o:setField(k, _, v) self.fields[k] = v end
  function o:registerObject(name) self.name = name end
  function o:setPosition(p) self.pos = p end
  function o:setScale(s) self.scale = s end
  function o:setRotation(q) self.rot = q end
  return o
end
scenetree = { findObject = function() return nil end }
debugDrawer = setmetatable({}, { __index = function() return function() end end })
core_camera = { getPosition = function() return vec3(0, 0, 0) end }
Engine = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })
local logged = {}
log = function(level, tag, msg) logged[#logged + 1] = tostring(level) .. " " .. tostring(msg) end
jsonEncode = J.encode
jsonDecode = J.decode

local hooked = {}
guihooks = { trigger = function(name, d) if name == "RMSI_Update" then hooked[#hooked + 1] = d end end }

local car = { pos = { x = -50, y = 0, z = 0 }, vel = { x = 0, y = 0, z = 0 } }
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
getPlayerVehicle = function() return vehicle end

-- any module not loaded for real answers every call with nothing
local function stub()
  return setmetatable({}, { __index = function() return function() end end })
end
extensions = setmetatable({}, { __index = function(t, k)
  if k == "isExtensionLoaded" then return function() return false end end
  if k == "load" or k == "unload" then return function() end end
  local s = stub()
  rawset(t, k, s)
  return s
end })

local simNow = 0
local handlers, sent = {}, {}
extensions.raceManager_clock = { now = function() return simNow end }
extensions.raceManager_net = {
  on = function(ch, fn) handlers[ch] = fn end,
  send = function(ch, d)
    sent[#sent + 1] = { ch = ch, d = d, x = car.pos.x }
    H.clientSend(0, ch, d)
    return true
  end,
  isConnected = function() return true end,
}
local notices = {}
local function pump()
  for _, m in ipairs(H.messages(0)) do
    local fn = handlers[m.c]
    if fn then
      local okC, err = pcall(fn, m.d)
      if not okC then print("  channel " .. tostring(m.c) .. " failed: " .. tostring(err)) end
    end
  end
  H.clearOutbox(0)
end

local ST = dofile("client/lua/ge/extensions/raceManager/state.lua")
extensions.raceManager_state = ST
local realNotice = ST.notice
ST.notice = function(text) notices[#notices + 1] = tostring(text) end
local T = dofile("client/lua/ge/extensions/raceManager/triggers.lua")
extensions.raceManager_triggers = T
local R = dofile("client/lua/ge/extensions/raceManager/race.lua")
extensions.raceManager_race = R
local S = dofile("client/lua/ge/extensions/raceManager/stellaUnit.lua")
extensions.raceManager_stellaUnit = S
local B = dofile("client/lua/ge/extensions/raceManager/stella.lua")
extensions.raceManager_stella = B
ST.onExtensionLoaded()
R.onExtensionLoaded()
S.onExtensionLoaded()
B.onExtensionLoaded()

-- every call the bridge makes to the unit about a zone, for the record
local zoneCalls = {}
local realSetZone = S.setSpeedZone
S.setSpeedZone = function(z)
  zoneCalls[#zoneCalls + 1] = { x = car.pos.x, z = z }
  return realSetZone(z)
end

local function snap() return S.getSnapshot() end
local function led() local s = snap() return { color = s.ledColor, flash = s.ledFlash, pattern = s.ledPattern } end
local function sounds()
  local out = {}
  for _, d in ipairs(hooked) do for _, s in ipairs(d.sounds or {}) do out[#out + 1] = s end end
  hooked = {}
  for _, s in ipairs(S.drainSounds()) do out[#out + 1] = s end
  return out
end
local function has(list, name) local n = 0 for _, s in ipairs(list) do if s == name then n = n + 1 end end return n end
local function sentOf(ch) local out = {} for _, m in ipairs(sent) do if m.ch == ch then out[#out + 1] = m end end return out end

-- the game, frame by frame at sixty a second: the car moves, the gate
-- volumes fire when it passes a gate, every module ticks, and every tenth
-- of a second the server ticks and its messages come down
local FRAME = 1 / 60
local serverSince = 0
local gates = { 0, 300, 600, 900, 1200 }
local function frame()
  local before = car.pos.x
  car.pos.x = car.pos.x + car.vel.x * FRAME
  simNow = simNow + FRAME
  for i, gx in ipairs(gates) do
    if before < gx and car.pos.x >= gx then
      T.onBeamNGTrigger({ triggerName = "rm_cp_" .. i, event = "enter", subjectID = 1 })
    end
  end
  T.onUpdate()
  B.onUpdate(FRAME)
  S.onUpdate(FRAME)
  R.onUpdate(FRAME)
  serverSince = serverSince + FRAME
  if serverSince >= 0.1 - 1e-9 then
    serverSince = 0
    H.advance(0.1)
    H.setVelocity(0, 1, car.vel.x, 0, 0)
    H.fire("rm:tick")
    pump()
  end
end
-- drive at a speed until the car reaches x, or for a time
local function driveTo(x, mps)
  car.vel.x = mps
  local guard = 0
  while car.pos.x < x and guard < 100000 do frame() guard = guard + 1 end
end
local function hold(seconds, mps)
  car.vel.x = mps or 0
  local t = 0
  while t < seconds - 1e-9 do frame() t = t + FRAME end
end
local MPH = 0.44704

section("the race is armed and the course comes down, so the volumes go up")
extensions.raceManager_net.send("race.arm", { id = "sim", mode = "controller", laps = 1 })
hold(0.5, 0)
eq(R.status().state, "armed", "armed")
ok(ST.get().track ~= nil and ST.get().track.id == "sim", "the full course is on the client")
eq(ST.get().track and #ST.get().track.zones, 1, "with its gate zone")
eq(ST.get().track and #ST.get().track.szGates, 1, "and its box")
eq(T.isRacing(), true, "the volumes are up")
eq(snap().raceActive, true, "the unit knows the race is on")
eq(led().color, "off", "nothing lit on the line")
sounds()

section("across the start line: green for a second, and the clock starts")
driveTo(5, 45 * MPH)
hold(0.3, 45 * MPH)
eq(R.status().state, "running", "running")
eq(R.status().done, 1, "one gate done")
eq(led().color, "green", "green")
eq(led().flash, false, "solid")
eq(led().pattern, "all", "all the dots")
eq(has(sounds(), "vcp"), 1, "the gate sound once")
eq(snap().speed, 45, "the speed the screen gets is mph")
local traced = sentOf("stella.trace")
ok(#traced >= 1 and tostring(traced[#traced].d.text):find("green all: gate", 1, true) ~= nil,
   "the light's change went up to the server with why")
hold(1.2, 45 * MPH)
eq(led().color, "off", "and off again after it")

section("two hundred metres from the box the warning comes: yellow 37, the sound once")
driveTo(270, 45 * MPH)
eq(led().color, "off", "two hundred and ten metres out, nothing yet")
driveTo(285, 45 * MPH)
hold(0.2, 45 * MPH)
eq(snap().speedZoneWarning, true, "warned")
eq(snap().speedZoneActive, false, "not in it")
eq(snap().speedZoneLimitMph, 37, "at thirty seven")
eq(led().color, "yellow", "yellow")
eq(led().pattern, "all", "spelling 37")
eq(has(sounds(), "advance"), 1, "the warning sound once")

section("gate two, inside the warning: green for a second, then the yellow is back")
driveTo(305, 45 * MPH)
hold(0.2, 45 * MPH)
eq(led().color, "green", "green at the gate")
eq(led().flash, false, "solid")
hold(1.2, 45 * MPH)
eq(led().color, "yellow", "yellow again once the green is done")
eq(led().pattern, "all", "still spelling 37")
eq(snap().speedZoneWarning, true, "still warned")
eq(has(sounds(), "advance"), 0, "and no second warning sound")

section("into the box under the limit: solid yellow, the entry sound, the server told once")
driveTo(486, 30 * MPH)
hold(0.3, 30 * MPH)
eq(snap().speedZoneActive, true, "in the zone")
eq(snap().speedExceeding, false, "under the limit")
eq(led().color, "yellow", "yellow, holding the limit")
eq(led().flash, false, "solid")
eq(led().pattern, "all", "the whole grid")
local s = sounds()
eq(has(s, "enter"), 1, "the entry sound once")
local states = sentOf("sz.state")
eq(#states, 1, "the server was told once")
eq(states[1] and states[1].d.inside, true, "in")
eq(states[1] and states[1].d.mph, 37, "at thirty seven")

section("!stella in the box: a live report on screen and in the server's log")
eq(B.selfTest(), true, "answered")
local live = notices[#notices] or ""
ok(live:find("Stella: race running", 1, true) ~= nil, "the race")
ok(live:find("poll box 1 at 37 mph, in", 1, true) ~= nil, "the box poll, with its limit")
ok(live:find("unit led yellow all", 1, true) ~= nil, "the unit's light")
ok(live:find("zone in 37 mph", 1, true) ~= nil, "and its zone")
hold(0.2, 30 * MPH)
local liveLogged = false
for _, l in ipairs(H.logs.info) do
  if tostring(l):find("Dard Stella: race running", 1, true) then liveLogged = true end
end
ok(liveLogged, "and the server logged it")
local ledLogged = false
for _, l in ipairs(H.logs.info) do
  if tostring(l):find("Dard Stella led yellow all: in a 37 mph zone", 1, true) then ledLogged = true end
end
ok(ledLogged, "as it logged the car entering the zone, which the dots alone do not show")

section("over the limit in the box: red, the exceed sound; under again, yellow")
car.vel.x = 50 * MPH
hold(0.4, 50 * MPH)
eq(snap().speedExceeding, true, "over")
eq(led().color, "red", "red")
eq(led().flash, false, "solid")
eq(has(sounds(), "exceed"), 1, "the exceed sound once")
hold(0.4, 25 * MPH)
eq(snap().speedExceeding, false, "under again")
eq(led().color, "yellow", "yellow again")

section("out of the box: off, the leaving beep, the server told once more, and five quiet seconds")
driveTo(524, 25 * MPH)
hold(0.3, 25 * MPH)
eq(snap().speedZoneActive, false, "out")
eq(snap().speedZoneWarning, false, "not warned")
eq(led().color, "off", "off")
eq(has(sounds(), "vcp"), 1, "the leaving beep once")
states = sentOf("sz.state")
eq(#states, 2, "the server was told once more")
eq(states[2] and states[2].d.inside, false, "out")
driveTo(560, 45 * MPH)
eq(snap().speedZoneWarning, false, "forty metres past the box: quiet, no warning of the box behind")

section("gate three in the quiet time: green; then the gate zone ahead warns two hundred metres out")
driveTo(605, 45 * MPH)
hold(0.2, 45 * MPH)
eq(led().color, "green", "green at gate three")
eq(led().flash, false, "solid")
eq(R.status().done, 3, "three gates done")
hold(1.2, 45 * MPH)
driveTo(690, 45 * MPH)
eq(led().color, "off", "two hundred and ten metres from gate four, nothing")
driveTo(705, 45 * MPH)
hold(0.2, 45 * MPH)
eq(snap().speedZoneWarning, true, "warned of the gate zone")
eq(led().color, "yellow", "yellow")
eq(led().pattern, "all", "spelling 37")
eq(has(sounds(), "advance"), 1, "the warning sound once")

section("through gate four into the gate zone: green, then yellow; red over the limit; gate five ends it")
driveTo(905, 30 * MPH)
hold(0.2, 30 * MPH)
eq(led().color, "green", "green at gate four")
hold(1.2, 30 * MPH)
eq(snap().speedZoneActive, true, "in the gate zone")
eq(led().color, "yellow", "yellow, holding the limit")
eq(led().flash, false, "solid")
eq(has(sounds(), "enter"), 1, "the entry sound once")
car.vel.x = 50 * MPH
hold(0.4, 50 * MPH)
eq(led().color, "red", "red over the limit")
eq(has(sounds(), "exceed"), 1, "the exceed sound once")
driveTo(1205, 50 * MPH)
hold(0.5, 50 * MPH)
eq(R.status().state, "finished", "finished")
eq(snap().raceActive, false, "the unit knows")
eq(snap().speedZoneActive, false, "no zone")
ok(led().color ~= "red", "not red any more")

section("nothing the client did failed")
local errors = {}
for _, l in ipairs(logged) do if l:match("^E ") then errors[#errors + 1] = l end end
eq(#errors, 0, "no errors logged (" .. table.concat(errors, " | "):sub(1, 300) .. ")")

print("")
print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then
  print("")
  print("zone calls:")
  for _, c in ipairs(zoneCalls) do
    local z = c.z
    print(("  x=%.0f %s"):format(c.x, z and ("upcoming=%s mph=%s faceDist=%s"):format(tostring(z.upcoming), tostring(z.limitMph), tostring(z.faceDist)) or "nil"))
  end
  print("notices:")
  for _, n in ipairs(notices) do print("  " .. n) end
end
os.exit(fail == 0 and 0 or 1)
