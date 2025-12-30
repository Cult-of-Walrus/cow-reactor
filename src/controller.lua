local log = require("logger").new("CONTROLLER")
local comp = require("component")
local thread = require("thread")
local cfg = require("config")

local controller = {}
local methods = {}

function controller.new(reactors)
  log:info("Initializing controller")

  local lsc = nil
  if comp.isAvailable("gt_machine") and comp.gt_machine.getName() ~= "multimachine.supercapacitor" then
    log:warn("No LSC detected! Running without")
  else
    lsc = comp.gt_machine
  end

  return setmetatable({
    reactors = reactors,
    io = comp.redstone,
    threads = {},
    is_swapping = false,
    lsc = lsc,
  }, { __index = methods })
end

function methods:emergency()
  self.io.setOutput(cfg.REDSTONE_ALARM_SIDE, 15)
  self:stopAll()
  while true do
    os.sleep(1000) -- keep alive
  end
end

function methods:swapCells()
  log:info("Swapping all hot coolant cells")
  self.io.setOutput(cfg.REDSTONE_COOLANT_SIDE, 15)
  os.sleep(0.1)
  self.io.setOutput(cfg.REDSTONE_COOLANT_SIDE, 0)
end

function methods:swapRods()
  log:info("Swapping all depleted fuel rods")
  self.io.setOutput(cfg.REDSTONE_FUEL_SIDE, 15)
  os.sleep(0.1)
  self.io.setOutput(cfg.REDSTONE_FUEL_SIDE, 0)
end

function methods:allReactorsOk()
  for _, r in ipairs(self.reactors) do
    local ok, reason = r:isOk()
    if not ok then
      log:warn("Reactor [" .. r.name .. "] is still not OK: " .. reason)
      -- TODO: add alarm if this repeats
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
  else
    log:critical("[" .. reactor.name .. "]  has a critical error: " .. reason)
    self:emergency()
  end

  log:info("Waiting for reactor [" .. reactor.name .. "]")
  local retries = 0
  while true do
    local ok, current_reason = reactor:isOk()
    if ok then
      break
    end

    retries = retries + 1
    if retries > cfg.MAX_FIX_RETRIES then
      log:critical("[" .. reactor.name .. "] failed to recover after " .. cfg.MAX_FIX_RETRIES .. " retries!")
      self:emergency()
    end

    log:warn("[" .. reactor.name .. "] is still OFFLINE: " .. current_reason .. " (" .. retries .. ")")
    os.sleep(1)
  end

  self.is_swapping = false
end

function methods:manage()
  log:info("Starting reactor management")
  if cfg.MOX_MODE then
    log:warn("Running in MOX mode")
  end

  for _, r in ipairs(self.reactors) do
    local t = thread.create(function(target, ctrl)
      local ok, reason = target:isOk(ctrl)
      if ok then
        target:run(ctrl)
      else
        log:warn("Skipped [" .. target.name .. "] during startup: " .. reason)
      end
    end, r, self)
    table.insert(self.threads, t)
  end

  while true do
    os.sleep(1000) -- keep alive
  end
end

return controller
