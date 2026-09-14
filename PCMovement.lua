local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local cameraBindName = "__PCMovementPersistentLock"
local movementBindName = "__PCMovementDigitalWASD"

-- V9: offset observado no Legacy PC.
-- Normal: camera deslocada para a direita/cima -> personagem aparece a esquerda/baixo do pontinho.
-- Emote: offset zera -> personagem volta para perto do centro/pontinho.
local NORMAL_MOUSE_LOCK_OFFSET = Vector3.new(2, 0.5, 0)
local EMOTE_MOUSE_LOCK_OFFSET = Vector3.zero

-- Limpa qualquer versao anterior antes de aplicar esta.
if getgenv().__PCMobileAimCleanup then
    pcall(getgenv().__PCMobileAimCleanup)
end
pcall(function()
    RunService:UnbindFromRenderStep(cameraBindName)
    RunService:UnbindFromRenderStep(movementBindName)
end)

if getgenv().PCMovementEnabled == nil then
    getgenv().PCMovementEnabled = true
end
if getgenv().PCMovementDigitalInput == nil then
    getgenv().PCMovementDigitalInput = true
end

local connections = {}
local character
local humanoid

local oldPlayerCameraMode
local oldDevTouchCameraMode
local oldStarterTouchMode
local oldUserTouchMode
local oldRotationType
local savedControllerState = {}

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

-- Pontinho = eixo central da camera/mouse do PC.
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
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = guiParent

local dot = Instance.new("Frame")
dot.Name = "AimPoint"
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Size = UDim2.fromOffset(2, 2)
dot.BorderSizePixel = 0
dot.BackgroundColor3 = Color3.new(1, 1, 1)
dot.ZIndex = 1000000
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

local playerModule
local cameras
local controls

local function getPlayerModule()
    if playerModule then
        return playerModule
    end

    pcall(function()
        local playerScripts = player:FindFirstChild("PlayerScripts")
        local moduleScript = playerScripts and playerScripts:FindFirstChild("PlayerModule")
        if moduleScript then
            local required = require(moduleScript)
            if type(required) == "table" then
                playerModule = required
            end
        end
    end)

    return playerModule
end

local function getCameras()
    if cameras then
        return cameras
    end

    local module = getPlayerModule()
    pcall(function()
        if module and type(module.GetCameras) == "function" then
            cameras = module:GetCameras()
        end
    end)

    return cameras
end

local function getControls()
    if controls then
        return controls
    end

    local module = getPlayerModule()
    pcall(function()
        if module and type(module.GetControls) == "function" then
            controls = module:GetControls()
        end
    end)

    return controls
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
    if not controller or savedControllerState[controller] then
        return
    end

    local state = {}
    pcall(function()
        if type(controller.GetIsMouseLocked) == "function" then
            state.mouseLocked = controller:GetIsMouseLocked()
        end
    end)
    pcall(function()
        if type(controller.GetMouseLockOffset) == "function" then
            state.offset = controller:GetMouseLockOffset()
        end
    end)
    savedControllerState[controller] = state
end

local function setControllerLock(locked, offset)
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

    if locked and type(controller.SetMouseLockOffset) == "function" then
        pcall(function()
            controller:SetMouseLockOffset(offset or NORMAL_MOUSE_LOCK_OFFSET)
        end)
    end

    if type(controller.UpdateMouseBehavior) == "function" then
        pcall(function()
            controller:UpdateMouseBehavior()
        end)
    end

    return changed
end

local function setRotationType(value)
    if not userGameSettings then return end
    trySetProperty(userGameSettings, "RotationType", value)
end

local function forcePCBaseCamera()
    -- Mantem a camera REAL do Roblox/Evade. Nada de Scriptable e nada de escrever CFrame.
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
    if camera and humanoid then
        pcall(function()
            if camera.CameraType ~= Enum.CameraType.Custom then
                camera.CameraType = Enum.CameraType.Custom
            end
            camera.CameraSubject = humanoid
        end)
    end
end

local function shouldReleaseLock()
    if not humanoid or humanoid.Health <= 0 then
        return true
    end

    local platformStand = false
    pcall(function()
        platformStand = humanoid.PlatformStand
    end)
    if platformStand then
        return true
    end

    local state
    pcall(function()
        state = humanoid:GetState()
    end)

    if state == Enum.HumanoidStateType.Dead
        or state == Enum.HumanoidStateType.Physics
        or state == Enum.HumanoidStateType.Ragdoll
        or state == Enum.HumanoidStateType.FallingDown then
        return true
    end

    return false
end

local emoteAttributes = {
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

local function hasTruthyAttribute(instance)
    if not instance then return false end

    for _, attributeName in ipairs(emoteAttributes) do
        local ok, value = pcall(function()
            return instance:GetAttribute(attributeName)
        end)
        if ok and (value == true or value == 1) then
            return true
        end
    end

    return false
end

local function trackLooksLikeEmote(track)
    if not track then return false end

    local isPlaying = false
    local weight = 0
    local priority
    local looped = false
    local length = 0
    local trackName = ""
    local animationName = ""

    pcall(function() isPlaying = track.IsPlaying end)
    pcall(function() weight = track.WeightCurrent end)
    pcall(function() priority = track.Priority end)
    pcall(function() looped = track.Looped end)
    pcall(function() length = track.Length end)
    pcall(function() trackName = track.Name or "" end)
    pcall(function()
        local animation = track.Animation
        if animation then
            animationName = animation.Name or ""
        end
    end)

    if not isPlaying or weight <= 0.01 then
        return false
    end

    local name = string.lower(trackName .. " " .. animationName)
    local explicit = string.find(name, "emote", 1, true)
        or string.find(name, "dance", 1, true)
        or string.find(name, "taunt", 1, true)
        or string.find(name, "march", 1, true)
        or string.find(name, "broom", 1, true)
        or string.find(name, "tank", 1, true)

    if explicit then
        return true
    end

    local actionPriority = false
    if priority then
        pcall(function()
            actionPriority = priority.Value >= Enum.AnimationPriority.Action.Value
        end)
    end

    -- Fallback para emotes do Evade com nomes ofuscados/genericos.
    if actionPriority and ((looped and length >= 0.8) or length >= 2.5) then
        return true
    end

    return false
end

local function isEmoting()
    if hasTruthyAttribute(character) or hasTruthyAttribute(humanoid) then
        return true
    end

    if not humanoid then
        return false
    end

    local tracks
    pcall(function()
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if animator then
            tracks = animator:GetPlayingAnimationTracks()
        else
            tracks = humanoid:GetPlayingAnimationTracks()
        end
    end)

    if type(tracks) ~= "table" then
        return false
    end

    for _, track in ipairs(tracks) do
        if trackLooksLikeEmote(track) then
            return true
        end
    end

    return false
end

local lastLocked
local lastOffset
local function applyPCLock(locked, offset, force)
    offset = offset or NORMAL_MOUSE_LOCK_OFFSET

    if not force and lastLocked == locked and lastOffset == offset then
        return
    end

    lastLocked = locked
    lastOffset = offset

    setControllerLock(locked, offset)

    if locked then
        setRotationType(Enum.RotationType.CameraRelative)
    else
        setRotationType(Enum.RotationType.MovementRelative)
    end
end

-- Converte o thumbstick analogico em exatamente as 8 combinacoes que um teclado pode gerar:
-- W, WA, A, AS, S, SD, D, DW. NAO toca em WalkSpeed nem em velocidade fisica.
local function quantizeToWASD(moveVector)
    local x = moveVector.X
    local z = moveVector.Z
    local magnitude = math.sqrt(x * x + z * z)

    if magnitude < 0.18 then
        return Vector3.zero
    end

    local angle = math.atan2(x, -z)
    local step = math.pi / 4
    local snapped = math.floor((angle / step) + 0.5) * step

    return Vector3.new(
        math.sin(snapped),
        0,
        -math.cos(snapped)
    )
end

local function currentDesiredOffset()
    if isEmoting() then
        return EMOTE_MOUSE_LOCK_OFFSET
    end
    return NORMAL_MOUSE_LOCK_OFFSET
end

local function attachCharacter(newCharacter)
    character = newCharacter
    humanoid = newCharacter:WaitForChild("Humanoid", 10)

    task.wait()
    forcePCBaseCamera()
    lastLocked = nil
    lastOffset = nil
    applyPCLock(not shouldReleaseLock(), currentDesiredOffset(), true)

    local camera = Workspace.CurrentCamera
    if camera and humanoid then
        pcall(function()
            camera.CameraType = Enum.CameraType.Custom
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
                forcePCBaseCamera()
                applyPCLock(not shouldReleaseLock(), currentDesiredOffset(), true)
            end)
        end
    end))
end)

-- V8 permanece: joystick analogico -> 8 direcoes digitais de teclado.
RunService:BindToRenderStep(movementBindName, Enum.RenderPriority.Input.Value + 2, function()
    if getgenv().PCMovementEnabled == false
        or getgenv().PCMovementDigitalInput == false
        or not UserInputService.TouchEnabled
        or not humanoid
        or shouldReleaseLock() then
        return
    end

    local controlModule = getControls()
    if not controlModule or type(controlModule.GetMoveVector) ~= "function" then
        return
    end

    local rawMove
    local ok = pcall(function()
        rawMove = controlModule:GetMoveVector()
    end)
    if not ok or typeof(rawMove) ~= "Vector3" then
        return
    end

    local digitalMove = quantizeToWASD(rawMove)
    pcall(function()
        player:Move(digitalMove, true)
    end)
end)

-- V9: o LOCK continua igual a V8. A unica mudanca visual e o offset:
-- normal = (2, 0.5, 0), emote = (0, 0, 0).
RunService:BindToRenderStep(cameraBindName, Enum.RenderPriority.Camera.Value + 2, function()
    local enabled = getgenv().PCMovementEnabled ~= false
    screenGui.Enabled = enabled

    if not enabled then
        applyPCLock(false, EMOTE_MOUSE_LOCK_OFFSET, false)
        return
    end

    if not humanoid then
        return
    end

    local release = shouldReleaseLock()
    local desiredOffset = currentDesiredOffset()
    applyPCLock(not release, desiredOffset, false)

    if not release then
        local controller = getActiveCameraController()
        if controller then
            rememberController(controller)

            if type(controller.SetIsMouseLocked) == "function" then
                pcall(function()
                    controller:SetIsMouseLocked(true)
                end)
            end

            if type(controller.SetMouseLockOffset) == "function" then
                pcall(function()
                    controller:SetMouseLockOffset(desiredOffset)
                end)
            end
        end

        pcall(function()
            if userGameSettings and userGameSettings.RotationType ~= Enum.RotationType.CameraRelative then
                setRotationType(Enum.RotationType.CameraRelative)
            end
        end)
    end
end)

getgenv().__PCMobileAimCleanup = function()
    pcall(function()
        RunService:UnbindFromRenderStep(cameraBindName)
        RunService:UnbindFromRenderStep(movementBindName)
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

    for controller, state in pairs(savedControllerState) do
        pcall(function()
            if state.mouseLocked ~= nil and type(controller.SetIsMouseLocked) == "function" then
                controller:SetIsMouseLocked(state.mouseLocked)
            elseif type(controller.SetIsMouseLocked) == "function" then
                controller:SetIsMouseLocked(false)
            end

            if state.offset ~= nil and type(controller.SetMouseLockOffset) == "function" then
                controller:SetMouseLockOffset(state.offset)
            end

            if type(controller.UpdateMouseBehavior) == "function" then
                controller:UpdateMouseBehavior()
            end
        end)
    end

    if oldRotationType ~= nil then
        setRotationType(oldRotationType)
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
