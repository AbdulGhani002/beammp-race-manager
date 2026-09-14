local M = {}

-- Put the interface on screen without anybody having to find it in UI Apps.

-- the name the game gives the app is its directive, raceManager. The folder
-- name was written into layouts for a while and this game still finds the
-- app by it, so both are ours.
local APP = "raceManager"
local APP_ALT = "RaceManager"

local PLACEMENT = {
  position = "absolute",
  top = "0", left = "0", right = "", bottom = "",
  width = "100%", height = "100%",
}

local function has(layout)
  if type(layout) ~= "table" or type(layout.apps) ~= "table" then return false end
  for _, a in ipairs(layout.apps) do
    if a.appName == APP or a.appName == APP_ALT or (type(a.appName) == "string" and a.appName:lower() == "racemanager") then
      return true
    end
  end
  return false
end

function M.install()
  local layouts = extensions.ui_appLayouts or ui_appLayouts
  if type(layouts) ~= "table" then return end

  local ok, layout = pcall(function() return layouts.getCurrentLayout() end)
  if not ok or type(layout) ~= "table" then return end

  -- the size the screen asked for, if it has, else the whole screen in percent
  local placement = PLACEMENT
  pcall(function()
    local want = extensions.raceManager_layout.askedFor()
    if type(want) == "table" then placement = want end
  end)

  if has(layout) then
    log("I", "raceManager", "interface already in the layout")
    return
  end

  local file = layout.filename or layout
  local ok2, added = pcall(function()
    return layouts.addApp(file, APP, placement)
  end)
  added = ok2 and added == true
  pcall(function() layouts.setCurrentLayout(file) end)

  log(added and "I" or "W", "raceManager",
    added and ("added the interface to layout " .. tostring(file))
          or "could not add the interface to the layout, add it by hand under UI Apps")
end

function M.forget()
end

return M
