--[[
    Evade Legacy PC Buraco - Full Native Lock R1

    Alvo:
      Evade Legacy (PlaceId 96537472072550)

    Ideia:
      Nao "corrigir" a camera depois do frame e nao prender o personagem em um pixel.
      Em vez disso, reconstruir o caminho que o proprio PlayerModule usa no PC:

        1) controller mouse-lock = true
        2) mouseLockOffset = (2, 0.5, 0)
        3) camera movement mode = modo de CAMERA do PC, nao o modo Touch
        4) RotationType = CameraRelative
        5) MouseBehavior = LockCenter
        6) deixar o CameraModule calcular CFrame/Focus normalmente

      O ponto branco 1x1 e apenas a representacao visual do centro/"buraco".
      O offset e aplicado pelo controller nativo antes do CameraModule.Update.
      O personagem acompanha a camera pelo RotationType.CameraRelative, como no PC.

    Compatibilidade:
      - carrega/usa o joystick PC V5.9 conhecido se ele ainda nao estiver ativo;
      - nao escreve HumanoidRootPart.CFrame;
      - nao escreve Camera.CFrame nem Camera.Focus;
      - nao altera WalkSpeed, velocidade, FOV ou zoom;
      - nao reduz a sensibilidade do Touch (sem "PC CAM lento");
      - continua ativo em primeira pessoa;
      - continua ativo em Ragdoll / Physics / FallingDown / PlatformStand;
      - solta somente em morte real ou CameraType.Scriptable.

    UI:
      - ponto branco 1x1 no centro exato;
      - botao BURACO PC movivel pelo dedo, inclusive para fora da tela;
      - toque curto no botao liga/desliga somente a camada de camera;
      - o joystick PC continua independente.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local VERSION = "EvadeLegacy-PCBuraco-FullNativeLock-R1"
local LEGACY_PLACE_ID = 96537472072550
local PRE_BIND = "__EvadeLegacyPCBuracoPre"
local POST_BIND = "__EvadeLegacyPCBuracoPost"
local GUI_NAME = "EvadeLegacyPCBuracoGui"

local CONFIG = ENV.EvadeLegacyPCBuracoConfig
if type(CONFIG) ~= "table" then
    CONFIG = {}
end

local SHOULDER_OFFSET = typeof(CONFIG.Offset) == "Vector3"
    and CONFIG.Offset
    or Vector3.new(2, 0.5, 0)

local AUTO_LOAD_PC_JOYSTICK = CONFIG.AutoLoadPCJoystick ~= false
local FORCE_COMPUTER_CAMERA_MODE = CONFIG.ForceComputerCameraMode ~= false
local FORCE_SHIFT_VALUE = CONFIG.ForceShiftLockValue ~= false
local SHOW_DOT = CONFIG.ShowCenterDot ~= false
local SHOW_BUTTON = CONFIG.ShowButton ~= false

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 5,
        })
    end)
end

-- Remove only previous versions of this exact camera layer.
local previous = ENV.EvadeLegacyPCBuraco
if type(previous) == "table" and type(previous.Cleanup) == "function" then
    pcall(function() previous.Cleanup(false) end)
end

-- Clean earlier Buraco compatibility prototypes if they are still present.
for _, key in ipairs({"LegacyBuracoCompatV1", "LegacyBuracoCompatV2"}) do
    local old = ENV[key]
    if type(old) == "table" and type(old.Cleanup) == "function" then
        pcall(old.Cleanup)
    end
end

-- The old main PCMovement/V500/V614 family owns the same camera lock fields and
-- can force MovementRelative. This build uses the isolated V5.9 joystick instead,
-- so remove a leftover main-camera experiment before installing the native lock.
if type(ENV.__PCMobileAimCleanup) == "function" then
    pcall(ENV.__PCMobileAimCleanup)
end

pcall(function() RunService:UnbindFromRenderStep(PRE_BIND) end)
pcall(function() RunService:UnbindFromRenderStep(POST_BIND) end)

if game.PlaceId ~= LEGACY_PLACE_ID then
    notify("BURACO PC", "Esse arquivo foi feito para o Evade Legacy.", 6)
    return {
        Version = VERSION,
        Installed = false,
        Reason = "wrong-place",
        PlaceId = game.PlaceId,
    }
end

-- The user said this camera will be used together with the PC-like joystick.
-- Reuse V5.9 if already active. Otherwise load the known isolated branch.
local joystickWasAlreadyPresent = type(ENV.PCModeLock) == "table"
local joystickLoadedByThisScript = false
local joystickLoadStatus = "already-present"

local function joystickLooksLikeV59()
    local api = ENV.PCModeLock
    if type(api) ~= "table" then return false end
    local version = tostring(api.Version or "")
    return string.find(version, "5.9", 1, true) ~= nil
end

local function ensurePCJoystick()
    if not AUTO_LOAD_PC_JOYSTICK then
        joystickLoadStatus = "auto-load-disabled"
        return true
    end

    if joystickLooksLikeV59() then
        if type(ENV.PCModeLock.SetEnabled) == "function" then
            pcall(function() ENV.PCModeLock.SetEnabled(true) end)
        end
        joystickLoadStatus = "v5.9-already-active"
        return true
    end

    -- If another PCModeLock revision is active, clean it before V5.9.
    if type(ENV.__PCModeLockCleanup) == "function" then
        pcall(ENV.__PCModeLockCleanup)
    end

    local url =
        "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/"
        .. "classic-wasd-experiment/PCModeLockV5_9.lua?_cb="
        .. HttpService:GenerateGUID(false)

    local ok, err = pcall(function()
        local source = game:HttpGet(url, true)
        local chunk, loadErr = loadstring(source)
        if not chunk then error(loadErr) end
        chunk()
    end)

    if not ok then
        joystickLoadStatus = "load-failed: " .. tostring(err)
        return false
    end

    joystickLoadedByThisScript = true
    joystickLoadStatus = joystickLooksLikeV59() and "v5.9-loaded" or "loaded-version-unconfirmed"
    return true
end

local joystickOk = ensurePCJoystick()
if not joystickOk then
    notify("BURACO PC", "Camera carregou, mas o joystick PC V5.9 falhou. A camera ainda funciona.", 7)
end

local userGameSettings
local oldRotationType
local oldMouseBehavior
pcall(function()
    userGameSettings = UserSettings():GetService("UserGameSettings")
    oldRotationType = userGameSettings.RotationType
end)
pcall(function()
    oldMouseBehavior = UserInputService.MouseBehavior
end)

local playerModule = nil
local cameras = nil
local activeController = nil
local controllerSnapshots = setmetatable({}, {__mode = "k"})
local shiftSnapshots = setmetatable({}, {__mode = "k"})
local lastShiftObject = nil
local lastControllerModeApplied = setmetatable({}, {__mode = "k"})

local enabled = true
local cleaned = false
local activeThisFrame = false
local firstPersonThisFrame = false
local downedThisFrame = false
local lastReason = "starting"
local frames = 0
local activeFrames = 0
local controllerChanges = 0
local computerModeApplications = 0
local preApplications = 0
local postApplications = 0

local function getPlayerModule()
    if type(playerModule) == "table" then return playerModule end

    local scripts = player:FindFirstChild("PlayerScripts")
    local moduleScript = scripts and scripts:FindFirstChild("PlayerModule")
    if not moduleScript then return nil end

    pcall(function()
        local value = require(moduleScript)
        if type(value) == "table" then
            playerModule = value
        end
    end)

    return playerModule
end

local function getCameras()
    if type(cameras) == "table" then return cameras end
    local module = getPlayerModule()
    if type(module) ~= "table" then return nil end

    pcall(function()
        if type(module.GetCameras) == "function" then
            cameras = module:GetCameras()
        end
        if type(cameras) ~= "table" then
            cameras = rawget(module, "cameras")
        end
    end)

    return type(cameras) == "table" and cameras or nil
end

local function getActiveCameraController()
    local module = getCameras()
    if type(module) ~= "table" then return nil end

    local controller
    pcall(function()
        controller = rawget(module, "activeCameraController")
    end)

    if type(controller) ~= "table" and type(module.GetActiveCameraController) == "function" then
        pcall(function()
            controller = module:GetActiveCameraController()
        end)
    end

    return type(controller) == "table" and controller or nil
end

local function snapshotController(controller)
    if type(controller) ~= "table" or controllerSnapshots[controller] then return end

    local snapshot = {}
    pcall(function() snapshot.rawLock = rawget(controller, "inMouseLockedMode") end)
    pcall(function() snapshot.rawOffset = rawget(controller, "mouseLockOffset") end)
    pcall(function() snapshot.rawMode = rawget(controller, "cameraMovementMode") end)
    pcall(function()
        if type(controller.GetIsMouseLocked) == "function" then
            snapshot.lock = controller:GetIsMouseLocked()
        end
    end)
    pcall(function()
        if type(controller.GetMouseLockOffset) == "function" then
            snapshot.offset = controller:GetMouseLockOffset()
        end
    end)
    controllerSnapshots[controller] = snapshot
end

local function restoreController(controller)
    local snapshot = controllerSnapshots[controller]
    if type(controller) ~= "table" or type(snapshot) ~= "table" then return end

    pcall(function()
        local value = snapshot.lock
        if value == nil then value = snapshot.rawLock end
        if value ~= nil then
            if type(controller.SetIsMouseLocked) == "function" then
                controller:SetIsMouseLocked(value)
            else
                rawset(controller, "inMouseLockedMode", value)
            end
        end
    end)

    pcall(function()
        local value = snapshot.offset
        if value == nil then value = snapshot.rawOffset end
        if value ~= nil then
            if type(controller.SetMouseLockOffset) == "function" then
                controller:SetMouseLockOffset(value)
            else
                rawset(controller, "mouseLockOffset", value)
            end
        end
    end)

    pcall(function()
        if snapshot.rawMode ~= nil and type(controller.SetCameraMovementMode) == "function" then
            controller:SetCameraMovementMode(snapshot.rawMode)
        end
    end)

    pcall(function()
        if type(controller.UpdateMouseBehavior) == "function" then
            controller:UpdateMouseBehavior()
        end
    end)
end

local function getShiftLockValueObject()
    local scripts = player:FindFirstChild("PlayerScripts")
    if not scripts then return nil end

    local exact = scripts:FindFirstChild("ShiftLockEnabled")
    if exact and exact:IsA("BoolValue") then
        return exact
    end

    -- Defensive fallback for games that parent it one level lower.
    local found
    pcall(function()
        found = scripts:FindFirstChild("ShiftLockEnabled", true)
    end)
    if found and found:IsA("BoolValue") then
        return found
    end

    return nil
end

local function rememberShiftObject(obj)
    if not obj or shiftSnapshots[obj] ~= nil then return end
    shiftSnapshots[obj] = obj.Value
end

local function forceShiftLockValue()
    if not FORCE_SHIFT_VALUE then return end
    local obj = getShiftLockValueObject()
    if not obj then return end

    if obj ~= lastShiftObject then
        lastShiftObject = obj
        rememberShiftObject(obj)
    end

    if obj.Value ~= true then
        pcall(function() obj.Value = true end)
    end
end

local function restoreShiftObjects()
    for obj, value in pairs(shiftSnapshots) do
        if obj and obj.Parent and type(value) == "boolean" then
            pcall(function() obj.Value = value end)
        end
    end
end

local function forceRotationType(value)
    if not userGameSettings then return end
    pcall(function() userGameSettings.RotationType = value end)
    if type(sethiddenproperty) == "function" then
        pcall(function() sethiddenproperty(userGameSettings, "RotationType", value) end)
    end
end

local function forceMouseBehavior(value)
    pcall(function() UserInputService.MouseBehavior = value end)
    if type(sethiddenproperty) == "function" then
        pcall(function() sethiddenproperty(UserInputService, "MouseBehavior", value) end)
    end
end

local function enumItemByName(enumObject, name)
    if type(name) ~= "string" then return nil end
    local result
    pcall(function()
        for _, item in ipairs(enumObject:GetEnumItems()) do
            if item.Name == name then
                result = item
                break
            end
        end
    end)
    return result
end

-- Reproduce the *computer* camera mode decision without changing physical Touch input.
local function desiredComputerCameraMode()
    if not FORCE_COMPUTER_CAMERA_MODE then return nil end

    local cameraMode
    pcall(function() cameraMode = player.CameraMode end)
    if cameraMode == Enum.CameraMode.LockFirstPerson then
        return enumItemByName(Enum.ComputerCameraMovementMode, "Classic")
    end

    local devMode
    pcall(function() devMode = player.DevComputerCameraMode end)

    if devMode == nil then
        pcall(function() devMode = player.DevComputerCameraMovementMode end)
    end

    local name = devMode and devMode.Name or nil
    if name == "UserChoice" or name == nil then
        local userMode
        if userGameSettings then
            pcall(function() userMode = userGameSettings.ComputerCameraMovementMode end)
        end
        if userMode then return userMode end
        return enumItemByName(Enum.ComputerCameraMovementMode, "Classic")
    end

    return enumItemByName(Enum.ComputerCameraMovementMode, name)
        or enumItemByName(Enum.ComputerCameraMovementMode, "Classic")
end

local function applyComputerCameraMode(controller)
    if type(controller) ~= "table" or type(controller.SetCameraMovementMode) ~= "function" then
        return
    end

    local desired = desiredComputerCameraMode()
    if desired == nil then return end

    -- Physical Touch can make CameraModule select its touch movement mode again.
    -- Read the controller every frame and only write when it actually drifted away
    -- from the computer-camera choice.
    local currentMode
    pcall(function() currentMode = rawget(controller, "cameraMovementMode") end)
    if currentMode == desired then
        lastControllerModeApplied[controller] = desired
        return
    end

    local ok = pcall(function()
        controller:SetCameraMovementMode(desired)
    end)

    if ok then
        lastControllerModeApplied[controller] = desired
        computerModeApplications += 1
    end
end

local function getCharacterState()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil

    if not character then
        return character, humanoid, false, false, "no-character"
    end

    if not humanoid then
        -- Some short respawn transitions have character before Humanoid; do not call it dead.
        return character, humanoid, false, false, "no-humanoid"
    end

    local health = 0
    local state
    local platformStand = false
    pcall(function() health = humanoid.Health end)
    pcall(function() state = humanoid:GetState() end)
    pcall(function() platformStand = humanoid.PlatformStand end)

    local hardDead = health <= 0 or state == Enum.HumanoidStateType.Dead
    local downed = platformStand
        or state == Enum.HumanoidStateType.Physics
        or state == Enum.HumanoidStateType.Ragdoll
        or state == Enum.HumanoidStateType.FallingDown

    return character, humanoid, hardDead, downed, tostring(state)
end

local function isFirstPerson(controller)
    if type(controller) == "table" then
        local result
        local ok = pcall(function()
            if type(controller.InFirstPerson) == "function" then
                result = controller:InFirstPerson()
            elseif type(controller.IsInFirstPerson) == "function" then
                result = controller:IsInFirstPerson()
            else
                result = rawget(controller, "inFirstPerson")
            end
        end)
        if ok and type(result) == "boolean" then
            return result
        end

        local distance
        pcall(function()
            if type(controller.GetCameraToSubjectDistance) == "function" then
                distance = controller:GetCameraToSubjectDistance()
            else
                distance = rawget(controller, "currentSubjectDistance")
            end
        end)
        if type(distance) == "number" and distance < 1.05 then
            return true
        end
    end

    local camera = workspace.CurrentCamera
    local character = player.Character
    local head = character and character:FindFirstChild("Head")
    if camera and head then
        local dist = (camera.CFrame.Position - head.Position).Magnitude
        if dist < 1.3 then return true end
    end

    return false
end

local function setControllerNativeLock(controller, locked)
    if type(controller) ~= "table" then return false end
    snapshotController(controller)

    local okOffset = pcall(function()
        if type(controller.SetMouseLockOffset) == "function" then
            controller:SetMouseLockOffset(locked and SHOULDER_OFFSET or Vector3.zero)
        else
            rawset(controller, "mouseLockOffset", locked and SHOULDER_OFFSET or Vector3.zero)
        end
    end)

    local okLock = pcall(function()
        if type(controller.SetIsMouseLocked) == "function" then
            controller:SetIsMouseLocked(locked)
        else
            rawset(controller, "inMouseLockedMode", locked)
        end
    end)

    if locked then
        -- This is the part V500 intentionally avoided. Here we WANT the native
        -- coupling, because on PC CameraRelative is what makes the character
        -- orientation follow the camera/center while using keyboard movement.
        pcall(function()
            if type(controller.UpdateMouseBehavior) == "function" then
                controller:UpdateMouseBehavior()
            end
        end)
    end

    return okOffset or okLock
end

local function canOwnCameraThisFrame()
    local camera = workspace.CurrentCamera
    if not camera then return false, "no-camera" end

    if camera.CameraType == Enum.CameraType.Scriptable then
        return false, "scriptable-camera"
    end

    local _, _, hardDead, downed = getCharacterState()
    downedThisFrame = downed

    if hardDead then
        return false, "dead"
    end

    local controller = getActiveCameraController()
    if type(controller) ~= "table" then
        return false, "no-active-controller"
    end

    return true, controller
end

local function releaseForDeathOrScriptable(controller)
    if type(controller) == "table" then
        pcall(function()
            if type(controller.SetIsMouseLocked) == "function" then
                controller:SetIsMouseLocked(false)
            else
                rawset(controller, "inMouseLockedMode", false)
            end
        end)
        pcall(function()
            if type(controller.SetMouseLockOffset) == "function" then
                controller:SetMouseLockOffset(Vector3.zero)
            else
                rawset(controller, "mouseLockOffset", Vector3.zero)
            end
        end)
        pcall(function()
            if type(controller.UpdateMouseBehavior) == "function" then
                controller:UpdateMouseBehavior()
            end
        end)
    end
end

local screenGui = nil
local dot = nil
local button = nil
local uiConnections = {}
local drag = {
    active = false,
    input = nil,
    startInput = nil,
    startPosition = nil,
    moved = false,
}

local function updateUI()
    if dot then
        dot.Visible = SHOW_DOT and enabled and activeThisFrame
    end

    if button then
        button.Text = enabled and "BURACO PC: ON" or "BURACO PC: OFF"
    end
end

local function installUI()
    local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 4)
    if not playerGui then return end

    local old = playerGui:FindFirstChild(GUI_NAME)
    if old then old:Destroy() end

    screenGui = Instance.new("ScreenGui")
    screenGui.Name = GUI_NAME
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 2147483000
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = playerGui

    dot = Instance.new("Frame")
    dot.Name = "CenterDot"
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.Position = UDim2.fromScale(0.5, 0.5)
    dot.Size = UDim2.fromOffset(1, 1)
    dot.BorderSizePixel = 0
    dot.BackgroundColor3 = Color3.new(1, 1, 1)
    dot.BackgroundTransparency = 0
    dot.Active = false
    dot.ZIndex = 100
    dot.Visible = false
    dot.Parent = screenGui

    if not SHOW_BUTTON then return end

    button = Instance.new("TextButton")
    button.Name = "Toggle"
    button.AnchorPoint = Vector2.new(0.5, 0.5)
    button.Position = UDim2.new(0.5, 0, 0, 46)
    button.Size = UDim2.fromOffset(124, 30)
    button.BackgroundColor3 = Color3.new(0, 0, 0)
    button.BackgroundTransparency = 0.28
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Font = Enum.Font.GothamBold
    button.TextColor3 = Color3.new(1, 1, 1)
    button.TextSize = 12
    button.Text = "BURACO PC: ON"
    button.ZIndex = 110
    button.Active = true
    button.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button

    local function inputPosition(input)
        local p
        pcall(function() p = input.Position end)
        return p
    end

    uiConnections[#uiConnections + 1] = button.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        drag.active = true
        drag.input = input
        drag.startInput = inputPosition(input)
        drag.startPosition = button.Position
        drag.moved = false
    end)

    uiConnections[#uiConnections + 1] = UserInputService.InputChanged:Connect(function(input)
        if not drag.active or not drag.startInput or not drag.startPosition then return end

        local isSameTouch = drag.input == input
        local isMouseMove = drag.input
            and drag.input.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseMovement

        if not isSameTouch and not isMouseMove then return end

        local p = inputPosition(input)
        if not p then return end

        local delta = p - drag.startInput
        if delta.Magnitude >= 5 then
            drag.moved = true
        end

        button.Position = UDim2.new(
            drag.startPosition.X.Scale,
            drag.startPosition.X.Offset + delta.X,
            drag.startPosition.Y.Scale,
            drag.startPosition.Y.Offset + delta.Y
        )
    end)

    local function endDrag(input)
        if not drag.active then return end

        local sameTouch = drag.input == input
        local sameMouse = drag.input
            and drag.input.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseButton1

        if not sameTouch and not sameMouse then return end

        local wasMoved = drag.moved
        drag.active = false
        drag.input = nil
        drag.startInput = nil
        drag.startPosition = nil
        drag.moved = false

        if not wasMoved then
            enabled = not enabled
            if not enabled then
                activeThisFrame = false
                for controller in pairs(controllerSnapshots) do
                    restoreController(controller)
                end
                restoreShiftObjects()
                if oldRotationType ~= nil then forceRotationType(oldRotationType) end
                if oldMouseBehavior ~= nil then forceMouseBehavior(oldMouseBehavior) end
            end
            updateUI()
        end
    end

    uiConnections[#uiConnections + 1] = button.InputEnded:Connect(endDrag)
end

local function preCameraStep()
    frames += 1
    activeThisFrame = false
    firstPersonThisFrame = false

    if not enabled then
        lastReason = "disabled"
        updateUI()
        return
    end

    local ok, result = canOwnCameraThisFrame()
    if not ok then
        lastReason = result
        if result == "dead" or result == "scriptable-camera" then
            releaseForDeathOrScriptable(activeController)
        end
        updateUI()
        return
    end

    local controller = result
    if controller ~= activeController then
        activeController = controller
        controllerChanges += 1
        snapshotController(controller)
        lastControllerModeApplied[controller] = nil
    end

    applyComputerCameraMode(controller)
    forceShiftLockValue()
    setControllerNativeLock(controller, true)

    -- PC semantics: the *character* uses the camera orientation. This is the
    -- missing coupling in the camera-only V500 approach.
    forceRotationType(Enum.RotationType.CameraRelative)
    forceMouseBehavior(Enum.MouseBehavior.LockCenter)

    firstPersonThisFrame = isFirstPerson(controller)
    activeThisFrame = true
    activeFrames += 1
    preApplications += 1
    lastReason = downedThisFrame and "downed-native-lock"
        or (firstPersonThisFrame and "first-person-native-lock" or "third-person-native-lock")

    updateUI()
end

local function postCameraStep()
    if not enabled or not activeThisFrame then return end

    local controller = getActiveCameraController()
    if type(controller) ~= "table" then return end

    if controller ~= activeController then
        activeController = controller
        controllerChanges += 1
        snapshotController(controller)
        lastControllerModeApplied[controller] = nil
        applyComputerCameraMode(controller)
    end

    -- Evade's custom CameraModule tail writes SetIsMouseLocked(ShiftLockEnabled.Value)
    -- after the controller update. Reassert after that tail so the next frame and
    -- Humanoid rotation state remain PC-like. No CFrame feedback is used.
    forceShiftLockValue()
    setControllerNativeLock(controller, true)
    forceRotationType(Enum.RotationType.CameraRelative)
    forceMouseBehavior(Enum.MouseBehavior.LockCenter)

    postApplications += 1
end

local function cleanup(stopJoystick)
    if cleaned then return end
    cleaned = true
    enabled = false
    activeThisFrame = false

    pcall(function() RunService:UnbindFromRenderStep(PRE_BIND) end)
    pcall(function() RunService:UnbindFromRenderStep(POST_BIND) end)

    for _, connection in ipairs(uiConnections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(uiConnections)

    if screenGui then
        pcall(function() screenGui:Destroy() end)
        screenGui = nil
        dot = nil
        button = nil
    end

    for controller in pairs(controllerSnapshots) do
        restoreController(controller)
    end
    restoreShiftObjects()

    if oldRotationType ~= nil then
        forceRotationType(oldRotationType)
    end
    if oldMouseBehavior ~= nil then
        forceMouseBehavior(oldMouseBehavior)
    end

    if stopJoystick == true and joystickLoadedByThisScript and type(ENV.__PCModeLockCleanup) == "function" then
        pcall(ENV.__PCModeLockCleanup)
    end

    ENV.EvadeLegacyPCBuraco = nil
end

local api = {
    Version = VERSION,
    Installed = true,
    Offset = SHOULDER_OFFSET,
    SetEnabled = function(value)
        enabled = value ~= false
        if not enabled then
            activeThisFrame = false
            for controller in pairs(controllerSnapshots) do
                restoreController(controller)
            end
            restoreShiftObjects()
            if oldRotationType ~= nil then forceRotationType(oldRotationType) end
            if oldMouseBehavior ~= nil then forceMouseBehavior(oldMouseBehavior) end
        end
        updateUI()
        return enabled
    end,
    IsEnabled = function()
        return enabled
    end,
    GetState = function()
        return {
            version = VERSION,
            enabled = enabled,
            activeThisFrame = activeThisFrame,
            firstPerson = firstPersonThisFrame,
            downed = downedThisFrame,
            lastReason = lastReason,
            frames = frames,
            activeFrames = activeFrames,
            controllerChanges = controllerChanges,
            preApplications = preApplications,
            postApplications = postApplications,
            computerModeApplications = computerModeApplications,
            offset = SHOULDER_OFFSET,
            joystickStatus = joystickLoadStatus,
            joystickWasAlreadyPresent = joystickWasAlreadyPresent,
            joystickLoadedByThisScript = joystickLoadedByThisScript,
            writesCameraCFrame = false,
            writesCameraFocus = false,
            writesRootCFrame = false,
            changesTouchSensitivity = false,
            forcesCameraRelative = true,
        }
    end,
    Cleanup = cleanup,
}

ENV.EvadeLegacyPCBuraco = api

installUI()

-- The right-half camera gate in PCModeLock V5.9 runs at Camera-6.
-- Apply native mouse-lock after ownership/input setup but immediately before
-- the normal Roblox/Evade camera update.
RunService:BindToRenderStep(PRE_BIND, Enum.RenderPriority.Camera.Value - 1, preCameraStep)

-- Reassert after CameraModule + Evade custom tail. This does NOT move the camera;
-- it only keeps the lock/rotation semantics from being left in the mobile state.
RunService:BindToRenderStep(POST_BIND, Enum.RenderPriority.Camera.Value + 6, postCameraStep)

notify(
    "BURACO PC",
    "Ativo: joystick PC + mouse-lock nativo + CameraRelative. Sensibilidade Touch intacta.",
    7
)

return api