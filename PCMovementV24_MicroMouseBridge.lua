local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")

local player=Players.LocalPlayer

-- V24 MICRO MOUSE BRIDGE
-- Final conservative experiment based on Camera X9 V3 + V23 video.
-- Base = exact V20 checkpoint the user liked.
-- Large swipes remain 100% V20/native touch.
-- Only tiny corrections and quick reversals receive a small PC-mouse-shaped impulse.
-- No Camera.CFrame writes, no RootPart writes, no body constraints, no jump/crouch changes.

local oldVirtualMouse=getgenv().PCVirtualMouseEnabled
getgenv().PCVirtualMouseEnabled=false

local src=game:HttpGet(
    "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV20_STABLE.lua?_cb="
    ..HttpService:GenerateGUID(false),true
)
local fn,err=loadstring(src)
if not fn then
    getgenv().PCVirtualMouseEnabled=oldVirtualMouse
    error(err)
end
fn()

local stableCleanup=getgenv().__PCMobileAimCleanup
getgenv().PCMovementVersion="V24-MicroMouseBridge"
getgenv().PCInputBridgeMode="legacy-rotateInput-micro-only"
getgenv().PCInputBridgeDiscovery="activeCameraController.rotateInput"
if getgenv().PCInputBridgeEnabled==nil then getgenv().PCInputBridgeEnabled=true end

-- Measured by Camera X9 V3 on this exact Evade/iPhone session.
local NATIVE_X=0.029688168050806058
local NATIVE_Y=0.010602966305655836

-- PC legacy mouse Y/X geometry recovered from the matching Roblox RootCamera source.
local PC_MOUSE_YX=0.76

-- Reuse the intended V18 polish strengths, but apply them at the controller that
-- actually exists on-device. These are EXTRA impulses only, not replacement sensitivity.
local MICRO_MAX=0.118      -- +11.8% only at the tiniest packet, tapering to zero
local REVERSE_MAX=0.0708   -- +7.08% on a strong direction reversal
local MICRO_CUTOFF=12      -- pixels; >= this gets no micro boost

getgenv().PCV24NativeX=NATIVE_X
getgenv().PCV24NativeY=NATIVE_Y
getgenv().PCV24MouseRatio=PC_MOUSE_YX
getgenv().PCV24MicroMax=MICRO_MAX
getgenv().PCV24ReverseMax=REVERSE_MAX

local connections={}
local touches={}
local dynamicThumbstickInput=nil
local cachedController=nil
local lastRawDelta=Vector2.zero
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

    local c=rawget(cameras,"activeCameraController")
    if c==nil and type(cameras.GetActiveCameraController)=="function" then
        pcall(function() c=cameras:GetActiveCameraController() end)
    end
    if type(c)=="table" then cachedController=c end
    return c
end

local function isInThumbstickArea(pos)
    local pg=player:FindFirstChildOfClass("PlayerGui")
    local touchGui=pg and pg:FindFirstChild("TouchGui")
    local cf=touchGui and touchGui:FindFirstChild("TouchControlFrame")
    if not cf then return false end

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
    for _,cameraTouch in pairs(touches) do
        if cameraTouch then n+=1 end
    end
    return n
end

local function invertY()
    local v=1
    if ugs then pcall(function() v=ugs:GetCameraYInvertValue() end) end
    return v
end

local function computePolish(raw)
    local mag=raw.Magnitude
    if mag<=0 then
        lastRawDelta=Vector2.zero
        return Vector2.zero,0,0
    end

    -- Micro impulse fades smoothly to zero by 12 px. Large swipes are untouched.
    local micro=0
    if mag<MICRO_CUTOFF then
        micro=MICRO_MAX*(1-math.clamp(mag/MICRO_CUTOFF,0,1))
    end

    -- One small extra impulse when the finger sharply reverses direction.
    local reverse=0
    if lastRawDelta.Magnitude>0.75 and mag>0.75 then
        local dot=lastRawDelta.Unit:Dot(raw.Unit)
        if dot< -0.15 then
            reverse=REVERSE_MAX*math.clamp((-dot-0.15)/0.85,0,1)
        end
    end

    lastRawDelta=raw
    local gain=micro+reverse
    if gain<=0 then return Vector2.zero,micro,reverse end

    -- IMPORTANT: use the PC ratio ONLY for this tiny EXTRA impulse.
    -- Native/V20 rotation remains underneath untouched, avoiding V23's strong vertical bite.
    local inv=invertY()
    local extra=Vector2.new(
        raw.X*NATIVE_X*gain,
        raw.Y*NATIVE_X*PC_MOUSE_YX*gain*inv
    )
    return extra,micro,reverse
end

local function shouldApply(c)
    return getgenv().PCMovementEnabled~=false
        and getgenv().PCInputBridgeEnabled~=false
        and type(c)=="table"
        and c.panEnabled~=false
        and typeof(c.rotateInput)=="Vector2"
        and cameraTouchCount()==1
end

table.insert(connections,UIS.InputBegan:Connect(function(input,gpe)
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    local thumb=isInThumbstickArea(input.Position)
    local cameraTouch=(not gpe) and (not thumb)
    touches[input]=cameraTouch
    if thumb and dynamicThumbstickInput==nil then dynamicThumbstickInput=input end
    if cameraTouch then lastRawDelta=Vector2.zero end
end))

table.insert(connections,UIS.InputChanged:Connect(function(input)
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    if input==dynamicThumbstickInput or touches[input]~=true then return end

    local d=input.Delta
    if not d then return end
    local raw=Vector2.new(d.X,d.Y)
    if raw.Magnitude<=0 then return end

    local extra=computePolish(raw)
    if extra.Magnitude<=0 then return end

    -- Let Evade/Roblox add its native touch rotation first. Then add only our tiny
    -- micro/reversal impulse before the camera update consumes rotateInput.
    task.defer(function()
        local c=getController()
        if shouldApply(c) then
            c.rotateInput=c.rotateInput+extra
        end
    end)
end))

table.insert(connections,UIS.InputEnded:Connect(function(input)
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    if input==dynamicThumbstickInput then dynamicThumbstickInput=nil end
    touches[input]=nil
    if cameraTouchCount()==0 then lastRawDelta=Vector2.zero end
end))

getgenv().PCV24Diagnostics=function()
    local c=getController()
    return {
        controllerFound=type(c)=="table",
        rotateInput=type(c)=="table" and c.rotateInput or nil,
        panEnabled=type(c)=="table" and c.panEnabled or nil,
        mouseLocked=type(c)=="table" and c.inMouseLockedMode or nil,
        native=Vector2.new(NATIVE_X,NATIVE_Y),
        mouseRatio=PC_MOUSE_YX,
        microMax=MICRO_MAX,
        reverseMax=REVERSE_MAX,
        cutoff=MICRO_CUTOFF,
    }
end

getgenv().__PCMobileAimCleanup=function()
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    touches={}
    dynamicThumbstickInput=nil
    cachedController=nil
    lastRawDelta=Vector2.zero

    getgenv().PCV24Diagnostics=nil
    getgenv().PCVirtualMouseEnabled=oldVirtualMouse
    getgenv().PCInputBridgeMode=nil
    getgenv().PCInputBridgeDiscovery=nil

    if stableCleanup then pcall(stableCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

print(string.format(
    "[V24] Micro Mouse Bridge | native=(%.6f, %.6f) micro<=%.1f%% reverse<=%.2f%% cutoff=%dpx",
    NATIVE_X,NATIVE_Y,MICRO_MAX*100,REVERSE_MAX*100,MICRO_CUTOFF
))