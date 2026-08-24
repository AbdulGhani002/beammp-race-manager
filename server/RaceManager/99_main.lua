RM = RM or {}

local TICK = "rm:tick"
local ticks = 0
local rosterEvery, saveEvery, helloEvery

-- one timer for the plugin. everything periodic divides into 100ms, and none
-- of it runs while the server is empty.
local function onTick()
  ticks = ticks + 1

  if MP.GetPlayerCount() == 0 then
    if ticks % saveEvery == 0 then RM.store.flushDirty() end
    return
  end

  if ticks % rosterEvery == 0 then RM.players.sample() end

  RM.players.tick()

  -- the clock probe rides the batch that is already going out
  if ticks % rosterEvery == 0 then
    for pid, s in pairs(RM.identity.sessions()) do
      if s.hello then RM.clock.maybeProbe(pid, s) end
    end
  end

  RM.bus.flush()

  if ticks % saveEvery  == 0 then RM.store.flushDirty() end
  if ticks % helloEvery == 0 then RM.identity.checkHello() end
end

local function onPlayerJoining(pid)
  local s = RM.identity.onJoin(pid)
  RM.players.onJoin(pid)
  RM.info(("player %d joining: %s / role %s / %s"):format(
    pid, s.key, s.role, s.name and ("named " .. s.name) or "no display name yet"))
end

local function onPlayerDisconnect(pid)
  RM.race.onLeave(pid)
  RM.players.onLeave(pid)
  RM.identity.onLeave(pid)
  RM.bus.forget(pid)
end

local function onShutdown()
  RM.info(("shutting down, wrote %d store(s)"):format(RM.store.flushAll()))
end

-- the speed reading needs to know which vehicle to look at, and BeamMP has no
-- currently-driving flag. the newest one they touched is the best available.
local function onVehicleSpawn(pid, vid)   RM.players.onVehicle(pid, vid) end
local function onVehicleReset(pid, vid)   RM.players.onVehicle(pid, vid) end
local function onVehicleEdited(pid, vid)  RM.players.onVehicle(pid, vid) end
local function onVehicleDeleted(pid, vid) RM.players.onVehicleGone(pid, vid) end

local function wireChannels()

  -- not onPlayerJoining: that fires before the game side extension is up, so
  -- the client tells us when it is actually ready to be talked to
  RM.bus.on("hello", function(pid, d)
    local s = RM.identity.session(pid)
    if not s then
      s = RM.identity.onJoin(pid)
      RM.players.onJoin(pid)
    end
    s.hello = true
    s.clientVersion = type(d) == "table" and tostring(d.version) or "?"
    if s.clientVersion ~= RM.VERSION then
      RM.warn(("player %d runs client %s, server is %s"):format(pid, s.clientVersion, RM.VERSION))
    end

    RM.bus.sendNow(pid, "welcome", {
      id     = pid,
      key    = s.key,
      name   = s.name,          -- nil means: ask them to pick one
      role   = s.role,
      guest  = s.guest,
      ranked = RM.identity.isRanked(pid),
      level  = s.level,
      config = RM.config.public,
      serverVersion = RM.VERSION,
    })
    RM.tracks.sendList(pid)
    RM.tracks.sendDraft(pid)
  end)

  RM.bus.on("name.set", function(pid, d)
    local raw = type(d) == "table" and d.name or d
    local ok, result, code = RM.identity.setName(pid, raw)
    if ok then
      RM.players.onNameChanged(pid)
      RM.bus.sendNow(pid, "name.result", { ok = true, name = result, code = code })
      RM.bus.broadcast("toast", { kind = "info", key = "player_named", a = result })
    else
      RM.bus.sendNow(pid, "name.result", { ok = false, reason = result })
    end
  end)

  -- a player whose connection changed, getting their own name back without
  -- needing an admin at the console
  RM.bus.on("name.recover", function(pid, d)
    local code = type(d) == "table" and d.code or d
    local ok, result = RM.identity.recover(pid, code)
    if ok then
      RM.players.onNameChanged(pid)
      RM.players.onRoleChanged(pid)
      RM.identity.sendMe(pid)
      RM.bus.sendNow(pid, "name.result", { ok = true, name = result, recovered = true })
    else
      RM.bus.sendNow(pid, "name.result", { ok = false, reason = result })
    end
  end)

  RM.bus.on("roster.sub", function(pid, d)
    RM.players.setSubscribed(pid, d == true or (type(d) == "table" and d.on == true))
  end)

  local function reply(pid, action, ok, result)
    RM.bus.queue(pid, "capture.result", {
      action = action,
      ok     = ok,
      reason = (not ok) and result or nil,
      data   = ok and result or nil,
    })
  end

  RM.bus.on("track.begin",  function(pid, d) reply(pid, "begin",  RM.tracks.beginCapture(pid, d)) end)
  RM.bus.on("track.mark",   function(pid, d) reply(pid, "mark",   RM.tracks.mark(pid, d)) end)
  RM.bus.on("track.undo",   function(pid)    reply(pid, "undo",   RM.tracks.undo(pid)) end)
  RM.bus.on("track.gate",   function(pid, d) reply(pid, "gate",   RM.tracks.setGate(pid, d)) end)
  RM.bus.on("track.start",  function(pid, d) reply(pid, "start",  RM.tracks.setStart(pid, d)) end)
  RM.bus.on("track.finish", function(pid)    reply(pid, "finish", RM.tracks.finishCapture(pid)) end)
  RM.bus.on("track.cancel", function(pid)    reply(pid, "cancel", RM.tracks.cancelCapture(pid)) end)

  RM.bus.on("track.delete", function(pid, d)
    reply(pid, "delete", RM.tracks.deleteTrack(pid, type(d) == "table" and d.id or d))
  end)

  RM.bus.on("track.get", function(pid, d)
    RM.tracks.sendTrack(pid, type(d) == "table" and d.id or d)
  end)

  RM.bus.on("options.demoteSelf", function(pid)
    local ok, result = RM.roles.demoteSelf(pid)
    RM.bus.queue(pid, "options.result", { action = "demoteSelf", ok = ok, value = result })
  end)

  RM.bus.on("clock.pong", function(pid, d)
    RM.clock.onPong(pid, d)
  end)

  RM.bus.on("race.arm", function(pid, d)
    local ok, result = RM.race.arm(pid, d)
    if ok then
      RM.bus.queue(pid, "race.state", RM.race.wire(pid))
      local track = RM.tracks.get(result.track)
      if track and track.start then
        RM.bus.queue(pid, "race.teleport", track.start)
      end
    else
      RM.bus.queue(pid, "race.result", { ok = false, reason = result })
    end
  end)

  RM.bus.on("race.end", function(pid)
    local ok = RM.race.endRace(pid)
    if ok then RM.bus.queue(pid, "race.state", RM.race.wire(pid)) end
  end)

  -- a crossing, stamped by the client at the frame the trigger fired. the
  -- server decides what that stamp is worth.
  RM.bus.on("cp.hit", function(pid, d)
    if type(d) ~= "table" then return end
    if not RM.identity.session(pid) then return end

    local ok, result = RM.race.gate(pid, d.i, tonumber(d.t))
    if not ok then
      RM.debug(("gate %s from %s: %s"):format(tostring(d.i),
        RM.identity.displayName(pid), tostring(result)))
      return
    end

    RM.bus.queue(pid, "race.split", result)
    if result.finished then
      RM.bus.queue(pid, "race.state", RM.race.wire(pid))
    end
  end)

  -- the FPS baseline every later delivery is measured against
  RM.bus.on("perf", function(pid, d)
    if type(d) ~= "table" then return end
    local perf = RM.store.load("perf", { runs = {} })
    local runs = perf.runs

    runs[#runs + 1] = {
      at      = os.time(),
      player  = RM.identity.displayName(pid),
      label   = tostring(d.label or "unlabelled"),
      seconds = tonumber(d.seconds) or 0,
      avg     = tonumber(d.avg) or 0,
      min     = tonumber(d.min) or 0,
      max     = tonumber(d.max) or 0,
      p1low   = tonumber(d.p1low) or 0,
      frames  = tonumber(d.frames) or 0,
      version = RM.VERSION,
    }

    -- keep the file from growing without a bound
    local over = #runs - RM.config.maxPerfRuns
    if over > 0 then
      for i = 1, #runs - over do runs[i] = runs[i + over] end
      for i = #runs - over + 1, #runs do runs[i] = nil end
    end

    RM.store.markDirty("perf")
    RM.store.flushNow("perf")
    RM.info(("FPS %s: avg %.1f, 1%% low %.1f, min %.1f, max %.1f over %ds"):format(
      tostring(d.label), tonumber(d.avg) or 0, tonumber(d.p1low) or 0,
      tonumber(d.min) or 0, tonumber(d.max) or 0, tonumber(d.seconds) or 0))
  end)
end

local function onInit()
  RM.util.startClock()

  RM.identity.init()
  RM.tracks.init()
  RM.store.load("perf", { runs = {} })

  local function every(ms) return math.max(1, math.floor(ms / RM.config.tickMs)) end
  rosterEvery = every(RM.config.rosterMs)
  saveEvery   = every(RM.config.autosaveMs)
  helloEvery  = every(5000)

  RM.bus.init()
  wireChannels()
  RM.handler(TICK, onTick)

  -- same reason as the register guard: a reload would leave the old timer running
  MP.CancelEventTimer(TICK)
  MP.CreateEventTimer(TICK, RM.config.tickMs)

  RM.info(("Race Manager %s ready. tick %dms, roster %dms, autosave %dms")
    :format(RM.VERSION, RM.config.tickMs, RM.config.rosterMs, RM.config.autosaveMs))
  if RM.roles.countOwners() == 0 then
    RM.warn("no owner set yet. type: rm role <name> owner")
  end
  RM.info("console: rm help")
end

RM.handler("onInit",             onInit)
RM.handler("onPlayerJoining",    onPlayerJoining)
RM.handler("onPlayerDisconnect", onPlayerDisconnect)
RM.handler("onShutdown",         onShutdown)
RM.handler("onVehicleSpawn",     onVehicleSpawn)
RM.handler("onVehicleReset",     onVehicleReset)
RM.handler("onVehicleEdited",    onVehicleEdited)
RM.handler("onVehicleDeleted",   onVehicleDeleted)
RM.handler("onConsoleInput",     function(input) return RM.console.handle(input) end)
