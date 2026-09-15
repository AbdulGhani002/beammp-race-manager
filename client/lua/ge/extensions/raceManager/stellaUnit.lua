-- Race Manager Stella Instrument (isolated) v2.1
-- UI is driven primarily by uiPoll() so LED / zone / keys do not depend on
-- guihooks reaching a nested Angular directive (that path was unreliable).
local M = {}
M.VERSION = "2.1-rmsi"

local cfg = {
  tick = 0.05,
  zoneWarnDistance = 250,
  greenSecs = 3.0,
  immediateRange = 8,
  rearApproachRange = 150,
  proximityClear = 175,
  proximityCooldown = 5,
}

local race, course = {}, {}
local nextCheckpoint, validatedCheckpoints = 1, 0
local zone, proximity, proximityLast = nil, nil, {}
local odo, lastPos, acc, clock = 0, nil, 0, 0
local led = { color = "off", flash = false, pattern = "none" }
local greenUntil = 0
local blueFlag = { state = "none", playerName = "" }
local breakdown, hazardAhead = false, nil
local lastExceeding, testOver = false, false
local lastHdg, lastSpd, lastDist = 0, 0, 0
local pendingSounds = {}  -- { "advance", "exceed", "vcp", "beep", ... }

local function num(v, d) return tonumber(v) or d or 0 end
local function point(cp)
  if not cp then return nil end
  local p = cp.pos or cp.position or cp
  if type(p) ~= "table" then return nil end
  return { x = num(p.x or p[1]), y = num(p.y or p[2]), z = num(p.z or p[3]) }
end

local function queueSound(name)
  pendingSounds[#pendingSounds + 1] = name
  if #pendingSounds > 12 then table.remove(pendingSounds, 1) end
  -- Engine-side play so the browser autoplay policy cannot block it
  pcall(function()
    local path = "/ui/modules/apps/RaceManagerStella/sounds/"
    local file
    if name == "advance" or name == "enter" then
      file = path .. "speed_zone_entry.mp3"
    elseif name == "exceed" then
      file = path .. "speed_zone_exceed.mp3"
    elseif name == "beep" then
      file = path .. "beep_corto.mp3"
    elseif name == "vcp" then
      file = "/ui/modules/apps/RaceManagerStella/vcp_sound.mp3"
    end
    if file and Engine and Engine.Audio and Engine.Audio.playOnce then
      Engine.Audio.playOnce("AudioGui", file)
    end
  end)
end

function M.drainSounds()
  local out = pendingSounds
  pendingSounds = {}
  return out
end

local function zoneMph(z)
  if type(z) ~= "table" then return 0 end
  local mph = tonumber(z.limitMph)
  if not mph then mph = num(z.limitKmh or z.speedLimitKmh) * 0.621371 end
  return math.floor(mph + 0.5)
end

local function limitPattern(z) return "limit:" .. tostring(zoneMph(z)) end

local function zoneIdentity(z)
  if type(z) ~= "table" then return "" end
  return table.concat({
    tostring(z.id or z.name or ""),
    tostring(z.from or z.entryCheckpoint or ""),
    tostring(z.to or ""),
    tostring(z.limitKmh or z.speedLimitKmh or ""),
  }, ":")
end

local function setLed(color, flash, pattern)
  led = { color = color or "off", flash = not not flash, pattern = pattern or "none" }
end

local function restoreLed()
  if greenUntil > 0 and clock < greenUntil then
    setLed("green", false, "all")
    return
  end
  if greenUntil > 0 then greenUntil = 0 end

  if hazardAhead then
    setLed("red", true, "triangle")
  elseif breakdown then
    setLed("yellow", true, "triangle")
  elseif blueFlag.state == "incoming" or blueFlag.state == "requested" or blueFlag.state == "accepted" then
    setLed("blue", true, "lines")
  elseif blueFlag.state == "delivered" then
    setLed("green", true, "lines")
  elseif blueFlag.state == "go" then
    setLed("green", true, "all")
  elseif proximity then
    setLed("yellow", true, "triangle")
  elseif zone and zone.upcoming then
    setLed("yellow", true, limitPattern(zone))
  elseif zone and not zone.upcoming then
    setLed("red", lastExceeding, limitPattern(zone))
  else
    setLed("off", false, "none")
  end
end

local function bridgeCall(name, ...)
  local ok, bridge = pcall(function() return extensions.raceManager_stella end)
  if not ok or type(bridge) ~= "table" or type(bridge[name]) ~= "function" then return false end
  local called, result = pcall(bridge[name], ...)
  return called and result ~= false
end

local function vehicle()
  return be and be:getPlayerVehicle(0) or nil
end

local function speedAndHeading(v)
  local vel, fwd = v:getVelocity(), v:getDirectionVector()
  local speed = vel and vel:length() * 3.6 or 0
  local heading = fwd and math.deg(math.atan2(fwd.x, fwd.y)) or 0
  if heading < 0 then heading = heading + 360 end
  return speed, heading, fwd
end

local function checkpointData(pos)
  local cp = course[nextCheckpoint]
  if not cp then return 0, 0, "", 0, false end
  local p = point(cp)
  if not p then return 0, 0, cp.name or "", #course, false end
  local dx, dy = p.x - pos.x, p.y - pos.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local bearing = math.deg(math.atan2(dx, dy))
  if bearing < 0 then bearing = bearing + 360 end
  return dist, bearing, cp.name or ("VCP" .. nextCheckpoint), #course, dist < 500
end

------------------------------------------------------------------ public

function M.setRaceState(data)
  local prev = not not race.active
  race = type(data) == "table" and data or {}
  if race.active == nil then race.active = race.raceActive end
  if race.started == nil then race.started = race.raceStarted end
  race.trackName = race.trackName or race.currentTrack or ""
  if race.checkpoints and #course == 0 then course = race.checkpoints end
  if not race.active then odo = 0; lastPos = nil end
  if prev and not race.active then
    blueFlag = { state = "none", playerName = "" }
    zone = nil
    lastExceeding = false
    greenUntil = 0
    restoreLed()
  end
end

function M.setCourse(track, checkpoints)
  if type(track) == "table" and checkpoints == nil then
    checkpoints = track.checkpoints
    track = track.name
  end
  race.trackName = track or race.trackName or ""
  course = type(checkpoints) == "table" and checkpoints or {}
end

function M.setTrack(track)
  if type(track) == "table" then
    race.trackName = track.name or track.id or race.trackName
    if type(track.checkpoints) == "table" then course = track.checkpoints end
  end
end

function M.setNextCheckpoint(index)
  nextCheckpoint = math.max(1, num(index, 1))
end

function M.setProgress(index, done)
  nextCheckpoint = math.max(1, num(index, nextCheckpoint))
  validatedCheckpoints = math.max(0, num(done, validatedCheckpoints))
end

function M.onVCPCrossed(index)
  greenUntil = clock + cfg.greenSecs
  setLed("green", false, "all")
  queueSound("vcp")
end

function M.setSpeedZone(z)
  if z == nil then
    if zone and not zone.upcoming then queueSound("vcp") end
    zone = nil
    lastExceeding = false
    testOver = false
    restoreLed()
    return
  end
  local wasActive = zone ~= nil and not zone.upcoming
  local oldKey = zoneIdentity(zone)
  local prevWarned = zone and zone.advanceWarned
  local prevUpcoming = zone and zone.upcoming
  local prevActive = zone and not zone.upcoming
  -- keep faceDist / entryPosition from the new payload
  zone = z
  local isActive = not z.upcoming
  local newKey = zoneIdentity(z)
  if prevWarned and prevUpcoming and z.upcoming and oldKey == newKey then
    zone.advanceWarned = true
  elseif z.upcoming and not prevUpcoming then
    -- just entered the 200 m shell around a green box: warn once
    zone.advanceWarned = false
  elseif isActive and not prevActive then
    zone.advanceWarned = true
  else
    zone.advanceWarned = zone.advanceWarned or false
  end
  -- entering the box volume: entry tone
  if isActive and not prevActive then
    queueSound("enter")
    zone.advanceWarned = true
  end
  if wasActive and isActive and oldKey ~= newKey then
    lastExceeding = false
  end
  restoreLed()
end

function M.onProximityAlert(data)
  proximity = data or {}
  setLed("yellow", true, "triangle")
end

function M.clearProximityAlert()
  proximity = nil
  restoreLed()
end

function M.requestState() end

function M.toggleMechanicalBreakdown()
  breakdown = not breakdown
  bridgeCall("sendBreakdown", breakdown)
  restoreLed()
end

function M.requestMechanicalBreakdown()
  if not breakdown then M.toggleMechanicalBreakdown() end
end

function M.acknowledgeBlueFlag()
  if blueFlag.state == "incoming" or blueFlag.state == "delivered" then
    blueFlag.state = "accepted"
    bridgeCall("acceptPass")
    restoreLed()
  end
end

function M.requestBlueFlag()
  bridgeCall("requestPass")
end

function M.onRaceManagerPassAlert(d)
  blueFlag = {
    state = "incoming",
    playerName = type(d) == "table" and (d.fromName or d.name or "") or "",
  }
  queueSound("beep")
  restoreLed()
end

function M.onRaceManagerPassStatus(d)
  if type(d) ~= "table" then return end
  blueFlag.state = tostring(d.state or blueFlag.state)
  if d.name or d.fromName then blueFlag.playerName = d.name or d.fromName end
  restoreLed()
end

function M.onRaceManagerPassGo(d)
  blueFlag.state = "go"
  queueSound("beep")
  restoreLed()
end

function M.onRaceManagerBreakdownState(d)
  breakdown = type(d) == "table" and d.active and true or false
  restoreLed()
end

function M.onRaceManagerBreakdownAlert(d)
  if type(d) == "table" and d.active == false then
    hazardAhead = nil
  else
    hazardAhead = d or {}
    queueSound("beep")
  end
  restoreLed()
end

function M.blueFlagState() return blueFlag.state end

function M.getSnapshot()
  local zoneActive = zone ~= nil and not zone.upcoming
  local zoneWarn = zone ~= nil and zone.upcoming == true
  local limit = zone and num(zone.limitKmh or zone.speedLimitKmh) or 0
  return {
    heading = lastHdg,
    speed = lastSpd,
    distToVCPm = math.floor(lastDist),
    distToVCPkm = lastDist / 1000,
    vcpName = course[nextCheckpoint] and (course[nextCheckpoint].name or ("VCP" .. nextCheckpoint)) or "",
    vcpIndex = nextCheckpoint,
    validatedVCPs = validatedCheckpoints,
    totalVCPs = #course,
    totalDistKm = odo / 1000,
    raceActive = not not race.active,
    raceStarted = not not race.started,
    isApproaching = lastDist < 500 and lastDist > 0,
    isStopped = lastSpd < 1.5,
    breakdownActive = breakdown,
    hazardAhead = hazardAhead ~= nil,
    blueFlagState = blueFlag.state,
    blueFlagPlayer = blueFlag.playerName,
    ledColor = led.color,
    ledFlash = led.flash,
    ledPattern = led.pattern,
    speedZoneActive = zoneActive,
    speedZoneWarning = zoneWarn or (zoneActive and not lastExceeding),
    speedZoneName = zone and zone.name or "",
    speedZoneLimit = limit,
    speedZoneLimitMph = zone and zoneMph(zone) or 0,
    speedExceeding = lastExceeding,
    greenLeft = math.max(0, greenUntil - clock),
  }
end

-- Called from the UI every ~100ms. Returns JSON so bngApi always gets a string.
function M.uiPoll()
  local keys = {}
  pcall(function()
    local k = extensions.raceManager_keys
    if k and k.pull then
      for _ = 1, 8 do
        local a = k.pull()
        if not a then break end
        keys[#keys + 1] = a
      end
    end
  end)
  local sounds = M.drainSounds()
  local snap = M.getSnapshot()
  snap.keys = keys
  snap.sounds = sounds
  -- Prefer jsonEncode when present (BeamNG)
  local ok, encoded = pcall(function()
    if jsonEncode then return jsonEncode(snap) end
    if json and json.encode then return json.encode(snap) end
    return nil
  end)
  if ok and type(encoded) == "string" then return encoded end
  -- minimal fallback
  return string.format(
    '{"ledColor":%q,"ledFlash":%s,"ledPattern":%q,"speedZoneActive":%s,"speedZoneWarning":%s,"speedExceeding":%s,"speedZoneLimitMph":%s,"heading":%d,"speed":%d,"raceActive":%s,"greenLeft":%.2f,"keys":[],"sounds":[]}',
    tostring(snap.ledColor or "off"),
    snap.ledFlash and "true" or "false",
    tostring(snap.ledPattern or "none"),
    snap.speedZoneActive and "true" or "false",
    snap.speedZoneWarning and "true" or "false",
    snap.speedExceeding and "true" or "false",
    tostring(snap.speedZoneLimitMph or 0),
    snap.heading or 0,
    snap.speed or 0,
    snap.raceActive and "true" or "false",
    snap.greenLeft or 0
  )
end

local function detectProximity(v, pos, fwd, playerSpeed)
  if not be or not be.getObjectCount then return end
  local found
  local n = be:getObjectCount()
  for i = 0, n - 1 do
    local ov = be:getObject(i)
    if ov and ov.getID and ov:getID() ~= v:getID() then
      local op = ov:getPosition()
      if op then
        local dx, dy = op.x - pos.x, op.y - pos.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < cfg.immediateRange then
          found = { kind = "nearby", vehicleId = ov:getID(), distance = d }
          break
        elseif d < cfg.rearApproachRange and playerSpeed > 5 then
          if (fwd.x * dx + fwd.y * dy) < 0 then
            found = { kind = "rearApproach", vehicleId = ov:getID(), distance = d }
          end
        end
      end
    end
  end
  if found then
    if not proximity or proximity.vehicleId ~= found.vehicleId
        or clock - (proximityLast[found.vehicleId] or -1e9) >= cfg.proximityCooldown then
      proximityLast[found.vehicleId] = clock
      M.onProximityAlert(found)
    end
  elseif proximity then
    local ov = proximity.vehicleId and be:getObjectByID(proximity.vehicleId)
    local op = ov and ov:getPosition()
    if not op then
      M.clearProximityAlert()
    else
      local d = math.sqrt((op.x - pos.x)^2 + (op.y - pos.y)^2)
      if d > cfg.proximityClear then M.clearProximityAlert() end
    end
  end
end

local function tickUnit(dt)
  dt = num(dt, 0)
  clock = clock + dt

  -- expire green every frame (not only on tick boundary)
  if greenUntil > 0 and clock >= greenUntil then
    greenUntil = 0
    restoreLed()
  end

  acc = acc + dt
  if acc < cfg.tick then return end
  acc = 0

  local v = vehicle()
  if not v then return end
  local pos = v:getPosition()
  if not pos then return end
  local speed, heading, fwd = speedAndHeading(v)
  fwd = fwd or { x = 0, y = 1, z = 0 }
  lastSpd, lastHdg = math.floor(speed), math.floor(heading)

  if lastPos and race.active and race.started then
    local dx, dy, dz = pos.x - lastPos.x, pos.y - lastPos.y, pos.z - lastPos.z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d < 50 then odo = odo + d end
  end
  lastPos = { x = pos.x, y = pos.y, z = pos.z }

  local dist, bearing = checkpointData(pos)
  lastDist = dist
  pcall(detectProximity, v, pos, fwd, speed)

  -- Zone / green-box proximity warning sound (once per approach)
  -- For SZ boxes, faceDist is metres to the nearest face (outside the volume).
  -- Active limit is only when zone.upcoming == false (exactly inside the box).
  if zone and zone.upcoming then
    local warnDist = num(zone.warnDistance, cfg.zoneWarnDistance)
    local ed = tonumber(zone.faceDist)
    if ed == nil then
      local ep = point(zone.entryPosition)
      if not ep and zone.entryCheckpoint then
        ep = point(course[num(zone.entryCheckpoint)])
      end
      ed = ep and math.sqrt((ep.x - pos.x)^2 + (ep.y - pos.y)^2) or 0
      if not ep then ed = 0 end
    end
    if ed <= warnDist and not zone.advanceWarned then
      zone.advanceWarned = true
      queueSound("advance")
    end
  end

  local zoneActive = zone ~= nil and not zone.upcoming
  local limit = zone and num(zone.limitKmh or zone.speedLimitKmh) or 0
  local exceeding = zoneActive and (testOver or (limit > 0 and speed > limit)) or false
  if exceeding and not lastExceeding then
    queueSound("exceed")
  end
  lastExceeding = exceeding

  restoreLed()
end

function M.testShow(what)
  local limit = { name = "Test zone", limitKmh = 37 * 1.609344, limitMph = 37, warnDistance = 1e9 }
  if what == "yellow" then setLed("yellow", true, "triangle")
  elseif what == "green" then
    greenUntil = clock + cfg.greenSecs
    setLed("green", false, "all")
  elseif what == "ahead" then
    limit.upcoming = true
    M.setSpeedZone(limit)
  elseif what == "in" then
    testOver = false
    limit.upcoming = false
    M.setSpeedZone(limit)
  elseif what == "over" then
    testOver = true
  else
    testOver = false
    M.setSpeedZone(nil)
    greenUntil = 0
    restoreLed()
  end
end

function M.onUpdate(dt)
  pcall(tickUnit, dt)
end

function M.onExtensionLoaded()
  greenUntil = 0
  setLed("off", false, "none")
  for _, rival in ipairs({ "bajaStella", "BajaStella", "baja_stella" }) do
    pcall(function()
      if extensions[rival] then extensions.unload(rival) end
    end)
  end
end

return M
