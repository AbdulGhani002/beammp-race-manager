-- The gate geometry, checked against the course that actually broke.
--
-- These are the real numbers out of the server's tracks.json for "tester": a
-- five gate loop whose grid was left half way round it, and whose gate 4 was
-- tapped after the hairpin had already been turned. On that course gate 1 sat
-- 176 degrees behind the car and gate 4 lay along the road instead of across
-- it, so a run could not be started without reversing and gate 4 could not be
-- driven through at all.
--
--   lua54 tools/test_geometry.lua

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
M.fire("onInit")

local function deg(r) return r * 180 / math.pi end

local function gap(a, b)
  local d = (a - b) % (2 * math.pi)
  if d > math.pi then d = d - 2 * math.pi end
  return d
end

-- the course exactly as it was saved, before any of this ran
local function tester()
  local cp = {
    { i = 1, pos = { x = -292.03564453125, y = -333.86447143555, z = 5.0511612892151 }, yaw =  0.12973949985894 },
    { i = 2, pos = { x = -231.19744873047, y = -321.46920776367, z = 6.0489692687988 }, yaw =  0.20921296344583 },
    { i = 3, pos = { x = -172.13401794434, y = -308.9475402832,  z = 5.9936428070068 }, yaw =  0.20795961026429 },
    { i = 4, pos = { x = -184.29998779297, y = -269.35739135742, z = 5.8742337226868 }, yaw = -2.851715386035  },
    { i = 5, pos = { x = -232.05101013184, y = -279.37,          z = 7.0100002288818 }, yaw = -2.9789          },
  }
  for _, c in ipairs(cp) do c.size = { w = 20, h = 8, d = 3 } end
  return {
    id = "tester", circuit = true, level = "utah_sc", checkpoints = cp,
    start = { pos = { x = -259.65008544922, y = -328.40216064453, z = 5.6020364761353 },
              yaw = 0.22604798334819 },
  }
end

-- how square a gate is to the way a car arrives at it. 1 is dead on, 0 is
-- edge on, which is the state gate 4 was in.
local function squareness(track, i)
  local cps = track.checkpoints
  local n = #cps
  local prev = cps[(i - 2) % n + 1]
  local here = cps[i]
  local dx, dy = here.pos.x - prev.pos.x, here.pos.y - prev.pos.y
  local m = math.sqrt(dx * dx + dy * dy)
  dx, dy = dx / m, dy / m
  return dx * math.cos(here.yaw) + dy * math.sin(here.yaw)
end

section("the course as it was saved is unracable")
local before = tester()
do
  local s = before.start
  local fx, fy = math.cos(s.yaw), math.sin(s.yaw)
  local g1 = before.checkpoints[1]
  local dx, dy = g1.pos.x - s.pos.x, g1.pos.y - s.pos.y
  local m = math.sqrt(dx * dx + dy * dy)
  local facing = (dx / m) * fx + (dy / m) * fy
  near(facing, -1, 0.05, "gate 1 sits directly behind the grid")
  near(deg(math.acos(facing)), 176.6, 1.0, "176 degrees behind, so it can only be reversed into")
  near(squareness(before, 4), 0, 0.05, "and gate 4 is edge on to the way you arrive")
end

section("squared up, and gate 1 is left alone")
local t = tester()
RM.tracks.squareUp(t)

eq(#t.checkpoints, 5, "no gate is lost")
near(t.checkpoints[1].pos.x, -292.04, 0.1,
     "gate 1 is still the gate that was dropped first")
near(t.checkpoints[5].pos.x, -232.05, 0.1, "and the order behind it is untouched")

section("every gate faces the way you drive through it")
for i = 1, 5 do
  ok(squareness(t, i) > 0.55,
     ("gate %d is square enough to the racing line to be driven through"):format(i))
end

section("the hairpin gate specifically")
do
  local hair = t.checkpoints[4]
  near(hair.pos.x, -184.30, 0.1, "the hairpin gate is where it always was")
  ok(squareness(t, 4) > 0.55, "but it now lies across the road rather than along it")
  local was = -2.851715386035
  ok(math.abs(gap(hair.yaw, was)) > 0.5,
     "having been turned more than 30 degrees off the heading that was captured")
end

section("a gate pointed roughly the way you drive keeps the heading it was given")
-- his courses: he points the car along the course and presses the key, and
-- that is where he wants the gate to face. thirty degrees off the line is a
-- corner entry, not a mistake, and it is left alone.
do
  local kept = tester()
  RM.tracks.squareUp(kept)
  local g2 = kept.checkpoints[2]
  local n = #kept.checkpoints
  local prev = kept.checkpoints[1]
  local into = math.atan(g2.pos.y - prev.pos.y, g2.pos.x - prev.pos.x)
  g2.yaw = into + math.rad(30)
  RM.tracks.squareUp(kept)
  near(g2.yaw, into + math.rad(30), 1e-9, "thirty degrees off the way in is left as marked")
  g2.yaw = into + math.rad(80)
  RM.tracks.squareUp(kept)
  ok(math.abs(gap(g2.yaw, into + math.rad(80))) > 0.3,
     "eighty degrees off is a slot, and is squared")
  ok(squareness(kept, 2) > 0.55, "to something a car can drive through")
end

section("running it twice changes nothing")
local twice = tester()
RM.tracks.squareUp(twice)
local snapshot = {}
for i, c in ipairs(twice.checkpoints) do snapshot[i] = { x = c.pos.x, yaw = c.yaw } end
RM.tracks.squareUp(twice)
for i, c in ipairs(twice.checkpoints) do
  near(c.pos.x, snapshot[i].x, 1e-9, ("gate %d stays where it was put"):format(i))
  near(c.yaw, snapshot[i].yaw, 1e-9, ("gate %d keeps its angle"):format(i))
end

section("the cars line up in front of gate 1, not on the saved grid")
do
  local g = RM.tracks.gridFor(t)
  local one = t.checkpoints[1]
  local dx, dy = one.pos.x - g.pos.x, one.pos.y - g.pos.y
  local m = math.sqrt(dx * dx + dy * dy)
  near(m, 8.0, 0.01, "eight metres back from it")
  local fx, fy = math.cos(g.yaw), math.sin(g.yaw)
  near((dx / m) * fx + (dy / m) * fy, 1, 0.001, "pointing straight at it")
  ok(m > 3.0, "and clear of the gate volume, so there is a crossing left to make")
end

-- the second course captured put its grid 1.26 metres PAST gate 1 facing away,
-- which with a correctly sized volume would start the car already through it
section("a grid left past its own gate 1")
do
  local baja = {
    id = "baja-like", circuit = true, level = "utah_sc",
    start = { pos = { x = -193.10482788086, y = -364.53088378906, z = 7.8178095817566 },
              yaw = -3.1187568399004 },
    checkpoints = {
      { i = 1, pos = { x = -191.84, y = -364.50, z = 7.85 }, yaw = -3.1199, size = { w = 20, h = 8, d = 3 } },
      { i = 2, pos = { x = -221.10, y = -365.19, z = 4.72 }, yaw = -3.1153, size = { w = 20, h = 8, d = 3 } },
      { i = 3, pos = { x = -255.43, y = -365.21, z = 5.83 }, yaw =  3.1185, size = { w = 20, h = 8, d = 3 } },
      { i = 4, pos = { x = -293.41, y = -361.87, z = 6.51 }, yaw =  3.0284, size = { w = 20, h = 8, d = 3 } },
    },
  }
  local wasFirst = baja.checkpoints[1].pos.x
  RM.tracks.squareUp(baja)
  near(baja.checkpoints[1].pos.x, wasFirst, 0.01, "gate 1 is where it was dropped")

  local g = RM.tracks.gridFor(baja)
  local one = baja.checkpoints[1]
  local dx, dy = one.pos.x - g.pos.x, one.pos.y - g.pos.y
  local m = math.sqrt(dx * dx + dy * dy)
  local fx, fy = math.cos(g.yaw), math.sin(g.yaw)
  ok(((dx / m) * fx + (dy / m) * fy) > 0.999, "and the car is still put in front of it facing it")
  near(m, 8.0, 0.01, "rather than a metre past it facing away")
end

section("a point to point course keeps its order too")
local ptp = tester()
ptp.circuit = false
local firstBefore = ptp.checkpoints[1].pos.x
RM.tracks.squareUp(ptp)
near(ptp.checkpoints[1].pos.x, firstBefore, 0.01, "gate 1 is the gate dropped first")

print("")
if fail > 0 then
  print(("%d passed, %d failed"):format(pass, fail))
  os.exit(1)
end
print(("%d passed, 0 failed"):format(pass))
