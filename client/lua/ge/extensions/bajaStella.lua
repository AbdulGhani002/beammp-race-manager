-- Standalone Stella III EVO client instrument.
-- This extension deliberately owns its state; it does not use Baja gameCommands,
-- speedGovernor, uiLayout, or BajaConfigs.
local M = {}

local cfg = {
  tick = 0.1, immediateRange = 8, rearApproachRange = 150,
  proximityClear = 175, proximityCooldown = 5, closingSpeed = 3
}
local race = {}
local course = {}
local nextCheckpoint = 1
local validatedCheckpoints = 0
local zone = nil
local speedWarning = nil
local proximity = nil
local proximityLast = {}
local odo, lastPos, timer = 0, nil, 0
local clock = 0
local led = {color="off", flash=false, pattern="none"}
local ledUntil = 0
local blueFlag = {state="none", playerName=""}
local breakdown = false
local hazardAhead = nil
local lastExceeding = false

local function num(v, d) return tonumber(v) or d or 0 end
local function point(cp)
  if not cp then return nil end
  local p = cp.pos or cp.position or cp
  if type(p) ~= "table" then return nil end
  return {x=num(p.x or p[1]), y=num(p.y or p[2]), z=num(p.z or p[3])}
end
local function emit(name, data) if guihooks then guihooks.trigger(name, data or {}) end end
local function setLed(color, flash, pattern)
  led = {color=color or "off", flash=flash or false, pattern=pattern or "none"}
  emit("BajaStella_LED", led)
end
-- the limit the way he reads it, in mph, for the dots to spell out
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
    tostring(z.limitKmh or z.speedLimitKmh or "")
  }, ":")
end
local function restoreLed()
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
  elseif zone and zone.upcoming and zone.advanceWarned then
    setLed("yellow", true, limitPattern(zone))
  elseif zone and not zone.upcoming then
    setLed("red", lastExceeding and true or false, limitPattern(zone))
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
local function publishAlert()
  emit("BajaStella_Alert", {
    breakdown=breakdown, hazardAhead=hazardAhead ~= nil, blueFlagState=blueFlag.state,
    blueFlagPlayer=blueFlag.playerName, ledColor=led.color,
    ledFlash=led.flash, ledPattern=led.pattern
  })
end
local function vehicle()
  return be and be:getPlayerVehicle(0) or nil
end
-- Airspeed: world velocity length in km/h. Same quantity as electrics.airspeed.
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
  local dx, dy = p.x-pos.x, p.y-pos.y
  local dist = math.sqrt(dx*dx + dy*dy)
  local bearing = math.deg(math.atan2(dx, dy)); if bearing < 0 then bearing=bearing+360 end
  return dist, bearing, cp.name or ("VCP"..nextCheckpoint), #course, dist < 500
end

-- Public bridge API ---------------------------------------------------------
function M.setRaceState(data)
  race = type(data) == "table" and data or {}
  if race.active == nil then race.active = race.raceActive end
  if race.started == nil then race.started = race.raceStarted end
  race.trackName = race.trackName or race.currentTrack or ""
  if race.checkpoints and #course == 0 then course=race.checkpoints end
  if race.currentCheckpoint then nextCheckpoint=num(race.currentCheckpoint, nextCheckpoint) end
  if race.active == false or race.active == nil then odo=0; lastPos=nil end
end
function M.setCourse(track, checkpoints)
  if type(track) == "table" and checkpoints == nil then checkpoints=track.checkpoints; track=track.name end
  race.trackName = track or race.trackName or ""; course=type(checkpoints)=="table" and checkpoints or {}
end
function M.setNextCheckpoint(index) nextCheckpoint=math.max(1, num(index, 1)) end
function M.setProgress(index, done)
  nextCheckpoint=math.max(1, num(index, nextCheckpoint))
  validatedCheckpoints=math.max(0, num(done, validatedCheckpoints))
end
function M.onVCPCrossed(index)
  setLed("green", false, "all")
  ledUntil = clock + 2
  emit("BajaStella_VCPCrossed", {index=index})
  emit("BajaStella_VCPSound", {index=index})
end
function M.setSpeedZone(z)
  if z == nil then
    if zone and not zone.upcoming then emit("BajaStella_SpeedZone", {event="exit"}) end
    zone=nil
    lastExceeding=false
    restoreLed()
    return
  end
  local wasActive = zone ~= nil and not zone.upcoming
  local oldKey = zoneIdentity(zone)
  zone=z
  zone.advanceWarned = zone.advanceWarned or false
  local isActive = not z.upcoming
  local newKey = zoneIdentity(z)
  if wasActive and isActive and oldKey ~= newKey then
    emit("BajaStella_SpeedZone", {event="exit"})
    lastExceeding=false
  end
  if isActive and (not wasActive or oldKey ~= newKey) then
    emit("BajaStella_SpeedZone", {event="enter", zoneName=z.name or "", limitKmh=num(z.limitKmh or z.speedLimitKmh)})
  end
  restoreLed()
end
function M.onSpeedWarning(data)
  speedWarning=data
  emit("BajaStella_SpeedZone", {event="exceeded", limitKmh=data and data.limitKmh, currentKmh=data and data.currentKmh})
end
function M.onProximityAlert(data)
  proximity=data or {}
  emit("BajaStella_Proximity", proximity)
  emit("Message", {msg=(proximity.kind=="rearApproach" and "⚠ Vehicle closing from behind" or "⚠ Vehicle nearby"), category="warning"})
  setLed("yellow", true, "triangle")
end
function M.clearProximityAlert() proximity=nil; emit("BajaStella_Proximity", {clear=true}); restoreLed() end
function M.requestState() emit("BajaStella_Show"); timer=cfg.tick end

-- The red UI control is a held mechanical/stopped warning, not SOS.
function M.toggleMechanicalBreakdown()
  breakdown = not breakdown
  emit("BajaStella_Breakdown", {active=breakdown})
  bridgeCall("sendBreakdown", breakdown)
  restoreLed()
  publishAlert()
end
function M.requestMechanicalBreakdown() M.toggleMechanicalBreakdown() end
-- Compatibility for older UI bindings: retain the name, but never emit SOS.
M.requestSOS = M.requestMechanicalBreakdown
function M.acknowledgeBlueFlag()
  if blueFlag.state == "incoming" then
    blueFlag.state="accepted"
    emit("BajaStella_BlueFlag", blueFlag)
    bridgeCall("acceptPass", blueFlag.requestId)
    restoreLed(); publishAlert()
  end
end
function M.requestBlueFlag()
  blueFlag={state="requested", playerName=""}
  emit("BajaStella_BlueFlag", blueFlag)
  bridgeCall("requestPass")
  restoreLed(); publishAlert()
end
M.stellaSOS = M.requestSOS
M.stellaOK = M.acknowledgeBlueFlag
M.stellaFlag = M.requestBlueFlag

function M.onRaceManagerPassAlert(data)
  if type(data) ~= "table" then return end
  blueFlag={state="incoming", playerName=tostring(data.requesterName or data.playerName or ""),
    requestId=data.requestId, requesterId=data.requesterId, distanceM=data.distanceM}
  emit("BajaStella_BlueFlag", blueFlag)
  emit("BajaStella_AlertSound", {kind="blueFlag", loud=false, beep=true})
  emit("Message", {msg="BLUE FLAG: vehicle asking to pass", category="warning"})
  restoreLed(); publishAlert()
end
function M.onRaceManagerPassStatus(data)
  if type(data) ~= "table" then return end
  local state=tostring(data.state or "")
  if state=="delivered" or state=="requested" or state=="accepted" or state=="cancelled" or state=="expired" or state=="complete" then
    blueFlag.state=(state=="cancelled" or state=="expired" or state=="complete") and "none" or state
    blueFlag.playerName=tostring(data.aheadName or data.playerName or "")
    blueFlag.requestId=data.requestId
    emit("BajaStella_BlueFlag", blueFlag)
    restoreLed(); publishAlert()
  end
end
function M.onRaceManagerPassGo(data)
  blueFlag={state="go", playerName=tostring(type(data)=="table" and (data.aheadName or data.playerName) or "")}
  emit("BajaStella_BlueFlag", blueFlag)
  emit("BajaStella_AlertSound", {kind="passGo", loud=false, beep=true})
  restoreLed(); publishAlert()
end
function M.onRaceManagerBreakdownState(data)
  if type(data) ~= "table" or data.active == nil then return end
  breakdown=data.active and true or false
  emit("BajaStella_Breakdown", {active=breakdown, remote=true})
  restoreLed(); publishAlert()
end
function M.onRaceManagerBreakdownAlert(data)
  if type(data) ~= "table" or data.active == false then
    hazardAhead=nil
    emit("BajaStella_HazardAhead", {active=false})
  else
    hazardAhead=data
    emit("BajaStella_HazardAhead", data)
    emit("BajaStella_AlertSound", {kind="stoppedVehicle", loud=true, beep=true})
    emit("Message", {msg="⚠ VEHICLE STOPPED AHEAD", category="warning"})
  end
  restoreLed(); publishAlert()
end

local function detectProximity(v, pos, fwd, playerSpeed)
  if not be or not be.getObjectCount then return end
  local pid=v:getID()
  local found=nil
  for i=0,be:getObjectCount()-1 do
    local other=be:getObject(i)
    if other and other:getID() ~= pid and not (other.isHidden and other:isHidden()) then
      local op=other:getPosition()
      if op then
        local dx,dy,dz=op.x-pos.x,op.y-pos.y,op.z-pos.z
        local dist=math.sqrt(dx*dx+dy*dy+dz*dz)
        if dist <= cfg.rearApproachRange then
          local front=(dx*fwd.x+dy*fwd.y+dz*fwd.z) >= 0
          local ov=other:getVelocity()
          local pv=v:getVelocity()
          local invDist=dist > 0.001 and (1/dist) or 0
          local closing=((pv and pv.x or 0)-(ov and ov.x or 0))*dx*invDist
            + ((pv and pv.y or 0)-(ov and ov.y or 0))*dy*invDist
            + ((pv and pv.z or 0)-(ov and ov.z or 0))*dz*invDist
          local kind
          if dist <= cfg.immediateRange then kind="nearby"
          elseif not front and closing >= cfg.closingSpeed then kind="rearApproach" end
          if kind then
            found={vehicleId=other:getID(), distance=math.floor(dist), kind=kind, closingSpeed=closing*3.6}
            break
          end
        end
      end
    end
  end
  if found then
    local now=clock
    if not proximity or proximity.vehicleId~=found.vehicleId or proximity.kind~=found.kind or now-(proximityLast[found.vehicleId] or -math.huge)>=cfg.proximityCooldown then
      proximityLast[found.vehicleId]=now; M.onProximityAlert(found)
    end
  elseif proximity then
    local p=vehicle(); local pp=p and p:getPosition()
    if not pp or not proximity.vehicleId then M.clearProximityAlert() else
      local ov=be:getObjectByID(proximity.vehicleId); local op=ov and ov:getPosition()
      if not op or math.sqrt((op.x-pp.x)^2+(op.y-pp.y)^2+(op.z-pp.z)^2)>cfg.proximityClear then M.clearProximityAlert() end
    end
  end
end

function M.onUpdate(dt)
  dt=dt or 0
  clock=clock+dt
  timer=timer+dt; if timer<cfg.tick then return end; timer=0
  local v=vehicle(); if not v then return end
  local pos=v:getPosition(); if not pos then return end
  local speed,heading,fwd=speedAndHeading(v)
  fwd=fwd or {x=0,y=1,z=0}
  if ledUntil > 0 and clock >= ledUntil then ledUntil=0; restoreLed() end
  if lastPos and race.active and race.started then
    local dx,dy,dz=pos.x-lastPos.x,pos.y-lastPos.y,pos.z-lastPos.z
    local d=math.sqrt(dx*dx+dy*dy+dz*dz); if d<50 then odo=odo+d end
  end
  lastPos={x=pos.x,y=pos.y,z=pos.z}
  local dist,bearing,name,total,approach=checkpointData(pos)
  detectProximity(v,pos,fwd,speed)
  if zone and zone.upcoming and not zone.advanceWarned then
    local ep=point(zone.entryPosition) or point(course[num(zone.entryCheckpoint, nextCheckpoint)])
    local ed=ep and math.sqrt((ep.x-pos.x)^2+(ep.y-pos.y)^2) or dist
    if ed <= num(zone.warnDistance, 90) then
      emit("BajaStella_SpeedZone",{event="advance",zoneName=zone.name or "",limitKmh=num(zone.limitKmh or zone.speedLimitKmh),distance=ed})
      zone.advanceWarned=true
      restoreLed()
    end
  end
  local zoneActive=zone~=nil and not zone.upcoming
  local exceeding=zoneActive and num(zone.limitKmh or zone.speedLimitKmh)>0 and speed>num(zone.limitKmh or zone.speedLimitKmh) or false
  if exceeding ~= lastExceeding then
    lastExceeding=exceeding
    emit("BajaStella_SpeedZone", exceeding and
      {event="exceeded",limitKmh=num(zone.limitKmh or zone.speedLimitKmh),currentKmh=speed} or
      {event="normalized"})
    if ledUntil == 0 then restoreLed() end
  end
  emit("BajaStella_Update",{heading=math.floor(heading),speed=math.floor(speed),distToVCPm=math.floor(dist),distToVCPkm=dist/1000,vcpName=name,vcpIndex=nextCheckpoint,validatedVCPs=validatedCheckpoints,totalVCPs=total,totalDistKm=odo/1000,raceActive=not not race.active,raceStarted=not not race.started,bearingToVCP=math.floor(bearing),isApproaching=approach,trackName=race.trackName or "",isStopped=speed<1.5,breakdownActive=breakdown,hazardAhead=hazardAhead~=nil,blueFlagState=blueFlag.state,blueFlagPlayer=blueFlag.playerName,ledColor=led.color,ledFlash=led.flash,ledPattern=led.pattern,speedZoneActive=zoneActive,speedZoneWarning=zone~=nil and zone.upcoming and zone.advanceWarned,speedZoneName=zone and zone.name or "",speedZoneLimit=zone and num(zone.limitKmh or zone.speedLimitKmh) or 0,speedZoneLimitMph=zone and zoneMph(zone) or 0,speedExceeding=exceeding})
end

function M.onExtensionLoaded() setLed("off",false,"none") end
return M