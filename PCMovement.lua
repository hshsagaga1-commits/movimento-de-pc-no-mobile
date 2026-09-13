local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local bindName = "__JoaoPCMovementLock"

-- Reexecutar o script substitui a instancia anterior sem empilhar conexoes.
if getgenv().__JoaoPCMovementCleanup then
    pcall(getgenv().__JoaoPCMovementCleanup)
end

pcall(function()
    RunService:UnbindFromRenderStep(bindName)
end)

local currentCharacter
local humanoid
local rootPart
local oldAutoRotate
local charConnection

local function clearCharacter()
    if humanoid and humanoid.Parent and oldAutoRotate ~= nil then
        pcall(function()
            humanoid.AutoRotate = oldAutoRotate
        end)
    end

    currentCharacter = nil
    humanoid = nil
    rootPart = nil
    oldAutoRotate = nil
end

local function attachCharacter(character)
    clearCharacter()

    currentCharacter = character
    humanoid = character:WaitForChild("Humanoid", 10)
    rootPart = character:WaitForChild("HumanoidRootPart", 10)

    if not humanoid or not rootPart then
        clearCharacter()
        return
    end

    oldAutoRotate = humanoid.AutoRotate
    humanoid.AutoRotate = false
end

if player.Character then
    task.spawn(attachCharacter, player.Character)
end

charConnection = player.CharacterAdded:Connect(function(character)
    task.spawn(attachCharacter, character)
end)

RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 1, function()
    if getgenv().PCMovementEnabled == false then
        if humanoid and humanoid.Parent and oldAutoRotate ~= nil then
            humanoid.AutoRotate = oldAutoRotate
        end
        return
    end

    if not currentCharacter or not currentCharacter.Parent or not humanoid or not rootPart then
        return
    end

    if humanoid.Health <= 0 or rootPart.Anchored then
        return
    end

    local state = humanoid:GetState()
    if state == Enum.HumanoidStateType.Dead
        or state == Enum.HumanoidStateType.Seated
        or state == Enum.HumanoidStateType.Ragdoll
        or state == Enum.HumanoidStateType.Physics then
        return
    end

    humanoid.AutoRotate = false

    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    -- O centro da camera funciona como o "crosshair virtual" do PC.
    -- A camera continua sendo controlada normalmente pelo dedo; o corpo segue
    -- exatamente o yaw desse ponto central, sem o atraso do AutoRotate mobile.
    local look = camera.CFrame.LookVector
    local flatLook = Vector3.new(look.X, 0, look.Z)

    if flatLook.Magnitude < 0.0001 then
        return
    end

    flatLook = flatLook.Unit

    local position = rootPart.Position
    local target = CFrame.lookAt(position, position + flatLook, Vector3.yAxis)

    local responsiveness = tonumber(getgenv().PCMovementResponsiveness)
    if responsiveness == nil then
        responsiveness = 1
    end
    responsiveness = math.clamp(responsiveness, 0.01, 1)

    if responsiveness >= 0.999 then
        rootPart.CFrame = target
    else
        rootPart.CFrame = rootPart.CFrame:Lerp(target, responsiveness)
    end
end)

getgenv().__JoaoPCMovementCleanup = function()
    pcall(function()
        RunService:UnbindFromRenderStep(bindName)
    end)

    if charConnection then
        pcall(function()
            charConnection:Disconnect()
        end)
        charConnection = nil
    end

    clearCharacter()
    getgenv().__JoaoPCMovementCleanup = nil
end

-- Defaults: resposta imediata, estilo mouse-lock/shift-lock de PC.
if getgenv().PCMovementEnabled == nil then
    getgenv().PCMovementEnabled = true
end
if getgenv().PCMovementResponsiveness == nil then
    getgenv().PCMovementResponsiveness = 1
end
