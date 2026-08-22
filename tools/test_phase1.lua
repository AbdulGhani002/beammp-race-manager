-- Runs the server plugin against the mock host. Everything phase 1 promises
-- gets exercised here: join, naming, the player list, the capture tool, the
-- permission gate, persistence, and the things a rewritten client might try.
--
--   lua54 tools/test_phase1.lua

local M = dofile("tools/mock/beammp.lua")

local pass, fail = 0, 0
local failures = {}

local function ok(cond, what)
  if cond then
    pass = pass + 1
  else
    fail = fail + 1
    failures[#failures + 1] = what
    print("  FAIL  " .. what)
  end
end

local function eq(got, want, what)
  ok(got == want, ("%s (got %s, wanted %s)"):format(what, tostring(got), tostring(want)))
end

local function section(title)
  print("")
  print("== " .. title)
end

-- alphabetical, exactly like the host loads them
local FILES = {
  "00_config", "01_util", "02_store", "03_bus", "04_identity",
  "05_roles", "06_players", "07_tracks", "08_console", "99_main",
}

os.execute("cmd /c rmdir /s /q Resources 2>nul")

for _, name in ipairs(FILES) do
  dofile("server/RaceManager/" .. name .. ".lua")
end

local function tick(n)
  for _ = 1, (n or 1) do M.fire("rm:tick") end
end

section("boot")
M.fire("onInit")
ok(M.hasHandler("rm:tick"), "tick handler registered")
ok(M.hasHandler("rmC2S"), "inbound handler registered")
ok(M.hasHandler("rm:c2s"), "the old event name still answers too")
ok(M.hasHandler("onPlayerJoining"), "join handler registered")
eq(RM.roles.countOwners(), 0, "nobody is owner on a fresh server")

section("join and handshake")
M.addPlayer(0, "DarrenBeamNG", "9001", false)
M.fire("onPlayerJoining", 0)
ok(RM.identity.session(0) ~= nil, "session exists after joining")
eq(RM.identity.session(0).key, "beammp:9001", "identity keyed on the forum id")
eq(RM.identity.session(0).hello, false, "hello not seen yet")

M.clientSend(0, "hello", { version = RM.VERSION })
local welcome = M.lastMessage(0, "welcome")
ok(welcome ~= nil, "welcome sent in reply to hello")
eq(welcome and welcome.name, nil, "no display name yet, so the client asks for one")
eq(welcome and welcome.role, "player", "new player starts as player")
eq(welcome and welcome.config and welcome.config.discordUrl ~= nil, true, "discord url reaches the client")
eq(RM.identity.session(0).hello, true, "hello recorded")

section("naming, once")
M.clientSend(0, "name.set", { name = "  Darren   Hardesty " })
local res = M.lastMessage(0, "name.result")
eq(res and res.ok, true, "name accepted")
eq(res and res.name, "Darren Hardesty", "whitespace tidied")

M.clientSend(0, "name.set", { name = "SomethingElse" })
res = M.lastMessage(0, "name.result")
eq(res and res.ok, false, "a second name is refused")
eq(res and res.reason, "already_named", "and says why")

M.addPlayer(1, "Guest_1234", nil, true)
M.fire("onPlayerJoining", 1)
M.clientSend(1, "hello", { version = RM.VERSION })
eq(RM.identity.session(1).key, "guest:Guest_1234", "guests key on their name")
eq(RM.identity.isRanked(1), false, "guests are not ranked")

M.clientSend(1, "name.set", { name = "darren hardesty" })
res = M.lastMessage(1, "name.result")
eq(res and res.reason, "taken", "display names are unique regardless of case")

M.clientSend(1, "name.set", { name = "x" })
eq(M.lastMessage(1, "name.result").reason, "too_short", "short names refused")
M.clientSend(1, "name.set", { name = string.rep("a", 40) })
eq(M.lastMessage(1, "name.result").reason, "too_long", "long names refused")
M.clientSend(1, "name.set", { name = "drop; table --" })
eq(M.lastMessage(1, "name.result").reason, "bad_chars", "odd characters refused")
M.clientSend(1, "name.set", { name = "Speedy" })
eq(M.lastMessage(1, "name.result").ok, true, "a good name still works")

section("player list")
M.clearOutbox()
M.clientSend(0, "roster.sub", { on = true })
tick(1)
local full = M.lastMessage(0, "roster.full")
ok(full ~= nil, "full roster sent when the list opens")
eq(#full, 2, "both players are in it")

M.fire("onVehicleSpawn", 0, 100)
M.setVelocity(0, 100, 20, 0, 0, 42)     -- 20 m/s is about 45 mph
M.clearOutbox()
M.advance(1)
tick(5)
local delta = M.lastMessage(0, "roster.delta")
ok(delta ~= nil, "a moving car produces a roster delta")
local row
for _, r in ipairs(delta or {}) do if r.id == 0 then row = r end end
ok(row and row.speed >= 44 and row.speed <= 46, "speed read server side from the velocity")
eq(row and row.ping, 42, "ping read server side too")

M.clearOutbox()
M.advance(1)
tick(5)
eq(M.lastMessage(0, "roster.delta"), nil, "nothing resent while the value is unchanged")

section("capture tool is admin only")
M.advance(5)
M.clearOutbox()
M.clientSend(0, "track.begin", { id = "baja-1000", name = "Baja 1000", kind = "race", level = "utah" })
tick(1)
local cap = M.lastMessage(0, "capture.result")
eq(cap and cap.ok, false, "a player cannot start a capture")
eq(cap and cap.reason, "not_allowed", "and is told why")

section("console grants the first owner")
local out = RM.console.handle("rm role Darren Hardesty owner")
ok(out and out:find("owner") ~= nil, "console promoted by display name")
eq(RM.roles.of(0), "owner", "role applied to the live session")
ok(RM.console.handle("rm role Nobody Here admin"):find("ever joined") ~= nil,
   "unknown names are refused")

section("capturing a course")
M.clearOutbox()
M.clientSend(0, "track.begin", { id = "Baja 1000", name = "Baja 1000", kind = "race", level = "utah" })
tick(1)
cap = M.lastMessage(0, "capture.result")
eq(cap and cap.ok, true, "capture starts for an owner")
eq(cap and cap.data and cap.data.id, "baja-1000", "the id is slugged")

local function mark(x, y, z)
  M.clearOutbox()
  M.clientSend(0, "track.mark", { pos = { x = x, y = y, z = z }, yaw = 1.5 })
  tick(1)
  return M.lastMessage(0, "capture.result")
end

eq(mark(0, 0, 10).ok, true, "first gate")
eq(mark(0, 0, 10).reason, "too_close", "a double tap on the same spot is refused")
eq(mark(100, 0, 10).ok, true, "second gate")
eq(mark(200, 0, 10).ok, true, "third gate")

M.clearOutbox()
M.clientSend(0, "track.mark", { pos = { x = 0 / 0, y = 0, z = 0 }, yaw = 1 })
tick(1)
eq(M.lastMessage(0, "capture.result").reason, "bad_pos", "nan position refused")

M.clearOutbox()
M.clientSend(0, "track.mark", { pos = { x = 1e9, y = 0, z = 0 }, yaw = 1 })
tick(1)
eq(M.lastMessage(0, "capture.result").reason, "bad_pos", "absurd position refused")

M.clearOutbox()
M.clientSend(0, "track.gate", { w = 40, h = 10, d = 4 })
tick(1)
eq(M.lastMessage(0, "capture.result").data.size.w, 40, "gate width corrected after the fact")

M.clearOutbox()
M.clientSend(0, "track.undo")
tick(1)
eq(M.lastMessage(0, "capture.result").data, 2, "undo drops the last gate")

eq(mark(200, 0, 10).ok, true, "and the gate can be placed again")

M.clearOutbox()
M.clientSend(0, "track.finish")
tick(1)
cap = M.lastMessage(0, "capture.result")
eq(cap and cap.ok, true, "capture saved")
ok(RM.tracks.get("baja-1000") ~= nil, "course is in the store")
eq(#RM.tracks.get("baja-1000").checkpoints, 3, "with all three gates")
ok(RM.tracks.get("baja-1000").start ~= nil, "and a start line")

section("a saved course is not overwritten by accident")
M.clearOutbox()
M.clientSend(0, "track.begin", { id = "baja-1000", name = "Baja 1000", kind = "race", level = "utah" })
tick(1)
eq(M.lastMessage(0, "capture.result").reason, "already_exists", "overwrite has to be asked for")

M.clearOutbox()
M.clientSend(0, "track.begin",
  { id = "baja-1000", name = "Baja 1000", kind = "race", level = "utah", overwrite = true })
tick(1)
eq(M.lastMessage(0, "capture.result").ok, true, "and is allowed when it is")
M.clientSend(0, "track.cancel")

section("the course menu stays small")
M.clearOutbox()
RM.tracks.sendList(0)
tick(1)
local list = M.lastMessage(0, "track.list")
ok(list and list[1] and list[1].count == 3, "summary carries the count")
eq(list and list[1] and list[1].checkpoints, nil, "but not the checkpoints themselves")

M.clearOutbox()
M.clientSend(0, "track.get", { id = "baja-1000" })
tick(1)
local one = M.lastMessage(0, "track.full")
ok(one and one.checkpoints and #one.checkpoints == 3, "asking for one course sends its gates")

section("a rewritten client cannot do damage")
M.clearOutbox()
M.clientSendRaw(0, "not json at all")
M.clientSendRaw(0, "")
M.clientSendRaw(0, "{}")
M.clientSendRaw(0, [[{"m":"not an array"}]])
M.clientSendRaw(0, [[{"m":[{"c":123}]}]])
M.clientSend(0, "track.mark", "a string where a table goes")
M.clientSend(0, "name.set", 12345)
M.clientSend(0, "nonexistent.channel", { a = 1 })
M.clientSend(0, "roster.sub", nil)
ok(true, "malformed input did not raise")

local before = RM.bus.stats().refused
for _ = 1, 120 do M.clientSend(0, "roster.sub", { on = true }) end
ok(RM.bus.stats().refused > before, "a flood gets rate limited")

M.clearOutbox()
local huge = { t = 0, m = {} }
for i = 1, 500 do huge.m[i] = { c = "roster.sub", d = { on = true } } end
M.clientSendRaw(0, Util.JsonEncode(huge))
ok(true, "an oversized batch did not raise")

eq(RM.util.handlerErrorCount(), 0, "no handler raised at any point")

section("forgetting a stored player")
eq(RM.console.handle("rm forget Speedy"):find("still_connected") ~= nil, true,
   "a connected player cannot be forgotten")
eq(RM.identity.keyForName("Speedy") ~= nil, true, "and is still known")

section("persistence")
RM.store.flushAll()
local raw = io.open("Resources/Server/RaceManager/data/tracks.json", "rb")
ok(raw ~= nil, "tracks written to disk")
if raw then
  local body = raw:read("*a")
  raw:close()
  local back = Util.JsonDecode(body)
  ok(back and back["baja-1000"] ~= nil, "and it decodes back")
  eq(back and back["baja-1000"] and #back["baja-1000"].checkpoints, 3, "with the gates intact")
end

section("leaving")
M.advance(10)
M.clearOutbox()
M.fire("onPlayerDisconnect", 1)
M.removePlayer(1)
tick(1)
eq(RM.identity.session(1), nil, "session cleared")
eq(M.lastMessage(0, "roster.drop"), 1, "the other client is told to drop the row")

M.fire("onPlayerDisconnect", 0)
M.removePlayer(0)
tick(2)
ok(true, "an empty server keeps ticking without raising")

ok(RM.console.handle("rm forget Speedy"):find("free again") ~= nil,
   "a disconnected player can be forgotten")
eq(RM.identity.keyForName("Speedy"), nil, "and the display name is free again")

M.fire("onShutdown")

print("")
print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then
  for _, f in ipairs(failures) do print("  - " .. f) end
  os.exit(1)
end
