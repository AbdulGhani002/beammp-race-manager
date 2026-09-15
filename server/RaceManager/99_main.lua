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
    if ticks % rosterEvery == 0 then RM.serverconfig.tick(RM.config.rosterMs / 1000) end
    return
  end

  if ticks % rosterEvery == 0 then pcall(RM.players.sample) end
  if ticks % (rosterEvery * 8) == 0 and RM.players.flushStats then pcall(RM.players.flushStats) end
  if ticks % (rosterEvery * 4) == 0 and RM.live then
    pcall(function() RM.live.writeRoster() end)
    pcall(function() RM.live.writeChallenges() end)
  end
  if ticks % (rosterEvery * 20) == 0 and RM.live and RM.live.writeDrivers then
    pcall(function() RM.live.writeDrivers() end)
  end

  RM.players.tick()

  -- a team whose cars stopped matching, and offers nobody answered
  if ticks % rosterEvery == 0 then RM.team.tick() end
  if ticks % rosterEvery == 0 then RM.stella.tick() end
  if ticks % rosterEvery == 0 then RM.copilot.tick() end
  if ticks % rosterEvery == 0 then RM.challenges.tick() end

  -- a hold that has run its course, so the game can do the job
  RM.service.tick(RM.now())

  -- the clock probe rides the batch that is already going out
  if ticks % rosterEvery == 0 then
    for pid, s in pairs(RM.identity.sessions()) do
      if s.hello then RM.clock.maybeProbe(pid, s) end
    end

    for pid, sess in pairs(RM.identity.sessions()) do
      local verdict = RM.zones.sample(pid, sess.speed)
      if verdict == "warn" or verdict == "charged" then
        local zw = {
          charged = verdict == "charged",
          zone = RM.zones.wire(pid),
        }
        RM.bus.queue(pid, "zone.warn", zw)
        if verdict == "charged" then
          RM.bus.queue(pid, "race.state", RM.race.wire(pid))
        end
      end
    end

    local ended = RM.race.sweep()
    if ended then
      for i = 1, #ended do
        local pid = ended[i]
        RM.bus.queue(pid, "race.state", RM.race.wire(pid))
        RM.results.onRunEnded(pid)
        RM.race.clear(pid)
      end
    end
  end

  -- the live board, once to everybody on a course that changed this tick
  RM.race.pushBoards()

  RM.bus.flush()

  if ticks % saveEvery  == 0 then RM.store.flushDirty() end
  if ticks % helloEvery == 0 then RM.identity.checkHello() end
  if ticks % rosterEvery == 0 then RM.identity.tick(RM.config.rosterMs / 1000) end
  if ticks % rosterEvery == 0 then RM.serverconfig.tick(RM.config.rosterMs / 1000) end
end

local function onPlayerJoining(pid)
  -- checked before anything is written down for them, so a banned account
  -- does not get a fresh record every time it knocks
  if RM.mod.turnAway(pid) then return end

  local s = RM.identity.onJoin(pid)
  RM.players.onJoin(pid)
  RM.info(("player %d joining: %s / role %s / %s"):format(
    pid, s.key, s.role, s.name and ("named " .. s.name) or "no display name yet"))
end

local function onPlayerDisconnect(pid)
  -- the run has to be read before it is thrown away, or whoever is still on
  -- track waits forever for somebody who is not coming back
  RM.race.onLeave(pid)
  RM.results.onRunEnded(pid)
  RM.team.forget(pid)
  RM.copilot.forget(pid)
  RM.stella.forget(pid)
  RM.race.clear(pid)
  RM.results.forget(pid)
  RM.service.forget(pid)
  RM.lobby.forget(pid)
  RM.players.onLeave(pid)
  RM.identity.onLeave(pid)
  RM.bus.forget(pid)
end

local function onShutdown()
  RM.info(("shutting down, wrote %d store(s)"):format(RM.store.flushAll()))
end

-- the speed reading needs to know which vehicle to look at, and BeamMP has no
-- currently-driving flag. the newest one they touched is the best available.
local function onVehicleSpawn(pid, vid, data)
  RM.players.onVehicle(pid, vid, data)
  -- whoever is watching this driver is pointed at the new car
  if RM.copilot then RM.copilot.onVehicle(pid) end
end
local function onVehicleReset(pid, vid, data) RM.players.onVehicle(pid, vid, data) end
local function onVehicleEdited(pid, vid, data)
  RM.players.onVehicle(pid, vid, data)
  -- swapping the car out from under a team is how a team stops matching
  if RM.team then RM.team.recheck(pid) end
  if RM.copilot then RM.copilot.onVehicle(pid) end
end
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
    pcall(function() RM.tracks.sendList(pid) end)
    pcall(function() RM.tracks.sendDraft(pid) end)
    pcall(function() RM.bus.queue(pid, "race.lobbies", RM.lobby.list()) end)
    pcall(function() RM.challenges.sendList(pid) end)
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
  RM.bus.on("track.refit",  function(pid, d) reply(pid, "refit",  RM.tracks.refit(pid, d)) end)
  RM.bus.on("track.start",  function(pid, d) reply(pid, "start",  RM.tracks.setStart(pid, d)) end)
  RM.bus.on("track.finish", function(pid)    reply(pid, "finish", RM.tracks.finishCapture(pid)) end)
  RM.bus.on("track.cancel", function(pid)    reply(pid, "cancel", RM.tracks.cancelCapture(pid)) end)

  RM.bus.on("track.delete", function(pid, d)
    reply(pid, "delete", RM.tracks.deleteTrack(pid, type(d) == "table" and d.id or d))
  end)

  RM.bus.on("track.get", function(pid, d)
    RM.tracks.sendTrack(pid, type(d) == "table" and d.id or d)
  end)

  -- XP and challenge tracking, on or off for yourself. off means practice
  -- that touches nothing: no XP, no challenge times.
  RM.bus.on("options.tracking", function(pid, d)
    local s = RM.identity.session(pid)
    local rec = s and RM.identity.record(s.key)
    if not rec then
      RM.bus.queue(pid, "options.result", { action = "tracking", ok = false, reason = "no_session" })
      return
    end
    local on = not (type(d) == "table" and d.on == false)
    -- false has to be stored as false: "x and false or nil" is nil in lua
    if on then rec.tracking = nil else rec.tracking = false end
    RM.identity.markDirty()
    RM.identity.sendMe(pid)
    RM.bus.queue(pid, "options.result", { action = "tracking", ok = true, value = on })
    RM.info(("%s turned XP and challenge tracking %s"):format(RM.identity.displayName(pid), on and "on" or "off"))
  end)

  -- watching another driver
  local function copilotReply(pid, ok, result)
    if ok then return end
    RM.bus.queue(pid, "copilot.failed", { why = result })
  end
  RM.bus.on("copilot.offer", function(pid, d)
    local target = type(d) == "table" and tonumber(d.to) or nil
    if target == nil or not RM.identity.session(target) then
      copilotReply(pid, false, "not_here")
      return
    end
    copilotReply(pid, RM.copilot.offer(pid, target, type(d) == "table" and d.kind or "invite"))
  end)
  RM.bus.on("copilot.accept",  function(pid) copilotReply(pid, RM.copilot.accept(pid)) end)
  RM.bus.on("copilot.decline", function(pid) copilotReply(pid, RM.copilot.decline(pid)) end)
  RM.bus.on("copilot.stop",    function(pid) copilotReply(pid, RM.copilot.stop(pid)) end)
  RM.bus.on("copilot.get", function(pid)
    local s = RM.identity.session(pid)
    RM.bus.queue(pid, "copilot.state", RM.copilot.wire(s and s.key))
  end)

  -- challenges: the board for everybody, the tools for admins
  local function challengeReply(pid, action, ok, result)
    RM.bus.queue(pid, "challenge.result", {
      action = action, ok = ok and true or false,
      reason = (not ok) and result or nil,
      id = ok and type(result) == "table" and result.id or nil,
    })
  end
  RM.bus.on("challenges.get",   function(pid) RM.challenges.sendList(pid) end)
  RM.bus.on("challenge.create", function(pid, d) challengeReply(pid, "create", RM.challenges.create(pid, d)) end)
  RM.bus.on("challenge.update", function(pid, d) challengeReply(pid, "update", RM.challenges.update(pid, d)) end)
  RM.bus.on("challenge.delete", function(pid, d)
    challengeReply(pid, "delete", RM.challenges.delete(pid, type(d) == "table" and d.id or d))
  end)
  RM.bus.on("challenge.end", function(pid, d)
    challengeReply(pid, "end", RM.challenges.endNow(pid, type(d) == "table" and d.id or d))
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
    if not ok then
      RM.bus.queue(pid, "race.result", { ok = false, reason = result })
      return
    end

    -- your own car is the one that races, so watching somebody else ends
    RM.copilot.onRaceArmed(pid)

    -- whatever they were entered for before, they are not in it now
    RM.results.forget(pid)
    RM.results.join(pid, result.track)
    RM.bus.queue(pid, "race.state", RM.race.wire(pid))

    local track = RM.tracks.get(result.track)
    if track and track.start then
      RM.bus.queue(pid, "race.teleport", RM.tracks.gridFor(track))
    end
  end)

  RM.bus.on("race.end", function(pid)
    local ok = RM.race.endRace(pid)
    if not ok then return end
    if RM.service.busy(pid) then
      RM.info(("%s ended the run with a job still held; the job is dropped"):format(
        RM.identity.displayName(pid)))
    end
    RM.service.forget(pid)
    RM.bus.queue(pid, "race.state", RM.race.wire(pid))
    RM.results.onRunEnded(pid)
    RM.race.clear(pid)
  end)

  -- the results screen is closed, so the run it was showing can go
  RM.bus.on("race.clear", function(pid)
    RM.race.clear(pid)
    RM.results.forget(pid)
    RM.bus.queue(pid, "race.state", RM.race.wire(pid))
  end)

  -- a crossing, stamped by the client at the frame the trigger fired. the
  -- server decides what that stamp is worth.
  RM.bus.on("cp.hit", function(pid, d)
    if type(d) ~= "table" then return end
    if not RM.identity.session(pid) then return end
    -- A passenger is in the car; their client must not count gates.
    local sess = RM.identity.session(pid)
    if sess and RM.copilot and RM.copilot.watchingOf and RM.copilot.watchingOf(sess.key) then
      return
    end

    local ok, result = RM.race.gate(pid, d.i, tonumber(d.t))
    if not ok then
      RM.debug(("gate %s from %s: %s"):format(tostring(d.i),
        RM.identity.displayName(pid), tostring(result)))
      return
    end

    RM.bus.queue(pid, "race.split", result)
    if result.finished then
      RM.bus.queue(pid, "race.state", RM.race.wire(pid))
      RM.results.onRunEnded(pid)
    end
  end)

  -- lobby changes fan out to everyone in it, and the list of open races to
  -- everybody on the server
  local function lobbyFan(l)
    if not l then return end
    for member in pairs(l.members) do
      RM.bus.queue(member, "race.lobby", RM.lobby.wire(member))
    end
  end

  local function lobbyList()
    RM.bus.broadcast("race.lobbies", RM.lobby.list())
  end

  -- A race is somewhere as well as something. Whoever makes one or joins
  -- one is put on the grid there and then, in the seat they got, so the cars
  -- gather behind the line while the rest turn up rather than at Start.
  local function seatOnGrid(pid, lobby)
    local track = RM.tracks.get(lobby.track)
    if not track or not track.start then return end
    local seat = tonumber(lobby.joined[pid]) or 1
    RM.bus.queue(pid, "race.teleport", RM.tracks.gridSpot(track, seat - 1))
  end

  RM.bus.on("race.create", function(pid, d)
    local ok, result = RM.lobby.create(pid, d)
    if not ok then
      RM.bus.queue(pid, "race.result", { ok = false, reason = result })
      return
    end
    RM.bus.queue(pid, "race.lobby", RM.lobby.wire(pid))
    seatOnGrid(pid, result)
    lobbyList()
  end)

  RM.bus.on("race.join", function(pid, d)
    local ok, result = RM.lobby.join(pid, type(d) == "table" and d.id or d)
    if not ok then
      RM.bus.queue(pid, "race.result", { ok = false, reason = result })
      return
    end
    lobbyFan(result)
    seatOnGrid(pid, result)
    lobbyList()
  end)

  RM.bus.on("race.invite", function(pid, d)
    local ok, result = RM.lobby.invite(pid, type(d) == "table" and d.who or d)
    if not ok then
      RM.bus.queue(pid, "race.result", { ok = false, reason = result })
      return
    end
    lobbyFan(result)
  end)

  RM.bus.on("race.leave", function(pid)
    local ok, result = RM.lobby.leave(pid)
    if not ok then return end
    RM.bus.queue(pid, "race.lobby", nil)
    lobbyFan(result)
    lobbyList()
  end)

  RM.bus.on("race.start", function(pid)
    local ok, result, order = RM.lobby.start(pid)
    if not ok then
      RM.bus.queue(pid, "race.result", { ok = false, reason = result })
      return
    end

    local track = RM.tracks.get(result.track)

    -- Whoever qualified quickest starts at the front. Without a qualifying
    -- session on this course the order is the order they joined, as before.
    order = RM.lobby.gridOrder(result.track, order)

    for i, member in ipairs(order) do
      RM.results.forget(member)
      local armed = RM.race.arm(member,
        { id = result.track, mode = result.mode, laps = result.laps,
          class = result.class,
          official = result.official,
          officialName = result.officialName })
      if armed then
        RM.results.join(member, result.track)
        RM.bus.queue(member, "race.lobby", nil)
        RM.bus.queue(member, "race.state", RM.race.wire(member))
        if track and track.start then
          RM.bus.queue(member, "race.teleport", RM.tracks.gridSpot(track, i - 1))
        end
      end
    end
    lobbyList()
  end)

  -- the pit is a place, and the client says when the car is in it
  RM.bus.on("pit.state", function(pid, d)
    local inside = type(d) == "table" and d.inside == true
    local ok = RM.race.setPit(pid, inside)
    if ok then RM.bus.queue(pid, "race.state", RM.race.wire(pid)) end
  end)

  RM.bus.on("track.pit", function(pid, d)
    reply(pid, "pit", RM.tracks.markPit(pid, d))
  end)

  RM.bus.on("track.pitundo", function(pid)
    reply(pid, "pitundo", RM.tracks.undoPit(pid))
  end)

  RM.bus.on("track.sz", function(pid, d)
    reply(pid, "sz", RM.tracks.markSpeedZone(pid, d))
  end)
  RM.bus.on("track.szundo", function(pid)
    reply(pid, "szundo", RM.tracks.undoSpeedZone(pid))
  end)
  RM.bus.on("track.szsize", function(pid, d)
    reply(pid, "sz", RM.tracks.setSzSize(pid, d))
  end)
  local function watching(pid)
    local s = RM.identity.session(pid)
    return s and RM.copilot and RM.copilot.watchingOf and RM.copilot.watchingOf(s.key)
  end
  RM.bus.on("sz.hit", function(pid, d)
    if watching(pid) then return end
    local i = type(d) == "table" and tonumber(d.i) or nil
    if not i then return end
    local what = RM.zones.onSzHit(pid, i)
    if what then
      RM.bus.queue(pid, "zone.warn", { charged = false, event = what, zone = RM.zones.wire(pid) })
    end
  end)
  RM.bus.on("sz.state", function(pid, d)
    if watching(pid) then return end
    local inside = type(d) == "table" and d.inside == true
    local mph = type(d) == "table" and tonumber(d.mph) or nil
    -- a car whose copy of the box carries no limit still gets judged: the
    -- server holds the same box and can look it up by its number
    if inside and not mph then
      local i = type(d) == "table" and tonumber(d.i) or nil
      local g = i and RM.zones.szGate((RM.race.get(pid) or {}).track, i) or nil
      mph = g and tonumber(g.mph) or nil
    end
    local what = RM.zones.onSzState(pid, inside, mph)
    if what then
      RM.bus.queue(pid, "zone.warn", { charged = false, event = what, zone = RM.zones.wire(pid) })
    end
  end)

  RM.bus.on("profile.get", function(pid, d)
    local key = type(d) == "table" and tostring(d.key or d.id or "") or tostring(d or "")
    if key == "" then
      local s = RM.identity.session(pid)
      key = s and s.key or ""
    end
    -- clicking a roster row sends a live player id
    local asPid = tonumber(key)
    if asPid and RM.identity.session(asPid) then
      local s = RM.identity.session(asPid)
      key = s.key
    end
    if (not key or key == "" or not RM.identity.record(key)) and type(d) == "table" and d.name then
      key = RM.identity.keyForName(tostring(d.name)) or key
    end
    RM.bus.queue(pid, "profile.data", RM.players.profile(key))
  end)
  RM.bus.on("profile.list", function(pid)
    local list = {}
    local all = RM.identity.all() or {}
    for key, rec in pairs(all) do
      if type(rec) == "table" and rec.name and rec.name ~= "" then
        list[#list + 1] = {
          key = key, name = rec.name, level = rec.level or 1,
          xp = rec.xp or 0, role = rec.role,
        }
      end
    end
    table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
    RM.bus.queue(pid, "profile.list", list)
  end)

  RM.bus.on("track.zones", function(pid, d)
    reply(pid, "zones", RM.tracks.setZones(pid, d))
  end)

  -- the bottom bar. one request in, a hold and then the job back out.
  RM.bus.on("service.use", function(pid, d)
    local ok, result = RM.service.use(pid, d)
    if not ok then
      RM.bus.queue(pid, "service.failed", {
        which = type(d) == "table" and d.which or nil, why = result })
      return
    end
    RM.bus.queue(pid, "service.hold", {
      which = result.which, hold = result.hold, penalty = result.cost })
    -- the clock on screen carries the penalty, so it has to hear about it now
    if result.cost then RM.bus.queue(pid, "race.state", RM.race.wire(pid)) end
  end)

  RM.bus.on("service.done", function(pid, d)
    local ok, job, why = RM.service.report(pid, d)
    if not ok or not job then return end
    if why then
      RM.bus.queue(pid, "service.failed", { which = job.which, why = why })
      if job.cost then RM.bus.queue(pid, "race.state", RM.race.wire(pid)) end
    end
  end)

  -- Team. Invite somebody into your car, or ask to get into theirs. The rule
  -- that both are in the same model is checked when it is offered and again
  -- when it is taken up, because cars change while an offer sits waiting.
  RM.bus.on("team.offer", function(pid, d)
    if type(d) ~= "table" then return end
    local target = math.floor(tonumber(d.who) or -1)
    if not RM.identity.session(target) then
      RM.bus.queue(pid, "team.failed", { why = "not_here" })
      return
    end
    local ok, why = RM.team.offer(pid, target, d.kind)
    if not ok then RM.bus.queue(pid, "team.failed", { why = why }) end
  end)

  RM.bus.on("team.accept", function(pid)
    local ok, why = RM.team.accept(pid)
    if not ok then RM.bus.queue(pid, "team.failed", { why = why }) end
  end)

  RM.bus.on("team.decline", function(pid) RM.team.decline(pid) end)

  RM.bus.on("team.leave", function(pid)
    local ok, why = RM.team.leave(pid)
    if not ok then RM.bus.queue(pid, "team.failed", { why = why }) end
  end)

  RM.bus.on("team.get", function(pid)
    local s = RM.identity.session(pid)
    RM.bus.queue(pid, "team.state", RM.team.wire(s and s.key or nil))
  end)

  -- The Stella box. A stopped car, and asking the car in front to let you by.
  -- The client only ever says what it wants; who is where is decided here.
  RM.bus.on("stella.breakdown.set", function(pid, d)
    RM.stella.setBreakdown(pid, type(d) == "table" and d.active == true)
  end)

  RM.bus.on("stella.pass.request", function(pid)
    RM.stella.requestPass(pid)
  end)

  -- the unit's word on itself: !stella during a race, and each change of
  -- its light with why, so a race that showed the wrong thing reads here
  RM.bus.on("stella.report", function(pid, d)
    RM.info(("%s Stella: %s"):format(RM.identity.displayName(pid),
      tostring(type(d) == "table" and d.text or "")))
  end)
  RM.bus.on("stella.trace", function(pid, d)
    if RM.config.stellaTrace == false then return end
    RM.info(("%s Stella %s"):format(RM.identity.displayName(pid),
      tostring(type(d) == "table" and d.text or "")))
  end)
  RM.bus.on("stella.pass.accept", function(pid, d)
    local ok, why = RM.stella.acceptPass(pid, type(d) == "table" and d.requestId or nil)
    if not ok then
      RM.bus.queue(pid, "stella.pass.status", { state = "cancelled", reason = why })
    end
  end)

  RM.bus.on("records.get", function(pid, d)
    local id = type(d) == "table" and (d.id or "") or (d or "")
    local s = RM.identity.session(pid)
    local class = type(d) == "table" and d.class or nil
    RM.bus.queue(pid, "records.data", RM.records.wire(id, s and s.key or nil, class))
  end)

  local function staffReply(pid, action, ok, result)
    RM.bus.queue(pid, "staff.result", {
      action = action, ok = ok and true or false,
      reason = (not ok) and result or nil,
      name = ok and result or nil,
    })
  end
  RM.bus.on("staff.role", function(pid, d)
    local key = type(d) == "table" and d.key or nil
    local role = type(d) == "table" and d.role or nil
    staffReply(pid, "role", RM.roles.set(pid, key, role))
  end)
  RM.bus.on("staff.kick", function(pid, d)
    staffReply(pid, "kick", RM.mod.kick(pid, type(d) == "table" and d.key or d, type(d) == "table" and d.why or nil))
  end)
  RM.bus.on("staff.ban", function(pid, d)
    staffReply(pid, "ban", RM.mod.ban(pid, type(d) == "table" and d.key or d, type(d) == "table" and d.why or nil))
  end)
  RM.bus.on("staff.clearRecords", function(pid, d)
    staffReply(pid, "clearRecords", RM.records.clearDriver(pid, type(d) == "table" and d.key or d))
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
  RM.identity.readGate()
  pcall(function()
    if RM.xp and RM.xp.resyncLevels then RM.xp.resyncLevels() end
  end)
  RM.mod.init()
  RM.tracks.init()
  RM.challenges.init()
  RM.store.load("perf", { runs = {} })
  RM.serverconfig.check()

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
RM.handler("onPlayerAuth",       function(name, role, isGuest) return RM.identity.onAuth(name, role, isGuest) end)
RM.handler("onPlayerDisconnect", onPlayerDisconnect)
RM.handler("onShutdown",         onShutdown)
RM.handler("onVehicleSpawn",     onVehicleSpawn)
RM.handler("onVehicleReset",     onVehicleReset)
RM.handler("onVehicleEdited",    onVehicleEdited)
RM.handler("onVehicleDeleted",   onVehicleDeleted)
RM.handler("onConsoleInput",     function(input) return RM.console.handle(input) end)

-- !resetui in chat puts that player's windows back and asks their game for
-- the whole screen again. Returning 1 keeps it out of everybody's chat.
-- The Options window says !restoreui, so that spelling works too.
local RESET_WORDS = { ["!resetui"] = true, ["!restoreui"] = true, ["!fixui"] = true, ["!ui"] = true }
local STELLA_WORDS = { ["!stella"] = true, ["!stellatest"] = true }
local function onChatMessage(pid, name, message)
  local text = RM.util.tidy(message):lower()
  if RESET_WORDS[text] then
    RM.bus.queue(pid, "ui.reset", {})
    RM.info(("%s asked for their interface back with %s"):format(RM.identity.displayName(pid), text))
    return 1
  end
  -- !stella runs the unit through everything it can show, on that player's screen
  if STELLA_WORDS[text] then
    RM.bus.queue(pid, "stella.test", {})
    RM.info(("%s asked for a Stella test"):format(RM.identity.displayName(pid)))
    return 1
  end
  return nil
end
RM.handler("onChatMessage", onChatMessage)
