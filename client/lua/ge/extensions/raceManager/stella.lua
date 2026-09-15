-- The bridge between Race Manager and the Stella unit. The unit owns the
-- display; this tells it what the race is doing and passes its buttons to
-- the server. Nothing about a pass, a breakdown or a penalty is worked out
-- here: the server judges, the unit shows what it is told.
--
-- Zones, the way he set them out: a zone of either kind, gate to gate or a
-- box, warns two hundred metres out, is on while the car is in it, and once
-- the car leaves it nothing warns for five seconds, then any zone near by
-- can warn again. A box is measured on this side, by the same poll that
-- tells the server the car is in it, so the unit and the server never
-- disagree about a box: the server's own word on a box is not shown.
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

local WARN_M = 200
local QUIET_SECS = 5
local quietUntil = 0
local clock = 0

local function stella()
  local ok, s = pcall(function() return extensions.raceManager_stellaUnit end)
  return ok and type(s) == "table" and s or nil
end

-- a Stella mod of its own in the mods folder is not the unit Race Manager
-- talks to any more; said once so its owner knows why it sits there dead.
-- Looked for every ten seconds, and only looked for: asking the extension
-- table for it by name made the game try to load one and log that it
-- could not, ten times a second.
local function extensionLoaded(name)
  local ok, is = pcall(function()
    if type(extensions.isExtensionLoaded) == "function" then return extensions.isExtensionLoaded(name) end
    return rawget(extensions, name) ~= nil
  end)
  return ok and is == true
end

local strangerSaid = false
local strangerSince = 10
local function noticeStranger(dt)
  if strangerSaid then return end
  strangerSince = strangerSince + (tonumber(dt) or 0)
  if strangerSince < 10 then return end
  strangerSince = 0
  if not extensionLoaded("bajaStella") then return end
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

-- Take the zone off the unit. Leaving a zone the car was in starts the
-- quiet time; a warning that stops because the car drove away does not.
local function clearZone()
  if lastZoneKey then
    if lastZoneUpcoming == false then quietUntil = clock + QUIET_SECS end
    call("setSpeedZone", nil)
  end
  lastZoneKey, lastZoneKph, lastZoneFrom, lastZoneTo, lastZoneUpcoming = nil, nil, nil, nil, nil
end

-- the gate zone the car is in, and the next one ahead of it. A zone is
-- current while its gates hold the gate the car is heading for.
local function gateZonesAt(track, nextCp)
  local zones = type(track) == "table" and track.zones
  if type(zones) ~= "table" or #zones == 0 then return nil, nil end
  local current, upcoming, upcomingFrom = nil, nil, nil
  for i, z in ipairs(zones) do
    if type(z) == "table" then
      local from, to = tonumber(z.from), tonumber(z.to)
      if from and to and tonumber(z.mph) then
        if nextCp > from and nextCp <= to then
          current = { z = z, i = i }
        elseif from >= nextCp and (not upcomingFrom or from < upcomingFrom) then
          upcoming, upcomingFrom = { z = z, i = i }, from
        end
      end
    end
  end
  return current, upcoming
end

-- a gate zone on the unit, told once, and once more when ahead becomes in.
-- The unit is given the entry gate and where it stands, and warns when the
-- car is within the warning distance of it.
local function showGate(track, chosen, isUpcoming)
  local z = chosen.z
  local mph = tonumber(z.mph)
  local key = zoneKey(z, chosen.i)
  local kph = mph * 1.609344
  if key == lastZoneKey and math.abs(kph - (lastZoneKph or 0)) < 0.001
      and isUpcoming == lastZoneUpcoming then
    return
  end
  local entry = checkpoint(track, z.from)
  local sent = call("setSpeedZone", {
    name = z.name or ("Zone " .. tostring(chosen.i)),
    limitKmh = kph,
    limitMph = mph,
    upcoming = isUpcoming,
    entryCheckpoint = tonumber(z.from),
    entryPosition = position(entry),
    warnDistance = WARN_M,
  })
  if sent then
    lastZoneKey, lastZoneKph = key, kph
    lastZoneFrom, lastZoneTo = tonumber(z.from), tonumber(z.to)
    lastZoneUpcoming = isUpcoming
  end
end

-- a box on the unit: in, or ahead with the distance to its nearest face.
-- Ahead is told again every tick, so the distance the unit holds is the
-- one measured now.
local function showBox(key, mph, upcoming, entryPos, faceDist)
  local kph = mph * 1.609344
  upcoming = upcoming and true or false
  if key == lastZoneKey and math.abs(kph - (lastZoneKph or 0)) < 0.001
      and upcoming == lastZoneUpcoming then
    if upcoming and type(faceDist) == "number" then
      call("setSpeedZone", {
        id = key,
        name = "Speed zone",
        limitKmh = kph,
        limitMph = mph,
        upcoming = true,
        entryPosition = entryPos,
        faceDist = faceDist,
        warnDistance = WARN_M,
        box = true,
      })
    end
    return
  end
  lastZoneKey, lastZoneKph, lastZoneUpcoming = key, kph, upcoming
  lastZoneFrom, lastZoneTo = nil, nil
  call("setSpeedZone", {
    id = key,
    name = "Speed zone",
    limitKmh = kph,
    limitMph = mph,
    upcoming = upcoming,
    entryPosition = entryPos,
    faceDist = faceDist,
    warnDistance = WARN_M,
    box = true,
  })
end

-- a box counts as ahead when its nearest face is in front of the car's
-- nose. The one just left is behind, and used to warn again once the
-- quiet time ran out, while the car drove away from it.
local function boxAhead(sz)
  local face = sz.face or (type(sz.box) == "table" and sz.box.pos) or nil
  if type(face) ~= "table" then return true end
  local pos, fwd
  pcall(function()
    local v = be:getPlayerVehicle(0)
    if v then pos, fwd = v:getPosition(), v:getDirectionVector() end
  end)
  if not pos or not fwd then return true end
  return ((face.x or 0) - pos.x) * fwd.x + ((face.y or 0) - pos.y) * fwd.y > 0
end

-- In this order: a box the car is in, then a gate zone it is in. Nothing
-- it is in and something was shown as in: that is leaving, and the quiet
-- time starts. Then, outside the quiet time, a box ahead within the
-- warning distance, then the next gate zone ahead.
local function updateZones(track, nextCp)
  local trig = extensions.raceManager_triggers
  local sz = trig and type(trig.szState) == "function" and trig.szState() or nil
  local boxMph = sz and type(sz.box) == "table" and tonumber(sz.box.mph) or nil
  local boxId = boxMph and tostring(sz.box.i or sz.box.id or boxMph) or nil

  if boxMph and sz.inside then
    showBox("box:" .. boxId, boxMph, false, nil, 0)
    return
  end
  local current, upcoming = gateZonesAt(track, nextCp)
  if current then
    showGate(track, current, false)
    return
  end

  if lastZoneKey and lastZoneUpcoming == false then
    clearZone()
    return
  end
  if clock < quietUntil then
    clearZone()
    return
  end

  if boxMph and (tonumber(sz.dist) or math.huge) <= WARN_M and boxAhead(sz) then
    showBox("box-approach:" .. boxId, boxMph, true, sz.face or sz.box.pos, sz.dist)
    return
  end
  if upcoming then
    showGate(track, upcoming, true)
    return
  end
  clearZone()
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
  -- keeps what it was told
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
  -- done is the server's count of gates done this lap. It climbs at every
  -- gate and drops back to one at the lap line, so any change while the
  -- race is on is a crossing, and the gate named is the one behind next.
  -- The drop to nothing when the race ends is not.
  if active and lastDone ~= nil and done ~= lastDone and done > 0 then
    local crossed = nextCp - 1
    local count = type(track) == "table" and type(track.checkpoints) == "table" and #track.checkpoints or 0
    if crossed < 1 and count > 0 then crossed = count end
    call("onVCPCrossed", crossed)
  end
  lastDone = done

  -- a race that is over takes its zones with it, and its quiet time
  if not active then
    clearZone()
    quietUntil = 0
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
  { "green",  "Stella test 3 of 6: green flashing, all dots" },
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

-- everything on the road at this moment: the race, what the bridge holds,
-- what the box poll measures and what the unit shows, with why
function M.liveReport()
  local rs = {}
  pcall(function() rs = extensions.raceManager_race.status() or {} end)
  local sz
  pcall(function() sz = extensions.raceManager_triggers.szState() end)
  local poll = "no box"
  if type(sz) == "table" then
    poll = ("box %s %s"):format(tostring(sz.box and sz.box.i or "?"),
      sz.inside and "in" or ("out, " .. math.floor(tonumber(sz.dist) or 0) .. " m"))
  end
  local quiet = math.max(0, quietUntil - clock)
  local unit = "no unit"
  pcall(function()
    local s = stella()
    if s and type(s.report) == "function" then unit = s.report() end
  end)
  return ("race %s, next %s, done %s | bridge %s%s | poll %s | unit %s"):format(
    tostring(rs.state or "idle"), tostring(rs.next or "?"), tostring(rs.done or "?"),
    lastZoneKey and (lastZoneKey .. (lastZoneUpcoming and " ahead" or " in")) or "no zone",
    quiet > 0 and (", quiet %.0f s"):format(quiet) or "",
    poll, unit)
end

function M.selfTest()
  local racing = false
  pcall(function() racing = extensions.raceManager_race.isActive() end)
  if racing then
    local line = M.liveReport()
    pcall(function() extensions.raceManager_state.notice("Stella: " .. line) end)
    if type(log) == "function" then log("I", "raceManager", "stella live: " .. line) end
    local net = extensions.raceManager_net
    if net and type(net.send) == "function" then net.send("stella.report", { text = line }) end
    return true
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
    call("testShow", "off", 0)
    local seen = screenAnswers
    local rate = testElapsed > 0 and math.floor((unitTicks() - ticksAt) / testElapsed + 0.5) or 0
    pcall(function()
      local head = ("Stella test over: unit ticking %d a second, screen answered %d of %d."):format(rate, seen, #TEST)
      if rate == 0 then
        extensions.raceManager_state.notice(head .. " The unit is not running. Rejoin the server and send Marx the console log.")
      elseif seen == 0 then
        extensions.raceManager_state.notice(head .. " The unit works, the screen is not receiving. Rejoin the server; if it says this again, send Marx the console log.")
      elseif seen < #TEST then
        extensions.raceManager_state.notice(head .. " Some steps did not reach the screen. Rejoin the server.")
      else
        extensions.raceManager_state.notice(head .. " Everything reached the screen. If you saw nothing, the unit is hidden: Options, Dash, Stella on.")
      end
    end)
    return
  end
  call("testShow", step[1], testStep)
  pcall(function() extensions.raceManager_state.notice(step[2]) end)
end

local EVERY = 0.1
local since = 0

function M.onUpdate(dt)
  dt = tonumber(dt) or 0
  clock = clock + dt
  testTick(dt)
  since = since + dt
  if since < EVERY then return end
  since = 0
  wireNetwork()
  noticeStranger(EVERY)
  sync()
end

-- The server's word on a box zone, from zone.warn. Kept for the code that
-- calls it; it shows nothing any more. The server learns the car is in a
-- box from the same poll that shows it here, so the two already agree,
-- and showing the word as well had the unit flicker at every box edge.
function M.setPairZone(z) end

-- each change of the unit's light, with why, up to the server's log
function M.trace(line)
  local net = extensions.raceManager_net
  if not net or type(net.send) ~= "function" then return false end
  return net.send("stella.trace", { text = tostring(line or "") })
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
