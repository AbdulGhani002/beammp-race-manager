-- Stella keybinds for Race Manager. Bound in Options → Controls from
-- race_manager.json. Delivers to the isolated RMSI UI via:
--   1) guihooks trigger RMSI_Key
--   2) a pull queue the Angular app polls (works when guihooks miss CEF)
--   3) window MessageEvent fallback
local M = {}

local queue = {}  -- FIFO of action strings for UI pull()

local function unit()
  local ok, s = pcall(function() return extensions.raceManager_stellaUnit end)
  return ok and type(s) == "table" and s or nil
end

local function enqueue(action)
  action = tostring(action or "")
  if action == "" then return end
  queue[#queue + 1] = action
  -- cap so a stuck UI cannot grow forever
  if #queue > 16 then table.remove(queue, 1) end
end

function M.pull()
  if #queue == 0 then return nil end
  return table.remove(queue, 1)
end

local function deliver(action)
  enqueue(action)
  pcall(function()
    if guihooks and guihooks.trigger then
      guihooks.trigger("RMSI_Key", { action = action })
      guihooks.trigger("RaceManagerStellaKey", { action = action })  -- legacy alias
    end
  end)
  pcall(function()
    if be and be.executeJS then
      be:executeJS(([[
        try {
          window.dispatchEvent(new MessageEvent('message', {
            data: { type: 'RMSI_Key', action: %q }
          }));
        } catch (e) {}
      ]]):format(action))
    end
  end)
end

function M.stellaToggle() deliver("toggle") end
function M.stellaOn()     deliver("on") end
function M.stellaOff()    deliver("off") end

function M.stellaPass()
  local s = unit()
  if not s then deliver("flag"); return end
  local incoming = false
  pcall(function() incoming = s.blueFlagState and s.blueFlagState() == "incoming" end)
  if incoming then
    pcall(s.acknowledgeBlueFlag)
  else
    pcall(s.requestBlueFlag)
  end
  deliver("flag")
end

function M.stellaOk()
  local s = unit()
  if s then pcall(s.acknowledgeBlueFlag) end
  deliver("ok")
end

function M.stellaSos()
  local s = unit()
  if s then pcall(s.toggleMechanicalBreakdown) end
  deliver("sos")
end

-- hook path some input maps prefer
function M.onRMStellaKey(action)
  action = tostring(action or "")
  if action == "toggle" then M.stellaToggle()
  elseif action == "on" then M.stellaOn()
  elseif action == "off" then M.stellaOff()
  elseif action == "pass" or action == "flag" then M.stellaPass()
  elseif action == "ok" then M.stellaOk()
  elseif action == "sos" then M.stellaSos()
  end
end

return M
