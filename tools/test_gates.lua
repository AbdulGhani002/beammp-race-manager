-- The sums that decide where a gate's volume sits and how wide it is. A gate
-- is marked from wherever the capture car was driving, which is rarely the
-- middle of the track, so each side is measured to the first wall or bank and
-- the gate is slid and widened to span the gap. The measuring needs the game;
-- the sums do not, and the sums are what put gates half off the road.
--
--   lua tools/test_gates.lua

ColorF = function() return {} end
ColorI = function() return {} end

local T = dofile("client/lua/ge/extensions/raceManager/triggers.lua")

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

-- a multi return in the middle of an argument list collapses to one value,
-- so the two results are taken here and compared after
local function span(w, l, r, wantAcross, wantOff, what)
  local across, off = T.fitSpan(w, l, r)
  local fine = math.abs(across - wantAcross) < 1e-9 and math.abs(off - wantOff) < 1e-9
  ok(fine, ("%s (got %s, %s wanted %s, %s)"):format(
    what, tostring(across), tostring(off), tostring(wantAcross), tostring(wantOff)))
end

local function section(t) print("") print("== " .. t) end

section("a gate marked mid track stays put")
span(20, 10, 10, 20, 0, "walls ten metres each side, twenty wide, centred")
span(20, 12.5, 12.5, 25, 0, "a wider gap and the gate grows to fill it")

section("a gate marked off to one side slides back to the middle")
-- baja gate 9: marked from the left half of the road, so its twenty metres
-- ended mid road and the right half of the road was outside it
span(20, 1, 24, 25, -11.5, "marked a metre off the left bank")
span(20, 24, 1, 25, 11.5, "and the same the other way round")
span(20, 5, 20, 25, -7.5, "part way over still centres on the gap")

section("open ground does not make a monster")
-- the desert. both rays ran out without touching anything, and reading that
-- as twenty five metres of track each way drew fifty metre gates.
span(20, nil, nil, 20, 0, "neither side found a thing, so the marked width stands")
span(20, 14, 10, 24, 2, "walls on both sides, the gate takes the gap it found")
span(20, 20, 20, 30, 0, "two distant walls are still pulled back to the ceiling")

section("a narrow gap never squeezes the gate below what was captured")
span(20, 3, 4, 20, -0.5, "a tight spot keeps the captured width")
span(8, 2, 3, 8, -0.5, "and a small gate keeps its own")

section("one side measured is still worth having")
span(20, nil, 10, 20, 0, "no left reading, the marked half fills in for it")
span(20, 10, nil, 20, 0, "no right reading, same")
span(20, nil, 4, 20, 3, "a close wall on the right slides the gate away from it")
span(20, 4, nil, 20, -3, "and the same on the left")
span(nil, nil, nil, 0, 0, "nothing at all falls back to zero width, not a crash")

-- ---------------------------------------------------------------- the road

-- The width and the middle now come off the road the game's own ai drives on,
-- because a ray fired sideways across open desert touches nothing and left
-- gates at their marked width, sitting wherever the capture car happened to be.
local function road(w, yaw, gx, gy, cx, cy, wide, wantAcross, wantOff, what)
  local across, off = T.fitRoad(w, yaw, gx, gy, cx, cy, wide)
  local fine = math.abs(across - wantAcross) < 1e-6 and math.abs(off - wantOff) < 1e-6
  ok(fine, ("%s (got %s, %s wanted %s, %s)"):format(
    what, tostring(across), tostring(off), tostring(wantAcross), tostring(wantOff)))
end

section("a gate takes the width of the road it is on")
road(20, 0, 100, 50, 100, 50, 24, 32, 0, "a wider road widens the gate, margin each side")
road(30, 0, 0, 0, 0, 0, 8, 30, 0, "a road narrower than the marked width leaves it alone")
road(20, 0, 0, 0, 0, 0, 60, 45, 0, "and a huge one still stops at the ceiling")

section("and reaches the middle of it without leaving the line that was driven")
-- yaw 0 means the gate faces along x, so across is y and the offset is the y gap
road(20, 0, 100, 50, 100, 53, 10, 20, 3, "the road's middle three metres to one side")
road(20, 0, 100, 50, 100, 46, 10, 20, -4, "and four the other way")
-- facing along y, across is x, and the sign turns over
road(20, math.pi / 2, 100, 50, 96, 50, 10, 20, 4, "the same gate turned a quarter turn")
road(20, 0, 100, 50, 100, 50, 10, 20, 0, "a gate already on the middle does not move")

-- The gate used to be slid onto the road's middle and left there, so a road
-- whose middle was further off than the gate was wide put the gate beside the
-- course with the racing line outside it. That is what was on screen: a gate
-- off to the left while the car drove past on the right.
section("the line the capture car drove is always inside its own gate")
local function covers(w, yaw, gx, gy, cx, cy, wide, what)
  local across, off = T.fitRoad(w, yaw, gx, gy, cx, cy, wide)
  local lo, hi = off - across * 0.5, off + across * 0.5
  ok(lo <= -3.9 and hi >= 3.9,
     ("%s (gate runs %s to %s, and zero is where the car was)")
       :format(what, tostring(lo), tostring(hi)))
end

covers(20, 0, 100, 50, 100, 65, 10, "a road fifteen metres off does not take the gate with it")
covers(20, 0, 100, 50, 100, 35, 10, "nor fifteen the other way")
covers(20, 0, 100, 50, 100, 90, 30, "nor a wide one forty off, once the ceiling has trimmed it")
covers(20, math.pi / 2, 0, 0, 25, 0, 12, "and the same turned a quarter turn")
covers(8, 0, 0, 0, 0, 22, 6, "a narrow gate beside a narrow road as well")

section("it still reaches the road it was told about")
road(20, 0, 100, 50, 100, 65, 10, 28, 10,
     "fifteen off with a ten wide road spans from the line out past the far edge")

-- ------------------------------------------------------------------- the pit

-- A pit is a place you sit in while a repair runs, not a line you cross. Built
-- to a gate's three metres it fired enter and exit in the same tenth of a
-- second, so driving through showed "in the pit" for a blink and parking in
-- one showed nothing at all.
section("a pit is long enough to stop in, a gate is not")
do
  local here = { pos = { x = 0, y = 0, z = 10 }, yaw = 0 }
  local _, gateLong = T.boxOf(here)
  local _, pitLong  = T.boxOf(here, "pit")
  ok(gateLong <= 6, ("a gate is a line to cross, %s deep"):format(tostring(gateLong)))
  ok(pitLong >= 15, ("a pit is a place to sit, %s long"):format(tostring(pitLong)))
  ok(pitLong > gateLong * 3, "and the two are not the same shape")

  -- the capture screen only ever offered a gate's depth, so a pit keeps its
  -- own length whatever was written against it
  local marked = { pos = { x = 0, y = 0, z = 10 }, yaw = 0, size = { w = 20, h = 8, d = 3 } }
  local _, stillLong = T.boxOf(marked, "pit")
  ok(stillLong >= 15, "even one captured with a gate's three metres against it")
end

section("a pit is somewhere you are, not something you cross")
T.pitsForgotten()
eq(T.pitCrossed("1", "enter"), true, "driving in says so")
eq(T.pitCrossed("1", "enter"), nil, "and says nothing the second time, sitting still")
eq(T.pitCrossed("1", "exit"), false, "driving out says so too")
eq(T.pitCrossed("1", "exit"), nil, "and only once")

section("a lane with a box at each end still holds")
T.pitsForgotten()
eq(T.pitCrossed("1", "enter"), true, "into the first")
eq(T.pitCrossed("2", "enter"), nil, "into the second while still in the first, no change")
eq(T.pitCrossed("1", "exit"), nil,
   "and out of the first is not out of the pit, which is the bug this had")
eq(T.pitCrossed("2", "exit"), false, "out of the last one is")

section("the boxes going away takes you out of the pit")
T.pitsForgotten()
T.pitCrossed("1", "enter")
T.pitsForgotten()
eq(T.pitCrossed("1", "exit"), nil,
   "a car that was in a pit when the course changed is not in it for ever")
eq(T.pitCrossed("1", "enter"), true, "and can enter one again")

-- ------------------------------------------------------------ putting back

section("reposition finds the nearest point on the leg being driven")
local A = { x = 0, y = 0, z = 0 }
local B = { x = 100, y = 0, z = 0 }

local function leg(px, py, a, b, wx, wy, wz, what)
  local x, y, z = T.legPoint(px, py, a, b)
  local fine = math.abs(x - wx) < 1e-6 and math.abs(y - wy) < 1e-6
               and math.abs(z - wz) < 1e-6
  ok(fine, ("%s (got %s,%s,%s wanted %s,%s,%s)"):format(
    what, tostring(x), tostring(y), tostring(z), tostring(wx), tostring(wy), tostring(wz)))
end

leg(50, 20, A, B, 50, 0, 0, "off the side of the leg comes straight back onto it")
leg(50, -20, A, B, 50, 0, 0, "from either side")
leg(-30, 5, A, B, 0, 0, 0, "behind the leg stops at the gate you came from")
leg(130, 5, A, B, 100, 0, 0, "past it stops at the one you are going for")
leg(50, 0, A, { x = 100, y = 0, z = 10 }, 50, 0, 5, "a climbing leg lands at the right height")

local _, _, _, yaw = T.legPoint(50, 5, A, B)
ok(math.abs(yaw) < 1e-6, "and points along the leg")
local _, _, _, yaw2 = T.legPoint(5, 50, A, { x = 0, y = 100, z = 0 })
ok(math.abs(yaw2 - math.pi / 2) < 1e-6, "whichever way the leg runs")

-- no ground is given and none taken, which is what stops it skipping a corner
local _, _, _, _, t = T.legPoint(25, 40, A, B)
ok(math.abs(t - 0.25) < 1e-6, "a quarter along the leg stays a quarter along it")

print("")
print(("%d passed, %d failed"):format(pass, fail))
for _, f in ipairs(failures) do print("  - " .. f) end
os.exit(fail == 0 and 0 or 1)
