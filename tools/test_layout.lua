-- The decision that puts Race Manager on the screen: add it, mend it, or
-- leave it alone. Run against layouts shaped like the ones the game writes,
-- including the one that was actually on his machine.
--
--   lua tools/test_layout.lua

local L = dofile("client/lua/ge/extensions/raceManager/layout.lua")

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

local function layout(apps) return { type = "beammp", filename = "x.uilayout.json", apps = apps } end
local function app(name, placement) return { appName = name, placement = placement } end

section("a fresh player has no entry, so it is added")
local a, i, x = L.decide(layout({ app("tacho2", { bottom = "5px" }), app("beammpchat", {}) }))
eq(a, "add", "the app list without it")
eq(i, nil, "no index to speak of")
eq(#x, 0, "and no copies")

eq(L.decide(nil), "add", "no layout at all still says add rather than crashing")
eq(L.decide({ apps = "nonsense" }), "add", "and so does a broken one")

section("the entry that was really on his machine gets mended")
-- his own beammp layout: added by hand, dragged to the middle, sized in ems
local his = layout({
  app("beammpchat", { bottom = "0px" }),
  app("raceManager", { bottom = "", height = "65.13em", left = "50%",
                       position = "absolute", right = "", top = "50%", width = "117.63em" }),
})
a, i, x = L.decide(his)
eq(a, "repair", "half way across the screen is not the whole screen")
eq(i, 1, "and it is the second entry, counted from nought the way the game does")

section("the whole screen from the corner is left alone")
local fine = layout({ app("raceManager", L.WANT) })
eq(L.decide(fine), "fine", "what this writes is what it accepts")
eq(L.decide(layout({ app("raceManager", { top = "0", left = 0, width = "100%", height = "100%" }) })),
   "fine", "nought spelt any way the game spells it")
eq(L.decide(layout({ app("raceManager", { top = "0em", left = "0.0px", width = "100%", height = "100%" }) })),
   "fine", "including with units on it")

section("anything short of the whole screen is mended")
eq(L.decide(layout({ app("raceManager", { top = "0px", left = "0px", width = "100%", height = "60%" }) })),
   "repair", "not tall enough")
eq(L.decide(layout({ app("raceManager", { top = "0px", left = "12px", width = "100%", height = "100%" }) })),
   "repair", "pushed in from the edge")
eq(L.decide(layout({ app("raceManager", { top = "0px", left = "0px", width = "1280px", height = "100%" }) })),
   "repair", "a fixed width is not the whole screen on every monitor")
eq(L.decide(layout({ app("raceManager") })), "repair", "and no placement at all")

section("two copies would draw two of everything")
a, i, x = L.decide(layout({
  app("raceManager", L.WANT), app("tacho2", {}), app("raceManager", { left = "50%" }),
  app("raceManager", {}),
}))
eq(a, "fine", "the first one is fine")
eq(i, 0, "it is the first entry")
eq(#x, 2, "the other two are copies")
eq(x[1], 2, "at the game's index two")
eq(x[2], 3, "and three")

section("what it wants is the app's own idea of itself")
eq(L.WANT.width, "100%", "full width")
eq(L.WANT.height, "100%", "full height")
eq(L.WANT.left, "0px", "from the left edge")
eq(L.WANT.top, "0px", "and the top")

-- ------------------------------------------------------------- the live part

-- The game's layout code, faked: it hands back a layout and writes down
-- every call, so the order of what force() asks for can be checked.
local calls, current, editing = {}, nil, false
extensions = { ui_appLayouts = {
  getCurrentLayout    = function() return current end,
  isEditing           = function() return editing end,
  addApp              = function(f, name, p) calls[#calls + 1] = { "add", f, name, p } return true end,
  applyPlacementPatch = function(f, i, p) calls[#calls + 1] = { "patch", f, i, p } return true end,
  removeApp           = function(f, i) calls[#calls + 1] = { "remove", f, i } return true end,
  setCurrentLayout    = function(f) calls[#calls + 1] = { "reload", f } return current end,
} }
log = function() end

local function reset() calls = {} end
local function names() local t = {} for i = 1, #calls do t[i] = calls[i][1] end return table.concat(t, ",") end

section("nothing is touched until the beammp layout is the one on screen")
current = nil
eq(L.force(), false, "no layout yet, look again later")
current = { type = "freeroam", filename = "/settings/ui_apps/layouts/default/freeroam.uilayout.json", apps = {} }
eq(L.force(), false, "somebody driving alone keeps their own layout")
eq(#calls, 0, "and nothing was written")

section("nor while the layout editor is open")
current = layout({})
current.filename = "/settings/ui_apps/layouts/default/beammp.uilayout.json"
editing = true
eq(L.force(), false, "wait for them to finish")
eq(#calls, 0, "without touching anything")
editing = false

section("a fresh player gets it added and shown straight away")
reset()
eq(L.force(), true, "done in one go")
eq(names(), "add,reload", "written, then read back in so it shows now")
eq(calls[1][3], "raceManager", "the right app")
eq(calls[1][4].width, "100%", "the whole screen")
eq(calls[2][2], current.filename, "the same file read back")

section("his own broken entry gets mended in place")
reset()
current = layout({ app("beammpchat", {}), app("raceManager", { left = "50%", top = "50%", width = "117.63em" }) })
current.filename = "/settings/ui_apps/layouts/default/beammp.uilayout.json"
eq(L.force(), true, "done")
eq(names(), "patch,reload", "patched where it is, then read back")
eq(calls[1][3], 1, "the second entry, counted from nought")
eq(calls[1][4].left, "0px", "back to the corner")

section("copies come off from the end first, so the kept one's index holds")
reset()
current = layout({ app("raceManager", { left = "50%" }), app("x", {}), app("raceManager", {}), app("raceManager", {}) })
current.filename = "f"
eq(L.force(), true, "done")
eq(names(), "remove,remove,patch,reload", "copies, then the mend, then the read back")
eq(calls[1][3], 3, "the last copy first")
eq(calls[2][3], 2, "then the one before it")
eq(calls[3][3], 0, "and the first entry is still the first")

section("a layout that is already right is left alone")
reset()
current = layout({ app("raceManager", L.WANT) })
current.filename = "f"
eq(L.force(), true, "nothing to do")
eq(#calls, 0, "and nothing was written, so a good file is not rewritten on every join")

section("an old game with no layout code is not an error")
extensions.ui_appLayouts = nil
eq(L.force(), true, "there is nothing to be done, so it is done")

section("it looks once a second after the level is up, and stops when it is done")
extensions.ui_appLayouts = { getCurrentLayout = function() return current end,
  addApp = function() end, applyPlacementPatch = function() end,
  removeApp = function() end, setCurrentLayout = function() end }
local looked = 0
extensions.ui_appLayouts.getCurrentLayout = function() looked = looked + 1 return nil end
L.arm()
for _ = 1, 25 do L.onUpdate(0.1) end
eq(looked, 2, "two and a half seconds, two looks")
current = layout({ app("raceManager", L.WANT) })
current.filename = "f"
extensions.ui_appLayouts.getCurrentLayout = function() looked = looked + 1 return current end
for _ = 1, 10 do L.onUpdate(0.1) end
eq(looked, 3, "one more look, and it was fine")
for _ = 1, 50 do L.onUpdate(0.1) end
eq(looked, 3, "and no more after that")

section("and gives up after half a minute rather than looking for ever")
looked = 0
extensions.ui_appLayouts.getCurrentLayout = function() looked = looked + 1 return nil end
L.arm()
-- six hundred tenths do not add up to exactly sixty in floating point, so
-- the count is allowed a look either side
for _ = 1, 600 do L.onUpdate(0.1) end
ok(looked >= 27 and looked <= 31, ("about thirty looks, not %d"):format(looked))
local before = looked
for _ = 1, 100 do L.onUpdate(0.1) end
eq(looked, before, "and none at all once it has given up")

print("")
print(("%d passed, %d failed"):format(pass, fail))
for _, f in ipairs(failures) do print("  - " .. f) end
os.exit(fail == 0 and 0 or 1)
