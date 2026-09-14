local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")

local player=Players.LocalPlayer

-- V21 PC INPUT BRIDGE
-- Keep V20's proven movement + native hard center, but disable the older V16/V17
-- touch-camera polish while this experiment is active. The bridge below replaces
-- the camera finger's native Touch.Move contribution with Mouse.Movement INSIDE
-- Roblox CameraInput whenever executor upvalue access is available.
local previousVirtualMouseSetting=getgenv().PCVirtualMouseEnabled
getgenv().PCVirtualMouseEnabled=false

local src=game:HttpGet(
    "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV20.lua?_cb="
    ..HttpService:GenerateGUID(false),
    true
)
local fn,err=loadstring(src)
if not fn then
    getgenv().PCVirtualMouseEnabled=previousVirtualMouseSetting
    error(err)
end
fn()

local v20Cleanup=getgenv().__PCMobileAimCleanup
getgenv().PCMovementVersion="V21-InputBridge"
if getgenv().PCInputBridgeEnabled==nil then getgenv().PCInputBridgeEnabled=true end
-- Roblox mouse rotates at 0.5 deg/pixel while touch uses 1 deg/pixel horizontally.
-- x2 preserves the V20 horizontal feel while routing through the real mouse path.
if getgenv().PCInputBridgeSensitivity==nil then getgenv().PCInputBridgeSensitivity=2.0 end
getgenv().PCInputBridgeMode="initializing"

local connections={}
local touches={}
local dynamicThumbstickInput=nil
local latestCameraDelta=Vector2.zero
local cameraInput
local previousGetRotation
local touchState
local mouseState
local userGameSettings

pcall(function()
    userGameSettings=UserSettings():GetService("UserGameSettings")
end)

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

local function cameraTouchCount()
    local n=0
    for _,sunk in pairs(touches) do
        if sunk==false then n+=1 end
    end
    return n
end

-- Different executors expose Luau upvalues differently. Normalize the common APIs.
local function getUpvalueValues(f)
    local out={}

    if debug and type(debug.getupvalues)=="function" then
        local ok,res=pcall(debug.getupvalues,f)
        if ok and type(res)=="table" then
            for _,v in pairs(res) do table.insert(out,v) end
        end
    end

    if #out==0 and type(getupvalues)=="function" then
        local ok,res=pcall(getupvalues,f)
        if ok and type(res)=="table" then
            for _,v in pairs(res) do table.insert(out,v) end
        end
    end

    if #out==0 and debug and type(debug.getupvalue)=="function" then
        for i=1,64 do
            local ok,a,b=pcall(debug.getupvalue,f,i)
            if not ok then break end
            if a==nil and b==nil then break end
            local value
            if type(a)=="string" then value=b else value=a end
            if value~=nil then table.insert(out,value) end
        end
    end

    if #out==0 and type(getupvalue)=="function" then
        for i=1,64 do
            local ok,a,b=pcall(getupvalue,f,i)
            if not ok then break end
            if a==nil and b==nil then break end
            local value
            if type(a)=="string" then value=b else value=a end
            if value~=nil then table.insert(out,value) end
        end
    end

    return out
end

local visited={}
local function scanFunction(f,depth)
    if type(f)~="function" or visited[f] or depth>10 then return end
    visited[f]=true

    for _,v in ipairs(getUpvalueValues(f)) do
        if type(v)=="table" then
            if not touchState
                and typeof(rawget(v,"Move"))=="Vector2"
                and type(rawget(v,"Pinch"))=="number"
                and rawget(v,"Movement")==nil then
                touchState=v
            end

            if not mouseState
                and typeof(rawget(v,"Movement"))=="Vector2"
                and typeof(rawget(v,"Pan"))=="Vector2"
                and type(rawget(v,"Wheel"))=="number"
                and type(rawget(v,"Pinch"))=="number" then
                mouseState=v
            end
        elseif type(v)=="function" then
            scanFunction(v,depth+1)
        end
    end
end

local function findCameraInput()
    local ps=player:FindFirstChild("PlayerScripts")
    local pm=ps and ps:FindFirstChild("PlayerModule")
    local cm=pm and pm:FindFirstChild("CameraModule")
    local ci=cm and cm:FindFirstChild("CameraInput")
    if not ci then return nil end

    local ok,module=pcall(require,ci)
    if ok and type(module)=="table" and type(module.getRotation)=="function" then
        return module
    end
    return nil
end

local function manualMouseContribution(raw)
    local scale=tonumber(getgenv().PCInputBridgeSensitivity) or 2.0
    local invertY=1
    if userGameSettings then
        pcall(function() invertY=userGameSettings:GetCameraYInvertValue() end)
    end
    -- Exact public Roblox mouse constants: (1, 0.77) * rad(0.5).
    return Vector2.new(
        raw.X*scale*math.rad(0.5),
        raw.Y*scale*0.77*math.rad(0.5)*invertY
    )
end

local function installBridge()
    if cameraInput and previousGetRotation then return true end

    cameraInput=findCameraInput()
    if not cameraInput then return false end

    previousGetRotation=cameraInput.getRotation
    visited={}
    touchState=nil
    mouseState=nil
    scanFunction(previousGetRotation,0)

    if not touchState then
        -- Cannot safely suppress the native touch contribution: leave V20 intact.
        getgenv().PCInputBridgeMode="fallback-v20"
        warn("[PC Input Bridge] CameraInput touchState not accessible; using V20 fallback")
        cameraInput=nil
        previousGetRotation=nil
        return true
    end

    if mouseState then
        getgenv().PCInputBridgeMode="native-mouse-state"
    else
        getgenv().PCInputBridgeMode="manual-mouse-math"
    end

    cameraInput.getRotation=function(...)
        local bridgeActive=getgenv().PCMovementEnabled~=false
            and getgenv().PCInputBridgeEnabled~=false
            and touchPreferred()
            and cameraTouchCount()==1

        if not bridgeActive then
            latestCameraDelta=Vector2.zero
            return previousGetRotation(...)
        end

        local raw=latestCameraDelta
        latestCameraDelta=Vector2.zero

        -- Kill ONLY the one-finger camera pan. Pinch remains native for zoom.
        touchState.Move=Vector2.zero

        if mouseState then
            -- This is the real mini-emulator path: feed the finger delta into the
            -- exact mouseState table consumed by Roblox CameraInput.getRotation().
            local oldMouse=mouseState.Movement
            local scale=tonumber(getgenv().PCInputBridgeSensitivity) or 2.0
            mouseState.Movement=oldMouse+(raw*scale)
            local result=previousGetRotation(...)
            mouseState.Movement=oldMouse
            return result
        end

        -- Executor exposed touchState but not mouseState. Still suppress native touch
        -- and add the exact public mouse formula after Roblox handles every other input.
        local result=previousGetRotation(...)
        if typeof(result)=="Vector2" and raw.Magnitude>0 then
            result+=manualMouseContribution(raw)
        end
        return result
    end

    print("[PC Input Bridge] active mode:",getgenv().PCInputBridgeMode)
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

    -- MouseMovement keeps the latest pointer delta rather than touch's accumulated pan.
    -- Mirroring that temporal behavior is part of the PC feel.
    if cameraTouchCount()==1 and touches[input]==false then
        local d=input.Delta
        latestCameraDelta=Vector2.new(d.X,d.Y)
    end
end))

table.insert(connections,UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    if input==dynamicThumbstickInput then dynamicThumbstickInput=nil end
    touches[input]=nil
    if cameraTouchCount()==0 then latestCameraDelta=Vector2.zero end
end))

task.spawn(function()
    for _=1,120 do
        if installBridge() then return end
        task.wait(0.1)
    end
    getgenv().PCInputBridgeMode="fallback-v20"
    warn("[PC Input Bridge] CameraInput not found; using V20 fallback")
end)

getgenv().__PCMobileAimCleanup=function()
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    touches={}
    dynamicThumbstickInput=nil
    latestCameraDelta=Vector2.zero

    if cameraInput and previousGetRotation then
        pcall(function() cameraInput.getRotation=previousGetRotation end)
    end

    getgenv().PCVirtualMouseEnabled=previousVirtualMouseSetting
    getgenv().PCInputBridgeMode=nil

    if v20Cleanup then pcall(v20Cleanup) end
    getgenv().__PCMobileAimCleanup=nil
end
