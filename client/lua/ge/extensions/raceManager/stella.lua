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
local boxInsideKey = nil
local boxSpent = {}
local mirror = nil

local function stella()
  local ok, s = pcall(function() return extensions.bajaStella end)
  return ok and type(s) == "table" and s or nil
end

local function watchedVehicle()
  local ok, cop = pcall(function()
    return extensions.raceManager_copilot and extensions.raceManager_copilot.status()
  end)
  if ok and cop and cop.gameId and be and be.getObjectByID then
    local obj = be:getObjectByID(cop.gameId)
    if obj then return obj end
  end
  local okp, veh = pcall(function() return be:getPlayerVehicle(0) end)
  return okp and veh or nil
end

local function call(name, ...)
  local s = stella()
  if not s or type(s[name]) ~= "function" then return false end
  return pcall(s[name], ...)
end

local function isBoxKey(key)
  return type(key) == "string" and key:sub(1, 4) == "box:"
end

local function wireNetwork()
  if netWired then return end
  local net = extensions.raceManager_net
  local s = stella()
  if not net or type(net.on) ~= "function" or not s then return end
  net.on("stella.pass.alert", function(d) call("onRaceManagerPassAlert", d) end)
  net.on("stella.pass.status", function(d)
    call("onRaceManagerPassStatus", d)
    if type(d) == "table" and tostring(d.state or "") == "cancelled" then
      local why = tostring(d.reason or "")
      local msg = "No pass: nobody close enough ahead"
      if why == "not_racing" then msg = "No pass: start the race first" end
      pcall(function() extensions.raceManager_state.notice(msg) end)
    end
  end)
  net.on("stella.pass.go", function(d) call("onRaceManagerPassGo", d) end)
  net.on("stella.breakdown.state", function(d) call("onRaceManagerBreakdownState", d) end)
  net.on("stella.breakdown.alert", function(d) call("onRaceManagerBreakdownAlert", d) end)
  net.on("stella.mirror", function(d)
    if type(d) ~= "table" then return end
    mirror = d
    if d.track then
      pcall(function() net.send("track.get", { id = d.track }) end)
    end
  end)
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

-- Original gate-to-gate path. Returns true if a gate zone owns Stella.
local function updateGateZones(track, nextCp)
  local zones = type(track) == "table" and track.zones
  if type(zones) ~= "table" or #zones == 0 then
    return false
  end

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
    return false
  end

  local z = chosen.z
  local mph = tonumber(z.mph)
  if not mph then return false end
  local key = zoneKey(z, chosen.i)
  local kph = mph * 1.609344
  local isUpcoming = chosen ~= current
  if key == lastZoneKey and math.abs(kph - (lastZoneKph or 0)) < 0.001
      and isUpcoming == lastZoneUpcoming then
    return true
  end

  local entry = checkpoint(track, z.from)
  local sent = call("setSpeedZone", {
    name = z.name or ("Zone " .. tostring(chosen.i)),
    limitKmh = kph,
    limitMph = mph,
    upcoming = isUpcoming,
    entryCheckpoint = tonumber(z.from),
    entryPosition = position(entry),
    warnDistance = 100,
  })
  if sent then
    lastZoneKey, lastZoneKph = key, kph
    lastZoneFrom, lastZoneTo = tonumber(z.from), tonumber(z.to)
    lastZoneUpcoming = isUpcoming
  end
  return true
end

local function pushBoxZone(mph, upcoming, entryPos)
  call("setSpeedZone", {
    name = "Speed zone",
    limitKmh = mph * 1.609344,
    limitMph = mph,
    upcoming = upcoming and true or false,
    entryPosition = entryPos,
    warnDistance = 100,
  })
end

local function updateBoxZones()
  local trig = extensions.raceManager_triggers
  if not (trig and type(trig.nearestSz) == "function") then return end
  local pos
  local veh = watchedVehicle()
  if veh then
    local ok2, pr = pcall(function() return veh:getPosition() end)
    if ok2 then pos = pr end
  end
  if not pos then return end

  local box, inside, dist, face = trig.nearestSz(pos)
  if not (box and tonumber(box.mph)) then
    if isBoxKey(lastZoneKey) then
      call("setSpeedZone", nil)
      lastZoneKey, lastZoneKph, lastZoneUpcoming = nil, nil, nil
      boxInsideKey = nil
    end
    return
  end

  local key = "box:" .. tostring(box.i or box.mph)
  if boxSpent[key] and not inside then
    if isBoxKey(lastZoneKey) then
      call("setSpeedZone", nil)
      lastZoneKey, lastZoneKph, lastZoneUpcoming = nil, nil, nil
    end
    boxInsideKey = nil
    return
  end

  if inside then
    boxInsideKey = key
    if lastZoneKey ~= key or lastZoneUpcoming then
      lastZoneKey, lastZoneKph, lastZoneUpcoming = key, box.mph * 1.609344, false
      pushBoxZone(box.mph, false, box.pos)
    end
    return
  end

  if boxInsideKey == key then
    boxSpent[key] = true
    boxInsideKey = nil
    call("setSpeedZone", nil)
    lastZoneKey, lastZoneKph, lastZoneUpcoming = nil, nil, nil
    return
  end

  if (dist or 999) <= 100 then
    if lastZoneKey ~= key or not lastZoneUpcoming then
      lastZoneKey, lastZoneKph, lastZoneUpcoming = key, box.mph * 1.609344, true
      pushBoxZone(box.mph, true, face or pos)
    end
    return
  end

  if isBoxKey(lastZoneKey) then
    call("setSpeedZone", nil)
    lastZoneKey, lastZoneKph, lastZoneUpcoming = nil, nil, nil
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
  local watching = false
  pcall(function()
    local c = extensions.raceManager_copilot.status()
    watching = c and c.watching and true or false
  end)
  if watching and type(mirror) == "table" and (mirror.state == "armed" or mirror.state == "running" or mirror.state == "finished") then
    rs = {
      state = mirror.state,
      track = mirror.track,
      next = mirror.next,
      done = mirror.done,
      lap = mirror.lap,
      gates = mirror.gates,
    }
  end
  local status = tostring(rs.state or "idle")
  local active = status == "armed" or status == "running"
  local running = status == "running"
  local track = rmState.track
  local trackId = type(track) == "table" and track.id or rs.track

  if trackId ~= lastTrackId then
    lastTrackId = trackId
    lastTrackPayload = nil
    lastZoneKey, lastZoneKph, lastZoneFrom, lastZoneTo, lastZoneUpcoming = nil, nil, nil, nil, nil
    boxInsideKey, boxSpent = nil, {}
  end
  if type(track) == "table" and track ~= lastTrackPayload then
    call("setCourse", track.name or track.id, track.checkpoints)
    call("setTrack", track)
    lastTrackPayload = track
  end

  if not active and lastZoneKey then
    call("setSpeedZone", nil)
    lastZoneKey, lastZoneKph, lastZoneFrom, lastZoneTo, lastZoneUpcoming = nil, nil, nil, nil, nil
    boxInsideKey, boxSpent = nil, {}
  end

  -- Always push race state so Stella LCD leaves idle / race modes even if a
  -- client joined mid-session or missed a single status transition.
  if status ~= lastState or active ~= (lastState == "armed" or lastState == "running") then
    lastState = status
  end
  call("setRaceState", {
    active = active,
    started = running,
    state = status,
    track = trackId,
    trackName = type(track) == "table" and (track.name or track.id) or trackId,
    currentCheckpoint = tonumber(rs.next) or 1,
  })

  local nextCp = tonumber(rs.next) or 1
  local done = tonumber(rs.done) or 0
  call("setProgress", nextCp, done)
  if nextCp ~= lastNext then
    lastNext = nextCp
    call("setNextCheckpoint", nextCp)
  end
  if lastDone ~= nil and done > lastDone then
    local crossed = math.max(1, done)
    call("onVCPCrossed", crossed)
  end
  lastDone = done

  -- Race quit / finish must clear zones immediately for Stella warnings
  if not active then
    if lastZoneKey then
      call("setSpeedZone", nil)
      lastZoneKey, lastZoneKph, lastZoneFrom, lastZoneTo, lastZoneUpcoming = nil, nil, nil, nil, nil
      boxInsideKey, boxSpent = nil, {}
    end
  end

  if not active or type(track) ~= "table" then return end

  -- Same Stella call for both. A box you are in or within 100 m of is the
  -- zone you are on; otherwise the gate-to-gate zone is shown as original.
  local nearBox = false
  local trig = extensions.raceManager_triggers
  local pos
  pcall(function()
    local veh = watchedVehicle()
    if veh then pos = veh:getPosition() end
  end)
  if pos and trig and type(trig.nearestSz) == "function" then
    local box, inside, dist = trig.nearestSz(pos)
    local key = box and ("box:" .. tostring(box.i or box.mph)) or nil
    if box and tonumber(box.mph) and not (key and boxSpent[key] and not inside) then
      if inside or (dist or 999) <= 100 then nearBox = true end
    end
  end
  if nearBox then
    updateBoxZones()
    return
  end
  if not updateGateZones(track, nextCp) then
    if lastZoneKey then
      call("setSpeedZone", nil)
      lastZoneKey, lastZoneKph, lastZoneFrom, lastZoneTo, lastZoneUpcoming = nil, nil, nil, nil, nil
    end
  end
end

function M.onExtensionLoaded()
  lastTrackId, lastTrackPayload, lastState, lastNext, lastDone = nil, nil, nil, nil, nil
  netWired = false
  wireNetwork()
end

local EVERY = 0.1
local since = 0

function M.onUpdate(dt)
  since = since + (tonumber(dt) or 0)
  if since < EVERY then return end
  since = 0
  wireNetwork()
  sync()
end

-- Limit / penalty path from the server. Must never clear a gate zone.
function M.setPairZone(z)
  if lastZoneKey and not isBoxKey(lastZoneKey) then
    return
  end
  if not z or not tonumber(z.mph) then
    if isBoxKey(lastZoneKey) then
      call("setSpeedZone", nil)
      lastZoneKey, lastZoneKph, lastZoneUpcoming = nil, nil, nil
    end
    boxInsideKey = nil
    return
  end
  local key = "box:" .. tostring(z.i or z.pair or z.mph)
  lastZoneKey, lastZoneKph, lastZoneUpcoming = key, z.mph * 1.609344, false
  boxInsideKey = key
  pushBoxZone(z.mph, false, nil)
end

function M.sendBreakdown(active)
  local net = extensions.raceManager_net
  if not net or type(net.send) ~= "function" then return false end
  return net.send("stella.breakdown.set", { active = active and true or false, kind = "mechanical" })
end

function M.requestPass()
  local net = extensions.raceManager_net
  if not net or type(net.send) ~= "function" then return false end
  return net.send("stella.pass.request", {})
end

function M.acceptPass(requestId)
  local net = extensions.raceManager_net
  if not net or type(net.send) ~= "function" then return false end
  return net.send("stella.pass.accept", { requestId = requestId })
end

return M
