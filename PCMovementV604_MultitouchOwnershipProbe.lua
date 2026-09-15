local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")

local player=Players.LocalPlayer
local WATCH_BIND="__PCMovementV604MultitouchOwnershipWatch"

--[[
    V604 / MULTITOUCH OWNERSHIP PROBE + GATED REAL-TOUCH MOUSE ROUTE

    V603 dynamically proved real Touch -> active BaseCamera.OnInputChanged ->
    OnMouseMoved using the same UserInputObject. It also proved that blindly
    routing every unprocessed Touch breaks joystick + camera multitouch.

    V604 keeps the proved stage but classifies each Touch by persistent identity:
      * joystick proof: active DynamicThumbstick.moveTouchObject == input;
      * camera proof: active BaseCamera.fingerTouches[input] == false;
      * unknown/conflict: fail open to the untouched V500 Touch path.

    The relay starts disabled on every load. It cannot be enabled until one
    joystick Touch and one camera Touch are simultaneously observed with those
    independent identity proofs and no role conflict.

    When enabled, a proved camera Touch first runs the original OnInputChanged
    with panEnabled temporarily false. This preserves OnTouchChanged bookkeeping,
    fingerTouches, and pinch state without Touch rotation. Only then is the same
    real Touch object passed to OnMouseMoved. Joystick, unknown, conflict, and
    two-camera-finger pinch events always remain on the original V500 path.

    No half-screen rule, synthetic input, reconnect, firesignal, VIM mouse input,
    UpdateMouseBehavior, CFrame/AutoRotate write, gain, or physics change exists.
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

getgenv().PCMovementVersion="V604-MultitouchOwnershipProbe"
getgenv().PCInputBridgeMode="v604-multitouch-diagnostic-over-v500"
getgenv().PCInputBridgeDiscovery="touch-ownership-proof-pending"
-- Never inherit an enabled relay from an earlier execution.
getgenv().PCV604RelayEnabled=false
if getgenv().PCV604RelayAutoFallback==nil then getgenv().PCV604RelayAutoFallback=true end
if getgenv().PCV604RelayNoRotateLimit==nil then getgenv().PCV604RelayNoRotateLimit=8 end

local playerModule
local cameras
local controls
local movementController
local activeController
local lastInstallAttempt=0
local lastMovementScanAttempt=0
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
local movementScanStatus="not-started"
local movementControllerOrigin="none"
local movementIdentityKeys={}
local movementRelevantMethods=0

local touchesObserved=0
local joystickTouchesIdentified=0
local cameraTouchesIdentified=0
local unknownTouchesObserved=0
local touchRoleConflicts=0
local joystickTouchesBlockedFromMouse=0
local cameraTouchesRelayedToMouse=0
local cameraTouchesDeferredForPinch=0
local unknownTouchesBlockedFromMouse=0
local touchBookkeepingPasses=0
local touchPanSuppressedConfirmed=0
local touchPanSuppressedUnclear=0
local simultaneousJoystickCameraObserved=0
local simultaneousJoystickCameraRelayed=0
local joystickMouseCrossovers=0
local ownershipGateProven=false
local ownershipProofStatus="awaiting-joystick-and-camera-identities"
local lastTouchId="none"
local lastTouchRole="unknown"
local lastOwnershipReason="not-observed"
local nextTouchId=0
local activeTouchRecords={}
local archivedTouchSummaries={}
local roleSeenCounts={joystick=0,camera=0,unknown=0,conflict=0}
local simultaneousActive=false
local touchStartedConnection=nil
local touchEndedConnection=nil
local touchLifecycleStatus="not-installed"

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

local relayEnabled=false
local relayAutoDisabled=false
local relayAttempts=0
local relayCompleted=0
local relayErrors=0
local relayRotateChanged=0
local relayRotateUnchanged=0
local relayConsecutiveUnchanged=0
local relaySameInputConfirmed=0
local relayLastStatus="disabled-until-dynamic-proof"
local lastRelayGate="not-evaluated"
local relayLastInput=nil

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

local function getControls()
    if type(controls)=="table" then return controls end
    local module=getPlayerModule()
    if type(module)~="table" then return nil end
    pcall(function()
        if type(module.GetControls)=="function" then controls=module:GetControls() end
        if type(controls)~="table" then controls=rawget(module,"controls") end
    end)
    return controls
end

local function getActiveMovementController()
    local controlModule=getControls()
    if type(controlModule)~="table" then return nil,"controls-unavailable" end
    local controller=rawget(controlModule,"activeController")
    if type(controller)=="table" then return controller,"controls.activeController" end
    controller=rawget(controlModule,"touchController")
    if type(controller)=="table" then return controller,"controls.touchController" end
    return nil,"active-movement-controller-unavailable"
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

local MOVEMENT_IDENTITY_FIELDS={
    "moveTouchObject","touchObject","moveTouch","movementTouchObject",
    "thumbstickTouch","activeTouchObject",
}

local function rememberMovementIdentityKey(key,origin)
    if type(key)~="string" then return end
    if not movementIdentityKeys[key] then movementIdentityKeys[key]=origin end
end

local function scanMovementController()
    movementController,movementControllerOrigin=getActiveMovementController()
    movementScanStatus="running"
    movementIdentityKeys={}
    movementRelevantMethods=0
    rememberMovementIdentityKey("moveTouchObject","known DynamicThumbstick state field")
    if type(movementController)~="table" then
        movementScanStatus=movementControllerOrigin
        addEvidence("MOVEMENT","active movement controller unavailable: "..movementControllerOrigin)
        return false
    end

    local seen={}
    local function visit(tbl,depth,origin)
        if type(tbl)~="table" or depth>10 or seen[tbl] then return end
        seen[tbl]=true
        local entries={}
        local ok,err=pcall(function()
            for key,value in pairs(tbl) do entries[#entries+1]={key=key,value=value} end
        end)
        if not ok then
            addEvidence("MOVEMENT","origin="..origin.." enumeration-error="..cleanText(err,160))
            return
        end
        table.sort(entries,function(a,b) return cleanText(a.key,90)<cleanText(b.key,90) end)
        addEvidence("MOVEMENT",string.format(
            "depth=%d origin=%s keys=%d table=%s",depth,origin,#entries,cleanText(tbl,100)
        ))
        local indexTable=nil
        for _,entry in ipairs(entries) do
            local keyText=cleanText(entry.key,100)
            local lower=string.lower(keyText)
            if entry.key=="__index" and type(entry.value)=="table" then indexTable=entry.value end
            if type(entry.value)=="function" and (
                string.find(lower,"input",1,true)
                or string.find(lower,"touch",1,true)
                or string.find(lower,"move",1,true)
                or string.find(lower,"thumb",1,true)
                or lower=="enable" or lower=="disable"
            ) then
                movementRelevantMethods+=1
                local constants,status=methodConstants(entry.value)
                addEvidence("MOVEMENT-METHOD",string.format(
                    "depth=%d origin=%s key=%s constantsStatus=%s constants={%s}",
                    depth,origin,keyText,status,table.concat(constants," | ")
                ))
                for _,constant in ipairs(constants) do
                    local constantLower=string.lower(constant)
                    if constantLower=="movetouchobject"
                        or (string.find(constantLower,"touch",1,true)
                            and string.find(constantLower,"object",1,true)) then
                        rememberMovementIdentityKey(constant,origin.."."..keyText.." constant")
                    end
                end
            elseif type(entry.key)=="string" then
                if (string.find(lower,"touch",1,true) and string.find(lower,"object",1,true))
                    or lower=="movetouch" then
                    rememberMovementIdentityKey(entry.key,origin.." raw state")
                end
            end
        end
        local metatable=nil
        if type(getrawmetatable)=="function" then pcall(function() metatable=getrawmetatable(tbl) end) end
        if type(metatable)~="table" then pcall(function() metatable=getmetatable(tbl) end) end
        if type(metatable)=="table" then visit(metatable,depth+1,origin.." -> getmetatable") end
        if type(indexTable)=="table" then visit(indexTable,depth+1,origin.." -> __index") end
    end
    visit(movementController,0,movementControllerOrigin)

    local keys={}
    for key,origin in pairs(movementIdentityKeys) do keys[#keys+1]=key.."@"..origin end
    table.sort(keys)
    movementScanStatus="complete"
    addEvidence("MOVEMENT-SUMMARY",string.format(
        "origin=%s relevantMethods=%d identityKeys={%s}",
        movementControllerOrigin,movementRelevantMethods,table.concat(keys," | ")
    ))
    return true
end

local TARGET_METHODS={
    OnInputBegan=true,
    OnInputChanged=true,
    OnInputEnded=true,
    OnTouchBegan=true,
    OnTouchChanged=true,
    OnTouchEnded=true,
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
        "levels=%d dedupedTables=%d maxDepth=%d OnTouchBegan=%s OnInputChanged=%s OnTouchChanged=%s OnTouchEnded=%s OnMouseMoved=%s ConnectInputEvents=%s",
        hierarchyLevelsVisited,hierarchyTablesDeduped,hierarchyMaxDepth,
        tostring(methodTargets.OnTouchBegan~=nil),
        tostring(methodTargets.OnInputChanged~=nil),
        tostring(methodTargets.OnTouchChanged~=nil),
        tostring(methodTargets.OnTouchEnded~=nil),
        tostring(methodTargets.OnMouseMoved~=nil),
        tostring(methodTargets.ConnectInputEvents~=nil)
    ))
    return methodTargets.OnInputChanged~=nil
end

local function ensureTouchRecord(input,processed,origin)
    local record=activeTouchRecords[input]
    if record then return record end
    nextTouchId+=1
    record={
        id="T"..tostring(nextTouchId),
        input=input,
        role="unknown",
        firstOrigin=origin,
        processedAtFirstObservation=processed,
        movementMatches=0,
        cameraMapFalse=0,
        joystickBlocked=0,
        mouseRelays=0,
        conflicts=0,
        unknownCounted=false,
        changes=0,
        lastProcessed=processed,
        lastMovementField="none",
        lastCameraMap="nil",
    }
    activeTouchRecords[input]=record
    touchesObserved+=1
    addEvidence("TOUCH-LIFECYCLE",string.format(
        "id=%s observed origin=%s processed=%s input=%s",
        record.id,origin,tostring(processed),cleanText(input,100)
    ))
    return record
end

local function readMovementIdentity(input)
    local controller,origin=getActiveMovementController()
    if type(controller)~="table" then return false,"none",origin end
    if controller~=movementController then
        movementController=controller
        movementControllerOrigin=origin
        movementScanStatus="controller-changed-rescan-needed"
    end
    local matches={}
    local tried={}
    local function tryKey(key)
        if type(key)~="string" or tried[key] then return end
        tried[key]=true
        local value
        local ok=pcall(function() value=rawget(controller,key) end)
        if ok and value==input then matches[#matches+1]=key end
    end
    for _,key in ipairs(MOVEMENT_IDENTITY_FIELDS) do tryKey(key) end
    for key in pairs(movementIdentityKeys) do tryKey(key) end
    table.sort(matches)
    return #matches>0,table.concat(matches,"+"),origin
end

local function readCameraTouchState(controller,input)
    local fingerTouches=rawget(controller,"fingerTouches")
    local mapValue=nil
    if type(fingerTouches)=="table" then pcall(function() mapValue=rawget(fingerTouches,input) end) end
    local unsunk=rawget(controller,"numUnsunkTouches")
    local dynamic=rawget(controller,"isDynamicThumbstickEnabled")
    return mapValue,unsunk,dynamic,type(fingerTouches)=="table"
end

local function updateSimultaneousProof()
    local hasJoystick=false
    local hasCamera=false
    for _,record in pairs(activeTouchRecords) do
        if record.role=="joystick" then hasJoystick=true end
        if record.role=="camera" then hasCamera=true end
    end
    local now=hasJoystick and hasCamera
    if now and not simultaneousActive then
        simultaneousJoystickCameraObserved+=1
        addEvidence("MULTITOUCH","proved simultaneous joystick identity + camera identity")
    end
    simultaneousActive=now
    if touchRoleConflicts>0 then
        ownershipGateProven=false
        ownershipProofStatus="rejected-role-conflict"
        getgenv().PCInputBridgeDiscovery=ownershipProofStatus
        if relayEnabled then
            relayEnabled=false
            relayAutoDisabled=true
            getgenv().PCV604RelayEnabled=false
            fallbackReason="ownership-conflict-v500-restored"
            getgenv().PCInputBridgeMode="v604-multitouch-diagnostic-over-v500"
        end
    elseif joystickTouchesIdentified>0 and cameraTouchesIdentified>0
        and simultaneousJoystickCameraObserved>0 then
        if not ownershipGateProven then
            addEvidence("OWNERSHIP-PROOF","gate proved: movement-controller identity and BaseCamera fingerTouches identity overlapped without conflict")
        end
        ownershipGateProven=true
        ownershipProofStatus="proved-by-simultaneous-object-identities"
        getgenv().PCInputBridgeDiscovery=ownershipProofStatus
    else
        ownershipProofStatus=string.format(
            "pending joystick=%d camera=%d simultaneous=%d",
            joystickTouchesIdentified,cameraTouchesIdentified,simultaneousJoystickCameraObserved
        )
    end
end

local function classifyTouch(controller,input,processed,origin)
    local record=ensureTouchRecord(input,processed,origin)
    record.changes+=1
    record.lastProcessed=processed
    local movementMatch,movementFields,movementOrigin=readMovementIdentity(input)
    local cameraMap,unsunk,dynamic,mapAvailable=readCameraTouchState(controller,input)
    local cameraMatch=mapAvailable and cameraMap==false
    local role="unknown"
    local reason
    local roleChanged=false
    if movementMatch and cameraMatch then
        role="conflict"
        reason="movement identity and fingerTouches=false both matched"
    elseif movementMatch then
        role="joystick"
        reason="active movement controller field(s)="..movementFields
    elseif cameraMatch then
        role="camera"
        reason="BaseCamera.fingerTouches[input]==false"
    else
        reason="no exact movement identity and camera map is "..tostring(cameraMap)
    end

    record.lastMovementField=movementFields~="" and movementFields or "none"
    record.lastCameraMap=tostring(cameraMap)
    record.lastUnsunk=unsunk
    record.lastDynamicThumbstick=dynamic
    if movementMatch then record.movementMatches+=1 end
    if cameraMatch then record.cameraMapFalse+=1 end

    if role~="unknown" and record.role~=role then
        if record.role=="unknown" then
            record.role=role
            roleChanged=true
            roleSeenCounts[role]+=1
            if role=="joystick" then joystickTouchesIdentified+=1 end
            if role=="camera" then cameraTouchesIdentified+=1 end
            if role=="conflict" then
                touchRoleConflicts+=1
                record.conflicts+=1
            end
        elseif record.role~="conflict" then
            record.role="conflict"
            roleChanged=true
            roleSeenCounts.conflict+=1
            touchRoleConflicts+=1
            record.conflicts+=1
            reason="role changed from a previously proved identity to "..role
        end
    end

    if record.role=="unknown" and not record.unknownCounted then
        record.unknownCounted=true
        unknownTouchesObserved+=1
        roleSeenCounts.unknown+=1
    elseif record.role~="unknown" and record.unknownCounted then
        record.unknownCounted=false
        unknownTouchesObserved=math.max(0,unknownTouchesObserved-1)
    end

    lastTouchId=record.id
    lastTouchRole=record.role
    lastOwnershipReason=reason
    updateSimultaneousProof()
    if roleChanged or record.changes<=6 or record.changes%100==0 then
        addEvidence("OWNERSHIP",string.format(
            "id=%s origin=%s role=%s movementMatch=%s movementFields=%s movementOrigin=%s fingerTouches=%s numUnsunkTouches=%s dynamicThumbstick=%s processed=%s reason=%s",
            record.id,origin,record.role,tostring(movementMatch),movementFields,
            movementOrigin,tostring(cameraMap),tostring(unsunk),tostring(dynamic),
            tostring(processed),reason
        ))
    end
    return record,record.role,unsunk,dynamic
end

local function archiveTouch(input,processed)
    local record=activeTouchRecords[input]
    if not record then return end
    local summary=string.format(
        "%s{role=%s,processedStart=%s,movementMatches=%d,cameraMapFalse=%d,joystickBlocked=%d,mouseRelays=%d,conflicts=%d}",
        record.id,record.role,tostring(record.processedAtFirstObservation),
        record.movementMatches,record.cameraMapFalse,record.joystickBlocked,
        record.mouseRelays,record.conflicts
    )
    archivedTouchSummaries[#archivedTouchSummaries+1]=summary
    if #archivedTouchSummaries>12 then table.remove(archivedTouchSummaries,1) end
    addEvidence("TOUCH-LIFECYCLE","ended "..summary.." processed="..tostring(processed))
    activeTouchRecords[input]=nil
    updateSimultaneousProof()
end

local function relayGateReason(controller,input,role,unsunk)
    if not relayEnabled then return "relay-disabled" end
    if relayAutoDisabled then return "relay-auto-disabled" end
    if not dynamicStageProven then return "dynamic-stage-unproven" end
    if not ownershipGateProven then return "ownership-gate-unproven" end
    if controller~=getActiveController() then return "controller-not-active" end
    if getInputType(input)~=Enum.UserInputType.Touch then return "not-touch" end
    if role=="joystick" then return "joystick-identity" end
    if role=="conflict" then return "ownership-conflict" end
    if role~="camera" then return "ownership-unknown" end
    if unsunk~=1 then return "camera-pinch-or-unsunk-count-"..tostring(unsunk) end
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
                if relayLastInput~=nil and input==relayLastInput then
                    relaySameInputConfirmed+=1
                    if context then context.sameRelayInput=true end
                end
                if context and context.role=="joystick" then
                    joystickMouseCrossovers+=1
                    context.joystickMouseCrossover=true
                    if relayEnabled then
                        relayEnabled=false
                        relayAutoDisabled=true
                        getgenv().PCV604RelayEnabled=false
                        fallbackReason="joystick-mouse-crossover-v500-restored"
                        getgenv().PCInputBridgeMode="v604-multitouch-diagnostic-over-v500"
                    end
                end
            end
            local contextId=context and context.id or 0
            local sameRelay=relayLastInput~=nil and input==relayLastInput
            if contextId<=40 or contextId%100==0 or (sameRelay and (relayAttempts<=40 or relayAttempts%100==0)) then
                addEvidence("BRANCH",string.format(
                    "method=%s activeController=%s inputType=%s delta=%s context=%s sameRelayInput=%s",
                    name,tostring(active),tostring(getInputType(input)),cleanText(getInputDelta(input),120),
                    tostring(context and context.id or "none"),tostring(sameRelay)
                ))
            end
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
                sameRelayInput=false,
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

            local touchRecord=nil
            local touchRole="not-touch"
            local unsunk=nil
            local dynamicThumbstick=nil
            if isActive and inputType==Enum.UserInputType.Touch then
                local firstProof=not dynamicStageProven
                dynamicStageProven=true
                if firstProof then
                    probeStatus="dynamic-stage-proven-observational"
                    getgenv().PCInputBridgeDiscovery="active-controller-OnInputChanged-received-real-Touch"
                    addEvidence("PROOF","dynamic stage proved by real Touch with self == activeCameraController")
                end
                touchRecord,touchRole,unsunk,dynamicThumbstick=classifyTouch(
                    self,input,processed,"active BaseCamera.OnInputChanged"
                )
            end

            context.touchId=touchRecord and touchRecord.id or "none"
            context.role=touchRole
            context.joystickMouseCrossover=false
            local gate=relayGateReason(self,input,touchRole,unsunk)
            lastRelayGate=gate
            local results
            local relayDispatchSucceeded=false
            local relayFailureDetail=nil
            if gate=="open" then
                relayAttempts+=1
                relayLastInput=input
                lastRoute="camera-bookkeeping-then-same-touch-onmousemoved"
                local mouseTarget=methodTargets.OnMouseMoved
                local previousPan=rawget(self,"panEnabled")
                if previousPan==nil then
                    gate="panEnabled-unobservable"
                    lastRelayGate=gate
                    lastRoute="pan-unobservable-original-v500"
                    results=table.pack(pcall(callOriginal,self,input,processed,...))
                else
                    self.panEnabled=false
                    local touchResults=table.pack(pcall(callOriginal,self,input,processed,...))
                    self.panEnabled=previousPan
                    touchBookkeepingPasses+=touchResults[1] and 1 or 0
                    local afterTouch=readRotate(self)
                    local touchChanged=rotationChanged(before,afterTouch)
                    if touchChanged==false then
                        touchPanSuppressedConfirmed+=1
                    else
                        touchPanSuppressedUnclear+=1
                    end
                    if not touchResults[1] then
                        results=touchResults
                    else
                        local mouseResults=table.pack(pcall(function()
                            return mouseTarget.fn(self,input)
                        end))
                        if mouseResults[1] then
                            results=touchResults
                            relayCompleted+=1
                            relayDispatchSucceeded=true
                            cameraTouchesRelayedToMouse+=1
                            if touchRecord then touchRecord.mouseRelays+=1 end
                            if simultaneousActive then simultaneousJoystickCameraRelayed+=1 end
                        else
                            relayFailureDetail="OnMouseMoved: "..cleanText(mouseResults[2],160)
                            -- OnTouchChanged bookkeeping already succeeded. Keep
                            -- its original return and fail open for later events.
                            results=touchResults
                        end
                    end
                end
                relayLastInput=nil
                if relayFailureDetail or not results[1] then
                    relayErrors+=1
                    if relayFailureDetail then callbackErrors+=1 end
                    relayEnabled=false
                    relayAutoDisabled=true
                    getgenv().PCV604RelayEnabled=false
                    lastRoute="relay-error-then-original-v500"
                    relayLastStatus="error-fallback-v500: "
                        ..tostring(relayFailureDetail or cleanText(results[2],160))
                    fallbackReason="relay-error-v500-restored"
                    getgenv().PCInputBridgeMode="v604-observational-pass-through-over-v500"
                    addEvidence("RELAY","bookkeeping/OnMouseMoved route failed; subsequent events restored to V500")
                end
            else
                if relayEnabled and touchRecord and touchRole=="joystick" then
                    joystickTouchesBlockedFromMouse+=1
                    touchRecord.joystickBlocked+=1
                    lastRoute="joystick-identity-original-v500"
                elseif relayEnabled and touchRecord and touchRole=="camera" and unsunk~=1 then
                    cameraTouchesDeferredForPinch+=1
                    lastRoute="camera-pinch-original-v500"
                elseif relayEnabled and touchRecord and (touchRole=="unknown" or touchRole=="conflict") then
                    unknownTouchesBlockedFromMouse+=1
                    lastRoute="unknown-or-conflict-original-v500"
                else
                    lastRoute="diagnostic-original-arguments-unchanged"
                end
                results=table.pack(pcall(callOriginal,self,input,processed,...))
            end

            local after=readRotate(self)
            rotateAfter=after
            lastOnInputCalledOnTouchChanged=context.calledTouch
            lastOnInputCalledOnMouseMoved=context.calledMouse
            contextStack[#contextStack]=nil

            if relayDispatchSucceeded then
                local changed=rotationChanged(before,after)
                if changed==true then
                    relayRotateChanged+=1
                    relayConsecutiveUnchanged=0
                    relayLastStatus=context.sameRelayInput
                        and "same-touch-object-onmousemoved-rotate-changed"
                        or "onmousemoved-rotate-changed-observer-unconfirmed"
                else
                    relayRotateUnchanged+=1
                    relayConsecutiveUnchanged+=1
                    relayLastStatus=changed==false
                        and "onmousemoved-returned-rotate-unchanged"
                        or "onmousemoved-returned-rotate-unobservable"
                    local limit=math.max(1,tonumber(getgenv().PCV604RelayNoRotateLimit) or 8)
                    if getgenv().PCV604RelayAutoFallback~=false
                        and relayConsecutiveUnchanged>=limit then
                        relayEnabled=false
                        relayAutoDisabled=true
                        getgenv().PCV604RelayEnabled=false
                        relayLastStatus="auto-disabled-after-"..tostring(limit).."-unchanged"
                        fallbackReason="relay-no-rotate-v500-restored"
                        getgenv().PCInputBridgeMode="v604-observational-over-v500"
                    end
                end
            end

            if context.id<=60 or context.id%100==0
                or (relayDispatchSucceeded and (relayAttempts<=40 or relayAttempts%100==0))
                or context.joystickMouseCrossover or not results[1] then
                addEvidence("ONINPUT",string.format(
                    "event=%d touchId=%s role=%s selfActive=%s inputType=%s delta=%s processed=%s route=%s gate=%s numUnsunk=%s dynamicThumbstick=%s touchBranch=%s mouseBranch=%s joystickMouseCrossover=%s rotateBefore=%s rotateAfter=%s ok=%s",
                    context.id,context.touchId,touchRole,tostring(isActive),tostring(inputType),cleanText(delta,120),
                    tostring(processed),lastRoute,gate,tostring(unsunk),tostring(dynamicThumbstick),
                    tostring(context.calledTouch),tostring(context.calledMouse),
                    tostring(context.joystickMouseCrossover),cleanText(before,120),cleanText(after,120),
                    tostring(results[1])
                ))
            end

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

local function installTouchLifecycleObservers()
    if touchStartedConnection or touchEndedConnection then return true end
    local startedOk,started=pcall(function()
        return UserInputService.TouchStarted:Connect(function(input,processed)
            local record=ensureTouchRecord(input,processed,"UIS.TouchStarted")
            task.defer(function()
                if activeTouchRecords[input]~=record then return end
                local controller=getActiveController()
                if type(controller)=="table" then
                    classifyTouch(controller,input,processed,"UIS.TouchStarted deferred")
                end
            end)
        end)
    end)
    if startedOk then touchStartedConnection=started end

    local endedOk,ended=pcall(function()
        return UserInputService.TouchEnded:Connect(function(input,processed)
            local controller=getActiveController()
            if type(controller)=="table" and activeTouchRecords[input] then
                classifyTouch(controller,input,processed,"UIS.TouchEnded")
            end
            archiveTouch(input,processed)
        end)
    end)
    if endedOk then touchEndedConnection=ended end
    touchLifecycleStatus=(touchStartedConnection and touchEndedConnection)
        and "TouchStarted+TouchEnded-installed"
        or "partial started="..tostring(touchStartedConnection~=nil)
            .." ended="..tostring(touchEndedConnection~=nil)
    addEvidence("TOUCH-LIFECYCLE",touchLifecycleStatus)
    return touchStartedConnection~=nil and touchEndedConnection~=nil
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
    scanMovementController()
    installTouchLifecycleObservers()

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
    probeStatus="multitouch-ownership-diagnostic-installed"
    fallbackReason="diagnostic-only-v500-preserved"
    getgenv().PCInputBridgeMode="v604-multitouch-diagnostic-over-v500"
    getgenv().PCInputBridgeDiscovery="awaiting-simultaneous-joystick-camera-identity-proof"
    addEvidence("ACTIVATION","ownership diagnostic installed; relay remains disabled and original arguments remain unchanged")
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
    touchesObserved=0
    joystickTouchesIdentified=0
    cameraTouchesIdentified=0
    unknownTouchesObserved=0
    touchRoleConflicts=0
    joystickTouchesBlockedFromMouse=0
    cameraTouchesRelayedToMouse=0
    cameraTouchesDeferredForPinch=0
    unknownTouchesBlockedFromMouse=0
    touchBookkeepingPasses=0
    touchPanSuppressedConfirmed=0
    touchPanSuppressedUnclear=0
    simultaneousJoystickCameraObserved=0
    simultaneousJoystickCameraRelayed=0
    joystickMouseCrossovers=0
    ownershipGateProven=false
    ownershipProofStatus="awaiting-joystick-and-camera-identities"
    lastTouchId="none"
    lastTouchRole="unknown"
    lastOwnershipReason="not-observed"
    nextTouchId=0
    activeTouchRecords={}
    archivedTouchSummaries={}
    roleSeenCounts={joystick=0,camera=0,unknown=0,conflict=0}
    simultaneousActive=false
    relayEnabled=false
    relayAutoDisabled=false
    relayAttempts=0
    relayCompleted=0
    relayErrors=0
    relayRotateChanged=0
    relayRotateUnchanged=0
    relayConsecutiveUnchanged=0
    relaySameInputConfirmed=0
    relayLastStatus="disabled-until-dynamic-proof"
    lastRelayGate="not-evaluated"
    relayLastInput=nil
    getgenv().PCV604RelayEnabled=false
end

getgenv().PCV604SetRelayEnabled=function(enabled)
    if enabled~=true then
        relayEnabled=false
        getgenv().PCV604RelayEnabled=false
        relayLastStatus="disabled-manually-v500-active"
        getgenv().PCInputBridgeMode="v604-multitouch-diagnostic-over-v500"
        return true,"relay-disabled"
    end
    if not ownershipGateProven then
        relayLastStatus="enable-rejected-ownership-gate-unproven"
        return false,"ownershipGateProven must be true after simultaneous joystick + camera observation"
    end
    if not probeInstalled or not methodTargets.OnMouseMoved then
        relayLastStatus="enable-rejected-OnMouseMoved-unavailable"
        return false,"OnMouseMoved observation target is unavailable"
    end
    relayAutoDisabled=false
    relayConsecutiveUnchanged=0
    relayEnabled=true
    getgenv().PCV604RelayEnabled=true
    relayLastStatus="enabled-awaiting-eligible-real-touch"
    fallbackReason="relay-experiment-active-v500-fail-open-available"
    getgenv().PCInputBridgeMode="v604-owned-camera-touch-to-OnMouseMoved"
    addEvidence("RELAY","explicitly enabled after multitouch ownership proof; joystick identities remain on V500 and camera identities use bookkeeping + same-object OnMouseMoved")
    return true,"relay-enabled"
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
    if os.clock()-lastMovementScanAttempt>=1 then
        local currentMovement=getActiveMovementController()
        if currentMovement~=movementController or movementScanStatus~="complete" then
            lastMovementScanAttempt=os.clock()
            pcall(scanMovementController)
        end
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

local function touchProofSummary()
    local lines={}
    for _,summary in ipairs(archivedTouchSummaries) do lines[#lines+1]=summary end
    local active={}
    for _,record in pairs(activeTouchRecords) do
        active[#active+1]=string.format(
            "%s{ACTIVE,role=%s,movementMatches=%d,cameraMapFalse=%d,joystickBlocked=%d,mouseRelays=%d,conflicts=%d}",
            record.id,record.role,record.movementMatches,record.cameraMapFalse,
            record.joystickBlocked,record.mouseRelays,record.conflicts
        )
    end
    table.sort(active)
    for _,summary in ipairs(active) do lines[#lines+1]=summary end
    return #lines>0 and table.concat(lines," | ") or "none"
end

local function activeTouchRoleState()
    local all={}
    local joystick={}
    local camera={}
    local unknown={}
    for _,record in pairs(activeTouchRecords) do
        all[#all+1]=record.id
        if record.role=="joystick" then joystick[#joystick+1]=record.id
        elseif record.role=="camera" then camera[#camera+1]=record.id
        else unknown[#unknown+1]=record.id end
    end
    table.sort(all)
    table.sort(joystick)
    table.sort(camera)
    table.sort(unknown)
    return #all,table.concat(joystick,","),table.concat(camera,","),table.concat(unknown,",")
end

getgenv().PCV604Diagnostics=function()
    local controller=getActiveController()
    local inMouseLockedMode=nil
    local getIsMouseLocked=nil
    local mouseLockOffset=nil
    local rotateInput=nil
    local fingerTouchesCount=nil
    local numUnsunkTouches=nil
    local isDynamicThumbstickEnabled=nil
    local currentMoveTouchObject=nil
    if type(controller)=="table" then
        pcall(function() inMouseLockedMode=controller.inMouseLockedMode end)
        pcall(function()
            if type(controller.GetIsMouseLocked)=="function" then
                getIsMouseLocked=controller:GetIsMouseLocked()
            end
        end)
        pcall(function() mouseLockOffset=controller.mouseLockOffset end)
        pcall(function() rotateInput=controller.rotateInput end)
        pcall(function()
            local fingerTouches=controller.fingerTouches
            if type(fingerTouches)=="table" then
                fingerTouchesCount=0
                for _ in pairs(fingerTouches) do fingerTouchesCount+=1 end
            end
        end)
        pcall(function() numUnsunkTouches=controller.numUnsunkTouches end)
        pcall(function() isDynamicThumbstickEnabled=controller.isDynamicThumbstickEnabled end)
    end
    local currentMovement,currentMovementOrigin=getActiveMovementController()
    if type(currentMovement)=="table" then
        pcall(function() currentMoveTouchObject=rawget(currentMovement,"moveTouchObject") end)
    end
    local identityKeys={}
    for key,origin in pairs(movementIdentityKeys) do identityKeys[#identityKeys+1]=key.."@"..origin end
    table.sort(identityKeys)
    local activeTouchCount,activeJoystickTouchIds,activeCameraTouchIds,activeUnknownTouchIds=
        activeTouchRoleState()
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
        onTouchBeganFound=methodTargets.OnTouchBegan~=nil,
        onTouchEndedFound=methodTargets.OnTouchEnded~=nil,
        hierarchyLevelsVisited=hierarchyLevelsVisited,
        hierarchyTablesDeduped=hierarchyTablesDeduped,
        hierarchyMaxDepth=hierarchyMaxDepth,
        movementControllerFound=type(currentMovement)=="table",
        movementControllerOrigin=currentMovementOrigin,
        movementScanStatus=movementScanStatus,
        movementRelevantMethods=movementRelevantMethods,
        movementIdentityKeys=table.concat(identityKeys," | "),
        moveTouchObjectActive=currentMoveTouchObject~=nil,
        moveTouchObjectValue=cleanText(currentMoveTouchObject,120),
        fingerTouchesCount=fingerTouchesCount,
        numUnsunkTouches=numUnsunkTouches,
        isDynamicThumbstickEnabled=isDynamicThumbstickEnabled,
        touchLifecycleStatus=touchLifecycleStatus,
        touchesObserved=touchesObserved,
        joystickTouchesIdentified=joystickTouchesIdentified,
        cameraTouchesIdentified=cameraTouchesIdentified,
        unknownTouchesObserved=unknownTouchesObserved,
        touchRoleConflicts=touchRoleConflicts,
        joystickTouchesBlockedFromMouse=joystickTouchesBlockedFromMouse,
        cameraTouchesRelayedToMouse=cameraTouchesRelayedToMouse,
        cameraTouchesDeferredForPinch=cameraTouchesDeferredForPinch,
        unknownTouchesBlockedFromMouse=unknownTouchesBlockedFromMouse,
        simultaneousJoystickCameraObserved=simultaneousJoystickCameraObserved,
        simultaneousJoystickCameraRelayed=simultaneousJoystickCameraRelayed,
        joystickMouseCrossovers=joystickMouseCrossovers,
        ownershipGateProven=ownershipGateProven,
        ownershipProofStatus=ownershipProofStatus,
        lastTouchId=lastTouchId,
        lastTouchRole=lastTouchRole,
        lastOwnershipReason=lastOwnershipReason,
        touchProofSummary=touchProofSummary(),
        activeTouchCount=activeTouchCount,
        activeJoystickTouchIds=activeJoystickTouchIds~="" and activeJoystickTouchIds or "none",
        activeCameraTouchIds=activeCameraTouchIds~="" and activeCameraTouchIds or "none",
        activeUnknownTouchIds=activeUnknownTouchIds~="" and activeUnknownTouchIds or "none",
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
        validationReady=probeInstalled and dynamicStageProven and ownershipGateProven,
        relayEnabled=relayEnabled,
        relayAutoDisabled=relayAutoDisabled,
        relayAttempts=relayAttempts,
        relayCompleted=relayCompleted,
        relayErrors=relayErrors,
        relayRotateChanged=relayRotateChanged,
        relayRotateUnchanged=relayRotateUnchanged,
        relaySameInputConfirmed=relaySameInputConfirmed,
        relayLastStatus=relayLastStatus,
        lastRelayGate=lastRelayGate,
        touchBookkeepingPasses=touchBookkeepingPasses,
        touchPanSuppressedConfirmed=touchPanSuppressedConfirmed,
        touchPanSuppressedUnclear=touchPanSuppressedUnclear,
        relayValidationReady=ownershipGateProven and relayCompleted>0
            and relaySameInputConfirmed>0 and relayRotateChanged>0
            and simultaneousJoystickCameraRelayed>0
            and joystickTouchesBlockedFromMouse>0
            and joystickMouseCrossovers==0 and callbackErrors==0,
        callbackErrors=callbackErrors,
        fallbackReason=fallbackReason,
        fallbackV500Preserved=restoreOk,
        v500TouchPathActive=not relayEnabled,
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
        relayPreservesOnTouchChangedBookkeeping=true,
        usesProcessedAsOwnershipGate=false,
        usesHalfScreenGate=false,
        usesSyntheticUserInputObject=false,
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
        warn("=== PC MOVEMENT V604 EVIDENCE CHUNK "..tostring(index).." ===\n"..table.concat(chunk,"\n"))
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

getgenv().PCV604Evidence=function()
    local lines={
        "Diagnostic mode is default: every OnInputChanged call forwards original arguments unchanged.",
        "Joystick ownership requires active movement-controller object identity; camera ownership requires fingerTouches[input] == false.",
        "Relay starts disabled and requires simultaneous joystick + camera proof before PCV604SetRelayEnabled(true).",
        "Relay preserves OnTouchChanged bookkeeping with pan temporarily suppressed, then sends only the same proved camera Touch to OnMouseMoved.",
        "Evidence lines stored="..tostring(#evidence).." dropped-after-cap="..tostring(evidenceDropped),
    }
    for _,line in ipairs(evidence) do lines[#lines+1]=line end
    warnEvidenceChunks(lines)
    return "=== PC MOVEMENT V604 DETAILED EVIDENCE ===\n"..table.concat(lines,"\n")
end

getgenv().PCV604Report=function(includeEvidence)
    local diagnostics=getgenv().PCV604Diagnostics()
    local keys={
        "version","bridgeMode","discovery","probeInstalled","probeStatus",
        "onInputChangedFound","onInputChangedOrigin","onTouchBeganFound","onTouchChangedFound",
        "onTouchChangedOrigin","onMouseMovedFound","onMouseMovedOrigin",
        "onTouchEndedFound","connectInputEventsFound","hierarchyLevelsVisited","hierarchyTablesDeduped",
        "hierarchyMaxDepth","movementControllerFound","movementControllerOrigin",
        "movementScanStatus","movementRelevantMethods","movementIdentityKeys",
        "moveTouchObjectActive","moveTouchObjectValue","fingerTouchesCount",
        "numUnsunkTouches","isDynamicThumbstickEnabled","touchLifecycleStatus",
        "touchesObserved","joystickTouchesIdentified","cameraTouchesIdentified",
        "unknownTouchesObserved","touchRoleConflicts","joystickTouchesBlockedFromMouse",
        "cameraTouchesRelayedToMouse","cameraTouchesDeferredForPinch",
        "unknownTouchesBlockedFromMouse","simultaneousJoystickCameraObserved",
        "simultaneousJoystickCameraRelayed","joystickMouseCrossovers",
        "ownershipGateProven","ownershipProofStatus","lastTouchId","lastTouchRole",
        "lastOwnershipReason","touchProofSummary","activeTouchCount",
        "activeJoystickTouchIds","activeCameraTouchIds","activeUnknownTouchIds",
        "onInputChangedObserved","onInputChangedObservedEvents",
        "onInputChangedActiveControllerHits","realTouchHits","onTouchChangedHits",
        "onMouseMovedHits","onInputTouchPathConfirmedHits","onInputMousePathConfirmedHits",
        "inactiveControllerCalls","lastSelfWasActive","lastInputType","lastInputDelta",
        "lastProcessed","rotateBefore","rotateAfter","lastRoute",
        "lastOnInputCalledOnTouchChanged","lastOnInputCalledOnMouseMoved",
        "dynamicStageProven","validationReady","relayEnabled","relayAutoDisabled",
        "relayAttempts","relayCompleted","relayErrors","relayRotateChanged",
        "relayRotateUnchanged","relaySameInputConfirmed","relayLastStatus","lastRelayGate",
        "touchBookkeepingPasses","touchPanSuppressedConfirmed","touchPanSuppressedUnclear",
        "relayValidationReady","callbackErrors","fallbackReason","fallbackV500Preserved",
        "v500TouchPathActive","restoreOk","restoreDetail","activeControllerFound","inMouseLockedMode",
        "getIsMouseLocked","mouseLockOffset","rotateInput","preferredInput","evidenceLines","evidenceDropped",
        "phase1ForwardsOriginalArguments","relayPreservesOnTouchChangedBookkeeping",
        "usesProcessedAsOwnershipGate","usesHalfScreenGate","usesSyntheticUserInputObject",
        "triggersReconnect","usesFireSignal",
        "usesVirtualMouseInjection","callsUpdateMouseBehavior","writesCameraCFrame",
        "writesRootPartCFrame","forcesAutoRotate","changesGainSensitivityPhysics",
    }
    local lines={"=== PC MOVEMENT V604 REPORT ==="}
    for _,key in ipairs(keys) do lines[#lines+1]=key.." = "..tostring(diagnostics[key]) end
    local summary=table.concat(lines,"\n")
    warn(summary)
    local details=""
    if includeEvidence~=false then details=getgenv().PCV604Evidence() end
    return details~="" and summary.."\n\n"..details or summary
end

getgenv().__PCMobileAimCleanup=function()
    pcall(function() RunService:UnbindFromRenderStep(WATCH_BIND) end)
    relayEnabled=false
    getgenv().PCV604RelayEnabled=false
    restoreHooks()
    if touchStartedConnection then pcall(function() touchStartedConnection:Disconnect() end) end
    if touchEndedConnection then pcall(function() touchEndedConnection:Disconnect() end) end
    touchStartedConnection=nil
    touchEndedConnection=nil

    getgenv().PCV604SetRelayEnabled=nil
    getgenv().PCV604Diagnostics=nil
    getgenv().PCV604Evidence=nil
    getgenv().PCV604Report=nil

    if baseCleanup then pcall(baseCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

warn(string.format(
    "[V604] multitouch ownership probe | status=%s | movement=%s | OnInputChanged=%s | OnTouchChanged=%s | OnMouseMoved=%s | relay=disabled",
    probeStatus,movementScanStatus,tostring(methodTargets.OnInputChanged~=nil),
    tostring(methodTargets.OnTouchChanged~=nil),tostring(methodTargets.OnMouseMoved~=nil)
))
