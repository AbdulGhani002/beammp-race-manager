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

-- Write beside, swap in, and keep the copy from before the save. A crash at
-- any point leaves either the old file or the new one, never a half file and
-- never nothing.
--
-- The backup is kept rather than tidied away. It used to be deleted the
-- moment the swap succeeded, which meant the recovery in load below had
-- nothing to recover from: a file that went empty between restarts was a
-- silent fresh start, and every name, level and record on it was gone.
-- noBackup: the old file is dropped rather than kept as .bak, for a file
-- that is itself a copy, or one that is not the store's to leave copies of
local function writeFileAtomic(path, body, noBackup)
  local tmp = path .. ".tmp"
  local bak = path .. ".bak"

  local f, err = io.open(tmp, "wb")
  if not f then
    RM.error("cannot open", tmp, err)
    return false
  end
  -- A full disk is the one failure that hides: a small write sits in the
  -- buffer and looks done, the flush fails on the way out, and the file
  -- lands empty. So every step is checked, and what landed is measured
  -- against what was sent before the old file is touched. His mods filled
  -- the disk and the store found out this way.
  local wrote, werr = f:write(body)
  local flushed, ferr = f:flush()
  local closed, cerr = f:close()
  if not wrote or not flushed or not closed then
    RM.error(("write failed for %s: %s"):format(tmp, tostring(werr or ferr or cerr or "unknown")))
    FS.Remove(tmp)
    return false
  end
  local check = io.open(tmp, "rb")
  local size = check and check:seek("end") or -1
  if check then check:close() end
  if size ~= #body then
    RM.error(("write of %s came up short: %d of %d bytes. Is the disk full?"):format(tmp, size, #body))
    FS.Remove(tmp)
    return false
  end

  local had = FS.Exists(path)
  if had and noBackup then
    FS.Remove(path)
    had = false
  elseif had then
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

  -- and the backup stays, on purpose. one extra copy per store is nothing
  -- against starting from nothing.
  return true
end

local function decodeOr(body)
  if not body or body == "" then return nil end
  local ok, decoded = pcall(Util.JsonDecode, body)
  if not ok or type(decoded) ~= "table" then return nil end
  return decoded
end

-- The saved file, or the copy from before the last save when the saved one is
-- missing, empty or will not decode. Returns the table and whether it came
-- from the backup.
--
-- A store that will not read is never quietly replaced with an empty one while
-- a good backup is sitting beside it. That is the whole point of keeping it.
local function readStore(name)
  local path = pathFor(name)
  local body = readFile(path)

  local found = decodeOr(body)
  if found then return found, false end

  if body and body ~= "" then
    -- it had something in it and we could not read it, so it is kept rather
    -- than written over
    local kept = path .. ".corrupt." .. tostring(os.time())
    FS.Copy(path, kept)
    RM.error("store '" .. name .. "' would not decode; kept a copy at " .. kept)
  end

  local bak = path .. ".bak"
  if not FS.Exists(bak) then return nil, false end

  local fromBak = decodeOr(readFile(bak))
  if not fromBak then
    RM.error("store '" .. name .. "' backup would not read either")
    return nil, false
  end

  -- The unreadable file goes, and anything worth keeping from it was copied
  -- aside above. Leaving it there would let the next save rotate it into the
  -- backup slot and throw away the only good copy we have.
  FS.Remove(path)
  return fromBak, true
end

-- the same careful write, for files that are not the store's own
RM.store.writeFileAtomic = writeFileAtomic

function RM.store.load(name, default)
  if cache[name] then return cache[name] end
  ensureDir()

  local found, recovered = readStore(name)
  if found then
    cache[name] = found
    if recovered then
      -- written back on the next save, so the good copy is the saved one again
      dirty[name] = true
      RM.warn("store '" .. name .. "' was unreadable and came back from its backup")
    else
      RM.info("store '" .. name .. "' loaded")
    end
    return cache[name]
  end

  cache[name] = default or {}
  dirty[name] = true
  RM.info("store '" .. name .. "' created")
  return cache[name]
end

function RM.store.get(name) return cache[name] end

-- Drop a store from memory so the next load reads disk again. The recovery
-- above only happens on a load, and without this there is no way to reach it
-- except by restarting the server, which is not a thing a test can do.
function RM.store.forget(name)
  cache[name] = nil
  dirty[name] = nil
end

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

-- a store that will not save is said once a minute, not every half minute
-- until the disk is fixed, and said again the moment it saves
local failing = {}

function RM.store.flushDirty()
  local n = 0
  for name in pairs(dirty) do
    if RM.store.flushNow(name) then
      n = n + 1
      if failing[name] then
        RM.info("store '" .. name .. "' saved again")
        failing[name] = nil
      end
    else
      failing[name] = (failing[name] or 0) + 1
      if failing[name] == 1 or failing[name] % 10 == 0 then
        RM.warn(("store '%s' has not saved %d time(s) running; everything done since is only in memory"):format(
          name, failing[name]))
      end
    end
  end
  return n
end

function RM.store.failing() return failing end

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
