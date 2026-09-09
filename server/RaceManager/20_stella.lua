RM = RM or {}
RM.stella = {}

-- The Stella is the little race control box on the dash. Its screen and its
-- sounds are its author's and live on the client. What lives here is the
-- part that has to be believed by more than one car: a driver saying their
-- truck is stopped, and a driver asking the truck ahead to let them by.
--
-- Nothing a client says is taken as proof. Who is ahead, how far away they
-- are and whether a request is still open are all worked out from the
-- positions the server already has.

local breakdowns = {}   -- pid -> { since, told = { [otherPid] = true } }
local requests   = {}   -- id  -> { id, from, to, state, at, until_ }
local openBy     = {}   -- requester pid -> request id
local nextId     = 1

local function cfg(name, fallback)
  local c = RM.config.stella
  local v = type(c) == "table" and tonumber(c[name]) or nil
  return v or fallback
end

------------------------------------------------------------------ positions

-- where a car is, from the sample BeamMP already keeps for the roster
function RM.stella.posOf(pid)
  local s = RM.identity.session(pid)
  if not s or not s.activeVid then return nil end
  local ok, raw = pcall(MP.GetPositionRaw, pid, s.activeVid)
  if not ok or type(raw) ~= "table" then return nil end
  local p = raw.pos
  if type(p) ~= "table" then return nil end
  local x, y, z = p[1] or p.x, p[2] or p.y, p[3] or p.z
  if type(x) ~= "number" or type(y) ~= "number" then return nil end
  return x, y, tonumber(z) or 0
end

local function distance(a, b)
  local ax, ay = RM.stella.posOf(a)
  local bx, by = RM.stella.posOf(b)
  if not ax or not bx then return nil end
  local dx, dy = ax - bx, ay - by
  return math.sqrt(dx * dx + dy * dy)
end

-- how far round the course somebody is: gates done first, and between two
-- cars on the same gate the one nearer to it
local function progress(pid)
  local r = RM.race.get(pid)
  if not r or r.state ~= "running" then return nil end
  local done = (r.currentLap or 0) * r.gates + (r.nextGate or 1) - 1
  local track = RM.tracks.get(r.track)
  local cp = track and track.checkpoints and track.checkpoints[r.nextGate]
  local x, y = RM.stella.posOf(pid)
  local toNext = 0
  if cp and cp.pos and x then
    local dx, dy = cp.pos.x - x, cp.pos.y - y
    toNext = math.sqrt(dx * dx + dy * dy)
  end
  return done, toNext, r.track
end

local function isAhead(otherPid, myDone, myToNext)
  local done, toNext = progress(otherPid)
  if not done then return false end
  if done ~= myDone then return done > myDone end
  return toNext < myToNext
end

-- the nearest car in front on the same course, inside the window
function RM.stella.ahead(pid)
  local myDone, myToNext, track = progress(pid)
  if not myDone then return nil, "not_racing" end
  local window = cfg("passWindowM", 300)

  local best, bestDist = nil, nil
  for other in pairs(RM.identity.sessions()) do
    if other ~= pid then
      local r = RM.race.get(other)
      if r and r.state == "running" and r.track == track and isAhead(other, myDone, myToNext) then
        local d = distance(pid, other)
        if d and d <= window and (not bestDist or d < bestDist) then
          best, bestDist = other, d
        end
      end
    end
  end
  if not best then return nil, "nobody_ahead" end
  return best, bestDist
end

------------------------------------------------------------------ breakdown

local function tell(pid, channel, payload)
  RM.bus.queue(pid, channel, payload)
end

local function vehicleOf(pid)
  local s = RM.identity.session(pid)
  return s and s.activeVid or nil
end

function RM.stella.setBreakdown(pid, active)
  if not RM.identity.session(pid) then return false, "no_session" end
  active = active and true or false

  if active then
    if not breakdowns[pid] then
      breakdowns[pid] = { since = RM.now(), told = {} }
      RM.info(("%s says their car is stopped"):format(RM.identity.displayName(pid)))
    end
  else
    local b = breakdowns[pid]
    if b then
      for other in pairs(b.told) do
        tell(other, "stella.breakdown.alert", { active = false, vehicleId = vehicleOf(pid),
          playerName = RM.identity.displayName(pid) })
      end
      breakdowns[pid] = nil
      RM.info(("%s is moving again"):format(RM.identity.displayName(pid)))
    end
  end

  tell(pid, "stella.breakdown.state", { active = active, vehicleId = vehicleOf(pid),
    playerName = RM.identity.displayName(pid) })
  return true, active
end

function RM.stella.isBrokenDown(pid) return breakdowns[pid] ~= nil end

-- who needs warning: anyone racing the same course inside the hazard range.
-- told once on the way in and once on the way out, not every tick.
local function warnAround(pid, b)
  local r = RM.race.get(pid)
  local track = r and r.track or nil
  local range = cfg("hazardRangeM", 250)
  local name = RM.identity.displayName(pid)
  local vid = vehicleOf(pid)

  for other in pairs(RM.identity.sessions()) do
    if other ~= pid then
      local ro = RM.race.get(other)
      local near = false
      if ro and ro.state == "running" and (not track or ro.track == track) then
        local d = distance(pid, other)
        near = d ~= nil and d <= range
        if near and not b.told[other] then
          b.told[other] = true
          tell(other, "stella.breakdown.alert", { active = true, vehicleId = vid,
            playerName = name, distanceM = math.floor(d + 0.5) })
        end
      end
      if not near and b.told[other] then
        b.told[other] = nil
        tell(other, "stella.breakdown.alert", { active = false, vehicleId = vid, playerName = name })
      end
    end
  end
end

------------------------------------------------------------------ passing

local function status(pid, req, state)
  tell(pid, "stella.pass.status", { state = state, requestId = req.id,
    aheadName = RM.identity.displayName(req.to) })
end

local function close(req, state)
  requests[req.id] = nil
  if openBy[req.from] == req.id then openBy[req.from] = nil end
  status(req.from, req, state)
  status(req.to, req, state)
end

function RM.stella.requestPass(pid)
  if not RM.identity.session(pid) then return false, "no_session" end

  -- one open request per driver. asking again while it is open is not a
  -- second request, it is the same one, so they are told where it stands.
  local openId = openBy[pid]
  local open = openId and requests[openId]
  if open then
    status(pid, open, open.state)
    return true, open
  end

  local ahead, why = RM.stella.ahead(pid)
  if not ahead then
    tell(pid, "stella.pass.status", { state = "cancelled", reason = why })
    return false, why
  end

  local id = nextId
  nextId = nextId + 1
  local req = { id = id, from = pid, to = ahead, state = "delivered", at = RM.now(),
                until_ = RM.now() + cfg("passReplySecs", 30) }
  requests[id] = req
  openBy[pid] = id

  tell(ahead, "stella.pass.alert", { requestId = id, requesterId = pid,
    requesterName = RM.identity.displayName(pid),
    distanceM = math.floor((why or 0) + 0.5) })
  status(pid, req, "delivered")
  RM.info(("%s asks %s to let them by, %dm"):format(
    RM.identity.displayName(pid), RM.identity.displayName(ahead), math.floor((why or 0) + 0.5)))
  return true, req
end

function RM.stella.acceptPass(pid, requestId)
  local req = requests[tonumber(requestId) or -1]
  if not req then return false, "no_such_request" end
  if req.to ~= pid then return false, "not_yours" end
  if req.state ~= "delivered" then return false, "not_open" end
  if RM.now() > req.until_ then
    close(req, "expired")
    return false, "expired"
  end

  req.state = "accepted"
  req.until_ = RM.now() + cfg("passGoSecs", 20)
  tell(req.from, "stella.pass.go", { requestId = req.id,
    aheadName = RM.identity.displayName(pid), expiresAt = req.until_ })
  status(pid, req, "accepted")
  RM.info(("%s lets %s by"):format(RM.identity.displayName(pid), RM.identity.displayName(req.from)))
  return true, req
end

function RM.stella.request(id) return requests[tonumber(id) or -1] end
function RM.stella.openFor(pid) local id = openBy[pid] return id and requests[id] or nil end

------------------------------------------------------------------ housekeeping

-- on the roster cadence, not every tick: it walks the positions
function RM.stella.tick()
  local now = RM.now()
  for id, req in pairs(requests) do
    if now > req.until_ then
      close(req, req.state == "accepted" and "complete" or "expired")
    end
  end
  for pid, b in pairs(breakdowns) do
    if RM.identity.session(pid) then warnAround(pid, b) else RM.stella.forget(pid) end
  end
end

-- somebody leaving takes their requests and their warning with them
function RM.stella.forget(pid)
  local b = breakdowns[pid]
  if b then
    for other in pairs(b.told) do
      tell(other, "stella.breakdown.alert", { active = false })
    end
    breakdowns[pid] = nil
  end
  for id, req in pairs(requests) do
    if req.from == pid or req.to == pid then
      requests[id] = nil
      if openBy[req.from] == id then openBy[req.from] = nil end
      local left = req.from == pid and req.to or req.from
      if RM.identity.session(left) then status(left, req, "cancelled") end
    end
  end
  openBy[pid] = nil
end

function RM.stella.count()
  local n, m = 0, 0
  for _ in pairs(breakdowns) do n = n + 1 end
  for _ in pairs(requests) do m = m + 1 end
  return n, m
end
