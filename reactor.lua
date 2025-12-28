local comp = require("component")
local log = require("logger").new("RCS")
local reactor = {}
local methods = {}

local function find_chambers()
  local reactor_chambers = {}

  for address in comp.list("reactor_chamber", true) do
    local proxy = comp.proxy(address)
    table.insert(reactor_chambers, proxy)
  end

  return reactor_chambers
end

local function find_all_redstone_ios()
  local redstone_ios = {}

  for address in comp.list("redstone", true) do
    local proxy = comp.proxy(address)
    table.insert(redstone_ios, proxy)
  end

  return redstone_ios
end

function reactor.init_all()
  local reactors = {}

  log:info("Searching for reactors...")
  local chambers = find_chambers()
  log:info("Found " .. #chambers .. " reactor chamber/s")
  local redstone_ios = find_all_redstone_ios()
  log:info("Found " .. #redstone_ios .. " redstone IO/s")

  for _, io in ipairs(redstone_ios) do
    io.setOutput({ 0, 0, 0, 0, 0, 0 })
  end

  for index, io in ipairs(redstone_ios) do
    log:debug("Searching for a chamber matching IO [" .. io.address .. "]")
    io.setOutput({ 15, 15, 15, 15, 15, 15 })

    os.sleep(0.5)

    local matched_chambers = {}
    for _, chamber in ipairs(chambers) do
      if chamber.producesEnergy() then
        table.insert(matched_chambers, chamber)
      end
    end

    if #matched_chambers > 1 then
      log:warn("IO [" .. io.address .. "] is powering " .. #matched_chambers .. " chambers! Skipping...")
    elseif #matched_chambers == 0 then
      log:warn("IO [" .. io.address .. "] matched no chambers")
    else
      local chamber = matched_chambers[1]
      log:info("Successfully matched IO [" .. io.address .. "] to chamber [" .. chamber.address .. "]")

      table.insert(reactors, reactor.new(index .. "-" .. string.sub(chamber.address, 1, 8), io, chamber))
    end

    io.setOutput({ 0, 0, 0, 0, 0, 0 })
  end

  return reactors
end

function reactor.new(name, io, chamber)
  log:info("Initializing reactor: " .. name)

  local instance = {
    name = name,
    io = io,
    chamber = chamber,
    status = chamber.producesEnergy() and "ACTIVE" or "IDLE",
    curr_heat = chamber.getHeat(),
    max_heat = chamber.getMaxHeat()
  }

  setmetatable(instance, { __index = methods })
  return instance
end

function methods:enable(status)
  self.io.setOutput({ status, status, status, status, status, status })
end

return reactor
