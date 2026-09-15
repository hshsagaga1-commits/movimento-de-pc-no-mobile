local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local WATCH_BIND="__PCMovementV601NativeMouseWatch"

--[[
    V601 / CALLBACK DISCOVERY + DECOUPLED NATIVE MOUSE PATH

    V500 proved that MovementRelative + camera-only mouse lock removes most of
    V26's character/camera coupling. V601 keeps that entire foundation and
    changes only the camera input path:

      touch delta -> proven Legacy camera InputChanged callback as MouseMovement

    Unlike V26, this layer NEVER calls UpdateMouseBehavior and NEVER selects
    CameraRelative. The proxy also reports the viewport center as Position, so
    every packet behaves like a centered relative-mouse packet instead of a
    touch-orbit position.

    V601 is deliberately evidence-first. It records every InputChanged wrapper,
    the wrapper fields exposed by the executor, every inspected function and
    upvalue, and the precise rejection reason. It also recognizes the common
    executor field LuaConnection, which V600 failed to inspect.

    Activation order:
      1. hook a strongly proven callback Function;
      2. if Function is hidden, isolate the exact wrapper and use wrapper:Fire();
      3. otherwise keep untouched V500 touch camera behavior.

    The second route is only eligible after exact RBXScriptConnection identity
    has been proven and the wrapper can be disabled/re-enabled. Riskier global
    paths such as firesignal or VirtualInputManager mouse injection are reported
    as capabilities but never used automatically.
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

getgenv().PCMovementVersion="V601-CallbackDiscovery"
getgenv().PCInputBridgeMode="v601-initializing-over-v500"
getgenv().PCInputBridgeDiscovery="pending"

if getgenv().PCV601MouseRelayEnabled==nil then getgenv().PCV601MouseRelayEnabled=true end
if getgenv().PCV601AutoFallback==nil then getgenv().PCV601AutoFallback=true end
if getgenv().PCV601RequireObservedCameraLock==nil then
    getgenv().PCV601RequireObservedCameraLock=false
end

-- X9 measured the real V20 angular response in the active Legacy controller.
-- These gains preserve that response while changing semantics/path only.
local V20_TOUCH_RAD_X=0.029688168050806058
local V20_TOUCH_RAD_Y=0.010602966305655836
local LEGACY_MOUSE_RAD_X=(math.pi*4)/1920
local LEGACY_MOUSE_RAD_Y=(math.pi*1.9)/1200
local DEFAULT_GAIN_X=V20_TOUCH_RAD_X/LEGACY_MOUSE_RAD_X
local DEFAULT_GAIN_Y=V20_TOUCH_RAD_Y/LEGACY_MOUSE_RAD_Y

if getgenv().PCV601MouseGainX==nil then getgenv().PCV601MouseGainX=DEFAULT_GAIN_X end
if getgenv().PCV601MouseGainY==nil then getgenv().PCV601MouseGainY=DEFAULT_GAIN_Y end

local userGameSettings
pcall(function() userGameSettings=UserSettings():GetService("UserGameSettings") end)

local playerModule
local cameras
local activeController
local activeTarget
local activeOriginal
local activeConnectionWrapper
local activeRelayConnection
local activeWrapperDisabled=false
local activeRoute="none"
local activeScore=0
local discoveryScore=-1
local lastHookAttempt=0
local hardUnavailable=false
local autoDisabled=false
local discoveryComplete=false
local callbackFound=false
local callbackFoundOrigin="none"
local callbackExecutedEvents=0
local realTouchCallbackEvents=0
local syntheticAttempts=0
local syntheticAcceptedEvents=0
local syntheticRejectedEvents=0
local rotateInputChangedEvents=0
local rotateInputUnchangedEvents=0
local relayedEvents=0
local ignoredEvents=0
local failedEvents=0
local consecutiveIgnored=0
local lastAppliedRotation=Vector2.zero
local lastRotateBefore=nil
local lastRotateAfter=nil
local lastSyntheticStatus="not-attempted"
local lastTouchEligibility="not-evaluated"
local relayGate="not-evaluated"
local lastReportedGate=nil
local unobservedLockWarningLogged=false
local fallbackReason="discovery-pending"
local lastFallbackEvidence=nil
local fallbackRestoreOk=true
local fallbackRestoreDetail="not-needed"
local gcScanStatus="not-needed"
local alternativeScanStatus="not-started"
local evidence={}
local evidenceDropped=0
local inspectedFunctions={}
local discoveryStats={
    connectionsFound=0,
    connectionFunctions=0,
    controllerFunctions=0,
    metatableFunctions=0,
    moduleFunctions=0,
    nestedFunctions=0,
    functionsExamined=0,
    upvaluesExamined=0,
    constantsExamined=0,
    candidatesFound=0,
    gcObjectsExamined=0,
    gcFunctionsExamined=0,
}

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

local function relayGateReason(controller)
    if getgenv().PCMovementEnabled==false then return "pc-movement-disabled" end
    if getgenv().PCV601MouseRelayEnabled==false then return "relay-disabled" end
    if autoDisabled then return "auto-fallback-active" end
    if not touchPreferred() then return "preferred-input-not-touch" end
    if controller~=getActiveController() then return "controller-no-longer-active" end
    if getgenv().PCV500CameraOnlyLockEnabled==false then return "v500-camera-only-lock-disabled" end
    if getgenv().PCV601RequireObservedCameraLock==true
        and not controllerIsCameraOnlyLocked(controller) then
        return "camera-only-lock-not-observed-strict-mode"
    end
    if not humanoidAllowsCameraRelay() then return "humanoid-state-blocked" end
    return "open"
end

local function shouldRelay(controller)
    relayGate=relayGateReason(controller)
    return relayGate=="open"
end

local function cleanText(value,limit)
    local output
    local ok=pcall(function() output=tostring(value) end)
    if not ok then output="<tostring-error>" end
    output=string.gsub(output or "nil","[\r\n\t]"," ")
    limit=limit or 180
    if #output>limit then output=string.sub(output,1,limit).."..." end
    return output
end

local function addEvidence(section,message)
    if #evidence>=700 then
        evidenceDropped+=1
        return
    end
    evidence[#evidence+1]=string.format("[%03d][%s] %s",#evidence+1,section,cleanText(message,900))
end

local function safeField(object,key)
    local value
    local ok,err=pcall(function() value=object[key] end)
    if ok then return true,value,nil end
    return false,nil,cleanText(err,120)
end

local function valueType(value)
    local robloxType="?"
    pcall(function() robloxType=typeof(value) end)
    return type(value).."/"..cleanText(robloxType,60)
end

local function describeValue(value)
    local kind=valueType(value)
    if type(value)=="table" then
        local count=0
        pcall(function() for _ in pairs(value) do count+=1 end end)
        return kind.." keys="..tostring(count).." id="..cleanText(value,80)
    end
    if typeof(value)=="Instance" then
        local path=cleanText(value,120)
        pcall(function() path=value:GetFullName() end)
        return kind.." path="..cleanText(path,150)
    end
    return kind.." value="..cleanText(value,120)
end

local CONNECTION_LINK_KEYS={
    "LuaConnection", -- the common executor mapping V600 missed
    "Connection","RBXScriptConnection","connection","SignalConnection",
}

local function safeConnectionFunction(connection)
    local ok,value= safeField(connection,"Function")
    return ok and type(value)=="function" and value or nil,valueType(value)
end

local function connectionEquals(connection,target)
    if target==nil then return false,"target-nil" end
    if connection==target then return true,"wrapper-itself" end
    for _,key in ipairs(CONNECTION_LINK_KEYS) do
        local ok,value=safeField(connection,key)
        if ok and value~=nil and value==target then return true,key end
    end
    return false,"no-identity-field-match"
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
    return string.lower(cleanText(source,220))
end

local function getUpvalueEntries(fn)
    local output={}
    if type(fn)~="function" then return output,"not-a-function" end

    local api="none"
    if debug and type(debug.getupvalues)=="function" then
        local ok,values=pcall(debug.getupvalues,fn)
        if ok and type(values)=="table" then
            api="debug.getupvalues"
            for name,value in pairs(values) do
                output[#output+1]={name=cleanText(name,60),value=value}
            end
        end
    end

    if #output==0 and type(getupvalues)=="function" then
        local ok,values=pcall(getupvalues,fn)
        if ok and type(values)=="table" then
            api="getupvalues"
            for name,value in pairs(values) do
                output[#output+1]={name=cleanText(name,60),value=value}
            end
        end
    end

    local single=(debug and debug.getupvalue) or getupvalue
    if #output==0 and type(single)=="function" then
        api=(debug and debug.getupvalue==single) and "debug.getupvalue" or "getupvalue"
        for index=1,80 do
            local ok,name,value=pcall(single,fn,index)
            if not ok or (name==nil and value==nil) then break end
            if type(name)=="string" then
                output[#output+1]={name=name,value=value}
            else
                output[#output+1]={name=tostring(index),value=name}
            end
        end
    end

    return output,api
end

local function getConstants(fn)
    local getter=(debug and debug.getconstants) or getconstants
    if type(getter)~="function" then return {},"none" end
    local ok,values=pcall(getter,fn)
    if not ok or type(values)~="table" then return {},"failed" end
    return values,(debug and debug.getconstants==getter) and "debug.getconstants" or "getconstants"
end

local function functionSignature(fn)
    local source=safeSource(fn)
    local name="?"
    local line="?"
    local args="?"
    if debug and type(debug.info)=="function" then
        pcall(function() name=cleanText(debug.info(fn,"n") or "?",80) end)
        pcall(function() line=cleanText(debug.info(fn,"l") or "?",30) end)
        pcall(function()
            local count,vararg=debug.info(fn,"a")
            args=tostring(count)..(vararg and "+vararg" or "")
        end)
    elseif debug and type(debug.getinfo)=="function" then
        pcall(function()
            local info=debug.getinfo(fn)
            name=cleanText(info and info.name or "?",80)
            line=cleanText(info and (info.linedefined or info.currentline) or "?",30)
            if info and info.nparams~=nil then
                args=tostring(info.nparams)..(info.isvararg and "+vararg" or "")
            end
        end)
    end
    local closure="unknown"
    if type(islclosure)=="function" then
        local ok,value=pcall(islclosure,fn)
        if ok and value then closure="Lua" end
    end
    if closure=="unknown" and type(iscclosure)=="function" then
        local ok,value=pcall(iscclosure,fn)
        if ok and value then closure="C" end
    end
    return string.format("kind=%s args=%s name=%s source=%s line=%s id=%s",closure,args,name,source,line,cleanText(fn,90)),source,name
end

local function inspectFunction(fn,controller,origin,depth)
    if type(fn)~="function" then return nil end
    if inspectedFunctions[fn] then return inspectedFunctions[fn] end
    if discoveryStats.functionsExamined>=180 then
        addEvidence("FUNCTION",origin.." rejected: function inspection budget reached")
        return nil
    end

    local record={
        fn=fn,
        origin=origin,
        referencesController=false,
        referenceDepth=nil,
        clueScore=0,
    }
    inspectedFunctions[fn]=record
    discoveryStats.functionsExamined+=1
    if depth and depth>0 then discoveryStats.nestedFunctions+=1 end

    local signature,source,name=functionSignature(fn)
    if string.find(source,"camera",1,true) then record.clueScore+=30 end
    if string.find(source,"player",1,true) then record.clueScore+=5 end
    local lowerName=string.lower(name)
    if string.find(lowerName,"input",1,true) and string.find(lowerName,"chang",1,true) then
        record.clueScore+=20
    end
    addEvidence("FUNCTION",origin.." | "..signature)

    local constants,constantApi=getConstants(fn)
    discoveryStats.constantsExamined+=#constants
    local constantSummary={}
    for _,constant in ipairs(constants) do
        if type(constant)=="string" or type(constant)=="number" or type(constant)=="boolean" then
            local printable=cleanText(constant,70)
            if #constantSummary<24 then constantSummary[#constantSummary+1]=printable end
            local lower=string.lower(tostring(constant))
            if lower=="mousemovement" or lower=="touch" or lower=="rotateinput"
                or lower=="panenabled" or lower=="inputchanged" then
                record.clueScore+=12
            end
        end
    end
    addEvidence("CONSTANTS",origin.." api="..constantApi.." count="..#constants.." observed={"..table.concat(constantSummary,", ").."}")

    local upvalues,upvalueApi=getUpvalueEntries(fn)
    discoveryStats.upvaluesExamined+=#upvalues
    local upvalueSummary={}
    local nested={}
    for index,entry in ipairs(upvalues) do
        local value=entry.value
        if value==controller then
            record.referencesController=true
            record.referenceDepth=0
        end
        if #upvalueSummary<32 then
            local marker=value==controller and "=ACTIVE_CONTROLLER" or ""
            upvalueSummary[#upvalueSummary+1]=string.format("%s:%s%s",entry.name,valueType(value),marker)
        end
        if type(value)=="function" and (depth or 0)<2 and #nested<12 then
            nested[#nested+1]={fn=value,origin=origin.." -> upvalue["..tostring(index)..":"..entry.name.."]"}
        end
    end
    addEvidence("UPVALUES",origin.." api="..upvalueApi.." count="..#upvalues.." observed={"..table.concat(upvalueSummary,", ").."}")

    for _,child in ipairs(nested) do
        local childRecord=inspectFunction(child.fn,controller,child.origin,(depth or 0)+1)
        if childRecord and childRecord.referencesController and not record.referencesController then
            record.referencesController=true
            record.referenceDepth=(childRecord.referenceDepth or 0)+1
        end
    end
    if record.referencesController then
        record.clueScore+=record.referenceDepth==0 and 200 or 120
    end
    return record
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
    local gainX=tonumber(getgenv().PCV601MouseGainX) or DEFAULT_GAIN_X
    local gainY=tonumber(getgenv().PCV601MouseGainY) or DEFAULT_GAIN_Y

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

local restoreActiveRoute

local function setFallback(reason,detail)
    fallbackReason=reason
    getgenv().PCInputBridgeMode="fallback-v500-"..reason
    getgenv().PCInputBridgeDiscovery=detail or reason
    local fingerprint=reason.."|"..tostring(detail or reason)
    if fingerprint~=lastFallbackEvidence then
        lastFallbackEvidence=fingerprint
        addEvidence("FALLBACK","reason="..reason.." detail="..tostring(detail or reason))
    end
end

local function requestRuntimeFallback(reason,detail)
    autoDisabled=true
    setFallback(reason,detail)
    task.defer(function()
        if restoreActiveRoute then restoreActiveRoute(true) end
    end)
end

local function noteIgnoredMousePacket(reason)
    ignoredEvents+=1
    rotateInputUnchangedEvents+=1
    consecutiveIgnored+=1
    lastSyntheticStatus=reason
    if getgenv().PCV601AutoFallback~=false and consecutiveIgnored>=12 then
        requestRuntimeFallback("synthetic-no-rotateinput-change",reason.." after "..tostring(consecutiveIgnored).." packets")
        warn("[V601] synthetic packets produced no rotateInput change; restoring V500 fallback")
    end
end

local function invokeWrapperMethod(wrapper,key,...)
    local okField,method,fieldError=safeField(wrapper,key)
    if not okField or type(method)~="function" then
        return false,"field-"..key.."-"..(fieldError or valueType(method))
    end
    local args=table.pack(...)
    local result=table.pack(pcall(function()
        return method(wrapper,table.unpack(args,1,args.n))
    end))
    if result[1] then return true,result end

    -- Some executors expose bound closure fields instead of colon methods.
    local bound=table.pack(pcall(function()
        return method(table.unpack(args,1,args.n))
    end))
    if bound[1] then return true,bound end
    return false,"self-call="..cleanText(result[2],140).."; bound-call="..cleanText(bound[2],140)
end

local function disableWrapper(wrapper)
    local ok,detail=invokeWrapperMethod(wrapper,"Disable")
    if ok then
        local enabledOk,enabled=safeField(wrapper,"Enabled")
        return true,"Disable(); EnabledAfter="..(enabledOk and cleanText(enabled,40) or "unobservable")
    end
    local writeOk,writeError=pcall(function() wrapper.Enabled=false end)
    if writeOk then
        local _,enabled=safeField(wrapper,"Enabled")
        return true,"Enabled=false; EnabledAfter="..cleanText(enabled,40)
    end
    return false,"Disable failed: "..cleanText(detail,180).."; Enabled write: "..cleanText(writeError,120)
end

local function enableWrapper(wrapper)
    local ok=invokeWrapperMethod(wrapper,"Enable")
    if ok then
        local enabledOk,enabled=safeField(wrapper,"Enabled")
        return true,"Enable(); EnabledAfter="..(enabledOk and cleanText(enabled,40) or "unobservable")
    end
    local writeOk,writeError=pcall(function() wrapper.Enabled=true end)
    return writeOk,writeOk and "Enabled=true" or cleanText(writeError,140)
end

restoreActiveRoute=function(preserveDiscovery)
    local routeRestoreOk=true
    local routeRestoreDetails={}
    if activeRelayConnection then
        pcall(function() activeRelayConnection:Disconnect() end)
        activeRelayConnection=nil
    end
    if activeConnectionWrapper and activeWrapperDisabled then
        local ok,detail=enableWrapper(activeConnectionWrapper)
        routeRestoreOk=routeRestoreOk and ok
        routeRestoreDetails[#routeRestoreDetails+1]="wrapper="..tostring(ok)..":"..tostring(detail)
        addEvidence("RESTORE","wrapper re-enable ok="..tostring(ok).." detail="..tostring(detail))
    end
    activeWrapperDisabled=false
    if activeTarget and activeOriginal and type(hookfunction)=="function" then
        local ok,err=pcall(function() hookfunction(activeTarget,activeOriginal) end)
        routeRestoreOk=routeRestoreOk and ok
        routeRestoreDetails[#routeRestoreDetails+1]="hook="..tostring(ok)..(ok and "" or ":"..cleanText(err,120))
        addEvidence("RESTORE","hook restore ok="..tostring(ok)..(ok and "" or " error="..cleanText(err,160)))
    end
    if #routeRestoreDetails>0 then
        fallbackRestoreOk=routeRestoreOk
        fallbackRestoreDetail=table.concat(routeRestoreDetails,"; ")
        if not routeRestoreOk then
            fallbackReason="original-route-restore-failed"
            getgenv().PCInputBridgeMode="fallback-restore-failed"
            getgenv().PCInputBridgeDiscovery=fallbackRestoreDetail
            warn("[V601] failed to restore the original V500 camera callback route: "..fallbackRestoreDetail)
        end
    end
    activeTarget=nil
    activeOriginal=nil
    activeConnectionWrapper=nil
    activeRoute="none"
    activeScore=preserveDiscovery and discoveryScore or 0
end

local function noteCallbackResult(results,isRealTouch)
    if results[1] then
        callbackExecutedEvents+=1
        if isRealTouch then realTouchCallbackEvents+=1 end
        return true
    end
    failedEvents+=1
    return false
end

local function processTouch(controller,input,processed,dispatch,...)
    local trailing=table.pack(...)
    if not shouldRelay(controller) then
        fallbackReason="relay-gate-"..relayGate
        getgenv().PCInputBridgeMode="fallback-v500-relay-gate-"..relayGate
        getgenv().PCInputBridgeDiscovery="callback-found-but-synthetic-gated"
        lastSyntheticStatus="not-attempted-gate-"..relayGate
        lastTouchEligibility="not-evaluated-gate-"..relayGate
        if relayGate~=lastReportedGate then
            lastReportedGate=relayGate
            addEvidence("RUNTIME","synthetic relay gated: "..relayGate.."; real touch sent unchanged to proven callback")
        end
        local pass=table.pack(pcall(function()
            return dispatch(input,processed,table.unpack(trailing,1,trailing.n))
        end))
        noteCallbackResult(pass,true)
        return pass
    end

    if not controllerIsCameraOnlyLocked(controller) and not unobservedLockWarningLogged then
        unobservedLockWarningLogged=true
        addEvidence("RUNTIME","camera-only lock was not observable, but the discovery experiment proceeded because PCV601RequireObservedCameraLock=false; this matches the V600 test state and is reported separately")
    end

    local previousPan=rawget(controller,"panEnabled")
    if previousPan==nil then
        relayGate="panEnabled-unobservable"
        fallbackReason="relay-gate-panEnabled-unobservable"
        getgenv().PCInputBridgeMode="fallback-v500-relay-gate-panEnabled-unobservable"
        getgenv().PCInputBridgeDiscovery="callback-found-but-panEnabled-unobservable"
        lastSyntheticStatus="not-attempted-panEnabled-unobservable"
        lastTouchEligibility="not-evaluated-panEnabled-unobservable"
        local pass=table.pack(pcall(function()
            return dispatch(input,processed,table.unpack(trailing,1,trailing.n))
        end))
        noteCallbackResult(pass,true)
        return pass
    end

    -- Preserve touch bookkeeping and pinch lifecycle while suppressing only the
    -- one-finger touch-pan contribution during the proven callback invocation.
    controller.panEnabled=false
    local touchResults=table.pack(pcall(function()
        return dispatch(input,processed,table.unpack(trailing,1,trailing.n))
    end))
    controller.panEnabled=previousPan
    local realTouchOk=noteCallbackResult(touchResults,true)
    if not realTouchOk then
        lastSyntheticStatus="real-touch-callback-error: "..cleanText(touchResults[2],160)
        requestRuntimeFallback("real-touch-callback-error",lastSyntheticStatus)
        return touchResults
    end

    local unsunk=cameraTouchIsUnsunk(controller,input,processed)
    local touchCount=unsunkTouchCount(controller)
    local delta
    pcall(function() delta=input.Delta end)
    local nonZeroDelta=delta~=nil
        and (math.abs(delta.X)>1e-6 or math.abs(delta.Y)>1e-6)
    local eligible=previousPan~=false and unsunk and touchCount==1 and nonZeroDelta
    if not eligible then
        if previousPan==false then
            lastTouchEligibility="rejected-panEnabled-was-false"
        elseif not unsunk then
            lastTouchEligibility="rejected-processed-or-sunk-touch"
        elseif touchCount~=1 then
            lastTouchEligibility="rejected-unsunk-touch-count-"..tostring(touchCount)
        elseif not nonZeroDelta then
            lastTouchEligibility="rejected-zero-or-missing-delta"
        else
            lastTouchEligibility="rejected-unknown"
        end
        if syntheticAttempts==0 then lastSyntheticStatus="not-attempted-"..lastTouchEligibility end
        return touchResults
    end
    lastTouchEligibility="accepted-single-unsunk-touch-with-delta"

    forceMovementRelative()
    syntheticAttempts+=1
    lastRotateBefore=rawget(controller,"rotateInput")
    local proxy=centeredMouseProxy(input)
    local mouseResults=table.pack(pcall(function() return dispatch(proxy,false) end))
    lastRotateAfter=rawget(controller,"rotateInput")
    forceMovementRelative()

    if not mouseResults[1] then
        syntheticRejectedEvents+=1
        failedEvents+=1
        lastSyntheticStatus="rejected-error: "..cleanText(mouseResults[2],180)
        if getgenv().PCV601AutoFallback~=false and syntheticRejectedEvents>=3 then
            requestRuntimeFallback("synthetic-callback-error",lastSyntheticStatus)
        end
        return touchResults
    end

    callbackExecutedEvents+=1
    syntheticAcceptedEvents+=1
    lastSyntheticStatus="accepted-dispatch"
    if typeof(lastRotateBefore)=="Vector2" and typeof(lastRotateAfter)=="Vector2" then
        local applied=lastRotateAfter-lastRotateBefore
        if applied.Magnitude>1e-8 then
            rotateInputChangedEvents+=1
            relayedEvents+=1
            consecutiveIgnored=0
            lastAppliedRotation=applied
            lastSyntheticStatus="accepted-rotateinput-changed"
            fallbackReason="none"
            getgenv().PCInputBridgeMode="decoupled-native-camera-mousemovement-"..activeRoute
            getgenv().PCInputBridgeDiscovery="callback-executed-synthetic-accepted-rotateinput-changed"
        else
            noteIgnoredMousePacket("accepted-but-rotateinput-unchanged")
        end
    else
        noteIgnoredMousePacket("accepted-but-rotateinput-unobservable before="..valueType(lastRotateBefore).." after="..valueType(lastRotateAfter))
    end
    return touchResults
end

local function unpackCallbackResults(results)
    if results[1] then return table.unpack(results,2,results.n) end
    error(results[2],0)
end

local function inspectTableFunctions(tbl,controller,origin,statKey)
    if type(tbl)~="table" then
        addEvidence("TABLE",origin.." unavailable type="..valueType(tbl))
        return
    end
    local entries={}
    local ok,err=pcall(function()
        for key,value in pairs(tbl) do
            entries[#entries+1]={key=cleanText(key,90),value=value}
        end
    end)
    if not ok then
        addEvidence("TABLE",origin.." enumeration failed: "..cleanText(err,160))
        return
    end
    table.sort(entries,function(a,b) return a.key<b.key end)
    local keySummary={}
    local inspectedHere=0
    for _,entry in ipairs(entries) do
        if #keySummary<140 then keySummary[#keySummary+1]=entry.key..":"..valueType(entry.value) end
        if type(entry.value)=="function" then
            inspectedHere+=1
            discoveryStats[statKey]+=1
            local functionOrigin=origin.."."..entry.key
            inspectFunction(entry.value,controller,functionOrigin,0)
            addEvidence("ALTERNATIVE",functionOrigin.." rejected for automatic direct call: function is visible but not proven to be the connected InputChanged stage")
            if inspectedHere%8==0 then task.wait() end
        end
    end
    addEvidence("TABLE",origin.." keys="..#entries.." observed={"..table.concat(keySummary,", ").."}")
end

local scanGCAlternatives

local function scanAlternativeSurfaces(controller,includeGC)
    task.wait()
    alternativeScanStatus="running-controller"
    inspectTableFunctions(controller,controller,"controller","controllerFunctions")
    task.wait()
    alternativeScanStatus="running-metatable"
    local metatable
    if type(getrawmetatable)=="function" then pcall(function() metatable=getrawmetatable(controller) end) end
    if type(metatable)~="table" then pcall(function() metatable=getmetatable(controller) end) end
    inspectTableFunctions(metatable,controller,"controller.metatable","metatableFunctions")
    task.wait()
    alternativeScanStatus="running-camera-module"
    inspectTableFunctions(getCameras(),controller,"cameraModule","moduleFunctions")
    alternativeScanStatus="complete"
    if includeGC then
        task.wait()
        scanGCAlternatives(controller)
    else
        gcScanStatus="skipped-proven-function"
        addEvidence("ALTERNATIVE","getgc scan skipped because a connection Function was already proven")
    end
end

scanGCAlternatives=function(controller)
    if type(getgc)~="function" then
        gcScanStatus="unavailable"
        addEvidence("ALTERNATIVE","getgc unavailable; GC closure route not inspectable")
        return
    end
    gcScanStatus="running"
    local ok,objects=pcall(getgc,true)
    if not ok or type(objects)~="table" then
        gcScanStatus="failed"
        addEvidence("ALTERNATIVE","getgc(true) failed: "..cleanText(objects,180))
        return
    end
    local budget=math.max(100,math.min(tonumber(getgenv().PCV601GCScanBudget) or 2500,6000))
    local matches=0
    for index,object in ipairs(objects) do
        if index>budget then break end
        discoveryStats.gcObjectsExamined+=1
        if type(object)=="function" then
            discoveryStats.gcFunctionsExamined+=1
            local source=safeSource(object)
            local interesting=string.find(source,"camera",1,true)~=nil
                or string.find(source,"playermodule",1,true)~=nil
            if not interesting then
                local constants=getConstants(object)
                for _,constant in ipairs(constants) do
                    if type(constant)=="string" then
                        local lower=string.lower(constant)
                        if lower=="rotateinput" or lower=="panenabled" or lower=="mousemovement"
                            or lower=="inputchanged" or lower=="fingertouches" then
                            interesting=true
                            break
                        end
                    end
                end
            end
            if interesting and matches<24 then
                matches+=1
                inspectFunction(object,controller,"getgc["..tostring(index).."]",0)
                addEvidence("ALTERNATIVE","getgc["..tostring(index).."] retained as diagnostic candidate only; no RBXScriptConnection identity proof")
            end
        end
        if index%250==0 then task.wait() end
    end
    gcScanStatus="complete-matches-"..tostring(matches)
    addEvidence("ALTERNATIVE","getgc scan complete objects="..tostring(discoveryStats.gcObjectsExamined).." functions="..tostring(discoveryStats.gcFunctionsExamined).." retained="..tostring(matches).." budget="..tostring(budget))
end

local function discoverCandidates(controller)
    local targetOk,target,targetError=safeField(controller,"inputChangedConn")
    addEvidence("DISCOVERY","active controller="..describeValue(controller))
    addEvidence("DISCOVERY","controller.inputChangedConn access="..tostring(targetOk).." type="..valueType(target)..(targetError and " error="..targetError or "").." value="..cleanText(target,120))
    addEvidence("CAPABILITY",string.format(
        "getconnections=%s hookfunction=%s firesignal=%s getgc=%s getcallbackvalue=%s getscriptclosure=%s debug.info=%s debug.getupvalues=%s getupvalues=%s wrapper-Fire=examined-per-candidate",
        type(getconnections),type(hookfunction),type(firesignal),type(getgc),
        type(getcallbackvalue),type(getscriptclosure),
        debug and type(debug.info) or "nil",
        debug and type(debug.getupvalues) or "nil",type(getupvalues)
    ))
    addEvidence("ALTERNATIVE","firesignal path observed="..type(firesignal).."; rejected for automatic use because it fans the synthetic event out to every UIS.InputChanged listener instead of the proven Legacy camera stage")
    local vimStatus="unavailable"
    pcall(function()
        local vim=game:GetService("VirtualInputManager")
        vimStatus=vim and "service-available" or "unavailable"
    end)
    addEvidence("ALTERNATIVE","VirtualInputManager mouse path="..vimStatus.."; rejected for automatic use because absolute mouse injection is not the isolated Legacy callback and can change input modality/position semantics")

    if type(getconnections)~="function" then
        hardUnavailable=true
        setFallback("no-getconnections","cannot enumerate UIS.InputChanged")
        return nil,nil
    end
    local connections
    local ok,connectionError=pcall(function() connections=getconnections(UserInputService.InputChanged) end)
    if not ok or type(connections)~="table" then
        hardUnavailable=true
        setFallback("inputchanged-connections-unavailable",cleanText(connectionError or connections,180))
        return nil,nil
    end

    discoveryStats.connectionsFound=#connections
    addEvidence("DISCOVERY","UIS.InputChanged connections found="..tostring(#connections))
    local bestHook
    local bestFire
    local bestProof
    local knownFields={
        "Function","Enabled","ForeignState","LuaConnection","Connection",
        "RBXScriptConnection","connection","SignalConnection","Thread","Fire",
        "Defer","Disable","Enable","Disconnect",
    }
    for index,connection in ipairs(connections) do
        local origin="UIS.InputChanged.getconnections["..tostring(index).."]"
        local exact,identityField=connectionEquals(connection,target)
        local fieldSummary={}
        for _,key in ipairs(knownFields) do
            local fieldOk,value,fieldError=safeField(connection,key)
            if fieldOk then
                fieldSummary[#fieldSummary+1]=key.."="..valueType(value)..(value==target and "=TARGET" or "")
            else
                fieldSummary[#fieldSummary+1]=key.."=<error:"..cleanText(fieldError,55)..">"
            end
        end
        addEvidence("CONNECTION",origin.." wrapper="..describeValue(connection).." exact="..tostring(exact).." identity="..identityField.." fields={"..table.concat(fieldSummary,", ").."}")

        local fn,observedFunctionType=safeConnectionFunction(connection)
        local functionRecord
        local score=exact and 1000 or 0
        if fn then
            discoveryStats.connectionFunctions+=1
            functionRecord=inspectFunction(fn,controller,origin..".Function",0)
            score+=functionRecord and functionRecord.clueScore or 0
        end
        if score>discoveryScore then discoveryScore=score end

        local _,fire=safeField(connection,"Fire")
        local _,disable=safeField(connection,"Disable")
        local _,enable=safeField(connection,"Enable")
        local hasFire=type(fire)=="function"
        local canIsolate=type(disable)=="function" and type(enable)=="function"
        local directControllerReference=functionRecord and functionRecord.referencesController
            and functionRecord.referenceDepth==0
        local nestedControllerReference=functionRecord and functionRecord.referencesController
            and (functionRecord.referenceDepth or 0)>0
        local functionProven=fn~=nil and (exact or directControllerReference)
        local callbackProven=exact or (fn~=nil and directControllerReference)
        local rejection={}
        if not exact then rejection[#rejection+1]="wrapper does not map to controller.inputChangedConn" end
        if not fn then rejection[#rejection+1]="Function unavailable/observed "..observedFunctionType end
        if nestedControllerReference and not exact then
            rejection[#rejection+1]="only a nested controller reference was found; insufficient proof for automatic hooking"
        elseif fn and not directControllerReference and not exact then
            rejection[#rejection+1]="Function/upvalues do not reference active controller"
        end
        if not hasFire then rejection[#rejection+1]="Fire unavailable" end
        if not canIsolate then rejection[#rejection+1]="Disable/Enable isolation unavailable" end

        if callbackProven then
            discoveryStats.candidatesFound+=1
            local proof={connection=connection,fn=fn,score=score,origin=origin,exact=exact,identityField=identityField}
            if not bestProof or proof.score>bestProof.score then bestProof=proof end
        end
        if functionProven then
            local candidate={connection=connection,fn=fn,score=score,origin=origin,exact=exact,identityField=identityField}
            if not bestHook or candidate.score>bestHook.score then bestHook=candidate end
        end
        if exact and hasFire and canIsolate then
            local candidate={connection=connection,score=score,origin=origin,exact=true,identityField=identityField}
            if not bestFire or candidate.score>bestFire.score then bestFire=candidate end
        end
        if callbackProven then
            addEvidence("CANDIDATE",origin.." accepted candidate score="..tostring(score).." hook="..tostring(functionProven).." wrapperFire="..tostring(exact and hasFire and canIsolate).." proof="..identityField)
        else
            addEvidence("REJECTION",origin.." rejected: "..table.concat(rejection,"; ").." score="..tostring(score))
        end
    end
    getgenv().PCV601DiscoveryScore=discoveryScore
    return bestHook,bestFire,bestProof
end

local function installHookRoute(controller,candidate)
    if not candidate then return false,"no-proven-function-candidate" end
    if type(hookfunction)~="function" then return false,"hookfunction-unavailable" end
    local original
    local replacement
    replacement=function(input,processed,...)
        local inputType
        pcall(function() inputType=input.UserInputType end)
        if inputType~=Enum.UserInputType.Touch then
            return original(input,processed,...)
        end
        local results=processTouch(controller,input,processed,original,...)
        return unpackCallbackResults(results)
    end
    local success,old=pcall(function() return hookfunction(candidate.fn,replacement) end)
    if not success or type(old)~="function" then
        return false,"hookfunction failed: "..cleanText(old,180)
    end
    original=old
    activeTarget=candidate.fn
    activeOriginal=old
    activeConnectionWrapper=candidate.connection
    activeScore=candidate.score
    activeRoute="hookfunction"
    fallbackRestoreDetail="hook-active-not-yet-restored"
    callbackFound=true
    callbackFoundOrigin=candidate.origin..".Function proof="..candidate.identityField
    fallbackReason="none-pending-execution"
    getgenv().PCInputBridgeMode="v601-callback-found-hook-installed"
    getgenv().PCInputBridgeDiscovery="callback-found-not-yet-executed"
    addEvidence("ACTIVATION","hook route installed origin="..candidate.origin.." score="..tostring(candidate.score).." proof="..candidate.identityField)
    return true,"installed"
end

local function installWrapperFireRoute(controller,candidate)
    if not candidate then return false,"no-exact-wrapper-fire-candidate" end
    local disabled,disableDetail=disableWrapper(candidate.connection)
    if not disabled then return false,"exact wrapper could not be isolated: "..disableDetail end

    local relay
    local connectOk,connectError=pcall(function()
        relay=UserInputService.InputChanged:Connect(function(input,processed,...)
            local inputType
            pcall(function() inputType=input.UserInputType end)
            local function dispatch(...)
                local fired,detail=invokeWrapperMethod(candidate.connection,"Fire",...)
                if not fired then error(detail,0) end
            end
            if inputType==Enum.UserInputType.Touch then
                processTouch(controller,input,processed,dispatch,...)
            else
                local pass=table.pack(pcall(dispatch,input,processed,...))
                if not pass[1] then
                    failedEvents+=1
                    requestRuntimeFallback("wrapper-fire-passthrough-error",cleanText(pass[2],180))
                end
            end
        end)
    end)
    if not connectOk or not relay then
        local restored,restoreDetail=enableWrapper(candidate.connection)
        fallbackRestoreOk=restored
        fallbackRestoreDetail="failed-install wrapper restore="..tostring(restored)..":"..tostring(restoreDetail)
        return false,"relay connection failed: "..cleanText(connectError,180).."; original wrapper restored="..tostring(restored)..":"..tostring(restoreDetail)
    end

    activeConnectionWrapper=candidate.connection
    activeRelayConnection=relay
    activeWrapperDisabled=true
    activeScore=candidate.score
    activeRoute="wrapper-fire"
    fallbackRestoreDetail="wrapper-isolated-not-yet-restored"
    callbackFound=true
    callbackFoundOrigin=candidate.origin.." proof="..candidate.identityField
    fallbackReason="none-pending-execution"
    getgenv().PCInputBridgeMode="v601-callback-found-wrapper-fire-installed"
    getgenv().PCInputBridgeDiscovery="callback-found-not-yet-executed"
    addEvidence("ACTIVATION","wrapper Fire route installed origin="..candidate.origin.." isolation="..disableDetail.." proof="..candidate.identityField)
    return true,"installed"
end

local function installRelay(controller)
    if type(controller)~="table" then
        setFallback("active-controller-missing","GetActiveCameraController did not return a table")
        return false
    end
    discoveryComplete=true
    local bestHook,bestFire,bestProof=discoverCandidates(controller)
    task.spawn(function() scanAlternativeSurfaces(controller,bestHook==nil) end)
    if bestProof then
        callbackFound=true
        callbackFoundOrigin=bestProof.origin..(bestProof.fn and ".Function" or "").." proof="..bestProof.identityField
        addEvidence("DISCOVERY","callback identity proven before activation: "..callbackFoundOrigin)
    end
    local installed,hookDetail=installHookRoute(controller,bestHook)
    if installed then return true end
    addEvidence("ACTIVATION","hook route rejected/failed: "..hookDetail)

    local fireInstalled,fireDetail=installWrapperFireRoute(controller,bestFire)
    if fireInstalled then return true end
    addEvidence("ACTIVATION","wrapper Fire route rejected/failed: "..fireDetail)

    if discoveryStats.candidatesFound==0 then
        setFallback("callback-unproven","no exact wrapper and no function referencing the active controller")
    else
        setFallback("callback-route-install-failed","hook="..hookDetail.."; wrapperFire="..fireDetail)
    end
    return false
end

local function resetForController()
    restoreActiveRoute(false)
    evidence={}
    evidenceDropped=0
    inspectedFunctions={}
    for key in pairs(discoveryStats) do discoveryStats[key]=0 end
    activeScore=0
    discoveryScore=-1
    discoveryComplete=false
    callbackFound=false
    callbackFoundOrigin="none"
    callbackExecutedEvents=0
    realTouchCallbackEvents=0
    syntheticAttempts=0
    syntheticAcceptedEvents=0
    syntheticRejectedEvents=0
    rotateInputChangedEvents=0
    rotateInputUnchangedEvents=0
    relayedEvents=0
    ignoredEvents=0
    failedEvents=0
    consecutiveIgnored=0
    lastAppliedRotation=Vector2.zero
    lastRotateBefore=nil
    lastRotateAfter=nil
    lastSyntheticStatus="not-attempted"
    lastTouchEligibility="not-evaluated"
    relayGate="not-evaluated"
    lastReportedGate=nil
    unobservedLockWarningLogged=false
    fallbackReason="discovery-pending"
    lastFallbackEvidence=nil
    fallbackRestoreOk=true
    fallbackRestoreDetail="not-needed"
    gcScanStatus="not-needed"
    alternativeScanStatus="not-started"
    autoDisabled=false
    hardUnavailable=false
    getgenv().PCInputBridgeMode="v601-initializing-over-v500"
    getgenv().PCInputBridgeDiscovery="pending"
end

RunService:BindToRenderStep(WATCH_BIND,Enum.RenderPriority.Camera.Value-4,function()
    local controller=getActiveController()
    if controller~=activeController then
        resetForController()
        activeController=controller
        lastHookAttempt=0
    end

    if type(controller)~="table" then
        if os.clock()-lastHookAttempt>=0.75 then
            lastHookAttempt=os.clock()
            setFallback("active-controller-pending","PlayerModule camera controller is not available yet")
        end
        return
    end
    if discoveryComplete or hardUnavailable then return end
    if os.clock()-lastHookAttempt<0.75 then return end
    lastHookAttempt=os.clock()
    local ok,err=pcall(function() installRelay(controller) end)
    if not ok then
        discoveryComplete=true
        setFallback("discovery-runtime-error",cleanText(err,240))
    end
end)

activeController=getActiveController()
if activeController then
    local ok,err=pcall(function() installRelay(activeController) end)
    if not ok then
        discoveryComplete=true
        setFallback("discovery-runtime-error",cleanText(err,240))
    end
else
    setFallback("active-controller-pending","PlayerModule camera controller is not available yet")
end

getgenv().PCV601Diagnostics=function()
    local controller=getActiveController()
    local currentGate=type(controller)=="table" and relayGateReason(controller) or "active-controller-missing"
    local bridgeMode=getgenv().PCInputBridgeMode
    local fallbackActive=string.sub(tostring(bridgeMode),1,8)=="fallback"
    local result={
        version=getgenv().PCMovementVersion,
        bridgeMode=bridgeMode,
        discovery=getgenv().PCInputBridgeDiscovery,
        discoveryComplete=discoveryComplete,
        discoveryScore=discoveryScore,
        activeRouteScore=activeScore,
        candidatesFound=discoveryStats.candidatesFound,
        connectionsFound=discoveryStats.connectionsFound,
        connectionFunctions=discoveryStats.connectionFunctions,
        controllerFunctions=discoveryStats.controllerFunctions,
        metatableFunctions=discoveryStats.metatableFunctions,
        moduleFunctions=discoveryStats.moduleFunctions,
        nestedFunctions=discoveryStats.nestedFunctions,
        functionsExamined=discoveryStats.functionsExamined,
        upvaluesExamined=discoveryStats.upvaluesExamined,
        constantsExamined=discoveryStats.constantsExamined,
        evidenceLines=#evidence,
        evidenceDropped=evidenceDropped,
        gcScanStatus=gcScanStatus,
        alternativeScanStatus=alternativeScanStatus,
        gcObjectsExamined=discoveryStats.gcObjectsExamined,
        gcFunctionsExamined=discoveryStats.gcFunctionsExamined,
        callbackFound=callbackFound,
        callbackFoundOrigin=callbackFoundOrigin,
        callbackRoute=activeRoute,
        callbackRouteInstalled=activeRoute~="none",
        callbackHooked=activeOriginal~=nil,
        callbackWrapperFireActive=activeRoute=="wrapper-fire" and activeWrapperDisabled,
        callbackExecuted=callbackExecutedEvents>0,
        callbackExecutedEvents=callbackExecutedEvents,
        realTouchCallbackEvents=realTouchCallbackEvents,
        syntheticAttempts=syntheticAttempts,
        syntheticAccepted=syntheticAcceptedEvents>0,
        syntheticAcceptedEvents=syntheticAcceptedEvents,
        syntheticRejected=syntheticRejectedEvents>0,
        syntheticRejectedEvents=syntheticRejectedEvents,
        lastSyntheticStatus=lastSyntheticStatus,
        lastTouchEligibility=lastTouchEligibility,
        rotateInputChanged=rotateInputChangedEvents>0,
        rotateInputChangedEvents=rotateInputChangedEvents,
        rotateInputUnchangedEvents=rotateInputUnchangedEvents,
        lastRotateBefore=lastRotateBefore,
        lastRotateAfter=lastRotateAfter,
        lastAppliedRotation=lastAppliedRotation,
        relayedEvents=relayedEvents,
        ignoredEvents=ignoredEvents,
        failedEvents=failedEvents,
        relayGate=currentGate,
        cameraLockObserved=type(controller)=="table" and controllerIsCameraOnlyLocked(controller) or false,
        requireObservedCameraLock=getgenv().PCV601RequireObservedCameraLock==true,
        fallbackActive=fallbackActive,
        fallbackReason=fallbackReason,
        fallbackRestoreOk=fallbackRestoreOk,
        fallbackRestoreDetail=fallbackRestoreDetail,
        fallbackV500Preserved=fallbackRestoreOk,
        validationReady=callbackFound and callbackExecutedEvents>0
            and syntheticAcceptedEvents>0 and rotateInputChangedEvents>0
            and relayedEvents>0 and activeRoute~="none"
            and not fallbackActive and not autoDisabled,
        relayEnabled=getgenv().PCV601MouseRelayEnabled~=false,
        autoFallback=getgenv().PCV601AutoFallback~=false,
        autoDisabled=autoDisabled,
        gainX=tonumber(getgenv().PCV601MouseGainX) or DEFAULT_GAIN_X,
        gainY=tonumber(getgenv().PCV601MouseGainY) or DEFAULT_GAIN_Y,
        preferredInput=tostring(UserInputService.PreferredInput),
        writesRootPartCFrame=false,
        writesCameraCFrame=false,
        forcesAutoRotate=false,
        callsUpdateMouseBehavior=false,
        forcesCameraRelative=false,
        usesGlobalFireSignal=false,
        usesVirtualMouseInjection=false,
    }
    if type(controller)=="table" then
        pcall(function() result.inMouseLockedMode=controller.inMouseLockedMode end)
        pcall(function() result.getIsMouseLocked=controller:GetIsMouseLocked() end)
        pcall(function() result.mouseLockOffset=controller.mouseLockOffset end)
        pcall(function() result.panEnabled=controller.panEnabled end)
        pcall(function() result.rotateInput=controller.rotateInput end)
        local _,target=safeField(controller,"inputChangedConn")
        result.inputChangedConnType=valueType(target)
        result.inputChangedConnValue=cleanText(target,120)
    end
    if userGameSettings then
        pcall(function() result.rotationType=tostring(userGameSettings.RotationType) end)
    end
    return result
end

local function warnEvidenceChunks(lines)
    local chunk={}
    local length=0
    local index=1
    local function flush()
        if #chunk==0 then return end
        warn("=== PC MOVEMENT V601 EVIDENCE CHUNK "..tostring(index).." ===\n"..table.concat(chunk,"\n"))
        index+=1
        chunk={}
        length=0
    end
    for _,line in ipairs(lines) do
        if length+#line+1>2600 then flush() end
        chunk[#chunk+1]=line
        length+=#line+1
    end
    flush()
end

getgenv().PCV601Evidence=function()
    local header={
        "Evidence is observational unless an [ACTIVATION] line says installed.",
        "Automatic routes are restricted to a proven callback Function or an exact LuaConnection wrapper with reversible isolation.",
        "Evidence lines stored="..tostring(#evidence).." dropped-after-cap="..tostring(evidenceDropped),
    }
    local lines={}
    for _,line in ipairs(header) do lines[#lines+1]=line end
    for _,line in ipairs(evidence) do lines[#lines+1]=line end
    warnEvidenceChunks(lines)
    return "=== PC MOVEMENT V601 DETAILED EVIDENCE ===\n"..table.concat(lines,"\n")
end

getgenv().PCV601Report=function(includeEvidence)
    local diagnostics=getgenv().PCV601Diagnostics()
    local keys={
        "version","bridgeMode","discovery","discoveryComplete","discoveryScore","activeRouteScore",
        "candidatesFound","connectionsFound","connectionFunctions","controllerFunctions",
        "metatableFunctions","moduleFunctions","nestedFunctions","functionsExamined",
        "upvaluesExamined","constantsExamined","evidenceLines","evidenceDropped",
        "alternativeScanStatus","gcScanStatus","gcObjectsExamined",
        "gcFunctionsExamined","callbackFound","callbackFoundOrigin","callbackRoute",
        "callbackRouteInstalled","callbackHooked","callbackWrapperFireActive",
        "callbackExecuted","callbackExecutedEvents","realTouchCallbackEvents",
        "syntheticAttempts","syntheticAccepted","syntheticAcceptedEvents",
        "syntheticRejected","syntheticRejectedEvents","lastSyntheticStatus","lastTouchEligibility",
        "rotateInputChanged","rotateInputChangedEvents","rotateInputUnchangedEvents",
        "lastRotateBefore","lastRotateAfter","lastAppliedRotation","relayedEvents",
        "ignoredEvents","failedEvents","relayGate","cameraLockObserved",
        "requireObservedCameraLock","fallbackActive","fallbackReason",
        "fallbackRestoreOk","fallbackRestoreDetail","fallbackV500Preserved",
        "validationReady","relayEnabled","autoFallback",
        "autoDisabled","gainX","gainY","preferredInput","rotationType",
        "inMouseLockedMode","getIsMouseLocked","mouseLockOffset","panEnabled",
        "rotateInput","inputChangedConnType","inputChangedConnValue",
        "writesRootPartCFrame","writesCameraCFrame","forcesAutoRotate",
        "callsUpdateMouseBehavior","forcesCameraRelative","usesGlobalFireSignal",
        "usesVirtualMouseInjection",
    }
    local lines={"=== PC MOVEMENT V601 REPORT ==="}
    for _,key in ipairs(keys) do
        lines[#lines+1]=key.." = "..tostring(diagnostics[key])
    end
    local summary=table.concat(lines,"\n")
    warn(summary)
    local details=""
    if includeEvidence~=false then details=getgenv().PCV601Evidence() end
    return details~="" and summary.."\n\n"..details or summary
end

getgenv().__PCMobileAimCleanup=function()
    pcall(function() RunService:UnbindFromRenderStep(WATCH_BIND) end)
    restoreActiveRoute(false)

    getgenv().PCV601Diagnostics=nil
    getgenv().PCV601Evidence=nil
    getgenv().PCV601Report=nil
    getgenv().PCV601DiscoveryScore=nil

    if baseCleanup then pcall(baseCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

warn(string.format(
    "[V601] callback discovery ready | mode=%s | discovery=%s | score=%s | candidates=%d | gains unchanged=(%.3f, %.3f)",
    tostring(getgenv().PCInputBridgeMode),
    tostring(getgenv().PCInputBridgeDiscovery),
    tostring(discoveryScore),
    discoveryStats.candidatesFound,
    tonumber(getgenv().PCV601MouseGainX) or DEFAULT_GAIN_X,
    tonumber(getgenv().PCV601MouseGainY) or DEFAULT_GAIN_Y
))
