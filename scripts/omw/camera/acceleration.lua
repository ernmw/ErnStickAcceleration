local core           = require('openmw.core')
local camera         = require('openmw.camera')
local input          = require('openmw.input')
local self           = require('openmw.self')
local util           = require('openmw.util')
local async          = require('openmw.async')
local I              = require('openmw.interfaces')
local storage        = require('openmw.storage')

local MODE           = camera.MODE

local settings       = storage.playerSection('SettingsOMWCameraAcceleration')

local M              = {
    enabled          = true,
    yawSensitivity   = 12,
    pitchSensitivity = 6,
}

local IntentBuffer   = {}
IntentBuffer.__index = IntentBuffer

local function emptyBuffer(size)
    local values = {}
    for _ = 1, size do
        table.insert(values, 0)
    end
    return values
end

function IntentBuffer.new(size)
    return setmetatable({
        size   = size or 4,
        values = emptyBuffer(size or 4),
        index  = 1,
    }, IntentBuffer)
end

function IntentBuffer:reset()
    self.index = 1
    self.values = emptyBuffer(self.size)
end

function IntentBuffer:push(v)
    self.values[self.index] = v
    self.index = self.index % self.size + 1
end

function IntentBuffer:getPredicted(accelerationFactor)
    local sum = 0
    for i = 1, self.size do
        sum = sum + self.values[i]
    end
    local avg = sum / self.size

    local newest = self.values[(self.index - 2) % self.size + 1]
    local oldest = self.values[self.index]

    if math.abs(newest) < math.abs(oldest) then
        return avg
    end

    local delta = newest - oldest
    return avg + delta * accelerationFactor
end

function IntentBuffer:getVelocity()
    local newest = self.values[(self.index - 2) % self.size + 1]
    local oldest = self.values[self.index]
    if math.abs(newest) < math.abs(oldest) then
        return 0
    end
    return newest - oldest
end

local yawBuffer   = IntentBuffer.new(4)
local pitchBuffer = IntentBuffer.new(4)

---@param enabled boolean
local function setEnabled(enabled)
    if M.enabled ~= enabled then
        if enabled then
            print("enabled!")
            yawBuffer:reset()
            pitchBuffer:reset()
        end
    end
    M.enabled = enabled
end

local function updateSettings()
    setEnabled(settings:get('enabled'))
    M.yawSensitivity = settings:get('yawSensitivity')
    M.pitchSensitivity = settings:get('pitchSensitivity')
end

updateSettings()
settings:subscribe(async:callback(updateSettings))

local retainedYawVelocity = 0
local retainedPitchVelocity = 0
function M.onFrame(dt)
    if (not M.enabled) or core.isWorldPaused() then return end
    if camera.getMode() == MODE.Static then return end

    local yawInput = util.clamp(input.getAxisValue(input.CONTROLLER_AXIS.LookLeftRight), -1, 1)
    local pitchInput = util.clamp(input.getAxisValue(input.CONTROLLER_AXIS.LookUpDown), -1, 1)

    local normalizedDistanceFromOrigin = math.sqrt(yawInput * yawInput + pitchInput * pitchInput)
    local accelFactor = normalizedDistanceFromOrigin * normalizedDistanceFromOrigin

    yawBuffer:push(yawInput)
    local currentYawVelocity = yawBuffer:getVelocity()
    -- retain yaw longer the closer we are to the edge of input
    retainedYawVelocity = retainedYawVelocity * math.abs(yawInput) +
        currentYawVelocity * (1 - math.abs(yawInput))
    self.controls.yawChange = self.controls.yawChange +
        accelFactor * retainedYawVelocity * M.yawSensitivity * dt

    pitchBuffer:push(pitchInput)
    local currentPitchVelocity = pitchBuffer:getVelocity()
    -- retain pitch longer the closer we are to the edge of input
    retainedPitchVelocity = retainedPitchVelocity * math.abs(pitchInput) +
        currentPitchVelocity * (1 - math.abs(pitchInput))
    self.controls.pitchChange = self.controls.pitchChange +
        accelFactor * retainedPitchVelocity * M.pitchSensitivity * dt
end

return M
