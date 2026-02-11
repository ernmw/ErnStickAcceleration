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
    yawSensitivity   = 0.2,
    pitchSensitivity = 0.1,
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

    local yawInput = input.getAxisValue(input.CONTROLLER_AXIS.LookLeftRight)
    local absYaw = math.abs(yawInput)
    local normalizedYaw = util.clamp(absYaw, 0, 1)
    local yawAccelFactor = normalizedYaw * normalizedYaw
    yawBuffer:push(yawInput)
    local currentYawVelocity = yawBuffer:getVelocity()
    -- retain yaw longer the closer we are to the edge of input
    retainedYawVelocity = retainedYawVelocity * normalizedYaw + currentYawVelocity * (1 - normalizedYaw)
    self.controls.yawChange = self.controls.yawChange +
        yawAccelFactor * retainedYawVelocity * M.yawSensitivity * dt

    local pitchInput = input.getAxisValue(input.CONTROLLER_AXIS.LookUpDown)
    local absPitch = math.abs(pitchInput)
    local normalizedPitch = util.clamp(absPitch, 0, 1)
    local pitchAccelFactor = normalizedPitch * normalizedPitch
    pitchBuffer:push(pitchInput)
    local currentPitchVelocity = pitchBuffer:getVelocity()
    -- retain pitch longer the closer we are to the edge of input
    retainedPitchVelocity = retainedPitchVelocity * normalizedPitch + currentPitchVelocity * (1 - normalizedPitch)
    self.controls.pitchChange = self.controls.pitchChange +
        pitchAccelFactor * retainedPitchVelocity * M.pitchSensitivity * dt
end

return M
