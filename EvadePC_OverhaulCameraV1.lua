-- Evade PC - Overhaul Camera V1
-- PC-like camera input without replacing Camera.CFrame.
-- 1) keeps absolute sensitivity separate from precision
-- 2) precision only removes tiny cross-axis noise; it never slows the main axis
-- 3) touches that begin on our joystick/jump controls never enter BaseCamera

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local CoreGui=game:GetService("CoreGui")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local ENV=(type(getgenv)=="function" and getgenv()) or _G

local VERSION="EvadePC-OverhaulCamera-V1-axis-clean-native-touch"
local EVADE_GAME_ID=3647333358
local LEGACY_PLACE_ID=96537472072550
local BIND_NAME="__EvadePCOverhaulCameraV1"
local GUI_NAME="EvadePCOverhaulCameraV1Gui"

local AXIS_SNAP_RATIO=0.12
local AXIS_MINOR_MAX=0.006
local MIN_MULTIPLIER=0.1
local MAX_MULTIPLIER=2.0
local MULTIPLIER_STEP=0.1

local previous=ENV.__EvadePCOverhaulCameraV1Cleanup
if type(previous)=="function" then pcall(previous) end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

if game.GameId~=EVADE_GAME_ID or game.PlaceId==LEGACY_PLACE_ID then
    local api={Version=VERSION,Installed=false,Reason="not-overhaul",PlaceId=game.PlaceId}
    ENV.EvadePCOverhaulCameraV1=api
    return api
end

local enabled=true
local precisionEnabled=true
local multiplier=tonumber(ENV.EvadePCOverhaulCameraMultiplier) or 1
multiplier=math.clamp(multiplier,MIN_MULTIPLIER,MAX_MULTIPLIER)

local cameraInput=nil
local originalGetRotation=nil
local rotationWrapper=nil
local playerModule=nil
local cameras=nil
local activeController=nil
local installedHooks={}
local blockedTouches=setmetatable({}, {__mode="k"})
local passedTouches=setmetatable({}, {__mode="k"})
local connections={}
local gui=nil

local filteredFrames=0
local snappedX=0
local snappedY=0
local blockedBegins=0
local blockedChanges=0
local blockedEnds=0
local hookErrors=0
local controllerReinstalls=0

local function cleanAxis(rotation)
    if typeof(rotation)~="Vector2" then
        local ok,result=pcall(function() return rotation*multiplier end)
        return ok and result or rotation
    end

    local x=rotation.X
    local y=rotation.Y

    if enabled and precisionEnabled then
        local ax=math.abs(x)
        local ay=math.abs(y)

        if ax>ay and ay<=AXIS_MINOR_MAX and ax>0 and (ay/ax)<=AXIS_SNAP_RATIO then
            if y~=0 then snappedY+=1 end
            y=0
        elseif ay>ax and ax<=AXIS_MINOR_MAX and ay>0 and (ax/ay)<=AXIS_SNAP_RATIO then
            if x~=0 then snappedX+=1 end
            x=0
        end
    end

    filteredFrames+=1
    return Vector2.new(x,y)*multiplier
end

local function findCameraInputModule()
    local scripts=player:FindFirstChild("PlayerScripts")
    if not scripts then return nil end

    local pm=scripts:FindFirstChild("PlayerModule")
    local cm=pm and pm:FindFirstChild("CameraModule")
    local direct=cm and cm:FindFirstChild("CameraInput")
    if direct and direct:IsA("ModuleScript") then return direct end

    for _,object in ipairs(scripts:GetDescendants()) do
        if object:IsA("ModuleScript") and object.Name=="CameraInput" then
            return object
        end
    end
    return nil
end

local function attachRotation()
    local module=findCameraInputModule()
    if not module then return false end

    local ok,value=pcall(require,module)
    if not ok or type(value)~="table" or type(value.getRotation)~="function" then
        return false
    end

    if cameraInput==value and value.getRotation==rotationWrapper then
        return true
    end

    if cameraInput and originalGetRotation and cameraInput.getRotation==rotationWrapper then
        pcall(function() cameraInput.getRotation=originalGetRotation end)
    end

    local original=value.getRotation
    local function wrapper(...)
        local rotation=original(...)
        if not enabled then return rotation end
        return cleanAxis(rotation)
    end

    cameraInput=value
    originalGetRotation=original
    rotationWrapper=wrapper
    value.getRotation=wrapper
    return true
end

local function getMeta(tbl)
    local mt=nil
    if type(getrawmetatable)=="function" then
        pcall(function() mt=getrawmetatable(tbl) end)
    end
    if type(mt)~="table" then
        pcall(function() mt=getmetatable(tbl) end)
    end
    return type(mt)=="table" and mt or nil
end

local function findMethod(root,name)
    local seen={}
    local function visit(tbl,depth)
        if type(tbl)~="table" or seen[tbl] or depth>14 then return nil end
        seen[tbl]=true

        local own=nil
        pcall(function() own=rawget(tbl,name) end)
        if type(own)=="function" then return {owner=tbl,fn=own,name=name} end

        local index=nil
        pcall(function() index=rawget(tbl,"__index") end)
        if type(index)=="table" then
            local found=visit(index,depth+1)
            if found then return found end
        end

        local mt=getMeta(tbl)
        if mt then
            local found=visit(mt,depth+1)
            if found then return found end
        end
        return nil
    end
    return visit(root,0)
end

local function getCameras()
    if type(cameras)=="table" then return cameras end

    local scripts=player:FindFirstChild("PlayerScripts")
    local pm=scripts and scripts:FindFirstChild("PlayerModule")
    if not pm then return nil end

    if type(playerModule)~="table" then
        pcall(function() playerModule=require(pm) end)
    end
    if type(playerModule)~="table" then return nil end

    pcall(function()
        if type(playerModule.GetCameras)=="function" then
            cameras=playerModule:GetCameras()
        else
            cameras=rawget(playerModule,"cameras")
        end
    end)
    return type(cameras)=="table" and cameras or nil
end

local function getActiveController()
    local cm=getCameras()
    if type(cm)~="table" then return nil end

    local controller=nil
    pcall(function() controller=rawget(cm,"activeCameraController") end)
    if type(controller)~="table" and type(cm.GetActiveCameraController)=="function" then
        pcall(function() controller=cm:GetActiveCameraController() end)
    end
    return type(controller)=="table" and controller or nil
end

local function pointInside(guiObject,position,padding)
    if not guiObject or not guiObject:IsA("GuiObject") or not guiObject.Visible then
        return false
    end
    padding=padding or 0
    local a=guiObject.AbsolutePosition-Vector2.new(padding,padding)
    local b=guiObject.AbsolutePosition+guiObject.AbsoluteSize+Vector2.new(padding,padding)
    return position.X>=a.X and position.Y>=a.Y and position.X<=b.X and position.Y<=b.Y
end

local function findOwnedControl(name)
    for _,guiName in ipairs({
        "EvadePCJoystickV7Gui","EvadePCJoystickV6Gui","EvadePCJoystickV5Gui",
        "EvadePCJoystickV4Gui","EvadePCJoystickV3Gui"
    }) do
        local screen=playerGui:FindFirstChild(guiName)
        local object=screen and screen:FindFirstChild(name,true)
        if object and object:IsA("GuiObject") then return object end
    end
    return nil
end

local function isOwnedTouch(input)
    if not input or input.UserInputType~=Enum.UserInputType.Touch then return false end
    local pos=Vector2.new(input.Position.X,input.Position.Y)
    return pointInside(findOwnedControl("PCJoystick"),pos,8)
        or pointInside(findOwnedControl("PCJump"),pos,8)
end

local function restoreHooks()
    for i=#installedHooks,1,-1 do
        local h=installedHooks[i]
        if h.mode=="hookfunction" and type(hookfunction)=="function" then
            pcall(function() hookfunction(h.target,h.original) end)
        elseif h.mode=="rawset" and type(h.owner)=="table" then
            pcall(function() rawset(h.owner,h.name,h.original) end)
        end
    end
    table.clear(installedHooks)
end

local function installOne(target,factory)
    if not target or type(target.fn)~="function" then
        hookErrors+=1
        return false
    end

    if type(hookfunction)=="function" then
        local original=nil
        local replacement=factory(function(...) return original(...) end)
        local ok,old=pcall(function() return hookfunction(target.fn,replacement) end)
        if ok and type(old)=="function" then
            original=old
            installedHooks[#installedHooks+1]={mode="hookfunction",target=target.fn,original=old}
            return true
        end
    end

    local previousFn=nil
    pcall(function() previousFn=rawget(target.owner,target.name) end)
    if type(previousFn)=="function" then
        local replacement=factory(previousFn)
        local ok=pcall(function() rawset(target.owner,target.name,replacement) end)
        if ok then
            installedHooks[#installedHooks+1]={
                mode="rawset",owner=target.owner,name=target.name,original=previousFn
            }
            return true
        end
    end

    hookErrors+=1
    return false
end

local function installTouchIsolation(controller)
    restoreHooks()
    blockedTouches=setmetatable({}, {__mode="k"})
    passedTouches=setmetatable({}, {__mode="k"})
    if type(controller)~="table" then return false end

    local began=findMethod(controller,"OnInputBegan")
    local changed=findMethod(controller,"OnInputChanged")
    local ended=findMethod(controller,"OnInputEnded")

    local beganOk=installOne(began,function(callOriginal)
        return function(self,input,...)
            if enabled and self==getActiveController()
                and input.UserInputType==Enum.UserInputType.Touch then
                if isOwnedTouch(input) then
                    blockedTouches[input]=true
                    passedTouches[input]=nil
                    blockedBegins+=1
                    return nil
                end
                passedTouches[input]=true
            end
            return callOriginal(self,input,...)
        end
    end)

    local changedOk=installOne(changed,function(callOriginal)
        return function(self,input,...)
            if enabled and self==getActiveController()
                and input.UserInputType==Enum.UserInputType.Touch then
                if blockedTouches[input] then
                    blockedChanges+=1
                    return nil
                end
                if passedTouches[input]~=true and isOwnedTouch(input) then
                    blockedTouches[input]=true
                    blockedChanges+=1
                    return nil
                end
            end
            return callOriginal(self,input,...)
        end
    end)

    local endedOk=installOne(ended,function(callOriginal)
        return function(self,input,...)
            if input.UserInputType==Enum.UserInputType.Touch and blockedTouches[input] then
                blockedTouches[input]=nil
                passedTouches[input]=nil
                blockedEnds+=1
                return nil
            end
            passedTouches[input]=nil
            return callOriginal(self,input,...)
        end
    end)

    controllerReinstalls+=1
    return beganOk and changedOk and endedOk
end

local function setMultiplier(value)
    value=math.clamp(tonumber(value) or 1,MIN_MULTIPLIER,MAX_MULTIPLIER)
    value=math.floor((value/MULTIPLIER_STEP)+0.5)*MULTIPLIER_STEP
    multiplier=math.floor(value*10+0.5)/10
    ENV.EvadePCOverhaulCameraMultiplier=multiplier
    return multiplier
end

-- Compact movable sensitivity UI.
local parent=nil
pcall(function() if type(gethui)=="function" then parent=gethui() end end)
if not parent then parent=CoreGui end

gui=Instance.new("ScreenGui")
gui.Name=GUI_NAME
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=false
gui.Parent=parent

local frame=Instance.new("Frame")
frame.Size=UDim2.fromOffset(238,88)
frame.Position=UDim2.new(0.5,-119,0.14,0)
frame.BackgroundColor3=Color3.fromRGB(24,24,27)
frame.BorderSizePixel=0
frame.Active=true
frame.Parent=gui

local corner=Instance.new("UICorner")
corner.CornerRadius=UDim.new(0,10)
corner.Parent=frame

local title=Instance.new("TextLabel")
title.BackgroundTransparency=1
title.Position=UDim2.fromOffset(10,5)
title.Size=UDim2.new(1,-70,0,26)
title.Text="Camera PC"
title.TextColor3=Color3.new(1,1,1)
title.Font=Enum.Font.GothamSemibold
title.TextSize=14
title.TextXAlignment=Enum.TextXAlignment.Left
title.Parent=frame

local valueLabel=Instance.new("TextLabel")
valueLabel.BackgroundTransparency=1
valueLabel.Position=UDim2.new(1,-62,0,5)
valueLabel.Size=UDim2.fromOffset(52,26)
valueLabel.TextColor3=Color3.new(1,1,1)
valueLabel.Font=Enum.Font.GothamMedium
valueLabel.TextSize=13
valueLabel.TextXAlignment=Enum.TextXAlignment.Right
valueLabel.Parent=frame

local bar=Instance.new("Frame")
bar.Position=UDim2.fromOffset(12,49)
bar.Size=UDim2.new(1,-24,0,8)
bar.BackgroundColor3=Color3.fromRGB(72,72,78)
bar.BorderSizePixel=0
bar.Active=true
bar.Parent=frame

local barCorner=Instance.new("UICorner")
barCorner.CornerRadius=UDim.new(1,0)
barCorner.Parent=bar

local fill=Instance.new("Frame")
fill.BackgroundColor3=Color3.fromRGB(235,235,240)
fill.BorderSizePixel=0
fill.Size=UDim2.fromScale(0,1)
fill.Parent=bar
local fillCorner=Instance.new("UICorner")
fillCorner.CornerRadius=UDim.new(1,0)
fillCorner.Parent=fill

local knob=Instance.new("Frame")
knob.AnchorPoint=Vector2.new(0.5,0.5)
knob.Size=UDim2.fromOffset(18,18)
knob.BackgroundColor3=Color3.fromRGB(250,250,250)
knob.BorderSizePixel=0
knob.Active=true
knob.Parent=bar
local knobCorner=Instance.new("UICorner")
knobCorner.CornerRadius=UDim.new(1,0)
knobCorner.Parent=knob

local function refreshUI()
    local alpha=(multiplier-MIN_MULTIPLIER)/(MAX_MULTIPLIER-MIN_MULTIPLIER)
    fill.Size=UDim2.fromScale(alpha,1)
    knob.Position=UDim2.fromScale(alpha,0.5)
    valueLabel.Text=string.format("%.1fx",multiplier)
end

local function updateFromX(x)
    local width=bar.AbsoluteSize.X
    if width<=0 then return end
    local alpha=math.clamp((x-bar.AbsolutePosition.X)/width,0,1)
    setMultiplier(MIN_MULTIPLIER+(MAX_MULTIPLIER-MIN_MULTIPLIER)*alpha)
    refreshUI()
end

local sliding=false
local slideInput=nil
local dragging=false
local dragInput=nil
local dragStart=nil
local dragPosition=nil

local function beginSlide(input)
    if input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseButton1 then
        sliding=true
        slideInput=input
        updateFromX(input.Position.X)
    end
end

connections[#connections+1]=bar.InputBegan:Connect(beginSlide)
connections[#connections+1]=knob.InputBegan:Connect(beginSlide)

connections[#connections+1]=frame.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseButton1 then
        if input.Position.Y<bar.AbsolutePosition.Y-7 then
            dragging=true
            dragInput=input
            dragStart=input.Position
            dragPosition=frame.Position
        end
    end
end)

connections[#connections+1]=UserInputService.InputChanged:Connect(function(input)
    if sliding and (input==slideInput
        or (slideInput and slideInput.UserInputType==Enum.UserInputType.MouseButton1
            and input.UserInputType==Enum.UserInputType.MouseMovement)) then
        updateFromX(input.Position.X)
    end

    if dragging and dragStart and dragPosition and (input==dragInput
        or (dragInput and dragInput.UserInputType==Enum.UserInputType.MouseButton1
            and input.UserInputType==Enum.UserInputType.MouseMovement)) then
        local delta=input.Position-dragStart
        frame.Position=UDim2.new(
            dragPosition.X.Scale,dragPosition.X.Offset+delta.X,
            dragPosition.Y.Scale,dragPosition.Y.Offset+delta.Y
        )
    end
end)

connections[#connections+1]=UserInputService.InputEnded:Connect(function(input)
    if input==slideInput
        or (slideInput and slideInput.UserInputType==Enum.UserInputType.MouseButton1
            and input.UserInputType==Enum.UserInputType.MouseButton1) then
        sliding=false
        slideInput=nil
    end
    if input==dragInput
        or (dragInput and dragInput.UserInputType==Enum.UserInputType.MouseButton1
            and input.UserInputType==Enum.UserInputType.MouseButton1) then
        dragging=false
        dragInput=nil
        dragStart=nil
        dragPosition=nil
    end
end)

refreshUI()
attachRotation()
activeController=getActiveController()
if activeController then pcall(function() installTouchIsolation(activeController) end) end

RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Camera.Value-6,function()
    if not enabled then return end

    if not cameraInput or cameraInput.getRotation~=rotationWrapper then
        pcall(attachRotation)
    end

    local controller=getActiveController()
    if controller~=activeController then
        activeController=controller
        pcall(function() installTouchIsolation(activeController) end)
    end
end)

local api={
    Version=VERSION,
    Installed=true,
    SetEnabled=function(value)
        enabled=value~=false
        gui.Enabled=enabled
    end,
    SetPrecisionEnabled=function(value)
        precisionEnabled=value~=false
    end,
    SetMultiplier=setMultiplier,
    GetMultiplier=function() return multiplier end,
    GetState=function()
        return {
            enabled=enabled,
            precisionEnabled=precisionEnabled,
            multiplier=multiplier,
            axisSnapRatio=AXIS_SNAP_RATIO,
            axisMinorMax=AXIS_MINOR_MAX,
            filteredFrames=filteredFrames,
            snappedX=snappedX,
            snappedY=snappedY,
            blockedBegins=blockedBegins,
            blockedChanges=blockedChanges,
            blockedEnds=blockedEnds,
            hookErrors=hookErrors,
            controllerReinstalls=controllerReinstalls,
            cameraInputAttached=cameraInput~=nil and cameraInput.getRotation==rotationWrapper,
            activeController=activeController~=nil,
            writesCameraCFrame=false,
            usesTemporalSmoothing=false,
        }
    end,
}

ENV.EvadePCOverhaulCameraV1=api
ENV.__EvadePCOverhaulCameraV1Cleanup=function()
    enabled=false
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    restoreHooks()

    if cameraInput and originalGetRotation and cameraInput.getRotation==rotationWrapper then
        pcall(function() cameraInput.getRotation=originalGetRotation end)
    end

    for _,connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(connections)

    if gui then pcall(function() gui:Destroy() end) end

    ENV.EvadePCOverhaulCameraV1=nil
    ENV.__EvadePCOverhaulCameraV1Cleanup=nil
end

return api
