local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local player=Players.LocalPlayer

-- V17 FINAL POLISH
-- V16 stays intact. This layer only sharpens tiny camera corrections and fast reversals.
-- No movement, jump, crouch, FOV, zoom, camera distance or shift-lock changes here.
local src=game:HttpGet("https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV16.lua?_cb="..HttpService:GenerateGUID(false),true)
local fn,err=loadstring(src)
if not fn then error(err) end
fn()

local v16Cleanup=getgenv().__PCMobileAimCleanup
getgenv().PCMovementVersion="V17"

if getgenv().PCMouseMicroPolishEnabled==nil then getgenv().PCMouseMicroPolishEnabled=true end
if getgenv().PCMouseMicroBoost==nil then getgenv().PCMouseMicroBoost=0.10 end
if getgenv().PCMouseReverseBoost==nil then getgenv().PCMouseReverseBoost=0.06 end

local userGameSettings
pcall(function() userGameSettings=UserSettings():GetService("UserGameSettings") end)

local cameraInput
local previousGetRotation
local connections={}
local touches={}
local dynamicThumbstickInput=nil
local pendingCameraDelta=Vector2.zero
local lastRawDelta=Vector2.zero

local function touchPreferred()
    local preferred=false
    local ok=pcall(function()
        preferred=UserInputService.PreferredInput==Enum.PreferredInput.Touch
    end)
    if ok then return preferred end
    return UserInputService.TouchEnabled
end

local function isInDynamicThumbstickArea(pos)
    local pg=player:FindFirstChildOfClass("PlayerGui")
    local touchGui=pg and pg:FindFirstChild("TouchGui")
    local touchFrame=touchGui and touchGui:FindFirstChild("TouchControlFrame")
    local frame=touchFrame and touchFrame:FindFirstChild("DynamicThumbstickFrame")
    if not frame or not touchGui.Enabled then return false end
    local a=frame.AbsolutePosition
    local b=a+frame.AbsoluteSize
    return pos.X>=a.X and pos.Y>=a.Y and pos.X<=b.X and pos.Y<=b.Y
end

local function unsunkTouchCount()
    local n=0
    for _,sunk in pairs(touches) do
        if sunk==false then n+=1 end
    end
    return n
end

-- Preserve the native Roblox touch pitch attenuation.
-- V12 showed that removing this curve made the camera worse.
local function adjustedTouchDelta(delta)
    local camera=workspace.CurrentCamera
    if not camera then return delta end
    local pitch=camera.CFrame:ToEulerAnglesYXZ()
    if delta.Y*pitch>=0 then return delta end
    local curveY=1-(2*math.abs(pitch)/math.pi)^0.75
    local sensitivity=curveY*0.75+0.25
    return Vector2.new(delta.X,delta.Y*sensitivity)
end

local function buildMicroCorrection(raw)
    local mag=raw.Magnitude
    if mag<=0 then
        lastRawDelta=Vector2.zero
        return Vector2.zero
    end

    -- Tiny swipes get a small extra impulse so camera corrections start/stop more like mouse input.
    -- Large swipes get essentially no extra gain, preserving V16's proven overall sensitivity.
    local microBoost=0
    local maxMicro=tonumber(getgenv().PCMouseMicroBoost) or 0.10
    if mag<12 then
        microBoost=maxMicro*(1-math.clamp(mag/12,0,1))
    end

    -- A quick direction reversal gets one small extra impulse.
    -- This targets the mouse-like "tap back" correction without adding smoothing or inertia.
    local reverseBoost=0
    if lastRawDelta.Magnitude>0.75 and mag>0.75 then
        local dot=lastRawDelta.Unit:Dot(raw.Unit)
        if dot< -0.15 then
            local maxReverse=tonumber(getgenv().PCMouseReverseBoost) or 0.06
            reverseBoost=maxReverse*math.clamp((-dot-0.15)/0.85,0,1)
        end
    end

    lastRawDelta=raw
    local gain=microBoost+reverseBoost
    if gain<=0 then return Vector2.zero end

    local adjusted=adjustedTouchDelta(raw)
    local invertY=1
    if userGameSettings then
        pcall(function() invertY=userGameSettings:GetCameraYInvertValue() end)
    end

    -- V16 already matches the touch camera's Y/X ratio to Roblox's mouse ratio (0.77).
    -- Use the same ratio for this tiny temporal correction so it does not bend the aim path.
    return Vector2.new(
        adjusted.X*math.rad(1),
        adjusted.Y*0.77*math.rad(1)*invertY
    )*gain
end

local function installCameraPolish()
    if cameraInput and previousGetRotation then return true end

    local ps=player:FindFirstChild("PlayerScripts")
    local pm=ps and ps:FindFirstChild("PlayerModule")
    local cm=pm and pm:FindFirstChild("CameraModule")
    local ci=cm and cm:FindFirstChild("CameraInput")
    if not ci then return false end

    local ok,module=pcall(require,ci)
    if not ok or type(module)~="table" or type(module.getRotation)~="function" then return false end

    cameraInput=module
    previousGetRotation=module.getRotation -- this is V16's camera wrapper

    module.getRotation=function(...)
        local result=previousGetRotation(...)
        local raw=pendingCameraDelta
        pendingCameraDelta=Vector2.zero

        if getgenv().PCMovementEnabled~=false
            and getgenv().PCVirtualMouseEnabled~=false
            and getgenv().PCMouseMicroPolishEnabled~=false
            and touchPreferred()
            and typeof(result)=="Vector2"
            and raw.Magnitude>0 then
            result+=buildMicroCorrection(raw)
        else
            lastRawDelta=Vector2.zero
        end

        return result
    end

    return true
end

table.insert(connections,UserInputService.InputBegan:Connect(function(input,gpe)
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    if dynamicThumbstickInput==nil and not gpe and isInDynamicThumbstickArea(input.Position) then
        dynamicThumbstickInput=input
        return
    end
    touches[input]=gpe and true or false
end))

table.insert(connections,UserInputService.InputChanged:Connect(function(input,gpe)
    if input.UserInputType~=Enum.UserInputType.Touch or input==dynamicThumbstickInput then return end
    if touches[input]==nil then touches[input]=gpe and true or false end
    if unsunkTouchCount()==1 and touches[input]==false then
        local d=input.Delta
        pendingCameraDelta+=Vector2.new(d.X,d.Y)
    end
end))

table.insert(connections,UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    if input==dynamicThumbstickInput then dynamicThumbstickInput=nil end
    touches[input]=nil
    if unsunkTouchCount()==0 then
        pendingCameraDelta=Vector2.zero
        lastRawDelta=Vector2.zero
    end
end))

task.spawn(function()
    for _=1,120 do
        if installCameraPolish() then return end
        task.wait(0.1)
    end
end)

getgenv().__PCMobileAimCleanup=function()
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    connections={}
    touches={}
    dynamicThumbstickInput=nil
    pendingCameraDelta=Vector2.zero
    lastRawDelta=Vector2.zero

    if cameraInput and previousGetRotation then
        pcall(function() cameraInput.getRotation=previousGetRotation end)
    end

    if v16Cleanup then pcall(v16Cleanup) end
    getgenv().__PCMobileAimCleanup=nil
end
