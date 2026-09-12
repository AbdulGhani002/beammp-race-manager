-- Guests, against the mock host: they count like everybody, the door follows
-- the file their discord bot keeps, and a BeamMP account is called what
-- BeamMP calls it without a card.
--
--   lua tools/test_guests.lua

local M = dofile("tools/mock/beammp.lua")

local pass, fail = 0, 0

local function ok(cond, what)
  if cond then pass = pass + 1
  else fail = fail + 1 print("  FAIL  " .. what) end
end

local function eq(got, want, what)
  ok(got == want, ("%s (got %s, wanted %s)"):format(what, tostring(got), tostring(want)))
end

local function section(t) print("") print("== " .. t) end

os.execute("cmd /c rmdir /s /q Resources 2>nul")
M.loadPlugin()

local function tick(n) for _ = 1, (n or 1) do M.fire("rm:tick") end end

local GATE = "Resources/Server/PatreonAuth/allowed_discord_ids.json"
local function writeGate(body)
  os.execute("cmd /c mkdir Resources\\Server\\PatreonAuth 2>nul")
  local f = assert(io.open(GATE, "wb"))
  f:write(body)
  f:close()
end
local function removeGate() os.remove(GATE) end

M.fire("onInit")

section("with no file from the bot, guests are allowed")
eq(RM.identity.guestsAllowed(), true, "allowed")
eq(M.fire("onPlayerAuth", "guest123", "player", true), nil, "a guest gets through the door")

section("a guest is a player here: named, ranked, paid, and let into challenges")
M.addPlayer(0, "guest0270130", "", true, "203.0.113.1")
M.fire("onPlayerJoining", 0)
M.clientSend(0, "hello", { version = RM.VERSION })
tick(1)
local welcome = M.lastMessage(0, "welcome")
eq(welcome and welcome.name, nil, "a guest is asked for a name, since the one BeamMP gave is a number")
M.clientSend(0, "name.set", { name = "Dard" })
tick(1)
eq(RM.identity.displayName(0), "Dard", "and is called what they picked")
eq(RM.identity.isRanked(0), true, "ranked")
local key = RM.identity.session(0).key
ok(key:find("^guest:ip:") ~= nil, "keyed on the address, so tomorrow it is the same person")
local total = RM.xp.give(key, 50, "test")
eq(total, 50, "XP goes on a guest")
RM.console.handle("rm role Dard owner")

section("the bot's file with the gate off keeps the door open")
writeGate('{"enabled": false, "source": "bobby-patreon-role-sync", "allowed": ["1", "2"]}')
RM.identity.readGate()
eq(RM.identity.guestsAllowed(), true, "allowed")
eq(M.fire("onPlayerAuth", "guest555", "player", true), nil, "a guest gets in")

section("the gate switched on turns guests away at the door, and accounts still get in")
writeGate('{"enabled": true, "source": "bobby-patreon-role-sync", "allowed": ["1", "2"]}')
-- nothing changes until the file is read again, which the tick does every ten seconds
eq(RM.identity.guestsAllowed(), true, "not yet, the file has not been read again")
for _ = 1, 110 do tick(1) end
eq(RM.identity.guestsAllowed(), false, "read again within ten seconds, and now off")
local why = M.fire("onPlayerAuth", "guest555", "player", true)
ok(type(why) == "string" and why:find("BeamMP account"), "a guest is told to log in: " .. tostring(why))
eq(M.fire("onPlayerAuth", "RealName", "player", false), nil, "an account still gets in")
ok(RM.console.handle("rm guests"):find("turned away"), "the console says so")

section("and back off again, live")
writeGate('{"enabled": false}')
for _ = 1, 110 do tick(1) end
eq(RM.identity.guestsAllowed(), true, "allowed again")
eq(M.fire("onPlayerAuth", "guest555", "player", true), nil, "and through the door")

section("a file that will not read, or a missing key, means allowed")
writeGate('not json at all')
RM.identity.readGate()
eq(RM.identity.guestsAllowed(), true, "broken file, allowed")
writeGate('{"something": "else"}')
RM.identity.readGate()
eq(RM.identity.guestsAllowed(), true, "no key, allowed")
removeGate()
RM.identity.readGate()
eq(RM.identity.guestsAllowed(), true, "no file, allowed")

section("a BeamMP account is called what BeamMP calls it, with no card")
M.addPlayer(1, "Marx", "7001", false, "203.0.113.2")
M.fire("onPlayerJoining", 1)
M.clearOutbox(1)
M.clientSend(1, "hello", { version = RM.VERSION })
tick(1)
local w = M.lastMessage(1, "welcome")
eq(w and w.name, "Marx", "welcomed by name, no card")
eq(RM.identity.session(1).key, "beammp:7001", "keyed on the account")
eq(RM.identity.isRanked(1), true, "ranked")

section("an account whose name this server cannot take gets the card instead")
M.addPlayer(2, "Dard", "7002", false, "203.0.113.3")
M.fire("onPlayerJoining", 2)
M.clientSend(2, "hello", { version = RM.VERSION })
tick(1)
eq((M.lastMessage(2, "welcome") or {}).name, nil, "Dard is taken here, so the card")
M.addPlayer(3, "x", "7003", false, "203.0.113.4")
M.fire("onPlayerJoining", 3)
M.clientSend(3, "hello", { version = RM.VERSION })
tick(1)
eq((M.lastMessage(3, "welcome") or {}).name, nil, "too short a name, so the card")
M.clientSend(3, "name.set", { name = "Xavier" })
tick(1)
eq(RM.identity.displayName(3), "Xavier", "and the card still works for them")

section("a name picked before accounts came back is kept, not replaced")
M.fire("onPlayerDisconnect", 1)
M.addPlayer(1, "MarxRenamed", "7001", false, "203.0.113.2")
M.fire("onPlayerJoining", 1)
M.clientSend(1, "hello", { version = RM.VERSION })
tick(1)
eq(RM.identity.displayName(1), "Marx", "the same account keeps the name it had")

removeGate()
print("")
if fail > 0 then
  print(("%d passed, %d failed"):format(pass, fail))
  os.exit(1)
end
print(("%d passed, 0 failed"):format(pass))
