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
local a, i, x = L.decide(layout({ app("damageApp", { bottom = "0px" }), app("beammpchat", {}) }))
eq(a, "add", "the app list without it")
eq(i, nil, "no index to speak of")
eq(#x, 0, "and nothing to take out")

-- what a fresh player really has: BeamMP's own dash, which the tachometer stands in for
a, i, x = L.decide(layout({ app("tacho2", { bottom = "5px" }), app("beammpchat", {}) }))
eq(a, "add", "still added")
eq(#x, 1, "and the stock tachometer goes")
eq(x[1], 0, "at the game's index nought")

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
  app("raceManager", L.WANT), app("beammpchat", {}), app("raceManager", { left = "50%" }),
  app("raceManager", {}),
}))
eq(a, "fine", "the first one is fine")
eq(i, 0, "it is the first entry")
eq(#x, 2, "the other two are copies")
eq(x[1], 3, "the higher one first, so taking it out moves nothing")
eq(x[2], 2, "then the lower")

-- a build of the mod wrote the folder name into layouts for a while, and
-- this game still draws the app under it, so it is ours too: kept when it
-- is the only one, taken out when it is a second copy
section("an entry under the folder name is the same app")
a, i, x = L.decide(layout({ app("beammpchat", {}), app("RaceManager", L.WANT) }))
eq(a, "fine", "the whole screen under the folder name is fine")
eq(i, 1, "and it is the entry it is")
eq(#x, 0, "nothing comes out")
a, i, x = L.decide(layout({ app("raceManager", L.WANT), app("RaceManager", L.WANT) }))
eq(a, "fine", "with both spellings the first is fine")
eq(#x, 1, "and the other is a copy")
eq(x[1], 1, "the second entry")

section("the stock gauges the dash stands in for come out")
-- the corner of his screen: his tachometer drawn over the stock one
a, i, x = L.decide(layout({
  app("forcedInduction", { bottom = "320px", right = "20px" }),
  app("simplePowertrainControl", { bottom = "0px", right = "260px" }),
  app("damageApp", { bottom = "0px", left = "0px" }),
  app("tacho2", { bottom = "5px", right = "5px" }),
  app("raceManager", L.WANT),
}))
eq(a, "fine", "Race Manager itself is fine")
eq(i, 4, "and is the fifth entry")
eq(#x, 3, "three stock gauges to take out")
eq(x[1], 3, "the stock tachometer, highest first")
eq(x[2], 1, "the engine buttons")
eq(x[3], 0, "the boost gauge")
ok(L.REPLACES.bajastella and L.REPLACES.BajaStella, "and a Stella app placed on its own, under either spelling: Race Manager carries its own")
ok(not L.REPLACES.damageApp, "the damage readout is not one of them, the dash has no damage")
ok(not L.REPLACES.beammpchat, "nor the chat")

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

-- BeamMP, faked: whether this game is on a server
MPCoreNetwork = { isMPSession = function() return true end }

section("nothing is touched until there is a layout on screen")
current = nil
eq(L.force(), false, "no layout yet, look again later")

section("somebody driving alone keeps their own layout, whatever it is called")
MPCoreNetwork.isMPSession = function() return false end
current = layout({})
current.filename = "/settings/ui_apps/layouts/default/beammp.uilayout.json"
eq(L.force(), false, "not on a server, so not touched, even the one named beammp")
eq(#calls, 0, "and nothing was written")
MPCoreNetwork.isMPSession = function() return true end

section("on a server, whatever layout is up is the one it goes into")
-- his new map brought its own layout, and the old rule only knew the one
-- BeamMP names beammp, so Race Manager stayed off the screen entirely
reset()
current = { type = "freeroam", filename = "/settings/ui_apps/layouts/default/freeroam.uilayout.json", apps = {} }
eq(L.force(), true, "a layout of another name still gets it")
eq(names(), "add,reload", "added and read back in")
reset()

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

section("the mend goes first, then what comes out, from the end")
reset()
current = layout({ app("tacho2", {}), app("raceManager", { left = "50%" }), app("x", {}),
                   app("raceManager", {}), app("raceManager", {}) })
current.filename = "f"
eq(L.force(), true, "done")
eq(names(), "patch,remove,remove,remove,reload",
   "mended while its index still points at it, then the removals, then the read back")
eq(calls[1][3], 1, "mended at the index it had")
eq(calls[2][3], 4, "the last copy first")
eq(calls[3][3], 3, "then the one before it")
eq(calls[4][3], 0, "and the stock tachometer last, below the one that was mended")

section("a layout that is already right is left alone")
reset()
current = layout({ app("damageApp", {}), app("beammpchat", {}), app("raceManager", L.WANT) })
current.filename = "f"
eq(L.force(), true, "nothing to do")
eq(#calls, 0, "and nothing was written, so a good file is not rewritten on every join")

section("a right layout that still has the stock gauges only loses those")
reset()
current = layout({ app("raceManager", L.WANT), app("tacho2", {}) })
current.filename = "f"
eq(L.force(), true, "done")
eq(names(), "remove,reload", "one out, read back, nothing else touched")
eq(calls[1][3], 1, "the stock tachometer")

-- This game keeps its layout in em, and its editor shows the layout in a
-- smaller frame: touch anything there and Race Manager's box is written
-- down as that smaller size, centred, and after the editor closes the app
-- sits in a box in the middle of the screen. The screen measures itself
-- and says its size in em; once said, that exact size is what is asked
-- for, and the box the editor wrote is mended to it.
section("the box the layout editor wrote is mended, to the size the screen said")
reset()
current = layout({ app("beammpchat", {}),
                   app("raceManager", { position = "absolute", left = "50%", top = "50%", width = "90.2em", height = "39.2em" }) })
current.filename = "f"
eq(L.force(), true, "done")
eq(names(), "patch,reload", "patched and read back")
eq(calls[1][4].width, "100%", "before the screen has said its size, the whole screen in percent")
L.arm(117.6, 66.12)
reset()
current = layout({ app("beammpchat", {}),
                   app("raceManager", { position = "absolute", left = "50%", top = "50%", width = "90.2em", height = "39.2em" }) })
current.filename = "f"
eq(L.force(), true, "done")
eq(calls[1][1], "patch", "patched")
eq(calls[1][4].width, "117.60em", "to the screen's width in em")
eq(calls[1][4].height, "66.12em", "and its height")
eq(calls[1][4].left, "0em", "from the left edge")
eq(calls[1][4].top, "0em", "and the top")

section("once the size is known, that size is fine and the percent one is mended to it")
reset()
current = layout({ app("raceManager", { position = "absolute", left = "0em", top = "0em", width = "117.60em", height = "66.12em" }) })
current.filename = "f"
eq(L.force(), true, "nothing to do")
eq(#calls, 0, "the exact box is left alone")
reset()
current = layout({ app("raceManager", L.WANT) })
current.filename = "f"
eq(L.force(), true, "done")
eq(names(), "patch,reload", "the percent box, two percent off on a scaled interface, is mended")
eq(calls[1][4].width, "117.60em", "to the exact size")
L.arm()
eq(L.askedFor().width, "117.60em", "asked again without numbers, the size said before still stands")
reset()
current = layout({ app("beammpchat", {}) })
current.filename = "f"
eq(L.force(), true, "done")
eq(calls[1][1], "add", "a fresh player gets it added")
eq(calls[1][4].width, "117.60em", "at the size the screen said")
L.wantEm = nil

section("an old game with no layout code is not an error")
extensions.ui_appLayouts = nil
eq(L.force(), true, "there is nothing to be done, so it is done")

section("it looks once a second after the level is up, and stops only when it is done")
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

section("and keeps looking for as long as the map takes to come up")
-- it used to stop after half a minute. a one gigabyte map is still loading
-- then, and Race Manager never came up on it at all.
looked = 0
extensions.ui_appLayouts.getCurrentLayout = function() looked = looked + 1 return nil end
L.arm()
for _ = 1, 3000 do L.onUpdate(0.1) end
-- tenths do not add up cleanly in floating point, so the count is loose;
-- what matters is that it is still going
ok(looked >= 250, ("five minutes in it is still looking, %d looks"):format(looked))
current = layout({ app("raceManager", L.WANT) })
current.filename = "f"
extensions.ui_appLayouts.getCurrentLayout = function() looked = looked + 1 return current end
for _ = 1, 20 do L.onUpdate(0.1) end
local seen = looked
for _ = 1, 100 do L.onUpdate(0.1) end
eq(looked, seen, "and stops the moment it is done")

section("being disarmed stops it too")
L.arm()
L.disarm()
looked = 0
for _ = 1, 50 do L.onUpdate(0.1) end
eq(looked, 0, "leaving the level stops the looking")

print("")
print(("%d passed, %d failed"):format(pass, fail))
for _, f in ipairs(failures) do print("  - " .. f) end
os.exit(fail == 0 and 0 or 1)
