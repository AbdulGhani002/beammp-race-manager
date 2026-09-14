-- Keybinds for Stella (on/off, pass, OK, SOS) and Race Manager players list.
-- Actions show up under Controls → Bindings once registered.
local M = {}

local function notice(text)
  pcall(function()
    if extensions.raceManager_state and extensions.raceManager_state.notice then
      extensions.raceManager_state.notice(text)
    end
  end)
end

local function gui(event, data)
  pcall(function()
    if guihooks and guihooks.trigger then
      guihooks.trigger(event, data)
    end
  end)
end

-- Stella power / visibility is owned by the Angular app (localStorage).
-- We fire a UI event the Stella app listens for.
function M.stellaToggle()
  gui("RaceManagerStellaKey", { action = "toggle" })
  notice("Stella toggle")
end

function M.stellaOn()
  gui("RaceManagerStellaKey", { action = "on" })
end

function M.stellaOff()
  gui("RaceManagerStellaKey", { action = "off" })
end

function M.stellaPass()
  pcall(function()
    if extensions.raceManager_stella and extensions.raceManager_stella.requestPass then
      extensions.raceManager_stella.requestPass()
    end
  end)
  gui("RaceManagerStellaKey", { action = "flag" })
end

function M.stellaOk()
  gui("RaceManagerStellaKey", { action = "ok" })
end

function M.stellaSos()
  pcall(function()
    if extensions.raceManager_stella and extensions.raceManager_stella.setBreakdown then
      extensions.raceManager_stella.setBreakdown(true)
    end
  end)
  gui("RaceManagerStellaKey", { action = "sos" })
end

function M.playersToggle()
  pcall(function()
    if extensions.raceManager_ui and extensions.raceManager_ui.togglePlayers then
      extensions.raceManager_ui.togglePlayers()
    end
  end)
end

local function onDown(fn)
  return function()
    local ok, err = pcall(fn)
    if not ok then log("E", "raceManager", "key action failed: " .. tostring(err)) end
  end
end

local ACTIONS = {
  {
    name = "rm_stella_toggle",
    title = "RM Stella On/Off",
    desc = "Toggle the Stella unit power / visibility",
    fn = M.stellaToggle,
  },
  {
    name = "rm_stella_pass",
    title = "RM Stella Pass Flag",
    desc = "Request overtake (blue flag) via Stella",
    fn = M.stellaPass,
  },
  {
    name = "rm_stella_ok",
    title = "RM Stella OK",
    desc = "Acknowledge / OK on Stella",
    fn = M.stellaOk,
  },
  {
    name = "rm_stella_sos",
    title = "RM Stella SOS / Breakdown",
    desc = "Hold equivalent: mechanical assistance request",
    fn = M.stellaSos,
  },
  {
    name = "rm_players_toggle",
    title = "RM Players List",
    desc = "Show or hide the Race Manager player list",
    fn = M.playersToggle,
  },
}

local registered = false

local function register()
  if registered then return end

  -- BeamNG core input actions (appear under Options → Controls)
  local ok = pcall(function()
    local list = {}
    for i = 1, #ACTIONS do
      local a = ACTIONS[i]
      list[a.name] = {
        order = 1200 + i,
        title = a.title,
        desc = a.desc,
        isBasic = true,
        onDown = onDown(a.fn),
      }
    end
    if extensions.core_input_actions and extensions.core_input_actions.registerActions then
      extensions.core_input_actions.registerActions(list)
      return true
    end
    if core_input_actions and core_input_actions.registerActions then
      core_input_actions.registerActions(list)
      return true
    end
    -- Older path: setExtensionActions
    if extensions.core_input and extensions.core_input.registerActions then
      extensions.core_input.registerActions(list)
      return true
    end
    return false
  end)

  if ok then
    registered = true
    log("I", "raceManager", "Stella / RM key actions registered (bind under Controls)")
  else
    log("W", "raceManager", "Could not register key actions yet; will retry")
  end
end

function M.onExtensionLoaded()
  register()
end

function M.onClientPostStartMission()
  register()
end

function M.onUpdate()
  if not registered then register() end
end

return M
