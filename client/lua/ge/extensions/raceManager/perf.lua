local M = {}

-- Measured FPS, mod off and mod on, every delivery. That was promised in
-- writing, so it is a button rather than a thing somebody remembers to do.
--
-- The sample buffer is allocated once and reused. Growing an array while
-- measuring frame times would be measuring the measurement.

local MAX_SECONDS = 120
local CAP = 30000

local samples = nil
local st = {
  running = false,
  label   = nil,
  left    = 0,
  frames  = 0,
  last    = nil,
}

function M.status() return st end

function M.start(label, seconds)
  if st.running then return false end
  if not samples then
    samples = table.new and table.new(CAP, 0) or {}
    for i = 1, CAP do samples[i] = 0 end
  end
  st.running = true
  st.label   = tostring(label or "unlabelled")
  st.left    = math.min(tonumber(seconds) or 30, MAX_SECONDS)
  st.total   = st.left
  st.frames  = 0
  extensions.raceManager_ui.push()
  return true
end

local function summarise()
  local n = st.frames
  if n < 2 then return nil end

  local sum, lo, hi = 0, math.huge, 0
  for i = 1, n do
    local fps = samples[i]
    sum = sum + fps
    if fps < lo then lo = fps end
    if fps > hi then hi = fps end
  end

  -- worst one percent of frames, which is where a stutter actually shows up
  local sorted = {}
  for i = 1, n do sorted[i] = samples[i] end
  table.sort(sorted)
  local slice = math.max(1, math.floor(n / 100))
  local lowSum = 0
  for i = 1, slice do lowSum = lowSum + sorted[i] end

  return {
    label   = st.label,
    seconds = st.total,
    frames  = n,
    avg     = sum / n,
    min     = lo,
    max     = hi,
    p1low   = lowSum / slice,
  }
end

local function stop()
  st.running = false
  local result = summarise()
  st.last = result
  if result then
    extensions.raceManager_net.send("perf", result)
    log("I", "raceManager", ("FPS %s: avg %.1f, 1%% low %.1f, min %.1f, max %.1f")
      :format(result.label, result.avg, result.p1low, result.min, result.max))
  end
  extensions.raceManager_ui.push()
end

function M.cancel()
  if not st.running then return end
  st.running = false
  st.frames = 0
  extensions.raceManager_ui.push()
end

local function onUpdate(dt)
  if not st.running then return end
  if dt and dt > 0 and st.frames < CAP then
    st.frames = st.frames + 1
    samples[st.frames] = 1 / dt
  end
  st.left = st.left - (dt or 0)
  if st.left <= 0 then stop() end
end

M.onUpdate = onUpdate

return M
