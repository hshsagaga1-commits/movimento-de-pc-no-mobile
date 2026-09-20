--[[
    Evade Legacy PC Buraco - Native State Owner R2

    Target:
      Evade Legacy (PlaceId 96537472072550)

    Architecture:
      Keep the real Legacy CameraModule / ClassicCamera pipeline intact.
      Physical Touch remains the camera rotation source so the old touch cadence,
      gain, zoom and multitouch behavior stay native.

      This layer owns only the state that the Legacy PC-style mouse-lock path
      already consumes:
        * PlayerScripts.ShiftLockEnabled = true
        * PlayerScripts.MouseLockOffset = Vector3.new(2, 0.5, 0)
        * active BaseCamera mouse-lock = true
        * active BaseCamera mouse-lock offset = Vector3.new(2, 0.5, 0)
        * BaseCamera:UpdateMouseBehavior() performs the native
          CameraRelative / LockCenter coupling.

      V608/V609 already proved that Evade's custom CameraModule tail calls
      SetIsMouseLocked(ShiftLockEnabled.Value) after the active controller update.
      Therefore this script does not fight the tail after every frame. It supplies
      the state the tail reads, then lets the game's own update finish.

    Important:
      * no Camera.CFrame / Camera.Focus writes
      * no HumanoidRootPart / Character CFrame writes
      * no first-person detector or first-person patch
      * no touch -> mouse relay
      * no camera sensitivity/gain rescaling
      * no camera movement-mode forcing
      * no zoom/FOV/currentSubjectDistance changes
      * ragdoll/Physics/FallingDown are not treated as release states
      * PCModeLock V5.9 remains the movement owner

    UI:
      * 1x1 white center marker is visual only
      * BURACO PC + RESYNC buttons share a draggable strip
      * drag the strip/buttons anywhere, including off-screen
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local VERSION = "EvadeLegacy-PCBuraco-NativeState-R2"
local LEGACY_PLACE_ID = 96537472072550
local WATCH_BIND = "__EvadeLegacyPCBuracoNativeStateR2Watch"
local GUI_NAME = "EvadeLegacyPCBuracoNativeStateR2Gui"
local V59_URL =
    "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/"
    .. "classic-wasd-experiment/PCModeLockV5_9.lua"

local CONFIG = ENV.EvadeLegacyPCBuracoConfig
if type(CONFIG) ~= "table" then
    CONFIG = {}
end

local SHOULDER_OFFSET = typeof(CONFIG.Offset) == "Vector3"
    and CONFIG.Offset
    or Vector3.new(2, 0.5, 0)

local AUTO_LOAD_PC_JOYSTICK = CONFIG.AutoLoadPCJoystick ~= false
local SHOW_DOT = CONFIG.ShowCenterDot ~= false
local SHOW_PANEL = CONFIG.ShowButton ~= false
local BEHAVIOR_RETRY_INTERVAL = math.max(0.05, tonumber(CONFIG.BehaviorRetryInterval) or 0.12)

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 5,
        })
    end)
end

local function nearVector3(a, b)
    return typeof(a) == "Vector3"
        and typeof(b) == "Vector3"
        and (a - b).Magnitude <= 0.00001
end

local function safeToString(value)
    local ok, text = pcall(function()
        return tostring(value)
    end)
    return ok and text or "<?>"
end

-- Clean only older Buraco layers. Do not touch the main/V614 investigation family.
local previous = ENV.EvadeLegacyPCBuraco
if type(previous) == "table" and type(previous.Cleanup) == "function" then
    pcall(function()
        previous.Cleanup(false)
    end)
end

for _, key in ipairs({"LegacyBuracoCompatV1", "LegacyBuracoCompatV2"}) do
    local old = ENV[key]
    if type(old) == "table" and type(old.Cleanup) == "function" then
        pcall(old.Cleanup)
    end
end

pcall(function()
    RunService:UnbindFromRenderStep(WATCH_BIND)
end)

if game.PlaceId ~= LEGACY_PLACE_ID then
    notify("BURACO PC", "Esse arquivo foi feito para o Evade Legacy.", 6)
    return {
        Version = VERSION,
        Installed = false,
        Reason = "wrong-place",
        PlaceId = game.PlaceId,
    }
end

-- ---------------------------------------------------------------------------
-- PCModeLock V5.9 integration
-- ---------------------------------------------------------------------------

local joystickLoadedByThisScript = false
local joystickStatus = "not-checked"

local function joystickLooksLikeV59()
    local api = ENV.PCModeLock
    if type(api) ~= "table" then
        return false
    end

    return string.find(safeToString(api.Version), "5.9", 1, true) ~= nil
end

local function ensureJoystickV59()
    if joystickLooksLikeV59() then
        if type(ENV.PCModeLock.SetEnabled) == "function" then
            pcall(function()
                ENV.PCModeLock.SetEnabled(true)
            end)
        end
        joystickStatus = "v5.9-already-active"
        return true
    end

    if type(ENV.PCModeLock) == "table" then
        -- Never tear down an unknown controller stack behind the user's back.
        -- The camera layer can still run, but reports the mismatch.
        joystickStatus = "existing-pcmode-is-not-v5.9"
        return false
    end

    if not AUTO_LOAD_PC_JOYSTICK then
        joystickStatus = "auto-load-disabled"
        return true
    end

    local ok, err = pcall(function()
        local source = game:HttpGet(
            V59_URL .. "?_cb=" .. HttpService:GenerateGUID(false),
            true
        )
        local chunk, loadError = loadstring(source)
        if not chunk then
            error(loadError)
        end
        chunk()
    end)

    if not ok then
        joystickStatus = "v5.9-load-failed:" .. safeToString(err)
        return false
    end

    joystickLoadedByThisScript = true
    joystickStatus = joystickLooksLikeV59()
        and "v5.9-loaded"
        or "loaded-version-unconfirmed"

    return joystickLooksLikeV59()
end

local joystickOk = ensureJoystickV59()
if not joystickOk then
    notify(
        "BURACO PC",
        "Camada de camera ativa; PCModeLock V5.9 nao foi confirmado.",
        7
    )
end

-- ---------------------------------------------------------------------------
-- PlayerModule / Legacy state discovery
-- ---------------------------------------------------------------------------

local playerModule = nil
local cameras = nil
local activeController = nil

local function getPlayerModule()
    if type(playerModule) == "table" then
        return playerModule
    end

    local scripts = player:FindFirstChild("PlayerScripts")
    local moduleScript = scripts and scripts:FindFirstChild("PlayerModule")
    if not moduleScript then
        return nil
    end

    pcall(function()
        local value = require(moduleScript)
        if type(value) == "table" then
            playerModule = value
        end
    end)

    return playerModule
end

local function getCameras()
    if type(cameras) == "table" then
        return cameras
    end

    local module = getPlayerModule()
    if type(module) ~= "table" then
        return nil
    end

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
    if type(module) ~= "table" then
        return nil
    end

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

local function findLegacyStateObjects()
    local scripts = player:FindFirstChild("PlayerScripts")
    if not scripts then
        return nil, nil
    end

    local shift = scripts:FindFirstChild("ShiftLockEnabled")
    if not (shift and shift:IsA("BoolValue")) then
        local found
        pcall(function()
            found = scripts:FindFirstChild("ShiftLockEnabled", true)
        end)
        shift = found and found:IsA("BoolValue") and found or nil
    end

    local offset = scripts:FindFirstChild("MouseLockOffset")
    if not (offset and offset:IsA("Vector3Value")) then
        local found
        pcall(function()
            found = scripts:FindFirstChild("MouseLockOffset", true)
        end)
        offset = found and found:IsA("Vector3Value") and found or nil
    end

    return shift, offset
end

-- ---------------------------------------------------------------------------
-- Snapshots and native state ownership
-- ---------------------------------------------------------------------------

local controllerSnapshots = setmetatable({}, {__mode = "k"})
local shiftSnapshots = setmetatable({}, {__mode = "k"})
local offsetSnapshots = setmetatable({}, {__mode = "k"})

local userGameSettings = nil
local originalRotationType = nil
local originalMouseBehavior = nil

pcall(function()
    userGameSettings = UserSettings():GetService("UserGameSettings")
    originalRotationType = userGameSettings.RotationType
end)
pcall(function()
    originalMouseBehavior = UserInputService.MouseBehavior
end)

local enabled = true
local cleaned = false
local restoring = false
local suspended = false
local suspensionReason = "starting"

local shiftObject = nil
local offsetObject = nil
local shiftConnection = nil
local offsetConnection = nil
local cameraTypeConnection = nil
local currentCameraConnection = nil
local characterConnection = nil
local humanoidConnections = {}

local frames = 0
local reconcileCount = 0
local controllerChanges = 0
local lockWrites = 0
local offsetWrites = 0
local shiftWrites = 0
local stateOffsetWrites = 0
local updateMouseBehaviorCalls = 0
local behaviorFallbackWrites = 0
local lastApplyClock = -math.huge
local lastReason = "starting"
local behaviorMismatch = false
local lastObservedRotationType = nil
local lastObservedMouseBehavior = nil

local requestReconcile
local reconcileNow

local function snapshotController(controller)
    if type(controller) ~= "table" or controllerSnapshots[controller] then
        return
    end

    local snapshot = {}

    pcall(function()
        snapshot.rawLock = rawget(controller, "inMouseLockedMode")
    end)
    pcall(function()
        snapshot.rawOffset = rawget(controller, "mouseLockOffset")
    end)
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

local function readControllerLock(controller)
    if type(controller) ~= "table" then
        return nil
    end

    local value
    pcall(function()
        if type(controller.GetIsMouseLocked) == "function" then
            value = controller:GetIsMouseLocked()
        else
            value = rawget(controller, "inMouseLockedMode")
        end
    end)

    return type(value) == "boolean" and value or nil
end

local function readControllerOffset(controller)
    if type(controller) ~= "table" then
        return nil
    end

    local value
    pcall(function()
        if type(controller.GetMouseLockOffset) == "function" then
            value = controller:GetMouseLockOffset()
        else
            value = rawget(controller, "mouseLockOffset")
        end
    end)

    return typeof(value) == "Vector3" and value or nil
end

local function callUpdateMouseBehavior(controller)
    if type(controller) ~= "table" then
        return false
    end

    local fn
    pcall(function()
        fn = controller.UpdateMouseBehavior
    end)

    if type(fn) ~= "function" then
        return false
    end

    local ok = pcall(function()
        controller:UpdateMouseBehavior()
    end)

    if ok then
        updateMouseBehaviorCalls = updateMouseBehaviorCalls + 1
    end

    return ok
end

local function setControllerLock(controller, value)
    if type(controller) ~= "table" then
        return false
    end

    local current = readControllerLock(controller)
    if current == value then
        return true
    end

    local ok = pcall(function()
        if type(controller.SetIsMouseLocked) == "function" then
            controller:SetIsMouseLocked(value)
        else
            rawset(controller, "inMouseLockedMode", value)
        end
    end)

    if ok then
        lockWrites = lockWrites + 1
    end

    return ok
end

local function setControllerOffset(controller, value)
    if type(controller) ~= "table" or typeof(value) ~= "Vector3" then
        return false
    end

    local current = readControllerOffset(controller)
    if nearVector3(current, value) then
        return true
    end

    local ok = pcall(function()
        if type(controller.SetMouseLockOffset) == "function" then
            controller:SetMouseLockOffset(value)
        else
            rawset(controller, "mouseLockOffset", value)
        end
    end)

    if ok then
        offsetWrites = offsetWrites + 1
    end

    return ok
end

local function restoreController(controller)
    local snapshot = controllerSnapshots[controller]
    if type(controller) ~= "table" or type(snapshot) ~= "table" then
        return
    end

    pcall(function()
        local value = snapshot.offset
        if value == nil then
            value = snapshot.rawOffset
        end

        if typeof(value) == "Vector3" then
            if type(controller.SetMouseLockOffset) == "function" then
                controller:SetMouseLockOffset(value)
            else
                rawset(controller, "mouseLockOffset", value)
            end
        end
    end)

    pcall(function()
        local value = snapshot.lock
        if value == nil then
            value = snapshot.rawLock
        end

        if type(value) == "boolean" then
            if type(controller.SetIsMouseLocked) == "function" then
                controller:SetIsMouseLocked(value)
            else
                rawset(controller, "inMouseLockedMode", value)
            end
        end
    end)

    callUpdateMouseBehavior(controller)
end

local function snapshotShiftObject(object)
    if object and shiftSnapshots[object] == nil then
        shiftSnapshots[object] = object.Value
    end
end

local function snapshotOffsetObject(object)
    if object and offsetSnapshots[object] == nil then
        offsetSnapshots[object] = object.Value
    end
end

local function disconnectHumanoidConnections()
    for _, connection in ipairs(humanoidConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(humanoidConnections)
end

local function hardSuspendReason()
    local camera = Workspace.CurrentCamera
    if not camera then
        return "no-camera"
    end

    if camera.CameraType == Enum.CameraType.Scriptable then
        return "scriptable-camera"
    end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not character or not humanoid then
        return "respawn-transition"
    end

    local health = nil
    local state = nil
    pcall(function()
        health = humanoid.Health
    end)
    pcall(function()
        state = humanoid:GetState()
    end)

    if type(health) == "number" and health <= 0 then
        return "dead"
    end
    if state == Enum.HumanoidStateType.Dead then
        return "dead"
    end

    -- Intentionally NOT releasing on:
    -- Physics / Ragdoll / FallingDown / PlatformStand / Freefall.
    return nil
end

local function directBehaviorFallback()
    -- Known Legacy exposes BaseCamera:UpdateMouseBehavior(), so this path should
    -- almost never run. It only owns PC mouse-lock state; it still never touches
    -- Camera.CFrame, character pose, zoom, FOV or sensitivity.
    local wrote = false

    if userGameSettings then
        local current
        pcall(function()
            current = userGameSettings.RotationType
        end)
        if current ~= Enum.RotationType.CameraRelative then
            local ok = pcall(function()
                userGameSettings.RotationType = Enum.RotationType.CameraRelative
            end)
            wrote = wrote or ok
        end
    end

    local mouseBehavior
    pcall(function()
        mouseBehavior = UserInputService.MouseBehavior
    end)
    if mouseBehavior ~= Enum.MouseBehavior.LockCenter then
        local ok = pcall(function()
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        end)
        wrote = wrote or ok
    end

    if wrote then
        behaviorFallbackWrites = behaviorFallbackWrites + 1
    end
end

local function readBehaviorState()
    local rotationType = nil
    local mouseBehavior = nil

    if userGameSettings then
        pcall(function()
            rotationType = userGameSettings.RotationType
        end)
    end

    pcall(function()
        mouseBehavior = UserInputService.MouseBehavior
    end)

    lastObservedRotationType = rotationType
    lastObservedMouseBehavior = mouseBehavior

    return rotationType, mouseBehavior
end

local function behaviorIsPC()
    local rotationType, mouseBehavior = readBehaviorState()
    return rotationType == Enum.RotationType.CameraRelative
        and mouseBehavior == Enum.MouseBehavior.LockCenter
end

local function applyLegacyStateObjects()
    if shiftObject and shiftObject.Parent then
        snapshotShiftObject(shiftObject)
        if shiftObject.Value ~= true then
            local ok = pcall(function()
                shiftObject.Value = true
            end)
            if ok then
                shiftWrites = shiftWrites + 1
            end
        end
    end

    if offsetObject and offsetObject.Parent then
        snapshotOffsetObject(offsetObject)
        if not nearVector3(offsetObject.Value, SHOULDER_OFFSET) then
            local ok = pcall(function()
                offsetObject.Value = SHOULDER_OFFSET
            end)
            if ok then
                stateOffsetWrites = stateOffsetWrites + 1
            end
        end
    end
end

local function applyControllerState(controller, forceBehavior)
    if type(controller) ~= "table" then
        return false
    end

    snapshotController(controller)

    local offsetOk = setControllerOffset(controller, SHOULDER_OFFSET)
    local lockOk = setControllerLock(controller, true)

    local behaviorOk = true
    if forceBehavior or not behaviorIsPC() then
        behaviorOk = callUpdateMouseBehavior(controller)
        if not behaviorOk then
            directBehaviorFallback()
            behaviorOk = behaviorIsPC()
        else
            behaviorOk = behaviorIsPC()
        end
    end

    behaviorMismatch = not behaviorOk
    return offsetOk and lockOk
end

local function releaseForHardSuspend(reason)
    suspended = true
    suspensionReason = reason or "suspended"
    lastReason = suspensionReason

    if shiftObject and shiftObject.Parent and shiftObject.Value ~= false then
        pcall(function()
            shiftObject.Value = false
        end)
    end

    local controller = getActiveCameraController()
    if type(controller) == "table" then
        snapshotController(controller)
        setControllerLock(controller, false)
        callUpdateMouseBehavior(controller)
    end
end

local function restoreOwnedState()
    restoring = true

    if shiftConnection then
        pcall(function()
            shiftConnection:Disconnect()
        end)
        shiftConnection = nil
    end

    if offsetConnection then
        pcall(function()
            offsetConnection:Disconnect()
        end)
        offsetConnection = nil
    end

    for object, value in pairs(shiftSnapshots) do
        if object and object.Parent and type(value) == "boolean" then
            pcall(function()
                object.Value = value
            end)
        end
    end

    for object, value in pairs(offsetSnapshots) do
        if object and object.Parent and typeof(value) == "Vector3" then
            pcall(function()
                object.Value = value
            end)
        end
    end

    for controller in pairs(controllerSnapshots) do
        restoreController(controller)
    end

    -- Exact teardown fallback. Runtime operation does not continuously write
    -- these globals; only cleanup restores what existed before the layer.
    if userGameSettings and originalRotationType ~= nil then
        pcall(function()
            userGameSettings.RotationType = originalRotationType
        end)
    end

    if originalMouseBehavior ~= nil then
        pcall(function()
            UserInputService.MouseBehavior = originalMouseBehavior
        end)
    end

    restoring = false
end

local reconcileQueued = false
local reconciling = false

local function bindStateObjectSignals()
    local newShift, newOffset = findLegacyStateObjects()

    if newShift ~= shiftObject then
        if shiftConnection then
            pcall(function()
                shiftConnection:Disconnect()
            end)
            shiftConnection = nil
        end

        shiftObject = newShift
        if shiftObject then
            snapshotShiftObject(shiftObject)
            shiftConnection = shiftObject:GetPropertyChangedSignal("Value"):Connect(function()
                if restoring or cleaned or not enabled or suspended then
                    return
                end
                requestReconcile("ShiftLockEnabled-changed")
            end)
        end
    end

    if newOffset ~= offsetObject then
        if offsetConnection then
            pcall(function()
                offsetConnection:Disconnect()
            end)
            offsetConnection = nil
        end

        offsetObject = newOffset
        if offsetObject then
            snapshotOffsetObject(offsetObject)
            offsetConnection = offsetObject:GetPropertyChangedSignal("Value"):Connect(function()
                if restoring or cleaned or not enabled or suspended then
                    return
                end
                requestReconcile("MouseLockOffset-changed")
            end)
        end
    end
end

local function bindHumanoid(character)
    disconnectHumanoidConnections()

    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid and character then
        humanoid = character:WaitForChild("Humanoid", 4)
    end
    if not humanoid then
        return
    end

    humanoidConnections[#humanoidConnections + 1] = humanoid.Died:Connect(function()
        requestReconcile("humanoid-died")
    end)

    humanoidConnections[#humanoidConnections + 1] = humanoid.HealthChanged:Connect(function()
        requestReconcile("humanoid-health")
    end)
end

local function bindCameraTypeSignal()
    if cameraTypeConnection then
        pcall(function()
            cameraTypeConnection:Disconnect()
        end)
        cameraTypeConnection = nil
    end

    local camera = Workspace.CurrentCamera
    if camera then
        cameraTypeConnection = camera:GetPropertyChangedSignal("CameraType"):Connect(function()
            requestReconcile("camera-type-changed")
        end)
    end
end

reconcileNow = function(reason, forceBehavior)
    if cleaned or not enabled or reconciling then
        return false
    end

    reconciling = true
    reconcileCount = reconcileCount + 1
    lastReason = reason or "reconcile"

    bindStateObjectSignals()

    local suspend = hardSuspendReason()
    if suspend then
        releaseForHardSuspend(suspend)
        reconciling = false
        return false
    end

    suspended = false
    suspensionReason = "none"

    applyLegacyStateObjects()

    local controller = getActiveCameraController()
    if controller ~= activeController then
        activeController = controller
        controllerChanges = controllerChanges + 1
        forceBehavior = true
    end

    if type(controller) == "table" then
        applyControllerState(controller, forceBehavior == true)
    end

    lastApplyClock = os.clock()
    lastReason = reason or "active-native-state"
    reconciling = false
    return type(controller) == "table"
end

requestReconcile = function(reason)
    if cleaned or not enabled or restoring or reconcileQueued then
        return
    end

    reconcileQueued = true
    task.defer(function()
        reconcileQueued = false
        if cleaned or not enabled or restoring then
            return
        end
        reconcileNow(reason, false)
    end)
end

local function stateNeedsReconcile(controller)
    if shiftObject and shiftObject.Parent and shiftObject.Value ~= true then
        return true, "shift-drift"
    end

    if offsetObject and offsetObject.Parent
        and not nearVector3(offsetObject.Value, SHOULDER_OFFSET) then
        return true, "offset-value-drift"
    end

    if type(controller) == "table" then
        if readControllerLock(controller) ~= true then
            return true, "controller-lock-drift"
        end

        local currentOffset = readControllerOffset(controller)
        if not nearVector3(currentOffset, SHOULDER_OFFSET) then
            return true, "controller-offset-drift"
        end
    end

    return false, nil
end

local function renderStateWatch()
    frames = frames + 1

    if cleaned or not enabled then
        return
    end

    bindStateObjectSignals()

    local suspend = hardSuspendReason()
    if suspend then
        if not suspended or suspensionReason ~= suspend then
            releaseForHardSuspend(suspend)
        end
        return
    end

    if suspended then
        suspended = false
        suspensionReason = "none"
        reconcileNow("resume-from-" .. safeToString(lastReason), true)
        return
    end

    local controller = getActiveCameraController()
    if controller ~= activeController then
        activeController = controller
        controllerChanges = controllerChanges + 1
        reconcileNow("active-controller-changed", true)
        return
    end

    local needs, why = stateNeedsReconcile(controller)
    if needs then
        reconcileNow(why, false)
        return
    end

    -- CameraRelative / LockCenter are part of BaseCamera's own mouse-lock behavior.
    -- If something external changes them, ask BaseCamera to rebuild its behavior;
    -- do not write camera geometry or character pose.
    local now = os.clock()
    if now - lastApplyClock >= BEHAVIOR_RETRY_INTERVAL and not behaviorIsPC() then
        reconcileNow("mouse-behavior-drift", true)
    end
end

-- ---------------------------------------------------------------------------
-- Event wiring
-- ---------------------------------------------------------------------------

currentCameraConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    bindCameraTypeSignal()
    requestReconcile("current-camera-changed")
end)

characterConnection = player.CharacterAdded:Connect(function(character)
    bindHumanoid(character)
    requestReconcile("character-added")
end)

bindHumanoid(player.Character)
bindCameraTypeSignal()
bindStateObjectSignals()

if userGameSettings then
    pcall(function()
        local connection = userGameSettings:GetPropertyChangedSignal("RotationType"):Connect(function()
            if not restoring and enabled and not suspended then
                requestReconcile("rotation-type-changed")
            end
        end)
        humanoidConnections[#humanoidConnections + 1] = connection
    end)
end

pcall(function()
    local connection = UserInputService:GetPropertyChangedSignal("MouseBehavior"):Connect(function()
        if not restoring and enabled and not suspended then
            requestReconcile("mouse-behavior-changed")
        end
    end)
    humanoidConnections[#humanoidConnections + 1] = connection
end)

-- V5.9's right-half BaseCamera gate watches at Camera-6.
-- R2 observes state at Camera-4: after the gate has refreshed controller identity,
-- before the normal Legacy CameraModule update.
RunService:BindToRenderStep(
    WATCH_BIND,
    Enum.RenderPriority.Camera.Value - 4,
    renderStateWatch
)

-- ---------------------------------------------------------------------------
-- Movable UI
-- ---------------------------------------------------------------------------

local screenGui = nil
local centerDot = nil
local panel = nil
local toggleButton = nil
local resyncButton = nil
local uiConnections = {}

local drag = {
    active = false,
    input = nil,
    startInput = nil,
    startPosition = nil,
    moved = false,
    action = nil,
}

local function panelPositionDefault()
    local saved = ENV.EvadeLegacyPCBuracoPanelPosition
    if typeof(saved) == "UDim2" then
        return saved
    end
    return UDim2.new(0.5, -112, 0, 44)
end

local function updateUI()
    if centerDot then
        centerDot.Visible = SHOW_DOT and enabled and not suspended
    end

    if toggleButton then
        toggleButton.Text = enabled and "BURACO PC: ON" or "BURACO PC: OFF"
    end

    if resyncButton then
        if suspended then
            resyncButton.Text = "PAUSA"
        elseif behaviorMismatch then
            resyncButton.Text = "SYNC !"
        else
            resyncButton.Text = "RESYNC"
        end
    end
end

local function inputPosition(input)
    local position
    pcall(function()
        position = input.Position
    end)
    return position
end

local function setEnabled(value)
    local want = value ~= false
    if want == enabled then
        if want then
            reconcileNow("set-enabled-already-on", true)
        end
        updateUI()
        return enabled
    end

    if not want then
        enabled = false
        suspended = false
        suspensionReason = "disabled"
        lastReason = "disabled"
        restoreOwnedState()
        updateUI()
        return false
    end

    enabled = true
    suspended = false
    suspensionReason = "none"
    lastReason = "enabled"
    bindStateObjectSignals()
    reconcileNow("enabled", true)
    updateUI()
    return true
end

local function resync()
    if not enabled then
        setEnabled(true)
        return
    end

    activeController = nil
    playerModule = nil
    cameras = nil
    reconcileNow("manual-resync", true)
    updateUI()
end

local function installUI()
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
        or player:WaitForChild("PlayerGui", 4)
    if not playerGui then
        return
    end

    local old = playerGui:FindFirstChild(GUI_NAME)
    if old then
        old:Destroy()
    end

    screenGui = Instance.new("ScreenGui")
    screenGui.Name = GUI_NAME
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 2147483000
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = playerGui

    centerDot = Instance.new("Frame")
    centerDot.Name = "CenterDot"
    centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
    centerDot.Position = UDim2.fromScale(0.5, 0.5)
    centerDot.Size = UDim2.fromOffset(1, 1)
    centerDot.BackgroundColor3 = Color3.new(1, 1, 1)
    centerDot.BackgroundTransparency = 0
    centerDot.BorderSizePixel = 0
    centerDot.Active = false
    centerDot.ZIndex = 100
    centerDot.Parent = screenGui

    if not SHOW_PANEL then
        updateUI()
        return
    end

    panel = Instance.new("Frame")
    panel.Name = "MovableControls"
    panel.Position = panelPositionDefault()
    panel.Size = UDim2.fromOffset(224, 32)
    panel.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
    panel.BackgroundTransparency = 0.20
    panel.BorderSizePixel = 0
    panel.Active = true
    panel.ZIndex = 110
    panel.Parent = screenGui

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 8)
    panelCorner.Parent = panel

    toggleButton = Instance.new("TextButton")
    toggleButton.Name = "Toggle"
    toggleButton.Position = UDim2.fromOffset(3, 3)
    toggleButton.Size = UDim2.fromOffset(137, 26)
    toggleButton.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
    toggleButton.BackgroundTransparency = 0.08
    toggleButton.BorderSizePixel = 0
    toggleButton.AutoButtonColor = false
    toggleButton.Font = Enum.Font.GothamBold
    toggleButton.TextColor3 = Color3.new(1, 1, 1)
    toggleButton.TextSize = 11
    toggleButton.Text = "BURACO PC: ON"
    toggleButton.Active = true
    toggleButton.ZIndex = 111
    toggleButton.Parent = panel

    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 6)
    toggleCorner.Parent = toggleButton

    resyncButton = Instance.new("TextButton")
    resyncButton.Name = "Resync"
    resyncButton.Position = UDim2.fromOffset(143, 3)
    resyncButton.Size = UDim2.fromOffset(78, 26)
    resyncButton.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
    resyncButton.BackgroundTransparency = 0.08
    resyncButton.BorderSizePixel = 0
    resyncButton.AutoButtonColor = false
    resyncButton.Font = Enum.Font.GothamBold
    resyncButton.TextColor3 = Color3.new(1, 1, 1)
    resyncButton.TextSize = 10
    resyncButton.Text = "RESYNC"
    resyncButton.Active = true
    resyncButton.ZIndex = 111
    resyncButton.Parent = panel

    local resyncCorner = Instance.new("UICorner")
    resyncCorner.CornerRadius = UDim.new(0, 6)
    resyncCorner.Parent = resyncButton

    local actionByObject = {
        [toggleButton] = "toggle",
        [resyncButton] = "resync",
        [panel] = nil,
    }

    local function beginDrag(object, input)
        if drag.active then
            return
        end

        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        local position = inputPosition(input)
        if not position then
            return
        end

        drag.active = true
        drag.input = input
        drag.startInput = position
        drag.startPosition = panel.Position
        drag.moved = false
        drag.action = actionByObject[object]
    end

    for object in pairs(actionByObject) do
        uiConnections[#uiConnections + 1] = object.InputBegan:Connect(function(input)
            beginDrag(object, input)
        end)
    end

    uiConnections[#uiConnections + 1] = UserInputService.InputChanged:Connect(function(input)
        if not drag.active or not drag.startInput or not drag.startPosition then
            return
        end

        local sameTouch = input == drag.input
        local mouseMove = drag.input
            and drag.input.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseMovement

        if not sameTouch and not mouseMove then
            return
        end

        local position = inputPosition(input)
        if not position then
            return
        end

        local delta = position - drag.startInput
        if delta.Magnitude >= 6 then
            drag.moved = true
        end

        panel.Position = UDim2.new(
            drag.startPosition.X.Scale,
            drag.startPosition.X.Offset + delta.X,
            drag.startPosition.Y.Scale,
            drag.startPosition.Y.Offset + delta.Y
        )
    end)

    uiConnections[#uiConnections + 1] = UserInputService.InputEnded:Connect(function(input)
        if not drag.active then
            return
        end

        local sameTouch = input == drag.input
        local sameMouse = drag.input
            and drag.input.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseButton1

        if not sameTouch and not sameMouse then
            return
        end

        local moved = drag.moved
        local action = drag.action

        drag.active = false
        drag.input = nil
        drag.startInput = nil
        drag.startPosition = nil
        drag.moved = false
        drag.action = nil

        ENV.EvadeLegacyPCBuracoPanelPosition = panel.Position

        if moved then
            return
        end

        if action == "toggle" then
            setEnabled(not enabled)
        elseif action == "resync" then
            resync()
        end
    end)

    updateUI()
end

-- ---------------------------------------------------------------------------
-- Public API / cleanup
-- ---------------------------------------------------------------------------

local function cleanup(stopJoystick)
    if cleaned then
        return
    end

    cleaned = true
    enabled = false

    pcall(function()
        RunService:UnbindFromRenderStep(WATCH_BIND)
    end)

    if currentCameraConnection then
        pcall(function()
            currentCameraConnection:Disconnect()
        end)
        currentCameraConnection = nil
    end

    if characterConnection then
        pcall(function()
            characterConnection:Disconnect()
        end)
        characterConnection = nil
    end

    if cameraTypeConnection then
        pcall(function()
            cameraTypeConnection:Disconnect()
        end)
        cameraTypeConnection = nil
    end

    disconnectHumanoidConnections()
    restoreOwnedState()

    for _, connection in ipairs(uiConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(uiConnections)

    if screenGui then
        pcall(function()
            screenGui:Destroy()
        end)
        screenGui = nil
        centerDot = nil
        panel = nil
        toggleButton = nil
        resyncButton = nil
    end

    if stopJoystick == true
        and joystickLoadedByThisScript
        and type(ENV.__PCModeLockCleanup) == "function" then
        pcall(ENV.__PCModeLockCleanup)
    end

    ENV.EvadeLegacyPCBuraco = nil
end

local api = {
    Version = VERSION,
    Installed = true,
    Offset = SHOULDER_OFFSET,

    SetEnabled = setEnabled,
    IsEnabled = function()
        return enabled
    end,

    Resync = resync,

    GetState = function()
        local controller = getActiveCameraController()
        local rotationType, mouseBehavior = readBehaviorState()

        return {
            version = VERSION,
            enabled = enabled,
            suspended = suspended,
            suspensionReason = suspensionReason,
            lastReason = lastReason,

            frames = frames,
            reconcileCount = reconcileCount,
            controllerChanges = controllerChanges,

            controllerLocked = readControllerLock(controller),
            controllerOffset = readControllerOffset(controller),
            shiftValue = shiftObject and shiftObject.Value or nil,
            stateOffset = offsetObject and offsetObject.Value or nil,
            rotationType = rotationType,
            mouseBehavior = mouseBehavior,

            lockWrites = lockWrites,
            offsetWrites = offsetWrites,
            shiftWrites = shiftWrites,
            stateOffsetWrites = stateOffsetWrites,
            updateMouseBehaviorCalls = updateMouseBehaviorCalls,
            behaviorFallbackWrites = behaviorFallbackWrites,
            behaviorMismatch = behaviorMismatch,

            joystickStatus = joystickStatus,
            joystickLoadedByThisScript = joystickLoadedByThisScript,

            usesNativeTouchRotation = true,
            usesEvadeShiftLockTail = shiftObject ~= nil,
            hasLegacyMouseLockOffsetValue = offsetObject ~= nil,

            firstPersonDetector = false,
            changesCameraMovementMode = false,
            changesTouchSensitivity = false,
            writesCameraCFrame = false,
            writesCameraFocus = false,
            writesCharacterCFrame = false,
            writesRootCFrame = false,
            changesZoom = false,
            changesFOV = false,
        }
    end,

    Cleanup = cleanup,
}

ENV.EvadeLegacyPCBuraco = api

installUI()
reconcileNow("initial-install", true)
updateUI()

notify(
    "BURACO PC R2",
    "Native State ativo: Touch gira; Legacy faz lock/offset/CameraRelative. V5.9 preservado.",
    7
)

return api
