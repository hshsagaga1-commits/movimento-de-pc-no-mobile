local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "PCClassicNativeKeysV3"
local BASE_SIZE = 128
local THUMB_SIZE = 52
local TOUCH_SIZE = 236
local BASE_LEFT = 28
local BASE_BOTTOM = 34
local AXIS_THRESHOLD = 0.30
local RELEASE_RADIUS = 0.12

local KEYCODES = {
    W = Enum.KeyCode.W,
    A = Enum.KeyCode.A,
    S = Enum.KeyCode.S,
    D = Enum.KeyCode.D,
}

-- Kill every older experiment first; V2 kept TouchGui enabled every frame and
-- would directly fight V3's keyboard-only control path if both survived.
for _, cleanupName in ipairs({
    "__PCClassicNativeKeysV3Cleanup",
    "__PCClassicNativeKeysCleanup",
    "__PCClassicWASDCleanup",
}) do
    local cleanup = getgenv()[cleanupName]
    if type(cleanup) == "function" then
        pcall(cleanup)
    end
end

local oldGui = playerGui:FindFirstChild(GUI_NAME)
if oldGui then oldGui:Destroy() end

local enabled = true
local activeTouch = nil
local pressed = { W = false, A = false, S = false, D = false }
local connections = {}
local touchGuiPreviousEnabled = nil
local lastChord = "-"

local function sendKey(name, down)
    local code = KEYCODES[name]
    if not code then return false end
    return pcall(function()
        VirtualInputManager:SendKeyEvent(down, code, false, game)
    end)
end

local function applyKeys(desired)
    desired = desired or {}

    for _, name in ipairs({"W", "A", "S", "D"}) do
        if pressed[name] and not desired[name] then
            sendKey(name, false)
            pressed[name] = false
        end
    end

    for _, name in ipairs({"W", "A", "S", "D"}) do
        if desired[name] and not pressed[name] then
            if sendKey(name, true) then
                pressed[name] = true
            end
        end
    end

    local parts = {}
    for _, name in ipairs({"W", "A", "S", "D"}) do
        if pressed[name] then parts[#parts + 1] = name end
    end
    lastChord = #parts > 0 and table.concat(parts, "+") or "-"
end

local function releaseAll()
    applyKeys({})
end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.Parent = playerGui

local base = Instance.new("Frame")
base.Name = "ClassicBase"
base.AnchorPoint = Vector2.new(0, 1)
base.Size = UDim2.fromOffset(BASE_SIZE, BASE_SIZE)
base.Position = UDim2.new(0, BASE_LEFT, 1, -BASE_BOTTOM)
base.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
base.BackgroundTransparency = 0.42
base.BorderSizePixel = 0
base.ZIndex = 10
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
thumb.ZIndex = 11
thumb.Parent = base

local thumbCorner = Instance.new("UICorner")
thumbCorner.CornerRadius = UDim.new(1, 0)
thumbCorner.Parent = thumb

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0, 1)
status.Size = UDim2.fromOffset(220, 22)
status.Position = UDim2.new(0, BASE_LEFT, 1, -(BASE_BOTTOM + BASE_SIZE + 6))
status.BackgroundTransparency = 1
status.TextColor3 = Color3.new(1, 1, 1)
status.TextTransparency = 0.20
status.TextXAlignment = Enum.TextXAlignment.Left
status.Font = Enum.Font.GothamMedium
status.TextSize = 12
status.ZIndex = 30
status.Text = "KEYS -"
status.Parent = gui

local touchArea = Instance.new("TextButton")
touchArea.Name = "TouchSenseLayer"
touchArea.AnchorPoint = Vector2.new(0.5, 0.5)
touchArea.Size = UDim2.fromOffset(TOUCH_SIZE, TOUCH_SIZE)
touchArea.Position = UDim2.new(
    0,
    BASE_LEFT + BASE_SIZE / 2,
    1,
    -(BASE_BOTTOM + BASE_SIZE / 2)
)
touchArea.BackgroundTransparency = 1
touchArea.Text = ""
touchArea.AutoButtonColor = false
touchArea.Active = true
touchArea.ZIndex = 20
touchArea.Parent = gui

local jump = Instance.new("TextButton")
jump.Name = "PCJump"
jump.AnchorPoint = Vector2.new(1, 1)
jump.Size = UDim2.fromOffset(76, 76)
jump.Position = UDim2.new(1, -32, 1, -38)
jump.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
jump.BackgroundTransparency = 0.42
jump.BorderSizePixel = 0
jump.Text = "↑"
jump.TextColor3 = Color3.fromRGB(225, 225, 225)
jump.Font = Enum.Font.GothamBold
jump.TextSize = 34
jump.ZIndex = 20
jump.Parent = gui
local jumpCorner = Instance.new("UICorner")
jumpCorner.CornerRadius = UDim.new(1, 0)
jumpCorner.Parent = jump

local function getCenter()
    return base.AbsolutePosition + base.AbsoluteSize / 2
end

local function updateMovement(screenPosition)
    if typeof(screenPosition) == "Vector3" then
        screenPosition = Vector2.new(screenPosition.X, screenPosition.Y)
    end
    if typeof(screenPosition) ~= "Vector2" then return end

    local center = getCenter()
    local delta = screenPosition - center
    local radius = BASE_SIZE / 2
    local magnitude = delta.Magnitude

    local clamped = delta
    if magnitude > radius and magnitude > 0 then
        clamped = delta.Unit * radius
    end
    thumb.Position = UDim2.fromOffset(BASE_SIZE / 2 + clamped.X, BASE_SIZE / 2 + clamped.Y)

    local nx = delta.X / radius
    local ny = delta.Y / radius

    if math.sqrt(nx * nx + ny * ny) < RELEASE_RADIUS then
        applyKeys({})
        return
    end

    -- Match the known-working PC-controller script: horizontal and vertical
    -- thresholds are independent, not an angle-sector quantizer.
    applyKeys({
        W = ny < -AXIS_THRESHOLD,
        S = ny > AXIS_THRESHOLD,
        A = nx < -AXIS_THRESHOLD,
        D = nx > AXIS_THRESHOLD,
    })
end

local function resetStick()
    activeTouch = nil
    thumb.Position = UDim2.fromScale(0.5, 0.5)
    releaseAll()
end

connections[#connections + 1] = touchArea.InputBegan:Connect(function(input)
    if not enabled or activeTouch ~= nil then return end
    if input.UserInputType ~= Enum.UserInputType.Touch then return end
    activeTouch = input
    updateMovement(input.Position)
end)

connections[#connections + 1] = touchArea.InputChanged:Connect(function(input)
    if enabled and input == activeTouch then
        updateMovement(input.Position)
    end
end)

connections[#connections + 1] = touchArea.InputEnded:Connect(function(input)
    if input == activeTouch then resetStick() end
end)

connections[#connections + 1] = UserInputService.InputEnded:Connect(function(input)
    if input == activeTouch then resetStick() end
end)

local jumpTouch = nil
connections[#connections + 1] = jump.InputBegan:Connect(function(input)
    if not enabled or jumpTouch ~= nil then return end
    if input.UserInputType ~= Enum.UserInputType.Touch then return end
    jumpTouch = input
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
    end)
end)
connections[#connections + 1] = jump.InputEnded:Connect(function(input)
    if input ~= jumpTouch then return end
    jumpTouch = nil
    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
    end)
end)

-- Key architectural difference from V2: mirror the known-working reference and
-- keep Roblox's native TouchGui disabled instead of keeping the touch movement
-- controller alive while keyboard events are being held.
connections[#connections + 1] = RunService.Stepped:Connect(function()
    local touchGui = playerGui:FindFirstChild("TouchGui")
    if touchGui and touchGui:IsA("ScreenGui") then
        if touchGuiPreviousEnabled == nil then
            touchGuiPreviousEnabled = touchGui.Enabled
        end
        if enabled then
            touchGui.Enabled = false
        end
    end

    local preferred = "?"
    pcall(function()
        preferred = tostring(UserInputService.PreferredInput):gsub("Enum.PreferredInput%.", "")
    end)
    status.Text = "KEYS " .. lastChord .. "  |  INPUT " .. preferred
end)

getgenv().PCClassicNativeKeysV3 = {
    Version = "3.0-touchgui-off-independent-axes",
    SetEnabled = function(value)
        enabled = value ~= false
        gui.Enabled = enabled
        if not enabled then
            resetStick()
            local touchGui = playerGui:FindFirstChild("TouchGui")
            if touchGui and touchGuiPreviousEnabled ~= nil then
                touchGui.Enabled = touchGuiPreviousEnabled
            end
        end
        return enabled
    end,
    IsEnabled = function() return enabled end,
    GetPressed = function()
        return {
            W = pressed.W,
            A = pressed.A,
            S = pressed.S,
            D = pressed.D,
            chord = lastChord,
        }
    end,
}

getgenv().__PCClassicNativeKeysV3Cleanup = function()
    enabled = false
    resetStick()
    if jumpTouch ~= nil then
        pcall(function()
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        end)
        jumpTouch = nil
    end
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(connections)

    local touchGui = playerGui:FindFirstChild("TouchGui")
    if touchGui and touchGuiPreviousEnabled ~= nil then
        pcall(function() touchGui.Enabled = touchGuiPreviousEnabled end)
    end

    if gui then pcall(function() gui:Destroy() end) end
    getgenv().PCClassicNativeKeysV3 = nil
    getgenv().__PCClassicNativeKeysV3Cleanup = nil
end
