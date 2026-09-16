local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "PCClassicNativeKeys"
local WATCH_BIND = "__PCClassicNativeKeysWatch"

-- Fixed/classic feel: small activation deadzone, then a sticky 8-way keyboard sector.
local BASE_SIZE = 128
local THUMB_SIZE = 52
local ENGAGE_RATIO = 0.22
local RELEASE_RATIO = 0.13
local SECTOR_HYSTERESIS_DEG = 8

local KEYCODES = {
    W = Enum.KeyCode.W,
    A = Enum.KeyCode.A,
    S = Enum.KeyCode.S,
    D = Enum.KeyCode.D,
}

local SECTOR_KEYS = {
    [0] = { W = true },
    [1] = { W = true, D = true },
    [2] = { D = true },
    [3] = { S = true, D = true },
    [4] = { S = true },
    [5] = { S = true, A = true },
    [6] = { A = true },
    [7] = { W = true, A = true },
}

if getgenv().__PCClassicNativeKeysCleanup then
    pcall(getgenv().__PCClassicNativeKeysCleanup)
end

pcall(function()
    RunService:UnbindFromRenderStep(WATCH_BIND)
end)

local enabled = true
local activeTouch = nil
local currentSector = nil
local pressed = { W = false, A = false, S = false, D = false }
local connections = {}
local hiddenNative = {}

local controls
local touchController
local originalTouchGetMoveVector
local previousOwnTouchGetMoveVector
local hadOwnTouchGetMoveVector = false

local function sendKey(keyName, isDown)
    local keyCode = KEYCODES[keyName]
    if not keyCode then
        return false
    end
    local ok = pcall(function()
        VirtualInputManager:SendKeyEvent(isDown, keyCode, false, game)
    end)
    return ok
end

local function applyDesiredKeys(desired)
    desired = desired or {}

    -- Release only keys that actually left the chord. W -> W+D therefore keeps W down.
    for _, keyName in ipairs({ "W", "A", "S", "D" }) do
        if pressed[keyName] and not desired[keyName] then
            sendKey(keyName, false)
            pressed[keyName] = false
        end
    end

    -- Press only newly-entered keys. No key-up/key-down pulse for keys that remain held.
    for _, keyName in ipairs({ "W", "A", "S", "D" }) do
        if desired[keyName] and not pressed[keyName] then
            if sendKey(keyName, true) then
                pressed[keyName] = true
            end
        end
    end
end

local function releaseAllKeys()
    applyDesiredKeys({})
end

local function normalizeAngle(angle)
    local twoPi = math.pi * 2
    angle = angle % twoPi
    if angle < 0 then
        angle += twoPi
    end
    return angle
end

local function angularDistance(a, b)
    local d = math.abs(normalizeAngle(a) - normalizeAngle(b))
    if d > math.pi then
        d = math.pi * 2 - d
    end
    return d
end

local function chooseSector(x, y)
    -- Screen Y is inverted before this function: +y means joystick-up / W.
    local angle = normalizeAngle(math.atan2(x, y))
    local sectorWidth = math.pi / 4
    local normalHalfWidth = sectorWidth / 2
    local hysteresis = math.rad(SECTOR_HYSTERESIS_DEG)

    if currentSector ~= nil then
        local center = currentSector * sectorWidth
        if angularDistance(angle, center) <= normalHalfWidth + hysteresis then
            return currentSector
        end
    end

    return math.floor((angle + normalHalfWidth) / sectorWidth) % 8
end

local function getControls()
    if type(controls) == "table" then
        return controls
    end

    local scripts = player:FindFirstChild("PlayerScripts")
    local moduleScript = scripts and scripts:FindFirstChild("PlayerModule")
    if not moduleScript then
        return nil
    end

    local ok, module = pcall(require, moduleScript)
    if not ok or type(module) ~= "table" then
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

local function restoreTouchControllerHook()
    if type(touchController) == "table" then
        pcall(function()
            if hadOwnTouchGetMoveVector then
                rawset(touchController, "GetMoveVector", previousOwnTouchGetMoveVector)
            else
                rawset(touchController, "GetMoveVector", nil)
            end
        end)
    end

    touchController = nil
    originalTouchGetMoveVector = nil
    previousOwnTouchGetMoveVector = nil
    hadOwnTouchGetMoveVector = false
end

local function hookTouchController(controller)
    if controller == touchController then
        return true
    end

    restoreTouchControllerHook()
    if type(controller) ~= "table" then
        return false
    end

    local resolved
    local ok = pcall(function()
        resolved = controller.GetMoveVector
    end)
    if not ok or type(resolved) ~= "function" then
        return false
    end

    local own = rawget(controller, "GetMoveVector")
    hadOwnTouchGetMoveVector = own ~= nil
    previousOwnTouchGetMoveVector = own
    originalTouchGetMoveVector = resolved
    touchController = controller

    rawset(controller, "GetMoveVector", function(self, ...)
        if enabled then
            return Vector3.zero
        end
        return originalTouchGetMoveVector(self, ...)
    end)

    return true
end

local function refreshTouchController()
    local controlModule = getControls()
    if type(controlModule) ~= "table" then
        return
    end

    -- Prefer the dedicated touch controller so keyboard key events remain untouched.
    local candidate = rawget(controlModule, "touchController")
    if type(candidate) ~= "table" then
        local active = rawget(controlModule, "activeController")
        if type(active) == "table" and rawget(active, "moveTouchObject") ~= nil then
            candidate = active
        end
    end

    if type(candidate) == "table" and candidate ~= touchController then
        hookTouchController(candidate)
    end
end

local function hideNativeThumbstickVisuals()
    local touchGui = playerGui:FindFirstChild("TouchGui")
    if not touchGui then
        return
    end

    for _, obj in ipairs(touchGui:GetDescendants()) do
        if obj:IsA("GuiObject") then
            local lower = string.lower(obj.Name)
            if string.find(lower, "thumbstick", 1, true) or string.find(lower, "joystick", 1, true) then
                if hiddenNative[obj] == nil then
                    hiddenNative[obj] = obj.Visible
                end
                obj.Visible = false
            end
        end
    end
end

local function restoreNativeThumbstickVisuals()
    for obj, wasVisible in pairs(hiddenNative) do
        if obj and obj.Parent then
            pcall(function()
                obj.Visible = wasVisible
            end)
        end
    end
    table.clear(hiddenNative)
end

local oldGui = playerGui:FindFirstChild(GUI_NAME)
if oldGui then
    oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.Parent = playerGui

local base = Instance.new("Frame")
base.Name = "ClassicBase"
base.Active = true
base.AnchorPoint = Vector2.new(0, 1)
base.Size = UDim2.fromOffset(BASE_SIZE, BASE_SIZE)
base.Position = UDim2.new(0, 28, 1, -34)
base.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
base.BackgroundTransparency = 0.42
base.BorderSizePixel = 0
base.Parent = gui

local baseCorner = Instance.new("UICorner")
baseCorner.CornerRadius = UDim.new(1, 0)
baseCorner.Parent = base

local baseStroke = Instance.new("UIStroke")
baseStroke.Thickness = 2
baseStroke.Transparency = 0.62
baseStroke.Color = Color3.fromRGB(225, 225, 225)
baseStroke.Parent = base

local thumb = Instance.new("Frame")
thumb.Name = "ClassicThumb"
thumb.AnchorPoint = Vector2.new(0.5, 0.5)
thumb.Size = UDim2.fromOffset(THUMB_SIZE, THUMB_SIZE)
thumb.Position = UDim2.fromScale(0.5, 0.5)
thumb.BackgroundColor3 = Color3.fromRGB(210, 210, 210)
thumb.BackgroundTransparency = 0.28
thumb.BorderSizePixel = 0
thumb.Parent = base

local thumbCorner = Instance.new("UICorner")
thumbCorner.CornerRadius = UDim.new(1, 0)
thumbCorner.Parent = thumb

local function updateFromScreenPosition(screenPos)
    if typeof(screenPos) == "Vector3" then
        screenPos = Vector2.new(screenPos.X, screenPos.Y)
    end
    if typeof(screenPos) ~= "Vector2" then
        return
    end

    local center = base.AbsolutePosition + base.AbsoluteSize / 2
    local delta = screenPos - center
    local radius = BASE_SIZE / 2
    local magnitude = delta.Magnitude
    local ratio = magnitude / radius

    local clamped = delta
    if magnitude > radius and magnitude > 0 then
        clamped = delta.Unit * radius
    end

    thumb.Position = UDim2.fromOffset(BASE_SIZE / 2 + clamped.X, BASE_SIZE / 2 + clamped.Y)

    if currentSector == nil then
        if ratio < ENGAGE_RATIO then
            applyDesiredKeys({})
            return
        end
    elseif ratio < RELEASE_RATIO then
        currentSector = nil
        applyDesiredKeys({})
        return
    end

    if magnitude <= 0 then
        return
    end

    local x = delta.X / radius
    local y = -delta.Y / radius
    currentSector = chooseSector(x, y)
    applyDesiredKeys(SECTOR_KEYS[currentSector])
end

local function resetJoystick()
    activeTouch = nil
    currentSector = nil
    thumb.Position = UDim2.fromScale(0.5, 0.5)
    releaseAllKeys()
end

connections[#connections + 1] = base.InputBegan:Connect(function(input)
    if not enabled or activeTouch ~= nil then
        return
    end
    if input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    activeTouch = input
    updateFromScreenPosition(input.Position)
end)

connections[#connections + 1] = UserInputService.InputChanged:Connect(function(input)
    if input == activeTouch and enabled then
        updateFromScreenPosition(input.Position)
    end
end)

connections[#connections + 1] = UserInputService.InputEnded:Connect(function(input)
    if input == activeTouch then
        resetJoystick()
    end
end)

RunService:BindToRenderStep(WATCH_BIND, Enum.RenderPriority.Input.Value + 1, function()
    refreshTouchController()
    hideNativeThumbstickVisuals()

    -- Key events can make Roblox consider keyboard the latest input. Keep the mobile
    -- controls container alive so jump/other native touch buttons do not disappear.
    local touchGui = playerGui:FindFirstChild("TouchGui")
    if touchGui and touchGui:IsA("ScreenGui") and enabled then
        touchGui.Enabled = true
    end
end)

getgenv().PCClassicNativeKeys = {
    Version = "2.0-persistent-real-wasd",
    SetEnabled = function(value)
        enabled = value ~= false
        gui.Enabled = enabled
        if not enabled then
            resetJoystick()
            restoreNativeThumbstickVisuals()
        else
            hideNativeThumbstickVisuals()
        end
        return enabled
    end,
    IsEnabled = function()
        return enabled
    end,
    GetPressed = function()
        return {
            W = pressed.W,
            A = pressed.A,
            S = pressed.S,
            D = pressed.D,
            sector = currentSector,
        }
    end,
}

getgenv().__PCClassicNativeKeysCleanup = function()
    enabled = false
    resetJoystick()

    pcall(function()
        RunService:UnbindFromRenderStep(WATCH_BIND)
    end)

    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(connections)

    restoreTouchControllerHook()
    restoreNativeThumbstickVisuals()

    if gui then
        pcall(function()
            gui:Destroy()
        end)
    end

    getgenv().PCClassicNativeKeys = nil
    getgenv().__PCClassicNativeKeysCleanup = nil
end
