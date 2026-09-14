local M = {}

-- Force Race Manager onto the active HUD layout as soon as the player is on a
-- BeamMP server. BeamMP often swaps layouts after join, so we keep re-checking
-- for a while instead of stopping after the first success.

-- Folder under ui/modules/apps/ is RaceManager — that is the appName the layout
-- system uses. Also accept the camelCase form used by older installs.
local APP_NAMES = { "RaceManager", "raceManager" }
local APP = "RaceManager"

local function onAServer()
  local ok, is = pcall(function()
    return MPCoreNetwork and MPCoreNetwork.isMPSession and MPCoreNetwork.isMPSession()
  end)
  return ok and is == true
end
M.onAServer = onAServer

M.REPLACES = { tacho2 = true, forcedInduction = true, simplePowertrainControl = true }

M.WANT = { top = "0px", left = "0px", right = "0px", bottom = "0px", width = "100%", height = "100%", position = "absolute" }

local function isOurApp(name)
  if type(name) ~= "string" then return false end
  for i = 1, #APP_NAMES do
    if name == APP_NAMES[i] then return true end
  end
  local low = name:lower()
  return low == "racemanager"
end

local function whole(v)
  return v == "100%"
end

local function nothing(v)
  if v == nil or v == 0 or v == "" then return true end
  local n = tonumber(tostring(v):match("^(-?[%d%.]+)"))
  return n == 0
end

function M.decide(layout)
  if type(layout) ~= "table" or type(layout.apps) ~= "table" then
    return "add", nil, {}
  end

  local found, foundAt = nil, nil
  local gone = {}

  for i, app in ipairs(layout.apps) do
    if type(app) == "table" then
      if isOurApp(app.appName) then
        if found then
          gone[#gone + 1] = i - 1
        else
          found, foundAt = app, i - 1
        end
      elseif M.REPLACES[app.appName] then
        gone[#gone + 1] = i - 1
      end
    end
  end

  table.sort(gone, function(a, b) return a > b end)

  if not found then
    return "add", nil, gone
  end

  local p = found
  local okSize = whole(p.width) and whole(p.height)
  local okPos = nothing(p.top) and nothing(p.left)
  if okSize and okPos then
    return "fine", foundAt, gone
  end
  return "repair", foundAt, gone
end

local function api()
  local a = extensions.ui_appLayouts or ui_appLayouts
  if type(a) ~= "table" or type(a.getCurrentLayout) ~= "function" then return nil end
  return a
end

-- True when the app is present and full-screen. False = keep trying.
function M.force()
  local a = api()
  if not a then return false end
  if type(a.isEditing) == "function" then
    local ok, editing = pcall(a.isEditing)
    if ok and editing then return false end
  end

  if not onAServer() then return false end

  local ok, layout = pcall(a.getCurrentLayout)
  if not ok or type(layout) ~= "table" then return false end
  if type(layout.filename) ~= "string" or layout.filename == "" then return false end

  local action, index, gone = M.decide(layout)
  if action == "fine" and #gone == 0 then
    return true
  end

  if action == "add" then
    pcall(a.addApp, layout.filename, APP, M.WANT)
    -- older clients may only know the camelCase name
    pcall(a.addApp, layout.filename, "raceManager", M.WANT)
  elseif action == "repair" and index ~= nil then
    pcall(a.applyPlacementPatch, layout.filename, index, M.WANT)
  end
  for i = 1, #gone do
    pcall(a.removeApp, layout.filename, gone[i])
  end

  pcall(a.setCurrentLayout, layout.filename)
  -- Some builds need an explicit reload
  pcall(function()
    if a.reloadCurrentLayout then a.reloadCurrentLayout() end
  end)

  log("I", "raceManager", ("layout: %s%s in %s"):format(
    action, #gone > 0 and (", " .. #gone .. " taken out") or "", layout.filename))

  -- Re-read to confirm; only stop retrying when it is actually fine.
  local ok2, layout2 = pcall(a.getCurrentLayout)
  if ok2 and type(layout2) == "table" then
    local a2, _, g2 = M.decide(layout2)
    if a2 == "fine" and #g2 == 0 then return true end
  end
  return false
end

-- Keep trying for a long time: BeamMP can swap the layout minutes after join.
local EVERY = 1.0
local MAX_ARMED = 600.0  -- seconds of retries after arm()

local armed, since, armedFor = false, 0, 0

function M.arm()
  armed, since, armedFor = true, 0, 0
  -- Try immediately as well
  pcall(M.force)
end

function M.disarm()
  armed = false
end

function M.onUpdate(dt)
  if not armed then return end
  dt = tonumber(dt) or 0
  since = since + dt
  armedFor = armedFor + dt
  if armedFor > MAX_ARMED then
    -- keep a slow heartbeat forever while on a server so a late BeamMP layout
    -- swap still gets Race Manager back on screen
    if since < 15.0 then return end
    since = 0
    if not onAServer() then return end
    M.force()
    return
  end
  if since < EVERY then return end
  since = 0
  M.force()
end

return M
