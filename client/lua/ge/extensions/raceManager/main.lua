local M = {}

M.VERSION = "0.7.11-own-stella"

-- ui goes last: it reads from every other module the moment it comes up
local SUBS = {
  "raceManager_state",
  "raceManager_editorlock",
  "raceManager_net",
  "raceManager_clock",
  "raceManager_triggers",
  "raceManager_capture",
  "raceManager_race",
  "raceManager_stellaUnit",
  "raceManager_stella",
  "raceManager_layout",
  "raceManager_keys",
  "raceManager_uifix",
  "raceManager_bottombar",
  "raceManager_service",
  "raceManager_copilot",
  "raceManager_hud",
  "raceManager_perf",
  "raceManager_ui",
}

-- The mod is activated as soon as it finishes downloading, which can be a long
-- way before the session is actually able to carry an event: on a first join
-- the map lands first and that took nine minutes. So hello is not a one shot.
-- It repeats until the server answers, and stops costing anything the moment
-- it does.
-- Quick at first, then slow, and never stopped. It used to stop for good
-- after ninety tries, and on a one gigabyte map all ninety went out during
-- the nine minutes the map took to download, into a session that was not
-- there yet. Then it fell silent, the server never heard hello, and nothing
-- came up on his screen at all. A tiny message every ten seconds costs
-- nothing; a player with no interface costs the evening.
local RETRY_EVERY = 2.0
local SLOW_AFTER  = 60        -- tries at the quick pace before slowing down
local SLOW_EVERY  = 10.0

local done, attempts, since = false, 0, 0

-- the server answering is a second chance to get on the screen: by then the
-- level is up for certain, however long the map took
local function onScreen()
  local ok = pcall(function() extensions.raceManager_layout.arm() end)
  return ok
end

function M.handshakeDone()
  onScreen()
  if done then return end
  done = true
  log("I", "raceManager", ("handshake done after %d attempt(s)"):format(attempts))
end

function M.isDone() return done end

local function trySayHello()
  attempts = attempts + 1

  if type(TriggerServerEvent) ~= "function" then
    if attempts == 1 or attempts % 10 == 0 then
      log("W", "raceManager", "BeamMP is not up yet, waiting to say hello")
    end
    return false
  end

  local sent = extensions.raceManager_net.send("hello", { version = M.VERSION })
  if attempts == 1 or attempts % 10 == 0 then
    log("I", "raceManager", ("hello attempt %d, sent=%s"):format(attempts, tostring(sent)))
  end
  return sent
end

function M.sayHello()
  trySayHello()
end

local function onExtensionLoaded()
  for _, name in ipairs(SUBS) do
    extensions.load(name)
    setExtensionUnloadMode(name, "manual")
  end
  setExtensionUnloadMode("raceManager_main", "manual")
  log("I", "raceManager", "Race Manager client " .. M.VERSION .. " loaded")
  trySayHello()
end

local function onClientStartMission(levelPath)
  -- the level is up, so the session is real now: back to the quick pace
  attempts, since = 0, 0
  extensions.raceManager_state.setLevel(levelPath)
  extensions.raceManager_triggers.onLevelLoaded()
  trySayHello()
end

-- leaving the level ends a run, the same as the button does. a run left open
-- would hold up the results for everybody else on the course.
local function onClientEndMission()
  extensions.raceManager_layout.disarm()
  extensions.raceManager_service.onLevelUnloaded()
  extensions.raceManager_copilot.onLevelUnloaded()
  extensions.raceManager_race.onLevelUnloaded()
  extensions.raceManager_triggers.clear()
  extensions.raceManager_capture.onLevelUnloaded()
end

-- BeamMP tears its network down and brings it back on a reconnect, so the
-- handshake has to be able to happen more than once
local function onClientPostStartMission()
  trySayHello()
  extensions.raceManager_hud.install()
  -- and onto the screen, without anyone opening the app list
  extensions.raceManager_layout.arm()
end

local function onExtensionUnloaded()
  extensions.raceManager_triggers.clear()
end

-- stops on the first line once the server has answered
local function onUpdate(dt)
  if done then return end
  since = since + dt
  if since < (attempts < SLOW_AFTER and RETRY_EVERY or SLOW_EVERY) then return end
  since = 0
  trySayHello()
end

M.onExtensionLoaded        = onExtensionLoaded
M.onExtensionUnloaded      = onExtensionUnloaded
M.onClientStartMission     = onClientStartMission
M.onClientPostStartMission = onClientPostStartMission
M.onClientEndMission       = onClientEndMission
M.onUpdate                 = onUpdate

return M
