local M = {}

-- Watching another driver. The server says who may watch whom; this puts
-- the camera on their car and keeps it off everyone else's.
--
-- BeamMP names every car by its owner and number, and its own player list
-- enters a car the same way this does: be:enterVehicle on the object. Once
-- in, the C key cycles the cameras as usual, which is where CoPilot (in the
-- seat) and Chase (behind the car) come from. The stock TAB switch is shut:
-- a switch to a car that is neither your own nor the one you were given is
-- undone on the spot, so watching is by invite or request only.

local st = {
  watching = nil,   -- { pid, vid, name } from the server
  gameId   = nil,   -- the game's id for that car, once found
  ownId    = nil,   -- the car to go back to
  pending  = nil,   -- a car the game has not spawned for us yet
  waited   = 0,
}

local LOOK_FOR = 20   -- seconds to keep looking for a car that is still loading (raised after queue take)

local function net() return extensions.raceManager_net end
local function notice(text) extensions.raceManager_state.notice(text) end

local function onServer()
  local ok, is = pcall(function()
    return MPCoreNetwork and MPCoreNetwork.isMPSession and MPCoreNetwork.isMPSession()
  end)
  return ok and is == true
end

local function playerVehicle()
  local ok, v = pcall(function() return be:getPlayerVehicle(0) end)
  return ok and v or nil
end

local function isOwn(gameId)
  local ok, own = pcall(function() return MPVehicleGE.isOwn(gameId) end)
  return ok and own == true
end

-- the game's id for a server car, or nil while it has not spawned here yet
local function gameIdFor(pid, vid)
  local ok, id = pcall(function()
    return MPVehicleGE.getGameVehicleID(tostring(pid) .. "-" .. tostring(vid))
  end)
  if ok and type(id) == "number" and id > 0 then return id end
  return nil
end

local function enter(gameId)
  local ok = pcall(function()
    local obj = be:getObjectByID(gameId)
    if obj then be:enterVehicle(0, obj) end
  end)
  return ok
end

local function rememberOwn()
  local v = playerVehicle()
  if not v then return end
  local ok, id = pcall(function() return v:getID() end)
  if ok and id and isOwn(id) then st.ownId = id end
end

-- what the screen shows
function M.status()
  return {
    watching = st.watching and {
      name = st.watching.name,
      found = st.gameId ~= nil,
      pid = st.watching.pid,
      vid = st.watching.vid,
      gameId = st.gameId,
    } or nil,
    gameId = st.gameId,
  }
end

------------------------------------------------------------ from the server

local function tryLook()
  if not st.watching then return end
  local id = gameIdFor(st.watching.pid, st.watching.vid)
  if not id then return false end
  st.gameId = id
  st.pending = nil
  enter(id)
  extensions.raceManager_ui.push()
  return true
end

local function onWatch(d)
  if type(d) ~= "table" or d.pid == nil or d.vid == nil then return end
  rememberOwn()
  st.watching = { pid = tonumber(d.pid), vid = tonumber(d.vid), name = tostring(d.name or "") }
  st.gameId = nil
  st.pending = true
  st.waited = 0
  if tryLook() then
    notice(("Watching %s. C changes the camera, Stop watching brings you back."):format(st.watching.name))
  else
    notice(("Watching %s once their car is in."):format(st.watching.name))
  end
end

local WHY = {
  stopped            = nil,
  ["driver ended it"] = "The driver ended it",
  ["the driver left"] = "The driver left",
  ["you armed a run"] = nil,
}

local function goHome()
  if st.ownId then enter(st.ownId) end
  st.watching, st.gameId, st.pending, st.waited = nil, nil, nil, 0
  extensions.raceManager_ui.push()
end

local function onRelease(d)
  local why = type(d) == "table" and tostring(d.why or "") or ""
  goHome()
  local text = WHY[why]
  if text == nil and why ~= "stopped" and why ~= "you armed a run" and why ~= "" then
    text = "Back in your own car: " .. why
  end
  if text then notice(text) end
end

local FAILED = {
  no_session        = "The server has not finished recognising you",
  not_yourself      = "Pick somebody else",
  not_here          = "They are not on the server",
  already_watching  = "You are already watching somebody. Stop first.",
  they_are_watching = "They are watching somebody else right now",
  you_are_racing    = "Finish your run first",
  they_are_racing   = "They are on a run right now",
  you_have_no_car   = "Get in a car first",
  they_have_no_car  = "They are not in a car",
  nothing_to_accept = "Nothing to accept",
  nothing_to_decline = "Nothing to turn down",
  nothing_to_stop   = "Nobody is watching anybody",
  they_left         = "They left",
}

local function onFailed(d)
  local why = type(d) == "table" and tostring(d.why or "") or ""
  notice(FAILED[why] or ("That did not work: " .. why))
end

local function onGone(d)
  local who = type(d) == "table" and tostring(d.who or "They") or "They"
  notice(who .. " said no")
end

------------------------------------------------------------ from the screen

function M.offer(pid, kind)
  local n = net()
  if not n then return end
  n.send("copilot.offer", { to = tonumber(pid), kind = (kind == "request") and "request" or "invite" })
end
function M.accept()  local n = net() if n then n.send("copilot.accept", {}) end end
function M.decline() local n = net() if n then n.send("copilot.decline", {}) end end
function M.stop()    local n = net() if n then n.send("copilot.stop", {}) end end
function M.get()     local n = net() if n then n.send("copilot.get", {}) end end

------------------------------------------------------------ the game

-- The stock switch, TAB or the BeamMP list, lands you in whichever car. If
-- it is not your own and not the one the server gave you, it is undone.
-- Switching back to your own car by hand counts as stopping.
function M.onVehicleSwitched(oldId, newId, player)
  if player ~= nil and player ~= 0 then return end
  if not onServer() then return end
  if type(newId) ~= "number" or newId < 0 then return end

  -- Still copiloting: if this is the car we were waiting on (or already on), keep it.
  if st.watching then
    if st.gameId == newId then return end
    local expected = gameIdFor(st.watching.pid, st.watching.vid)
    if expected and expected == newId then
      st.gameId = newId
      st.pending = nil
      st.waited = 0
      extensions.raceManager_ui.push()
      return
    end
    -- Any vehicle belonging to the driver we are watching counts as their seat
    -- (vid can change when they swap cars / queue applies a new spawn).
    local okOwner, ownerPid = pcall(function()
      if not MPVehicleGE or not MPVehicleGE.getVehicleByGameID then return nil end
      local veh = MPVehicleGE.getVehicleByGameID(newId)
      if type(veh) == "table" then
        return tonumber(veh.ownerID) or tonumber(tostring(veh.serverVehicleID or ""):match("^(%d+)%-"))
      end
      return nil
    end)
    if okOwner and ownerPid and tonumber(ownerPid) == tonumber(st.watching.pid) then
      st.gameId = newId
      st.pending = nil
      st.waited = 0
      st.watching.vid = st.watching.vid  -- keep last known; server will refresh via look()
      extensions.raceManager_ui.push()
      return
    end
  end

  if isOwn(newId) then
    st.ownId = newId
    if st.watching then
      -- Manual switch back to own car ends the watch session.
      st.watching, st.gameId, st.pending = nil, nil, nil
      local n = net()
      if n then n.send("copilot.stop", {}) end
      extensions.raceManager_ui.push()
    end
    return
  end

  if st.watching and st.gameId == newId then return end

  -- somebody else's car, and not one you were given
  local back = st.gameId or st.ownId
  if back and back ~= newId then
    enter(back)
    notice("Watching is by invite or request. Ask them under CoPilot.")
  end
end

-- Called after their BeamMP spawn/edit queue is applied so we keep looking for the car.
function M.keepWatchingAfterQueue(pid)
  pid = tonumber(pid)
  if not pid or not st.watching then return end
  if tonumber(st.watching.pid) ~= pid then return end
  st.pending = true
  st.waited = 0
  -- Give BeamMP time to finish the spawn after the queue is applied.
  LOOK_FOR = 45
  tryLook()
  extensions.raceManager_ui.push()
end

function M.onUpdate(dt)
  if not st.pending then return end
  st.waited = st.waited + (tonumber(dt) or 0)
  if st.waited > LOOK_FOR then
    st.pending = nil
    notice("Their car never turned up here, so watching is off")
    local n = net()
    if n then n.send("copilot.stop", {}) end
    st.watching, st.gameId = nil, nil
    extensions.raceManager_ui.push()
    return
  end
  tryLook()
end

function M.onLevelUnloaded()
  st.watching, st.gameId, st.ownId, st.pending, st.waited = nil, nil, nil, nil, 0
end

function M.onExtensionLoaded()
  local n = net()
  if not n then return end
  n.on("copilot.watch",   onWatch)
  n.on("copilot.release", onRelease)
  n.on("copilot.failed",  onFailed)
  n.on("copilot.gone",    onGone)
end

return M
