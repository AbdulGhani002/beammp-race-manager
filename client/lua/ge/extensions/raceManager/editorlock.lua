-- Level / world editor (F11 / rebound / console / menu) is staff/admin/owner
-- only. Non-staff are blocked from opening it and force-closed if it ever
-- activates.
-- Only while on a server: driving alone, the editor is the player's own.
--
-- Two layers, not one. core_input_actionFilter below blocks the game's own
-- "editor" action group (editorToggle, objectEditorToggle,
-- editorSafeModeToggle -- confirmed against the game's own
-- core/input/actionFilter.lua, not a guess) at the input level, so the
-- keybind never fires. But a menu button or a console command can call
-- editor.setEditorActive(true) or editor.toggleActive() directly, entirely
-- bypassing input actions -- and closeEditor() below only ever reacted
-- after the editor was already active, for however long the next poll
-- took to catch it. installGuard() instead wraps those two functions at
-- the source: activation itself now refuses to go through for a locked
-- player, regardless of what asked for it, and the editor never actually
-- turns on rather than turning on and being closed a moment later.
local M = {}

-- the game's own names for the keys that open an editor. Anything else in
-- this list was a guess, and one of the guesses was the C key, the camera.
local ACTIONS = {
  "editorToggle",
  "objectEditorToggle",
  "editorSafeModeToggle",
}
local GROUP = "raceManagerEditorLock"

local filtered = nil
local noticeCooldown = 0
local closing = false
local sinceLook = 0
local guardInstalled = false

local function isStaff()
  local st = extensions.raceManager_state
  if not (st and st.get) then return false end
  local me = st.get().me
  if not me then return false end
  local r = me.role
  return r == "staff" or r == "admin" or r == "owner"
end

local function onAServer()
  local ok, is = pcall(function()
    return MPCoreNetwork and MPCoreNetwork.isMPSession and MPCoreNetwork.isMPSession()
  end)
  return ok and is == true
end

local function filterActions(on)
  on = on and true or false
  if filtered == on then return end
  filtered = on
  pcall(function()
    local f = core_input_actionFilter
    if not (f and f.addAction) then return end
    -- addAction(filterId, groupOrAction, blocked): the filter the game
    -- itself uses is 0, and a named group blocks its actions together
    if f.setGroup then f.setGroup(GROUP, ACTIONS) end
    f.addAction(0, GROUP, on)
  end)
end

local function editorIsOpen()
  local open = false
  pcall(function()
    if editor and editor.isEditorActive and editor.isEditorActive() then open = true end
  end)
  if not open then
    pcall(function()
      if editor and editor.active == true then open = true end
    end)
  end
  if not open then
    pcall(function()
      if worldEditor and worldEditor.isActive and worldEditor.isActive() then open = true end
    end)
  end
  -- not by asking the extension table for an editor: that makes the game
  -- try to load an extension of that name and log that it could not, four
  -- times a second. The editor's own global says whether it is up.
  return open
end

-- Never use toggleActive alone: if state is wrong it can leave the player stuck ON.
local function closeEditor()
  if closing then return end
  closing = true
  pcall(function()
    if editor and editor.setEditorActive then
      editor.setEditorActive(false)
    end
  end)
  pcall(function()
    if editor and editor.setActive then
      editor.setActive(false)
    end
  end)
  pcall(function()
    if worldEditor and worldEditor.setActive then
      worldEditor.setActive(false)
    end
  end)
  pcall(function()
    if editor and editor.isEditorActive and editor.isEditorActive() and editor.toggleActive then
      editor.toggleActive()
    end
  end)
  pcall(function()
    -- Last-resort console path used by some BeamNG versions
    if type(toggleWorldEditor) == "function" and editorIsOpen() then
      -- do not call toggle if we cannot verify — already tried setEditorActive
    end
  end)
  pcall(function()
    if guihooks and guihooks.trigger then
      guihooks.trigger("EditorActivityChanged", false)
      guihooks.trigger("onEditorDeactivated")
    end
  end)
  closing = false
end

local function noticeBlocked()
  if noticeCooldown > 0 then return end
  noticeCooldown = 2.5
  pcall(function()
    if extensions.raceManager_state and extensions.raceManager_state.notice then
      extensions.raceManager_state.notice("World Editor is locked on this server.")
    end
  end)
end

local function locked()
  return onAServer() and not isStaff()
end

-- wraps editor.setEditorActive and editor.toggleActive so activation
-- itself refuses for a locked player, whatever called it -- a menu button
-- or a console command included, not only the input-bound keys the
-- filter above already covers. Deactivation is never touched: a call that
-- is turning the editor OFF always goes through untouched, including the
-- ones closeEditor() below makes -- only a call trying to turn it ON, made
-- while locked, is refused.
local function installGuard()
  if guardInstalled then return end
  if type(editor) ~= "table" then return end
  local ok = pcall(function()
    if type(editor.setEditorActive) == "function" then
      local original = editor.setEditorActive
      editor.setEditorActive = function(activate, safeMode)
        if activate and locked() then
          noticeBlocked()
          return
        end
        return original(activate, safeMode)
      end
    end
    if type(editor.toggleActive) == "function" then
      local original = editor.toggleActive
      editor.toggleActive = function(safeMode)
        if (not editorIsOpen()) and locked() then
          noticeBlocked()
          return
        end
        return original(safeMode)
      end
    end
  end)
  if ok then guardInstalled = true end
end

function M.sync()
  installGuard()
  if not locked() then
    filterActions(false)
    return
  end
  filterActions(true)
  if editorIsOpen() then
    closeEditor()
    noticeBlocked()
  end
end

-- looked at a few times a second, not every frame: the role and the server
-- do not change faster than that
function M.onUpdate(dt)
  dt = tonumber(dt) or 0
  if noticeCooldown > 0 then noticeCooldown = noticeCooldown - dt end
  sinceLook = sinceLook + dt
  if sinceLook < 0.25 then return end
  sinceLook = 0
  M.sync()
end

function M.onEditorActivated()
  if not locked() then return end
  closeEditor()
  noticeBlocked()
end

function M.onEditorDeactivated()
  -- nothing
end

function M.onEditorInitialized()
  M.sync()
end

function M.onEditorToggled()
  if not locked() then return end
  closeEditor()
  noticeBlocked()
end

function M.onWorldEditorToggled()
  if not locked() then return end
  closeEditor()
  noticeBlocked()
end

function M.onExtensionLoaded()
  M.sync()
end

function M.onClientStartMission()
  M.sync()
end

function M.onClientPostStartMission()
  M.sync()
end

return M
