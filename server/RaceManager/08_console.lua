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
}

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
  else
    for i = 1, #HELP do say(HELP[i]) end
  end

  return table.concat(out, "\n")
end
