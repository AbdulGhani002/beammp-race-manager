RM = RM or {}
RM.serverconfig = {}

-- The BeamMP server rewrites ServerConfig.toml every time it starts. With
-- the disk full it opens the file for writing, which empties it, and then
-- cannot write it back, so the next start comes up on the default map with
-- no AuthKey and nobody can join. It happened on the 12th and again on the
-- 14th, and both times the key had to be found and pasted back by hand.
--
-- So a copy of the last good file is kept beside the plugin's own data, and
-- an empty one is put back from the copy, now and every minute until the
-- disk lets it. The copy never leaves the server.

RM.serverconfig.FILE = "ServerConfig.toml"
RM.serverconfig.COPY = "Resources/Server/RaceManager/data/ServerConfig.toml.bak"

-- a config with a key and a map in it is never this short
local REAL = 100
local EVERY = 60

-- healthy means long enough and with an AuthKey in it. A config typed in
-- by hand with the key still to come is not the one to keep a copy of.
local function healthy(body)
  return type(body) == "string" and #body > REAL
     and body:match('AuthKey%s*=%s*"[^"]+"') ~= nil
end

local since = 0
local said = nil

local function readAll(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

local function say(what, line)
  if said == what then return end
  said = what
  if what == "restored" then RM.warn(line) else RM.error(line) end
end

-- "ok" when the file is healthy, "restored" when it was empty and the copy
-- went back, "waiting" when it is empty and the disk will not take the copy
-- yet, "nocopy" when it is empty and there is nothing to put back, "nokey"
-- when it is written out but has no AuthKey, and "absent" when there is no
-- such file at all, which is somebody else's setup and not ours to touch.
function RM.serverconfig.check()
  local live = readAll(RM.serverconfig.FILE)
  if live == nil then return "absent" end

  if healthy(live) then
    if readAll(RM.serverconfig.COPY) ~= live then
      RM.store.writeFileAtomic(RM.serverconfig.COPY, live, true)
    end
    said = nil
    return "ok"
  end

  -- written out but without a key: left as it is, said once
  if #live > REAL then
    say("nokey", RM.serverconfig.FILE .. " has no AuthKey in it. Put the key in and restart.")
    return "nokey"
  end

  local copy = readAll(RM.serverconfig.COPY)
  if not healthy(copy) then
    say("nocopy", RM.serverconfig.FILE .. " is empty and there is no copy to put back. "
      .. "The disk was full when the server started. Put the AuthKey, Map and the rest back by hand before the next restart.")
    return "nocopy"
  end

  if RM.store.writeFileAtomic(RM.serverconfig.FILE, copy, true) then
    say("restored", RM.serverconfig.FILE .. " was empty, the disk was full when the server started, "
      .. "and it has been put back from the copy in " .. RM.serverconfig.COPY)
    return "restored"
  end

  say("waiting", RM.serverconfig.FILE .. " is empty and the copy cannot be written back yet. "
    .. "Is the disk full? Trying again every minute.")
  return "waiting"
end

function RM.serverconfig.tick(dt)
  since = since + (tonumber(dt) or 0)
  if since < EVERY then return end
  since = 0
  RM.serverconfig.check()
end

function RM.serverconfig.reset()
  since, said = 0, nil
end
