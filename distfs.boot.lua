local function DoDistFS()
  local dfs = require("distfs")
  local fs = require("filesystem")
  local io = require("io")
  local serialization = require("serialization")

  if not fs.exists("/lib/distfs.lua") then
    io.stderr:write("Unable to load DistFS: DistFS library missing!")
    return
  end

  require("filesystem").mount(
    require("distfs").proxy
  , "/distfs")

  local function split(s)
    local fields = {}
    local pattern = string.format("([^%s]+)", "=")
    s:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
  end

  if not fs.exists("/etc/distfs/distfs.cfg") then
    io.stderr:write("DistFS configuration file missing!  Reverting to defaults...")
  end

  local function toValue(s)
    s = tostring(s)
    if tonumber(s) ~= nil then return tonumber(s) end
    local t = serialization.unserialize(s)
    if t ~= nil then return t end
    if s:lower() == "true" then return true end
    if s:lower() == "nil" then return nil end
    return false
  end

  for line in io.lines("/etc/distfs/distfs.cfg") do 
    local d = split(line)
    dfs[d[1]] = toValue(d[2])
  end

  dfs.init()

end

local success, err = pcall(DoDistFS)

if not success then
  --io.stderr:write("Failed to initialize DistFS: " .. err)
end