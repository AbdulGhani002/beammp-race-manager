RM = RM or {}
RM.service = {}

-- The bottom bar. The server decides whether you may press a button, holds you
-- still for as long as the job takes and charges the penalty. The game does the
-- work; nothing in here touches a car.
--
-- The penalty is charged when the hold starts, not when it ends, or you could
-- quit half way through and get the repair for nothing.

local jobs = {}   -- a hold that is still running
local sent = {}   -- told the client to do it, waiting to hear how it went

local ACTIONS = {
  reposition = { hold = "reposition", penalty = "recovery" },
  spare      = { hold = "spareTire",  penalty = nil, needsFlat = true,
                 takesSpare = true },
  repair     = { hold = "repair",     penalty = nil },
  fuel       = { hold = "fuel",       penalty = nil, pitOnly = true },
  -- filling the rack again is a pit job. it costs the wait and nothing else,
  -- which is the point of driving in rather than fixing it where you stopped.
  rerack     = { hold = "rerack",     penalty = nil, pitOnly = true,
                 fillsRack = true },
}

-- The rack is the limit. A car carries what it carries: two on a race truck,
-- one on a UTV, none on plenty of things. The client counts what is actually
-- bolted to the car and the count is seeded from that the first time the
-- button is pressed, so nobody has to keep a table of every vehicle.
local function spareCap(reported)
  local cap = tonumber(RM.config.spareChanges)
  local have = tonumber(reported)
  if not have or have < 0 then have = 0 end
  if cap and cap >= 0 and cap < have then return cap end
  return have
end

-- How many changes are left, seeded the first time the car tells us. A car
-- that says nothing is unknown rather than empty, so an old client or a
-- vehicle whose parts could not be read keeps its button instead of losing it.
local function sparesLeft(r, reported)
  if not r then return nil end
  if r.spares == nil and reported ~= nil then r.spares = spareCap(reported) end
  return r.spares
end

function RM.service.spares(pid)
  local r = RM.race.get(pid)
  return r and r.spares or nil
end

function RM.service.get(pid) return jobs[pid] end

function RM.service.busy(pid) return jobs[pid] ~= nil end

function RM.service.use(pid, d)
  if not RM.identity.session(pid) then return false, "no_session" end

  local which = type(d) == "table" and tostring(d.which or "") or ""
  local action = ACTIONS[which]
  if not action then return false, "no_such_action" end
  if jobs[pid] then return false, "already_working" end

  local r = RM.race.get(pid)
  local racing = r ~= nil and r.state == "running"

  -- The game can burst a tire and cannot mend one. The only repair it has
  -- rebuilds the whole car, so a spare is the same job as a repair for half
  -- the wait. Needing a flat first is what stops it replacing repair outright.
  local inPitNow = racing and r.inPit == true
  if action.needsFlat and racing and not inPitNow
     and not (type(d) == "table" and d.flat == true) then
    return false, "no_flat_tire"
  end

  if action.pitOnly and racing and not inPitNow then
    return false, "pit_only"
  end

  -- The rack empties as it is used and only the pit fills it again. Outside a
  -- run there is nothing to ration, so it is not counted.
  local reported = type(d) == "table" and d.spares or nil
  -- the car's own remembered peak (see rackCount0 in service.lua), sent
  -- alongside spares -- the one number that tells "never had a rack" (this
  -- stays 0 no matter what) apart from "has one, currently empty" (spares
  -- can be 0 while this is still positive)
  local trueCap = type(d) == "table" and tonumber(d.cap) or nil
  if racing and action.takesSpare then
    if inPitNow then
      -- the pit is a full stop: a spare tire here does not wait on a
      -- separate rerack first, it just works, as many times as the car's
      -- own rack allows -- the whole reason to drive in rather than fix
      -- it out on the course. A car whose peak was ever above zero is
      -- reseeded to it; a car that never had one still has none, pit or not.
      r.spares = spareCap(trueCap or reported)
      if r.spares <= 0 then return false, "no_rack" end
    else
      local left = sparesLeft(r, reported)
      if left ~= nil and left <= 0 then
        if (trueCap or reported or 0) <= 0 then return false, "no_rack" end
        return false, "no_spares_left"
      end
    end
  end
  if racing and action.fillsRack then
    r.spares = spareCap(reported)
    if r.spares <= 0 then return false, "no_rack" end
  end

  -- free driving costs nothing and waits for nothing. neither does the pit:
  -- the hold still runs and the clock is still going, but nothing is added on
  -- top, which is the whole point of stopping there.
  local inPit = racing and r.inPit == true

  local hold, cost = 0, nil
  if racing then
    hold = tonumber(RM.config.holds[action.hold]) or 0
    -- a repair, a spare or fuel costs no time on top of the hold, his rule:
    -- the hold is the penalty, so none of those names one. A reposition
    -- still costs its recovery time, as its key says it does.
    if action.penalty and not inPit then
      local seconds = tonumber(RM.config.penalties[action.penalty])
      if seconds and seconds > 0 then
        RM.race.penalty(pid, seconds, action.penalty)
        cost = seconds
      end
    end
  end

  jobs[pid] = {
    which  = which,
    hold   = hold,
    endsAt = RM.now() + hold,
    cost   = cost,
    reason = action.penalty,
    lap    = r and r.currentLap or nil,
    full   = inPit,
    -- one comes off the rack every time, run or no run. only the count of
    -- how many are left is a race thing, and that is kept in report below.
    takes  = action.takesSpare and true or false,
    -- where the car actually was when the hold began, so the tick below
    -- can tell a genuine hold from one that stopped being enforced. The
    -- hold itself -- freezing the car -- is entirely the client's own
    -- doing (core_vehicleBridge setFreeze); the server only ever measured
    -- time, never verified the car actually stayed put, which is how
    -- someone found they could open System > HUD Apps mid-hold and just
    -- drive off. This can't reach in and re-freeze a car the client isn't
    -- cooperating with, but it can catch that it happened and make it
    -- worthless: see the movement check in RM.service.tick.
    holdX = nil, holdY = nil, holdZ = nil,
  }
  if hold > 0 then
    -- RM.stella.posOf(pid) returns three values (x, y, z) -- but as the
    -- last operand of "and", Lua truncates a function call to exactly one
    -- return value, so hy/hz were always nil regardless of what posOf
    -- actually returned. That's not just wrong data: the very next
    -- RM.service.tick for this job did `y - job.holdY` with both sides
    -- nil, which throws -- uncaught, since this tick isn't pcall-wrapped
    -- -- aborting everything queued after it in that tick, every tick,
    -- for as long as this job existed. Splitting the existence check from
    -- the call itself is what actually keeps all three return values.
    if RM.stella and RM.stella.posOf then
      local hx, hy, hz = RM.stella.posOf(pid)
      if hx then jobs[pid].holdX, jobs[pid].holdY, jobs[pid].holdZ = hx, hy, hz end
    end
  end

  RM.info(("%s: %s%s"):format(RM.identity.displayName(pid), which,
    hold > 0 and (", %ds hold, %ss on the clock"):format(hold, tostring(cost or 0)) or ", free"))
  return true, jobs[pid]
end

-- a car more than this far from where a hold began is not still frozen,
-- whatever the client claims -- a little slack for suspension settling or
-- a slope, not for driving away
local HOLD_BREAK_M = 4.0

-- rides the 100ms tick that already exists, so this adds no timer
function RM.service.tick(now)
  local ready
  for pid, job in pairs(jobs) do
    -- checked every tick a hold is outstanding, not only when it ends: a
    -- car that got free of the freeze (the HUD Apps trick, a client error,
    -- anything) is caught within a tenth of a second, not only discovered
    -- once the job was already about to pay out
    if job.holdX and not job.broke then
      local x, y, z
      if RM.stella and RM.stella.posOf then x, y, z = RM.stella.posOf(pid) end
      if x then
        local dx, dy = x - job.holdX, y - job.holdY
        local dz = (z or 0) - (job.holdZ or 0)
        if (dx * dx + dy * dy + dz * dz) > (HOLD_BREAK_M * HOLD_BREAK_M) then
          job.broke = true
          local r = RM.race.get(pid)
          if r then r.suspect = true end
          RM.info(("%s: moved during the %s hold (server-side check) -- run marked suspect"):format(
            RM.identity.displayName(pid), tostring(job.which)))
        end
      end
    end
    if now >= job.endsAt then
      ready = ready or {}
      ready[#ready + 1] = pid
    end
  end
  if not ready then return nil end

  for i = 1, #ready do
    local pid = ready[i]
    sent[pid] = jobs[pid]
    jobs[pid] = nil
    RM.bus.queue(pid, "service.run", {
      which = sent[pid].which, full = sent[pid].full and true or false,
      takes = sent[pid].takes and true or false })
  end
  return ready
end

-- what the client made of it. a job the game could not do gives its charge back.
function RM.service.report(pid, d)
  local job = sent[pid]
  sent[pid] = nil
  if not job then return false, "nothing_pending" end

  if type(d) == "table" and d.ok then
    -- A change is a change however the game managed it. Letting air back into
    -- a punctured tire and bolting a fresh one on both cost the driver one off
    -- the rack, because that is the rule he wanted, not an engine detail.
    if job.takes then
      local r = RM.race.get(pid)
      if r and type(r.spares) == "number" and r.spares > 0 then
        r.spares = r.spares - 1
        RM.info(("%s: spare used, %d left before the pit"):format(
          RM.identity.displayName(pid), r.spares))
      end
    end
    return true, job
  end

  if job.cost and job.reason then
    RM.race.dropPenalty(pid, job.reason, job.lap)
    RM.info(("%s: %s could not be done, %ds given back"):format(
      RM.identity.displayName(pid), job.which, job.cost))
  end
  return true, job, (type(d) == "table" and tostring(d.why or "failed") or "failed")
end

function RM.service.forget(pid)
  jobs[pid] = nil
  sent[pid] = nil
end

function RM.service.wire(pid)
  local r = RM.race.get(pid)
  local spares = r and r.spares or nil
  local job = jobs[pid]
  if not job then return { which = nil, spares = spares } end
  return {
    which  = job.which,
    hold   = job.hold,
    left   = RM.util.round(math.max(0, job.endsAt - RM.now()), 2),
    cost   = job.cost,
    spares = spares,
  }
end

function RM.service.count()
  local n = 0
  for _ in pairs(jobs) do n = n + 1 end
  return n
end
