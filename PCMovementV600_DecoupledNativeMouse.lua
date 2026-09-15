local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local WATCH_BIND="__PCMovementV600NativeMouseWatch"

--[[
    V600 / DECOUPLED NATIVE MOUSE PATH

    V500 proved that MovementRelative + camera-only mouse lock removes most of
    V26's character/camera coupling. V600 keeps that entire foundation and
    changes only the camera input path:

      touch delta -> proven Legacy camera InputChanged callback as MouseMovement

    Unlike V26, this layer NEVER calls UpdateMouseBehavior and NEVER selects
    CameraRelative. The proxy also reports the viewport center as Position, so
    every packet behaves like a centered relative-mouse packet instead of a
    touch-orbit position.

    If the exact camera callback cannot be proven, the executor lacks the hook
    APIs, or the proxy does not change Legacy rotateInput, V600 fails open to
    untouched V500 touch camera behavior.
]]

local baseSource=game:HttpGet(
    "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV500_ScrapFusion.lua?_cb="
    ..HttpService:GenerateGUID(false),
    true
)
local baseChunk,baseError=loadstring(baseSource)
if not baseChunk then error(baseError) end
baseChunk()

local baseCleanup=getgenv().__PCMobileAimCleanup

pcall(function() RunService:UnbindFromRenderStep(WATCH_BIND) end)

getgenv().PCMovementVersion="V600-DecoupledNativeMouse"
getgenv().PCInputBridgeMode="v600-initializing-over-v500"
getgenv().PCInputBridgeDiscovery="pending"

if getgenv().PCV600MouseRelayEnabled==nil then getgenv().PCV600MouseRelayEnabled=true end
if getgenv().PCV600AutoFallback==nil then getgenv().PCV600AutoFallback=true end

-- X9 measured the real V20 angular response in the active Legacy controller.
-- These gains preserve that response while changing semantics/path only.
local V20_TOUCH_RAD_X=0.029688168050806058
local V20_TOUCH_RAD_Y=0.010602966305655836
local LEGACY_MOUSE_RAD_X=(math.pi*4)/1920
local LEGACY_MOUSE_RAD_Y=(math.pi*1.9)/1200
local DEFAULT_GAIN_X=V20_TOUCH_RAD_X/LEGACY_MOUSE_RAD_X
local DEFAULT_GAIN_Y=V20_TOUCH_RAD_Y/LEGACY_MOUSE_RAD_Y

if getgenv().PCV600MouseGainX==nil then getgenv().PCV600MouseGainX=DEFAULT_GAIN_X end
if getgenv().PCV600MouseGainY==nil then getgenv().PCV600MouseGainY=DEFAULT_GAIN_Y end

local userGameSettings
pcall(function() userGameSettings=UserSettings():GetService("UserGameSettings") end)

local playerModule
local cameras
local activeController
local activeTarget
local activeOriginal
local activeScore=0
local lastHookAttempt=0
local hardUnavailable=false
local autoDisabled=false
local relayedEvents=0
local ignoredEvents=0
local failedEvents=0
local consecutiveIgnored=0
local lastAppliedRotation=Vector2.zero

local function getPlayerModule()
    if type(playerModule)=="table" then return playerModule end
    local scripts=player:FindFirstChild("PlayerScripts")
    local module=scripts and scripts:FindFirstChild("PlayerModule")
    if not module then return nil end
    pcall(function()
        local value=require(module)
        if type(value)=="table" then playerModule=value end
    end)
    return playerModule
end

local function getCameras()
    if type(cameras)=="table" then return cameras end
    local module=getPlayerModule()
    if type(module)~="table" then return nil end
    pcall(function()
        if type(module.GetCameras)=="function" then cameras=module:GetCameras() end
        if type(cameras)~="table" then cameras=rawget(module,"cameras") end
    end)
    return cameras
end

local function getActiveController()
    local cameraModule=getCameras()
    if type(cameraModule)~="table" then return nil end
    local controller=rawget(cameraModule,"activeCameraController")
    if type(controller)~="table" and type(cameraModule.GetActiveCameraController)=="function" then
        pcall(function() controller=cameraModule:GetActiveCameraController() end)
    end
    return type(controller)=="table" and controller or nil
end

local function touchPreferred()
    local preferred
    local ok=pcall(function() preferred=UserInputService.PreferredInput end)
    if ok and preferred~=nil then return preferred==Enum.PreferredInput.Touch end
    return UserInputService.TouchEnabled
end

local function forceMovementRelative()
    if not userGameSettings then return end
    pcall(function() userGameSettings.RotationType=Enum.RotationType.MovementRelative end)
    if sethiddenproperty then
        pcall(function()
            sethiddenproperty(userGameSettings,"RotationType",Enum.RotationType.MovementRelative)
        end)
    end
end

local function controllerIsCameraOnlyLocked(controller)
    local locked=false
    pcall(function()
        if type(controller.GetIsMouseLocked)=="function" then
            locked=controller:GetIsMouseLocked()==true
        else
            locked=controller.inMouseLockedMode==true
        end
    end)
    return locked
end

local function humanoidAllowsCameraRelay()
    local character=player.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health<=0 then return false end

    local platform=false
    pcall(function() platform=humanoid.PlatformStand end)
    if platform then return false end

    local state
    pcall(function() state=humanoid:GetState() end)
    return state~=Enum.HumanoidStateType.Dead
        and state~=Enum.HumanoidStateType.Physics
        and state~=Enum.HumanoidStateType.Ragdoll
        and state~=Enum.HumanoidStateType.FallingDown
end

local function shouldRelay(controller)
    return getgenv().PCMovementEnabled~=false
        and getgenv().PCV600MouseRelayEnabled~=false
        and not autoDisabled
        and touchPreferred()
        and controller==getActiveController()
        and controllerIsCameraOnlyLocked(controller)
        and humanoidAllowsCameraRelay()
end

local function safeConnectionFunction(connection)
    local value
    pcall(function() value=connection.Function end)
    return type(value)=="function" and value or nil
end

local function connectionEquals(connection,target)
    if connection==target then return true end
    for _,key in ipairs({"Connection","RBXScriptConnection","connection"}) do
        local value
        pcall(function() value=connection[key] end)
        if value~=nil and value==target then return true end
    end
    return false
end

local function safeSource(fn)
    local source=""
    if debug and type(debug.info)=="function" then
        pcall(function() source=debug.info(fn,"s") or "" end)
    elseif debug and type(debug.getinfo)=="function" then
        pcall(function()
            local info=debug.getinfo(fn)
            source=(info and (info.source or info.short_src)) or ""
        end)
    end
    return string.lower(tostring(source))
end

local function getUpvalueValues(fn)
    local output={}
    if type(fn)~="function" then return output end

    if debug and type(debug.getupvalues)=="function" then
        local ok,values=pcall(debug.getupvalues,fn)
        if ok and type(values)=="table" then
            for _,value in pairs(values) do table.insert(output,value) end
        end
    end

    if #output==0 and type(getupvalues)=="function" then
        local ok,values=pcall(getupvalues,fn)
        if ok and type(values)=="table" then
            for _,value in pairs(values) do table.insert(output,value) end
        end
    end

    local single=(debug and debug.getupvalue) or getupvalue
    if #output==0 and type(single)=="function" then
        for index=1,80 do
            local ok,name,value=pcall(single,fn,index)
            if not ok or (name==nil and value==nil) then break end
            local resolved=type(name)=="string" and value or name
            if resolved~=nil then table.insert(output,resolved) end
        end
    end

    return output
end

local function referencesController(fn,controller,depth,seen)
    if type(fn)~="function" or depth<0 then return 0 end
    seen=seen or {}
    if seen[fn] then return 0 end
    seen[fn]=true

    local score=0
    for _,value in ipairs(getUpvalueValues(fn)) do
        if value==controller then
            score+=80
        elseif type(value)=="function" and depth>0 then
            score+=math.min(25,referencesController(value,controller,depth-1,seen))
        end
    end
    return score
end

local function callbackScore(connection,fn,controller)
    local score=0
    local directConnection
    pcall(function() directConnection=controller.inputChangedConn end)
    if directConnection and connectionEquals(connection,directConnection) then score+=1000 end
    score+=referencesController(fn,controller,2,{})

    local source=safeSource(fn)
    if string.find(source,"camera",1,true) then score+=25 end
    if string.find(source,"player",1,true) then score+=5 end
    return score
end

local function cameraTouchIsUnsunk(controller,input,processed)
    if processed then return false end
    local classification
    pcall(function()
        if type(controller.fingerTouches)=="table" then
            classification=controller.fingerTouches[input]
        end
    end)
    if classification~=nil then return classification==false end
    return true
end

local function unsunkTouchCount(controller)
    local count
    pcall(function()
        if type(controller.numUnsunkTouches)=="number" then
            count=controller.numUnsunkTouches
        end
    end)
    if count~=nil then return count end

    pcall(function()
        if type(controller.fingerTouches)=="table" then
            local total=0
            for _,processed in pairs(controller.fingerTouches) do
                if processed==false then total+=1 end
            end
            count=total
        end
    end)
    return count
end

local function centeredMouseProxy(input)
    local delta=input.Delta
    local dx=delta and delta.X or 0
    local dy=delta and delta.Y or 0
    local gainX=tonumber(getgenv().PCV600MouseGainX) or DEFAULT_GAIN_X
    local gainY=tonumber(getgenv().PCV600MouseGainY) or DEFAULT_GAIN_Y

    local center=Vector2.zero
    local camera=Workspace.CurrentCamera
    if camera then
        pcall(function() center=camera.ViewportSize*0.5 end)
    end

    return {
        UserInputType=Enum.UserInputType.MouseMovement,
        UserInputState=Enum.UserInputState.Change,
        KeyCode=Enum.KeyCode.Unknown,
        Delta=Vector3.new(dx*gainX,dy*gainY,0),
        Position=Vector3.new(center.X,center.Y,0),
    }
end

local function noteIgnoredMousePacket()
    ignoredEvents+=1
    consecutiveIgnored+=1
    if getgenv().PCV600AutoFallback~=false and consecutiveIgnored>=12 then
        autoDisabled=true
        getgenv().PCInputBridgeMode="fallback-v500-mouse-packets-ignored"
        getgenv().PCInputBridgeDiscovery="rotateInput-unchanged"
        warn("[V600] native mouse packets were ignored; restored V500 touch camera fallback")
    end
end

local function restoreActiveHook()
    if activeTarget and activeOriginal and type(hookfunction)=="function" then
        pcall(function() hookfunction(activeTarget,activeOriginal) end)
    end
    activeTarget=nil
    activeOriginal=nil
    activeScore=0
end

local function installRelay(controller)
    if type(controller)~="table" then return false end
    if type(getconnections)~="function" or type(hookfunction)~="function" then
        hardUnavailable=true
        getgenv().PCInputBridgeMode="fallback-v500-no-hook-capability"
        getgenv().PCInputBridgeDiscovery="missing-getconnections-or-hookfunction"
        return false
    end

    local connections
    local ok=pcall(function() connections=getconnections(UserInputService.InputChanged) end)
    if not ok or type(connections)~="table" then
        getgenv().PCInputBridgeMode="fallback-v500-no-connections"
        getgenv().PCInputBridgeDiscovery="inputchanged-connections-unavailable"
        return false
    end

    local bestFunction
    local bestScore=-1
    for _,connection in ipairs(connections) do
        local fn=safeConnectionFunction(connection)
        if fn then
            local score=callbackScore(connection,fn,controller)
            if score>bestScore then
                bestFunction=fn
                bestScore=score
            end
        end
    end

    getgenv().PCV600DiscoveryScore=bestScore
    if not bestFunction or bestScore<80 then
        getgenv().PCInputBridgeMode="fallback-v500-callback-unproven"
        getgenv().PCInputBridgeDiscovery="camera-inputchanged-score-"..tostring(bestScore)
        return false
    end

    if activeTarget==bestFunction and activeOriginal then return true end
    restoreActiveHook()

    local original
    local replacement
    replacement=function(input,processed,...)
        local inputType
        pcall(function() inputType=input.UserInputType end)
        if inputType~=Enum.UserInputType.Touch or not shouldRelay(controller) then
            return original(input,processed,...)
        end

        -- Keep Roblox's own touch bookkeeping and pinch lifecycle, but remove only
        -- the one-finger touch-pan contribution from this callback invocation.
        local previousPan=rawget(controller,"panEnabled")
        if previousPan==nil then return original(input,processed,...) end
        controller.panEnabled=false
        local touchResults=table.pack(pcall(original,input,processed,...))
        controller.panEnabled=previousPan

        if not touchResults[1] then
            failedEvents+=1
            error(touchResults[2],0)
        end

        if previousPan~=false
            and cameraTouchIsUnsunk(controller,input,processed)
            and unsunkTouchCount(controller)==1 then
            local delta=input.Delta
            if delta and (math.abs(delta.X)>1e-6 or math.abs(delta.Y)>1e-6) then
                forceMovementRelative()

                local before=rawget(controller,"rotateInput")
                local proxy=centeredMouseProxy(input)
                local mouseResults=table.pack(pcall(original,proxy,false))
                local after=rawget(controller,"rotateInput")

                forceMovementRelative()

                if not mouseResults[1] then
                    failedEvents+=1
                    if getgenv().PCV600AutoFallback~=false and failedEvents>=3 then
                        autoDisabled=true
                        getgenv().PCInputBridgeMode="fallback-v500-proxy-error"
                        getgenv().PCInputBridgeDiscovery="mouse-proxy-callback-error"
                    end
                elseif typeof(before)=="Vector2" and typeof(after)=="Vector2" then
                    local applied=after-before
                    if applied.Magnitude>1e-8 then
                        relayedEvents+=1
                        consecutiveIgnored=0
                        lastAppliedRotation=applied
                        getgenv().PCInputBridgeMode="decoupled-native-camera-mousemovement"
                        getgenv().PCInputBridgeDiscovery="exact-callback-score-"..tostring(activeScore)
                    else
                        noteIgnoredMousePacket()
                    end
                else
                    -- A future controller may consume mouse state elsewhere. A successful
                    -- callback is safer than disabling the bridge without an observable field.
                    relayedEvents+=1
                    consecutiveIgnored=0
                    getgenv().PCInputBridgeMode="decoupled-native-mouse-unobservable-state"
                end
            end
        end

        return table.unpack(touchResults,2,touchResults.n)
    end

    local success,old=pcall(function() return hookfunction(bestFunction,replacement) end)
    if not success or type(old)~="function" then
        getgenv().PCInputBridgeMode="fallback-v500-hook-failed"
        getgenv().PCInputBridgeDiscovery="hookfunction-failed"
        return false
    end

    original=old
    activeTarget=bestFunction
    activeOriginal=old
    activeScore=bestScore
    getgenv().PCInputBridgeMode="v600-native-mouse-hook-installed"
    getgenv().PCInputBridgeDiscovery="score-"..tostring(bestScore)
    return true
end

RunService:BindToRenderStep(WATCH_BIND,Enum.RenderPriority.Camera.Value-4,function()
    local controller=getActiveController()
    if controller~=activeController then
        restoreActiveHook()
        activeController=controller
        lastHookAttempt=0
        autoDisabled=false
        consecutiveIgnored=0
    end

    if type(controller)~="table" or activeOriginal or hardUnavailable then return end
    if os.clock()-lastHookAttempt<0.75 then return end
    lastHookAttempt=os.clock()
    pcall(function() installRelay(controller) end)
end)

activeController=getActiveController()
if activeController then pcall(function() installRelay(activeController) end) end

getgenv().PCV600Diagnostics=function()
    local controller=getActiveController()
    local result={
        version=getgenv().PCMovementVersion,
        bridgeMode=getgenv().PCInputBridgeMode,
        discovery=getgenv().PCInputBridgeDiscovery,
        discoveryScore=activeScore,
        callbackHooked=activeOriginal~=nil,
        relayEnabled=getgenv().PCV600MouseRelayEnabled~=false,
        autoFallback=getgenv().PCV600AutoFallback~=false,
        autoDisabled=autoDisabled,
        relayedEvents=relayedEvents,
        ignoredEvents=ignoredEvents,
        failedEvents=failedEvents,
        gainX=tonumber(getgenv().PCV600MouseGainX) or DEFAULT_GAIN_X,
        gainY=tonumber(getgenv().PCV600MouseGainY) or DEFAULT_GAIN_Y,
        lastAppliedRotation=lastAppliedRotation,
        preferredInput=tostring(UserInputService.PreferredInput),
        writesRootPartCFrame=false,
        writesCameraCFrame=false,
        forcesAutoRotate=false,
        callsUpdateMouseBehavior=false,
        forcesCameraRelative=false,
    }
    if type(controller)=="table" then
        pcall(function() result.inMouseLockedMode=controller.inMouseLockedMode end)
        pcall(function() result.mouseLockOffset=controller.mouseLockOffset end)
        pcall(function() result.panEnabled=controller.panEnabled end)
        pcall(function() result.rotateInput=controller.rotateInput end)
    end
    if userGameSettings then
        pcall(function() result.rotationType=tostring(userGameSettings.RotationType) end)
    end
    return result
end

getgenv().PCV600Report=function()
    local diagnostics=getgenv().PCV600Diagnostics()
    local keys={
        "version","bridgeMode","discovery","discoveryScore","callbackHooked",
        "relayEnabled","autoFallback","autoDisabled","relayedEvents","ignoredEvents",
        "failedEvents","gainX","gainY","lastAppliedRotation","preferredInput",
        "rotationType","inMouseLockedMode","mouseLockOffset","panEnabled","rotateInput",
        "writesRootPartCFrame","writesCameraCFrame","forcesAutoRotate",
        "callsUpdateMouseBehavior","forcesCameraRelative",
    }
    local lines={"=== PC MOVEMENT V600 REPORT ==="}
    for _,key in ipairs(keys) do
        table.insert(lines,key.." = "..tostring(diagnostics[key]))
    end
    local report=table.concat(lines,"\n")
    warn(report)
    return report
end

getgenv().__PCMobileAimCleanup=function()
    pcall(function() RunService:UnbindFromRenderStep(WATCH_BIND) end)
    restoreActiveHook()

    getgenv().PCV600Diagnostics=nil
    getgenv().PCV600Report=nil
    getgenv().PCV600DiscoveryScore=nil

    if baseCleanup then pcall(baseCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

warn(string.format(
    "[V600] decoupled native mouse path ready | mode=%s | discovery=%s | gains=(%.3f, %.3f)",
    tostring(getgenv().PCInputBridgeMode),
    tostring(getgenv().PCInputBridgeDiscovery),
    tonumber(getgenv().PCV600MouseGainX) or DEFAULT_GAIN_X,
    tonumber(getgenv().PCV600MouseGainY) or DEFAULT_GAIN_Y
))
