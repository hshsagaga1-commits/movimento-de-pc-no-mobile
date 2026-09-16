local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BIND_NAME = "__PCIndependentJoystickBridge"
local OVERLAY_GUI_NAME = "PCIndependentJoystickAssist"

-- Hard ownership split: movement bridge can only own touches that BEGIN on
-- the left half of the screen. Right-half touches are never movement touches.
local MOVEMENT_SCREEN_FRACTION = 0.50

-- Keyboard-like movement tuning.
local PRESS_THRESHOLD = 0.30
local RELEASE_THRESHOLD = 0.18
local DIRECTION_LATCH_SECONDS = 0.09

-- Jump assist: explicit taps only. Fast double taps are spaced instead of spammed.
local JUMP_MIN_INTERVAL = 0.11
local JUMP_BUFFER_SECONDS = 0.14
local SPACE_PULSE_SECONDS = 0.055

local KEYCODES = {
    W = Enum.KeyCode.W,
    A = Enum.KeyCode.A,
    S = Enum.KeyCode.S,
    D = Enum.KeyCode.D,
}

-- Older experiments used different control architectures. Never let two run together.
for _, cleanupName in ipairs({
    "__PCIndependentJoystickCleanup",
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

local oldOverlay = playerGui:FindFirstChild(OVERLAY_GUI_NAME)
if oldOverlay then
    oldOverlay:Destroy()
end

local enabled = true
local movementTouch = nil
local movementCenter = nil
local movementRadius = 64
local latestTouchPosition = nil
local latestNormalizedX = 0
local latestNormalizedZ = 0
local joystickFrame = nil
local joystickFrameName = "none"
local joystickFrameRefreshAt = 0

local pressed = { W = false, A = false, S = false, D = false }
local axisX = { state = 0, releaseAt = nil }
local axisZ = { state = 0, releaseAt = nil }
local latestDigital = Vector3.zero
local latestChord = "-"
local latestPreferredInput = "?"

local inputConnections = {}
local jumpConnections = {}
local keySendErrors = 0
local moveApplyErrors = 0
local movementCaptures = 0
local movementUpdates = 0
local rightHalfRejected = 0
local movementCrossHalfReleases = 0
local jumpRequests = 0
local jumpPulses = 0
local bufferedJumpCount = 0

local jumpButton = nil
local jumpOverlay = nil
local lastJumpPulse = -math.huge
local pendingJumpDeadline = nil
local pendingSpaceReleaseToken = 0

local function viewportSize()
    local camera = workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1108, 512)
end

local function isMovementHalf(position)
    if typeof(position) == "Vector3" then
        position = Vector2.new(position.X, position.Y)
    end
    if typeof(position) ~= "Vector2" then
        return false
    end
    local viewport = viewportSize()
    return position.X <= viewport.X * MOVEMENT_SCREEN_FRACTION
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

    -- Release only keys that really left the chord. W -> W+D therefore keeps W held.
    for _, name in ipairs({ "W", "A", "S", "D" }) do
        if pressed[name] and not desired[name] then
            sendKey(name, false)
            pressed[name] = false
        end
    end

    -- Press only newly-entered keys. No key-up/key-down pulses while a direction is held.
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

local function resetAxis(axis)
    axis.state = 0
    axis.releaseAt = nil
end

local function updateAxis(axis, value, now)
    -- Opposite direction wins immediately; no sticky delay when intentionally reversing.
    if value >= PRESS_THRESHOLD then
        axis.state = 1
        axis.releaseAt = nil
        return 1
    elseif value <= -PRESS_THRESHOLD then
        axis.state = -1
        axis.releaseAt = nil
        return -1
    end

    if axis.state == 1 then
        if value >= RELEASE_THRESHOLD then
            axis.releaseAt = nil
            return 1
        end
        if axis.releaseAt == nil then
            axis.releaseAt = now + DIRECTION_LATCH_SECONDS
        end
        if now < axis.releaseAt then
            return 1
        end
        resetAxis(axis)
        return 0
    elseif axis.state == -1 then
        if value <= -RELEASE_THRESHOLD then
            axis.releaseAt = nil
            return -1
        end
        if axis.releaseAt == nil then
            axis.releaseAt = now + DIRECTION_LATCH_SECONDS
        end
        if now < axis.releaseAt then
            return -1
        end
        resetAxis(axis)
        return 0
    end

    return 0
end

local function refreshDigitalIntent(now)
    if movementTouch == nil or not enabled then
        resetAxis(axisX)
        resetAxis(axisZ)
        latestDigital = Vector3.zero
        releaseAllKeys()
        return
    end

    local x = updateAxis(axisX, latestNormalizedX, now)
    local z = updateAxis(axisZ, latestNormalizedZ, now)

    applyKeys({
        W = z < 0,
        S = z > 0,
        A = x < 0,
        D = x > 0,
    })

    local digital = Vector3.new(x, 0, z)
    if digital.Magnitude > 1 then
        digital = digital.Unit
    end
    latestDigital = digital
end

local function getTouchControlFrame()
    local touchGui = playerGui:FindFirstChild("TouchGui")
    if not touchGui then
        return nil
    end
    return touchGui:FindFirstChild("TouchControlFrame", true)
end

local function findNativeJoystickFrame(force)
    local now = os.clock()
    if not force and joystickFrame and joystickFrame.Parent and now < joystickFrameRefreshAt then
        return joystickFrame
    end
    joystickFrameRefreshAt = now + 0.5

    local touchControlFrame = getTouchControlFrame()
    if not touchControlFrame then
        joystickFrame = nil
        joystickFrameName = "none"
        return nil
    end

    local best = nil
    local bestArea = 0
    for _, obj in ipairs(touchControlFrame:GetDescendants()) do
        if obj:IsA("GuiObject") then
            local lower = string.lower(obj.Name)
            if string.find(lower, "thumbstick", 1, true) or string.find(lower, "joystick", 1, true) then
                local size = obj.AbsoluteSize
                local area = size.X * size.Y
                if size.X >= 48 and size.Y >= 48 and area > bestArea then
                    best = obj
                    bestArea = area
                end
            end
        end
    end

    joystickFrame = best
    joystickFrameName = best and best.Name or "fallback-left-bottom"
    return best
end

local function pointInsideExpandedFrame(position, frame, padding)
    if not frame or not frame.Parent then
        return false
    end
    local topLeft = frame.AbsolutePosition - Vector2.new(padding, padding)
    local bottomRight = frame.AbsolutePosition + frame.AbsoluteSize + Vector2.new(padding, padding)
    return position.X >= topLeft.X
        and position.Y >= topLeft.Y
        and position.X <= bottomRight.X
        and position.Y <= bottomRight.Y
end

local function fallbackJoystickHit(position)
    local viewport = viewportSize()
    -- Fallback stays lower-left AND is bounded by the hard 50% split.
    return position.X <= viewport.X * MOVEMENT_SCREEN_FRACTION
        and position.X <= viewport.X * 0.33
        and position.Y >= viewport.Y * 0.48
end

local function acquireMovementGeometry(inputPosition)
    -- Absolute ownership rule: right half can never be claimed as movement,
    -- even if Roblox exposes a giant DynamicThumbstickFrame.
    if not isMovementHalf(inputPosition) then
        rightHalfRejected += 1
        return false
    end

    local frame = findNativeJoystickFrame(true)
    if frame and pointInsideExpandedFrame(inputPosition, frame, 18) then
        local nameLower = string.lower(frame.Name)
        if string.find(nameLower, "dynamic", 1, true) then
            movementCenter = inputPosition
            movementRadius = math.max(52, math.min(frame.AbsoluteSize.X, frame.AbsoluteSize.Y) * 0.24)
        else
            movementCenter = frame.AbsolutePosition + frame.AbsoluteSize / 2
            movementRadius = math.max(46, math.min(frame.AbsoluteSize.X, frame.AbsoluteSize.Y) / 2)
        end
        return true
    end

    if fallbackJoystickHit(inputPosition) then
        local viewport = viewportSize()
        movementCenter = inputPosition
        movementRadius = math.max(52, math.min(viewport.X, viewport.Y) * 0.12)
        return true
    end

    return false
end

local function updateMovementPosition(position)
    if typeof(position) == "Vector3" then
        position = Vector2.new(position.X, position.Y)
    end
    if typeof(position) ~= "Vector2" or not movementCenter then
        return
    end

    latestTouchPosition = position
    local delta = position - movementCenter
    local radius = math.max(1, movementRadius)
    latestNormalizedX = delta.X / radius
    latestNormalizedZ = delta.Y / radius
    movementUpdates += 1
end

local function releaseMovementTouch()
    movementTouch = nil
    movementCenter = nil
    latestTouchPosition = nil
    latestNormalizedX = 0
    latestNormalizedZ = 0
    resetAxis(axisX)
    resetAxis(axisZ)
    latestDigital = Vector3.zero
    releaseAllKeys()
end

local function getHumanoid()
    local character = player.Character
    if not character then
        return nil
    end
    return character:FindFirstChildOfClass("Humanoid")
end

local function pulseJump()
    local now = os.clock()
    lastJumpPulse = now
    pendingJumpDeadline = nil
    jumpPulses += 1

    -- One explicit user tap -> one clean jump request + one PC Space pulse.
    local humanoid = getHumanoid()
    if humanoid then
        pcall(function()
            humanoid.Jump = true
        end)
    end

    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
    end)

    pendingSpaceReleaseToken += 1
    local token = pendingSpaceReleaseToken
    task.delay(SPACE_PULSE_SECONDS, function()
        if token ~= pendingSpaceReleaseToken then
            return
        end
        pcall(function()
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        end)
    end)
end

local function requestJump()
    if not enabled then
        return
    end
    jumpRequests += 1

    local now = os.clock()
    if now - lastJumpPulse >= JUMP_MIN_INTERVAL then
        pulseJump()
        return
    end

    -- Do not spam two jumps into the same tiny mobile timing window. Keep one
    -- pending request and fire it as soon as the clean PC-like interval opens.
    pendingJumpDeadline = now + JUMP_BUFFER_SECONDS
    bufferedJumpCount += 1
end

local function findNativeJumpButton()
    local touchControlFrame = getTouchControlFrame()
    if not touchControlFrame then
        return nil
    end

    local exact = touchControlFrame:FindFirstChild("JumpButton", true)
    if exact and exact:IsA("GuiObject") then
        return exact
    end

    for _, obj in ipairs(touchControlFrame:GetDescendants()) do
        if obj:IsA("GuiObject") and string.find(string.lower(obj.Name), "jump", 1, true) then
            local size = obj.AbsoluteSize
            if size.X >= 40 and size.Y >= 40 then
                return obj
            end
        end
    end
    return nil
end

local overlayGui = Instance.new("ScreenGui")
overlayGui.Name = OVERLAY_GUI_NAME
overlayGui.ResetOnSpawn = false
overlayGui.IgnoreGuiInset = true
overlayGui.DisplayOrder = 10000
overlayGui.Parent = playerGui

local function disconnectJumpOverlay()
    for _, connection in ipairs(jumpConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(jumpConnections)

    if jumpOverlay then
        pcall(function()
            jumpOverlay:Destroy()
        end)
        jumpOverlay = nil
    end
    jumpButton = nil
end

local function installJumpOverlay(button)
    if button == jumpButton and jumpOverlay and jumpOverlay.Parent then
        return
    end

    disconnectJumpOverlay()
    if not button or not button.Parent then
        return
    end

    jumpButton = button
    jumpOverlay = Instance.new("TextButton")
    jumpOverlay.Name = "JumpTimingAssistCapture"
    jumpOverlay.BackgroundTransparency = 1
    jumpOverlay.Text = ""
    jumpOverlay.AutoButtonColor = false
    jumpOverlay.Active = true
    jumpOverlay.ZIndex = 100
    jumpOverlay.Parent = overlayGui

    jumpConnections[#jumpConnections + 1] = jumpOverlay.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            requestJump()
        end
    end)
end

local function syncJumpOverlay()
    local button = findNativeJumpButton()
    if button ~= jumpButton or not jumpOverlay or not jumpOverlay.Parent then
        installJumpOverlay(button)
    end

    if not jumpOverlay or not jumpButton or not jumpButton.Parent then
        return
    end

    jumpOverlay.Visible = enabled and jumpButton.Visible
    jumpOverlay.Position = UDim2.fromOffset(jumpButton.AbsolutePosition.X, jumpButton.AbsolutePosition.Y)
    jumpOverlay.Size = UDim2.fromOffset(jumpButton.AbsoluteSize.X, jumpButton.AbsoluteSize.Y)
end

inputConnections[#inputConnections + 1] = UserInputService.InputBegan:Connect(function(input)
    if not enabled or movementTouch ~= nil then
        return
    end
    if input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    local position = Vector2.new(input.Position.X, input.Position.Y)
    if not isMovementHalf(position) then
        rightHalfRejected += 1
        return
    end

    if acquireMovementGeometry(position) then
        movementTouch = input
        movementCaptures += 1
        updateMovementPosition(input.Position)
        refreshDigitalIntent(os.clock())
    end
end)

inputConnections[#inputConnections + 1] = UserInputService.InputChanged:Connect(function(input)
    if enabled and input == movementTouch then
        local position = Vector2.new(input.Position.X, input.Position.Y)
        if not isMovementHalf(position) then
            movementCrossHalfReleases += 1
            releaseMovementTouch()
            return
        end
        updateMovementPosition(input.Position)
    end
end)

inputConnections[#inputConnections + 1] = UserInputService.InputEnded:Connect(function(input)
    if input == movementTouch then
        releaseMovementTouch()
    end
end)

findNativeJoystickFrame(true)
syncJumpOverlay()

-- PlayerModule is allowed to switch PreferredInput between Touch and Keyboard.
-- It no longer owns the final locomotion value: this write happens at the end of
-- PreRender, after the normal ControlModule render step. Camera Touch is untouched.
RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Last.Value, function()
    local now = os.clock()

    if enabled then
        refreshDigitalIntent(now)

        local okMove = pcall(function()
            player:Move(latestDigital, true)
        end)
        if not okMove then
            moveApplyErrors += 1
        end

        if pendingJumpDeadline then
            if now > pendingJumpDeadline then
                pendingJumpDeadline = nil
            elseif now - lastJumpPulse >= JUMP_MIN_INTERVAL then
                pulseJump()
            end
        end

        syncJumpOverlay()
        findNativeJoystickFrame(false)
    end

    pcall(function()
        latestPreferredInput = tostring(UserInputService.PreferredInput):gsub("Enum.PreferredInput%.", "")
    end)
end)

getgenv().PCIndependentJoystick = {
    Version = "4.1-left-half-gated-final-move-jump-buffer",
    SetEnabled = function(value)
        enabled = value ~= false
        overlayGui.Enabled = enabled
        if not enabled then
            releaseMovementTouch()
            pendingJumpDeadline = nil
            pendingSpaceReleaseToken += 1
            pcall(function()
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
            end)
            pcall(function()
                player:Move(Vector3.zero, true)
            end)
        end
        return enabled
    end,
    IsEnabled = function()
        return enabled
    end,
    GetState = function()
        return {
            chord = latestChord,
            digitalVector = latestDigital,
            normalizedX = latestNormalizedX,
            normalizedZ = latestNormalizedZ,
            movementTouchActive = movementTouch ~= nil,
            joystickFrame = joystickFrameName,
            preferredInput = latestPreferredInput,
            movementScreenFraction = MOVEMENT_SCREEN_FRACTION,
            directionLatchSeconds = DIRECTION_LATCH_SECONDS,
            jumpMinInterval = JUMP_MIN_INTERVAL,
            movementCaptures = movementCaptures,
            movementUpdates = movementUpdates,
            rightHalfRejected = rightHalfRejected,
            movementCrossHalfReleases = movementCrossHalfReleases,
            jumpRequests = jumpRequests,
            jumpPulses = jumpPulses,
            bufferedJumpCount = bufferedJumpCount,
            keySendErrors = keySendErrors,
            moveApplyErrors = moveApplyErrors,
        }
    end,
}

getgenv().__PCIndependentJoystickCleanup = function()
    enabled = false
    releaseMovementTouch()
    pendingJumpDeadline = nil
    pendingSpaceReleaseToken += 1

    pcall(function()
        RunService:UnbindFromRenderStep(BIND_NAME)
    end)
    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
    end)
    pcall(function()
        player:Move(Vector3.zero, true)
    end)

    for _, connection in ipairs(inputConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(inputConnections)

    disconnectJumpOverlay()

    if overlayGui then
        pcall(function()
            overlayGui:Destroy()
        end)
    end

    getgenv().PCIndependentJoystick = nil
    getgenv().__PCIndependentJoystickCleanup = nil
end
