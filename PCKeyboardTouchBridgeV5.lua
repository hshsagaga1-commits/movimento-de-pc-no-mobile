local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BIND_NAME = "__PCKeyboardTouchBridgeV5"
local GUI_NAME = "PCKeyboardTouchBridgeV5Overlay"
local MOVEMENT_HALF = 0.50
local PRESS_THRESHOLD = 0.30
local RELEASE_THRESHOLD = 0.18
local DIRECTION_LATCH_SECONDS = 0.09
local JUMP_MIN_INTERVAL = 0.11
local JUMP_BUFFER_SECONDS = 0.14
local SPACE_PULSE_SECONDS = 0.055

for _, cleanupName in ipairs({
    "__PCKeyboardTouchBridgeV5Cleanup",
    "__PCIndependentJoystickCleanup",
    "__PCSelectiveWASDCleanup",
    "__PCClassicNativeKeysV3Cleanup",
    "__PCClassicNativeKeysCleanup",
    "__PCClassicWASDCleanup",
}) do
    local cleanup = getgenv()[cleanupName]
    if type(cleanup) == "function" then pcall(cleanup) end
end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local oldGui = playerGui:FindFirstChild(GUI_NAME)
if oldGui then oldGui:Destroy() end

local enabled = true
local movementTouch = nil
local movementCenter = nil
local movementRadius = 64
local latestX = 0
local latestZ = 0
local pressed = {W=false,A=false,S=false,D=false}
local axisX = {state=0, releaseAt=nil}
local axisZ = {state=0, releaseAt=nil}
local latestChord = "-"
local connections = {}
local jumpConnections = {}
local joystickFrame = nil
local jumpButton = nil
local jumpOverlay = nil
local lastJumpPulse = -math.huge
local pendingJumpDeadline = nil
local pendingSpaceReleaseToken = 0
local movementCaptures = 0
local movementUpdates = 0
local keyEvents = 0
local jumpRequests = 0
local jumpPulses = 0
local bufferedJumpCount = 0

local KEYS = {
    W=Enum.KeyCode.W,
    A=Enum.KeyCode.A,
    S=Enum.KeyCode.S,
    D=Enum.KeyCode.D,
}

local function viewportSize()
    local camera = workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1108,512)
end

local function onMovementHalf(position)
    if typeof(position)=="Vector3" then position=Vector2.new(position.X,position.Y) end
    if typeof(position)~="Vector2" then return false end
    return position.X <= viewportSize().X * MOVEMENT_HALF
end

local function sendKey(name,down)
    local code=KEYS[name]
    if not code then return end
    local ok=pcall(function()
        VirtualInputManager:SendKeyEvent(down,code,false,game)
    end)
    if ok then keyEvents += 1 end
end

local function rebuildChord()
    local out={}
    for _,name in ipairs({"W","A","S","D"}) do
        if pressed[name] then out[#out+1]=name end
    end
    latestChord=#out>0 and table.concat(out,"+") or "-"
end

local function applyKeys(desired)
    for _,name in ipairs({"W","A","S","D"}) do
        if pressed[name] and not desired[name] then
            sendKey(name,false)
            pressed[name]=false
        end
    end
    for _,name in ipairs({"W","A","S","D"}) do
        if desired[name] and not pressed[name] then
            sendKey(name,true)
            pressed[name]=true
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
        resetAxis(axisX) resetAxis(axisZ)
        releaseKeys()
        return
    end
    local x=updateAxis(axisX,latestX,now)
    local z=updateAxis(axisZ,latestZ,now)
    applyKeys({
        W=z<0,
        S=z>0,
        A=x<0,
        D=x>0,
    })
end

local function getTouchControlFrame()
    local tg=playerGui:FindFirstChild("TouchGui")
    return tg and tg:FindFirstChild("TouchControlFrame",true) or nil
end

local function findJoystickFrame()
    local root=getTouchControlFrame()
    if not root then joystickFrame=nil return nil end
    local best=nil
    local bestArea=0
    for _,obj in ipairs(root:GetDescendants()) do
        if obj:IsA("GuiObject") then
            local n=string.lower(obj.Name)
            if string.find(n,"thumbstick",1,true) or string.find(n,"joystick",1,true) then
                local s=obj.AbsoluteSize
                local area=s.X*s.Y
                if s.X>=48 and s.Y>=48 and area>bestArea then
                    best=obj bestArea=area
                end
            end
        end
    end
    joystickFrame=best
    return best
end

local function insideFrame(position,frame,padding)
    if not frame or not frame.Parent then return false end
    local a=frame.AbsolutePosition-Vector2.new(padding,padding)
    local b=frame.AbsolutePosition+frame.AbsoluteSize+Vector2.new(padding,padding)
    return position.X>=a.X and position.Y>=a.Y and position.X<=b.X and position.Y<=b.Y
end

local function acquireMovement(position)
    if not onMovementHalf(position) then return false end
    local frame=findJoystickFrame()
    if frame and insideFrame(position,frame,18) then
        local n=string.lower(frame.Name)
        if string.find(n,"dynamic",1,true) then
            movementCenter=position
            movementRadius=math.max(52,math.min(frame.AbsoluteSize.X,frame.AbsoluteSize.Y)*0.24)
        else
            movementCenter=frame.AbsolutePosition+frame.AbsoluteSize/2
            movementRadius=math.max(46,math.min(frame.AbsoluteSize.X,frame.AbsoluteSize.Y)/2)
        end
        return true
    end
    local vp=viewportSize()
    if position.X<=vp.X*0.33 and position.Y>=vp.Y*0.48 then
        movementCenter=position
        movementRadius=math.max(52,math.min(vp.X,vp.Y)*0.12)
        return true
    end
    return false
end

local function updateMovement(position)
    if typeof(position)=="Vector3" then position=Vector2.new(position.X,position.Y) end
    if typeof(position)~="Vector2" or not movementCenter then return end
    local d=position-movementCenter
    local r=math.max(1,movementRadius)
    latestX=d.X/r
    latestZ=d.Y/r
    movementUpdates += 1
end

local function releaseMovement()
    movementTouch=nil
    movementCenter=nil
    latestX=0 latestZ=0
    resetAxis(axisX) resetAxis(axisZ)
    releaseKeys()
end

local function pulseJump()
    lastJumpPulse=os.clock()
    pendingJumpDeadline=nil
    jumpPulses += 1
    pcall(function()
        VirtualInputManager:SendKeyEvent(true,Enum.KeyCode.Space,false,game)
    end)
    pendingSpaceReleaseToken += 1
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
    jumpRequests += 1
    local now=os.clock()
    if now-lastJumpPulse>=JUMP_MIN_INTERVAL then
        pulseJump()
    else
        pendingJumpDeadline=now+JUMP_BUFFER_SECONDS
        bufferedJumpCount += 1
    end
end

local function findJumpButton()
    local root=getTouchControlFrame()
    if not root then return nil end
    local exact=root:FindFirstChild("JumpButton",true)
    if exact and exact:IsA("GuiObject") then return exact end
    for _,obj in ipairs(root:GetDescendants()) do
        if obj:IsA("GuiObject") and string.find(string.lower(obj.Name),"jump",1,true) then
            local s=obj.AbsoluteSize
            if s.X>=40 and s.Y>=40 then return obj end
        end
    end
    return nil
end

local gui=Instance.new("ScreenGui")
gui.Name=GUI_NAME
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.DisplayOrder=10000
gui.Parent=playerGui

local function clearJumpOverlay()
    for _,c in ipairs(jumpConnections) do pcall(function() c:Disconnect() end) end
    table.clear(jumpConnections)
    if jumpOverlay then pcall(function() jumpOverlay:Destroy() end) end
    jumpOverlay=nil jumpButton=nil
end

local function syncJumpOverlay()
    local button=findJumpButton()
    if button~=jumpButton then
        clearJumpOverlay()
        jumpButton=button
        if button then
            jumpOverlay=Instance.new("TextButton")
            jumpOverlay.Name="JumpTimingAssistCapture"
            jumpOverlay.BackgroundTransparency=1
            jumpOverlay.Text=""
            jumpOverlay.AutoButtonColor=false
            jumpOverlay.Active=true
            jumpOverlay.ZIndex=100
            jumpOverlay.Parent=gui
            jumpConnections[#jumpConnections+1]=jumpOverlay.InputBegan:Connect(function(input)
                if input.UserInputType==Enum.UserInputType.Touch then requestJump() end
            end)
        end
    end
    if jumpOverlay and jumpButton and jumpButton.Parent then
        jumpOverlay.Visible=enabled and jumpButton.Visible
        jumpOverlay.Position=UDim2.fromOffset(jumpButton.AbsolutePosition.X,jumpButton.AbsolutePosition.Y)
        jumpOverlay.Size=UDim2.fromOffset(jumpButton.AbsoluteSize.X,jumpButton.AbsoluteSize.Y)
    end
end

connections[#connections+1]=UserInputService.InputBegan:Connect(function(input)
    if not enabled or movementTouch~=nil then return end
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    local p=Vector2.new(input.Position.X,input.Position.Y)
    if acquireMovement(p) then
        movementTouch=input
        movementCaptures += 1
        updateMovement(input.Position)
        refreshKeys(os.clock())
    end
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

syncJumpOverlay()
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
    syncJumpOverlay()
end)

getgenv().PCKeyboardTouchBridgeV5={
    Version="5.1-keyboard-only-no-player-move",
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
        }
    end,
}

getgenv().__PCKeyboardTouchBridgeV5Cleanup=function()
    enabled=false
    releaseMovement()
    pendingJumpDeadline=nil
    pendingSpaceReleaseToken += 1
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    pcall(function() VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Space,false,game) end)
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    clearJumpOverlay()
    pcall(function() gui:Destroy() end)
    getgenv().PCKeyboardTouchBridgeV5=nil
    getgenv().__PCKeyboardTouchBridgeV5Cleanup=nil
end
