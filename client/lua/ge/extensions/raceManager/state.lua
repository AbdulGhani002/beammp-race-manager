local M = {}

-- everything the interface draws lives here. the server owns all of it; this
-- side only mirrors what it was told and never invents a value.

local S = {
  ready      = false,
  needsName  = false,
  me         = { id = -1, key = nil, name = nil, role = "player", level = 1, guest = false },
  config     = {},
  roster     = {},          -- id -> row
  rosterOpen = false,
  tracks     = {},          -- summary list
  track      = nil,         -- one full course, when asked for
  draft      = nil,         -- capture in progress
  level      = nil,
  serverTime = 0,
  toast      = nil,
}

function M.get() return S end

function M.setLevel(levelPath)
  S.level = levelPath and tostring(levelPath):match("([^/]+)/?$") or nil
end

function M.setServerClock(t)
  if type(t) == "number" then S.serverTime = t end
end

function M.isAdmin()
  return S.me.role == "admin" or S.me.role == "owner"
end

local function changed()
  extensions.raceManager_ui.push()
end

local function onWelcome(d)
  if type(d) ~= "table" then return end
  S.ready     = true
  S.me.id     = d.id or -1
  S.me.key    = d.key
  S.me.name   = d.name
  S.me.role   = d.role or "player"
  S.me.level  = d.level or 1
  S.me.guest  = d.guest and true or false
  S.config    = d.config or {}
  S.needsName = (d.name == nil or d.name == "")
  log("I", "raceManager", "welcome: " .. tostring(d.name or "unnamed") .. " / " .. tostring(d.role))
  changed()
end

local function onNameResult(d)
  if type(d) ~= "table" then return end
  if d.ok then
    S.me.name   = d.name
    S.needsName = false
    S.nameError = nil
  else
    S.nameError = d.reason
  end
  changed()
end

local function onRosterFull(d)
  S.roster = {}
  for _, row in ipairs(type(d) == "table" and d or {}) do
    S.roster[row.id] = row
  end
  changed()
end

local function onRosterDelta(d)
  for _, row in ipairs(type(d) == "table" and d or {}) do
    S.roster[row.id] = row
  end
  changed()
end

local function onRosterDrop(id)
  if S.roster[id] then
    S.roster[id] = nil
    changed()
  end
end

local function onTrackList(d)
  S.tracks = type(d) == "table" and d or {}
  changed()
end

local function onTrackFull(d)
  S.track = type(d) == "table" and d or nil
  if S.track then extensions.raceManager_triggers.preview(S.track) end
  changed()
end

local function onDraft(d)
  S.draft = type(d) == "table" and d or nil
  if S.draft then extensions.raceManager_capture.resume(S.draft) end
  changed()
end

local function onToast(d)
  S.toast = d
  changed()
end

local function onCaptureResult(d)
  extensions.raceManager_capture.onResult(d)
end

local function onOptionsResult(d)
  if type(d) == "table" and d.ok and d.action == "demoteSelf" then
    S.me.role = d.value or "player"
  end
  changed()
end

local function onExtensionLoaded()
  local net = extensions.raceManager_net
  net.on("welcome",        onWelcome)
  net.on("name.result",    onNameResult)
  net.on("roster.full",    onRosterFull)
  net.on("roster.delta",   onRosterDelta)
  net.on("roster.drop",    onRosterDrop)
  net.on("track.list",     onTrackList)
  net.on("track.full",     onTrackFull)
  net.on("track.draft",    onDraft)
  net.on("toast",          onToast)
  net.on("capture.result", onCaptureResult)
  net.on("options.result", onOptionsResult)
end

M.onExtensionLoaded = onExtensionLoaded

return M
