-- Boost / nitrous (funBoost, toggleNitrousOxide, etc.) is staff/admin/owner only.
-- Non-staff have the actions filtered while on a server.
local M = {}

local ACTIONS = {
  "funBoost",
  "funBoostBackwards",
  "toggleNitrousOxide",
  "overrideNitrousOxide",
}
local GROUP = "raceManagerBoostLock"

local filtered = nil
local noticeCooldown = 0
local sinceLook = 0

local function isStaff()
  local st = extensions.raceManager_state
  if not (st and st.get) then return false end
  local me = st.get().me
  if not me then return false end
  local r = me.role
  return r == "staff" or r == "admin" or r == "owner"
end

local function onAServer()
  local ok, is = pcall(function()
    return MPCoreNetwork and MPCoreNetwork.isMPSession and MPCoreNetwork.isMPSession()
  end)
  return ok and is == true
end

local function filterActions(on)
  on = on and true or false
  if filtered == on then return end
  filtered = on
  pcall(function()
    local f = core_input_actionFilter
    if not (f and f.addAction) then return end
    if f.setGroup then f.setGroup(GROUP, ACTIONS) end
    f.addAction(0, GROUP, on)
  end)
end

local function noticeBlocked()
  if noticeCooldown > 0 then return end
  noticeCooldown = 2.5
  pcall(function()
    if extensions.raceManager_state and extensions.raceManager_state.notice then
      extensions.raceManager_state.notice("Boost / nitrous is locked on this server.")
    end
  end)
end

local function locked()
  return onAServer() and not isStaff()
end

function M.sync()
  if not locked() then
    filterActions(false)
    return
  end
  filterActions(true)
end

function M.onUpdate(dt)
  dt = tonumber(dt) or 0
  if noticeCooldown > 0 then noticeCooldown = noticeCooldown - dt end
  sinceLook = sinceLook + dt
  if sinceLook < 0.25 then return end
  sinceLook = 0
  M.sync()
end

function M.onExtensionLoaded()
  M.sync()
end

function M.onClientStartMission()
  M.sync()
end

function M.onClientPostStartMission()
  M.sync()
end

return M
