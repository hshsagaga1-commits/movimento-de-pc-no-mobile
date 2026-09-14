local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local player=Players.LocalPlayer

-- V16 = V15 intact + one camera-only experiment.
-- Keep the proven V15 movement, jump, crouch, FOV, zoom and offset untouched.
local src=game:HttpGet("https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV15.lua?_cb="..HttpService:GenerateGUID(false),true)
local fn,err=loadstring(src)
if not fn then error(err) end
fn()

local v15Cleanup=getgenv().__PCMobileAimCleanup
getgenv().PCMovementVersion="V16"
if getgenv().PCVirtualMouseEnabled==nil then getgenv().PCVirtualMouseEnabled=true end

local userGameSettings
pcall(function() userGameSettings=UserSettings():GetService("UserGameSettings") end)

local cameraInput
local originalGetRotation
local connections={}
local touches={}
local dynamicThumbstickInput=nil
local pendingCameraDelta=Vector2.zero

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

local function adjustedTouchDelta(delta)
    local camera=workspace.CurrentCamera
    if not camera then return delta end
    local pitch=camera.CFrame:ToEulerAnglesYXZ()
    if delta.Y*pitch>=0 then return delta end
    local curveY=1-(2*math.abs(pitch)/math.pi)^0.75
    local sensitivity=curveY*0.75+0.25
    return Vector2.new(delta.X,delta.Y*sensitivity)
end

local function installCameraBridge()
    if cameraInput and originalGetRotation then return true end
    local ps=player:FindFirstChild("PlayerScripts")
    local pm=ps and ps:FindFirstChild("PlayerModule")
    local cm=pm and pm:FindFirstChild("CameraModule")
    local ci=cm and cm:FindFirstChild("CameraInput")
    if not ci then return false end

    local ok,module=pcall(require,ci)
    if not ok or type(module)~="table" or type(module.getRotation)~="function" then return false end

    cameraInput=module
    originalGetRotation=module.getRotation

    module.getRotation=function(...)
        local result=originalGetRotation(...)
        local raw=pendingCameraDelta
        pendingCameraDelta=Vector2.zero

        if getgenv().PCMovementEnabled~=false
            and getgenv().PCVirtualMouseEnabled~=false
            and touchPreferred()
            and typeof(result)=="Vector2"
            and raw.Magnitude>0 then

            -- Roblox mouse and touch use different vertical/horizontal ratios:
            -- mouse = (1, 0.77), touch = (1, 0.66).
            -- Do NOT halve overall sensitivity: physical finger delta and mouse delta
            -- are different devices. Preserve V15 horizontal feel and only convert
            -- the touch Y/X response to the mouse Y/X response.
            -- Also keep Roblox's native touch pitch attenuation; V12 showed removing
            -- that curve made vertical camera behavior worse.
            local adjusted=adjustedTouchDelta(raw)
            local invertY=1
            if userGameSettings then
                pcall(function() invertY=userGameSettings:GetCameraYInvertValue() end)
            end
            local extraY=adjusted.Y*(0.77-0.66)*math.rad(1)*invertY
            result+=Vector2.new(0,extraY)
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
end))

task.spawn(function()
    for _=1,120 do
        if installCameraBridge() then return end
        task.wait(0.1)
    end
end)

getgenv().__PCMobileAimCleanup=function()
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    connections={}
    touches={}
    dynamicThumbstickInput=nil
    pendingCameraDelta=Vector2.zero
    if cameraInput and originalGetRotation then
        pcall(function() cameraInput.getRotation=originalGetRotation end)
    end
    if v15Cleanup then pcall(v15Cleanup) end
    getgenv().__PCMobileAimCleanup=nil
end
