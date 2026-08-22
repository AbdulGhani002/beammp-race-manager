local M = {}

-- the only bridge to the html. nothing here runs per frame except one boolean
-- test: if nothing changed there is nothing to send, and when something did
-- change it still goes out at most ten times a second. nobody reads a player
-- list at 120fps.

local UI_EVENT = "rmState"
local MIN_GAP  = 0.1

local dirty, acc = false, 0
local snap = { me = {}, roster = {}, tracks = {}, capture = {} }

function M.push()
  dirty = true
end

local function build()
  local S = extensions.raceManager_state.get()

  snap.ready     = S.ready
  snap.needsName = S.needsName
  snap.nameError = S.nameError
  snap.level     = S.level
  snap.isAdmin   = extensions.raceManager_state.isAdmin()
  snap.connected = extensions.raceManager_net.isConnected()
  snap.toast     = S.toast
  snap.config    = S.config

  snap.me.id    = S.me.id
  snap.me.name  = S.me.name
  snap.me.role  = S.me.role
  snap.me.level = S.me.level
  snap.me.guest = S.me.guest

  -- angular wants a list, and it wants it sorted the same way every time
  local n = 0
  for _, row in pairs(S.roster) do
    n = n + 1
    snap.roster[n] = row
  end
  for i = n + 1, #snap.roster do snap.roster[i] = nil end
  table.sort(snap.roster, function(a, b) return (a.name or "") < (b.name or "") end)

  snap.tracks = S.tracks
  snap.capture = extensions.raceManager_capture.status()
  snap.perf = extensions.raceManager_perf.status()

  return snap
end

local function flush()
  dirty = false
  acc = 0
  guihooks.trigger(UI_EVENT, build())
end

local function onUpdate(dt)
  -- a toast nobody dismissed should not sit on screen for the rest of the
  -- session. one nil test per frame when there is not one.
  local S = extensions.raceManager_state.get()
  if S.toast then
    S.toastFor = (S.toastFor or 0) - dt
    if S.toastFor <= 0 then
      S.toast = nil
      dirty = true
    end
  end

  if not dirty then return end
  acc = acc + dt
  if acc < MIN_GAP then return end
  flush()
end

-- the app can come up after the state did, so it asks once on its own
function M.requestState()
  flush()
end

------------------------------------------------------------ called from html

function M.setName(name)
  extensions.raceManager_net.send("name.set", { name = tostring(name or "") })
end

function M.setRosterOpen(open)
  local on = open and true or false
  extensions.raceManager_state.get().rosterOpen = on
  extensions.raceManager_net.send("roster.sub", { on = on })
  M.push()
end

function M.togglePlayers()
  M.setRosterOpen(not extensions.raceManager_state.get().rosterOpen)
end

function M.demoteSelf()
  extensions.raceManager_net.send("options.demoteSelf", {})
end

function M.openDiscord()
  local url = extensions.raceManager_state.get().config.discordUrl
  if type(url) ~= "string" or url == "" then
    log("W", "raceManager", "no discord url is set on the server")
    return
  end

  if type(openWebBrowser) ~= "function" then
    log("W", "raceManager", "no browser hook in this build. the link is " .. url)
    return
  end

  -- openWebBrowser is an engine binding and is a no-op in some builds, so
  -- fall through to the shell, which handles an http url on windows. the
  -- panel shows the link regardless, which is the part that always works.
  local browserOk = pcall(openWebBrowser, url)
  local shellOk = false
  if not browserOk then
    shellOk = pcall(function() Engine.Platform.exploreFolder(url) end)
  end

  log("I", "raceManager", ("discord: browser=%s shell=%s url=%s")
    :format(tostring(browserOk), tostring(shellOk), url))
end

function M.exitServer()
  local ok = pcall(function() MPCoreNetwork.leaveServer(true) end)
  if not ok then
    pcall(function() returnToMainMenu() end)
  end
end

function M.clearToast()
  extensions.raceManager_state.get().toast = nil
  M.push()
end

M.onUpdate = onUpdate
M.flush    = flush

return M
