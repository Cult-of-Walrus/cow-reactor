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

function reactor.init_all()
  local reactors = {}

  log:info("Searching for reactors...")
  local chambers = find_chambers()
  log:info("Found " .. #chambers .. " reactor chamber/s")

  for index, chamber in ipairs(chambers) do
    table.insert(reactors, reactor.new(index .. "-" .. string.sub(chamber.address, 1, 8), chamber))
  end

  return reactors
end

function reactor.new(name, chamber)
  log:info("Initializing reactor: " .. name)

  local instance = {
    name = name,
    chamber = chamber,
    status = chamber.producesEnergy() and "ACTIVE" or "IDLE",
    curr_heat = chamber.getHeat(),
    max_heat = chamber.getMaxHeat()
  }

  setmetatable(instance, { __index = methods })
  return instance
end

function methods:enable(status)
  self.chamber.setActive(status)
end

return reactor
