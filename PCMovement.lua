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
local focusOffset = Vector3.new(0, 1.5, 0)
local suspended = false

-- Ajustes globais opcionais:
-- getgenv().PCMovementSensitivity = 0.005
-- getgenv().PCMovementDistance = 8
-- getgenv().PCMovementFocusOffset = Vector3.new(0, 1.5, 0)
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

-- PONTO FIXO: equivale ao cursor travado no centro no PC.
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
    local rotation = CFrame.Angles(pitch, yaw, 0)
    return rotation.LookVector
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

local function currentFocusOffset()
    local override = getgenv().PCMovementFocusOffset
    if typeof(override) == "Vector3" then
        return override
    end
    return focusOffset
end

local function releaseLookTouch(input)
    if activeLookTouch == input then
        activeLookTouch = nil
        lastTouchPosition = nil
    end
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

    -- Comeca exatamente do enquadramento em que o jogo ja estava.
    setAnglesFromLookVector(cam.CFrame.LookVector)

    local initialFocus = cam.Focus.Position
    local candidateOffset = initialFocus - rootPart.Position
    if candidateOffset.Magnitude <= 6 then
        focusOffset = candidateOffset
    else
        focusOffset = Vector3.new(0, 1.5, 0)
        initialFocus = rootPart.Position + focusOffset
    end

    local candidateDistance = (cam.CFrame.Position - initialFocus).Magnitude
    if candidateDistance >= 2 and candidateDistance <= 30 then
        distance = candidateDistance
    else
        distance = 8
    end

    pcall(function()
        cam.CameraType = Enum.CameraType.Scriptable
    end)

    table.insert(connections, humanoid.Died:Connect(function()
        suspended = true
        activeLookTouch = nil
        lastTouchPosition = nil

        local current = getCamera()
        if current then
            pcall(function()
                current.CameraType = Enum.CameraType.Custom
                current.CameraSubject = humanoid
            end)
        end
    end))
end

if player.Character then
    task.spawn(attachCharacter, player.Character)
end

table.insert(connections, player.CharacterAdded:Connect(function(newCharacter)
    task.spawn(attachCharacter, newCharacter)
end))

-- Dedo da DIREITA = mouse relativo. O joystick da esquerda nunca e capturado.
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

table.insert(connections, UserInputService.TouchMoved:Connect(function(input, gameProcessedEvent)
    if input ~= activeLookTouch or not enabled() or suspended then
        return
    end

    local now = Vector2.new(input.Position.X, input.Position.Y)
    local previous = lastTouchPosition or now
    local delta = now - previous
    lastTouchPosition = now

    -- RAW: sem lerp, sem aceleracao, sem smoothing do controlador touch do Roblox.
    local sensitivity = currentSensitivity()
    yaw = yaw - delta.X * sensitivity
    pitch = math.clamp(pitch - delta.Y * sensitivity, math.rad(-80), math.rad(80))
end))

table.insert(connections, UserInputService.TouchEnded:Connect(function(input)
    releaseLookTouch(input)
end))

local function getTrackedFocus()
    if not rootPart or not rootPart.Parent then
        return nil
    end

    -- Tracking de edicao: so POSICAO.
    -- Nao usa CFrame/rotacao do personagem, entao emote/ragdoll continuam livres.
    return rootPart.Position + currentFocusOffset()
end

local function solveCameraPosition(focus, desiredPosition)
    if getgenv().PCMovementCameraCollision == false or not character then
        return desiredPosition
    end

    raycastParams.FilterDescendantsInstances = { character }

    local direction = desiredPosition - focus
    local result = Workspace:Raycast(focus, direction, raycastParams)
    if not result then
        return desiredPosition
    end

    -- Puxa a camera um pouco para fora da parede.
    local safePosition = result.Position + result.Normal * 0.25
    if (safePosition - focus).Magnitude < 0.6 then
        safePosition = focus + direction.Unit * 0.6
    end
    return safePosition
end

RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 50, function()
    screenGui.Enabled = enabled() and not suspended

    if not enabled() or suspended then
        return
    end

    local cam = getCamera()
    if not cam or not humanoid or not rootPart or humanoid.Health <= 0 then
        return
    end

    -- Mantem o controlador touch padrao fora da equacao.
    if cam.CameraType ~= Enum.CameraType.Scriptable then
        pcall(function()
            cam.CameraType = Enum.CameraType.Scriptable
        end)
    end

    local focus = getTrackedFocus()
    if not focus then return end

    local look = getLookVector()
    local wantedPosition = focus - look * currentDistance()
    local cameraPosition = solveCameraPosition(focus, wantedPosition)

    -- Translacao acompanha o boneco 1:1 no mesmo frame.
    -- Rotacao vem SOMENTE do delta do dedo, como mouse preso no centro.
    cam.CFrame = CFrame.lookAt(cameraPosition, focus, Vector3.yAxis)
    cam.Focus = CFrame.new(focus)
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

    local cam = getCamera()
    if cam then
        if oldCameraType ~= nil then
            pcall(function()
                cam.CameraType = oldCameraType
            end)
        else
            pcall(function()
                cam.CameraType = Enum.CameraType.Custom
            end)
        end

        if oldCameraSubject ~= nil then
            pcall(function()
                cam.CameraSubject = oldCameraSubject
            end)
        elseif humanoid then
            pcall(function()
                cam.CameraSubject = humanoid
            end)
        end
    end

    activeLookTouch = nil
    lastTouchPosition = nil
    getgenv().__PCMobileAimCleanup = nil
end
