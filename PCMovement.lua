local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local bindName = "__PCMobileAimRender"

if getgenv().__PCMobileAimCleanup then
    pcall(getgenv().__PCMobileAimCleanup)
end

pcall(function()
    RunService:UnbindFromRenderStep(bindName)
end)

local guiParent = CoreGui
pcall(function()
    if gethui then
        guiParent = gethui()
    end
end)

pcall(function()
    local old = guiParent:FindFirstChild("PCMobileAim")
    if old then
        old:Destroy()
    end
end)

-- O PONTO e a referencia principal. A camera e o personagem sao seguidores separados.
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

local character
local humanoid
local rootPart
local oldAutoRotate
local oldCameraOffset
local aimAttachment
local aimAlign
local characterConnection
local targetLook

local function enabled()
    return getgenv().PCMovementEnabled ~= false
end

local function getCameraOffset()
    local v = getgenv().PCMovementCameraOffset
    if typeof(v) == "Vector3" then
        return v
    end

    -- Aproxima o deslocamento lateral do mouse-lock/shift-lock de PC.
    return Vector3.new(1.6, 0, 0)
end

local function destroyAimObjects()
    if aimAlign then
        pcall(function() aimAlign:Destroy() end)
        aimAlign = nil
    end
    if aimAttachment then
        pcall(function() aimAttachment:Destroy() end)
        aimAttachment = nil
    end
end

local function restoreCharacter()
    destroyAimObjects()

    if humanoid and humanoid.Parent then
        if oldAutoRotate ~= nil then
            pcall(function()
                humanoid.AutoRotate = oldAutoRotate
            end)
        end
        if oldCameraOffset ~= nil then
            pcall(function()
                humanoid.CameraOffset = oldCameraOffset
            end)
        end
    end

    character = nil
    humanoid = nil
    rootPart = nil
    oldAutoRotate = nil
    oldCameraOffset = nil
    targetLook = nil
end

local function makeAimLock()
    destroyAimObjects()
    if not rootPart then return end

    aimAttachment = Instance.new("Attachment")
    aimAttachment.Name = "__PCMobileAimAttachment"
    aimAttachment.Parent = rootPart

    aimAlign = Instance.new("AlignOrientation")
    aimAlign.Name = "__PCMobileAimLock"
    aimAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment
    aimAlign.Attachment0 = aimAttachment
    aimAlign.RigidityEnabled = true
    aimAlign.Responsiveness = 200
    aimAlign.MaxTorque = math.huge
    aimAlign.MaxAngularVelocity = math.huge
    aimAlign.Parent = rootPart
end

local function attachCharacter(newCharacter)
    restoreCharacter()

    character = newCharacter
    humanoid = newCharacter:WaitForChild("Humanoid", 10)
    rootPart = newCharacter:WaitForChild("HumanoidRootPart", 10)

    if not humanoid or not rootPart then
        restoreCharacter()
        return
    end

    oldAutoRotate = humanoid.AutoRotate
    oldCameraOffset = humanoid.CameraOffset

    humanoid.AutoRotate = false
    humanoid.CameraOffset = getCameraOffset()
    makeAimLock()
end

if player.Character then
    task.spawn(attachCharacter, player.Character)
end

characterConnection = player.CharacterAdded:Connect(function(newCharacter)
    task.spawn(attachCharacter, newCharacter)
end)

local function canLockBody()
    if not enabled() then return false end
    if not character or not character.Parent then return false end
    if not humanoid or not humanoid.Parent then return false end
    if not rootPart or not rootPart.Parent then return false end
    if humanoid.Health <= 0 then return false end
    if humanoid.Sit then return false end
    if humanoid.PlatformStand then return false end
    if rootPart.Anchored then return false end

    local state = humanoid:GetState()
    if state == Enum.HumanoidStateType.Dead or state == Enum.HumanoidStateType.Seated then
        return false
    end

    -- IMPORTANTE: nao bloqueamos HumanoidStateType.Physics.
    -- Jogos como Evade podem usar estados fisicos durante a movimentacao normal.
    return true
end

local function updateAimFromPoint()
    local camera = Workspace.CurrentCamera
    if not camera then return end

    local viewport = camera.ViewportSize
    if viewport.X <= 0 or viewport.Y <= 0 then return end

    -- A DIRECAO nasce do pixel do pontinho, nao da posicao/direcao do personagem.
    local centerX = viewport.X * 0.5
    local centerY = viewport.Y * 0.5
    local ray = camera:ViewportPointToRay(centerX, centerY)

    local dir = ray.Direction
    local flat = Vector3.new(dir.X, 0, dir.Z)
    if flat.Magnitude < 0.0001 then return end

    targetLook = flat.Unit
end

local function applyBodyLock()
    if not canLockBody() or not targetLook then
        return
    end

    humanoid.AutoRotate = false
    humanoid.CameraOffset = getCameraOffset()

    local p = rootPart.Position
    local target = CFrame.lookAt(p, p + targetLook, Vector3.yAxis)

    if aimAlign and aimAlign.Parent then
        aimAlign.CFrame = target.Rotation
    end

    -- Hard-lock do yaw. Mantem a velocidade/movimento, mas impede o corpo
    -- de girar para o lado que o joystick esta empurrando.
    rootPart.CFrame = target
    rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
end

-- Primeiro a camera do Roblox processa o toque. Depois lemos EXATAMENTE o centro
-- da tela e usamos esse ponto como a nova direcao de mira.
RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 50, function()
    if not enabled() then
        screenGui.Enabled = false
        if humanoid and humanoid.Parent and oldAutoRotate ~= nil then
            humanoid.AutoRotate = oldAutoRotate
            if oldCameraOffset ~= nil then
                humanoid.CameraOffset = oldCameraOffset
            end
        end
        return
    end

    screenGui.Enabled = true
    updateAimFromPoint()
    applyBodyLock()
end)

-- Reaplica no passo de fisica tambem. Assim o controlador do jogo nao consegue
-- soltar o corpo da mira entre frames.
local heartbeatConnection = RunService.Heartbeat:Connect(function()
    applyBodyLock()
end)

getgenv().__PCMobileAimCleanup = function()
    pcall(function()
        RunService:UnbindFromRenderStep(bindName)
    end)

    if heartbeatConnection then
        pcall(function() heartbeatConnection:Disconnect() end)
        heartbeatConnection = nil
    end

    if characterConnection then
        pcall(function() characterConnection:Disconnect() end)
        characterConnection = nil
    end

    restoreCharacter()

    pcall(function()
        screenGui:Destroy()
    end)

    getgenv().__PCMobileAimCleanup = nil
end

if getgenv().PCMovementEnabled == nil then
    getgenv().PCMovementEnabled = true
end
