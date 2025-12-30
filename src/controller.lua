local log = require("logger").new("CONTROLLER")
local comp = require("component")
local thread = require("thread")
local cfg = require("config")

local controller = {}
local methods = {}

local function findBattery()
  local battery = nil

  if comp.isAvailable("gt_machine") and comp.gt_machine.getName() == "multimachine.supercapacitor" then
    battery = {
      current = comp.gt_machine.getEUStored,
      max = comp.gt_machine.getEUCapacity()
    }
  elseif comp.isAvailable("gt_batterybuffer") then
    local max = 0
    for i = 1, 16, 1 do
      if comp.gt_batterybuffer.getMaxBatteryCharge(i) ~= nil then
        max = max + comp.gt_batterybuffer.getMaxBatteryCharge(i)
      end
    end

    if max == 0 then
      log:warn("Battery buffer detected but it's empty!")
      return nil
    end

    battery = {
      current = function()
        local current = 0
        for i = 1, 16, 1 do
          if comp.gt_batterybuffer.getBatteryCharge(i) ~= nil then
            current = current + comp.gt_batterybuffer.getBatteryCharge(i)
          end
        end

        return current
      end,
      max = max
    }

    log:warn("It seems you are using a battery buffer. They are slow! Consider upgrading to an LSC")
  end

  return battery
end

function controller.new(reactors)
  log:info("Initializing controller")

  return setmetatable({
    reactors = reactors,
    io = comp.redstone,
    threads = {},
    is_swapping = false,
    battery = findBattery()
  }, { __index = methods })
end

function methods:redstonePulse(side, duration)
  duration = duration or 0.1

  self.io.setOutput(side, 15)
  os.sleep(duration)
  self.io.setOutput(side, 0)
end

function methods:swapCells()
  log:info("Swapping all hot coolant cells")
  self:redstonePulse(cfg.REDSTONE_COOLANT_SIDE)
end

function methods:swapRods()
  log:info("Swapping all depleted fuel rods")
  self:redstonePulse(cfg.REDSTONE_FUEL_SIDE)
end

function methods:startAll()
  log:info("Starting all reactors")
  self.io.setOutput(cfg.REDSTONE_COOLANT_SIDE, 0)
  self.io.setOutput(cfg.REDSTONE_FUEL_SIDE, 0)

  for _, r in ipairs(self.reactors) do
    local t = thread.create(function(target, ctrl)
      local ok, reason = target:isOk(ctrl)
      if ok then
        target:run(ctrl)
      else
        log:warn("Skipped [" .. target.name .. "] during startup: " .. reason)
        self:redstonePulse(cfg.REDSTONE_ALARM_SIDE, 1.5)
      end
    end, r, self)
    table.insert(self.threads, t)
  end
end

function methods:stopAll()
  log:info("Stopping all reactors")
  self.io.setOutput(cfg.REDSTONE_COOLANT_SIDE, 0)
  self.io.setOutput(cfg.REDSTONE_FUEL_SIDE, 0)

  for _, t in ipairs(self.threads) do
    if t:status() ~= "dead" then t:kill() end
  end
  self.threads = {}
  for _, r in ipairs(self.reactors) do
    r:enable(false)
  end
end

function methods:emergency()
  self.io.setOutput(cfg.REDSTONE_ALARM_SIDE, 15)
  self:stopAll()
  while true do
    os.sleep(1000) -- keep alive
  end
end

function methods:shutdown()
  log:info("Shutdown initiated")

  self:stopAll()
  self.io.setOutput({ 0, 0, 0, 0, 0, 0 })

  log:info("Shutdown complete")
end

function methods:fix(reactor, reason)
  while self.is_fixing do
    os.sleep(0.05)
  end

  self.is_fixing = true
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

  self.is_fixing = false
end

function methods:manage()
  log:info("Starting reactor management")
  if cfg.MOX_MODE then
    log:warn("Running in MOX mode")
  end

  if not self.battery then
    log:warn("No valid battery detected. Running reactors indefinitely")
    self:startAll()
    while true do
      os.sleep(1000)
    end
  end

  log:info("Valid battery detected. Monitoring energy levels...")
  local running = false

  while true do
    local stored = self.battery.current() / self.battery.max
    local stored_eu_pct = math.floor(stored * 100)

    if not running and stored <= cfg.MIN_BATTERY_EU_PCT then
      log:warn("Battery low (" .. stored_eu_pct .. "%)")
      self:startAll()
      running = true
    elseif running and stored >= cfg.MAX_BATTERY_EU_PCT then
      log:info("Battery charged (" .. stored_eu_pct .. "%)")
      self:stopAll()
      running = false
    end

    os.sleep(cfg.BATTERY_CHECK_FREQUENCY_SEC)
  end
end

return controller
