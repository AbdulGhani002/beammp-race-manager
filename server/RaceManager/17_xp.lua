RM = RM or {}
RM.xp = {}

-- Experience and levels.
--
-- Finishing pays by where you came: two hundred for the win, two less for each
-- place after it, never below the floor. That is the ladder from his document
-- and the numbers live in config so they can be changed without a reinstall.
--
-- Nothing is paid for a run the clock could not vouch for, and nothing to a
-- guest, who has no record on disk to put it in. XP sits on the identity
-- record beside the name, so it survives a restart for the same reason the
-- name does.

-- what one finishing place is worth
function RM.xp.forPlace(pos)
  local c = RM.config.xpCurve or {}
  local first = tonumber(c.first) or 200
  local step  = tonumber(c.step) or 2
  local floor = tonumber(c.floor) or 20

  local p = math.floor(tonumber(pos) or 0)
  if p < 1 then return 0 end

  local paid = first - (p - 1) * step
  if paid < floor then paid = floor end
  return paid
end

-- Growing ladder: 750 to hit 2, 1,750 to hit 3, 3,000 to hit 4, and so on.
-- Each next level costs 250 more than the last (750, 1000, 1250, 1500…).
-- Cumulative XP to *be* level n is 125 * (n-1) * (n+4).
function RM.xp.neededFor(level)
  local n = math.floor(tonumber(level) or 1)
  if n < 2 then return 0 end
  if n > 500 then n = 500 end
  return 125 * (n - 1) * (n + 4)
end

function RM.xp.levelFor(total)
  local t = tonumber(total) or 0
  if t < 0 then t = 0 end
  local n = 1
  while RM.xp.neededFor(n + 1) <= t and n < 500 do
    n = n + 1
  end
  return n
end

-- XP already in this level, XP this level spans, current level
function RM.xp.progress(total)
  local t = tonumber(total) or 0
  if t < 0 then t = 0 end
  local lvl = RM.xp.levelFor(t)
  local floor = RM.xp.neededFor(lvl)
  local span = RM.xp.neededFor(lvl + 1) - floor
  if span < 1 then span = 1 end
  return t - floor, span, lvl
end

function RM.xp.rankOf(key)
  key = tostring(key or "")
  local rec = RM.identity.record(key)
  if not rec then return nil, 0 end
  local mine = tonumber(rec.xp) or 0
  local rank, total = 1, 0
  for k, r in pairs(RM.identity.all() or {}) do
    if type(r) == "table" and r.name and r.name ~= "" then
      total = total + 1
      if k ~= key and (tonumber(r.xp) or 0) > mine then
        rank = rank + 1
      end
    end
  end
  return rank, total
end

-- Recompute saved levels after the curve changes.
function RM.xp.resyncLevels()
  local dirty = false
  for _, rec in pairs(RM.identity.all() or {}) do
    if type(rec) == "table" then
      local lvl = RM.xp.levelFor(tonumber(rec.xp) or 0)
      if rec.level ~= lvl then rec.level = lvl; dirty = true end
    end
  end
  if dirty then RM.identity.markDirty() end
end

-- Puts XP on a saved identity and moves the level with it. Returns the new
-- total and level, or nil if there was nobody to pay.
function RM.xp.give(key, amount, why)
  local rec = RM.identity.record(key)
  if not rec then return nil, "no_such_player" end
  if rec.guest and not RM.config.guestsRanked then return nil, "guest" end
  -- turned off under Options: practice that touches nothing
  if rec.tracking == false then return nil, "tracking_off" end

  local add = math.floor(tonumber(amount) or 0)
  if add == 0 then return nil, "nothing_to_give" end

  local was = tonumber(rec.xp) or 0
  local now = was + add
  if now < 0 then now = 0 end

  rec.xp = now
  local wasLevel = tonumber(rec.level) or 1
  rec.level = RM.xp.levelFor(now)
  RM.identity.markDirty()

  -- the roster carries the level, so a change has to reach the screen
  local pid = RM.identity.pidForKey(key)
  if pid then
    local s = RM.identity.session(pid)
    if s then s.level = rec.level end
    RM.players.setLevel(pid, rec.level)
    RM.bus.queue(pid, "xp.gain", {
      amount = add, total = now, level = rec.level,
      levelled = rec.level > wasLevel or nil,
      why = why and tostring(why) or nil,
    })
    if rec.level > wasLevel then
      RM.info(("%s reached level %d"):format(RM.identity.displayName(pid), rec.level))
    end
  end

  return now, rec.level
end

-- Everyone who finished, paid by where they came. Called once when the heat
-- closes, off the same payload the results screen is built from, so the place
-- that pays is the corrected one that decided the race.
function RM.xp.forRace(payload)
  if type(payload) ~= "table" or type(payload.finished) ~= "table" then return 0 end

  local paid = 0
  for i = 1, #payload.finished do
    local e = payload.finished[i]
    if type(e) == "table" and e.key and not e.suspect then
      local amount = RM.xp.forPlace(e.pos)
      if amount > 0 and RM.xp.give(e.key, amount, "finish") then
        e.xp = amount
        paid = paid + 1
      end
    end
  end
  return paid
end

function RM.xp.of(key)
  local rec = RM.identity.record(key)
  if not rec then return nil end
  return tonumber(rec.xp) or 0, tonumber(rec.level) or 1
end
