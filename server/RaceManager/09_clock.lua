RM = RM or {}
RM.clock = {}

-- Stamping a crossing when the server hears about it adds half the round trip
-- to every split. On a 200ms connection that is roughly 100ms per gate, and
-- jitter makes it a different amount each time, so the driver with the worse
-- connection quietly loses. Across 29 gates it is seconds.
--
-- So the client stamps the crossing at the frame the trigger fires and the
-- server converts it. This is the arithmetic that makes the conversion
-- possible: the same four timestamp exchange NTP uses.
--
--   T1  server sent the probe
--   T2  client received it
--   T3  client sent the reply
--   T4  server received the reply
--
--   delay  = (T4 - T1) - (T3 - T2)
--   offset = ((T2 - T1) + (T3 - T4)) / 2
--
-- The sample kept is the one with the lowest delay, not the average. A slow
-- sample is one that sat in a queue, and queuing is asymmetric, which is
-- exactly what poisons an averaged offset. NTP keeps the best of the last
-- eight for the same reason.

local KEEP = 8
local PROBE_EVERY = 4.0

-- rides the batch that is already going out, so it costs no messages
function RM.clock.maybeProbe(pid, s)
  local now = RM.now()
  if s.clockNext and now < s.clockNext then return end
  s.clockNext = now + PROBE_EVERY
  s.clockSentAt = now
  RM.bus.queue(pid, "clock.ping", RM.util.round(now, 4))
end

function RM.clock.onPong(pid, d)
  local s = RM.identity.session(pid)
  if not s or type(d) ~= "table" then return end

  local t1 = tonumber(d.t1)
  local t2 = tonumber(d.t2)
  local t3 = tonumber(d.t3)
  local t4 = RM.now()
  if not (RM.util.isNum(t1) and RM.util.isNum(t2) and RM.util.isNum(t3)) then return end

  local delay  = (t4 - t1) - (t3 - t2)
  local offset = ((t2 - t1) + (t3 - t4)) / 2

  -- a negative delay is impossible and means the client is making numbers up
  if delay < 0 or delay > 10 then return end

  s.clockSamples = s.clockSamples or {}
  local n = #s.clockSamples + 1
  s.clockSamples[n] = { delay = delay, offset = offset }
  while #s.clockSamples > KEEP do table.remove(s.clockSamples, 1) end

  local best = nil
  for i = 1, #s.clockSamples do
    local c = s.clockSamples[i]
    if not best or c.delay < best.delay then best = c end
  end

  s.clockOffset = best.offset
  s.clockDelay  = best.delay
end

-- a client stamp turned into server time. returns the time and whether it was
-- trusted, so the caller can mark a run rather than silently using a guess.
function RM.clock.toServer(pid, clientTime)
  local s = RM.identity.session(pid)
  local now = RM.now()
  if not s or not RM.util.isNum(clientTime) or not s.clockOffset then
    return now, false
  end

  local t = clientTime - s.clockOffset
  local slack = (s.clockDelay or 0) + (RM.config.clockTrustMs / 1000)

  -- it cannot have happened in the future, and it cannot have happened
  -- further back than the connection could hide
  if t > now or t < (now - slack) then
    return now, false
  end

  return t, true
end

function RM.clock.info(pid)
  local s = RM.identity.session(pid)
  if not s then return nil end
  return {
    offset  = s.clockOffset,
    delay   = s.clockDelay,
    samples = s.clockSamples and #s.clockSamples or 0,
  }
end
