-- Level editor (F11 / rebound / console) is owner-only.
-- Non-owners are blocked from opening it and force-closed if it ever activates.
local M = {}

local ACTIONS = {
  "toggleWorldEditor",
  "editorToggle",
  "toggleEditor",
  "worldEditor",
  "openWorldEditor",
  "closeWorldEditor",
  "editor_toggle",
  "toggle_world_editor",
  "editorActivate",
  "editorDeactivate",
  "toggleCamera",
  "editorToggleActive",
}

local filtered = nil
local lastNotice = 0
local closing = false

local function isOwner()
  local st = extensions.raceManager_state
  if not (st and st.get) then return false end
  local me = st.get().me
  return me and me.role == "owner"
end

local function filterActions(on)
  on = on and true or false
  if filtered == on then return end
  filtered = on
  pcall(function()
    local f = core_input_actionFilter
    if not f then return end
    for i = 1, #ACTIONS do
      local name = ACTIONS[i]
      -- BeamNG has used both (filterId, action, enabled) and (action, enabled)
      if f.addAction then
        pcall(f.addAction, f, 0, name, on)
        pcall(f.addAction, 0, name, on)
        pcall(f.addAction, name, on)
      end
      if f.setActionEnabled then
        pcall(f.setActionEnabled, name, not on)
      end
    end
  end)
  -- Also try the input system action filter used by some builds
  pcall(function()
    if ActionMap and ActionMap.enableBindingsExceptFilter then
      -- no-op: keep map, we only filter named actions above
    end
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
  if not open then
    pcall(function()
      -- Some builds expose this through extensions
      local e = extensions and (extensions.editor or extensions.core_editor)
      if e and e.isActive and e.isActive() then open = true end
    end)
  end
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
  local now = os.clock()
  if now - lastNotice < 2.5 then return end
  lastNotice = now
  pcall(function()
    if extensions.raceManager_state and extensions.raceManager_state.notice then
      extensions.raceManager_state.notice("World Editor is locked on this server.")
    end
  end)
end

function M.sync()
  if isOwner() then
    filterActions(false)
    return
  end
  filterActions(true)
  if editorIsOpen() then
    closeEditor()
    noticeBlocked()
  end
end

function M.onUpdate()
  if isOwner() then
    if filtered then filterActions(false) end
    return
  end
  if filtered ~= true then filterActions(true) end
  if editorIsOpen() then
    closeEditor()
    noticeBlocked()
  end
end

function M.onEditorActivated()
  if isOwner() then return end
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
  if isOwner() then return end
  closeEditor()
  noticeBlocked()
end

function M.onWorldEditorToggled()
  if isOwner() then return end
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
