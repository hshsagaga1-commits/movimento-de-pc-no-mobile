local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local WATCH_BIND="__PCMovementV602NativeMouseWatch"

--[[
    V602 / INHERITED CALLBACK + FUTURE CONNECT PROBE

    V500 proved that MovementRelative + camera-only mouse lock removes most of
    V26's character/camera coupling. V602 keeps that entire foundation and
    changes only the camera input path:

      touch delta -> proven Legacy camera InputChanged callback as MouseMovement

    Unlike V26, this layer NEVER calls UpdateMouseBehavior and NEVER selects
    CameraRelative. The proxy also reports the viewport center as Position, so
    every packet behaves like a centered relative-mouse packet instead of a
    touch-orbit position.

    Delta exposed LuaConnection as a boolean in V601, so wrapper identity cannot
    be reconstructed after the connection already exists. V602 first walks the
    complete controller inheritance graph: getmetatable(table), then table-valued
    __index chains, with table/function deduplication and origin/depth evidence.

    Activation order:
      1. cross-link an inherited input method with functions reachable from the
         existing UIS.InputChanged connection closures;
      2. only if no inherited stage is proved, observe future InputChanged:Connect
         calls and compare the returned connection directly with inputChangedConn;
      3. otherwise keep untouched V500 touch camera behavior.

    The future-Connect observer forwards the original callback unchanged. It does
    not trigger a reconnect. firesignal and VirtualInputManager are not solutions.
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

getgenv().PCMovementVersion="V602-InheritedCallbackProbe"
getgenv().PCInputBridgeMode="v602-initializing-over-v500"
getgenv().PCInputBridgeDiscovery="pending"

if getgenv().PCV602MouseRelayEnabled==nil then getgenv().PCV602MouseRelayEnabled=true end
if getgenv().PCV602AutoFallback==nil then getgenv().PCV602AutoFallback=true end
if getgenv().PCV602RequireObservedCameraLock==nil then
    getgenv().PCV602RequireObservedCameraLock=false
end

-- X9 measured the real V20 angular response in the active Legacy controller.
-- These gains preserve that response while changing semantics/path only.
local V20_TOUCH_RAD_X=0.029688168050806058
local V20_TOUCH_RAD_Y=0.010602966305655836
local LEGACY_MOUSE_RAD_X=(math.pi*4)/1920
local LEGACY_MOUSE_RAD_Y=(math.pi*1.9)/1200
local DEFAULT_GAIN_X=V20_TOUCH_RAD_X/LEGACY_MOUSE_RAD_X
local DEFAULT_GAIN_Y=V20_TOUCH_RAD_Y/LEGACY_MOUSE_RAD_Y

if getgenv().PCV602MouseGainX==nil then getgenv().PCV602MouseGainX=DEFAULT_GAIN_X end
if getgenv().PCV602MouseGainY==nil then getgenv().PCV602MouseGainY=DEFAULT_GAIN_Y end

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
local hierarchyScanStatus="not-started"
local hierarchyStageFound=false
local hierarchyStageOrigin="none"
local hierarchyStageScore=0
local hierarchyStageActivationKind="none"
local hierarchyBestCandidateOrigin="none"
local hierarchyBestCandidateScore=0
local hierarchyBestCandidateKind="none"
local hierarchyLevelsVisited=0
local hierarchyTablesDeduped=0
local hierarchyFunctionsEnumerated=0
local hierarchyRelevantFunctions=0
local hierarchyInputObjectLikely=0
local hierarchyInputChangedConnRefs=0
local hierarchyCrossLinks=0
local hierarchyMaxDepth=0
local connectionFunctionGraph={}
local connectionGraphFunctions=0
local activeInputChangedConnTarget=nil
local connectObserverInstalled=false
local connectObserverMode="none"
local connectObserverStatus="not-needed"
local connectObserverTarget=nil
local connectObserverOriginal=nil
local namecallObserverOriginal=nil
local futureConnectsSeen=0
local futureCallbacksCaptured=0
local futureCameraCallbacksProven=0
local lastFutureCallbackOrigin="none"
local lastFutureCallbackStatus="not-seen"
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
    connectionGraphFunctions=0,
    hierarchyLevels=0,
    hierarchyFunctions=0,
    hierarchyRelevantFunctions=0,
    futureConnects=0,
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
    if getgenv().PCV602MouseRelayEnabled==false then return "relay-disabled" end
    if autoDisabled then return "auto-fallback-active" end
    if not touchPreferred() then return "preferred-input-not-touch" end
    if controller~=getActiveController() then return "controller-no-longer-active" end
    if getgenv().PCV500CameraOnlyLockEnabled==false then return "v500-camera-only-lock-disabled" end
    if getgenv().PCV602RequireObservedCameraLock==true
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
    local argCount=nil
    local isVararg=nil
    if debug and type(debug.info)=="function" then
        pcall(function() name=cleanText(debug.info(fn,"n") or "?",80) end)
        pcall(function() line=cleanText(debug.info(fn,"l") or "?",30) end)
        pcall(function()
            local count,vararg=debug.info(fn,"a")
            argCount=count
            isVararg=vararg
            args=tostring(count)..(vararg and "+vararg" or "")
        end)
    elseif debug and type(debug.getinfo)=="function" then
        pcall(function()
            local info=debug.getinfo(fn)
            name=cleanText(info and info.name or "?",80)
            line=cleanText(info and (info.linedefined or info.currentline) or "?",30)
            if info and info.nparams~=nil then
                argCount=info.nparams
                isVararg=info.isvararg
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
    return string.format("kind=%s args=%s name=%s source=%s line=%s id=%s",closure,args,name,source,line,cleanText(fn,90)),source,name,argCount,isVararg,closure
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
        referencesInputChangedConn=false,
        constantsLower={},
        argCount=nil,
        isVararg=nil,
        closureKind="unknown",
        clueScore=0,
    }
    inspectedFunctions[fn]=record
    discoveryStats.functionsExamined+=1
    if depth and depth>0 then discoveryStats.nestedFunctions+=1 end

    local signature,source,name,argCount,isVararg,closureKind=functionSignature(fn)
    record.argCount=argCount
    record.isVararg=isVararg
    record.closureKind=closureKind
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
            record.constantsLower[lower]=true
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
        if activeInputChangedConnTarget~=nil and value==activeInputChangedConnTarget then
            record.referencesInputChangedConn=true
        end
        if #upvalueSummary<32 then
            local marker=value==controller and "=ACTIVE_CONTROLLER" or ""
            if activeInputChangedConnTarget~=nil and value==activeInputChangedConnTarget then
                marker=marker.."=INPUTCHANGED_CONN"
            end
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
        if childRecord and childRecord.referencesInputChangedConn then
            record.referencesInputChangedConn=true
        end
    end
    if record.referencesController then
        record.clueScore+=record.referenceDepth==0 and 200 or 120
    end
    return record
end

local function mapConnectionFunctionGraph(fn,controller,origin,depth,seen)
    if type(fn)~="function" or depth>5 or connectionGraphFunctions>=320 then return end
    seen=seen or {}
    if seen[fn] then return end
    seen[fn]=true

    local graphRecord=connectionFunctionGraph[fn]
    if not graphRecord then
        graphRecord={minDepth=depth,origins={}}
        connectionFunctionGraph[fn]=graphRecord
        connectionGraphFunctions+=1
        discoveryStats.connectionGraphFunctions=connectionGraphFunctions
    elseif depth<graphRecord.minDepth then
        graphRecord.minDepth=depth
    end
    if #graphRecord.origins<6 then graphRecord.origins[#graphRecord.origins+1]=origin end
    inspectFunction(fn,controller,origin,depth)

    local upvalues=getUpvalueEntries(fn)
    local followed=0
    for index,entry in ipairs(upvalues) do
        if type(entry.value)=="function" and followed<20 then
            followed+=1
            mapConnectionFunctionGraph(
                entry.value,
                controller,
                origin.." -> upvalue["..tostring(index)..":"..entry.name.."]",
                depth+1,
                seen
            )
        end
    end

    local protoGetter=(debug and debug.getprotos) or getprotos
    if type(protoGetter)=="function" and depth<3 then
        local ok,protos=pcall(protoGetter,fn)
        if ok and type(protos)=="table" then
            local retained=0
            for index,proto in ipairs(protos) do
                if type(proto)=="function" and retained<12 then
                    retained+=1
                    mapConnectionFunctionGraph(proto,controller,origin.." -> proto["..tostring(index).."]",depth+1,seen)
                end
            end
        end
    end
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
    local gainX=tonumber(getgenv().PCV602MouseGainX) or DEFAULT_GAIN_X
    local gainY=tonumber(getgenv().PCV602MouseGainY) or DEFAULT_GAIN_Y

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
    if getgenv().PCV602AutoFallback~=false and consecutiveIgnored>=12 then
        requestRuntimeFallback("synthetic-no-rotateinput-change",reason.." after "..tostring(consecutiveIgnored).." packets")
        warn("[V602] synthetic packets produced no rotateInput change; restoring V500 fallback")
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
            warn("[V602] failed to restore the original V500 camera callback route: "..fallbackRestoreDetail)
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
        addEvidence("RUNTIME","camera-only lock was not observable, but the discovery experiment proceeded because PCV602RequireObservedCameraLock=false; this matches the V600 test state and is reported separately")
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
        if getgenv().PCV602AutoFallback~=false and syntheticRejectedEvents>=3 then
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

local METHOD_KEYWORDS={
    "inputchanged","input","mouse","touch","rotate","camerainput","camera",
    "enable","disable",
}

local function relevantMethodName(name)
    local lower=string.lower(tostring(name))
    for _,needle in ipairs(METHOD_KEYWORDS) do
        if string.find(lower,needle,1,true) then return true,needle end
    end
    return false,"none"
end

local function likelyReceivesUserInputObject(record,methodName)
    if not record then return false,"no-function-record" end
    local constants=record.constantsLower or {}
    local inputConstants=constants.userinputtype or constants.userinputstate
        or constants.mousemovement or constants.touch or constants.keycode
        or constants.delta or constants.position or constants.userinputobject
    local lower=string.lower(tostring(methodName))
    local inputName=string.find(lower,"input",1,true)~=nil
        or string.find(lower,"mouse",1,true)~=nil
        or string.find(lower,"touch",1,true)~=nil
    -- This is only a heuristic for the report. Automatic activation below is
    -- stricter and requires observable self + UserInputObject-compatible arity.
    local arityCompatible=record.argCount==nil or record.argCount>=2 or record.isVararg==true
    local likely=(inputConstants or inputName) and arityCompatible
    local reason=string.format(
        "nameInput=%s constantsInput=%s argCount=%s vararg=%s",
        tostring(inputName),tostring(inputConstants and true or false),
        tostring(record.argCount),tostring(record.isVararg)
    )
    return likely,reason
end

local function hierarchyMethodScore(methodName,record,graphRecord,inputLikely)
    local lower=string.lower(tostring(methodName))
    local score=0
    if lower=="inputchanged" or lower=="oninputchanged" or lower=="handleinputchanged" then score+=120 end
    if string.find(lower,"inputchanged",1,true) then score+=80 end
    if string.find(lower,"input",1,true) then score+=20 end
    if string.find(lower,"mouse",1,true) then score+=18 end
    if string.find(lower,"touch",1,true) then score+=18 end
    if string.find(lower,"rotate",1,true) then score+=16 end
    if string.find(lower,"camera",1,true) then score+=12 end
    if lower=="enable" or lower=="disable" then score+=8 end
    if inputLikely then score+=60 end
    if record and record.referencesInputChangedConn then score+=900 end
    if graphRecord then score+=1000 end
    if record then score+=record.clueScore or 0 end
    return score
end

local function scanInheritedController(controller,target)
    hierarchyScanStatus="running"
    hierarchyStageFound=false
    hierarchyStageOrigin="none"
    hierarchyStageScore=0
    hierarchyStageActivationKind="none"
    hierarchyBestCandidateOrigin="none"
    hierarchyBestCandidateScore=0
    hierarchyBestCandidateKind="none"
    local seenTables={}
    local seenFunctions={}
    local maxDepth=math.max(2,math.min(tonumber(getgenv().PCV602InheritanceMaxDepth) or 16,32))
    local bestCandidate=nil
    local bestProvenCandidate=nil

    local function visit(tbl,depth,origin)
        if type(tbl)~="table" then
            addEvidence("HIERARCHY",string.format("depth=%d origin=%s rejected-non-table type=%s",depth,origin,valueType(tbl)))
            return
        end
        if depth>maxDepth then
            addEvidence("HIERARCHY",string.format("depth=%d origin=%s rejected-max-depth=%d",depth,origin,maxDepth))
            return
        end
        if seenTables[tbl] then
            hierarchyTablesDeduped+=1
            addEvidence("HIERARCHY",string.format("depth=%d origin=%s deduped firstOrigin=%s",depth,origin,seenTables[tbl]))
            return
        end
        seenTables[tbl]=origin
        hierarchyLevelsVisited+=1
        discoveryStats.hierarchyLevels=hierarchyLevelsVisited
        hierarchyMaxDepth=math.max(hierarchyMaxDepth,depth)

        local entries={}
        local ok,err=pcall(function()
            for key,value in pairs(tbl) do
                entries[#entries+1]={rawKey=key,key=cleanText(key,100),value=value}
            end
        end)
        if not ok then
            addEvidence("HIERARCHY",string.format("depth=%d origin=%s enumeration-error=%s",depth,origin,cleanText(err,180)))
            return
        end
        table.sort(entries,function(a,b) return a.key<b.key end)
        addEvidence("HIERARCHY",string.format("depth=%d origin=%s table=%s keys=%d",depth,origin,cleanText(tbl,100),#entries))

        local indexTable=nil
        for _,entry in ipairs(entries) do
            local keyLower=string.lower(entry.key)
            if keyLower=="inputchangedconn" or entry.value==target then
                hierarchyInputChangedConnRefs+=1
                addEvidence("HIERARCHY-CONNREF",string.format(
                    "depth=%d origin=%s key=%s valueType=%s equalsControllerTarget=%s value=%s",
                    depth,origin,entry.key,valueType(entry.value),tostring(entry.value==target),cleanText(entry.value,120)
                ))
            end
            if entry.rawKey=="__index" and type(entry.value)=="table" then indexTable=entry.value end

            if type(entry.value)=="function" then
                hierarchyFunctionsEnumerated+=1
                discoveryStats.hierarchyFunctions=hierarchyFunctionsEnumerated
                local relevant,matchedKeyword=relevantMethodName(entry.key)
                local duplicateOrigin=seenFunctions[entry.value]
                addEvidence("HIERARCHY-METHOD",string.format(
                    "depth=%d origin=%s key=%s relevant=%s keyword=%s function=%s duplicateOf=%s",
                    depth,origin,entry.key,tostring(relevant),matchedKeyword,
                    cleanText(entry.value,100),tostring(duplicateOrigin or "none")
                ))
                if not duplicateOrigin then seenFunctions[entry.value]=origin.."."..entry.key end

                if relevant then
                    hierarchyRelevantFunctions+=1
                    discoveryStats.hierarchyRelevantFunctions=hierarchyRelevantFunctions
                    local methodOrigin=string.format("hierarchy depth=%d %s.%s",depth,origin,entry.key)
                    local record=inspectFunction(entry.value,controller,methodOrigin,0)
                    local graphRecord=connectionFunctionGraph[entry.value]
                    local inputLikely,inputReason=likelyReceivesUserInputObject(record,entry.key)
                    if inputLikely then hierarchyInputObjectLikely+=1 end
                    if record and record.referencesInputChangedConn then hierarchyInputChangedConnRefs+=1 end
                    if graphRecord then hierarchyCrossLinks+=1 end
                    local score=hierarchyMethodScore(entry.key,record,graphRecord,inputLikely)
                    local directConnectionCallback=graphRecord and graphRecord.minDepth==0
                    local activationKind=directConnectionCallback and "connection-callback" or "inherited-method"
                    local argsCompatible=record and (
                        (directConnectionCallback and type(record.argCount)=="number" and record.argCount>=1)
                        or ((not directConnectionCallback) and type(record.argCount)=="number" and record.argCount>=2)
                        or record.isVararg==true
                    )
                    local proof=(graphRecord~=nil or (record and record.referencesInputChangedConn))
                        and inputLikely and argsCompatible
                    local graphOrigins="none"
                    if graphRecord then graphOrigins=table.concat(graphRecord.origins," | ") end
                    addEvidence("HIERARCHY-CANDIDATE",string.format(
                        "depth=%d origin=%s key=%s score=%d userInputObjectLikely=%s inputReason={%s} connectionGraphCrossLink=%s graphDepth=%s graphOrigins={%s} referencesInputChangedConn=%s activationKind=%s argsCompatible=%s proof=%s",
                        depth,origin,entry.key,score,tostring(inputLikely),inputReason,
                        tostring(graphRecord~=nil),tostring(graphRecord and graphRecord.minDepth or "none"),graphOrigins,
                        tostring(record and record.referencesInputChangedConn or false),activationKind,
                        tostring(argsCompatible),tostring(proof)
                    ))
                    local candidate={
                        fn=entry.value,
                        methodName=entry.key,
                        origin=origin.."."..entry.key,
                        depth=depth,
                        score=score,
                        record=record,
                        graphRecord=graphRecord,
                        inputLikely=inputLikely,
                        activationKind=activationKind,
                        proof=proof,
                    }
                    if not bestCandidate or candidate.score>bestCandidate.score then bestCandidate=candidate end
                    if proof and (not hierarchyStageFound or score>hierarchyStageScore) then
                        hierarchyStageFound=true
                        hierarchyStageOrigin=candidate.origin
                        hierarchyStageScore=score
                        hierarchyStageActivationKind=activationKind
                        bestProvenCandidate=candidate
                    end
                end
            end
        end

        local metatable=nil
        if type(getrawmetatable)=="function" then pcall(function() metatable=getrawmetatable(tbl) end) end
        if type(metatable)~="table" then pcall(function() metatable=getmetatable(tbl) end) end
        if type(metatable)=="table" then visit(metatable,depth+1,origin.." -> getmetatable") end
        if type(indexTable)=="table" then visit(indexTable,depth+1,origin.." -> __index") end
    end

    visit(controller,0,"controller")
    if bestCandidate then
        hierarchyBestCandidateOrigin=bestCandidate.origin
        hierarchyBestCandidateScore=bestCandidate.score
        hierarchyBestCandidateKind=bestCandidate.activationKind
    end
    hierarchyScanStatus="complete"
    alternativeScanStatus="replaced-by-recursive-hierarchy"
    gcScanStatus="skipped-v602-inheritance-and-future-connect-only"
    addEvidence("HIERARCHY-SUMMARY",string.format(
        "levels=%d dedupedTables=%d maxDepth=%d methods=%d relevantMethods=%d likelyUserInputObject=%d inputChangedConnRefs=%d connectionCrossLinks=%d stageFound=%s stageOrigin=%s stageScore=%d activationKind=%s",
        hierarchyLevelsVisited,hierarchyTablesDeduped,hierarchyMaxDepth,
        hierarchyFunctionsEnumerated,hierarchyRelevantFunctions,hierarchyInputObjectLikely,
        hierarchyInputChangedConnRefs,hierarchyCrossLinks,tostring(hierarchyStageFound),
        hierarchyStageOrigin,hierarchyStageScore,hierarchyStageActivationKind
    ))
    return bestProvenCandidate,bestCandidate
end

local function discoverCandidates(controller)
    local targetOk,target,targetError=safeField(controller,"inputChangedConn")
    activeInputChangedConnTarget=target
    addEvidence("DISCOVERY","active controller="..describeValue(controller))
    addEvidence("DISCOVERY","controller.inputChangedConn access="..tostring(targetOk).." type="..valueType(target)..(targetError and " error="..targetError or "").." value="..cleanText(target,120))
    addEvidence("CAPABILITY",string.format(
        "getconnections=%s hookfunction=%s hookmetamethod=%s getnamecallmethod=%s firesignal=%s getgc=%s getcallbackvalue=%s getscriptclosure=%s debug.info=%s debug.getupvalues=%s getupvalues=%s wrapper-Fire=examined-per-candidate",
        type(getconnections),type(hookfunction),type(hookmetamethod),type(getnamecallmethod),type(firesignal),type(getgc),
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
            mapConnectionFunctionGraph(fn,controller,origin..".Function",0,{})
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
    getgenv().PCV602DiscoveryScore=discoveryScore
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
    getgenv().PCInputBridgeMode="v602-callback-found-hook-installed"
    getgenv().PCInputBridgeDiscovery="callback-found-not-yet-executed"
    addEvidence("ACTIVATION","hook route installed origin="..candidate.origin.." score="..tostring(candidate.score).." proof="..candidate.identityField)
    return true,"installed"
end

local function installInheritedMethodRoute(controller,candidate)
    if not candidate or not candidate.proof then return false,"no-proven-inherited-method" end
    if candidate.activationKind~="inherited-method" then return false,"candidate is a direct connection callback" end
    if type(hookfunction)~="function" then return false,"hookfunction-unavailable" end
    local record=candidate.record
    if not record or not (
        (type(record.argCount)=="number" and record.argCount>=2)
        or record.isVararg==true
    ) then
        return false,"inherited method self + UserInputObject arity was not observed"
    end

    local original
    local replacement
    replacement=function(self,input,processed,...)
        if self~=controller then return original(self,input,processed,...) end
        local inputType
        pcall(function() inputType=input.UserInputType end)
        if inputType~=Enum.UserInputType.Touch then
            return original(self,input,processed,...)
        end
        local function dispatch(nextInput,nextProcessed,...)
            return original(self,nextInput,nextProcessed,...)
        end
        local results=processTouch(controller,input,processed,dispatch,...)
        return unpackCallbackResults(results)
    end

    local success,old=pcall(function() return hookfunction(candidate.fn,replacement) end)
    if not success or type(old)~="function" then
        return false,"inherited method hook failed: "..cleanText(old,180)
    end
    original=old
    activeTarget=candidate.fn
    activeOriginal=old
    activeConnectionWrapper=nil
    activeScore=candidate.score
    activeRoute="inherited-method-hook"
    fallbackRestoreDetail="inherited-method-hook-active-not-yet-restored"
    callbackFound=true
    callbackFoundOrigin="hierarchy depth="..tostring(candidate.depth).." origin="..candidate.origin
    fallbackReason="none-pending-execution"
    getgenv().PCInputBridgeMode="v602-inherited-input-method-hook-installed"
    getgenv().PCInputBridgeDiscovery="inherited-stage-proven-not-yet-executed"
    addEvidence("ACTIVATION",string.format(
        "inherited method hook installed depth=%d origin=%s method=%s score=%d connectionCrossLink=%s referencesInputChangedConn=%s",
        candidate.depth,candidate.origin,candidate.methodName,candidate.score,
        tostring(candidate.graphRecord~=nil),
        tostring(candidate.record and candidate.record.referencesInputChangedConn or false)
    ))
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
    getgenv().PCInputBridgeMode="v602-callback-found-wrapper-fire-installed"
    getgenv().PCInputBridgeDiscovery="callback-found-not-yet-executed"
    addEvidence("ACTIVATION","wrapper Fire route installed origin="..candidate.origin.." isolation="..disableDetail.." proof="..candidate.identityField)
    return true,"installed"
end

local function restoreConnectObserver(preserveStatus)
    local restored=true
    local details={}
    if connectObserverTarget and connectObserverOriginal and type(hookfunction)=="function" then
        local ok,err=pcall(function() hookfunction(connectObserverTarget,connectObserverOriginal) end)
        restored=restored and ok
        details[#details+1]="Connect-hook="..tostring(ok)..(ok and "" or ":"..cleanText(err,140))
    end
    if namecallObserverOriginal and type(hookmetamethod)=="function" then
        local ok,err=pcall(function() hookmetamethod(game,"__namecall",namecallObserverOriginal) end)
        restored=restored and ok
        details[#details+1]="namecall-hook="..tostring(ok)..(ok and "" or ":"..cleanText(err,140))
    end
    connectObserverTarget=nil
    connectObserverOriginal=nil
    namecallObserverOriginal=nil
    connectObserverInstalled=false
    connectObserverMode="none"
    if not preserveStatus then
        connectObserverStatus=restored and "restored" or "restore-failed"
    end
    if #details>0 then addEvidence("CONNECT-OBSERVER","restore "..table.concat(details,"; ")) end
    return restored,table.concat(details,"; ")
end

local function evaluateFutureConnect(callback,returnedConnection,origin)
    futureCallbacksCaptured+=1
    discoveryStats.futureConnects=futureConnectsSeen
    lastFutureCallbackOrigin=origin
    local controller=getActiveController()
    local _,target=safeField(controller,"inputChangedConn")
    local exact=target~=nil and returnedConnection==target
    local record=inspectFunction(callback,controller,origin..".callback",0)
    mapConnectionFunctionGraph(callback,controller,origin..".callback",0,{})
    addEvidence("FUTURE-CONNECT",string.format(
        "origin=%s callbackType=%s returnedConnectionType=%s targetType=%s returnedEqualsControllerInputChangedConn=%s callbackRecord=%s",
        origin,valueType(callback),valueType(returnedConnection),valueType(target),
        tostring(exact),tostring(record~=nil)
    ))
    if not exact then
        lastFutureCallbackStatus="captured-non-camera-inputchanged-connect"
        return
    end

    futureCameraCallbacksProven+=1
    callbackFound=true
    callbackFoundOrigin=origin.." returnedConnection==controller.inputChangedConn"
    lastFutureCallbackStatus="camera-callback-proven"
    connectObserverStatus="camera-callback-proven"
    addEvidence("FUTURE-CONNECT","PROOF exact returned RBXScriptConnection equals active controller.inputChangedConn")

    if activeRoute~="none" then
        addEvidence("FUTURE-CONNECT","callback proved but an active route already exists: "..activeRoute)
        return
    end
    local candidate={
        connection=returnedConnection,
        fn=callback,
        score=2200,
        origin=origin,
        exact=true,
        identityField="future-Connect-return==controller.inputChangedConn",
    }
    local installed,detail=installHookRoute(controller,candidate)
    if installed then
        connectObserverStatus="camera-callback-captured-and-hooked"
        lastFutureCallbackStatus="camera-callback-captured-and-hooked"
        restoreConnectObserver(true)
    else
        connectObserverStatus="camera-callback-proven-hook-failed"
        lastFutureCallbackStatus="camera-callback-proven-hook-failed: "..detail
        setFallback("future-callback-hook-failed",detail)
    end
end

local function noteFutureConnect(callback,returnedConnection,mode)
    futureConnectsSeen+=1
    discoveryStats.futureConnects=futureConnectsSeen
    local origin="future UIS.InputChanged:Connect #"..tostring(futureConnectsSeen).." via "..mode
    lastFutureCallbackOrigin=origin
    lastFutureCallbackStatus="captured-awaiting-controller-assignment"
    addEvidence("FUTURE-CONNECT",origin.." callback="..describeValue(callback).." returned="..describeValue(returnedConnection))
    task.defer(function() evaluateFutureConnect(callback,returnedConnection,origin) end)
end

local function installFutureConnectObserver()
    if connectObserverInstalled then return true,"already-installed" end
    connectObserverStatus="installing"
    addEvidence("CONNECT-OBSERVER","inheritance did not prove the camera stage; installing a filtered observer for future UIS.InputChanged Connect calls without triggering reconnection")

    local connectMethod
    pcall(function() connectMethod=UserInputService.InputChanged.Connect end)
    if type(connectMethod)=="function" and type(hookfunction)=="function" then
        local original
        local replacement
        replacement=function(signal,callback,...)
            if signal~=UserInputService.InputChanged or type(callback)~="function" then
                return original(signal,callback,...)
            end
            local returned=original(signal,callback,...)
            noteFutureConnect(callback,returned,"hookfunction-Signal.Connect")
            return returned
        end
        local ok,old=pcall(function() return hookfunction(connectMethod,replacement) end)
        if ok and type(old)=="function" then
            original=old
            connectObserverTarget=connectMethod
            connectObserverOriginal=old
            connectObserverInstalled=true
            connectObserverMode="hookfunction-Signal.Connect"
            connectObserverStatus="waiting-for-future-connect"
            addEvidence("CONNECT-OBSERVER","installed mode=hookfunction-Signal.Connect; all non-InputChanged Connect calls are forwarded unchanged")
            return true,"installed-direct-connect-hook"
        end
        addEvidence("CONNECT-OBSERVER","direct Signal.Connect hook failed: "..cleanText(old,180))
    else
        addEvidence("CONNECT-OBSERVER","direct Signal.Connect hook unavailable connectMethod="..type(connectMethod).." hookfunction="..type(hookfunction))
    end

    if type(hookmetamethod)=="function" and type(getnamecallmethod)=="function" then
        local original
        local replacement
        replacement=function(self,...)
            local method=""
            pcall(function() method=getnamecallmethod() end)
            local args=table.pack(...)
            if self==UserInputService.InputChanged
                and string.lower(tostring(method))=="connect"
                and type(args[1])=="function" then
                local returned=original(self,table.unpack(args,1,args.n))
                noteFutureConnect(args[1],returned,"hookmetamethod-__namecall")
                return returned
            end
            return original(self,table.unpack(args,1,args.n))
        end
        local wrapped=replacement
        if type(newcclosure)=="function" then
            local ok,value=pcall(newcclosure,replacement)
            if ok and type(value)=="function" then wrapped=value end
        end
        local ok,old=pcall(function() return hookmetamethod(game,"__namecall",wrapped) end)
        if ok and type(old)=="function" then
            original=old
            namecallObserverOriginal=old
            connectObserverInstalled=true
            connectObserverMode="hookmetamethod-__namecall"
            connectObserverStatus="waiting-for-future-connect"
            addEvidence("CONNECT-OBSERVER","installed fallback mode=hookmetamethod-__namecall filtered to UIS.InputChanged + Connect")
            return true,"installed-namecall-hook"
        end
        addEvidence("CONNECT-OBSERVER","namecall observer failed: "..cleanText(old,180))
    else
        addEvidence("CONNECT-OBSERVER","namecall observer unavailable hookmetamethod="..type(hookmetamethod).." getnamecallmethod="..type(getnamecallmethod))
    end

    connectObserverStatus="unavailable"
    return false,"no future-Connect interception capability"
end

local function installRelay(controller)
    if type(controller)~="table" then
        setFallback("active-controller-missing","GetActiveCameraController did not return a table")
        return false
    end
    discoveryComplete=true
    local bestHook,bestFire,bestProof=discoverCandidates(controller)
    local inheritedProof=scanInheritedController(controller,activeInputChangedConnTarget)
    if bestProof then
        callbackFound=true
        callbackFoundOrigin=bestProof.origin..(bestProof.fn and ".Function" or "").." proof="..bestProof.identityField
        addEvidence("DISCOVERY","callback identity proven before activation: "..callbackFoundOrigin)
    end

    if inheritedProof then
        callbackFound=true
        callbackFoundOrigin="hierarchy proof: "..inheritedProof.origin
        local inheritedInstalled,inheritedDetail
        if inheritedProof.activationKind=="connection-callback" then
            inheritedInstalled,inheritedDetail=installHookRoute(controller,{
                connection=nil,
                fn=inheritedProof.fn,
                score=inheritedProof.score,
                origin=inheritedProof.origin,
                exact=true,
                identityField="hierarchy-method==UIS.InputChanged connection Function",
            })
        else
            inheritedInstalled,inheritedDetail=installInheritedMethodRoute(controller,inheritedProof)
        end
        if inheritedInstalled then
            connectObserverStatus="not-needed-inherited-stage-proven"
            return true
        end
        addEvidence("ACTIVATION","proven inherited stage could not be installed: "..inheritedDetail)
        setFallback("inherited-stage-install-failed",inheritedDetail)
        connectObserverStatus="not-installed-inherited-stage-already-proven"
        return false
    end

    local installed,hookDetail=installHookRoute(controller,bestHook)
    if installed then return true end
    addEvidence("ACTIVATION","hook route rejected/failed: "..hookDetail)

    local fireInstalled,fireDetail=installWrapperFireRoute(controller,bestFire)
    if fireInstalled then return true end
    addEvidence("ACTIVATION","wrapper Fire route rejected/failed: "..fireDetail)

    local observerInstalled,observerDetail=installFutureConnectObserver()
    if observerInstalled then
        setFallback(
            "awaiting-future-inputchanged-connect",
            "recursive metatable/__index scan found no proven stage; observer="..connectObserverMode
        )
    elseif discoveryStats.candidatesFound==0 then
        setFallback(
            "callback-unproven-after-inheritance",
            "no exact wrapper, no proven inherited stage, and future Connect observer unavailable: "..observerDetail
        )
    else
        setFallback(
            "callback-route-install-failed",
            "hook="..hookDetail.."; wrapperFire="..fireDetail.."; futureObserver="..observerDetail
        )
    end
    return false
end

local function resetForController()
    restoreActiveRoute(false)
    restoreConnectObserver(false)
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
    hierarchyScanStatus="not-started"
    hierarchyStageFound=false
    hierarchyStageOrigin="none"
    hierarchyStageScore=0
    hierarchyStageActivationKind="none"
    hierarchyBestCandidateOrigin="none"
    hierarchyBestCandidateScore=0
    hierarchyBestCandidateKind="none"
    hierarchyLevelsVisited=0
    hierarchyTablesDeduped=0
    hierarchyFunctionsEnumerated=0
    hierarchyRelevantFunctions=0
    hierarchyInputObjectLikely=0
    hierarchyInputChangedConnRefs=0
    hierarchyCrossLinks=0
    hierarchyMaxDepth=0
    connectionFunctionGraph={}
    connectionGraphFunctions=0
    activeInputChangedConnTarget=nil
    connectObserverInstalled=false
    connectObserverMode="none"
    connectObserverStatus="not-needed"
    connectObserverTarget=nil
    connectObserverOriginal=nil
    namecallObserverOriginal=nil
    futureConnectsSeen=0
    futureCallbacksCaptured=0
    futureCameraCallbacksProven=0
    lastFutureCallbackOrigin="none"
    lastFutureCallbackStatus="not-seen"
    autoDisabled=false
    hardUnavailable=false
    getgenv().PCInputBridgeMode="v602-initializing-over-v500"
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

getgenv().PCV602Diagnostics=function()
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
        connectionGraphFunctions=connectionGraphFunctions,
        evidenceLines=#evidence,
        evidenceDropped=evidenceDropped,
        hierarchyScanStatus=hierarchyScanStatus,
        hierarchyStageFound=hierarchyStageFound,
        hierarchyStageOrigin=hierarchyStageOrigin,
        hierarchyStageScore=hierarchyStageScore,
        hierarchyStageActivationKind=hierarchyStageActivationKind,
        hierarchyBestCandidateOrigin=hierarchyBestCandidateOrigin,
        hierarchyBestCandidateScore=hierarchyBestCandidateScore,
        hierarchyBestCandidateKind=hierarchyBestCandidateKind,
        hierarchyLevelsVisited=hierarchyLevelsVisited,
        hierarchyTablesDeduped=hierarchyTablesDeduped,
        hierarchyMaxDepth=hierarchyMaxDepth,
        hierarchyFunctionsEnumerated=hierarchyFunctionsEnumerated,
        hierarchyRelevantFunctions=hierarchyRelevantFunctions,
        hierarchyInputObjectLikely=hierarchyInputObjectLikely,
        hierarchyInputChangedConnRefs=hierarchyInputChangedConnRefs,
        hierarchyCrossLinks=hierarchyCrossLinks,
        connectObserverInstalled=connectObserverInstalled,
        connectObserverMode=connectObserverMode,
        connectObserverStatus=connectObserverStatus,
        futureConnectsSeen=futureConnectsSeen,
        futureCallbacksCaptured=futureCallbacksCaptured,
        futureCameraCallbacksProven=futureCameraCallbacksProven,
        lastFutureCallbackOrigin=lastFutureCallbackOrigin,
        lastFutureCallbackStatus=lastFutureCallbackStatus,
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
        requireObservedCameraLock=getgenv().PCV602RequireObservedCameraLock==true,
        fallbackActive=fallbackActive,
        fallbackReason=fallbackReason,
        fallbackRestoreOk=fallbackRestoreOk,
        fallbackRestoreDetail=fallbackRestoreDetail,
        fallbackV500Preserved=fallbackRestoreOk,
        validationReady=callbackFound and callbackExecutedEvents>0
            and syntheticAcceptedEvents>0 and rotateInputChangedEvents>0
            and relayedEvents>0 and activeRoute~="none"
            and not fallbackActive and not autoDisabled,
        relayEnabled=getgenv().PCV602MouseRelayEnabled~=false,
        autoFallback=getgenv().PCV602AutoFallback~=false,
        autoDisabled=autoDisabled,
        gainX=tonumber(getgenv().PCV602MouseGainX) or DEFAULT_GAIN_X,
        gainY=tonumber(getgenv().PCV602MouseGainY) or DEFAULT_GAIN_Y,
        preferredInput=tostring(UserInputService.PreferredInput),
        writesRootPartCFrame=false,
        writesCameraCFrame=false,
        forcesAutoRotate=false,
        callsUpdateMouseBehavior=false,
        forcesCameraRelative=false,
        usesGlobalFireSignal=false,
        usesVirtualMouseInjection=false,
        triggersCameraReconnect=false,
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
        warn("=== PC MOVEMENT V602 EVIDENCE CHUNK "..tostring(index).." ===\n"..table.concat(chunk,"\n"))
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

getgenv().PCV602Evidence=function()
    local header={
        "Evidence is observational unless an [ACTIVATION] line says installed.",
        "An inherited stage activates only with a connection-graph/inputChangedConn link, UserInputObject evidence, and observable compatible arity.",
        "The future Connect observer proves identity only when the returned RBXScriptConnection equals controller.inputChangedConn after assignment.",
        "V602 does not trigger a reconnect; it only observes a future UIS.InputChanged:Connect if the camera reconnects naturally.",
        "Evidence lines stored="..tostring(#evidence).." dropped-after-cap="..tostring(evidenceDropped),
    }
    local lines={}
    for _,line in ipairs(header) do lines[#lines+1]=line end
    for _,line in ipairs(evidence) do lines[#lines+1]=line end
    warnEvidenceChunks(lines)
    return "=== PC MOVEMENT V602 DETAILED EVIDENCE ===\n"..table.concat(lines,"\n")
end

getgenv().PCV602Report=function(includeEvidence)
    local diagnostics=getgenv().PCV602Diagnostics()
    local keys={
        "version","bridgeMode","discovery","discoveryComplete","discoveryScore","activeRouteScore",
        "candidatesFound","connectionsFound","connectionFunctions","controllerFunctions",
        "metatableFunctions","moduleFunctions","nestedFunctions","functionsExamined",
        "upvaluesExamined","constantsExamined","connectionGraphFunctions",
        "evidenceLines","evidenceDropped","hierarchyScanStatus","hierarchyStageFound",
        "hierarchyStageOrigin","hierarchyStageScore","hierarchyStageActivationKind",
        "hierarchyBestCandidateOrigin","hierarchyBestCandidateScore","hierarchyBestCandidateKind",
        "hierarchyLevelsVisited","hierarchyTablesDeduped",
        "hierarchyMaxDepth","hierarchyFunctionsEnumerated","hierarchyRelevantFunctions",
        "hierarchyInputObjectLikely","hierarchyInputChangedConnRefs","hierarchyCrossLinks",
        "connectObserverInstalled","connectObserverMode","connectObserverStatus",
        "futureConnectsSeen","futureCallbacksCaptured","futureCameraCallbacksProven",
        "lastFutureCallbackOrigin","lastFutureCallbackStatus",
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
        "usesVirtualMouseInjection","triggersCameraReconnect",
    }
    local lines={"=== PC MOVEMENT V602 REPORT ==="}
    for _,key in ipairs(keys) do
        lines[#lines+1]=key.." = "..tostring(diagnostics[key])
    end
    local summary=table.concat(lines,"\n")
    warn(summary)
    local details=""
    if includeEvidence~=false then details=getgenv().PCV602Evidence() end
    return details~="" and summary.."\n\n"..details or summary
end

getgenv().__PCMobileAimCleanup=function()
    pcall(function() RunService:UnbindFromRenderStep(WATCH_BIND) end)
    restoreActiveRoute(false)
    restoreConnectObserver(false)

    getgenv().PCV602Diagnostics=nil
    getgenv().PCV602Evidence=nil
    getgenv().PCV602Report=nil
    getgenv().PCV602DiscoveryScore=nil

    if baseCleanup then pcall(baseCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

warn(string.format(
    "[V602] inheritance probe ready | mode=%s | hierarchy=%s/%s | observer=%s | score=%s | candidates=%d | gains unchanged=(%.3f, %.3f)",
    tostring(getgenv().PCInputBridgeMode),
    tostring(hierarchyScanStatus),
    tostring(hierarchyStageFound),
    tostring(connectObserverStatus),
    tostring(discoveryScore),
    discoveryStats.candidatesFound,
    tonumber(getgenv().PCV602MouseGainX) or DEFAULT_GAIN_X,
    tonumber(getgenv().PCV602MouseGainY) or DEFAULT_GAIN_Y
))
