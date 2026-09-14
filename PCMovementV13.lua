local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local V9_URL = "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovement.lua"

local OLD_MOVEMENT_BIND = "__PCMovementDigitalWASD"
local MOVEMENT_BIND = "__PCMovementKeyboardCloneV13"
local CAMERA_BIND = "__PCMovementCrouchAnchorV13"

-- V13 e um rebuild a partir da V9, depois da revisao quadro-a-quadro.
-- NAO herda o zoom 1.30 da V11/V12.
-- NAO altera CameraInput/getRotation e NAO desfaz a curva vertical do touch.
-- Mantem a camera nativa, o shift-lock (2, .5, 0) e o comportamento de emote da V9.
-- Movimento: replica o caminho do ControlModule de teclado do Roblox:
-- teclado digital -> transformacao camera-yaw -> Player:Move(..., false).
-- Crouch: usa o proprio KeybindUsed("Crouch", true/false) do Legacy e ancora a
-- altura do subject em relacao ao chao, sem travar pitch/yaw e sem Camera.CFrame.

local source = game:HttpGet(
    V9_URL .. "?_cb=" .. HttpService:GenerateGUID(false),
    true
)
local chunk, err = loadstring(source)
if not chunk then
    error(err)
end
chunk()

-- A V9 acabou de instalar o baseline. Guardamos seu cleanup e substituimos
-- apenas a camada de movimento que antes usava Player:Move(vector, true).
local v9Cleanup = getgenv().__PCMobileAimCleanup
pcall(function()
    RunService:UnbindFromRenderStep(OLD_MOVEMENT_BIND)
    RunService:UnbindFromRenderStep(MOVEMENT_BIND)
    RunService:UnbindFromRenderStep(CAMERA_BIND)
end)

getgenv().PCMovementVersion = "V13"

local playerModule
local controls
local cameras
local character
local humanoid
local root
local connections = {}

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

local function attachCharacter(newCharacter)
    character = newCharacter
    humanoid = newCharacter:WaitForChild("Humanoid", 10)
    root = newCharacter:WaitForChild("HumanoidRootPart", 10)
end

if player.Character then
    task.spawn(attachCharacter, player.Character)
end

table.insert(connections, player.CharacterAdded:Connect(function(newCharacter)
    task.spawn(attachCharacter, newCharacter)
end))

-- Exatamente as combinacoes que um teclado produz. Diagonais ficam (1,0,1),
-- e nao (0.707,0,0.707); Player:Move faz o mesmo tratamento final usado no PC.
local function quantizeToKeyboard(moveVector)
    local x = moveVector.X
    local z = moveVector.Z
    local magnitude = math.sqrt(x * x + z * z)

    if magnitude < 0.18 then
        return Vector3.zero
    end

    local angle = math.atan2(x, -z)
    local step = math.pi / 4
    local snapped = math.floor((angle / step) + 0.5) * step

    local keyboardX = math.round(math.sin(snapped))
    local keyboardZ = math.round(-math.cos(snapped))

    return Vector3.new(keyboardX, 0, keyboardZ)
end

-- Mesma transformacao yaw-only usada pelo ControlModule antes de chamar
-- Player:Move(..., false). Isso evita deixar o pitch da camera contaminar
-- a direcao do WASD quando a camera esta muito para cima/baixo.
local function calculatePCMoveVector(cameraRelativeMoveVector)
    local camera = Workspace.CurrentCamera
    if not camera then
        return cameraRelativeMoveVector
    end

    if humanoid then
        local state
        pcall(function()
            state = humanoid:GetState()
        end)
        if state == Enum.HumanoidStateType.Swimming then
            return camera.CFrame:VectorToWorldSpace(cameraRelativeMoveVector)
        end
    end

    local _, _, _, R00, R01, R02, _, _, R12, _, _, R22 = camera.CFrame:GetComponents()
    local c, s

    if R12 < 1 and R12 > -1 then
        c = R22
        s = R02
    else
        c = R00
        s = -R01 * math.sign(R12)
    end

    local norm = math.sqrt(c * c + s * s)
    if norm < 1e-6 then
        return Vector3.zero
    end

    return Vector3.new(
        (c * cameraRelativeMoveVector.X + s * cameraRelativeMoveVector.Z) / norm,
        0,
        (c * cameraRelativeMoveVector.Z - s * cameraRelativeMoveVector.X) / norm
    )
end

RunService:BindToRenderStep(MOVEMENT_BIND, Enum.RenderPriority.Input.Value + 2, function()
    if getgenv().PCMovementEnabled == false
        or getgenv().PCMovementDigitalInput == false
        or not UserInputService.TouchEnabled
        or not humanoid
        or humanoid.Health <= 0 then
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

    local keyboardMove = quantizeToKeyboard(rawMove)
    local worldMove = calculatePCMoveVector(keyboardMove)

    pcall(function()
        player:Move(worldMove, false)
    end)
end)

-- ==================== CROUCH CAMERA ANCHOR ====================
-- A camera do PC de referencia nao acompanha toda a queda visual do corpo no
-- crouch/stand. Em vez de inferir crouch por HipHeight/maximos (V12), V13 escuta
-- o evento que o proprio Legacy usa e segura somente a ALTURA do subject.
-- Yaw/pitch/zoom continuam 100% nativos.

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local originalSubjectMethods = {}
local crouchActive = false
local releasePending = false
local releaseDeadline = 0
local standingSubjectAboveGround
local lastGroundY

local function isGrounded()
    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    local grounded = false
    pcall(function()
        grounded = humanoid.FloorMaterial ~= Enum.Material.Air
    end)
    return grounded
end

local function groundY()
    if not character or not root then
        return nil
    end

    rayParams.FilterDescendantsInstances = {character}

    local result
    pcall(function()
        result = Workspace:Raycast(
            root.Position + Vector3.new(0, 2.5, 0),
            Vector3.new(0, -12, 0),
            rayParams
        )
    end)

    if not result then
        return nil
    end

    return result.Position.Y
end

local function nativeSubjectPosition(controller)
    if not controller then
        return nil
    end

    local original = originalSubjectMethods[controller]
    local position

    pcall(function()
        if type(original) == "function" then
            position = original(controller)
        elseif type(controller.GetSubjectPosition) == "function" then
            position = controller:GetSubjectPosition()
        end
    end)

    if typeof(position) == "Vector3" then
        return position
    end
    return nil
end

local function captureStandingHeight()
    if not isGrounded() then
        return false
    end

    local controller = getActiveCameraController()
    local position = nativeSubjectPosition(controller)
    local floorY = groundY()

    if not position or not floorY then
        return false
    end

    standingSubjectAboveGround = position.Y - floorY
    lastGroundY = floorY
    return true
end

local function beginCrouch()
    if crouchActive then
        return
    end

    captureStandingHeight()
    crouchActive = true
    releasePending = false
end

local function endCrouch()
    if not crouchActive and not releasePending then
        return
    end

    crouchActive = false
    -- O evento de soltar pode chegar antes do root terminar de subir. Segura a
    -- referencia por poucos frames e libera assim que o subject alcancar a altura.
    releasePending = standingSubjectAboveGround ~= nil
    releaseDeadline = os.clock() + 0.40
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
        if typeof(position) ~= "Vector3" then
            return position
        end

        if not (crouchActive or releasePending)
            or standingSubjectAboveGround == nil
            or not isGrounded() then
            return position
        end

        local floorY = groundY()
        if not floorY then
            return position
        end

        lastGroundY = floorY
        local targetY = floorY + standingSubjectAboveGround
        local correction = targetY - position.Y

        -- Nunca empurra a camera para baixo; so cancela a queda causada pelo crouch.
        if correction > 0.03 then
            position = position + Vector3.new(0, math.clamp(correction, 0, 2.5), 0)
        elseif releasePending then
            releasePending = false
        end

        if releasePending and os.clock() >= releaseDeadline then
            releasePending = false
        end

        return position
    end
end

local function resetCrouchState()
    crouchActive = false
    releasePending = false
    releaseDeadline = 0
    standingSubjectAboveGround = nil
    lastGroundY = nil
end

table.insert(connections, player.CharacterAdded:Connect(function()
    resetCrouchState()
end))

-- Escuta exatamente a interface do Legacy. Scripts mobile publicos usam
-- PlayerScripts.Events.KeybindUsed:Fire("Crouch", true/false), e o botao nativo
-- passa pela mesma rota.
task.spawn(function()
    local playerScripts = player:WaitForChild("PlayerScripts", 15)
    if not playerScripts then return end

    local events = playerScripts:WaitForChild("Events", 15)
    local keybindUsed = events and events:WaitForChild("KeybindUsed", 15)
    if not keybindUsed then return end

    local signal
    pcall(function()
        signal = keybindUsed.Event
    end)

    if signal and type(signal.Connect) == "function" then
        local connection = signal:Connect(function(key, state)
            if tostring(key) ~= "Crouch" then
                return
            end

            if state == true then
                beginCrouch()
            elseif state == false then
                endCrouch()
            end
        end)
        table.insert(connections, connection)
    end
end)

RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 3, function()
    if getgenv().PCMovementEnabled == false then
        return
    end

    local controller = getActiveCameraController()
    if controller then
        patchSubjectPosition(controller)
    end

    -- Fora do crouch, acompanha lentamente a altura standing real para lidar com
    -- respawn/escala do avatar, mas nunca aprende a postura abaixada.
    if not crouchActive and not releasePending and isGrounded() then
        local verticalSpeed = 0
        pcall(function()
            verticalSpeed = math.abs(root.AssemblyLinearVelocity.Y)
        end)

        if verticalSpeed < 2.5 then
            local position = nativeSubjectPosition(controller)
            local floorY = groundY()
            if position and floorY then
                local relativeY = position.Y - floorY
                if standingSubjectAboveGround == nil then
                    standingSubjectAboveGround = relativeY
                elseif math.abs(relativeY - standingSubjectAboveGround) < 0.35 then
                    standingSubjectAboveGround = standingSubjectAboveGround * 0.90 + relativeY * 0.10
                elseif relativeY > standingSubjectAboveGround then
                    -- Aceita aumento real de altura/escala; queda grande nao vira baseline.
                    standingSubjectAboveGround = standingSubjectAboveGround * 0.95 + relativeY * 0.05
                end
            end
        end
    end
end)

getgenv().__PCMobileAimCleanup = function()
    pcall(function()
        RunService:UnbindFromRenderStep(MOVEMENT_BIND)
        RunService:UnbindFromRenderStep(CAMERA_BIND)
    end)

    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(connections)

    for controller, original in pairs(originalSubjectMethods) do
        pcall(function()
            controller.GetSubjectPosition = original
        end)
    end

    if v9Cleanup then
        pcall(v9Cleanup)
    end

    getgenv().__PCMobileAimCleanup = nil
end
