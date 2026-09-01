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
  spare      = { hold = "spareTire",  penalty = "flatTire", needsFlat = true },
  repair     = { hold = "repair",     penalty = "repair" },
  fuel       = { hold = "fuel",       penalty = nil },
}

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

  -- free driving costs nothing and waits for nothing. neither does the pit:
  -- the hold still runs and the clock is still going, but nothing is added on
  -- top, which is the whole point of stopping there.
  local inPit = racing and r.inPit == true

  local hold, cost = 0, nil
  if racing then
    hold = tonumber(RM.config.holds[action.hold]) or 0
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
  }

  RM.info(("%s: %s%s"):format(RM.identity.displayName(pid), which,
    hold > 0 and (", %ds hold, %ss on the clock"):format(hold, tostring(cost or 0)) or ", free"))
  return true, jobs[pid]
end

-- rides the 100ms tick that already exists, so this adds no timer
function RM.service.tick(now)
  local ready
  for pid, job in pairs(jobs) do
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
      which = sent[pid].which, full = sent[pid].full and true or false })
  end
  return ready
end

-- what the client made of it. a job the game could not do gives its charge back.
function RM.service.report(pid, d)
  local job = sent[pid]
  sent[pid] = nil
  if not job then return false, "nothing_pending" end
  if type(d) == "table" and d.ok then return true, job end

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
  local job = jobs[pid]
  if not job then return { which = nil } end
  return {
    which = job.which,
    hold  = job.hold,
    left  = RM.util.round(math.max(0, job.endsAt - RM.now()), 2),
    cost  = job.cost,
  }
end

function RM.service.count()
  local n = 0
  for _ in pairs(jobs) do n = n + 1 end
  return n
end
