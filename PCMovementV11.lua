local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local bindName = "__PCMovementPCFramingV11"
local V9_URL = "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovement.lua"

-- V11 = V9 intacta + enquadramento refinado usando a comparacao no MESMO mapa.
-- O video novo mostrou que +15% (V10) ainda deixava o personagem mobile ~25-35% maior/proximo.
-- Mantemos FOV, offset, input, emotes e CameraModule da V9; somente a distancia nativa muda.
local DEFAULT_DISTANCE_SCALE = 1.30

-- Carrega a V9 real, sem cache.
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
    -- Se veio da V10 com o default antigo, sobe automaticamente para o alvo novo.
    local existing = tonumber(getgenv().PCCameraDistanceScale)
    if existing and math.abs(existing - 1.15) < 0.001 then
        getgenv().PCCameraDistanceScale = DEFAULT_DISTANCE_SCALE
    end
end

local v9Cleanup = getgenv().__PCMobileAimCleanup
local oldMaxZoom
pcall(function()
    oldMaxZoom = player.CameraMaxZoomDistance
end)

local playerModule
local cameras
local activeController
local baseDistance
local originalDistances = {}
local captureAfter = os.clock() + 0.20

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

local function resetCapture()
    activeController = nil
    baseDistance = nil
    captureAfter = os.clock() + 0.20
end

local charConnection = player.CharacterAdded:Connect(function()
    resetCapture()
end)

RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 3, function()
    if getgenv().PCMovementEnabled == false then
        return
    end

    local controller = getActiveController()
    if not controller or type(controller.SetCameraToSubjectDistance) ~= "function" then
        return
    end

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

    -- So aumenta o limite se o jogo estiver bloqueando a distancia alvo.
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

    if v9Cleanup then
        pcall(v9Cleanup)
    end

    getgenv().__PCMobileAimCleanup = nil
end
