local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local VirtualInputManager=game:GetService("VirtualInputManager")

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")

local BIND_NAME="__PCKeyboardTouchBridgeV52"
local GUI_NAME="PCKeyboardTouchBridgeV52Overlay"
local MOVEMENT_HALF=0.50
local PRESS_THRESHOLD=0.30
local RELEASE_THRESHOLD=0.18
local DIRECTION_LATCH_SECONDS=0.09
local JUMP_MIN_INTERVAL=0.11
local JUMP_BUFFER_SECONDS=0.14
local SPACE_PULSE_SECONDS=0.055

for _,cleanupName in ipairs({
    "__PCKeyboardTouchBridgeV52Cleanup",
    "__PCKeyboardTouchBridgeV5Cleanup",
    "__PCIndependentJoystickCleanup",
    "__PCSelectiveWASDCleanup",
    "__PCClassicNativeKeysV3Cleanup",
    "__PCClassicNativeKeysCleanup",
    "__PCClassicWASDCleanup",
}) do
    local cleanup=getgenv()[cleanupName]
    if type(cleanup)=="function" then pcall(cleanup) end
end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local oldGui=playerGui:FindFirstChild(GUI_NAME)
if oldGui then oldGui:Destroy() end

local enabled=true
local movementTouch=nil
local movementCenter=nil
local movementRadius=64
local latestX=0
local latestZ=0
local pressed={W=false,A=false,S=false,D=false}
local axisX={state=0,releaseAt=nil}
local axisZ={state=0,releaseAt=nil}
local latestChord="-"
local connections={}
local lastJumpPulse=-math.huge
local pendingJumpDeadline=nil
local pendingSpaceReleaseToken=0
local movementCaptures=0
local movementUpdates=0
local keyEvents=0
local jumpRequests=0
local jumpPulses=0
local bufferedJumpCount=0

local KEYS={
    W=Enum.KeyCode.W,
    A=Enum.KeyCode.A,
    S=Enum.KeyCode.S,
    D=Enum.KeyCode.D,
}

local function viewportSize()
    local camera=workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1108,512)
end

local function onMovementHalf(position)
    if typeof(position)=="Vector3" then position=Vector2.new(position.X,position.Y) end
    if typeof(position)~="Vector2" then return false end
    return position.X<=viewportSize().X*MOVEMENT_HALF
end

local function sendKey(name,down)
    local code=KEYS[name]
    if not code then return false end
    local ok=pcall(function()
        VirtualInputManager:SendKeyEvent(down,code,false,game)
    end)
    if ok then keyEvents+=1 end
    return ok
end

local function rebuildChord()
    local out={}
    for _,name in ipairs({"W","A","S","D"}) do
        if pressed[name] then out[#out+1]=name end
    end
    latestChord=#out>0 and table.concat(out,"+") or "-"
end

local function applyKeys(desired)
    desired=desired or {}
    for _,name in ipairs({"W","A","S","D"}) do
        if pressed[name] and not desired[name] then
            sendKey(name,false)
            pressed[name]=false
        end
    end
    for _,name in ipairs({"W","A","S","D"}) do
        if desired[name] and not pressed[name] then
            if sendKey(name,true) then pressed[name]=true end
        end
    end
    rebuildChord()
end

local function releaseKeys()
    applyKeys({})
end

local function resetAxis(axis)
    axis.state=0
    axis.releaseAt=nil
end

local function updateAxis(axis,value,now)
    if value>=PRESS_THRESHOLD then
        axis.state=1 axis.releaseAt=nil return 1
    elseif value<=-PRESS_THRESHOLD then
        axis.state=-1 axis.releaseAt=nil return -1
    end
    if axis.state==1 then
        if value>=RELEASE_THRESHOLD then axis.releaseAt=nil return 1 end
        if axis.releaseAt==nil then axis.releaseAt=now+DIRECTION_LATCH_SECONDS end
        if now<axis.releaseAt then return 1 end
        resetAxis(axis)
    elseif axis.state==-1 then
        if value<=-RELEASE_THRESHOLD then axis.releaseAt=nil return -1 end
        if axis.releaseAt==nil then axis.releaseAt=now+DIRECTION_LATCH_SECONDS end
        if now<axis.releaseAt then return -1 end
        resetAxis(axis)
    end
    return 0
end

local function refreshKeys(now)
    if not enabled or movementTouch==nil then
        resetAxis(axisX)
        resetAxis(axisZ)
        releaseKeys()
        return
    end
    local x=updateAxis(axisX,latestX,now)
    local z=updateAxis(axisZ,latestZ,now)
    applyKeys({W=z<0,S=z>0,A=x<0,D=x>0})
end

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

local function setKnobFromPosition(position)
    if typeof(position)=="Vector3" then position=Vector2.new(position.X,position.Y) end
    if typeof(position)~="Vector2" or not movementCenter then return end
    local delta=position-movementCenter
    local maxVisual=math.max(1,movementRadius*0.62)
    local visual=delta
    if visual.Magnitude>maxVisual then visual=visual.Unit*maxVisual end
    knob.Position=UDim2.fromOffset(joystick.AbsoluteSize.X/2+visual.X,joystick.AbsoluteSize.Y/2+visual.Y)
end

local function updateMovement(position)
    if typeof(position)=="Vector3" then position=Vector2.new(position.X,position.Y) end
    if typeof(position)~="Vector2" or not movementCenter then return end
    local delta=position-movementCenter
    local r=math.max(1,movementRadius)
    latestX=delta.X/r
    latestZ=delta.Y/r
    movementUpdates+=1
    setKnobFromPosition(position)
end

local function releaseMovement()
    movementTouch=nil
    movementCenter=nil
    latestX=0
    latestZ=0
    resetAxis(axisX)
    resetAxis(axisZ)
    releaseKeys()
    knob.Position=UDim2.fromScale(0.5,0.5)
end

local function pulseJump()
    lastJumpPulse=os.clock()
    pendingJumpDeadline=nil
    jumpPulses+=1
    pcall(function()
        VirtualInputManager:SendKeyEvent(true,Enum.KeyCode.Space,false,game)
    end)
    pendingSpaceReleaseToken+=1
    local token=pendingSpaceReleaseToken
    task.delay(SPACE_PULSE_SECONDS,function()
        if token~=pendingSpaceReleaseToken then return end
        pcall(function()
            VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Space,false,game)
        end)
    end)
end

local function requestJump()
    if not enabled then return end
    jumpRequests+=1
    local now=os.clock()
    if now-lastJumpPulse>=JUMP_MIN_INTERVAL then
        pulseJump()
    else
        pendingJumpDeadline=now+JUMP_BUFFER_SECONDS
        bufferedJumpCount+=1
    end
end

connections[#connections+1]=joystick.InputBegan:Connect(function(input)
    if not enabled or movementTouch~=nil then return end
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    local p=Vector2.new(input.Position.X,input.Position.Y)
    if not onMovementHalf(p) then return end
    movementTouch=input
    movementCenter=joystick.AbsolutePosition+joystick.AbsoluteSize/2
    movementRadius=math.max(46,math.min(joystick.AbsoluteSize.X,joystick.AbsoluteSize.Y)*0.42)
    movementCaptures+=1
    updateMovement(input.Position)
    refreshKeys(os.clock())
end)

connections[#connections+1]=UserInputService.InputChanged:Connect(function(input)
    if enabled and input==movementTouch then
        local p=Vector2.new(input.Position.X,input.Position.Y)
        if not onMovementHalf(p) then
            releaseMovement()
            return
        end
        updateMovement(input.Position)
    end
end)

connections[#connections+1]=UserInputService.InputEnded:Connect(function(input)
    if input==movementTouch then releaseMovement() end
end)

connections[#connections+1]=jumpButton.InputBegan:Connect(function(input)
    if enabled and input.UserInputType==Enum.UserInputType.Touch then
        requestJump()
    end
end)

RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Input.Value+8,function()
    local now=os.clock()
    refreshKeys(now)
    if pendingJumpDeadline then
        if now>pendingJumpDeadline then
            pendingJumpDeadline=nil
        elseif now-lastJumpPulse>=JUMP_MIN_INTERVAL then
            pulseJump()
        end
    end
end)

getgenv().PCKeyboardTouchBridgeV52={
    Version="5.2-visible-joystick-keyboard-only",
    GetState=function()
        return {
            chord=latestChord,
            movementTouchActive=movementTouch~=nil,
            movementCaptures=movementCaptures,
            movementUpdates=movementUpdates,
            keyEvents=keyEvents,
            jumpRequests=jumpRequests,
            jumpPulses=jumpPulses,
            bufferedJumpCount=bufferedJumpCount,
            directPlayerMove=false,
            visibleJoystick=true,
            movementHalf=MOVEMENT_HALF,
        }
    end,
}

getgenv().__PCKeyboardTouchBridgeV52Cleanup=function()
    enabled=false
    releaseMovement()
    pendingJumpDeadline=nil
    pendingSpaceReleaseToken+=1
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    pcall(function() VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Space,false,game) end)
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    pcall(function() gui:Destroy() end)
    getgenv().PCKeyboardTouchBridgeV52=nil
    getgenv().__PCKeyboardTouchBridgeV52Cleanup=nil
end
