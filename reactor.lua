local log = require("logger").new("RCS")
local reactor = {}
local methods = {}

function reactor.findAll()
  log:info("Searching for reactors...")
end

function reactor.new(name)
  log:info("Initializing a new reactor: " .. name)

  local instance = {
    name = name,
    active = false
  }

  setmetatable(instance, { __index = methods })
  return instance
end

function methods:start()
  log:warn("Starting reactor: " .. self.name)
end

function methods:status()
  return "Online"
end

return reactor
