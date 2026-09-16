local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local LOCK_BIND = "__PCModeLockV5Watch"
local STATUS_GUI = "PCModeLockV5Status"
local BASE_URL = "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/ClassicJoystickSelectiveWASD.lua"

-- Clean a previous V5 first. The base joystick has its own cleanup too.
local oldLockCleanup = getgenv().__PCModeLockCleanup
if type(oldLockCleanup) == "function" then
    pcall(oldLockCleanup)
end
pcall(function()
    RunService:UnbindFromRenderStep(LOCK_BIND)
end)

-- Keep physical Touch as a SENSOR for our executor bridge, but hide the usual
-- mobile-capability answers from normal Roblox Luau. This does NOT delete Touch
-- from the engine; it prevents the normal Lua control stack from treating it as
-- the preferred control scheme.
local lockEnabled = true
local facadeInstalled = false
local switchLockInstalled = false
local spoofReads = 0
local blockedTouchSwitches = 0
local forcedKeyboardRestores = 0
local keyboardSeedAttempts = 0
local keyboardSeedSucceeded = false
local lastError = "none"

local previousIndex
local previousNamecall
local switchHookTarget
local switchOriginal
local switchOwner
local switchOwnerPrevious
local switchHookMode = "none"

local controls
local playerModule
local touchModule
local touchController
local keyboardModule
local keyboardController

local function cleanText(value, limit)
    local out
    local ok = pcall(function() out = tostring(value) end)
    if not ok then out = "<tostring-error>" end
    out = string.gsub(out or "nil", "[\r\n\t]", " ")
    limit = limit or 120
    if #out > limit then out = string.sub(out, 1, limit) .. "..." end
    return out
end

local function getMeta(tbl)
    local mt
    if type(getrawmetatable) == "function" then
        pcall(function() mt = getrawmetatable(tbl) end)
    end
    if type(mt) ~= "table" then
        pcall(function() mt = getmetatable(tbl) end)
    end
    return type(mt) == "table" and mt or nil
end

local function findMethod(root, name)
    local seen = {}
    local function visit(tbl, depth)
        if type(tbl) ~= "table" or depth > 12 or seen[tbl] then
            return nil
        end
        seen[tbl] = true

        local own
        pcall(function() own = rawget(tbl, name) end)
        if type(own) == "function" then
            return { owner = tbl, fn = own, name = name }
        end

        local index
        pcall(function() index = rawget(tbl, "__index") end)
        local mt = getMeta(tbl)
        local found
        if type(index) == "table" then
            found = visit(index, depth + 1)
            if found then return found end
        end
        if mt then
            found = visit(mt, depth + 1)
            if found then return found end
        end
        return nil
    end
    return visit(root, 0)
end

local function locateControls()
    local scripts = player:FindFirstChild("PlayerScripts")
    local moduleScript = scripts and scripts:FindFirstChild("PlayerModule")
    if not moduleScript then
        return false, "PlayerModule-missing"
    end

    local okModule, module = pcall(require, moduleScript)
    if not okModule or type(module) ~= "table" then
        return false, "PlayerModule-require-failed:" .. cleanText(module)
    end
    playerModule = module

    local okControls, value = pcall(function()
        if type(module.GetControls) == "function" then
            return module:GetControls()
        end
        return rawget(module, "controls")
    end)
    if not okControls or type(value) ~= "table" then
        return false, "controls-unavailable"
    end

    controls = value
    touchModule = rawget(controls, "activeControlModule")
    touchController = rawget(controls, "activeController")
    return true, "ok"
end

local function callerIsExecutor()
    if type(checkcaller) ~= "function" then
        return false
    end
    local ok, result = pcall(checkcaller)
    return ok and result == true
end

local function installInputFacade()
    if type(hookmetamethod) ~= "function"
        or type(checkcaller) ~= "function"
        or type(getnamecallmethod) ~= "function" then
        return false, "metamethod-hooks-unavailable"
    end

    local closure = type(newcclosure) == "function" and newcclosure or function(fn) return fn end

    local indexReplacement
    indexReplacement = closure(function(self, key)
        if lockEnabled and self == UserInputService and not callerIsExecutor() then
            if key == "PreferredInput" then
                spoofReads += 1
                return Enum.PreferredInput.KeyboardAndMouse
            elseif key == "TouchEnabled" then
                spoofReads += 1
                return false
            elseif key == "KeyboardEnabled" then
                spoofReads += 1
                return true
            elseif key == "MouseEnabled" then
                spoofReads += 1
                return true
            elseif key == "GamepadEnabled" then
                spoofReads += 1
                return false
            end
        end
        return previousIndex(self, key)
    end)

    local okIndex, oldIndex = pcall(function()
        return hookmetamethod(game, "__index", indexReplacement)
    end)
    if not okIndex or type(oldIndex) ~= "function" then
        return false, "__index-hook-failed:" .. cleanText(oldIndex)
    end
    previousIndex = oldIndex

    local namecallReplacement
    namecallReplacement = closure(function(self, ...)
        if lockEnabled and self == UserInputService and not callerIsExecutor() then
            local method = getnamecallmethod()
            if method == "GetLastInputType" then
                spoofReads += 1
                return Enum.UserInputType.Keyboard
            elseif method == "GetPlatform" then
                spoofReads += 1
                local windows
                pcall(function() windows = Enum.Platform.Windows end)
                if windows then return windows end
            end
        end
        return previousNamecall(self, ...)
    end)

    local okNamecall, oldNamecall = pcall(function()
        return hookmetamethod(game, "__namecall", namecallReplacement)
    end)
    if not okNamecall or type(oldNamecall) ~= "function" then
        -- Restore __index if the second half cannot be installed.
        pcall(function() hookmetamethod(game, "__index", previousIndex) end)
        previousIndex = nil
        return false, "__namecall-hook-failed:" .. cleanText(oldNamecall)
    end
    previousNamecall = oldNamecall
    facadeInstalled = true
    return true, "installed"
end

local function getUpvalues(fn)
    local getter = (debug and debug.getupvalues) or getupvalues
    if type(getter) ~= "function" then
        return nil
    end
    local ok, values = pcall(getter, fn)
    if ok and type(values) == "table" then
        return values
    end
    return nil
end

local function discoverKeyboardFromUpvalues()
    if type(controls) ~= "table" then return nil end
    local target = findMethod(controls, "SelectComputerMovementModule")
    if not target then return nil end

    local values = getUpvalues(target.fn)
    if not values then return nil end
    for _, value in pairs(values) do
        if type(value) == "table" then
            local candidate
            local ok = pcall(function()
                candidate = value[Enum.UserInputType.Keyboard]
            end)
            if ok and type(candidate) == "table" and candidate ~= touchModule then
                return candidate
            end
        end
    end
    return nil
end

local function seedKeyboardInput()
    keyboardSeedAttempts += 1
    local ok = pcall(function()
        -- Non-movement key: only makes Roblox run its keyboard-input selection path.
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftControl, false, game)
        task.wait(0.035)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
    end)
    if not ok then
        return false
    end

    for _ = 1, 10 do
        task.wait(0.025)
        local activeModule = rawget(controls, "activeControlModule")
        if type(activeModule) == "table" and activeModule ~= touchModule then
            keyboardModule = activeModule
            keyboardController = rawget(controls, "activeController")
            keyboardSeedSucceeded = true
            return true
        end
    end
    return false
end

local function discoverKeyboardModule()
    keyboardModule = discoverKeyboardFromUpvalues()
    if keyboardModule then
        return true, "upvalue-map"
    end

    if seedKeyboardInput() then
        return true, "synthetic-keyboard-selection"
    end

    -- With the facade active, this asks ControlModule to resolve computer input
    -- while it sees KeyboardEnabled=true.
    local target = findMethod(controls, "OnComputerMovementModeChange")
    if target then
        pcall(function() target.fn(controls) end)
        task.wait(0.03)
        local activeModule = rawget(controls, "activeControlModule")
        if type(activeModule) == "table" and activeModule ~= touchModule then
            keyboardModule = activeModule
            keyboardController = rawget(controls, "activeController")
            return true, "computer-mode-change"
        end
    end

    return false, "keyboard-module-not-found"
end

local function installSwitchLock()
    if type(controls) ~= "table" or type(keyboardModule) ~= "table" then
        return false, "missing-controls-or-keyboard-module"
    end

    local target = findMethod(controls, "SwitchToController")
    if not target then
        return false, "SwitchToController-missing"
    end

    switchHookTarget = target.fn
    local replacement

    if type(hookfunction) == "function" then
        local original
        replacement = function(self, module, ...)
            if lockEnabled and self == controls and touchModule ~= nil and module == touchModule then
                blockedTouchSwitches += 1
                if rawget(self, "activeControlModule") ~= keyboardModule then
                    forcedKeyboardRestores += 1
                    return original(self, keyboardModule, ...)
                end
                return nil
            end
            return original(self, module, ...)
        end

        local ok, old = pcall(function()
            return hookfunction(target.fn, replacement)
        end)
        if ok and type(old) == "function" then
            original = old
            switchOriginal = old
            switchHookMode = "hookfunction"
            switchLockInstalled = true
            return true, "hookfunction"
        end
    end

    -- Fallback for executors without hookfunction: replace the method on the
    -- table where it was actually found. Existing dynamic self:method() calls
    -- will still pass through this gate.
    switchOwner = target.owner
    switchOwnerPrevious = rawget(switchOwner, target.name)
    if type(switchOwnerPrevious) ~= "function" then
        return false, "raw-method-replacement-unavailable"
    end
    switchOriginal = switchOwnerPrevious
    replacement = function(self, module, ...)
        if lockEnabled and self == controls and touchModule ~= nil and module == touchModule then
            blockedTouchSwitches += 1
            if rawget(self, "activeControlModule") ~= keyboardModule then
                forcedKeyboardRestores += 1
                return switchOriginal(self, keyboardModule, ...)
            end
            return nil
        end
        return switchOriginal(self, module, ...)
    end
    rawset(switchOwner, target.name, replacement)
    switchHookMode = "rawset"
    switchLockInstalled = true
    return true, "rawset"
end

local function forceKeyboardNow()
    if type(controls) ~= "table" or type(keyboardModule) ~= "table" then
        return false
    end

    local current = rawget(controls, "activeControlModule")
    if current == keyboardModule then
        keyboardController = rawget(controls, "activeController")
        return true
    end

    local target = findMethod(controls, "SwitchToController")
    local fn = switchOriginal or (target and target.fn)
    if type(fn) ~= "function" then
        return false
    end

    local ok = pcall(function()
        fn(controls, keyboardModule)
    end)
    if ok then
        keyboardController = rawget(controls, "activeController")
        forcedKeyboardRestores += 1
    end
    return ok
end

local function keepTouchGuiVisible()
    local touchGui = playerGui:FindFirstChild("TouchGui")
    if touchGui and touchGui:IsA("ScreenGui") and not touchGui.Enabled then
        touchGui.Enabled = true
    end
end

-- Load the latest left-half joystick + direction latch + jump buffer first.
local baseSource = game:HttpGet(BASE_URL .. "?_cb=" .. HttpService:GenerateGUID(false), true)
local baseChunk, baseError = loadstring(baseSource)
if not baseChunk then
    error(baseError)
end
baseChunk()
local baseCleanup = getgenv().__PCIndependentJoystickCleanup

local controlsOk, controlsStatus = locateControls()
if not controlsOk then
    lastError = controlsStatus
else
    local facadeOk, facadeStatus = installInputFacade()
    if not facadeOk then
        lastError = facadeStatus
    end

    local keyboardOk, keyboardStatus = discoverKeyboardModule()
    if not keyboardOk then
        lastError = keyboardStatus
    else
        -- Switch once before installing the gate, then reject future Touch module
        -- selections even when the physical screen keeps producing Touch events.
        if not forceKeyboardNow() then
            lastError = "initial-keyboard-force-failed"
        end
        local switchOk, switchStatus = installSwitchLock()
        if not switchOk then
            lastError = switchStatus
        end
    end
end

local oldStatus = playerGui:FindFirstChild(STATUS_GUI)
if oldStatus then oldStatus:Destroy() end
local statusGui = Instance.new("ScreenGui")
statusGui.Name = STATUS_GUI
statusGui.ResetOnSpawn = false
statusGui.IgnoreGuiInset = true
statusGui.DisplayOrder = 10001
statusGui.Parent = playerGui

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.BackgroundTransparency = 0.35
statusLabel.BackgroundColor3 = Color3.new(0, 0, 0)
statusLabel.TextColor3 = Color3.new(1, 1, 1)
statusLabel.BorderSizePixel = 0
statusLabel.Position = UDim2.fromOffset(8, 7)
statusLabel.Size = UDim2.fromOffset(370, 24)
statusLabel.Font = Enum.Font.Code
statusLabel.TextSize = 12
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Text = " PC LOCK starting..."
statusLabel.Parent = statusGui

RunService:BindToRenderStep(LOCK_BIND, Enum.RenderPriority.Last.Value - 1, function()
    if not lockEnabled then return end

    keepTouchGuiVisible()

    if type(controls) == "table" and type(keyboardModule) == "table" then
        local activeModule = rawget(controls, "activeControlModule")
        -- Only correct a real regression back into the captured Touch module.
        -- nil (menus/textboxes) and unrelated modules are left alone.
        if touchModule ~= nil and activeModule == touchModule then
            forceKeyboardNow()
        end
    end

    local controllerState = "NOCTRL"
    if type(controls) == "table" then
        local active = rawget(controls, "activeControlModule")
        if keyboardModule and active == keyboardModule then
            controllerState = "PC"
        elseif touchModule and active == touchModule then
            controllerState = "TOUCH"
        elseif active == nil then
            controllerState = "NONE"
        else
            controllerState = "OTHER"
        end
    end

    statusLabel.Text = string.format(
        " PC LOCK:%s  CTRL:%s  touch-switch blocked:%d  facade:%s",
        switchLockInstalled and "ON" or "PARTIAL",
        controllerState,
        blockedTouchSwitches,
        facadeInstalled and "ON" or "OFF"
    )
end)

getgenv().PCModeLock = {
    Version = "5.0-input-facade-controlmodule-pc-lock",
    SetEnabled = function(value)
        lockEnabled = value ~= false
        statusGui.Enabled = lockEnabled
        if lockEnabled then
            forceKeyboardNow()
        end
        return lockEnabled
    end,
    IsEnabled = function()
        return lockEnabled
    end,
    GetState = function()
        return {
            facadeInstalled = facadeInstalled,
            switchLockInstalled = switchLockInstalled,
            switchHookMode = switchHookMode,
            touchModuleFound = type(touchModule) == "table",
            keyboardModuleFound = type(keyboardModule) == "table",
            keyboardSeedAttempts = keyboardSeedAttempts,
            keyboardSeedSucceeded = keyboardSeedSucceeded,
            blockedTouchSwitches = blockedTouchSwitches,
            forcedKeyboardRestores = forcedKeyboardRestores,
            spoofReads = spoofReads,
            lastError = lastError,
        }
    end,
}

getgenv().__PCModeLockCleanup = function()
    lockEnabled = false

    pcall(function()
        RunService:UnbindFromRenderStep(LOCK_BIND)
    end)

    if switchLockInstalled then
        if switchHookMode == "hookfunction" and type(hookfunction) == "function"
            and type(switchHookTarget) == "function" and type(switchOriginal) == "function" then
            pcall(function()
                hookfunction(switchHookTarget, switchOriginal)
            end)
        elseif switchHookMode == "rawset" and type(switchOwner) == "table"
            and type(switchOwnerPrevious) == "function" then
            pcall(function()
                rawset(switchOwner, "SwitchToController", switchOwnerPrevious)
            end)
        end
    end

    if facadeInstalled and type(hookmetamethod) == "function" then
        if type(previousNamecall) == "function" then
            pcall(function() hookmetamethod(game, "__namecall", previousNamecall) end)
        end
        if type(previousIndex) == "function" then
            pcall(function() hookmetamethod(game, "__index", previousIndex) end)
        end
    end

    if statusGui then
        pcall(function() statusGui:Destroy() end)
    end

    if type(baseCleanup) == "function" then
        pcall(baseCleanup)
    end

    getgenv().PCModeLock = nil
    getgenv().__PCModeLockCleanup = nil
end
