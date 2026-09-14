RM = RM or {}
RM.zones = {}

-- Speed limits between two checkpoints you pick. He asked for the 37 mph pit
-- limit to work between selected waypoints, and this is that.
--
-- The server does the checking. It already reads everybody's speed for the
-- player list, so this costs nothing new and there is nothing for a driver's
-- own game to lie about.
--
-- Going over does not punish you straight away. You get a warning, and the
-- charge only lands if you stay over, so one bump over a crest is free. Once
-- it has charged you it will not charge again until you drop back under.

function RM.zones.szGate(trackId, index)
  local track = RM.tracks.get(trackId)
  if not track or type(track.szGates) ~= "table" then return nil end
  return track.szGates[math.floor(tonumber(index) or 0)]
end

function RM.zones.onSzHit(pid, index)
  -- kept so an old client that still sends sz.hit does not error
  local g = RM.zones.szGate((RM.race.get(pid) or {}).track, index)
  if g then return RM.zones.onSzState(pid, true, g.mph) end
  return nil
end

function RM.zones.onSzState(pid, inside, mph)
  local r = RM.race.get(pid)
  if not r or (r.state ~= "running" and r.state ~= "armed") then return nil end
  if inside then
    r.szInside = true
    r.szMph = tonumber(mph) or r.szMph or RM.config.speedZoneMph or 37
    return "on"
  end
  r.szInside, r.szMph = false, nil
  r.overFor, r.overCharged = nil, nil
  return "off"
end

-- which zone covers the stretch you are on. the stretch is named by the gate
-- you are heading for, so a zone from 12 to 14 covers the drive to 13 and 14.
function RM.zones.at(trackId, nextGate)
  local track = RM.tracks.get(trackId)
  if not track or type(track.zones) ~= "table" then return nil end

  local g = math.floor(tonumber(nextGate) or 0)
  for i = 1, #track.zones do
    local z = track.zones[i]
    if g > z.from and g <= z.to then return z end
  end
  return nil
end

function RM.zones.sample(pid, mph)
  local r = RM.race.get(pid)
  if not r or r.state ~= "running" then return nil end
  if not RM.util.isNum(mph) then return nil end

  local zone = RM.zones.at(r.track, r.nextGate)
  if not zone and r.szInside and r.szMph then
    zone = { mph = r.szMph, from = 0, to = 0, box = true }
  end
  if not zone then
    r.overFor, r.overCharged = nil, nil
    return nil
  end

  if mph <= zone.mph then
    r.overFor, r.overCharged = 0, false
    return nil
  end

  r.overFor = (r.overFor or 0) + (RM.config.rosterMs / 1000)

  if r.overCharged then return "over" end
  if r.overFor < (RM.config.speedGraceSec or 3) then return "warn" end

  r.overCharged = true
  local seconds = tonumber(RM.config.penalties.speeding) or 0
  if seconds > 0 then
    RM.race.penalty(pid, seconds, "speeding", r.nextGate)
    RM.info(("%s went over %d mph in the zone before gate %d"):format(
      RM.identity.displayName(pid), zone.mph, r.nextGate))
  end
  return "charged"
end

-- what the screen needs to show a limit while you are inside one
function RM.zones.wire(pid)
  local r = RM.race.get(pid)
  if not r or r.state ~= "running" then return nil end
  local zone = RM.zones.at(r.track, r.nextGate)
  if not zone and r.szInside and r.szMph then
    return { mph = r.szMph, box = true, from = 0, to = 0 }
  end
  if not zone then return nil end
  return { mph = zone.mph, from = zone.from, to = zone.to }
end
