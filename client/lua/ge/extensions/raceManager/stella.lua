-- Race Manager -> Baja Stella display bridge.
--
-- This is deliberately a state/network adapter. Race Manager remains the
-- authority for arming, checkpoint hits, penalties, and race state. It never
-- creates trigger volumes or infers server decisions locally.
local M = {}

local lastTrackId
local lastState
local lastNext
local lastDone
local lastZoneKey
local lastZoneKph
local lastZoneFrom
local lastZoneTo
local lastZoneUpcoming
local lastTrackPayload
local netWired = false

local function stella()
  local ok, s = pcall(function() return extensions.bajaStella end)
  return ok and type(s) == "table" and s or nil
end

local function call(name, ...)
  local s = stella()
  if not s or type(s[name]) ~= "function" then return false end
  return pcall(s[name], ...)
end

-- Stella owns the display, while this optional adapter owns the Race Manager
-- network registration.  Server support is deliberately required: these
-- handlers do not infer a pass, a breakdown, or a penalty locally.
local function wireNetwork()
  if netWired then return end
  local net = extensions.raceManager_net
  local s = stella()
  if not net or type(net.on) ~= "function" or not s then return end
  net.on("stella.pass.alert", function(d) call("onRaceManagerPassAlert", d) end)
  net.on("stella.pass.status", function(d) call("onRaceManagerPassStatus", d) end)
  net.on("stella.pass.go", function(d) call("onRaceManagerPassGo", d) end)
  net.on("stella.breakdown.state", function(d) call("onRaceManagerBreakdownState", d) end)
  net.on("stella.breakdown.alert", function(d) call("onRaceManagerBreakdownAlert", d) end)
  netWired = true
end

local function position(cp)
  return type(cp) == "table" and type(cp.pos) == "table" and cp.pos or nil
end

local function checkpoint(track, index)
  local cps = type(track) == "table" and track.checkpoints
  return type(cps) == "table" and cps[tonumber(index) or 0] or nil
end

local function zoneKey(z, i)
  return tostring(i) .. ":" .. tostring(z.from) .. ":" .. tostring(z.to)
end

local function updateZones(track, nextCp)
  local zones = type(track) == "table" and track.zones
  if type(zones) ~= "table" then
    if lastZoneKey then call("setSpeedZone", nil) end
    lastZoneKey, lastZoneKph, lastZoneFrom, lastZoneTo = nil, nil, nil, nil
    return
  end

  -- A zone is current while its checkpoint interval contains the next
  -- checkpoint, and upcoming when its entry is still ahead.  Race Manager's
  -- saved indices are used as-is; no local crossing or scoring is inferred.
  local current, upcoming, upcomingFrom = nil, nil, nil
  for i, z in ipairs(zones) do
    if type(z) == "table" then
      local from, to = tonumber(z.from), tonumber(z.to)
      if from and to then
        if nextCp > from and nextCp <= to then
          current = { z = z, i = i }
        elseif from >= nextCp and (not upcomingFrom or from < upcomingFrom) then
          upcoming, upcomingFrom = { z = z, i = i }, from
        end
      end
    end
  end
  local chosen = current or upcoming
  if not chosen then
    if lastZoneKey then call("setSpeedZone", nil) end
    lastZoneKey, lastZoneKph, lastZoneFrom, lastZoneTo = nil, nil, nil, nil
    return
  end

  local z = chosen.z
  local mph = tonumber(z.mph)
  if not mph then return end
  local key = zoneKey(z, chosen.i)
  local kph = mph * 1.609344
  local isUpcoming = chosen ~= current
  if key == lastZoneKey and math.abs(kph - (lastZoneKph or 0)) < 0.001
      and isUpcoming == lastZoneUpcoming then return end

  -- Stella owns the warning distance.  The entry checkpoint and position are
  -- supplied so it can warn approximately 90 m before entry.
  local entry = checkpoint(track, z.from)
  local sent = call("setSpeedZone", {
    name = z.name or ("Zone " .. tostring(chosen.i)),
    limitKmh = kph,
    upcoming = isUpcoming,
    entryCheckpoint = tonumber(z.from),
    entryPosition = position(entry),
    warnDistance = 90,
  })
  if sent then
    lastZoneKey, lastZoneKph = key, kph
    lastZoneFrom, lastZoneTo = tonumber(z.from), tonumber(z.to)
    lastZoneUpcoming = isUpcoming
  end
end

local function sync()
  local s = stella()
  if not s then return end
  local state = extensions.raceManager_state
  local race = extensions.raceManager_race
  if not state or type(state.get) ~= "function" or not race or type(race.status) ~= "function" then
    return
  end

  local rmState = state.get() or {}
  local rs = race.status() or {}
  local status = tostring(rs.state or "idle")
  local active = status == "armed" or status == "running"
  local running = status == "running"
  local track = rmState.track
  local trackId = type(track) == "table" and track.id or rs.track

  if trackId ~= lastTrackId then
    lastTrackId = trackId
    lastTrackPayload = nil
    lastZoneKey, lastZoneKph, lastZoneFrom, lastZoneTo, lastZoneUpcoming = nil, nil, nil, nil, nil
  end
  if type(track) == "table" and track ~= lastTrackPayload then
    -- A full track can arrive after race.state, so do not require an ID change.
    -- Stella's public API takes the display name plus the complete checkpoint
    -- array (rather than the Race Manager wrapper table).
    call("setCourse", track.name or track.id, track.checkpoints)
    -- Preserve the full wrapper for Stella variants that expose this richer
    -- optional API; the shipped client simply ignores the absent method.
    call("setTrack", track)
    lastTrackPayload = track
  end

  if not active and lastZoneKey then
    call("setSpeedZone", nil)
    lastZoneKey, lastZoneKph, lastZoneFrom, lastZoneTo, lastZoneUpcoming = nil, nil, nil, nil, nil
  end

  if status ~= lastState then
    lastState = status
    call("setRaceState", {
      active = active,
      started = running,
      state = status,
      track = trackId,
      trackName = type(track) == "table" and (track.name or track.id) or trackId,
    })
  end

  local nextCp = tonumber(rs.next) or 1
  local done = tonumber(rs.done) or 0
  call("setProgress", nextCp, done)
  if nextCp ~= lastNext then
    lastNext = nextCp
    call("setNextCheckpoint", nextCp, checkpoint(track, nextCp))
  end
  -- `done` is server-confirmed and remains monotonic across circuit lap wraps,
  -- unlike `next`, so it is the reliable VCP notification source.
  if lastDone ~= nil and done > lastDone then
    local crossed = nextCp - 1
    local count = type(track) == "table" and type(track.checkpoints) == "table" and #track.checkpoints or 0
    if crossed < 1 and count > 0 then crossed = count end
    call("onVCPCrossed", crossed)
  end
  lastDone = done

  if type(track) == "table" and active then updateZones(track, nextCp) end
end

function M.onExtensionLoaded()
  -- Stella may be loaded after Race Manager (or not installed at all).
  -- Polling also avoids touching Race Manager's network channel handlers.
  lastTrackId, lastTrackPayload, lastState, lastNext, lastDone = nil, nil, nil, nil, nil
  netWired = false
  wireNetwork()
end

-- Stella samples ten times a second, so telling it more often than that is
-- work nobody sees. The rest of this file is as its author shipped it.
local EVERY = 0.1
local since = 0

function M.onUpdate(dt)
  since = since + (tonumber(dt) or 0)
  if since < EVERY then return end
  since = 0
  wireNetwork()
  sync()
end

function M.sendBreakdown(active)
  local net=extensions.raceManager_net
  if not net or type(net.send)~="function" then return false end
  return net.send("stella.breakdown.set", {active=active and true or false, kind="mechanical"})
end

function M.requestPass()
  local net=extensions.raceManager_net
  if not net or type(net.send)~="function" then return false end
  -- Informational only. The server applies the event-configured 200–300 m range.
  return net.send("stella.pass.request", {})
end

function M.acceptPass(requestId)
  local net=extensions.raceManager_net
  if not net or type(net.send)~="function" or requestId==nil then return false end
  return net.send("stella.pass.accept", {requestId=requestId})
end

return M