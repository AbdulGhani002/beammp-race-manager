-- just enough JSON for the harness. the real server uses nlohmann through
-- Util.JsonEncode, this only has to round trip the same shapes.
local J = {}

local BS = string.char(92)

local ESC = {
  ['"']  = BS .. '"',
  [BS]   = BS .. BS,
  ["\n"] = BS .. "n",
  ["\r"] = BS .. "r",
  ["\t"] = BS .. "t",
}

local CTRL = "[%c" .. '"' .. BS .. "]"

local function quote(s)
  return '"' .. s:gsub(CTRL, function(c)
    return ESC[c] or (BS .. "u%04x"):format(c:byte())
  end) .. '"'
end

local function isArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  if n == 0 then return false end
  for i = 1, n do if t[i] == nil then return false end end
  return true, n
end

local function enc(v, out)
  local ty = type(v)
  if v == nil then
    out[#out + 1] = "null"
  elseif ty == "boolean" then
    out[#out + 1] = tostring(v)
  elseif ty == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      out[#out + 1] = "null"
    elseif math.type and math.type(v) == "integer" then
      out[#out + 1] = tostring(v)
    else
      out[#out + 1] = ("%.14g"):format(v)
    end
  elseif ty == "string" then
    out[#out + 1] = quote(v)
  elseif ty == "table" then
    local arr, n = isArray(v)
    if arr then
      out[#out + 1] = "["
      for i = 1, n do
        if i > 1 then out[#out + 1] = "," end
        enc(v[i], out)
      end
      out[#out + 1] = "]"
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      out[#out + 1] = "{"
      for i = 1, #keys do
        if i > 1 then out[#out + 1] = "," end
        out[#out + 1] = quote(tostring(keys[i])) .. ":"
        enc(v[keys[i]], out)
      end
      out[#out + 1] = "}"
    end
  else
    out[#out + 1] = "null"
  end
end

function J.encode(t)
  local out = {}
  enc(t, out)
  return table.concat(out)
end

local pos, str

local function skip()
  while true do
    local c = str:sub(pos, pos)
    if c == " " or c == "\n" or c == "\t" or c == "\r" then pos = pos + 1 else break end
  end
end

local UNESC = { n = "\n", r = "\r", t = "\t", b = "\b", f = "\f" }
UNESC['"'] = '"'
UNESC[BS]  = BS
UNESC["/"] = "/"

local function value()
  skip()
  local c = str:sub(pos, pos)

  if c == "{" then
    pos = pos + 1
    local t = {}
    skip()
    if str:sub(pos, pos) == "}" then pos = pos + 1 return t end
    while true do
      skip()
      local k = value()
      skip()
      pos = pos + 1                       -- colon
      t[k] = value()
      skip()
      local d = str:sub(pos, pos)
      pos = pos + 1
      if d == "}" then return t end
    end

  elseif c == "[" then
    pos = pos + 1
    local t, n = {}, 0
    skip()
    if str:sub(pos, pos) == "]" then pos = pos + 1 return t end
    while true do
      n = n + 1
      t[n] = value()
      skip()
      local d = str:sub(pos, pos)
      pos = pos + 1
      if d == "]" then return t end
    end

  elseif c == '"' then
    local out, i = {}, pos + 1
    while true do
      local ch = str:sub(i, i)
      if ch == '"' or ch == "" then break end
      if ch == BS then
        local nx = str:sub(i + 1, i + 1)
        if nx == "u" then
          out[#out + 1] = string.char(tonumber(str:sub(i + 2, i + 5), 16) % 256)
          i = i + 6
        else
          out[#out + 1] = UNESC[nx] or nx
          i = i + 2
        end
      else
        out[#out + 1] = ch
        i = i + 1
      end
    end
    pos = i + 1
    return table.concat(out)

  elseif str:sub(pos, pos + 3) == "true" then
    pos = pos + 4 return true
  elseif str:sub(pos, pos + 4) == "false" then
    pos = pos + 5 return false
  elseif str:sub(pos, pos + 3) == "null" then
    pos = pos + 4 return nil
  end

  local s, e = str:find("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
  if not s then return nil end
  local num = tonumber(str:sub(s, e))
  pos = e + 1
  return num
end

function J.decode(s)
  if type(s) ~= "string" or s == "" then return nil end
  str, pos = s, 1
  local ok, res = pcall(value)
  if not ok then return nil end
  return res
end

return J
