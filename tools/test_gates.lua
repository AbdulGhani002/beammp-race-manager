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
span(20, 25, 25, 50, 0, "nothing found either side is capped")
span(20, 25, 10, 35, 7.5, "open on one side only takes what it found")

section("a narrow gap never squeezes the gate below what was captured")
span(20, 3, 4, 20, -0.5, "a tight spot keeps the captured width")
span(8, 2, 3, 8, -0.5, "and a small gate keeps its own")

section("bad measurements change nothing")
span(20, nil, 10, 20, 0, "no left measurement, gate as captured")
span(20, 10, nil, 20, 0, "no right measurement, same")
span(nil, nil, nil, 0, 0, "nothing at all falls back to zero width, not a crash")

print("")
print(("%d passed, %d failed"):format(pass, fail))
for _, f in ipairs(failures) do print("  - " .. f) end
os.exit(fail == 0 and 0 or 1)
