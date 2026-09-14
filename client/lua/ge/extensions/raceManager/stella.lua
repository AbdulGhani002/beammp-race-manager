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
local serverBox = nil
local mirror = nil
local mirrorTrackAsked = nil

local function stella()
  local ok, s = pcall(function() return extensions.bajaStella end)
  return ok and type(s) == "table" and s or nil
end

-- the car the unit is about: the driver's while copiloting, else your own
local function watchedVehicle()
  local ok, cop = pcall(function()
    return extensions.raceManager_copilot and extensions.raceManager_copilot.status()
  end)
  if ok and cop and cop.watching and cop.gameId and be and be.getObjectByID then
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
  -- the driver's race, twice a second while copiloting. Their course is
  -- asked for once per course, not on every mirror.
  net.on("stella.mirror", function(d)
    if type(d) ~= "table" then return end
    mirror = d
    if d.track and d.track ~= mirrorTrackAsked then
      mirrorTrackAsked = d.track
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

local function clearZone()
  if lastZoneKey then call("setSpeedZone", nil) end
  lastZoneKey, lastZoneKph, lastZoneFrom, lastZoneTo, lastZoneUpcoming = nil, nil, nil, nil, nil
end

-- a box zone on the unit, told once: again only when it is another box,
-- another limit, or ahead has become in
local function showBox(key, mph, upcoming, entryPos)
  local kph = mph * 1.609344
  if lastZoneKey == key and lastZoneUpcoming == upcoming
     and math.abs(kph - (lastZoneKph or 0)) < 0.001 then return end
  lastZoneKey, lastZoneKph, lastZoneUpcoming = key, kph, upcoming
  lastZoneFrom, lastZoneTo = nil, nil
  pushBoxZone(mph, upcoming, entryPos)
end

-- where the car the unit is about stands
local function carPosition()
  local pos
  pcall(function()
    local veh = watchedVehicle()
    if veh then pos = veh:getPosition() end
  end)
  return pos
end

-- The zone the unit is told about, in this order. First the server's word:
-- it judges the speed and hands out the penalty, so while it says the car
-- is in a box the unit says so too, whatever this side measures. That word
-- used to be taken down a tick later by the measuring below, when this
-- side could not see the box, and all that was left of a zone was the
-- beep. Then a box this side measures the car inside, or within a hundred
-- metres of, for the warning ahead. Then the gate to gate zone from the
-- course. A box driven through is spent until the car is a hundred metres
-- clear of it, so it warns again next lap round and not the moment the
-- car leaves it.
local function updateZones(track, nextCp)
  if serverBox then
    showBox(serverBox.key, serverBox.mph, false, nil)
    return
  end

  local trig = extensions.raceManager_triggers
  local pos = carPosition()
  if pos and trig and type(trig.nearestSz) == "function" then
    local box, inside, dist, face = trig.nearestSz(pos)
    local mph = box and tonumber(box.mph) or nil
    if mph then
      local key = "box:" .. tostring(box.i or box.mph)
      if inside then
        boxInsideKey = key
        showBox(key, mph, false, box.pos)
        return
      end
      if boxInsideKey == key then
        boxSpent[key] = true
        boxInsideKey = nil
      end
      dist = dist or 999
      if dist > 100 then boxSpent[key] = nil end
      if dist <= 100 and not boxSpent[key] then
        showBox(key, mph, true, face or pos)
        return
      end
    end
  end

  if not updateGateZones(track, nextCp) then clearZone() end
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

  -- told when it changes, and the first time, which is enough: the unit
  -- keeps what it was told. Told every tick it cleared itself ten times a
  -- second while idle.
  local stateKey = status .. "|" .. tostring(trackId)
  if stateKey ~= lastState then
    lastState = stateKey
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
    call("setNextCheckpoint", nextCp)
  end
  -- done is the server's count and climbs across laps, unlike next, so it
  -- is what says a gate was crossed. The gate named is the one behind next.
  if lastDone ~= nil and done > lastDone then
    local crossed = nextCp - 1
    local count = type(track) == "table" and type(track.checkpoints) == "table" and #track.checkpoints or 0
    if crossed < 1 and count > 0 then crossed = count end
    call("onVCPCrossed", crossed)
  end
  lastDone = done

  -- a race that is over takes its zones with it
  if not active then
    clearZone()
    serverBox = nil
    boxInsideKey, boxSpent = nil, {}
  end

  if not active or type(track) ~= "table" then return end
  updateZones(track, nextCp)
end

function M.onExtensionLoaded()
  lastTrackId, lastTrackPayload, lastState, lastNext, lastDone = nil, nil, nil, nil, nil
  netWired = false
  wireNetwork()
end

-- !stella in chat: a run through everything the unit can show, one thing
-- every two seconds, with a notice saying what should be on. For a unit
-- that is doubted, so the dots and the screen can be watched without
-- setting up a race. Not during a race: the race owns the unit then.
local TEST = {
  { "yellow", "Stella test 1 of 6: yellow triangle, flashing" },
  { "blue",   "Stella test 2 of 6: blue lines, flashing" },
  { "green",  "Stella test 3 of 6: green, all dots" },
  { "ahead",  "Stella test 4 of 6: speed zone ahead, 37 in yellow" },
  { "in",     "Stella test 5 of 6: in the zone, 37 in red" },
  { "over",   "Stella test 6 of 6: over the limit, red flashing" },
}
local testStep, testSince = nil, 0
local TEST_EVERY = 2.0

function M.selfTest()
  local racing = false
  pcall(function() racing = extensions.raceManager_race.isActive() end)
  if racing then
    pcall(function() extensions.raceManager_state.notice("Stella test: not during a race") end)
    return false
  end
  testStep, testSince = 0, TEST_EVERY
  return true
end

local function testTick(dt)
  if not testStep then return end
  testSince = testSince + dt
  if testSince < TEST_EVERY then return end
  testSince = 0
  testStep = testStep + 1
  local step = TEST[testStep]
  if not step then
    testStep = nil
    call("testShow", "off")
    pcall(function() extensions.raceManager_state.notice("Stella test over: everything off") end)
    return
  end
  call("testShow", step[1])
  pcall(function() extensions.raceManager_state.notice(step[2]) end)
end

local EVERY = 0.1
local since = 0

function M.onUpdate(dt)
  testTick(tonumber(dt) or 0)
  since = since + (tonumber(dt) or 0)
  if since < EVERY then return end
  since = 0
  wireNetwork()
  sync()
end

-- The server's word on a box zone, from zone.warn: on with the limit, or
-- off. Shown straight away and kept until off, whatever this side
-- measures in between. On off, the box the car is measured inside is
-- marked spent, so the measuring does not put the zone straight back.
function M.setPairZone(z)
  local mph = type(z) == "table" and tonumber(z.mph) or nil
  if mph then
    serverBox = { mph = mph, key = "server:" .. tostring(z.pair or z.i or mph) }
    showBox(serverBox.key, mph, false, nil)
    return
  end
  serverBox = nil
  if lastZoneKey and lastZoneKey:sub(1, 7) == "server:" then clearZone() end
  pcall(function()
    local trig = extensions.raceManager_triggers
    local pos = carPosition()
    if not (pos and trig and type(trig.nearestSz) == "function") then return end
    local box, inside = trig.nearestSz(pos)
    if box and inside then
      boxSpent["box:" .. tostring(box.i or box.mph)] = true
      boxInsideKey = nil
    end
  end)
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
