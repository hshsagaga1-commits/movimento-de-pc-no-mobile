local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")

local player=Players.LocalPlayer
local POST_BIND="__PCMovementV606PostComposition"
local UI_NAME="PCMovementV606Panel"

--[[
    V606 / MOUSE-LOCK COMPOSITION TRACE

    V604 remains the untouched functional layer. V606 does not repeat its
    ownership discovery and does not reuse V605's broad scan. It targets only
    the chain already implicated by the real V605 report:

      CameraModule.Update
        -> active camera controller Update
        -> GetSubjectPosition / CalculateNewLookCFrame
        -> GetIsMouseLocked / GetMouseLockOffset
        -> occlusion Update
        -> final camera result

    The real V605 constants also exposed an Evade-specific block containing
    PlayerScripts.ShiftLockEnabled, Character.PrimaryPart, ToOrientation and
    CFrame. V606 observes whether that block changes PrimaryPart during the
    camera update and records its order relative to camera composition.

    No experimental geometry mutation is enabled without runtime proof. The
    panel exposes a deliberately blocked experiment control until such proof
    exists. Emergency fallback only disables the validated V604 relay.
]]

local v604Source=game:HttpGet(
    "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV604_MultitouchOwnershipProbe.lua?_cb="
    ..HttpService:GenerateGUID(false),
    true
)
local v604Chunk,v604Error=loadstring(v604Source)
if not v604Chunk then error(v604Error) end
v604Chunk()

local baseCleanup=getgenv().__PCMobileAimCleanup
local baseSetRelay=getgenv().PCV604SetRelayEnabled
local baseDiagnostics=getgenv().PCV604Diagnostics
local baseReport=getgenv().PCV604Report

pcall(function() RunService:UnbindFromRenderStep(POST_BIND) end)

getgenv().PCMovementVersion="V606-MouseLockCompositionTrace"
getgenv().PCInputBridgeMode="v606-targeted-trace-over-v604"

local playerModule
local cameras
local controller
local occlusionController
local mouseLockController
local userGameSettings
pcall(function() userGameSettings=UserSettings():GetService("UserGameSettings") end)

local probeRunning=false
local probeFrames=0
local probeStartedAt=0
local probeDuration=0
local traceFrames=0
local traceErrors=0
local postSampleErrors=0
local currentContext=nil
local lastModuleExit=nil
local traceLines={}
local traceLinesDropped=0
local evidence={}
local evidenceDropped=0
local sequenceCounts={}
local installedHooks={}
local targets={}
local targetEvidence={}
local targetDiscoveryStatus="not-started"
local targetMethodsFound=0
local targetMethodsMissing={}

local cameraModuleUpdates=0
local controllerUpdates=0
local controllerUpdateErrors=0
local occlusionUpdates=0
local updateMouseBehaviorCalls=0
local updateMouseBehaviorInside=0
local updateMouseBehaviorOutside=0
local setIsMouseLockedCalls=0
local setIsMouseLockedInside=0
local setIsMouseLockedOutside=0
local setMouseLockOffsetCalls=0
local setMouseLockOffsetInside=0
local setMouseLockOffsetOutside=0
local getIsMouseLockedCalls=0
local getIsMouseLockedInside=0
local getMouseLockOffsetCalls=0
local getMouseLockOffsetInside=0
local getSubjectPositionCalls=0
local getSubjectPositionInside=0
local calculateLookCalls=0
local calculateLookInside=0
local getCameraLookCalls=0
local getCameraLookInside=0

local primaryPartChangedDuringUpdate=0
local primaryPartYawChangedDuringUpdate=0
local primaryPartPositionChangedDuringUpdate=0
local primaryPartYawDeltaSum=0
local primaryPartYawDeltaMax=0
local primaryPartPositionDeltaSum=0
local primaryPartPositionDeltaMax=0

local compositionSamples=0
local compositionMatches=0
local compositionMismatches=0
local compositionResidualSum=0
local compositionResidualMax=0
local compositionLastResidual=nil
local compositionLastActualShift=nil
local compositionLastPredictedShift=nil
local compositionLastSubjectPosition=nil
local compositionLastControllerFocus=nil
local compositionLookCandidateCount=0

local occlusionSamples=0
local occlusionPositionDeltaSum=0
local occlusionPositionDeltaMax=0
local occlusionFocusDeltaSum=0
local occlusionFocusDeltaMax=0
local postCameraSamples=0
local postCameraExternalChanges=0
local postCameraPositionDeltaSum=0
local postCameraPositionDeltaMax=0
local postCameraFocusDeltaSum=0
local postCameraFocusDeltaMax=0

local stationaryFrames=0
local movingFrames=0
local rootProjectionFrames=0
local rootScreenStepSum=0
local rootScreenStepMax=0
local previousRootScreen=nil

local lastInsideLockArg=nil
local lastOutsideLockArg=nil
local lastInsideOffsetArg=nil
local lastOutsideOffsetArg=nil
local lastGetLockReturn=nil
local lastGetOffsetReturn=nil
local lastMouseBehaviorBefore=nil
local lastMouseBehaviorAfter=nil
local lastRotationTypeBefore=nil
local lastRotationTypeAfter=nil
local lastControllerUpdateCFrame=nil
local lastControllerUpdateFocus=nil
local lastFinalCameraCFrame=nil
local lastFinalCameraFocus=nil

local screenGui=nil
local statusLabel=nil
local startButton=nil
local relayButton=nil
local experimentButton=nil
local uiConnections={}

local experimentEligible=false
local experimentEligibilityReason="no-safe-native-transformation-proved"
local experimentEnabled=false
local experimentAttempts=0
local experimentRejected=0

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
    local scale=10^(digits or 4)
    if value>=0 then return math.floor(value*scale+0.5)/scale end
    return math.ceil(value*scale-0.5)/scale
end

local function addEvidence(section,message)
    if #evidence>=260 then
        evidenceDropped+=1
        return
    end
    evidence[#evidence+1]=string.format("[%03d][%s] %s",#evidence+1,section,cleanText(message,1000))
end

local function addTrace(message)
    if #traceLines>=420 then
        traceLinesDropped+=1
        return
    end
    traceLines[#traceLines+1]=message
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
    local module=getCameras()
    if type(module)~="table" then return nil end
    local active=rawget(module,"activeCameraController")
    if type(active)~="table" and type(module.GetActiveCameraController)=="function" then
        pcall(function() active=module:GetActiveCameraController() end)
    end
    return type(active)=="table" and active or nil
end

local function refreshObjects()
    cameras=getCameras()
    controller=getActiveController()
    if type(cameras)=="table" then
        occlusionController=rawget(cameras,"activeOcclusionModule")
        mouseLockController=rawget(cameras,"activeMouseLockController")
    end
end

local function getMeta(tbl)
    local mt
    if type(getrawmetatable)=="function" then pcall(function() mt=getrawmetatable(tbl) end) end
    if type(mt)~="table" then pcall(function() mt=getmetatable(tbl) end) end
    return type(mt)=="table" and mt or nil
end

local function findMethod(root,name)
    local seen={}
    local function visit(tbl,depth,origin)
        if type(tbl)~="table" or depth>14 or seen[tbl] then return nil end
        seen[tbl]=true
        local value
        pcall(function() value=rawget(tbl,name) end)
        if type(value)=="function" then
            return {fn=value,owner=tbl,name=name,origin=origin.."."..name,depth=depth}
        end
        local index
        pcall(function() index=rawget(tbl,"__index") end)
        local mt=getMeta(tbl)
        local result
        if mt then result=visit(mt,depth+1,origin.." -> getmetatable") end
        if result then return result end
        if type(index)=="table" then result=visit(index,depth+1,origin.." -> __index") end
        return result
    end
    return visit(root,0,name=="Update" and cleanText(root,70) or "target")
end

local function constantsSummary(fn)
    local getter=(debug and debug.getconstants) or getconstants
    if type(getter)~="function" then return "unavailable" end
    local ok,values=pcall(getter,fn)
    if not ok or type(values)~="table" then return "error:"..cleanText(values,100) end
    local result={}
    for _,value in ipairs(values) do
        if (type(value)=="string" or type(value)=="number") and #result<80 then
            result[#result+1]=cleanText(value,65)
        end
    end
    return table.concat(result," | ")
end

local function tableShape(tbl)
    if type(tbl)~="table" then return "not-table" end
    local keys={}
    local ok=pcall(function()
        for key in pairs(tbl) do
            if #keys<30 then keys[#keys+1]=cleanText(key,55) end
        end
    end)
    if not ok then return "enumeration-error" end
    table.sort(keys)
    return "keys={"..table.concat(keys," | ").."}"
end

local function valueDetail(value)
    local kind=typeof(value)
    if kind=="table" then return "table:"..tableShape(value) end
    if kind=="Instance" then
        local full=cleanText(value,120)
        pcall(function() full=value:GetFullName() end)
        return "Instance:"..full
    end
    return kind..":"..cleanText(value,180)
end

local function upvaluesSummary(fn)
    local getter=(debug and debug.getupvalues) or getupvalues
    if type(getter)~="function" then return "unavailable" end
    local ok,values=pcall(getter,fn)
    if not ok or type(values)~="table" then return "error:"..cleanText(values,100) end
    local result={}
    for index,value in pairs(values) do
        if #result<36 then result[#result+1]=tostring(index).."="..valueDetail(value) end
    end
    return table.concat(result," | ")
end

local function protosSummary(fn)
    local getter=(debug and debug.getprotos) or getprotos
    if type(getter)~="function" then return "unavailable" end
    local ok,values=pcall(getter,fn)
    if not ok or type(values)~="table" then return "error:"..cleanText(values,100) end
    local result={}
    for index,proto in pairs(values) do
        if type(proto)=="function" and #result<16 then
            result[#result+1]=tostring(index).."{"..constantsSummary(proto).."}"
        end
    end
    return #result>0 and table.concat(result," | ") or "none"
end

local function registerTarget(id,root,name)
    local target=type(root)=="table" and findMethod(root,name) or nil
    targets[id]=target
    if target then
        targetMethodsFound+=1
        local detail={
            id=id,
            name=name,
            origin=target.origin,
            constants=constantsSummary(target.fn),
            upvalues=upvaluesSummary(target.fn),
            protos=protosSummary(target.fn),
        }
        targetEvidence[id]=detail
        addEvidence("TARGET",string.format(
            "%s origin=%s constants={%s} upvalues={%s} protos={%s}",
            id,detail.origin,detail.constants,detail.upvalues,detail.protos
        ))
    else
        targetMethodsMissing[#targetMethodsMissing+1]=id
        addEvidence("TARGET",id.." missing")
    end
end

local function discoverTargets()
    targetDiscoveryStatus="running"
    refreshObjects()
    targets={}
    targetEvidence={}
    targetMethodsFound=0
    targetMethodsMissing={}
    registerTarget("CameraModule.Update",cameras,"Update")
    registerTarget("Controller.Update",controller,"Update")
    registerTarget("Controller.UpdateMouseBehavior",controller,"UpdateMouseBehavior")
    registerTarget("Controller.SetIsMouseLocked",controller,"SetIsMouseLocked")
    registerTarget("Controller.GetIsMouseLocked",controller,"GetIsMouseLocked")
    registerTarget("Controller.SetMouseLockOffset",controller,"SetMouseLockOffset")
    registerTarget("Controller.GetMouseLockOffset",controller,"GetMouseLockOffset")
    registerTarget("Controller.GetSubjectPosition",controller,"GetSubjectPosition")
    registerTarget("Controller.CalculateNewLookCFrame",controller,"CalculateNewLookCFrame")
    registerTarget("Controller.GetCameraLookVector",controller,"GetCameraLookVector")
    registerTarget("Occlusion.Update",occlusionController,"Update")
    registerTarget("MouseLock.GetIsMouseLocked",mouseLockController,"GetIsMouseLocked")
    registerTarget("MouseLock.GetMouseLockOffset",mouseLockController,"GetMouseLockOffset")
    registerTarget("CameraModule.OnMouseLockToggled",cameras,"OnMouseLockToggled")
    targetDiscoveryStatus="complete"
end

local function yawFromCFrame(cf)
    if typeof(cf)~="CFrame" then return nil end
    return math.deg(math.atan2(-cf.LookVector.X,-cf.LookVector.Z))
end

local function angleDelta(current,previous)
    if type(current)~="number" or type(previous)~="number" then return nil end
    return (current-previous+180)%360-180
end

local function cframeDifference(a,b)
    if typeof(a)~="CFrame" or typeof(b)~="CFrame" then return nil,nil end
    local position=(a.Position-b.Position).Magnitude
    local dot=math.clamp(a.LookVector:Dot(b.LookVector),-1,1)
    local angle=math.deg(math.acos(dot))
    return position,angle
end

local function readRotationType()
    local value
    pcall(function() value=userGameSettings.RotationType end)
    return value
end

local function readMouseBehavior()
    local value
    pcall(function() value=UserInputService.MouseBehavior end)
    return value
end

local function callerClass()
    if type(checkcaller)~="function" then return "unknown" end
    local ok,value=pcall(checkcaller)
    if not ok then return "unknown" end
    return value and "executor" or "game"
end

local function stageRecord(name,phase,detail)
    local ctx=currentContext
    if ctx then
        ctx.sequence+=1
        ctx.order[#ctx.order+1]=name..":"..phase
        if ctx.capture then
            addTrace(string.format(
                "F%04d.%02d %s %s %s",ctx.id,ctx.sequence,name,phase,cleanText(detail,650)
            ))
        end
    end
end

local function packCall(original,...)
    return table.pack(pcall(original,...))
end

local function returnPacked(results)
    if not results[1] then error(results[2],0) end
    return table.unpack(results,2,results.n)
end

local function shouldCaptureFrame(id)
    return probeRunning and (id<=8 or id%120==0)
end

local function snapshotShiftState()
    local result={}
    local scripts=player:FindFirstChild("PlayerScripts")
    local shift=scripts and scripts:FindFirstChild("ShiftLockEnabled")
    result.instance=shift
    result.found=shift~=nil
    result.class=shift and shift.ClassName or "none"
    if shift then pcall(function() result.value=shift.Value end) end
    local character=player.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    local primary=character and character.PrimaryPart
    result.character=character
    result.humanoid=humanoid
    result.primary=primary
    if primary then pcall(function() result.primaryCFrame=primary.CFrame end) end
    if humanoid then
        pcall(function() result.autoRotate=humanoid.AutoRotate end)
        pcall(function() result.cameraOffset=humanoid.CameraOffset end)
        pcall(function() result.moveDirection=humanoid.MoveDirection end)
    end
    return result
end

local function controllerState()
    local state={}
    if type(controller)~="table" then return state end
    pcall(function() state.inMouseLockedMode=rawget(controller,"inMouseLockedMode") end)
    pcall(function() state.mouseLockOffset=rawget(controller,"mouseLockOffset") end)
    pcall(function() state.inFirstPerson=rawget(controller,"inFirstPerson") end)
    pcall(function() state.cameraMovementMode=rawget(controller,"cameraMovementMode") end)
    pcall(function() state.isFollowCamera=rawget(controller,"isFollowCamera") end)
    pcall(function() state.rotateInput=rawget(controller,"rotateInput") end)
    return state
end

local function mouseLockControllerState()
    local state={found=type(mouseLockController)=="table"}
    if type(mouseLockController)~="table" then return state end
    pcall(function() state.enabled=rawget(mouseLockController,"enabled") end)
    pcall(function() state.isMouseLocked=rawget(mouseLockController,"isMouseLocked") end)
    local getLock=targets["MouseLock.GetIsMouseLocked"]
    local getOffset=targets["MouseLock.GetMouseLockOffset"]
    if getLock then pcall(function() state.methodLocked=getLock.fn(mouseLockController) end) end
    if getOffset then pcall(function() state.methodOffset=getOffset.fn(mouseLockController) end) end
    return state
end

local function updateComposition(ctx)
    if not ctx.subjectPosition or typeof(ctx.controllerFocus)~="CFrame" then return end
    if #ctx.lookCFrames==0 or typeof(ctx.mouseLockOffset)~="Vector3" then return end
    local shift=ctx.shiftEntry
    local cameraOffset=shift and shift.cameraOffset
    if typeof(cameraOffset)~="Vector3" then cameraOffset=Vector3.zero end
    local totalOffset=ctx.mouseLockOffset+cameraOffset
    local actual=ctx.controllerFocus.Position-ctx.subjectPosition
    local bestResidual=math.huge
    local bestPredicted=nil
    for _,look in ipairs(ctx.lookCFrames) do
        if typeof(look)=="CFrame" then
            local predicted=totalOffset.X*look.RightVector
                +totalOffset.Y*look.UpVector+totalOffset.Z*look.LookVector
            local residual=(actual-predicted).Magnitude
            compositionLookCandidateCount+=1
            if residual<bestResidual then
                bestResidual=residual
                bestPredicted=predicted
            end
        end
    end
    if bestPredicted==nil then return end
    compositionSamples+=1
    compositionResidualSum+=bestResidual
    compositionResidualMax=math.max(compositionResidualMax,bestResidual)
    compositionLastResidual=bestResidual
    compositionLastActualShift=actual
    compositionLastPredictedShift=bestPredicted
    compositionLastSubjectPosition=ctx.subjectPosition
    compositionLastControllerFocus=ctx.controllerFocus.Position
    if bestResidual<=0.025 then compositionMatches+=1 else compositionMismatches+=1 end
    if ctx.capture then
        addTrace(string.format(
            "F%04d COMPOSITION actual=%s predicted=%s residual=%.6f offset=%s humanoidCameraOffset=%s lookCandidates=%d",
            ctx.id,cleanText(actual,120),cleanText(bestPredicted,120),bestResidual,
            cleanText(ctx.mouseLockOffset,90),cleanText(cameraOffset,90),#ctx.lookCFrames
        ))
    end
end

local function finishModuleContext(ctx)
    local shiftAfter=snapshotShiftState()
    ctx.shiftAfter=shiftAfter
    if typeof(ctx.shiftEntry.primaryCFrame)=="CFrame" and typeof(shiftAfter.primaryCFrame)=="CFrame" then
        local positionDelta,yawAngle=cframeDifference(ctx.shiftEntry.primaryCFrame,shiftAfter.primaryCFrame)
        positionDelta=positionDelta or 0
        yawAngle=yawAngle or 0
        local beforeYaw=yawFromCFrame(ctx.shiftEntry.primaryCFrame)
        local afterYaw=yawFromCFrame(shiftAfter.primaryCFrame)
        local yawDelta=math.abs(angleDelta(afterYaw,beforeYaw) or 0)
        if positionDelta>1e-6 or yawAngle>1e-5 then primaryPartChangedDuringUpdate+=1 end
        if yawDelta>1e-4 then primaryPartYawChangedDuringUpdate+=1 end
        if positionDelta>1e-5 then primaryPartPositionChangedDuringUpdate+=1 end
        primaryPartYawDeltaSum+=yawDelta
        primaryPartYawDeltaMax=math.max(primaryPartYawDeltaMax,yawDelta)
        primaryPartPositionDeltaSum+=positionDelta
        primaryPartPositionDeltaMax=math.max(primaryPartPositionDeltaMax,positionDelta)
        if ctx.capture then
            addTrace(string.format(
                "F%04d PRIMARY deltaPosition=%.8f deltaYaw=%.6f shiftValue=%s autoRotate=%s",
                ctx.id,positionDelta,yawDelta,tostring(shiftAfter.value),tostring(shiftAfter.autoRotate)
            ))
        end
    end
    updateComposition(ctx)
    local signature=table.concat(ctx.order,">")
    sequenceCounts[signature]=(sequenceCounts[signature] or 0)+1
end

local function installHook(id,factory)
    local target=targets[id]
    if not target then return false,"target-missing" end
    if type(hookfunction)~="function" then return false,"hookfunction-unavailable" end
    local original
    local replacement=factory(function(...)
        return original(...)
    end)
    local ok,old=pcall(function() return hookfunction(target.fn,replacement) end)
    if not ok or type(old)~="function" then return false,cleanText(old,160) end
    original=old
    installedHooks[#installedHooks+1]={id=id,target=target.fn,original=old}
    addEvidence("HOOK",id.." installed")
    return true,"installed"
end

local function cameraModuleUpdateFactory(callOriginal)
    return function(self,dt,...)
        if not probeRunning then return callOriginal(self,dt,...) end
        cameraModuleUpdates+=1
        probeFrames+=1
        local ctx={
            id=probeFrames,
            sequence=0,
            order={},
            capture=shouldCaptureFrame(probeFrames),
            shiftEntry=snapshotShiftState(),
            controllerEntry=controllerState(),
            cameraEntry=workspace.CurrentCamera and workspace.CurrentCamera.CFrame or nil,
            focusEntry=workspace.CurrentCamera and workspace.CurrentCamera.Focus or nil,
            lookCFrames={},
            caller=callerClass(),
        }
        currentContext=ctx
        stageRecord("CameraModule.Update","enter",string.format(
            "dt=%s caller=%s entryCFrame=%s entryFocus=%s shift=%s controllerLock=%s controllerOffset=%s MouseBehavior=%s RotationType=%s",
            cleanText(dt,50),ctx.caller,cleanText(ctx.cameraEntry,180),cleanText(ctx.focusEntry,180),
            tostring(ctx.shiftEntry.value),
            tostring(ctx.controllerEntry.inMouseLockedMode),cleanText(ctx.controllerEntry.mouseLockOffset,80),
            cleanText(readMouseBehavior(),80),cleanText(readRotationType(),80)
        ))
        local results=packCall(callOriginal,self,dt,...)
        local camera=workspace.CurrentCamera
        if camera then
            lastFinalCameraCFrame=camera.CFrame
            lastFinalCameraFocus=camera.Focus
            ctx.finalCameraCFrame=camera.CFrame
            ctx.finalCameraFocus=camera.Focus
        end
        stageRecord("CameraModule.Update","exit",string.format(
            "ok=%s finalCFrame=%s finalFocus=%s MouseBehavior=%s RotationType=%s",
            tostring(results[1]),cleanText(ctx.finalCameraCFrame,180),cleanText(ctx.finalCameraFocus,180),
            cleanText(readMouseBehavior(),80),cleanText(readRotationType(),80)
        ))
        if probeRunning then
            traceFrames+=1
            local okFinish,finishError=pcall(finishModuleContext,ctx)
            if not okFinish then
                traceErrors+=1
                addEvidence("TRACE-ERROR",finishError)
            end
            lastModuleExit={
                frame=ctx.id,
                cameraCFrame=ctx.finalCameraCFrame,
                cameraFocus=ctx.finalCameraFocus,
                time=os.clock(),
            }
        end
        currentContext=nil
        return returnPacked(results)
    end
end

local function controllerUpdateFactory(callOriginal)
    return function(self,dt,...)
        if not probeRunning then return callOriginal(self,dt,...) end
        controllerUpdates+=1
        stageRecord("Controller.Update","enter",string.format(
            "dt=%s lock=%s offset=%s rotateInput=%s MouseBehavior=%s RotationType=%s",
            cleanText(dt,50),tostring(rawget(self,"inMouseLockedMode")),
            cleanText(rawget(self,"mouseLockOffset"),80),cleanText(rawget(self,"rotateInput"),80),
            cleanText(readMouseBehavior(),80),cleanText(readRotationType(),80)
        ))
        local results=packCall(callOriginal,self,dt,...)
        local outCFrame=results[2]
        local outFocus=results[3]
        if not results[1] then controllerUpdateErrors+=1 end
        if typeof(outCFrame)=="CFrame" then lastControllerUpdateCFrame=outCFrame end
        if typeof(outFocus)=="CFrame" then lastControllerUpdateFocus=outFocus end
        local ctx=currentContext
        if ctx then
            ctx.controllerCFrame=outCFrame
            ctx.controllerFocus=outFocus
        end
        stageRecord("Controller.Update","exit",string.format(
            "ok=%s cframe=%s focus=%s",tostring(results[1]),cleanText(outCFrame,180),cleanText(outFocus,180)
        ))
        return returnPacked(results)
    end
end

local function updateMouseBehaviorFactory(callOriginal)
    return function(self,...)
        if not probeRunning then return callOriginal(self,...) end
        updateMouseBehaviorCalls+=1
        local inside=currentContext~=nil
        if inside then updateMouseBehaviorInside+=1 else updateMouseBehaviorOutside+=1 end
        local beforeMouse=readMouseBehavior()
        local beforeRotation=readRotationType()
        stageRecord("UpdateMouseBehavior","enter",string.format(
            "inside=%s caller=%s lock=%s firstPerson=%s MouseBehavior=%s RotationType=%s",
            tostring(inside),callerClass(),tostring(rawget(self,"inMouseLockedMode")),
            tostring(rawget(self,"inFirstPerson")),cleanText(beforeMouse,80),cleanText(beforeRotation,80)
        ))
        local results=packCall(callOriginal,self,...)
        local afterMouse=readMouseBehavior()
        local afterRotation=readRotationType()
        lastMouseBehaviorBefore=beforeMouse
        lastMouseBehaviorAfter=afterMouse
        lastRotationTypeBefore=beforeRotation
        lastRotationTypeAfter=afterRotation
        stageRecord("UpdateMouseBehavior","exit",string.format(
            "ok=%s MouseBehavior=%s RotationType=%s",tostring(results[1]),cleanText(afterMouse,80),cleanText(afterRotation,80)
        ))
        return returnPacked(results)
    end
end

local function setLockFactory(callOriginal)
    return function(self,value,...)
        if not probeRunning then return callOriginal(self,value,...) end
        setIsMouseLockedCalls+=1
        local inside=currentContext~=nil
        if inside then setIsMouseLockedInside+=1; lastInsideLockArg=value
        else setIsMouseLockedOutside+=1; lastOutsideLockArg=value end
        stageRecord("SetIsMouseLocked","enter",string.format(
            "inside=%s caller=%s arg=%s before=%s",tostring(inside),callerClass(),tostring(value),tostring(rawget(self,"inMouseLockedMode"))
        ))
        local results=packCall(callOriginal,self,value,...)
        stageRecord("SetIsMouseLocked","exit",string.format("ok=%s after=%s",tostring(results[1]),tostring(rawget(self,"inMouseLockedMode"))))
        return returnPacked(results)
    end
end

local function setOffsetFactory(callOriginal)
    return function(self,value,...)
        if not probeRunning then return callOriginal(self,value,...) end
        setMouseLockOffsetCalls+=1
        local inside=currentContext~=nil
        if inside then setMouseLockOffsetInside+=1; lastInsideOffsetArg=value
        else setMouseLockOffsetOutside+=1; lastOutsideOffsetArg=value end
        stageRecord("SetMouseLockOffset","enter",string.format(
            "inside=%s caller=%s arg=%s before=%s",tostring(inside),callerClass(),cleanText(value,100),cleanText(rawget(self,"mouseLockOffset"),100)
        ))
        local results=packCall(callOriginal,self,value,...)
        stageRecord("SetMouseLockOffset","exit",string.format("ok=%s after=%s",tostring(results[1]),cleanText(rawget(self,"mouseLockOffset"),100)))
        return returnPacked(results)
    end
end

local function getterFactory(kind)
    return function(callOriginal)
        return function(self,...)
            if not probeRunning then return callOriginal(self,...) end
            if kind=="lock" then
                getIsMouseLockedCalls+=1
                if currentContext then getIsMouseLockedInside+=1 end
            else
                getMouseLockOffsetCalls+=1
                if currentContext then getMouseLockOffsetInside+=1 end
            end
            stageRecord(kind=="lock" and "GetIsMouseLocked" or "GetMouseLockOffset","enter","caller="..callerClass())
            local results=packCall(callOriginal,self,...)
            local value=results[2]
            if kind=="lock" then lastGetLockReturn=value else lastGetOffsetReturn=value end
            local ctx=currentContext
            if ctx then
                if kind=="lock" then ctx.mouseLocked=value else ctx.mouseLockOffset=value end
            end
            stageRecord(kind=="lock" and "GetIsMouseLocked" or "GetMouseLockOffset","exit","ok="..tostring(results[1]).." value="..cleanText(value,100))
            return returnPacked(results)
        end
    end
end

local function subjectFactory(callOriginal)
    return function(self,...)
        if not probeRunning then return callOriginal(self,...) end
        getSubjectPositionCalls+=1
        if currentContext then getSubjectPositionInside+=1 end
        stageRecord("GetSubjectPosition","enter",string.format(
            "lock=%s subject=%s",tostring(rawget(self,"inMouseLockedMode")),cleanText(workspace.CurrentCamera and workspace.CurrentCamera.CameraSubject,100)
        ))
        local results=packCall(callOriginal,self,...)
        local value=results[2]
        if currentContext and typeof(value)=="Vector3" then currentContext.subjectPosition=value end
        stageRecord("GetSubjectPosition","exit","ok="..tostring(results[1]).." value="..cleanText(value,120))
        return returnPacked(results)
    end
end

local function lookFactory(callOriginal)
    return function(self,...)
        if not probeRunning then return callOriginal(self,...) end
        calculateLookCalls+=1
        if currentContext then calculateLookInside+=1 end
        local args=table.pack(...)
        stageRecord("CalculateNewLookCFrame","enter",string.format(
            "args=%s,%s rotateInput=%s",cleanText(args[1],100),cleanText(args[2],100),cleanText(rawget(self,"rotateInput"),100)
        ))
        local results=packCall(callOriginal,self,...)
        local value=results[2]
        if currentContext and typeof(value)=="CFrame" then currentContext.lookCFrames[#currentContext.lookCFrames+1]=value end
        stageRecord("CalculateNewLookCFrame","exit","ok="..tostring(results[1]).." value="..cleanText(value,180))
        return returnPacked(results)
    end
end

local function cameraLookFactory(callOriginal)
    return function(self,...)
        if not probeRunning then return callOriginal(self,...) end
        getCameraLookCalls+=1
        if currentContext then getCameraLookInside+=1 end
        stageRecord("GetCameraLookVector","enter","caller="..callerClass())
        local results=packCall(callOriginal,self,...)
        stageRecord("GetCameraLookVector","exit","ok="..tostring(results[1]).." value="..cleanText(results[2],120))
        return returnPacked(results)
    end
end

local function occlusionFactory(callOriginal)
    return function(self,dt,inputCFrame,inputFocus,...)
        if not probeRunning then return callOriginal(self,dt,inputCFrame,inputFocus,...) end
        occlusionUpdates+=1
        stageRecord("Occlusion.Update","enter",string.format(
            "dt=%s cframe=%s focus=%s",cleanText(dt,50),cleanText(inputCFrame,160),cleanText(inputFocus,160)
        ))
        local results=packCall(callOriginal,self,dt,inputCFrame,inputFocus,...)
        local outputCFrame=results[2]
        local outputFocus=results[3]
        if typeof(inputCFrame)=="CFrame" and typeof(outputCFrame)=="CFrame" then
            local positionDelta=cframeDifference(inputCFrame,outputCFrame)
            local focusDelta=typeof(inputFocus)=="CFrame" and typeof(outputFocus)=="CFrame"
                and (inputFocus.Position-outputFocus.Position).Magnitude or 0
            occlusionSamples+=1
            occlusionPositionDeltaSum+=positionDelta or 0
            occlusionPositionDeltaMax=math.max(occlusionPositionDeltaMax,positionDelta or 0)
            occlusionFocusDeltaSum+=focusDelta
            occlusionFocusDeltaMax=math.max(occlusionFocusDeltaMax,focusDelta)
        end
        local ctx=currentContext
        if ctx then ctx.occlusionCFrame=outputCFrame; ctx.occlusionFocus=outputFocus end
        stageRecord("Occlusion.Update","exit",string.format(
            "ok=%s cframe=%s focus=%s",tostring(results[1]),cleanText(outputCFrame,160),cleanText(outputFocus,160)
        ))
        return returnPacked(results)
    end
end

local function installTargetHooks()
    local specs={
        {"CameraModule.Update",cameraModuleUpdateFactory},
        {"Controller.Update",controllerUpdateFactory},
        {"Controller.UpdateMouseBehavior",updateMouseBehaviorFactory},
        {"Controller.SetIsMouseLocked",setLockFactory},
        {"Controller.SetMouseLockOffset",setOffsetFactory},
        {"Controller.GetIsMouseLocked",getterFactory("lock")},
        {"Controller.GetMouseLockOffset",getterFactory("offset")},
        {"Controller.GetSubjectPosition",subjectFactory},
        {"Controller.CalculateNewLookCFrame",lookFactory},
        {"Controller.GetCameraLookVector",cameraLookFactory},
        {"Occlusion.Update",occlusionFactory},
    }
    for _,spec in ipairs(specs) do
        local ok,detail=installHook(spec[1],spec[2])
        if not ok then addEvidence("HOOK",spec[1].." rejected="..detail) end
    end
end

local function resetCounters()
    probeFrames=0
    probeDuration=0
    traceFrames=0
    traceErrors=0
    postSampleErrors=0
    traceLines={}
    traceLinesDropped=0
    sequenceCounts={}
    cameraModuleUpdates=0
    controllerUpdates=0
    controllerUpdateErrors=0
    occlusionUpdates=0
    updateMouseBehaviorCalls=0
    updateMouseBehaviorInside=0
    updateMouseBehaviorOutside=0
    setIsMouseLockedCalls=0
    setIsMouseLockedInside=0
    setIsMouseLockedOutside=0
    setMouseLockOffsetCalls=0
    setMouseLockOffsetInside=0
    setMouseLockOffsetOutside=0
    getIsMouseLockedCalls=0
    getIsMouseLockedInside=0
    getMouseLockOffsetCalls=0
    getMouseLockOffsetInside=0
    getSubjectPositionCalls=0
    getSubjectPositionInside=0
    calculateLookCalls=0
    calculateLookInside=0
    getCameraLookCalls=0
    getCameraLookInside=0
    primaryPartChangedDuringUpdate=0
    primaryPartYawChangedDuringUpdate=0
    primaryPartPositionChangedDuringUpdate=0
    primaryPartYawDeltaSum=0
    primaryPartYawDeltaMax=0
    primaryPartPositionDeltaSum=0
    primaryPartPositionDeltaMax=0
    compositionSamples=0
    compositionMatches=0
    compositionMismatches=0
    compositionResidualSum=0
    compositionResidualMax=0
    compositionLastResidual=nil
    compositionLastActualShift=nil
    compositionLastPredictedShift=nil
    compositionLastSubjectPosition=nil
    compositionLastControllerFocus=nil
    compositionLookCandidateCount=0
    occlusionSamples=0
    occlusionPositionDeltaSum=0
    occlusionPositionDeltaMax=0
    occlusionFocusDeltaSum=0
    occlusionFocusDeltaMax=0
    postCameraSamples=0
    postCameraExternalChanges=0
    postCameraPositionDeltaSum=0
    postCameraPositionDeltaMax=0
    postCameraFocusDeltaSum=0
    postCameraFocusDeltaMax=0
    stationaryFrames=0
    movingFrames=0
    rootProjectionFrames=0
    rootScreenStepSum=0
    rootScreenStepMax=0
    previousRootScreen=nil
    lastModuleExit=nil
    lastInsideLockArg=nil
    lastOutsideLockArg=nil
    lastInsideOffsetArg=nil
    lastOutsideOffsetArg=nil
    lastGetLockReturn=nil
    lastGetOffsetReturn=nil
    lastMouseBehaviorBefore=nil
    lastMouseBehaviorAfter=nil
    lastRotationTypeBefore=nil
    lastRotationTypeAfter=nil
    lastControllerUpdateCFrame=nil
    lastControllerUpdateFocus=nil
    lastFinalCameraCFrame=nil
    lastFinalCameraFocus=nil
end

local function startProbe()
    resetCounters()
    probeRunning=true
    probeStartedAt=os.clock()
    addEvidence("PROBE","targeted composition trace started")
end

local function stopProbe()
    if probeRunning then
        probeRunning=false
        probeDuration=os.clock()-probeStartedAt
        addEvidence("PROBE","stopped duration="..tostring(round(probeDuration,3)))
    end
end

local function postCameraSample()
    if not probeRunning then return end
    local ok,err=pcall(function()
        local camera=workspace.CurrentCamera
        if not camera then return end
        postCameraSamples+=1
        if lastModuleExit and typeof(lastModuleExit.cameraCFrame)=="CFrame" then
            local positionDelta=cframeDifference(camera.CFrame,lastModuleExit.cameraCFrame)
            local focusDelta=typeof(lastModuleExit.cameraFocus)=="CFrame"
                and (camera.Focus.Position-lastModuleExit.cameraFocus.Position).Magnitude or 0
            postCameraPositionDeltaSum+=positionDelta or 0
            postCameraPositionDeltaMax=math.max(postCameraPositionDeltaMax,positionDelta or 0)
            postCameraFocusDeltaSum+=focusDelta
            postCameraFocusDeltaMax=math.max(postCameraFocusDeltaMax,focusDelta)
            if (positionDelta or 0)>1e-5 or focusDelta>1e-5 then postCameraExternalChanges+=1 end
        end
        local character=player.Character
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        local root=character and character:FindFirstChild("HumanoidRootPart")
        if humanoid then
            if humanoid.MoveDirection.Magnitude>0.05 then movingFrames+=1 else stationaryFrames+=1 end
        end
        if root then
            local point,onScreen=camera:WorldToViewportPoint(root.Position)
            if onScreen then
                rootProjectionFrames+=1
                local current=Vector2.new(point.X,point.Y)
                if previousRootScreen then
                    local step=(current-previousRootScreen).Magnitude
                    rootScreenStepSum+=step
                    rootScreenStepMax=math.max(rootScreenStepMax,step)
                end
                previousRootScreen=current
            end
        end
    end)
    if not ok then
        postSampleErrors+=1
        if postSampleErrors<=8 then addEvidence("POST-ERROR",err) end
    end
end

local function v604Safe()
    if type(baseDiagnostics)~="function" then return {} end
    local ok,value=pcall(baseDiagnostics)
    return ok and type(value)=="table" and value or {}
end

local function sequenceSummary()
    local rows={}
    for sequence,count in pairs(sequenceCounts) do rows[#rows+1]={sequence=sequence,count=count} end
    table.sort(rows,function(a,b) return a.count>b.count end)
    local lines={}
    for index,row in ipairs(rows) do
        if index>8 then break end
        lines[#lines+1]=tostring(row.count).."x{"..row.sequence.."}"
    end
    return #lines>0 and table.concat(lines," | ") or "none"
end

local function targetSummary()
    local lines={}
    for _,id in ipairs({
        "CameraModule.Update","Controller.Update","Controller.UpdateMouseBehavior",
        "Controller.SetIsMouseLocked","Controller.GetIsMouseLocked",
        "Controller.SetMouseLockOffset","Controller.GetMouseLockOffset",
        "Controller.GetSubjectPosition","Controller.CalculateNewLookCFrame",
        "Controller.GetCameraLookVector","Occlusion.Update",
        "MouseLock.GetIsMouseLocked","MouseLock.GetMouseLockOffset",
        "CameraModule.OnMouseLockToggled",
    }) do
        local detail=targetEvidence[id]
        lines[#lines+1]=detail and (id.."@"..detail.origin) or (id.."@missing")
    end
    return table.concat(lines," | ")
end

local function determineDivergence(base,shift,nativeLock,controllerNow)
    local matchRatio=compositionSamples>0 and compositionMatches/compositionSamples or 0
    local nativeReportedUnlocked=nativeLock.methodLocked==false
        or (nativeLock.methodLocked==nil and nativeLock.isMouseLocked==false)
    if compositionSamples==0 then
        return "unproven-controller-composition-not-captured"
    end
    if getMouseLockOffsetInside==0 then
        return "mouse-lock-offset-not-consumed-inside-controller-update"
    end
    if matchRatio<0.90 then
        return "camera-relative-offset-does-not-match-controller-focus-output"
    end
    if postCameraExternalChanges>math.max(2,postCameraSamples*0.10) then
        return "post-CameraModule-transform-modifies-final-camera"
    end
    if nativeLock.found and nativeReportedUnlocked
        and controllerNow.inMouseLockedMode==true then
        return "first-static-divergence-native-MouseLockController-unlocked-while-camera-controller-is-forced-locked"
    end
    if tostring(UserInputService.PreferredInput)==tostring(Enum.PreferredInput.Touch) then
        return "first-platform-divergence-PreferredInput-Touch-native-mouse-lock-activation-unavailable-downstream-composition-already-present"
    end
    if shift.found and shift.value==true and primaryPartYawChangedDuringUpdate>0 then
        return "Evade-ShiftLockEnabled-block-and-camera-composition-both-executed-no-missing-stage-proved"
    end
    return "no-first-divergence-proved-inside-CameraModule-composition"
end

getgenv().PCV606Diagnostics=function()
    refreshObjects()
    local base=v604Safe()
    local shift=snapshotShiftState()
    local nativeLock=mouseLockControllerState()
    local controllerNow=controllerState()
    local camera=workspace.CurrentCamera
    local scripts=player:FindFirstChild("PlayerScripts")
    local divergence=determineDivergence(base,shift,nativeLock,controllerNow)
    experimentEligible=false
    experimentEligibilityReason="blocked: diagnostic evidence does not prove a safe missing native transform; "..divergence
    local moduleDetail=targetEvidence["CameraModule.Update"] or {}
    local controllerDetail=targetEvidence["Controller.Update"] or {}
    local result={
        version="V606-MouseLockCompositionTrace",
        bridgeMode=getgenv().PCInputBridgeMode,
        probePurpose="reconstruct-executed-CameraModule-mouse-lock-composition-chain",
        probeRunning=probeRunning,
        probeFrames=probeFrames,
        probeDuration=round(probeRunning and (os.clock()-probeStartedAt) or probeDuration,3),
        traceFrames=traceFrames,
        traceErrors=traceErrors,
        postSampleErrors=postSampleErrors,
        targetDiscoveryStatus=targetDiscoveryStatus,
        targetMethodsFound=targetMethodsFound,
        targetMethodsMissing=table.concat(targetMethodsMissing," | "),
        targetSummary=targetSummary(),
        cameraModuleUpdateOrigin=moduleDetail.origin,
        cameraModuleUpdateConstants=moduleDetail.constants,
        cameraModuleUpdateUpvalues=moduleDetail.upvalues,
        cameraModuleUpdateProtos=moduleDetail.protos,
        controllerUpdateOrigin=controllerDetail.origin,
        controllerUpdateConstants=controllerDetail.constants,
        controllerUpdateUpvalues=controllerDetail.upvalues,
        sequenceSummary=sequenceSummary(),
        cameraModuleUpdates=cameraModuleUpdates,
        controllerUpdates=controllerUpdates,
        controllerUpdateErrors=controllerUpdateErrors,
        occlusionUpdates=occlusionUpdates,
        updateMouseBehaviorCalls=updateMouseBehaviorCalls,
        updateMouseBehaviorInside=updateMouseBehaviorInside,
        updateMouseBehaviorOutside=updateMouseBehaviorOutside,
        setIsMouseLockedCalls=setIsMouseLockedCalls,
        setIsMouseLockedInside=setIsMouseLockedInside,
        setIsMouseLockedOutside=setIsMouseLockedOutside,
        setMouseLockOffsetCalls=setMouseLockOffsetCalls,
        setMouseLockOffsetInside=setMouseLockOffsetInside,
        setMouseLockOffsetOutside=setMouseLockOffsetOutside,
        getIsMouseLockedCalls=getIsMouseLockedCalls,
        getIsMouseLockedInside=getIsMouseLockedInside,
        getMouseLockOffsetCalls=getMouseLockOffsetCalls,
        getMouseLockOffsetInside=getMouseLockOffsetInside,
        getSubjectPositionCalls=getSubjectPositionCalls,
        getSubjectPositionInside=getSubjectPositionInside,
        calculateLookCalls=calculateLookCalls,
        calculateLookInside=calculateLookInside,
        getCameraLookCalls=getCameraLookCalls,
        getCameraLookInside=getCameraLookInside,
        lastInsideLockArg=lastInsideLockArg,
        lastOutsideLockArg=lastOutsideLockArg,
        lastInsideOffsetArg=lastInsideOffsetArg,
        lastOutsideOffsetArg=lastOutsideOffsetArg,
        lastGetLockReturn=lastGetLockReturn,
        lastGetOffsetReturn=lastGetOffsetReturn,
        lastMouseBehaviorBefore=lastMouseBehaviorBefore,
        lastMouseBehaviorAfter=lastMouseBehaviorAfter,
        lastRotationTypeBefore=lastRotationTypeBefore,
        lastRotationTypeAfter=lastRotationTypeAfter,
        lastControllerUpdateCFrame=lastControllerUpdateCFrame,
        lastControllerUpdateFocus=lastControllerUpdateFocus,
        lastFinalCameraCFrame=lastFinalCameraCFrame,
        lastFinalCameraFocus=lastFinalCameraFocus,
        shiftLockValueFound=shift.found,
        shiftLockValueClass=shift.class,
        shiftLockValue=shift.value,
        playerScriptsPath=cleanText(scripts,100),
        preferredInput=tostring(UserInputService.PreferredInput),
        mouseBehavior=tostring(readMouseBehavior()),
        rotationType=tostring(readRotationType()),
        controllerInMouseLockedMode=controllerNow.inMouseLockedMode,
        controllerMouseLockOffset=controllerNow.mouseLockOffset,
        controllerInFirstPerson=controllerNow.inFirstPerson,
        controllerCameraMovementMode=controllerNow.cameraMovementMode,
        controllerIsFollowCamera=controllerNow.isFollowCamera,
        nativeMouseLockControllerFound=nativeLock.found,
        nativeMouseLockControllerEnabled=nativeLock.enabled,
        nativeMouseLockControllerState=nativeLock.isMouseLocked,
        nativeMouseLockMethodLocked=nativeLock.methodLocked,
        nativeMouseLockMethodOffset=nativeLock.methodOffset,
        humanoidAutoRotate=shift.autoRotate,
        humanoidCameraOffset=shift.cameraOffset,
        cameraType=camera and tostring(camera.CameraType) or "none",
        cameraSubject=camera and cleanText(camera.CameraSubject,100) or "none",
        characterPrimaryPart=cleanText(shift.primary,100),
        primaryPartChangedDuringUpdate=primaryPartChangedDuringUpdate,
        primaryPartYawChangedDuringUpdate=primaryPartYawChangedDuringUpdate,
        primaryPartPositionChangedDuringUpdate=primaryPartPositionChangedDuringUpdate,
        primaryPartYawDeltaMean=cameraModuleUpdates>0 and round(primaryPartYawDeltaSum/cameraModuleUpdates,6) or nil,
        primaryPartYawDeltaMax=round(primaryPartYawDeltaMax,6),
        primaryPartPositionDeltaMean=cameraModuleUpdates>0 and round(primaryPartPositionDeltaSum/cameraModuleUpdates,8) or nil,
        primaryPartPositionDeltaMax=round(primaryPartPositionDeltaMax,8),
        compositionSamples=compositionSamples,
        compositionMatches=compositionMatches,
        compositionMismatches=compositionMismatches,
        compositionMatchRatio=compositionSamples>0 and round(compositionMatches/compositionSamples,6) or nil,
        compositionResidualMean=compositionSamples>0 and round(compositionResidualSum/compositionSamples,7) or nil,
        compositionResidualMax=round(compositionResidualMax,7),
        compositionLastResidual=compositionLastResidual and round(compositionLastResidual,7) or nil,
        compositionLastActualFocusShift=compositionLastActualShift,
        compositionLastPredictedMouseLockShift=compositionLastPredictedShift,
        compositionLastSubjectPosition=compositionLastSubjectPosition,
        compositionLastControllerFocus=compositionLastControllerFocus,
        compositionLookCandidateCount=compositionLookCandidateCount,
        occlusionSamples=occlusionSamples,
        occlusionPositionDeltaMean=occlusionSamples>0 and round(occlusionPositionDeltaSum/occlusionSamples,7) or nil,
        occlusionPositionDeltaMax=round(occlusionPositionDeltaMax,7),
        occlusionFocusDeltaMean=occlusionSamples>0 and round(occlusionFocusDeltaSum/occlusionSamples,7) or nil,
        occlusionFocusDeltaMax=round(occlusionFocusDeltaMax,7),
        postCameraSamples=postCameraSamples,
        postCameraExternalChanges=postCameraExternalChanges,
        postCameraPositionDeltaMean=postCameraSamples>0 and round(postCameraPositionDeltaSum/postCameraSamples,7) or nil,
        postCameraPositionDeltaMax=round(postCameraPositionDeltaMax,7),
        postCameraFocusDeltaMean=postCameraSamples>0 and round(postCameraFocusDeltaSum/postCameraSamples,7) or nil,
        postCameraFocusDeltaMax=round(postCameraFocusDeltaMax,7),
        stationaryFrames=stationaryFrames,
        movingFrames=movingFrames,
        rootProjectionFrames=rootProjectionFrames,
        rootScreenStepMean=rootProjectionFrames>1 and round(rootScreenStepSum/(rootProjectionFrames-1),6) or nil,
        rootScreenStepMax=round(rootScreenStepMax,6),
        firstDivergenceCandidate=divergence,
        dynamicChainProven=controllerUpdates>0 and getSubjectPositionInside>0
            and getMouseLockOffsetInside>0 and calculateLookInside>0,
        compositionStageProven=compositionSamples>0 and compositionMatches>0,
        validationReady=traceFrames>=30 and traceErrors==0 and compositionSamples>0,
        experimentEligible=experimentEligible,
        experimentEligibilityReason=experimentEligibilityReason,
        experimentEnabled=experimentEnabled,
        experimentAttempts=experimentAttempts,
        experimentRejected=experimentRejected,
        relayEnabled=base.relayEnabled,
        relayValidationReady=base.relayValidationReady,
        ownershipGateProven=base.ownershipGateProven,
        touchRoleConflicts=base.touchRoleConflicts,
        joystickMouseCrossovers=base.joystickMouseCrossovers,
        relayErrors=base.relayErrors,
        callbackErrors=base.callbackErrors,
        traceLines=#traceLines,
        traceLinesDropped=traceLinesDropped,
        evidenceLines=#evidence,
        evidenceDropped=evidenceDropped,
        preservesV604Ownership=true,
        usesProcessedAsOwnershipGate=false,
        usesHalfScreenGate=false,
        usesSyntheticUserInputObject=false,
        usesFireSignal=false,
        addsVirtualInput=false,
        callsUpdateMouseBehavior=false,
        writesCameraCFrame=false,
        writesRootPartCFrame=false,
        forcesAutoRotate=false,
        changesSensitivity=false,
        changesGain=false,
        changesPhysics=false,
        appliesScreenSpaceCorrection=false,
        fallbackV500Preserved=true,
    }
    return result
end

local REPORT_KEYS={
    "version","bridgeMode","probePurpose","probeRunning","probeFrames","probeDuration",
    "traceFrames","traceErrors","postSampleErrors","targetDiscoveryStatus","targetMethodsFound",
    "targetMethodsMissing","targetSummary","cameraModuleUpdateOrigin","cameraModuleUpdateConstants",
    "cameraModuleUpdateUpvalues","cameraModuleUpdateProtos","controllerUpdateOrigin",
    "controllerUpdateConstants","controllerUpdateUpvalues","sequenceSummary",
    "cameraModuleUpdates","controllerUpdates","controllerUpdateErrors","occlusionUpdates",
    "updateMouseBehaviorCalls","updateMouseBehaviorInside","updateMouseBehaviorOutside",
    "setIsMouseLockedCalls","setIsMouseLockedInside","setIsMouseLockedOutside",
    "setMouseLockOffsetCalls","setMouseLockOffsetInside","setMouseLockOffsetOutside",
    "getIsMouseLockedCalls","getIsMouseLockedInside","getMouseLockOffsetCalls",
    "getMouseLockOffsetInside","getSubjectPositionCalls","getSubjectPositionInside",
    "calculateLookCalls","calculateLookInside","getCameraLookCalls","getCameraLookInside",
    "lastInsideLockArg","lastOutsideLockArg","lastInsideOffsetArg","lastOutsideOffsetArg",
    "lastGetLockReturn","lastGetOffsetReturn","lastMouseBehaviorBefore","lastMouseBehaviorAfter",
    "lastRotationTypeBefore","lastRotationTypeAfter","lastControllerUpdateCFrame",
    "lastControllerUpdateFocus","lastFinalCameraCFrame","lastFinalCameraFocus",
    "shiftLockValueFound","shiftLockValueClass","shiftLockValue","playerScriptsPath",
    "preferredInput","mouseBehavior","rotationType","controllerInMouseLockedMode",
    "controllerMouseLockOffset","controllerInFirstPerson","controllerCameraMovementMode",
    "controllerIsFollowCamera","nativeMouseLockControllerFound","nativeMouseLockControllerEnabled",
    "nativeMouseLockControllerState","nativeMouseLockMethodLocked","nativeMouseLockMethodOffset",
    "humanoidAutoRotate","humanoidCameraOffset","cameraType","cameraSubject","characterPrimaryPart",
    "primaryPartChangedDuringUpdate","primaryPartYawChangedDuringUpdate",
    "primaryPartPositionChangedDuringUpdate","primaryPartYawDeltaMean","primaryPartYawDeltaMax",
    "primaryPartPositionDeltaMean","primaryPartPositionDeltaMax","compositionSamples",
    "compositionMatches","compositionMismatches","compositionMatchRatio",
    "compositionResidualMean","compositionResidualMax","compositionLastResidual",
    "compositionLastActualFocusShift","compositionLastPredictedMouseLockShift",
    "compositionLastSubjectPosition","compositionLastControllerFocus",
    "compositionLookCandidateCount","occlusionSamples","occlusionPositionDeltaMean",
    "occlusionPositionDeltaMax","occlusionFocusDeltaMean","occlusionFocusDeltaMax",
    "postCameraSamples","postCameraExternalChanges","postCameraPositionDeltaMean",
    "postCameraPositionDeltaMax","postCameraFocusDeltaMean","postCameraFocusDeltaMax",
    "stationaryFrames","movingFrames","rootProjectionFrames","rootScreenStepMean",
    "rootScreenStepMax","firstDivergenceCandidate","dynamicChainProven","compositionStageProven",
    "validationReady","experimentEligible","experimentEligibilityReason","experimentEnabled",
    "experimentAttempts","experimentRejected","relayEnabled","relayValidationReady",
    "ownershipGateProven","touchRoleConflicts","joystickMouseCrossovers","relayErrors",
    "callbackErrors","traceLines","traceLinesDropped","evidenceLines","evidenceDropped",
    "preservesV604Ownership","usesProcessedAsOwnershipGate","usesHalfScreenGate",
    "usesSyntheticUserInputObject","usesFireSignal","addsVirtualInput","callsUpdateMouseBehavior",
    "writesCameraCFrame","writesRootPartCFrame","forcesAutoRotate","changesSensitivity",
    "changesGain","changesPhysics","appliesScreenSpaceCorrection","fallbackV500Preserved",
}

getgenv().PCV606Report=function(includeEvidence)
    local diagnostics=getgenv().PCV606Diagnostics()
    local lines={"=== PC MOVEMENT V606 REPORT ==="}
    for _,key in ipairs(REPORT_KEYS) do lines[#lines+1]=key.." = "..tostring(diagnostics[key]) end
    if includeEvidence~=false then
        lines[#lines+1]=""
        lines[#lines+1]="=== PC MOVEMENT V606 TARGET EVIDENCE ==="
        for _,id in ipairs({
            "CameraModule.Update","Controller.Update","Controller.UpdateMouseBehavior",
            "Controller.SetIsMouseLocked","Controller.GetIsMouseLocked",
            "Controller.SetMouseLockOffset","Controller.GetMouseLockOffset",
            "Controller.GetSubjectPosition","Controller.CalculateNewLookCFrame",
            "Controller.GetCameraLookVector","Occlusion.Update",
            "MouseLock.GetIsMouseLocked","MouseLock.GetMouseLockOffset",
            "CameraModule.OnMouseLockToggled",
        }) do
            local detail=targetEvidence[id]
            if detail then
                lines[#lines+1]=id.." origin="..detail.origin
                lines[#lines+1]="  constants={"..detail.constants.."}"
                lines[#lines+1]="  upvalues={"..detail.upvalues.."}"
                lines[#lines+1]="  protos={"..detail.protos.."}"
            else
                lines[#lines+1]=id.." = missing"
            end
        end
        lines[#lines+1]=""
        lines[#lines+1]="=== PC MOVEMENT V606 ORDERED TRACE ==="
        for _,line in ipairs(traceLines) do lines[#lines+1]=line end
        lines[#lines+1]=""
        lines[#lines+1]="=== PC MOVEMENT V606 EVIDENCE ==="
        for _,line in ipairs(evidence) do lines[#lines+1]=line end
        if type(baseReport)=="function" then
            local ok,baseText=pcall(baseReport,false)
            if ok then lines[#lines+1]=""; lines[#lines+1]=baseText end
        end
    end
    return table.concat(lines,"\n")
end

local function setStatus(text,color)
    if statusLabel then
        statusLabel.Text=text
        if color then statusLabel.TextColor3=color end
    end
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

local function makeButton(parent,text,color,order)
    local button=Instance.new("TextButton")
    button.LayoutOrder=order
    button.Size=UDim2.new(1,0,0,39)
    button.BackgroundColor3=color
    button.BorderSizePixel=0
    button.Text=text
    button.TextColor3=Color3.fromRGB(255,255,255)
    button.TextSize=13
    button.TextWrapped=true
    button.Font=Enum.Font.GothamBold
    button.Parent=parent
    local corner=Instance.new("UICorner")
    corner.CornerRadius=UDim.new(0,9)
    corner.Parent=button
    return button
end

local function refreshButtons()
    if startButton then
        startButton.Text=probeRunning and "PARAR TRACE" or "INICIAR TRACE"
        startButton.BackgroundColor3=probeRunning and Color3.fromRGB(245,158,11) or Color3.fromRGB(34,197,94)
    end
    if relayButton then
        local d=v604Safe()
        relayButton.Text=d.relayEnabled and "RELAY V604: LIGADO" or "RELAY V604: DESLIGADO"
        relayButton.BackgroundColor3=d.relayEnabled and Color3.fromRGB(124,58,237) or Color3.fromRGB(71,85,105)
    end
    if experimentButton then
        experimentButton.Text="EXPERIMENTO NATIVO: BLOQUEADO"
        experimentButton.BackgroundColor3=Color3.fromRGB(55,65,81)
    end
end

local function createPanel()
    local parent=CoreGui
    pcall(function() if gethui then parent=gethui() end end)
    if not parent then return end
    local old=parent:FindFirstChild(UI_NAME)
    if old then old:Destroy() end
    local gui=Instance.new("ScreenGui")
    gui.Name=UI_NAME
    gui.ResetOnSpawn=false
    gui.DisplayOrder=999999
    gui.Parent=parent
    screenGui=gui

    local panel=Instance.new("Frame")
    panel.Size=UDim2.fromOffset(314,385)
    panel.Position=UDim2.new(1,-326,0.5,-192)
    panel.BackgroundColor3=Color3.fromRGB(10,15,27)
    panel.BackgroundTransparency=0.04
    panel.BorderSizePixel=0
    panel.Active=true
    panel.Draggable=true
    panel.Parent=gui
    local corner=Instance.new("UICorner")
    corner.CornerRadius=UDim.new(0,14)
    corner.Parent=panel
    local stroke=Instance.new("UIStroke")
    stroke.Color=Color3.fromRGB(167,139,250)
    stroke.Thickness=1.5
    stroke.Parent=panel

    local title=Instance.new("TextLabel")
    title.Size=UDim2.new(1,-48,0,34)
    title.Position=UDim2.fromOffset(13,7)
    title.BackgroundTransparency=1
    title.Text="V606 • CAMERA CHAIN TRACE"
    title.TextColor3=Color3.fromRGB(196,181,253)
    title.TextSize=15
    title.Font=Enum.Font.GothamBold
    title.TextXAlignment=Enum.TextXAlignment.Left
    title.Parent=panel

    local collapse=Instance.new("TextButton")
    collapse.Size=UDim2.fromOffset(30,30)
    collapse.Position=UDim2.new(1,-38,0,7)
    collapse.BackgroundColor3=Color3.fromRGB(31,41,55)
    collapse.BorderSizePixel=0
    collapse.Text="–"
    collapse.TextColor3=Color3.new(1,1,1)
    collapse.TextSize=20
    collapse.Font=Enum.Font.GothamBold
    collapse.Parent=panel
    local collapseCorner=Instance.new("UICorner")
    collapseCorner.CornerRadius=UDim.new(0,8)
    collapseCorner.Parent=collapse

    local body=Instance.new("Frame")
    body.Size=UDim2.new(1,-24,1,-48)
    body.Position=UDim2.fromOffset(12,42)
    body.BackgroundTransparency=1
    body.Parent=panel
    local layout=Instance.new("UIListLayout")
    layout.Padding=UDim.new(0,6)
    layout.SortOrder=Enum.SortOrder.LayoutOrder
    layout.Parent=body

    local instructions=Instance.new("TextLabel")
    instructions.LayoutOrder=0
    instructions.Size=UDim2.new(1,0,0,66)
    instructions.BackgroundColor3=Color3.fromRGB(22,28,45)
    instructions.BorderSizePixel=0
    instructions.Text="1) Prove joystick+câmera e ligue o relay\n2) INICIE; gire parado e depois andando\n3) Faça reversão rápida, 180°, pitch e zoom\n4) PARE e COPIE antes de sair do Roblox"
    instructions.TextColor3=Color3.fromRGB(226,232,240)
    instructions.TextSize=11
    instructions.TextWrapped=true
    instructions.TextXAlignment=Enum.TextXAlignment.Left
    instructions.Font=Enum.Font.Gotham
    instructions.Parent=body
    local instructionCorner=Instance.new("UICorner")
    instructionCorner.CornerRadius=UDim.new(0,8)
    instructionCorner.Parent=instructions

    startButton=makeButton(body,"INICIAR TRACE",Color3.fromRGB(34,197,94),1)
    relayButton=makeButton(body,"RELAY V604: DESLIGADO",Color3.fromRGB(71,85,105),2)
    experimentButton=makeButton(body,"EXPERIMENTO NATIVO: BLOQUEADO",Color3.fromRGB(55,65,81),3)
    local emergency=makeButton(body,"EMERGÊNCIA • RELAY OFF / V500",Color3.fromRGB(190,24,93),4)
    local copy=makeButton(body,"COPIAR REPORT COMPLETO",Color3.fromRGB(2,132,199),5)
    statusLabel=Instance.new("TextLabel")
    statusLabel.LayoutOrder=6
    statusLabel.Size=UDim2.new(1,0,0,28)
    statusLabel.BackgroundTransparency=1
    statusLabel.Text="Pronto. Nenhuma mutação experimental ativa."
    statusLabel.TextColor3=Color3.fromRGB(148,163,184)
    statusLabel.TextSize=10
    statusLabel.TextWrapped=true
    statusLabel.Font=Enum.Font.Gotham
    statusLabel.Parent=body

    uiConnections[#uiConnections+1]=startButton.Activated:Connect(function()
        if probeRunning then
            stopProbe()
            setStatus("Trace parado. Agora copie o relatório.",Color3.fromRGB(250,204,21))
        else
            startProbe()
            setStatus("Gravando a cadeia… gire parado e andando.",Color3.fromRGB(74,222,128))
        end
        refreshButtons()
    end)
    uiConnections[#uiConnections+1]=relayButton.Activated:Connect(function()
        local d=v604Safe()
        local want=not d.relayEnabled
        if type(baseSetRelay)~="function" then
            setStatus("Relay indisponível; V500 continua ativo.",Color3.fromRGB(251,113,133))
            return
        end
        local ok,result=pcall(baseSetRelay,want)
        if not ok or result==false then
            setStatus("Relay recusado: faça joystick+câmera juntos primeiro.",Color3.fromRGB(250,204,21))
        else
            setStatus(want and "Relay V604 ligado." or "Relay desligado; V500 ativo.",want and Color3.fromRGB(196,181,253) or Color3.fromRGB(148,163,184))
        end
        refreshButtons()
    end)
    uiConnections[#uiConnections+1]=experimentButton.Activated:Connect(function()
        experimentAttempts+=1
        experimentRejected+=1
        experimentEnabled=false
        setStatus("Bloqueado: ainda não há transformação nativa segura provada.",Color3.fromRGB(250,204,21))
        addEvidence("EXPERIMENT","rejected; observational-only because no safe missing stage is proved")
    end)
    uiConnections[#uiConnections+1]=emergency.Activated:Connect(function()
        stopProbe()
        experimentEnabled=false
        if type(baseSetRelay)=="function" then pcall(baseSetRelay,false) end
        setStatus("Emergência: relay OFF, V500 preservado.",Color3.fromRGB(251,113,133))
        refreshButtons()
    end)
    uiConnections[#uiConnections+1]=copy.Activated:Connect(function()
        stopProbe()
        refreshButtons()
        local ok=copyToClipboard(getgenv().PCV606Report(true))
        setStatus(ok and "REPORT COPIADO. Agora pode sair e colar." or "Clipboard indisponível no executor.",ok and Color3.fromRGB(74,222,128) or Color3.fromRGB(251,113,133))
    end)
    local expanded=true
    uiConnections[#uiConnections+1]=collapse.Activated:Connect(function()
        expanded=not expanded
        body.Visible=expanded
        panel.Size=expanded and UDim2.fromOffset(314,385) or UDim2.fromOffset(314,45)
        collapse.Text=expanded and "–" or "+"
    end)
end

RunService:BindToRenderStep(POST_BIND,Enum.RenderPriority.Camera.Value+20,postCameraSample)

local discoverOk,discoverError=pcall(discoverTargets)
if not discoverOk then
    targetDiscoveryStatus="error:"..cleanText(discoverError,180)
    addEvidence("DISCOVERY",targetDiscoveryStatus)
else
    local hookOk,hookError=pcall(installTargetHooks)
    if not hookOk then addEvidence("HOOK","installation-error="..cleanText(hookError,180)) end
end
local uiOk,uiError=pcall(createPanel)
if not uiOk then addEvidence("UI","creation-error="..cleanText(uiError,180)) end

getgenv().PCV606Start=function()
    startProbe()
    refreshButtons()
    return true,"trace-started"
end

getgenv().PCV606Stop=function()
    stopProbe()
    refreshButtons()
    return getgenv().PCV606Report(false)
end

getgenv().PCV606EmergencyV500=function()
    stopProbe()
    experimentEnabled=false
    if type(baseSetRelay)=="function" then pcall(baseSetRelay,false) end
    refreshButtons()
    return true,"relay-disabled-v500-active"
end

local function restoreHooks()
    for index=#installedHooks,1,-1 do
        local hook=installedHooks[index]
        pcall(function() hookfunction(hook.target,hook.original) end)
    end
    installedHooks={}
end

getgenv().__PCMobileAimCleanup=function()
    probeRunning=false
    experimentEnabled=false
    pcall(function() RunService:UnbindFromRenderStep(POST_BIND) end)
    for _,connection in ipairs(uiConnections) do pcall(function() connection:Disconnect() end) end
    uiConnections={}
    if screenGui then pcall(function() screenGui:Destroy() end) end
    screenGui=nil
    restoreHooks()

    getgenv().PCV606Start=nil
    getgenv().PCV606Stop=nil
    getgenv().PCV606EmergencyV500=nil
    getgenv().PCV606Diagnostics=nil
    getgenv().PCV606Report=nil

    if baseCleanup then pcall(baseCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

addEvidence("READY","V606 targeted CameraModule/mouse-lock composition trace ready; experiment blocked")
refreshButtons()
warn("[V606] targeted CameraModule/mouse-lock composition trace ready | observational only | use mobile panel")
