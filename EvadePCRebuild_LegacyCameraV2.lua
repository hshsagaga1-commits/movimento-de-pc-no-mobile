-- Evade PC Rebuild - Legacy Camera V2
-- Native Legacy mouse-lock state owner.
-- Owns only lock/offset/CameraRelative state. Body/framing is a separate layer.
-- Does not write Camera.CFrame, Focus, FOV, zoom, or character pose.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local VERSION = "EvadePCRebuild-LegacyCamera-V2.1-native-pc-camera-emote-center"
local LEGACY_PLACE_ID = 96537472072550
local BIND_NAME = "__EvadePCRebuildLegacyCameraV2"
local SHOULDER_OFFSET = Vector3.new(1.75, 0, 0)\nlocal EMOTE_OFFSET = Vector3.zero

local previousCleanup = ENV.__EvadePCRebuildLegacyCameraV2Cleanup
if type(previousCleanup) == "function" then
    pcall(previousCleanup)
end
local previousV1Cleanup = ENV.__EvadePCRebuildLegacyCameraV1Cleanup
if type(previousV1Cleanup) == "function" then
    pcall(previousV1Cleanup)
end
pcall(function()
    RunService:UnbindFromRenderStep(BIND_NAME)
end)

-- Retire the older BURACO/R2 camera owner if it is still alive in this session.
local oldBuraco = ENV.EvadeLegacyPCBuraco
if type(oldBuraco) == "table" and type(oldBuraco.Cleanup) == "function" then
    pcall(function()
        oldBuraco.Cleanup(false)
    end)
end

if game.PlaceId ~= LEGACY_PLACE_ID then
    local api = {
        Version = VERSION,
        Installed = false,
        Reason = "wrong-place",
        PlaceId = game.PlaceId,
    }
    ENV.EvadePCRebuildLegacyCameraV2 = api
    return api
end

local playerModule = nil
local cameras = nil
local lastController = nil
local controllerSnapshots = setmetatable({}, {__mode = "k"})

local shiftObject = nil
local offsetObject = nil
local shiftOriginal = nil
local offsetOriginal = nil

local userGameSettings = nil
local originalRotationType = nil
local enabled = true
local emoteCentered = false
local effectiveOffset = SHOULDER_OFFSET
local frames = 0
local lockWrites = 0
local offsetWrites = 0
local stateWrites = 0
local behaviorRefreshes = 0
local lastBehaviorRefresh = -math.huge

pcall(function()
    userGameSettings = UserSettings():GetService("UserGameSettings")
    originalRotationType = userGameSettings.RotationType
end)

local function getPlayerModule()
    if type(playerModule) == "table" then
        return playerModule
    end

    local scripts = player:FindFirstChild("PlayerScripts")
    local moduleScript = scripts and scripts:FindFirstChild("PlayerModule")
    if not moduleScript then
        return nil
    end

    pcall(function()
        local value = require(moduleScript)
        if type(value) == "table" then
            playerModule = value
        end
    end)

    return playerModule
end

local function getCameras()
    if type(cameras) == "table" then
        return cameras
    end

    local module = getPlayerModule()
    if type(module) ~= "table" then
        return nil
    end

    pcall(function()
        if type(module.GetCameras) == "function" then
            cameras = module:GetCameras()
        end
    end)

    return type(cameras) == "table" and cameras or nil
end

local function getActiveController()
    local cameraModule = getCameras()
    if type(cameraModule) ~= "table" then
        return nil
    end

    local controller = nil
    pcall(function()
        controller = rawget(cameraModule, "activeCameraController")
    end)

    if type(controller) ~= "table" then
        pcall(function()
            if type(cameraModule.GetActiveCameraController) == "function" then
                controller = cameraModule:GetActiveCameraController()
            end
        end)
    end

    return type(controller) == "table" and controller or nil
end

local function findLegacyStateObjects()
    local scripts = player:FindFirstChild("PlayerScripts")
    if not scripts then
        return
    end

    if not shiftObject or not shiftObject.Parent then
        local found = scripts:FindFirstChild("ShiftLockEnabled", true)
        if found and found:IsA("BoolValue") then
            shiftObject = found
            if shiftOriginal == nil then
                shiftOriginal = found.Value
            end
        end
    end

    if not offsetObject or not offsetObject.Parent then
        local found = scripts:FindFirstChild("MouseLockOffset", true)
        if found and found:IsA("Vector3Value") then
            offsetObject = found
            if offsetOriginal == nil then
                offsetOriginal = found.Value
            end
        end
    end
end

local function snapshotController(controller)
    if type(controller) ~= "table" or controllerSnapshots[controller] then
        return
    end

    local snapshot = {}

    pcall(function()
        if type(controller.GetIsMouseLocked) == "function" then
            snapshot.locked = controller:GetIsMouseLocked()
        else
            snapshot.locked = rawget(controller, "inMouseLockedMode")
        end
    end)

    pcall(function()
        if type(controller.GetMouseLockOffset) == "function" then
            snapshot.offset = controller:GetMouseLockOffset()
        else
            snapshot.offset = rawget(controller, "mouseLockOffset")
        end
    end)

    controllerSnapshots[controller] = snapshot
end

local function setControllerState(controller)
    if type(controller) ~= "table" then
        return
    end

    snapshotController(controller)

    local locked = nil
    pcall(function()
        if type(controller.GetIsMouseLocked) == "function" then
            locked = controller:GetIsMouseLocked()
        else
            locked = rawget(controller, "inMouseLockedMode")
        end
    end)

    if locked ~= true then
        local ok = pcall(function()
            if type(controller.SetIsMouseLocked) == "function" then
                controller:SetIsMouseLocked(true)
            else
                rawset(controller, "inMouseLockedMode", true)
            end
        end)
        if ok then
            lockWrites = lockWrites + 1
        end
    end

    local currentOffset = nil
    pcall(function()
        if type(controller.GetMouseLockOffset) == "function" then
            currentOffset = controller:GetMouseLockOffset()
        else
            currentOffset = rawget(controller, "mouseLockOffset")
        end
    end)

    if typeof(currentOffset) ~= "Vector3" or (currentOffset - effectiveOffset).Magnitude > 0.0001 then
        local ok = pcall(function()
            if type(controller.SetMouseLockOffset) == "function" then
                controller:SetMouseLockOffset(effectiveOffset)
            else
                rawset(controller, "mouseLockOffset", effectiveOffset)
            end
        end)
        if ok then
            offsetWrites = offsetWrites + 1
        end
    end

    if os.clock() - lastBehaviorRefresh >= 0.15 then
        local ok = pcall(function()
            if type(controller.UpdateMouseBehavior) == "function" then
                controller:UpdateMouseBehavior()
            end
        end)
        if ok then
            behaviorRefreshes = behaviorRefreshes + 1
            lastBehaviorRefresh = os.clock()
        end
    end
end

local function applyLegacyState()
    effectiveOffset = emoteCentered and EMOTE_OFFSET or SHOULDER_OFFSET
    findLegacyStateObjects()

    if shiftObject and shiftObject.Value ~= true then
        local ok = pcall(function()
            shiftObject.Value = true
        end)
        if ok then
            stateWrites = stateWrites + 1
        end
    end

    if offsetObject and ((offsetObject.Value - effectiveOffset).Magnitude > 0.0001) then
        local ok = pcall(function()
            offsetObject.Value = effectiveOffset
        end)
        if ok then
            stateWrites = stateWrites + 1
        end
    end

    if userGameSettings then
        pcall(function()
            if userGameSettings.RotationType ~= Enum.RotationType.CameraRelative then
                userGameSettings.RotationType = Enum.RotationType.CameraRelative
            end
        end)
    end

    local controller = getActiveController()
    if controller ~= lastController then
        lastController = controller
    end

    setControllerState(controller)
end

local function shouldRun()
    if not enabled then
        return false
    end

    local camera = Workspace.CurrentCamera
    if not camera or camera.CameraType == Enum.CameraType.Scriptable then
        return false
    end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    return true
end

RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value - 1, function()
    frames = frames + 1

    if shouldRun() then
        applyLegacyState()
    end
end)

local function restoreController(controller, snapshot)
    if type(controller) ~= "table" or type(snapshot) ~= "table" then
        return
    end

    pcall(function()
        if typeof(snapshot.offset) == "Vector3" then
            if type(controller.SetMouseLockOffset) == "function" then
                controller:SetMouseLockOffset(snapshot.offset)
            else
                rawset(controller, "mouseLockOffset", snapshot.offset)
            end
        end
    end)

    pcall(function()
        if type(snapshot.locked) == "boolean" then
            if type(controller.SetIsMouseLocked) == "function" then
                controller:SetIsMouseLocked(snapshot.locked)
            else
                rawset(controller, "inMouseLockedMode", snapshot.locked)
            end
        end
    end)

    pcall(function()
        if type(controller.UpdateMouseBehavior) == "function" then
            controller:UpdateMouseBehavior()
        end
    end)
end

local api = {
    Version = VERSION,
    Installed = true,
    SetEnabled = function(value)
        enabled = value ~= false
        if enabled then
            applyLegacyState()
        end
    end,
    SetEmoteCentered = function(value)
        local nextValue = value == true
        if emoteCentered ~= nextValue then
            emoteCentered = nextValue
            applyLegacyState()
        end
    end,
    Resync = function()
        cameras = nil
        playerModule = nil
        shiftObject = nil
        offsetObject = nil
        applyLegacyState()
    end,
    GetState = function()
        return {
            frames = frames,
            lockWrites = lockWrites,
            offsetWrites = offsetWrites,
            stateWrites = stateWrites,
            behaviorRefreshes = behaviorRefreshes,
            emoteCentered = emoteCentered,
            shoulderOffset = SHOULDER_OFFSET,
            emoteOffset = EMOTE_OFFSET,
            effectiveOffset = effectiveOffset,
            ownsCameraCFrame = false,
            ownsCameraFocus = false,
            hasController = type(getActiveController()) == "table",
            hasShiftObject = shiftObject ~= nil,
            hasOffsetObject = offsetObject ~= nil,
            mouseBehavior = tostring(UserInputService.MouseBehavior),
        }
    end,
}

ENV.EvadePCRebuildLegacyCameraV2 = api

ENV.__EvadePCRebuildLegacyCameraV2Cleanup = function()
    enabled = false
    emoteCentered = false
    effectiveOffset = SHOULDER_OFFSET

    pcall(function()
        RunService:UnbindFromRenderStep(BIND_NAME)
    end)

    if shiftObject and shiftOriginal ~= nil then
        pcall(function()
            shiftObject.Value = shiftOriginal
        end)
    end

    if offsetObject and typeof(offsetOriginal) == "Vector3" then
        pcall(function()
            offsetObject.Value = offsetOriginal
        end)
    end

    for controller, snapshot in pairs(controllerSnapshots) do
        restoreController(controller, snapshot)
    end

    if userGameSettings and originalRotationType ~= nil then
        pcall(function()
            userGameSettings.RotationType = originalRotationType
        end)
    end

    ENV.EvadePCRebuildLegacyCameraV2 = nil
    ENV.__EvadePCRebuildLegacyCameraV2Cleanup = nil
end

applyLegacyState()
return api
