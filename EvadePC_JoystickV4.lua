-- Evade PC Joystick V4
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

local VERSION="EvadePC-Joystick-V4-digital-six-sector-legacy-route"
local BIND_NAME="__EvadePCJoystickV4"
local GUI_NAME="EvadePCJoystickV4Gui"
local EVADE_GAME_ID=3647333358
local LEGACY_PLACE_ID=96537472072550

local THUMBSTICK_SHEET="rbxasset://textures/ui/TouchControlsSheet.png"
local JUMP_SHEET="rbxasset://textures/ui/Input/TouchControlsSheetV2.png"

-- Sector geometry. W is intentionally narrow, WA/WD own most of the upper arc,
-- and pure A/D only own the far lateral edges.
local PRESS_RADIUS=0.18
local W_RATIO_MAX=0.28
local DIAG_RATIO_MAX=3.20

-- Dry diagonal swap: when a held upper-arc touch crosses sides, retain the
-- current diagonal through the center band and switch directly on the far side.
local UPPER_ARC_Z_MAX=-0.10
local DIAG_SWAP_X=0.08

local JUMP_BURST=0.20

-- Visual-only reach. The knob center reaches almost the ring radius, so the
-- native stick sprite visibly extends outside the outer circle like Roblox.
local KNOB_VISUAL_RADIUS_FACTOR=0.96

local IS_EVADE=(game.GameId==EVADE_GAME_ID)
local IS_LEGACY=(IS_EVADE and game.PlaceId==LEGACY_PLACE_ID)

for _,name in ipairs({
    "__EvadePCJoystickV4Cleanup",
    "__EvadePCJoystickV3Cleanup",
    "__EvadePCJoystickV2Cleanup",
}) do
    local cleanup=ENV[name]
    if type(cleanup)=="function" then pcall(cleanup) end
end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

for _,name in ipairs({"EvadePCJoystickV4Gui","EvadePCJoystickV3Gui"}) do
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
local diagonalLatch=nil -- "A" or "D"

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

local function rawClassify(v)
    local x=v.X
    local z=v.Y

    if v.Magnitude<PRESS_RADIUS then
        return {},"-"
    end

    -- Lower half is S only. There is intentionally no SA/SD.
    if z>0.12 then
        return {S=true},"S"
    end

    if z<0 then
        local ratio=math.abs(x)/math.max(-z,0.0001)

        if ratio<=W_RATIO_MAX then
            return {W=true},"W"
        elseif ratio<=DIAG_RATIO_MAX then
            if x<0 then
                return {W=true,A=true},"W+A"
            else
                return {W=true,D=true},"W+D"
            end
        end
    end

    if x<0 then
        return {A=true},"A"
    elseif x>0 then
        return {D=true},"D"
    end

    return z<0 and {W=true} or {S=true},z<0 and "W" or "S"
end

local function classifyDigital(v)
    if v.Magnitude<PRESS_RADIUS then
        diagonalLatch=nil
        lastRawChord="-"
        return {}
    end

    local raw,rawName=rawClassify(v)
    lastRawChord=rawName

    -- Leaving the upper arc ends the dry-swap latch. This preserves normal
    -- access to pure A/D and S.
    if v.Y>UPPER_ARC_Z_MAX then
        diagonalLatch=nil
        return raw
    end

    -- Enter a diagonal normally from center/W.
    if rawName=="W+A" then
        if diagonalLatch=="D" then
            dryDiagonalSwaps+=1
        end
        diagonalLatch="A"
        return raw
    elseif rawName=="W+D" then
        if diagonalLatch=="A" then
            dryDiagonalSwaps+=1
        end
        diagonalLatch="D"
        return raw
    end

    -- While already in a diagonal sweep, do not emit W through the center.
    if diagonalLatch=="D" then
        if v.X<=-DIAG_SWAP_X then
            diagonalLatch="A"
            dryDiagonalSwaps+=1
            return {W=true,A=true}
        end
        return {W=true,D=true}
    elseif diagonalLatch=="A" then
        if v.X>=DIAG_SWAP_X then
            diagonalLatch="D"
            dryDiagonalSwaps+=1
            return {W=true,D=true}
        end
        return {W=true,A=true}
    end

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
    diagonalLatch=nil
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
    diagonalLatch=nil
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
        diagonalLatch=nil
    end

    -- Shared path, already known to work in Overhaul.
    applyKeys(desired)

    -- LEGACY ONLY. Overhaul never executes Player:Move here.
    -- This is still fully digital: six fixed vectors, no analog magnitude.
    if IS_LEGACY then
        local move=digitalMoveVector(chord)
        pcall(function()
            player:Move(move,true)
            legacyMoveWrites+=1
        end)
    end
end)

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
            diagonalLatch=diagonalLatch,
            touchActive=movementTouch~=nil,
            captures=movementCaptures,
            updates=movementUpdates,
            keyEvents=keyEvents,
            jumpRequests=jumpRequests,
            legacyMoveWrites=legacyMoveWrites,
            dryDiagonalSwaps=dryDiagonalSwaps,
            isLegacy=IS_LEGACY,
            sectors={"W","W+A","W+D","S","A","D"},
            wRatioMax=W_RATIO_MAX,
            diagonalRatioMax=DIAG_RATIO_MAX,
            knobVisualRadiusFactor=KNOB_VISUAL_RADIUS_FACTOR,
            analogMagnitudeControlsSpeed=false,
            ownsVisibleControls=true,
        }
    end,
}

ENV.EvadePCJoystickV4=api

ENV.__EvadePCJoystickV4Cleanup=function()
    enabled=false
    jumpToken+=1
    releaseMovement()

    pcall(function()
        RunService:UnbindFromRenderStep(BIND_NAME)
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

    ENV.EvadePCJoystickV4=nil
    ENV.__EvadePCJoystickV4Cleanup=nil
end

return api
