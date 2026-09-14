-- The world editor lock, run outside the game: on a server the editor keys
-- are blocked for everybody but the owner, an editor that is open anyway is
-- shut, and driving alone nothing is touched.
--
--   lua tools/test_editorlock_client.lua

local pass, fail = 0, 0

local function ok(cond, what)
  if cond then pass = pass + 1
  else fail = fail + 1 print("  FAIL  " .. what) end
end

local function eq(got, want, what)
  ok(got == want, ("%s (got %s, wanted %s)"):format(what, tostring(got), tostring(want)))
end

local function section(t) print("") print("== " .. t) end

-- the game, faked: the action filter, the editor, the server flag, the role
local groups, blocked, notices = {}, {}, {}
core_input_actionFilter = {
  setGroup = function(name, list) groups[name] = list end,
  addAction = function(filter, name, on) blocked[#blocked + 1] = { filter = filter, name = name, on = on } end,
}
local editorOpen, closedTimes = false, 0
editor = {
  isEditorActive = function() return editorOpen end,
  setEditorActive = function(on) if not on then editorOpen = false closedTimes = closedTimes + 1 end end,
}
local onServer, role = true, "player"
MPCoreNetwork = { isMPSession = function() return onServer end }
extensions = {
  raceManager_state = {
    get = function() return { me = { role = role } } end,
    notice = function(t) notices[#notices + 1] = t end,
  },
}
guihooks = { trigger = function() end }

local L = dofile("client/lua/ge/extensions/raceManager/editorlock.lua")

section("the keys it blocks are the editor's own, and nothing else")
do
  local src = io.open("client/lua/ge/extensions/raceManager/editorlock.lua"):read("a")
  ok(src:find('"editorToggle"', 1, true) ~= nil, "F11, the editor toggle")
  ok(src:find('"objectEditorToggle"', 1, true) ~= nil, "the object editor")
  ok(src:find('"editorSafeModeToggle"', 1, true) ~= nil, "and safe mode")
  ok(src:find("toggleCamera", 1, true) == nil, "the C key is the camera and is left alone")
  local block = src:match("local ACTIONS = {(.-)}")
  for name in block:gmatch('"(%w+)",') do
    if name ~= "editorToggle" and name ~= "objectEditorToggle" and name ~= "editorSafeModeToggle" then
      ok(false, "an action the game does not have: " .. name)
    end
  end
end

section("a player on a server has the editor keys blocked, once")
L.sync()
eq(#blocked, 1, "one filter call")
eq(blocked[1].filter, 0, "on the game's own filter")
eq(blocked[1].name, "raceManagerEditorLock", "by group name")
eq(blocked[1].on, true, "blocked")
eq(#groups.raceManagerEditorLock, 3, "the group holds the three editor keys")
L.sync()
L.onUpdate(1)
eq(#blocked, 1, "asked again, nothing is sent again")

section("an editor that is open anyway is shut, and the player told")
editorOpen = true
L.onUpdate(1)
eq(editorOpen, false, "shut")
eq(closedTimes, 1, "once")
eq(#notices, 1, "with a notice")
ok(notices[1]:find("locked", 1, true) ~= nil, "saying it is locked")

section("the owner is not blocked")
role = "owner"
L.onUpdate(1)
eq(#blocked, 2, "the filter is changed")
eq(blocked[2].on, false, "to let the keys through")
editorOpen = true
L.onUpdate(1)
eq(editorOpen, true, "and the owner's editor stays open")

section("driving alone, the editor is the player's own")
role = "player"
L.onUpdate(1)
eq(blocked[#blocked].on, true, "a player on a server: blocked")
onServer = false
L.onUpdate(1)
eq(blocked[#blocked].on, false, "off the server: the keys are given back")
editorOpen = true
L.onUpdate(1)
eq(editorOpen, true, "and an open editor is left open")

section("the check is a few times a second, not every frame")
onServer = true
local before = #blocked
L.onUpdate(0.01)
L.onUpdate(0.01)
eq(#blocked, before, "two frames later nothing has been looked at")
L.onUpdate(0.3)
eq(#blocked, before + 1, "a quarter second later it has")
eq(blocked[#blocked].on, true, "and the keys are blocked again")

print("")
print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
