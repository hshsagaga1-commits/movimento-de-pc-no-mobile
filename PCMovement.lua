local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local bindName = "__JoaoPCMovementCenterLock"

-- Reexecutar substitui a versao anterior sem empilhar nada.
if getgenv().__JoaoPCMovementCleanup then
    pcall(getgenv().__JoaoPCMovementCleanup)
end

pcall(function()
    RunService:UnbindFromRenderStep(bindName)
end)

local gui
local dot
local character
local humanoid
local rootPart
local oldAutoRotate
local attachment
local alignOrientation
local characterAddedConnection

local function destroyOrientation()
    if alignOrientation then
        pcall(function()
            alignOrientation:Destroy()
        end)
        alignOrientation = nil
    end

    if attachment then
        pcall(function()
            attachment:Destroy()
        end)
        attachment = nil
    end
end

local function clearCharacter()
    destroyOrientation()

    if humanoid and humanoid.Parent and oldAutoRotate ~= nil then
        pcall(function()
            humanoid.AutoRotate = oldAutoRotate
        end)
    end

    character = nil
    humanoid = nil
    rootPart = nil
    oldAutoRotate = nil
end

local function makeCenterDot()
    local playerGui = player:WaitForChild("PlayerGui")

    local old = playerGui:FindFirstChild("PCMovementCenterDot")
    if old then
        old:Destroy()
    end

    gui = Instance.new("ScreenGui")
    gui.Name = "PCMovementCenterDot"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 2147483647
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui

    dot = Instance.new("Frame")
    dot.Name = "CenterDot"
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.Position = UDim2.fromScale(0.5, 0.5)
    dot.Size = UDim2.fromOffset(2, 2)
    dot.BorderSizePixel = 0
    dot.BackgroundColor3 = Color3.new(1, 1, 1)
    dot.ZIndex = 1000000
    dot.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = dot
end

local function attachCharacter(newCharacter)
    clearCharacter()

    character = newCharacter
    humanoid = newCharacter:WaitForChild("Humanoid", 10)
    rootPart = newCharacter:WaitForChild("HumanoidRootPart", 10)

    if not humanoid or not rootPart then
        clearCharacter()
        return
    end

    oldAutoRotate = humanoid.AutoRotate
    humanoid.AutoRotate = false

    attachment = Instance.new("Attachment")
    attachment.Name = "__PCMovementCenterAttachment"
    attachment.Parent = rootPart

    alignOrientation = Instance.new("AlignOrientation")
    alignOrientation.Name = "__PCMovementCenterOrientation"
    alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
    alignOrientation.Attachment0 = attachment
    alignOrientation.RigidityEnabled = true
    alignOrientation.Responsiveness = 200
    alignOrientation.MaxTorque = math.huge
    alignOrientation.Parent = rootPart
end

local function getCenterDirection(camera)
    -- O PONTO e a referencia principal: pegamos um raio que sai EXATAMENTE
    -- do pixel central da tela, igual a mira do Minecraft / mouse-lock do PC.
    local viewport = camera.ViewportSize
    local centerX = viewport.X * 0.5
    local centerY = viewport.Y * 0.5
    local ray = camera:ViewportPointToRay(centerX, centerY)

    local direction = ray.Direction
    local flat = Vector3.new(direction.X, 0, direction.Z)

    if flat.Magnitude < 0.0001 then
        return nil
    end

    return flat.Unit
end

local function shouldLock()
    if getgenv().PCMovementEnabled == false then
        return false
    end

    if not character or not character.Parent or not humanoid or not rootPart then
        return false
    end

    if humanoid.Health <= 0 or rootPart.Anchored or humanoid.Sit then
        return false
    end

    local state = humanoid:GetState()
    if state == Enum.HumanoidStateType.Dead
        or state == Enum.HumanoidStateType.Seated
        or state == Enum.HumanoidStateType.Physics then
        return false
    end

    return true
end

makeCenterDot()

if player.Character then
    task.spawn(attachCharacter, player.Character)
end

characterAddedConnection = player.CharacterAdded:Connect(function(newCharacter)
    task.spawn(attachCharacter, newCharacter)
end)

-- Roda depois da camera e do controlador padrao de personagem.
-- Assim o centro da tela ganha a ultima palavra na orientacao visual.
RunService:BindToRenderStep(bindName, Enum.RenderPriority.Last.Value - 1, function()
    if gui then
        gui.Enabled = getgenv().PCMovementEnabled ~= false
    end

    if not shouldLock() then
        if alignOrientation then
            alignOrientation.Enabled = false
        end
        if humanoid and humanoid.Parent and oldAutoRotate ~= nil then
            humanoid.AutoRotate = oldAutoRotate
        end
        return
    end

    humanoid.AutoRotate = false

    if alignOrientation then
        alignOrientation.Enabled = true
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    local direction = getCenterDirection(camera)
    if not direction then
        return
    end

    -- O avatar fica cravado na direcao apontada pelo ponto central.
    local targetRotation = CFrame.lookAt(Vector3.zero, direction, Vector3.yAxis)

    if alignOrientation then
        alignOrientation.CFrame = targetRotation
    end

    -- Hard-lock visual no fim do frame. O AlignOrientation segura essa mesma
    -- orientacao na fisica, enquanto este snap impede scripts de camera/movimento
    -- do jogo de deixarem o personagem 'preguicoso' ou atrasado.
    if getgenv().PCMovementHardLock ~= false then
        local position = rootPart.Position
        rootPart.CFrame = CFrame.lookAt(position, position + direction, Vector3.yAxis)
    end
end)

getgenv().__JoaoPCMovementCleanup = function()
    pcall(function()
        RunService:UnbindFromRenderStep(bindName)
    end)

    if characterAddedConnection then
        pcall(function()
            characterAddedConnection:Disconnect()
        end)
        characterAddedConnection = nil
    end

    if gui then
        pcall(function()
            gui:Destroy()
        end)
        gui = nil
        dot = nil
    end

    clearCharacter()
    getgenv().__JoaoPCMovementCleanup = nil
end

if getgenv().PCMovementEnabled == nil then
    getgenv().PCMovementEnabled = true
end

-- true = ponto central manda na orientacao sem atraso.
if getgenv().PCMovementHardLock == nil then
    getgenv().PCMovementHardLock = true
end
