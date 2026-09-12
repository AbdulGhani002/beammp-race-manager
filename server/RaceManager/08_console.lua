RM = RM or {}
RM.console = {}

-- typed into the host panel console. that console is already behind the panel
-- login, so a line arriving here is the server owner by definition. it is the
-- only place a role can be granted, and it lets you check the plugin without
-- starting the game.

local HELP = {
  "rm status              plugin health, one line",
  "rm players             who is on, level, speed, ping, role",
  "rm tracks              saved courses",
  "rm track <id>          checkpoints for one course",
  "rm drafts              captures in progress",
  "rm role <name> <role>  owner | admin | staff | player",
  "rm forget <name>      drop a stored player, frees the display name",
  "rm claim <name>       give a stored name, and its role, to whoever just joined",
  "rm races               runs on track now, and who results are waiting on",
  "rm perf                recorded FPS runs",
  "rm save                write every store now",
  "rm zones <id>          the speed zones on a course",
  "rm zone <id> <from> <to> <mph>   add one, e.g. rm zone baja-1000 12 14 37",
  "rm zoneclear <id>      remove every zone from a course",
  "rm challenges          the challenges on the board",
  "rm challenge end <id>  end a challenge now",
  "rm challenge delete <id>  take a challenge off the board",
  "rm watching            who is watching whom",
  "rm kick <name> [why]   remove somebody now",
  "rm ban <name> [why]    remove them and turn them away next time",
  "rm unban <name>        lift a ban",
  "rm bans                who is banned, and why",
  "rm xp <name> <amount>  hand out experience, negative takes it back",
  "rm classes             the race classes, by division",
  "rm gatewidth <course> <metres>   widen every gate on a course",
  "rm square <course>     turn every gate to face along the course",
  "rm records <id> [class]  the board for a course, whole or one class",
}

-- The console is the server owner by definition, so it is not gated on a role
-- the way the in game path is. It still refuses to act on somebody who is not
-- there, because a typo should say so rather than do nothing quietly.
local function keyByName(name)
  if not name or name == "" then return nil end
  return RM.identity.keyForName(name)
end

local WHY_NOT = {
  not_allowed   = "you cannot do that",
  not_yourself  = "not on yourself",
  outranks_you  = "they rank as high as you or higher",
  already_banned = "already banned",
  not_here      = "they are not on the server",
  not_banned    = "not banned",
}

local function punish(say, what, name, why)
  local key = keyByName(name)
  if not key then say("no stored player called " .. tostring(name)) return end
  if why == "" then why = nil end

  -- the console has no player id behind it, so it acts as the owner it is
  local ok, got
  if what == "ban" then ok, got = RM.mod.banFromConsole(key, why)
  else ok, got = RM.mod.kickFromConsole(key, why) end

  if ok then say(("%s %s"):format(what == "ban" and "banned" or "kicked", tostring(got)))
  else say(WHY_NOT[got] or tostring(got)) end
end

local function unban(say, name)
  local key = keyByName(name)
  if not key then
    -- a banned account may have had its name freed, so the key itself works too
    key = name and RM.mod.isBanned(name) and name or nil
  end
  if not key then say("no ban on " .. tostring(name)) return end
  local ok, got = RM.mod.unban(key)
  say(ok and ("ban lifted on " .. tostring(got)) or (WHY_NOT[got] or tostring(got)))
end

local function banLines(say)
  local n = 0
  for key, b in pairs(RM.mod.all()) do
    n = n + 1
    say(("%s: %s (by %s)"):format(
      tostring(b.name or key), tostring(b.why or "no reason given"),
      tostring(b.byName or "console")))
  end
  if n == 0 then say("nobody is banned") end
end

local function giveXp(say, name, amount)
  local key = keyByName(name)
  if not key then say("no stored player called " .. tostring(name)) return end
  local total, level = RM.xp.give(key, tonumber(amount), "granted")
  if not total then say(WHY_NOT[level] or tostring(level)) return end
  say(("%s now has %d xp, level %d"):format(tostring(name), total, level))
end

local function statusLines(say)
  local s = RM.bus.stats()
  say(("v%s | players %d | uptime %.0fs | tracks %d")
    :format(RM.VERSION, MP.GetPlayerCount(), RM.now(), RM.tracks.countTracks()))
  say(("bus sent %d recv %d dropped %d refused %d | handler errors %d")
    :format(s.sent, s.recv, s.dropped, s.refused, RM.util.handlerErrorCount()))
  say(("lua memory %.1f KB | pooled tables %d | roster watchers %d")
    :format(MP.GetStateMemoryUsage() / 1024, RM.util.poolSize(), RM.players.subscriberCount()))
  if RM.roles.countOwners() == 0 then
    say("no owner yet. run: rm role <name> owner")
  end
end

local function playerLines(say)
  local n = 0
  for pid, row in pairs(RM.players.roster()) do
    n = n + 1
    say(("  %-3d %-20s lvl %-3d %3d mph  %4s ms  %-6s%s"):format(
      pid, row.name, row.level, row.speed,
      row.ping >= 0 and tostring(row.ping) or "-", row.role,
      row.guest and "  (guest, unranked)" or ""))
  end
  if n == 0 then say("  nobody connected") end
end

local function trackLines(say)
  local n = 0
  for _, t in pairs(RM.tracks.summary()) do
    n = n + 1
    say(("  %-24s %-11s %-22s %3d checkpoints%s"):format(
      t.id, t.kind, t.level, t.count, t.circuit and "  (circuit)" or ""))
  end
  if n == 0 then say("  no courses captured yet") end
end

local function trackDetail(say, id)
  local t = RM.tracks.get(id)
  if not t then say("  no course with that id") return end
  say(("%s (%s) on %s, %d checkpoints%s"):format(
    t.name, t.kind, t.level, #t.checkpoints, t.circuit and ", circuit" or ""))
  if t.start then
    say(("  start  %8.1f %8.1f %8.1f  yaw %.2f"):format(
      t.start.pos.x, t.start.pos.y, t.start.pos.z, t.start.yaw))
  end
  for i = 1, #t.checkpoints do
    local cp = t.checkpoints[i]
    say(("  %3d    %8.1f %8.1f %8.1f  yaw %.2f  gate %.0fx%.0fx%.0f"):format(
      i, cp.pos.x, cp.pos.y, cp.pos.z, cp.yaw, cp.size.w, cp.size.h, cp.size.d))
  end
end

local function draftLines(say)
  local n = 0
  for key, d in pairs(RM.store.get("trackdrafts") or {}) do
    n = n + 1
    say(("  %-28s %-20s %s  %d checkpoints"):format(key, d.id, d.kind, #d.checkpoints))
  end
  if n == 0 then say("  no captures in progress") end
end

local function perfLines(say)
  local perf = RM.store.get("perf")
  local runs = perf and perf.runs or {}
  if #runs == 0 then say("  no FPS runs recorded yet") return end
  for i = math.max(1, #runs - 19), #runs do
    local r = runs[i]
    say(("  %-16s %-18s avg %6.1f  1%% low %6.1f  min %6.1f  max %6.1f  %ds"):format(
      os.date("%Y-%m-%d %H:%M", r.at), r.label, r.avg, r.p1low, r.min, r.max, r.seconds))
  end
end

local function setRole(say, name, role)
  if not name or not role then say("  usage: rm role <name> <owner|admin|staff|player>") return end
  local key = RM.identity.keyForName(name)
  if not key then say("  nobody by that display name has ever joined") return end
  local ok, result = RM.roles.setFromConsole(key, role)
  if ok then
    say(("  %s is now %s"):format(name, result))
  else
    say("  " .. tostring(result))
  end
end

local function claim(say, rest)
  local id, name = rest:match("^claim%s+(%d+)%s+(.+)%s*$")
  local pid = tonumber(id)

  if not pid then
    name = rest:match("^claim%s+(.+)%s*$")
    local waiting = RM.identity.unnamed()
    if #waiting == 0 then
      say("  nobody is connected without a name")
      return
    elseif #waiting > 1 then
      say("  more than one player has no name yet, so say which:")
      for _, p in ipairs(waiting) do
        say(("    rm claim %d <name>   (%s)"):format(p, RM.identity.displayName(p)))
      end
      return
    end
    pid = waiting[1]
  end

  if not name then say("  usage: rm claim <name>   or   rm claim <id> <name>") return end

  local ok, result = RM.identity.claim(pid, name)
  if not ok then
    say("  " .. tostring(result))
    return
  end

  RM.players.onNameChanged(pid)
  RM.players.onRoleChanged(pid)
  RM.identity.sendMe(pid)
  say(("  player %d is now %s, role %s"):format(pid, result, RM.roles.of(pid)))
end

local function raceLines(say)
  local n = 0
  RM.race.forEach(function(pid, r)
    n = n + 1
    local when = r.startedAt and (RM.now() - r.startedAt) or 0
    say(("  %-20s %-14s %-9s lap %d/%d  gate %d/%d  %6.1fs  %d penalty%s%s"):format(
      RM.identity.displayName(pid), r.track, r.state,
      r.currentLap, r.laps, math.min(r.nextGate, r.gates), r.gates, when,
      #r.penalties, #r.penalties == 1 and "" or "s",
      r.suspect and "  (marked)" or ""))
  end)
  if n == 0 then say("  nobody is racing") end

  local heats = 0
  for track in pairs(RM.results.heats()) do
    heats = heats + 1
    local left = RM.results.waitingOn(track)
    say(("  heat %s: %s"):format(track,
      left and ("waiting on " .. left) or "everyone is in, results go out next tick"))
  end
  if heats == 0 then say("  no heat open") end
end

local function forget(say, name)
  if not name then say("  usage: rm forget <name>") return end
  local key = RM.identity.keyForName(name)
  if not key then say("  nobody by that display name has ever joined") return end
  local ok, why = RM.identity.forget(key)
  if ok then
    say(("  forgot %s, the name is free again"):format(name))
  else
    say("  " .. tostring(why))
  end
end

-- The classes his bot announces. Printed here so whoever is running the
-- server can read the exact spelling the race screen wants.
local function classLines(say)
  local list = RM.records.classList()
  if #list == 0 then say("no classes are set") return end
  local division = nil
  for i = 1, #list do
    local c = list[i]
    if c.division ~= division then
      division = c.division
      say((division and tostring(division) or "Other") .. " division")
    end
    say("  " .. c.name)
  end
  say(("%d class(es)"):format(#list))
end

local function recordLines(say, id, class)
  if not id then say("  usage: rm records <course> [class]") return end
  local track = RM.tracks.get(id)
  if not track then say("no course called " .. tostring(id)) return end

  if class and class ~= "" and not RM.records.isClass(class) then
    say("no class called " .. class .. ". try rm classes")
    return
  end

  local w = RM.records.wire(track.id, nil, class)
  local shown = false
  for mode, board in pairs(w.modes) do
    if #board.top > 0 then
      shown = true
      say(("%s%s, %d run(s)"):format(mode, class and (" in " .. class) or "", board.total))
      for i = 1, #board.top do
        local r = board.top[i]
        say(("  %d. %-20s %8.3f%s"):format(
          r.pos, tostring(r.name), r.corrected, r.class and ("  " .. r.class) or ""))
      end
    end
  end
  if not shown then say("nothing on the board yet") end
  if #w.classes > 0 then
    say("classes raced here: " .. table.concat(w.classes, ", "))
  end
end

function RM.console.handle(input)
  if type(input) ~= "string" then return end
  local rest = input:match("^%s*rm%s+(.*)$")
  if not rest then return end

  local cmd, a, b = rest:match("^(%S+)%s*(%S*)%s*(%S*)")
  if not cmd then return end

  local out = {}
  local function say(s) out[#out + 1] = s end

  if cmd == "status" then
    statusLines(say)
  elseif cmd == "players" then
    playerLines(say)
  elseif cmd == "tracks" then
    trackLines(say)
  elseif cmd == "track" then
    trackDetail(say, a)
  elseif cmd == "drafts" then
    draftLines(say)
  elseif cmd == "perf" then
    perfLines(say)
  elseif cmd == "races" or cmd == "race" then
    raceLines(say)
  elseif cmd == "role" then
    local name, role = rest:match("^role%s+(.+)%s+(%S+)%s*$")
    setRole(say, name, role)
  elseif cmd == "claim" then
    claim(say, rest)
  elseif cmd == "forget" then
    local name = rest:match("^forget%s+(.+)%s*$")
    forget(say, name)
  elseif cmd == "save" then
    say(("wrote %d store(s)"):format(RM.store.flushAll()))
  elseif cmd == "kick" then
    local name, why = rest:match("^kick%s+(%S+)%s*(.*)$")
    punish(say, "kick", name, why)
  elseif cmd == "ban" then
    local name, why = rest:match("^ban%s+(%S+)%s*(.*)$")
    punish(say, "ban", name, why)
  elseif cmd == "unban" then
    local name = rest:match("^unban%s+(.+)%s*$")
    unban(say, name)
  elseif cmd == "bans" then
    banLines(say)
  elseif cmd == "xp" then
    local name, amount = rest:match("^xp%s+(%S+)%s+(-?%d+)%s*$")
    giveXp(say, name, amount)
  elseif cmd == "classes" then
    classLines(say)
  elseif cmd == "records" then
    local id, class = rest:match("^records%s+(%S+)%s*(.*)$")
    recordLines(say, id, class ~= "" and class or nil)
  elseif cmd == "zones" then
    local id = rest:match("^zones%s+(%S+)%s*$")
    local track = id and RM.tracks.get(id)
    if not track then
      say("no course called " .. tostring(id))
    else
      local zones = type(track.zones) == "table" and track.zones or {}
      if #zones == 0 then say("no zones on " .. track.id) end
      for i = 1, #zones do
        local z = zones[i]
        say(("%d: gates %d to %d, %d mph"):format(i, z.from, z.to, z.mph))
      end
    end
  elseif cmd == "zone" then
    local id, from, to, mph = rest:match("^zone%s+(%S+)%s+(%d+)%s+(%d+)%s+(%d+)%s*$")
    local track = id and RM.tracks.get(id)
    if not track then
      say("rm zone <course> <from> <to> <mph>")
    else
      local zones = type(track.zones) == "table" and track.zones or {}
      zones[#zones + 1] = { from = tonumber(from), to = tonumber(to), mph = tonumber(mph) }
      local ok, why = RM.tracks.setZonesDirect(track.id, zones)
      if ok then say(("zone added: gates %s to %s at %s mph"):format(from, to, mph))
      else say("could not add it: " .. tostring(why)) end
    end
  elseif cmd == "square" then
    local id = rest:match("^square%s+(%S+)%s*$")
    if not id then
      say("  usage: rm square <course>. gates face the way the car pointed when marked;")
      say("  this turns every one along the course instead, for a course captured sideways")
    else
      local ok, got = RM.tracks.squareAll(id)
      if ok then say(("%d of %d gate(s) on %s turned to face along the course"):format(got.turned, got.gates, got.id))
      else say("could not do it: " .. tostring(got)) end
    end
  elseif cmd == "gatewidth" then
    local id, w = rest:match("^gatewidth%s+(%S+)%s+([%d%.]+)%s*$")
    if not id then
      say("  usage: rm gatewidth <course> <metres>, e.g. rm gatewidth baja-1000 34")
    else
      local ok, got = RM.tracks.setWidthDirect(id, w)
      if ok then
        say(("%d gate(s) on %s are now %s metres across"):format(got.gates, got.id, got.w))
        say("drivers pick it up when they next open the course")
      else
        say("could not do it: " .. tostring(got))
      end
    end
  elseif cmd == "challenges" then
    local rows = RM.challenges.wire(nil)
    if #rows == 0 then say("no challenges") end
    for _, c in ipairs(rows) do
      say(("%s  %s  %s  %s  %d lap(s)  %d tier(s)  %d entered  %s"):format(
        c.id, c.kind, c.state, c.track, c.laps, #(c.tiers or {}), c.entered or 0,
        c.state == "live" and (("%dh left"):format(math.floor(c.secondsLeft / 3600)))
          or (c.state == "scheduled" and (("starts in %dh"):format(math.floor(c.startsIn / 3600))) or "over")))
    end
  elseif cmd == "challenge" then
    local what, id = rest:match("^challenge%s+(%a+)%s+(%S+)%s*$")
    local c = id and RM.challenges.get(id)
    if not what or not c then
      say("rm challenge end <id>  or  rm challenge delete <id>")
    elseif what == "end" then
      c.endsAt = RM.challenges.clock()
      RM.store.markDirty("challenges") RM.store.flushNow("challenges")
      RM.challenges.broadcastList()
      say("challenge " .. id .. " ended")
    elseif what == "delete" then
      RM.challenges.all()[id] = nil
      RM.store.markDirty("challenges") RM.store.flushNow("challenges")
      RM.challenges.broadcastList()
      say("challenge " .. id .. " deleted")
    else
      say("rm challenge end <id>  or  rm challenge delete <id>")
    end
  elseif cmd == "watching" then
    local n = 0
    for pid in pairs(RM.identity.sessions()) do
      local s = RM.identity.session(pid)
      local d = s and RM.copilot.watchingOf(s.key)
      if d then
        n = n + 1
        say(("%s is watching %s"):format(RM.identity.displayName(pid),
          RM.identity.displayName(RM.identity.pidForKey(d) or -1)))
      end
    end
    if n == 0 then say("nobody is watching anybody") end
  elseif cmd == "zoneclear" then
    local id = rest:match("^zoneclear%s+(%S+)%s*$")
    local ok, why = id and RM.tracks.setZonesDirect(id, {})
    if ok then say("zones cleared from " .. id)
    else say("could not clear: " .. tostring(why)) end
  else
    for i = 1, #HELP do say(HELP[i]) end
  end

  return table.concat(out, "\n")
end
