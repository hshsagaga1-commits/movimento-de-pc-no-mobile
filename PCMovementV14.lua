local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local V9_URL = "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovement.lua"

local OLD_V9_MOVEMENT_BIND = "__PCMovementDigitalWASD"
local PATCH_BIND = "__PCMovementInputSourceV14"

-- V14: source-level rebuild.
-- Base visual/camera = V9 (o checkpoint que ficou mais proximo do Legacy PC).
-- Diferenca principal: nao chama Player:Move por cima do ControlModule.
-- Em vez disso, altera o vetor do CONTROLADOR MOBILE antes do ControlModule ler,
-- fazendo o pipeline nativo receber exatamente as 8 combinacoes digitais do teclado.
-- Tambem espelha o estado PC do Legacy via PlayerScripts.CamStats.MouseEnabled
-- e antecipa o Crouch no MouseButton1Down/Up do botao mobile real.

local source = game:HttpGet(
    V9_URL .. "?_cb=" .. HttpService:GenerateGUID(false),
    true
)
local chunk, err = loadstring(source)
if not chunk then
    error(err)
end
chunk()

local v9Cleanup = getgenv().__PCMobileAimCleanup

-- Remove SOMENTE a camada de movimento da V9. Camera/offset/emote ficam intactos.
pcall(function()
    RunService:UnbindFromRenderStep(OLD_V9_MOVEMENT_BIND)
    RunService:UnbindFromRenderStep(PATCH_BIND)
end)

getgenv().PCMovementVersion = "V14"
if getgenv().PCMovementEnabled == nil then
    getgenv().PCMovementEnabled = true
end
if getgenv().PCMovementDigitalInput == nil then
    getgenv().PCMovementDigitalInput = true
end
if getgenv().PCInstantCrouch == nil then
    getgenv().PCInstantCrouch = true
end
if getgenv().PCLegacyMouseIdentity == nil then
    getgenv().PCLegacyMouseIdentity = true
end

local connections = {}
local character = player.Character
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
local playerModule
local controls
local patchedControllers = {}
local crouchButtons = setmetatable({}, {__mode = "k"})
local keybindUsed
local camStats
local oldCamStatsMouseEnabled
local camStatsHadMouseEnabled = false
local internalCamStatsWrite = false

local function attachCharacter(newCharacter)
    character = newCharacter
    humanoid = newCharacter:WaitForChild("Humanoid", 10)
end

if player.Character then
    task.spawn(attachCharacter, player.Character)
end

table.insert(connections, player.CharacterAdded:Connect(function(newCharacter)
    task.spawn(attachCharacter, newCharacter)
end))

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

local function getActiveController()
    local controlModule = getControls()
    if type(controlModule) ~= "table" then
        return nil
    end

    local controller
    pcall(function()
        if type(controlModule.GetActiveController) == "function" then
            controller = controlModule:GetActiveController()
        else
            controller = controlModule.activeController
        end
    end)

    return controller
end

local function touchIsPreferred()
    local preferredTouch = false
    local ok = pcall(function()
        preferredTouch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
    end)

    if ok then
        return preferredTouch
    end

    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Keyboard.lua produz componentes exatamente -1 / 0 / +1.
-- A diagonal real do teclado tem magnitude sqrt(2), entao NAO normalizamos para 0.707.
local function quantizeLikeKeyboard(moveVector)
    if typeof(moveVector) ~= "Vector3" then
        return moveVector
    end

    local x = moveVector.X
    local z = moveVector.Z
    local magnitude = math.sqrt(x * x + z * z)

    -- DynamicThumbstick ja aplicou a dead-zone dele antes daqui.
    if magnitude <= 1e-4 then
        return Vector3.zero
    end

    local angle = math.atan2(x, -z)
    local step = math.pi / 4
    local snapped = math.floor((angle / step) + 0.5) * step

    return Vector3.new(
        math.round(math.sin(snapped)),
        0,
        math.round(-math.cos(snapped))
    )
end

local function patchController(controller)
    if not controller or patchedControllers[controller] then
        return
    end

    local original = controller.GetMoveVector
    if type(original) ~= "function" then
        return
    end

    patchedControllers[controller] = original

    controller.GetMoveVector = function(self, ...)
        local moveVector = original(self, ...)

        if getgenv().PCMovementEnabled == false
            or getgenv().PCMovementDigitalInput == false
            or not touchIsPreferred() then
            return moveVector
        end

        return quantizeLikeKeyboard(moveVector)
    end
end

-- Roda ANTES do ControlScriptRenderstep (Input priority).
-- Assim, quando o ControlModule pedir GetMoveVector(), ele ja recebe WASD digital.
RunService:BindToRenderStep(PATCH_BIND, Enum.RenderPriority.Input.Value - 1, function()
    if getgenv().PCMovementEnabled == false then
        return
    end

    local controller = getActiveController()
    if controller then
        patchController(controller)
    end
end)

-- ==================== LEGACY PC IDENTITY ====================
-- O Legacy possui PlayerScripts.CamStats e codigo publico especifico do Legacy
-- usa o atributo MouseEnabled. Mantemos true enquanto V14 estiver ativa.
local function setLegacyMouseIdentity()
    if getgenv().PCLegacyMouseIdentity == false then
        return
    end

    if not camStats or not camStats.Parent then
        local playerScripts = player:FindFirstChild("PlayerScripts")
        camStats = playerScripts and playerScripts:FindFirstChild("CamStats")
    end

    if not camStats then
        return
    end

    if oldCamStatsMouseEnabled == nil and not camStatsHadMouseEnabled then
        local current
        pcall(function()
            current = camStats:GetAttribute("MouseEnabled")
        end)
        camStatsHadMouseEnabled = current ~= nil
        oldCamStatsMouseEnabled = current
    end

    internalCamStatsWrite = true
    pcall(function()
        camStats:SetAttribute("MouseEnabled", true)
    end)
    internalCamStatsWrite = false
end

task.spawn(function()
    local playerScripts = player:WaitForChild("PlayerScripts", 15)
    if not playerScripts then return end

    camStats = playerScripts:FindFirstChild("CamStats") or playerScripts:WaitForChild("CamStats", 10)
    if camStats then
        local current
        pcall(function()
            current = camStats:GetAttribute("MouseEnabled")
        end)
        camStatsHadMouseEnabled = current ~= nil
        oldCamStatsMouseEnabled = current

        setLegacyMouseIdentity()

        local connection = camStats:GetAttributeChangedSignal("MouseEnabled"):Connect(function()
            if internalCamStatsWrite or getgenv().PCMovementEnabled == false then
                return
            end
            if getgenv().PCLegacyMouseIdentity ~= false then
                task.defer(setLegacyMouseIdentity)
            end
        end)
        table.insert(connections, connection)
    end
end)

-- ==================== INSTANT LEGACY CROUCH ====================
local function findKeybindUsed()
    if keybindUsed and keybindUsed.Parent then
        return keybindUsed
    end

    local playerScripts = player:FindFirstChild("PlayerScripts")
    local events = playerScripts and playerScripts:FindFirstChild("Events")
    keybindUsed = events and events:FindFirstChild("KeybindUsed")
    return keybindUsed
end

local function setLocalCrouch(state)
    if not character then return end
    pcall(function()
        character:SetAttribute("Crouching", state == true)
    end)
end

local function fireLegacyCrouch(state)
    if getgenv().PCMovementEnabled == false or getgenv().PCInstantCrouch == false then
        return
    end

    setLocalCrouch(state)

    local event = findKeybindUsed()
    if event then
        pcall(function()
            event:Fire("Crouch", state == true)
        end)
    end
end

local function hookCrouchButton(button)
    if not button or crouchButtons[button] then
        return
    end
    if not button:IsA("GuiButton") then
        return
    end

    crouchButtons[button] = true

    -- MouseButton1Down/Up reproduz a semantica key-down/key-up do teclado.
    table.insert(connections, button.MouseButton1Down:Connect(function()
        fireLegacyCrouch(true)
    end))

    table.insert(connections, button.MouseButton1Up:Connect(function()
        fireLegacyCrouch(false)
    end))
end

local function scanForLegacyCrouchButton()
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return end

    -- Caminho observado no Legacy: HUD.Right.Mobile.Crouch
    local hud = playerGui:FindFirstChild("HUD")
    local right = hud and hud:FindFirstChild("Right")
    local mobile = right and right:FindFirstChild("Mobile")
    local crouch = mobile and mobile:FindFirstChild("Crouch")
    if crouch then
        hookCrouchButton(crouch)
        return
    end

    -- Fallback para pequenas mudancas de hierarquia sem tocar em Overhaul.
    for _, descendant in ipairs(playerGui:GetDescendants()) do
        if descendant.Name == "Crouch" and descendant:IsA("GuiButton") then
            local parentName = descendant.Parent and descendant.Parent.Name or ""
            if parentName == "Mobile" then
                hookCrouchButton(descendant)
            end
        end
    end
end

task.spawn(function()
    local playerScripts = player:WaitForChild("PlayerScripts", 15)
    local events = playerScripts and playerScripts:WaitForChild("Events", 15)
    keybindUsed = events and events:WaitForChild("KeybindUsed", 15)

    if keybindUsed then
        local signal
        pcall(function()
            signal = keybindUsed.Event
        end)

        if signal and type(signal.Connect) == "function" then
            table.insert(connections, signal:Connect(function(key, state)
                if tostring(key) == "Crouch" and type(state) == "boolean" then
                    -- Espelha o estado local no MESMO frame do keybind.
                    setLocalCrouch(state)
                end
            end))
        end
    end
end)

task.spawn(function()
    local playerGui = player:WaitForChild("PlayerGui", 15)
    if not playerGui then return end

    scanForLegacyCrouchButton()
    table.insert(connections, playerGui.DescendantAdded:Connect(function(descendant)
        if descendant.Name == "Crouch" then
            task.defer(scanForLegacyCrouchButton)
        end
    end))
end)

getgenv().__PCMobileAimCleanup = function()
    pcall(function()
        RunService:UnbindFromRenderStep(PATCH_BIND)
    end)

    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(connections)

    for controller, original in pairs(patchedControllers) do
        pcall(function()
            controller.GetMoveVector = original
        end)
    end
    table.clear(patchedControllers)

    if camStats and camStats.Parent then
        internalCamStatsWrite = true
        pcall(function()
            if camStatsHadMouseEnabled then
                camStats:SetAttribute("MouseEnabled", oldCamStatsMouseEnabled)
            else
                camStats:SetAttribute("MouseEnabled", nil)
            end
        end)
        internalCamStatsWrite = false
    end

    -- Garante que nao fique preso agachado se o script for trocado segurando o botao.
    pcall(function()
        local event = findKeybindUsed()
        if event then
            event:Fire("Crouch", false)
        end
    end)

    if v9Cleanup then
        pcall(v9Cleanup)
    end

    getgenv().__PCMobileAimCleanup = nil
end
