local core     = require('openmw.core')
local camera   = require('openmw.camera')
local input    = require('openmw.input')
local self     = require('openmw.self')
local util     = require('openmw.util')
local async    = require('openmw.async')
local I        = require('openmw.interfaces')
local storage  = require('openmw.storage')

local MODE     = camera.MODE

local settings = storage.playerSection('SettingsOMWCameraCurve')

local M        = {
    enabled       = true,
    innerDeadzone = 0.05,
    cubicWeight   = 0.9,
    sensitivity   = 1.4,
}

local function updateSettings()
    M.enabled       = settings:get('enabled')
    M.innerDeadzone = util.clamp(settings:get('innerDeadzone'), 0, 1)
    M.cubicWeight   = util.clamp(settings:get('cubicWeight'), 0, 1)
    M.sensitivity   = util.clamp(settings:get('sensitivity'), 0, 5)
end

updateSettings()
settings:subscribe(async:callback(updateSettings))

function M.onFrame(dt)
    if (not M.enabled) or core.isWorldPaused() then return end
    if camera.getMode() == MODE.Static then return end

    local yawInput = util.clamp(input.getAxisValue(input.CONTROLLER_AXIS.LookLeftRight), -1, 1)
    local pitchInput = util.clamp(input.getAxisValue(input.CONTROLLER_AXIS.LookUpDown), -1, 1)

    local actualControlsDistanceFromOrigin = math.sqrt(self.controls.yawChange * self.controls.yawChange +
        self.controls.pitchChange * self.controls.pitchChange)
    local normalizedDistanceFromOrigin = math.sqrt(yawInput * yawInput + pitchInput * pitchInput)

    if actualControlsDistanceFromOrigin > normalizedDistanceFromOrigin then
        -- Player is using the mouse to move the camera.
        return
    end

    if normalizedDistanceFromOrigin < M.innerDeadzone then
        self.controls.yawChange = 0
        self.controls.pitchChange = 0
        return
    end

    local remappedDistance = util.remap(normalizedDistanceFromOrigin, M.innerDeadzone, 1, 0, 1)

    local newInputLength = M.sensitivity * (
        (remappedDistance * remappedDistance * remappedDistance) * M.cubicWeight +
        remappedDistance * (1 - M.cubicWeight)
    )

    -- normalize each input, then scale by new length
    self.controls.yawChange = (self.controls.yawChange / normalizedDistanceFromOrigin) * newInputLength
    self.controls.pitchChange = (self.controls.pitchChange / normalizedDistanceFromOrigin) * newInputLength
end

return M
