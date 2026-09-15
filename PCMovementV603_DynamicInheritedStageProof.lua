local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")

local player=Players.LocalPlayer
local WATCH_BIND="__PCMovementV603DynamicStageWatch"

--[[
    V603 / DYNAMIC INHERITED STAGE PROOF

    V602 found the BaseCamera inheritance stage on Delta:
      ConnectInputEvents -> OnInputChanged -> OnTouchChanged / OnMouseMoved

    V603 deliberately stops inferring ownership through getconnections(). It
    finds the exact inherited method names, hooks OnInputChanged, and initially
    forwards every call to the original with byte-for-byte identical arguments.
    Calls count as active-camera proof only when self is the controller returned
    by PlayerModule's GetActiveCameraController path at call time.

    OnTouchChanged and OnMouseMoved are optional observation hooks. They also
    forward unchanged and exist only to prove which branch OnInputChanged chose.

    Phase 2 is separate, disabled on every load, and cannot be enabled before a
    real Touch reaches OnInputChanged with self == activeCameraController. When
    explicitly enabled, it routes an eligible real Touch UserInputObject to the
    inherited OnMouseMoved method without creating a synthetic input object.

    This layer never reconnects UIS.InputChanged, calls UpdateMouseBehavior,
    uses firesignal/VirtualInputManager mouse injection, changes gain/physics,
    writes Camera/RootPart CFrame, or changes Humanoid.AutoRotate. V500 remains
    loaded underneath as the fail-open camera/movement behavior.
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

getgenv().PCMovementVersion="V603-DynamicInheritedStageProof"
getgenv().PCInputBridgeMode="v603-observational-over-v500"
getgenv().PCInputBridgeDiscovery="inherited-method-scan-pending"
-- Never inherit an enabled phase 2 from an earlier execution.
getgenv().PCV603Phase2Enabled=false
if getgenv().PCV603Phase2AutoFallback==nil then getgenv().PCV603Phase2AutoFallback=true end
if getgenv().PCV603Phase2NoRotateLimit==nil then getgenv().PCV603Phase2NoRotateLimit=8 end

local playerModule
local cameras
local activeController
local lastInstallAttempt=0
local probeInstalled=false
local probeStatus="not-installed"
local fallbackReason="probe-pending-v500-active"
local restoreOk=true
local restoreDetail="not-needed"

local methodTargets={}
local installedHooks={}
local hierarchyLevelsVisited=0
local hierarchyTablesDeduped=0
local hierarchyMaxDepth=0

local onInputChangedObservedEvents=0
local onInputChangedActiveControllerHits=0
local realTouchHits=0
local onTouchChangedHits=0
local onMouseMovedHits=0
local onInputTouchPathConfirmedHits=0
local onInputMousePathConfirmedHits=0
local inactiveControllerCalls=0
local callbackErrors=0
local lastInputType="none"
local lastInputDelta=nil
local lastProcessed=nil
local rotateBefore=nil
local rotateAfter=nil
local lastRoute="not-observed"
local lastSelfWasActive=false
local lastOnInputCalledOnTouchChanged=false
local lastOnInputCalledOnMouseMoved=false
local dynamicStageProven=false

local phase2Enabled=false
local phase2AutoDisabled=false
local phase2Attempts=0
local phase2Completed=0
local phase2Errors=0
local phase2RotateChanged=0
local phase2RotateUnchanged=0
local phase2ConsecutiveUnchanged=0
local phase2SameInputConfirmed=0
local phase2LastStatus="disabled-until-dynamic-proof"
local lastPhase2Gate="not-evaluated"
local phase2LastInput=nil

local contextStack={}
local evidence={}
local evidenceDropped=0

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
    if #evidence>=600 then
        evidenceDropped+=1
        return
    end
    evidence[#evidence+1]=string.format(
        "[%03d][%s] %s",#evidence+1,section,cleanText(message,900)
    )
end

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

local function getInputType(input)
    local inputType
    pcall(function() inputType=input.UserInputType end)
    return inputType
end

local function getInputDelta(input)
    local delta
    pcall(function() delta=input.Delta end)
    return delta
end

local function readRotate(controller)
    local value
    pcall(function() value=rawget(controller,"rotateInput") end)
    return value
end

local function rotationChanged(before,after)
    if typeof(before)~="Vector2" or typeof(after)~="Vector2" then return nil end
    return (after-before).Magnitude>1e-8
end

local function methodConstants(fn)
    local constants={}
    local getter=(debug and debug.getconstants) or getconstants
    if type(getter)~="function" then return constants,"unavailable" end
    local ok,values=pcall(getter,fn)
    if not ok or type(values)~="table" then return constants,"error:"..cleanText(values,100) end
    for _,value in ipairs(values) do
        if type(value)=="string" or type(value)=="number" then
            if #constants<36 then constants[#constants+1]=cleanText(value,70) end
        end
    end
    return constants,"ok"
end

local TARGET_METHODS={
    OnInputChanged=true,
    OnTouchChanged=true,
    OnMouseMoved=true,
    ConnectInputEvents=true,
}

local function findInheritedMethods(controller)
    methodTargets={}
    hierarchyLevelsVisited=0
    hierarchyTablesDeduped=0
    hierarchyMaxDepth=0
    local seen={}
    local maxDepth=16

    local function visit(tbl,depth,origin)
        if type(tbl)~="table" or depth>maxDepth then return end
        if seen[tbl] then
            hierarchyTablesDeduped+=1
            addEvidence("HIERARCHY",string.format(
                "depth=%d origin=%s deduped firstOrigin=%s",depth,origin,seen[tbl]
            ))
            return
        end
        seen[tbl]=origin
        hierarchyLevelsVisited+=1
        hierarchyMaxDepth=math.max(hierarchyMaxDepth,depth)

        local entries={}
        local ok,err=pcall(function()
            for key,value in pairs(tbl) do
                entries[#entries+1]={rawKey=key,key=cleanText(key,100),value=value}
            end
        end)
        if not ok then
            addEvidence("HIERARCHY",string.format(
                "depth=%d origin=%s enumeration-error=%s",depth,origin,cleanText(err,180)
            ))
            return
        end
        table.sort(entries,function(a,b) return a.key<b.key end)
        addEvidence("HIERARCHY",string.format(
            "depth=%d origin=%s table=%s keys=%d",depth,origin,cleanText(tbl,100),#entries
        ))

        local indexTable=nil
        for _,entry in ipairs(entries) do
            if entry.rawKey=="__index" and type(entry.value)=="table" then
                indexTable=entry.value
            end
            if TARGET_METHODS[entry.rawKey] and type(entry.value)=="function" then
                local constants,constantStatus=methodConstants(entry.value)
                local candidate={
                    fn=entry.value,
                    name=entry.rawKey,
                    depth=depth,
                    origin=origin.."."..entry.rawKey,
                    constants=constants,
                    constantStatus=constantStatus,
                }
                if not methodTargets[entry.rawKey] then methodTargets[entry.rawKey]=candidate end
                addEvidence("METHOD",string.format(
                    "name=%s depth=%d origin=%s function=%s constantsStatus=%s constants={%s}",
                    entry.rawKey,depth,candidate.origin,cleanText(entry.value,100),
                    constantStatus,table.concat(constants," | ")
                ))
            end
        end

        local metatable=nil
        if type(getrawmetatable)=="function" then
            pcall(function() metatable=getrawmetatable(tbl) end)
        end
        if type(metatable)~="table" then pcall(function() metatable=getmetatable(tbl) end) end
        if type(metatable)=="table" then visit(metatable,depth+1,origin.." -> getmetatable") end
        if type(indexTable)=="table" then visit(indexTable,depth+1,origin.." -> __index") end
    end

    visit(controller,0,"controller")
    addEvidence("HIERARCHY-SUMMARY",string.format(
        "levels=%d dedupedTables=%d maxDepth=%d OnInputChanged=%s OnTouchChanged=%s OnMouseMoved=%s ConnectInputEvents=%s",
        hierarchyLevelsVisited,hierarchyTablesDeduped,hierarchyMaxDepth,
        tostring(methodTargets.OnInputChanged~=nil),
        tostring(methodTargets.OnTouchChanged~=nil),
        tostring(methodTargets.OnMouseMoved~=nil),
        tostring(methodTargets.ConnectInputEvents~=nil)
    ))
    return methodTargets.OnInputChanged~=nil
end

local function phase2GateReason(controller,input,processed)
    if not phase2Enabled then return "phase2-disabled" end
    if phase2AutoDisabled then return "phase2-auto-disabled" end
    if not dynamicStageProven then return "dynamic-stage-unproven" end
    if controller~=getActiveController() then return "controller-not-active" end
    if getInputType(input)~=Enum.UserInputType.Touch then return "not-touch" end
    if processed==true then return "processed-touch" end
    local delta=getInputDelta(input)
    if delta==nil then return "delta-unavailable" end
    local nonZero=false
    pcall(function() nonZero=math.abs(delta.X)>1e-6 or math.abs(delta.Y)>1e-6 end)
    if not nonZero then return "zero-delta" end
    if getgenv().PCMovementEnabled==false then return "pc-movement-disabled" end
    if getgenv().PCV500CameraOnlyLockEnabled==false then return "v500-camera-lock-disabled" end
    local character=player.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health<=0 then return "humanoid-unavailable" end
    local blocked=false
    pcall(function()
        local state=humanoid:GetState()
        blocked=humanoid.PlatformStand
            or state==Enum.HumanoidStateType.Dead
            or state==Enum.HumanoidStateType.Physics
            or state==Enum.HumanoidStateType.Ragdoll
            or state==Enum.HumanoidStateType.FallingDown
    end)
    if blocked then return "humanoid-state-blocked" end
    if not methodTargets.OnMouseMoved then return "onmousemoved-unavailable" end
    return "open"
end

local function currentContext()
    return contextStack[#contextStack]
end

local function installHook(target,name,replacementFactory)
    if not target or type(target.fn)~="function" then return false,name.."-missing" end
    if type(hookfunction)~="function" then return false,"hookfunction-unavailable" end
    local original
    local replacement=replacementFactory(function(...)
        return original(...)
    end)
    local ok,old=pcall(function() return hookfunction(target.fn,replacement) end)
    if not ok or type(old)~="function" then
        return false,name.." hook failed: "..cleanText(old,180)
    end
    original=old
    installedHooks[#installedHooks+1]={name=name,target=target.fn,original=old}
    addEvidence("HOOK","installed observational hook name="..name.." origin="..target.origin)
    return true,"installed"
end

local function makeBranchObserver(name)
    return function(callOriginal)
        return function(self,input,...)
            local active=self==getActiveController()
            local context=currentContext()
            if active and name=="OnTouchChanged" then
                onTouchChangedHits+=1
                if context and context.self==self and context.input==input then
                    context.calledTouch=true
                    onInputTouchPathConfirmedHits+=1
                end
            elseif active and name=="OnMouseMoved" then
                onMouseMovedHits+=1
                if context and context.self==self and context.input==input then
                    context.calledMouse=true
                    onInputMousePathConfirmedHits+=1
                end
                if phase2LastInput~=nil and input==phase2LastInput then
                    phase2SameInputConfirmed+=1
                    if context then context.samePhase2Input=true end
                end
            end
            addEvidence("BRANCH",string.format(
                "method=%s activeController=%s inputType=%s delta=%s context=%s samePhase2Input=%s",
                name,tostring(active),tostring(getInputType(input)),cleanText(getInputDelta(input),120),
                tostring(context and context.id or "none"),
                tostring(phase2LastInput~=nil and input==phase2LastInput)
            ))
            return callOriginal(self,input,...)
        end
    end
end

local function makeOnInputObserver()
    return function(callOriginal)
        return function(self,input,processed,...)
            onInputChangedObservedEvents+=1
            local controller=getActiveController()
            local isActive=self==controller
            local inputType=getInputType(input)
            local delta=getInputDelta(input)
            local before=readRotate(self)
            local context={
                id=onInputChangedObservedEvents,
                self=self,
                input=input,
                calledTouch=false,
                calledMouse=false,
                samePhase2Input=false,
            }
            contextStack[#contextStack+1]=context

            lastInputType=tostring(inputType)
            lastInputDelta=delta
            lastProcessed=processed
            rotateBefore=before
            lastSelfWasActive=isActive
            lastOnInputCalledOnTouchChanged=false
            lastOnInputCalledOnMouseMoved=false
            if isActive then
                onInputChangedActiveControllerHits+=1
                if inputType==Enum.UserInputType.Touch then realTouchHits+=1 end
            else
                inactiveControllerCalls+=1
            end

            -- The first qualifying touch can only prove phase 1. Phase 2 is
            -- false on load and requires a later explicit setter call.
            if isActive and inputType==Enum.UserInputType.Touch then
                local firstProof=not dynamicStageProven
                dynamicStageProven=true
                if firstProof then
                    probeStatus="dynamic-stage-proven-observational"
                    getgenv().PCInputBridgeDiscovery="active-controller-OnInputChanged-received-real-Touch"
                    addEvidence("PROOF","dynamic stage proved by real Touch with self == activeCameraController")
                end
            end

            local gate=phase2GateReason(self,input,processed)
            lastPhase2Gate=gate
            local results
            local phase2DispatchSucceeded=false
            if gate=="open" then
                phase2Attempts+=1
                phase2LastInput=input
                lastRoute="phase2-touch-to-onmousemoved-same-object"
                local mouseTarget=methodTargets.OnMouseMoved
                results=table.pack(pcall(function()
                    return mouseTarget.fn(self,input)
                end))
                phase2LastInput=nil
                if results[1] then
                    phase2Completed+=1
                    phase2DispatchSucceeded=true
                else
                    phase2Errors+=1
                    callbackErrors+=1
                    phase2Enabled=false
                    phase2AutoDisabled=true
                    getgenv().PCV603Phase2Enabled=false
                    lastRoute="phase2-error-then-original-v500"
                    phase2LastStatus="error-fallback-v500: "..cleanText(results[2],160)
                    fallbackReason="phase2-error-v500-restored"
                    getgenv().PCInputBridgeMode="v603-observational-pass-through-over-v500"
                    addEvidence("PHASE2","OnMouseMoved error; forwarding same event to original OnInputChanged for fail-open V500")
                    results=table.pack(pcall(callOriginal,self,input,processed,...))
                end
            else
                lastRoute="phase1-original-arguments-unchanged"
                results=table.pack(pcall(callOriginal,self,input,processed,...))
            end

            local after=readRotate(self)
            rotateAfter=after
            lastOnInputCalledOnTouchChanged=context.calledTouch
            lastOnInputCalledOnMouseMoved=context.calledMouse
            contextStack[#contextStack]=nil

            if phase2DispatchSucceeded then
                local changed=rotationChanged(before,after)
                if changed==true then
                    phase2RotateChanged+=1
                    phase2ConsecutiveUnchanged=0
                    phase2LastStatus=context.samePhase2Input
                        and "same-touch-object-onmousemoved-rotate-changed"
                        or "onmousemoved-rotate-changed-observer-unconfirmed"
                else
                    phase2RotateUnchanged+=1
                    phase2ConsecutiveUnchanged+=1
                    phase2LastStatus=changed==false
                        and "onmousemoved-returned-rotate-unchanged"
                        or "onmousemoved-returned-rotate-unobservable"
                    local limit=math.max(1,tonumber(getgenv().PCV603Phase2NoRotateLimit) or 8)
                    if getgenv().PCV603Phase2AutoFallback~=false
                        and phase2ConsecutiveUnchanged>=limit then
                        phase2Enabled=false
                        phase2AutoDisabled=true
                        getgenv().PCV603Phase2Enabled=false
                        phase2LastStatus="auto-disabled-after-"..tostring(limit).."-unchanged"
                        fallbackReason="phase2-no-rotate-v500-restored"
                        getgenv().PCInputBridgeMode="v603-observational-over-v500"
                    end
                end
            end

            addEvidence("ONINPUT",string.format(
                "event=%d selfActive=%s inputType=%s delta=%s processed=%s route=%s gate=%s touchBranch=%s mouseBranch=%s rotateBefore=%s rotateAfter=%s ok=%s",
                context.id,tostring(isActive),tostring(inputType),cleanText(delta,120),
                tostring(processed),lastRoute,gate,tostring(context.calledTouch),
                tostring(context.calledMouse),cleanText(before,120),cleanText(after,120),
                tostring(results[1])
            ))

            if not results[1] then
                callbackErrors+=1
                error(results[2],0)
            end
            return table.unpack(results,2,results.n)
        end
    end
end

local function restoreHooks()
    local okAll=true
    local details={}
    for index=#installedHooks,1,-1 do
        local hook=installedHooks[index]
        local ok,err=pcall(function() hookfunction(hook.target,hook.original) end)
        okAll=okAll and ok
        details[#details+1]=hook.name.."="..tostring(ok)..(ok and "" or ":"..cleanText(err,100))
    end
    installedHooks={}
    probeInstalled=false
    restoreOk=okAll
    restoreDetail=#details>0 and table.concat(details,"; ") or "not-needed"
    if #details>0 then addEvidence("RESTORE",restoreDetail) end
    return okAll
end

local function installProbe(controller)
    probeStatus="scanning-inheritance"
    if type(controller)~="table" then
        probeStatus="active-controller-missing"
        fallbackReason="active-controller-missing-v500-active"
        return false
    end
    if not findInheritedMethods(controller) then
        probeStatus="OnInputChanged-not-found"
        fallbackReason="inherited-OnInputChanged-not-found-v500-active"
        getgenv().PCInputBridgeDiscovery=probeStatus
        return false
    end

    -- Helpers are optional observation points. Failure never blocks the primary
    -- OnInputChanged pass-through probe.
    if methodTargets.OnTouchChanged then
        local ok,detail=installHook(
            methodTargets.OnTouchChanged,"OnTouchChanged",makeBranchObserver("OnTouchChanged")
        )
        if not ok then addEvidence("HOOK","optional OnTouchChanged observer rejected: "..detail) end
    end
    if methodTargets.OnMouseMoved then
        local ok,detail=installHook(
            methodTargets.OnMouseMoved,"OnMouseMoved",makeBranchObserver("OnMouseMoved")
        )
        if not ok then addEvidence("HOOK","optional OnMouseMoved observer rejected: "..detail) end
    end

    local ok,detail=installHook(
        methodTargets.OnInputChanged,"OnInputChanged",makeOnInputObserver()
    )
    if not ok then
        restoreHooks()
        probeStatus="OnInputChanged-hook-failed: "..detail
        fallbackReason="OnInputChanged-hook-failed-v500-active"
        getgenv().PCInputBridgeDiscovery=probeStatus
        return false
    end

    probeInstalled=true
    probeStatus="observational-pass-through-installed"
    fallbackReason="observational-only-v500-preserved"
    getgenv().PCInputBridgeMode="v603-observational-pass-through-over-v500"
    getgenv().PCInputBridgeDiscovery="OnInputChanged-hooked-awaiting-active-controller-touch"
    addEvidence("ACTIVATION","OnInputChanged observational pass-through installed; arguments remain unchanged")
    return true
end

local function resetDynamicCounters()
    onInputChangedObservedEvents=0
    onInputChangedActiveControllerHits=0
    realTouchHits=0
    onTouchChangedHits=0
    onMouseMovedHits=0
    onInputTouchPathConfirmedHits=0
    onInputMousePathConfirmedHits=0
    inactiveControllerCalls=0
    callbackErrors=0
    lastInputType="none"
    lastInputDelta=nil
    lastProcessed=nil
    rotateBefore=nil
    rotateAfter=nil
    lastRoute="not-observed"
    lastSelfWasActive=false
    lastOnInputCalledOnTouchChanged=false
    lastOnInputCalledOnMouseMoved=false
    dynamicStageProven=false
    phase2Enabled=false
    phase2AutoDisabled=false
    phase2Attempts=0
    phase2Completed=0
    phase2Errors=0
    phase2RotateChanged=0
    phase2RotateUnchanged=0
    phase2ConsecutiveUnchanged=0
    phase2SameInputConfirmed=0
    phase2LastStatus="disabled-until-dynamic-proof"
    lastPhase2Gate="not-evaluated"
    phase2LastInput=nil
    getgenv().PCV603Phase2Enabled=false
end

getgenv().PCV603SetPhase2Enabled=function(enabled)
    if enabled~=true then
        phase2Enabled=false
        getgenv().PCV603Phase2Enabled=false
        phase2LastStatus="disabled-manually-v500-active"
        getgenv().PCInputBridgeMode="v603-observational-pass-through-over-v500"
        return true,"phase2-disabled"
    end
    if not dynamicStageProven then
        phase2LastStatus="enable-rejected-dynamic-stage-unproven"
        return false,"dynamicStageProven must be true before phase 2"
    end
    if not probeInstalled or not methodTargets.OnMouseMoved then
        phase2LastStatus="enable-rejected-OnMouseMoved-unavailable"
        return false,"OnMouseMoved observation target is unavailable"
    end
    phase2AutoDisabled=false
    phase2ConsecutiveUnchanged=0
    phase2Enabled=true
    getgenv().PCV603Phase2Enabled=true
    phase2LastStatus="enabled-awaiting-eligible-real-touch"
    fallbackReason="phase2-experiment-active-v500-fail-open-available"
    getgenv().PCInputBridgeMode="v603-phase2-same-touch-to-OnMouseMoved"
    addEvidence("PHASE2","explicitly enabled after dynamic proof; same real Touch object will be passed to OnMouseMoved")
    return true,"phase2-enabled"
end

RunService:BindToRenderStep(WATCH_BIND,Enum.RenderPriority.Camera.Value-4,function()
    local controller=getActiveController()
    if controller~=activeController then
        restoreHooks()
        activeController=controller
        resetDynamicCounters()
        probeStatus="controller-changed-reinstall-pending"
        fallbackReason="controller-changed-v500-active"
        lastInstallAttempt=0
    end
    if probeInstalled or os.clock()-lastInstallAttempt<0.75 then return end
    lastInstallAttempt=os.clock()
    local ok,err=pcall(function() installProbe(controller) end)
    if not ok then
        probeStatus="install-runtime-error: "..cleanText(err,180)
        fallbackReason="probe-runtime-error-v500-active"
        getgenv().PCInputBridgeDiscovery=probeStatus
    end
end)

activeController=getActiveController()
if activeController then
    local ok,err=pcall(function() installProbe(activeController) end)
    if not ok then
        probeStatus="install-runtime-error: "..cleanText(err,180)
        fallbackReason="probe-runtime-error-v500-active"
        getgenv().PCInputBridgeDiscovery=probeStatus
    end
else
    probeStatus="active-controller-pending"
    fallbackReason="active-controller-pending-v500-active"
end

getgenv().PCV603Diagnostics=function()
    local controller=getActiveController()
    local inMouseLockedMode=nil
    local getIsMouseLocked=nil
    local mouseLockOffset=nil
    local rotateInput=nil
    if type(controller)=="table" then
        pcall(function() inMouseLockedMode=controller.inMouseLockedMode end)
        pcall(function()
            if type(controller.GetIsMouseLocked)=="function" then
                getIsMouseLocked=controller:GetIsMouseLocked()
            end
        end)
        pcall(function() mouseLockOffset=controller.mouseLockOffset end)
        pcall(function() rotateInput=controller.rotateInput end)
    end
    return {
        version=getgenv().PCMovementVersion,
        bridgeMode=getgenv().PCInputBridgeMode,
        discovery=getgenv().PCInputBridgeDiscovery,
        probeInstalled=probeInstalled,
        probeStatus=probeStatus,
        onInputChangedFound=methodTargets.OnInputChanged~=nil,
        onInputChangedOrigin=methodTargets.OnInputChanged and methodTargets.OnInputChanged.origin or "none",
        onTouchChangedFound=methodTargets.OnTouchChanged~=nil,
        onTouchChangedOrigin=methodTargets.OnTouchChanged and methodTargets.OnTouchChanged.origin or "none",
        onMouseMovedFound=methodTargets.OnMouseMoved~=nil,
        onMouseMovedOrigin=methodTargets.OnMouseMoved and methodTargets.OnMouseMoved.origin or "none",
        connectInputEventsFound=methodTargets.ConnectInputEvents~=nil,
        hierarchyLevelsVisited=hierarchyLevelsVisited,
        hierarchyTablesDeduped=hierarchyTablesDeduped,
        hierarchyMaxDepth=hierarchyMaxDepth,
        onInputChangedObserved=onInputChangedObservedEvents>0,
        onInputChangedObservedEvents=onInputChangedObservedEvents,
        onInputChangedActiveControllerHits=onInputChangedActiveControllerHits,
        realTouchHits=realTouchHits,
        onTouchChangedHits=onTouchChangedHits,
        onMouseMovedHits=onMouseMovedHits,
        onInputTouchPathConfirmedHits=onInputTouchPathConfirmedHits,
        onInputMousePathConfirmedHits=onInputMousePathConfirmedHits,
        inactiveControllerCalls=inactiveControllerCalls,
        lastSelfWasActive=lastSelfWasActive,
        lastInputType=lastInputType,
        lastInputDelta=lastInputDelta,
        lastProcessed=lastProcessed,
        rotateBefore=rotateBefore,
        rotateAfter=rotateAfter,
        lastRoute=lastRoute,
        lastOnInputCalledOnTouchChanged=lastOnInputCalledOnTouchChanged,
        lastOnInputCalledOnMouseMoved=lastOnInputCalledOnMouseMoved,
        dynamicStageProven=dynamicStageProven,
        validationReady=probeInstalled and dynamicStageProven,
        phase2Enabled=phase2Enabled,
        phase2AutoDisabled=phase2AutoDisabled,
        phase2Attempts=phase2Attempts,
        phase2Completed=phase2Completed,
        phase2Errors=phase2Errors,
        phase2RotateChanged=phase2RotateChanged,
        phase2RotateUnchanged=phase2RotateUnchanged,
        phase2SameInputConfirmed=phase2SameInputConfirmed,
        phase2LastStatus=phase2LastStatus,
        lastPhase2Gate=lastPhase2Gate,
        phase2ValidationReady=phase2Completed>0
            and phase2SameInputConfirmed>0 and phase2RotateChanged>0,
        callbackErrors=callbackErrors,
        fallbackReason=fallbackReason,
        fallbackV500Preserved=restoreOk,
        v500TouchPathActive=not phase2Enabled,
        restoreOk=restoreOk,
        restoreDetail=restoreDetail,
        activeControllerFound=type(controller)=="table",
        inMouseLockedMode=inMouseLockedMode,
        getIsMouseLocked=getIsMouseLocked,
        mouseLockOffset=mouseLockOffset,
        rotateInput=rotateInput,
        preferredInput=tostring(UserInputService.PreferredInput),
        evidenceLines=#evidence,
        evidenceDropped=evidenceDropped,
        phase1ForwardsOriginalArguments=true,
        triggersReconnect=false,
        usesFireSignal=false,
        usesVirtualMouseInjection=false,
        callsUpdateMouseBehavior=false,
        writesCameraCFrame=false,
        writesRootPartCFrame=false,
        forcesAutoRotate=false,
        changesGainSensitivityPhysics=false,
    }
end

local function warnEvidenceChunks(lines)
    local chunk={}
    local length=0
    local index=1
    local function flush()
        if #chunk==0 then return end
        warn("=== PC MOVEMENT V603 EVIDENCE CHUNK "..tostring(index).." ===\n"..table.concat(chunk,"\n"))
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

getgenv().PCV603Evidence=function()
    local lines={
        "Phase 1 is observational: OnInputChanged and optional branch hooks forward original arguments unchanged.",
        "Only self == current activeCameraController contributes to dynamic proof counters.",
        "Phase 2 starts disabled and requires explicit PCV603SetPhase2Enabled(true) after proof.",
        "Evidence lines stored="..tostring(#evidence).." dropped-after-cap="..tostring(evidenceDropped),
    }
    for _,line in ipairs(evidence) do lines[#lines+1]=line end
    warnEvidenceChunks(lines)
    return "=== PC MOVEMENT V603 DETAILED EVIDENCE ===\n"..table.concat(lines,"\n")
end

getgenv().PCV603Report=function(includeEvidence)
    local diagnostics=getgenv().PCV603Diagnostics()
    local keys={
        "version","bridgeMode","discovery","probeInstalled","probeStatus",
        "onInputChangedFound","onInputChangedOrigin","onTouchChangedFound",
        "onTouchChangedOrigin","onMouseMovedFound","onMouseMovedOrigin",
        "connectInputEventsFound","hierarchyLevelsVisited","hierarchyTablesDeduped",
        "hierarchyMaxDepth","onInputChangedObserved","onInputChangedObservedEvents",
        "onInputChangedActiveControllerHits","realTouchHits","onTouchChangedHits",
        "onMouseMovedHits","onInputTouchPathConfirmedHits","onInputMousePathConfirmedHits",
        "inactiveControllerCalls","lastSelfWasActive","lastInputType","lastInputDelta",
        "lastProcessed","rotateBefore","rotateAfter","lastRoute",
        "lastOnInputCalledOnTouchChanged","lastOnInputCalledOnMouseMoved",
        "dynamicStageProven","validationReady","phase2Enabled","phase2AutoDisabled",
        "phase2Attempts","phase2Completed","phase2Errors","phase2RotateChanged",
        "phase2RotateUnchanged","phase2SameInputConfirmed","phase2LastStatus","lastPhase2Gate",
        "phase2ValidationReady","callbackErrors","fallbackReason","fallbackV500Preserved",
        "v500TouchPathActive","restoreOk","restoreDetail","activeControllerFound","inMouseLockedMode",
        "getIsMouseLocked","mouseLockOffset","rotateInput","preferredInput","evidenceLines","evidenceDropped",
        "phase1ForwardsOriginalArguments","triggersReconnect","usesFireSignal",
        "usesVirtualMouseInjection","callsUpdateMouseBehavior","writesCameraCFrame",
        "writesRootPartCFrame","forcesAutoRotate","changesGainSensitivityPhysics",
    }
    local lines={"=== PC MOVEMENT V603 REPORT ==="}
    for _,key in ipairs(keys) do lines[#lines+1]=key.." = "..tostring(diagnostics[key]) end
    local summary=table.concat(lines,"\n")
    warn(summary)
    local details=""
    if includeEvidence~=false then details=getgenv().PCV603Evidence() end
    return details~="" and summary.."\n\n"..details or summary
end

getgenv().__PCMobileAimCleanup=function()
    pcall(function() RunService:UnbindFromRenderStep(WATCH_BIND) end)
    phase2Enabled=false
    getgenv().PCV603Phase2Enabled=false
    restoreHooks()

    getgenv().PCV603SetPhase2Enabled=nil
    getgenv().PCV603Diagnostics=nil
    getgenv().PCV603Evidence=nil
    getgenv().PCV603Report=nil

    if baseCleanup then pcall(baseCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

warn(string.format(
    "[V603] dynamic inherited-stage probe | status=%s | OnInputChanged=%s | OnTouchChanged=%s | OnMouseMoved=%s | phase2=disabled",
    probeStatus,tostring(methodTargets.OnInputChanged~=nil),
    tostring(methodTargets.OnTouchChanged~=nil),tostring(methodTargets.OnMouseMoved~=nil)
))
