-- The gate geometry that decides whether driving through a checkpoint scores.
-- This is client lua, so the game's drawing globals are stubbed and only the
-- maths is exercised. That maths is what the 29 August recording turned on.
--
--   lua tools/test_gates.lua

-- triggers.lua builds its colours at load time and nothing else touches the
-- game until a function is called
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

local function near(got, want, tol, what)
  ok(type(got) == "number" and math.abs(got - want) <= tol,
     ("%s (got %s, wanted %s +/- %s)"):format(what, tostring(got), tostring(want), tostring(tol)))
end

local function section(t) print("") print("== " .. t) end
local function rad(d) return d * math.pi / 180 end

section("the turn between two gates")
near(T.angleGap(rad(0), rad(0)), 0, 1e-9, "no turn at all")
near(T.angleGap(rad(60), rad(11)), rad(49), 1e-9, "gate 11 to gate 12 on zaza is forty nine degrees")
near(T.angleGap(rad(11), rad(60)), rad(49), 1e-9, "and it does not matter which way round")

-- the saved yaws are raw radians off the car, so they run past a full turn
-- and below zero. 86 and -204 are seventy degrees apart, not two hundred and ninety.
near(T.angleGap(rad(86), rad(-204)), rad(70), 1e-9, "the long way round is never the answer")
near(T.angleGap(rad(-175), rad(176)), rad(9), 1e-9, "and it wraps at the back too")
near(T.angleGap(rad(180), rad(0)), rad(180), 1e-9, "a gate faced backwards is half a turn")

section("how much wider a turned gate has to be")
-- cross a gate at an angle and the gap across your path is w times cos, so the
-- width is divided by the same cos to put the gap back
near(T.turnStretch(0), 1.0, 1e-9, "a gate square to you is left alone")
near(T.turnStretch(rad(49)), 1 / math.cos(rad(49)), 1e-9, "zaza gate 12 is stretched by one over cos")
near(T.turnStretch(rad(49)) * 20, 30.5, 0.2, "so its twenty metres becomes about thirty")
near(T.turnStretch(rad(30)), 1.1547, 1e-3, "a gentle bend barely moves")
near(T.turnStretch(rad(60)), 2.0, 1e-9, "sixty degrees is exactly double")

section("and it never runs away")
near(T.turnStretch(rad(90)), 2.0, 1e-9, "square on, cos is zero, so the cap holds it")
near(T.turnStretch(rad(120)), 2.0, 1e-9, "past square it is still capped")
near(T.turnStretch(rad(180)), 2.0, 1e-9, "and a gate faced backwards does not invert")
ok(T.turnStretch(rad(179)) > 0, "nothing comes back negative")

section("the straight that already worked is not touched much")
-- gates 7 to 11 on zaza sit within a couple of degrees of each other, and every
-- one of them scored first time. they should stay as they are.
for _, pair in ipairs({ { 11, 9 }, { 9, 9 }, { 9, 8 }, { 8, 11 } }) do
  local s = T.turnStretch(T.angleGap(rad(pair[1]), rad(pair[2])))
  ok(s < 1.01, ("a straight gate keeps its width (%d to %d)"):format(pair[2], pair[1]))
end

print("")
print(("%d passed, %d failed"):format(pass, fail))
for _, f in ipairs(failures) do print("  - " .. f) end
os.exit(fail == 0 and 0 or 1)
