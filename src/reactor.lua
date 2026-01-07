local log = require("lib.cow-logging.src.logger").new("REACTOR_CHAMBER")
local comp = require("component")
local cfg = require("config")

local reactor = {}
local methods = {}

local STATUS = {
  OK = "OK",
  DEPLETED_FUEL = "DEPLETED_FUEL",
  DEPLETED_COOLANT = "DEPLETED_COOLANT",
  OVERHEATED = "OVERHEATED",
  WRONG_LAYOUT = "WRONG_LAYOUT",
  LOW_ENERGY = "LOW_ENERGY",
  ENERGY_FULL = "ENERGY_FULL",
  EXPLODED = "EXPLODED",
  UNKNOWN = "UNKNOWN"
}



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
      snapshots[inv.address] = hashOf(inv.getAllStacks(cfg.REACTOR_ADAPTER_TARGET_SIDE).getAll())
    end

    cham.setActive(true)
    os.sleep(0)
    os.sleep(1.00)
    cham.setActive(false)

    local found = false
    for _, inv in ipairs(controllers) do
      local newState = hashOf(inv.getAllStacks(cfg.REACTOR_ADAPTER_TARGET_SIDE).getAll())

      if newState ~= snapshots[inv.address] then
        table.insert(pairs, {
          chamber = cham,
          inventory = inv,
        })
        log:info("Mapped chamber [" .. nameOf(cham) .. "] to inventory controller [" .. nameOf(inv) .. "]")
        found = true
        break
      end
    end

    if not found then
      log:warn("Mapping failed for [" .. nameOf(cham) .. "]! Are you missing the controller or fuel?")
    end

    snapshots = nil
  end

  return pairs
end

function reactor.getAll()
  local reactors = {}

  log:info("Searching for reactors...")

  local components = findComponentPairs()
  if #components == 0 then
    log:err("No valid reactors found!")
    os.exit(1)
  end

  log:info("Found " .. #components .. " valid reactor/s")
  for _, c in ipairs(components) do
    table.insert(reactors, reactor.new(nameOf(c.chamber), c.chamber, c.inventory))
  end

  return reactors
end

function reactor.new(name, chamber, inventory)
  log:info("Initializing reactor [" .. name .. "]")
  chamber.setActive(false)

  local max_heat = chamber.getMaxHeat() -- caching it to minimize use of component api
  return setmetatable({
    name = name,
    chamber = chamber,
    inventory = inventory,
    curr_heat = chamber.getHeat,
    curr_heat_pct = chamber.getHeat() / max_heat,
    max_heat = max_heat,
    output = chamber.getReactorEUOutput
  }, { __index = methods })
end

function methods:hasDepletedFuelRod(inventory)
  for _, item in ipairs(inventory) do
    if cfg.KNOWN_ITEMS[item.name] == cfg.KNOWN_ITEMS.FUEL_ROD_DEPLETED then
      return true
    end
  end

  return false
end

function methods:hasDepletedCoolant(inventory)
  for _, item in pairs(inventory) do
    if cfg.KNOWN_ITEMS[item.name] == cfg.KNOWN_ITEMS.COOLANT_CELL then
      if item.damage / item.maxDamage >= cfg.MAX_COOLANT_DMG_PCT then
        return true
      end
    end
  end

  return false
end

function methods:hasWrongLayout(inventory)
  for slotIndex = 0, #cfg.LAYOUT - 1 do
    local item = inventory[slotIndex]
    if item.name == nil then
      log:warn("Reactor [" .. self.name .. "] slot " .. slotIndex .. " is empty")
      return true
    end

    local expected = cfg.LAYOUT[slotIndex + 1]
    local actual = cfg.KNOWN_ITEMS[item.name]

    if actual ~= expected then
      log:warn("Reactor [" .. self.name .. "] layout mismatch at slot " .. slotIndex)
      log:warn("Expected type " .. expected .. " but found " .. (actual or "UNKNOWN"))
      return true
    end
  end

  return false
end

function methods:isOk()
  local inv = self.inventory.getAllStacks(cfg.REACTOR_ADAPTER_TARGET_SIDE).getAll()

  if self:hasDepletedCoolant(inv) then
    return false, STATUS.DEPLETED_COOLANT
  end

  if self:hasDepletedFuelRod(inv) then
    return false, STATUS.DEPLETED_FUEL
  end

  if self:hasWrongLayout(inv) then
    return false, STATUS.WRONG_LAYOUT
  end

  if not cfg.MOX_MODE then
    if self.curr_heat_pct > cfg.MAX_OPERATING_HEAT_PCT then
      return false, STATUS.OVERHEATED
    end
  end

  if comp.proxy(self.chamber.address) == nil then
    return false, STATUS.EXPLODED
  end

  return true, STATUS.OK
end

function methods:enable(enabled)
  self.chamber.setActive(enabled)
end

function methods:run(controller)
  if cfg.MOX_MODE and self.curr_heat_pct < cfg.MOX_TARGET_OPERATING_HEAT_PCT then
    log:warn("Reactor [" .. self.name .. "] didn't reach MOX target heat")
  end

  while true do
    self:enable(true)
    log:info("Reactor [" .. self.name .. "] is now ONLINE")

    local reason = STATUS.UNKNOWN
    while true do
      controller:syncToTick()
      os.sleep(0.1)

      local ok, stop_reason = self:isOk()
      if not ok then
        reason = stop_reason
        break
      end
    end

    self:enable(false)
    log:info("Reactor [" .. self.name .. "] is now OFFLINE: " .. reason)

    controller:fix(self, reason)
  end
end

return reactor
