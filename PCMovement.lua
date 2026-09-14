local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer

-- Limpa qualquer versao anterior (inclusive as V1/V2 que prendiam a rotacao do corpo).
if getgenv().__PCMobileAimCleanup then
    pcall(getgenv().__PCMobileAimCleanup)
end

local connections = {}
local oldPlayerCameraMode
local oldDevTouchCameraMode
local oldStarterTouchMode
local oldUserTouchMode

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
end)

-- O pontinho e apenas a referencia visual do centro da camera.
-- ELE NAO gira o personagem. O joystick continua sendo exclusivamente do personagem.
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

local function forceClassicCamera()
    -- Terceira pessoa normal. Nao ativa shift-lock e nao prende o corpo na camera.
    pcall(function()
        player.CameraMode = Enum.CameraMode.Classic
    end)

    -- Esse e o ponto principal: no touch, Classic acompanha a POSICAO do jogador,
    -- mas nao gira a camera automaticamente quando o personagem anda para os lados.
    trySetProperty(player, "DevTouchCameraMode", Enum.DevTouchCameraMovementMode.Classic)
    trySetProperty(StarterPlayer, "DevTouchCameraMovementMode", Enum.DevTouchCameraMovementMode.Classic)

    if userGameSettings then
        trySetProperty(userGameSettings, "TouchCameraMovementMode", Enum.TouchCameraMovementMode.Classic)
    end

    -- Se a API atual do PlayerModule estiver exposta, manda o controlador ativo
    -- usar Classic imediatamente. Em clientes onde a API e fechada, simplesmente ignora.
    pcall(function()
        local playerScripts = player:FindFirstChild("PlayerScripts")
        local moduleScript = playerScripts and playerScripts:FindFirstChild("PlayerModule")
        if not moduleScript then return end

        local playerModule = require(moduleScript)
        if type(playerModule) ~= "table" or type(playerModule.GetCameras) ~= "function" then
            return
        end

        local cameras = playerModule:GetCameras()
        if type(cameras) ~= "table" then return end

        if type(cameras.ActivateCameraController) == "function" then
            cameras:ActivateCameraController(Enum.ComputerCameraMovementMode.Classic)
        elseif type(cameras.GetActiveCameraController) == "function" then
            local controller = cameras:GetActiveCameraController()
            if controller and type(controller.SetCameraMovementMode) == "function" then
                controller:SetCameraMovementMode(Enum.ComputerCameraMovementMode.Classic)
            end
        end
    end)

    -- Mantem o CameraSubject normal no personagem. Isso e o que faz a camera
    -- acompanhar a translacao dele pela fase, sem amarrar a orientacao do corpo.
    local camera = Workspace.CurrentCamera
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if camera and humanoid and camera.CameraType ~= Enum.CameraType.Scriptable then
        pcall(function()
            camera.CameraType = Enum.CameraType.Custom
            camera.CameraSubject = humanoid
        end)
    end
end

forceClassicCamera()

-- Respawn: reaplica apenas a camera. Nao toca no movimento/rotacao do personagem.
table.insert(connections, player.CharacterAdded:Connect(function(character)
    local humanoid = character:WaitForChild("Humanoid", 10)
    task.wait()
    forceClassicCamera()

    local camera = Workspace.CurrentCamera
    if camera and humanoid and camera.CameraType ~= Enum.CameraType.Scriptable then
        pcall(function()
            camera.CameraSubject = humanoid
        end)
    end
end))

-- Se o jogo tentar trocar o modo touch de volta para Follow/UserChoice,
-- reaplica Classic. Nada aqui escreve CFrame do personagem.
pcall(function()
    table.insert(connections, player:GetPropertyChangedSignal("DevTouchCameraMode"):Connect(function()
        if getgenv().PCMovementEnabled ~= false then
            task.defer(forceClassicCamera)
        end
    end))
end)

getgenv().__PCMobileAimCleanup = function()
    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(connections)

    pcall(function()
        screenGui:Destroy()
    end)

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

if getgenv().PCMovementEnabled == nil then
    getgenv().PCMovementEnabled = true
end
