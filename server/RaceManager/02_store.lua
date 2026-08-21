RM = RM or {}
RM.store = {}

-- data lives in a subfolder on purpose: BeamMP reloads the lua state when a
-- file changes directly in the plugin folder.
local DIR = "Resources/Server/RaceManager/data"

local cache = {}
local dirty = {}

local function pathFor(name) return DIR .. "/" .. name .. ".json" end

local function ensureDir()
  if not FS.Exists(DIR) then
    local ok, err = FS.CreateDirectory(DIR)
    if not ok then RM.error("cannot create data dir:", err) end
  end
end

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

-- write beside, swap in, keep the old copy until the swap is done. a crash at
-- any point leaves either the old file or the new one, never a half file and
-- never nothing.
local function writeFileAtomic(path, body)
  local tmp = path .. ".tmp"
  local bak = path .. ".bak"

  local f, err = io.open(tmp, "wb")
  if not f then
    RM.error("cannot open", tmp, err)
    return false
  end
  local wrote = f:write(body)
  f:flush()
  f:close()
  if not wrote then
    RM.error("write failed for", tmp)
    FS.Remove(tmp)
    return false
  end

  local had = FS.Exists(path)
  if had then
    FS.Remove(bak)
    if not FS.Rename(path, bak) then
      RM.error("cannot move", path, "aside")
      FS.Remove(tmp)
      return false
    end
  end

  if not FS.Rename(tmp, path) then
    RM.error("cannot move", tmp, "into place")
    if had then FS.Rename(bak, path) end
    FS.Remove(tmp)
    return false
  end

  if had then FS.Remove(bak) end
  return true
end

function RM.store.load(name, default)
  if cache[name] then return cache[name] end
  ensureDir()

  local body = readFile(pathFor(name))

  -- a previous run died between the two renames, so the only copy is the backup
  if (not body or body == "") and FS.Exists(pathFor(name) .. ".bak") then
    RM.warn("store '" .. name .. "' recovered from backup")
    body = readFile(pathFor(name) .. ".bak")
  end

  if not body or body == "" then
    cache[name] = default or {}
    dirty[name] = true
    RM.info("store '" .. name .. "' created")
    return cache[name]
  end

  local ok, decoded = pcall(Util.JsonDecode, body)
  if not ok or type(decoded) ~= "table" then
    -- never quietly start fresh on top of a file we failed to read
    local backup = pathFor(name) .. ".corrupt." .. tostring(os.time())
    FS.Copy(pathFor(name), backup)
    RM.error("store '" .. name .. "' would not decode; kept a copy at " .. backup)
    cache[name] = default or {}
    dirty[name] = true
    return cache[name]
  end

  cache[name] = decoded
  RM.info("store '" .. name .. "' loaded")
  return cache[name]
end

function RM.store.get(name) return cache[name] end

function RM.store.markDirty(name) dirty[name] = true end

function RM.store.isDirty(name) return dirty[name] == true end

function RM.store.flushNow(name)
  local t = cache[name]
  if not t then return false end
  ensureDir()
  local ok, encoded = pcall(Util.JsonEncode, t)
  if not ok then
    RM.error("store '" .. name .. "' would not encode:", encoded)
    return false
  end
  local written = writeFileAtomic(pathFor(name), Util.JsonPrettify(encoded))
  if written then dirty[name] = nil end
  return written
end

function RM.store.flushDirty()
  local n = 0
  for name in pairs(dirty) do
    if RM.store.flushNow(name) then n = n + 1 end
  end
  return n
end

function RM.store.flushAll()
  local n = 0
  for name in pairs(cache) do
    if RM.store.flushNow(name) then n = n + 1 end
  end
  return n
end

function RM.store.names()
  local out, n = {}, 0
  for name in pairs(cache) do n = n + 1; out[n] = name end
  table.sort(out)
  return out
end
