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
    enabled           = true,
    sensitivity       = 4,
    edgeBonusSpeed    = 2,
    edgeBonusDeadzone = 0.7,
    lag               = 6,
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

function IntentBuffer.new()
    return setmetatable({
        size   = M.lag,
        values = emptyBuffer(M.lag),
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

function IntentBuffer:getVelocity()
    local newest = self.values[(self.index - 2) % self.size + 1]
    local oldest = self.values[self.index]
    return newest - oldest
end

local yawBuffer   = IntentBuffer.new()
local pitchBuffer = IntentBuffer.new()

local function updateSettings()
    M.enabled        = settings:get('enabled')
    M.lag            = settings:get('memory')
    M.sensitivity    = settings:get('sensitivity')
    M.edgeBonusSpeed = settings:get('edgeBonusSpeed')

    yawBuffer        = IntentBuffer.new()
    pitchBuffer      = IntentBuffer.new()
end

updateSettings()
settings:subscribe(async:callback(updateSettings))

local function bonusSpeed(inputValue)
    if inputValue > M.edgeBonusDeadzone then
        return M.edgeBonusSpeed
    elseif inputValue < -1 * M.edgeBonusDeadzone then
        return -1 * M.edgeBonusSpeed
    else
        return 0
    end
end

function M.onFrame(dt)
    if (not M.enabled) or core.isWorldPaused() then return end
    if camera.getMode() == MODE.Static then return end

    local yawInput = util.clamp(input.getAxisValue(input.CONTROLLER_AXIS.LookLeftRight), -1, 1)
    local pitchInput = util.clamp(input.getAxisValue(input.CONTROLLER_AXIS.LookUpDown), -1, 1)

    local normalizedDistanceFromOrigin = math.sqrt(yawInput * yawInput + pitchInput * pitchInput)
    local accelFactor = normalizedDistanceFromOrigin * normalizedDistanceFromOrigin
    local edgeBonusFactor = util.remap(accelFactor, 0, 1, M.edgeBonusDeadzone, 1)

    yawBuffer:push(yawInput)
    local currentYawVelocity = yawBuffer:getVelocity()
    self.controls.yawChange = self.controls.yawChange +
        accelFactor * currentYawVelocity * M.sensitivity * dt +
        edgeBonusFactor * bonusSpeed(yawInput) * dt

    pitchBuffer:push(pitchInput)
    local currentPitchVelocity = pitchBuffer:getVelocity()
    self.controls.pitchChange = self.controls.pitchChange +
        accelFactor * currentPitchVelocity * M.sensitivity * dt +
        edgeBonusFactor * bonusSpeed(pitchInput) * dt
end

return M
