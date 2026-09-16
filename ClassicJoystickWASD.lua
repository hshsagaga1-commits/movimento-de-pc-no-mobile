local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Rigid 8-way keyboard-like snapping for the native/classic thumbstick.
-- The Roblox joystick UI stays native; only its movement vector is quantized.
local ENGAGE_MAGNITUDE = 0.22
local RELEASE_MAGNITUDE = 0.14
local DIAGONAL_ENTER_RATIO = 0.68
local DIAGONAL_RELEASE_RATIO = 0.52

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
local enabled = true
local engaged = false
local snapMode = "none"

local function sign(value)
    if value > 0 then
        return 1
    elseif value < 0 then
        return -1
    end
    return 0
end

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

local function resetSnapState()
    engaged = false
    snapMode = "none"
end

local function quantize(rawVector)
    if typeof(rawVector) ~= "Vector3" then
        resetSnapState()
        return rawVector
    end

    local magnitude = rawVector.Magnitude

    if not engaged then
        if magnitude < ENGAGE_MAGNITUDE then
            snapMode = "none"
            return Vector3.zero
        end
        engaged = true
    elseif magnitude < RELEASE_MAGNITUDE then
        resetSnapState()
        return Vector3.zero
    end

    local x = rawVector.X
    local z = rawVector.Z
    local absX = math.abs(x)
    local absZ = math.abs(z)
    local dominant = math.max(absX, absZ)

    if dominant <= 1e-6 then
        resetSnapState()
        return Vector3.zero
    end

    local ratio = math.min(absX, absZ) / dominant
    local diagonalThreshold = snapMode == "diag"
        and DIAGONAL_RELEASE_RATIO
        or DIAGONAL_ENTER_RATIO

    if ratio >= diagonalThreshold then
        snapMode = "diag"
        return Vector3.new(sign(x), 0, sign(z))
    end

    if absX > absZ then
        snapMode = "x"
        return Vector3.new(sign(x), 0, 0)
    end

    snapMode = "z"
    return Vector3.new(0, 0, sign(z))
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
    resetSnapState()
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
            resetSnapState()
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
    Version = "1.1-rigid-8way-native-classic",
    SetEnabled = function(value)
        enabled = value ~= false
        if not enabled then
            resetSnapState()
        end
        return enabled
    end,
    IsEnabled = function()
        return enabled
    end,
    GetTuning = function()
        return {
            engageMagnitude = ENGAGE_MAGNITUDE,
            releaseMagnitude = RELEASE_MAGNITUDE,
            diagonalEnterRatio = DIAGONAL_ENTER_RATIO,
            diagonalReleaseRatio = DIAGONAL_RELEASE_RATIO,
        }
    end,
    GetState = function()
        return {
            engaged = engaged,
            snapMode = snapMode,
        }
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
