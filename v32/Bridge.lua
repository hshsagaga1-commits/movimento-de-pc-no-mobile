-- UI and sector geometry derived from the preserved V3.1 bridge.
return function(watchPosture)
    local Players=game:GetService("Players")
    local RunService=game:GetService("RunService")
    local inputService=game:GetService("UserInputService")
    local inputManager=game:GetService("VirtualInputManager")
    local player=Players.LocalPlayer
    local playerGui=assert(player:FindFirstChild("PlayerGui"))
    local env=getgenv()
    local BIND_NAME="__PCKeyboardTouchBridgeV52"
    local GUI_NAME="PCKeyboardTouchBridgeV52Overlay"
    local PRESS_THRESHOLD=0.30
    local SWEEP_STAGE_SECONDS=0.016
    local JUMP_BURST_SECONDS=0.200
    local KEY_CODES={Enum.KeyCode.W,Enum.KeyCode.A,Enum.KeyCode.S,Enum.KeyCode.D}
    local KEY_BITS={1,2,4,8}
    local CHORD_BITS={["-"]=0,W=1,A=2,S=4,D=8,["W+A"]=3,["W+D"]=9,
        ["W+A+D"]=11,["A+D"]=10,["A+S"]=6,["S+D"]=12}
    local BIT_CHORD={}
    for bits=0,15 do
        local names={}
        for index,name in ipairs({"W","A","S","D"}) do
            if bit32.btest(bits,KEY_BITS[index]) then names[#names+1]=name end
        end
        BIT_CHORD[bits]=#names==0 and "-" or table.concat(names,"+")
    end
    local STANDING={A="W+A",D="W+D",["W+A+D"]="W"}
    local LOW={["W+A"]="A",["W+D"]="D"}
    local SIDE={A=-1,["W+A"]=-1,D=1,["W+D"]=1}

    local previous=env.__PCKeyboardTouchBridgeV52Cleanup
    if type(previous)=="function" then previous() end
    local oldGui=playerGui:FindFirstChild(GUI_NAME)
    if oldGui then oldGui:Destroy() end

    local gui=Instance.new("ScreenGui")
    gui.Name=GUI_NAME
    gui.ResetOnSpawn=false
    gui.IgnoreGuiInset=true
    gui.DisplayOrder=10020
    gui.Parent=playerGui

    local joystick=Instance.new("TextButton")
    joystick.Name="PCJoystick"
    joystick.Text=""
    joystick.AutoButtonColor=false
    joystick.Active=true
    joystick.BackgroundColor3=Color3.fromRGB(55,55,55)
    joystick.BackgroundTransparency=0.48
    joystick.BorderSizePixel=0
    joystick.AnchorPoint=Vector2.new(0,1)
    joystick.Position=UDim2.new(0,42,1,-42)
    joystick.Size=UDim2.fromOffset(132,132)
    joystick.ZIndex=20
    joystick.Parent=gui
    local joystickCorner=Instance.new("UICorner")
    joystickCorner.CornerRadius=UDim.new(1,0)
    joystickCorner.Parent=joystick
    local joystickStroke=Instance.new("UIStroke")
    joystickStroke.Thickness=3
    joystickStroke.Transparency=0.35
    joystickStroke.Parent=joystick

    local knob=Instance.new("Frame")
    knob.Name="Knob"
    knob.BackgroundColor3=Color3.fromRGB(205,205,205)
    knob.BackgroundTransparency=0.22
    knob.BorderSizePixel=0
    knob.AnchorPoint=Vector2.new(0.5,0.5)
    knob.Position=UDim2.fromScale(0.5,0.5)
    knob.Size=UDim2.fromOffset(54,54)
    knob.ZIndex=21
    knob.Parent=joystick
    local knobCorner=Instance.new("UICorner")
    knobCorner.CornerRadius=UDim.new(1,0)
    knobCorner.Parent=knob

    local jumpButton=Instance.new("TextButton")
    jumpButton.Name="PCJump"
    jumpButton.Text="↑"
    jumpButton.Font=Enum.Font.GothamBold
    jumpButton.TextSize=35
    jumpButton.TextColor3=Color3.fromRGB(225,225,225)
    jumpButton.AutoButtonColor=false
    jumpButton.Active=true
    jumpButton.BackgroundColor3=Color3.fromRGB(55,55,55)
    jumpButton.BackgroundTransparency=0.46
    jumpButton.BorderSizePixel=0
    jumpButton.AnchorPoint=Vector2.new(1,1)
    jumpButton.Position=UDim2.new(1,-52,1,-122)
    jumpButton.Size=UDim2.fromOffset(86,86)
    jumpButton.ZIndex=20
    jumpButton.Parent=gui
    local jumpCorner=Instance.new("UICorner")
    jumpCorner.CornerRadius=UDim.new(1,0)
    jumpCorner.Parent=jumpButton
    local jumpStroke=Instance.new("UIStroke")
    jumpStroke.Thickness=3
    jumpStroke.Transparency=0.35
    jumpStroke.Parent=jumpButton

    local enabled=true
    local acceptingInput=true
    local connections={}
    local unwatch
    local touch,center
    local radius=46
    local x,z=0,0
    local low,postureSource=false,"unknown"
    local lateralLatch,centerExpires
    local target,applied,pressed="-","-",0
    local retryAt
    local sweepTarget,sweepAt
    local jumpConnection,jumpDeadline
    local spaceDown=false
    local knobTarget,knobOffset=Vector2.zero,Vector2.zero
    local movementCaptures,movementUpdates,keyEvents,jumpRequests,jumpPulses=0,0,0,0,0
    local evaluations,knobWrites,keyErrors=0,0,0

    local function sendKey(code,down)
        local ok=pcall(inputManager.SendKeyEvent,inputManager,down,code,false,game)
        if ok then keyEvents+=1 else keyErrors+=1 end
        return ok
    end

    local function applyChord(chord,now)
        applied=chord
        local wanted=CHORD_BITS[chord]
        if pressed==wanted then retryAt=nil return end
        -- V3.1 presses additions before removing old keys, including on pure A/D swaps.
        for i,code in ipairs(KEY_CODES) do
            local bit=KEY_BITS[i]
            if bit32.btest(wanted,bit) and not bit32.btest(pressed,bit) and sendKey(code,true) then
                pressed=bit32.bor(pressed,bit)
            end
        end
        for i,code in ipairs(KEY_CODES) do
            local bit=KEY_BITS[i]
            if bit32.btest(pressed,bit) and not bit32.btest(wanted,bit) and sendKey(code,false) then
                pressed=bit32.band(pressed,bit32.bnot(bit))
            end
        end
        retryAt=pressed~=wanted and now+1/30 or nil
    end

    local function chooseSector(now)
        local ax,az=math.abs(x),math.abs(z)
        local magnitudeSquared=x*x+z*z
        local horizontal=x<0 and "A" or "D"
        local inSideCorridor=az<=0.24

        if lateralLatch then
            if not inSideCorridor then
                lateralLatch,centerExpires=nil,nil
            elseif (lateralLatch=="A" and x>=0.08) or (lateralLatch=="D" and x<=-0.08) then
                lateralLatch,centerExpires=horizontal,nil
                return horizontal
            elseif magnitudeSquared>=PRESS_THRESHOLD^2 then
                centerExpires=nil
                return lateralLatch
            else
                centerExpires=centerExpires or now
                if now<=centerExpires then return lateralLatch end
                lateralLatch,centerExpires=nil,nil
            end
        end

        if magnitudeSquared<PRESS_THRESHOLD^2 then return "-" end
        if az<=0.0001 then
            lateralLatch=horizontal
            return horizontal
        end

        local ratio=ax/az
        if z<0 then
            if ax<=0.0001 then return "W" end
            if ratio<=0.34 then return "W+A+D" end
            if magnitudeSquared>=0.55^2 and ratio<=2.20 then
                return horizontal=="A" and "W+A" or "W+D"
            end
            if ratio<=1 then return "W" end
        else
            if ratio<0.65 then return "S" end
            if ratio<=1.54 then return horizontal=="A" and "A+S" or "S+D" end
        end
        if inSideCorridor then lateralLatch=horizontal end
        return horizontal
    end

    local function refreshKeys(now,modeChanged)
        evaluations+=1
        local sector=chooseSector(now)
        local mapped=(low and LOW or STANDING)[sector] or sector
        if mapped==target and not modeChanged then return end

        local previousSide=SIDE[target]
        local nextSide=SIDE[mapped]
        local turning=not modeChanged and not sweepTarget and z < -0.24
            and previousSide and nextSide and previousSide~=nextSide
        target=mapped
        sweepTarget,sweepAt=nil,nil
        if turning then
            sweepTarget,sweepAt=mapped,now+SWEEP_STAGE_SECONDS
            applyChord(low and "A+D" or "W+A+D",now)
        else
            applyChord(mapped,now)
        end
    end

    local config=env.PCMovementV32Config
    if type(config)=="table" and config.Profile==true and debug.profilebegin and debug.profileend then
        local evaluate=refreshKeys
        refreshKeys=function(now,modeChanged)
            debug.profilebegin("PC Movement V3.2 / Joystick")
            evaluate(now,modeChanged)
            debug.profileend()
        end
    end

    local function writeKnob()
        local size=joystick.AbsoluteSize
        knob.Position=UDim2.fromOffset(size.X/2+knobOffset.X,size.Y/2+knobOffset.Y)
        knobWrites+=1
    end

    local function updateKnobTarget(dx,dy)
        local size=joystick.AbsoluteSize
        local reach=math.max(1,math.min(size.X,size.Y)/2)
        local distanceSquared=dx*dx+dy*dy
        local scale=distanceSquared>reach*reach and reach/math.sqrt(distanceSquared) or 1
        knobTarget=Vector2.new(dx*scale,dy*scale)
    end

    local function updateMovement(position,begin)
        local dx,dy=position.X-center.X,position.Y-center.Y
        local newX,newZ=dx/radius,dy/radius
        if not begin and newX==x and newZ==z then return end
        x,z=newX,newZ
        movementUpdates+=1
        updateKnobTarget(dx,dy)
        if begin then
            knobOffset=knobTarget
            writeKnob()
        end
        refreshKeys(os.clock(),false)
    end

    local function releaseMovement(now)
        local owned=touch~=nil
        touch,center=nil,nil
        x,z=0,0
        lateralLatch,centerExpires=nil,nil
        sweepTarget,sweepAt=nil,nil
        target="-"
        applyChord("-",now)
        if owned then
            knobTarget,knobOffset=Vector2.zero,Vector2.zero
            knob.Position=UDim2.fromScale(0.5,0.5)
            knobWrites+=1
        end
    end

    local function stopJump()
        jumpDeadline=nil
        if jumpConnection then
            jumpConnection:Disconnect()
            jumpConnection=nil
        end
        if spaceDown and sendKey(Enum.KeyCode.Space,false) then spaceDown=false end
    end

    local function pulseJump()
        -- Keep the original up/down sequence, including the initial pulse.
        if sendKey(Enum.KeyCode.Space,false) then spaceDown=false end
        if sendKey(Enum.KeyCode.Space,true) then spaceDown=true end
        jumpPulses+=1
    end

    local function requestJump()
        jumpRequests+=1
        jumpDeadline=os.clock()+JUMP_BURST_SECONDS
        pulseJump()
        if not jumpConnection then
            jumpConnection=RunService.Heartbeat:Connect(function()
                if not jumpDeadline then return end
                if os.clock()>=jumpDeadline then stopJump() else pulseJump() end
            end)
        end
    end

    local function resetInput()
        releaseMovement(os.clock())
        stopJump()
    end

    local function containsPoint(control,position)
        if not control.Parent then return false end
        local p,s=control.AbsolutePosition,control.AbsoluteSize
        return position.X>=p.X and position.X<=p.X+s.X
            and position.Y>=p.Y and position.Y<=p.Y+s.Y
    end

    local api={}
    local function cleanup()
        if not enabled then return end
        enabled=false
        RunService:UnbindFromRenderStep(BIND_NAME)
        for _,connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
        if unwatch then unwatch() end
        resetInput()
        -- Give a transient injection failure one last chance before releasing ownership.
        if pressed~=0 then applyChord("-",os.clock()) end
        if spaceDown then stopJump() end
        gui:Destroy()
        if env.PCKeyboardTouchBridgeV52==api then env.PCKeyboardTouchBridgeV52=nil end
        if env.__PCKeyboardTouchBridgeV52Cleanup==cleanup then env.__PCKeyboardTouchBridgeV52Cleanup=nil end
    end
    env.__PCKeyboardTouchBridgeV52Cleanup=cleanup

    connections[#connections+1]=inputService.InputBegan:Connect(function(input)
        if not enabled or not acceptingInput or gui.Parent~=playerGui or input.UserInputType~=Enum.UserInputType.Touch then return end
        local position=input.Position
        if containsPoint(joystick,position) then
            if touch then return end
            touch=input
            local size=joystick.AbsoluteSize
            center=joystick.AbsolutePosition+size/2
            radius=math.max(46,math.min(size.X,size.Y)*0.42)
            movementCaptures+=1
            updateMovement(position,true)
        elseif containsPoint(jumpButton,position) then
            requestJump()
        end
    end)

    connections[#connections+1]=inputService.InputChanged:Connect(function(input)
        if enabled and input==touch then
            if input.UserInputState==Enum.UserInputState.Cancel then
                releaseMovement(os.clock())
            else
                updateMovement(input.Position,false)
            end
        end
    end)

    connections[#connections+1]=inputService.InputEnded:Connect(function(input)
        if enabled and input==touch then
            if input.UserInputState~=Enum.UserInputState.Cancel then updateMovement(input.Position,false) end
            releaseMovement(os.clock())
        end
    end)
    connections[#connections+1]=inputService.WindowFocusReleased:Connect(resetInput)
    connections[#connections+1]=player.CharacterRemoving:Connect(resetInput)
    connections[#connections+1]=joystick:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if touch then
            updateKnobTarget(x*radius,z*radius)
            writeKnob()
        end
    end)

    unwatch=watchPosture(function(isLow,source)
        if not enabled then return end
        postureSource=source
        if low~=isLow then
            low=isLow
            if touch then refreshKeys(os.clock(),true) end
        end
    end)

    RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Input.Value+8,function(dt)
        if not enabled then return end
        if sweepAt or centerExpires or retryAt or (spaceDown and not jumpConnection) then
            local now=os.clock()
            if centerExpires and now>centerExpires then refreshKeys(now,false) end
            if sweepAt and now>=sweepAt then
                local nextChord=sweepTarget
                sweepTarget,sweepAt=nil,nil
                applyChord(nextChord,now)
            end
            if retryAt and now>=retryAt then applyChord(applied,now) end
            if spaceDown and not jumpConnection then stopJump() end
        end
        if touch and knobOffset~=knobTarget then
            local step=math.clamp(dt or 1/60,0,0.05)
            knobOffset=knobOffset:Lerp(knobTarget,1-math.exp(-step/0.040))
            if (knobOffset-knobTarget).Magnitude<0.06 then knobOffset=knobTarget end
            writeKnob()
        end
    end)

    api.SuspendInput=function()
        if not enabled or not acceptingInput then return end
        acceptingInput=false
        resetInput()
    end
    api.Version="3.2-adaptive"
    api.OwnsTouch=function(input) return touch~=nil and touch==input end
    api.ReadMovement=function()
        return BIT_CHORD[pressed],x,z,sweepTarget~=nil,jumpPulses
    end
    api.GetState=function()
        return {chord=BIT_CHORD[pressed],analogX=x,analogZ=z,sweepActive=sweepTarget~=nil,
            movementTouchActive=touch~=nil,movementTouch=touch,movementCaptures=movementCaptures,
            movementUpdates=movementUpdates,keyEvents=keyEvents,keyErrors=keyErrors,jumpRequests=jumpRequests,
            jumpPulses=jumpPulses,bufferedJumpCount=0,jumpActive=jumpConnection~=nil,
            directPlayerMove=false,visibleJoystick=true,movementHalf=0.80,
            mode=low and "crouch-or-emote" or "standing",postureSource=postureSource,
            sectorEvaluations=evaluations,knobWrites=knobWrites}
    end
    env.PCKeyboardTouchBridgeV52=api
    return api
end
