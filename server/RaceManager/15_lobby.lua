RM = RM or {}
RM.lobby = {}

-- A race you make and other people join, instead of a run that arms itself
-- the moment you pick a course. Nothing is live until the host presses Start
-- Race, and then each driver's clock still starts at their own crossing of
-- the line, which is what keeps the timing fair.

local lobbies = {}   -- id -> lobby
local seq = 0

local function keyOf(pid)
  local s = RM.identity.session(pid)
  return s and s.key or nil
end

local function shortId()
  seq = seq + 1
  return tostring(seq)
end

function RM.lobby.of(pid)
  for _, l in pairs(lobbies) do
    if l.members[pid] then return l end
  end
  return nil
end

function RM.lobby.get(id)
  return lobbies[tostring(id or "")]
end

-- joined order decides grid spots and who inherits a race the host walks
-- out of
local function memberList(l)
  local out = {}
  for pid in pairs(l.members) do out[#out + 1] = pid end
  table.sort(out, function(a, b) return l.joined[a] < l.joined[b] end)
  return out
end

function RM.lobby.create(pid, d)
  if type(d) ~= "table" then return false, "bad_request" end
  if not RM.identity.session(pid) then return false, "no_session" end
  if RM.lobby.of(pid) then return false, "already_in_one" end

  local track = RM.tracks.get(tostring(d.track or ""))
  if not track then return false, "no_such_track" end
  if #track.checkpoints < 2 then return false, "course_too_short" end

  -- one race per course. two lobbies on one course would fight over the grid
  -- and the results table.
  for _, l in pairs(lobbies) do
    if l.track == track.id then return false, "course_in_use" end
  end

  local laps = math.floor(tonumber(d.laps) or 1)
  if laps < 1 or laps > 99 then return false, "bad_laps" end
  if not track.circuit and laps > 1 then return false, "not_a_circuit" end

  -- One class for the race, set by whoever made it, the way his bot announces
  -- them. Everybody who joins is armed in it, so nobody has to be told twice.
  local class = nil
  if d.class ~= nil and d.class ~= "" then
    class = RM.records and RM.records.isClass(d.class)
    if not class then return false, "no_such_class" end
  end

  local official, officialName = false, nil
  if d.official and RM.roles and RM.roles.atLeast and RM.roles.atLeast(pid, "staff") then
    official = true
    local nm = tostring(d.officialName or d.official_name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if nm ~= "" then officialName = nm:sub(1, 80) end
  end

  local id = shortId()
  lobbies[id] = {
    id      = id,
    host    = pid,
    track   = track.id,
    laps    = laps,
    mode    = tostring(d.mode or "controller"),
    class   = class,
    open    = d.open and true or false,
    official = official,
    officialName = officialName,
    state   = "waiting",
    members = { [pid] = true },
    joined  = { [pid] = 1 },
    nextSeat = 2,
    invited = {},
  }
  RM.info(("%s made a race on %s: %s"):format(
    RM.identity.displayName(pid), track.id, lobbies[id].open and "public" or "invite only"))
  return true, lobbies[id]
end

function RM.lobby.join(pid, id)
  local l = lobbies[tostring(id or "")]
  if not l then return false, "no_such_race" end
  if l.state ~= "waiting" then return false, "already_started" end
  if RM.lobby.of(pid) then return false, "already_in_one" end

  local key = keyOf(pid)
  if not key then return false, "no_session" end
  if not l.open and not l.invited[key] then return false, "not_invited" end

  l.members[pid] = true
  l.joined[pid] = l.nextSeat
  l.nextSeat = l.nextSeat + 1
  return true, l
end

-- invites stick to the player's key, not their seat number, so somebody who
-- reconnects while the lobby waits is still invited
function RM.lobby.invite(pid, who)
  local l = RM.lobby.of(pid)
  if not l then return false, "no_lobby" end
  if l.host ~= pid then return false, "not_the_host" end
  if l.state ~= "waiting" then return false, "already_started" end

  local targetPid = math.floor(tonumber(who) or -1)
  local key = keyOf(targetPid)
  if not key then return false, "no_such_player" end
  l.invited[key] = true
  local track = RM.tracks.get(l.track)
  RM.bus.queue(targetPid, "invite.push", {
    kind = "race",
    from = RM.identity.displayName(pid),
    track = (track and (track.name or track.id)) or l.track,
    lobby = l.id,
  })
  return true, l
end

function RM.lobby.leave(pid)
  local l = RM.lobby.of(pid)
  if not l then return false, "no_lobby" end

  l.members[pid] = nil
  l.joined[pid] = nil

  local rest = memberList(l)
  if #rest == 0 then
    lobbies[l.id] = nil
    return true, nil
  end

  -- the race outlives its host. whoever joined first inherits it.
  if l.host == pid then l.host = rest[1] end
  return true, l
end

function RM.lobby.start(pid)
  local l = RM.lobby.of(pid)
  if not l then return false, "no_lobby" end
  if l.host ~= pid then return false, "not_the_host" end
  if l.state ~= "waiting" then return false, "already_started" end

  l.state = "started"
  local order = memberList(l)
  RM.info(("%s started the race on %s with %d driver(s)"):format(
    RM.identity.displayName(pid), l.track, #order))

  -- the lobby's job is done once everyone is armed. the race itself is the
  -- same machinery as always, and the results already collect by course.
  lobbies[l.id] = nil
  return true, l, order
end

-- The grid, quickest qualifier first. Anyone who did not qualify keeps their
-- place behind those who did, in the order they joined, so a late arrival
-- starts at the back rather than being turned away.
function RM.lobby.gridOrder(trackId, joined)
  local order = RM.results and RM.results.qualifyingOrder(trackId)
  if type(order) ~= "table" or #order == 0 then return joined end

  local rank = {}
  for i = 1, #order do rank[order[i]] = i end

  local front, back = {}, {}
  for i = 1, #joined do
    local pid = joined[i]
    local s = RM.identity.session(pid)
    local place = s and s.key and rank[s.key]
    if place then front[#front + 1] = { pid = pid, place = place }
    else back[#back + 1] = pid end
  end

  table.sort(front, function(a, b) return a.place < b.place end)

  local out = {}
  for i = 1, #front do out[#out + 1] = front[i].pid end
  for i = 1, #back do out[#out + 1] = back[i] end
  return out
end

function RM.lobby.forget(pid)
  RM.lobby.leave(pid)
end

-- the open races, for the panel
function RM.lobby.list()
  local out = {}
  for _, l in pairs(lobbies) do
    local track = RM.tracks.get(l.track)
    local n = 0
    for _ in pairs(l.members) do n = n + 1 end
    local display = track and track.name or l.track
    if l.official and l.officialName and l.officialName ~= "" then
      display = "Baja Sim Official Race (" .. l.officialName .. ")"
    elseif l.official then
      display = "Baja Sim Official Race"
    end
    out[#out + 1] = {
      id      = l.id,
      track   = l.track,
      name    = display,
      host    = RM.identity.displayName(l.host),
      laps    = l.laps,
      class   = l.class,
      open    = l.open,
      official = l.official and true or false,
      officialName = l.officialName,
      drivers = n,
    }
  end
  table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
  return out
end

-- the one you are in, for the lobby card
function RM.lobby.wire(pid)
  local l = RM.lobby.of(pid)
  if not l then return nil end

  local track = RM.tracks.get(l.track)
  local members = {}
  for _, mpid in ipairs(memberList(l)) do
    members[#members + 1] = {
      id   = mpid,
      name = RM.identity.displayName(mpid),
      host = mpid == l.host,
    }
  end

  local display = track and track.name or l.track
  if l.official and l.officialName and l.officialName ~= "" then
    display = "Baja Sim Official Race (" .. l.officialName .. ")"
  elseif l.official then
    display = "Baja Sim Official Race"
  end
  return {
    id      = l.id,
    track   = l.track,
    name    = display,
    laps    = l.laps,
    mode    = l.mode,
    class   = l.class,
    open    = l.open,
    official = l.official and true or false,
    officialName = l.officialName,
    host    = l.host == pid,
    members = members,
  }
end

function RM.lobby.count()
  local n = 0
  for _ in pairs(lobbies) do n = n + 1 end
  return n
end
