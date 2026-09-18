local M = {}

-- the only bridge to the html. nothing here runs per frame except one boolean
-- test: if nothing changed there is nothing to send, and when something did
-- change it still goes out at most ten times a second. nobody reads a player
-- list at 120fps.

local UI_EVENT = "rmState"
local MIN_GAP  = 0.1

local dirty, acc = false, 0
local queueAcc, lastQueueKey = 0, ""
local resubAcc = 0
local snap = { me = {}, roster = {}, tracks = {}, capture = {}, rosterSeq = 0 }

local function beamQueues()
  local flags = {}
  local ok, vehs = pcall(function()
    return MPVehicleGE and MPVehicleGE.getVehicles and MPVehicleGE.getVehicles()
  end)
  if not ok or type(vehs) ~= "table" then return flags end
  for sid, veh in pairs(vehs) do
    if type(veh) == "table" and (veh.spawnQueue or veh.editQueue) then
      local pid = tonumber(veh.ownerID)
      if not pid then
        pid = tonumber(tostring(sid):match("^(%d+)%-"))
      end
      if pid then flags[pid] = true end
    end
  end
  return flags
end

function M.push()
  dirty = true
end

local function build()
  local S = extensions.raceManager_state.get()

  snap.ready     = S.ready
  snap.needsName = S.needsName
  snap.nameError = S.nameError
  snap.level     = S.level
  snap.isAdmin   = extensions.raceManager_state.isAdmin()
  snap.isOwner   = extensions.raceManager_state.isOwner and extensions.raceManager_state.isOwner()
  snap.isStaff   = extensions.raceManager_state.isStaff and extensions.raceManager_state.isStaff()
  snap.connected = extensions.raceManager_net.isConnected()
  snap.toast     = S.toast
  snap.invites   = S.invites or {}
  snap.config    = S.config

  -- Player list stays open. Toggle is only a refresh/subscription bump.
  S.rosterOpen = true
  snap.rosterOpen = true
  snap.lights     = S.lights and true or false
  snap.team       = S.team
  snap.myCode     = S.myCode
  snap.recovered  = S.recovered and true or false

  snap.me.id    = S.me.id
  snap.me.name  = S.me.name
  snap.me.role  = S.me.role
  snap.me.level = S.me.level
  snap.me.guest = S.me.guest
  snap.me.tracking = S.me.tracking ~= false
  snap.me.ranked = S.me.ranked ~= false

  -- watching: what the server says, and whether the car has been found here
  snap.copilot  = S.copilot
  local watchOk, watchSt = pcall(function() return extensions.raceManager_copilot.status() end)
  snap.watching = (watchOk and watchSt and watchSt.watching) or false
  snap.challenges = S.challenges
  snap.challengeFinished = S.challengeFinished
  snap.profile    = S.profile
  snap.drivers    = S.drivers

  -- Angular needs a *new* array of *new* row tables every push. Reusing the
  -- same Lua table references meant the CEF side saw no change and the list
  -- only refreshed when the user toggled Players.
  local n = 0
  local fresh = {}
  for _, row in pairs(S.roster) do
    if type(row) == "table" then
      n = n + 1
      fresh[n] = {
        id = row.id,
        name = row.name,
        level = row.level,
        guest = row.guest and true or false,
        speed = row.speed,
        ping = row.ping,
        role = row.role,
        model = row.model,
        queued = false,
      }
    end
  end
  table.sort(fresh, function(a, b) return (a.name or "") < (b.name or "") end)
  local qflags = beamQueues()
  for i = 1, n do
    local row = fresh[i]
    if row then
      row.queued = qflags[tonumber(row.id)] and true or false
    end
  end
  snap.roster = fresh
  snap.rosterSeq = (snap.rosterSeq or 0) + 1

  snap.tracks = S.tracks
  snap.capture = extensions.raceManager_capture.status()
  snap.perf = extensions.raceManager_perf.status()
  snap.race = extensions.raceManager_race.status()
  snap.challengeLive = extensions.raceManager_telemetry.status()
  snap.service = extensions.raceManager_service.status()
  snap.records = S.records

  return snap
end

local function flush()
  dirty = false
  acc = 0
  local ok, payload = pcall(build)
  if not ok then
    log("E", "raceManager", "ui build failed: " .. tostring(payload))
    local S = extensions.raceManager_state.get()
    payload = { ready = S.ready, needsName = S.needsName, me = S.me or {},
                roster = {}, tracks = {}, connected = true }
  end
  guihooks.trigger(UI_EVENT, payload)
end

local function onUpdate(dt)
  -- a toast nobody dismissed should not sit on screen for the rest of the
  -- session. one nil test per frame when there is not one.
  local S = extensions.raceManager_state.get()
  if S.toast then
    S.toastFor = (S.toastFor or 0) - dt
    if S.toastFor <= 0 then
      S.toast = nil
      dirty = true
    end
  end
  pcall(function() extensions.raceManager_state.tickInvites(dt) end)

  queueAcc = queueAcc + dt
  if queueAcc >= 0.4 then
    queueAcc = 0
    local flags = beamQueues()
    local keys = {}
    for pid in pairs(flags) do keys[#keys + 1] = tostring(pid) end
    table.sort(keys)
    local sig = table.concat(keys, ",")
    if sig ~= lastQueueKey then
      lastQueueKey = sig
      dirty = true
    end
  end

  -- Resubscribe every 15s so a missed join still lands a full roster.
  resubAcc = resubAcc + dt
  if resubAcc >= 15.0 then
    resubAcc = 0
    pcall(function()
      extensions.raceManager_net.send("roster.sub", { on = true })
    end)
  end

  if not dirty then return end
  acc = acc + dt
  if acc < MIN_GAP then return end
  flush()
end

-- the app can come up after the state did, so it asks once on its own
function M.requestState()
  flush()
end

------------------------------------------------------------ called from html

function M.setName(name)
  extensions.raceManager_net.send("name.set", { name = tostring(name or "") })
end

function M.recoverName(code)
  extensions.raceManager_net.send("name.recover", { code = tostring(code or "") })
end

function M.dismissCode()
  extensions.raceManager_state.get().myCode = nil
  M.push()
end

function M.setRosterOpen(open)
  -- Always on. open=false is ignored so the list never vanishes mid-session.
  extensions.raceManager_state.get().rosterOpen = true
  -- Flip sub off/on so the server re-sends roster.full even if already subscribed.
  pcall(function()
    extensions.raceManager_net.send("roster.sub", { on = false })
    extensions.raceManager_net.send("roster.sub", { on = true })
  end)
  M.push()
end

function M.keepRoster()
  pcall(function()
    extensions.raceManager_net.send("roster.sub", { on = false })
    extensions.raceManager_net.send("roster.sub", { on = true })
  end)
end

function M.takeInvite(id)
  extensions.raceManager_state.takeInvite(id)
end

function M.refuseInvite(id)
  extensions.raceManager_state.refuseInvite(id)
end

function M.toggleLights()
  extensions.raceManager_state.toggleLights()
end

function M.closeLights()
  extensions.raceManager_state.closeLights()
end

function M.togglePlayers()
  -- Button is a hard refresh, not a hide. List stays open.
  M.setRosterOpen(true)
end

function M.demoteSelf()
  extensions.raceManager_net.send("options.demoteSelf", {})
end

-- The game is the only thing that knows whether this worked, and it used to
-- keep that to itself: press the button on a build without the binding and
-- nothing happens at all, which reads as broken rather than unsupported. So
-- every route says what it did, and the one that always works is the link
-- sitting on the panel above the button.
function M.openDiscord()
  local notice = extensions.raceManager_state.notice
  local url = extensions.raceManager_state.get().config.discordUrl

  if type(url) ~= "string" or url == "" then
    log("W", "raceManager", "no discord url is set on the server")
    notice("No Discord link is set on the server")
    return
  end

  -- The engine's own call is behind a domain filter that only lets BeamNG's
  -- sites through, and discord is not one of them: it logged "unable to open
  -- webpage due to domain filter" and did nothing. BeamMP's launcher runs
  -- outside the game and opens whatever it is handed, so on a server that
  -- goes first.
  local viaLauncher = false
  pcall(function()
    if MPCoreNetwork and type(MPCoreNetwork.openURL) == "function"
       and MPCoreNetwork.isMPSession and MPCoreNetwork.isMPSession() then
      MPCoreNetwork.openURL(url)
      viaLauncher = true
    end
  end)
  if viaLauncher then
    log("I", "raceManager", "discord: asked the BeamMP launcher to open " .. url)
    notice("Opened it through BeamMP. The game keeps focus, so Alt-Tab to your browser")
    return
  end

  if type(openWebBrowser) ~= "function" then
    log("W", "raceManager", "no browser hook in this build. the link is " .. url)
    notice("This build cannot open a browser. Use Copy link instead")
    return
  end

  local browserOk = pcall(openWebBrowser, url)

  -- the shell handles an http url on windows and is worth a try when the
  -- engine binding is present but refuses
  local shellOk = false
  if not browserOk then
    shellOk = pcall(function() Engine.Platform.exploreFolder(url) end)
  end

  log("I", "raceManager", ("discord: browser=%s shell=%s url=%s")
    :format(tostring(browserOk), tostring(shellOk), url))

  if browserOk or shellOk then
    notice("Opened it. The game keeps focus, so Alt-Tab to your browser")
  else
    notice("Could not open a browser. Use Copy link instead")
  end
end

function M.exitServer()
  local ok = pcall(function() MPCoreNetwork.leaveServer(true) end)
  if not ok then
    pcall(function() returnToMainMenu() end)
  end
end

function M.getRecords(id, class)
  extensions.raceManager_net.send("records.get", {
    id    = tostring(id or ""),
    class = type(class) == "string" and class ~= "" and class or nil,
  })
end

function M.getProfile(keyOrPid)
  local key, id, name = keyOrPid, keyOrPid, nil
  if type(keyOrPid) == "table" then
    key  = keyOrPid.key or keyOrPid.id or keyOrPid.name
    id   = keyOrPid.id or keyOrPid.key
    name = keyOrPid.name
  end
  extensions.raceManager_net.send("profile.get", { key = key, id = id, name = name })
end

function M.getDrivers()
  local net = extensions.raceManager_net
  if net and type(net.send) == "function" then
    net.send("profile.list", {})
  end
end
M.drivers = M.getDrivers

function M.staffRole(key, role)
  extensions.raceManager_net.send("staff.role", { key = key, role = role })
end
function M.staffKick(key)
  extensions.raceManager_net.send("staff.kick", { key = key })
end
-- kicks a driver out of whatever race they're currently in, not off the
-- server -- they stay connected, only their run ends as a DNF, so an afk
-- driver doesn't leave everyone else waiting on a heat that can't close
function M.staffRaceKick(pid)
  extensions.raceManager_net.send("race.kick", { pid = pid })
end
-- picks one live challenge and starts an attempt for every connected
-- driver right now, kicking off a scheduled event on the spot
function M.staffLaunchAll(challengeId)
  extensions.raceManager_net.send("race.launchAll", { challenge = challengeId })
end
function M.staffBan(key)
  extensions.raceManager_net.send("staff.ban", { key = key, why = "banned" })
end
function M.staffClearRecords(key)
  extensions.raceManager_net.send("staff.clearRecords", { key = key })
end

function M.takePlayerQueue(pid)
  pid = tonumber(type(pid) == "table" and pid.id or pid)
  if not pid then return false end
  local ok, vehs = pcall(function()
    return MPVehicleGE and MPVehicleGE.getVehicles and MPVehicleGE.getVehicles()
  end)
  if not ok or type(vehs) ~= "table" then return false end
  local saved, had = {}, false
  for sid, veh in pairs(vehs) do
    if type(veh) == "table" then
      local owner = tonumber(veh.ownerID) or tonumber(tostring(sid):match("^(%d+)%-"))
      if owner == pid and (veh.spawnQueue or veh.editQueue) then
        had = true
      elseif owner ~= pid and (veh.spawnQueue or veh.editQueue) then
        saved[sid] = { spawn = veh.spawnQueue, edit = veh.editQueue }
        veh.spawnQueue, veh.editQueue = nil, nil
      end
    end
  end
  if had then
    pcall(function() MPVehicleGE.applyQueuedEvents() end)
  end
  for sid, q in pairs(saved) do
    local veh = vehs[sid]
    if veh then
      if q.spawn and not veh.spawnQueue then veh.spawnQueue = q.spawn end
      if q.edit and not veh.editQueue then veh.editQueue = q.edit end
    end
  end
  -- If we are copiloting this driver, stay on them and re-seek their car after the queue applies.
  pcall(function()
    local cp = extensions.raceManager_copilot
    if cp and type(cp.keepWatchingAfterQueue) == "function" then
      cp.keepWatchingAfterQueue(pid)
    end
  end)
  M.push()
  return had
end

function M.queuePlayerThenProfile(pid)
  local id, key, name
  if type(pid) == "table" then
    id, key, name = tonumber(pid.id), pid.key, pid.name
  else
    id = tonumber(pid)
  end
  -- Best-effort BeamMP apply queue so their car is here before the card opens.
  pcall(function()
    if MPVehicleGE and type(MPVehicleGE.applyQueuedEvents) == "function" then
      MPVehicleGE.applyQueuedEvents()
    end
  end)
  extensions.raceManager_net.send("profile.get", { id = id, key = key or id, name = name })
end

function M.clearToast()
  extensions.raceManager_state.get().toast = nil
  M.push()
end

function M.armRace(id, mode, laps, class, challenge, official, officialName)
  extensions.raceManager_race.arm(id, mode, laps, class, challenge, official, officialName)
end

-- a challenge with no course picked -- see race.lua's M.armChallenge
function M.armChallenge(challengeId, mode, class)
  extensions.raceManager_race.armChallenge(challengeId, mode, class)
end

function M.createLobby(trackId, mode, laps, open, class, official, officialName)
  extensions.raceManager_race.createLobby(trackId, mode, laps, open, class, official, officialName)
end

-- the challenge board and its tools
function M.challengesGet()
  extensions.raceManager_net.send("challenges.get", {})
end

local function formTable(form)
  if type(form) == "string" then
    local ok, t = pcall(jsonDecode, form)
    if ok and type(t) == "table" then return t end
    return nil
  end
  if type(form) == "table" then return form end
  return nil
end

function M.challengeCreate(form)
  form = formTable(form)
  if not form then
    extensions.raceManager_state.notice("Challenge was not posted: the form did not send")
    return
  end
  extensions.raceManager_net.send("challenge.create", form)
  extensions.raceManager_state.notice("Posting challenge…")
end

function M.challengeUpdate(form)
  form = formTable(form)
  if not form or not form.id then
    extensions.raceManager_state.notice("Challenge was not saved: the form did not send")
    return
  end
  extensions.raceManager_net.send("challenge.update", form)
  extensions.raceManager_state.notice("Saving challenge…")
end

function M.challengeDelete(id)
  if type(id) ~= "string" then return end
  extensions.raceManager_net.send("challenge.delete", { id = id })
end

function M.challengeEnd(id)
  if type(id) ~= "string" then return end
  extensions.raceManager_net.send("challenge.end", { id = id })
end

-- !resetui in chat: every window back in place and the whole screen asked
-- for again. His uifix does the work; the screen hook is the fallback.
function M.resetWindows()
  local done = pcall(function() return extensions.raceManager_uifix.restore() end)
  if not done then
    guihooks.trigger("rmResetAsked", {})
    pcall(function() extensions.raceManager_layout.arm() end)
  end
end

-- XP and challenge tracking, on or off for yourself
function M.setTracking(on)
  extensions.raceManager_net.send("options.tracking", { on = on and true or false })
end

function M.endRace()
  extensions.raceManager_race.endRace()
end

function M.restartRace()
  extensions.raceManager_race.restart()
end

function M.closeResults()
  extensions.raceManager_race.closeResults()
end

-- the personal challenge-results screen, closed
function M.clearChallengeFinished()
  extensions.raceManager_state.clearChallengeFinished()
end

M.onUpdate = onUpdate
M.flush    = flush

return M
