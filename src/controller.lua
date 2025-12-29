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
    threads = {}
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

function methods:manage()
  while true do
    log:info("Starting all reactors")

    for _, r in ipairs(self.reactors) do
      local t = thread.create(function(target)
        return target:run()
      end, r)
      table.insert(self.threads, t)
    end

    thread.waitForAny(self.threads)

    os.sleep(0) -- sync with minecraft ticks
    self:stopAll()
    self:swapCells()
    self:swapRods()

    log:info("Waiting for all systems clear...")
    while not self:allReactorsOk() do
      os.sleep(2)
    end

    log:info("All systems clear. Resuming...")
  end
end

return controller
