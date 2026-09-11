-- The bottom bar's game half, run outside the game: a hold locks the car and
-- every road out of a hold unlocks it. A locked gearbox is an engine that
-- revs and a car that does not move, and that must not be left behind by a
-- car swap, a run that ends, or a server that goes quiet.
--
--   lua tools/test_service_client.lua

local pass, fail = 0, 0

local function ok(cond, what)
  if cond then pass = pass + 1
  else fail = fail + 1 print("  FAIL  " .. what) end
end

local function eq(got, want, what)
  ok(got == want, ("%s (got %s, wanted %s)"):format(what, tostring(got), tostring(want)))
end

local function section(t) print("") print("== " .. t) end

-- the game, faked: two cars, a bridge that records freezes, a clock
local cars = {}
local function car(id)
  cars[id] = cars[id] or { id = id, getID = function() return id end,
    getPosition = function() return { x = 0, y = 0, z = 0 } end,
    getDirectionVector = function() return { x = 1, y = 0, z = 0 } end,
    queueLuaCommand = function() end }
  return cars[id]
end
local driving = 7
be = {
  getPlayerVehicle = function() return car(driving) end,
  getObjectByID = function(_, id) return cars[id] end,
}
local frozen = {}      -- id -> true/false, as last told
local actions = {}
core_vehicleBridge = {
  executeAction = function(v, what, arg)
    actions[#actions + 1] = { id = v.id, what = what, arg = arg }
    if what == "setFreeze" then frozen[v.id] = arg end
  end,
  requestValue = function() end,
}
local now = 1000
local sent, handlers, notices = {}, {}, {}
extensions = {
  raceManager_clock = { now = function() return now end },
  raceManager_net = {
    on = function(ch, fn) handlers[ch] = fn end,
    send = function(ch, d) sent[#sent + 1] = { ch = ch, d = d } end,
  },
  raceManager_state = { notice = function(t) notices[#notices + 1] = t end,
                        get = function() return { config = { penalties = {} } } end },
  raceManager_ui = { push = function() end },
  raceManager_race = { isRunning = function() return true end, inPit = function() return false end },
  raceManager_triggers = {},
  core_vehicle_manager = { getPlayerVehicleData = function() return nil end },
}

-- the game's maths and teleport, enough for a repair to go through
vec3 = function(x, y, z) return { x = x, y = y, z = z } end
quatFromDir = function() return { x = 0, y = 0, z = 0, w = 1 } end
spawn = { safeTeleport = function() end }

local S = dofile("client/lua/ge/extensions/raceManager/service.lua")
S.onExtensionLoaded()

local function freezes(id)
  local n = 0
  for _, a in ipairs(actions) do
    if a.what == "setFreeze" and a.id == id and a.arg == true then n = n + 1 end
  end
  return n
end

section("a hold locks the car, and the job at the end of it unlocks it")
handlers["service.hold"]({ which = "repair", hold = 20 })
eq(frozen[7], true, "locked for the hold")
eq(S.status().which, "repair", "and the bar knows what it is waiting for")
now = now + 20
S.onUpdate()
eq(frozen[7], true, "still locked the moment the hold is up: the server has the say")
handlers["service.run"]({ which = "repair" })
eq(frozen[7], false, "let go when the job comes")
eq(S.status().which, nil, "and the wait is over")

section("the car that was locked is the one let go, whatever the player is in by then")
actions = {}
handlers["service.hold"]({ which = "fuel", hold = 10 })
eq(frozen[7], true, "car 7 locked")
driving = 9
now = now + 10
handlers["service.run"]({ which = "fuel", full = false })
eq(frozen[7], false, "car 7 let go although the player is now in car 9")
ok(frozen[9] ~= true, "and car 9 was never locked")

section("a server that goes quiet after the hold is up does not keep the car")
actions = {}
driving = 7
handlers["service.hold"]({ which = "spare", hold = 20 })
eq(frozen[7], true, "locked")
now = now + 20
S.onUpdate()
eq(frozen[7], true, "up, but the grace is still running")
now = now + 4
S.onUpdate()
eq(frozen[7], true, "four seconds of grace")
now = now + 2
S.onUpdate()
eq(frozen[7], false, "six seconds past the end the car is let go regardless")
eq(S.status().which, nil, "the wait is cleared")
ok(notices[#notices] and notices[#notices]:find("let go"), "and the driver is told: " .. tostring(notices[#notices]))

section("a run ending while a car is held lets it go")
handlers["service.hold"]({ which = "repair", hold = 20 })
eq(frozen[7], true, "locked")
S.release()
eq(frozen[7], false, "released with the run")

section("the server refusing the job lets it go too")
handlers["service.hold"]({ which = "repair", hold = 20 })
eq(frozen[7], true, "locked")
handlers["service.failed"]({ which = "repair", why = "no_vehicle" })
eq(frozen[7], false, "released on the refusal")

section("leaving the level forgets the hold, so nothing is chased later")
handlers["service.hold"]({ which = "repair", hold = 20 })
S.onLevelUnloaded()
eq(S.status().which, nil, "no hold")
local said = #notices
now = now + 100
S.onUpdate()
eq(#notices, said, "and nothing is said about a job dropped")

section("a hold on top of a hold releases the first car before locking again")
actions = {}
driving = 7
handlers["service.hold"]({ which = "repair", hold = 20 })
driving = 9
handlers["service.hold"]({ which = "repair", hold = 20 })
eq(frozen[7], false, "car 7 let go")
eq(frozen[9], true, "car 9 locked")
handlers["service.run"]({ which = "repair" })
eq(frozen[9], false, "and let go when the job comes")

print("")
if fail > 0 then
  print(("%d passed, %d failed"):format(pass, fail))
  os.exit(1)
end
print(("%d passed, 0 failed"):format(pass))
