local comp = require("component")
local log = require("logger").new("CONTROLLER")
local controller = {}
local methods = {}

local function findTransposer()
  local address = comp.list("transposer", true)()

  if address then
    return comp.proxy(address)
  end

  log:err("No transposer found!")
  os.exit(1)
end

function controller.new(reactors)
  log:info("Initializing controller")

  local instance = {
    reactors = reactors,
    transposer = findTransposer()
  }

  return setmetatable(instance, { __index = methods })
end

function methods:shutdown()
  log:info("Shutting down all reactors")
  for _, r in ipairs(self.reactors) do
    r:enable(false)
  end
end

return controller
