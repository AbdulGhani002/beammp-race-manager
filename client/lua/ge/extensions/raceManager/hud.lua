local M = {}

-- Put the interface on screen without anybody having to find it. He asked for
-- this after watching a new player fail to add it: the app list is three menus
-- deep and nobody on a race server should have to go there.
--
-- It adds our app to whatever layout they are already using. It does not
-- replace the layout: their speedo, tacho and everything else they arranged
-- stays exactly where it was. Forcing a whole layout on someone is how you
-- make a mod people uninstall.

local APP = "raceManager"

local PLACEMENT = {
  position = "absolute",
  top = "0", left = "0", right = "", bottom = "",
  width = "100%", height = "100%",
}

local checked = false

local function has(layout)
  if type(layout) ~= "table" or type(layout.apps) ~= "table" then return false end
  for _, a in ipairs(layout.apps) do
    if a.appName == APP then return true end
  end
  return false
end

function M.install()
  if checked then return end
  if type(ui_appLayouts) ~= "table" then return end

  local ok, layout = pcall(function() return ui_appLayouts.getCurrentLayout() end)
  if not ok or type(layout) ~= "table" then return end

  checked = true

  if has(layout) then
    log("I", "raceManager", "interface already in the layout")
    return
  end

  local added = pcall(function()
    return ui_appLayouts.addApp(layout.filename or layout, APP, PLACEMENT)
  end)

  log(added and "I" or "W", "raceManager",
    added and ("added the interface to layout " .. tostring(layout.filename))
          or "could not add the interface to the layout, add it by hand under UI Apps")
end

-- so somebody who really does not want it can drop it and be left alone until
-- they next reconnect
function M.forget()
  checked = false
end

return M
