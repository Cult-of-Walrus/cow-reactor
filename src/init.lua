local log = require("lib.cow-logging.src.logger").new("SYSTEM")
local comp = require("component")
local event = require("event")
local thread = require("thread")

local function main()
  if comp.isAvailable("redstone") then
    comp.redstone.setOutput({ 0, 0, 0, 0, 0, 0 })
  else
    log:err("No redstone I/O detected!")
    return
  end

  log:warn("Make sure you have sufficient coolant in every reactor during startup!")
  os.sleep(5) -- grace period
  local reactors = require("reactor").getAll()
  local controller = require("controller").new(reactors)

  local runner = thread.create(function()
    controller:manage()
  end)

  local power_monitor = thread.create(function()
    local computer = require("computer")
    while true do
      if computer.energy() / computer.maxEnergy() < 0.5 then
        log:critical("Computer is losing power!")
        controller:emergency()
        os.exit()
      end

      os.sleep(5)
    end
  end)

  local _ = event.pull("interrupted")

  power_monitor:kill()
  runner:kill()
  controller:shutdown()
end

local ok, err = pcall(main)
if not ok then
  log:err(err)
end
