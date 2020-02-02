-- Installer / Configurer for DistFS
local io = require("io")
local os = require("os")
local fs = require("filesystem")
local shell = require("shell")
local computer = require("computer")
local serialization = require("serialization")
local component = require("component")

local folders = {
  "/etc/distfs"
}

local files = {
  ["distfs.boot.lua"] = "/boot/97_distfs.lua",
  ["distfs.filesystem.lua"] = "/lib/distfs.lua",
  ["distfs.version"] = "/etc/distfs/distfs.version"
}

function split(s)
  local fields = {}
  local pattern = string.format("([^%s]+)", ",")
  s:gsub(pattern, function(c) fields[#fields+1] = c end)
  return fields
end
  
function getYesNo(question, defaultYes)
  while true do
    local yesNo = "? [y/N] "
    if defaultYes then yesNo = "? [Y/n] " end
    io.write(question..yesNo)
    yesNo = io.read():lower()
    if yesNo == "y" then return true end
    if yesNo == "n" then return false end
    if yesNo == "" then return defaultYes end
  end
end

function getString(question)
  io.write(question..": ")
  return io.read()
end

local filePath = nil
for mountpoint in fs.list("/mnt") do
  if fs.exists("/mnt/" .. mountpoint .. "distfs.version") then
    filePath = "/mnt/" .. mountpoint .. "distfs.version"
    break
  end
end

if filePath == nil then
  print("Unable to locate install disk in mount structure")
  return
end

local install = false
local freshInstall = not fs.exists("/etc/distfs/distfs.cfg")

local sourcePath = fs.path(filePath)
local versionFile, err = io.open(filePath)

local version = "??"
if versionFile ~= nil then
  version = versionFile:read("*n")
  versionFile:close()
  versionFile = nil
else
  io.write("Error opening distfs.version: " .. err .. ".  Press enter to continue.")
  io.read()
end

os.execute("clear")

io.write("\n")
io.write("    ___    _        __   ______ _____ \n")
io.write("   / __ \\ (_)_____ / /_ / ____// ___/\n")
io.write("  / / / // // ___// __// /_    \\__ \\ \n")
io.write(" / /_/ // /(__  )/ /_ / __/   ___/ / \n")
io.write("/_____//_//____/ \\__//_/     /____/  \n")

io.write("\nDistFS v" .. version .. " for OpenOS by Sukasa\n")
io.write("\n")

if true then

  install = getYesNo("Install DistFS", true)

  if install then
    for _, folder in pairs(folders) do
      fs.makeDirectory(folder)
    end
  
    for src,dst in pairs(files) do
      io.write(src .. " -> " .. dst .. "\n")
      local command = "yes | cp " .. sourcePath .. src .. " " .. dst .. " > /dev/null"
      os.execute(command)      
    end
  end
  
  if not install and freshInstall then
    os.execute("clear")
    return
  end
  
  if install then
    io.write("\nInstalled DistFS v" .. version )
    io.write("\n")
  end
  
end

-- Now ask about options

local reconfigure = false
local configureMe = fs.exists("/etc/distfs/distfs.cfg")
local configString = "Configure"
if not freshInstall then configString = "Reconfigure" end

if (freshInstall and install) or (configureMe and getYesNo(configString .. " DistFS", true)) then
  reconfigure = true

  local restrictedMode = getYesNo("Use whitelist of RAID arrays", false)
  local raidOnly = (not restrictedMode) and getYesNo("Ignore local hard drives and disk drives", true)
  local allowHotplug = (not restrictedMode) and getYesNo("Allow hotplugging of new RAID units", true)
  local arrayMaster = getYesNo("System is array master", false)
  local bootSync = arrayMaster and getYesNo("Synchronize RAID arrays on boot", false)
  local addSync = arrayMaster and (not restrictedMode) and getYesNo("Synchronize RAID arrays on volume addition", true)

  local restricted = {}
  
  if restrictedMode then
    local doneAdding = false
    local idx = 1
    local UUIDs = {}
    print("Select which filesystems should be incorporated into the RAID: ")
    print("")
    
    for k,v in pairs(component.list("filesystem")) do
      print(tonumber(idx).. ") " .. k .. '("' .. component.proxy(k).getLabel() .. '")')
      UUIDs[idx] = k
      idx = idx + 1
    end
    
    local restrictedIndexes = split(getString("Select filesystems, separated by commas"))
    
    for k,v in ipairs(restrictedIndexes) do
      v = tonumber(v) or 0
      if v > 0 and v < idx then
        table.insert(restricted, UUIDs[v])
      end
    end 
  end
  
  local configFile = io.open("/etc/distfs/distfs.cfg", "w")
  configFile:write("raidOnly=" .. tostring(raidOnly) .."\n")
  configFile:write("arrayMaster=" .. tostring(arrayMaster) .."\n")
  configFile:write("allowHotplug=" .. tostring(allowHotplug) .."\n")
  configFile:write("restrictedMode=" .. tostring(restrictedMode) .."\n")
  configFile:write("restricted=" .. serialization.serialize(restricted) .."\n")
  configFile:write("bootSync=" .. tostring(bootSync) .."\n")
  configFile:write("addSync=" .. tostring(addSync) .."\n")
  configFile:close()  

  io.write("Wrote new DistFS configuration\n\n")

end

local reboot = false

if install then
  reboot = getYesNo("DistFS has been installed.\n\nReboot now", true)
end

if not install and reconfigure then
  reboot = getYesNo("DistFS has been reconfigured.\n\nReboot now", true)
end

if reboot then
  computer.shutdown(true)
else
  os.execute("clear")
end