-- Watching in the car, run outside the game: the camera goes onto the car
-- the server named, comes back on release, and the stock TAB switch onto
-- anybody else's car is undone.
--
--   lua tools/test_copilot_client.lua

local pass, fail = 0, 0

local function ok(cond, what)
  if cond then pass = pass + 1
  else fail = fail + 1 print("  FAIL  " .. what) end
end

local function eq(got, want, what)
  ok(got == want, ("%s (got %s, wanted %s)"):format(what, tostring(got), tostring(want)))
end

local function section(t) print("") print("== " .. t) end

-- the game and BeamMP, faked
local onServer = true
MPCoreNetwork = { isMPSession = function() return onServer end }

local own = { [100] = true }          -- game ids of my own cars
local known = { ["3-1"] = 300 }       -- server car -> game id, once spawned here
MPVehicleGE = {
  isOwn = function(id) return own[id] == true end,
  getGameVehicleID = function(sid) return known[sid] or -1 end,
}

local entered = {}
local current = 100
local objects = {}
local function obj(id) objects[id] = objects[id] or { id = id, getID = function() return id end } return objects[id] end
be = {
  getPlayerVehicle = function() return obj(current) end,
  getObjectByID = function(_, id) return obj(id) end,
  enterVehicle = function(_, _, o) entered[#entered + 1] = o.id; current = o.id end,
}

local sent, handlers, notices = {}, {}, {}
extensions = {
  raceManager_net = {
    on = function(ch, fn) handlers[ch] = fn end,
    send = function(ch, d) sent[#sent + 1] = { ch = ch, d = d } end,
  },
  raceManager_state = { notice = function(t) notices[#notices + 1] = t end },
  raceManager_ui = { push = function() end },
}

local C = dofile("client/lua/ge/extensions/raceManager/copilot.lua")
C.onExtensionLoaded()

local function lastSent(ch)
  for i = #sent, 1, -1 do if sent[i].ch == ch then return sent[i].d end end
  return nil
end

section("told to watch a car that is here, the camera goes onto it")
handlers["copilot.watch"]({ pid = 3, vid = 1, name = "Dard" })
eq(entered[#entered], 300, "entered Dard's car")
eq(C.status().watching and C.status().watching.name, "Dard", "the screen says who")
eq(C.status().watching.found, true, "and that the car was found")
ok(notices[#notices]:find("Watching Dard"), "and the driver is told: " .. notices[#notices])

section("TAB onto a stranger's car is undone while watching")
entered = {}
C.onVehicleSwitched(300, 500, 0)
eq(entered[#entered], 300, "back into Dard's car")
ok(notices[#notices]:find("invite or request"), "and told why")

section("TAB back to your own car counts as stopping")
entered = {}
C.onVehicleSwitched(300, 100, 0)
eq(#entered, 0, "nothing is undone")
eq(C.status().watching, nil, "not watching")
ok(lastSent("copilot.stop") ~= nil, "and the server is told")

section("released, the camera comes home")
handlers["copilot.watch"]({ pid = 3, vid = 1, name = "Dard" })
entered = {}
handlers["copilot.release"]({ why = "driver ended it" })
eq(entered[#entered], 100, "back in my own car")
eq(C.status().watching, nil, "watching nobody")
ok(notices[#notices]:find("driver ended"), "and told: " .. notices[#notices])

section("TAB onto a stranger's car is undone when not watching too")
entered = {}
C.onVehicleSwitched(100, 500, 0)
eq(entered[#entered], 100, "back in my own car")

section("a switch made for another player, or off a server, is left alone")
entered = {}
C.onVehicleSwitched(100, 500, 1)
eq(#entered, 0, "another player's switch is theirs")
onServer = false
C.onVehicleSwitched(100, 500, 0)
eq(#entered, 0, "single player keeps the stock switch")
onServer = true

section("a car that has not spawned here yet is waited for, then entered")
entered = {}
handlers["copilot.watch"]({ pid = 4, vid = 2, name = "Ghani" })
eq(#entered, 0, "nothing to enter yet")
eq(C.status().watching.found, false, "the screen says it is not here yet")
ok(notices[#notices]:find("once their car is in"), "and says so")
for _ = 1, 10 do C.onUpdate(0.5) end
eq(#entered, 0, "five seconds on, still waiting")
known["4-2"] = 400
C.onUpdate(0.5)
eq(entered[#entered], 400, "entered the moment it turned up")
eq(C.status().watching.found, true, "found")

section("a car that never turns up gives up after twenty seconds and says so")
handlers["copilot.release"]({ why = "stopped" })
sent = {}
handlers["copilot.watch"]({ pid = 5, vid = 9, name = "Nobody" })
for _ = 1, 50 do C.onUpdate(0.5) end
eq(C.status().watching, nil, "watching is off")
ok(lastSent("copilot.stop") ~= nil, "the server is told")
ok(notices[#notices]:find("never turned up"), "and so is the driver")

section("the driver's car changing moves the camera")
known["3-1"], known["3-2"] = 300, 301
handlers["copilot.watch"]({ pid = 3, vid = 1, name = "Dard" })
entered = {}
handlers["copilot.watch"]({ pid = 3, vid = 2, name = "Dard" })
eq(entered[#entered], 301, "onto the new car")
entered = {}
C.onVehicleSwitched(301, 300, 0)
eq(entered[#entered], 301, "and the old one is a stranger's car now")

section("the screen's buttons send the right thing")
sent = {}
C.offer(7, "request") eq(lastSent("copilot.offer").kind, "request", "a request")
eq(lastSent("copilot.offer").to, 7, "to the right player")
C.offer(7, "anything") eq(lastSent("copilot.offer").kind, "invite", "anything else is an invite")
C.accept()  ok(lastSent("copilot.accept") ~= nil, "accept")
C.decline() ok(lastSent("copilot.decline") ~= nil, "decline")
C.stop()    ok(lastSent("copilot.stop") ~= nil, "stop")

section("leaving the level forgets everything")
C.onLevelUnloaded()
eq(C.status().watching, nil, "nothing kept")

print("")
if fail > 0 then
  print(("%d passed, %d failed"):format(pass, fail))
  os.exit(1)
end
print(("%d passed, 0 failed"):format(pass))
