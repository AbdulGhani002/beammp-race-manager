RM = RM or {}
RM.util = {}

local function fmt(...)
  local n = select('#', ...)
  if n == 0 then return "" end
  local parts = {}
  for i = 1, n do
    local v = select(i, ...)
    parts[i] = type(v) == "string" and v or tostring(v)
  end
  return table.concat(parts, " ")
end

function RM.info(...)  Util.LogInfo(fmt(...))  end
function RM.warn(...)  Util.LogWarn(fmt(...))  end
function RM.error(...) Util.LogError(fmt(...)) end
function RM.debug(...) Util.LogDebug(fmt(...)) end

-- the official race clock. one timer, started at init, never reset.
-- client clocks are never trusted for anything that decides a result.
local clock = nil

function RM.util.startClock()
  clock = MP.CreateTimer()
  clock:Start()
end

function RM.now()
  if not clock then return 0.0 end
  return clock:GetCurrent()
end

local handlerErrors = {}

-- editing a file in the plugin folder re-runs it without discarding the lua
-- state, so MP.RegisterEvent has to be called once per event and no more.
-- the function body is always refreshed so a reload picks up the new code.
RM._registered = RM._registered or {}

-- the only way handlers get registered here, so everything is wrapped
function RM.handler(eventName, fn)
  local globalName = "RM_h_" .. eventName:gsub("[^%w]", "_")
  _G[globalName] = function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      local n = (handlerErrors[eventName] or 0) + 1
      handlerErrors[eventName] = n
      -- throttled: a repeating fault flooding the console costs more than the fault
      if n <= 5 or n % 100 == 0 then
        RM.error(("handler %s failed (%d): %s"):format(eventName, n, tostring(err)))
      end
      return nil
    end
    return err
  end
  if not RM._registered[globalName] then
    MP.RegisterEvent(eventName, globalName)
    RM._registered[globalName] = true
  end
  return globalName
end

function RM.util.handlerErrorCount()
  local total = 0
  for _, n in pairs(handlerErrors) do total = total + n end
  return total
end

-- scratch table pool. the bus and roster run every tick all session; allocating
-- there is what produces the GC pause he described as tick lag.
local pool, poolSize = {}, 0

function RM.util.take()
  if poolSize > 0 then
    local t = pool[poolSize]
    pool[poolSize] = nil
    poolSize = poolSize - 1
    return t
  end
  return {}
end

function RM.util.give(t)
  if type(t) ~= "table" then return end
  for k in pairs(t) do t[k] = nil end
  if poolSize < 128 then
    poolSize = poolSize + 1
    pool[poolSize] = t
  end
end

function RM.util.poolSize() return poolSize end

function RM.util.clear(t)
  for k in pairs(t) do t[k] = nil end
  return t
end

function RM.util.count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function RM.util.round(v, places)
  local m = 10 ^ (places or 0)
  return math.floor(v * m + 0.5) / m
end

function RM.util.clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

-- nan and inf both slip past a plain type() check and poison anything they touch
function RM.util.isNum(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function RM.util.tidy(s)
  if type(s) ~= "string" then return "" end
  return (s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

function RM.util.slug(s)
  local out = tostring(s or ""):lower()
  out = out:gsub("[^%w]+", "-")
  out = out:gsub("^%-+", "")
  out = out:gsub("%-+$", "")
  return out
end

local MPS_TO_MPH = 2.2369362920544

function RM.util.mph(vx, vy, vz)
  if not (RM.util.isNum(vx) and RM.util.isNum(vy) and RM.util.isNum(vz)) then return 0 end
  return math.sqrt(vx * vx + vy * vy + vz * vz) * MPS_TO_MPH
end
