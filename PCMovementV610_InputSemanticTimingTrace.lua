local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")

local player=Players.LocalPlayer
local UI_NAME="PCMovementV610Panel"
local userGameSettings=nil
pcall(function() userGameSettings=UserSettings():GetService("UserGameSettings") end)

--[[
    V610 / INPUT SEMANTIC + TIMING TRACE

    Closed and not re-scanned: V604 ownership, V605 root yaw, V606 downstream
    composition, V607 MouseLockController, V608 lock writers and the V609 custom
    Evade block. The only target here is the pipeline that writes, consumes and
    clears activeCameraController.rotateInput.

    V610 is observational. It never creates input, changes gain/sensitivity,
    writes a CFrame, or forces an input/camera/character state.
]]

local v604Source=game:HttpGet(
    "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV604_MultitouchOwnershipProbe.lua?_cb="
    ..HttpService:GenerateGUID(false),true
)
local v604Chunk,v604Error=loadstring(v604Source)
if not v604Chunk then error(v604Error) end
v604Chunk()

local baseCleanup=getgenv().__PCMobileAimCleanup
local baseSetRelay=getgenv().PCV604SetRelayEnabled
local baseDiagnostics=getgenv().PCV604Diagnostics
local baseReport=getgenv().PCV604Report

getgenv().PCMovementVersion="V610-InputSemanticTimingTrace"
getgenv().PCInputBridgeMode="v610-observational-input-pipeline-over-v604"

local cameras=nil
local activeController=nil
local cameraModuleScript=nil
local baseCameraScript=nil
local controllerScript=nil
local targets={}
local targetEvidence={}
local installedHooks={}
local hooksInstalledTotal=0
local hookInstallFailures=0
local hookRestoreOk=nil
local hookRestoreDetail="not-stopped"
local discoveryStatus="not-started"
local discoveryErrors={}
local decompileStatus="not-attempted"
local baseCameraSnippet=""
local controllerUpdateSnippet=""
local staticTouchTranslationFound=false
local staticMouseDeltaFound=false
local staticMouseSensitivityFound=false
local staticRotateResetFound=false

local probeRunning=false
local suppressTrace=false
local probeStartedAt=0
local probeDuration=0
local probeFrames=0
local callbackErrors=0
local traceLines={}
local traceDropped=0
local evidence={}
local evidenceDropped=0

local inputStack={}
local routeStack={}
local currentUpdate=nil
local updateSerial=0
local lastUpdateAt=nil
local lastHandlerAt={}
local pending=nil
local stateAtStart=nil
local stateAtStop=nil

local onInputChangedCalls=0
local touchInputEvents=0
local mouseMovementInputEvents=0
local otherInputEvents=0
local onTouchChangedCalls=0
local onMouseMovedCalls=0
local touchHandlerExtraArgCalls=0
local mouseHandlerExtraArgCalls=0
local handlerNumericDtLikeArgs=0
local relayMouseCallsNestedInTouchInput=0
local nativeMouseCallsNestedInMouseInput=0
local sameTouchObjectRelayCalls=0
local mouseCallsWithoutMatchingInputEvent=0
local inputTranslationCalls=0
local inputTranslationTouchCalls=0
local inputTranslationMouseCalls=0
local inputTranslationExtraArgCalls=0
local inputTranslationNumericDtLikeArgs=0
local calculateLookCalls=0
local cameraModuleUpdates=0
local controllerUpdates=0
local controllerUpdateErrors=0
local rotateNonzeroAtCameraUpdateEntry=0
local rotateNonzeroAtControllerEntry=0
local rotateZeroAtControllerExit=0
local rotateConsumedOrClearedInController=0
local rotateClearedInsideCalculateLook=0
local rotateClearedAfterCalculateLook=0
local updatesWithTouchNativeWrites=0
local updatesWithRelayMouseWrites=0
local updatesWithNativeMouseWrites=0
local updatesWithMultipleInputWrites=0
local maxWritesBeforeOneUpdate=0
local updateDtCount=0
local updateDtSum=0
local updateDtMin=math.huge
local updateDtMax=0
local inputTranslationXCount=0
local inputTranslationXCoeffSum=0
local inputTranslationXCoeffMin=math.huge
local inputTranslationXCoeffMax=-math.huge
local inputTranslationYCount=0
local inputTranslationYCoeffSum=0
local inputTranslationYCoeffMin=math.huge
local inputTranslationYCoeffMax=-math.huge
local lastUpdateSequence=""
local updateSequenceCounts={}
local lastInputSequence=""
local lastTimingSnapshot=""
local lastControllerStateChange=""
local stateChangeCounts={}

local screenGui=nil
local statusLabel=nil
local relayButton=nil
local experimentButton=nil
local uiConnections={}

local function newPending()
    return {
        writes=0,
        touchNativeWrites=0,
        touchBookkeepingWrites=0,
        relayMouseWrites=0,
        nativeMouseWrites=0,
        otherWrites=0,
        rotateContribution=Vector2.new(),
        lastWriteAt=nil,
    }
end
pending=newPending()

local function newRouteStats()
    return {
        calls=0,errors=0,nonzero=0,zero=0,
        deltaXAbs=0,deltaYAbs=0,rotateXAbs=0,rotateYAbs=0,
        xCoeffCount=0,xCoeffSum=0,xCoeffMin=math.huge,xCoeffMax=-math.huge,
        yCoeffCount=0,yCoeffSum=0,yCoeffMin=math.huge,yCoeffMax=-math.huge,
        intervalCount=0,intervalSum=0,intervalMin=math.huge,intervalMax=0,
        updateLagCount=0,updateLagSum=0,updateLagMin=math.huge,updateLagMax=0,
        helperCalls=0,
        mouseSensitivityCount=0,mouseSensitivitySum=0,mouseSensitivityMin=math.huge,mouseSensitivityMax=-math.huge,
        viewportSamples=0,viewportXMin=math.huge,viewportXMax=0,viewportYMin=math.huge,viewportYMax=0,
    }
end

local routeStats={
    touchNativeRelayOff=newRouteStats(),
    touchBookkeepingRelayOn=newRouteStats(),
    mouseTouchRelay=newRouteStats(),
    mouseNative=newRouteStats(),
    mouseOther=newRouteStats(),
}

local function cleanText(value,limit)
    local output
    local ok=pcall(function() output=tostring(value) end)
    if not ok then output="<tostring-error>" end
    output=string.gsub(output or "nil","[\r\n\t]"," ")
    limit=limit or 180
    if #output>limit then output=string.sub(output,1,limit).."..." end
    return output
end

local function round(value,digits)
    if type(value)~="number" then return value end
    local scale=10^(digits or 6)
    if value>=0 then return math.floor(value*scale+0.5)/scale end
    return math.ceil(value*scale-0.5)/scale
end

local function addEvidence(section,message)
    if #evidence>=180 then evidenceDropped+=1; return end
    evidence[#evidence+1]=string.format("[%03d][%s] %s",#evidence+1,section,cleanText(message,1800))
end

local function addTrace(message)
    if #traceLines>=220 then traceDropped+=1; return end
    traceLines[#traceLines+1]=cleanText(message,1700)
end

local function packCall(original,...)
    return table.pack(pcall(original,...))
end

local function returnPacked(results)
    if not results[1] then error(results[2],0) end
    return table.unpack(results,2,results.n)
end

local function relayEnabled()
    return getgenv().PCV604RelayEnabled==true
end

local function getPlayerModule()
    local scripts=player:FindFirstChild("PlayerScripts")
    local module=scripts and scripts:FindFirstChild("PlayerModule")
    if not module then return nil end
    local result
    pcall(function() result=require(module) end)
    return type(result)=="table" and result or nil
end

local function locateObjects()
    local scripts=player:FindFirstChild("PlayerScripts")
    local playerModuleScript=scripts and scripts:FindFirstChild("PlayerModule")
    cameraModuleScript=playerModuleScript and playerModuleScript:FindFirstChild("CameraModule")
    baseCameraScript=cameraModuleScript and cameraModuleScript:FindFirstChild("BaseCamera")
    controllerScript=cameraModuleScript and (cameraModuleScript:FindFirstChild("ClassicCamera")
        or cameraModuleScript:FindFirstChild("OrbitalCamera"))
    local playerModule=getPlayerModule()
    if type(playerModule)=="table" then
        pcall(function()
            if type(playerModule.GetCameras)=="function" then cameras=playerModule:GetCameras() end
            if type(cameras)~="table" then cameras=rawget(playerModule,"cameras") end
        end)
    end
    if type(cameras)=="table" then activeController=rawget(cameras,"activeCameraController") end
end

local function getActiveController()
    if type(cameras)~="table" then locateObjects() end
    local controller=type(cameras)=="table" and rawget(cameras,"activeCameraController") or nil
    return type(controller)=="table" and controller or nil
end

local function getMeta(tbl)
    local mt=nil
    if type(getrawmetatable)=="function" then pcall(function() mt=getrawmetatable(tbl) end) end
    if type(mt)~="table" then pcall(function() mt=getmetatable(tbl) end) end
    return type(mt)=="table" and mt or nil
end

local function findMethod(root,name)
    local seen={}
    local function visit(tbl,depth,origin)
        if type(tbl)~="table" or depth>12 or seen[tbl] then return nil end
        seen[tbl]=true
        local value=nil
        pcall(function() value=rawget(tbl,name) end)
        if type(value)=="function" then return {fn=value,owner=tbl,origin=origin.."."..name,depth=depth} end
        local mt=getMeta(tbl)
        local found=mt and visit(mt,depth+1,origin.." -> getmetatable") or nil
        if found then return found end
        local index=nil
        pcall(function() index=rawget(tbl,"__index") end)
        if type(index)=="table" then return visit(index,depth+1,origin.." -> __index") end
        return nil
    end
    return visit(root,0,"target")
end

local function constantsSummary(fn)
    local getter=(debug and debug.getconstants) or getconstants
    if type(getter)~="function" then return "unavailable" end
    local ok,values=pcall(getter,fn)
    if not ok or type(values)~="table" then return "error:"..cleanText(values,100) end
    local items={}
    for _,value in ipairs(values) do
        if #items>=100 then break end
        if type(value)=="string" or type(value)=="number" or type(value)=="boolean" then
            items[#items+1]=cleanText(value,90)
        end
    end
    return table.concat(items," | ")
end

local function upvaluesSummary(fn)
    local getter=(debug and debug.getupvalues) or getupvalues
    if type(getter)~="function" then return "unavailable" end
    local ok,values=pcall(getter,fn)
    if not ok or type(values)~="table" then return "error:"..cleanText(values,100) end
    local items={}
    for index,value in pairs(values) do
        if #items>=30 then break end
        local kind=typeof(value)
        local text=kind
        if kind=="number" or kind=="boolean" or kind=="Vector2" or kind=="Vector3" then text=text..":"..cleanText(value,90) end
        items[#items+1]=tostring(index).."="..text
    end
    table.sort(items)
    return table.concat(items," | ")
end

local function registerTarget(id,root,name)
    local target=type(root)=="table" and findMethod(root,name) or nil
    targets[id]=target
    if not target then
        discoveryErrors[#discoveryErrors+1]=id.." missing"
        addEvidence("TARGET",id.." missing")
        return
    end
    targetEvidence[id]={
        origin=target.origin,
        constants=constantsSummary(target.fn),
        upvalues=upvaluesSummary(target.fn),
    }
    addEvidence("TARGET",id.." origin="..target.origin.." constants={"..targetEvidence[id].constants
        .."} upvalues={"..targetEvidence[id].upvalues.."}")
end

local function focusedWindows(source,markers)
    if type(source)~="string" then return "" end
    local lower=string.lower(source)
    local chunks={}
    local used={}
    for _,marker in ipairs(markers) do
        local found=string.find(lower,string.lower(marker),1,true)
        if found then
            local first=math.max(1,found-500)
            local last=math.min(#source,found+1700)
            local key=tostring(first)..":"..tostring(last)
            if not used[key] then
                used[key]=true
                chunks[#chunks+1]="--- marker "..marker.." ---\n"..string.sub(source,first,last)
            end
        end
    end
    return table.concat(chunks,"\n\n")
end

local function extractFocusedStatic()
    local env=getgenv()
    local decompiler=env.decompile or decompile
    if type(decompiler)~="function" then decompileStatus="decompile-unavailable"; return end
    local statuses={}
    if baseCameraScript then
        local ok,source=pcall(decompiler,baseCameraScript)
        if ok and type(source)=="string" then
            baseCameraSnippet=focusedWindows(source,{
                "OnInputChanged","OnTouchChanged","OnMouseMoved","InputTranslationToCameraAngleChange",
                "CalculateNewLookCFrame","rotateInput",
            })
            local lower=string.lower(baseCameraSnippet)
            staticTouchTranslationFound=string.find(lower,"ontouchchanged",1,true)~=nil
                or string.find(lower,"inputtranslationtocameraanglechange",1,true)~=nil
            staticMouseDeltaFound=string.find(lower,"onmousemoved",1,true)~=nil
                and string.find(lower,"delta",1,true)~=nil
            staticMouseSensitivityFound=string.find(lower,"mousesensitivity",1,true)~=nil
            statuses[#statuses+1]="BaseCamera-focused"
        else statuses[#statuses+1]="BaseCamera-error:"..cleanText(source,90) end
    else statuses[#statuses+1]="BaseCamera-missing" end
    if controllerScript then
        local ok,source=pcall(decompiler,controllerScript)
        if ok and type(source)=="string" then
            controllerUpdateSnippet=focusedWindows(source,{"function","Update","rotateInput","CalculateNewLookCFrame"})
            local lower=string.lower(controllerUpdateSnippet)
            staticRotateResetFound=string.find(lower,"rotateinput%s*=%s*vector2%.new")~=nil
                or string.find(lower,"rotateinput%s*=%s*vector2%.zero")~=nil
            statuses[#statuses+1]="ControllerUpdate-focused"
        else statuses[#statuses+1]="Controller-error:"..cleanText(source,90) end
    else statuses[#statuses+1]="Controller-script-missing" end
    decompileStatus=table.concat(statuses," | ")
    addEvidence("STATIC",string.format("status=%s touchTranslation=%s mouseDelta=%s mouseSensitivity=%s rotateReset=%s",
        decompileStatus,tostring(staticTouchTranslationFound),tostring(staticMouseDeltaFound),
        tostring(staticMouseSensitivityFound),tostring(staticRotateResetFound)))
end

local function discoverFocusedPipeline()
    discoveryStatus="running"
    locateObjects()
    registerTarget("CameraModule.Update",cameras,"Update")
    registerTarget("Controller.Update",activeController,"Update")
    registerTarget("OnInputChanged",activeController,"OnInputChanged")
    registerTarget("OnTouchChanged",activeController,"OnTouchChanged")
    registerTarget("OnMouseMoved",activeController,"OnMouseMoved")
    registerTarget("InputTranslationToCameraAngleChange",activeController,"InputTranslationToCameraAngleChange")
    registerTarget("CalculateNewLookCFrame",activeController,"CalculateNewLookCFrame")
    extractFocusedStatic()
    discoveryStatus=#discoveryErrors==0 and "complete" or "partial"
end

local function readRotate(controller)
    local value=nil
    if type(controller)=="table" then pcall(function() value=rawget(controller,"rotateInput") end) end
    return typeof(value)=="Vector2" and value or nil
end

local function inputType(input)
    local value=nil
    pcall(function() value=input.UserInputType end)
    return value
end

local function inputDelta(input)
    local value=nil
    pcall(function() value=input.Delta end)
    return value
end

local function vector2Delta(after,before)
    if typeof(after)~="Vector2" or typeof(before)~="Vector2" then return nil end
    return after-before
end

local function nonzero(value)
    return typeof(value)=="Vector2" and value.Magnitude>1e-8
end

local function controllerState(controller)
    if type(controller)~="table" then return {} end
    local result={}
    for _,name in ipairs({
        "rotateInput","lastPos","startPos","panBeginLook","userPanningTheCamera","panEnabled",
        "numUnsunkTouches","isDynamicThumbstickEnabled","inMouseLockedMode","mouseLockOffset","lastThumbstickPos",
    }) do
        pcall(function() result[name]=rawget(controller,name) end)
    end
    return result
end

local function valueChanged(a,b)
    if typeof(a)~=typeof(b) then return true end
    if typeof(a)=="Vector2" or typeof(a)=="Vector3" then return (a-b).Magnitude>1e-7 end
    if typeof(a)=="CFrame" then return a~=b end
    return a~=b
end

local function recordStateChanges(route,before,after)
    local changed={}
    for name,beforeValue in pairs(before) do
        local afterValue=after[name]
        if valueChanged(beforeValue,afterValue) then
            local key=route.."."..name
            stateChangeCounts[key]=(stateChangeCounts[key] or 0)+1
            changed[#changed+1]=name..":"..cleanText(beforeValue,70).."->"..cleanText(afterValue,70)
        end
    end
    for name,afterValue in pairs(after) do
        if before[name]==nil then
            local key=route.."."..name
            stateChangeCounts[key]=(stateChangeCounts[key] or 0)+1
            changed[#changed+1]=name..":nil->"..cleanText(afterValue,70)
        end
    end
    if #changed>0 then lastControllerStateChange=route.."{"..table.concat(changed," | ").."}" end
end

local function addCoefficient(stats,axis,delta,rotation)
    if type(delta)~="number" or type(rotation)~="number" or math.abs(delta)<0.05 then return end
    local coefficient=math.abs(rotation/delta)
    if axis=="x" then
        stats.xCoeffCount+=1; stats.xCoeffSum+=coefficient
        stats.xCoeffMin=math.min(stats.xCoeffMin,coefficient); stats.xCoeffMax=math.max(stats.xCoeffMax,coefficient)
    else
        stats.yCoeffCount+=1; stats.yCoeffSum+=coefficient
        stats.yCoeffMin=math.min(stats.yCoeffMin,coefficient); stats.yCoeffMax=math.max(stats.yCoeffMax,coefficient)
    end
end

local function noteTiming(route,stats,now)
    local previous=lastHandlerAt[route]
    if previous then
        local interval=now-previous
        stats.intervalCount+=1; stats.intervalSum+=interval
        stats.intervalMin=math.min(stats.intervalMin,interval); stats.intervalMax=math.max(stats.intervalMax,interval)
    end
    lastHandlerAt[route]=now
end

local function recordRoute(route,input,beforeRotate,afterRotate,beforeState,afterState,ok)
    local stats=routeStats[route]
    if not stats then return end
    local now=os.clock()
    stats.calls+=1
    if not ok then stats.errors+=1 end
    noteTiming(route,stats,now)
    if userGameSettings then
        local sensitivity=nil
        pcall(function() sensitivity=userGameSettings.MouseSensitivity end)
        if type(sensitivity)=="number" then
            stats.mouseSensitivityCount+=1; stats.mouseSensitivitySum+=sensitivity
            stats.mouseSensitivityMin=math.min(stats.mouseSensitivityMin,sensitivity)
            stats.mouseSensitivityMax=math.max(stats.mouseSensitivityMax,sensitivity)
        end
    end
    local camera=workspace.CurrentCamera
    local viewport=camera and camera.ViewportSize or nil
    if typeof(viewport)=="Vector2" then
        stats.viewportSamples+=1
        stats.viewportXMin=math.min(stats.viewportXMin,viewport.X); stats.viewportXMax=math.max(stats.viewportXMax,viewport.X)
        stats.viewportYMin=math.min(stats.viewportYMin,viewport.Y); stats.viewportYMax=math.max(stats.viewportYMax,viewport.Y)
    end
    local delta=inputDelta(input)
    local change=vector2Delta(afterRotate,beforeRotate)
    if typeof(delta)=="Vector3" then
        stats.deltaXAbs+=math.abs(delta.X); stats.deltaYAbs+=math.abs(delta.Y)
    end
    if typeof(change)=="Vector2" then
        stats.rotateXAbs+=math.abs(change.X); stats.rotateYAbs+=math.abs(change.Y)
        if nonzero(change) then stats.nonzero+=1 else stats.zero+=1 end
        if typeof(delta)=="Vector3" then
            addCoefficient(stats,"x",delta.X,change.X)
            addCoefficient(stats,"y",delta.Y,change.Y)
        end
        pending.rotateContribution+=change
    else stats.zero+=1 end
    pending.writes+=1
    pending.lastWriteAt=now
    if route=="touchNativeRelayOff" then pending.touchNativeWrites+=1
    elseif route=="touchBookkeepingRelayOn" then pending.touchBookkeepingWrites+=1
    elseif route=="mouseTouchRelay" then pending.relayMouseWrites+=1
    elseif route=="mouseNative" then pending.nativeMouseWrites+=1
    else pending.otherWrites+=1 end
    recordStateChanges(route,beforeState,afterState)
end

local function installHook(id,factory)
    local target=targets[id]
    if not target then return false,"target-missing" end
    if type(hookfunction)~="function" then return false,"hookfunction-unavailable" end
    local original=nil
    local replacement=factory(function(...) return original(...) end)
    local ok,old=pcall(function() return hookfunction(target.fn,replacement) end)
    if not ok or type(old)~="function" then return false,cleanText(old,140) end
    original=old
    target.original=old
    installedHooks[#installedHooks+1]={id=id,target=target.fn,original=old}
    hooksInstalledTotal+=1
    addEvidence("HOOK",id.." installed")
    return true,"installed"
end

local function currentInputContext()
    return inputStack[#inputStack]
end

local function currentRoute()
    return routeStack[#routeStack]
end

local function onInputFactory(callOriginal)
    return function(self,input,processed,...)
        if not probeRunning or suppressTrace then return callOriginal(self,input,processed,...) end
        local active=getActiveController()
        if self~=active then return callOriginal(self,input,processed,...) end
        onInputChangedCalls+=1
        local kind=inputType(input)
        if kind==Enum.UserInputType.Touch then touchInputEvents+=1
        elseif kind==Enum.UserInputType.MouseMovement then mouseMovementInputEvents+=1
        else otherInputEvents+=1 end
        local ctx={
            id=onInputChangedCalls,input=input,inputType=kind,processed=processed,
            startedAt=os.clock(),updateSerial=updateSerial,relayAtEntry=relayEnabled(),
            rotateBefore=readRotate(self),sequence={"OnInputChanged("..tostring(kind).."):enter"},
        }
        inputStack[#inputStack+1]=ctx
        local results=packCall(callOriginal,self,input,processed,...)
        ctx.rotateAfter=readRotate(self)
        ctx.finishedAt=os.clock()
        ctx.sequence[#ctx.sequence+1]="OnInputChanged:exit"
        lastInputSequence=table.concat(ctx.sequence,">")
        inputStack[#inputStack]=nil
        if ctx.id<=18 or ctx.id%120==0 then
            addTrace(string.format("I%04d frame=%d type=%s relay=%s processed=%s delta=%s rotate=%s->%s sequence={%s} durationMs=%.4f",
                ctx.id,ctx.updateSerial,tostring(kind),tostring(ctx.relayAtEntry),tostring(processed),
                cleanText(inputDelta(input),80),cleanText(ctx.rotateBefore,80),cleanText(ctx.rotateAfter,80),
                lastInputSequence,(ctx.finishedAt-ctx.startedAt)*1000))
        end
        if not results[1] then callbackErrors+=1 end
        return returnPacked(results)
    end
end

local function handlerFactory(name)
    return function(callOriginal)
        return function(self,input,...)
            if not probeRunning or suppressTrace then return callOriginal(self,input,...) end
            local active=getActiveController()
            if self~=active then return callOriginal(self,input,...) end
            local kind=inputType(input)
            local extras=table.pack(...)
            if extras.n>0 then
                if name=="OnTouchChanged" then touchHandlerExtraArgCalls+=1 else mouseHandlerExtraArgCalls+=1 end
                for index=1,extras.n do
                    if type(extras[index])=="number" then handlerNumericDtLikeArgs+=1; break end
                end
            end
            local inputCtx=currentInputContext()
            local route
            if name=="OnTouchChanged" then
                onTouchChangedCalls+=1
                route=relayEnabled() and "touchBookkeepingRelayOn" or "touchNativeRelayOff"
            else
                onMouseMovedCalls+=1
                if kind==Enum.UserInputType.Touch then route="mouseTouchRelay"
                elseif kind==Enum.UserInputType.MouseMovement then route="mouseNative"
                else route="mouseOther" end
                if route=="mouseTouchRelay" and inputCtx and inputCtx.inputType==Enum.UserInputType.Touch then
                    relayMouseCallsNestedInTouchInput+=1
                    if inputCtx.input==input then sameTouchObjectRelayCalls+=1 end
                elseif route=="mouseNative" and inputCtx and inputCtx.inputType==Enum.UserInputType.MouseMovement then
                    nativeMouseCallsNestedInMouseInput+=1
                else mouseCallsWithoutMatchingInputEvent+=1 end
            end
            if inputCtx then inputCtx.sequence[#inputCtx.sequence+1]=name.."("..route.."):enter" end
            routeStack[#routeStack+1]=route
            local beforeRotate=readRotate(self)
            local beforeState=controllerState(self)
            local results=packCall(callOriginal,self,input,...)
            local afterState=controllerState(self)
            local afterRotate=readRotate(self)
            routeStack[#routeStack]=nil
            if inputCtx then inputCtx.sequence[#inputCtx.sequence+1]=name..":exit" end
            recordRoute(route,input,beforeRotate,afterRotate,beforeState,afterState,results[1])
            local stats=routeStats[route]
            if stats.calls<=14 or stats.calls%120==0 then
                addTrace(string.format("H %s call=%d frame=%d inputType=%s sameOuterInput=%s delta=%s rotate=%s->%s change=%s helperCalls=%d",
                    route,stats.calls,updateSerial,tostring(kind),tostring(inputCtx and inputCtx.input==input),
                    cleanText(inputDelta(input),80),cleanText(beforeRotate,80),cleanText(afterRotate,80),
                    cleanText(vector2Delta(afterRotate,beforeRotate),80),stats.helperCalls))
            end
            if not results[1] then callbackErrors+=1 end
            return returnPacked(results)
        end
    end
end

local function inputTranslationFactory(callOriginal)
    return function(self,translation,...)
        if not probeRunning or suppressTrace then return callOriginal(self,translation,...) end
        inputTranslationCalls+=1
        local extras=table.pack(...)
        if extras.n>0 then
            inputTranslationExtraArgCalls+=1
            for index=1,extras.n do
                if type(extras[index])=="number" then inputTranslationNumericDtLikeArgs+=1; break end
            end
        end
        local route=currentRoute() or "outside-handler"
        local results=packCall(callOriginal,self,translation,...)
        local output=results[2]
        local stats=routeStats[route]
        if stats then stats.helperCalls+=1 end
        if string.sub(route,1,5)=="touch" then inputTranslationTouchCalls+=1
        elseif string.sub(route,1,5)=="mouse" then inputTranslationMouseCalls+=1 end
        if typeof(translation)=="Vector2" and typeof(output)=="Vector2" then
            if math.abs(translation.X)>0.05 then
                local coefficient=math.abs(output.X/translation.X)
                inputTranslationXCount+=1; inputTranslationXCoeffSum+=coefficient
                inputTranslationXCoeffMin=math.min(inputTranslationXCoeffMin,coefficient)
                inputTranslationXCoeffMax=math.max(inputTranslationXCoeffMax,coefficient)
            end
            if math.abs(translation.Y)>0.05 then
                local coefficient=math.abs(output.Y/translation.Y)
                inputTranslationYCount+=1; inputTranslationYCoeffSum+=coefficient
                inputTranslationYCoeffMin=math.min(inputTranslationYCoeffMin,coefficient)
                inputTranslationYCoeffMax=math.max(inputTranslationYCoeffMax,coefficient)
            end
        end
        if inputTranslationCalls<=18 or inputTranslationCalls%120==0 then
            addTrace(string.format("T helper call=%d route=%s frame=%d translation=%s output=%s",
                inputTranslationCalls,route,updateSerial,cleanText(translation,100),cleanText(output,100)))
        end
        if not results[1] then callbackErrors+=1 end
        return returnPacked(results)
    end
end

local function calculateLookFactory(callOriginal)
    return function(self,...)
        if not probeRunning or suppressTrace then return callOriginal(self,...) end
        calculateLookCalls+=1
        local before=readRotate(self)
        if currentUpdate then currentUpdate.sequence[#currentUpdate.sequence+1]="CalculateNewLookCFrame:enter" end
        local results=packCall(callOriginal,self,...)
        local after=readRotate(self)
        if currentUpdate then
            currentUpdate.sequence[#currentUpdate.sequence+1]="CalculateNewLookCFrame:exit"
            currentUpdate.calculateBefore=before
            currentUpdate.calculateAfter=after
        end
        if nonzero(before) and not nonzero(after) then rotateClearedInsideCalculateLook+=1 end
        if not results[1] then callbackErrors+=1 end
        return returnPacked(results)
    end
end

local function controllerUpdateFactory(callOriginal)
    return function(self,dt,...)
        if not probeRunning or suppressTrace then return callOriginal(self,dt,...) end
        local active=getActiveController()
        if self~=active then return callOriginal(self,dt,...) end
        controllerUpdates+=1
        local before=readRotate(self)
        if nonzero(before) then rotateNonzeroAtControllerEntry+=1 end
        if currentUpdate then
            currentUpdate.sequence[#currentUpdate.sequence+1]="Controller.Update:enter"
            currentUpdate.controllerBefore=before
            currentUpdate.dt=dt
        end
        local results=packCall(callOriginal,self,dt,...)
        local after=readRotate(self)
        if currentUpdate then
            currentUpdate.sequence[#currentUpdate.sequence+1]="Controller.Update:exit"
            currentUpdate.controllerAfter=after
        end
        if not nonzero(after) then rotateZeroAtControllerExit+=1 end
        if nonzero(before) and (not nonzero(after) or (after-before).Magnitude>1e-8) then
            rotateConsumedOrClearedInController+=1
            if currentUpdate and nonzero(currentUpdate.calculateAfter) then rotateClearedAfterCalculateLook+=1 end
        end
        if not results[1] then controllerUpdateErrors+=1; callbackErrors+=1 end
        return returnPacked(results)
    end
end

local function cameraUpdateFactory(callOriginal)
    return function(self,dt,...)
        if not probeRunning or suppressTrace then return callOriginal(self,dt,...) end
        cameraModuleUpdates+=1
        probeFrames+=1
        updateSerial+=1
        local now=os.clock()
        if type(dt)=="number" then
            updateDtCount+=1; updateDtSum+=dt
            updateDtMin=math.min(updateDtMin,dt); updateDtMax=math.max(updateDtMax,dt)
        end
        local controller=getActiveController()
        local before=readRotate(controller)
        local interval=lastUpdateAt and now-lastUpdateAt or nil
        lastUpdateAt=now
        local captured=pending
        pending=newPending()
        if nonzero(before) then rotateNonzeroAtCameraUpdateEntry+=1 end
        if captured.touchNativeWrites>0 then updatesWithTouchNativeWrites+=1 end
        if captured.relayMouseWrites>0 then updatesWithRelayMouseWrites+=1 end
        if captured.nativeMouseWrites>0 then updatesWithNativeMouseWrites+=1 end
        if captured.writes>1 then updatesWithMultipleInputWrites+=1 end
        maxWritesBeforeOneUpdate=math.max(maxWritesBeforeOneUpdate,captured.writes)
        if captured.lastWriteAt then
            local lag=now-captured.lastWriteAt
            local key=captured.relayMouseWrites>0 and "mouseTouchRelay"
                or (captured.nativeMouseWrites>0 and "mouseNative")
                or (captured.touchNativeWrites>0 and "touchNativeRelayOff")
                or (captured.touchBookkeepingWrites>0 and "touchBookkeepingRelayOn") or nil
            local stats=key and routeStats[key] or nil
            if stats then
                stats.updateLagCount+=1; stats.updateLagSum+=lag
                stats.updateLagMin=math.min(stats.updateLagMin,lag); stats.updateLagMax=math.max(stats.updateLagMax,lag)
            end
        end
        local ctx={
            id=updateSerial,startedAt=now,dt=dt,interval=interval,before=before,pending=captured,
            sequence={"CameraModule.Update:enter"},
        }
        currentUpdate=ctx
        local results=packCall(callOriginal,self,dt,...)
        ctx.after=readRotate(getActiveController())
        ctx.sequence[#ctx.sequence+1]="CameraModule.Update:exit"
        lastUpdateSequence=table.concat(ctx.sequence,">")
        updateSequenceCounts[lastUpdateSequence]=(updateSequenceCounts[lastUpdateSequence] or 0)+1
        lastTimingSnapshot=string.format("frame=%d dt=%s interval=%s writes=%d touch=%d bookkeeping=%d relayMouse=%d nativeMouse=%d contribution=%s rotateEntry=%s calc=%s->%s controller=%s->%s rotateExit=%s",
            ctx.id,cleanText(dt,30),cleanText(interval,30),captured.writes,captured.touchNativeWrites,
            captured.touchBookkeepingWrites,captured.relayMouseWrites,captured.nativeMouseWrites,
            cleanText(captured.rotateContribution,80),cleanText(before,80),cleanText(ctx.calculateBefore,80),
            cleanText(ctx.calculateAfter,80),cleanText(ctx.controllerBefore,80),cleanText(ctx.controllerAfter,80),
            cleanText(ctx.after,80))
        if ctx.id<=16 or ctx.id%120==0 or captured.writes>1 then addTrace("U "..lastTimingSnapshot.." sequence={"..lastUpdateSequence.."}") end
        currentUpdate=nil
        if not results[1] then callbackErrors+=1 end
        return returnPacked(results)
    end
end

local function installFocusedHooks()
    local specs={
        {"OnInputChanged",onInputFactory},
        {"OnTouchChanged",handlerFactory("OnTouchChanged")},
        {"OnMouseMoved",handlerFactory("OnMouseMoved")},
        {"InputTranslationToCameraAngleChange",inputTranslationFactory},
        {"CalculateNewLookCFrame",calculateLookFactory},
        {"Controller.Update",controllerUpdateFactory},
        {"CameraModule.Update",cameraUpdateFactory},
    }
    for _,spec in ipairs(specs) do
        local ok,detail=installHook(spec[1],spec[2])
        if not ok then hookInstallFailures+=1; addEvidence("HOOK",spec[1].." rejected="..detail) end
    end
end

local function restoreHooks()
    local okAll=true
    local details={}
    for index=#installedHooks,1,-1 do
        local hook=installedHooks[index]
        local ok,err=pcall(function() hookfunction(hook.target,hook.original) end)
        okAll=okAll and ok
        details[#details+1]=hook.id.."="..tostring(ok)..(ok and "" or ":"..cleanText(err,100))
    end
    installedHooks={}
    hookRestoreOk=okAll
    hookRestoreDetail=#details>0 and table.concat(details,"; ") or "not-needed"
    return okAll
end

local function resetCounters()
    probeFrames=0; callbackErrors=0; traceLines={}; traceDropped=0
    inputStack={}; routeStack={}; currentUpdate=nil; updateSerial=0; lastUpdateAt=nil; lastHandlerAt={}; pending=newPending()
    onInputChangedCalls=0; touchInputEvents=0; mouseMovementInputEvents=0; otherInputEvents=0
    onTouchChangedCalls=0; onMouseMovedCalls=0; relayMouseCallsNestedInTouchInput=0
    touchHandlerExtraArgCalls=0; mouseHandlerExtraArgCalls=0; handlerNumericDtLikeArgs=0
    nativeMouseCallsNestedInMouseInput=0; sameTouchObjectRelayCalls=0; mouseCallsWithoutMatchingInputEvent=0
    inputTranslationCalls=0; inputTranslationTouchCalls=0; inputTranslationMouseCalls=0; calculateLookCalls=0
    inputTranslationExtraArgCalls=0; inputTranslationNumericDtLikeArgs=0
    cameraModuleUpdates=0; controllerUpdates=0; controllerUpdateErrors=0
    rotateNonzeroAtCameraUpdateEntry=0; rotateNonzeroAtControllerEntry=0; rotateZeroAtControllerExit=0
    rotateConsumedOrClearedInController=0; rotateClearedInsideCalculateLook=0; rotateClearedAfterCalculateLook=0
    updatesWithTouchNativeWrites=0; updatesWithRelayMouseWrites=0; updatesWithNativeMouseWrites=0
    updatesWithMultipleInputWrites=0; maxWritesBeforeOneUpdate=0
    updateDtCount=0; updateDtSum=0; updateDtMin=math.huge; updateDtMax=0
    inputTranslationXCount=0; inputTranslationXCoeffSum=0
    inputTranslationXCoeffMin=math.huge; inputTranslationXCoeffMax=-math.huge
    inputTranslationYCount=0; inputTranslationYCoeffSum=0
    inputTranslationYCoeffMin=math.huge; inputTranslationYCoeffMax=-math.huge
    lastUpdateSequence=""; updateSequenceCounts={}; lastInputSequence=""; lastTimingSnapshot=""
    lastControllerStateChange=""; stateChangeCounts={}
    hookRestoreOk=nil; hookRestoreDetail="running"
    routeStats={
        touchNativeRelayOff=newRouteStats(),touchBookkeepingRelayOn=newRouteStats(),
        mouseTouchRelay=newRouteStats(),mouseNative=newRouteStats(),mouseOther=newRouteStats(),
    }
end

local function startProbe()
    if probeRunning then return false,"already-running" end
    if #installedHooks==0 then
        local ok,err=pcall(installFocusedHooks)
        if not ok or #installedHooks==0 then
            addEvidence("HOOK","restart-error="..cleanText(err,160))
            return false,"hook-install-failed"
        end
    end
    resetCounters()
    stateAtStart={rotateInput=readRotate(getActiveController()),relayEnabled=relayEnabled(),preferredInput=UserInputService.PreferredInput}
    stateAtStop=nil
    probeStartedAt=os.clock(); probeDuration=0; probeRunning=true
    addEvidence("PROBE","V610 input semantic/timing trace started")
    return true,"started"
end

local function stopProbe()
    if not probeRunning then
        if #installedHooks>0 then
            stateAtStop={rotateInput=readRotate(getActiveController()),relayEnabled=relayEnabled(),preferredInput=UserInputService.PreferredInput}
            restoreHooks()
            addEvidence("PROBE","idle hooks restored")
            return true,"idle-hooks-restored"
        end
        return true,"already-stopped"
    end
    probeDuration=os.clock()-probeStartedAt
    probeRunning=false
    inputStack={}; routeStack={}; currentUpdate=nil
    stateAtStop={rotateInput=readRotate(getActiveController()),relayEnabled=relayEnabled(),preferredInput=UserInputService.PreferredInput}
    restoreHooks()
    addEvidence("PROBE","stopped duration="..tostring(round(probeDuration,3)))
    return true,"stopped"
end

local function baseSafe()
    if type(baseDiagnostics)~="function" then return {} end
    suppressTrace=true
    local ok,value=pcall(baseDiagnostics)
    suppressTrace=false
    return ok and type(value)=="table" and value or {}
end

local function countSummary(counts,limit)
    local rows={}
    for key,count in pairs(counts) do rows[#rows+1]={key=tostring(key),count=count} end
    table.sort(rows,function(a,b) return a.count>b.count end)
    local result={}
    for index=1,math.min(#rows,limit or 12) do result[#result+1]=rows[index].key..":"..rows[index].count end
    return #result>0 and table.concat(result," | ") or "none"
end

local function statValue(stats,name)
    if name=="xCoeffMean" then return stats.xCoeffCount>0 and stats.xCoeffSum/stats.xCoeffCount or nil end
    if name=="yCoeffMean" then return stats.yCoeffCount>0 and stats.yCoeffSum/stats.yCoeffCount or nil end
    if name=="xCoeffMin" then return stats.xCoeffCount>0 and stats.xCoeffMin or nil end
    if name=="xCoeffMax" then return stats.xCoeffCount>0 and stats.xCoeffMax or nil end
    if name=="yCoeffMin" then return stats.yCoeffCount>0 and stats.yCoeffMin or nil end
    if name=="yCoeffMax" then return stats.yCoeffCount>0 and stats.yCoeffMax or nil end
    if name=="intervalMeanMs" then return stats.intervalCount>0 and stats.intervalSum/stats.intervalCount*1000 or nil end
    if name=="intervalMinMs" then return stats.intervalCount>0 and stats.intervalMin*1000 or nil end
    if name=="intervalMaxMs" then return stats.intervalCount>0 and stats.intervalMax*1000 or nil end
    if name=="updateLagMeanMs" then return stats.updateLagCount>0 and stats.updateLagSum/stats.updateLagCount*1000 or nil end
    if name=="updateLagMinMs" then return stats.updateLagCount>0 and stats.updateLagMin*1000 or nil end
    if name=="updateLagMaxMs" then return stats.updateLagCount>0 and stats.updateLagMax*1000 or nil end
    if name=="mouseSensitivityMean" then return stats.mouseSensitivityCount>0 and stats.mouseSensitivitySum/stats.mouseSensitivityCount or nil end
    if name=="mouseSensitivityMin" then return stats.mouseSensitivityCount>0 and stats.mouseSensitivityMin or nil end
    if name=="mouseSensitivityMax" then return stats.mouseSensitivityCount>0 and stats.mouseSensitivityMax or nil end
    if name=="viewportXMin" then return stats.viewportSamples>0 and stats.viewportXMin or nil end
    if name=="viewportXMax" then return stats.viewportSamples>0 and stats.viewportXMax or nil end
    if name=="viewportYMin" then return stats.viewportSamples>0 and stats.viewportYMin or nil end
    if name=="viewportYMax" then return stats.viewportSamples>0 and stats.viewportYMax or nil end
    return stats[name]
end

local function classification()
    local nestedRelay=relayMouseCallsNestedInTouchInput>0
        and sameTouchObjectRelayCalls==relayMouseCallsNestedInTouchInput
    local nativeDispatch=nativeMouseCallsNestedInMouseInput>0
    local touchStats=routeStats.touchNativeRelayOff
    local relayStats=routeStats.mouseTouchRelay
    local gainOrigin=touchStats.xCoeffCount>0 and relayStats.xCoeffCount>0
        and inputTranslationTouchCalls>0
    local timingDivergence=nestedRelay
    local touchPipeline=string.format(
        "real Touch -> OnInputChanged(Touch) -> OnTouchChanged -> InputTranslationToCameraAngleChange -> rotateInput; calls=%d helper=%d nonzero=%d xCoeff=%s yCoeff=%s",
        touchStats.calls,inputTranslationTouchCalls,touchStats.nonzero,
        tostring(round(statValue(touchStats,"xCoeffMean"),9)),tostring(round(statValue(touchStats,"yCoeffMean"),9)))
    local mousePipeline
    if nativeDispatch then
        mousePipeline=string.format("MouseMovement InputChanged -> OnInputChanged(MouseMovement) -> OnMouseMoved -> rotateInput; nativeCalls=%d xCoeff=%s yCoeff=%s",
            routeStats.mouseNative.calls,tostring(round(statValue(routeStats.mouseNative,"xCoeffMean"),9)),
            tostring(round(statValue(routeStats.mouseNative,"yCoeffMean"),9)))
    else
        mousePipeline=string.format("V604 relay: inside OnInputChanged(Touch), bookkeeping OnTouchChanged then synchronous OnMouseMoved(same Touch); relayedCalls=%d sameObject=%d xCoeff=%s yCoeff=%s; native MouseMovement runtime not observed",
            relayStats.calls,sameTouchObjectRelayCalls,tostring(round(statValue(relayStats,"xCoeffMean"),9)),
            tostring(round(statValue(relayStats,"yCoeffMean"),9)))
    end
    local divergence
    if timingDivergence then
        divergence="same OnMouseMoved Lua function is reused, but V604 executes it synchronously inside a Touch InputChanged callback; no distinct MouseMovement InputChanged/cadence is reproduced"
    elseif gainOrigin then
        divergence="different Touch translation and Mouse delta transforms proved; event-source timing still unproved"
    else divergence="insufficient runtime samples to prove the first Touch-vs-Mouse semantic divergence" end
    local anchor
    if timingDivergence or gainOrigin then
        anchor="input semantic divergence is concrete and can change rotation magnitude/cadence before Controller.Update; causal link to PC screen-space stability remains unproved"
    else anchor="not established" end
    return {
        touchInputPipeline=touchPipeline,
        mouseInputPipeline=mousePipeline,
        firstInputSemanticDivergence=divergence,
        timingDivergenceFound=timingDivergence,
        gainOriginFound=gainOrigin,
        pcSemanticsReproducible=false,
        anchorRelevance=anchor,
        experimentEligible=false,
        experimentReason=(timingDivergence or gainOrigin)
            and "blocked: divergence measured, but no safe native MouseMovement scheduling stage is available on Touch"
            or "blocked: divergence not yet proved",
    }
end

getgenv().PCV610Diagnostics=function()
    local base=baseSafe()
    local decision=classification()
    local frozen=(not probeRunning and stateAtStop) or {
        rotateInput=readRotate(getActiveController()),relayEnabled=relayEnabled(),preferredInput=UserInputService.PreferredInput,
    }
    local result={
        version="V610-InputSemanticTimingTrace",
        bridgeMode=getgenv().PCInputBridgeMode,
        probePurpose="compare-Touch-vs-MouseMovement-rotateInput-semantics-and-timing",
        probeRunning=probeRunning,
        probeFrames=probeFrames,
        probeDuration=round(probeRunning and (os.clock()-probeStartedAt) or probeDuration,3),
        discoveryStatus=discoveryStatus,
        discoveryErrors=table.concat(discoveryErrors," | "),
        decompileStatus=decompileStatus,
        staticTouchTranslationFound=staticTouchTranslationFound,
        staticMouseDeltaFound=staticMouseDeltaFound,
        staticMouseSensitivityFound=staticMouseSensitivityFound,
        staticRotateResetFound=staticRotateResetFound,
        hooksCurrentlyInstalled=#installedHooks,
        hooksInstalledTotal=hooksInstalledTotal,
        hookInstallFailures=hookInstallFailures,
        hookRestoreOk=hookRestoreOk,
        hookRestoreDetail=hookRestoreDetail,
        callbackErrors=callbackErrors,
        traceDropped=traceDropped,
        evidenceDropped=evidenceDropped,
        onInputChangedCalls=onInputChangedCalls,
        touchInputEvents=touchInputEvents,
        mouseMovementInputEvents=mouseMovementInputEvents,
        otherInputEvents=otherInputEvents,
        onTouchChangedCalls=onTouchChangedCalls,
        onMouseMovedCalls=onMouseMovedCalls,
        touchHandlerExtraArgCalls=touchHandlerExtraArgCalls,
        mouseHandlerExtraArgCalls=mouseHandlerExtraArgCalls,
        handlerNumericDtLikeArgs=handlerNumericDtLikeArgs,
        relayMouseCallsNestedInTouchInput=relayMouseCallsNestedInTouchInput,
        nativeMouseCallsNestedInMouseInput=nativeMouseCallsNestedInMouseInput,
        sameTouchObjectRelayCalls=sameTouchObjectRelayCalls,
        mouseCallsWithoutMatchingInputEvent=mouseCallsWithoutMatchingInputEvent,
        inputTranslationCalls=inputTranslationCalls,
        inputTranslationTouchCalls=inputTranslationTouchCalls,
        inputTranslationMouseCalls=inputTranslationMouseCalls,
        inputTranslationExtraArgCalls=inputTranslationExtraArgCalls,
        inputTranslationNumericDtLikeArgs=inputTranslationNumericDtLikeArgs,
        handlerDtDependencyObserved=handlerNumericDtLikeArgs>0,
        inputTranslationDtDependencyObserved=inputTranslationNumericDtLikeArgs>0,
        calculateLookCalls=calculateLookCalls,
        cameraModuleUpdates=cameraModuleUpdates,
        controllerUpdates=controllerUpdates,
        controllerUpdateErrors=controllerUpdateErrors,
        rotateNonzeroAtCameraUpdateEntry=rotateNonzeroAtCameraUpdateEntry,
        rotateNonzeroAtControllerEntry=rotateNonzeroAtControllerEntry,
        rotateZeroAtControllerExit=rotateZeroAtControllerExit,
        rotateConsumedOrClearedInController=rotateConsumedOrClearedInController,
        rotateClearedInsideCalculateLook=rotateClearedInsideCalculateLook,
        rotateClearedAfterCalculateLook=rotateClearedAfterCalculateLook,
        updatesWithTouchNativeWrites=updatesWithTouchNativeWrites,
        updatesWithRelayMouseWrites=updatesWithRelayMouseWrites,
        updatesWithNativeMouseWrites=updatesWithNativeMouseWrites,
        updatesWithMultipleInputWrites=updatesWithMultipleInputWrites,
        maxWritesBeforeOneUpdate=maxWritesBeforeOneUpdate,
        updateDtCount=updateDtCount,
        updateDtMean=updateDtCount>0 and round(updateDtSum/updateDtCount,9) or nil,
        updateDtMin=updateDtCount>0 and round(updateDtMin,9) or nil,
        updateDtMax=updateDtCount>0 and round(updateDtMax,9) or nil,
        inputTranslationXCount=inputTranslationXCount,
        inputTranslationXCoeffMean=inputTranslationXCount>0 and round(inputTranslationXCoeffSum/inputTranslationXCount,9) or nil,
        inputTranslationXCoeffMin=inputTranslationXCount>0 and round(inputTranslationXCoeffMin,9) or nil,
        inputTranslationXCoeffMax=inputTranslationXCount>0 and round(inputTranslationXCoeffMax,9) or nil,
        inputTranslationYCount=inputTranslationYCount,
        inputTranslationYCoeffMean=inputTranslationYCount>0 and round(inputTranslationYCoeffSum/inputTranslationYCount,9) or nil,
        inputTranslationYCoeffMin=inputTranslationYCount>0 and round(inputTranslationYCoeffMin,9) or nil,
        inputTranslationYCoeffMax=inputTranslationYCount>0 and round(inputTranslationYCoeffMax,9) or nil,
        updateSequenceSummary=countSummary(updateSequenceCounts),
        stateChangeSummary=countSummary(stateChangeCounts,20),
        lastInputSequence=lastInputSequence,
        lastUpdateSequence=lastUpdateSequence,
        lastTimingSnapshot=lastTimingSnapshot,
        lastControllerStateChange=lastControllerStateChange,
        rotateAtStart=stateAtStart and stateAtStart.rotateInput,
        rotateAtStop=frozen and frozen.rotateInput,
        preferredInputAtStop=frozen and frozen.preferredInput,
        relayEnabled=frozen and frozen.relayEnabled,
        relayValidationReady=base.relayValidationReady,
        ownershipGateProven=base.ownershipGateProven,
        touchRoleConflicts=base.touchRoleConflicts,
        joystickMouseCrossovers=base.joystickMouseCrossovers,
        relayErrors=base.relayErrors,
        v604CallbackErrors=base.callbackErrors,
        validationReady=probeFrames>=30 and callbackErrors==0 and onInputChangedCalls>0
            and controllerUpdates>0 and calculateLookCalls>0,
        experimentReason=decision.experimentReason,
        observationalOnly=true,
        writesCameraCFrame=false,
        writesRootPartCFrame=false,
        forcesPreferredInput=false,
        forcesMouseBehavior=false,
        forcesRotationType=false,
        forcesAutoRotate=false,
        changesSensitivity=false,
        changesGain=false,
        changesPhysics=false,
        usesSyntheticUserInputObject=false,
        usesFireSignal=false,
        usesVirtualInput=false,
        preservesV604Ownership=true,
        fallbackV500Preserved=true,
        touchInputPipeline=decision.touchInputPipeline,
        mouseInputPipeline=decision.mouseInputPipeline,
        firstInputSemanticDivergence=decision.firstInputSemanticDivergence,
        timingDivergenceFound=decision.timingDivergenceFound,
        gainOriginFound=decision.gainOriginFound,
        pcSemanticsReproducible=decision.pcSemanticsReproducible,
        anchorRelevance=decision.anchorRelevance,
        experimentEligible=decision.experimentEligible,
    }
    for route,stats in pairs(routeStats) do
        for _,name in ipairs({
            "calls","errors","nonzero","zero","deltaXAbs","deltaYAbs","rotateXAbs","rotateYAbs",
            "xCoeffCount","xCoeffMean","xCoeffMin","xCoeffMax","yCoeffCount","yCoeffMean","yCoeffMin","yCoeffMax",
            "intervalCount","intervalMeanMs","intervalMinMs","intervalMaxMs",
            "updateLagCount","updateLagMeanMs","updateLagMinMs","updateLagMaxMs","helperCalls",
            "mouseSensitivityCount","mouseSensitivityMean","mouseSensitivityMin","mouseSensitivityMax",
            "viewportSamples","viewportXMin","viewportXMax","viewportYMin","viewportYMax",
        }) do result[route..name:sub(1,1):upper()..name:sub(2)]=round(statValue(stats,name),9) end
    end
    return result
end

local REPORT_KEYS={
    "version","bridgeMode","probePurpose","probeRunning","probeFrames","probeDuration","discoveryStatus",
    "discoveryErrors","decompileStatus","staticTouchTranslationFound","staticMouseDeltaFound",
    "staticMouseSensitivityFound","staticRotateResetFound","hooksCurrentlyInstalled","hooksInstalledTotal",
    "hookInstallFailures","hookRestoreOk","hookRestoreDetail","callbackErrors","traceDropped","evidenceDropped",
    "onInputChangedCalls","touchInputEvents","mouseMovementInputEvents","otherInputEvents","onTouchChangedCalls",
    "onMouseMovedCalls","touchHandlerExtraArgCalls","mouseHandlerExtraArgCalls","handlerNumericDtLikeArgs",
    "relayMouseCallsNestedInTouchInput","nativeMouseCallsNestedInMouseInput",
    "sameTouchObjectRelayCalls","mouseCallsWithoutMatchingInputEvent","inputTranslationCalls",
    "inputTranslationTouchCalls","inputTranslationMouseCalls","inputTranslationExtraArgCalls",
    "inputTranslationNumericDtLikeArgs","handlerDtDependencyObserved","inputTranslationDtDependencyObserved",
    "calculateLookCalls","cameraModuleUpdates",
    "controllerUpdates","controllerUpdateErrors","rotateNonzeroAtCameraUpdateEntry","rotateNonzeroAtControllerEntry",
    "rotateZeroAtControllerExit","rotateConsumedOrClearedInController","rotateClearedInsideCalculateLook",
    "rotateClearedAfterCalculateLook","updatesWithTouchNativeWrites","updatesWithRelayMouseWrites",
    "updatesWithNativeMouseWrites","updatesWithMultipleInputWrites","maxWritesBeforeOneUpdate",
    "updateDtCount","updateDtMean","updateDtMin","updateDtMax","inputTranslationXCount",
    "inputTranslationXCoeffMean","inputTranslationXCoeffMin","inputTranslationXCoeffMax",
    "inputTranslationYCount","inputTranslationYCoeffMean","inputTranslationYCoeffMin","inputTranslationYCoeffMax",
    "updateSequenceSummary","stateChangeSummary","lastInputSequence","lastUpdateSequence","lastTimingSnapshot",
    "lastControllerStateChange","rotateAtStart","rotateAtStop","preferredInputAtStop","relayEnabled",
    "relayValidationReady","ownershipGateProven","touchRoleConflicts","joystickMouseCrossovers","relayErrors",
    "v604CallbackErrors","validationReady","experimentReason","observationalOnly","writesCameraCFrame",
    "writesRootPartCFrame","forcesPreferredInput","forcesMouseBehavior","forcesRotationType","forcesAutoRotate",
    "changesSensitivity","changesGain","changesPhysics","usesSyntheticUserInputObject","usesFireSignal",
    "usesVirtualInput","preservesV604Ownership","fallbackV500Preserved",
}

local ROUTE_KEYS={"touchNativeRelayOff","touchBookkeepingRelayOn","mouseTouchRelay","mouseNative","mouseOther"}
local ROUTE_FIELDS={
    "Calls","Errors","Nonzero","Zero","DeltaXAbs","DeltaYAbs","RotateXAbs","RotateYAbs",
    "XCoeffCount","XCoeffMean","XCoeffMin","XCoeffMax","YCoeffCount","YCoeffMean","YCoeffMin","YCoeffMax",
    "IntervalCount","IntervalMeanMs","IntervalMinMs","IntervalMaxMs",
    "UpdateLagCount","UpdateLagMeanMs","UpdateLagMinMs","UpdateLagMaxMs","HelperCalls",
    "MouseSensitivityCount","MouseSensitivityMean","MouseSensitivityMin","MouseSensitivityMax",
    "ViewportSamples","ViewportXMin","ViewportXMax","ViewportYMin","ViewportYMax",
}

getgenv().PCV610Report=function(includeEvidence)
    local diagnostics=getgenv().PCV610Diagnostics()
    local lines={"=== PC MOVEMENT V610 REPORT ==="}
    for _,key in ipairs(REPORT_KEYS) do lines[#lines+1]=key.." = "..tostring(diagnostics[key]) end
    for _,route in ipairs(ROUTE_KEYS) do
        for _,field in ipairs(ROUTE_FIELDS) do
            local key=route..field
            lines[#lines+1]=key.." = "..tostring(diagnostics[key])
        end
    end
    if includeEvidence~=false then
        lines[#lines+1]=""
        lines[#lines+1]="=== V610 FOCUSED BASECAMERA STATIC WINDOWS ==="
        lines[#lines+1]=baseCameraSnippet~="" and baseCameraSnippet or "unavailable"
        lines[#lines+1]=""
        lines[#lines+1]="=== V610 FOCUSED CONTROLLER UPDATE WINDOW ==="
        lines[#lines+1]=controllerUpdateSnippet~="" and controllerUpdateSnippet or "unavailable"
        lines[#lines+1]=""
        lines[#lines+1]="=== V610 RUNTIME TIMING TRACE ==="
        for _,line in ipairs(traceLines) do lines[#lines+1]=line end
        lines[#lines+1]=""
        lines[#lines+1]="=== V610 TARGET EVIDENCE ==="
        for _,line in ipairs(evidence) do lines[#lines+1]=line end
        if type(baseReport)=="function" then
            local ok,text=pcall(baseReport,false)
            if ok then lines[#lines+1]=""; lines[#lines+1]=text end
        end
    end
    lines[#lines+1]=""
    lines[#lines+1]="=== V610 REQUIRED DECISION ==="
    lines[#lines+1]="touchInputPipeline = "..tostring(diagnostics.touchInputPipeline)
    lines[#lines+1]="mouseInputPipeline = "..tostring(diagnostics.mouseInputPipeline)
    lines[#lines+1]="firstInputSemanticDivergence = "..tostring(diagnostics.firstInputSemanticDivergence)
    lines[#lines+1]="timingDivergenceFound = "..tostring(diagnostics.timingDivergenceFound)
    lines[#lines+1]="gainOriginFound = "..tostring(diagnostics.gainOriginFound)
    lines[#lines+1]="pcSemanticsReproducible = "..tostring(diagnostics.pcSemanticsReproducible)
    lines[#lines+1]="anchorRelevance = "..tostring(diagnostics.anchorRelevance)
    lines[#lines+1]="experimentEligible = "..tostring(diagnostics.experimentEligible)
    return table.concat(lines,"\n")
end

local function copyToClipboard(text)
    local env=getgenv()
    for _,fn in ipairs({env.setclipboard,env.toclipboard,setclipboard,toclipboard}) do
        if type(fn)=="function" and pcall(fn,text) then return true end
    end
    local clipboard=env.Clipboard
    if type(clipboard)=="table" then
        for _,name in ipairs({"set","Set","setclipboard"}) do
            if type(clipboard[name])=="function" and pcall(clipboard[name],text) then return true end
        end
    end
    return false
end

local function setStatus(text,color)
    if statusLabel then statusLabel.Text=text; if color then statusLabel.TextColor3=color end end
end

local function makeButton(parent,text,color,order)
    local button=Instance.new("TextButton")
    button.LayoutOrder=order
    button.Size=UDim2.new(1,0,0,34)
    button.BackgroundColor3=color
    button.BorderSizePixel=0
    button.Text=text
    button.TextColor3=Color3.new(1,1,1)
    button.TextSize=12
    button.TextWrapped=true
    button.Font=Enum.Font.GothamBold
    button.Parent=parent
    local corner=Instance.new("UICorner")
    corner.CornerRadius=UDim.new(0,8)
    corner.Parent=button
    return button
end

local function refreshRelayButton()
    if not relayButton then return end
    local active=relayEnabled()
    relayButton.Text=active and "RELAY V604: LIGADO • MOUSE ROUTE" or "RELAY V604: OFF • TOUCH NATIVO"
    relayButton.BackgroundColor3=active and Color3.fromRGB(124,58,237) or Color3.fromRGB(71,85,105)
end

local function createPanel()
    local parent=CoreGui
    pcall(function() if gethui then parent=gethui() end end)
    if not parent then return end
    local old=parent:FindFirstChild(UI_NAME)
    if old then old:Destroy() end
    local gui=Instance.new("ScreenGui")
    gui.Name=UI_NAME; gui.ResetOnSpawn=false; gui.DisplayOrder=999999; gui.Parent=parent
    screenGui=gui

    local panel=Instance.new("Frame")
    panel.Size=UDim2.fromOffset(318,462)
    panel.Position=UDim2.new(1,-330,0.5,-231)
    panel.BackgroundColor3=Color3.fromRGB(9,14,28)
    panel.BackgroundTransparency=0.04
    panel.BorderSizePixel=0; panel.Active=true; panel.Draggable=true; panel.Parent=gui
    local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(0,14); corner.Parent=panel
    local stroke=Instance.new("UIStroke"); stroke.Color=Color3.fromRGB(56,189,248); stroke.Thickness=1.5; stroke.Parent=panel

    local title=Instance.new("TextLabel")
    title.Size=UDim2.new(1,-48,0,34); title.Position=UDim2.fromOffset(13,7)
    title.BackgroundTransparency=1; title.Text="V610 • INPUT TIMING TRACE"
    title.TextColor3=Color3.fromRGB(125,211,252); title.TextSize=15; title.Font=Enum.Font.GothamBold
    title.TextXAlignment=Enum.TextXAlignment.Left; title.Parent=panel

    local collapse=Instance.new("TextButton")
    collapse.Size=UDim2.fromOffset(30,30); collapse.Position=UDim2.new(1,-38,0,7)
    collapse.BackgroundColor3=Color3.fromRGB(30,41,59); collapse.BorderSizePixel=0
    collapse.Text="–"; collapse.TextColor3=Color3.new(1,1,1); collapse.TextSize=20
    collapse.Font=Enum.Font.GothamBold; collapse.Parent=panel
    local collapseCorner=Instance.new("UICorner"); collapseCorner.CornerRadius=UDim.new(0,8); collapseCorner.Parent=collapse

    local body=Instance.new("Frame")
    body.Size=UDim2.new(1,-24,1,-48); body.Position=UDim2.fromOffset(12,42)
    body.BackgroundTransparency=1; body.Parent=panel
    local layout=Instance.new("UIListLayout"); layout.Padding=UDim.new(0,6); layout.SortOrder=Enum.SortOrder.LayoutOrder; layout.Parent=body

    local instructions=Instance.new("TextLabel")
    instructions.LayoutOrder=0; instructions.Size=UDim2.new(1,0,0,94)
    instructions.BackgroundColor3=Color3.fromRGB(18,28,48); instructions.BorderSizePixel=0
    instructions.Text="1) INICIAR e arrastar com RELAY OFF (Touch nativo)\n2) Faça joystick+câmera; ligue RELAY V604\n3) Arraste igual com relay ligado\n4) PARAR e COPIAR antes de sair"
    instructions.TextColor3=Color3.fromRGB(226,232,240); instructions.TextSize=11
    instructions.TextWrapped=true; instructions.TextXAlignment=Enum.TextXAlignment.Left
    instructions.Font=Enum.Font.Gotham; instructions.Parent=body
    local instructionCorner=Instance.new("UICorner"); instructionCorner.CornerRadius=UDim.new(0,8); instructionCorner.Parent=instructions

    local start=makeButton(body,"INICIAR",Color3.fromRGB(34,197,94),1)
    relayButton=makeButton(body,"RELAY V604: OFF • TOUCH NATIVO",Color3.fromRGB(71,85,105),2)
    local stop=makeButton(body,"PARAR",Color3.fromRGB(245,158,11),3)
    experimentButton=makeButton(body,"EXPERIMENTO: BLOQUEADO",Color3.fromRGB(55,65,81),4)
    local emergency=makeButton(body,"EMERGÊNCIA • RELAY OFF / V500",Color3.fromRGB(190,24,93),5)
    local copy=makeButton(body,"COPIAR REPORT COMPLETO",Color3.fromRGB(2,132,199),6)
    statusLabel=Instance.new("TextLabel")
    statusLabel.LayoutOrder=7; statusLabel.Size=UDim2.new(1,0,0,30); statusLabel.BackgroundTransparency=1
    statusLabel.Text="Pronto. Primeiro teste Touch nativo com relay OFF."
    statusLabel.TextColor3=Color3.fromRGB(148,163,184); statusLabel.TextSize=10
    statusLabel.TextWrapped=true; statusLabel.Font=Enum.Font.Gotham; statusLabel.Parent=body

    uiConnections[#uiConnections+1]=start.Activated:Connect(function()
        local ok=startProbe()
        setStatus(ok and "Trace ativo. Arraste primeiro com relay OFF." or "Falha ao iniciar hooks.",
            ok and Color3.fromRGB(74,222,128) or Color3.fromRGB(251,113,133))
    end)
    uiConnections[#uiConnections+1]=relayButton.Activated:Connect(function()
        local want=not relayEnabled()
        if type(baseSetRelay)~="function" then
            setStatus("Relay indisponível; V500 preservado.",Color3.fromRGB(251,113,133)); return
        end
        local ok,result=pcall(baseSetRelay,want)
        if not ok or result==false then
            setStatus("Relay recusado: faça joystick+câmera juntos.",Color3.fromRGB(250,204,21))
        else
            setStatus(want and "Relay ligado. Repita o mesmo arrasto." or "Relay OFF: Touch nativo.",Color3.fromRGB(196,181,253))
        end
        refreshRelayButton()
    end)
    uiConnections[#uiConnections+1]=stop.Activated:Connect(function()
        stopProbe(); setStatus("Trace parado e hooks restaurados. Agora copie.",Color3.fromRGB(250,204,21))
    end)
    uiConnections[#uiConnections+1]=experimentButton.Activated:Connect(function()
        setStatus("Bloqueado: V610 mede; não altera timing nem gain.",Color3.fromRGB(250,204,21))
    end)
    uiConnections[#uiConnections+1]=emergency.Activated:Connect(function()
        stopProbe()
        if type(baseSetRelay)=="function" then pcall(baseSetRelay,false) end
        refreshRelayButton()
        setStatus("Emergência: relay OFF; V500 ativo.",Color3.fromRGB(251,113,133))
    end)
    uiConnections[#uiConnections+1]=copy.Activated:Connect(function()
        stopProbe()
        local ok=copyToClipboard(getgenv().PCV610Report(true))
        setStatus(ok and "REPORT COPIADO. Agora pode sair e colar." or "Clipboard indisponível no Delta.",
            ok and Color3.fromRGB(74,222,128) or Color3.fromRGB(251,113,133))
    end)
    local expanded=true
    uiConnections[#uiConnections+1]=collapse.Activated:Connect(function()
        expanded=not expanded; body.Visible=expanded
        panel.Size=expanded and UDim2.fromOffset(318,462) or UDim2.fromOffset(318,45)
        collapse.Text=expanded and "–" or "+"
    end)
    refreshRelayButton()
end

local discoverOk,discoverError=pcall(discoverFocusedPipeline)
if not discoverOk then discoveryStatus="error:"..cleanText(discoverError,180); addEvidence("DISCOVERY",discoveryStatus) end
local hookOk,hookError=pcall(installFocusedHooks)
if not hookOk then addEvidence("HOOK","installation-error="..cleanText(hookError,180)) end
local uiOk,uiError=pcall(createPanel)
if not uiOk then addEvidence("UI","creation-error="..cleanText(uiError,180)) end

getgenv().PCV610Start=startProbe
getgenv().PCV610Stop=function() stopProbe(); return getgenv().PCV610Report(false) end
getgenv().PCV610EmergencyV500=function()
    stopProbe()
    if type(baseSetRelay)=="function" then pcall(baseSetRelay,false) end
    refreshRelayButton()
    return true,"relay-disabled-v500-active"
end

getgenv().__PCMobileAimCleanup=function()
    probeRunning=false; inputStack={}; routeStack={}; currentUpdate=nil
    for _,connection in ipairs(uiConnections) do pcall(function() connection:Disconnect() end) end
    uiConnections={}
    if screenGui then pcall(function() screenGui:Destroy() end) end
    screenGui=nil
    restoreHooks()
    getgenv().PCV610Start=nil
    getgenv().PCV610Stop=nil
    getgenv().PCV610EmergencyV500=nil
    getgenv().PCV610Diagnostics=nil
    getgenv().PCV610Report=nil
    if baseCleanup then pcall(baseCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

addEvidence("READY","V610 focused rotateInput semantic/timing trace ready; observational only")
warn("[V610] input semantic/timing trace ready | observational only | use mobile panel")
