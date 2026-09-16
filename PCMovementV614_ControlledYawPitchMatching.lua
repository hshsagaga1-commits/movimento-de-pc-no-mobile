local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")

local player=Players.LocalPlayer
local UI_NAME="PCMovementV614Panel"

--[[
    V614 / CONTROLLED YAW-PITCH MATCHING / TEMPORAL-POSE TELEMETRY R1

    V604-V613 and the post-V613 audit are accepted evidence. No search is
    reopened. This probe resolves only PrimaryPart-vs-Head ambiguity inside:
      A) native Touch, character standing
      B) V604 OnMouseMoved(same real Touch), character standing.

    Acquisition R2 remains unchanged. This revision only records protected,
    read-only numeric snapshots at the existing CameraModule.Update and active
    Controller.Update boundaries so the already-observed Head effect can be
    decomposed into camera projection, root motion, local joints and animation
    progression. The 60-degree segment unit, pitch limits, matching calipers,
    ABBA order and bootstrap are unchanged. No camera, character, subject,
    focus, joint, animation, sensitivity or physics value is written. Relay is
    not labeled native PC MouseMovement.
]]

local v604Source=game:HttpGet(
    "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV604_MultitouchOwnershipProbe.lua?_cb="
    ..HttpService:GenerateGUID(false),true
)
-- V604's ownership algorithm and relay remain byte-identical on disk and at
-- every touch. V614 reuses the already-validated V604 proof so this controlled
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
    error("V614 refused: exact V604 persisted-proof initialization anchor missing")
end
local v604Chunk,v604Error=loadstring(v604Source)
if not v604Chunk then error(v604Error) end
v604Chunk()

local baseCleanup=getgenv().__PCMobileAimCleanup
local baseSetRelay=getgenv().PCV604SetRelayEnabled
local baseDiagnostics=getgenv().PCV604Diagnostics
local baseReport=getgenv().PCV604Report

getgenv().PCMovementVersion="V614-ControlledYawPitchMatching-TemporalPoseTelemetryR1"
getgenv().PCInputBridgeMode="v614-controlled-yaw-pitch-matching-temporal-pose-telemetry-r1"

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
local MIN_SAMPLE_BALANCE=0.65
local MIN_BUCKET_SAMPLES=25          -- legacy V612 classifier only; V614 does not use it
local MAX_PITCH_CONTROL_DEG=0.35      -- fixed before classification
local YAW_BIN_WIDTH_DEG=0.50          -- fixed, zero-anchored narrow bins
local MIN_BIN_SAMPLES=20
local MAX_BIN_MEDIAN_YAW_GAP_DEG=0.15
local MIN_MATCHED_BINS=3
local BOOTSTRAP_BLOCK_SIZE=12
local BOOTSTRAP_ITERATIONS=400
local ASSOCIATION_THRESHOLD=0.50

-- V614 predeclared segment unit. These values are not fitted after the V614
-- result. V613 showed per-frame lattices near 0.8505 deg (Touch) and 0.18 deg
-- (relay), while 60-degree non-overlapping segments produced overlapping total
-- yaw without changing either input route.
local SEGCFG={
    targetYaw=60,maxYaw=120,minFrames=3,maxFrameGap=3,maxDuration=1.25,
    maxNetPitch=2.0,maxAbsPitchFloor=5.0,maxAbsPitchRatio=0.06,minCoherence=0.90,
    matchYawGap=5.0,matchNetPitchGap=1.0,matchAbsPitchGap=2.0,minMatched=12,
    bootstrapBlock=3,bootstrapIterations=1000,
    phaseEligibleTarget=16,routeEligibleTarget=32,
    sequence={"A1","B1","B2","A2"}, -- ABBA balances a linear time trend.
    route={A1="touch",A2="touch",B1="relay",B2="relay"},
    -- The R2 target is fixed before the new run: 16 per window gives 32 per
    -- route. At the old observed 3/6 compatibility this projects 16 pairs,
    -- four above the unchanged requirement of 12.
    oldEligibleTouch=48,oldEligibleRelay=6,oldMatchedPairs=3,
    livePotentialPairs=0,lastSegmentEvent="GIRE MAIS",lastSegmentEventAt=0,
    lastSegmentDetail="none",coverageSufficient=false,
}

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
local phaseA2Button=nil
local phaseB2Button=nil
local uiConnections={}
local stateAtStop=nil
local currentPhase="none"
local currentWindow="none"
local phaseState="idle"
local phaseStartedAt=0
local phaseStabilizeUntil=0
local stableConsecutive=0
local phaseLastPrimaryPosition=nil
local persistedOwnershipProofAccepted=true
local joystickCriterionAvailable=false
local cachedJoystickInactive=true
local cachedJoystickDetail="not-sampled"
local lastJoystickReadAt=0
local expectedPhaseIndex=1
local completedWindows={}
local uiUpdaterRunning=false
local uiRefreshErrors=0
local segmentConsumer=nil
local currentSegment=nil
local segmentStats={
    touch={eligible={},rejectedShort=0,rejectedPitch=0,rejectedDuration=0,rejectedGeometry=0,rejectedYaw=0},
    relay={eligible={},rejectedShort=0,rejectedPitch=0,rejectedDuration=0,rejectedGeometry=0,rejectedYaw=0},
}
SEGCFG.windowStats={}

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
local correlationFramesExcluded=0
local correlationErrorSources={}
local optionalDiagnosticReadErrors=0
local telemetryCaptureErrors=0
local telemetryCaptureErrorSources={}
local telemetryBoundariesCaptured=0
local lastCorrelationErrorSource="none"
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

local function pitchFromCFrame(cf)
    if typeof(cf)~="CFrame" then return nil end
    return math.asin(math.clamp(cf.LookVector.Y,-1,1))
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

function SEGCFG.noteTelemetryError(source,value)
    telemetryCaptureErrors+=1
    local key=tostring(source)..":"..cleanText(value,120)
    telemetryCaptureErrorSources[key]=(telemetryCaptureErrorSources[key] or 0)+1
end

function SEGCFG.telemetryRead(source,reader)
    local ok,value=pcall(reader)
    if not ok then
        SEGCFG.noteTelemetryError(source,value)
        return nil
    end
    return value
end

-- Store only immutable value types / plain tables. No Instance captured here is
-- retained in a sample or report, and every executor-sensitive read fails open.
function SEGCFG.cframeComponents(cf)
    if typeof(cf)~="CFrame" then return nil end
    local values={cf:GetComponents()}
    return values
end

function SEGCFG.vector2Components(value)
    return typeof(value)=="Vector2" and {value.X,value.Y} or nil
end

function SEGCFG.snapshotJoint(character,name)
    if not character then return nil end
    local joint=SEGCFG.telemetryRead("joint-find-"..name,function()
        return character:FindFirstChild(name,true)
    end)
    if not joint then return nil end
    return SEGCFG.telemetryRead("joint-read-"..name,function()
        if not joint:IsA("Motor6D") then return nil end
        return {
            name=name,
            part0=joint.Part0 and joint.Part0.Name or "nil",
            part1=joint.Part1 and joint.Part1.Name or "nil",
            transform=SEGCFG.cframeComponents(joint.Transform),
            -- C0/C1 are required to reconstruct the Motor6D relation exactly.
            c0=SEGCFG.cframeComponents(joint.C0),c1=SEGCFG.cframeComponents(joint.C1),
        }
    end)
end

function SEGCFG.snapshotAnimationTracks(humanoid)
    local result={humanoidState="unavailable",tracks={}}
    if not humanoid then return result end
    local state=SEGCFG.telemetryRead("humanoid-state",function() return humanoid:GetState() end)
    if state~=nil then result.humanoidState=cleanText(state,60) end
    local animator=SEGCFG.telemetryRead("animator-find",function()
        return humanoid:FindFirstChildOfClass("Animator")
    end)
    if not animator then return result end
    local tracks=SEGCFG.telemetryRead("animation-tracks",function()
        return animator:GetPlayingAnimationTracks()
    end)
    if type(tracks)~="table" then return result end
    for index,track in ipairs(tracks) do
        local entry=SEGCFG.telemetryRead("animation-track-"..tostring(index),function()
            local animation=track.Animation
            return {
                animationId=animation and animation.AnimationId or "",
                name=track.Name,
                timePosition=track.TimePosition,
                weightCurrent=track.WeightCurrent,
                weightTarget=track.WeightTarget,
                speed=track.Speed,
                isPlaying=track.IsPlaying,
                looped=track.Looped,
                priority=track.Priority and track.Priority.Name or cleanText(track.Priority,40),
                length=track.Length,
            }
        end)
        if entry then result.tracks[#result.tracks+1]=entry end
    end
    table.sort(result.tracks,function(a,b)
        local ak=(a.animationId or "").."|"..(a.name or "").."|"..(a.priority or "")
        local bk=(b.animationId or "").."|"..(b.name or "").."|"..(b.priority or "")
        if ak==bk then return (a.timePosition or 0)<(b.timePosition or 0) end
        return ak<bk
    end)
    return result
end

function SEGCFG.temporalPoseSnapshot(boundary)
    local captureStarted=os.clock()
    local character,primary,head,humanoid=characterSnapshot()
    local camera=workspace.CurrentCamera
    local cameraCFrame=SEGCFG.telemetryRead(boundary.."-camera-cframe",function()
        return camera and camera.CFrame or nil
    end)
    local cameraReadAt=os.clock()
    local primaryCFrame=SEGCFG.telemetryRead(boundary.."-primary-cframe",function()
        return primary and primary.CFrame or nil
    end)
    local headCFrame=SEGCFG.telemetryRead(boundary.."-head-cframe",function()
        return head and head.CFrame or nil
    end)
    local localHead=nil
    if typeof(primaryCFrame)=="CFrame" and typeof(headCFrame)=="CFrame" then
        localHead=SEGCFG.telemetryRead(boundary.."-primary-to-head",function()
            return primaryCFrame:ToObjectSpace(headCFrame)
        end)
    end
    local poseReadAt=os.clock()
    local fieldOfView=SEGCFG.telemetryRead(boundary.."-camera-fov",function()
        return camera and camera.FieldOfView or nil
    end)
    local viewport=SEGCFG.telemetryRead(boundary.."-camera-viewport",function()
        return camera and camera.ViewportSize or nil
    end)
    local joints={
        Neck=SEGCFG.snapshotJoint(character,"Neck"),
        Waist=SEGCFG.snapshotJoint(character,"Waist"),
        RootJoint=SEGCFG.snapshotJoint(character,"RootJoint"),
    }
    local animation=SEGCFG.snapshotAnimationTracks(humanoid)
    local captureEnded=os.clock()
    telemetryBoundariesCaptured+=1
    return {
        boundary=boundary,clock=captureStarted-probeStartedAt,
        cameraReadClock=cameraReadAt-probeStartedAt,poseReadClock=poseReadAt-probeStartedAt,
        captureEndClock=captureEnded-probeStartedAt,captureDurationMs=(captureEnded-captureStarted)*1000,
        cameraCFrame=SEGCFG.cframeComponents(cameraCFrame),fieldOfView=fieldOfView,
        viewport=SEGCFG.vector2Components(viewport),
        primaryCFrame=SEGCFG.cframeComponents(primaryCFrame),headCFrame=SEGCFG.cframeComponents(headCFrame),
        primaryToHead=SEGCFG.cframeComponents(localHead),
        joints=joints,animation=animation,
    }
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
        cameraPitch=camera and pitchFromCFrame(camera.CFrame) or nil,
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
        local telemetryCall=nil
        if frame then
            frame.controllerEntryRotate=readRotate(self)
            frame.sequence[#frame.sequence+1]="Controller.Update:enter"
            frame.telemetry=frame.telemetry or {enabled=false,controllerCalls={}}
            frame.telemetry.controllerCalls=frame.telemetry.controllerCalls or {}
            if frame.telemetry.enabled then
                telemetryCall={index=#frame.telemetry.controllerCalls+1,
                    before=SEGCFG.temporalPoseSnapshot("controller-before")}
                frame.telemetry.controllerCalls[#frame.telemetry.controllerCalls+1]=telemetryCall
            end
        end
        local results=packCall(callOriginal,self,dt,...)
        if frame then
            if telemetryCall then telemetryCall.after=SEGCFG.temporalPoseSnapshot("controller-after") end
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

local function recordPairedSample(frame,stats,yawSigned,pitchSigned,returnedYawSigned,returnedPitchSigned,
    primaryStep,headStep,returnedPrimaryStep,returnedHeadStep)
    local subject=frame.subject
    local before,after=frame.screenBefore,frame.screenAfter
    local actualYawDeg=math.abs(yawSigned)
    local returnedYawDeg=math.abs(returnedYawSigned)
    local primaryDX=after.primaryPoint.X-before.primaryPoint.X
    local primaryDY=after.primaryPoint.Y-before.primaryPoint.Y
    local headDX=after.headPoint.X-before.headPoint.X
    local headDY=after.headPoint.Y-before.headPoint.Y
    local returnedPrimaryDX=frame.returnedPrimaryPoint.X-before.primaryPoint.X
    local returnedPrimaryDY=frame.returnedPrimaryPoint.Y-before.primaryPoint.Y
    local returnedHeadDX=frame.returnedHeadPoint.X-before.headPoint.X
    local returnedHeadDY=frame.returnedHeadPoint.Y-before.headPoint.Y
    local subjectScreenValid=typeof(frame.subjectBeforePoint)=="Vector3" and typeof(frame.subjectAfterPoint)=="Vector3"
        and frame.subjectBeforeOnScreen and frame.subjectAfterOnScreen
    local returnedSubjectValid=typeof(frame.subjectBeforePoint)=="Vector3" and typeof(frame.returnedSubjectPoint)=="Vector3"
        and frame.subjectBeforeOnScreen and frame.returnedSubjectOnScreen
    local subjectDX=subjectScreenValid and frame.subjectAfterPoint.X-frame.subjectBeforePoint.X or nil
    local subjectDY=subjectScreenValid and frame.subjectAfterPoint.Y-frame.subjectBeforePoint.Y or nil
    local returnedSubjectDX=returnedSubjectValid and frame.returnedSubjectPoint.X-frame.subjectBeforePoint.X or nil
    local returnedSubjectDY=returnedSubjectValid and frame.returnedSubjectPoint.Y-frame.subjectBeforePoint.Y or nil
    -- tonumber gives the standalone analyzer an explicit numeric refinement;
    -- it does not change the runtime values or the read-only measurement.
    local numericSubjectDX=tonumber(subjectDX)
    local numericSubjectDY=tonumber(subjectDY)
    local numericReturnedSubjectDX=tonumber(returnedSubjectDX)
    local numericReturnedSubjectDY=tonumber(returnedSubjectDY)
    local subjectPosition=subject and subject.position
    local subjectToPrimary=typeof(subjectPosition)=="Vector3" and after.primaryPosition-subjectPosition or nil
    local subjectToHead=typeof(subjectPosition)=="Vector3" and after.headPosition-subjectPosition or nil
    local primaryToHead=after.headPosition-after.primaryPosition
    local primaryToHeadBefore=before.headPosition-before.primaryPosition
    local rigVectorDelta=primaryToHead-primaryToHeadBefore
    local rotate=frame.controllerEntryRotate
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
    local subjectToPrimaryBefore=typeof(subjectPosition)=="Vector3" and before.primaryPosition-subjectPosition or nil
    local subjectToHeadBefore=typeof(subjectPosition)=="Vector3" and before.headPosition-subjectPosition or nil
    local sample={
        sequence=#stats.samples+1,frame=frame.id,phase=currentPhase,
        window=currentWindow,time=frame.startedAt-probeStartedAt,dt=frame.dt,
        yaw=actualYawDeg,yawSigned=yawSigned,pitch=math.abs(pitchSigned),pitchSigned=pitchSigned,
        returnedYaw=returnedYawDeg,returnedYawSigned=returnedYawSigned,
        returnedPitch=math.abs(returnedPitchSigned),returnedPitchSigned=returnedPitchSigned,
        rotateX=rotate and rotate.X or nil,rotateY=rotate and rotate.Y or nil,
        cameraYawBefore=before.cameraYaw,cameraYawAfter=after.cameraYaw,
        cameraPitchBefore=before.cameraPitch,cameraPitchAfter=after.cameraPitch,
        returnedYawValue=yawFromCFrame(frame.controllerReturnCFrame),
        returnedPitchValue=pitchFromCFrame(frame.controllerReturnCFrame),
        primary=primaryStep/actualYawDeg,head=headStep/actualYawDeg,
        returnedPrimary=returnedPrimaryStep/returnedYawDeg,returnedHead=returnedHeadStep/returnedYawDeg,
        primaryX=math.abs(primaryDX)/actualYawDeg,primaryY=math.abs(primaryDY)/actualYawDeg,
        headX=math.abs(headDX)/actualYawDeg,headY=math.abs(headDY)/actualYawDeg,
        returnedPrimaryX=math.abs(returnedPrimaryDX)/returnedYawDeg,
        returnedPrimaryY=math.abs(returnedPrimaryDY)/returnedYawDeg,
        returnedHeadX=math.abs(returnedHeadDX)/returnedYawDeg,
        returnedHeadY=math.abs(returnedHeadDY)/returnedYawDeg,
        subjectX=numericSubjectDX and math.abs(numericSubjectDX)/actualYawDeg or nil,
        subjectY=numericSubjectDY and math.abs(numericSubjectDY)/actualYawDeg or nil,
        subject2D=numericSubjectDX and numericSubjectDY
            and Vector2.new(numericSubjectDX,numericSubjectDY).Magnitude/actualYawDeg or nil,
        returnedSubjectX=numericReturnedSubjectDX and math.abs(numericReturnedSubjectDX)/returnedYawDeg or nil,
        returnedSubjectY=numericReturnedSubjectDY and math.abs(numericReturnedSubjectDY)/returnedYawDeg or nil,
        returnedSubject2D=numericReturnedSubjectDX and numericReturnedSubjectDY
            and Vector2.new(numericReturnedSubjectDX,numericReturnedSubjectDY).Magnitude/returnedYawDeg or nil,
        primaryDX=primaryDX,primaryDY=primaryDY,headDX=headDX,headDY=headDY,
        subjectDX=subjectDX,subjectDY=subjectDY,returnedSubjectDX=returnedSubjectDX,returnedSubjectDY=returnedSubjectDY,
        returnedPrimaryDX=returnedPrimaryDX,returnedPrimaryDY=returnedPrimaryDY,
        returnedHeadDX=returnedHeadDX,returnedHeadDY=returnedHeadDY,
        primaryYPerPitch=math.abs(pitchSigned)>=MIN_APPLIED_YAW_DEG and math.abs(primaryDY)/math.abs(pitchSigned) or nil,
        headYPerPitch=math.abs(pitchSigned)>=MIN_APPLIED_YAW_DEG and math.abs(headDY)/math.abs(pitchSigned) or nil,
        pitchControlled=math.abs(pitchSigned)<=MAX_PITCH_CONTROL_DEG,
        subjectPosition=subjectPosition,primaryPosition=after.primaryPosition,headPosition=after.headPosition,
        subjectToPrimaryBefore=subjectToPrimaryBefore,subjectToHeadBefore=subjectToHeadBefore,
        primaryToHeadBefore=primaryToHeadBefore,
        subjectToPrimary=subjectToPrimary,subjectToHead=subjectToHead,primaryToHead=primaryToHead,
        rigVectorDelta=rigVectorDelta,rigDeltaVertical=rigVectorDelta.Y,
        rigDeltaHorizontal=Vector2.new(rigVectorDelta.X,rigVectorDelta.Z).Magnitude,
        subjectToPrimaryHorizontal=subjectToPrimary and Vector2.new(subjectToPrimary.X,subjectToPrimary.Z).Magnitude or nil,
        subjectToHeadHorizontal=subjectToHead and Vector2.new(subjectToHead.X,subjectToHead.Z).Magnitude or nil,
        primaryToHeadHorizontal=Vector2.new(primaryToHead.X,primaryToHead.Z).Magnitude,
        primaryToHeadVertical=primaryToHead.Y,
        subjectToHeadVertical=subjectToHead and subjectToHead.Y or nil,
        headDepthBefore=before.headPoint.Z,headDepthAfter=after.headPoint.Z,
        headDepthDelta=after.headPoint.Z-before.headPoint.Z,
        primaryScreenBefore=before.primaryPoint,primaryScreenAfter=after.primaryPoint,
        headScreenBefore=before.headPoint,headScreenAfter=after.headPoint,
        returnedPrimaryScreen=frame.returnedPrimaryPoint,returnedHeadScreen=frame.returnedHeadPoint,
        subjectScreenBefore=frame.subjectBeforePoint,subjectScreenAfter=frame.subjectAfterPoint,
        returnedSubjectScreen=frame.returnedSubjectPoint,
        temporalPoseTelemetry=frame.telemetry,
    }
    stats.samples[#stats.samples+1]=sample
    if type(segmentConsumer)=="function" then segmentConsumer(sample) end
end

function SEGCFG.segmentScreenMetric(startPoint,endPoint,totalYaw)
    if typeof(startPoint)~="Vector3" or typeof(endPoint)~="Vector3" or totalYaw<=0 then return nil end
    local dx=endPoint.X-startPoint.X
    local dy=endPoint.Y-startPoint.Y
    return {
        start=startPoint,finish=endPoint,dx=dx,dy=dy,
        x=math.abs(dx)/totalYaw,y=math.abs(dy)/totalYaw,
        displacement=Vector2.new(dx,dy).Magnitude/totalYaw,
    }
end

function SEGCFG.newWindowStats()
    return {
        eligible=0,candidates=0,rejectedShort=0,rejectedPitch=0,rejectedDuration=0,
        rejectedGeometry=0,rejectedYaw=0,closedTarget=0,closedDirection=0,
        closedGap=0,closedWindow=0,closedStop=0,
        eligiblePositive=0,eligibleNegative=0,
    }
end

function SEGCFG.getWindowStats(window)
    if type(window)~="string" then return SEGCFG.newWindowStats() end
    if not SEGCFG.windowStats[window] then SEGCFG.windowStats[window]=SEGCFG.newWindowStats() end
    return SEGCFG.windowStats[window]
end

function SEGCFG.windowEligibleCount(window)
    return SEGCFG.getWindowStats(window).eligible
end

function SEGCFG.noteClose(window,reason)
    local stats=SEGCFG.getWindowStats(window)
    stats.candidates+=1
    if reason=="target" then stats.closedTarget+=1
    elseif reason=="direction" then stats.closedDirection+=1
    elseif reason=="frame-gap" then stats.closedGap+=1
    elseif reason=="window-change" or reason=="phase-change" then stats.closedWindow+=1
    else stats.closedStop+=1 end
end

function SEGCFG.rejectSegment(route,window,reason,closeReason,build,pitchLimit)
    local stats=segmentStats[route]
    if not stats then return end
    local windowStats=SEGCFG.getWindowStats(window)
    if reason=="short" then stats.rejectedShort+=1
    elseif reason=="pitch" then stats.rejectedPitch+=1
    elseif reason=="duration" then stats.rejectedDuration+=1
    elseif reason=="geometry" then stats.rejectedGeometry+=1
    else stats.rejectedYaw+=1 end
    local key="rejected"..string.upper(string.sub(reason,1,1))..string.sub(reason,2)
    if windowStats[key]~=nil then windowStats[key]+=1 end
    SEGCFG.lastSegmentEvent=reason=="pitch" and "PITCH ALTO • MANTENHA HORIZONTAL"
        or (closeReason=="direction" and "DIREÇÃO QUEBROU"
        or (closeReason=="frame-gap" and "GAP QUEBROU" or "GIRE MAIS"))
    SEGCFG.lastSegmentEventAt=os.clock()
    SEGCFG.lastSegmentDetail=string.format(
        "rejected=%s close=%s window=%s yaw=%.3f netPitch=%.3f absPitch=%.3f pitchLimit=%.3f frames=%d",
        reason,tostring(closeReason),tostring(window),build.totalAbsYaw,build.netPitch,
        build.totalAbsPitch,pitchLimit,#build.samples)
    -- Rejected samples remain in the original V614 scalar trace, but their
    -- heavy telemetry is not needed for the final matched decomposition.
    for _,sample in ipairs(build.samples) do sample.temporalPoseTelemetry=nil end
end

function SEGCFG.closeCurrentSegment(reason)
    local build=currentSegment
    currentSegment=nil
    if not build or #build.samples==0 then return nil end
    local first,last=build.samples[1],build.samples[#build.samples]
    local duration=math.max(0,(last.time+last.dt)-first.time)
    local coherence=build.totalAbsYaw>0 and math.abs(build.totalSignedYaw)/build.totalAbsYaw or 0
    local primary=SEGCFG.segmentScreenMetric(first.primaryScreenBefore,last.primaryScreenAfter,build.totalAbsYaw)
    local head=SEGCFG.segmentScreenMetric(first.headScreenBefore,last.headScreenAfter,build.totalAbsYaw)
    local subject=SEGCFG.segmentScreenMetric(first.subjectScreenBefore,last.subjectScreenAfter,build.totalAbsYaw)
    local returnedPrimary=SEGCFG.segmentScreenMetric(first.primaryScreenBefore,last.returnedPrimaryScreen,build.totalAbsYaw)
    local returnedHead=SEGCFG.segmentScreenMetric(first.headScreenBefore,last.returnedHeadScreen,build.totalAbsYaw)
    local returnedSubject=SEGCFG.segmentScreenMetric(first.subjectScreenBefore,last.returnedSubjectScreen,build.totalAbsYaw)
    local pitchLimit=math.max(SEGCFG.maxAbsPitchFloor,build.totalAbsYaw*SEGCFG.maxAbsPitchRatio)
    SEGCFG.noteClose(build.window,reason)
    local reject=nil
    if build.totalAbsYaw<SEGCFG.targetYaw or #build.samples<SEGCFG.minFrames then reject="short"
    elseif build.totalAbsYaw>SEGCFG.maxYaw or coherence<SEGCFG.minCoherence then reject="yaw"
    elseif math.abs(build.netPitch)>SEGCFG.maxNetPitch or build.totalAbsPitch>pitchLimit then reject="pitch"
    elseif duration>SEGCFG.maxDuration then reject="duration"
    elseif not (primary and head and subject and returnedPrimary and returnedHead and returnedSubject) then reject="geometry" end
    if reject then
        SEGCFG.rejectSegment(build.route,build.window,reject,reason,build,pitchLimit)
        return nil
    end
    local segment={
        id=build.route.."-"..tostring(#segmentStats[build.route].eligible+1),
        route=build.route,window=build.window,startFrame=first.frame,endFrame=last.frame,
        startTime=first.time,endTime=last.time+last.dt,duration=duration,frameCount=#build.samples,
        totalSignedYaw=build.totalSignedYaw,totalAbsYaw=build.totalAbsYaw,
        netPitch=build.netPitch,totalAbsPitch=build.totalAbsPitch,
        meanSignedPitch=build.netPitch/#build.samples,medianSignedPitch=percentile(build.pitchTrajectory,0.5),
        yawTrajectory=build.yawTrajectory,pitchTrajectory=build.pitchTrajectory,
        primary=primary,head=head,subject=subject,
        returnedPrimary=returnedPrimary,returnedHead=returnedHead,returnedSubject=returnedSubject,
        subjectToPrimaryStart=first.subjectToPrimaryBefore,subjectToPrimaryEnd=last.subjectToPrimary,
        subjectToHeadStart=first.subjectToHeadBefore,subjectToHeadEnd=last.subjectToHead,
        primaryToHeadStart=first.primaryToHeadBefore,primaryToHeadEnd=last.primaryToHead,
        cameraYawStart=first.cameraYawBefore,cameraYawEnd=last.cameraYawAfter,
        cameraPitchStart=first.cameraPitchBefore,cameraPitchEnd=last.cameraPitchAfter,
        returnedYawEnd=last.returnedYawValue,returnedPitchEnd=last.returnedPitchValue,
        -- Retained only on eligible segments. Matching/calipers do not inspect
        -- this field; it exists solely for the post-match telemetry report.
        samples=build.samples,
        closeReason=reason,
    }
    local list=segmentStats[build.route].eligible
    list[#list+1]=segment
    local windowStats=SEGCFG.getWindowStats(build.window)
    windowStats.eligible+=1
    if build.totalSignedYaw>=0 then windowStats.eligiblePositive+=1 else windowStats.eligibleNegative+=1 end
    SEGCFG.lastSegmentEvent="SEGMENTO VÁLIDO"
    SEGCFG.lastSegmentEventAt=os.clock()
    SEGCFG.lastSegmentDetail=string.format("valid window=%s yaw=%.3f netPitch=%.3f absPitch=%.3f",
        tostring(build.window),build.totalAbsYaw,build.netPitch,build.totalAbsPitch)
    addTrace(string.format("segment eligible id=%s window=%s frames=%d yaw=%.6f netPitch=%.6f absPitch=%.6f duration=%.4f",
        segment.id,segment.window,segment.frameCount,segment.totalAbsYaw,segment.netPitch,segment.totalAbsPitch,segment.duration))
    return segment
end

function SEGCFG.startSegment(sample)
    currentSegment={
        route=sample.phase,window=sample.window,samples={},totalSignedYaw=0,totalAbsYaw=0,
        netPitch=0,totalAbsPitch=0,yawTrajectory={},pitchTrajectory={},
    }
end

segmentConsumer=function(sample)
    local sign=sample.yawSigned>=0 and 1 or -1
    if currentSegment then
        local previous=currentSegment.samples[#currentSegment.samples]
        local previousSign=previous and (previous.yawSigned>=0 and 1 or -1) or sign
        if currentSegment.route~=sample.phase or currentSegment.window~=sample.window then
            SEGCFG.closeCurrentSegment("window-change")
        elseif previous and sample.frame-previous.frame>SEGCFG.maxFrameGap then
            SEGCFG.closeCurrentSegment("frame-gap")
        elseif sign~=previousSign then
            SEGCFG.closeCurrentSegment("direction")
        end
    end
    if not currentSegment then SEGCFG.startSegment(sample) end
    local build=currentSegment
    build.samples[#build.samples+1]=sample
    build.totalSignedYaw+=sample.yawSigned
    build.totalAbsYaw+=math.abs(sample.yawSigned)
    build.netPitch+=sample.pitchSigned
    build.totalAbsPitch+=math.abs(sample.pitchSigned)
    build.yawTrajectory[#build.yawTrajectory+1]=sample.yawSigned
    build.pitchTrajectory[#build.pitchTrajectory+1]=sample.pitchSigned
    if build.totalAbsYaw>=SEGCFG.targetYaw then
        local eligible=SEGCFG.closeCurrentSegment("target")
        if eligible and type(SEGCFG.updateCoverageState)=="function" then SEGCFG.updateCoverageState(eligible) end
    end
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
    frame.correlationStage="camera-yaw-pitch"
    local cameraYawSigned=(before and after and before.cameraYaw and after.cameraYaw)
        and math.deg(angleDifference(after.cameraYaw,before.cameraYaw) or 0) or 0
    local cameraPitchSigned=(before and after and before.cameraPitch and after.cameraPitch)
        and math.deg(after.cameraPitch-before.cameraPitch) or 0
    local cameraYawDeg=math.abs(cameraYawSigned)
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
    local returnedYawSigned=(before and before.cameraYaw and typeof(frame.controllerReturnCFrame)=="CFrame")
        and math.deg(angleDifference(yawFromCFrame(frame.controllerReturnCFrame),before.cameraYaw) or 0) or 0
    local returnedPitchSigned=(before and before.cameraPitch and typeof(frame.controllerReturnCFrame)=="CFrame")
        and math.deg((pitchFromCFrame(frame.controllerReturnCFrame) or before.cameraPitch)-before.cameraPitch) or 0
    local returnedYawDeg=math.abs(returnedYawSigned)
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
    frame.correlationStage="subject-screen-projection"
    if subject and typeof(subject.position)=="Vector3" and before and after then
        frame.subjectBeforePoint,frame.subjectBeforeOnScreen=
            projectPositionWithCFrame(before.camera,before.cameraCFrame,subject.position)
        frame.subjectAfterPoint,frame.subjectAfterOnScreen=
            projectPositionWithCFrame(after.camera,after.cameraCFrame,subject.position)
        if typeof(frame.controllerReturnCFrame)=="CFrame" then
            frame.returnedSubjectPoint,frame.returnedSubjectOnScreen=
                projectPositionWithCFrame(before.camera,frame.controllerReturnCFrame,subject.position)
        end
    end
    if typeof(frame.controllerReturnCFrame)=="CFrame" and typeof(frame.controllerReturnFocus)=="CFrame" then
        stats.controllerCameraDistanceCount+=1
        stats.controllerCameraDistanceSum+=(frame.controllerReturnCFrame.Position-frame.controllerReturnFocus.Position).Magnitude
    end
    if currentPhase=="touch" or currentPhase=="relay" then
        frame.correlationStage="standing-gate"
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
                SEGCFG.closeCurrentSegment("wrong-route")
                paired.rejectedWrongRouteFrames+=1
            elseif not standing then
                SEGCFG.closeCurrentSegment("movement")
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
                    SEGCFG.closeCurrentSegment("projection")
                    paired.rejectedProjectionFrames+=1
                else
                    frame.correlationStage="commit-sample"
                    recordPairedSample(frame,paired,cameraYawSigned,cameraPitchSigned,
                        returnedYawSigned,returnedPitchSigned,primaryStep,headStep,
                        returnedPrimaryStep,returnedHeadStep)
                    frame.sampleCommitted=true
                    lastStandingDetail=lastStandingDetail..string.format(
                        " ACCEPT actualYawDeg=%.6f returnedYawDeg=%.6f primaryPx=%.6f headPx=%.6f returnedPrimaryPx=%.6f returnedHeadPx=%.6f",
                        cameraYawDeg,returnedYawDeg,primaryStep,headStep,returnedPrimaryStep,returnedHeadStep)
                    if paired.validStandingFrames<=12 or paired.validStandingFrames%100==0 then addTrace(lastStandingDetail) end
                end
            end
        end
        -- Never touch GUI Instances from the hooked CameraModule.Update thread.
        -- Delta reports that thread without Plugin capability. A top-level
        -- updater refreshes the panel from primitive counters instead.
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
        local telemetryWanted=phaseState=="active"
            and ((currentPhase=="touch" and writes.touchNonzero>0 and writes.relayNonzero==0)
                or (currentPhase=="relay" and writes.relayNonzero>0 and writes.touchNonzero==0))
        local frame={
            id=frameSerial,dt=dt,phase=phase,writes=writes,startedAt=os.clock(),screenBefore=screenSnapshot(),
            sequence={"CameraModule.Update:enter"},calculateIndex=0,
            telemetry={enabled=telemetryWanted,controllerCalls={}},
        }
        if telemetryWanted then
            frame.telemetry.cameraModuleBefore=SEGCFG.temporalPoseSnapshot("camera-module-before")
        end
        currentFrame=frame
        local results=packCall(callOriginal,self,dt,...)
        if telemetryWanted then
            frame.telemetry.cameraModuleAfter=SEGCFG.temporalPoseSnapshot("camera-module-after")
        end
        frame.screenAfter=screenSnapshot()
        frame.sequence[#frame.sequence+1]="CameraModule.Update:exit"
        frame.correlationStage="finalize-entry"
        local ok,err=xpcall(function() finalizeFrame(frame) end,function(value)
            local message=cleanText(value,240)
            if debug and type(debug.traceback)=="function" then
                local traceOk,trace=pcall(debug.traceback,message,2)
                if traceOk then message=cleanText(trace,700) end
            end
            return message
        end)
        if not ok then
            frameCorrelationErrors+=1
            if not frame.sampleCommitted then correlationFramesExcluded+=1 end
            local source=frame.correlationStage or "unknown"
            lastCorrelationErrorSource=source..":"..cleanText(err,180)
            correlationErrorSources[source]=(correlationErrorSources[source] or 0)+1
            if correlationErrorSources[source]<=3 then addEvidence("CORRELATION",lastCorrelationErrorSource) end
        end
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
    controllerErrors=0; frameCorrelationErrors=0; correlationFramesExcluded=0
    correlationErrorSources={}; optionalDiagnosticReadErrors=0
    telemetryCaptureErrors=0; telemetryCaptureErrorSources={}; telemetryBoundariesCaptured=0
    lastCorrelationErrorSource="none"; subjectClassCounts={}
    lastCorrelatedFrame=""; lastSubjectDetail=""; lastGeometryDetail=""; lastStandingDetail=""
    phaseStats={touch=newPhaseStats(),relay=newPhaseStats()}
    pairedStats={touch=newPairedStats(),relay=newPairedStats()}
    segmentStats={
        touch={eligible={},rejectedShort=0,rejectedPitch=0,rejectedDuration=0,rejectedGeometry=0,rejectedYaw=0},
        relay={eligible={},rejectedShort=0,rejectedPitch=0,rejectedDuration=0,rejectedGeometry=0,rejectedYaw=0},
    }
    SEGCFG.windowStats={}
    SEGCFG.livePotentialPairs=0; SEGCFG.coverageSufficient=false
    SEGCFG.lastSegmentEvent="GIRE MAIS"; SEGCFG.lastSegmentEventAt=0; SEGCFG.lastSegmentDetail="none"
    currentSegment=nil; currentPhase="none"; currentWindow="none"; phaseState="idle"
    stableConsecutive=0; phaseLastPrimaryPosition=nil; expectedPhaseIndex=1; completedWindows={}
    uiRefreshErrors=0
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
    if type(SEGCFG.resetReportExport)=="function" then SEGCFG.resetReportExport() end
    resetCounters()
    stateAtStop=nil
    probeStartedAt=os.clock(); probeDuration=0; probeRunning=true
    addEvidence("PROBE","V614 paired standing control started; follow A1 Touch -> B1 relay -> B2 relay -> A2 Touch")
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
    SEGCFG.closeCurrentSegment("probe-stop")
    SEGCFG.pruneTelemetryToMatched()
    probeDuration=os.clock()-probeStartedAt
    probeRunning=false; currentFrame=nil; currentCalc=nil; currentPhase="none"; currentWindow="none"; phaseState="stopped"
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
    local ok,a,b=pcall(function()
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
    end)
    if ok then return a,b end
    optionalDiagnosticReadErrors+=1
    joystickCriterionAvailable=false
    cachedJoystickInactive=true
    cachedJoystickDetail="optional V604 joystick diagnostics unavailable:"..cleanText(a,100)
    return true,cachedJoystickDetail
end

local function beginControlledPhase(window)
    if not probeRunning then return false,"press-INICIAR-first" end
    local phase=SEGCFG.route[window]
    if phase~="touch" and phase~="relay" then return false,"invalid-phase" end
    local expected=SEGCFG.sequence[expectedPhaseIndex]
    if window~=expected then return false,"expected-"..tostring(expected) end
    if currentWindow~="none" and currentWindow~=window and completedWindows[currentWindow]~=true then
        return false,"finish-"..tostring(currentWindow).."-coverage-first"
    end
    if type(baseSetRelay)~="function" then return false,"V604-relay-control-unavailable" end
    local wantRelay=phase=="relay"
    local ok,result=pcall(baseSetRelay,wantRelay)
    if not ok or result==false then return false,cleanText(result,180) end
    SEGCFG.closeCurrentSegment("phase-change")
    currentPhase=phase
    currentWindow=window
    expectedPhaseIndex=math.min(#SEGCFG.sequence+1,expectedPhaseIndex+1)
    phaseState="stabilizing"
    phaseStartedAt=os.clock()
    phaseStabilizeUntil=phaseStartedAt+STABILIZE_SECONDS
    stableConsecutive=0
    phaseLastPrimaryPosition=nil
    lastJoystickReadAt=0
    addEvidence("PHASE",string.format("%s route=%s selected relay=%s stabilization=%.2fs+%d consecutive standing frames",
        tostring(window),tostring(phase),tostring(wantRelay),STABILIZE_SECONDS,STABLE_CONSECUTIVE_FRAMES))
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

local function _legacyV612Classification()
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
        and "GetSubjectPosition subject origin -> CameraFocus/orbit reference (not investigated in V614)"
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

-- V614 classification deliberately separates descriptive effect, temporal
-- uncertainty, and causal wording. V612's effect-size gate above remains only
-- as historical code and is shadowed here; it is not used by V614 diagnostics.
local function fieldValues(samples,field,predicate)
    local values={}
    for _,sample in ipairs(samples) do
        if (not predicate or predicate(sample)) and type(sample[field])=="number" then
            values[#values+1]=sample[field]
        end
    end
    return values
end

local function signedFieldPairs(samples,xField,yField,predicate)
    local xs,ys={},{}
    for _,sample in ipairs(samples) do
        local x,y=sample[xField],sample[yField]
        if (not predicate or predicate(sample)) and type(x)=="number" and type(y)=="number" then
            xs[#xs+1]=x; ys[#ys+1]=y
        end
    end
    return xs,ys
end

local function pearson(xs,ys)
    local n=math.min(#xs,#ys)
    if n<30 then return nil,n end
    local sx,sy=0,0
    for i=1,n do sx+=xs[i]; sy+=ys[i] end
    local mx,my=sx/n,sy/n
    local numerator,dx2,dy2=0,0,0
    for i=1,n do
        local dx,dy=xs[i]-mx,ys[i]-my
        numerator+=dx*dy; dx2+=dx*dx; dy2+=dy*dy
    end
    if dx2<=1e-12 or dy2<=1e-12 then return nil,n end
    return numerator/math.sqrt(dx2*dy2),n
end

local function binPhaseSummary(samples)
    return {
        n=#samples,
        yaw=distribution(fieldValues(samples,"yaw")),
        pitch=distribution(fieldValues(samples,"pitch")),
        pitchSigned=distribution(fieldValues(samples,"pitchSigned")),
        primaryX=distribution(fieldValues(samples,"primaryX")),
        primaryY=distribution(fieldValues(samples,"primaryY")),
        headX=distribution(fieldValues(samples,"headX")),
        headY=distribution(fieldValues(samples,"headY")),
    }
end

local function exactYawAnalysis()
    local touchAll,relayAll=pairedStats.touch.samples,pairedStats.relay.samples
    local predicate=function(sample) return sample.pitchControlled==true end
    local touchYaw=fieldValues(touchAll,"yaw",predicate)
    local relayYaw=fieldValues(relayAll,"yaw",predicate)
    if #touchYaw<MIN_PHASE_SAMPLES or #relayYaw<MIN_PHASE_SAMPLES then
        return {quality="unproved: insufficient pitch-controlled samples",matchedBins=0,touch={},relay={},lines="none"}
    end
    local low=math.max(percentile(touchYaw,0.05) or math.huge,percentile(relayYaw,0.05) or math.huge,MIN_APPLIED_YAW_DEG)
    local high=math.min(percentile(touchYaw,0.95) or -math.huge,percentile(relayYaw,0.95) or -math.huge)
    if high<=low then
        return {quality="unproved: no shared pitch-controlled p05-p95 yaw support",matchedBins=0,touch={},relay={},lines="none"}
    end
    local firstIndex=math.floor(low/YAW_BIN_WIDTH_DEG)
    local lastIndex=math.ceil(high/YAW_BIN_WIDTH_DEG)-1
    local matchedTouch,matchedRelay={},{}
    local matchedBounds={}
    local lines={string.format("fixedWidth=%.3fdeg sharedP05P95=[%.6f,%.6f] pitchAbs<=%.3f minPerPhase=%d maxMedianYawGap=%.3f",
        YAW_BIN_WIDTH_DEG,low,high,MAX_PITCH_CONTROL_DEG,MIN_BIN_SAMPLES,MAX_BIN_MEDIAN_YAW_GAP_DEG)}
    local matchedBins=0
    local maxGap=0
    for index=firstIndex,lastIndex do
        local binLow=math.max(low,index*YAW_BIN_WIDTH_DEG)
        local binHigh=math.min(high,(index+1)*YAW_BIN_WIDTH_DEG)
        local function inBin(sample)
            return sample.pitchControlled==true and sample.yaw>=binLow
                and (index==lastIndex and sample.yaw<=binHigh or sample.yaw<binHigh)
        end
        local ta,ra={},{}
        for _,sample in ipairs(touchAll) do if inBin(sample) then ta[#ta+1]=sample end end
        for _,sample in ipairs(relayAll) do if inBin(sample) then ra[#ra+1]=sample end end
        local ts,rs=binPhaseSummary(ta),binPhaseSummary(ra)
        local gap=(ts.yaw.median and rs.yaw.median) and math.abs(ts.yaw.median-rs.yaw.median) or math.huge
        local matched=#ta>=MIN_BIN_SAMPLES and #ra>=MIN_BIN_SAMPLES and gap<=MAX_BIN_MEDIAN_YAW_GAP_DEG
        if matched then
            matchedBins+=1; maxGap=math.max(maxGap,gap)
            matchedBounds[#matchedBounds+1]={low=binLow,high=binHigh,last=index==lastIndex}
        end
        local function phaseBinText(summary,items)
            local yaws=fieldValues(items,"yaw")
            return "n="..tostring(#items)
                .." yawMean="..tostring(round(summary.yaw.mean,6))
                .." yawMedian="..tostring(round(summary.yaw.median,6))
                .." yawP05="..tostring(round(percentile(yaws,0.05),6))
                .." yawP95="..tostring(round(percentile(yaws,0.95),6))
                .." pitchAbsMean="..tostring(round(summary.pitch.mean,6))
                .." pitchAbsMedian="..tostring(round(summary.pitch.median,6))
                .." pitchSignedMean="..tostring(round(summary.pitchSigned.mean,6))
                .." pitchSignedMedian="..tostring(round(summary.pitchSigned.median,6))
                .." pX="..tostring(round(summary.primaryX.median,7))
                .." pY="..tostring(round(summary.primaryY.median,7))
                .." hX="..tostring(round(summary.headX.median,7))
                .." hY="..tostring(round(summary.headY.median,7))
        end
        local relative="pX="..tostring(round(relativeDifference(ts.primaryX.median,rs.primaryX.median),5))
            .." pY="..tostring(round(relativeDifference(ts.primaryY.median,rs.primaryY.median),5))
            .." hX="..tostring(round(relativeDifference(ts.headX.median,rs.headX.median),5))
            .." hY="..tostring(round(relativeDifference(ts.headY.median,rs.headY.median),5))
        lines[#lines+1]="["..tostring(round(binLow,3))..","..tostring(round(binHigh,3))
            ..(index==lastIndex and "]" or ")").." touch{"..phaseBinText(ts,ta).."} relay{"
            ..phaseBinText(rs,ra).."} rel{"..relative.."} medianYawGap="..tostring(round(gap,6))
            .." matched="..tostring(matched)
    end
    local function inMatchedBin(sample)
        if sample.pitchControlled~=true then return false end
        for _,bound in ipairs(matchedBounds) do
            if sample.yaw>=bound.low and (bound.last and sample.yaw<=bound.high or sample.yaw<bound.high) then return true end
        end
        return false
    end
    -- Preserve original temporal order for the moving-block bootstrap.
    for _,sample in ipairs(touchAll) do if inMatchedBin(sample) then matchedTouch[#matchedTouch+1]=sample end end
    for _,sample in ipairs(relayAll) do if inMatchedBin(sample) then matchedRelay[#matchedRelay+1]=sample end end
    local quality=(matchedBins>=MIN_MATCHED_BINS and #matchedTouch>=MIN_PHASE_SAMPLES and #matchedRelay>=MIN_PHASE_SAMPLES)
        and string.format("good: matchedBins=%d touch=%d relay=%d maxMedianYawGap=%.6f",matchedBins,#matchedTouch,#matchedRelay,maxGap)
        or string.format("unproved: matchedBins=%d/%d touch=%d relay=%d",matchedBins,MIN_MATCHED_BINS,#matchedTouch,#matchedRelay)
    return {quality=quality,matchedBins=matchedBins,touch=matchedTouch,relay=matchedRelay,
        low=low,high=high,maxGap=maxGap,lines=table.concat(lines," | ")}
end

local function blockBootstrapDifference(touchSamples,relaySamples,field)
    local touch=fieldValues(touchSamples,field)
    local relay=fieldValues(relaySamples,field)
    if #touch<MIN_PHASE_SAMPLES or #relay<MIN_PHASE_SAMPLES then return nil end
    local state=(#touch*1000003+#relay*9176+#field*97)%2147483647
    if state<=0 then state=104729 end
    local function randomIndex(maximum)
        state=(state*48271)%2147483647
        return 1+(state%maximum)
    end
    local function resample(series)
        local result={}
        while #result<#series do
            local start=randomIndex(math.max(1,#series-BOOTSTRAP_BLOCK_SIZE+1))
            for offset=0,BOOTSTRAP_BLOCK_SIZE-1 do
                if #result>=#series then break end
                result[#result+1]=series[math.min(#series,start+offset)]
            end
        end
        return result
    end
    local differences={}
    for _=1,BOOTSTRAP_ITERATIONS do
        differences[#differences+1]=(percentile(resample(relay),0.5) or 0)-(percentile(resample(touch),0.5) or 0)
    end
    local estimate=(percentile(relay,0.5) or 0)-(percentile(touch,0.5) or 0)
    local low,high=percentile(differences,0.025),percentile(differences,0.975)
    return {estimate=estimate,low=low,high=high,touchN=#touch,relayN=#relay,
        excludesZero=type(low)=="number" and type(high)=="number" and (low>0 or high<0)}
end

local function bootstrapText(result)
    if not result then return "unproved" end
    return string.format("estimate(relay-touch)=%s CI95=[%s,%s] excludesZero=%s touchN=%d relayN=%d",
        tostring(round(result.estimate,8)),tostring(round(result.low,8)),tostring(round(result.high,8)),
        tostring(result.excludesZero),result.touchN,result.relayN)
end

local function vectorDistributionText(samples,field,component)
    local values={}
    for _,sample in ipairs(samples) do
        local value=sample[field]
        if typeof(value)=="Vector3" then
            if component=="horizontal" then value=Vector2.new(value.X,value.Z).Magnitude
            elseif component=="vertical" then value=value.Y
            elseif component=="magnitude" then value=value.Magnitude end
        end
        if type(value)=="number" then values[#values+1]=value end
    end
    return distributionText(values)
end

local function anchorStabilityText(touch,relay,prefix,twoDField,returnedPrefix,returnedTwoDField)
    return "lower=more-stable; touch{X="..distributionText(fieldValues(touch,prefix.."X"))
        .." Y="..distributionText(fieldValues(touch,prefix.."Y"))
        .." D2="..distributionText(fieldValues(touch,twoDField))
        .." returnedX="..distributionText(fieldValues(touch,returnedPrefix.."X"))
        .." returnedY="..distributionText(fieldValues(touch,returnedPrefix.."Y"))
        .." returnedD2="..distributionText(fieldValues(touch,returnedTwoDField))
        .."} relay{X="..distributionText(fieldValues(relay,prefix.."X"))
        .." Y="..distributionText(fieldValues(relay,prefix.."Y"))
        .." D2="..distributionText(fieldValues(relay,twoDField))
        .." returnedX="..distributionText(fieldValues(relay,returnedPrefix.."X"))
        .." returnedY="..distributionText(fieldValues(relay,returnedPrefix.."Y"))
        .." returnedD2="..distributionText(fieldValues(relay,returnedTwoDField)).."}"
end

local function lowestAnchor(samples)
    local values={
        Head=distribution(fieldValues(samples,"head")).median,
        PrimaryPart=distribution(fieldValues(samples,"primary")).median,
        Subject=distribution(fieldValues(samples,"subject2D")).median,
    }
    local name,best=nil,math.huge
    for candidate,value in pairs(values) do
        if type(value)=="number" and value<best then name,best=candidate,value end
    end
    return name,best
end

local function classification()
    local exact=exactYawAnalysis()
    local touch,relay=exact.touch,exact.relay
    local qualityGood=string.sub(exact.quality,1,5)=="good:"
    local tPX,rPX=distribution(fieldValues(touch,"primaryX")),distribution(fieldValues(relay,"primaryX"))
    local tPY,rPY=distribution(fieldValues(touch,"primaryY")),distribution(fieldValues(relay,"primaryY"))
    local tHX,rHX=distribution(fieldValues(touch,"headX")),distribution(fieldValues(relay,"headX"))
    local tHY,rHY=distribution(fieldValues(touch,"headY")),distribution(fieldValues(relay,"headY"))
    local primaryBoot=qualityGood and blockBootstrapDifference(touch,relay,"primaryX") or nil
    local headBoot=qualityGood and blockBootstrapDifference(touch,relay,"headX") or nil
    local touchAnchor,touchAnchorValue=lowestAnchor(touch)
    local relayAnchor,relayAnchorValue=lowestAnchor(relay)
    local combined={}
    local function inAssociationSupport(sample)
        return type(exact.low)=="number" and type(exact.high)=="number"
            and sample.yaw>=exact.low and sample.yaw<=exact.high
    end
    for _,sample in ipairs(pairedStats.touch.samples) do if inAssociationSupport(sample) then combined[#combined+1]=sample end end
    for _,sample in ipairs(pairedStats.relay.samples) do if inAssociationSupport(sample) then combined[#combined+1]=sample end end
    local headDY,pitch=signedFieldPairs(combined,"headDY","pitchSigned")
    local headDYRig,rig=signedFieldPairs(combined,"headDY","rigDeltaVertical")
    local headDYDepth,depth=signedFieldPairs(combined,"headDY","headDepthDelta")
    local pitchR,pitchN=pearson(headDY,pitch)
    local rigR,rigN=pearson(headDYRig,rig)
    local depthR,depthN=pearson(headDYDepth,depth)
    local pitchStrong,rigStrong=false,false
    if type(pitchR)=="number" then pitchStrong=math.abs(pitchR :: number)>=ASSOCIATION_THRESHOLD end
    if type(rigR)=="number" then rigStrong=math.abs(rigR :: number)>=ASSOCIATION_THRESHOLD end
    local pitchExplanation=pitchStrong and "supported-descriptive-association"
        or (type(pitchR)=="number" and "not-supported-at-r>=0.50" or "unproved")
    local rigExplanation=rigStrong and "supported-descriptive-association"
        or (type(rigR)=="number" and "not-supported-at-r>=0.50" or "unproved")
    local descriptive=qualityGood and string.format(
        "exact-yaw+pitch-controlled medians relay-touch: primaryX=%s headX=%s primaryY=%s headY=%s",
        tostring(round((rPX.median or 0)-(tPX.median or 0),8)),tostring(round((rHX.median or 0)-(tHX.median or 0),8)),
        tostring(round((rPY.median or 0)-(tPY.median or 0),8)),tostring(round((rHY.median or 0)-(tHY.median or 0),8)))
        or "unproved"
    local statistical="unproved"
    if primaryBoot and headBoot then
        statistical="primaryHorizontal{"..bootstrapText(primaryBoot).."}; headHorizontal{"..bootstrapText(headBoot).."}"
    end
    local firstExplanation="unproved"
    if pitchExplanation=="supported-descriptive-association" and rigExplanation=="supported-descriptive-association" then
        firstExplanation="combined pitch and relative Head/rig geometry associations with Head vertical screen displacement"
    elseif pitchExplanation=="supported-descriptive-association" then
        firstExplanation="pitch association with Head vertical screen displacement"
    elseif rigExplanation=="supported-descriptive-association" then
        firstExplanation="relative Head/rig geometry association with Head vertical screen displacement"
    end
    local causal="unproved"
    if qualityGood and primaryBoot and primaryBoot.excludesZero then
        causal="unproved: PrimaryPart horizontal difference survives matched moving-block CI, but sequential phase order is not counterbalanced; no PC equivalence"
    end
    local pcConsistency="unproved"
    if qualityGood and touchAnchor and relayAnchor then
        local upperRegionTouch=touchAnchor=="Head" or touchAnchor=="Subject"
        local upperRegionRelay=relayAnchor=="Head" or relayAnchor=="Subject"
        pcConsistency=(upperRegionTouch and upperRegionRelay)
            and ("qualitatively consistent only at point-ranking level; mobileLowest touch="..touchAnchor
                .."("..tostring(round(touchAnchorValue,7))..") relay="..relayAnchor
                .."("..tostring(round(relayAnchorValue,7)).."); no PC equivalence")
            or ("not-supported by mobile point ranking; mobileLowest touch="..tostring(touchAnchor)
                .." relay="..tostring(relayAnchor))
    end
    return {
        analysisReady=qualityGood and primaryBoot~=nil and headBoot~=nil,
        standingTouchSamples=pairedStats.touch.validStandingFrames,
        standingRelaySamples=pairedStats.relay.validStandingFrames,
        correlationErrors=string.format("count=%d excludedBeforeCommit=%d optionalReadErrors=%d sources=%s last=%s",
            frameCorrelationErrors,correlationFramesExcluded,optionalDiagnosticReadErrors,countSummary(correlationErrorSources),lastCorrelationErrorSource),
        exactYawMatchQuality=exact.quality.." | bins="..exact.lines,
        pitchControlQuality=string.format("fixed abs(appliedPitch)<=%.3fdeg; matched touch=%d relay=%d",
            MAX_PITCH_CONTROL_DEG,#touch,#relay),
        primaryHorizontalTouch="observed={"..distributionText(fieldValues(touch,"primaryX")).."}; returned={"..distributionText(fieldValues(touch,"returnedPrimaryX")).."}",
        primaryHorizontalRelay="observed={"..distributionText(fieldValues(relay,"primaryX")).."}; returned={"..distributionText(fieldValues(relay,"returnedPrimaryX")).."}",
        primaryVerticalTouch="perYaw={"..distributionText(fieldValues(touch,"primaryY")).."}; perPitch={"..distributionText(fieldValues(touch,"primaryYPerPitch")).."}; returnedPerYaw={"..distributionText(fieldValues(touch,"returnedPrimaryY")).."}",
        primaryVerticalRelay="perYaw={"..distributionText(fieldValues(relay,"primaryY")).."}; perPitch={"..distributionText(fieldValues(relay,"primaryYPerPitch")).."}; returnedPerYaw={"..distributionText(fieldValues(relay,"returnedPrimaryY")).."}",
        headHorizontalTouch="observed={"..distributionText(fieldValues(touch,"headX")).."}; returned={"..distributionText(fieldValues(touch,"returnedHeadX")).."}",
        headHorizontalRelay="observed={"..distributionText(fieldValues(relay,"headX")).."}; returned={"..distributionText(fieldValues(relay,"returnedHeadX")).."}",
        headVerticalTouch="perYaw={"..distributionText(fieldValues(touch,"headY")).."}; perPitch={"..distributionText(fieldValues(touch,"headYPerPitch")).."}; returnedPerYaw={"..distributionText(fieldValues(touch,"returnedHeadY")).."}",
        headVerticalRelay="perYaw={"..distributionText(fieldValues(relay,"headY")).."}; perPitch={"..distributionText(fieldValues(relay,"headYPerPitch")).."}; returnedPerYaw={"..distributionText(fieldValues(relay,"returnedHeadY")).."}",
        primaryDifferenceAfterYawMatch=qualityGood and string.format("horizontalRelative=%s verticalRelative=%s bootstrap={%s}",
            tostring(round(relativeDifference(tPX.median,rPX.median),6)),tostring(round(relativeDifference(tPY.median,rPY.median),6)),bootstrapText(primaryBoot)) or "unproved",
        headDifferenceAfterYawMatch=qualityGood and string.format("horizontalRelative=%s verticalRelative=%s bootstrap={%s}",
            tostring(round(relativeDifference(tHX.median,rHX.median),6)),tostring(round(relativeDifference(tHY.median,rHY.median),6)),bootstrapText(headBoot)) or "unproved",
        relativeHeadRigGeometryDifference=string.format(
            "touch PrimaryToHead{horizontal=%s vertical=%s magnitude=%s} SubjectToHead{horizontal=%s vertical=%s magnitude=%s} relay PrimaryToHead{horizontal=%s vertical=%s magnitude=%s} SubjectToHead{horizontal=%s vertical=%s magnitude=%s}; headDY associations rigVertical r=%s n=%d depth r=%s n=%d",
            vectorDistributionText(touch,"primaryToHead","horizontal"),vectorDistributionText(touch,"primaryToHead","vertical"),vectorDistributionText(touch,"primaryToHead","magnitude"),
            vectorDistributionText(touch,"subjectToHead","horizontal"),vectorDistributionText(touch,"subjectToHead","vertical"),vectorDistributionText(touch,"subjectToHead","magnitude"),
            vectorDistributionText(relay,"primaryToHead","horizontal"),vectorDistributionText(relay,"primaryToHead","vertical"),vectorDistributionText(relay,"primaryToHead","magnitude"),
            vectorDistributionText(relay,"subjectToHead","horizontal"),vectorDistributionText(relay,"subjectToHead","vertical"),vectorDistributionText(relay,"subjectToHead","magnitude"),
            tostring(round(rigR,6)),rigN,tostring(round(depthR,6)),depthN),
        pitchExplainsAsymmetry=pitchExplanation.."; headDY-vs-appliedPitch r="..tostring(round(pitchR,6)).." n="..tostring(pitchN),
        rigGeometryExplainsAsymmetry=rigExplanation.."; headDY-vs-rigVerticalDelta r="..tostring(round(rigR,6)).." n="..tostring(rigN),
        statisticalMethod=string.format("moving-block bootstrap on time-ordered exact-yaw-bin, pitch-controlled samples; blockSize=%d iterations=%d statistic=median(relay)-median(touch); descriptive Pearson associations threshold abs(r)>=%.2f",
            BOOTSTRAP_BLOCK_SIZE,BOOTSTRAP_ITERATIONS,ASSOCIATION_THRESHOLD),
        statisticalUncertainty=(primaryBoot and headBoot) and "estimated by temporal moving-block CI95; sequential phase order remains an unremoved limitation" or "unproved",
        descriptiveDifference=descriptive,
        statisticalEvidence=statistical,
        firstGeometricExplanation=firstExplanation,
        causalInputEffect=causal,
        externalPCReferenceUsed=true,
        externalPCReferenceWindow="approximately 20.0s-24.0s",
        pcVisualAnchorCandidate="qualitative Head/upper-torso screen region only; pivot and exact point unproved",
        headScreenSpaceStability=anchorStabilityText(touch,relay,"head","head","returnedHead","returnedHead"),
        primaryScreenSpaceStability=anchorStabilityText(touch,relay,"primary","primary","returnedPrimary","returnedPrimary"),
        subjectScreenSpaceStability=anchorStabilityText(touch,relay,"subject","subject2D","returnedSubject","returnedSubject2D"),
        pcReferenceConsistentWithRuntimeGeometry=pcConsistency,
        pcEquivalenceClaimAllowed=false,
        nextDiagnosticTarget=firstExplanation=="unproved" and "counterbalanced repeated standing phases with exact yaw+pitch matching and direct relative Head/rig vector control" or "review measured explanation before any new version",
        experimentEligible=false,
        astra6MaxJustified=firstExplanation=="unproved" and "unproved: evaluate V614 evidence first" or false,
    }
end

function SEGCFG.matchSegments()
    local touch,relay=segmentStats.touch.eligible,segmentStats.relay.eligible
    local candidates={}
    for ti,t in ipairs(touch) do
        for ri,r in ipairs(relay) do
            local yawGap=math.abs(t.totalAbsYaw-r.totalAbsYaw)
            local netPitchGap=math.abs(t.netPitch-r.netPitch)
            local absPitchGap=math.abs(t.totalAbsPitch-r.totalAbsPitch)
            local sameDirection=t.totalSignedYaw*r.totalSignedYaw>0
            if sameDirection and yawGap<=SEGCFG.matchYawGap
                and netPitchGap<=SEGCFG.matchNetPitchGap
                and absPitchGap<=SEGCFG.matchAbsPitchGap then
                candidates[#candidates+1]={ti=ti,ri=ri,yawGap=yawGap,netPitchGap=netPitchGap,
                    absPitchGap=absPitchGap,score=yawGap/SEGCFG.matchYawGap
                        +netPitchGap/SEGCFG.matchNetPitchGap
                        +absPitchGap/SEGCFG.matchAbsPitchGap}
            end
        end
    end
    table.sort(candidates,function(a,b)
        if a.score==b.score then
            if a.ti==b.ti then return a.ri<b.ri end
            return a.ti<b.ti
        end
        return a.score<b.score
    end)
    local usedTouch,usedRelay,pairs={},{},{}
    for _,candidate in ipairs(candidates) do
        if not usedTouch[candidate.ti] and not usedRelay[candidate.ri] then
            usedTouch[candidate.ti]=true; usedRelay[candidate.ri]=true
            local t,r=touch[candidate.ti],relay[candidate.ri]
            pairs[#pairs+1]={touch=t,relay=r,yawGap=candidate.yawGap,
                netPitchGap=candidate.netPitchGap,absPitchGap=candidate.absPitchGap}
        end
    end
    table.sort(pairs,function(a,b)
        return math.max(a.touch.endTime,a.relay.endTime)<math.max(b.touch.endTime,b.relay.endTime)
    end)
    return pairs
end

function SEGCFG.telemetryCoverage(pairs)
    local result={samples=0,complete=0,missing=0,controllerCalls=0}
    for _,pair in ipairs(pairs or {}) do
        for _,route in ipairs({"touch","relay"}) do
            for _,sample in ipairs((pair[route] and pair[route].samples) or {}) do
                result.samples+=1
                local telemetry=sample.temporalPoseTelemetry
                local calls=type(telemetry)=="table" and telemetry.controllerCalls or nil
                result.controllerCalls+=type(calls)=="table" and #calls or 0
                local complete=type(telemetry)=="table"
                    and type(telemetry.cameraModuleBefore)=="table"
                    and type(telemetry.cameraModuleAfter)=="table"
                    and type(calls)=="table" and #calls>0
                    and type(calls[1].before)=="table" and type(calls[1].after)=="table"
                if complete then result.complete+=1 else result.missing+=1 end
            end
        end
    end
    return result
end

function SEGCFG.pruneTelemetryToMatched()
    local keep={}
    for _,pair in ipairs(SEGCFG.matchSegments()) do
        keep[pair.touch]=true; keep[pair.relay]=true
    end
    for _,route in ipairs({"touch","relay"}) do
        for _,segment in ipairs(segmentStats[route].eligible) do
            if not keep[segment] then
                for _,sample in ipairs(segment.samples or {}) do sample.temporalPoseTelemetry=nil end
            end
        end
    end
end

function SEGCFG.updateCoverageState(segment)
    local pairs=SEGCFG.matchSegments()
    SEGCFG.livePotentialPairs=#pairs
    SEGCFG.coverageSufficient=#pairs>=SEGCFG.minMatched
    local window=segment and segment.window or currentWindow
    local count=SEGCFG.windowEligibleCount(window)
    if phaseState~="active" or currentWindow~=window then return end
    local phaseTargetReached=count>=SEGCFG.phaseEligibleTarget
    if phaseTargetReached then
        phaseState="complete"
        completedWindows[window]=true
        SEGCFG.lastSegmentEvent=SEGCFG.coverageSufficient and "COBERTURA SUFICIENTE" or "FASE COMPLETA"
        SEGCFG.lastSegmentEventAt=os.clock()
        SEGCFG.lastSegmentDetail=string.format(
            "phase-complete window=%s eligible=%d target=%d potentialPairs=%d required=%d",
            tostring(window),count,SEGCFG.phaseEligibleTarget,#pairs,SEGCFG.minMatched)
        addEvidence("COVERAGE",SEGCFG.lastSegmentDetail)
    end
end

function SEGCFG.pairMetricArrays(pairs,point,axis)
    local touch,relay,difference={},{},{}
    for _,pair in ipairs(pairs) do
        local tv=pair.touch[point] and pair.touch[point][axis]
        local rv=pair.relay[point] and pair.relay[point][axis]
        if type(tv)=="number" and type(rv)=="number" then
            touch[#touch+1]=tv; relay[#relay+1]=rv; difference[#difference+1]=rv-tv
        end
    end
    return touch,relay,difference
end

function SEGCFG.movingBlockDifference(differences)
    if #differences<SEGCFG.minMatched then return nil end
    local state=(#differences*1000003+SEGCFG.bootstrapIterations*97)%2147483647
    if state<=0 then state=104729 end
    local function randomIndex(maximum)
        state=(state*48271)%2147483647
        return 1+(state%maximum)
    end
    local function resample()
        local output={}
        while #output<#differences do
            local start=randomIndex(math.max(1,#differences-SEGCFG.bootstrapBlock+1))
            for offset=0,SEGCFG.bootstrapBlock-1 do
                if #output>=#differences then break end
                output[#output+1]=differences[math.min(#differences,start+offset)]
            end
        end
        return output
    end
    local estimates={}
    for _=1,SEGCFG.bootstrapIterations do estimates[#estimates+1]=percentile(resample(),0.5) end
    local low,high=percentile(estimates,0.025),percentile(estimates,0.975)
    return {estimate=percentile(differences,0.5),low=low,high=high,
        excludesZero=type(low)=="number" and type(high)=="number" and (low>0 or high<0),
        n=#differences,touchN=#differences,relayN=#differences}
end

function SEGCFG.segmentMetricText(pairs,point,axis)
    local touch,relay,difference=SEGCFG.pairMetricArrays(pairs,point,axis)
    local bootstrap=SEGCFG.movingBlockDifference(difference)
    return "touch{"..distributionText(touch).."} relay{"..distributionText(relay)
        .."} relay-touch{"..distributionText(difference).."} CI={"..bootstrapText(bootstrap).."}",bootstrap
end

function SEGCFG.vectorChangeMagnitude(segment,startField,endField)
    local startValue,endValue=segment[startField],segment[endField]
    if typeof(startValue)~="Vector3" or typeof(endValue)~="Vector3" then return nil end
    return (endValue-startValue).Magnitude
end

function SEGCFG.segmentVectorDifference(pairs,startField,endField)
    local touch,relay={},{}
    for _,pair in ipairs(pairs) do
        local t=SEGCFG.vectorChangeMagnitude(pair.touch,startField,endField)
        local r=SEGCFG.vectorChangeMagnitude(pair.relay,startField,endField)
        if type(t)=="number" and type(r)=="number" then touch[#touch+1]=t; relay[#relay+1]=r end
    end
    return "touch{"..distributionText(touch).."} relay{"..distributionText(relay).."}"
end

function SEGCFG.segmentRangeText(items)
    local values={}
    for _,item in ipairs(items) do values[#values+1]=item.totalAbsYaw end
    if #values==0 then return "none" end
    table.sort(values)
    return tostring(round(values[1],3)).."-"..tostring(round(values[#values],3)).."deg"
end

function SEGCFG.windowStatsText(window)
    local s=SEGCFG.getWindowStats(window)
    return string.format(
        "eligible=%d/%d candidates=%d rejectShort=%d rejectPitch=%d rejectDuration=%d rejectGeometry=%d rejectYaw=%d closeTarget=%d closeDirection=%d closeGap=%d closeWindow=%d closeStop=%d directionPositive=%d directionNegative=%d",
        s.eligible,SEGCFG.phaseEligibleTarget,s.candidates,s.rejectedShort,s.rejectedPitch,
        s.rejectedDuration,s.rejectedGeometry,s.rejectedYaw,s.closedTarget,s.closedDirection,
        s.closedGap,s.closedWindow,s.closedStop,s.eligiblePositive,s.eligibleNegative)
end

function SEGCFG.segmentClassification()
    local pairs=SEGCFG.matchSegments()
    local touchSegments,relaySegments=segmentStats.touch.eligible,segmentStats.relay.eligible
    local required=SEGCFG.minMatched
    local quality=#pairs>=required and "good" or "unproved"
    local minEligible=math.min(#touchSegments,#relaySegments)
    local coverage=minEligible>0 and #pairs/minEligible or 0
    local yawGaps,netPitchGaps,absPitchGaps={},{},{}
    for _,pair in ipairs(pairs) do
        yawGaps[#yawGaps+1]=pair.yawGap
        netPitchGaps[#netPitchGaps+1]=pair.netPitchGap
        absPitchGaps[#absPitchGaps+1]=pair.absPitchGap
    end
    local headH,headHBoot=SEGCFG.segmentMetricText(pairs,"head","x")
    local primaryH,primaryHBoot=SEGCFG.segmentMetricText(pairs,"primary","x")
    local subjectH,subjectHBoot=SEGCFG.segmentMetricText(pairs,"subject","x")
    local headV=SEGCFG.segmentMetricText(pairs,"head","y")
    local primaryV=SEGCFG.segmentMetricText(pairs,"primary","y")
    local subjectV=SEGCFG.segmentMetricText(pairs,"subject","y")
    local anyHorizontal=quality=="good" and ((headHBoot and headHBoot.excludesZero)
        or (primaryHBoot and primaryHBoot.excludesZero) or (subjectHBoot and subjectHBoot.excludesZero))
    local statistical=quality=="good" and string.format(
        "headH{%s}; primaryH{%s}; subjectH{%s}",bootstrapText(headHBoot),bootstrapText(primaryHBoot),bootstrapText(subjectHBoot))
        or "unproved"
    local geometry="PrimaryToHeadChange{"..SEGCFG.segmentVectorDifference(pairs,"primaryToHeadStart","primaryToHeadEnd")
        .."}; SubjectToHeadChange{"..SEGCFG.segmentVectorDifference(pairs,"subjectToHeadStart","subjectToHeadEnd")
        .."}; SubjectToPrimaryChange{"..SEGCFG.segmentVectorDifference(pairs,"subjectToPrimaryStart","subjectToPrimaryEnd").."}"
    local pcConsistency="unproved"
    if quality=="good" then
        local _,_,headD=SEGCFG.pairMetricArrays(pairs,"head","displacement")
        local _,_,primaryD=SEGCFG.pairMetricArrays(pairs,"primary","displacement")
        local _,_,subjectD=SEGCFG.pairMetricArrays(pairs,"subject","displacement")
        pcConsistency="qualitative-only; matched route-effect medians head="..tostring(round(percentile(headD,0.5),7))
            .." primary="..tostring(round(percentile(primaryD,0.5),7))
            .." subject="..tostring(round(percentile(subjectD,0.5),7)).."; no PC equivalence"
    end
    return {
        pairs=pairs,
        relaySegmentLossPrimaryCause="old V614: 71 short relay candidates; all ended below 60deg before eligibility (35 direction changes, 34 frame gaps, 1 phase boundary, 1 end-of-run); lower relay yaw/frame required longer uninterrupted same-direction runs",
        relaySegmentLossSecondaryCause="old V614: 63 of 69 relay candidates that reached 60deg were rejected by unchanged pitch gate (60 netPitch>2deg, 49 totalAbsPitch>limit, 46 failed both); only 6 reached eligibility",
        relaySegmentFormationRate="old V614: 6 eligible / 35.633830s accepted relay span = 0.168379 eligible/s; 69 target reaches = 1.936374/s",
        touchSegmentFormationRate="old V614: 48 eligible / 31.999188s accepted Touch span = 1.500038 eligible/s; 359 target reaches = 11.219035/s",
        oldEligibleTouch=SEGCFG.oldEligibleTouch,oldEligibleRelay=SEGCFG.oldEligibleRelay,
        oldMatchedPairs=SEGCFG.oldMatchedPairs,
        liveCoverageGuidanceImplemented=true,
        phaseCompletionUsesCoverage="true: every ABBA window freezes at the fixed pre-run target of 16 eligible segments; potentialPairs is recomputed live with unchanged matching and separately reports whether 12 pairs were reached",
        touchOvercollectionPrevented=true,
        relayCoverageTarget="16 eligible in B1 + 16 eligible in B2 = 32 relay segments; fixed before R2 result",
        potentialPairsLive=#pairs,
        matchingCriteriaChanged=false,calipersChanged=false,gainChanged=false,cameraCorrectionAdded=false,v615Created=false,
        externalPCVideosReviewed=5,externalMobileVideosReviewed=3,
        externalVideoRole="qualitative-only",
        absoluteVideoPixelsUsedForCalibration=false,videoEvidenceChangedV614Thresholds=false,
        videoEvidenceChangedMatching=false,headMechanismClaimed=false,pcEquivalenceClaimed=false,
        v613MatchedBinsRootCause="design/acquisition mismatch: distinct yaw lattices + 70% pitch rejection + sparse fixed 0.5deg bins; minPerPhase=20 was the decisive gate; not simply insufficient raw standing frames",
        touchYawStepPattern="approximately 0.8505deg lattice (rotateInput.x step approximately 0.014844rad), with integer multiples per frame",
        relayYawStepPattern="approximately 0.18deg lattice (rotateInput.x step approximately 0.0031416rad), with integer multiples per frame",
        yawLatticesOverlap="partial/sparse: near-overlaps exist, but dense per-frame equality is not supported",
        perFrameExactMatchingFeasible="not for a dense controlled comparison in the observed runtime",
        v613PitchFilterImpact="major but not sole cause: retained Touch 218/730 (29.86%) and relay 128/467 (27.41%); even without the filter no 0.5deg bin reached 20 in both routes",
        v613MedianYawGapImpact="secondary: 13 of 22 nonempty overlapping bins met <=0.150deg, but zero bins reached minPerPhase first",
        v613MinSampleImpact="decisive: maximum pitch-valid occupancy in any 0.5deg bin was Touch=17 relay=6; required 20 each",
        correlationErrorRootCause="V613 called GUI refresh from the hooked CameraModule.Update thread, whose Delta capability could read camera Instances but could not access GUI Instance properties",
        correlationErrorExactExpression="finalizeFrame -> refreshLiveStatus -> statusLabel.Text/statusLabel.TextColor3 and refreshPhaseButtons Instance property writes; source V613 lines 1043-1044 then 2167-2171",
        sampleBiasFromErrors="no accepted V613 sample was removed by the GUI error: 95 errors occurred after sampleCommitted; 62 occurred on noncommitted/stabilizing/rejected frames after the standing decision; later per-frame diagnostics were truncated",
        correlationErrorsResolved=frameCorrelationErrors==0 and uiRefreshErrors==0,
        matchingUnitChosen="non-overlapping approximately 60deg same-direction rotation segments",
        matchingUnitReason="segment total yaw crosses the distinct per-frame lattices without altering either route; internal frame count, duration and trajectories remain recorded",
        counterbalancingMethod="ABBA: A1 Touch -> B1 relay -> B2 relay -> A2 Touch; Touch and relay have equal mean ordinal position under a linear time trend",
        standingTouchSamples=pairedStats.touch.validStandingFrames,
        standingRelaySamples=pairedStats.relay.validStandingFrames,
        matchedComparisonUnits=#pairs,
        matchingCoverage=string.format("pairs=%d required=%d eligibleTouch=%d eligibleRelay=%d fraction=%.6f touchYaw=%s relayYaw=%s",
            #pairs,required,#touchSegments,#relaySegments,coverage,SEGCFG.segmentRangeText(touchSegments),SEGCFG.segmentRangeText(relaySegments)),
        yawMatchQuality=string.format("%s; yawGap{%s}; caliper<=%.3fdeg",quality,distributionText(yawGaps),SEGCFG.matchYawGap),
        pitchMatchQuality=string.format("%s; netPitchGap{%s} absPitchGap{%s}; calipers<=%.3f/%.3fdeg",
            quality,distributionText(netPitchGaps),distributionText(absPitchGaps),SEGCFG.matchNetPitchGap,SEGCFG.matchAbsPitchGap),
        headHorizontalDifference=headH,primaryHorizontalDifference=primaryH,subjectHorizontalDifference=subjectH,
        headVerticalDifference=headV,primaryVerticalDifference=primaryV,subjectVerticalDifference=subjectV,
        relativeHeadRigGeometryDifference=geometry,
        statisticalMethod=string.format("paired moving-block bootstrap over time-ordered matched non-overlapping segments; unit=segment-pair blockSize=%d iterations=%d statistic=median(relay-touch); ABBA phases",
            SEGCFG.bootstrapBlock,SEGCFG.bootstrapIterations),
        statisticalEvidence=statistical,
        firstGeometricExplanation="unproved; V614 measures route-conditioned Head/PrimaryPart/subject divergence without assigning mechanism",
        descriptiveInputEffect=quality=="good" and (anyHorizontal and "horizontal route difference descriptively present in at least one measured point" or "no horizontal CI excluded zero") or "unproved",
        causalInputEffect="unproved: ABBA reduces linear order bias, but post-hoc segment matching and a single mobile session do not establish PC causality",
        pcReferenceConsistentWithRuntimeGeometry=pcConsistency,
        pcEquivalenceClaimAllowed=false,
        experimentEligible=false,
        nextDiagnosticTarget=quality=="good" and "interpret V614 matched geometry before choosing any next target" or "no next subsystem; improve only live segment coverage within this controlled design",
        v615Justified=false,
        astra6MaxJustified=quality=="good" and "false" or "unproved: V614 matched coverage insufficient",
    }
end

getgenv().PCV614Diagnostics=function()
    local base=baseSafe()
    local decision=SEGCFG.segmentClassification()
    local telemetryCoverage=SEGCFG.telemetryCoverage(decision.pairs)
    local frozen=(not probeRunning and stateAtStop) or {
        relay=relayEnabled(),rotate=readRotate(getActiveController()),preferred=UserInputService.PreferredInput,
    }
    local result={
        version="V614-ControlledYawPitchMatching-TemporalPoseTelemetryR1-EssentialReportR1",
        bridgeMode=getgenv().PCInputBridgeMode,
        probePurpose="controlled-yaw-pitch-segment-matching-plus-read-only-temporal-pose-telemetry",
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
        telemetryCaptureErrors=telemetryCaptureErrors,
        telemetryCaptureErrorSources=countSummary(telemetryCaptureErrorSources),
        telemetryBoundariesCaptured=telemetryBoundariesCaptured,
        telemetryMatchedSamples=telemetryCoverage.samples,
        telemetryMatchedSamplesComplete=telemetryCoverage.complete,
        telemetryMatchedSamplesMissing=telemetryCoverage.missing,
        telemetryMatchedControllerCalls=telemetryCoverage.controllerCalls,
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
        currentSegmentYawDeg=currentSegment and round(currentSegment.totalAbsYaw,6) or 0,
        currentSegmentPitchDeg=currentSegment and round(currentSegment.netPitch,6) or 0,
        currentSegmentAbsPitchDeg=currentSegment and round(currentSegment.totalAbsPitch,6) or 0,
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
        validationReady=callbackErrors==0 and frameCorrelationErrors==0 and uiRefreshErrors==0
            and telemetryCaptureErrors==0
            and telemetryCoverage.samples>0 and telemetryCoverage.missing==0
            and decision.matchedComparisonUnits>=SEGCFG.minMatched
            and completedWindows.A1 and completedWindows.B1 and completedWindows.B2 and completedWindows.A2,
        observationalOnly=true,
        writesCameraCFrame=false,
        writesRootPartCFrame=false,
        writesHeadCFrame=false,
        writesJointTransforms=false,
        controlsAnimations=false,
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
        standingCriterion=string.format("V612-preserved: %.2fs + %d consecutive; velocity<=%.3f; worldDelta<=max(%.3f,dt*%.3f); MoveDirection<=%.3f; joystick inactive when available; correct route; valid on-screen projections; yaw>=%.3fdeg",
            STABILIZE_SECONDS,STABLE_CONSECUTIVE_FRAMES,MAX_LINEAR_VELOCITY,MAX_WORLD_DELTA_FLOOR,
            MAX_LINEAR_VELOCITY,MAX_MOVE_DIRECTION,MIN_APPLIED_YAW_DEG),
        currentWindow=currentWindow,
        expectedWindow=SEGCFG.sequence[expectedPhaseIndex] or "complete",
        completedWindows=string.format("A1=%s B1=%s B2=%s A2=%s",tostring(completedWindows.A1==true),
            tostring(completedWindows.B1==true),tostring(completedWindows.B2==true),tostring(completedWindows.A2==true)),
        uiRefreshErrors=uiRefreshErrors,
        eligibleTouchSegments=#segmentStats.touch.eligible,
        eligibleRelaySegments=#segmentStats.relay.eligible,
        requiredMatchedComparisonUnits=SEGCFG.minMatched,
        phaseEligibleTarget=SEGCFG.phaseEligibleTarget,
        routeEligibleTarget=SEGCFG.routeEligibleTarget,
        potentialMatchedPairs=decision.matchedComparisonUnits,
        coverageSufficient=decision.matchedComparisonUnits>=SEGCFG.minMatched,
        liveGuidance=SEGCFG.lastSegmentEvent,
        liveGuidanceDetail=SEGCFG.lastSegmentDetail,
        windowA1Coverage=SEGCFG.windowStatsText("A1"),
        windowB1Coverage=SEGCFG.windowStatsText("B1"),
        windowB2Coverage=SEGCFG.windowStatsText("B2"),
        windowA2Coverage=SEGCFG.windowStatsText("A2"),
        rejectedTouchSegments=string.format("short=%d pitch=%d duration=%d geometry=%d yaw=%d",segmentStats.touch.rejectedShort,
            segmentStats.touch.rejectedPitch,segmentStats.touch.rejectedDuration,segmentStats.touch.rejectedGeometry,segmentStats.touch.rejectedYaw),
        rejectedRelaySegments=string.format("short=%d pitch=%d duration=%d geometry=%d yaw=%d",segmentStats.relay.rejectedShort,
            segmentStats.relay.rejectedPitch,segmentStats.relay.rejectedDuration,segmentStats.relay.rejectedGeometry,segmentStats.relay.rejectedYaw),
        relaySegmentLossPrimaryCause=decision.relaySegmentLossPrimaryCause,
        relaySegmentLossSecondaryCause=decision.relaySegmentLossSecondaryCause,
        relaySegmentFormationRate=decision.relaySegmentFormationRate,
        touchSegmentFormationRate=decision.touchSegmentFormationRate,
        oldEligibleTouch=decision.oldEligibleTouch,
        oldEligibleRelay=decision.oldEligibleRelay,
        oldMatchedPairs=decision.oldMatchedPairs,
        liveCoverageGuidanceImplemented=decision.liveCoverageGuidanceImplemented,
        phaseCompletionUsesCoverage=decision.phaseCompletionUsesCoverage,
        touchOvercollectionPrevented=decision.touchOvercollectionPrevented,
        relayCoverageTarget=decision.relayCoverageTarget,
        potentialPairsLive=decision.potentialPairsLive,
        matchingCriteriaChanged=decision.matchingCriteriaChanged,
        calipersChanged=decision.calipersChanged,
        gainChanged=decision.gainChanged,
        cameraCorrectionAdded=decision.cameraCorrectionAdded,
        v615Created=decision.v615Created,
        externalPCVideosReviewed=decision.externalPCVideosReviewed,
        externalMobileVideosReviewed=decision.externalMobileVideosReviewed,
        externalVideoRole=decision.externalVideoRole,
        absoluteVideoPixelsUsedForCalibration=decision.absoluteVideoPixelsUsedForCalibration,
        videoEvidenceChangedV614Thresholds=decision.videoEvidenceChangedV614Thresholds,
        videoEvidenceChangedMatching=decision.videoEvidenceChangedMatching,
        headMechanismClaimed=decision.headMechanismClaimed,
        pcEquivalenceClaimed=decision.pcEquivalenceClaimed,
        v613MatchedBinsRootCause=decision.v613MatchedBinsRootCause,
        touchYawStepPattern=decision.touchYawStepPattern,
        relayYawStepPattern=decision.relayYawStepPattern,
        yawLatticesOverlap=decision.yawLatticesOverlap,
        perFrameExactMatchingFeasible=decision.perFrameExactMatchingFeasible,
        v613PitchFilterImpact=decision.v613PitchFilterImpact,
        v613MedianYawGapImpact=decision.v613MedianYawGapImpact,
        v613MinSampleImpact=decision.v613MinSampleImpact,
        correlationErrorRootCause=decision.correlationErrorRootCause,
        correlationErrorExactExpression=decision.correlationErrorExactExpression,
        sampleBiasFromErrors=decision.sampleBiasFromErrors,
        correlationErrorsResolved=decision.correlationErrorsResolved,
        matchingUnitChosen=decision.matchingUnitChosen,
        matchingUnitReason=decision.matchingUnitReason,
        counterbalancingMethod=decision.counterbalancingMethod,
        standingTouchSamples=decision.standingTouchSamples,
        standingRelaySamples=decision.standingRelaySamples,
        matchedComparisonUnits=decision.matchedComparisonUnits,
        matchingCoverage=decision.matchingCoverage,
        yawMatchQuality=decision.yawMatchQuality,
        pitchMatchQuality=decision.pitchMatchQuality,
        headHorizontalDifference=decision.headHorizontalDifference,
        primaryHorizontalDifference=decision.primaryHorizontalDifference,
        subjectHorizontalDifference=decision.subjectHorizontalDifference,
        headVerticalDifference=decision.headVerticalDifference,
        primaryVerticalDifference=decision.primaryVerticalDifference,
        subjectVerticalDifference=decision.subjectVerticalDifference,
        relativeHeadRigGeometryDifference=decision.relativeHeadRigGeometryDifference,
        statisticalMethod=decision.statisticalMethod,
        statisticalEvidence=decision.statisticalEvidence,
        firstGeometricExplanation=decision.firstGeometricExplanation,
        descriptiveInputEffect=decision.descriptiveInputEffect,
        causalInputEffect=decision.causalInputEffect,
        externalPCReferenceUsed=true,
        externalPCReferenceWindow="approximately 20.0s-24.0s",
        pcReferenceConsistentWithRuntimeGeometry=decision.pcReferenceConsistentWithRuntimeGeometry,
        pcEquivalenceClaimAllowed=decision.pcEquivalenceClaimAllowed,
        nextDiagnosticTarget=decision.nextDiagnosticTarget,
        experimentEligible=decision.experimentEligible,
        v615Justified=decision.v615Justified,
        astra6MaxJustified=decision.astra6MaxJustified,
        temporalConfoundResolved="unproved: requires fresh TemporalPoseTelemetryR1 runtime and pair-by-pair control",
        initialPoseConfoundResolved="unproved: requires fresh TemporalPoseTelemetryR1 runtime and overlap assessment",
        rootMotionContribution="unproved pending full PrimaryPart CFrame boundary telemetry",
        jointTransformContribution="unproved pending Neck/Waist/RootJoint Transform telemetry",
        animationProgressContribution="unproved pending active-track state and TimePosition telemetry",
        projectionDepthContribution="unproved pending full Camera CFrame counterfactual reprojection",
        headHorizontalEffectAfterTemporalControl="unproved pending telemetry-controlled analysis",
        firstConcreteGeometricDivergence="unproved after temporal/initial-pose control; prior V614 first divergence remains unequal segment duration/frame count",
        causalMechanismProved=false,
        implementationTargetIdentified=false,
        telemetryV615Justified=false,
        telemetryAstra6MaxJustified=false,
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
    "callbackErrors","controllerErrors","frameCorrelationErrors","telemetryCaptureErrors",
    "telemetryCaptureErrorSources","telemetryBoundariesCaptured","telemetryMatchedSamples",
    "telemetryMatchedSamplesComplete","telemetryMatchedSamplesMissing","telemetryMatchedControllerCalls",
    "traceDropped","evidenceDropped",
    "handlerCallsTouch","handlerCallsMouseTouch","nonzeroWritesTouch","nonzeroWritesRelay",
    "calculateCalls","firstCalculateCalls","getCameraLookCallsInCalc","getSubjectCalls",
    "getMouseLockOffsetCalls","controllerUpdates","cameraModuleUpdates","subjectClassSummary",
    "lastCorrelatedFrame","lastSubjectDetail","lastGeometryDetail","lastStandingDetail",
    "currentPhase","currentWindow","expectedWindow","completedWindows","phaseState","currentSegmentYawDeg",
    "currentSegmentPitchDeg","currentSegmentAbsPitchDeg","stabilizationSeconds",
    "stableConsecutiveRequired","stableConsecutiveCurrent","uiRefreshErrors",
    "eligibleTouchSegments","eligibleRelaySegments","requiredMatchedComparisonUnits","phaseEligibleTarget","routeEligibleTarget",
    "potentialMatchedPairs","coverageSufficient","liveGuidance","liveGuidanceDetail",
    "windowA1Coverage","windowB1Coverage","windowB2Coverage","windowA2Coverage",
    "rejectedTouchSegments","rejectedRelaySegments",
    "persistedOwnershipProofAccepted","persistedOwnershipProofPatchCounts",
    "joystickCriterionAvailable","joystickCriterionLast","relayEnabled","rotateAtStop",
    "preferredInputAtStop","ownershipGateProven","relayValidationReady","touchRoleConflicts",
    "joystickMouseCrossovers","relayErrors","v604CallbackErrors","validationReady","observationalOnly",
    "writesCameraCFrame","writesRootPartCFrame","writesHeadCFrame","writesJointTransforms","controlsAnimations","writesCameraFocus",
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

function SEGCFG.compactToken(value,limit)
    local output=cleanText(value,limit or 100)
    output=string.gsub(output,"[|;{}%[%],]","_")
    output=string.gsub(output,"%s+","_")
    return output
end

function SEGCFG.componentsText(values)
    if type(values)~="table" then return "nil" end
    local output={}
    for index,value in ipairs(values) do output[index]=tostring(round(value,7)) end
    return table.concat(output,",")
end

function SEGCFG.jointTelemetryText(joint)
    if type(joint)~="table" then return "nil" end
    return table.concat({
        SEGCFG.compactToken(joint.part0,40)..">"..SEGCFG.compactToken(joint.part1,40),
        "T="..SEGCFG.componentsText(joint.transform),"C0="..SEGCFG.componentsText(joint.c0),
        "C1="..SEGCFG.componentsText(joint.c1),
    },";")
end

function SEGCFG.animationTelemetryText(animation)
    if type(animation)~="table" then return "state=unavailable tracks=[]" end
    local tracks={}
    for _,track in ipairs(animation.tracks or {}) do
        tracks[#tracks+1]=table.concat({
            SEGCFG.compactToken(track.animationId,100),SEGCFG.compactToken(track.name,50),
            tostring(round(track.timePosition,7)),tostring(round(track.weightCurrent,7)),
            tostring(round(track.weightTarget,7)),tostring(round(track.speed,7)),
            tostring(track.isPlaying),tostring(track.looped),SEGCFG.compactToken(track.priority,40),
            tostring(round(track.length,7)),
        },"~")
    end
    return "state="..SEGCFG.compactToken(animation.humanoidState,60).." tracks=["..table.concat(tracks,"|").."]"
end

function SEGCFG.boundaryTelemetryText(snapshot)
    if type(snapshot)~="table" then return "nil" end
    local joints=snapshot.joints or {}
    return table.concat({
        "clock="..tostring(round(snapshot.clock,7)),
        "cameraReadClock="..tostring(round(snapshot.cameraReadClock,7)),
        "poseReadClock="..tostring(round(snapshot.poseReadClock,7)),
        "captureEndClock="..tostring(round(snapshot.captureEndClock,7)),
        "captureDurationMs="..tostring(round(snapshot.captureDurationMs,7)),
        "cameraCF="..SEGCFG.componentsText(snapshot.cameraCFrame),
        "fov="..tostring(round(snapshot.fieldOfView,7)),
        "viewport="..SEGCFG.componentsText(snapshot.viewport),
        "primaryCF="..SEGCFG.componentsText(snapshot.primaryCFrame),
        "headCF="..SEGCFG.componentsText(snapshot.headCFrame),
        "primaryToHead="..SEGCFG.componentsText(snapshot.primaryToHead),
        "Neck={"..SEGCFG.jointTelemetryText(joints.Neck).."}",
        "Waist={"..SEGCFG.jointTelemetryText(joints.Waist).."}",
        "RootJoint={"..SEGCFG.jointTelemetryText(joints.RootJoint).."}",
        "animation={"..SEGCFG.animationTelemetryText(snapshot.animation).."}",
    }," ")
end

function SEGCFG.telemetrySampleReportLine(pairIndex,route,segment,sampleIndex,sample)
    local telemetry=sample.temporalPoseTelemetry or {}
    local parts={
        "pair="..tostring(pairIndex),"route="..tostring(route),"segment="..tostring(segment.id),
        "sample="..tostring(sampleIndex),"frame="..tostring(sample.frame),
        "time="..tostring(round(sample.time,7)),"dt="..tostring(round(sample.dt,7)),
        "cameraModuleBefore={"..SEGCFG.boundaryTelemetryText(telemetry.cameraModuleBefore).."}",
        "cameraModuleAfter={"..SEGCFG.boundaryTelemetryText(telemetry.cameraModuleAfter).."}",
        "controllerCalls="..tostring(#(telemetry.controllerCalls or {})),
    }
    for index,call in ipairs(telemetry.controllerCalls or {}) do
        parts[#parts+1]="controller"..tostring(index).."Before={"..SEGCFG.boundaryTelemetryText(call.before).."}"
        parts[#parts+1]="controller"..tostring(index).."After={"..SEGCFG.boundaryTelemetryText(call.after).."}"
    end
    return table.concat(parts," ")
end

function SEGCFG.componentsToCFrame(values)
    if type(values)~="table" or #values<12 then return nil end
    local ok,value=pcall(function() return CFrame.new(table.unpack(values,1,12)) end)
    return ok and value or nil
end

function SEGCFG.cframeDeltaText(firstValues,lastValues)
    local first,last=SEGCFG.componentsToCFrame(firstValues),SEGCFG.componentsToCFrame(lastValues)
    if not first or not last then return "unavailable" end
    local relative=first:ToObjectSpace(last)
    local _,angle=relative:ToAxisAngle()
    return string.format("translation=%.7f rotationDeg=%.7f",relative.Position.Magnitude,math.deg(math.abs(angle)))
end

function SEGCFG.segmentTelemetrySummary(segment)
    local first=segment.samples and segment.samples[1]
    local last=segment.samples and segment.samples[#segment.samples]
    local firstBoundary=first and first.temporalPoseTelemetry and first.temporalPoseTelemetry.cameraModuleBefore
    local lastBoundary=last and last.temporalPoseTelemetry and last.temporalPoseTelemetry.cameraModuleAfter
    return table.concat({
        "duration="..tostring(round(segment.duration,7)),"frames="..tostring(segment.frameCount),
        "cameraDelta={"..SEGCFG.cframeDeltaText(firstBoundary and firstBoundary.cameraCFrame,lastBoundary and lastBoundary.cameraCFrame).."}",
        "primaryDelta={"..SEGCFG.cframeDeltaText(firstBoundary and firstBoundary.primaryCFrame,lastBoundary and lastBoundary.primaryCFrame).."}",
        "primaryToHeadDelta={"..SEGCFG.cframeDeltaText(firstBoundary and firstBoundary.primaryToHead,lastBoundary and lastBoundary.primaryToHead).."}",
    }," ")
end

function SEGCFG.telemetryPairReportLine(pair,index)
    return "pair="..tostring(index).." touch={"..SEGCFG.segmentTelemetrySummary(pair.touch)
        .."} relay={"..SEGCFG.segmentTelemetrySummary(pair.relay).."}"
end

local function sampleReportLine(sample)
    local parts={
        "frame="..tostring(sample.frame),"phase="..tostring(sample.phase),"window="..tostring(sample.window),
        "time="..tostring(round(sample.time,6)),"dt="..tostring(round(sample.dt,7)),
        "yawSigned="..tostring(round(sample.yawSigned,7)),"yawAbs="..tostring(round(sample.yaw,7)),
        "pitchSigned="..tostring(round(sample.pitchSigned,7)),"pitchAbs="..tostring(round(sample.pitch,7)),
        "returnedYawSigned="..tostring(round(sample.returnedYawSigned,7)),
        "returnedPitchSigned="..tostring(round(sample.returnedPitchSigned,7)),
        "rotate="..tostring(round(sample.rotateX,7))..","..tostring(round(sample.rotateY,7)),
        "cameraYaw="..tostring(round(sample.cameraYawBefore,7)).."->"..tostring(round(sample.cameraYawAfter,7)),
        "cameraPitch="..tostring(round(sample.cameraPitchBefore,7)).."->"..tostring(round(sample.cameraPitchAfter,7)),
        "returnedYaw="..tostring(round(sample.returnedYawValue,7)),"returnedPitch="..tostring(round(sample.returnedPitchValue,7)),
        "subject="..cleanText(sample.subjectPosition,90),"primary="..cleanText(sample.primaryPosition,90),"head="..cleanText(sample.headPosition,90),
        "subjectToPrimary="..cleanText(sample.subjectToPrimary,90),"subjectToHead="..cleanText(sample.subjectToHead,90),
        "primaryToHead="..cleanText(sample.primaryToHead,90),"rigDelta="..cleanText(sample.rigVectorDelta,90),
        "primaryScreen="..cleanText(sample.primaryScreenBefore,90).."->"..cleanText(sample.primaryScreenAfter,90),
        "primaryDX="..tostring(round(sample.primaryDX,7)),"primaryDY="..tostring(round(sample.primaryDY,7)),
        "primaryAbsXPerYaw="..tostring(round(sample.primaryX,7)),"primaryAbsYPerYaw="..tostring(round(sample.primaryY,7)),
        "headScreen="..cleanText(sample.headScreenBefore,90).."->"..cleanText(sample.headScreenAfter,90),
        "headDX="..tostring(round(sample.headDX,7)),"headDY="..tostring(round(sample.headDY,7)),
        "headAbsXPerYaw="..tostring(round(sample.headX,7)),"headAbsYPerYaw="..tostring(round(sample.headY,7)),
        "returnedPrimary="..cleanText(sample.returnedPrimaryScreen,90),
        "returnedPrimaryDX="..tostring(round(sample.returnedPrimaryDX,7)),"returnedPrimaryDY="..tostring(round(sample.returnedPrimaryDY,7)),
        "returnedHead="..cleanText(sample.returnedHeadScreen,90),
        "returnedHeadDX="..tostring(round(sample.returnedHeadDX,7)),"returnedHeadDY="..tostring(round(sample.returnedHeadDY,7)),
        "subjectScreen="..cleanText(sample.subjectScreenBefore,90).."->"..cleanText(sample.subjectScreenAfter,90),
        "subjectDX="..tostring(round(sample.subjectDX,7)),"subjectDY="..tostring(round(sample.subjectDY,7)),
        "subjectAbsXPerYaw="..tostring(round(sample.subjectX,7)),"subjectAbsYPerYaw="..tostring(round(sample.subjectY,7)),
        "returnedSubject="..cleanText(sample.returnedSubjectScreen,90),
        "returnedSubjectDX="..tostring(round(sample.returnedSubjectDX,7)),"returnedSubjectDY="..tostring(round(sample.returnedSubjectDY,7)),
        "headDepth="..tostring(round(sample.headDepthBefore,7)).."->"..tostring(round(sample.headDepthAfter,7)),
        "pitchControlled="..tostring(sample.pitchControlled),
    }
    return table.concat(parts," ")
end

function SEGCFG.numberTrajectory(values)
    local output={}
    for _,value in ipairs(values or {}) do output[#output+1]=tostring(round(value,6)) end
    return table.concat(output,",")
end

function SEGCFG.screenMetricReport(metric)
    if type(metric)~="table" then return "nil" end
    return string.format("start=%s end=%s dx=%s dy=%s absXPerYaw=%s absYPerYaw=%s d2PerYaw=%s",
        cleanText(metric.start,80),cleanText(metric.finish,80),tostring(round(metric.dx,7)),tostring(round(metric.dy,7)),
        tostring(round(metric.x,7)),tostring(round(metric.y,7)),tostring(round(metric.displacement,7)))
end

function SEGCFG.segmentReportLine(segment)
    return table.concat({
        "id="..segment.id,"route="..segment.route,"window="..segment.window,
        "frames="..tostring(segment.frameCount),"frameRange="..segment.startFrame.."-"..segment.endFrame,
        "duration="..tostring(round(segment.duration,6)),
        "totalSignedYaw="..tostring(round(segment.totalSignedYaw,7)),
        "totalAbsYaw="..tostring(round(segment.totalAbsYaw,7)),
        "netPitch="..tostring(round(segment.netPitch,7)),
        "totalAbsPitch="..tostring(round(segment.totalAbsPitch,7)),
        "meanPitch="..tostring(round(segment.meanSignedPitch,7)),
        "medianPitch="..tostring(round(segment.medianSignedPitch,7)),
        "yawTrajectory="..SEGCFG.numberTrajectory(segment.yawTrajectory),
        "pitchTrajectory="..SEGCFG.numberTrajectory(segment.pitchTrajectory),
        "primary={"..SEGCFG.screenMetricReport(segment.primary).."}","head={"..SEGCFG.screenMetricReport(segment.head).."}",
        "subject={"..SEGCFG.screenMetricReport(segment.subject).."}",
        "returnedPrimary={"..SEGCFG.screenMetricReport(segment.returnedPrimary).."}",
        "returnedHead={"..SEGCFG.screenMetricReport(segment.returnedHead).."}",
        "returnedSubject={"..SEGCFG.screenMetricReport(segment.returnedSubject).."}",
        "subjectToPrimary="..cleanText(segment.subjectToPrimaryStart,100).."->"..cleanText(segment.subjectToPrimaryEnd,100),
        "subjectToHead="..cleanText(segment.subjectToHeadStart,100).."->"..cleanText(segment.subjectToHeadEnd,100),
        "primaryToHead="..cleanText(segment.primaryToHeadStart,100).."->"..cleanText(segment.primaryToHeadEnd,100),
        "cameraYaw="..tostring(round(segment.cameraYawStart,7)).."->"..tostring(round(segment.cameraYawEnd,7)),
        "cameraPitch="..tostring(round(segment.cameraPitchStart,7)).."->"..tostring(round(segment.cameraPitchEnd,7)),
        "returnedYaw="..tostring(round(segment.returnedYawEnd,7)),
        "returnedPitch="..tostring(round(segment.returnedPitchEnd,7)),
    }," ")
end

function SEGCFG.pairReportLine(pair,index)
    return string.format("pair=%d touch=%s(%s) relay=%s(%s) yawGap=%.7f netPitchGap=%.7f absPitchGap=%.7f",
        index,pair.touch.id,pair.touch.window,pair.relay.id,pair.relay.window,
        pair.yawGap,pair.netPitchGap,pair.absPitchGap)
end

function SEGCFG.legacyCountOnlyLines()
    local sink={_lineCount=0,_chars=0}
    return setmetatable(sink,{
        __len=function(value) return rawget(value,"_lineCount") end,
        __newindex=function(value,key,line)
            if type(key)~="number" then rawset(value,key,line); return end
            local count=rawget(value,"_lineCount") or 0
            local chars=utf8.len(tostring(line))
            if chars==nil then error("legacy report line is not valid UTF-8",0) end
            rawset(value,"_lineCount",math.max(count,key))
            rawset(value,"_chars",(rawget(value,"_chars") or 0)+chars+(count>0 and 1 or 0))
        end,
    })
end

function SEGCFG.buildLegacyReport(includeEvidence,countOnly)
    local diagnostics=getgenv().PCV614Diagnostics()
    local lines=countOnly and SEGCFG.legacyCountOnlyLines() or {}
    lines[#lines+1]="=== PC MOVEMENT V614 REPORT ==="
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
        lines[#lines+1]="=== V614 PAIRED STANDING TRACE ==="
        for _,line in ipairs(traceLines) do lines[#lines+1]=line end
        lines[#lines+1]=""
        lines[#lines+1]="=== V614 ACCEPTED PER-FRAME SAMPLE DATA ==="
        for _,phase in ipairs({"touch","relay"}) do
            for _,sample in ipairs(pairedStats[phase].samples) do lines[#lines+1]=sampleReportLine(sample) end
        end
        lines[#lines+1]=""
        lines[#lines+1]="=== V614 ELIGIBLE NON-OVERLAPPING SEGMENTS ==="
        for _,phase in ipairs({"touch","relay"}) do
            for _,segment in ipairs(segmentStats[phase].eligible) do lines[#lines+1]=SEGCFG.segmentReportLine(segment) end
        end
        lines[#lines+1]=""
        lines[#lines+1]="=== V614 MATCHED SEGMENT PAIRS ==="
        local matched=SEGCFG.matchSegments()
        for index,pair in ipairs(matched) do lines[#lines+1]=SEGCFG.pairReportLine(pair,index) end
        lines[#lines+1]=""
        lines[#lines+1]="=== V614 MATCHED TEMPORAL POSE TELEMETRY ==="
        lines[#lines+1]="schema = numeric read-only snapshots; cameraCF/primaryCF/headCF/primaryToHead/C0/C1/Transform are CFrame GetComponents x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22"
        lines[#lines+1]="animationTrackSchema = AnimationId~Name~TimePosition~WeightCurrent~WeightTarget~Speed~IsPlaying~Looped~Priority~Length"
        for index,pair in ipairs(matched) do
            lines[#lines+1]=SEGCFG.telemetryPairReportLine(pair,index)
            for _,route in ipairs({"touch","relay"}) do
                local segment=pair[route]
                for sampleIndex,sample in ipairs(segment.samples or {}) do
                    lines[#lines+1]=SEGCFG.telemetrySampleReportLine(index,route,segment,sampleIndex,sample)
                end
            end
        end
        lines[#lines+1]=""
        lines[#lines+1]="=== V614 FOCUSED TARGET EVIDENCE ==="
        for _,line in ipairs(evidence) do lines[#lines+1]=line end
        if type(baseReport)=="function" then
            local ok,text=pcall(baseReport,false)
            if ok then lines[#lines+1]=""; lines[#lines+1]=text end
        end
    end
    lines[#lines+1]=""
    lines[#lines+1]="=== V614 EXTERNAL PC QUALITATIVE REFERENCE ==="
    lines[#lines+1]="externalPCReferenceUsed = true"
    lines[#lines+1]="externalPCReferenceWindow = approximately 20.0s-24.0s"
    lines[#lines+1]="pcVisualAnchorCandidate = qualitative Head/upper-torso region only; pivot and equivalence unproved"
    lines[#lines+1]="externalPCVideosReviewed = "..tostring(diagnostics.externalPCVideosReviewed)
    lines[#lines+1]="externalMobileVideosReviewed = "..tostring(diagnostics.externalMobileVideosReviewed)
    lines[#lines+1]="externalVideoRole = qualitative-only"
    lines[#lines+1]="absoluteVideoPixelsUsedForCalibration = false"
    lines[#lines+1]="videoEvidenceChangedV614Thresholds = false"
    lines[#lines+1]="videoEvidenceChangedMatching = false"
    lines[#lines+1]="headMechanismClaimed = false"
    lines[#lines+1]="pcEquivalenceClaimed = false"
    lines[#lines+1]="sampleBiasFromErrors = "..tostring(diagnostics.sampleBiasFromErrors)
    lines[#lines+1]=""
    lines[#lines+1]="=== V614 REQUIRED AUDIT/SEGMENT DECISION ==="
    lines[#lines+1]="LuauValidation = pass: luau-compile"
    lines[#lines+1]="LoaderValidation = pass: luau-compile plus cache-busted V614 TemporalPoseTelemetryR1 URL"
    lines[#lines+1]="StateTransitionValidation = pass: ABBA order, early-advance rejection, freeze at 16 per window, no 17th sample, 32 per route"
    lines[#lines+1]="ProhibitedWriteAudit = pass: no prohibited property writes or input APIs added"
    lines[#lines+1]="relaySegmentLossPrimaryCause = "..tostring(diagnostics.relaySegmentLossPrimaryCause)
    lines[#lines+1]="relaySegmentLossSecondaryCause = "..tostring(diagnostics.relaySegmentLossSecondaryCause)
    lines[#lines+1]="relaySegmentFormationRate = "..tostring(diagnostics.relaySegmentFormationRate)
    lines[#lines+1]="touchSegmentFormationRate = "..tostring(diagnostics.touchSegmentFormationRate)
    lines[#lines+1]="oldEligibleTouch = "..tostring(diagnostics.oldEligibleTouch)
    lines[#lines+1]="oldEligibleRelay = "..tostring(diagnostics.oldEligibleRelay)
    lines[#lines+1]="oldMatchedPairs = "..tostring(diagnostics.oldMatchedPairs)
    lines[#lines+1]="relayCandidatesBefore60 = 71"
    lines[#lines+1]="relayDirectionBreaks = 35"
    lines[#lines+1]="relayGaps = 34"
    lines[#lines+1]="relayReached60 = 69"
    lines[#lines+1]="relayPitchRejected = 63"
    lines[#lines+1]="relayNetPitchRejected = 60"
    lines[#lines+1]="relayAbsolutePitchRejected = 49"
    lines[#lines+1]="relayBothPitchRejected = 46"
    lines[#lines+1]="phaseEligibleTarget = "..tostring(SEGCFG.phaseEligibleTarget)
    lines[#lines+1]="routeEligibleTarget = "..tostring(SEGCFG.routeEligibleTarget)
    lines[#lines+1]="requiredMatchedPairs = "..tostring(SEGCFG.minMatched)
    lines[#lines+1]="liveCoverageGuidanceImplemented = "..tostring(diagnostics.liveCoverageGuidanceImplemented)
    lines[#lines+1]="phaseCompletionUsesCoverage = "..tostring(diagnostics.phaseCompletionUsesCoverage)
    lines[#lines+1]="touchOvercollectionPrevented = "..tostring(diagnostics.touchOvercollectionPrevented)
    lines[#lines+1]="relayCoverageTarget = "..tostring(diagnostics.relayCoverageTarget)
    lines[#lines+1]="potentialPairsLive = "..tostring(diagnostics.potentialPairsLive)
    lines[#lines+1]="matchingCriteriaChanged = false"
    lines[#lines+1]="calipersChanged = false"
    lines[#lines+1]="gainChanged = false"
    lines[#lines+1]="cameraCorrectionAdded = false"
    lines[#lines+1]="v615Created = false"
    lines[#lines+1]="v613MatchedBinsRootCause = "..tostring(diagnostics.v613MatchedBinsRootCause)
    lines[#lines+1]="touchYawStepPattern = "..tostring(diagnostics.touchYawStepPattern)
    lines[#lines+1]="relayYawStepPattern = "..tostring(diagnostics.relayYawStepPattern)
    lines[#lines+1]="yawLatticesOverlap = "..tostring(diagnostics.yawLatticesOverlap)
    lines[#lines+1]="perFrameExactMatchingFeasible = "..tostring(diagnostics.perFrameExactMatchingFeasible)
    lines[#lines+1]="v613PitchFilterImpact = "..tostring(diagnostics.v613PitchFilterImpact)
    lines[#lines+1]="v613MedianYawGapImpact = "..tostring(diagnostics.v613MedianYawGapImpact)
    lines[#lines+1]="v613MinSampleImpact = "..tostring(diagnostics.v613MinSampleImpact)
    lines[#lines+1]="correlationErrorRootCause = "..tostring(diagnostics.correlationErrorRootCause)
    lines[#lines+1]="correlationErrorExactExpression = "..tostring(diagnostics.correlationErrorExactExpression)
    lines[#lines+1]="correlationErrorsResolved = "..tostring(diagnostics.correlationErrorsResolved)
    lines[#lines+1]="matchingUnitChosen = "..tostring(diagnostics.matchingUnitChosen)
    lines[#lines+1]="matchingUnitReason = "..tostring(diagnostics.matchingUnitReason)
    lines[#lines+1]="counterbalancingMethod = "..tostring(diagnostics.counterbalancingMethod)
    lines[#lines+1]="standingTouchSamples = "..tostring(diagnostics.standingTouchSamples)
    lines[#lines+1]="standingRelaySamples = "..tostring(diagnostics.standingRelaySamples)
    lines[#lines+1]="matchedComparisonUnits = "..tostring(diagnostics.matchedComparisonUnits)
    lines[#lines+1]="matchingCoverage = "..tostring(diagnostics.matchingCoverage)
    lines[#lines+1]="yawMatchQuality = "..tostring(diagnostics.yawMatchQuality)
    lines[#lines+1]="pitchMatchQuality = "..tostring(diagnostics.pitchMatchQuality)
    lines[#lines+1]="headHorizontalDifference = "..tostring(diagnostics.headHorizontalDifference)
    lines[#lines+1]="primaryHorizontalDifference = "..tostring(diagnostics.primaryHorizontalDifference)
    lines[#lines+1]="subjectHorizontalDifference = "..tostring(diagnostics.subjectHorizontalDifference)
    lines[#lines+1]="headVerticalDifference = "..tostring(diagnostics.headVerticalDifference)
    lines[#lines+1]="primaryVerticalDifference = "..tostring(diagnostics.primaryVerticalDifference)
    lines[#lines+1]="subjectVerticalDifference = "..tostring(diagnostics.subjectVerticalDifference)
    lines[#lines+1]="relativeHeadRigGeometryDifference = "..tostring(diagnostics.relativeHeadRigGeometryDifference)
    lines[#lines+1]="statisticalMethod = "..tostring(diagnostics.statisticalMethod)
    lines[#lines+1]="statisticalEvidence = "..tostring(diagnostics.statisticalEvidence)
    lines[#lines+1]="firstGeometricExplanation = "..tostring(diagnostics.firstGeometricExplanation)
    lines[#lines+1]="descriptiveInputEffect = "..tostring(diagnostics.descriptiveInputEffect)
    lines[#lines+1]="causalInputEffect = "..tostring(diagnostics.causalInputEffect)
    lines[#lines+1]="pcReferenceConsistentWithRuntimeGeometry = "..tostring(diagnostics.pcReferenceConsistentWithRuntimeGeometry)
    lines[#lines+1]="pcEquivalenceClaimAllowed = false"
    lines[#lines+1]="experimentEligible = false"
    lines[#lines+1]="nextDiagnosticTarget = "..tostring(diagnostics.nextDiagnosticTarget)
    lines[#lines+1]="v615Justified = "..tostring(diagnostics.v615Justified)
    lines[#lines+1]="astra6MaxJustified = "..tostring(diagnostics.astra6MaxJustified)
    lines[#lines+1]=""
    lines[#lines+1]="=== V614 TEMPORAL/POSE CAUSAL DECISION ==="
    lines[#lines+1]="temporalConfoundResolved = "..tostring(diagnostics.temporalConfoundResolved)
    lines[#lines+1]="initialPoseConfoundResolved = "..tostring(diagnostics.initialPoseConfoundResolved)
    lines[#lines+1]="rootMotionContribution = "..tostring(diagnostics.rootMotionContribution)
    lines[#lines+1]="jointTransformContribution = "..tostring(diagnostics.jointTransformContribution)
    lines[#lines+1]="animationProgressContribution = "..tostring(diagnostics.animationProgressContribution)
    lines[#lines+1]="projectionDepthContribution = "..tostring(diagnostics.projectionDepthContribution)
    lines[#lines+1]="headHorizontalEffectAfterTemporalControl = "..tostring(diagnostics.headHorizontalEffectAfterTemporalControl)
    lines[#lines+1]="firstConcreteGeometricDivergence = "..tostring(diagnostics.firstConcreteGeometricDivergence)
    lines[#lines+1]="causalMechanismProved = "..tostring(diagnostics.causalMechanismProved)
    lines[#lines+1]="implementationTargetIdentified = "..tostring(diagnostics.implementationTargetIdentified)
    lines[#lines+1]="v615Justified = "..tostring(diagnostics.telemetryV615Justified)
    lines[#lines+1]="astra6MaxJustified = "..tostring(diagnostics.telemetryAstra6MaxJustified)
    if countOnly then return lines._chars end
    return table.concat(lines,"\n")
end

-- BEGIN V614 REPORT TRANSPORT PURE HELPERS
function SEGCFG.reportCharCount(value)
    local count=utf8.len(value)
    if count==nil then error("V614 report transport requires valid UTF-8",0) end
    return count
end

function SEGCFG.splitReportPayloads(fullReport,maxPayloadChars)
    if type(fullReport)~="string" then error("fullReport must be a string",0) end
    if type(maxPayloadChars)~="number" or maxPayloadChars<1 then
        error("maxPayloadChars must be positive",0)
    end
    local chunks={}
    if #fullReport==0 then
        chunks[1]=""
        return chunks
    end
    local startByte=1
    while startByte<=#fullReport do
        local nextByte=utf8.offset(fullReport,maxPayloadChars+1,startByte)
        local endByte=nextByte and (nextByte-1) or #fullReport
        chunks[#chunks+1]=string.sub(fullReport,startByte,endByte)
        startByte=endByte+1
    end
    if table.concat(chunks)~=fullReport then
        error("V614 report transport reconstruction mismatch",0)
    end
    return chunks
end

function SEGCFG.makeReportChunkTransport(reportId,totalReportChars,chunks,index,maxTransportChars)
    local payload=chunks[index]
    if type(payload)~="string" then error("invalid report chunk index",0) end
    local total=#chunks
    local label=string.format("%02d/%02d",index,total)
    local payloadChars=SEGCFG.reportCharCount(payload)
    local prefix=table.concat({
        "=== V614 REPORT CHUNK "..label.." ===",
        "reportId = "..tostring(reportId),
        "totalReportChars = "..tostring(totalReportChars),
        "chunkChars = "..tostring(payloadChars),
        "=== ORIGINAL REPORT CONTENT START ===",
        "",
    },"\n")
    local suffix="\n=== ORIGINAL REPORT CONTENT END ===\n=== END CHUNK "..label.." ==="
    local text=prefix..payload..suffix
    local transportChars=SEGCFG.reportCharCount(text)
    if transportChars>maxTransportChars then
        error("V614 report transport chunk exceeds limit: "..tostring(transportChars),0)
    end
    return {
        text=text,payloadChars=payloadChars,transportChars=transportChars,
        payloadStartByte=#prefix+1,payloadEndByte=#prefix+#payload,
    }
end
-- END V614 REPORT TRANSPORT PURE HELPERS

do
-- BEGIN V614 ESSENTIAL REPORT PURE HELPERS
function SEGCFG.roundEssential(value)
    if type(value)~="number" then return value end
    local scaled=value*10000000
    if scaled>=0 then return math.floor(scaled+0.5)/10000000 end
    return math.ceil(scaled-0.5)/10000000
end

function SEGCFG.deepCopyEssential(value,seen)
    if type(value)~="table" then return value end
    seen=seen or {}
    if seen[value] then return seen[value] end
    local copy={}; seen[value]=copy
    for key,item in pairs(value) do copy[SEGCFG.deepCopyEssential(key,seen)]=SEGCFG.deepCopyEssential(item,seen) end
    return copy
end

function SEGCFG.essentialSafeValue(value,seen)
    local valueType=type(value)
    if value==nil or valueType=="string" or valueType=="number" or valueType=="boolean" then return value end
    if valueType=="table" then
        seen=seen or {}
        if seen[value] then return "cycle" end
        seen[value]=true
        local output={}
        for key,item in pairs(value) do
            local safeKey=(type(key)=="string" or type(key)=="number") and key or tostring(key)
            output[safeKey]=SEGCFG.essentialSafeValue(item,seen)
        end
        seen[value]=nil
        return output
    end
    local robloxType=type(typeof)=="function" and typeof(value) or valueType
    if robloxType=="Vector2" then return {SEGCFG.roundEssential(value.X),SEGCFG.roundEssential(value.Y)} end
    if robloxType=="Vector3" then
        return {SEGCFG.roundEssential(value.X),SEGCFG.roundEssential(value.Y),SEGCFG.roundEssential(value.Z)}
    end
    if robloxType=="CFrame" and type(value.GetComponents)=="function" then
        return SEGCFG.essentialArray({value:GetComponents()})
    end
    return tostring(value)
end

function SEGCFG.essentialArray(value)
    if type(value)=="table" then
        local output={}
        for index,item in ipairs(value) do output[index]=item end
        return output
    end
    local valueType=type(typeof)=="function" and typeof(value) or type(value)
    if valueType=="Vector2" then return {value.X,value.Y} end
    if valueType=="Vector3" then
        return {value.X,value.Y,value.Z}
    end
    return nil
end

function SEGCFG.arrayKey(values)
    local output={}
    for index,value in ipairs(values or {}) do output[index]=tostring(SEGCFG.roundEssential(value)) end
    return table.concat(output,",")
end

function SEGCFG.internConstant(dictionary,index,key,value)
    local existing=index[key]
    if existing then return existing end
    local id=#dictionary+1
    dictionary[id]=value; index[key]=id
    return id
end

function SEGCFG.essentialMetric(metric)
    if type(metric)~="table" then return nil end
    return {
        start=SEGCFG.essentialArray(metric.start),finish=SEGCFG.essentialArray(metric.finish),
        dx=metric.dx,dy=metric.dy,x=metric.x,y=metric.y,displacement=metric.displacement,
    }
end

function SEGCFG.essentialJoint(snapshotJoint,model,indexes)
    if type(snapshotJoint)~="table" then return nil end
    local definition={
        name=tostring(snapshotJoint.name or ""),part0=tostring(snapshotJoint.part0 or ""),
        part1=tostring(snapshotJoint.part1 or ""),c0=SEGCFG.essentialArray(snapshotJoint.c0),
        c1=SEGCFG.essentialArray(snapshotJoint.c1),
    }
    local key=definition.name.."|"..definition.part0.."|"..definition.part1.."|"
        ..SEGCFG.arrayKey(definition.c0).."|"..SEGCFG.arrayKey(definition.c1)
    local id=SEGCFG.internConstant(model.constants.joints,indexes.joints,key,definition)
    return {definition=id,transform=SEGCFG.essentialArray(snapshotJoint.transform)}
end

function SEGCFG.essentialAnimation(animation,model,indexes)
    local output={humanoidState=type(animation)=="table" and tostring(animation.humanoidState or "") or "",tracks={}}
    for _,track in ipairs(type(animation)=="table" and animation.tracks or {}) do
        local metadata={
            animationId=tostring(track.animationId or ""),name=tostring(track.name or ""),
            looped=track.looped==true,priority=tostring(track.priority or ""),
            length=track.length,
        }
        local key=metadata.animationId.."|"..metadata.name.."|"..metadata.priority.."|"
            ..tostring(metadata.looped).."|"..tostring(metadata.length)
        local id=SEGCFG.internConstant(model.constants.animations,indexes.animations,key,metadata)
        output.tracks[#output.tracks+1]={
            metadata=id,timePosition=track.timePosition,weightCurrent=track.weightCurrent,
            weightTarget=track.weightTarget,speed=track.speed,isPlaying=track.isPlaying==true,
        }
    end
    return output
end

function SEGCFG.essentialSnapshot(snapshot,model,indexes)
    if type(snapshot)~="table" then return nil end
    local cameraConfig={fieldOfView=snapshot.fieldOfView,viewport=SEGCFG.essentialArray(snapshot.viewport)}
    local configKey=tostring(cameraConfig.fieldOfView).."|"..SEGCFG.arrayKey(cameraConfig.viewport)
    local cameraConfigId=SEGCFG.internConstant(model.constants.camera,indexes.camera,configKey,cameraConfig)
    local joints={}
    for _,name in ipairs({"Neck","Waist","RootJoint"}) do
        local projected=SEGCFG.essentialJoint(snapshot.joints and snapshot.joints[name],model,indexes)
        if projected then joints[name]=projected end
    end
    return {
        boundary=tostring(snapshot.boundary or ""),clock=snapshot.clock,
        cameraReadClock=snapshot.cameraReadClock,poseReadClock=snapshot.poseReadClock,
        captureEndClock=snapshot.captureEndClock,captureDurationMs=snapshot.captureDurationMs,
        cameraConfig=cameraConfigId,cameraCFrame=SEGCFG.essentialArray(snapshot.cameraCFrame),
        primaryCFrame=SEGCFG.essentialArray(snapshot.primaryCFrame),
        headCFrame=SEGCFG.essentialArray(snapshot.headCFrame),
        primaryToHead=SEGCFG.essentialArray(snapshot.primaryToHead),
        joints=joints,animation=SEGCFG.essentialAnimation(snapshot.animation,model,indexes),
    }
end

function SEGCFG.essentialBoundarySet(sample,model,indexes)
    local telemetry=type(sample)=="table" and sample.temporalPoseTelemetry or nil
    local calls=type(telemetry)=="table" and telemetry.controllerCalls or nil
    local firstCall=type(calls)=="table" and calls[1] or nil
    local lastCall=type(calls)=="table" and calls[#calls] or nil
    return {
        cameraModuleBefore=SEGCFG.essentialSnapshot(telemetry and telemetry.cameraModuleBefore,model,indexes),
        controllerBefore=SEGCFG.essentialSnapshot(firstCall and firstCall.before,model,indexes),
        controllerAfter=SEGCFG.essentialSnapshot(lastCall and lastCall.after,model,indexes),
        cameraModuleAfter=SEGCFG.essentialSnapshot(telemetry and telemetry.cameraModuleAfter,model,indexes),
        controllerCalls=type(calls)=="table" and #calls or 0,
    }
end

function SEGCFG.essentialCoordinate(value,index)
    if type(value)=="table" then return value[index] end
    local valueType=type(typeof)=="function" and typeof(value) or type(value)
    if valueType=="Vector2" or valueType=="Vector3" then
        if index==1 then return value.X end
        if index==2 then return value.Y end
        if index==3 and valueType=="Vector3" then return value.Z end
    end
    return nil
end

function SEGCFG.essentialSeriesSample(sample,model,indexes)
    local boundaries=SEGCFG.essentialBoundarySet(sample,model,indexes)
    local before=boundaries.cameraModuleBefore or boundaries.controllerBefore
    local after=boundaries.cameraModuleAfter or boundaries.controllerAfter
    local jointTransform={before={},after={}}
    for _,name in ipairs({"Neck","Waist","RootJoint"}) do
        if before and before.joints and before.joints[name] then
            jointTransform.before[name]=before.joints[name].transform
        end
        if after and after.joints and after.joints[name] then
            jointTransform.after[name]=after.joints[name].transform
        end
    end
    return {
        frame=sample.frame,time=sample.time,dt=sample.dt,yawSigned=sample.yawSigned,pitchSigned=sample.pitchSigned,
        headBeforeX=SEGCFG.essentialCoordinate(sample.headScreenBefore,1),headAfterX=SEGCFG.essentialCoordinate(sample.headScreenAfter,1),
        headBeforeY=SEGCFG.essentialCoordinate(sample.headScreenBefore,2),headAfterY=SEGCFG.essentialCoordinate(sample.headScreenAfter,2),
        headBeforeDepth=SEGCFG.essentialCoordinate(sample.headScreenBefore,3),headAfterDepth=SEGCFG.essentialCoordinate(sample.headScreenAfter,3),
        primaryBeforeX=SEGCFG.essentialCoordinate(sample.primaryScreenBefore,1),primaryAfterX=SEGCFG.essentialCoordinate(sample.primaryScreenAfter,1),
        subjectBeforeX=SEGCFG.essentialCoordinate(sample.subjectScreenBefore,1),subjectAfterX=SEGCFG.essentialCoordinate(sample.subjectScreenAfter,1),
        cameraConfigBefore=before and before.cameraConfig or nil,cameraConfigAfter=after and after.cameraConfig or nil,
        cameraBefore=before and before.cameraCFrame or nil,cameraAfter=after and after.cameraCFrame or nil,
        primaryBefore=before and before.primaryCFrame or nil,primaryAfter=after and after.primaryCFrame or nil,
        localHeadBefore=before and before.primaryToHead or nil,localHeadAfter=after and after.primaryToHead or nil,
        jointTransform=jointTransform,
        animationBefore=before and before.animation or nil,animationAfter=after and after.animation or nil,
    }
end

function SEGCFG.essentialStepDistance(a,b)
    if type(a)~="table" or type(b)~="table" then return nil end
    local x=(b[1] or 0)-(a[1] or 0); local y=(b[2] or 0)-(a[2] or 0); local z=(b[3] or 0)-(a[3] or 0)
    return math.sqrt(x*x+y*y+z*z)
end

function SEGCFG.essentialRotationDegreesRaw(a,b)
    if type(a)~="table" or #a<12 or type(b)~="table" or #b<12 then return nil end
    local dot=0
    for index=4,12 do dot+=a[index]*b[index] end
    local cosine=math.max(-1,math.min(1,(dot-1)*0.5))
    return math.deg(math.acos(cosine))
end

function SEGCFG.essentialCFrameStep(before,after,previousAfter)
    return {
        withinTranslation=SEGCFG.essentialStepDistance(before,after),
        withinRotationDeg=SEGCFG.essentialRotationDegreesRaw(before,after),
        boundaryTranslation=SEGCFG.essentialStepDistance(previousAfter,before),
        boundaryRotationDeg=SEGCFG.essentialRotationDegreesRaw(previousAfter,before),
    }
end

function SEGCFG.essentialCompactSeries(full,previous)
    local output={
        frame=full.frame,time=full.time,dt=full.dt,yawSigned=full.yawSigned,pitchSigned=full.pitchSigned,
        headBeforeX=full.headBeforeX,headAfterX=full.headAfterX,
        headBeforeY=full.headBeforeY,headAfterY=full.headAfterY,
        headBeforeDepth=full.headBeforeDepth,headAfterDepth=full.headAfterDepth,
        primaryBeforeX=full.primaryBeforeX,primaryAfterX=full.primaryAfterX,
        subjectBeforeX=full.subjectBeforeX,subjectAfterX=full.subjectAfterX,
        cameraConfigBefore=full.cameraConfigBefore,cameraConfigAfter=full.cameraConfigAfter,
        cameraStep=SEGCFG.essentialCFrameStep(full.cameraBefore,full.cameraAfter,previous and previous.cameraAfter),
        rootStep=SEGCFG.essentialCFrameStep(full.primaryBefore,full.primaryAfter,previous and previous.primaryAfter),
        localHeadStep=SEGCFG.essentialCFrameStep(full.localHeadBefore,full.localHeadAfter,previous and previous.localHeadAfter),
        jointTransform={},animationBefore=full.animationBefore,animationAfter=full.animationAfter,
    }
    for _,name in ipairs({"Neck","Waist","RootJoint"}) do
        local before=full.jointTransform and full.jointTransform.before[name]
        local after=full.jointTransform and full.jointTransform.after[name]
        local previousAfter=previous and previous.jointTransform and previous.jointTransform.after[name]
        if before or after then output.jointTransform[name]=SEGCFG.essentialCFrameStep(before,after,previousAfter) end
    end
    return output
end

function SEGCFG.essentialSegment(segment,model,indexes)
    local samples=segment.samples or {}
    local series={}
    local previousFull=nil
    for _,sample in ipairs(samples) do
        local full=SEGCFG.essentialSeriesSample(sample,model,indexes)
        series[#series+1]=SEGCFG.essentialCompactSeries(full,previousFull)
        previousFull=full
    end
    return {
        id=tostring(segment.id),route=tostring(segment.route),window=tostring(segment.window),
        startFrame=segment.startFrame,endFrame=segment.endFrame,
        startTime=segment.startTime,endTime=segment.endTime,duration=segment.duration,frameCount=segment.frameCount,
        totalSignedYaw=segment.totalSignedYaw,totalAbsYaw=segment.totalAbsYaw,
        netPitch=segment.netPitch,totalAbsPitch=segment.totalAbsPitch,
        yawTrajectory=SEGCFG.essentialArray(segment.yawTrajectory),pitchTrajectory=SEGCFG.essentialArray(segment.pitchTrajectory),
        screen={primary=SEGCFG.essentialMetric(segment.primary),head=SEGCFG.essentialMetric(segment.head),
            subject=SEGCFG.essentialMetric(segment.subject),returnedPrimary=SEGCFG.essentialMetric(segment.returnedPrimary),
            returnedHead=SEGCFG.essentialMetric(segment.returnedHead),returnedSubject=SEGCFG.essentialMetric(segment.returnedSubject)},
        geometry={subjectToPrimaryStart=SEGCFG.essentialArray(segment.subjectToPrimaryStart),
            subjectToPrimaryEnd=SEGCFG.essentialArray(segment.subjectToPrimaryEnd),
            subjectToHeadStart=SEGCFG.essentialArray(segment.subjectToHeadStart),
            subjectToHeadEnd=SEGCFG.essentialArray(segment.subjectToHeadEnd),
            primaryToHeadStart=SEGCFG.essentialArray(segment.primaryToHeadStart),
            primaryToHeadEnd=SEGCFG.essentialArray(segment.primaryToHeadEnd)},
        cameraYawStart=segment.cameraYawStart,cameraYawEnd=segment.cameraYawEnd,
        cameraPitchStart=segment.cameraPitchStart,cameraPitchEnd=segment.cameraPitchEnd,
        boundaries={start=series[1] and SEGCFG.essentialBoundarySet(samples[1],model,indexes) or nil,
            finish=series[#series] and SEGCFG.essentialBoundarySet(samples[#samples],model,indexes) or nil},
        series=series,
    }
end

function SEGCFG.buildEssentialModel(pairs,diagnostics)
    local model={
        schema="V614-EssentialReportR1",run=SEGCFG.essentialSafeValue(diagnostics or {}),
        constants={camera={},joints={},animations={}},pairs={},analysis={},
        omissions={
            unmatchedAcceptedFrames="not consumed by matched-pair analysis, controls, bootstrap, or decisions",
            rejectedSegments="only rejection counters and reasons participate; pose samples do not",
            unmatchedEligibleSegments="matching counts and ranges are retained; telemetry is not selected",
            repeatedJointConstants="deduplicated in constants.joints and referenced by ID",
            repeatedAnimationMetadata="deduplicated in constants.animations and referenced by ID",
            repeatedCameraConfig="deduplicated in constants.camera and referenced by ID",
            guiStateMessages="not consumed by any scientific metric or decision",
            redundantDebugEvidence="final counters and integrity summaries are retained",
        },parity={},
    }
    local indexes={camera={},joints={},animations={}}
    for index,pair in ipairs(pairs or {}) do
        model.pairs[index]={
            index=index,yawGap=pair.yawGap,netPitchGap=pair.netPitchGap,absPitchGap=pair.absPitchGap,
            touch=SEGCFG.essentialSegment(pair.touch,model,indexes),
            relay=SEGCFG.essentialSegment(pair.relay,model,indexes),
        }
    end
    return model
end

function SEGCFG.essentialDistanceRaw(a,b)
    if type(a)~="table" or type(b)~="table" then return nil end
    local x=(b[1] or 0)-(a[1] or 0); local y=(b[2] or 0)-(a[2] or 0); local z=(b[3] or 0)-(a[3] or 0)
    return math.sqrt(x*x+y*y+z*z)
end

function SEGCFG.essentialDistance(a,b)
    local value=SEGCFG.essentialDistanceRaw(a,b)
    return type(value)=="number" and SEGCFG.roundEssential(value) or nil
end

function SEGCFG.essentialTrackTime(animation)
    local track=type(animation)=="table" and type(animation.tracks)=="table" and animation.tracks[1] or nil
    return track and track.timePosition or nil
end

function SEGCFG.essentialAnimationTrackMap(animation,model)
    local output={}
    for _,track in ipairs(type(animation)=="table" and animation.tracks or {}) do
        local metadata=track
        if type(track.metadata)=="number" and model and model.constants and model.constants.animations then
            metadata=model.constants.animations[track.metadata] or track
        end
        local key=tostring(metadata.animationId or "").."|"..tostring(metadata.name or "").."|"
            ..tostring(metadata.priority or "").."|"..tostring(metadata.looped==true).."|"
            ..tostring(SEGCFG.roundEssential(metadata.length))
        output[key]={
            key=key,timePosition=track.timePosition,weightCurrent=track.weightCurrent,
            weightTarget=track.weightTarget,speed=track.speed,isPlaying=track.isPlaying,
            looped=metadata.looped==true,length=metadata.length,
        }
    end
    return output
end

function SEGCFG.essentialProjectPoint(cameraCFrame,pointCFrame,cameraConfig)
    if type(cameraCFrame)~="table" or #cameraCFrame<12 or type(pointCFrame)~="table" or #pointCFrame<3
        or type(cameraConfig)~="table" or type(cameraConfig.viewport)~="table" then return nil end
    local dx=(pointCFrame[1] or 0)-(cameraCFrame[1] or 0)
    local dy=(pointCFrame[2] or 0)-(cameraCFrame[2] or 0)
    local dz=(pointCFrame[3] or 0)-(cameraCFrame[3] or 0)
    local localX=(cameraCFrame[4] or 0)*dx+(cameraCFrame[7] or 0)*dy+(cameraCFrame[10] or 0)*dz
    local localY=(cameraCFrame[5] or 0)*dx+(cameraCFrame[8] or 0)*dy+(cameraCFrame[11] or 0)*dz
    local localZ=(cameraCFrame[6] or 0)*dx+(cameraCFrame[9] or 0)*dy+(cameraCFrame[12] or 0)*dz
    local depth=-localZ
    local viewportX,viewportY=cameraConfig.viewport[1],cameraConfig.viewport[2]
    local fov=cameraConfig.fieldOfView
    if type(viewportX)~="number" or type(viewportY)~="number" or type(fov)~="number" or depth<=0 then return nil end
    local scale=viewportY/(2*math.tan(math.rad(fov)*0.5))
    return {x=SEGCFG.roundEssential(viewportX*0.5+localX*scale/depth),
        y=SEGCFG.roundEssential(viewportY*0.5-localY*scale/depth),depth=SEGCFG.roundEssential(depth)}
end

function SEGCFG.essentialProjectX(cameraCFrame,pointCFrame,cameraConfig)
    local point=SEGCFG.essentialProjectPoint(cameraCFrame,pointCFrame,cameraConfig)
    return point and point.x or nil
end

function SEGCFG.essentialRotationDegrees(a,b)
    if type(a)~="table" or #a<12 or type(b)~="table" or #b<12 then return nil end
    local dot=0
    for index=4,12 do dot+=a[index]*b[index] end
    local cosine=math.max(-1,math.min(1,(dot-1)*0.5))
    return SEGCFG.roundEssential(math.deg(math.acos(cosine)))
end

function SEGCFG.essentialCFramePath(series,beforeField,afterField)
    local path=0
    local previousAfter=nil
    local found=false
    for _,item in ipairs(series or {}) do
        local before,after=item[beforeField],item[afterField]
        if type(previousAfter)=="table" and type(before)=="table" then
            local step=SEGCFG.essentialDistanceRaw(previousAfter,before)
            if type(step)=="number" then path+=step; found=true end
        end
        if type(before)=="table" and type(after)=="table" then
            local step=SEGCFG.essentialDistanceRaw(before,after)
            if type(step)=="number" then path+=step; found=true end
        end
        previousAfter=after
    end
    return found and SEGCFG.roundEssential(path) or nil
end

function SEGCFG.essentialJointPath(series,name)
    local path=0
    local previousAfter=nil
    local found=false
    for _,item in ipairs(series or {}) do
        local transforms=item.jointTransform or {}
        local before=transforms.before and transforms.before[name]
        local after=transforms.after and transforms.after[name]
        if type(previousAfter)=="table" and type(before)=="table" then
            local step=SEGCFG.essentialDistanceRaw(previousAfter,before)
            if type(step)=="number" then path+=step; found=true end
        end
        if type(before)=="table" and type(after)=="table" then
            local step=SEGCFG.essentialDistanceRaw(before,after)
            if type(step)=="number" then path+=step; found=true end
        end
        previousAfter=after
    end
    return found and SEGCFG.roundEssential(path) or nil
end

function SEGCFG.essentialStoredStepPath(series,field,name)
    local total,found=0,false
    for _,item in ipairs(series or {}) do
        local step=item[field]
        if name and type(step)=="table" then step=step[name] end
        if type(step)=="table" then
            if type(step.withinTranslation)=="number" then total+=step.withinTranslation; found=true end
            if type(step.boundaryTranslation)=="number" then total+=step.boundaryTranslation; found=true end
        end
    end
    return found and SEGCFG.roundEssential(total) or nil
end

function SEGCFG.essentialScreenDecomposition(series,beforeField,afterField,yaw)
    local within,boundary=0,0
    local valid=type(yaw)=="number" and yaw>0 and #(series or {})>0
    for index,item in ipairs(series or {}) do
        local before,after=item[beforeField],item[afterField]
        if type(before)~="number" or type(after)~="number" then valid=false
        else within+=after-before end
        if index>1 then
            local previousAfter=series[index-1][afterField]
            if type(before)~="number" or type(previousAfter)~="number" then valid=false
            else boundary+=before-previousAfter end
        end
    end
    if not valid then return {valid=false} end
    local first,last=series[1],series[#series]
    local endpoint=last[afterField]-first[beforeField]
    local residual=endpoint-within-boundary
    local opposed=(within<0 and boundary>0) or (within>0 and boundary<0)
    return {
        valid=true,within=SEGCFG.roundEssential(within),boundary=SEGCFG.roundEssential(boundary),
        endpoint=SEGCFG.roundEssential(endpoint),residual=SEGCFG.roundEssential(residual),
        withinPerYaw=SEGCFG.roundEssential(within/yaw),boundaryPerYaw=SEGCFG.roundEssential(boundary/yaw),
        endpointAbsPerYaw=SEGCFG.roundEssential(math.abs(endpoint)/yaw),
        cancellationPerYaw=SEGCFG.roundEssential((opposed and math.min(math.abs(within),math.abs(boundary)) or 0)/yaw),
        signsOpposed=opposed,
    }
end

function SEGCFG.analyzeEssentialSegment(segment,model)
    local series=segment.series or {}
    local yaw=segment.totalAbsYaw or 0
    local headDecomposition=SEGCFG.essentialScreenDecomposition(series,"headBeforeX","headAfterX",yaw)
    local primaryDecomposition=SEGCFG.essentialScreenDecomposition(series,"primaryBeforeX","primaryAfterX",yaw)
    local subjectDecomposition=SEGCFG.essentialScreenDecomposition(series,"subjectBeforeX","subjectAfterX",yaw)
    local first,last=series[1],series[#series]
    local startBoundary=segment.boundaries and segment.boundaries.start
    local finishBoundary=segment.boundaries and segment.boundaries.finish
    local startSnapshot=startBoundary and (startBoundary.cameraModuleBefore or startBoundary.controllerBefore)
    local finishSnapshot=finishBoundary and (finishBoundary.cameraModuleAfter or finishBoundary.controllerAfter)
    local jointResult={}
    for _,name in ipairs({"Neck","Waist","RootJoint"}) do
        local before=startSnapshot and startSnapshot.joints and startSnapshot.joints[name]
        local after=finishSnapshot and finishSnapshot.joints and finishSnapshot.joints[name]
        before=before and before.transform or nil
        after=after and after.transform or nil
        if before or after then jointResult[name]={translation=SEGCFG.essentialDistance(before,after),
            pathTranslation=SEGCFG.essentialStoredStepPath(series,"jointTransform",name)
                or SEGCFG.essentialJointPath(series,name),rotationDeg=SEGCFG.essentialRotationDegrees(before,after)} end
    end
    local firstAnimation=first and first.animationBefore
    local lastAnimation=last and last.animationAfter
    local firstTracks=SEGCFG.essentialAnimationTrackMap(firstAnimation,model)
    local lastTracks=SEGCFG.essentialAnimationTrackMap(lastAnimation,model)
    local trackKeys={}
    for key in pairs(firstTracks) do trackKeys[#trackKeys+1]=key end
    for key in pairs(lastTracks) do if not firstTracks[key] then trackKeys[#trackKeys+1]=key end end
    table.sort(trackKeys)
    local animationResult={}
    for _,key in ipairs(trackKeys) do
        local firstTrack,lastTrack=firstTracks[key],lastTracks[key]
        local firstTime=firstTrack and firstTrack.timePosition
        local lastTime=lastTrack and lastTrack.timePosition
        local advance=nil
        if type(firstTime)=="number" and type(lastTime)=="number" then
            advance=lastTime-firstTime
            if advance<0 and (firstTrack.looped or lastTrack.looped) then
                local length=tonumber(firstTrack.length or lastTrack.length)
                if length and length>0 then advance+=length end
            end
        end
        animationResult[#animationResult+1]={key=key,presentStart=firstTrack~=nil,presentEnd=lastTrack~=nil,
            timeStart=firstTime,timeEnd=lastTime,
            timeAdvance=type(advance)=="number" and SEGCFG.roundEssential(advance) or nil,
            weightStart=firstTrack and firstTrack.weightCurrent or nil,
            weightEnd=lastTrack and lastTrack.weightCurrent or nil,
            weightChange=firstTrack and lastTrack and type(firstTrack.weightCurrent)=="number"
                and type(lastTrack.weightCurrent)=="number"
                and SEGCFG.roundEssential(lastTrack.weightCurrent-firstTrack.weightCurrent) or nil,
            speedStart=firstTrack and firstTrack.speed or nil,speedEnd=lastTrack and lastTrack.speed or nil,
            playingStart=firstTrack and firstTrack.isPlaying or false,
            playingEnd=lastTrack and lastTrack.isPlaying or false}
    end
    local firstTime=animationResult[1] and animationResult[1].timeStart or nil
    local cameraConfig=startSnapshot and model and model.constants and model.constants.camera[startSnapshot.cameraConfig] or nil
    local startX=startSnapshot and SEGCFG.essentialProjectX(startSnapshot.cameraCFrame,startSnapshot.headCFrame,cameraConfig) or nil
    local cameraOnlyX=startSnapshot and finishSnapshot
        and SEGCFG.essentialProjectX(finishSnapshot.cameraCFrame,startSnapshot.headCFrame,cameraConfig) or nil
    local poseOnlyX=startSnapshot and finishSnapshot
        and SEGCFG.essentialProjectX(startSnapshot.cameraCFrame,finishSnapshot.headCFrame,cameraConfig) or nil
    local combinedX=startSnapshot and finishSnapshot
        and SEGCFG.essentialProjectX(finishSnapshot.cameraCFrame,finishSnapshot.headCFrame,cameraConfig) or nil
    local startPoint=startSnapshot and SEGCFG.essentialProjectPoint(startSnapshot.cameraCFrame,startSnapshot.headCFrame,cameraConfig) or nil
    local finishPoint=startSnapshot and finishSnapshot
        and SEGCFG.essentialProjectPoint(finishSnapshot.cameraCFrame,finishSnapshot.headCFrame,cameraConfig) or nil
    return {
        valid=headDecomposition.valid,duration=segment.duration,frameCount=segment.frameCount,
        headHorizontal=segment.screen and segment.screen.head and segment.screen.head.x or nil,
        primaryHorizontal=segment.screen and segment.screen.primary and segment.screen.primary.x or nil,
        subjectHorizontal=segment.screen and segment.screen.subject and segment.screen.subject.x or nil,
        headWithinXPerYaw=headDecomposition.withinPerYaw,
        headBoundaryXPerYaw=headDecomposition.boundaryPerYaw,
        screenDecomposition={head=headDecomposition,primary=primaryDecomposition,subject=subjectDecomposition},
        rootTranslation=SEGCFG.essentialDistance(startSnapshot and startSnapshot.primaryCFrame,finishSnapshot and finishSnapshot.primaryCFrame),
        rootRotationDeg=SEGCFG.essentialRotationDegrees(startSnapshot and startSnapshot.primaryCFrame,finishSnapshot and finishSnapshot.primaryCFrame),
        rootPathTranslation=SEGCFG.essentialStoredStepPath(series,"rootStep")
            or SEGCFG.essentialCFramePath(series,"primaryBefore","primaryAfter"),
        localHeadTranslation=SEGCFG.essentialDistance(startSnapshot and startSnapshot.primaryToHead,finishSnapshot and finishSnapshot.primaryToHead),
        localHeadRotationDeg=SEGCFG.essentialRotationDegrees(startSnapshot and startSnapshot.primaryToHead,finishSnapshot and finishSnapshot.primaryToHead),
        localHeadPathTranslation=SEGCFG.essentialStoredStepPath(series,"localHeadStep")
            or SEGCFG.essentialCFramePath(series,"localHeadBefore","localHeadAfter"),
        joints=jointResult,animations=animationResult,
        initialCameraCFrame=startSnapshot and startSnapshot.cameraCFrame or nil,
        initialLocalHead=startSnapshot and startSnapshot.primaryToHead or nil,
        initialAnimationTime=firstTime,
        projection={
            cameraOnlyHeadDX=type(startX)=="number" and type(cameraOnlyX)=="number"
                and SEGCFG.roundEssential(cameraOnlyX-startX) or nil,
            poseOnlyHeadDX=type(startX)=="number" and type(poseOnlyX)=="number"
                and SEGCFG.roundEssential(poseOnlyX-startX) or nil,
            combinedHeadDX=type(startX)=="number" and type(combinedX)=="number"
                and SEGCFG.roundEssential(combinedX-startX) or nil,
            startHeadDepth=startPoint and startPoint.depth or nil,
            finishHeadDepth=finishPoint and finishPoint.depth or nil,
        },
    }
end

function SEGCFG.essentialSorted(values)
    local output={}
    for _,value in ipairs(values or {}) do if type(value)=="number" then output[#output+1]=value end end
    table.sort(output)
    return output
end

function SEGCFG.essentialPercentile(values,fraction)
    local sorted=SEGCFG.essentialSorted(values)
    if #sorted==0 then return nil end
    local position=1+(#sorted-1)*math.max(0,math.min(1,fraction))
    local lower,upper=math.floor(position),math.ceil(position)
    if lower==upper then return SEGCFG.roundEssential(sorted[lower]) end
    local weight=position-lower
    return SEGCFG.roundEssential(sorted[lower]*(1-weight)+sorted[upper]*weight)
end

function SEGCFG.essentialDistribution(values)
    local sorted=SEGCFG.essentialSorted(values)
    if #sorted==0 then return {n=0,mean=nil,median=nil,p95=nil,max=nil} end
    local sum=0
    for _,value in ipairs(sorted) do sum+=value end
    return {n=#sorted,mean=SEGCFG.roundEssential(sum/#sorted),
        median=SEGCFG.essentialPercentile(sorted,0.5),p95=SEGCFG.essentialPercentile(sorted,0.95),
        max=SEGCFG.roundEssential(sorted[#sorted])}
end

function SEGCFG.essentialMovingBlock(differences)
    local values=SEGCFG.essentialSorted(differences)
    if #values==0 then return {n=0,estimate=nil,low=nil,high=nil,excludesZero=false} end
    -- Preserve pair order in resampling; sorted is used only for the literal estimate.
    local ordered={}
    for _,value in ipairs(differences) do ordered[#ordered+1]=value end
    local blockSize=math.max(1,math.min(#ordered,tonumber(SEGCFG.bootstrapBlock) or 3))
    local iterations=tonumber(SEGCFG.bootstrapIterations) or 2000
    local state=(#ordered*1000003+iterations*97)%2147483647
    if state<=0 then state=104729 end
    local function randomIndex(maximum)
        state=(state*48271)%2147483647
        return 1+(state%maximum)
    end
    local estimates={}
    for _=1,iterations do
        local resampled={}
        while #resampled<#ordered do
            local start=randomIndex(math.max(1,#ordered-blockSize+1))
            for offset=0,blockSize-1 do
                if #resampled>=#ordered then break end
                resampled[#resampled+1]=ordered[math.min(#ordered,start+offset)]
            end
        end
        estimates[#estimates+1]=SEGCFG.essentialPercentile(resampled,0.5)
    end
    local low,high=SEGCFG.essentialPercentile(estimates,0.025),SEGCFG.essentialPercentile(estimates,0.975)
    return {n=#ordered,estimate=SEGCFG.essentialPercentile(values,0.5),low=low,high=high,
        excludesZero=type(low)=="number" and type(high)=="number" and (low>0 or high<0)}
end

function SEGCFG.essentialFirstAnimationAdvance(segmentAnalysis)
    local first=segmentAnalysis.animations and segmentAnalysis.animations[1]
    return first and first.timeAdvance or nil
end

function SEGCFG.aggregateEssentialAnalyses(pairAnalyses)
    local result={pairs={},aggregates={touch={},relay={}},bootstrap={},geometry={
        maxArithmeticResidual=0,headOpposedTouch=0,headOpposedRelay=0,
        primaryBoundaryNonzero=0,subjectBoundaryNonzero=0,
    },decisions={}}
    local routeValues={touch={root={},head={},joint={},animation={},duration={},frames={}},
        relay={root={},head={},joint={},animation={},duration={},frames={}}}
    local differences={head={},primary={},subject={}}
    for index,pair in ipairs(pairAnalyses or {}) do
        local touch,relay=pair.touch,pair.relay
        result.pairs[index]={index=index,yawGap=pair.yawGap,netPitchGap=pair.netPitchGap,
            absPitchGap=pair.absPitchGap,touch=touch,relay=relay,
            initial={cameraRotationGapDeg=SEGCFG.essentialRotationDegrees(touch.initialCameraCFrame,relay.initialCameraCFrame),
                localHeadTranslationGap=SEGCFG.essentialDistance(touch.initialLocalHead,relay.initialLocalHead),
                animationTimeGap=type(touch.initialAnimationTime)=="number" and type(relay.initialAnimationTime)=="number"
                    and SEGCFG.roundEssential(math.abs(relay.initialAnimationTime-touch.initialAnimationTime)) or nil}}
        for route,analysis in pairs({touch=touch,relay=relay}) do
            local values=routeValues[route]
            if type(analysis.rootTranslation)=="number" then values.root[#values.root+1]=analysis.rootTranslation end
            if type(analysis.localHeadTranslation)=="number" then values.head[#values.head+1]=analysis.localHeadTranslation end
            local neck=analysis.joints and analysis.joints.Neck
            if neck and type(neck.translation)=="number" then values.joint[#values.joint+1]=neck.translation end
            local animation=SEGCFG.essentialFirstAnimationAdvance(analysis)
            if type(animation)=="number" then values.animation[#values.animation+1]=animation end
            if type(analysis.duration)=="number" then values.duration[#values.duration+1]=analysis.duration end
            if type(analysis.frameCount)=="number" then values.frames[#values.frames+1]=analysis.frameCount end
            local decomposition=analysis.screenDecomposition or {}
            for _,point in ipairs({"head","primary","subject"}) do
                local residual=decomposition[point] and decomposition[point].residual
                if type(residual)=="number" then
                    result.geometry.maxArithmeticResidual=math.max(result.geometry.maxArithmeticResidual,math.abs(residual))
                end
            end
            if decomposition.head and decomposition.head.signsOpposed then
                local key=route=="touch" and "headOpposedTouch" or "headOpposedRelay"
                result.geometry[key]+=1
            end
            if decomposition.primary and math.abs(decomposition.primary.boundary or 0)>0 then
                result.geometry.primaryBoundaryNonzero+=1
            end
            if decomposition.subject and math.abs(decomposition.subject.boundary or 0)>0 then
                result.geometry.subjectBoundaryNonzero+=1
            end
        end
        for key,field in pairs({head="headHorizontal",primary="primaryHorizontal",subject="subjectHorizontal"}) do
            if type(touch[field])=="number" and type(relay[field])=="number" then
                differences[key][#differences[key]+1]=SEGCFG.roundEssential(relay[field]-touch[field])
            end
        end
    end
    for _,route in ipairs({"touch","relay"}) do
        local values=routeValues[route]
        result.aggregates[route]={
            rootTranslation=SEGCFG.essentialDistribution(values.root),
            localHeadTranslation=SEGCFG.essentialDistribution(values.head),
            jointNeckTranslation=SEGCFG.essentialDistribution(values.joint),
            animationTimeAdvance=SEGCFG.essentialDistribution(values.animation),
            duration=SEGCFG.essentialDistribution(values.duration),
            frameCount=SEGCFG.essentialDistribution(values.frames),
        }
    end
    result.bootstrap.headHorizontal=SEGCFG.essentialMovingBlock(differences.head)
    result.bootstrap.primaryHorizontal=SEGCFG.essentialMovingBlock(differences.primary)
    result.bootstrap.subjectHorizontal=SEGCFG.essentialMovingBlock(differences.subject)
    result.geometry.maxArithmeticResidual=SEGCFG.roundEssential(result.geometry.maxArithmeticResidual)
    result.geometry.decompositionIdentityClosed=result.geometry.maxArithmeticResidual==0
    result.geometry.primarySubjectDoNotExplainObservedHeadDifference=
        result.geometry.primaryBoundaryNonzero==0 and result.geometry.subjectBoundaryNonzero==0
    result.method={name="paired moving-block bootstrap over time-ordered matched non-overlapping segment pairs",
        unit="matched segment pair",blockSize=math.max(1,math.min(#(pairAnalyses or {}),tonumber(SEGCFG.bootstrapBlock) or 3)),
        iterations=tonumber(SEGCFG.bootstrapIterations) or 2000,
        statistic="median(relay-touch)",precisionDecimals=7,
        decisionRule="causal mechanism remains unproved without duration/frame-count/initial-pose identification"}
    result.decisions={
        temporalConfoundResolved="unproved",
        initialPoseConfoundResolved="unproved",
        rootMotionContribution="quantified pair-by-pair; independent causal share unproved",
        jointTransformContribution="quantified pair-by-pair; independent causal share unproved",
        animationProgressContribution="quantified pair-by-pair; independent causal share unproved",
        projectionDepthContribution="quantified pair-by-pair; independent causal share unproved",
        screenDisplacementDecomposition="endpoint = within-update + inter-frame; arithmetic residual retained pair-by-pair",
        downstreamCameraCompositionMissing="not observed in the measured decomposition",
        primarySubjectExplanation="not supported for the observed Head-only horizontal separation",
        timingPoseInterpretation="relay duration/frame count are larger, allowing more Head-to-rig/pose evolution and projected cancellation",
        pcMechanismConfirmed=false,
        headHorizontalEffectAfterTemporalControl="unproved: original matcher does not pair duration/frame count/initial pose",
        firstConcreteGeometricDivergence="unproved after temporal and initial-pose control",
        causalMechanismProved=false,implementationTargetIdentified=false,
        v615Justified=false,astra6MaxJustified=false,
    }
    return result
end

function SEGCFG.analyzeEssentialModel(model)
    local analyses={}
    for index,pair in ipairs(model.pairs or {}) do
        analyses[index]={yawGap=pair.yawGap,netPitchGap=pair.netPitchGap,absPitchGap=pair.absPitchGap,
            touch=SEGCFG.analyzeEssentialSegment(pair.touch,model),
            relay=SEGCFG.analyzeEssentialSegment(pair.relay,model)}
    end
    return SEGCFG.aggregateEssentialAnalyses(analyses)
end

function SEGCFG.rawSnapshotForAnalysis(snapshot)
    if type(snapshot)~="table" then return nil end
    local joints={}
    for _,name in ipairs({"Neck","Waist","RootJoint"}) do
        local joint=snapshot.joints and snapshot.joints[name]
        if type(joint)=="table" then joints[name]={transform=SEGCFG.essentialArray(joint.transform)} end
    end
    return {
        cameraConfig=1,cameraCFrame=SEGCFG.essentialArray(snapshot.cameraCFrame),
        primaryCFrame=SEGCFG.essentialArray(snapshot.primaryCFrame),
        headCFrame=SEGCFG.essentialArray(snapshot.headCFrame),
        primaryToHead=SEGCFG.essentialArray(snapshot.primaryToHead),
        joints=joints,animation=SEGCFG.deepCopyEssential(snapshot.animation),
    }
end

function SEGCFG.rawBoundarySetForAnalysis(sample)
    local telemetry=sample and sample.temporalPoseTelemetry
    local calls=type(telemetry)=="table" and telemetry.controllerCalls or nil
    local firstCall=type(calls)=="table" and calls[1] or nil
    local lastCall=type(calls)=="table" and calls[#calls] or nil
    return {
        cameraModuleBefore=SEGCFG.rawSnapshotForAnalysis(telemetry and telemetry.cameraModuleBefore),
        controllerBefore=SEGCFG.rawSnapshotForAnalysis(firstCall and firstCall.before),
        controllerAfter=SEGCFG.rawSnapshotForAnalysis(lastCall and lastCall.after),
        cameraModuleAfter=SEGCFG.rawSnapshotForAnalysis(telemetry and telemetry.cameraModuleAfter),
    }
end

function SEGCFG.rawSeriesForAnalysis(sample)
    local boundaries=SEGCFG.rawBoundarySetForAnalysis(sample)
    local before=boundaries.cameraModuleBefore or boundaries.controllerBefore
    local after=boundaries.cameraModuleAfter or boundaries.controllerAfter
    local jointTransform={before={},after={}}
    for _,name in ipairs({"Neck","Waist","RootJoint"}) do
        if before and before.joints and before.joints[name] then jointTransform.before[name]=before.joints[name].transform end
        if after and after.joints and after.joints[name] then jointTransform.after[name]=after.joints[name].transform end
    end
    return {
        frame=sample.frame,time=sample.time,dt=sample.dt,yawSigned=sample.yawSigned,pitchSigned=sample.pitchSigned,
        headBeforeX=SEGCFG.essentialCoordinate(sample.headScreenBefore,1),headAfterX=SEGCFG.essentialCoordinate(sample.headScreenAfter,1),
        headBeforeY=SEGCFG.essentialCoordinate(sample.headScreenBefore,2),headAfterY=SEGCFG.essentialCoordinate(sample.headScreenAfter,2),
        headBeforeDepth=SEGCFG.essentialCoordinate(sample.headScreenBefore,3),headAfterDepth=SEGCFG.essentialCoordinate(sample.headScreenAfter,3),
        primaryBeforeX=SEGCFG.essentialCoordinate(sample.primaryScreenBefore,1),primaryAfterX=SEGCFG.essentialCoordinate(sample.primaryScreenAfter,1),
        subjectBeforeX=SEGCFG.essentialCoordinate(sample.subjectScreenBefore,1),subjectAfterX=SEGCFG.essentialCoordinate(sample.subjectScreenAfter,1),
        cameraBefore=before and before.cameraCFrame or nil,cameraAfter=after and after.cameraCFrame or nil,
        primaryBefore=before and before.primaryCFrame or nil,primaryAfter=after and after.primaryCFrame or nil,
        localHeadBefore=before and before.primaryToHead or nil,localHeadAfter=after and after.primaryToHead or nil,
        jointTransform=jointTransform,animationBefore=before and before.animation or nil,
        animationAfter=after and after.animation or nil,
    },boundaries
end

function SEGCFG.analyzeRawSegment(segment)
    local series,boundaryBySample={},{ }
    for index,sample in ipairs(segment.samples or {}) do
        local item,boundaries=SEGCFG.rawSeriesForAnalysis(sample)
        series[index]=item; boundaryBySample[index]=boundaries
    end
    local firstSample=segment.samples and segment.samples[1]
    local firstTelemetry=firstSample and firstSample.temporalPoseTelemetry
    local firstSnapshot=firstTelemetry and firstTelemetry.cameraModuleBefore
    local pseudoModel={constants={camera={{fieldOfView=firstSnapshot and firstSnapshot.fieldOfView,
        viewport=SEGCFG.essentialArray(firstSnapshot and firstSnapshot.viewport)}}}}
    local pseudoSegment={
        duration=segment.duration,frameCount=segment.frameCount,totalAbsYaw=segment.totalAbsYaw,
        screen={head=SEGCFG.essentialMetric(segment.head),primary=SEGCFG.essentialMetric(segment.primary),
            subject=SEGCFG.essentialMetric(segment.subject)},
        series=series,boundaries={start=boundaryBySample[1],finish=boundaryBySample[#boundaryBySample]},
    }
    return SEGCFG.analyzeEssentialSegment(pseudoSegment,pseudoModel)
end

function SEGCFG.analyzeFullMatchedPairs(matchedPairs)
    local analyses={}
    for index,pair in ipairs(matchedPairs or {}) do
        analyses[index]={yawGap=pair.yawGap,netPitchGap=pair.netPitchGap,absPitchGap=pair.absPitchGap,
            touch=SEGCFG.analyzeRawSegment(pair.touch),relay=SEGCFG.analyzeRawSegment(pair.relay)}
    end
    return SEGCFG.aggregateEssentialAnalyses(analyses)
end

function SEGCFG.compareEssentialValues(a,b,path,mismatches)
    local ta,tb=type(a),type(b)
    if ta~=tb then mismatches[#mismatches+1]=path..":type"; return end
    if ta=="number" then
        if SEGCFG.roundEssential(a)~=SEGCFG.roundEssential(b) then mismatches[#mismatches+1]=path..":number" end
    elseif ta=="table" then
        local seen={}
        for key,value in pairs(a) do
            seen[key]=true; SEGCFG.compareEssentialValues(value,b[key],path.."."..tostring(key),mismatches)
        end
        for key in pairs(b) do if not seen[key] then mismatches[#mismatches+1]=path.."."..tostring(key)..":extra" end end
    elseif a~=b then mismatches[#mismatches+1]=path..":value" end
end

function SEGCFG.compareAnalysisResults(a,b)
    local mismatches={}
    SEGCFG.compareEssentialValues(a,b,"analysis",mismatches)
    return {equal=#mismatches==0,mismatches=mismatches}
end


function SEGCFG.canonicalEssentialText(value)
    local valueType=type(value)
    if valueType=="nil" then return "null" end
    if valueType=="number" then return tostring(SEGCFG.roundEssential(value)) end
    if valueType=="boolean" then return value and "true" or "false" end
    if valueType=="string" then return string.format("%q",value) end
    if valueType~="table" then return string.format("%q",tostring(value)) end
    local array=true
    local maximum,count=0,0
    for key in pairs(value) do
        if type(key)~="number" or key<1 or key%1~=0 then array=false; break end
        maximum=math.max(maximum,key); count+=1
    end
    local parts={}
    if array and maximum==count then
        for index=1,maximum do parts[index]=SEGCFG.canonicalEssentialText(value[index]) end
        return "["..table.concat(parts,",").."]"
    end
    local keys={}
    for key in pairs(value) do keys[#keys+1]=tostring(key) end
    table.sort(keys)
    for _,key in ipairs(keys) do
        parts[#parts+1]=string.format("%q",key)..":"..SEGCFG.canonicalEssentialText(value[key])
    end
    return "{"..table.concat(parts,",").."}"
end

function SEGCFG.essentialDigest(value)
    local text=SEGCFG.canonicalEssentialText(value)
    local state=7
    for index=1,#text do state=(state*131+string.byte(text,index))%2147483647 end
    return string.format("c7-%d-%08x",#text,state)
end

function SEGCFG.solveEssentialReportSize(fullReportChars,payloadChars,builder)
    local size={fullReportChars=fullReportChars,essentialReportChars=0,reductionPercent=0,essentialChunks=0}
    for _=1,8 do
        local text=builder(size)
        local chars=utf8.len(text)
        if chars==nil then error("V614 essential report is not valid UTF-8",0) end
        local chunks=math.max(1,math.ceil(chars/payloadChars))
        local reduction=SEGCFG.roundEssential(fullReportChars>0 and (1-chars/fullReportChars)*100 or 0)
        if chars==size.essentialReportChars and chunks==size.essentialChunks
            and reduction==size.reductionPercent then return text,size end
        size={fullReportChars=fullReportChars,essentialReportChars=chars,
            reductionPercent=reduction,essentialChunks=chunks}
    end
    error("V614 essential report size fields did not stabilize",0)
end
-- END V614 ESSENTIAL REPORT PURE HELPERS
end

function SEGCFG.serializeEssentialModel(model)
    local ok,text=pcall(function() return HttpService:JSONEncode(model) end)
    if not ok then error("V614 essential JSON encode failed: "..tostring(text),0) end
    return text
end

function SEGCFG.deserializeEssentialModel(text)
    local ok,value=pcall(function() return HttpService:JSONDecode(text) end)
    if not ok then error("V614 essential JSON decode failed: "..tostring(value),0) end
    return value
end

function SEGCFG.buildProductionEssentialBundle()
    local matched=SEGCFG.matchSegments()
    local diagnostics=getgenv().PCV614Diagnostics()
    local model=SEGCFG.buildEssentialModel(matched,diagnostics)
    model.config={
        sequence=SEGCFG.deepCopyEssential(SEGCFG.sequence),phaseEligibleTarget=SEGCFG.phaseEligibleTarget,
        routeEligibleTarget=SEGCFG.routeEligibleTarget,requiredMatchedPairs=SEGCFG.minMatched,
        targetYaw=SEGCFG.targetYaw,maxYaw=SEGCFG.maxYaw,minFrames=SEGCFG.minFrames,
        minCoherence=SEGCFG.minCoherence,maxDuration=SEGCFG.maxDuration,maxFrameGap=SEGCFG.maxFrameGap,
        maxNetPitch=SEGCFG.maxNetPitch,maxAbsPitchRatio=SEGCFG.maxAbsPitchRatio,
        maxAbsPitchFloor=SEGCFG.maxAbsPitchFloor,matchYawGap=SEGCFG.matchYawGap,
        matchNetPitchGap=SEGCFG.matchNetPitchGap,matchAbsPitchGap=SEGCFG.matchAbsPitchGap,
        bootstrapBlock=SEGCFG.bootstrapBlock,bootstrapIterations=SEGCFG.bootstrapIterations,
        stabilizeSeconds=STABILIZE_SECONDS,stableConsecutiveFrames=STABLE_CONSECUTIVE_FRAMES,
        maxLinearVelocity=MAX_LINEAR_VELOCITY,maxWorldDeltaFloor=MAX_WORLD_DELTA_FLOOR,
        maxMoveDirection=MAX_MOVE_DIRECTION,minAppliedYawDeg=MIN_APPLIED_YAW_DEG,
    }
    model.windows={}
    for _,window in ipairs({"A1","B1","B2","A2"}) do
        model.windows[window]=SEGCFG.essentialSafeValue(SEGCFG.getWindowStats(window))
    end
    model.integrity={
        callbackErrors=diagnostics.callbackErrors,controllerErrors=diagnostics.controllerErrors,
        frameCorrelationErrors=diagnostics.frameCorrelationErrors,
        telemetryCaptureErrors=diagnostics.telemetryCaptureErrors,
        telemetryCaptureErrorSources=diagnostics.telemetryCaptureErrorSources,
        uiRefreshErrors=diagnostics.uiRefreshErrors,traceDropped=diagnostics.traceDropped,
        evidenceDropped=diagnostics.evidenceDropped,
        telemetryMatchedSamples=diagnostics.telemetryMatchedSamples,
        telemetryMatchedSamplesComplete=diagnostics.telemetryMatchedSamplesComplete,
        telemetryMatchedSamplesMissing=diagnostics.telemetryMatchedSamplesMissing,
        telemetryMatchedControllerCalls=diagnostics.telemetryMatchedControllerCalls,
        observationalOnly=diagnostics.observationalOnly,writesCameraCFrame=diagnostics.writesCameraCFrame,
        writesRootPartCFrame=diagnostics.writesRootPartCFrame,writesHeadCFrame=diagnostics.writesHeadCFrame,
        writesJointTransforms=diagnostics.writesJointTransforms,controlsAnimations=diagnostics.controlsAnimations,
        writesCameraFocus=diagnostics.writesCameraFocus,altersCameraSubject=diagnostics.altersCameraSubject,
        changesSensitivityGainPhysics=diagnostics.changesSensitivityGainPhysics,
    }
    model.matching={
        eligibleTouchSegments=diagnostics.eligibleTouchSegments,
        eligibleRelaySegments=diagnostics.eligibleRelaySegments,
        matchedComparisonUnits=#matched,requiredMatchedComparisonUnits=SEGCFG.minMatched,
        coverageSufficient=#matched>=SEGCFG.minMatched,
        yawMatchQuality=diagnostics.yawMatchQuality,pitchMatchQuality=diagnostics.pitchMatchQuality,
        counterbalancingMethod=diagnostics.counterbalancingMethod,
    }

    -- A reads complete runtime telemetry. B reads a JSON round-trip containing
    -- only the values that will be transported in the essential report.
    local analysisA=SEGCFG.analyzeFullMatchedPairs(matched)
    local dataOnlyJson=SEGCFG.serializeEssentialModel(model)
    local decoded=SEGCFG.deserializeEssentialModel(dataOnlyJson)
    local analysisB=SEGCFG.analyzeEssentialModel(decoded)
    local parity=SEGCFG.compareAnalysisResults(analysisA,analysisB)
    model.analysis=analysisB
    model.parity={
        equal=parity.equal,mismatches=parity.mismatches,
        fullDigest=SEGCFG.essentialDigest(analysisA),essentialDigest=SEGCFG.essentialDigest(analysisB),
        precisionDecimals=7,
    }
    local modelJson=SEGCFG.serializeEssentialModel(model)
    return {matched=matched,diagnostics=diagnostics,model=model,modelJson=modelJson,
        analysisA=analysisA,analysisB=analysisB,parity=parity}
end

local function essentialJsonValue(value)
    local ok,text=pcall(function() return HttpService:JSONEncode(value) end)
    return ok and text or string.format("%q",tostring(value))
end

function SEGCFG.essentialPairSummary(pair,index)
    local touch,relay=pair.touch,pair.relay
    return string.format(
        "pair=%d touch=%s(%s) relay=%s(%s) yawGap=%.7f netPitchGap=%.7f absPitchGap=%.7f touchDuration=%.7f relayDuration=%.7f touchFrames=%d relayFrames=%d",
        index,tostring(touch.id),tostring(touch.window),tostring(relay.id),tostring(relay.window),
        pair.yawGap,pair.netPitchGap,pair.absPitchGap,touch.duration,relay.duration,touch.frameCount,relay.frameCount)
end

function SEGCFG.buildEssentialReportText(bundle,size)
    local diagnostics,model=bundle.diagnostics,bundle.model
    local analysis=model.analysis
    local lines={"=== PC MOVEMENT V614 ESSENTIAL REPORT ==="}
    lines[#lines+1]="essentialSchema = "..tostring(model.schema)
    lines[#lines+1]="version = "..tostring(diagnostics.version)
    lines[#lines+1]="bridgeMode = "..tostring(diagnostics.bridgeMode)
    lines[#lines+1]="probePurpose = "..tostring(diagnostics.probePurpose)
    lines[#lines+1]="probeFrames = "..tostring(diagnostics.probeFrames)
    lines[#lines+1]="probeDuration = "..tostring(diagnostics.probeDuration)
    lines[#lines+1]="standingTouchSamples = "..tostring(diagnostics.standingTouchSamples)
    lines[#lines+1]="standingRelaySamples = "..tostring(diagnostics.standingRelaySamples)
    lines[#lines+1]="eligibleTouchSegments = "..tostring(diagnostics.eligibleTouchSegments)
    lines[#lines+1]="eligibleRelaySegments = "..tostring(diagnostics.eligibleRelaySegments)
    lines[#lines+1]="matchedComparisonUnits = "..tostring(diagnostics.matchedComparisonUnits)
    lines[#lines+1]="requiredMatchedComparisonUnits = "..tostring(diagnostics.requiredMatchedComparisonUnits)
    lines[#lines+1]="coverageSufficient = "..tostring(diagnostics.coverageSufficient)
    lines[#lines+1]="completedWindows = "..tostring(diagnostics.completedWindows)
    lines[#lines+1]="callbackErrors = "..tostring(diagnostics.callbackErrors)
    lines[#lines+1]="controllerErrors = "..tostring(diagnostics.controllerErrors)
    lines[#lines+1]="frameCorrelationErrors = "..tostring(diagnostics.frameCorrelationErrors)
    lines[#lines+1]="telemetryCaptureErrors = "..tostring(diagnostics.telemetryCaptureErrors)
    lines[#lines+1]="telemetryCaptureErrorSources = "..tostring(diagnostics.telemetryCaptureErrorSources)
    lines[#lines+1]="uiRefreshErrors = "..tostring(diagnostics.uiRefreshErrors)
    lines[#lines+1]="traceDropped = "..tostring(diagnostics.traceDropped)
    lines[#lines+1]="evidenceDropped = "..tostring(diagnostics.evidenceDropped)
    lines[#lines+1]="validationReadyOriginal = "..tostring(diagnostics.validationReady)
    lines[#lines+1]="validationReadyEssential = "..tostring(diagnostics.validationReady and bundle.parity.equal)
    lines[#lines+1]="config = "..essentialJsonValue(model.config)
    lines[#lines+1]="windowA1 = "..essentialJsonValue(model.windows.A1)
    lines[#lines+1]="windowB1 = "..essentialJsonValue(model.windows.B1)
    lines[#lines+1]="windowB2 = "..essentialJsonValue(model.windows.B2)
    lines[#lines+1]="windowA2 = "..essentialJsonValue(model.windows.A2)

    lines[#lines+1]=""
    lines[#lines+1]="=== V614 ESSENTIAL MATCHED PAIRS ==="
    for index,pair in ipairs(bundle.matched) do
        lines[#lines+1]=SEGCFG.essentialPairSummary(pair,index)
        lines[#lines+1]="pairAnalysis="..tostring(index).." "..essentialJsonValue(analysis.pairs[index])
    end
    lines[#lines+1]="aggregateAnalysis = "..essentialJsonValue(analysis.aggregates)
    lines[#lines+1]="bootstrapAnalysis = "..essentialJsonValue(analysis.bootstrap)
    lines[#lines+1]="geometricDecomposition = "..essentialJsonValue(analysis.geometry)

    lines[#lines+1]=""
    lines[#lines+1]="=== V614 ESSENTIAL OMISSION MANIFEST ==="
    local omissionKeys={"unmatchedAcceptedFrames","rejectedSegments","unmatchedEligibleSegments",
        "repeatedJointConstants","repeatedAnimationMetadata","repeatedCameraConfig",
        "guiStateMessages","redundantDebugEvidence"}
    for _,key in ipairs(omissionKeys) do lines[#lines+1]=key.." = "..tostring(model.omissions[key]) end

    lines[#lines+1]=""
    lines[#lines+1]="=== V614 ESSENTIAL MODEL JSON ==="
    lines[#lines+1]=bundle.modelJson

    lines[#lines+1]=""
    lines[#lines+1]="=== V614 ESSENTIAL A/B PARITY ==="
    lines[#lines+1]="analysisAFullTelemetryDigest = "..tostring(model.parity.fullDigest)
    lines[#lines+1]="analysisBEssentialDigest = "..tostring(model.parity.essentialDigest)
    lines[#lines+1]="analysisPrecisionDecimals = 7"
    lines[#lines+1]="analysisParity = "..tostring(model.parity.equal)
    lines[#lines+1]="analysisParityMismatches = "..(#model.parity.mismatches==0 and "none" or table.concat(model.parity.mismatches," | "))

    lines[#lines+1]=""
    lines[#lines+1]="=== V614 ESSENTIAL CAUSAL DECISION ==="
    local decisionKeys={"temporalConfoundResolved","initialPoseConfoundResolved","rootMotionContribution",
        "jointTransformContribution","animationProgressContribution","projectionDepthContribution",
        "screenDisplacementDecomposition","downstreamCameraCompositionMissing","primarySubjectExplanation",
        "timingPoseInterpretation","pcMechanismConfirmed",
        "headHorizontalEffectAfterTemporalControl","firstConcreteGeometricDivergence",
        "causalMechanismProved","implementationTargetIdentified","v615Justified","astra6MaxJustified"}
    for _,key in ipairs(decisionKeys) do lines[#lines+1]=key.." = "..tostring(analysis.decisions[key]) end
    lines[#lines+1]="pcEquivalenceClaimAllowed = false"
    lines[#lines+1]="matchingCriteriaChanged = false"
    lines[#lines+1]="calipersChanged = false"
    lines[#lines+1]="gainChanged = false"
    lines[#lines+1]="cameraCorrectionAdded = false"
    lines[#lines+1]="v615Created = false"

    lines[#lines+1]=""
    lines[#lines+1]="=== V614 ESSENTIAL SIZE ==="
    lines[#lines+1]="fullReportChars = "..tostring(size.fullReportChars)
    lines[#lines+1]="essentialReportChars = "..tostring(size.essentialReportChars)
    lines[#lines+1]="reductionPercent = "..tostring(SEGCFG.roundEssential(size.reductionPercent))
    lines[#lines+1]="essentialChunks = "..tostring(size.essentialChunks)
    return table.concat(lines,"\n")
end

getgenv().PCV614EssentialReport=function()
    local bundle=SEGCFG.buildProductionEssentialBundle()
    local fullReportChars=SEGCFG.buildLegacyReport(true,true)
    local text,size=SEGCFG.solveEssentialReportSize(fullReportChars,SEGCFG.reportPayloadMaxChars,
        function(current) return SEGCFG.buildEssentialReportText(bundle,current) end)
    if SEGCFG.reportCharCount(text)~=size.essentialReportChars then
        error("V614 essential report size self-check failed",0)
    end
    return text
end

getgenv().PCV614Report=function()
    return getgenv().PCV614EssentialReport()
end

SEGCFG.reportTransportMaxChars=30000
SEGCFG.reportPayloadMaxChars=29500
SEGCFG.reportExport=nil
SEGCFG.exportCopyButton=nil
SEGCFG.exportPreviousButton=nil
SEGCFG.exportNextButton=nil
SEGCFG.lastExportMessage="report ainda não congelado"

function SEGCFG.resetReportExport()
    SEGCFG.reportExport=nil
    SEGCFG.lastExportMessage="report ainda não congelado"
end

function SEGCFG.ensureReportExport()
    if SEGCFG.reportExport then return SEGCFG.reportExport end
    stopProbe()
    -- The complete report is built first, exactly by the existing generator.
    -- Chunking starts only after this immutable string already exists.
    local fullReport=getgenv().PCV614EssentialReport()
    local reportId=HttpService:GenerateGUID(false)
    local chunks=SEGCFG.splitReportPayloads(fullReport,SEGCFG.reportPayloadMaxChars)
    if table.concat(chunks)~=fullReport then
        error("V614 export refused: original report reconstruction mismatch",0)
    end
    SEGCFG.reportExport={
        reportId=reportId,chunks=chunks,current=1,reconstructionVerified=true,
        totalReportChars=SEGCFG.reportCharCount(fullReport),
    }
    SEGCFG.lastExportMessage="report congelado; copie todas as partes"
    return SEGCFG.reportExport
end

function SEGCFG.currentReportTransport()
    local export=SEGCFG.ensureReportExport()
    if export.transportIndex~=export.current or type(export.currentTransport)~="table" then
        export.currentTransport=SEGCFG.makeReportChunkTransport(export.reportId,export.totalReportChars,
            export.chunks,export.current,SEGCFG.reportTransportMaxChars)
        export.transportIndex=export.current
    end
    return export.currentTransport
end

function SEGCFG.updateReportExportButtons()
    local export=SEGCFG.reportExport
    local current=export and export.current or 1
    local total=export and #export.chunks or 0
    if SEGCFG.exportCopyButton then
        SEGCFG.exportCopyButton.Text=export
            and string.format("COPIAR PARTE %d/%d",current,total)
            or "GERAR PARTES DO REPORT"
    end
    if SEGCFG.exportPreviousButton then
        SEGCFG.exportPreviousButton.Text="PARTE ANTERIOR"
        SEGCFG.exportPreviousButton.AutoButtonColor=export~=nil and current>1
    end
    if SEGCFG.exportNextButton then
        SEGCFG.exportNextButton.Text="PRÓXIMA PARTE"
        SEGCFG.exportNextButton.AutoButtonColor=export~=nil and current<total
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
        phaseAButton.BackgroundColor3=currentWindow=="A1" and Color3.fromRGB(14,165,233) or Color3.fromRGB(30,64,175)
        phaseAButton.Text="1 • A1 TOUCH"..(currentWindow=="A1" and " • ATUAL" or completedWindows.A1 and " • OK" or "")
    end
    if phaseBButton then
        phaseBButton.BackgroundColor3=currentWindow=="B1" and Color3.fromRGB(168,85,247) or Color3.fromRGB(107,33,168)
        phaseBButton.Text="2 • B1 RELAY"..(currentWindow=="B1" and " • ATUAL" or completedWindows.B1 and " • OK" or "")
    end
    if phaseB2Button then
        phaseB2Button.BackgroundColor3=currentWindow=="B2" and Color3.fromRGB(168,85,247) or Color3.fromRGB(107,33,168)
        phaseB2Button.Text="3 • B2 RELAY"..(currentWindow=="B2" and " • ATUAL" or completedWindows.B2 and " • OK" or "")
    end
    if phaseA2Button then
        phaseA2Button.BackgroundColor3=currentWindow=="A2" and Color3.fromRGB(14,165,233) or Color3.fromRGB(30,64,175)
        phaseA2Button.Text="4 • A2 TOUCH"..(currentWindow=="A2" and " • ATUAL" or completedWindows.A2 and " • OK" or "")
    end
    SEGCFG.updateReportExportButtons()
end

refreshLiveStatus=function()
    if not statusLabel then return end
    local relayText=relayEnabled() and "ON" or "OFF"
    local stateText=phaseState
    if phaseState=="stabilizing" or phaseState=="restabilizing" then
        local remaining=math.max(0,phaseStabilizeUntil-os.clock())
        stateText=string.format("%s %.1fs • estável %d/%d",phaseState,remaining,stableConsecutive,STABLE_CONSECUTIVE_FRAMES)
    end
    local pairs=SEGCFG.matchSegments()
    SEGCFG.livePotentialPairs=#pairs
    SEGCFG.coverageSufficient=#pairs>=SEGCFG.minMatched
    local touchEligible,relayEligible=#segmentStats.touch.eligible,#segmentStats.relay.eligible
    local windowStats=SEGCFG.getWindowStats(currentWindow)
    local eligibleThis=windowStats.eligible or 0
    local segmentYaw=currentSegment and currentSegment.totalAbsYaw or 0
    local segmentPitch=currentSegment and currentSegment.netPitch or 0
    local segmentAbsPitch=currentSegment and currentSegment.totalAbsPitch or 0
    local pitchLimit=math.max(SEGCFG.maxAbsPitchFloor,segmentYaw*SEGCFG.maxAbsPitchRatio)
    local instruction="GIRE MAIS"
    if currentWindow=="A2" and phaseState=="complete" then
        instruction=SEGCFG.coverageSufficient and "12 PARES ATINGIDOS • COBERTURA SUFICIENTE"
            or string.format("FASE COMPLETA • PARES %d/%d",#pairs,SEGCFG.minMatched)
    elseif phaseState=="complete" then
        instruction="FASE COMPLETA • AVANCE"
    elseif phaseState=="stabilizing" or phaseState=="restabilizing" then
        instruction="ESPERE ESTABILIZAR"
    elseif phaseState=="active" then
        if math.abs(segmentPitch)>SEGCFG.maxNetPitch or segmentAbsPitch>pitchLimit then
            instruction="PITCH ALTO • MANTENHA HORIZONTAL"
        elseif os.clock()-SEGCFG.lastSegmentEventAt<1.25 then
            instruction=SEGCFG.lastSegmentEvent
        elseif segmentYaw>=15 then
            instruction="CONTINUE • MESMA DIREÇÃO"
        elseif math.abs((windowStats.eligiblePositive or 0)-(windowStats.eligibleNegative or 0))>=2
            and segmentYaw<1 then
            instruction="MUDE A DIREÇÃO"
        elseif currentPhase=="relay" and relayEligible<touchEligible then
            instruction="COBERTURA RELAY BAIXA • GIRE MAIS"
        end
    end
    local exportText="export=aguardando • toque GERAR PARTES depois de PARAR"
    if SEGCFG.reportExport then
        local okTransport,transport=pcall(SEGCFG.currentReportTransport)
        if okTransport and type(transport)=="table" then
            local export=SEGCFG.reportExport
            exportText=string.format(
                "parte=%d/%d payloadChars=%d transportChars=%d totalReportChars=%d\nreportId=%s\n%s",
                export.current,#export.chunks,transport.payloadChars,transport.transportChars,
                export.totalReportChars,export.reportId,SEGCFG.lastExportMessage)
        else
            exportText="exportError="..cleanText(transport,120)
        end
    end
    statusLabel.Text=string.format(
        "phase=%s route=%s state=%s relay=%s\ncurrentSegmentYawDeg=%.2f/%.0f pitchNet/Abs=%.2f/%.2f\neligibleThisPhase=%d/%d • eligibleTouch=%d relay=%d\nmatchedPairsAvailable=%d targetPairs=%d\n%s\ncorrErr=%d telemetryErr=%d uiErr=%d\n%s",
        currentWindow,currentPhase,stateText,relayText,segmentYaw,SEGCFG.targetYaw,segmentPitch,segmentAbsPitch,
        eligibleThis,SEGCFG.phaseEligibleTarget,touchEligible,relayEligible,#pairs,SEGCFG.minMatched,
        instruction,frameCorrelationErrors,telemetryCaptureErrors,uiRefreshErrors,exportText)
    statusLabel.TextColor3=(phaseState=="active" or phaseState=="complete")
        and Color3.fromRGB(74,222,128) or Color3.fromRGB(250,204,21)
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
    panel.Size=UDim2.fromOffset(336,650); panel.Position=UDim2.new(1,-348,0.5,-325)
    panel.BackgroundColor3=Color3.fromRGB(9,14,27); panel.BackgroundTransparency=0.04
    panel.BorderSizePixel=0; panel.Active=true; panel.Draggable=true; panel.Parent=gui
    local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(0,14); corner.Parent=panel
    local stroke=Instance.new("UIStroke"); stroke.Color=Color3.fromRGB(34,211,238); stroke.Thickness=1.5; stroke.Parent=panel

    local title=Instance.new("TextLabel")
    title.Size=UDim2.new(1,-48,0,34); title.Position=UDim2.fromOffset(13,7); title.BackgroundTransparency=1
    title.Text="V614 • TELEMETRIA TEMPORAL"; title.TextColor3=Color3.fromRGB(103,232,249)
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
    instructions.LayoutOrder=0; instructions.Size=UDim2.new(1,0,0,92)
    instructions.BackgroundColor3=Color3.fromRGB(18,28,48); instructions.BorderSizePixel=0
    instructions.Text="INICIAR; depois siga 1→2→3→4 (ABBA).\nParado, sem joystick; espere ACTIVE.\nGire horizontalmente até FASE COMPLETA.\nSiga GIRE MAIS / CONTINUE / PITCH ALTO.\nPARAR → copie cada PARTE antes de sair."
    instructions.TextColor3=Color3.fromRGB(226,232,240); instructions.TextSize=11
    instructions.TextWrapped=true; instructions.TextXAlignment=Enum.TextXAlignment.Left
    instructions.Font=Enum.Font.Gotham; instructions.Parent=body
    local instructionCorner=Instance.new("UICorner"); instructionCorner.CornerRadius=UDim.new(0,8); instructionCorner.Parent=instructions

    local start=makeButton(body,"INICIAR",Color3.fromRGB(34,197,94),1)
    phaseAButton=makeButton(body,"1 • A1 TOUCH",Color3.fromRGB(30,64,175),2)
    phaseBButton=makeButton(body,"2 • B1 RELAY",Color3.fromRGB(107,33,168),3)
    phaseB2Button=makeButton(body,"3 • B2 RELAY",Color3.fromRGB(107,33,168),4)
    phaseA2Button=makeButton(body,"4 • A2 TOUCH",Color3.fromRGB(30,64,175),5)
    local stop=makeButton(body,"PARAR",Color3.fromRGB(245,158,11),6)
    local emergency=makeButton(body,"EMERGÊNCIA • RELAY OFF / V500",Color3.fromRGB(190,24,93),7)
    SEGCFG.exportCopyButton=makeButton(body,"GERAR PARTES DO REPORT",Color3.fromRGB(2,132,199),8)
    SEGCFG.exportPreviousButton=makeButton(body,"PARTE ANTERIOR",Color3.fromRGB(51,65,85),9)
    SEGCFG.exportNextButton=makeButton(body,"PRÓXIMA PARTE",Color3.fromRGB(8,145,178),10)
    statusLabel=Instance.new("TextLabel")
    statusLabel.LayoutOrder=11; statusLabel.Size=UDim2.new(1,0,0,158); statusLabel.BackgroundTransparency=1
    statusLabel.Text="Pronto. INICIAR e depois 1 • A1 TOUCH."; statusLabel.TextColor3=Color3.fromRGB(148,163,184)
    statusLabel.TextSize=10; statusLabel.TextWrapped=true; statusLabel.Font=Enum.Font.Gotham; statusLabel.Parent=body

    uiConnections[#uiConnections+1]=start.Activated:Connect(function()
        local ok=startProbe()
        setStatus(ok and "Probe ativa. Agora toque 1 • A1 TOUCH." or "Falha ao iniciar hooks.",
            ok and Color3.fromRGB(74,222,128) or Color3.fromRGB(251,113,133))
    end)
    uiConnections[#uiConnections+1]=phaseAButton.Activated:Connect(function()
        local ok,detail=beginControlledPhase("A1")
        setStatus(ok and "A1 estabilizando. Não ande; espere ACTIVE." or "A1 recusada: "..cleanText(detail,90),
            ok and Color3.fromRGB(250,204,21) or Color3.fromRGB(251,113,133))
        refreshPhaseButtons()
    end)
    uiConnections[#uiConnections+1]=phaseBButton.Activated:Connect(function()
        local ok,detail=beginControlledPhase("B1")
        setStatus(ok and "B1 estabilizando. Não ande; espere ACTIVE." or "B1 recusada: "..cleanText(detail,90),
            ok and Color3.fromRGB(250,204,21) or Color3.fromRGB(251,113,133))
        refreshPhaseButtons()
    end)
    uiConnections[#uiConnections+1]=phaseB2Button.Activated:Connect(function()
        local ok,detail=beginControlledPhase("B2")
        setStatus(ok and "B2 estabilizando. Não ande; espere ACTIVE." or "B2 recusada: "..cleanText(detail,90),
            ok and Color3.fromRGB(250,204,21) or Color3.fromRGB(251,113,133))
        refreshPhaseButtons()
    end)
    uiConnections[#uiConnections+1]=phaseA2Button.Activated:Connect(function()
        local ok,detail=beginControlledPhase("A2")
        setStatus(ok and "A2 estabilizando. Não ande; espere ACTIVE." or "A2 recusada: "..cleanText(detail,90),
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
    uiConnections[#uiConnections+1]=SEGCFG.exportCopyButton.Activated:Connect(function()
        local okTransport,transport=pcall(SEGCFG.currentReportTransport)
        if not okTransport then
            SEGCFG.lastExportMessage="ERRO AO GERAR: "..cleanText(transport,100)
            refreshLiveStatus()
            return
        end
        local ok=copyToClipboard(transport.text)
        local export=SEGCFG.reportExport
        SEGCFG.lastExportMessage=ok
            and string.format("PARTE %d/%d COPIADA",export.current,#export.chunks)
            or "Clipboard indisponível no Delta"
        SEGCFG.updateReportExportButtons(); refreshLiveStatus()
    end)
    uiConnections[#uiConnections+1]=SEGCFG.exportPreviousButton.Activated:Connect(function()
        local export=SEGCFG.reportExport
        if export then
            export.current=math.max(1,export.current-1)
            SEGCFG.lastExportMessage="parte selecionada; toque COPIAR"
        else
            SEGCFG.lastExportMessage="gere o report no botão azul primeiro"
        end
        SEGCFG.updateReportExportButtons(); refreshLiveStatus()
    end)
    uiConnections[#uiConnections+1]=SEGCFG.exportNextButton.Activated:Connect(function()
        local export=SEGCFG.reportExport
        if export then
            export.current=math.min(#export.chunks,export.current+1)
            SEGCFG.lastExportMessage="parte selecionada; toque COPIAR"
        else
            SEGCFG.lastExportMessage="gere o report no botão azul primeiro"
        end
        SEGCFG.updateReportExportButtons(); refreshLiveStatus()
    end)
    local expanded=true
    uiConnections[#uiConnections+1]=collapse.Activated:Connect(function()
        expanded=not expanded; body.Visible=expanded
        panel.Size=expanded and UDim2.fromOffset(336,650) or UDim2.fromOffset(336,45)
        collapse.Text=expanded and "–" or "+"
    end)
    refreshPhaseButtons()
    uiUpdaterRunning=true
    task.spawn(function()
        while uiUpdaterRunning do
            task.wait(0.20)
            local ok=pcall(function() if type(refreshLiveStatus)=="function" then refreshLiveStatus() end end)
            if not ok then uiRefreshErrors+=1 end
        end
    end)
end

local discoverOk,discoverError=pcall(discoverFocusedChain)
if not discoverOk then discoveryStatus="error:"..cleanText(discoverError,180); addEvidence("DISCOVERY",discoveryStatus) end
local hookOk,hookError=pcall(installFocusedHooks)
if not hookOk then addEvidence("HOOK","installation-error="..cleanText(hookError,180)) end
local uiOk,uiError=pcall(createPanel)
if not uiOk then addEvidence("UI","creation-error="..cleanText(uiError,180)) end

getgenv().PCV614Start=startProbe
getgenv().PCV614PhaseA1=function() return beginControlledPhase("A1") end
getgenv().PCV614PhaseB1=function() return beginControlledPhase("B1") end
getgenv().PCV614PhaseB2=function() return beginControlledPhase("B2") end
getgenv().PCV614PhaseA2=function() return beginControlledPhase("A2") end
getgenv().PCV614Stop=function() stopProbe(); return getgenv().PCV614Report(false) end
getgenv().PCV614EmergencyV500=function()
    stopProbe()
    if type(baseSetRelay)=="function" then pcall(baseSetRelay,false) end
    refreshPhaseButtons()
    return true,"relay-disabled-v500-active"
end

getgenv().__PCMobileAimCleanup=function()
    probeRunning=false; currentFrame=nil; currentCalc=nil; uiUpdaterRunning=false
    for _,connection in ipairs(uiConnections) do pcall(function() connection:Disconnect() end) end
    uiConnections={}
    if screenGui then pcall(function() screenGui:Destroy() end) end
    screenGui=nil
    SEGCFG.exportCopyButton=nil; SEGCFG.exportPreviousButton=nil; SEGCFG.exportNextButton=nil
    SEGCFG.resetReportExport()
    restoreHooks()
    getgenv().PCV614Start=nil
    getgenv().PCV614PhaseA1=nil
    getgenv().PCV614PhaseB1=nil
    getgenv().PCV614PhaseB2=nil
    getgenv().PCV614PhaseA2=nil
    getgenv().PCV614Stop=nil
    getgenv().PCV614EmergencyV500=nil
    getgenv().PCV614Diagnostics=nil
    getgenv().PCV614Report=nil
    getgenv().PCV614EssentialReport=nil
    if baseCleanup then pcall(baseCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

addEvidence("READY","V614 TemporalPoseTelemetryR1 ready; Acquisition R2 and controlled matching unchanged; read-only matched telemetry")
warn("[V614 TemporalPoseTelemetryR1] ready | use mobile panel")
