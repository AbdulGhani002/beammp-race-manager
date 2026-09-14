-- Keep Race Manager full-screen after HUD edit, and restore UI positions on demand.
-- Typing !restoreui / /restoreui in chat clears saved bar/panel positions and re-fits the screen.
local M = {}

local function notice(text)
  pcall(function()
    if extensions.raceManager_state and extensions.raceManager_state.notice then
      extensions.raceManager_state.notice(text)
    end
  end)
end

local function layoutApi()
  return extensions.ui_appLayouts or ui_appLayouts
end

local function isEditing()
  local a = layoutApi()
  if not a or type(a.isEditing) ~= "function" then return false end
  local ok, editing = pcall(a.isEditing)
  return ok and editing and true or false
end

-- Ask the Angular UI to wipe localStorage positions and re-center everything.
-- With fit set it only pins the box and nudges the bars into view, and
-- keeps where everybody put things.
local function triggerUiRestore(hard, fit)
  pcall(function()
    if guihooks and guihooks.trigger then
      guihooks.trigger("RaceManagerRestoreUi", { hard = hard and true or false, fit = fit and true or false })
    end
  end)
  -- Also try executeJS paths some builds expose
  pcall(function()
    if be and be.executeJS then
      be:executeJS([[
        try {
          window.dispatchEvent(new CustomEvent('RaceManagerRestoreUi', { detail: { hard: true } }));
        } catch (e) {}
      ]])
    end
  end)
end

function M.forceHost()
  pcall(function()
    if extensions.raceManager_layout and extensions.raceManager_layout.force then
      extensions.raceManager_layout.arm()
      extensions.raceManager_layout.force()
    end
  end)
  pcall(function()
    if extensions.raceManager_hud and extensions.raceManager_hud.install then
      extensions.raceManager_hud.install()
    end
  end)
end

-- Full reset: clear saved positions + full-screen host + show instruments.
function M.restore()
  M.forceHost()
  triggerUiRestore(true)
  notice("Race Manager UI restored: bars and Stella put back.")
  return true
end

-- The soft one: the box back to the whole screen and every bar in view,
-- with the positions people chose left alone. A join used to run the full
-- reset and forget everybody's layout every time.
function M.fit()
  M.forceHost()
  triggerUiRestore(false, true)
end

-- Chat: !restoreui / /restoreui / !resetui
function M.maybeChatCommand(msg)
  if type(msg) ~= "string" then return false end
  local low = msg:lower():gsub("^%s+", ""):gsub("%s+$", "")
  low = low:gsub("^!", ""):gsub("^/", "")
  if low == "restoreui" or low == "resetui" or low == "fixui" or low == "ui restore" then
    M.restore()
    return true
  end
  return false
end

------------------------------------------------------------------ hooks

local wasEditing = false

function M.onUpdate(dt)
  local editing = isEditing()
  if wasEditing and not editing then
    -- Just left the HUD Apps editor — layout often saves a partial box and
    -- bars/Stella vanish. Force full screen and restore defaults after a beat.
    notice("Re-fitting Race Manager after UI edit")
    M.forceHost()
    -- delayed so BeamNG finishes applying the layout file first
    M._pendingFitIn = 0.35
  end
  wasEditing = editing

  if M._pendingFitIn then
    M._pendingFitIn = M._pendingFitIn - (tonumber(dt) or 0)
    if M._pendingFitIn <= 0 then
      M._pendingFitIn = nil
      M.fit()
    end
  end
end

-- BeamMP / game chat entry points (whichever this build fires)
function M.onChatMessage(message, sender)
  local text = message
  if type(message) == "table" then
    text = message.message or message.msg or message.text or message[1]
  end
  return M.maybeChatCommand(tostring(text or ""))
end

function M.onSendChatMessage(message)
  return M.maybeChatCommand(tostring(message or ""))
end

function M.onExtensionLoaded()
  -- Register as input action too
  pcall(function()
    local list = {
      rm_restore_ui = {
        order = 1210,
        title = "RM Restore UI",
        desc = "Reset Race Manager bars and Stella to default positions",
        isBasic = true,
        onDown = function() M.restore() end,
      },
    }
    if extensions.core_input_actions and extensions.core_input_actions.registerActions then
      extensions.core_input_actions.registerActions(list)
    elseif core_input_actions and core_input_actions.registerActions then
      core_input_actions.registerActions(list)
    end
  end)
end

function M.onClientPostStartMission()
  M.forceHost()
  M._pendingFitIn = 1.0
end

return M
