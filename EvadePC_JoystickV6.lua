-- Evade PC Joystick V6
-- Mobile-looking shell, digital PC-style core.
-- The finger position only selects one of six digital chords:
-- W, W+A, W+D, S, A, D. Analog magnitude never controls movement speed.
--
-- Overhaul:
--   Keeps the already-working keyboard-event route unchanged.
--
-- Legacy:
--   Uses the exact same keyboard events PLUS a Legacy-only digital Player:Move
--   compatibility route so fixing Legacy cannot alter Overhaul movement.
--
-- Upper sweep:
--   W+D <-> W+A swaps dry while the same touch stays in the upper arc.
--   It does not emit an intermediate W frame. Recenter/release clears the latch.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local VirtualInputManager=game:GetService("VirtualInputManager")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local ENV=(type(getgenv)=="function" and getgenv()) or _G

local VERSION="EvadePC-Joystick-V6-timed-dry-swap-legacy-late-route"
local BIND_NAME="__EvadePCJoystickV6"
local LEGACY_BIND_NAME="__EvadePCJoystickV6LegacyLateMove"
local GUI_NAME="EvadePCJoystickV6Gui"
local EVADE_GAME_ID=3647333358
local LEGACY_PLACE_ID=96537472072550

local THUMBSTICK_SHEET="rbxasset://textures/ui/TouchControlsSheet.png"
local JUMP_SHEET="rbxasset://textures/ui/Input/TouchControlsSheetV2.png"

-- Six digital angular sectors. Requested balance:
--   W       = large
--   W+A/W+D = large (still slightly wider than pure A/D)
--   A/D     = medium-large
--   S       = small
--
-- Angle is measured from W/up:
--   0 deg = W, +90 = D, -90 = A, +/-180 = S.
local PRESS_RADIUS=0.18
local W_HALF_DEG=40       -- W total width: 80 deg
local DIAG_END_DEG=105    -- each WA/WD: 65 deg
local SIDE_END_DEG=160    -- each A/D: 55 deg
                            -- S gets the remaining 40 deg total

-- Dry diagonal swap is only a short transition bridge, never a permanent latch.
-- If the finger stays in W, W takes over after this tiny grace period.
local DRY_SWAP_GRACE_SECONDS=0.085

local JUMP_BURST=0.20

-- Visual-only reach. The knob center reaches almost the ring radius, so the
-- native stick sprite visibly extends outside the outer circle like Roblox.
local KNOB_VISUAL_RADIUS_FACTOR=0.96

local IS_EVADE=(game.GameId==EVADE_GAME_ID)
local IS_LEGACY=(IS_EVADE and game.PlaceId==LEGACY_PLACE_ID)

for _,name in ipairs({
    "__EvadePCJoystickV6Cleanup",
    "__EvadePCJoystickV5Cleanup",
    "__EvadePCJoystickV4Cleanup",
    "__EvadePCJoystickV3Cleanup",
    "__EvadePCJoystickV2Cleanup",
}) do
    local cleanup=ENV[name]
    if type(cleanup)=="function" then pcall(cleanup) end
end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

for _,name in ipairs({"EvadePCJoystickV6Gui","EvadePCJoystickV5Gui","EvadePCJoystickV4Gui","EvadePCJoystickV3Gui"}) do
    local oldGui=playerGui:FindFirstChild(name)
    if oldGui then oldGui:Destroy() end
end

local enabled=true
local movementTouch=nil
local movementCenter=nil
local movementRadius=1
local latest=Vector2.zero

local pressed={W=false,A=false,S=false,D=false}
local chord="-"
local bridgeSide=nil -- "A" or "D", only during a short diagonal crossing
local bridgeDeadline=-math.huge

local connections={}
local cameraViewportConnection=nil
local jumpToken=0

local keyEvents=0
local movementCaptures=0
local movementUpdates=0
local jumpRequests=0
local legacyMoveWrites=0
local dryDiagonalSwaps=0
local lastRawChord="-"

local KEYS={
    W=Enum.KeyCode.W,
    A=Enum.KeyCode.A,
    S=Enum.KeyCode.S,
    D=Enum.KeyCode.D,
}

local function chordName(desired)
    if type(desired)~="table" then return "-" end
    if desired.W and desired.A then return "W+A" end
    if desired.W and desired.D then return "W+D" end
    if desired.W then return "W" end
    if desired.S then return "S" end
    if desired.A then return "A" end
    if desired.D then return "D" end
    return "-"
end

local function sendKey(name,down)
    local key=KEYS[name]
    if not key then return false end

    local ok=pcall(function()
        VirtualInputManager:SendKeyEvent(down,key,false,game)
    end)

    if ok then keyEvents+=1 end
    return ok
end

local function rebuildChord()
    if pressed.W and pressed.A then
        chord="W+A"
    elseif pressed.W and pressed.D then
        chord="W+D"
    elseif pressed.W then
        chord="W"
    elseif pressed.S then
        chord="S"
    elseif pressed.A then
        chord="A"
    elseif pressed.D then
        chord="D"
    else
        chord="-"
    end
end

local function applyKeys(desired)
    desired=desired or {}

    -- Release first so W+D -> W+A becomes D-up/A-down in the same render step.
    for _,name in ipairs({"W","A","D","S"}) do
        if pressed[name] and not desired[name] then
            sendKey(name,false)
            pressed[name]=false
        end
    end

    for _,name in ipairs({"W","A","D","S"}) do
        if desired[name] and not pressed[name] then
            if sendKey(name,true) then
                pressed[name]=true
            end
        end
    end

    rebuildChord()
end

local function directionAngleDeg(v)
    -- atan2(x,-y): 0 = W, +90 = D, -90 = A, +/-180 = S.
    return math.deg(math.atan2(v.X,-v.Y))
end

local function rawClassify(v)
    if v.Magnitude<PRESS_RADIUS then
        return {},"-",0
    end

    local angle=directionAngleDeg(v)
    local absAngle=math.abs(angle)

    if absAngle<=W_HALF_DEG then
        return {W=true},"W",angle
    elseif absAngle<=DIAG_END_DEG then
        if angle<0 then
            return {W=true,A=true},"W+A",angle
        else
            return {W=true,D=true},"W+D",angle
        end
    elseif absAngle<=SIDE_END_DEG then
        if angle<0 then
            return {A=true},"A",angle
        else
            return {D=true},"D",angle
        end
    end

    return {S=true},"S",angle
end

local function classifyDigital(v)
    local now=os.clock()

    if v.Magnitude<PRESS_RADIUS then
        bridgeSide=nil
        bridgeDeadline=-math.huge
        lastRawChord="-"
        return {}
    end

    local previousRaw=lastRawChord
    local raw,rawName=rawClassify(v)
    lastRawChord=rawName

    -- Entering a real diagonal always wins immediately.
    if rawName=="W+A" then
        if bridgeSide=="D" and now<=bridgeDeadline then
            dryDiagonalSwaps+=1
        end
        bridgeSide=nil
        bridgeDeadline=-math.huge
        return raw
    elseif rawName=="W+D" then
        if bridgeSide=="A" and now<=bridgeDeadline then
            dryDiagonalSwaps+=1
        end
        bridgeSide=nil
        bridgeDeadline=-math.huge
        return raw
    end

    if rawName=="W" then
        -- Just left a diagonal and entered W: create a VERY short bridge.
        -- If the user is crossing to the opposite diagonal, W never appears.
        -- If they actually stay in W, the bridge expires and W takes over.
        if bridgeSide==nil then
            if previousRaw=="W+A" then
                bridgeSide="A"
                bridgeDeadline=now+DRY_SWAP_GRACE_SECONDS
            elseif previousRaw=="W+D" then
                bridgeSide="D"
                bridgeDeadline=now+DRY_SWAP_GRACE_SECONDS
            end
        end

        if bridgeSide and now<=bridgeDeadline then
            if bridgeSide=="A" then
                return {W=true,A=true}
            else
                return {W=true,D=true}
            end
        end

        bridgeSide=nil
        bridgeDeadline=-math.huge
        return raw
    end

    -- A, D or S means this was not an upper diagonal crossing.
    bridgeSide=nil
    bridgeDeadline=-math.huge
    return raw
end

local function digitalMoveVector(currentChord)
    if currentChord=="W" then
        return Vector3.new(0,0,-1)
    elseif currentChord=="S" then
        return Vector3.new(0,0,1)
    elseif currentChord=="A" then
        return Vector3.new(-1,0,0)
    elseif currentChord=="D" then
        return Vector3.new(1,0,0)
    elseif currentChord=="W+A" then
        return Vector3.new(-1,0,-1).Unit
    elseif currentChord=="W+D" then
        return Vector3.new(1,0,-1).Unit
    end
    return Vector3.zero
end

local gui=Instance.new("ScreenGui")
gui.Name=GUI_NAME
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.DisplayOrder=10020
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=playerGui

local joystick=Instance.new("TextButton")
joystick.Name="PCJoystick"
joystick.Text=""
joystick.AutoButtonColor=false
joystick.Active=true
joystick.BackgroundTransparency=1
joystick.BorderSizePixel=0
joystick.ZIndex=20
joystick.Parent=gui

local outer=Instance.new("ImageLabel")
outer.Name="RobloxThumbstickOuter"
outer.BackgroundTransparency=1
outer.Image=THUMBSTICK_SHEET
outer.ImageRectOffset=Vector2.new(0,0)
outer.ImageRectSize=Vector2.new(220,220)
outer.Size=UDim2.fromScale(1,1)
outer.Active=false
outer.ZIndex=20
outer.Parent=joystick

local knob=Instance.new("Frame")
knob.Name="Knob"
knob.BackgroundTransparency=1
knob.BorderSizePixel=0
knob.AnchorPoint=Vector2.new(0.5,0.5)
knob.ZIndex=21
knob.Parent=joystick

local stick=Instance.new("ImageLabel")
stick.Name="RobloxThumbstickStick"
stick.BackgroundTransparency=1
stick.Image=THUMBSTICK_SHEET
stick.ImageRectOffset=Vector2.new(220,0)
stick.ImageRectSize=Vector2.new(111,111)
stick.Size=UDim2.fromScale(1,1)
stick.Active=false
stick.ZIndex=21
stick.Parent=knob

local jumpButton=Instance.new("TextButton")
jumpButton.Name="PCJump"
jumpButton.Text=""
jumpButton.AutoButtonColor=false
jumpButton.Active=true
jumpButton.BackgroundTransparency=1
jumpButton.BorderSizePixel=0
jumpButton.ZIndex=20
jumpButton.Parent=gui

local jumpImage=Instance.new("ImageLabel")
jumpImage.Name="RobloxJumpButton"
jumpImage.BackgroundTransparency=1
jumpImage.Image=JUMP_SHEET
jumpImage.ImageRectOffset=Vector2.new(1,146)
jumpImage.ImageRectSize=Vector2.new(144,144)
jumpImage.Size=UDim2.fromScale(1,1)
jumpImage.Active=false
jumpImage.ZIndex=20
jumpImage.Parent=jumpButton

local function viewportSize()
    local camera=Workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(896,414)
end

local function applyNativeLayout()
    local viewport=viewportSize()
    local isSmall=math.min(viewport.X,viewport.Y)<=500

    local thumbSize=isSmall and 70 or 120
    local thumbPos=isSmall
        and UDim2.new(0,(thumbSize/2)-10,1,-thumbSize-20)
        or UDim2.new(0,thumbSize/2,1,-thumbSize*1.75)

    joystick.Size=UDim2.fromOffset(thumbSize,thumbSize)
    joystick.Position=thumbPos

    knob.Size=UDim2.fromOffset(thumbSize/2,thumbSize/2)
    if movementTouch==nil then
        knob.Position=UDim2.fromOffset(thumbSize/2,thumbSize/2)
    end

    local jumpSize=isSmall and 70 or 120
    local jumpPos=isSmall
        and UDim2.new(1,-(jumpSize*1.5-10),1,-jumpSize-20)
        or UDim2.new(1,-(jumpSize*1.5-10),1,-jumpSize*1.75)

    jumpButton.Size=UDim2.fromOffset(jumpSize,jumpSize)
    jumpButton.Position=jumpPos
end

local function setKnobFromPosition(position)
    if not movementCenter then return end

    local delta=position-movementCenter
    local maxVisual=math.max(1,movementRadius*KNOB_VISUAL_RADIUS_FACTOR)

    if delta.Magnitude>maxVisual then
        delta=delta.Unit*maxVisual
    end

    local center=joystick.AbsoluteSize/2
    knob.Position=UDim2.fromOffset(center.X+delta.X,center.Y+delta.Y)
end

local function updateMovement(position)
    if typeof(position)=="Vector3" then
        position=Vector2.new(position.X,position.Y)
    end
    if typeof(position)~="Vector2" or not movementCenter then
        return
    end

    local delta=position-movementCenter
    local r=math.max(1,movementRadius)

    -- This normalized vector ONLY chooses a digital sector. Its magnitude is
    -- never passed to character movement.
    latest=Vector2.new(delta.X/r,delta.Y/r)
    if latest.Magnitude>1 then
        latest=latest.Unit
    end

    movementUpdates+=1
    setKnobFromPosition(position)
end

local function releaseMovement()
    movementTouch=nil
    movementCenter=nil
    latest=Vector2.zero
    bridgeSide=nil
    bridgeDeadline=-math.huge
    lastRawChord="-"
    applyKeys({})

    if IS_LEGACY then
        pcall(function()
            player:Move(Vector3.zero,true)
        end)
    end

    local center=joystick.AbsoluteSize/2
    knob.Position=UDim2.fromOffset(center.X,center.Y)
end

local function burstJump()
    if not enabled then return end

    local character=player.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")

    -- Keep a direct local jump fallback, especially useful on Legacy.
    if humanoid and humanoid.Health>0 then
        pcall(function()
            humanoid.Jump=true
        end)
    end

    jumpRequests+=1
    jumpToken+=1

    local token=jumpToken
    local deadline=os.clock()+JUMP_BURST

    task.spawn(function()
        while enabled and token==jumpToken and os.clock()<deadline do
            pcall(function()
                VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Space,false,game)
                VirtualInputManager:SendKeyEvent(true,Enum.KeyCode.Space,false,game)
            end)
            RunService.Heartbeat:Wait()
        end

        if token==jumpToken then
            pcall(function()
                VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Space,false,game)
            end)
        end
    end)
end

connections[#connections+1]=joystick.InputBegan:Connect(function(input)
    if not enabled or movementTouch~=nil then return end

    if input.UserInputType~=Enum.UserInputType.Touch
        and input.UserInputType~=Enum.UserInputType.MouseButton1 then
        return
    end

    movementTouch=input
    movementCenter=joystick.AbsolutePosition+(joystick.AbsoluteSize/2)
    movementRadius=math.max(1,math.min(joystick.AbsoluteSize.X,joystick.AbsoluteSize.Y)*0.50)
    bridgeSide=nil
    bridgeDeadline=-math.huge
    movementCaptures+=1
    updateMovement(input.Position)
end)

connections[#connections+1]=UserInputService.InputChanged:Connect(function(input)
    if enabled and input==movementTouch then
        updateMovement(input.Position)
    end
end)

connections[#connections+1]=UserInputService.InputEnded:Connect(function(input)
    if input==movementTouch then
        releaseMovement()
    end
end)

connections[#connections+1]=jumpButton.InputBegan:Connect(function(input)
    if not enabled then return end

    if input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseButton1 then
        jumpImage.ImageRectOffset=Vector2.new(146,146)
        burstJump()
    end
end)

connections[#connections+1]=jumpButton.InputEnded:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseButton1 then
        jumpImage.ImageRectOffset=Vector2.new(1,146)
    end
end)

RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Input.Value+8,function()
    gui.Enabled=enabled

    if not enabled then
        applyKeys({})
        if IS_LEGACY then
            pcall(function() player:Move(Vector3.zero,true) end)
        end
        return
    end

    local desired={}
    if movementTouch then
        desired=classifyDigital(latest)
    else
        bridgeSide=nil
        bridgeDeadline=-math.huge
    end

    -- Shared path, already known to work in Overhaul.
    applyKeys(desired)

end)

-- Legacy gets its direct digital movement at the END of the render pipeline,
-- after normal PlayerModule / game control scripts had a chance to write.
-- Overhaul never binds this step.
if IS_LEGACY then
    RunService:BindToRenderStep(LEGACY_BIND_NAME,Enum.RenderPriority.Last.Value,function()
        if not enabled then
            pcall(function() player:Move(Vector3.zero,true) end)
            return
        end

        local move=digitalMoveVector(chord)
        pcall(function()
            player:Move(move,true)
            legacyMoveWrites+=1
        end)
    end)

    -- Second Legacy-only route immediately before character simulation.
    -- This does not set velocity or boost speed; it repeats the same six
    -- fixed digital intents directly to the Humanoid so a late Legacy
    -- controller cannot zero Player:Move before physics consumes it.
    connections[#connections+1]=RunService.PreSimulation:Connect(function()
        if not enabled then return end

        local character=player.Character
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health<=0 then return end

        local move=digitalMoveVector(chord)
        pcall(function()
            humanoid:Move(move,true)
        end)
    end)
end

local function bindViewport()
    if cameraViewportConnection then
        pcall(function() cameraViewportConnection:Disconnect() end)
        cameraViewportConnection=nil
    end

    local camera=Workspace.CurrentCamera
    if camera then
        cameraViewportConnection=camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyNativeLayout)
    end

    applyNativeLayout()
end

connections[#connections+1]=Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindViewport)
bindViewport()

local api={
    Version=VERSION,
    SetEnabled=function(value)
        enabled=value~=false
        gui.Enabled=enabled
        if not enabled then releaseMovement() end
    end,
    IsEnabled=function()
        return enabled
    end,
    GetState=function()
        return {
            chord=chord,
            rawChord=lastRawChord,
            bridgeSide=bridgeSide,
            bridgeRemaining=math.max(0,bridgeDeadline-os.clock()),
            drySwapGraceSeconds=DRY_SWAP_GRACE_SECONDS,
            touchActive=movementTouch~=nil,
            captures=movementCaptures,
            updates=movementUpdates,
            keyEvents=keyEvents,
            jumpRequests=jumpRequests,
            legacyMoveWrites=legacyMoveWrites,
            dryDiagonalSwaps=dryDiagonalSwaps,
            isLegacy=IS_LEGACY,
            sectors={"W","W+A","W+D","S","A","D"},
            wHalfDegrees=W_HALF_DEG,
            diagonalEndDegrees=DIAG_END_DEG,
            sideEndDegrees=SIDE_END_DEG,
            sectorWidthsDegrees={
                W=W_HALF_DEG*2,
                WA=DIAG_END_DEG-W_HALF_DEG,
                WD=DIAG_END_DEG-W_HALF_DEG,
                A=SIDE_END_DEG-DIAG_END_DEG,
                D=SIDE_END_DEG-DIAG_END_DEG,
                S=(180-SIDE_END_DEG)*2,
            },
            knobVisualRadiusFactor=KNOB_VISUAL_RADIUS_FACTOR,
            analogMagnitudeControlsSpeed=false,
            ownsVisibleControls=true,
        }
    end,
}

ENV.EvadePCJoystickV6=api

ENV.__EvadePCJoystickV6Cleanup=function()
    enabled=false
    jumpToken+=1
    releaseMovement()

    pcall(function()
        RunService:UnbindFromRenderStep(BIND_NAME)
    end)
    pcall(function()
        RunService:UnbindFromRenderStep(LEGACY_BIND_NAME)
    end)

    pcall(function()
        VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Space,false,game)
    end)

    if cameraViewportConnection then
        pcall(function() cameraViewportConnection:Disconnect() end)
        cameraViewportConnection=nil
    end

    for _,c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(connections)

    pcall(function() gui:Destroy() end)

    ENV.EvadePCJoystickV6=nil
    ENV.__EvadePCJoystickV6Cleanup=nil
end

return api
