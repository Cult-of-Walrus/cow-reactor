local reactor_mod = require("reactor")
local controller_mod = require("controller")
local event = require("event")

local function main()
  local reactors = reactor_mod.getAll()
  local controller = controller_mod.new(reactors)

  local runner = require("thread").create(function()
    controller:manage()
  end)

  local _ = event.pull("interrupted")

  runner:kill()
  controller:shutdown()
end

local ok, err = pcall(main)
if not ok and err ~= "interrupted" then
  print(tostring(err))
end
