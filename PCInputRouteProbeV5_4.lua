local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local GUI_NAME="PCInputRouteProbeV54"
local BIND_NAME="__PCInputRouteProbeV54"

local oldCleanup=getgenv().__PCInputRouteProbeV54Cleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
local oldGui=playerGui:FindFirstChild(GUI_NAME)
if oldGui then oldGui:Destroy() end

local playerModule=nil
local controls=nil
pcall(function()
    local scripts=player:FindFirstChild("PlayerScripts")
    local moduleScript=scripts and scripts:FindFirstChild("PlayerModule")
    if moduleScript then playerModule=require(moduleScript) end
    if type(playerModule)=="table" then
        if type(playerModule.GetControls)=="function" then controls=playerModule:GetControls() end
        if type(controls)~="table" then controls=rawget(playerModule,"controls") end
    end
end)

local keyboardBegins=0
local keyboardEnds=0
local spaceBegins=0
local spaceEnds=0
local touchBegins=0
local lastKeyboard="-"
local connections={}

local function isMovementKey(code)
    return code==Enum.KeyCode.W or code==Enum.KeyCode.A or code==Enum.KeyCode.S or code==Enum.KeyCode.D
end

connections[#connections+1]=UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch then
        touchBegins+=1
    elseif input.UserInputType==Enum.UserInputType.Keyboard then
        if isMovementKey(input.KeyCode) then
            keyboardBegins+=1
            lastKeyboard=input.KeyCode.Name.."+"
        elseif input.KeyCode==Enum.KeyCode.Space then
            spaceBegins+=1
            lastKeyboard="Space+"
        end
    end
end)

connections[#connections+1]=UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Keyboard then
        if isMovementKey(input.KeyCode) then
            keyboardEnds+=1
            lastKeyboard=input.KeyCode.Name.."-"
        elseif input.KeyCode==Enum.KeyCode.Space then
            spaceEnds+=1
            lastKeyboard="Space-"
        end
    end
end)

local gui=Instance.new("ScreenGui")
gui.Name=GUI_NAME
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.DisplayOrder=10050
gui.Parent=playerGui

local label=Instance.new("TextLabel")
label.Name="Route"
label.BackgroundColor3=Color3.new(0,0,0)
label.BackgroundTransparency=0.22
label.TextColor3=Color3.new(1,1,1)
label.BorderSizePixel=0
label.Position=UDim2.fromOffset(8,34)
label.Size=UDim2.fromOffset(900,25)
label.Font=Enum.Font.Code
label.TextSize=12
label.TextXAlignment=Enum.TextXAlignment.Left
label.Text=" PROBE waiting..."
label.Parent=gui

local function magnitudeText(v)
    if typeof(v)=="Vector3" then return string.format("%.2f",v.Magnitude) end
    return "?"
end

RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Last.Value,function()
    local bridgeState={}
    local bridge=getgenv().PCKeyboardTouchBridgeV52
    if type(bridge)=="table" and type(bridge.GetState)=="function" then
        local ok,state=pcall(bridge.GetState)
        if ok and type(state)=="table" then bridgeState=state end
    end

    local activeModule=nil
    local activeController=nil
    local controllerEnabled="?"
    local controlMove=nil
    local controllerMove=nil
    if type(controls)=="table" then
        pcall(function() activeModule=rawget(controls,"activeControlModule") end)
        pcall(function() activeController=rawget(controls,"activeController") end)
        pcall(function()
            if type(controls.GetMoveVector)=="function" then controlMove=controls:GetMoveVector() end
        end)
    end
    if type(activeController)=="table" then
        pcall(function()
            local e=rawget(activeController,"enabled")
            if e==nil then e=rawget(activeController,"Enabled") end
            controllerEnabled=tostring(e)
        end)
        pcall(function()
            if type(activeController.GetMoveVector)=="function" then controllerMove=activeController:GetMoveVector() end
        end)
    end

    local humMove=nil
    local character=player.Character
    local hum=character and character:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() humMove=hum.MoveDirection end) end

    local lastInput="?"
    pcall(function() lastInput=UserInputService:GetLastInputType().Name end)

    local lockState="?"
    local lock=getgenv().PCModeLock
    if type(lock)=="table" and type(lock.GetState)=="function" then
        local ok,state=pcall(lock.GetState)
        if ok and type(state)=="table" then
            lockState=string.format("fac=%s lock=%s blocked=%s",tostring(state.facadeInstalled),tostring(state.switchLockInstalled),tostring(state.blockedTouchSwitches))
        end
    end

    label.Text=string.format(
        " J:%s cap:%s upd:%s send:%s | UISkey:%d/%d space:%d/%d lastKey:%s | ctrlEn:%s cMV:%s aMV:%s hum:%s last:%s | jump:%s/%s | %s",
        tostring(bridgeState.chord or "-"),tostring(bridgeState.movementCaptures or 0),tostring(bridgeState.movementUpdates or 0),tostring(bridgeState.keyEvents or 0),
        keyboardBegins,keyboardEnds,spaceBegins,spaceEnds,lastKeyboard,controllerEnabled,magnitudeText(controlMove),magnitudeText(controllerMove),magnitudeText(humMove),lastInput,
        tostring(bridgeState.jumpRequests or 0),tostring(bridgeState.jumpPulses or 0),lockState
    )
end)

getgenv().__PCInputRouteProbeV54Cleanup=function()
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    pcall(function() gui:Destroy() end)
    getgenv().__PCInputRouteProbeV54Cleanup=nil
end
