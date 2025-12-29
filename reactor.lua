local log = require("logger").new("REACTOR")
local comp = require("component")
local status = require("status")
local side = require("sides")
local reactor = {}
local methods = {}

local MAX_OPERATING_HEAT_PCT = 0.5
local TARGET_SIDE = side.top

local function nameOf(component)
  return string.sub(component.address, 1, 8)
end

local function hashOf(inventory)
  local hash = 2166136261
  for slot, item in pairs(inventory) do
    local data = string.format("%d%s%s",
      slot,
      item.name or "",
      item.tag or ""
    )

    for i = 1, #data do
      hash = (hash ~ string.byte(data, i)) * 16777619
      hash = hash % 4294967296
    end
  end
  return hash
end

local function findComponentPairs()
  local chambers = {}
  local controllers = {}
  local pairs = {}

  for addr in comp.list("reactor_chamber") do
    table.insert(chambers, comp.proxy(addr))
  end

  for addr in comp.list("inventory_controller") do
    table.insert(controllers, comp.proxy(addr))
  end

  for _, cham in ipairs(chambers) do
    local snapshots = {}
    for _, inv in ipairs(controllers) do
      snapshots[inv.address] = hashOf(inv.getAllStacks(TARGET_SIDE).getAll())
    end

    cham.setActive(true)
    os.sleep(1.02)
    cham.setActive(false)

    local found = false
    for _, inv in ipairs(controllers) do
      local newState = hashOf(inv.getAllStacks(TARGET_SIDE).getAll())

      if newState ~= snapshots[inv.address] then
        table.insert(pairs, {
          chamber = cham,
          inventory = inv,
          side = TARGET_SIDE
        })
        log:info("Mapped chamber [" .. nameOf(cham) .. "] to inventory controller [" .. nameOf(inv) .. "]")
        found = true
        break
      end
    end

    if not found then
      log:warn("Mapping failed for [" .. nameOf(cham) .. "]! Check for fuel and coolant")
    end

    snapshots = nil
  end

  return pairs
end

function reactor.initAll()
  local reactors = {}

  log:info("Searching for reactors...")
  local components = findComponentPairs()
  log:info("Found " .. #components .. " valid reactor/s")

  for _, c in ipairs(components) do
    table.insert(reactors, reactor.new(nameOf(c.chamber), c.chamber, c.inventory))
  end

  return reactors
end

function reactor.new(name, chamber, inventory)
  log:info("Initializing reactor [" .. name .. "]")
  chamber.setActive(false)

  local instance = {
    name = name,
    chamber = chamber,
    inventory = inventory,
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

    os.sleep(0)
  end

  self:enable(false)
  return reason
end

return reactor
