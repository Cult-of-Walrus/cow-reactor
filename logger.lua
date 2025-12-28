local component = require("component")
local gpu = component.gpu

local logger = {}
local methods = {}

local COLORS = {
  RESET = 0xFFFFFF, -- White
  INFO  = 0x00FF00, -- Green
  WARN  = 0xFFAA00, -- Orange/Gold
  ERR   = 0xFF0000  -- Red
}

function logger.new(prefix)
  local instance = { prefix = prefix }
  setmetatable(instance, { __index = methods })
  return instance
end

local function log(prefix, label, msg, color)
  local oldColor = gpu.getForeground()
  gpu.setForeground(color)
  io.write("[" .. prefix .. "] [" .. label .. "]: ")
  gpu.setForeground(COLORS.RESET)
  print(msg)
  gpu.setForeground(oldColor)
end

function methods:info(msg)
  log(self.prefix, "INFO", msg, COLORS.INFO)
end

function methods:warn(msg)
  log(self.prefix, "WARNING", msg, COLORS.WARN)
end

function methods:err(msg)
  log(self.prefix, "ERROR", msg, COLORS.ERR)
end

return logger
