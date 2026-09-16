local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Tuned for a fixed/classic thumbstick: small deadzone, then full digital axes.
local PRESS_THRESHOLD = 0.34
local RELEASE_THRESHOLD = 0.22
local STOP_MAGNITUDE = 0.08

if getgenv().__PCClassicWASDCleanup then
    pcall(getgenv().__PCClassicWASDCleanup)
end

local playerModule
local controls
local hookedController
local originalGetMoveVector
local previousOwnGetMoveVector
local hadOwnGetMoveVector = false
local watchConnection
local latchedX, latchedZ = 0, 0
local enabled = true

local function getControls()
    if type(controls) == "table" then
        return controls
    end

    local scripts = player:FindFirstChild("PlayerScripts")
    local moduleScript = scripts and scripts:FindFirstChild("PlayerModule")
    if not moduleScript then
        return nil
    end

    local ok, module = pcall(require, moduleScript)
    if not ok or type(module) ~= "table" then
        return nil
    end

    playerModule = module

    local okControls, value = pcall(function()
        if type(module.GetControls) == "function" then
            return module:GetControls()
        end
        return rawget(module, "controls")
    end)

    if okControls and type(value) == "table" then
        controls = value
        return controls
    end

    return nil
end

local function nextAxis(value, state)
    if state == 0 then
        if value >= PRESS_THRESHOLD then
            return 1
        elseif value <= -PRESS_THRESHOLD then
            return -1
        end
        return 0
    elseif state == 1 then
        if value <= -PRESS_THRESHOLD then
            return -1
        elseif value < RELEASE_THRESHOLD then
            return 0
        end
        return 1
    elseif state == -1 then
        if value >= PRESS_THRESHOLD then
            return 1
        elseif value > -RELEASE_THRESHOLD then
            return 0
        end
        return -1
    end

    return 0
end

local function quantize(rawVector)
    if typeof(rawVector) ~= "Vector3" then
        latchedX, latchedZ = 0, 0
        return rawVector
    end

    if rawVector.Magnitude < STOP_MAGNITUDE then
        latchedX, latchedZ = 0, 0
        return Vector3.zero
    end

    local nextX = nextAxis(rawVector.X, latchedX)
    local nextZ = nextAxis(rawVector.Z, latchedZ)
    latchedX, latchedZ = nextX, nextZ

    return Vector3.new(nextX, 0, nextZ)
end

local function restoreHook()
    if type(hookedController) == "table" then
        pcall(function()
            if hadOwnGetMoveVector then
                rawset(hookedController, "GetMoveVector", previousOwnGetMoveVector)
            else
                rawset(hookedController, "GetMoveVector", nil)
            end
        end)
    end

    hookedController = nil
    originalGetMoveVector = nil
    previousOwnGetMoveVector = nil
    hadOwnGetMoveVector = false
    latchedX, latchedZ = 0, 0
end

local function installHook(controller)
    if controller == hookedController then
        return true
    end

    restoreHook()

    if type(controller) ~= "table" then
        return false
    end

    local resolved
    local okResolved = pcall(function()
        resolved = controller.GetMoveVector
    end)
    if not okResolved or type(resolved) ~= "function" then
        return false
    end

    local own = rawget(controller, "GetMoveVector")
    hadOwnGetMoveVector = own ~= nil
    previousOwnGetMoveVector = own
    originalGetMoveVector = resolved
    hookedController = controller

    rawset(controller, "GetMoveVector", function(self, ...)
        local rawVector = originalGetMoveVector(self, ...)
        if not enabled or not UserInputService.TouchEnabled then
            latchedX, latchedZ = 0, 0
            return rawVector
        end
        return quantize(rawVector)
    end)

    return true
end

local function refreshController()
    local controlModule = getControls()
    if type(controlModule) ~= "table" then
        return
    end

    local activeController = rawget(controlModule, "activeController")
    if type(activeController) ~= "table" then
        activeController = rawget(controlModule, "touchController")
    end

    if type(activeController) == "table" and activeController ~= hookedController then
        installHook(activeController)
    end
end

refreshController()
watchConnection = RunService.RenderStepped:Connect(refreshController)

getgenv().PCClassicWASD = {
    Version = "1.0-classic-native-ui-vector-quantizer",
    SetEnabled = function(value)
        enabled = value ~= false
        if not enabled then
            latchedX, latchedZ = 0, 0
        end
        return enabled
    end,
    IsEnabled = function()
        return enabled
    end,
    GetThresholds = function()
        return PRESS_THRESHOLD, RELEASE_THRESHOLD, STOP_MAGNITUDE
    end,
}

getgenv().__PCClassicWASDCleanup = function()
    if watchConnection then
        pcall(function()
            watchConnection:Disconnect()
        end)
        watchConnection = nil
    end
    restoreHook()
    getgenv().PCClassicWASD = nil
    getgenv().__PCClassicWASDCleanup = nil
end
