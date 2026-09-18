RM = RM or {}
RM.discordbridge = {}

-- Bobby (the Discord bot) already reads Race Manager's live_*.json files,
-- from disk directly when it shares a machine with the server, or over SFTP
-- when it does not (see README_LOCAL_RM_HOOK.txt). That is read-only. This
-- file is the other direction: a one-shot request/response pair of JSON
-- files, the same shape BobbyMap already uses to ask the game server to
-- change map. Bobby writes a request, this ticks over it, creates the
-- challenge through the exact same validation the in-game panel uses
-- (RM.challenges.createFromDiscord, which is RM.challenges.create minus the
-- in-game role check -- Bobby has already gated who may reach this before
-- anything was written to disk), and writes a response Bobby is polling for.
--
-- One request at a time, by design. Two admins posting a challenge from
-- Discord in the same second is rare enough that "the second write wins"
-- is an acceptable answer, and it keeps this file honest: no directory
-- listing, no queue, no lock file, just two JSON files whose shapes never
-- change.

local DIR      = "Resources/Server/RaceManager/data"
local REQUEST  = DIR .. "/discord_challenge_request.json"
local RESPONSE = DIR .. "/discord_challenge_response.json"
-- a second, separate request/response pair for launching a challenge for
-- everyone, rather than overloading the create pair above with a second
-- shape -- "just two JSON files whose shapes never change" per file, so a
-- new action gets its own pair instead of a field that means different
-- things depending on what else is set.
local LAUNCH_REQUEST  = DIR .. "/discord_launch_request.json"
local LAUNCH_RESPONSE = DIR .. "/discord_launch_response.json"

-- the id of the request already answered, so a restart does not redo (or a
-- slow Bobby does not re-read) the same one. Seeded from the response file
-- itself at startup, so this survives a plugin reload.
local lastHandledId = nil
local lastHandledLaunchId = nil

local function readJson(path)
  if not FS.Exists(path) then return nil end
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  if not body or body == "" then return nil end
  local ok, decoded = pcall(Util.JsonDecode, body)
  if not ok or type(decoded) ~= "table" then return nil end
  return decoded
end

local function writeJson(path, t)
  if not FS.Exists(DIR) then FS.CreateDirectory(DIR) end
  local ok, body = pcall(Util.JsonEncode, t)
  if not ok then
    RM.error("discordbridge: could not encode response:", body)
    return false
  end
  return RM.store.writeFileAtomic(path, body, true)
end

function RM.discordbridge.init()
  local prior = readJson(RESPONSE)
  if type(prior) == "table" and prior.id then
    lastHandledId = tostring(prior.id)
  end
  local priorLaunch = readJson(LAUNCH_RESPONSE)
  if type(priorLaunch) == "table" and priorLaunch.id then
    lastHandledLaunchId = tostring(priorLaunch.id)
  end
end

-- Turns what Bobby's modal collected into the same field shape
-- RM.challenges.readFields expects from the in-game panel (see
-- 22_challenges.lua), so both paths run through one validator. Bobby sends
-- tiers already split into { time = <value>, xp = <n> } rows -- it is the
-- one that parses the "value:xp, value:xp" text the admin typed into the
-- modal, because that parsing is about the Discord form, not about what a
-- challenge is.
local function fieldsFromRequest(req)
  return {
    name        = req.name,
    kind        = req.kind,
    style       = req.style,
    track       = req.track,
    laps        = req.laps,
    classes     = req.classes,
    tiers       = req.tiers,
    description = req.description,
    timeLimit   = req.timeLimit,
    measure     = req.measure,
    startInHours = req.startInHours,
  }
end

function RM.discordbridge.tick()
  local req = readJson(REQUEST)
  if not req or type(req.id) ~= "string" or req.id == "" then return end
  if req.id == lastHandledId then return end

  local ok, result = RM.challenges.createFromDiscord(
    fieldsFromRequest(req), req.requestedBy)

  local response = { id = req.id, at = os.time() }
  if ok then
    response.ok = true
    response.challenge = {
      id = result.id, name = result.name, kind = result.kind, style = result.style,
      track = result.track, trackName = result.trackName, laps = result.laps,
    }
    RM.info(("discord bridge: created challenge %s for %s"):format(
      result.id, tostring(req.requestedBy)))
  else
    response.ok = false
    response.reason = tostring(result)
    RM.info(("discord bridge: challenge request from %s refused: %s"):format(
      tostring(req.requestedBy), tostring(result)))
  end

  writeJson(RESPONSE, response)
  lastHandledId = req.id
end

-- launching a live challenge for every connected driver, requested from
-- Discord rather than in-game (see RM.challenges.launchAllFromDiscord,
-- 22_challenges.lua) -- same request/response file pair pattern as the
-- create above, its own pair since the shape is different.
function RM.discordbridge.tickLaunch()
  local req = readJson(LAUNCH_REQUEST)
  if not req or type(req.id) ~= "string" or req.id == "" then return end
  if req.id == lastHandledLaunchId then return end

  local ok, result = RM.challenges.launchAllFromDiscord(
    req.challenge, req.requestedBy, RM.race.afterArm)

  local response = { id = req.id, at = os.time() }
  if ok then
    response.ok = true
    response.launched = result.launched
    response.skipped = result.skipped
    response.name = result.name
    if type(result.skips) == "table" and #result.skips > 0 then
      local skips = {}
      for i = 1, #result.skips do
        skips[i] = { name = result.skips[i].name, why = result.skips[i].why }
      end
      response.skips = skips
    end
  else
    response.ok = false
    response.reason = tostring(result)
    RM.info(("discord bridge: launch request from %s refused: %s"):format(
      tostring(req.requestedBy), tostring(result)))
  end

  writeJson(LAUNCH_RESPONSE, response)
  lastHandledLaunchId = req.id
end
