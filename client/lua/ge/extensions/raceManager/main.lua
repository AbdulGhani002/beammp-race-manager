local M = {}

M.VERSION = "0.2.0-phase1"

-- ui last: it reads from every other module the moment it comes up
local SUBS = {
  "raceManager_state",
  "raceManager_net",
  "raceManager_triggers",
  "raceManager_capture",
  "raceManager_perf",
  "raceManager_ui",
}

local helloSent = false

local function sayHello()
  if helloSent then return end
  -- BeamMP injects this when its own client lua is up. joining a singleplayer
  -- session means it never arrives, and that is fine.
  if type(TriggerServerEvent) ~= "function" then return end
  helloSent = true
  extensions.raceManager_net.send("hello", { version = M.VERSION })
end

local function onExtensionLoaded()
  for _, name in ipairs(SUBS) do
    extensions.load(name)
    setExtensionUnloadMode(name, "manual")
  end
  setExtensionUnloadMode("raceManager_main", "manual")
  log("I", "raceManager", "Race Manager client " .. M.VERSION .. " loaded")
  sayHello()
end

local function onClientStartMission(levelPath)
  helloSent = false
  sayHello()
  extensions.raceManager_state.setLevel(levelPath)
  extensions.raceManager_triggers.onLevelLoaded()
end

local function onClientEndMission()
  extensions.raceManager_triggers.clear()
  extensions.raceManager_capture.onLevelUnloaded()
end

-- BeamMP tears its network down and brings it back on a reconnect, so the
-- handshake has to be able to happen more than once
local function onExtensionUnloaded()
  extensions.raceManager_triggers.clear()
end

M.onExtensionLoaded    = onExtensionLoaded
M.onExtensionUnloaded  = onExtensionUnloaded
M.onClientStartMission = onClientStartMission
M.onClientEndMission   = onClientEndMission
M.sayHello             = sayHello

return M
