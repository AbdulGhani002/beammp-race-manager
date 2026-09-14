-- The things his build plan promised for phases 1 to 5 that had not been
-- written yet: experience and levels, kick and ban and granting xp, teams,
-- records that can split by class, and a qualifying session that sets the grid.
--
--   lua tools/test_promised.lua

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

local function section(t) print("") print("== " .. t) end

os.execute("cmd /c rmdir /s /q Resources 2>nul")
M.loadPlugin()

local function tick(n) for _ = 1, (n or 1) do M.fire("rm:tick") end end

M.fire("onInit")

-- three named drivers, one of them the owner
local function join(pid, name, beammp)
  M.addPlayer(pid, name, beammp, false, "203.0.113." .. pid)
  M.fire("onPlayerJoining", pid)
  M.clientSend(pid, "hello", { version = RM.VERSION })
  M.clientSend(pid, "name.set", { name = name })
  tick(1)
end

join(0, "Boss", "9001")
join(1, "Marx", "9002")
join(2, "Colt", "9003")
RM.console.handle("rm role Boss owner")

local function keyOf(pid) return RM.identity.session(pid).key end

-- =====================================================================  xp

section("what a finish pays")
eq(RM.xp.forPlace(1), 200, "the win pays two hundred")
eq(RM.xp.forPlace(2), 198, "second pays two less")
eq(RM.xp.forPlace(3), 196, "and third two less again")
eq(RM.xp.forPlace(200), 20, "a long way down it stops at the floor")
eq(RM.xp.forPlace(0), 0, "no place, no pay")

-- his curve from 2026-09-14: the first level is 750 points and every level
-- after it asks 250 more than the one before, so the top of the ladder is
-- earned and not just sat through
section("levels climb with it, and each one asks more than the last")
eq(RM.xp.levelFor(0), 1, "everybody starts at one")
eq(RM.xp.levelFor(749), 1, "a point short is still the level below")
eq(RM.xp.levelFor(750), 2, "and the 750th point turns it over")
eq(RM.xp.neededFor(3) - RM.xp.neededFor(2), 1000, "the next level is a thousand on top")
eq(RM.xp.neededFor(4) - RM.xp.neededFor(3), 1250, "and the one after that 1250")
eq(RM.xp.levelFor(4200), 4, "further up it keeps counting")
eq(RM.xp.levelFor(4500), 5, "with level five at 4500")

section("giving it lands on the record and the roster")
local total, level = RM.xp.give(keyOf(1), 200, "finish")
eq(total, 200, "the total moved")
eq(level, 1, "not enough for a level yet")
eq(RM.identity.record(keyOf(1)).xp, 200, "and it is on the saved record")

RM.xp.give(keyOf(1), 900, "finish")
eq(select(2, RM.xp.of(keyOf(1))), 2, "past a thousand and the level goes up")
eq(RM.identity.session(1).level, 2, "and the live session carries it, so the screen sees it")

section("taking it back works too, and never goes under nothing")
RM.xp.give(keyOf(1), -100, "granted")
eq(RM.xp.of(keyOf(1)), 1000, "a negative grant takes it off")
RM.xp.give(keyOf(1), -99999, "granted")
eq(RM.xp.of(keyOf(1)), 0, "and it stops at zero rather than going below")

-- ==============================================================  kick and ban

section("only somebody above you can move you")
local ok1, why1 = RM.mod.ban(1, keyOf(2), "no")
eq(ok1, false, "a plain player cannot ban")
eq(why1, "not_allowed", "and is told why")

RM.roles.setFromConsole(keyOf(1), "admin")
eq(RM.mod.ban(1, keyOf(1), "x"), false, "not even on yourself")
eq(select(2, RM.mod.ban(1, keyOf(0), "x")), "outranks_you", "and not on the owner")

section("a ban turns them away next time")
local banned = RM.mod.ban(1, keyOf(2), "wrecking")
eq(banned, true, "an admin can ban a player")
ok(RM.mod.isBanned(keyOf(2)), "and the list remembers")
eq(RM.mod.reasonFor(keyOf(2)), "wrecking", "with the reason")

local key2 = keyOf(2)
M.fire("onPlayerDisconnect", 2)
M.removePlayer(2)
eq(RM.identity.session(2), nil, "they are gone")

M.addPlayer(2, "Colt", "9003", false, "203.0.113.2")
M.fire("onPlayerJoining", 2)
eq(RM.identity.session(2), nil,
   "knocking again is turned away before anything is written down for them")

section("and lifting it lets them in again")
eq(RM.mod.unban(key2), true, "the ban comes off")
eq(RM.mod.isBanned(key2), false, "the list forgets")
eq(RM.mod.turnAway(2), false, "and the door opens")

section("the ban list is on disk")
RM.mod.ban(1, keyOf(1) == key2 and key2 or key2, "again")
RM.store.flushAll()
local f = io.open("Resources/Server/RaceManager/data/bans.json", "rb")
ok(f ~= nil, "bans.json is written")
if f then f:close() end
RM.mod.unban(key2)

-- ====================================================================  team

M.addPlayer(2, "Colt", "9003", false, "203.0.113.2")
M.fire("onPlayerJoining", 2)
M.clientSend(2, "hello", { version = RM.VERSION })
tick(1)

local function drives(pid, model)
  M.fire("onVehicleSpawn", pid, pid * 10, model .. ':{"jbm":"' .. model .. '"}')
end

section("the car is read off the spawn as BeamMP really sends it")
-- from the server log: name, then pid-vid, then the json. the old strip took
-- one word and one colon and handed 0-0:{...} to the decoder, which is not
-- json, so the model was lost on every spawn on the live server.
M.fire("onVehicleSpawn", 1, 10,
  'guest8493757:1-10:{"pro":"0","abs":"realistic","pos":[-8.9,799.7,129.5],"jbm":"nine","pid":1,"ign":3}')
eq(RM.players.modelOf(1), "nine", "the model comes out of the real payload")

section("a team needs both of you in the same car")
drives(1, "pickup")
drives(2, "bigrig")
eq(select(2, RM.team.offer(1, 2, "invite")), "different_cars",
   "different cars are refused before anyone agrees to anything")

drives(2, "pickup")
eq(RM.team.offer(1, 2, "invite"), true, "the same car is allowed")

section("and somebody has to say yes")
eq(RM.team.of(keyOf(1)), nil, "an offer on its own is not a team")
local made = RM.team.accept(2)
ok(made, "accepting makes one")
ok(RM.team.of(keyOf(1)) ~= nil, "both of them are in it")
ok(RM.team.of(keyOf(2)) ~= nil, "not just the one who asked")
eq(RM.team.of(keyOf(1)).model, "pickup", "and it remembers the car")

section("changing car breaks it up on its own")
drives(2, "covet")
RM.team.recheck(2)
eq(RM.team.of(keyOf(1)), nil, "the team is gone")
eq(RM.team.of(keyOf(2)), nil, "for both of them")

section("leaving the server takes it with you")
drives(2, "pickup")
RM.team.offer(1, 2, "invite")
RM.team.accept(2)
ok(RM.team.of(keyOf(1)) ~= nil, "teamed again")
RM.team.forget(2)
eq(RM.team.of(keyOf(1)), nil, "and gone when one of them walks")

section("the team result is the two of them added up")
drives(2, "pickup")
RM.team.offer(1, 2, "invite")
RM.team.accept(2)
local standings = RM.team.standings({
  { key = keyOf(1), name = "Marx", corrected = 100 },
  { key = keyOf(2), name = "Colt", corrected = 110 },
})
ok(standings ~= nil, "there is a standing")
eq(#standings, 1, "one team")
eq(standings[1].total, 210, "and the two times added together")

local half = RM.team.standings({ { key = keyOf(1), name = "Marx", corrected = 100 } })
eq(half, nil, "a team with only one of them home does not place")
RM.team.leave(1)

-- =================================================================  records

section("his class list is the one the server knows")
local names = RM.records.classList()
eq(#names, 17, "all seventeen he sent")
eq(names[1].name, "Class 10", "in his order, starting where his list starts")
eq(names[1].division, "Limited", "with the division he put it in")
eq(names[#names].name, "Trophy Truck", "and ending where his ends")
eq(RM.records.isClass("Trophy Truck Spec"), "Trophy Truck Spec", "a real one is known")
eq(RM.records.isClass("Class 4"), nil, "one he never sent is not")
eq(RM.records.isClass("trophy truck"), nil, "and the spelling has to match")

section("a class is entered, not guessed from the car")
eq(RM.records.classOf("pickup"), "all",
   "he allows every vehicle, so no car belongs to a class on its own")
eq(RM.records.classFor({ vehicle = "pickup", class = "Class 8" }), "Class 8",
   "what the driver entered is what counts")
eq(RM.records.classFor({ vehicle = "pickup", class = "Class 4" }), "all",
   "and a class nobody has heard of counts for nothing")
eq(RM.records.classFor({ vehicle = "pickup" }), "all",
   "a run with no class sits on the board everybody shares")

section("a class can still be pinned to cars, for the day he wants that")
local hisClasses = RM.config.classes
RM.config.classes = {
  { division = "Unlimited", name = "Trophy Truck", cars = { "pickup" } },
  { division = "Limited",   name = "UTV Pro NA",   cars = { "utv" } },
}
eq(RM.records.classOf("pickup"), "Trophy Truck", "the car finds its class")
eq(RM.records.classOf("covet"), "all", "and a car left off every list finds none")
eq(RM.records.carAllowed("Trophy Truck", "pickup"), true, "the right car may enter")
eq(RM.records.carAllowed("Trophy Truck", "covet"), false, "the wrong one may not")
RM.config.classes = hisClasses

section("the books split by class when asked")
RM.records.submit("loop", { key = "beammp:1", name = "A", mode = "controller",
  corrected = 90, clean = 90, laps = {}, vehicle = "pickup", class = "Trophy Truck" })
RM.records.submit("loop", { key = "beammp:2", name = "B", mode = "controller",
  corrected = 80, clean = 80, laps = {}, vehicle = "pickup", class = "UTV Pro NA" })
RM.records.submit("loop", { key = "beammp:3", name = "C", mode = "controller",
  corrected = 70, clean = 70, laps = {}, vehicle = "pickup" })

local all = RM.records.wire("loop")
eq(all.modes.controller.total, 3, "unfiltered holds all of them")
eq(all.modes.controller.top[1].name, "C", "quickest first")

local trucks = RM.records.wire("loop", nil, "Trophy Truck")
eq(trucks.modes.controller.total, 1, "one truck")
eq(trucks.modes.controller.top[1].name, "A", "and it is the one who entered it")
eq(trucks.modes.controller.top[1].pos, 1, "placed first inside its own class")

local seen = {}
for _, c in ipairs(all.classes) do seen[c] = true end
ok(seen["Trophy Truck"] and seen["UTV Pro NA"], "the classes raced here are listed")
eq(seen["all"], nil, "and the unentered run is not offered as a class of its own")

local order = all.classes
eq(order[1], "UTV Pro NA", "listed in his order, limited before unlimited")
eq(order[2], "Trophy Truck", "not alphabetically")

section("your best is kept once per class, not once per course")
-- A slower run in another class is that class's first entry, not a run that
-- failed to beat you. Two very different cars are not the same lap.
RM.records.submit("split", { key = "beammp:9", name = "D", mode = "controller",
  corrected = 60, clean = 60, laps = {}, class = "Class 8" })
local second = RM.records.submit("split", { key = "beammp:9", name = "D",
  mode = "controller", corrected = 95, clean = 95, laps = {}, class = "Class 11" })
ok(second ~= nil, "the slower run in a second class still lands")
eq(second.class, "Class 11", "and takes that class outright, being the only one in it")

eq(RM.records.wire("split", nil, "Class 8").modes.controller.total, 1, "one in the first")
eq(RM.records.wire("split", nil, "Class 11").modes.controller.total, 1, "one in the second")
eq(RM.records.wire("split").modes.controller.total, 2, "and two on the shared board")

local worse = RM.records.submit("split", { key = "beammp:9", name = "D",
  mode = "controller", corrected = 99, clean = 99, laps = {}, class = "Class 11" })
eq(worse, nil, "a slower run in a class you already hold does not move the books")
eq(RM.records.wire("split").modes.controller.total, 2, "and adds no row")

local better = RM.records.submit("split", { key = "beammp:9", name = "D",
  mode = "controller", corrected = 50, clean = 50, laps = {}, class = "Class 11" })
ok(better and better.personal, "beating your own class time does")
ok(better.track, "and taking the whole course with it says so")
eq(RM.records.wire("split").modes.controller.total, 2, "still two rows, one per class")

-- ==============================================================  qualifying

section("qualifying sets the grid for the next race")
eq(RM.lobby.gridOrder("nothing", { 1, 2 })[1], 1,
   "with no qualifying the order is the order they joined")

-- a qualifying session on this course put Colt ahead of Marx
local realOrder = RM.results.qualifyingOrder
RM.results.qualifyingOrder = function(id)
  if id == "quali-test" then return { keyOf(2), keyOf(1) } end
  return realOrder(id)
end

local grid = RM.lobby.gridOrder("quali-test", { 1, 2 })
eq(grid[1], 2, "the quicker qualifier starts at the front")
eq(grid[2], 1, "and the slower one behind")

-- somebody who was not in qualifying still gets a place, at the back
join(3, "Rico", "9004")
local mixed = RM.lobby.gridOrder("quali-test", { 3, 1, 2 })
eq(mixed[1], 2, "qualifiers first, quickest of them at the front")
eq(mixed[2], 1, "then the other qualifier")
eq(mixed[3], 3, "and whoever did not qualify lines up behind them")

RM.results.qualifyingOrder = realOrder

print("")
print(("%d passed, %d failed"):format(pass, fail))
for _, f in ipairs(failures) do print("  - " .. f) end
os.exit(fail == 0 and 0 or 1)
