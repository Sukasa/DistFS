local function DoDistFS()
  local dfs = require("distfs")
  local fs = require("filesystem")
  local io = require("io")

  if not fs.exists("/lib/distfs.lua") then
    io.stderr:write("DistFS missing!  Unable to load DistFS")
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

  local function toBool(s)
    return s:lower() == "true"
  end

  for line in io.lines("/etc/distfs/distfs.cfg") do 
    local d = split(line)
    dfs[d[1]] = toBool(d[2])
  end

  dfs.init()

end

local success, err = pcall(DoDistFS)

if not success then
  --io.stderr:write("Failed to initialize DistFS: " .. err)
end