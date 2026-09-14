local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local bindName = "__PCMovementLegacyLock"

-- Limpa qualquer versao anterior (inclusive V4/V5 com CameraType Scriptable).
if getgenv().__PCMobileAimCleanup then
    pcall(getgenv().__PCMobileAimCleanup)
end
pcall(function()
    RunService:UnbindFromRenderStep(bindName)
end)

local connections = {}
local character
local humanoid
local animator
local rootPart

local oldPlayerCameraMode
local oldDevTouchCameraMode
local oldStarterTouchMode
local oldUserTouchMode
local oldRotationType
local oldAutoRotate
local oldCameraController
local oldControllerMouseLocked
local oldControllerOffset
local lastLockState

pcall(function()
    oldPlayerCameraMode = player.CameraMode
end)
pcall(function()
    oldDevTouchCameraMode = player.DevTouchCameraMode
end)
pcall(function()
    oldStarterTouchMode = StarterPlayer.DevTouchCameraMovementMode
end)

local userGameSettings
pcall(function()
    userGameSettings = UserSettings():GetService("UserGameSettings")
    oldUserTouchMode = userGameSettings.TouchCameraMovementMode
    oldRotationType = userGameSettings.RotationType
end)

if getgenv().PCMovementEnabled == nil then
    getgenv().PCMovementEnabled = true
end

-- O pontinho representa a direcao da camera/mouse do PC.
local guiParent = CoreGui
pcall(function()
    if gethui then
        guiParent = gethui()
    end
end)

pcall(function()
    local old = guiParent:FindFirstChild("PCMobileAim")
    if old then old:Destroy() end
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PCMobileAim"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 1000000
screenGui.Parent = guiParent

local dot = Instance.new("Frame")
dot.Name = "AimPoint"
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Size = UDim2.fromOffset(2, 2)
dot.BorderSizePixel = 0
dot.BackgroundColor3 = Color3.new(1, 1, 1)
dot.ZIndex = 10
dot.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = dot

local function trySetProperty(object, property, value)
    local worked = false

    if object then
        local ok = pcall(function()
            object[property] = value
        end)
        worked = worked or ok

        if sethiddenproperty then
            local okHidden = pcall(function()
                sethiddenproperty(object, property, value)
            end)
            worked = worked or okHidden
        end

        if setscriptable then
            pcall(function()
                setscriptable(object, property, true)
            end)
            local okScriptable = pcall(function()
                object[property] = value
            end)
            worked = worked or okScriptable
        end
    end

    return worked
end

local cameras
local function getCameras()
    if cameras then
        return cameras
    end

    pcall(function()
        local playerScripts = player:FindFirstChild("PlayerScripts")
        local moduleScript = playerScripts and playerScripts:FindFirstChild("PlayerModule")
        if not moduleScript then return end

        local playerModule = require(moduleScript)
        if type(playerModule) == "table" and type(playerModule.GetCameras) == "function" then
            cameras = playerModule:GetCameras()
        end
    end)

    return cameras
end

local function getActiveCameraController()
    local cameraModule = getCameras()
    if type(cameraModule) ~= "table" then
        return nil
    end

    local controller
    pcall(function()
        if type(cameraModule.GetActiveCameraController) == "function" then
            controller = cameraModule:GetActiveCameraController()
        end
    end)
    return controller
end

local function rememberController(controller)
    if not controller or oldCameraController ~= nil then
        return
    end

    oldCameraController = controller
    pcall(function()
        if type(controller.GetIsMouseLocked) == "function" then
            oldControllerMouseLocked = controller:GetIsMouseLocked()
        end
    end)
    pcall(function()
        if type(controller.GetMouseLockOffset) == "function" then
            oldControllerOffset = controller:GetMouseLockOffset()
        end
    end)
end

local function setRotationType(rotationType)
    if not userGameSettings then return false end
    return trySetProperty(userGameSettings, "RotationType", rotationType)
end

local function setControllerLock(locked)
    local controller = getActiveCameraController()
    if not controller then
        return false
    end

    rememberController(controller)
    local changed = false

    if type(controller.SetIsMouseLocked) == "function" then
        local ok = pcall(function()
            controller:SetIsMouseLocked(locked)
        end)
        changed = changed or ok
    end

    -- ZERO offset: personagem fica no mesmo eixo do pontinho, nao deslocado pro ombro.
    if locked and type(controller.SetMouseLockOffset) == "function" then
        pcall(function()
            controller:SetMouseLockOffset(Vector3.zero)
        end)
    end

    if type(controller.UpdateMouseBehavior) == "function" then
        pcall(function()
            controller:UpdateMouseBehavior()
        end)
    end

    return changed
end

local function forceClassicCamera()
    -- BASE V3: camera normal do Roblox/Evade. Nada de CameraType Scriptable.
    pcall(function()
        player.CameraMode = Enum.CameraMode.Classic
    end)

    trySetProperty(player, "DevTouchCameraMode", Enum.DevTouchCameraMovementMode.Classic)
    trySetProperty(StarterPlayer, "DevTouchCameraMovementMode", Enum.DevTouchCameraMovementMode.Classic)

    if userGameSettings then
        trySetProperty(userGameSettings, "TouchCameraMovementMode", Enum.TouchCameraMovementMode.Classic)
    end

    pcall(function()
        local cameraModule = getCameras()
        if type(cameraModule) ~= "table" then return end

        if type(cameraModule.ActivateCameraController) == "function" then
            cameraModule:ActivateCameraController(Enum.ComputerCameraMovementMode.Classic)
        elseif type(cameraModule.GetActiveCameraController) == "function" then
            local controller = cameraModule:GetActiveCameraController()
            if controller and type(controller.SetCameraMovementMode) == "function" then
                controller:SetCameraMovementMode(Enum.ComputerCameraMovementMode.Classic)
            end
        end
    end)

    local camera = Workspace.CurrentCamera
    if camera and humanoid and camera.CameraType ~= Enum.CameraType.Scriptable then
        pcall(function()
            camera.CameraType = Enum.CameraType.Custom
            camera.CameraSubject = humanoid
        end)
    end
end

local EMOTE_ATTRIBUTE_NAMES = {
    "IsEmoting",
    "Emoting",
    "EmotePlaying",
    "PlayingEmote",
    "DoingEmote",
    "IsDancing",
    "Dancing",
    "IsTaunting",
    "Taunting",
}

local function valueMeansActive(value)
    if value == nil or value == false or value == 0 or value == "" then
        return false
    end
    return true
end

local function hasEmoteAttribute(instance)
    if not instance then return false end

    for _, name in ipairs(EMOTE_ATTRIBUTE_NAMES) do
        local ok, value = pcall(function()
            return instance:GetAttribute(name)
        end)
        if ok and valueMeansActive(value) then
            return true
        end
    end

    return false
end

local function nameLooksLikeEmote(name)
    name = string.lower(tostring(name or ""))
    return string.find(name, "emote", 1, true)
        or string.find(name, "dance", 1, true)
        or string.find(name, "taunt", 1, true)
end

local function trackLooksLikeEmote(track)
    if not track then return false end

    local playing = false
    local weight = 0
    local priorityValue = -1
    local looped = false
    local length = 0
    local trackName = ""
    local animationName = ""

    pcall(function() playing = track.IsPlaying end)
    if not playing then return false end

    pcall(function() weight = track.WeightCurrent end)
    if weight <= 0.01 then return false end

    pcall(function() priorityValue = track.Priority.Value end)
    if priorityValue < Enum.AnimationPriority.Action.Value then
        return false
    end

    pcall(function() looped = track.Looped end)
    pcall(function() length = track.Length end)
    pcall(function() trackName = track.Name end)
    pcall(function()
        if track.Animation then
            animationName = track.Animation.Name
        end
    end)

    -- Primeiro tenta nome explicito. Depois usa perfil tipico de emote:
    -- Action + loop longo, ou Action bem comprida mesmo sem loop.
    if nameLooksLikeEmote(trackName) or nameLooksLikeEmote(animationName) then
        return true
    end

    if looped and length >= 0.8 then
        return true
    end

    if length >= 2.5 then
        return true
    end

    return false
end

local function isEmoting()
    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    if hasEmoteAttribute(player) or hasEmoteAttribute(character) or hasEmoteAttribute(humanoid) then
        return true
    end

    if animator then
        local tracks
        pcall(function()
            tracks = animator:GetPlayingAnimationTracks()
        end)

        if type(tracks) == "table" then
            for _, track in ipairs(tracks) do
                if trackLooksLikeEmote(track) then
                    return true
                end
            end
        end
    end

    return false
end

local function applyLegacyLock(locked, force)
    if not force and lastLockState == locked then
        return
    end
    lastLockState = locked

    -- PC legacy normal: shift-lock/camera-relative.
    -- Emote: destrava a orientacao, mas a camera continua seguindo o Humanoid pela V3.
    setControllerLock(locked)

    if locked then
        setRotationType(Enum.RotationType.CameraRelative)
    else
        setRotationType(Enum.RotationType.MovementRelative)
    end
end

local function attachCharacter(newCharacter)
    character = newCharacter
    humanoid = newCharacter:WaitForChild("Humanoid", 10)
    rootPart = newCharacter:WaitForChild("HumanoidRootPart", 10)
    animator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)) or nil

    if humanoid and oldAutoRotate == nil then
        pcall(function()
            oldAutoRotate = humanoid.AutoRotate
        end)
    end

    task.wait()
    forceClassicCamera()
    lastLockState = nil
    applyLegacyLock(not isEmoting(), true)

    local camera = Workspace.CurrentCamera
    if camera and humanoid and camera.CameraType ~= Enum.CameraType.Scriptable then
        pcall(function()
            camera.CameraSubject = humanoid
        end)
    end
end

if player.Character then
    task.spawn(attachCharacter, player.Character)
end

table.insert(connections, player.CharacterAdded:Connect(function(newCharacter)
    task.spawn(attachCharacter, newCharacter)
end))

pcall(function()
    table.insert(connections, player:GetPropertyChangedSignal("DevTouchCameraMode"):Connect(function()
        if getgenv().PCMovementEnabled ~= false then
            task.defer(function()
                forceClassicCamera()
                applyLegacyLock(not isEmoting(), true)
            end)
        end
    end))
end)

-- Nao escreve CFrame da camera nem do HumanoidRootPart.
-- So alterna o MESMO estado de orientacao que o shift-lock usa.
RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 2, function()
    local enabled = getgenv().PCMovementEnabled ~= false
    screenGui.Enabled = enabled

    if not enabled or not humanoid or humanoid.Health <= 0 then
        if lastLockState ~= false then
            applyLegacyLock(false, true)
        end
        return
    end

    local emoting = isEmoting()
    applyLegacyLock(not emoting, false)

    -- Se o jogo trocou o controlador de camera, reaplica o estado uma vez nele.
    local controller = getActiveCameraController()
    if controller and controller ~= oldCameraController then
        applyLegacyLock(not emoting, true)
    end
end)

getgenv().__PCMobileAimCleanup = function()
    pcall(function()
        RunService:UnbindFromRenderStep(bindName)
    end)

    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(connections)

    pcall(function()
        screenGui:Destroy()
    end)

    local controller = getActiveCameraController()
    if controller then
        if oldControllerMouseLocked ~= nil and type(controller.SetIsMouseLocked) == "function" then
            pcall(function()
                controller:SetIsMouseLocked(oldControllerMouseLocked)
            end)
        else
            pcall(function()
                if type(controller.SetIsMouseLocked) == "function" then
                    controller:SetIsMouseLocked(false)
                end
            end)
        end

        if oldControllerOffset ~= nil and type(controller.SetMouseLockOffset) == "function" then
            pcall(function()
                controller:SetMouseLockOffset(oldControllerOffset)
            end)
        end

        if type(controller.UpdateMouseBehavior) == "function" then
            pcall(function()
                controller:UpdateMouseBehavior()
            end)
        end
    end

    if oldRotationType ~= nil then
        setRotationType(oldRotationType)
    end

    if humanoid and oldAutoRotate ~= nil then
        pcall(function()
            humanoid.AutoRotate = oldAutoRotate
        end)
    end

    if oldPlayerCameraMode ~= nil then
        pcall(function()
            player.CameraMode = oldPlayerCameraMode
        end)
    end

    if oldDevTouchCameraMode ~= nil then
        trySetProperty(player, "DevTouchCameraMode", oldDevTouchCameraMode)
    end

    if oldStarterTouchMode ~= nil then
        trySetProperty(StarterPlayer, "DevTouchCameraMovementMode", oldStarterTouchMode)
    end

    if userGameSettings and oldUserTouchMode ~= nil then
        trySetProperty(userGameSettings, "TouchCameraMovementMode", oldUserTouchMode)
    end

    getgenv().__PCMobileAimCleanup = nil
end
