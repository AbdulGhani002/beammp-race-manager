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

------------------------------------------------------------------ monthly

-- Real calendar month, not RM.now() -- that clock is a monotonic server
-- uptime timer (see RM.now() in 01_util.lua: MP.CreateTimer():GetCurrent()),
-- not wall-clock time, so it would think every server was perpetually in
-- January 1970. os.time()/os.date() are the actual system clock, already
-- used elsewhere in this codebase for real dates (RM.players.remember's
-- event.at, the weekly schedule, and others).
local function currentMonthKey(now)
  return os.date("%Y-%m", now or os.time())
end

local function monthLabel(monthKey)
  local y, m = tostring(monthKey or ""):match("^(%d+)-(%d+)$")
  if not y then return tostring(monthKey or "") end
  local t = os.time({ year = tonumber(y), month = tonumber(m), day = 1, hour = 12 })
  return os.date("%B %Y", t)
end

-- the unix time of the 1st of next month, midnight -- what a countdown
-- counts down to
function RM.xp.nextMonthResetUnix(now)
  now = now or os.time()
  local t = os.date("*t", now)
  local y, m = t.year, t.month + 1
  if m > 12 then m = 1; y = y + 1 end
  return os.time({ year = y, month = m, day = 1, hour = 0, min = 0, sec = 0 })
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

  -- this calendar month's own running total, separate from the lifetime
  -- total above -- reset the moment a stale month is noticed on this
  -- record, right here, rather than needing a separate sweep over every
  -- identity record just to catch the rollover. A record this system has
  -- genuinely never seen before (monthKey still nil) is treated
  -- differently from one that's just stale: see the full reasoning on
  -- the backfill in RM.xp.monthlyTop below, which is where this actually
  -- gets applied in practice -- this copy here is only a defensive
  -- fallback for the unlikely case XP gets given before that ever runs.
  local month = currentMonthKey()
  if rec.monthKey ~= month then
    rec.monthXp = (rec.monthKey == nil) and was or 0
    rec.monthKey = month
  end
  rec.monthXp = (tonumber(rec.monthXp) or 0) + add

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
--
-- Two separate amounts, on purpose: e.xp is the placement reward (first
-- pays more than last), e.completionXp is a flat bonus for finishing at
-- all, paid to everyone who crossed the line clean, win or last place. The
-- results screen shows them apart so "you finished" and "you did well" read
-- as the two different things they are.
function RM.xp.forRace(payload)
  if type(payload) ~= "table" or type(payload.finished) ~= "table" then return 0 end

  local completion = math.floor(tonumber(RM.config.raceCompletionXp) or 0)
  local paid = 0
  for i = 1, #payload.finished do
    local e = payload.finished[i]
    if type(e) == "table" and e.key and not e.suspect then
      local amount = RM.xp.forPlace(e.pos)
      if amount > 0 and RM.xp.give(e.key, amount, "finish") then
        e.xp = amount
        paid = paid + 1
      end
      if completion > 0 and RM.xp.give(e.key, completion, "completion") then
        e.completionXp = completion
      end
      if RM.players and RM.players.markRaceCompleted then
        RM.players.markRaceCompleted(e.key)
      end
      -- this row has had what a finish pays. A laptime challenge on a
      -- course comes through here and then through the challenge ladder,
      -- and both used to hand out the finishing bonus and count the race.
      e.paidForFinishing = true
    end
  end
  return paid
end

function RM.xp.of(key)
  local rec = RM.identity.record(key)
  if not rec then return nil end
  return tonumber(rec.xp) or 0, tonumber(rec.level) or 1
end

-- top N by THIS CALENDAR MONTH's own XP (not lifetime total), each with
-- enough detail for a leaderboard post: level/progress, current vehicle
-- if they're connected right now, and their 5 most recent challenge
-- attempts (from the same history RM.players.remember already keeps).
-- forMonth defaults to the current month; the archive job below passes
-- the just-ended month explicitly so it can snapshot final standings
-- before anyone's counter resets for the new one.
-- among a set of challenge history entries (most-recent-first, matching
-- how RM.players.remember stores them), the vehicle that shows up most
-- often; a tie goes to whichever of the tied vehicles appears earliest in
-- the list -- i.e. the one used most recently, per how a tie should be
-- broken here.
local function mostUsedVehicle(entries)
  if #entries == 0 then return nil end
  local counts, firstIdx = {}, {}
  for i = 1, #entries do
    local v = entries[i].vehicle
    if v and v ~= "" then
      counts[v] = (counts[v] or 0) + 1
      if not firstIdx[v] then firstIdx[v] = i end
    end
  end
  local best, bestCount, bestIdx = nil, 0, math.huge
  for v, c in pairs(counts) do
    if c > bestCount or (c == bestCount and firstIdx[v] < bestIdx) then
      best, bestCount, bestIdx = v, c, firstIdx[v]
    end
  end
  return best
end

function RM.xp.monthlyTop(n, forMonth)
  -- an explicit forMonth (the archive job asking about the month that
  -- just ended) is always a real month already on someone's record --
  -- only the plain "what's the current standing" call ever needs to
  -- backfill anyone, and only for the current month specifically.
  local isCurrent = forMonth == nil
  local month = forMonth or currentMonthKey()
  local rows = {}
  local dirty = false
  for key, rec in pairs(RM.identity.all() or {}) do
    if type(rec) == "table" and rec.name and rec.name ~= "" then
      -- A record this feature has never seen before (monthKey still
      -- nil) would otherwise sit at monthXp=0 until that driver next
      -- earns something new -- which is exactly why the board looked
      -- empty even for drivers who already had real XP on the server:
      -- their existing lifetime total had nowhere to go yet. Treated as
      -- a one-time migration instead: their current lifetime total
      -- becomes this month's starting point, the first time this ever
      -- runs for them. Every month after this one still resets to zero
      -- normally -- this only ever fires once per record, right here or
      -- in RM.xp.give, whichever happens first.
      if isCurrent and rec.monthKey == nil then
        rec.monthKey = month
        rec.monthXp = tonumber(rec.xp) or 0
        dirty = true
      end
      if rec.monthKey == month then
      local amount = tonumber(rec.monthXp) or 0
      if amount > 0 then
        local totalXp = tonumber(rec.xp) or 0
        local into, need, lvl = RM.xp.progress(totalXp)

        -- every challenge-kind entry in the record's history (up to the
        -- 10 RM.players.remember keeps, mixed with race entries too) --
        -- not just whichever happen to be the first 5 history slots
        -- overall, which could under-count if some of those slots were
        -- races rather than challenges.
        local challengeEntries = {}
        for i = 1, #(rec.history or {}) do
          local h = rec.history[i]
          if type(h) == "table" and h.kind == "challenge" then
            challengeEntries[#challengeEntries + 1] = h
          end
        end

        local recent = {}
        for i = 1, math.min(5, #challengeEntries) do
          local h = challengeEntries[i]
          recent[i] = {
            name = h.name, trackName = h.trackName, vehicle = h.vehicle,
            class = h.class, tier = h.tier, xp = h.xp, at = h.at,
          }
        end

        rows[#rows + 1] = {
          key = key, name = rec.name, monthXp = amount, totalXp = totalXp,
          level = lvl, xpInto = math.floor(into + 0.5), xpNeed = math.floor(need + 0.5),
          xpPct = math.floor((need > 0 and (into / need) or 0) * 100 + 0.5),
          -- the vehicle actually used to earn this XP, not whatever they
          -- currently happen to be sitting in (or nothing at all if
          -- they're offline when the board is viewed, which is most of
          -- the time) -- ties broken to whichever was used most recently
          vehicle = mostUsedVehicle(challengeEntries),
          recent = recent,
        }
      end
      end
    end
  end
  if dirty then RM.identity.markDirty() end
  table.sort(rows, function(a, b)
    if a.monthXp ~= b.monthXp then return a.monthXp > b.monthXp end
    return tostring(a.name) < tostring(b.name)
  end)
  local out = {}
  for i = 1, math.min(n or 5, #rows) do out[i] = rows[i] end
  return out
end

------------------------------------------------------------ month archive

-- "diagnostic info" for past months: a standalone store, not tied to any
-- one identity record, so it survives even a player's record being
-- cleared later. Lazily loaded once, matching the pattern every other
-- module here uses (RM.store.load/markDirty/flushNow).
local ARCHIVE_STORE = "xp_leaderboard_archive"
local archive = nil

local function loadArchive()
  if not archive then
    archive = RM.store.load(ARCHIVE_STORE, { months = {}, lastSeenMonth = nil })
    archive.months = archive.months or {}
  end
  return archive
end

local function saveArchive()
  RM.store.markDirty(ARCHIVE_STORE)
  RM.store.flushNow(ARCHIVE_STORE)
end

-- called on a slow tick (see 99_main.lua) -- cheap to call often since it
-- does nothing at all once the month it already knows about still matches
-- today's. The first time this ever runs on a fresh install, there is no
-- "outgoing month" to archive yet, so it just learns the current month
-- and waits for the next real rollover.
function RM.xp.checkMonthRollover()
  local a = loadArchive()
  local nowMonth = currentMonthKey()
  if a.lastSeenMonth == nil then
    a.lastSeenMonth = nowMonth
    saveArchive()
    return false
  end
  if a.lastSeenMonth == nowMonth then return false end

  local outgoing = a.lastSeenMonth
  local top = RM.xp.monthlyTop(5, outgoing)
  a.months[outgoing] = {
    month = outgoing, label = monthLabel(outgoing),
    archivedAt = os.time(), top = top,
  }
  a.lastSeenMonth = nowMonth
  saveArchive()
  RM.info(("XP leaderboard for %s archived (%d on the board)"):format(
    monthLabel(outgoing), #top))
  return true
end

-- every archived month key, most recent first
function RM.xp.archivedMonths()
  local a = loadArchive()
  local keys = {}
  for k in pairs(a.months) do keys[#keys + 1] = k end
  table.sort(keys, function(x, y) return x > y end)
  return keys
end

function RM.xp.archivedMonth(monthKey)
  local a = loadArchive()
  return a.months[tostring(monthKey or "")]
end

function RM.xp.currentMonthKey()
  return currentMonthKey()
end

function RM.xp.monthLabel(monthKey)
  return monthLabel(monthKey)
end
