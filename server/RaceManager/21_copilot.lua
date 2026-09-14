RM = RM or {}
RM.copilot = {}

-- Watching another driver. From his document: send an invite to a driver by
-- name, or send a request to watch one. Both sides can accept or say no. On
-- accept the watcher's camera goes onto the driver's car and the C key does
-- the rest, so CoPilot (in the car) and Chase (behind it) are the same thing
-- seen from two seats. The watcher's own timing is untouched, and the plain
-- TAB spectate is shut on the client, so this is the only way to watch.
--
-- The server keeps who is watching whom, because the driver's car can change
-- and the watcher has to be told where to look. Nothing here is on disk.

local offers   = {}   -- key being asked -> { from = key, kind, at }
local watching = {}   -- watcher key -> driver key
local OFFER_SECS = 30

local function keyOf(pid)
  local s = RM.identity.session(pid)
  return s and s.key or nil
end

local function nameOf(key)
  local rec = RM.identity.record(key)
  if rec and rec.name then return rec.name end
  local pid = RM.identity.pidForKey(key)
  return pid and RM.identity.displayName(pid) or key
end

local function tell(key, event, payload)
  local pid = RM.identity.pidForKey(key)
  if pid then RM.bus.queue(pid, event, payload) end
end

local function racing(pid)
  return RM.race.isActive and RM.race.isActive(pid) or false
end

function RM.copilot.watchingOf(key) return key and watching[key] or nil end

function RM.copilot.watchersOf(key)
  local out = {}
  for w, d in pairs(watching) do
    if d == key then out[#out + 1] = w end
  end
  table.sort(out)
  return out
end

function RM.copilot.wire(key)
  if not key then return { watching = nil, watchers = {}, offer = nil } end
  local driver = watching[key]
  local names = {}
  for _, w in ipairs(RM.copilot.watchersOf(key)) do names[#names + 1] = nameOf(w) end
  local o = offers[key]
  return {
    watching = driver and { name = nameOf(driver) } or nil,
    watchers = names,
    offer    = o and { from = nameOf(o.from), kind = o.kind } or nil,
  }
end

local function push(key)
  tell(key, "copilot.state", RM.copilot.wire(key))
end

-- what the watcher's game needs to find the car: the driver's id and the car
-- BeamMP knows them by, which the spawn told us
local function look(watcherKey, driverKey)
  local driverPid = RM.identity.pidForKey(driverKey)
  local s = driverPid and RM.identity.session(driverPid)
  if not s or not s.activeVid then return false end
  tell(watcherKey, "copilot.watch", {
    pid = driverPid, vid = s.activeVid, name = nameOf(driverKey),
  })
  return true
end

------------------------------------------------------------------ asking

-- Who watches whom, from an offer: "invite" is the sender saying come and
-- watch me, "request" is the sender asking to watch. Either way the watcher
-- has to be free and the driver has to have a car. The reason comes back
-- naming the role, and is worded for whoever is being told afterwards.
local function pair(senderPid, targetPid, kind)
  local aKey, bKey = keyOf(senderPid), keyOf(targetPid)
  if not aKey or not bKey then return nil, nil, "no_session" end
  if aKey == bKey then return nil, nil, "not_yourself" end
  local watcherPid, driverPid = targetPid, senderPid
  if kind == "request" then watcherPid, driverPid = senderPid, targetPid end
  local watcherKey, driverKey = keyOf(watcherPid), keyOf(driverPid)
  if watching[watcherKey] then return nil, nil, "watcher_watching", watcherPid end
  if racing(watcherPid) then return nil, nil, "watcher_racing", watcherPid end
  local s = RM.identity.session(driverPid)
  if not s or not s.activeVid then return nil, nil, "driver_no_car", driverPid end
  return watcherKey, driverKey, nil
end

-- the same reason, worded for the one who is told it
local WORDS = {
  watcher_watching = { me = "already_watching", them = "they_are_watching" },
  watcher_racing   = { me = "you_are_racing",   them = "they_are_racing" },
  driver_no_car    = { me = "you_have_no_car",  them = "they_have_no_car" },
}
local function worded(stop, aboutPid, toldPid)
  local w = WORDS[stop]
  if not w then return stop end
  return (aboutPid == toldPid) and w.me or w.them
end

function RM.copilot.offer(pid, targetPid, kind)
  kind = (kind == "request") and "request" or "invite"
  local _, _, stop, about = pair(pid, targetPid, kind)
  if stop then return false, worded(stop, about, pid) end
  local aKey, bKey = keyOf(pid), keyOf(targetPid)
  offers[bKey] = { from = aKey, kind = kind, at = RM.now() }
  push(bKey)
  local bPid = RM.identity.pidForKey(bKey)
  if bPid then
    RM.bus.queue(bPid, "invite.push", {
      kind = "copilot",
      sub = kind,
      from = nameOf(aKey),
    })
  end
  RM.info(("%s sent a copilot %s to %s"):format(nameOf(aKey), kind, nameOf(bKey)))
  return true, kind
end

function RM.copilot.accept(pid)
  local key = keyOf(pid)
  if not key then return false, "no_session" end
  local o = offers[key]
  if not o then return false, "nothing_to_accept" end
  offers[key] = nil

  local fromPid = RM.identity.pidForKey(o.from)
  if not fromPid then push(key) return false, "they_left" end

  -- the offer said who watches whom; checked again, cars and runs change
  local watcherKey, driverKey, stop, about = pair(fromPid, pid, o.kind)
  if stop then push(key) return false, worded(stop, about, pid) end

  watching[watcherKey] = driverKey
  push(watcherKey)
  push(driverKey)
  look(watcherKey, driverKey)
  RM.info(("%s is watching %s"):format(nameOf(watcherKey), nameOf(driverKey)))
  return true, { watcher = watcherKey, driver = driverKey }
end

function RM.copilot.decline(pid)
  local key = keyOf(pid)
  if not key or not offers[key] then return false, "nothing_to_decline" end
  local from = offers[key].from
  offers[key] = nil
  push(key)
  tell(from, "copilot.gone", { why = "declined", who = nameOf(key) })
  return true
end

------------------------------------------------------------------ ending

local function release(watcherKey, why)
  local driverKey = watching[watcherKey]
  if not driverKey then return false end
  watching[watcherKey] = nil
  tell(watcherKey, "copilot.release", { why = why })
  push(watcherKey)
  push(driverKey)
  RM.info(("%s stopped watching %s: %s"):format(nameOf(watcherKey), nameOf(driverKey), tostring(why)))
  return true
end

-- a watcher stops watching, or a driver sends every watcher back to their
-- own car. one button does both, because you are only ever one of the two.
function RM.copilot.stop(pid)
  local key = keyOf(pid)
  if not key then return false, "no_session" end
  if watching[key] then
    release(key, "stopped")
    return true, "stopped"
  end
  local mine = RM.copilot.watchersOf(key)
  if #mine == 0 then return false, "nothing_to_stop" end
  for _, w in ipairs(mine) do release(w, "driver ended it") end
  return true, "cleared"
end

-- the driver's car changed, so everybody watching is pointed at the new one
function RM.copilot.onVehicle(pid)
  local key = keyOf(pid)
  if not key then return end
  for _, w in ipairs(RM.copilot.watchersOf(key)) do look(w, key) end
end

-- arming a run needs your own car back
function RM.copilot.onRaceArmed(pid)
  local key = keyOf(pid)
  if key and watching[key] then release(key, "you armed a run") end
end

function RM.copilot.forget(pid)
  local key = keyOf(pid)
  if not key then return end
  offers[key] = nil
  for k, o in pairs(offers) do
    if o.from == key then offers[k] = nil; push(k) end
  end
  if watching[key] then watching[key] = nil end
  for _, w in ipairs(RM.copilot.watchersOf(key)) do release(w, "the driver left") end
end

function RM.copilot.tick()
  local now = RM.now()
  for key, o in pairs(offers) do
    if now - o.at > OFFER_SECS then
      offers[key] = nil
      push(key)
    end
  end
end

function RM.copilot.count()
  local n = 0
  for _ in pairs(watching) do n = n + 1 end
  return n
end
