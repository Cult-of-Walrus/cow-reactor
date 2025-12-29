local log = require("logger").new("CONTROLLER")
local comp = require("component")
local side = require("sides")
local thread = require("thread")

local controller = {}
local methods = {}

local REDSTONE_COOLANT_SIDE = side.south
local REDSTONE_FUEL_SIDE = side.north

function controller.new(reactors)
  log:info("Initializing controller")

  if not comp.isAvailable("redstone") then
    log:err("No redstone I/O detected!")
    os.exit(1)
  end

  comp.redstone.setOutput({ 0, 0, 0, 0, 0, 0 })

  return setmetatable({
    reactors = reactors,
    io = comp.redstone,
    threads = {},
    is_swapping = false
  }, { __index = methods })
end

function methods:swapCells()
  log:info("Swapping all hot coolant cells")
  self.io.setOutput(REDSTONE_COOLANT_SIDE, 15)
  os.sleep(0.1)
  self.io.setOutput(REDSTONE_COOLANT_SIDE, 0)
end

function methods:swapRods()
  log:info("Swapping all depleted fuel rods")
  self.io.setOutput(REDSTONE_FUEL_SIDE, 15)
  os.sleep(0.1)
  self.io.setOutput(REDSTONE_FUEL_SIDE, 0)
end

function methods:allReactorsOk()
  for _, r in ipairs(self.reactors) do
    local ok, reason = r:isOk()
    if not ok then
      log:warn("Reactor [" .. r.name .. "] is still not OK: " .. reason)
      return false
    end
  end
  return true
end

function methods:stopAll()
  log:info("Stopping all reactors")
  for _, t in ipairs(self.threads) do
    if t:status() ~= "dead" then t:kill() end
  end
  self.threads = {}
  for _, r in ipairs(self.reactors) do
    r:enable(false)
  end
end

function methods:shutdown()
  log:info("Shutdown initiated")

  self:stopAll()
  self.io.setOutput({ 0, 0, 0, 0, 0, 0 })

  log:info("Shutdown complete")
end

function methods:fix(reactor, reason)
  while self.is_swapping do
    os.sleep(0.05)
  end

  self.is_swapping = true
  os.sleep(0)    -- sync with mc world
  os.sleep(0.05) -- skip reactor tick

  if reason == "DEPLETED_COOLANT" then
    self:swapCells()
  elseif reason == "DEPLETED_FUEL" then
    self:swapRods()
  end

  log:info("Waiting for reactor [" .. reactor.name .. "]")
  while true do
    local ok, _ = reactor:isOk()
    if ok then
      break
    end

    os.sleep(1)
  end

  self.is_swapping = false
end

function methods:manage()
  log:info("Starting independent reactor management")
  for _, r in ipairs(self.reactors) do
    local t = thread.create(function(target, ctrl)
      target:run(ctrl)
    end, r, self)
    table.insert(self.threads, t)
  end

  while true do
    os.sleep(1000) -- keep alive
  end
end

return controller
