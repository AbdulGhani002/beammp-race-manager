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
  lights     = false,
}

function M.get() return S end

function M.setLevel(levelPath)
  if not levelPath then S.level = nil return end
  -- it arrives as /levels/utah_sc/info.json, and the part worth keeping is
  -- the folder, not the file on the end of it
  local p = tostring(levelPath)
  S.level = p:match("/levels/([^/]+)") or p:match("([^/]+)/[^/]*$") or p
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
  extensions.raceManager_main.handshakeDone()
  log("I", "raceManager", "welcome: " .. tostring(d.name or "unnamed") .. " / " .. tostring(d.role))
  changed()
end

local function onNameResult(d)
  if type(d) ~= "table" then return end
  if d.ok then
    S.me.name   = d.name
    S.needsName = false
    S.nameError = nil
    -- shown once, so it has to be hard to miss
    if d.code then S.myCode = d.code end
    S.recovered = d.recovered and true or false
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

  -- the same course arrives for two different reasons. armed means the
  -- volumes go up to be raced on; anything else is somebody looking at it.
  if S.track then
    local race = extensions.raceManager_race
    if race.isActive() and race.status().track == S.track.id then
      race.onTrackReady(S.track)
    else
      extensions.raceManager_triggers.preview(S.track)
    end
  end

  extensions.raceManager_capture.onPreview()
  changed()
end

local function onDraft(d)
  S.draft = type(d) == "table" and d or nil
  if S.draft then extensions.raceManager_capture.resume(S.draft) end
  changed()
end

-- your own record, pushed when something about you changes. the roster only
-- carries rows for the player list, and it is not open half the time.
-- a message from our own side rather than the server. same slot as a toast,
-- so it expires the same way.
-- how long a message sits there, and the seq so the bar counting it down
-- starts again when the next one replaces it rather than carrying on
local TOAST_SECS = 10
local seq = 0

function M.notice(text)
  seq = seq + 1
  S.toast = { text = tostring(text or ""), secs = TOAST_SECS, seq = seq }
  S.toastFor = TOAST_SECS
  changed()
end

function M.toggleLights()
  S.lights = not S.lights
  changed()
end

function M.closeLights()
  if not S.lights then return end
  S.lights = false
  changed()
end

local function onMe(d)
  if type(d) ~= "table" then return end
  if d.id    ~= nil then S.me.id    = d.id end
  if d.name  ~= nil then S.me.name  = d.name end
  if d.role  ~= nil then S.me.role  = d.role end
  if d.level ~= nil then S.me.level = d.level end
  if d.guest ~= nil then S.me.guest = d.guest and true or false end
  S.needsName = (S.me.name == nil or S.me.name == "")
  log("I", "raceManager", "you are now " .. tostring(S.me.role))
  changed()
end

local function onToast(d)
  seq = seq + 1
  S.toast = d
  if type(S.toast) == "table" then
    S.toast.secs = TOAST_SECS
    S.toast.seq = seq
  end
  S.toastFor = TOAST_SECS
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
  net.on("me",             onMe)
  net.on("toast",          onToast)
  net.on("capture.result", onCaptureResult)
  net.on("options.result", onOptionsResult)
end

M.onExtensionLoaded = onExtensionLoaded

return M
