local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")

local player=Players.LocalPlayer

-- V23 LEGACY MOUSE BRIDGE
-- Base = the exact V20 checkpoint the user liked.
-- Do NOT use V16/V17 touch-camera wrappers here; this version corrects the actual
-- legacy controller.rotateInput directly, based on Camera X9 V3 measurements.
local oldVirtualMouse=getgenv().PCVirtualMouseEnabled
getgenv().PCVirtualMouseEnabled=false

local src=game:HttpGet(
    "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV20_STABLE.lua?_cb="
    ..HttpService:GenerateGUID(false),true)
local fn,err=loadstring(src)
if not fn then
    getgenv().PCVirtualMouseEnabled=oldVirtualMouse
    error(err)
end
fn()

local stableCleanup=getgenv().__PCMobileAimCleanup
getgenv().PCMovementVersion="V23-LegacyMouseBridge"
getgenv().PCInputBridgeMode="legacy-rotateInput-mouse-ratio"
getgenv().PCInputBridgeDiscovery="activeCameraController.rotateInput"
if getgenv().PCInputBridgeEnabled==nil then getgenv().PCInputBridgeEnabled=true end

-- Measured from Camera X9 V3 on this exact iPhone/Evade session.
local NATIVE_TOUCH_X=0.029688168050806058
local NATIVE_TOUCH_Y=0.010602966305655836

-- Legacy Roblox mouse path constants recovered from the matching RootCamera source.
local PC_MOUSE_X=(math.pi*4)/1920
local PC_MOUSE_Y=(math.pi*1.9)/1200

-- A finger pixel and a mouse count are not physically the same thing.
-- Preserve the already-good V20 horizontal feel and convert ONLY the input geometry
-- to the PC mouse Y/X ratio. This makes the virtual mouse gain deterministic.
local VIRTUAL_MOUSE_GAIN=NATIVE_TOUCH_X/PC_MOUSE_X
local TARGET_X=PC_MOUSE_X*VIRTUAL_MOUSE_GAIN
local TARGET_Y=PC_MOUSE_Y*VIRTUAL_MOUSE_GAIN
local CORRECTION_X=TARGET_X-NATIVE_TOUCH_X
local CORRECTION_Y=TARGET_Y-NATIVE_TOUCH_Y

getgenv().PCLegacyNativeTouchX=NATIVE_TOUCH_X
getgenv().PCLegacyNativeTouchY=NATIVE_TOUCH_Y
getgenv().PCLegacyVirtualMouseGain=VIRTUAL_MOUSE_GAIN
getgenv().PCLegacyTargetMouseX=TARGET_X
getgenv().PCLegacyTargetMouseY=TARGET_Y

local connections={}
local touches={}
local dynamicThumbstickInput=nil
local cachedCameras=nil
local cachedController=nil
local ugs=nil
pcall(function() ugs=UserSettings():GetService("UserGameSettings") end)

local function getController()
    if type(cachedController)=="table" and cachedController.enabled~=false then
        return cachedController
    end

    local ps=player:FindFirstChild("PlayerScripts")
    local pmInst=ps and ps:FindFirstChild("PlayerModule")
    if not pmInst then return nil end

    local pm
    pcall(function() pm=require(pmInst) end)
    if type(pm)~="table" then return nil end

    local cameras
    pcall(function()
        if type(pm.GetCameras)=="function" then cameras=pm:GetCameras()
        else cameras=rawget(pm,"cameras") end
    end)
    if type(cameras)~="table" then return nil end
    cachedCameras=cameras

    local controller=rawget(cameras,"activeCameraController")
    if controller==nil and type(cameras.GetActiveCameraController)=="function" then
        pcall(function() controller=cameras:GetActiveCameraController() end)
    end
    if type(controller)=="table" then cachedController=controller end
    return controller
end

local function isInThumbstickArea(pos)
    local pg=player:FindFirstChildOfClass("PlayerGui")
    local touchGui=pg and pg:FindFirstChild("TouchGui")
    local cf=touchGui and touchGui:FindFirstChild("TouchControlFrame")
    if not cf then return false end

    -- Covers both DynamicThumbstickFrame and older touch thumbstick layouts.
    for _,name in ipairs({"DynamicThumbstickFrame","ThumbstickFrame","TouchThumbstick"}) do
        local f=cf:FindFirstChild(name,true)
        if f and f:IsA("GuiObject") and f.Visible then
            local a=f.AbsolutePosition
            local b=a+f.AbsoluteSize
            if pos.X>=a.X and pos.Y>=a.Y and pos.X<=b.X and pos.Y<=b.Y then
                return true
            end
        end
    end
    return false
end

local function cameraTouchCount()
    local n=0
    for _,isCameraTouch in pairs(touches) do
        if isCameraTouch then n+=1 end
    end
    return n
end

local function invertY()
    local v=1
    if ugs then pcall(function() v=ugs:GetCameraYInvertValue() end) end
    return v
end

local function shouldBridge(controller)
    if getgenv().PCMovementEnabled==false or getgenv().PCInputBridgeEnabled==false then return false end
    if type(controller)~="table" or controller.panEnabled==false then return false end
    if typeof(controller.rotateInput)~="Vector2" then return false end
    if cameraTouchCount()~=1 then return false end
    return true
end

table.insert(connections,UIS.InputBegan:Connect(function(input,gpe)
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    local cameraTouch=(not gpe) and (not isInThumbstickArea(input.Position))
    touches[input]=cameraTouch
    if not cameraTouch and dynamicThumbstickInput==nil and isInThumbstickArea(input.Position) then
        dynamicThumbstickInput=input
    end
end))

table.insert(connections,UIS.InputChanged:Connect(function(input,gpe)
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    if input==dynamicThumbstickInput then return end
    if touches[input]~=true then return end

    local d=input.Delta
    if not d then return end
    local raw=Vector2.new(d.X,d.Y)
    if raw.Magnitude<=0 then return end

    -- Let Roblox/Evade's own touch callback run first, then replace only its
    -- just-added touch geometry with the equivalent PC mouse geometry.
    task.defer(function()
        local controller=getController()
        if not shouldBridge(controller) then return end

        local inv=invertY()
        local correction=Vector2.new(
            raw.X*CORRECTION_X,
            raw.Y*CORRECTION_Y*inv
        )

        -- No CFrame writes. No body lock. Only alter the pending camera rotation
        -- accumulator before the camera consumes it on the next update.
        controller.rotateInput=controller.rotateInput+correction
    end)
end))

table.insert(connections,UIS.InputEnded:Connect(function(input)
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    if input==dynamicThumbstickInput then dynamicThumbstickInput=nil end
    touches[input]=nil
end))

-- Diagnostics for CameraX9 / console.
getgenv().PCLegacyBridgeDiagnostics=function()
    local c=getController()
    return {
        controllerFound=type(c)=="table",
        rotateInput=type(c)=="table" and c.rotateInput or nil,
        panEnabled=type(c)=="table" and c.panEnabled or nil,
        mouseLocked=type(c)=="table" and c.inMouseLockedMode or nil,
        nativeTouch=Vector2.new(NATIVE_TOUCH_X,NATIVE_TOUCH_Y),
        targetMouse=Vector2.new(TARGET_X,TARGET_Y),
        correction=Vector2.new(CORRECTION_X,CORRECTION_Y),
        gain=VIRTUAL_MOUSE_GAIN,
        targetYX=TARGET_Y/TARGET_X,
    }
end

getgenv().__PCMobileAimCleanup=function()
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    touches={}
    dynamicThumbstickInput=nil
    cachedController=nil
    cachedCameras=nil

    getgenv().PCLegacyBridgeDiagnostics=nil
    getgenv().PCVirtualMouseEnabled=oldVirtualMouse
    getgenv().PCInputBridgeMode=nil
    getgenv().PCInputBridgeDiscovery=nil

    if stableCleanup then pcall(stableCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

print(string.format(
    "[V23] Legacy Mouse Bridge active | native=(%.6f, %.6f) target=(%.6f, %.6f) gain=%.3f Y/X=%.2f",
    NATIVE_TOUCH_X,NATIVE_TOUCH_Y,TARGET_X,TARGET_Y,VIRTUAL_MOUSE_GAIN,TARGET_Y/TARGET_X
))
