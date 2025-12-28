local reactor_mod = require("reactor")
local controller_mod = require("controller")

local function main()
  local reactors = reactor_mod.initAll()
  local controller = controller_mod.new(reactors)

  controller:shutdown()
end

main()
