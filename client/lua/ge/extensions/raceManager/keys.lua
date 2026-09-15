-- Keys for the Stella: power, push to pass, OK and the red button. They are
-- bound under Options, Controls, from the actions file next to the other
-- Race Manager keys, and every one of them is a press of the button on
-- the screen: the screen polls the unit ten times a second and takes the
-- presses from a queue here. That is the one road. There were three for a
-- while, a hook, a message and this queue, and a press that arrives three
-- times toggles the power off and on again.
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
end

function M.stellaToggle() deliver("toggle") end
function M.stellaOn()     deliver("on") end
function M.stellaOff()    deliver("off") end

function M.stellaPass() deliver("flag") end
function M.stellaOk()   deliver("ok") end
function M.stellaSos()  deliver("sos") end

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
