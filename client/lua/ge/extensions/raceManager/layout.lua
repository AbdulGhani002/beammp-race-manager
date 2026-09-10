local M = {}

-- Puts Race Manager on the screen without anyone opening the app list.
--
-- BeamMP switches every player to its own layout when they join a server,
-- and the game keeps that layout as a file in the player's settings. This
-- looks at that layout once the session is up and makes sure Race Manager
-- is in it, the whole screen from the corner, the way its own app.json asks.
-- Nothing else is touched. A player's freeroam layout is their own business,
-- and so is where they put every other app.
--
-- The game's own layout code does the writing. What is here is only the
-- decision, kept apart so it can be tested without a game.

local APP  = "raceManager"

-- Whether we are on a server at all. BeamMP says so; a game with no BeamMP
-- is a game driving alone. It used to be judged by the layout being the one
-- BeamMP names "beammp", and a map that brings its own layout put the
-- session on a different one, and Race Manager stayed off the screen.
local function onAServer()
  local ok, is = pcall(function()
    return MPCoreNetwork and MPCoreNetwork.isMPSession and MPCoreNetwork.isMPSession()
  end)
  return ok and is == true
end
M.onAServer = onAServer

-- What the dash inside Race Manager stands in for. BeamMP puts these in
-- the same corner, and two tachometers on top of each other is what was on
-- his screen. His gauge shows revs, speed, gear, boost and the drivetrain
-- buttons, so all three are covered.
M.REPLACES = { tacho2 = true, forcedInduction = true, simplePowertrainControl = true }

-- the whole screen, because the bars and windows are drawn inside it
M.WANT = { top = "0px", left = "0px", width = "100%", height = "100%", position = "absolute" }

local function whole(v)
  return v == "100%"
end

local function nothing(v)
  if v == nil or v == 0 or v == "" then return true end
  local n = tonumber(tostring(v):match("^(-?[%d%.]+)"))
  return n == 0
end

-- What to do about a layout: "add" when Race Manager is not in it, "repair"
-- when it is but not the whole screen, "fine" otherwise. The second value is
-- the entry's index as the game counts them, from nought. The third is
-- everything to take out: further copies of Race Manager, which happen when
-- somebody adds it twice by hand and would draw two of everything, and the
-- stock gauges the dash stands in for. Highest index first, so taking one
-- out does not move the next.
function M.decide(layout)
  if type(layout) ~= "table" or type(layout.apps) ~= "table" then
    return "add", nil, {}
  end

  local first, gone = nil, {}
  for i, app in ipairs(layout.apps) do
    if type(app) == "table" then
      if app.appName == APP then
        if first == nil then first = i else gone[#gone + 1] = i - 1 end
      elseif M.REPLACES[app.appName] then
        gone[#gone + 1] = i - 1
      end
    end
  end
  table.sort(gone, function(a, b) return a > b end)
  if first == nil then return "add", nil, gone end

  local p = layout.apps[first].placement
  local fine = type(p) == "table" and whole(p.width) and whole(p.height)
               and nothing(p.left) and nothing(p.top)
  return fine and "fine" or "repair", first - 1, gone
end

------------------------------------------------------------------ the game

local function api()
  local a = extensions.ui_appLayouts
  if type(a) ~= "table" or type(a.getCurrentLayout) ~= "function" then return nil end
  return a
end

-- True when there is nothing more to do, false to look again later.
function M.force()
  local a = api()
  if not a then
    -- an older game with no layout code to speak to. the app list still works.
    return true
  end
  if type(a.isEditing) == "function" and a.isEditing() then return false end

  -- somebody driving alone keeps their own layout, whatever it is called
  if not onAServer() then return false end

  local ok, layout = pcall(a.getCurrentLayout)
  if not ok or type(layout) ~= "table" then return false end
  if type(layout.filename) ~= "string" then return false end

  local action, index, gone = M.decide(layout)
  if action == "fine" and #gone == 0 then return true end

  -- The mend goes first, while the index it was given still points at the
  -- right entry. What comes out comes out afterwards, from the end, and by
  -- then nothing needs the index any more.
  if action == "add" then
    pcall(a.addApp, layout.filename, APP, M.WANT)
  elseif action == "repair" then
    pcall(a.applyPlacementPatch, layout.filename, index, M.WANT)
  end
  for i = 1, #gone do
    pcall(a.removeApp, layout.filename, gone[i])
  end

  -- Those write the file quietly. Reading it back in as the current layout
  -- is what tells the screen, so it shows now rather than on the next join.
  pcall(a.setCurrentLayout, layout.filename)
  log("I", "raceManager", ("layout: %s%s in %s"):format(
    action, #gone > 0 and (", " .. #gone .. " taken out") or "", layout.filename))
  return true
end

------------------------------------------------------------------ timing

-- BeamMP puts its layout up some moments after the level, and on a big map
-- that is minutes rather than seconds. So this looks once a second for as
-- long as it takes, and stops only when it is done. It used to give up after
-- half a minute, and on a one gigabyte map that was before the layout was
-- there to be looked at, so Race Manager never came up at all.
local EVERY = 1.0

local armed, since = false, 0

function M.arm()
  armed, since = true, 0
end

function M.disarm()
  armed = false
end

function M.onUpdate(dt)
  if not armed then return end
  dt = tonumber(dt) or 0
  since = since + dt
  if since < EVERY then return end
  since = 0
  if M.force() then armed = false end
end

return M
