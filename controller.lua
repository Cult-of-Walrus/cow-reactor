local log = require("logger").new("CONTROLLER")
local controller = {}
local methods = {}

function controller.new(reactors)
  log:info("Initializing controller")

  local instance = {
    reactors = reactors,
  }

  return setmetatable(instance, {
    __index = methods
  })
end

function methods:shutdown()
  log:info("Shutting down all reactors")
  for _, r in ipairs(self.reactors) do
    r:enable(false)
  end

  -- TODO: do final swap
end

return controller
