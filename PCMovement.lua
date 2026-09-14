local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local bindName = "__PCMobileRawCamera"

-- Limpa qualquer versao anterior sem empilhar conexoes/cameras.
if getgenv().__PCMobileAimCleanup then
    pcall(getgenv().__PCMobileAimCleanup)
end
pcall(function()
    RunService:UnbindFromRenderStep(bindName)
end)

local camera = Workspace.CurrentCamera
local oldCameraType = camera and camera.CameraType or nil
local oldCameraSubject = camera and camera.CameraSubject or nil

local connections = {}
local character
local humanoid
local rootPart
local activeLookTouch
local lastTouchPosition
local yaw = 0
local pitch = 0
local distance = 8
local suspended = false
local scriptOwnsCamera = false

-- Ajustes opcionais:
-- getgenv().PCMovementSensitivity = 0.005
-- getgenv().PCMovementDistance = 8
-- getgenv().PCMovementTrackOffset = Vector3.new(0, 0, 0)
-- getgenv().PCMovementTouchStartX = 0.42
-- getgenv().PCMovementCameraCollision = true

if getgenv().PCMovementEnabled == nil then
    getgenv().PCMovementEnabled = true
end
if getgenv().PCMovementSensitivity == nil then
    getgenv().PCMovementSensitivity = 0.005
end
if getgenv().PCMovementTouchStartX == nil then
    getgenv().PCMovementTouchStartX = 0.42
end
if getgenv().PCMovementCameraCollision == nil then
    getgenv().PCMovementCameraCollision = true
end

local function enabled()
    return getgenv().PCMovementEnabled ~= false
end

-- O ponto fica imovel no centro da tela, como o cursor travado no PC.
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

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

local function getCamera()
    camera = Workspace.CurrentCamera
    return camera
end

local function setAnglesFromLookVector(look)
    if not look or look.Magnitude < 0.001 then
        return
    end

    local unit = look.Unit
    pitch = math.asin(math.clamp(unit.Y, -1, 1))
    yaw = math.atan2(-unit.X, -unit.Z)
end

local function getLookVector()
    return CFrame.Angles(pitch, yaw, 0).LookVector
end

local function currentSensitivity()
    local value = tonumber(getgenv().PCMovementSensitivity)
    if not value then
        return 0.005
    end
    return math.clamp(value, 0.0005, 0.03)
end

local function currentDistance()
    local override = tonumber(getgenv().PCMovementDistance)
    if override then
        return math.clamp(override, 2, 30)
    end
    return math.clamp(distance, 2, 30)
end

local function currentTrackOffset()
    local override = getgenv().PCMovementTrackOffset
    if typeof(override) == "Vector3" then
        return override
    end
    return Vector3.zero
end

local function releaseLookTouch(input)
    if activeLookTouch == input then
        activeLookTouch = nil
        lastTouchPosition = nil
    end
end

local function restoreRobloxCamera(subject)
    local cam = getCamera()
    if not cam then return end

    pcall(function()
        cam.CameraType = oldCameraType or Enum.CameraType.Custom
    end)

    local wantedSubject = subject or oldCameraSubject or humanoid
    if wantedSubject then
        pcall(function()
            cam.CameraSubject = wantedSubject
        end)
    end

    scriptOwnsCamera = false
end

local function attachCharacter(newCharacter)
    character = newCharacter
    humanoid = newCharacter:WaitForChild("Humanoid", 10)
    rootPart = newCharacter:WaitForChild("HumanoidRootPart", 10)
    suspended = false
    activeLookTouch = nil
    lastTouchPosition = nil

    if not humanoid or not rootPart then
        return
    end

    local cam = getCamera()
    if not cam then return end

    -- Mantem o angulo e o zoom aproximados que o jogo ja estava usando.
    setAnglesFromLookVector(cam.CFrame.LookVector)

    local trackPoint = rootPart.Position + currentTrackOffset()
    local candidateDistance = (cam.CFrame.Position - trackPoint).Magnitude
    if candidateDistance >= 2 and candidateDistance <= 30 then
        distance = candidateDistance
    else
        distance = 8
    end

    pcall(function()
        cam.CameraType = Enum.CameraType.Scriptable
        scriptOwnsCamera = true
    end)

    table.insert(connections, humanoid.Died:Connect(function()
        suspended = true
        activeLookTouch = nil
        lastTouchPosition = nil
        restoreRobloxCamera(humanoid)
    end))
end

if player.Character then
    task.spawn(attachCharacter, player.Character)
end

table.insert(connections, player.CharacterAdded:Connect(function(newCharacter)
    task.spawn(attachCharacter, newCharacter)
end))

-- Dedo da direita = mouse relativo. O joystick da esquerda nao e usado pela camera.
table.insert(connections, UserInputService.TouchStarted:Connect(function(input, gameProcessedEvent)
    if gameProcessedEvent or not enabled() or suspended then
        return
    end

    local cam = getCamera()
    if not cam then return end

    local viewport = cam.ViewportSize
    if viewport.X <= 0 then return end

    local threshold = math.clamp(tonumber(getgenv().PCMovementTouchStartX) or 0.42, 0.25, 0.75)
    if input.Position.X < viewport.X * threshold then
        return
    end

    if activeLookTouch == nil then
        activeLookTouch = input
        lastTouchPosition = Vector2.new(input.Position.X, input.Position.Y)
    end
end))

table.insert(connections, UserInputService.TouchMoved:Connect(function(input)
    if input ~= activeLookTouch or not enabled() or suspended then
        return
    end

    local now = Vector2.new(input.Position.X, input.Position.Y)
    local previous = lastTouchPosition or now
    local delta = now - previous
    lastTouchPosition = now

    -- RAW: sem lerp e sem smoothing do controlador touch padrao.
    local sensitivity = currentSensitivity()
    yaw = yaw - delta.X * sensitivity
    pitch = math.clamp(pitch - delta.Y * sensitivity, math.rad(-80), math.rad(80))
end))

table.insert(connections, UserInputService.TouchEnded:Connect(function(input)
    releaseLookTouch(input)
end))

local function getTrackedPoint()
    if not rootPart or not rootPart.Parent then
        return nil
    end

    -- Esse e o "tracking de edicao": o ponto rastreado e a POSICAO do personagem.
    -- A rotacao do HumanoidRootPart nao entra na conta; emote/ragdoll podem girar livres.
    return rootPart.Position + currentTrackOffset()
end

local function solveCameraPosition(trackPoint, desiredPosition)
    if getgenv().PCMovementCameraCollision == false or not character then
        return desiredPosition
    end

    raycastParams.FilterDescendantsInstances = { character }

    local direction = desiredPosition - trackPoint
    if direction.Magnitude < 0.001 then
        return desiredPosition
    end

    local result = Workspace:Raycast(trackPoint, direction, raycastParams)
    if not result then
        return desiredPosition
    end

    local safePosition = result.Position + result.Normal * 0.25
    if (safePosition - trackPoint).Magnitude < 0.6 then
        safePosition = trackPoint + direction.Unit * 0.6
    end
    return safePosition
end

RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 50, function()
    screenGui.Enabled = enabled() and not suspended

    if not enabled() or suspended then
        if scriptOwnsCamera then
            restoreRobloxCamera()
        end
        return
    end

    local cam = getCamera()
    if not cam or not humanoid or not rootPart or humanoid.Health <= 0 then
        return
    end

    if cam.CameraType ~= Enum.CameraType.Scriptable then
        pcall(function()
            cam.CameraType = Enum.CameraType.Scriptable
            scriptOwnsCamera = true
        end)
    end

    local trackPoint = getTrackedPoint()
    if not trackPoint then return end

    local look = getLookVector()
    local wantedPosition = trackPoint - look * currentDistance()
    local cameraPosition = solveCameraPosition(trackPoint, wantedPosition)

    -- O personagem fica CRAVADO no pontinho porque a camera olha exatamente
    -- para o ponto rastreado do HumanoidRootPart em todo frame.
    -- A camera acompanha apenas a translacao; a rotacao vem exclusivamente do dedo.
    cam.CFrame = CFrame.lookAt(cameraPosition, trackPoint, Vector3.yAxis)
    cam.Focus = CFrame.new(trackPoint)
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

    restoreRobloxCamera()

    activeLookTouch = nil
    lastTouchPosition = nil
    getgenv().__PCMobileAimCleanup = nil
end
