local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BIND_NAME = "__PCSelectiveWASDMove"
local PRESS_THRESHOLD = 0.30
local RELEASE_THRESHOLD = 0.18
local CONTROLLER_REFRESH_SECONDS = 0.20

local KEYCODES = {
    W = Enum.KeyCode.W,
    A = Enum.KeyCode.A,
    S = Enum.KeyCode.S,
    D = Enum.KeyCode.D,
}

-- Remove every older movement experiment so two bridges cannot fight each other.
for _, cleanupName in ipairs({
    "__PCSelectiveWASDCleanup",
    "__PCClassicNativeKeysV3Cleanup",
    "__PCClassicNativeKeysCleanup",
    "__PCClassicWASDCleanup",
}) do
    local cleanup = getgenv()[cleanupName]
    if type(cleanup) == "function" then
        pcall(cleanup)
    end
end

pcall(function()
    RunService:UnbindFromRenderStep(BIND_NAME)
end)

local controls
local touchController
local originalGetMoveVector
local previousOwnGetMoveVector
local hadOwnGetMoveVector = false
local lastControllerRefresh = 0
local previousTouchGuiEnabled = nil
local enabled = true

local pressed = { W = false, A = false, S = false, D = false }
local axisX = 0
local axisZ = 0
local latestRaw = Vector3.zero
local latestDigital = Vector3.zero
local latestChord = "-"
local latestPreferredInput = "?"
local latestControllerEnabled = nil
local latestMoveTouchActive = false
local keySendErrors = 0
local moveApplyErrors = 0
local controllerReenableCount = 0
local hookInstallCount = 0

local function getControls()
    if type(controls) == "table" then
        return controls
    end

    local scripts = player:FindFirstChild("PlayerScripts")
    local moduleScript = scripts and scripts:FindFirstChild("PlayerModule")
    if not moduleScript then
        return nil
    end

    local okModule, module = pcall(require, moduleScript)
    if not okModule or type(module) ~= "table" then
        return nil
    end

    local okControls, value = pcall(function()
        if type(module.GetControls) == "function" then
            return module:GetControls()
        end
        return rawget(module, "controls")
    end)

    if okControls and type(value) == "table" then
        controls = value
        return controls
    end

    return nil
end

local function resolveTouchController()
    local controlModule = getControls()
    if type(controlModule) ~= "table" then
        return nil
    end

    local candidate = rawget(controlModule, "touchController")
    if type(candidate) == "table" and type(candidate.GetMoveVector) == "function" then
        return candidate
    end

    local active = rawget(controlModule, "activeController")
    if type(active) == "table" and type(active.GetMoveVector) == "function" then
        local moveTouch = rawget(active, "moveTouchObject")
        if moveTouch ~= nil then
            return active
        end
    end

    -- Last-resort direct-field scan. This stays inside Controls; it does not scan
    -- camera objects or hook arbitrary game tables.
    for _, value in pairs(controlModule) do
        if type(value) == "table" and type(value.GetMoveVector) == "function" then
            local name = string.lower(tostring(rawget(value, "name") or rawget(value, "Name") or ""))
            if string.find(name, "touch", 1, true) or rawget(value, "moveTouchObject") ~= nil then
                return value
            end
        end
    end

    return nil
end

local function sendKey(name, down)
    local keyCode = KEYCODES[name]
    if not keyCode then
        return false
    end

    local ok = pcall(function()
        VirtualInputManager:SendKeyEvent(down, keyCode, false, game)
    end)
    if not ok then
        keySendErrors += 1
    end
    return ok
end

local function rebuildChord()
    local parts = {}
    for _, name in ipairs({ "W", "A", "S", "D" }) do
        if pressed[name] then
            parts[#parts + 1] = name
        end
    end
    latestChord = #parts > 0 and table.concat(parts, "+") or "-"
end

local function applyKeys(desired)
    desired = desired or {}

    -- Release only keys that actually left the chord. W -> W+D keeps W held.
    for _, name in ipairs({ "W", "A", "S", "D" }) do
        if pressed[name] and not desired[name] then
            sendKey(name, false)
            pressed[name] = false
        end
    end

    -- Press only newly-entered keys. No repeated key pulses while held.
    for _, name in ipairs({ "W", "A", "S", "D" }) do
        if desired[name] and not pressed[name] then
            if sendKey(name, true) then
                pressed[name] = true
            end
        end
    end

    rebuildChord()
end

local function releaseAllKeys()
    applyKeys({})
end

local function nextAxis(value, state)
    if state == 0 then
        if value >= PRESS_THRESHOLD then
            return 1
        elseif value <= -PRESS_THRESHOLD then
            return -1
        end
        return 0
    elseif state == 1 then
        if value <= -PRESS_THRESHOLD then
            return -1
        elseif value < RELEASE_THRESHOLD then
            return 0
        end
        return 1
    elseif state == -1 then
        if value >= PRESS_THRESHOLD then
            return 1
        elseif value > -RELEASE_THRESHOLD then
            return 0
        end
        return -1
    end

    return 0
end

local function updateIntent(rawVector)
    if typeof(rawVector) ~= "Vector3" then
        rawVector = Vector3.zero
    end

    latestRaw = rawVector
    axisX = nextAxis(rawVector.X, axisX)
    axisZ = nextAxis(rawVector.Z, axisZ)

    local desired = {
        W = axisZ < 0,
        S = axisZ > 0,
        A = axisX < 0,
        D = axisX > 0,
    }
    applyKeys(desired)

    local digital = Vector3.new(axisX, 0, axisZ)
    if digital.Magnitude > 1 then
        digital = digital.Unit
    end
    latestDigital = digital
end

local function restoreHook()
    if type(touchController) == "table" then
        pcall(function()
            if hadOwnGetMoveVector then
                rawset(touchController, "GetMoveVector", previousOwnGetMoveVector)
            else
                rawset(touchController, "GetMoveVector", nil)
            end
        end)
    end

    touchController = nil
    originalGetMoveVector = nil
    previousOwnGetMoveVector = nil
    hadOwnGetMoveVector = false
end

local function installHook(controller)
    if controller == touchController and type(originalGetMoveVector) == "function" then
        return true
    end

    restoreHook()
    if type(controller) ~= "table" then
        return false
    end

    local resolved
    local okResolved = pcall(function()
        resolved = controller.GetMoveVector
    end)
    if not okResolved or type(resolved) ~= "function" then
        return false
    end

    local own = rawget(controller, "GetMoveVector")
    hadOwnGetMoveVector = own ~= nil
    previousOwnGetMoveVector = own
    originalGetMoveVector = resolved
    touchController = controller

    rawset(controller, "GetMoveVector", function(self, ...)
        local rawVector = originalGetMoveVector(self, ...)
        if typeof(rawVector) == "Vector3" then
            latestRaw = rawVector
        end

        if enabled then
            -- The native classic joystick still owns/updates its touch and visuals,
            -- but its analog locomotion contribution is removed here.
            return Vector3.zero
        end
        return rawVector
    end)

    hookInstallCount += 1
    return true
end

local function refreshController(force)
    local now = os.clock()
    if not force and now - lastControllerRefresh < CONTROLLER_REFRESH_SECONDS then
        return
    end
    lastControllerRefresh = now

    local controller = resolveTouchController()
    if type(controller) == "table" and controller ~= touchController then
        installHook(controller)
    end
end

local function keepNativeTouchMovementAlive()
    local touchGui = playerGui:FindFirstChild("TouchGui")
    if touchGui and touchGui:IsA("ScreenGui") then
        if previousTouchGuiEnabled == nil then
            previousTouchGuiEnabled = touchGui.Enabled
        end
        -- Keyboard events may make Roblox prefer KeyboardAndMouse. Keep the native
        -- mobile GUI alive so the fixed thumbstick remains available to the finger.
        if enabled and not touchGui.Enabled then
            touchGui.Enabled = true
        end
    end

    if type(touchController) ~= "table" then
        latestControllerEnabled = nil
        return
    end

    latestControllerEnabled = rawget(touchController, "enabled")
    latestMoveTouchActive = rawget(touchController, "moveTouchObject") ~= nil

    -- If the Controls module disabled only the touch movement controller after a
    -- synthetic keyboard event, re-enable that controller. Its GetMoveVector is
    -- still hooked to zero, so this cannot add a second locomotion source; it only
    -- keeps the native joystick receiving/updating its own touch stream.
    if enabled and latestControllerEnabled == false and type(touchController.Enable) == "function" then
        local ok = pcall(function()
            touchController:Enable(true)
        end)
        if ok then
            controllerReenableCount += 1
            latestControllerEnabled = rawget(touchController, "enabled")
        end
    end
end

local function pollNativeVector()
    if type(touchController) ~= "table" or type(originalGetMoveVector) ~= "function" then
        updateIntent(Vector3.zero)
        return
    end

    local rawVector
    local ok = pcall(function()
        rawVector = originalGetMoveVector(touchController)
    end)
    if not ok or typeof(rawVector) ~= "Vector3" then
        rawVector = latestRaw
    end

    updateIntent(rawVector)
end

refreshController(true)

RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Input.Value + 6, function()
    refreshController(false)
    keepNativeTouchMovementAlive()
    pollNativeVector()

    local okMove = pcall(function()
        -- Locomotion is explicit and therefore does not depend on whichever input
        -- controller PreferredInput selected this frame. Touch camera stays Touch;
        -- key events exist only for keyboard-specific game semantics.
        player:Move(latestDigital, true)
    end)
    if not okMove then
        moveApplyErrors += 1
    end

    pcall(function()
        latestPreferredInput = tostring(UserInputService.PreferredInput):gsub("Enum.PreferredInput%.", "")
    end)
end)

getgenv().PCSelectiveWASD = {
    Version = "1.0-native-touch-selective-keyboard-semantics",
    SetEnabled = function(value)
        enabled = value ~= false
        if not enabled then
            axisX, axisZ = 0, 0
            latestDigital = Vector3.zero
            releaseAllKeys()
            pcall(function()
                player:Move(Vector3.zero, true)
            end)
        else
            refreshController(true)
        end
        return enabled
    end,
    IsEnabled = function()
        return enabled
    end,
    GetState = function()
        return {
            rawVector = latestRaw,
            digitalVector = latestDigital,
            chord = latestChord,
            preferredInput = latestPreferredInput,
            controllerEnabled = latestControllerEnabled,
            moveTouchActive = latestMoveTouchActive,
            hookInstallCount = hookInstallCount,
            controllerReenableCount = controllerReenableCount,
            keySendErrors = keySendErrors,
            moveApplyErrors = moveApplyErrors,
        }
    end,
}

getgenv().__PCSelectiveWASDCleanup = function()
    enabled = false
    axisX, axisZ = 0, 0
    latestDigital = Vector3.zero
    releaseAllKeys()

    pcall(function()
        RunService:UnbindFromRenderStep(BIND_NAME)
    end)
    pcall(function()
        player:Move(Vector3.zero, true)
    end)

    restoreHook()

    local touchGui = playerGui:FindFirstChild("TouchGui")
    if touchGui and touchGui:IsA("ScreenGui") and previousTouchGuiEnabled ~= nil then
        pcall(function()
            touchGui.Enabled = previousTouchGuiEnabled
        end)
    end

    getgenv().PCSelectiveWASD = nil
    getgenv().__PCSelectiveWASDCleanup = nil
end
