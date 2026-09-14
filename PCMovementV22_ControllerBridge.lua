local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")

local player=Players.LocalPlayer

-- V22: same stable V20 base, but discover the ACTUAL CameraInput table through
-- the active camera controller used by this client build. V21's fixed instance
-- path was not exposed on-device, as confirmed by CameraX9.
local previousVirtualMouseSetting=getgenv().PCVirtualMouseEnabled
getgenv().PCVirtualMouseEnabled=false

local src=game:HttpGet(
    "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV20_STABLE.lua?_cb="
    ..HttpService:GenerateGUID(false),true)
local fn,err=loadstring(src)
if not fn then
    getgenv().PCVirtualMouseEnabled=previousVirtualMouseSetting
    error(err)
end
fn()

local stableCleanup=getgenv().__PCMobileAimCleanup
getgenv().PCMovementVersion="V22-ControllerBridge"
if getgenv().PCInputBridgeEnabled==nil then getgenv().PCInputBridgeEnabled=true end
if getgenv().PCInputBridgeSensitivity==nil then getgenv().PCInputBridgeSensitivity=2.0 end
getgenv().PCInputBridgeMode="initializing"
getgenv().PCInputBridgeDiscovery="none"

local connections={}
local touches={}
local dynamicThumbstickInput=nil
local latestCameraDelta=Vector2.zero
local cameraInput=nil
local previousGetRotation=nil
local touchState=nil
local mouseState=nil
local userGameSettings=nil
pcall(function() userGameSettings=UserSettings():GetService("UserGameSettings") end)

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

local function getUpvalueValues(f)
    local out={}
    if type(f)~="function" then return out end

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

    local single=(debug and debug.getupvalue) or getupvalue
    if #out==0 and type(single)=="function" then
        for i=1,80 do
            local ok,a,b=pcall(single,f,i)
            if not ok or (a==nil and b==nil) then break end
            local value=(type(a)=="string") and b or a
            if value~=nil then table.insert(out,value) end
        end
    end

    return out
end

local function looksLikeCameraInput(t)
    return type(t)=="table"
        and type(rawget(t,"getRotation"))=="function"
        and (type(rawget(t,"getZoomDelta"))=="function" or type(rawget(t,"getRotationActivated"))=="function")
end

local function getPlayerCameraObjects()
    local ps=player:FindFirstChild("PlayerScripts")
    local pmInst=ps and ps:FindFirstChild("PlayerModule")
    if not pmInst then return nil,nil,nil end

    local playerModule
    pcall(function() playerModule=require(pmInst) end)
    if type(playerModule)~="table" then return nil,nil,nil end

    local cameras
    pcall(function()
        if type(playerModule.GetCameras)=="function" then cameras=playerModule:GetCameras()
        else cameras=rawget(playerModule,"cameras") end
    end)
    if type(cameras)~="table" then return playerModule,nil,nil end

    -- CameraX9 proved this build exposes activeCameraController as a direct field.
    local controller=rawget(cameras,"activeCameraController")
    if controller==nil then
        pcall(function()
            if type(cameras.GetActiveCameraController)=="function" then
                controller=cameras:GetActiveCameraController()
            end
        end)
    end
    return playerModule,cameras,controller
end

local function findCameraInputFromController(controller)
    if type(controller)~="table" then return nil,"controller-not-table" end

    -- Some builds may expose it directly on the controller or its metatable.
    for _,root in ipairs({controller,getmetatable(controller)}) do
        if type(root)=="table" then
            for _,v in pairs(root) do
                if looksLikeCameraInput(v) then return v,"controller-table" end
            end
        end
    end

    local visitedFns={}
    local visitedTables={}
    local function walk(value,depth)
        if depth>12 then return nil end

        if looksLikeCameraInput(value) then return value end

        if type(value)=="function" then
            if visitedFns[value] then return nil end
            visitedFns[value]=true
            for _,uv in ipairs(getUpvalueValues(value)) do
                local found=walk(uv,depth+1)
                if found then return found end
            end
        elseif type(value)=="table" then
            if visitedTables[value] then return nil end
            visitedTables[value]=true
            for _,v in pairs(value) do
                if type(v)=="function" or type(v)=="table" then
                    local found=walk(v,depth+1)
                    if found then return found end
                end
            end
            local mt=getmetatable(value)
            if type(mt)=="table" then
                local found=walk(mt,depth+1)
                if found then return found end
            end
        end
        return nil
    end

    -- Prefer Update first: ClassicCamera's Update closure normally references CameraInput.
    local updateFn=controller.Update
    if type(updateFn)=="function" then
        local found=walk(updateFn,0)
        if found then return found,"controller.Update-upvalues" end
    end

    local found=walk(controller,0)
    if found then return found,"controller-recursive" end
    return nil,"not-found"
end

local function findInputStates(getRotation)
    local foundTouch,foundMouse=nil,nil
    local visitedFns={}
    local visitedTables={}

    local function walk(v,depth)
        if depth>10 then return end
        if type(v)=="function" then
            if visitedFns[v] then return end
            visitedFns[v]=true
            for _,uv in ipairs(getUpvalueValues(v)) do walk(uv,depth+1) end
        elseif type(v)=="table" then
            if visitedTables[v] then return end
            visitedTables[v]=true

            if not foundTouch
                and typeof(rawget(v,"Move"))=="Vector2"
                and type(rawget(v,"Pinch"))=="number"
                and rawget(v,"Movement")==nil then
                foundTouch=v
            end

            if not foundMouse
                and typeof(rawget(v,"Movement"))=="Vector2"
                and typeof(rawget(v,"Pan"))=="Vector2"
                and type(rawget(v,"Wheel"))=="number"
                and type(rawget(v,"Pinch"))=="number" then
                foundMouse=v
            end

            for _,child in pairs(v) do
                if type(child)=="function" or type(child)=="table" then walk(child,depth+1) end
            end
        end
    end

    walk(getRotation,0)
    return foundTouch,foundMouse
end

local function manualMouseContribution(raw)
    local scale=tonumber(getgenv().PCInputBridgeSensitivity) or 2.0
    local invertY=1
    if userGameSettings then pcall(function() invertY=userGameSettings:GetCameraYInvertValue() end) end
    return Vector2.new(
        raw.X*scale*math.rad(0.5),
        raw.Y*scale*0.77*math.rad(0.5)*invertY
    )
end

local function installBridge()
    if cameraInput and previousGetRotation then return true end

    local _,cameras,controller=getPlayerCameraObjects()
    if type(cameras)~="table" then return false end

    local ci,where=findCameraInputFromController(controller)
    if not ci then
        getgenv().PCInputBridgeDiscovery=where or "not-found"
        return false
    end

    cameraInput=ci
    previousGetRotation=ci.getRotation
    getgenv().PCInputBridgeDiscovery=where

    touchState,mouseState=findInputStates(previousGetRotation)
    if not touchState then
        getgenv().PCInputBridgeMode="cameraInput-found-touchState-hidden"
        warn("[V22] CameraInput found via "..tostring(where)..", but touchState is hidden; stable V20 behavior kept")
        cameraInput=nil
        previousGetRotation=nil
        return true
    end

    getgenv().PCInputBridgeMode=mouseState and "native-mouse-state" or "manual-mouse-math"

    ci.getRotation=function(...)
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

        -- Suppress the camera finger's native Touch.Move contribution only.
        touchState.Move=Vector2.zero

        if mouseState then
            -- True bridge: feed finger delta into CameraInput's actual mouse state.
            local old=mouseState.Movement
            local scale=tonumber(getgenv().PCInputBridgeSensitivity) or 2.0
            mouseState.Movement=old+(raw*scale)
            local result=previousGetRotation(...)
            mouseState.Movement=old
            return result
        end

        local result=previousGetRotation(...)
        if typeof(result)=="Vector2" and raw.Magnitude>0 then
            result+=manualMouseContribution(raw)
        end
        return result
    end

    print("[V22] PC Input Bridge active:",getgenv().PCInputBridgeMode,"via",getgenv().PCInputBridgeDiscovery)
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
    if cameraTouchCount()==1 and touches[input]==false then
        local d=input.Delta
        -- Intentionally latest packet, matching CameraInput mouseState.Movement semantics.
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
    warn("[V22] CameraInput still not discoverable; stable V20 behavior kept. Discovery="..tostring(getgenv().PCInputBridgeDiscovery))
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
    getgenv().PCInputBridgeDiscovery=nil

    if stableCleanup then pcall(stableCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end
