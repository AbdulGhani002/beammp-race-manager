RM = RM or {}
RM.racelog = {}

-- One line of json per finished race, for their discord bot. It runs on this
-- box already, so it just reads the file.
--
-- Append only, never read back. The other stores rewrite the whole file every
-- save, which would get slow on a log that only grows.

local DIR  = "Resources/Server/RaceManager/data"
local PATH = DIR .. "/results.jsonl"
local SCHEMA = 2

local written = 0
local failed = 0

-- flat on purpose. a reader that has to dig for the headline numbers will get
-- one of them wrong.
local function driverLine(e)
  local penSeconds, penCount = 0, 0
  for i = 1, #(e.penalties or {}) do
    penSeconds = penSeconds + (e.penalties[i].seconds or 0)
    penCount = penCount + 1
  end

  return {
    pos            = e.pos,
    name           = e.name,
    correctedTotal = e.corrected,   -- whole race, penalties in, what the order is by
    rawTotal       = e.clean,
    penaltySeconds = RM.util.round(penSeconds, 3),
    penaltyCount   = penCount,
    bestLap        = e.bestLap and e.bestLap.time or nil,
    bestLapNumber  = e.bestLap and e.bestLap.lap or nil,
    toLeader       = e.toLeader,
    toAhead        = e.toAhead,
    laps           = e.laps and #e.laps or 0,
    mode           = e.mode,
    class          = e.class,
    vehicle        = e.vehicle,
    marked         = e.suspect and true or false,
  }
end

function RM.racelog.record(payload, at)
  if type(payload) ~= "table" then return false end

  local line = {
    v         = SCHEMA,
    at        = at or os.time(),
    track     = payload.track,
    trackName = payload.trackName,
    circuit   = payload.circuit and true or false,
    gates     = payload.gates,
    bestLap   = payload.bestLap,
    finished  = {},
    dnf       = {},
  }

  for i = 1, #(payload.finished or {}) do
    line.finished[i] = driverLine(payload.finished[i])
  end

  for i = 1, #(payload.dnf or {}) do
    local d = payload.dnf[i]
    line.dnf[i] = { name = d.name, why = d.why, lap = d.lap }
  end

  local ok, body = pcall(Util.JsonEncode, line)
  if not ok or type(body) ~= "string" then
    failed = failed + 1
    RM.warn("could not encode a race for the log:", tostring(body))
    return false
  end

  if not FS.Exists(DIR) then FS.CreateDirectory(DIR) end

  local f, err = io.open(PATH, "ab")
  if not f then
    failed = failed + 1
    RM.warn("could not open the race log:", tostring(err))
    return false
  end

  -- checked, because on a full disk the write sits in a buffer and looks
  -- done, and the result was lost without a word
  local wrote = f:write(body, "\n")
  local flushed = f:flush()
  local closed = f:close()
  if not wrote or not flushed or not closed then
    failed = failed + 1
    RM.warn("a race did not reach the race log. Is the disk full?")
    return false
  end

  written = written + 1
  return true
end

function RM.racelog.stats()
  return { written = written, failed = failed, path = PATH }
end
