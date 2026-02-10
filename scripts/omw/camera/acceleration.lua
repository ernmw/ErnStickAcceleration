local core           = require('openmw.core')
local camera         = require('openmw.camera')
local input          = require('openmw.input')
local self           = require('openmw.self')
local util           = require('openmw.util')
local I              = require('openmw.interfaces')

local MODE           = camera.MODE

local M              = {
    enabled        = true,
    yawTurnSpeed   = 0.5,
    pitchTurnSpeed = 0.3,
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

    local trend = (newest - oldest) / self.size

    return (avg + trend * accelerationFactor) / (1 + accelerationFactor)
end

local yawBuffer   = IntentBuffer.new(4)
local pitchBuffer = IntentBuffer.new(4)

---Enable or disable acceleration.
---@param enabled boolean
function M.setEnabled(enabled)
    print("changing enable")
    if M.enabled ~= enabled then
        if enabled then
            yawBuffer:reset()
            pitchBuffer:reset()
        end
    end
    M.enabled = enabled
end

function M.onFrame(dt)
    if (not M.enabled) or core.isWorldPaused() then return end
    if camera.getMode() == MODE.Static then return end
    -- Once for yaw
    yawBuffer:push(self.controls.yawChange)
    self.controls.yawChange = yawBuffer:getPredicted(M.yawTurnSpeed)

    -- Again for pitch
    pitchBuffer:push(self.controls.pitchChange)
    self.controls.pitchChange = pitchBuffer:getPredicted(M.pitchTurnSpeed)
end

return M
