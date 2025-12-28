local comp = require("component")
local log = require("logger").new("REACTOR")
local reactor = {}
local methods = {}

local MAX_OPERATING_HEAT_PCT = 0.5

local function findChambers()
  local reactor_chambers = {}

  for address in comp.list("reactor_chamber", true) do
    table.insert(reactor_chambers, comp.proxy(address))
  end

  if #reactor_chambers < 1 then
    log:err("No reactor chambers found!")
    os.exit(1)
  end

  return reactor_chambers
end

function reactor.initAll()
  local reactors = {}

  log:info("Searching for reactors...")
  local chambers = findChambers()
  log:info("Found " .. #chambers .. " reactor chamber/s")

  for index, chamber in ipairs(chambers) do
    table.insert(reactors, reactor.new(index .. "-" .. string.sub(chamber.address, 1, 8), chamber))
  end

  return reactors
end

function reactor.new(name, chamber)
  log:info("Initializing reactor: " .. name)
  chamber.setActive(false)

  local instance = {
    name = name,
    chamber = chamber,
    status = chamber.producesEnergy and "ACTIVE" or "IDLE",
    curr_heat = chamber.getHeat,
    max_heat = chamber.getMaxHeat,
    output = chamber.getReactorEUOutput
  }

  return setmetatable(instance, { __index = methods })
end

function methods:hasDepletedCoolant()
  error("Not Implemented", 2)
end

function methods:hasDepletedFuelRod()
  error("Not Implemented", 2)
end

function methods:isOk()
  if self:hasDepletedCoolant() then
    return false
  end

  if self:hasDepletedFuelRod() then
    return false
  end

  local threshold = self:max_heat() / self:curr_heat()
  if threshold > MAX_OPERATING_HEAT_PCT or threshold == math.huge then
    return false
  end
end

function methods:run()
  while self:isOk() do
  end
end

function methods:enable(enabled)
  self.chamber.setActive(enabled)
end

return reactor
