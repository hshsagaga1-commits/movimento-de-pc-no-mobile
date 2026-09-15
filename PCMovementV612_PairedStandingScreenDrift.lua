local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")

local player=Players.LocalPlayer
local UI_NAME="PCMovementV612Panel"

--[[
    V612 / PAIRED STANDING SCREEN-DRIFT CONTROL

    V604-V611 are accepted evidence. No search is reopened. This probe repeats
    only the already-instrumented geometry reads inside two explicit windows:
      A) native Touch, character standing
      B) V604 OnMouseMoved(same real Touch), character standing.

    No camera, character, subject, focus, sensitivity or physics value is
    written. The relay is not labeled native PC MouseMovement.
]]

local v604Source=game:HttpGet(
    "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV604_MultitouchOwnershipProbe.lua?_cb="
    ..HttpService:GenerateGUID(false),true
)
-- V604's ownership algorithm and relay remain byte-identical on disk and at
-- every touch. V612 reuses the already-validated V604 proof so this controlled
-- standing test does not require a new joystick gesture in every fresh run.
-- Only the initial proof boolean/status are changed in the fetched copy; all
-- per-touch identity gates, bookkeeping, pinch handling and fail-open remain.
local proofInitCount,proofStatusCount
v604Source,proofInitCount=string.gsub(v604Source,"local ownershipGateProven=false",
    "local ownershipGateProven=true",1)
v604Source,proofStatusCount=string.gsub(v604Source,
    'local ownershipProofStatus="awaiting%-joystick%-and%-camera%-identities"',
    'local ownershipProofStatus="accepted-persisted-v604-runtime-proof"',1)
if proofInitCount~=1 or proofStatusCount~=1 then
    error("V612 refused: exact V604 persisted-proof initialization anchor missing")
end
local v604Chunk,v604Error=loadstring(v604Source)
if not v604Chunk then error(v604Error) end
v604Chunk()

local baseCleanup=getgenv().__PCMobileAimCleanup
local baseSetRelay=getgenv().PCV604SetRelayEnabled
local baseDiagnostics=getgenv().PCV604Diagnostics
local baseReport=getgenv().PCV604Report

getgenv().PCMovementVersion="V612-PairedStandingScreenDrift"
getgenv().PCInputBridgeMode="v612-paired-standing-touch-vs-v604-relay"

local cameras=nil
local activeController=nil
local targets={}
local targetEvidence={}
local installedHooks={}
local hooksInstalledTotal=0
local hookInstallFailures=0
local hookRestoreOk=nil
local hookRestoreDetail="not-stopped"
local discoveryStatus="not-started"
local discoveryErrors={}
local horizontalClampMin=-math.pi*2
local horizontalClampMax=math.pi*2
local horizontalBoundsSource="fallback-V610-decompile"

-- Standing is intentionally conservative. Thresholds are observations only.
local STABILIZE_SECONDS=1.50
local STABLE_CONSECUTIVE_FRAMES=12
local MAX_LINEAR_VELOCITY=0.15       -- studs/s, full 3D AssemblyLinearVelocity
local MAX_WORLD_DELTA_FLOOR=0.004    -- studs between CameraModule.Update entries
local MAX_MOVE_DIRECTION=0.01
local MIN_APPLIED_YAW_DEG=0.05       -- avoids division by numerical near-zero yaw
local MIN_PHASE_SAMPLES=120
local MIN_BUCKET_SAMPLES=25
local MIN_SAMPLE_BALANCE=0.65

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

local currentFrame=nil
local currentCalc=nil
local frameSerial=0
local pendingWrites=nil
local screenGui=nil
local statusLabel=nil
local phaseAButton=nil
local phaseBButton=nil
local uiConnections={}
local stateAtStop=nil
local currentPhase="none"
local phaseState="idle"
local phaseStartedAt=0
local phaseStabilizeUntil=0
local stableConsecutive=0
local phaseLastPrimaryPosition=nil
local uiLastRefresh=0
local persistedOwnershipProofAccepted=true
local joystickCriterionAvailable=false
local cachedJoystickInactive=true
local cachedJoystickDetail="not-sampled"
local lastJoystickReadAt=0

local handlerCallsTouch=0
local handlerCallsMouseTouch=0
local nonzeroWritesTouch=0
local nonzeroWritesRelay=0
local calculateCalls=0
local firstCalculateCalls=0
local getCameraLookCallsInCalc=0
local getSubjectCalls=0
local getMouseLockOffsetCalls=0
local controllerUpdates=0
local cameraModuleUpdates=0
local controllerErrors=0
local frameCorrelationErrors=0
local subjectClassCounts={}
local lastCorrelatedFrame=""
local lastSubjectDetail=""
local lastGeometryDetail=""
local lastStandingDetail=""
local readJoystickStandingState
local refreshLiveStatus

local function newPending()
    return {
        totalNonzero=0,touchNonzero=0,relayNonzero=0,
        touchSum=Vector2.new(),relaySum=Vector2.new(),totalSum=Vector2.new(),
        firstAt=nil,lastAt=nil,
    }
end
pendingWrites=newPending()

local function newPhaseStats()
    return {
        frames=0,inputFrames=0,calcFrames=0,
        writeCount=0,writeXAbs=0,writeYAbs=0,
        maxWritesPerFrame=0,writeFirstAgeMsSum=0,writeLastAgeMsSum=0,writeAgeSamples=0,
        requestedCount=0,requestedXAbs=0,effectiveXAbs=0,actualEffectiveXAbs=0,
        effectiveRatioSum=0,effectiveRatioCount=0,
        clampFrames=0,clampAmountAbs=0,clampResidualSum=0,clampResidualMax=0,
        cameraYawAppliedAbsDeg=0,lookYawAppliedAbsDeg=0,
        subjectSamples=0,subjectPrimaryDistanceSum=0,subjectHeadDistanceSum=0,
        subjectCloserPrimary=0,subjectCloserHead=0,subjectEquidistant=0,
        offsetSamples=0,offsetMagnitudeSum=0,focusResidualSum=0,focusResidualMax=0,
        primaryScreenSamples=0,primaryScreenStepSum=0,primaryDriftYawDeg=0,
        headScreenSamples=0,headScreenStepSum=0,headDriftYawDeg=0,
        returnedPrimaryScreenSamples=0,returnedPrimaryScreenStepSum=0,returnedPrimaryDriftYawDeg=0,
        returnedHeadScreenSamples=0,returnedHeadScreenStepSum=0,returnedHeadDriftYawDeg=0,
        returnedStandingPrimarySamples=0,returnedStandingPrimaryStepSum=0,returnedStandingPrimaryYawDeg=0,
        returnedStandingHeadSamples=0,returnedStandingHeadStepSum=0,returnedStandingHeadYawDeg=0,
        standingPrimarySamples=0,standingPrimaryStepSum=0,standingPrimaryYawDeg=0,
        standingHeadSamples=0,standingHeadStepSum=0,standingHeadYawDeg=0,
        movingPrimarySamples=0,movingPrimaryStepSum=0,movingPrimaryYawDeg=0,
        controllerCameraDistanceSum=0,controllerCameraDistanceCount=0,
    }
end

local phaseStats={touch=newPhaseStats(),relay=newPhaseStats()}

local function newPairedStats()
    return {
        validStandingFrames=0,rejectedMovingFrames=0,rejectedWrongRouteFrames=0,
        rejectedLowYawFrames=0,rejectedProjectionFrames=0,stabilizationFrames=0,
        cameraYawAppliedAbsDeg=0,
        primaryDisplacementSum=0,headDisplacementSum=0,
        returnedPrimaryDisplacementSum=0,returnedHeadDisplacementSum=0,
        subjectPositionSum=Vector3.new(),subjectPositionCount=0,lastSubjectPosition=nil,
        subjectPrimaryDistances={},subjectHeadDistances={},offsetMagnitudes={},focusResiduals={},
        yawDegrees={},primaryRatios={},headRatios={},returnedPrimaryRatios={},returnedHeadRatios={},
        primaryDisplacements={},headDisplacements={},returnedPrimaryDisplacements={},returnedHeadDisplacements={},
        linearVelocities={},worldDeltas={},moveDirections={},samples={},
    }
end

local pairedStats={touch=newPairedStats(),relay=newPairedStats()}

local function cleanText(value,limit)
    local output=nil
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
    if #evidence>=160 then evidenceDropped+=1; return end
    evidence[#evidence+1]=string.format("[%03d][%s] %s",#evidence+1,section,cleanText(message,1800))
end

local function addTrace(message)
    if #traceLines>=210 then traceDropped+=1; return end
    traceLines[#traceLines+1]=cleanText(message,1800)
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
    local result=nil
    pcall(function() result=require(module) end)
    return type(result)=="table" and result or nil
end

local function locateObjects()
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
        if type(value)=="function" then return {fn=value,origin=origin.."."..name,depth=depth} end
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
        if #items>=90 then break end
        if type(value)=="string" or type(value)=="number" or type(value)=="boolean" then
            items[#items+1]=cleanText(value,90)
        end
    end
    return table.concat(items," | ")
end

local function upvalues(fn)
    local getter=(debug and debug.getupvalues) or getupvalues
    if type(getter)~="function" then return nil,"unavailable" end
    local ok,values=pcall(getter,fn)
    if not ok or type(values)~="table" then return nil,"error:"..cleanText(values,100) end
    return values,"ok"
end

local function upvaluesSummary(fn)
    local values,status=upvalues(fn)
    if type(values)~="table" then return status end
    local items={}
    for index,value in pairs(values) do
        if #items>=24 then break end
        local kind=typeof(value)
        items[#items+1]=tostring(index).."="..kind..((kind=="number" or kind=="Vector2" or kind=="Vector3") and ":"..cleanText(value,80) or "")
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
    targetEvidence[id]={origin=target.origin,constants=constantsSummary(target.fn),upvalues=upvaluesSummary(target.fn)}
    addEvidence("TARGET",id.." origin="..target.origin.." constants={"..targetEvidence[id].constants
        .."} upvalues={"..targetEvidence[id].upvalues.."}")
end

local function discoverFocusedChain()
    discoveryStatus="running"
    locateObjects()
    registerTarget("CameraModule.Update",cameras,"Update")
    registerTarget("Controller.Update",activeController,"Update")
    registerTarget("OnTouchChanged",activeController,"OnTouchChanged")
    registerTarget("OnMouseMoved",activeController,"OnMouseMoved")
    registerTarget("CalculateNewLookCFrame",activeController,"CalculateNewLookCFrame")
    registerTarget("GetCameraLookVector",activeController,"GetCameraLookVector")
    registerTarget("GetSubjectPosition",activeController,"GetSubjectPosition")
    registerTarget("GetMouseLockOffset",activeController,"GetMouseLockOffset")
    local calculate=targets["CalculateNewLookCFrame"]
    if calculate then
        local values,status=upvalues(calculate.fn)
        local negative=nil
        local positive=nil
        if type(values)=="table" then
            for _,value in pairs(values) do
                if type(value)=="number" and value<=-math.pi then
                    negative=negative and math.min(negative,value) or value
                elseif type(value)=="number" and value>=math.pi then
                    positive=positive and math.max(positive,value) or value
                end
            end
        end
        if negative and positive then
            horizontalClampMin=negative
            horizontalClampMax=positive
            horizontalBoundsSource="CalculateNewLookCFrame-upvalues:"..status
        end
    end
    addEvidence("CLAMP",string.format("horizontal bounds min=%.12f max=%.12f source=%s",
        horizontalClampMin,horizontalClampMax,horizontalBoundsSource))
    discoveryStatus=#discoveryErrors==0 and "complete" or "partial"
end

local function readRotate(controller)
    local value=nil
    if type(controller)=="table" then pcall(function() value=rawget(controller,"rotateInput") end) end
    return typeof(value)=="Vector2" and value or nil
end

local function yawFromLook(look)
    if typeof(look)~="Vector3" then return nil end
    local flat=Vector3.new(look.X,0,look.Z)
    if flat.Magnitude<1e-8 then return nil end
    return math.atan2(-flat.Unit.X,-flat.Unit.Z)
end

local function yawFromCFrame(cf)
    return typeof(cf)=="CFrame" and yawFromLook(cf.LookVector) or nil
end

local function wrapRadians(value)
    if type(value)~="number" then return nil end
    return (value+math.pi)%(math.pi*2)-math.pi
end

local function angleDifference(a,b)
    if type(a)~="number" or type(b)~="number" then return nil end
    return wrapRadians(a-b)
end

local function characterSnapshot()
    local character=player.Character
    local primary=character and character.PrimaryPart or nil
    local head=character and character:FindFirstChild("Head") or nil
    local humanoid=character and character:FindFirstChildOfClass("Humanoid") or nil
    return character,primary,head,humanoid
end

local function projectPart(camera,part)
    if not camera or not part then return nil,false end
    local point,onScreen=nil,false
    local ok=pcall(function() point,onScreen=camera:WorldToViewportPoint(part.Position) end)
    return ok and point or nil,ok and onScreen or false
end

-- Projects with a supplied CFrame without assigning it to CurrentCamera. This
-- lets the trace observe Controller.Update's returned geometry even on builds
-- where CameraModule applies that return after the wrapped function unwinds.
local function projectPositionWithCFrame(camera,cf,position)
    if not camera or typeof(cf)~="CFrame" or typeof(position)~="Vector3" then return nil,false end
    local viewport=camera.ViewportSize
    local fieldOfView=camera.FieldOfView
    if typeof(viewport)~="Vector2" or type(fieldOfView)~="number" or viewport.Y<=0 then return nil,false end
    local localPoint=cf:PointToObjectSpace(position)
    local depth=-localPoint.Z
    if depth<=1e-6 then return nil,false end
    local scale=viewport.Y/(2*math.tan(math.rad(fieldOfView)*0.5))
    local point=Vector3.new(viewport.X*0.5+localPoint.X*scale/depth,
        viewport.Y*0.5-localPoint.Y*scale/depth,depth)
    local onScreen=point.X>=0 and point.X<=viewport.X and point.Y>=0 and point.Y<=viewport.Y
    return point,onScreen
end

local function screenSnapshot()
    local camera=workspace.CurrentCamera
    local character,primary,head,humanoid=characterSnapshot()
    local primaryPoint,primaryOn=projectPart(camera,primary)
    local headPoint,headOn=projectPart(camera,head)
    return {
        camera=camera,cameraCFrame=camera and camera.CFrame or nil,cameraFocus=camera and camera.Focus or nil,
        cameraYaw=camera and yawFromCFrame(camera.CFrame) or nil,
        character=character,primary=primary,head=head,humanoid=humanoid,
        primaryPosition=primary and primary.Position or nil,headPosition=head and head.Position or nil,
        linearVelocity=primary and primary.AssemblyLinearVelocity or nil,
        moveDirection=humanoid and humanoid.MoveDirection or nil,
        primaryPoint=primaryPoint,primaryOnScreen=primaryOn,headPoint=headPoint,headOnScreen=headOn,
        moving=humanoid and humanoid.MoveDirection.Magnitude>=0.05 or false,
    }
end

local function vector2Change(after,before)
    if typeof(after)~="Vector2" or typeof(before)~="Vector2" then return nil end
    return after-before
end

local function recordInputWrite(route,before,after)
    local change=vector2Change(after,before)
    if typeof(change)~="Vector2" or change.Magnitude<=1e-8 then return end
    local now=os.clock()
    pendingWrites.totalNonzero+=1
    pendingWrites.totalSum+=change
    pendingWrites.firstAt=pendingWrites.firstAt or now
    pendingWrites.lastAt=now
    if route=="touch" then
        nonzeroWritesTouch+=1; pendingWrites.touchNonzero+=1; pendingWrites.touchSum+=change
    else
        nonzeroWritesRelay+=1; pendingWrites.relayNonzero+=1; pendingWrites.relaySum+=change
    end
end

local function predictEffectiveX(look,rootCFrame,requestedX)
    if typeof(look)~="Vector3" or typeof(rootCFrame)~="CFrame" or type(requestedX)~="number" then
        return nil,nil,nil,nil
    end
    local cameraYaw=yawFromLook(look)
    local _,rootYaw,_=rootCFrame:ToOrientation()
    if not cameraYaw then return nil,nil,nil,nil end
    local adjustedRootYaw=rootYaw
    local gap=cameraYaw-adjustedRootYaw
    if math.abs(gap)>=math.pi then
        local cameraEdge=cameraYaw>0 and math.pi-cameraYaw or -math.pi-cameraYaw
        local rootEdge=adjustedRootYaw>0 and math.pi-adjustedRootYaw or -math.pi-adjustedRootYaw
        adjustedRootYaw=cameraYaw+(cameraEdge-rootEdge)
    end
    local requestedTarget=cameraYaw-requestedX
    local clamped=math.clamp(requestedTarget,horizontalClampMin+adjustedRootYaw,horizontalClampMax+adjustedRootYaw)
    local effective=cameraYaw-clamped
    if math.abs(effective)<0.001 then effective=0 end
    return effective,cameraYaw,rootYaw,adjustedRootYaw
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

local function inputHandlerFactory(routeName)
    return function(callOriginal)
        return function(self,input,...)
            if not probeRunning or suppressTrace then return callOriginal(self,input,...) end
            if self~=getActiveController() then return callOriginal(self,input,...) end
            if routeName=="touch" then handlerCallsTouch+=1 else handlerCallsMouseTouch+=1 end
            local before=readRotate(self)
            local results=packCall(callOriginal,self,input,...)
            local after=readRotate(self)
            local route=routeName
            if routeName=="touch" and relayEnabled() then route="bookkeeping" end
            if routeName=="mouse" then
                local kind=nil
                pcall(function() kind=input.UserInputType end)
                route=kind==Enum.UserInputType.Touch and "relay" or "mouse-other"
            end
            if route=="touch" or route=="relay" then recordInputWrite(route,before,after) end
            if not results[1] then callbackErrors+=1 end
            return returnPacked(results)
        end
    end
end

local function getCameraLookFactory(callOriginal)
    return function(self,...)
        if not probeRunning or suppressTrace then return callOriginal(self,...) end
        local results=packCall(callOriginal,self,...)
        if currentCalc and self==getActiveController() then
            getCameraLookCallsInCalc+=1
            currentCalc.getCameraLook=results[2]
        end
        if not results[1] then callbackErrors+=1 end
        return returnPacked(results)
    end
end

local function calculateFactory(callOriginal)
    return function(self,lookOverride,...)
        if not probeRunning or suppressTrace then return callOriginal(self,lookOverride,...) end
        calculateCalls+=1
        local frame=currentFrame
        local isRelevant=frame and self==getActiveController()
        local calc=nil
        if isRelevant then
            frame.calculateIndex=(frame.calculateIndex or 0)+1
            calc={
                index=frame.calculateIndex,requested=readRotate(self),lookOverride=lookOverride,
                primary=select(2,characterSnapshot()),
            }
            if calc.primary then calc.primaryCFrame=calc.primary.CFrame end
            if calc.index==1 then frame.firstCalc=calc; firstCalculateCalls+=1 end
            currentCalc=calc
            frame.sequence[#frame.sequence+1]="Calculate("..tostring(calc.index).."):enter"
        end
        local results=packCall(callOriginal,self,lookOverride,...)
        if calc then
            currentCalc=nil
            calc.returnCFrame=results[2]
            calc.inputLook=lookOverride or calc.getCameraLook
            calc.requestedX=calc.requested and calc.requested.X or nil
            calc.predictedEffectiveX,calc.cameraYaw,calc.rootYaw,calc.adjustedRootYaw=
                predictEffectiveX(calc.inputLook,calc.primaryCFrame,calc.requestedX)
            calc.returnLookYaw=typeof(calc.returnCFrame)=="CFrame" and yawFromLook(calc.returnCFrame.LookVector) or nil
            calc.actualEffectiveX=(calc.cameraYaw and calc.returnLookYaw)
                and angleDifference(calc.cameraYaw,calc.returnLookYaw) or nil
            if calc.predictedEffectiveX and calc.requestedX then
                calc.clampAmount=calc.requestedX-calc.predictedEffectiveX
            end
            if calc.predictedEffectiveX and calc.actualEffectiveX then
                calc.predictionResidual=math.abs(angleDifference(calc.predictedEffectiveX,calc.actualEffectiveX) or 0)
            end
            frame.sequence[#frame.sequence+1]="Calculate("..tostring(calc.index).."):exit"
        end
        if not results[1] then callbackErrors+=1 end
        return returnPacked(results)
    end
end

local function getSubjectFactory(callOriginal)
    return function(self,...)
        if not probeRunning or suppressTrace then return callOriginal(self,...) end
        local results=packCall(callOriginal,self,...)
        local frame=currentFrame
        if frame and self==getActiveController() then
            getSubjectCalls+=1
            frame.sequence[#frame.sequence+1]="GetSubjectPosition"
            if not frame.subject then
                local position=results[2]
                local camera=workspace.CurrentCamera
                local subject=camera and camera.CameraSubject or nil
                local _,primary,head=characterSnapshot()
                local detail={position=position,subject=subject,primary=primary,head=head}
                if typeof(position)=="Vector3" then
                    detail.primaryDistance=primary and (position-primary.Position).Magnitude or nil
                    detail.headDistance=head and (position-head.Position).Magnitude or nil
                end
                if subject then
                    local className,name="unknown","unknown"
                    pcall(function() className=subject.ClassName; name=subject.Name end)
                    detail.subjectClass=className; detail.subjectName=name
                    local key=className..":"..name
                    subjectClassCounts[key]=(subjectClassCounts[key] or 0)+1
                end
                frame.subject=detail
                lastSubjectDetail=string.format("subject=%s:%s position=%s primaryDist=%s headDist=%s",
                    tostring(detail.subjectClass),tostring(detail.subjectName),cleanText(position,90),
                    cleanText(detail.primaryDistance,40),cleanText(detail.headDistance,40))
            end
        end
        if not results[1] then callbackErrors+=1 end
        return returnPacked(results)
    end
end

local function getOffsetFactory(callOriginal)
    return function(self,...)
        if not probeRunning or suppressTrace then return callOriginal(self,...) end
        local results=packCall(callOriginal,self,...)
        local frame=currentFrame
        if frame and self==getActiveController() then
            getMouseLockOffsetCalls+=1
            frame.sequence[#frame.sequence+1]="GetMouseLockOffset"
            if frame.offset==nil then frame.offset=results[2] end
        end
        if not results[1] then callbackErrors+=1 end
        return returnPacked(results)
    end
end

local function controllerFactory(callOriginal)
    return function(self,dt,...)
        if not probeRunning or suppressTrace then return callOriginal(self,dt,...) end
        if self~=getActiveController() then return callOriginal(self,dt,...) end
        controllerUpdates+=1
        local frame=currentFrame
        if frame then
            frame.controllerEntryRotate=readRotate(self)
            frame.sequence[#frame.sequence+1]="Controller.Update:enter"
        end
        local results=packCall(callOriginal,self,dt,...)
        if frame then
            frame.controllerReturnCFrame=results[2]
            frame.controllerReturnFocus=results[3]
            frame.controllerExitRotate=readRotate(self)
            frame.sequence[#frame.sequence+1]="Controller.Update:exit"
        end
        if not results[1] then controllerErrors+=1; callbackErrors+=1 end
        return returnPacked(results)
    end
end

local function pointStep(a,b)
    if typeof(a)~="Vector3" or typeof(b)~="Vector3" then return nil end
    return Vector2.new(b.X-a.X,b.Y-a.Y).Magnitude
end

local function appendLimited(list,value,limit)
    if type(value)=="number" and value==value and #list<(limit or 2400) then list[#list+1]=value end
end

local function sortedCopy(values)
    local copy={}
    for _,value in ipairs(values) do copy[#copy+1]=value end
    table.sort(copy)
    return copy
end

local function percentile(values,fraction)
    if #values==0 then return nil end
    local sorted=sortedCopy(values)
    local position=1+(#sorted-1)*math.clamp(fraction,0,1)
    local lower=math.floor(position)
    local upper=math.ceil(position)
    if lower==upper then return sorted[lower] end
    local weight=position-lower
    return sorted[lower]*(1-weight)+sorted[upper]*weight
end

local function distribution(values)
    if #values==0 then return {count=0,mean=nil,median=nil,p95=nil,max=nil} end
    local sum=0
    local maximum=-math.huge
    for _,value in ipairs(values) do sum+=value; maximum=math.max(maximum,value) end
    return {count=#values,mean=sum/#values,median=percentile(values,0.5),p95=percentile(values,0.95),max=maximum}
end

local function distributionText(values)
    local d=distribution(values)
    return string.format("n=%d mean=%s median=%s p95=%s max=%s",d.count,
        tostring(round(d.mean,7)),tostring(round(d.median,7)),tostring(round(d.p95,7)),tostring(round(d.max,7)))
end

local function standingObservation(frame)
    local before=frame.screenBefore
    if not before or typeof(before.primaryPosition)~="Vector3" then
        return false,"primary-position-unavailable",nil,nil,nil,false
    end
    local velocity=typeof(before.linearVelocity)=="Vector3" and before.linearVelocity.Magnitude or math.huge
    local moveDirection=typeof(before.moveDirection)=="Vector3" and before.moveDirection.Magnitude or math.huge
    local worldDelta=typeof(phaseLastPrimaryPosition)=="Vector3"
        and (before.primaryPosition-phaseLastPrimaryPosition).Magnitude or math.huge
    phaseLastPrimaryPosition=before.primaryPosition
    local deltaLimit=math.max(MAX_WORLD_DELTA_FLOOR,(tonumber(frame.dt) or 1/60)*MAX_LINEAR_VELOCITY)
    local joystickInactive,joystickDetail=true,"unavailable-not-required"
    if type(readJoystickStandingState)=="function" then joystickInactive,joystickDetail=readJoystickStandingState() end
    local standing=velocity<=MAX_LINEAR_VELOCITY and worldDelta<=deltaLimit
        and moveDirection<=MAX_MOVE_DIRECTION and joystickInactive
    local detail=string.format("velocity=%.6f<=%.3f worldDelta=%.6f<=%.6f moveDirection=%.6f<=%.3f joystickInactive=%s(%s)",
        velocity,MAX_LINEAR_VELOCITY,worldDelta,deltaLimit,moveDirection,MAX_MOVE_DIRECTION,
        tostring(joystickInactive),cleanText(joystickDetail,100))
    return standing,detail,velocity,worldDelta,moveDirection,joystickInactive
end

local function routeMatchesPhase(frame)
    local writes=frame.writes
    if not writes then return false end
    if currentPhase=="touch" then return writes.touchNonzero>0 and writes.relayNonzero==0 end
    if currentPhase=="relay" then return writes.relayNonzero>0 and writes.touchNonzero==0 end
    return false
end

local function recordPairedSample(frame,stats,actualYawDeg,returnedYawDeg,primaryStep,headStep,returnedPrimaryStep,returnedHeadStep)
    local subject=frame.subject
    stats.validStandingFrames+=1
    stats.cameraYawAppliedAbsDeg+=actualYawDeg
    stats.primaryDisplacementSum+=primaryStep
    stats.headDisplacementSum+=headStep
    stats.returnedPrimaryDisplacementSum+=returnedPrimaryStep
    stats.returnedHeadDisplacementSum+=returnedHeadStep
    appendLimited(stats.yawDegrees,actualYawDeg)
    appendLimited(stats.primaryRatios,primaryStep/actualYawDeg)
    appendLimited(stats.headRatios,headStep/actualYawDeg)
    appendLimited(stats.returnedPrimaryRatios,returnedPrimaryStep/returnedYawDeg)
    appendLimited(stats.returnedHeadRatios,returnedHeadStep/returnedYawDeg)
    appendLimited(stats.primaryDisplacements,primaryStep)
    appendLimited(stats.headDisplacements,headStep)
    appendLimited(stats.returnedPrimaryDisplacements,returnedPrimaryStep)
    appendLimited(stats.returnedHeadDisplacements,returnedHeadStep)
    if subject and typeof(subject.position)=="Vector3" then
        stats.subjectPositionSum+=subject.position
        stats.subjectPositionCount+=1
        stats.lastSubjectPosition=subject.position
        appendLimited(stats.subjectPrimaryDistances,subject.primaryDistance)
        appendLimited(stats.subjectHeadDistances,subject.headDistance)
    end
    if typeof(frame.worldOffset)=="Vector3" then appendLimited(stats.offsetMagnitudes,frame.worldOffset.Magnitude) end
    appendLimited(stats.focusResiduals,frame.focusResidual)
    stats.samples[#stats.samples+1]={
        yaw=actualYawDeg,primary=primaryStep/actualYawDeg,head=headStep/actualYawDeg,
        returnedPrimary=returnedPrimaryStep/returnedYawDeg,returnedHead=returnedHeadStep/returnedYawDeg,
    }
end

local function finalizeFrame(frame)
    local phase=frame.phase
    local stats=phaseStats[phase]
    if not stats then return end
    stats.frames+=1
    local writes=frame.writes
    local relevant=writes and writes.totalNonzero>0
    if relevant then
        stats.inputFrames+=1
        stats.writeCount+=writes.totalNonzero
        stats.maxWritesPerFrame=math.max(stats.maxWritesPerFrame,writes.totalNonzero)
        stats.writeXAbs+=math.abs(writes.totalSum.X)
        stats.writeYAbs+=math.abs(writes.totalSum.Y)
        if frame.startedAt and writes.firstAt and writes.lastAt then
            frame.writeFirstAgeMs=(frame.startedAt-writes.firstAt)*1000
            frame.writeLastAgeMs=(frame.startedAt-writes.lastAt)*1000
            stats.writeFirstAgeMsSum+=frame.writeFirstAgeMs
            stats.writeLastAgeMsSum+=frame.writeLastAgeMs
            stats.writeAgeSamples+=1
        end
    end
    local calc=frame.firstCalc
    if relevant and calc and type(calc.requestedX)=="number" and type(calc.predictedEffectiveX)=="number" then
        stats.calcFrames+=1
        stats.requestedCount+=1
        stats.requestedXAbs+=math.abs(calc.requestedX)
        stats.effectiveXAbs+=math.abs(calc.predictedEffectiveX)
        if type(calc.actualEffectiveX)=="number" then stats.actualEffectiveXAbs+=math.abs(calc.actualEffectiveX) end
        if math.abs(calc.requestedX)>1e-6 then
            stats.effectiveRatioSum+=math.abs(calc.predictedEffectiveX/calc.requestedX)
            stats.effectiveRatioCount+=1
        end
        local amount=math.abs(calc.clampAmount or 0)
        if amount>1e-6 then stats.clampFrames+=1; stats.clampAmountAbs+=amount end
        local residual=calc.predictionResidual or 0
        stats.clampResidualSum+=residual
        stats.clampResidualMax=math.max(stats.clampResidualMax,residual)
        if calc.cameraYaw and calc.returnLookYaw then
            stats.lookYawAppliedAbsDeg+=math.deg(math.abs(angleDifference(calc.returnLookYaw,calc.cameraYaw) or 0))
        end
    end
    local subject=frame.subject
    if subject and typeof(subject.position)=="Vector3" then
        stats.subjectSamples+=1
        if type(subject.primaryDistance)=="number" then stats.subjectPrimaryDistanceSum+=subject.primaryDistance end
        if type(subject.headDistance)=="number" then stats.subjectHeadDistanceSum+=subject.headDistance end
        if type(subject.primaryDistance)=="number" and type(subject.headDistance)=="number" then
            if subject.primaryDistance+0.02<subject.headDistance then stats.subjectCloserPrimary+=1
            elseif subject.headDistance+0.02<subject.primaryDistance then stats.subjectCloserHead+=1
            else stats.subjectEquidistant+=1 end
        end
    end
    if calc and typeof(calc.returnCFrame)=="CFrame" and typeof(frame.offset)=="Vector3" and subject
        and typeof(subject.position)=="Vector3" then
        local offset=frame.offset
        frame.offsetRightVector=calc.returnCFrame.RightVector
        frame.offsetUpVector=calc.returnCFrame.UpVector
        frame.offsetLookVector=calc.returnCFrame.LookVector
        local worldOffset=offset.X*frame.offsetRightVector+offset.Y*frame.offsetUpVector
            +offset.Z*frame.offsetLookVector
        frame.worldOffset=worldOffset
        frame.subjectAfterOffset=subject.position+worldOffset
        stats.offsetSamples+=1
        stats.offsetMagnitudeSum+=worldOffset.Magnitude
        if typeof(frame.controllerReturnFocus)=="CFrame" then
            local residual=(frame.controllerReturnFocus.Position-frame.subjectAfterOffset).Magnitude
            frame.focusResidual=residual
            stats.focusResidualSum+=residual
            stats.focusResidualMax=math.max(stats.focusResidualMax,residual)
        end
    end
    local before=frame.screenBefore
    local after=frame.screenAfter
    local cameraYawDeg=(before and after and before.cameraYaw and after.cameraYaw)
        and math.deg(math.abs(angleDifference(after.cameraYaw,before.cameraYaw) or 0)) or 0
    if relevant then stats.cameraYawAppliedAbsDeg+=cameraYawDeg end
    if relevant and cameraYawDeg>0.001 and before and after then
        local primaryStep=pointStep(before.primaryPoint,after.primaryPoint)
        if primaryStep and before.primaryOnScreen and after.primaryOnScreen then
            stats.primaryScreenSamples+=1; stats.primaryScreenStepSum+=primaryStep; stats.primaryDriftYawDeg+=cameraYawDeg
            if before.moving then
                stats.movingPrimarySamples+=1; stats.movingPrimaryStepSum+=primaryStep; stats.movingPrimaryYawDeg+=cameraYawDeg
            else
                stats.standingPrimarySamples+=1; stats.standingPrimaryStepSum+=primaryStep; stats.standingPrimaryYawDeg+=cameraYawDeg
            end
        end
        local headStep=pointStep(before.headPoint,after.headPoint)
        if headStep and before.headOnScreen and after.headOnScreen then
            stats.headScreenSamples+=1; stats.headScreenStepSum+=headStep; stats.headDriftYawDeg+=cameraYawDeg
            if not before.moving then
                stats.standingHeadSamples+=1; stats.standingHeadStepSum+=headStep; stats.standingHeadYawDeg+=cameraYawDeg
            end
        end
    end
    local returnedYawDeg=(before and before.cameraYaw and typeof(frame.controllerReturnCFrame)=="CFrame")
        and math.deg(math.abs(angleDifference(yawFromCFrame(frame.controllerReturnCFrame),before.cameraYaw) or 0)) or 0
    if relevant and returnedYawDeg>0.001 and before and after and typeof(frame.controllerReturnCFrame)=="CFrame" then
        local camera=before.camera or workspace.CurrentCamera
        local returnedPrimary,returnedPrimaryOn=projectPositionWithCFrame(camera,frame.controllerReturnCFrame,after.primaryPosition)
        local returnedHead,returnedHeadOn=projectPositionWithCFrame(camera,frame.controllerReturnCFrame,after.headPosition)
        frame.returnedPrimaryPoint=returnedPrimary; frame.returnedHeadPoint=returnedHead
        frame.returnedPrimaryOnScreen=returnedPrimaryOn; frame.returnedHeadOnScreen=returnedHeadOn
        local primaryStep=pointStep(before.primaryPoint,returnedPrimary)
        if primaryStep and before.primaryOnScreen and returnedPrimaryOn then
            stats.returnedPrimaryScreenSamples+=1
            stats.returnedPrimaryScreenStepSum+=primaryStep
            stats.returnedPrimaryDriftYawDeg+=returnedYawDeg
            if not before.moving then
                stats.returnedStandingPrimarySamples+=1
                stats.returnedStandingPrimaryStepSum+=primaryStep
                stats.returnedStandingPrimaryYawDeg+=returnedYawDeg
            end
        end
        local headStep=pointStep(before.headPoint,returnedHead)
        if headStep and before.headOnScreen and returnedHeadOn then
            stats.returnedHeadScreenSamples+=1
            stats.returnedHeadScreenStepSum+=headStep
            stats.returnedHeadDriftYawDeg+=returnedYawDeg
            if not before.moving then
                stats.returnedStandingHeadSamples+=1
                stats.returnedStandingHeadStepSum+=headStep
                stats.returnedStandingHeadYawDeg+=returnedYawDeg
            end
        end
    end
    if typeof(frame.controllerReturnCFrame)=="CFrame" and typeof(frame.controllerReturnFocus)=="CFrame" then
        stats.controllerCameraDistanceCount+=1
        stats.controllerCameraDistanceSum+=(frame.controllerReturnCFrame.Position-frame.controllerReturnFocus.Position).Magnitude
    end
    if currentPhase=="touch" or currentPhase=="relay" then
        local paired=pairedStats[currentPhase]
        local standing,standingDetail,velocity,worldDelta,moveDirection=standingObservation(frame)
        lastStandingDetail="phase="..currentPhase.." state="..phaseState.." "..standingDetail
        if phaseState=="stabilizing" or phaseState=="restabilizing" then
            paired.stabilizationFrames+=1
            if os.clock()>=phaseStabilizeUntil and standing then stableConsecutive+=1 else stableConsecutive=0 end
            if stableConsecutive>=STABLE_CONSECUTIVE_FRAMES then
                phaseState="active"
                addEvidence("PHASE",currentPhase.." stabilization complete; controlled collection active")
            end
        elseif phaseState=="active" and relevant then
            appendLimited(paired.linearVelocities,velocity)
            appendLimited(paired.worldDeltas,worldDelta)
            appendLimited(paired.moveDirections,moveDirection)
            if not routeMatchesPhase(frame) then
                paired.rejectedWrongRouteFrames+=1
            elseif not standing then
                paired.rejectedMovingFrames+=1
                phaseState="restabilizing"
                phaseStabilizeUntil=os.clock()+0.35
                stableConsecutive=0
                addTrace("rejected-moving frame="..frame.id.." phase="..currentPhase.." "..standingDetail)
            elseif cameraYawDeg<MIN_APPLIED_YAW_DEG or returnedYawDeg<MIN_APPLIED_YAW_DEG then
                paired.rejectedLowYawFrames+=1
            else
                local primaryStep=before and after and pointStep(before.primaryPoint,after.primaryPoint)
                local headStep=before and after and pointStep(before.headPoint,after.headPoint)
                local returnedPrimaryStep=before and pointStep(before.primaryPoint,frame.returnedPrimaryPoint)
                local returnedHeadStep=before and pointStep(before.headPoint,frame.returnedHeadPoint)
                local projectionsValid=primaryStep and headStep and returnedPrimaryStep and returnedHeadStep
                    and before.primaryOnScreen and before.headOnScreen
                    and after.primaryOnScreen and after.headOnScreen
                    and frame.returnedPrimaryOnScreen and frame.returnedHeadOnScreen
                if not projectionsValid then
                    paired.rejectedProjectionFrames+=1
                else
                    recordPairedSample(frame,paired,cameraYawDeg,returnedYawDeg,primaryStep,headStep,
                        returnedPrimaryStep,returnedHeadStep)
                    lastStandingDetail=lastStandingDetail..string.format(
                        " ACCEPT actualYawDeg=%.6f returnedYawDeg=%.6f primaryPx=%.6f headPx=%.6f returnedPrimaryPx=%.6f returnedHeadPx=%.6f",
                        cameraYawDeg,returnedYawDeg,primaryStep,headStep,returnedPrimaryStep,returnedHeadStep)
                    if paired.validStandingFrames<=12 or paired.validStandingFrames%100==0 then addTrace(lastStandingDetail) end
                end
            end
        end
        if type(refreshLiveStatus)=="function" and os.clock()-uiLastRefresh>=0.20 then
            uiLastRefresh=os.clock(); refreshLiveStatus()
        end
    end
    if relevant then
        local rootGap=(calc and calc.cameraYaw and calc.rootYaw) and math.deg(angleDifference(calc.cameraYaw,calc.rootYaw) or 0) or nil
        lastCorrelatedFrame=string.format(
            "frame=%d phase=%s writes=%d touchWrites=%d relayWrites=%d touchSum=%s relaySum=%s totalSum=%s firstAgeMs=%s lastAgeMs=%s rotateEntry=%s requestedX=%s effectiveX=%s actualX=%s clampAmount=%s cameraYaw=%s rootYaw=%s gapDeg=%s lookYaw=%s subject={%s} offset=%s right=%s up=%s look=%s worldOffset=%s focusResidual=%s screenPrimaryStep=%s screenHeadStep=%s returnedPrimaryStep=%s returnedHeadStep=%s cameraYawAppliedDeg=%s returnedYawDeg=%s sequence={%s}",
            frame.id,phase,writes.totalNonzero,writes.touchNonzero,writes.relayNonzero,
            cleanText(writes.touchSum,70),cleanText(writes.relaySum,70),cleanText(writes.totalSum,70),
            cleanText(frame.writeFirstAgeMs,35),cleanText(frame.writeLastAgeMs,35),cleanText(frame.controllerEntryRotate,70),
            cleanText(calc and calc.requestedX,35),cleanText(calc and calc.predictedEffectiveX,35),
            cleanText(calc and calc.actualEffectiveX,35),cleanText(calc and calc.clampAmount,35),
            cleanText(calc and calc.cameraYaw,35),cleanText(calc and calc.rootYaw,35),cleanText(rootGap,35),
            cleanText(calc and calc.returnLookYaw,35),lastSubjectDetail,cleanText(frame.offset,60),
            cleanText(frame.offsetRightVector,70),cleanText(frame.offsetUpVector,70),cleanText(frame.offsetLookVector,70),
            cleanText(frame.worldOffset,70),cleanText(frame.focusResidual,35),
            cleanText(before and after and pointStep(before.primaryPoint,after.primaryPoint),35),
            cleanText(before and after and pointStep(before.headPoint,after.headPoint),35),
            cleanText(before and pointStep(before.primaryPoint,frame.returnedPrimaryPoint),35),
            cleanText(before and pointStep(before.headPoint,frame.returnedHeadPoint),35),
            cleanText(cameraYawDeg,35),cleanText(returnedYawDeg,35),
            table.concat(frame.sequence,">"))
        lastGeometryDetail=string.format("phase=%s subjectRaw=%s primaryPosition=%s headPosition=%s subjectAfterOffset=%s right=%s up=%s look=%s controllerCFrame=%s controllerFocus=%s",
            phase,cleanText(subject and subject.position,80),cleanText(before and before.primaryPosition,80),
            cleanText(before and before.headPosition,80),cleanText(frame.subjectAfterOffset,80),
            cleanText(frame.offsetRightVector,80),cleanText(frame.offsetUpVector,80),cleanText(frame.offsetLookVector,80),
            cleanText(frame.controllerReturnCFrame,110),cleanText(frame.controllerReturnFocus,110))
        if stats.inputFrames<=18 or stats.inputFrames%100==0 or (calc and math.abs(calc.clampAmount or 0)>1e-6) then
            addTrace(lastCorrelatedFrame)
        end
    end
end

local function cameraModuleFactory(callOriginal)
    return function(self,dt,...)
        if not probeRunning or suppressTrace then return callOriginal(self,dt,...) end
        cameraModuleUpdates+=1; probeFrames+=1; frameSerial+=1
        local writes=pendingWrites
        pendingWrites=newPending()
        local phase=writes.relayNonzero>0 and "relay" or (writes.touchNonzero>0 and "touch")
            or (relayEnabled() and "relay" or "touch")
        local frame={
            id=frameSerial,dt=dt,phase=phase,writes=writes,startedAt=os.clock(),screenBefore=screenSnapshot(),
            sequence={"CameraModule.Update:enter"},calculateIndex=0,
        }
        currentFrame=frame
        local results=packCall(callOriginal,self,dt,...)
        frame.screenAfter=screenSnapshot()
        frame.sequence[#frame.sequence+1]="CameraModule.Update:exit"
        local ok,err=pcall(finalizeFrame,frame)
        if not ok then frameCorrelationErrors+=1; addEvidence("CORRELATION","frame error="..cleanText(err,160)) end
        currentFrame=nil; currentCalc=nil
        if not results[1] then callbackErrors+=1 end
        return returnPacked(results)
    end
end

local function installFocusedHooks()
    local specs={
        {"OnTouchChanged",inputHandlerFactory("touch")},
        {"OnMouseMoved",inputHandlerFactory("mouse")},
        {"GetCameraLookVector",getCameraLookFactory},
        {"CalculateNewLookCFrame",calculateFactory},
        {"GetSubjectPosition",getSubjectFactory},
        {"GetMouseLockOffset",getOffsetFactory},
        {"Controller.Update",controllerFactory},
        {"CameraModule.Update",cameraModuleFactory},
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
        details[#details+1]=hook.id.."="..tostring(ok)..(ok and "" or ":"..cleanText(err,90))
    end
    installedHooks={}
    hookRestoreOk=okAll
    hookRestoreDetail=#details>0 and table.concat(details,"; ") or "not-needed"
    return okAll
end

local function resetCounters()
    probeFrames=0; callbackErrors=0; traceLines={}; traceDropped=0
    currentFrame=nil; currentCalc=nil; frameSerial=0; pendingWrites=newPending()
    handlerCallsTouch=0; handlerCallsMouseTouch=0; nonzeroWritesTouch=0; nonzeroWritesRelay=0
    calculateCalls=0; firstCalculateCalls=0; getCameraLookCallsInCalc=0
    getSubjectCalls=0; getMouseLockOffsetCalls=0; controllerUpdates=0; cameraModuleUpdates=0
    controllerErrors=0; frameCorrelationErrors=0; subjectClassCounts={}
    lastCorrelatedFrame=""; lastSubjectDetail=""; lastGeometryDetail=""; lastStandingDetail=""
    phaseStats={touch=newPhaseStats(),relay=newPhaseStats()}
    pairedStats={touch=newPairedStats(),relay=newPairedStats()}
    currentPhase="none"; phaseState="idle"; stableConsecutive=0; phaseLastPrimaryPosition=nil
    hookRestoreOk=nil; hookRestoreDetail="running"
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
    stateAtStop=nil
    probeStartedAt=os.clock(); probeDuration=0; probeRunning=true
    addEvidence("PROBE","V612 paired standing control started; choose explicit phase A then B")
    return true,"started"
end

local function stopProbe()
    if not probeRunning then
        if #installedHooks>0 then
            stateAtStop={relay=relayEnabled(),rotate=readRotate(getActiveController()),preferred=UserInputService.PreferredInput}
            restoreHooks(); addEvidence("PROBE","idle hooks restored")
            return true,"idle-hooks-restored"
        end
        return true,"already-stopped"
    end
    probeDuration=os.clock()-probeStartedAt
    probeRunning=false; currentFrame=nil; currentCalc=nil; currentPhase="none"; phaseState="stopped"
    stateAtStop={relay=relayEnabled(),rotate=readRotate(getActiveController()),preferred=UserInputService.PreferredInput}
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

readJoystickStandingState=function()
    local now=os.clock()
    if now-lastJoystickReadAt>=0.10 then
        lastJoystickReadAt=now
        local base=baseSafe()
        local hasMoveField=base.moveTouchObjectActive~=nil
        local hasIds=base.activeJoystickTouchIds~=nil
        joystickCriterionAvailable=hasMoveField or hasIds
        local moveInactive=base.moveTouchObjectActive~=true
        local idsInactive=base.activeJoystickTouchIds==nil or base.activeJoystickTouchIds=="none"
        cachedJoystickInactive=moveInactive and idsInactive
        cachedJoystickDetail=string.format("available=%s moveTouch=%s ids=%s",tostring(joystickCriterionAvailable),
            tostring(base.moveTouchObjectActive),tostring(base.activeJoystickTouchIds))
    end
    return cachedJoystickInactive,cachedJoystickDetail
end

local function beginControlledPhase(phase)
    if not probeRunning then return false,"press-INICIAR-first" end
    if phase~="touch" and phase~="relay" then return false,"invalid-phase" end
    if type(baseSetRelay)~="function" then return false,"V604-relay-control-unavailable" end
    local wantRelay=phase=="relay"
    local ok,result=pcall(baseSetRelay,wantRelay)
    if not ok or result==false then return false,cleanText(result,180) end
    pairedStats[phase]=newPairedStats()
    currentPhase=phase
    phaseState="stabilizing"
    phaseStartedAt=os.clock()
    phaseStabilizeUntil=phaseStartedAt+STABILIZE_SECONDS
    stableConsecutive=0
    phaseLastPrimaryPosition=nil
    lastJoystickReadAt=0
    addEvidence("PHASE",string.format("%s selected relay=%s stabilization=%.2fs+%d consecutive standing frames",
        tostring(phase),tostring(wantRelay),STABILIZE_SECONDS,STABLE_CONSECUTIVE_FRAMES))
    return true,"stabilizing"
end

local function countSummary(counts,limit)
    local rows={}
    for key,count in pairs(counts) do rows[#rows+1]={key=tostring(key),count=count} end
    table.sort(rows,function(a,b) return a.count>b.count end)
    local result={}
    for index=1,math.min(#rows,limit or 12) do result[#result+1]=rows[index].key..":"..rows[index].count end
    return #result>0 and table.concat(result," | ") or "none"
end

local function phaseValue(stats,name)
    if name=="requestedXMeanAbs" then return stats.requestedCount>0 and stats.requestedXAbs/stats.requestedCount or nil end
    if name=="writeFirstAgeMsMean" then return stats.writeAgeSamples>0 and stats.writeFirstAgeMsSum/stats.writeAgeSamples or nil end
    if name=="writeLastAgeMsMean" then return stats.writeAgeSamples>0 and stats.writeLastAgeMsSum/stats.writeAgeSamples or nil end
    if name=="effectiveXMeanAbs" then return stats.requestedCount>0 and stats.effectiveXAbs/stats.requestedCount or nil end
    if name=="actualEffectiveXMeanAbs" then return stats.requestedCount>0 and stats.actualEffectiveXAbs/stats.requestedCount or nil end
    if name=="effectiveRatioMean" then return stats.effectiveRatioCount>0 and stats.effectiveRatioSum/stats.effectiveRatioCount or nil end
    if name=="clampRate" then return stats.requestedCount>0 and stats.clampFrames/stats.requestedCount or nil end
    if name=="clampResidualMean" then return stats.requestedCount>0 and stats.clampResidualSum/stats.requestedCount or nil end
    if name=="subjectPrimaryDistanceMean" then return stats.subjectSamples>0 and stats.subjectPrimaryDistanceSum/stats.subjectSamples or nil end
    if name=="subjectHeadDistanceMean" then return stats.subjectSamples>0 and stats.subjectHeadDistanceSum/stats.subjectSamples or nil end
    if name=="offsetMagnitudeMean" then return stats.offsetSamples>0 and stats.offsetMagnitudeSum/stats.offsetSamples or nil end
    if name=="focusResidualMean" then return stats.offsetSamples>0 and stats.focusResidualSum/stats.offsetSamples or nil end
    if name=="primaryDriftPerYawDegree" then return stats.primaryDriftYawDeg>0 and stats.primaryScreenStepSum/stats.primaryDriftYawDeg or nil end
    if name=="headDriftPerYawDegree" then return stats.headDriftYawDeg>0 and stats.headScreenStepSum/stats.headDriftYawDeg or nil end
    if name=="returnedPrimaryDriftPerYawDegree" then return stats.returnedPrimaryDriftYawDeg>0 and stats.returnedPrimaryScreenStepSum/stats.returnedPrimaryDriftYawDeg or nil end
    if name=="returnedHeadDriftPerYawDegree" then return stats.returnedHeadDriftYawDeg>0 and stats.returnedHeadScreenStepSum/stats.returnedHeadDriftYawDeg or nil end
    if name=="returnedStandingPrimaryDriftPerYawDegree" then return stats.returnedStandingPrimaryYawDeg>0 and stats.returnedStandingPrimaryStepSum/stats.returnedStandingPrimaryYawDeg or nil end
    if name=="returnedStandingHeadDriftPerYawDegree" then return stats.returnedStandingHeadYawDeg>0 and stats.returnedStandingHeadStepSum/stats.returnedStandingHeadYawDeg or nil end
    if name=="standingPrimaryDriftPerYawDegree" then return stats.standingPrimaryYawDeg>0 and stats.standingPrimaryStepSum/stats.standingPrimaryYawDeg or nil end
    if name=="standingHeadDriftPerYawDegree" then return stats.standingHeadYawDeg>0 and stats.standingHeadStepSum/stats.standingHeadYawDeg or nil end
    if name=="movingPrimaryDriftPerYawDegree" then return stats.movingPrimaryYawDeg>0 and stats.movingPrimaryStepSum/stats.movingPrimaryYawDeg or nil end
    if name=="controllerCameraDistanceMean" then return stats.controllerCameraDistanceCount>0 and stats.controllerCameraDistanceSum/stats.controllerCameraDistanceCount or nil end
    return stats[name]
end

local function relativeDifference(a,b)
    if type(a)~="number" or type(b)~="number" then return nil end
    local denominator=math.max(math.abs(a),math.abs(b),1e-9)
    return math.abs(a-b)/denominator
end

local function samplesInBucket(samples,low,high,lastBucket)
    local result={primary={},head={},returnedPrimary={},returnedHead={}}
    for _,sample in ipairs(samples) do
        local inside=sample.yaw>=low and (lastBucket and sample.yaw<=high or sample.yaw<high)
        if inside then
            result.primary[#result.primary+1]=sample.primary
            result.head[#result.head+1]=sample.head
            result.returnedPrimary[#result.returnedPrimary+1]=sample.returnedPrimary
            result.returnedHead[#result.returnedHead+1]=sample.returnedHead
        end
    end
    return result
end

local function meanSubjectPosition(stats)
    return stats.subjectPositionCount>0 and stats.subjectPositionSum/stats.subjectPositionCount or nil
end

local function equivalentDistribution(a,b,absoluteTolerance,relativeTolerance,minSamples)
    local da,db=distribution(a),distribution(b)
    if da.count<(minSamples or MIN_PHASE_SAMPLES) or db.count<(minSamples or MIN_PHASE_SAMPLES) then return "unproved" end
    local medianDifference=math.abs((da.median or 0)-(db.median or 0))
    local p95Difference=math.abs((da.p95 or 0)-(db.p95 or 0))
    local medianRelative=relativeDifference(da.median,db.median) or math.huge
    local p95Relative=relativeDifference(da.p95,db.p95) or math.huge
    return (medianDifference<=absoluteTolerance or medianRelative<=relativeTolerance)
        and (p95Difference<=absoluteTolerance*2 or p95Relative<=relativeTolerance*2)
end

local function bucketComparison()
    local touch,relay=pairedStats.touch,pairedStats.relay
    if #touch.yawDegrees<MIN_PHASE_SAMPLES or #relay.yawDegrees<MIN_PHASE_SAMPLES then
        return "unproved: insufficient per-phase yaw samples",0,0,0
    end
    local overlapLow=math.max(MIN_APPLIED_YAW_DEG,percentile(touch.yawDegrees,0.05) or math.huge,
        percentile(relay.yawDegrees,0.05) or math.huge)
    local overlapHigh=math.min(percentile(touch.yawDegrees,0.95) or -math.huge,
        percentile(relay.yawDegrees,0.95) or -math.huge)
    if overlapHigh<=overlapLow then return "unproved: no shared p05-p95 yaw support",0,0,0 end
    local combined={}
    for _,value in ipairs(touch.yawDegrees) do
        if value>=overlapLow and value<=overlapHigh then combined[#combined+1]=value end
    end
    for _,value in ipairs(relay.yawDegrees) do
        if value>=overlapLow and value<=overlapHigh then combined[#combined+1]=value end
    end
    if #combined<MIN_BUCKET_SAMPLES*3 then return "unproved: insufficient yaw samples inside shared support",0,0,0 end
    local q33=percentile(combined,1/3)
    local q67=percentile(combined,2/3)
    if not q33 or not q67 or q67-q33<1e-6 then return "unproved: yaw quantiles collapsed",0,0,0 end
    local bounds={{overlapLow,q33,false,"small"},{q33,q67,false,"medium"},{q67,overlapHigh,true,"large"}}
    local lines={string.format("neutral tertiles inside shared p05-p95 yaw support low=%.6fdeg high=%.6fdeg q33=%.6fdeg q67=%.6fdeg minPerPhase=%d",overlapLow,overlapHigh,q33,q67,MIN_BUCKET_SAMPLES)}
    local matched,significant,equivalent=0,0,0
    local direction=0
    for _,bound in ipairs(bounds) do
        local a=samplesInBucket(touch.samples,bound[1],bound[2],bound[3])
        local b=samplesInBucket(relay.samples,bound[1],bound[2],bound[3])
        local ap,bp=distribution(a.primary),distribution(b.primary)
        local arp,brp=distribution(a.returnedPrimary),distribution(b.returnedPrimary)
        local ah,bh=distribution(a.head),distribution(b.head)
        local arh,brh=distribution(a.returnedHead),distribution(b.returnedHead)
        local relActual=relativeDifference(ap.median,bp.median)
        local relReturned=relativeDifference(arp.median,brp.median)
        local relHead=relativeDifference(ah.median,bh.median)
        local relReturnedHead=relativeDifference(arh.median,brh.median)
        local enough=ap.count>=MIN_BUCKET_SAMPLES and bp.count>=MIN_BUCKET_SAMPLES
        if enough then
            matched+=1
            local signed=(bp.median or 0)-(ap.median or 0)
            local thisDirection=signed>0 and 1 or (signed<0 and -1 or 0)
            if relActual and relReturned and relActual>=0.20 and relReturned>=0.20
                and relHead and relReturnedHead and relHead>=0.15 and relReturnedHead>=0.15 then
                significant+=1
                if direction==0 then direction=thisDirection elseif direction~=thisDirection then direction=99 end
            end
            if relActual and relReturned and relHead and relReturnedHead
                and relActual<=0.15 and relReturned<=0.15
                and relHead<=0.20 and relReturnedHead<=0.20 then equivalent+=1 end
        end
        lines[#lines+1]=string.format("%s touchN=%d relayN=%d touchPrimaryMedian=%s relayPrimaryMedian=%s touchReturnedMedian=%s relayReturnedMedian=%s relActual=%s relReturned=%s relHead=%s relReturnedHead=%s matched=%s",
            bound[4],ap.count,bp.count,tostring(round(ap.median,7)),tostring(round(bp.median,7)),
            tostring(round(arp.median,7)),tostring(round(brp.median,7)),tostring(round(relActual,5)),
            tostring(round(relReturned,5)),tostring(round(relHead,5)),tostring(round(relReturnedHead,5)),tostring(enough))
    end
    return table.concat(lines," | "),matched,significant,equivalent,direction
end

local function classification()
    local touch,relay=pairedStats.touch,pairedStats.relay
    local minimum=math.min(touch.validStandingFrames,relay.validStandingFrames)
    local maximum=math.max(touch.validStandingFrames,relay.validStandingFrames)
    local balance=maximum>0 and minimum/maximum or 0
    local enough=touch.validStandingFrames>=MIN_PHASE_SAMPLES
        and relay.validStandingFrames>=MIN_PHASE_SAMPLES and balance>=MIN_SAMPLE_BALANCE
    local buckets,matched,significant,equivalent,direction=bucketComparison()
    local touchPrimary,relayPrimary=distribution(touch.primaryRatios),distribution(relay.primaryRatios)
    local touchReturned,relayReturned=distribution(touch.returnedPrimaryRatios),distribution(relay.returnedPrimaryRatios)
    local touchHead,relayHead=distribution(touch.headRatios),distribution(relay.headRatios)
    local touchReturnedHead,relayReturnedHead=distribution(touch.returnedHeadRatios),distribution(relay.returnedHeadRatios)
    local aggregatePrimaryDiff=relativeDifference(touchPrimary.median,relayPrimary.median)
    local aggregateReturnedDiff=relativeDifference(touchReturned.median,relayReturned.median)
    local aggregateHeadDiff=relativeDifference(touchHead.median,relayHead.median)
    local aggregateReturnedHeadDiff=relativeDifference(touchReturnedHead.median,relayReturnedHead.median)

    local causal="unproved"
    if enough and matched>=2 then
        local aggregateSupported=aggregatePrimaryDiff and aggregateReturnedDiff and aggregateHeadDiff
            and aggregateReturnedHeadDiff and aggregatePrimaryDiff>=0.20 and aggregateReturnedDiff>=0.20
            and aggregateHeadDiff>=0.15 and aggregateReturnedHeadDiff>=0.15
        local aggregateEquivalent=aggregatePrimaryDiff and aggregateReturnedDiff and aggregateHeadDiff
            and aggregateReturnedHeadDiff and aggregatePrimaryDiff<=0.10 and aggregateReturnedDiff<=0.10
            and aggregateHeadDiff<=0.15 and aggregateReturnedHeadDiff<=0.15
        if aggregateSupported and significant>=2 and direction~=99 then
            causal="supported"
        elseif aggregateEquivalent and equivalent==matched then
            causal="not-supported"
        end
    end

    local subjectPrimaryEquivalent=equivalentDistribution(touch.subjectPrimaryDistances,
        relay.subjectPrimaryDistances,0.03,0.02)
    local subjectHeadEquivalent=equivalentDistribution(touch.subjectHeadDistances,
        relay.subjectHeadDistances,0.12,0.12)
    local subjectEquivalent=(subjectPrimaryEquivalent==true and subjectHeadEquivalent==true) and true
        or ((subjectPrimaryEquivalent=="unproved" or subjectHeadEquivalent=="unproved") and "unproved" or false)
    local mouseEquivalent=equivalentDistribution(touch.offsetMagnitudes,relay.offsetMagnitudes,0.01,0.01)
    local focusEquivalent=equivalentDistribution(touch.focusResiduals,relay.focusResiduals,0.01,0.10)

    local firstDifference="none"
    if causal=="supported" then
        firstDifference=string.format("normalized screen projection after Controller.Update; primaryMedianRelativeDiff=%s returnedPrimaryMedianRelativeDiff=%s corroboratingMatchedBuckets=%d direction=%s",
            tostring(round(aggregatePrimaryDiff,5)),tostring(round(aggregateReturnedDiff,5)),significant,
            direction==1 and "relay-higher" or "touch-higher")
    elseif causal=="unproved" then firstDifference="unproved" end
    local nextSuspect=causal=="not-supported"
        and "GetSubjectPosition subject origin -> CameraFocus/orbit reference (not investigated in V612)"
        or (causal=="supported" and "not-applicable: input pipeline caused measured standing drift difference"
            or "unproved: repeat paired standing windows with sufficient matched yaw buckets")

    return {
        standingCriterion=string.format("accepted only after %.2fs stabilization + %d consecutive standing frames; AssemblyLinearVelocity<=%.3f studs/s; frame-to-frame PrimaryPart delta<=max(%.3f,dt*%.3f) studs; MoveDirection<=%.3f; no active V604 joystick identity when available; matching camera route; applied yaw>=%.3fdeg; all four projections on-screen",
            STABILIZE_SECONDS,STABLE_CONSECUTIVE_FRAMES,MAX_LINEAR_VELOCITY,MAX_WORLD_DELTA_FLOOR,
            MAX_LINEAR_VELOCITY,MAX_MOVE_DIRECTION,MIN_APPLIED_YAW_DEG),
        touchStandingSamples=touch.validStandingFrames,
        relayStandingSamples=relay.validStandingFrames,
        standingSampleBalance=string.format("ratio=%.6f minimum=%d maximum=%d requiredRatio=%.2f requiredEach=%d sufficient=%s",
            balance,minimum,maximum,MIN_SAMPLE_BALANCE,MIN_PHASE_SAMPLES,tostring(enough)),
        touchPrimaryPxPerYawDeg=distributionText(touch.primaryRatios),
        relayPrimaryPxPerYawDeg=distributionText(relay.primaryRatios),
        touchHeadPxPerYawDeg=distributionText(touch.headRatios),
        relayHeadPxPerYawDeg=distributionText(relay.headRatios),
        touchReturnedPrimaryPxPerYawDeg=distributionText(touch.returnedPrimaryRatios),
        relayReturnedPrimaryPxPerYawDeg=distributionText(relay.returnedPrimaryRatios),
        touchReturnedHeadPxPerYawDeg=distributionText(touch.returnedHeadRatios),
        relayReturnedHeadPxPerYawDeg=distributionText(relay.returnedHeadRatios),
        yawBucketComparison=buckets,
        subjectGeometryEquivalent=string.format("%s; primaryTouch={%s}; primaryRelay={%s}; headTouch={%s}; headRelay={%s}; meanPositionTouch=%s meanPositionRelay=%s lastTouch=%s lastRelay=%s",
            tostring(subjectEquivalent),distributionText(touch.subjectPrimaryDistances),distributionText(relay.subjectPrimaryDistances),
            distributionText(touch.subjectHeadDistances),distributionText(relay.subjectHeadDistances),
            cleanText(meanSubjectPosition(touch),90),cleanText(meanSubjectPosition(relay),90),
            cleanText(touch.lastSubjectPosition,90),cleanText(relay.lastSubjectPosition,90)),
        mouseLockGeometryEquivalent=tostring(mouseEquivalent).."; touchOffsetMagnitude={"..distributionText(touch.offsetMagnitudes)
            .."}; relayOffsetMagnitude={"..distributionText(relay.offsetMagnitudes).."}",
        focusGeometryEquivalent=tostring(focusEquivalent).."; touchResidual={"..distributionText(touch.focusResiduals)
            .."}; relayResidual={"..distributionText(relay.focusResiduals).."}",
        inputCausalForScreenDrift=causal,
        firstDifferenceIfSupported=firstDifference,
        nextSuspectIfNotSupported=nextSuspect,
        experimentEligible=false,
    }
end

getgenv().PCV612Diagnostics=function()
    local base=baseSafe()
    local decision=classification()
    local frozen=(not probeRunning and stateAtStop) or {
        relay=relayEnabled(),rotate=readRotate(getActiveController()),preferred=UserInputService.PreferredInput,
    }
    local result={
        version="V612-PairedStandingScreenDrift",
        bridgeMode=getgenv().PCInputBridgeMode,
        probePurpose="paired-standing-Touch-vs-V604-relay-screen-drift-causality",
        probeRunning=probeRunning,
        probeFrames=probeFrames,
        probeDuration=round(probeRunning and (os.clock()-probeStartedAt) or probeDuration,3),
        discoveryStatus=discoveryStatus,
        discoveryErrors=table.concat(discoveryErrors," | "),
        horizontalClampMin=horizontalClampMin,
        horizontalClampMax=horizontalClampMax,
        horizontalBoundsSource=horizontalBoundsSource,
        hooksCurrentlyInstalled=#installedHooks,
        hooksInstalledTotal=hooksInstalledTotal,
        hookInstallFailures=hookInstallFailures,
        hookRestoreOk=hookRestoreOk,
        hookRestoreDetail=hookRestoreDetail,
        callbackErrors=callbackErrors,
        controllerErrors=controllerErrors,
        frameCorrelationErrors=frameCorrelationErrors,
        traceDropped=traceDropped,
        evidenceDropped=evidenceDropped,
        handlerCallsTouch=handlerCallsTouch,
        handlerCallsMouseTouch=handlerCallsMouseTouch,
        nonzeroWritesTouch=nonzeroWritesTouch,
        nonzeroWritesRelay=nonzeroWritesRelay,
        calculateCalls=calculateCalls,
        firstCalculateCalls=firstCalculateCalls,
        getCameraLookCallsInCalc=getCameraLookCallsInCalc,
        getSubjectCalls=getSubjectCalls,
        getMouseLockOffsetCalls=getMouseLockOffsetCalls,
        controllerUpdates=controllerUpdates,
        cameraModuleUpdates=cameraModuleUpdates,
        subjectClassSummary=countSummary(subjectClassCounts),
        lastCorrelatedFrame=lastCorrelatedFrame,
        lastSubjectDetail=lastSubjectDetail,
        lastGeometryDetail=lastGeometryDetail,
        lastStandingDetail=lastStandingDetail,
        currentPhase=currentPhase,
        phaseState=phaseState,
        stabilizationSeconds=STABILIZE_SECONDS,
        stableConsecutiveRequired=STABLE_CONSECUTIVE_FRAMES,
        stableConsecutiveCurrent=stableConsecutive,
        persistedOwnershipProofAccepted=persistedOwnershipProofAccepted,
        persistedOwnershipProofPatchCounts=tostring(proofInitCount)..","..tostring(proofStatusCount),
        joystickCriterionAvailable=joystickCriterionAvailable,
        joystickCriterionLast=cachedJoystickDetail,
        relayEnabled=frozen and frozen.relay,
        rotateAtStop=frozen and frozen.rotate,
        preferredInputAtStop=frozen and frozen.preferred,
        ownershipGateProven=base.ownershipGateProven,
        relayValidationReady=base.relayValidationReady,
        touchRoleConflicts=base.touchRoleConflicts,
        joystickMouseCrossovers=base.joystickMouseCrossovers,
        relayErrors=base.relayErrors,
        v604CallbackErrors=base.callbackErrors,
        validationReady=callbackErrors==0 and frameCorrelationErrors==0
            and pairedStats.touch.validStandingFrames>=MIN_PHASE_SAMPLES
            and pairedStats.relay.validStandingFrames>=MIN_PHASE_SAMPLES,
        observationalOnly=true,
        writesCameraCFrame=false,
        writesRootPartCFrame=false,
        writesHeadCFrame=false,
        writesCameraFocus=false,
        altersCameraSubject=false,
        forcesPreferredInput=false,
        forcesMouseBehavior=false,
        forcesRotationType=false,
        forcesAutoRotate=false,
        changesSensitivityGainPhysics=false,
        usesSyntheticUserInputObject=false,
        usesFireSignal=false,
        usesVirtualInput=false,
        preservesV604Ownership=true,
        fallbackV500Preserved=true,
        standingCriterion=decision.standingCriterion,
        touchStandingSamples=decision.touchStandingSamples,
        relayStandingSamples=decision.relayStandingSamples,
        standingSampleBalance=decision.standingSampleBalance,
        touchPrimaryPxPerYawDeg=decision.touchPrimaryPxPerYawDeg,
        relayPrimaryPxPerYawDeg=decision.relayPrimaryPxPerYawDeg,
        touchHeadPxPerYawDeg=decision.touchHeadPxPerYawDeg,
        relayHeadPxPerYawDeg=decision.relayHeadPxPerYawDeg,
        touchReturnedPrimaryPxPerYawDeg=decision.touchReturnedPrimaryPxPerYawDeg,
        relayReturnedPrimaryPxPerYawDeg=decision.relayReturnedPrimaryPxPerYawDeg,
        touchReturnedHeadPxPerYawDeg=decision.touchReturnedHeadPxPerYawDeg,
        relayReturnedHeadPxPerYawDeg=decision.relayReturnedHeadPxPerYawDeg,
        yawBucketComparison=decision.yawBucketComparison,
        subjectGeometryEquivalent=decision.subjectGeometryEquivalent,
        mouseLockGeometryEquivalent=decision.mouseLockGeometryEquivalent,
        focusGeometryEquivalent=decision.focusGeometryEquivalent,
        inputCausalForScreenDrift=decision.inputCausalForScreenDrift,
        firstDifferenceIfSupported=decision.firstDifferenceIfSupported,
        nextSuspectIfNotSupported=decision.nextSuspectIfNotSupported,
        experimentEligible=decision.experimentEligible,
    }
    local names={
        "frames","inputFrames","calcFrames","writeCount","writeXAbs","writeYAbs",
        "maxWritesPerFrame","writeAgeSamples","writeFirstAgeMsMean","writeLastAgeMsMean",
        "requestedCount","requestedXMeanAbs","effectiveXMeanAbs","actualEffectiveXMeanAbs",
        "effectiveRatioCount","effectiveRatioMean","clampFrames","clampRate","clampAmountAbs",
        "clampResidualMean","clampResidualMax","cameraYawAppliedAbsDeg","lookYawAppliedAbsDeg",
        "subjectSamples","subjectPrimaryDistanceMean","subjectHeadDistanceMean","subjectCloserPrimary",
        "subjectCloserHead","subjectEquidistant","offsetSamples","offsetMagnitudeMean",
        "focusResidualMean","focusResidualMax","primaryScreenSamples","primaryDriftPerYawDegree",
        "headScreenSamples","headDriftPerYawDegree","standingPrimarySamples",
        "returnedPrimaryScreenSamples","returnedPrimaryDriftPerYawDegree",
        "returnedHeadScreenSamples","returnedHeadDriftPerYawDegree",
        "returnedStandingPrimarySamples","returnedStandingPrimaryDriftPerYawDegree",
        "returnedStandingHeadSamples","returnedStandingHeadDriftPerYawDegree",
        "standingPrimaryDriftPerYawDegree","standingHeadSamples","standingHeadDriftPerYawDegree",
        "movingPrimarySamples","movingPrimaryDriftPerYawDegree","controllerCameraDistanceMean",
    }
    for phase,stats in pairs(phaseStats) do
        for _,name in ipairs(names) do
            local key=phase..name:sub(1,1):upper()..name:sub(2)
            result[key]=round(phaseValue(stats,name),9)
        end
    end
    for phase,stats in pairs(pairedStats) do
        local prefix=phase.."Paired"
        result[prefix.."ValidStandingFrames"]=stats.validStandingFrames
        result[prefix.."RejectedMovingFrames"]=stats.rejectedMovingFrames
        result[prefix.."RejectedWrongRouteFrames"]=stats.rejectedWrongRouteFrames
        result[prefix.."RejectedLowYawFrames"]=stats.rejectedLowYawFrames
        result[prefix.."RejectedProjectionFrames"]=stats.rejectedProjectionFrames
        result[prefix.."StabilizationFrames"]=stats.stabilizationFrames
        result[prefix.."CameraYawAppliedAbsDeg"]=round(stats.cameraYawAppliedAbsDeg,9)
        result[prefix.."PrimaryScreenDisplacementPx"]=round(stats.primaryDisplacementSum,9)
        result[prefix.."HeadScreenDisplacementPx"]=round(stats.headDisplacementSum,9)
        result[prefix.."ReturnedPrimaryScreenDisplacementPx"]=round(stats.returnedPrimaryDisplacementSum,9)
        result[prefix.."ReturnedHeadScreenDisplacementPx"]=round(stats.returnedHeadDisplacementSum,9)
        result[prefix.."PrimaryScreenDisplacementDistribution"]=distributionText(stats.primaryDisplacements)
        result[prefix.."HeadScreenDisplacementDistribution"]=distributionText(stats.headDisplacements)
        result[prefix.."ReturnedPrimaryScreenDisplacementDistribution"]=distributionText(stats.returnedPrimaryDisplacements)
        result[prefix.."ReturnedHeadScreenDisplacementDistribution"]=distributionText(stats.returnedHeadDisplacements)
        result[prefix.."YawDistribution"]=distributionText(stats.yawDegrees)
        result[prefix.."LinearVelocityDistribution"]=distributionText(stats.linearVelocities)
        result[prefix.."WorldDeltaDistribution"]=distributionText(stats.worldDeltas)
        result[prefix.."MoveDirectionDistribution"]=distributionText(stats.moveDirections)
        result[prefix.."SubjectPositionMean"]=meanSubjectPosition(stats)
        result[prefix.."SubjectPositionLast"]=stats.lastSubjectPosition
        result[prefix.."SubjectPrimaryDistance"]=distributionText(stats.subjectPrimaryDistances)
        result[prefix.."SubjectHeadDistance"]=distributionText(stats.subjectHeadDistances)
        result[prefix.."MouseLockWorldOffsetMagnitude"]=distributionText(stats.offsetMagnitudes)
        result[prefix.."FocusResidual"]=distributionText(stats.focusResiduals)
    end
    return result
end

local REPORT_KEYS={
    "version","bridgeMode","probePurpose","probeRunning","probeFrames","probeDuration","discoveryStatus",
    "discoveryErrors","horizontalClampMin","horizontalClampMax","horizontalBoundsSource",
    "hooksCurrentlyInstalled","hooksInstalledTotal","hookInstallFailures","hookRestoreOk","hookRestoreDetail",
    "callbackErrors","controllerErrors","frameCorrelationErrors","traceDropped","evidenceDropped",
    "handlerCallsTouch","handlerCallsMouseTouch","nonzeroWritesTouch","nonzeroWritesRelay",
    "calculateCalls","firstCalculateCalls","getCameraLookCallsInCalc","getSubjectCalls",
    "getMouseLockOffsetCalls","controllerUpdates","cameraModuleUpdates","subjectClassSummary",
    "lastCorrelatedFrame","lastSubjectDetail","lastGeometryDetail","lastStandingDetail",
    "currentPhase","phaseState","stabilizationSeconds","stableConsecutiveRequired","stableConsecutiveCurrent",
    "persistedOwnershipProofAccepted","persistedOwnershipProofPatchCounts",
    "joystickCriterionAvailable","joystickCriterionLast","relayEnabled","rotateAtStop",
    "preferredInputAtStop","ownershipGateProven","relayValidationReady","touchRoleConflicts",
    "joystickMouseCrossovers","relayErrors","v604CallbackErrors","validationReady","observationalOnly",
    "writesCameraCFrame","writesRootPartCFrame","writesHeadCFrame","writesCameraFocus",
    "altersCameraSubject","forcesPreferredInput","forcesMouseBehavior","forcesRotationType","forcesAutoRotate",
    "changesSensitivityGainPhysics","usesSyntheticUserInputObject","usesFireSignal","usesVirtualInput",
    "preservesV604Ownership","fallbackV500Preserved",
}

local PAIRED_FIELDS={
    "ValidStandingFrames","RejectedMovingFrames","RejectedWrongRouteFrames","RejectedLowYawFrames",
    "RejectedProjectionFrames","StabilizationFrames","CameraYawAppliedAbsDeg",
    "PrimaryScreenDisplacementPx","HeadScreenDisplacementPx",
    "ReturnedPrimaryScreenDisplacementPx","ReturnedHeadScreenDisplacementPx","YawDistribution",
    "PrimaryScreenDisplacementDistribution","HeadScreenDisplacementDistribution",
    "ReturnedPrimaryScreenDisplacementDistribution","ReturnedHeadScreenDisplacementDistribution",
    "LinearVelocityDistribution","WorldDeltaDistribution","MoveDirectionDistribution",
    "SubjectPositionMean","SubjectPositionLast","SubjectPrimaryDistance","SubjectHeadDistance",
    "MouseLockWorldOffsetMagnitude","FocusResidual",
}

local PHASE_FIELDS={
    "Frames","InputFrames","CalcFrames","WriteCount","WriteXAbs","WriteYAbs","RequestedCount",
    "MaxWritesPerFrame","WriteAgeSamples","WriteFirstAgeMsMean","WriteLastAgeMsMean",
    "RequestedXMeanAbs","EffectiveXMeanAbs","ActualEffectiveXMeanAbs","EffectiveRatioCount",
    "EffectiveRatioMean","ClampFrames","ClampRate","ClampAmountAbs","ClampResidualMean","ClampResidualMax",
    "CameraYawAppliedAbsDeg","LookYawAppliedAbsDeg","SubjectSamples","SubjectPrimaryDistanceMean",
    "SubjectHeadDistanceMean","SubjectCloserPrimary","SubjectCloserHead","SubjectEquidistant",
    "OffsetSamples","OffsetMagnitudeMean","FocusResidualMean","FocusResidualMax","PrimaryScreenSamples",
    "PrimaryDriftPerYawDegree","HeadScreenSamples","HeadDriftPerYawDegree","StandingPrimarySamples",
    "ReturnedPrimaryScreenSamples","ReturnedPrimaryDriftPerYawDegree",
    "ReturnedHeadScreenSamples","ReturnedHeadDriftPerYawDegree",
    "ReturnedStandingPrimarySamples","ReturnedStandingPrimaryDriftPerYawDegree",
    "ReturnedStandingHeadSamples","ReturnedStandingHeadDriftPerYawDegree",
    "StandingPrimaryDriftPerYawDegree","StandingHeadSamples","StandingHeadDriftPerYawDegree",
    "MovingPrimarySamples","MovingPrimaryDriftPerYawDegree","ControllerCameraDistanceMean",
}

getgenv().PCV612Report=function(includeEvidence)
    local diagnostics=getgenv().PCV612Diagnostics()
    local lines={"=== PC MOVEMENT V612 REPORT ==="}
    for _,key in ipairs(REPORT_KEYS) do lines[#lines+1]=key.." = "..tostring(diagnostics[key]) end
    for _,phase in ipairs({"touch","relay"}) do
        for _,field in ipairs(PHASE_FIELDS) do
            local key=phase..field
            lines[#lines+1]=key.." = "..tostring(diagnostics[key])
        end
        for _,field in ipairs(PAIRED_FIELDS) do
            local key=phase.."Paired"..field
            lines[#lines+1]=key.." = "..tostring(diagnostics[key])
        end
    end
    if includeEvidence~=false then
        lines[#lines+1]=""
        lines[#lines+1]="=== V612 PAIRED STANDING TRACE ==="
        for _,line in ipairs(traceLines) do lines[#lines+1]=line end
        lines[#lines+1]=""
        lines[#lines+1]="=== V612 FOCUSED TARGET EVIDENCE ==="
        for _,line in ipairs(evidence) do lines[#lines+1]=line end
        if type(baseReport)=="function" then
            local ok,text=pcall(baseReport,false)
            if ok then lines[#lines+1]=""; lines[#lines+1]=text end
        end
    end
    lines[#lines+1]=""
    lines[#lines+1]="=== V612 REQUIRED PAIRED DECISION ==="
    lines[#lines+1]="standingCriterion = "..tostring(diagnostics.standingCriterion)
    lines[#lines+1]="touchStandingSamples = "..tostring(diagnostics.touchStandingSamples)
    lines[#lines+1]="relayStandingSamples = "..tostring(diagnostics.relayStandingSamples)
    lines[#lines+1]="standingSampleBalance = "..tostring(diagnostics.standingSampleBalance)
    lines[#lines+1]="touchPrimaryPxPerYawDeg = "..tostring(diagnostics.touchPrimaryPxPerYawDeg)
    lines[#lines+1]="relayPrimaryPxPerYawDeg = "..tostring(diagnostics.relayPrimaryPxPerYawDeg)
    lines[#lines+1]="touchHeadPxPerYawDeg = "..tostring(diagnostics.touchHeadPxPerYawDeg)
    lines[#lines+1]="relayHeadPxPerYawDeg = "..tostring(diagnostics.relayHeadPxPerYawDeg)
    lines[#lines+1]="touchReturnedPrimaryPxPerYawDeg = "..tostring(diagnostics.touchReturnedPrimaryPxPerYawDeg)
    lines[#lines+1]="relayReturnedPrimaryPxPerYawDeg = "..tostring(diagnostics.relayReturnedPrimaryPxPerYawDeg)
    lines[#lines+1]="yawBucketComparison = "..tostring(diagnostics.yawBucketComparison)
    lines[#lines+1]="subjectGeometryEquivalent = "..tostring(diagnostics.subjectGeometryEquivalent)
    lines[#lines+1]="mouseLockGeometryEquivalent = "..tostring(diagnostics.mouseLockGeometryEquivalent)
    lines[#lines+1]="focusGeometryEquivalent = "..tostring(diagnostics.focusGeometryEquivalent)
    lines[#lines+1]="inputCausalForScreenDrift = "..tostring(diagnostics.inputCausalForScreenDrift)
    lines[#lines+1]="firstDifferenceIfSupported = "..tostring(diagnostics.firstDifferenceIfSupported)
    lines[#lines+1]="nextSuspectIfNotSupported = "..tostring(diagnostics.nextSuspectIfNotSupported)
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
    button.LayoutOrder=order; button.Size=UDim2.new(1,0,0,31); button.BackgroundColor3=color
    button.BorderSizePixel=0; button.Text=text; button.TextColor3=Color3.new(1,1,1)
    button.TextSize=12; button.TextWrapped=true; button.Font=Enum.Font.GothamBold; button.Parent=parent
    local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(0,8); corner.Parent=button
    return button
end

local function refreshPhaseButtons()
    if phaseAButton then
        phaseAButton.BackgroundColor3=currentPhase=="touch" and Color3.fromRGB(14,165,233) or Color3.fromRGB(30,64,175)
        phaseAButton.Text="FASE A • TOUCH PARADO"..(currentPhase=="touch" and " • ATUAL" or "")
    end
    if phaseBButton then
        phaseBButton.BackgroundColor3=currentPhase=="relay" and Color3.fromRGB(168,85,247) or Color3.fromRGB(107,33,168)
        phaseBButton.Text="FASE B • RELAY PARADO"..(currentPhase=="relay" and " • ATUAL" or "")
    end
end

refreshLiveStatus=function()
    if not statusLabel then return end
    local a,b=pairedStats.touch,pairedStats.relay
    local relayText=relayEnabled() and "ON" or "OFF"
    local stateText=phaseState
    if phaseState=="stabilizing" or phaseState=="restabilizing" then
        local remaining=math.max(0,phaseStabilizeUntil-os.clock())
        stateText=string.format("%s %.1fs • estável %d/%d",phaseState,remaining,stableConsecutive,STABLE_CONSECUTIVE_FRAMES)
    end
    statusLabel.Text=string.format("fase=%s • %s • relay=%s\nA válidas=%d rejeitadas=%d | B válidas=%d rejeitadas=%d",
        currentPhase,stateText,relayText,a.validStandingFrames,a.rejectedMovingFrames,
        b.validStandingFrames,b.rejectedMovingFrames)
    statusLabel.TextColor3=phaseState=="active" and Color3.fromRGB(74,222,128) or Color3.fromRGB(250,204,21)
    refreshPhaseButtons()
end

local function createPanel()
    local parent=CoreGui
    pcall(function() if gethui then parent=gethui() end end)
    if not parent then return end
    local old=parent:FindFirstChild(UI_NAME)
    if old then old:Destroy() end
    local gui=Instance.new("ScreenGui")
    gui.Name=UI_NAME; gui.ResetOnSpawn=false; gui.DisplayOrder=999999; gui.Parent=parent; screenGui=gui

    local panel=Instance.new("Frame")
    panel.Size=UDim2.fromOffset(320,404); panel.Position=UDim2.new(1,-332,0.5,-202)
    panel.BackgroundColor3=Color3.fromRGB(9,14,27); panel.BackgroundTransparency=0.04
    panel.BorderSizePixel=0; panel.Active=true; panel.Draggable=true; panel.Parent=gui
    local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(0,14); corner.Parent=panel
    local stroke=Instance.new("UIStroke"); stroke.Color=Color3.fromRGB(34,211,238); stroke.Thickness=1.5; stroke.Parent=panel

    local title=Instance.new("TextLabel")
    title.Size=UDim2.new(1,-48,0,34); title.Position=UDim2.fromOffset(13,7); title.BackgroundTransparency=1
    title.Text="V612 • STANDING PAREADO"; title.TextColor3=Color3.fromRGB(103,232,249)
    title.TextSize=15; title.Font=Enum.Font.GothamBold; title.TextXAlignment=Enum.TextXAlignment.Left; title.Parent=panel

    local collapse=Instance.new("TextButton")
    collapse.Size=UDim2.fromOffset(30,30); collapse.Position=UDim2.new(1,-38,0,7)
    collapse.BackgroundColor3=Color3.fromRGB(30,41,59); collapse.BorderSizePixel=0
    collapse.Text="–"; collapse.TextColor3=Color3.new(1,1,1); collapse.TextSize=20
    collapse.Font=Enum.Font.GothamBold; collapse.Parent=panel
    local collapseCorner=Instance.new("UICorner"); collapseCorner.CornerRadius=UDim.new(0,8); collapseCorner.Parent=collapse

    local body=Instance.new("Frame")
    body.Size=UDim2.new(1,-24,1,-48); body.Position=UDim2.fromOffset(12,42); body.BackgroundTransparency=1; body.Parent=panel
    local layout=Instance.new("UIListLayout"); layout.Padding=UDim.new(0,4); layout.SortOrder=Enum.SortOrder.LayoutOrder; layout.Parent=body

    local instructions=Instance.new("TextLabel")
    instructions.LayoutOrder=0; instructions.Size=UDim2.new(1,0,0,72)
    instructions.BackgroundColor3=Color3.fromRGB(18,28,48); instructions.BorderSizePixel=0
    instructions.Text="1) INICIAR → FASE A; fique parado e só gire ~15 s\n2) Toque FASE B; continue parado e repita ~15 s\n3) Aguarde COLETA ATIVA em cada fase\n4) PARAR → COPIAR antes de sair"
    instructions.TextColor3=Color3.fromRGB(226,232,240); instructions.TextSize=11
    instructions.TextWrapped=true; instructions.TextXAlignment=Enum.TextXAlignment.Left
    instructions.Font=Enum.Font.Gotham; instructions.Parent=body
    local instructionCorner=Instance.new("UICorner"); instructionCorner.CornerRadius=UDim.new(0,8); instructionCorner.Parent=instructions

    local start=makeButton(body,"INICIAR",Color3.fromRGB(34,197,94),1)
    phaseAButton=makeButton(body,"FASE A • TOUCH PARADO",Color3.fromRGB(30,64,175),2)
    phaseBButton=makeButton(body,"FASE B • RELAY PARADO",Color3.fromRGB(107,33,168),3)
    local stop=makeButton(body,"PARAR",Color3.fromRGB(245,158,11),4)
    local emergency=makeButton(body,"EMERGÊNCIA • RELAY OFF / V500",Color3.fromRGB(190,24,93),5)
    local copy=makeButton(body,"COPIAR REPORT COMPLETO",Color3.fromRGB(2,132,199),6)
    statusLabel=Instance.new("TextLabel")
    statusLabel.LayoutOrder=7; statusLabel.Size=UDim2.new(1,0,0,54); statusLabel.BackgroundTransparency=1
    statusLabel.Text="Pronto. INICIAR e depois FASE A."; statusLabel.TextColor3=Color3.fromRGB(148,163,184)
    statusLabel.TextSize=10; statusLabel.TextWrapped=true; statusLabel.Font=Enum.Font.Gotham; statusLabel.Parent=body

    uiConnections[#uiConnections+1]=start.Activated:Connect(function()
        local ok=startProbe()
        setStatus(ok and "Probe ativa. Agora toque FASE A." or "Falha ao iniciar hooks.",
            ok and Color3.fromRGB(74,222,128) or Color3.fromRGB(251,113,133))
    end)
    uiConnections[#uiConnections+1]=phaseAButton.Activated:Connect(function()
        local ok,detail=beginControlledPhase("touch")
        setStatus(ok and "FASE A estabilizando. Não ande; espere COLETA ATIVA." or "FASE A recusada: "..cleanText(detail,90),
            ok and Color3.fromRGB(250,204,21) or Color3.fromRGB(251,113,133))
        refreshPhaseButtons()
    end)
    uiConnections[#uiConnections+1]=phaseBButton.Activated:Connect(function()
        local ok,detail=beginControlledPhase("relay")
        setStatus(ok and "FASE B estabilizando. Não ande; espere COLETA ATIVA." or "FASE B recusada: "..cleanText(detail,90),
            ok and Color3.fromRGB(250,204,21) or Color3.fromRGB(251,113,133))
        refreshPhaseButtons()
    end)
    uiConnections[#uiConnections+1]=stop.Activated:Connect(function()
        stopProbe(); setStatus("Parado; hooks restaurados. Agora copie.",Color3.fromRGB(250,204,21))
    end)
    uiConnections[#uiConnections+1]=emergency.Activated:Connect(function()
        stopProbe()
        if type(baseSetRelay)=="function" then pcall(baseSetRelay,false) end
        refreshPhaseButtons(); setStatus("Emergência: relay OFF; V500 ativo.",Color3.fromRGB(251,113,133))
    end)
    uiConnections[#uiConnections+1]=copy.Activated:Connect(function()
        stopProbe()
        local ok=copyToClipboard(getgenv().PCV612Report(true))
        setStatus(ok and "REPORT COPIADO. Agora pode sair e colar." or "Clipboard indisponível no Delta.",
            ok and Color3.fromRGB(74,222,128) or Color3.fromRGB(251,113,133))
    end)
    local expanded=true
    uiConnections[#uiConnections+1]=collapse.Activated:Connect(function()
        expanded=not expanded; body.Visible=expanded
        panel.Size=expanded and UDim2.fromOffset(320,404) or UDim2.fromOffset(320,45)
        collapse.Text=expanded and "–" or "+"
    end)
    refreshPhaseButtons()
end

local discoverOk,discoverError=pcall(discoverFocusedChain)
if not discoverOk then discoveryStatus="error:"..cleanText(discoverError,180); addEvidence("DISCOVERY",discoveryStatus) end
local hookOk,hookError=pcall(installFocusedHooks)
if not hookOk then addEvidence("HOOK","installation-error="..cleanText(hookError,180)) end
local uiOk,uiError=pcall(createPanel)
if not uiOk then addEvidence("UI","creation-error="..cleanText(uiError,180)) end

getgenv().PCV612Start=startProbe
getgenv().PCV612PhaseA=function() return beginControlledPhase("touch") end
getgenv().PCV612PhaseB=function() return beginControlledPhase("relay") end
getgenv().PCV612Stop=function() stopProbe(); return getgenv().PCV612Report(false) end
getgenv().PCV612EmergencyV500=function()
    stopProbe()
    if type(baseSetRelay)=="function" then pcall(baseSetRelay,false) end
    refreshPhaseButtons()
    return true,"relay-disabled-v500-active"
end

getgenv().__PCMobileAimCleanup=function()
    probeRunning=false; currentFrame=nil; currentCalc=nil
    for _,connection in ipairs(uiConnections) do pcall(function() connection:Disconnect() end) end
    uiConnections={}
    if screenGui then pcall(function() screenGui:Destroy() end) end
    screenGui=nil
    restoreHooks()
    getgenv().PCV612Start=nil
    getgenv().PCV612PhaseA=nil
    getgenv().PCV612PhaseB=nil
    getgenv().PCV612Stop=nil
    getgenv().PCV612EmergencyV500=nil
    getgenv().PCV612Diagnostics=nil
    getgenv().PCV612Report=nil
    if baseCleanup then pcall(baseCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

addEvidence("READY","V612 paired standing Touch-vs-relay control ready; observational geometry only")
warn("[V612] paired standing screen-drift control ready | use mobile panel")
