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

section("levels climb with it")
eq(RM.xp.levelFor(0), 1, "everybody starts at one")
eq(RM.xp.levelFor(999), 1, "a level short is still the level below")
eq(RM.xp.levelFor(1000), 2, "and the thousandth point turns it over")
eq(RM.xp.levelFor(4200), 5, "further up it keeps counting")

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

section("with no class list every car shares one book")
eq(RM.records.classOf("pickup"), "all", "a car nobody sorted is in the one book")

RM.config.classes = { ["Trophy Truck"] = { "pickup" }, ["Buggy"] = { "utv" } }
eq(RM.records.classOf("pickup"), "Trophy Truck", "once there is a list it is used")
eq(RM.records.classOf("utv"), "Buggy", "for each of them")
eq(RM.records.classOf("covet"), "all", "and anything left out stays in the one book")

section("the books split by class when asked")
RM.records.submit("loop", { key = "beammp:1", name = "A", mode = "controller",
  corrected = 90, clean = 90, laps = {}, vehicle = "pickup" })
RM.records.submit("loop", { key = "beammp:2", name = "B", mode = "controller",
  corrected = 80, clean = 80, laps = {}, vehicle = "utv" })

local all = RM.records.wire("loop")
eq(all.modes.controller.total, 2, "unfiltered holds both")
eq(all.modes.controller.top[1].name, "B", "quickest first")

local trucks = RM.records.wire("loop", nil, "Trophy Truck")
eq(trucks.modes.controller.total, 1, "one truck")
eq(trucks.modes.controller.top[1].name, "A", "and it is the truck driver")
eq(trucks.modes.controller.top[1].pos, 1, "placed first inside its own class")

local seen = {}
for _, c in ipairs(all.classes) do seen[c] = true end
ok(seen["Trophy Truck"] and seen["Buggy"], "and the classes on the course are listed")
RM.config.classes = {}

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
