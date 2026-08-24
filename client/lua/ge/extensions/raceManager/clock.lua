local M = {}

-- The client half of the timing.
--
-- A crossing is stamped here, at the frame the trigger fires, and the server
-- converts that stamp into its own clock. Stamping it when the server hears
-- about it would add half a round trip to every split, and jitter would make
-- it a different amount each time, so the driver with the worse connection
-- would quietly lose seconds over a lap.
--
-- This side does not decide anything. It hands out a number that only ever
-- goes up and answers the probe honestly. The server works out the offset and
-- decides whether a stamp is worth believing.

local frames = 0        -- accumulated frame time, always kept warm as a floor
local read = nil        -- whichever source we settled on
local sourceName = "none"
local timer = nil

local function engineRuntime()
  return Engine.Platform.getRuntime()
end

local function highPerfTimer()
  return timer:stop() / 1000
end

local function frameTime()
  return frames
end

-- Any monotonic source works, because the offset is re-measured every few
-- seconds and the server keeps the best sample of the last eight. Engine
-- runtime is wall time and is the one we want; the others are here so a build
-- without it still races rather than failing to time anything at all.
local function choose()
  local ok, v = pcall(engineRuntime)
  if ok and type(v) == "number" and v > 0 then
    read, sourceName = engineRuntime, "engine runtime"
    return
  end

  local okNew, t = pcall(function() return hptimer() end)
  if okNew and t then
    timer = t
    local okRead, ms = pcall(highPerfTimer)
    if okRead and type(ms) == "number" then
      read, sourceName = highPerfTimer, "high performance timer"
      return
    end
  end

  read, sourceName = frameTime, "accumulated frame time"
end

function M.now()
  if not read then choose() end
  local ok, v = pcall(read)
  if ok and type(v) == "number" then return v end
  return frames
end

function M.source() return sourceName end

-- T2 is when the probe arrived and T3 is when the reply leaves. They are read
-- separately on purpose: whatever this side spends between them is real, and
-- subtracting it out is what keeps our own scheduling out of the offset.
local function onPing(t1)
  local t2 = M.now()
  local t3 = M.now()
  extensions.raceManager_net.send("clock.pong", { t1 = t1, t2 = t2, t3 = t3 })
end

local function onExtensionLoaded()
  choose()
  extensions.raceManager_net.on("clock.ping", onPing)
  log("I", "raceManager", "clock source: " .. sourceName)
end

local function onUpdate(dt)
  frames = frames + (dt or 0)
end

M.onExtensionLoaded = onExtensionLoaded
M.onUpdate          = onUpdate

return M
