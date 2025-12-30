local log = require("logger").new("SYSTEM")
local comp = require("component")
local event = require("event")

local function main()
  if not comp.isAvailable("redstone") then
    log:err("No redstone I/O detected!")
    os.exit(1)
  end

  comp.redstone.setOutput({ 0, 0, 0, 0, 0, 0 })

  local reactors = require("reactor").getAll()
  local controller = require("controller").new(reactors)

  local runner = require("thread").create(function()
    controller:manage()
  end)

  local _ = event.pull("interrupted")

  runner:kill()
  controller:shutdown()
end

pcall(main)
