local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")
local HttpService=game:GetService("HttpService")

local player=Players.LocalPlayer
local GUARD_BIND="__PCMovementV25RelativeCenterGuard"
local NORMAL_MOUSE_LOCK_OFFSET=Vector3.new(2,0.5,0)

-- V25: TRUE RELATIVE CENTER
--
-- Camera X9 V3 proved this Evade session is NOT using the modern CameraInput module.
-- Touch input lives directly on cameras.activeCameraController:
--   fingerTouches / numUnsunkTouches / panEnabled / rotateInput / input*Conn.
--
-- The important architectural change is here:
--   1) keep Roblox's native touch lifecycle alive (buttons, touch classification, pinch zoom),
--   2) set ONLY controller.panEnabled=false so native touch can no longer rotate the camera,
--   3) treat the camera finger only as relative movement (InputObject.Delta),
--   4) feed that delta directly into controller.rotateInput with the legacy PC mouse formula.
--
-- The finger's absolute screen position never participates in aim. The fixed screen center is
-- the only aiming reference, exactly like a captured/locked mouse. No Camera.CFrame writes,
-- no RootPart writes, no AlignOrientation, no smoothing and no movement-speed changes.

-- Load the exact V20 checkpoint the user liked. Disable the old V16/V17 virtual-camera
-- experiments while loading so V25 is the only camera-input bridge on top of V20.
local previousVirtualMouseEnabled=getgenv().PCVirtualMouseEnabled
getgenv().PCVirtualMouseEnabled=false

local baseSource=game:HttpGet(
    "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV20_STABLE.lua?_cb="
    ..HttpService:GenerateGUID(false),
    true
)
local baseChunk,baseError=loadstring(baseSource)
if not baseChunk then
    getgenv().PCVirtualMouseEnabled=previousVirtualMouseEnabled
    error(baseError)
end
baseChunk()

local baseCleanup=getgenv().__PCMobileAimCleanup

getgenv().PCMovementVersion="V25-TrueRelativeCenter"
getgenv().PCInputBridgeMode="true-relative-center"
getgenv().PCInputBridgeDiscovery="activeCameraController.panEnabled+rotateInput"
if getgenv().PCRelativeCenterEnabled==nil then getgenv().PCRelativeCenterEnabled=true end

-- Camera X9 V3 measured the native touch yaw response on THIS exact device/session.
-- We use it only to choose how many virtual mouse counts one physical touch pixel represents,
-- preserving the already-good V20 horizontal speed while changing the INPUT MODEL to PC mouse.
local X9_NATIVE_TOUCH_X=0.029688168050806058
local X9_NATIVE_TOUCH_Y=0.010602966305655836

-- Matching legacy Roblox PC mouse path:
-- MouseTranslationToAngle(delta) = (delta.X/1920, delta.Y/1200)
-- MOUSE_SENSITIVITY = (4*pi, 1.9*pi)
local PC_MOUSE_X=(math.pi*4)/1920
local PC_MOUSE_Y=(math.pi*1.9)/1200
local DEFAULT_MOUSE_GAIN=X9_NATIVE_TOUCH_X/PC_MOUSE_X

-- Keep these globals live so a later test can tune without making another file/version.
if getgenv().PCRelativeMouseGain==nil then getgenv().PCRelativeMouseGain=DEFAULT_MOUSE_GAIN end
if getgenv().PCRelativeMouseVerticalScale==nil then getgenv().PCRelativeMouseVerticalScale=1 end

getgenv().PCRelativeMouseDefaultGain=DEFAULT_MOUSE_GAIN
getgenv().PCRelativeMouseCoeffX=PC_MOUSE_X
getgenv().PCRelativeMouseCoeffY=PC_MOUSE_Y
getgenv().PCRelativeMouseNativeX=X9_NATIVE_TOUCH_X
getgenv().PCRelativeMouseNativeY=X9_NATIVE_TOUCH_Y
getgenv().PCRelativeMousePCYXRatio=PC_MOUSE_Y/PC_MOUSE_X

local userGameSettings
pcall(function() userGameSettings=UserSettings():GetService("UserGameSettings") end)

local playerModule
local cameras
local activeController
local controllerStates=setmetatable({}, {__mode="k"})
local connections={}
local touches={}
local injectedEvents=0
local injectedDelta=Vector2.zero
local panBypassWorking=false

local function getPlayerModule()
    if type(playerModule)=="table" then return playerModule end
    local ps=player:FindFirstChild("PlayerScripts")
    local pm=ps and ps:FindFirstChild("PlayerModule")
    if not pm then return nil end
    pcall(function()
        local value=require(pm)
        if type(value)=="table" then playerModule=value end
    end)
    return playerModule
end

local function getCameras()
    if type(cameras)=="table" then return cameras end
    local pm=getPlayerModule()
    if type(pm)~="table" then return nil end
    pcall(function()
        if type(pm.GetCameras)=="function" then
            cameras=pm:GetCameras()
        else
            cameras=rawget(pm,"cameras")
        end
    end)
    return cameras
end

local function readActiveController()
    local c=getCameras()
    if type(c)~="table" then return nil end

    local controller=rawget(c,"activeCameraController")
    if type(controller)~="table" and type(c.GetActiveCameraController)=="function" then
        pcall(function() controller=c:GetActiveCameraController() end)
    end
    if type(controller)=="table" then return controller end
    return nil
end

local function rememberController(controller)
    if type(controller)~="table" or controllerStates[controller] then return end
    local state={}
    pcall(function() state.panEnabled=controller.panEnabled end)
    pcall(function() state.inMouseLockedMode=controller.inMouseLockedMode end)
    pcall(function() state.mouseLockOffset=controller.mouseLockOffset end)
    controllerStates[controller]=state
end

local function restoreController(controller)
    local state=controllerStates[controller]
    if not state then return end
    pcall(function()
        if state.panEnabled~=nil then controller.panEnabled=state.panEnabled end
    end)
    pcall(function()
        if state.inMouseLockedMode~=nil then controller.inMouseLockedMode=state.inMouseLockedMode end
    end)
    pcall(function()
        if state.mouseLockOffset~=nil then controller.mouseLockOffset=state.mouseLockOffset end
    end)
end

local function setController(controller)
    if controller==activeController then return end
    if activeController then restoreController(activeController) end
    activeController=controller
    if activeController then rememberController(activeController) end
end

local function bridgeAllowed(controller)
    if getgenv().PCMovementEnabled==false or getgenv().PCRelativeCenterEnabled==false then return false end
    if type(controller)~="table" or controller.enabled==false then return false end
    local camera=Workspace.CurrentCamera
    if not camera or camera.CameraType==Enum.CameraType.Scriptable then return false end
    return true
end

local function applyRelativeCenter(controller)
    if not bridgeAllowed(controller) then
        if controller then restoreController(controller) end
        panBypassWorking=false
        return false
    end

    rememberController(controller)

    -- This is the key. Native OnTouchChanged still runs, keeps finger state and pinch zoom,
    -- but its camera-pan branch cannot add touch rotation while panEnabled is false.
    local wrotePan=false
    pcall(function()
        controller.panEnabled=false
        wrotePan=(controller.panEnabled==false)
    end)
    panBypassWorking=wrotePan

    -- iOS ignores UIS.MouseBehavior=LockCenter, so enforce the controller's logical
    -- mouse-lock state directly. X9 showed these exact fields exist in this controller.
    pcall(function() controller.inMouseLockedMode=true end)
    pcall(function() controller.mouseLockOffset=NORMAL_MOUSE_LOCK_OFFSET end)
    if userGameSettings then
        pcall(function() userGameSettings.RotationType=Enum.RotationType.CameraRelative end)
    end

    getgenv().PCRelativeCenterControllerFound=true
    getgenv().PCRelativeCenterPanBypassed=wrotePan
    return wrotePan
end

local function thumbstickContains(pos)
    local pg=player:FindFirstChildOfClass("PlayerGui")
    local touchGui=pg and pg:FindFirstChild("TouchGui")
    local frame=touchGui and touchGui:FindFirstChild("TouchControlFrame")
    if not frame then return false end

    for _,name in ipairs({"DynamicThumbstickFrame","ThumbstickFrame","TouchThumbstick"}) do
        local obj=frame:FindFirstChild(name,true)
        if obj and obj:IsA("GuiObject") and obj.Visible then
            local a=obj.AbsolutePosition
            local b=a+obj.AbsoluteSize
            if pos.X>=a.X and pos.Y>=a.Y and pos.X<=b.X and pos.Y<=b.Y then
                return true
            end
        end
    end
    return false
end

local function controllerClassifiesAsCameraTouch(controller,input)
    if type(controller)=="table" and type(controller.fingerTouches)=="table" then
        local state=controller.fingerTouches[input]
        if state~=nil then
            return state==false
        end
    end
    return nil
end

local function nativeUnsunkTouchCount(controller)
    if type(controller)=="table" and type(controller.numUnsunkTouches)=="number" then
        return controller.numUnsunkTouches
    end
    if type(controller)=="table" and type(controller.fingerTouches)=="table" then
        local n=0
        for _,processed in pairs(controller.fingerTouches) do
            if processed==false then n+=1 end
        end
        return n
    end
    return nil
end

local function ourCameraTouchCount()
    local n=0
    for _,cameraTouch in pairs(touches) do
        if cameraTouch==true then n+=1 end
    end
    return n
end

local function cameraYInvert()
    local value=1
    if userGameSettings then
        pcall(function() value=userGameSettings:GetCameraYInvertValue() end)
    end
    return value
end

local function injectRelativeMouse(input,gpe)
    local controller=activeController or readActiveController()
    if controller~=activeController then setController(controller) end
    if not controller or not applyRelativeCenter(controller) or not panBypassWorking then return end
    if input.UserInputType~=Enum.UserInputType.Touch then return end

    local nativeClassification=controllerClassifiesAsCameraTouch(controller,input)
    local isCameraTouch
    if nativeClassification~=nil then
        isCameraTouch=nativeClassification
    else
        isCameraTouch=(touches[input]==true) and not gpe
    end
    if not isCameraTouch then return end

    -- Exactly one unsunk camera finger = mouse movement. Two unsunk fingers are left to
    -- Roblox's native pinch-zoom logic; processed/UI/joystick touches never aim.
    local count=nativeUnsunkTouchCount(controller)
    if count==nil then count=ourCameraTouchCount() end
    if count~=1 then return end

    local d=input.Delta
    if not d then return end
    local dx=d.X
    local dy=d.Y
    if math.abs(dx)<1e-6 and math.abs(dy)<1e-6 then return end

    local gain=tonumber(getgenv().PCRelativeMouseGain) or DEFAULT_MOUSE_GAIN
    local yScale=tonumber(getgenv().PCRelativeMouseVerticalScale) or 1
    local invY=cameraYInvert()

    -- Literal legacy-PC mouse angular path, driven by finger DELTA only.
    -- No use of input.Position, viewport size, touch start position, screen edge or gesture origin.
    local relativeRotation=Vector2.new(
        dx*PC_MOUSE_X*gain,
        dy*PC_MOUSE_Y*gain*yScale*invY
    )

    if typeof(controller.rotateInput)~="Vector2" then return end
    controller.rotateInput=controller.rotateInput+relativeRotation

    -- Keep the classic camera's "user recently panned" state coherent without creating
    -- touch drag geometry. The native touch callback also updates its own panning state.
    pcall(function() controller.lastUserPanCamera=tick() end)

    injectedEvents+=1
    injectedDelta+=Vector2.new(dx,dy)
    getgenv().PCRelativeCenterInjectedEvents=injectedEvents
end

-- Controller guard runs before camera update and survives respawns/camera-controller swaps.
pcall(function() RunService:UnbindFromRenderStep(GUARD_BIND) end)
RunService:BindToRenderStep(GUARD_BIND,Enum.RenderPriority.Camera.Value-2,function()
    local controller=readActiveController()
    if controller~=activeController then setController(controller) end

    if controller then
        applyRelativeCenter(controller)
    else
        getgenv().PCRelativeCenterControllerFound=false
        getgenv().PCRelativeCenterPanBypassed=false
        panBypassWorking=false
    end
end)

-- Track touch starts only as a fallback. Whenever possible V25 trusts the controller's own
-- fingerTouches/numUnsunkTouches classification, so the same touches Roblox considers UI/joystick
-- are also ignored by the virtual mouse.
table.insert(connections,UserInputService.InputBegan:Connect(function(input,gpe)
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    touches[input]=(not gpe) and (not thumbstickContains(input.Position))
end))

table.insert(connections,UserInputService.InputChanged:Connect(function(input,gpe)
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    if touches[input]==nil then
        touches[input]=(not gpe) and (not thumbstickContains(input.Position))
    end
    injectRelativeMouse(input,gpe)
end))

table.insert(connections,UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    touches[input]=nil
end))

-- Useful if Camera X9 or the console needs the exact live state after the test.
getgenv().PCRelativeCenterDiagnostics=function()
    local controller=activeController or readActiveController()
    local gain=tonumber(getgenv().PCRelativeMouseGain) or DEFAULT_MOUSE_GAIN
    local yScale=tonumber(getgenv().PCRelativeMouseVerticalScale) or 1
    return {
        version=getgenv().PCMovementVersion,
        controllerFound=type(controller)=="table",
        panEnabled=type(controller)=="table" and controller.panEnabled or nil,
        panBypassed=panBypassWorking,
        inMouseLockedMode=type(controller)=="table" and controller.inMouseLockedMode or nil,
        mouseLockOffset=type(controller)=="table" and controller.mouseLockOffset or nil,
        numUnsunkTouches=type(controller)=="table" and controller.numUnsunkTouches or nil,
        gain=gain,
        verticalScale=yScale,
        mouseCoeff=Vector2.new(PC_MOUSE_X,PC_MOUSE_Y),
        targetRadPerTouchPx=Vector2.new(PC_MOUSE_X*gain,PC_MOUSE_Y*gain*yScale),
        targetYX=(PC_MOUSE_Y*yScale)/PC_MOUSE_X,
        x9NativeRadPerTouchPx=Vector2.new(X9_NATIVE_TOUCH_X,X9_NATIVE_TOUCH_Y),
        injectedEvents=injectedEvents,
        injectedRawDelta=injectedDelta,
    }
end

getgenv().__PCMobileAimCleanup=function()
    pcall(function() RunService:UnbindFromRenderStep(GUARD_BIND) end)
    for _,connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(connections)
    table.clear(touches)

    if activeController then restoreController(activeController) end
    for controller in pairs(controllerStates) do restoreController(controller) end

    getgenv().PCRelativeCenterDiagnostics=nil
    getgenv().PCRelativeCenterControllerFound=nil
    getgenv().PCRelativeCenterPanBypassed=nil
    getgenv().PCRelativeCenterInjectedEvents=nil
    getgenv().PCVirtualMouseEnabled=previousVirtualMouseEnabled

    if baseCleanup then pcall(baseCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

-- Prime once instead of waiting for the first render frame.
local initialController=readActiveController()
setController(initialController)
if initialController then applyRelativeCenter(initialController) end

local initialGain=tonumber(getgenv().PCRelativeMouseGain) or DEFAULT_MOUSE_GAIN
warn(string.format(
    "[V25] TRUE RELATIVE CENTER active | panBypass=%s | gain=%.4f | target=(%.6f, %.6f) rad/touchpx | Y/X=%.3f",
    tostring(panBypassWorking),
    initialGain,
    PC_MOUSE_X*initialGain,
    PC_MOUSE_Y*initialGain*(tonumber(getgenv().PCRelativeMouseVerticalScale) or 1),
    (PC_MOUSE_Y*(tonumber(getgenv().PCRelativeMouseVerticalScale) or 1))/PC_MOUSE_X
))
