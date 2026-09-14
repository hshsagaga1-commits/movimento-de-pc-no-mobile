local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local bindName = "__PCMovementPCBehaviorV12"
local V9_URL = "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovement.lua"

-- V12 = V9 intacta + comportamento de camera observado no PC.
-- 1) Mantem o enquadramento refinado da V11.
-- 2) Evita a camera descer junto quando crouch/slide reduz a altura fisica do personagem.
-- 3) Remove a reducao vertical exclusiva do TOUCH em angulos altos, deixando as viradas mais parecidas com mouse.
-- 4) Mantem CameraModule nativo: nada de CameraType Scriptable e nada de escrever Camera.CFrame.
local DEFAULT_DISTANCE_SCALE = 1.30

-- A V9 continua sendo o checkpoint real do movimento/shift-lock.
local source = game:HttpGet(
    V9_URL .. "?_cb=" .. HttpService:GenerateGUID(false),
    true
)
local chunk, err = loadstring(source)
if not chunk then
    error(err)
end
chunk()

pcall(function()
    RunService:UnbindFromRenderStep(bindName)
end)

if getgenv().PCCameraDistanceScale == nil then
    getgenv().PCCameraDistanceScale = DEFAULT_DISTANCE_SCALE
else
    local existing = tonumber(getgenv().PCCameraDistanceScale)
    if existing and math.abs(existing - 1.15) < 0.001 then
        getgenv().PCCameraDistanceScale = DEFAULT_DISTANCE_SCALE
    end
end
if getgenv().PCCrouchCameraAnchor == nil then
    getgenv().PCCrouchCameraAnchor = true
end
if getgenv().PCMousePitchResponse == nil then
    getgenv().PCMousePitchResponse = true
end

local v9Cleanup = getgenv().__PCMobileAimCleanup

local oldMaxZoom
pcall(function()
    oldMaxZoom = player.CameraMaxZoomDistance
end)

local oldFovMode
pcall(function()
    local camera = Workspace.CurrentCamera
    if camera then
        oldFovMode = camera.FieldOfViewMode
    end
end)

local playerModule
local cameras
local cameraInput
local oldGetRotation
local activeController
local baseDistance
local originalDistances = {}
local originalSubjectMethods = {}
local captureAfter = os.clock() + 0.20

local character
local humanoid
local root
local standingHipHeight
local standingRootSizeY
local standingClearance
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

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

local function getActiveController()
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

local function readDistance(controller)
    if not controller or type(controller.GetCameraToSubjectDistance) ~= "function" then
        return nil
    end

    local distance
    pcall(function()
        distance = controller:GetCameraToSubjectDistance()
    end)

    if type(distance) == "number" and distance == distance and distance > 0.5 then
        return distance
    end
    return nil
end

local function rememberDistance(controller)
    if controller and originalDistances[controller] == nil then
        originalDistances[controller] = readDistance(controller)
    end
end

local function stateAllowsAnchor()
    if not humanoid or not root or humanoid.Health <= 0 then
        return false
    end

    local state
    pcall(function()
        state = humanoid:GetState()
    end)

    if state == Enum.HumanoidStateType.Dead
        or state == Enum.HumanoidStateType.Physics
        or state == Enum.HumanoidStateType.Ragdoll
        or state == Enum.HumanoidStateType.FallingDown then
        return false
    end

    return true
end

local function currentGroundClearance()
    if not stateAllowsAnchor() then
        return nil
    end

    rayParams.FilterDescendantsInstances = {character}

    local result
    pcall(function()
        result = Workspace:Raycast(
            root.Position + Vector3.new(0, 0.25, 0),
            Vector3.new(0, -8, 0),
            rayParams
        )
    end)

    if not result then
        return nil
    end

    local clearance = root.Position.Y - result.Position.Y
    if clearance < 0.25 or clearance > 6 then
        return nil
    end

    return clearance
end

local function updateStandingBaselines()
    if not stateAllowsAnchor() then
        return
    end

    pcall(function()
        local hip = humanoid.HipHeight
        if type(hip) == "number" then
            if standingHipHeight == nil or hip > standingHipHeight then
                standingHipHeight = hip
            end
        end
    end)

    pcall(function()
        local sizeY = root.Size.Y
        if type(sizeY) == "number" then
            if standingRootSizeY == nil or sizeY > standingRootSizeY then
                standingRootSizeY = sizeY
            end
        end
    end)

    local clearance = currentGroundClearance()
    if clearance then
        local grounded = false
        pcall(function()
            grounded = humanoid.FloorMaterial ~= Enum.Material.Air
        end)

        local lowVerticalSpeed = true
        pcall(function()
            lowVerticalSpeed = math.abs(root.AssemblyLinearVelocity.Y) < 5
        end)

        if grounded and lowVerticalSpeed then
            if standingClearance == nil or clearance > standingClearance then
                standingClearance = clearance
            end
        end
    end
end

local function crouchHeightCompensation()
    if getgenv().PCCrouchCameraAnchor == false or not stateAllowsAnchor() then
        return 0
    end

    updateStandingBaselines()

    local compensation = 0

    -- Metodo 1: se o jogo reduz HipHeight/root size no crouch, desfaz exatamente essa queda.
    pcall(function()
        if standingHipHeight ~= nil then
            compensation = math.max(compensation, standingHipHeight - humanoid.HipHeight)
        end

        if standingRootSizeY ~= nil then
            compensation = math.max(
                compensation,
                (standingRootSizeY - root.Size.Y) * 0.5
            )
        end
    end)

    -- Metodo 2: cobre implementacoes que movem o root para baixo sem alterar HipHeight.
    local clearance = currentGroundClearance()
    if clearance and standingClearance then
        local grounded = false
        pcall(function()
            grounded = humanoid.FloorMaterial ~= Enum.Material.Air
        end)

        if grounded then
            compensation = math.max(compensation, standingClearance - clearance)
        end
    end

    if compensation < 0.10 then
        return 0
    end

    return math.clamp(compensation, 0, 2.5)
end

local function patchSubjectPosition(controller)
    if not controller or originalSubjectMethods[controller] ~= nil then
        return
    end

    local original = controller.GetSubjectPosition
    if type(original) ~= "function" then
        return
    end

    originalSubjectMethods[controller] = original

    controller.GetSubjectPosition = function(self, ...)
        local position = original(self, ...)

        if typeof(position) == "Vector3" and getgenv().PCCrouchCameraAnchor ~= false then
            local compensation = crouchHeightCompensation()
            if compensation > 0 then
                position = position + Vector3.new(0, compensation, 0)
            end
        end

        return position
    end
end

local function patchTouchPitchResponse()
    if cameraInput or oldGetRotation then
        return
    end

    local playerScripts = player:FindFirstChild("PlayerScripts")
    local playerModuleScript = playerScripts and playerScripts:FindFirstChild("PlayerModule")
    local cameraModuleScript = playerModuleScript and playerModuleScript:FindFirstChild("CameraModule")
    local cameraInputScript = cameraModuleScript and cameraModuleScript:FindFirstChild("CameraInput")
    if not cameraInputScript then
        return
    end

    local required
    local ok = pcall(function()
        required = require(cameraInputScript)
    end)
    if not ok or type(required) ~= "table" or type(required.getRotation) ~= "function" then
        return
    end

    cameraInput = required
    oldGetRotation = required.getRotation

    required.getRotation = function(...)
        local rotation = oldGetRotation(...)

        if getgenv().PCMousePitchResponse == false
            or not UserInputService.TouchEnabled
            or UserInputService.MouseEnabled
            or typeof(rotation) ~= "Vector2" then
            return rotation
        end

        local camera = Workspace.CurrentCamera
        if not camera then
            return rotation
        end

        -- CameraInput do Roblox reduz progressivamente o eixo Y do TOUCH quando a camera
        -- se aproxima de cima/baixo. Mouse nao faz isso. Desfazemos apenas essa curva,
        -- preservando a sensibilidade horizontal que o usuario ja usa no celular.
        local lookY = math.clamp(camera.CFrame.LookVector.Y, -1, 1)
        local pitch = math.asin(lookY)
        local curveY = 1 - (2 * math.abs(pitch) / math.pi) ^ 0.75
        local touchPitchSensitivity = curveY * 0.75 + 0.25

        return Vector2.new(
            rotation.X,
            rotation.Y / math.max(touchPitchSensitivity, 0.25)
        )
    end
end

local function resetCapture()
    activeController = nil
    baseDistance = nil
    captureAfter = os.clock() + 0.20
end

local function attachCharacter(newCharacter)
    character = newCharacter
    humanoid = newCharacter:WaitForChild("Humanoid", 10)
    root = newCharacter:WaitForChild("HumanoidRootPart", 10)

    standingHipHeight = nil
    standingRootSizeY = nil
    standingClearance = nil
    rayParams.FilterDescendantsInstances = {newCharacter}

    task.defer(function()
        updateStandingBaselines()
    end)

    resetCapture()
end

if player.Character then
    task.spawn(attachCharacter, player.Character)
end

local charConnection = player.CharacterAdded:Connect(function(newCharacter)
    task.spawn(attachCharacter, newCharacter)
end)

patchTouchPitchResponse()

RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 3, function()
    if getgenv().PCMovementEnabled == false then
        return
    end

    local camera = Workspace.CurrentCamera
    if camera then
        -- O video PC usa a projecao vertical normal; mantemos o FOV escolhido no Evade,
        -- apenas impedimos modos de FOV dependentes do aspect ratio de alterarem a geometria central.
        pcall(function()
            camera.FieldOfViewMode = Enum.FieldOfViewMode.Vertical
        end)
    end

    updateStandingBaselines()
    patchTouchPitchResponse()

    local controller = getActiveController()
    if not controller or type(controller.SetCameraToSubjectDistance) ~= "function" then
        return
    end

    patchSubjectPosition(controller)

    if controller ~= activeController then
        activeController = controller
        baseDistance = nil
        captureAfter = os.clock() + 0.20
        rememberDistance(controller)
    end

    if os.clock() < captureAfter then
        return
    end

    if not baseDistance then
        baseDistance = readDistance(controller)
        if not baseDistance then
            return
        end
    end

    local scale = tonumber(getgenv().PCCameraDistanceScale) or DEFAULT_DISTANCE_SCALE
    scale = math.clamp(scale, 1.0, 1.45)
    local target = baseDistance * scale

    pcall(function()
        if player.CameraMaxZoomDistance < target then
            player.CameraMaxZoomDistance = target
        end
    end)

    pcall(function()
        controller:SetCameraToSubjectDistance(target)
    end)
end)

getgenv().__PCMobileAimCleanup = function()
    pcall(function()
        RunService:UnbindFromRenderStep(bindName)
    end)

    pcall(function()
        charConnection:Disconnect()
    end)

    if cameraInput and oldGetRotation then
        pcall(function()
            cameraInput.getRotation = oldGetRotation
        end)
    end

    for controller, original in pairs(originalSubjectMethods) do
        pcall(function()
            controller.GetSubjectPosition = original
        end)
    end

    for controller, distance in pairs(originalDistances) do
        if distance and type(controller.SetCameraToSubjectDistance) == "function" then
            pcall(function()
                controller:SetCameraToSubjectDistance(distance)
            end)
        end
    end

    if oldMaxZoom ~= nil then
        pcall(function()
            player.CameraMaxZoomDistance = oldMaxZoom
        end)
    end

    if oldFovMode ~= nil then
        pcall(function()
            local camera = Workspace.CurrentCamera
            if camera then
                camera.FieldOfViewMode = oldFovMode
            end
        end)
    end

    if v9Cleanup then
        pcall(v9Cleanup)
    end

    getgenv().__PCMobileAimCleanup = nil
end
