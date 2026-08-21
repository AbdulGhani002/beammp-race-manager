local M = {}

local C2S = "rm:c2s"
local S2C = "rm:s2c"

local channels = {}
local wired = false

-- one envelope shape in both directions: { t = server clock, m = { {c,d}, ... } }
-- the server batches because it talks constantly. this side does not batch,
-- because everything it sends is caused by a keypress or a trigger crossing,
-- never by a frame. that keeps the send path off the per frame loop entirely.

function M.on(channel, fn)
  channels[channel] = fn
end

local function dispatch(raw)
  if type(raw) ~= "string" or raw == "" then return end

  local okDecode, env = pcall(jsonDecode, raw)
  if not okDecode or type(env) ~= "table" or type(env.m) ~= "table" then
    log("W", "raceManager", "undecodable message from server")
    return
  end

  extensions.raceManager_state.setServerClock(env.t)

  for i = 1, #env.m do
    local msg = env.m[i]
    if type(msg) == "table" and type(msg.c) == "string" then
      local fn = channels[msg.c]
      if fn then
        local ok, err = pcall(fn, msg.d)
        if not ok then
          log("E", "raceManager", ("channel %s failed: %s"):format(msg.c, tostring(err)))
        end
      end
    end
  end
end

function M.send(channel, payload)
  if type(TriggerServerEvent) ~= "function" then return false end
  local ok, body = pcall(jsonEncode, { m = { { c = channel, d = payload } } })
  if not ok then
    log("E", "raceManager", "could not encode " .. tostring(channel))
    return false
  end
  TriggerServerEvent(C2S, body)
  return true
end

function M.isConnected()
  return type(TriggerServerEvent) == "function"
end

local function wire()
  if wired then return end
  if type(AddEventHandler) ~= "function" then return end
  AddEventHandler(S2C, dispatch)
  wired = true
  log("I", "raceManager", "network bridge up")
end

local function onExtensionLoaded()
  wire()
end

-- BeamMP can finish loading after we do, so keep trying until the hook exists
local function onClientStartMission()
  wire()
end

M.onExtensionLoaded    = onExtensionLoaded
M.onClientStartMission = onClientStartMission
M.dispatch             = dispatch

return M
