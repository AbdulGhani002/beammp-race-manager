-- The bridge between Race Manager and the Stella unit. The unit owns the
-- display; this tells it what the race is doing and passes its buttons to
-- the server. Nothing about a pass, a breakdown or a penalty is worked out
-- here: the server judges, the unit shows what it is told.
--
-- A copilot's unit was made to mirror the driver's for a while, and that
-- is where the unit stopped working for him. It is out again: the unit is
-- always about your own car and your own race.
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

-- the server's word on a box zone, kept until the server takes it back
local serverBox = nil

local function stella()
  local ok, s = pcall(function() return extensions.raceManager_stellaUnit end)
  return ok and type(s) == "table" and s or nil
end

-- a Stella mod of its own in the mods folder is not the unit Race Manager
-- talks to any more; said once so its owner knows why it sits there dead
local strangerSaid = false
local function noticeStranger()
  if strangerSaid then return end
  local other = false
  pcall(function() other = type(extensions.bajaStella) == "table" end)
  if not other then return end
  strangerSaid = true
  pcall(function()
    extensions.raceManager_state.notice("Another Stella mod is installed. Race Manager uses its own; remove the other from your mods folder.")
  end)
  if type(log) == "function" then log("W", "raceManager", "a standalone Stella mod is loaded beside Race Manager's unit") end
end

local function call(name, ...)
  local s = stella()
  if not s or type(s[name]) ~= "function" then return false end
  return pcall(s[name], ...)
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

local function clearZone()
  if lastZoneKey then call("setSpeedZone", nil) end
  lastZoneKey, lastZoneKph, lastZoneFrom, lastZoneTo, lastZoneUpcoming = nil, nil, nil, nil, nil
end

-- A zone is current while its gates hold the gate you are heading for, and
-- ahead while its first gate is still to come. The unit is told once per
-- zone and once more when ahead becomes in. Returns true when a zone is up.
local function updateGateZones(track, nextCp)
  local zones = type(track) == "table" and track.zones
  if type(zones) ~= "table" or #zones == 0 then return false end

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
  if not chosen then return false end

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

  -- the unit owns the warning distance: it is given the entry gate and
  -- where it stands, and warns a hundred metres before it, as he asked
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

-- a box zone on the unit, told once: again only when it is another box or
-- another limit
local function showBox(key, mph)
  local kph = mph * 1.609344
  if lastZoneKey == key and math.abs(kph - (lastZoneKph or 0)) < 0.001 then return end
  lastZoneKey, lastZoneKph, lastZoneUpcoming = key, kph, false
  lastZoneFrom, lastZoneTo = nil, nil
  call("setSpeedZone", {
    name = "Speed zone",
    limitKmh = kph,
    limitMph = mph,
    upcoming = false,
    warnDistance = 100,
  })
end

-- The server's word first: it judges the speed and hands out the penalty,
-- so while it says the car is in a box the unit says so too. Then the gate
-- to gate zone from the course. Nothing is measured on this side any more;
-- measuring here took the server's zone down a tick after it was shown.
local function updateZones(track, nextCp)
  if serverBox then
    showBox(serverBox.key, serverBox.mph)
    return
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
    call("setCourse", track.name or track.id, track.checkpoints)
    call("setTrack", track)
    lastTrackPayload = track
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
    return
  end
  if type(track) ~= "table" then return end
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
-- setting up a race. Not during a race: the race owns the unit then. At
-- the end it says how fast the unit was ticking and how many of its lights
-- the screen answered, so a dead unit, a dead screen and a dead link
-- between them each read differently.
local TEST = {
  { "yellow", "Stella test 1 of 6: yellow triangle, flashing" },
  { "blue",   "Stella test 2 of 6: blue lines, flashing" },
  { "green",  "Stella test 3 of 6: green, all dots" },
  { "ahead",  "Stella test 4 of 6: speed zone ahead, 37 in yellow" },
  { "in",     "Stella test 5 of 6: in the zone, 37 in red" },
  { "over",   "Stella test 6 of 6: over the limit, red flashing" },
}
local TEST_EVERY = 2.0
local testStep, testSince, testElapsed = nil, 0, 0
local ticksAt = 0
local screenAnswers = 0

function M.screenSaw() screenAnswers = screenAnswers + 1 end

local function unitTicks()
  local s = stella()
  local ok, n = pcall(function() return s and type(s.ticks) == "function" and s.ticks() or 0 end)
  return ok and tonumber(n) or 0
end

function M.selfTest()
  local racing = false
  pcall(function() racing = extensions.raceManager_race.isActive() end)
  if racing then
    pcall(function() extensions.raceManager_state.notice("Stella test: not during a race") end)
    return false
  end
  local s = stella()
  if not s then
    pcall(function() extensions.raceManager_state.notice("Stella test: the unit is not loaded. Rejoin the server.") end)
    return false
  end
  pcall(function()
    extensions.raceManager_state.notice("Stella test: unit " .. tostring(s.VERSION or "older than 0.7.11") .. ". Watch the dots and the screen.")
  end)
  screenAnswers = 0
  ticksAt = unitTicks()
  testStep, testSince, testElapsed = 0, TEST_EVERY, 0
  return true
end

local function testTick(dt)
  if not testStep then return end
  testSince = testSince + dt
  testElapsed = testElapsed + dt
  if testSince < TEST_EVERY then return end
  testSince = 0
  testStep = testStep + 1
  local step = TEST[testStep]
  if not step then
    testStep = nil
    call("testShow", "off")
    local seen = screenAnswers
    local rate = testElapsed > 0 and math.floor((unitTicks() - ticksAt) / testElapsed + 0.5) or 0
    pcall(function()
      local head = ("Stella test over: unit ticking %d a second, screen answered %d of %d."):format(rate, seen, #TEST)
      if rate == 0 then
        extensions.raceManager_state.notice(head .. " The unit is not running. Rejoin the server and send Marx the console log.")
      elseif seen == 0 then
        extensions.raceManager_state.notice(head .. " The unit works, the screen is not receiving. Type !resetui, or rejoin.")
      elseif seen < #TEST then
        extensions.raceManager_state.notice(head .. " Some lights did not reach the screen. Type !resetui.")
      else
        extensions.raceManager_state.notice(head .. " Everything reached the screen. If you saw nothing, the unit is hidden: Options, Dash, Stella on.")
      end
    end)
    return
  end
  call("testShow", step[1])
  pcall(function() extensions.raceManager_state.notice(step[2]) end)
end

local EVERY = 0.1
local since = 0

function M.onUpdate(dt)
  dt = tonumber(dt) or 0
  testTick(dt)
  since = since + dt
  if since < EVERY then return end
  since = 0
  wireNetwork()
  noticeStranger()
  sync()
end

-- The server's word on a box zone, from zone.warn: on with the limit, or
-- off. Shown straight away and kept until off.
function M.setPairZone(z)
  local mph = type(z) == "table" and tonumber(z.mph) or nil
  if mph then
    serverBox = { mph = mph, key = "server:" .. tostring(z.pair or z.i or mph) }
    showBox(serverBox.key, mph)
    return
  end
  serverBox = nil
  clearZone()
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
