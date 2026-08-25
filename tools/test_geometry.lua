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

local FILES = {
  "00_config", "01_util", "02_store", "03_bus", "04_identity", "05_roles",
  "06_players", "07_tracks", "08_console", "09_clock", "10_race", "11_results",
  "99_main",
}

os.execute("cmd /c rmdir /s /q Resources 2>nul")
for _, n in ipairs(FILES) do dofile("server/RaceManager/" .. n .. ".lua") end
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

section("squared up")
local t = tester()
RM.tracks.squareUp(t)

eq(#t.checkpoints, 5, "no gate is lost")
do
  local s = t.start
  local fx, fy = math.cos(s.yaw), math.sin(s.yaw)
  local g1 = t.checkpoints[1]
  local dx, dy = g1.pos.x - s.pos.x, g1.pos.y - s.pos.y
  local m = math.sqrt(dx * dx + dy * dy)
  ok(((dx / m) * fx + (dy / m) * fy) > 0.9, "gate 1 is now the gate the grid points at")
  near(m, 29.3, 1.0, "the one 29 metres up the road")
end

near(t.checkpoints[1].pos.x, -231.20, 0.1, "which is the gate that was numbered 2")
near(t.checkpoints[5].pos.x, -292.04, 0.1, "and the old gate 1 is now the last one before the line")

section("every gate faces the way you drive through it")
for i = 1, 5 do
  ok(squareness(t, i) > 0.55,
     ("gate %d is square enough to the racing line to be driven through"):format(i))
end

section("the hairpin gate specifically")
do
  -- old gate 4 is old index 4 -> new index 3 after the roll
  local hair = t.checkpoints[3]
  near(hair.pos.x, -184.30, 0.1, "the hairpin gate is where it always was")
  ok(squareness(t, 3) > 0.55, "but it now lies across the road rather than along it")
  local was = -2.851715386035
  ok(math.abs(gap(hair.yaw, was)) > 0.5,
     "having been turned more than 30 degrees off the heading that was captured")
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
  near(baja.checkpoints[1].pos.x, wasFirst, 0.01,
       "its gate 1 really is the first one, so the numbering is left alone")

  local g = RM.tracks.gridFor(baja)
  local one = baja.checkpoints[1]
  local dx, dy = one.pos.x - g.pos.x, one.pos.y - g.pos.y
  local m = math.sqrt(dx * dx + dy * dy)
  local fx, fy = math.cos(g.yaw), math.sin(g.yaw)
  ok(((dx / m) * fx + (dy / m) * fy) > 0.999, "and the car is still put in front of it facing it")
  near(m, 8.0, 0.01, "rather than a metre past it facing away")
end

section("a point to point course is not renumbered")
local ptp = tester()
ptp.circuit = false
local firstBefore = ptp.checkpoints[1].pos.x
RM.tracks.squareUp(ptp)
near(ptp.checkpoints[1].pos.x, firstBefore, 0.01,
     "its gate 1 is a real first gate, so the order is left alone")

print("")
if fail > 0 then
  print(("%d passed, %d failed"):format(pass, fail))
  os.exit(1)
end
print(("%d passed, 0 failed"):format(pass))
