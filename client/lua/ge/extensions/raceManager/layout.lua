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
local TYPE = "beammp"

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
-- the entry's index as the game counts them, from nought. The third is any
-- further copies, which happen when somebody adds it twice by hand and would
-- otherwise draw two of everything.
function M.decide(layout)
  if type(layout) ~= "table" or type(layout.apps) ~= "table" then
    return "add", nil, {}
  end

  local first, extras = nil, {}
  for i, app in ipairs(layout.apps) do
    if type(app) == "table" and app.appName == APP then
      if first == nil then first = i else extras[#extras + 1] = i - 1 end
    end
  end
  if first == nil then return "add", nil, extras end

  local p = layout.apps[first].placement
  local fine = type(p) == "table" and whole(p.width) and whole(p.height)
               and nothing(p.left) and nothing(p.top)
  return fine and "fine" or "repair", first - 1, extras
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

  local ok, layout = pcall(a.getCurrentLayout)
  if not ok or type(layout) ~= "table" then return false end
  if layout.type ~= TYPE or type(layout.filename) ~= "string" then return false end

  local action, index, extras = M.decide(layout)
  if action == "fine" and #extras == 0 then return true end

  -- copies go first and from the end, so the index of the one kept holds
  for i = #extras, 1, -1 do
    pcall(a.removeApp, layout.filename, extras[i])
  end
  if action == "add" then
    pcall(a.addApp, layout.filename, APP, M.WANT)
  elseif action == "repair" then
    pcall(a.applyPlacementPatch, layout.filename, index, M.WANT)
  end

  -- Those write the file quietly. Reading it back in as the current layout
  -- is what tells the screen, so it shows now rather than on the next join.
  pcall(a.setCurrentLayout, layout.filename)
  log("I", "raceManager", ("layout: %s%s in %s"):format(
    action, #extras > 0 and (", " .. #extras .. " copy(s) removed") or "", layout.filename))
  return true
end

------------------------------------------------------------------ timing

-- BeamMP puts its layout up some moments after the level, so this looks
-- once a second for a while rather than once and giving up.
local EVERY   = 1.0
local GIVE_UP = 30.0

local armed, since, total = false, 0, 0

function M.arm()
  armed, since, total = true, 0, 0
end

function M.disarm()
  armed = false
end

function M.onUpdate(dt)
  if not armed then return end
  dt = tonumber(dt) or 0
  since, total = since + dt, total + dt
  if since < EVERY then return end
  since = 0
  if M.force() or total >= GIVE_UP then armed = false end
end

return M
