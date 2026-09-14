-- Keys for the Stella: power, push to pass, OK and the red button. They are
-- bound under Options, Controls, from the actions file next to the other
-- Race Manager keys. A key does what the button on the unit does, through
-- the unit's own functions, so the unit shows the press the same way.
-- Power is the screen's to keep, so that one goes to the screen.
local M = {}

local function unit()
  local ok, s = pcall(function() return extensions.bajaStella end)
  return ok and type(s) == "table" and s or nil
end

local function gui(event, data)
  pcall(function()
    if guihooks and guihooks.trigger then
      guihooks.trigger(event, data)
    end
  end)
end

function M.stellaToggle() gui("RaceManagerStellaKey", { action = "toggle" }) end
function M.stellaOn()     gui("RaceManagerStellaKey", { action = "on" }) end
function M.stellaOff()    gui("RaceManagerStellaKey", { action = "off" }) end

-- the flag: an answer to a car asking to pass, otherwise a request of our own
function M.stellaPass()
  local s = unit()
  if not s then return end
  local incoming = false
  pcall(function() incoming = s.blueFlagState and s.blueFlagState() == "incoming" end)
  if incoming then
    pcall(s.acknowledgeBlueFlag)
  else
    pcall(s.requestBlueFlag)
  end
end

function M.stellaOk()
  local s = unit()
  if s then pcall(s.acknowledgeBlueFlag) end
end

-- the red button: stopped, or moving again
function M.stellaSos()
  local s = unit()
  if s then pcall(s.toggleMechanicalBreakdown) end
end

return M
