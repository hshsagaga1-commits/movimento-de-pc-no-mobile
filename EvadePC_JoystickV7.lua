-- Evade PC Joystick V7
-- Mobile-looking shell, digital PC-style core.
-- The finger position only selects one of six digital chords:
-- W, W+A, W+D, S, A, D. Analog magnitude never controls movement speed.
--
-- Overhaul:
--   Keeps the already-working keyboard-event route unchanged.
--
-- Legacy:
--   Uses the same keyboard events, plus a Legacy-only wake for Roblox's selected
--   keyboard activeController. No Player:Move / Humanoid:Move writer is used.
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

local VERSION="EvadePC-Joystick-V7.12-real-native-touch-taps-200ms"
local BIND_NAME="__EvadePCJoystickV7"
local LEGACY_BIND_NAME="__EvadePCJoystickV7LegacyKeyboardWake"
local GUI_NAME="EvadePCJoystickV7Gui"
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
local W_HALF_DEG=28       -- W total width: 56 deg
local DIAG_END_DEG=84     -- A/D reaches a tiny bit farther toward W, matching the new reference
local SIDE_END_DEG=142    -- pure A/D stays exactly 58 deg on both A and D
                            -- S begins 4 deg earlier on each side

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
    "__EvadePCJoystickV7Cleanup",
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

for _,name in ipairs({"EvadePCJoystickV7Gui","EvadePCJoystickV6Gui","EvadePCJoystickV5Gui","EvadePCJoystickV4Gui","EvadePCJoystickV3Gui"}) do
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
local jumpEpoch=0
local jumpBursts={}
local activeJumpBursts=0
local jumpPulseCount=0
local jumpPulsePhase=false
local jumpForcePulse=false

local keyEvents=0
local movementCaptures=0
local movementUpdates=0
local jumpRequests=0
local legacyMoveWrites=0 -- retained for state compatibility; V7 no longer writes Player:Move
local dryDiagonalSwaps=0
local lastRawChord="-"

local sharedControls=nil
local touchJumpController=nil
local jumpRoute="unresolved"
local jumpBridgeHits=0
local jumpFallbackHits=0

local nativeJumpController=nil
local nativeJumpOriginalController=nil
local nativeJumpGui=nil
local nativeJumpFrame=nil
local nativeJumpLoopRunning=false
local nativeTouchId=7300

local legacyControls=nil
local legacyWakeAttempts=0
local legacyWakeControlModuleCalls=0
local legacyWakeDirectCalls=0
local legacyWakeErrors=0
local legacyControllerEnabled=nil
local legacyControlsEnabled=nil
local legacyWakeStatus=IS_LEGACY and "starting" or "not-legacy"

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

    local center=joystick.AbsoluteSize/2
    knob.Position=UDim2.fromOffset(center.X,center.Y)
end

local function locateSharedControls()
    if type(sharedControls)=="table" then
        local cached=rawget(sharedControls,"touchJumpController")
        if type(cached)=="table" then
            touchJumpController=cached
        end
        return true
    end

    local ok=pcall(function()
        local scripts=player:FindFirstChild("PlayerScripts")
        local moduleScript=scripts and scripts:FindFirstChild("PlayerModule")
        if not moduleScript then return end

        local playerModule=require(moduleScript)
        if type(playerModule)~="table" then return end

        local controls=nil
        if type(playerModule.GetControls)=="function" then
            controls=playerModule:GetControls()
        end
        if type(controls)~="table" then
            controls=rawget(playerModule,"controls")
        end

        if type(controls)=="table" then
            sharedControls=controls
            local tj=rawget(controls,"touchJumpController")
            if type(tj)=="table" then
                touchJumpController=tj
            end
        end
    end)

    return ok and type(sharedControls)=="table"
end

local function destroyNativeJumpBridge()
    if type(sharedControls)=="table" then
        pcall(function()
            if rawget(sharedControls,"touchJumpController")==nativeJumpController then
                rawset(sharedControls,"touchJumpController",nativeJumpOriginalController)
            end
        end)
    end

    if type(nativeJumpController)=="table" then
        pcall(function() nativeJumpController:Enable(false) end)
    end

    if nativeJumpGui then
        pcall(function() nativeJumpGui:Destroy() end)
    end

    nativeJumpController=nil
    nativeJumpOriginalController=nil
    nativeJumpGui=nil
    nativeJumpFrame=nil
end

local function ensureRealNativeJump()
    if not locateSharedControls() then
        jumpRoute="native-touch-controls-missing"
        return nil,nil
    end

    if type(nativeJumpController)=="table"
        and nativeJumpGui and nativeJumpGui.Parent
        and nativeJumpFrame and nativeJumpFrame.Parent then

        pcall(function()
            -- PC Identity can make ControlModule disable TouchJump later.
            -- Re-enable the genuine module before every synthetic mobile tap.
            nativeJumpController:Enable(true,nativeJumpFrame)
        end)

        local button=rawget(nativeJumpController,"jumpButton")
        if button and button.Parent then
            button.Visible=true
            button.ImageTransparency=1
            button.BackgroundTransparency=1
            button.Size=UDim2.fromOffset(4,4)
            button.AnchorPoint=Vector2.new(0.5,0.5)
            button.Position=UDim2.fromScale(0.5,0.5)
            button.ZIndex=100
            return nativeJumpController,button
        end
    end

    destroyNativeJumpBridge()

    local ok,controller,button=pcall(function()
        local scripts=player:FindFirstChild("PlayerScripts")
        local playerModuleScript=scripts and scripts:FindFirstChild("PlayerModule")
        local controlModuleScript=playerModuleScript and playerModuleScript:FindFirstChild("ControlModule")
        local touchModuleScript=controlModuleScript and controlModuleScript:FindFirstChild("TouchJump")
        if not touchModuleScript then return nil,nil end

        local TouchJump=require(touchModuleScript)
        if type(TouchJump)~="table" or type(TouchJump.new)~="function" then
            return nil,nil
        end

        nativeJumpOriginalController=rawget(sharedControls,"touchJumpController")

        local bridgeGui=Instance.new("ScreenGui")
        bridgeGui.Name="EvadePCNativeJumpBridge"
        bridgeGui.ResetOnSpawn=false
        bridgeGui.IgnoreGuiInset=true
        bridgeGui.DisplayOrder=100000
        bridgeGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
        bridgeGui.Parent=playerGui

        local bridgeFrame=Instance.new("Frame")
        bridgeFrame.Name="TouchControlFrame"
        bridgeFrame.Size=UDim2.fromScale(1,1)
        bridgeFrame.BackgroundTransparency=1
        bridgeFrame.Active=false
        bridgeFrame.Parent=bridgeGui

        local created=TouchJump.new()
        created:Enable(true,bridgeFrame)

        local nativeButton=rawget(created,"jumpButton")
        if not nativeButton then
            created:Create()
            nativeButton=rawget(created,"jumpButton")
        end
        if not nativeButton then
            bridgeGui:Destroy()
            return nil,nil
        end

        -- Invisible 4x4 real Roblox JumpButton placed at screen center.
        -- It exists only so VirtualInputManager can send ACTUAL touch begin/end
        -- events through TouchJump's own InputBegan/InputEnded handlers.
        nativeButton.Visible=true
        nativeButton.ImageTransparency=1
        nativeButton.BackgroundTransparency=1
        nativeButton.Size=UDim2.fromOffset(4,4)
        nativeButton.AnchorPoint=Vector2.new(0.5,0.5)
        nativeButton.Position=UDim2.fromScale(0.5,0.5)
        nativeButton.ZIndex=100

        rawset(sharedControls,"touchJumpController",created)

        nativeJumpGui=bridgeGui
        nativeJumpFrame=bridgeFrame
        nativeJumpController=created

        return created,nativeButton
    end)

    if ok and type(controller)=="table" and button then
        jumpRoute="real-native-touchjump"
        return controller,button
    end

    jumpFallbackHits+=1
    jumpRoute="real-native-touchjump-create-failed"
    destroyNativeJumpBridge()
    return nil,nil
end

local function pruneJumpBursts()
    local now=os.clock()
    for i=#jumpBursts,1,-1 do
        if jumpBursts[i]<=now then
            table.remove(jumpBursts,i)
        end
    end
    activeJumpBursts=#jumpBursts
    return activeJumpBursts
end

local function sendRealNativeTap()
    local controller,button=ensureRealNativeJump()
    if type(controller)~="table" or not button then
        return false
    end

    nativeTouchId+=1
    local touchId=nativeTouchId
    local pos=button.AbsolutePosition+(button.AbsoluteSize/2)

    local okStart=pcall(function()
        -- Roblox's own test stack defines: 0=TOUCH_START, 2=TOUCH_END.
        VirtualInputManager:SendTouchEvent(touchId,0,pos.X,pos.Y)
        if type(VirtualInputManager.WaitForInputEventsProcessed)=="function" then
            VirtualInputManager:WaitForInputEventsProcessed()
        end
    end)

    if not okStart then
        jumpFallbackHits+=1
        jumpRoute="native-touch-start-failed"
        return false
    end

    jumpPulsePhase=true
    jumpPulseCount+=1
    jumpBridgeHits+=1
    jumpRoute="real-native-touch-taps"

    -- Keep the native press alive for one rendered frame so ControlModule
    -- definitely samples TouchJump:GetIsJumping()==true.
    RunService.RenderStepped:Wait()

    pcall(function()
        VirtualInputManager:SendTouchEvent(touchId,2,pos.X,pos.Y)
        if type(VirtualInputManager.WaitForInputEventsProcessed)=="function" then
            VirtualInputManager:WaitForInputEventsProcessed()
        end
    end)

    jumpPulsePhase=false

    -- One released frame makes the next iteration a genuinely NEW mobile click.
    RunService.RenderStepped:Wait()
    return true
end

local function runNativeJumpPulseLoop()
    if nativeJumpLoopRunning then return end
    nativeJumpLoopRunning=true

    task.spawn(function()
        while enabled and pruneJumpBursts()>0 do
            -- REAL click #1, #2, #3... for as long as any 200 ms window exists.
            -- This is not a hold and does not synthesize Space.
            if not sendRealNativeTap() then
                RunService.Heartbeat:Wait()
            end
        end

        jumpPulsePhase=false
        activeJumpBursts=pruneJumpBursts()
        nativeJumpLoopRunning=false
    end)
end

local function burstJump()
    if not enabled then return end

    jumpRequests+=1

    -- Every physical tap gets its OWN 200 ms deadline.
    -- New taps overlap; they never cancel or restart older deadlines.
    jumpBursts[#jumpBursts+1]=os.clock()+JUMP_BURST
    activeJumpBursts=#jumpBursts

    runNativeJumpPulseLoop()
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

-- Legacy-only keyboard-controller wake.
-- Older runtime evidence from this project showed the PC/keyboard module could be
-- selected while its activeController remained disabled. V7 fixes that layer
-- instead of writing Player:Move / Humanoid:Move.
local function readControllerEnabled(controller)
    if type(controller)~="table" then return nil end
    local value=nil
    pcall(function()
        value=rawget(controller,"enabled")
        if value==nil then value=rawget(controller,"Enabled") end
    end)
    return value
end

local function locateLegacyControls()
    if not IS_LEGACY then return false end
    if type(legacyControls)=="table" then return true end

    local ok=locateSharedControls()
    if ok and type(sharedControls)=="table" then
        legacyControls=sharedControls
    end

    if not ok or type(legacyControls)~="table" then
        legacyWakeStatus="controls-missing"
        return false
    end
    return true
end

local function wakeLegacyKeyboardController()
    if not IS_LEGACY or not enabled then return end
    if not locateLegacyControls() then return end

    local controller=rawget(legacyControls,"activeController")
    local activeModule=rawget(legacyControls,"activeControlModule")
    legacyControlsEnabled=rawget(legacyControls,"controlsEnabled")
    legacyControllerEnabled=readControllerEnabled(controller)

    if type(controller)~="table" or type(activeModule)~="table" then
        legacyWakeStatus="active-controller-missing"
        return
    end

    if legacyControllerEnabled==true then
        legacyWakeStatus="already-enabled"
        return
    end

    legacyWakeAttempts+=1

    if legacyControlsEnabled~=false
        and type(legacyControls.UpdateActiveControlModuleEnabled)=="function" then
        local ok=pcall(function()
            legacyControls:UpdateActiveControlModuleEnabled()
        end)
        if ok then
            legacyWakeControlModuleCalls+=1
        else
            legacyWakeErrors+=1
        end
    end

    legacyControllerEnabled=readControllerEnabled(controller)
    if legacyControllerEnabled==true then
        legacyWakeStatus="enabled-by-controlmodule"
        return
    end

    if legacyControlsEnabled~=false and type(controller.Enable)=="function" then
        local ok=pcall(function()
            controller:Enable(true)
        end)
        if ok then
            legacyWakeDirectCalls+=1
        else
            legacyWakeErrors+=1
        end
    end

    legacyControllerEnabled=readControllerEnabled(controller)
    if legacyControllerEnabled==true then
        legacyWakeStatus="enabled-directly"
    elseif legacyControlsEnabled==false then
        legacyWakeStatus="global-controls-disabled"
    else
        legacyWakeStatus="enable-failed"
    end
end

if IS_LEGACY then
    locateLegacyControls()
    wakeLegacyKeyboardController()

    -- Wake before normal input processing. The joystick still sends the exact
    -- same W/A/S/D key events as Overhaul; only Legacy receives this wake step.
    RunService:BindToRenderStep(
        LEGACY_BIND_NAME,
        Enum.RenderPriority.Input.Value-1,
        wakeLegacyKeyboardController
    )
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
            activeJumpBursts=activeJumpBursts,
            jumpPulseCount=jumpPulseCount,
            jumpPulsePhase=jumpPulsePhase,
            jumpBurstSeconds=JUMP_BURST,
            jumpCooldownSeconds=0,
            overlappingJumpBursts=true,
            jumpRoute=jumpRoute,
            jumpBridgeHits=jumpBridgeHits,
            jumpFallbackHits=jumpFallbackHits,
            nativeJumpBridgeInstalled=type(nativeJumpController)=="table",
            touchJumpControllerFound=type(touchJumpController)=="table",
            legacyMoveWrites=legacyMoveWrites,
            legacyWakeStatus=legacyWakeStatus,
            legacyControllerEnabled=legacyControllerEnabled,
            legacyControlsEnabled=legacyControlsEnabled,
            legacyWakeAttempts=legacyWakeAttempts,
            legacyWakeControlModuleCalls=legacyWakeControlModuleCalls,
            legacyWakeDirectCalls=legacyWakeDirectCalls,
            legacyWakeErrors=legacyWakeErrors,
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

ENV.EvadePCJoystickV7=api

ENV.__EvadePCJoystickV7Cleanup=function()
    enabled=false
    jumpEpoch+=1
    table.clear(jumpBursts)
    activeJumpBursts=0
    jumpPulsePhase=false
    jumpForcePulse=false
    jumpPulsePhase=false
    pcall(destroyNativeJumpBridge)
    releaseMovement()

    pcall(function()
        RunService:UnbindFromRenderStep(BIND_NAME)
    end)
    pcall(function()
        RunService:UnbindFromRenderStep(LEGACY_BIND_NAME)
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

    ENV.EvadePCJoystickV7=nil
    ENV.__EvadePCJoystickV7Cleanup=nil
end

return api
