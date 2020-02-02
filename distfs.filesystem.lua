local event = require("event")
local component = require("component")
local io = require("io")
local os = require("os")

fs = {}

-- Default configuration
fs.raidsOnly = true
fs.allowHotplug = true
fs.arrayMaster = false
fs.bootSync = false
fs.addSync = false

function fs.componentAdded(eventId, componentPath, componentType)
  if componentType == "filesystem" then
    for i = 1, #fs.filesystems do
      if fs.filesystems[i].address == componentPath then
        return -- Don't re-add filesystems if they're already in.
      end
    end
    local sys = component.proxy(componentPath)
    if (not fs.raidsOnly) or sys.getLabel() == "raid" then
      table.insert(fs.filesystems, sys)
      if eventId == "component_added" and fs.arrayMaster and fs.addSync then
        fs.syncFilesystems()
      end
      if eventId == "init" then
        --io.write("> .. Mounted FS " .. componentPath .. "\n")
      end
    end
  end
end

function fs.syncFilesystems()
  if not fs.arrayMaster then return false, "Not array master" end
  local folderList = { "/" }
  
  -- Build a list of all folders on all drives
  for i = 1,#folderList do
    local path = folderList[i]
    
    local search = {}
    for _,system in pairs(fs.filesystems) do
      local sysFiles = system.list(path)
      for _,file in ipairs(sysFiles) do
        local filePath = path..file
        if system.isDirectory(filePath) then
          if not fs.contains(search, filePath) then
            table.insert(search, filePath)
            table.insert(folderList, filePath)
          end
        end
      end
      --os.sleep(0.05)
    end
    
  end
  
  -- Ensure each of these folders exists on every drive
  for _, folder in ipairs(folderList) do
    for _, system in ipairs(fs.filesystems) do
      system.makeDirectory(folder)
    end
    --os.sleep(0.05)
  end
  
  return true
end

function fs.init()
  fs.handles = {}
  fs.filesystems = {}
  --io.write("> . Performing DistFS initialization...\n")
  if fs.restrictedMode then
    for k,_ in pairs(component.list("filesystem")) do
      if fs.contains(fs.restricted, k) then
        fs.componentAdded("init", k, "filesystem")
      end
    end
  else  
    for k,_ in pairs(component.list("filesystem")) do
      fs.componentAdded("init", k, "filesystem")
    end
  end
  if fs.allowHotplug then event.listen("component_added", fs.componentAdded) end
  if fs.bootSync and fs.arrayMaster then
    --io.write("> . Performing DistFS synchronization...\n")
    fs.syncFilesystems()
  end
  
  --io.write("> . DistFS ready!  Spanning " .. #fs.filesystems .. " volumes.\n")
end

function fs.contains(haystack, needle)
  for i=1,#haystack do
    if haystack[i] == needle then return true end
  end
  return false
end

function fs.merge(outTable, table2)
  for src = 1, #table2 do
    if not fs.contains(outTable, table2[src]) then table.insert(outTable, table2[src]) end
  end
end

function fs.mostFreeSpace()
  -- Return whichever FS has the most free space available
  local avail = 0
  local sys = nil
  for _,system in pairs(fs.filesystems) do
    local a = system.spaceTotal() - system.spaceUsed()
    if a > avail then
      avail = a
      sys = system
    end
  end
  return sys
end

function fs.findFile(path)
  -- Search through filesystems until I find the file we're looking for and return the filesystem containing it
  for _, sys in pairs(fs.filesystems) do
    if sys.exists(path) then return sys end
  end
  return nil
end

-- Proxy Objects for FS Component --

fs.proxy = {}
fs.proxy.address = "62645f02-a97d-4e3a-8c1d-7f88f4dacbc2"

function fs.proxy.spaceUsed()
  local used = 0
  for _,system in pairs(fs.filesystems) do
    used = used + system.spaceUsed()
  end
  return used
end

function fs.proxy.open(path, mode)
  if #fs.filesystems == 0 then return nil, "No spanned volumes" end
  -- Either open the file on its existing filesystem, create it on the FS with the most free space, or fail if we're trying to open something non-existent for reading
  
  checkArg(1, path, "string")
  checkArg(2, mode, "string", "nil")
  
  mode = tostring(mode or "r")
  local bRead = mode:match("[ra]")
  local bWrite = mode:match("[wa]")

  if not bRead and not bWrite then
    return nil, "invalid mode"
  end
  
  local system = fs.findFile(path)
  local handle, err
  
  if system ~= nil then
    handle, err = system.open(path, mode)
  else
    if bRead and not bWrite then
      return nil, path .. "does not exist"
    end
    
    system = fs.mostFreeSpace()
    handle, err = system.open(path, mode)
  end
  
  -- Associate the file handle with the FS in fs.handles
  if handle ~= nil then
    fs.handles[handle] = system
  end
  
  return handle, err
end

function fs.proxy.seek(handle, whence, offset)
  if fs.handles[handle] == nil then
    return false, "unknown file handle"
  end
  fs.handles[handle].seek(handle, whence, offset)
end

function fs.proxy.makeDirectory(path)
  if #fs.filesystems == 0 then return false, "No spanned volumes" end
  local okay = true
  for _,system in pairs(fs.filesystems) do
    okay = okay and ((not system.exists(path)) or system.isDirectory(path))
  end
  
  if not okay then return false end
  
  for _,system in pairs(fs.filesystems) do
    okay = okay and (system.isDirectory(path) or system.makeDirectory(path))
  end
  
  return okay
end

function fs.proxy.exists(path)
  if #fs.filesystems == 0 then return nil, "No spanned volumes" end
  for _,system in pairs(fs.filesystems) do
    if system.exists(path) then return true end
  end
  return false
end

function fs.proxy.isReadOnly()
  return false
end

function fs.proxy.write(handle, value)
  if #fs.filesystems == 0 then return nil, "No spanned volumes" end
  if fs.handles[handle] == nil then
    return false, "unknown file handle"
  end
  return fs.handles[handle].write(handle, value)
end

function fs.proxy.spaceTotal()
  local total = 0
  for _,system in pairs(fs.filesystems) do
    total = total + system.spaceTotal()
  end
  return total
end

function fs.proxy.isDirectory(path)
  if #fs.filesystems == 0 then return nil, "No spanned volumes" end
  return fs.filesystems[1].isDirectory(path) -- this relies on the filesystems being in sync
end

function fs.proxy.rename(from, to)
  if fs.proxy.exists(to) then
    return false, "target file already exists"
  else
    local srcsys = fs.findFile(from)
    if srcsys == nil then return false, "source file doesn't exist" end
    return srcsys.rename(from, to)
  end
end

function fs.proxy.list(path)
  if #fs.filesystems == 0 then return nil, "No spanned volumes" end
  local list = {}
  -- Get a list of all files from every fs for this folder and return it
  for _, sys in pairs(fs.filesystems) do
    local add = sys.list(path)
    if add ~= nil then
      fs.merge(list, sys.list(path))
    end
  end
  
  if #list == 0 then return nil end
  return list
end

function fs.proxy.lastModified(path)
  if #fs.filesystems == 0 then return nil, "No spanned volumes" end
  local sys = fs.findFile(path)
  if sys == nil then return nil, "file doesn't exist" end
  return sys.lastModified(path)
end

function fs.proxy.getLabel()
  return "DistFS"
end

function fs.proxy.remove(path)
  if #fs.filesystems == 0 then return false, "No spanned volumes" end
  local sys = fs.findFile(path)
  if sys == nil then return false, "file doesn't exist" end
  return sys.remove(path)
end

function fs.proxy.close(handle)
  if fs.handles[handle] == nil then
    return false, "unknown file handle"
  end
  local a, b = fs.handles[handle].close(handle)
  if a then fs.handles[handle] = nil end
  return a, b
end

function fs.proxy.size(path)
  if #fs.filesystems == 0 then return nil, "No spanned volumes" end
  local sys = fs.findFile(path)
  if sys == nil then return nil, "file doesn't exist" end
  return sys.size(path)
end

function fs.proxy.read(handle, count)
  if fs.handles[handle] == nil then
    return false, "unknown file handle"
  end
  return fs.handles[handle].read(handle, count)
end

function fs.proxy.setLabel(newLabel)
  return fs.proxy.getLabel() -- No.
end

-- Extra utility functions
function fs.proxy.sync()
  fs.syncFilesystems()
end

return fs