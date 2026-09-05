local M = {}

M.VERSION = "0.5.8-store-backup"

-- ui goes last: it reads from every other module the moment it comes up
local SUBS = {
  "raceManager_state",
  "raceManager_net",
  "raceManager_clock",
  "raceManager_triggers",
  "raceManager_capture",
  "raceManager_race",
  "raceManager_bottombar",
  "raceManager_service",
  "raceManager_hud",
  "raceManager_perf",
  "raceManager_ui",
}

-- The mod is activated as soon as it finishes downloading, which can be a long
-- way before the session is actually able to carry an event: on a first join
-- the map lands first and that took nine minutes. So hello is not a one shot.
-- It repeats until the server answers, and stops costing anything the moment
-- it does.
local RETRY_EVERY = 2.0
local GIVE_UP_AFTER = 90

local done, attempts, since = false, 0, 0

function M.handshakeDone()
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
  extensions.raceManager_state.setLevel(levelPath)
  extensions.raceManager_triggers.onLevelLoaded()
  trySayHello()
end

-- leaving the level ends a run, the same as the button does. a run left open
-- would hold up the results for everybody else on the course.
local function onClientEndMission()
  extensions.raceManager_race.onLevelUnloaded()
  extensions.raceManager_triggers.clear()
  extensions.raceManager_capture.onLevelUnloaded()
end

-- BeamMP tears its network down and brings it back on a reconnect, so the
-- handshake has to be able to happen more than once
local function onClientPostStartMission()
  trySayHello()
  extensions.raceManager_hud.install()
end

local function onExtensionUnloaded()
  extensions.raceManager_triggers.clear()
end

-- stops on the first line once the server has answered
local function onUpdate(dt)
  if done then return end
  if attempts >= GIVE_UP_AFTER then return end
  since = since + dt
  if since < RETRY_EVERY then return end
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
