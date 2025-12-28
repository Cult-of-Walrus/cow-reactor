local log = require("logger").new("REACTOR")
local comp = require("component")
local status = require("status")
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
    curr_heat = chamber.getHeat,
    max_heat = chamber.getMaxHeat(),
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
    return false, status.DEPLETED_COOLANT
  end

  if self:hasDepletedFuelRod() then
    return false, status.DEPLETED_FUEL
  end

  local heat_pct = self:curr_heat() / self.max_heat
  if heat_pct > MAX_OPERATING_HEAT_PCT then
    return false, status.OVERHEATED
  end

  return true, status.OK
end

function methods:enable(enabled)
  self.chamber.setActive(enabled)
end

function methods:run()
  self:enable(true)
  local reason = status.UNKNOWN

  while true do
    local ok, stop_reason = self:isOk()
    if not ok then
      reason = stop_reason
      break
    end

    os.sleep(0.5) -- avoid tight loops?
  end

  self:enable(false)
  return reason
end

return reactor
