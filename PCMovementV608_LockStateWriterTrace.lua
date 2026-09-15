local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")

local player=Players.LocalPlayer
local UI_NAME="PCMovementV608Panel"

--[[
    V608 / LOCK-STATE WRITER TRACE

    Accepted without re-testing:
      * V604 owns multitouch classification and the proved real-Touch relay.
      * V606 proved downstream mouse-lock composition in 1416/1416 frames.
      * V607 proved MouseLockController adds toggle/binding/cursor state, not geometry.

    This build has one purpose: explain the V606 -> V607 lock-state discrepancy.
    It hooks only CameraModule.Update and these existing BaseCamera methods:
      SetIsMouseLocked, SetMouseLockOffset, GetIsMouseLocked, GetMouseLockOffset.

    Every original call is forwarded unchanged. V608 never invokes a lock/offset
    setter or getter to collect data and never writes any camera/character state.
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

getgenv().PCMovementVersion="V608-LockStateWriterTrace"
getgenv().PCInputBridgeMode="v608-observational-lock-writer-trace-over-v604"

local cameras
local targetController
local targets={}
local targetEvidence={}
local installedHooks={}
local discoveryStatus="not-started"
local discoveryErrors={}

local probeRunning=false
local probeStartedAt=0
local probeDuration=0
local probeFrames=0
local eventSerial=0
local traceErrors=0
local traceLines={}
local traceDropped=0
local evidence={}
local evidenceDropped=0
local currentUpdate=nil
local pendingBeforeUpdate={}
local sequenceCounts={}
local suppressTrace=false

local stateAtStart=nil
local stateAtStop=nil
local lastState=nil
local lastLockWriter=nil
local lastOffsetWriter=nil

local cameraModuleUpdates=0
local updateShiftTrue=0
local updateShiftFalse=0
local updateShiftMissing=0
local updatePrimaryPartPresent=0

local setLockCalls=0
local setLockInside=0
local setLockOutside=0
local setLockActiveSelf=0
local setLockOtherSelf=0
local setLockTrue=0
local setLockFalse=0
local setLockExecutor=0
local setLockGame=0
local setOffsetCalls=0
local setOffsetInside=0
local setOffsetOutside=0
local setOffsetActiveSelf=0
local setOffsetOtherSelf=0
local setOffsetNormal=0
local setOffsetZero=0
local setOffsetOther=0
local setOffsetExecutor=0
local setOffsetGame=0
local getLockCalls=0
local getLockInside=0
local getLockOutside=0
local getLockActiveSelf=0
local getLockOtherSelf=0
local getOffsetCalls=0
local getOffsetInside=0
local getOffsetOutside=0
local getOffsetActiveSelf=0
local getOffsetOtherSelf=0

local customLockCalls=0
local customLockShiftMatches=0
local customLockShiftMismatches=0
local customLockTrue=0
local customLockFalse=0
local customOffsetCalls=0
local v500CandidateLockCalls=0
local v500CandidateOffsetCalls=0
local v500NormalLockCalls=0
local v500ReleaseLockCalls=0
local v500NormalOffsetCalls=0
local v500ZeroOffsetCalls=0
local v500StateReasonMatches=0
local v500StateReasonMismatches=0
local beforeUpdateLockCalls=0
local beforeUpdateOffsetCalls=0
local activeControllerChanges=0
local lastActiveController=nil
local v500FramePairs={}
local v500NormalPairFrames=0
local v500ReleasePairFrames=0
local v500ReleaseReasons={}

local screenGui=nil
local statusLabel=nil
local relayButton=nil
local uiConnections={}

local NORMAL_OFFSET=Vector3.new(2,0.5,0)
local ZERO_OFFSET=Vector3.zero
local REQUIRED_UPDATE_CONSTANTS={
    "PlayerScripts","ShiftLockEnabled","Character","PrimaryPart","ToOrientation","CFrame","math","abs",
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
    local scale=10^(digits or 4)
    if value>=0 then return math.floor(value*scale+0.5)/scale end
    return math.ceil(value*scale-0.5)/scale
end

local function addEvidence(section,message)
    if #evidence>=180 then evidenceDropped+=1; return end
    evidence[#evidence+1]=string.format("[%03d][%s] %s",#evidence+1,section,cleanText(message,950))
end

local function addTrace(message,force)
    if not force and #traceLines>=520 then traceDropped+=1; return end
    if #traceLines>=620 then traceDropped+=1; return end
    traceLines[#traceLines+1]=cleanText(message,1400)
end

local function getPlayerModule()
    local scripts=player:FindFirstChild("PlayerScripts")
    local module=scripts and scripts:FindFirstChild("PlayerModule")
    if not module then return nil end
    local result
    pcall(function() result=require(module) end)
    return type(result)=="table" and result or nil
end

local function getCameras()
    local module=getPlayerModule()
    if type(module)~="table" then return nil end
    local result
    pcall(function()
        if type(module.GetCameras)=="function" then result=module:GetCameras() end
        if type(result)~="table" then result=rawget(module,"cameras") end
    end)
    return type(result)=="table" and result or nil
end

local function getActiveController()
    local module=cameras
    if type(module)~="table" then module=getCameras(); cameras=module end
    if type(module)~="table" then return nil end
    local active
    pcall(function()
        active=rawget(module,"activeCameraController")
        if type(active)~="table" and type(module.GetActiveCameraController)=="function" then
            active=module:GetActiveCameraController()
        end
    end)
    return type(active)=="table" and active or nil
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
        if type(tbl)~="table" or depth>12 or seen[tbl] then return nil end
        seen[tbl]=true
        local value
        pcall(function() value=rawget(tbl,name) end)
        if type(value)=="function" then
            return {fn=value,owner=tbl,origin=origin.."."..name,depth=depth}
        end
        local mt=getMeta(tbl)
        local found
        if mt then found=visit(mt,depth+1,origin.." -> getmetatable") end
        if found then return found end
        local index
        pcall(function() index=rawget(tbl,"__index") end)
        if type(index)=="table" then return visit(index,depth+1,origin.." -> __index") end
        return nil
    end
    return visit(root,0,"target")
end

local function constantsList(fn)
    local getter=(debug and debug.getconstants) or getconstants
    if type(getter)~="function" then return {},"unavailable" end
    local ok,values=pcall(getter,fn)
    if not ok or type(values)~="table" then return {},"error:"..cleanText(values,100) end
    local result={}
    for _,value in ipairs(values) do
        if (type(value)=="string" or type(value)=="number") and #result<100 then
            result[#result+1]=cleanText(value,70)
        end
    end
    return result,table.concat(result," | ")
end

local function hasConstants(list,wanted)
    local found={}
    for _,value in ipairs(list) do found[tostring(value)]=true end
    local missing={}
    for _,value in ipairs(wanted) do if not found[value] then missing[#missing+1]=value end end
    return #missing==0,missing
end

local function registerTarget(id,root,name)
    local target=type(root)=="table" and findMethod(root,name) or nil
    targets[id]=target
    if not target then
        discoveryErrors[#discoveryErrors+1]=id.." missing"
        addEvidence("TARGET",id.." missing")
        return
    end
    local list,summary=constantsList(target.fn)
    target.constants=list
    targetEvidence[id]={origin=target.origin,constants=summary}
    addEvidence("TARGET",id.." origin="..target.origin.." constants={"..summary.."}")
end

local function readShiftState()
    local result={}
    local scripts=player:FindFirstChild("PlayerScripts")
    local shift=scripts and scripts:FindFirstChild("ShiftLockEnabled")
    result.found=shift~=nil
    result.class=shift and shift.ClassName or "none"
    if shift then pcall(function() result.value=shift.Value end) end
    local character=player.Character
    result.character=character
    result.primary=character and character.PrimaryPart or nil
    return result
end

local function releaseSnapshot()
    local result={
        pcMovementEnabled=getgenv().PCMovementEnabled,
        v500CameraOnlyLockEnabled=getgenv().PCV500CameraOnlyLockEnabled,
    }
    local character=player.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    result.character=character
    result.humanoid=humanoid
    if not humanoid then result.reason="humanoid-unavailable"; return result end
    pcall(function() result.health=humanoid.Health end)
    pcall(function() result.platformStand=humanoid.PlatformStand end)
    pcall(function() result.humanoidState=humanoid:GetState() end)
    if result.pcMovementEnabled==false then result.reason="PCMovementEnabled=false"
    elseif result.v500CameraOnlyLockEnabled==false then result.reason="PCV500CameraOnlyLockEnabled=false"
    elseif type(result.health)=="number" and result.health<=0 then result.reason="Humanoid.Health<=0"
    elseif result.platformStand==true then result.reason="Humanoid.PlatformStand=true"
    elseif result.humanoidState==Enum.HumanoidStateType.Dead then result.reason="HumanoidState.Dead"
    elseif result.humanoidState==Enum.HumanoidStateType.Physics then result.reason="HumanoidState.Physics"
    elseif result.humanoidState==Enum.HumanoidStateType.Ragdoll then result.reason="HumanoidState.Ragdoll"
    elseif result.humanoidState==Enum.HumanoidStateType.FallingDown then result.reason="HumanoidState.FallingDown"
    else result.reason="open" end
    return result
end

local function rawControllerState(controller)
    local result={controller=controller}
    if type(controller)=="table" then
        pcall(function() result.lock=rawget(controller,"inMouseLockedMode") end)
        pcall(function() result.offset=rawget(controller,"mouseLockOffset") end)
        pcall(function() result.class=cleanText(rawget(controller,"cameraMovementMode"),80) end)
    end
    return result
end

local function snapshotState()
    local active=getActiveController()
    local controllerState=rawControllerState(active)
    local shift=readShiftState()
    local release=releaseSnapshot()
    return {
        activeController=active,
        lock=controllerState.lock,
        offset=controllerState.offset,
        shiftFound=shift.found,
        shiftValue=shift.value,
        primaryPart=shift.primary,
        releaseReason=release.reason,
        humanoidState=release.humanoidState,
        health=release.health,
        platformStand=release.platformStand,
        pcMovementEnabled=release.pcMovementEnabled,
        v500CameraOnlyLockEnabled=release.v500CameraOnlyLockEnabled,
    }
end

local function callerClass()
    if type(checkcaller)~="function" then return "unknown" end
    local ok,value=pcall(checkcaller)
    return ok and (value and "executor" or "game") or "unknown"
end

local function callerStack()
    local callingScript="unavailable"
    if type(getcallingscript)=="function" then
        local ok,value=pcall(getcallingscript)
        if ok then callingScript=cleanText(value,100) end
    end
    if not debug or type(debug.info)~="function" then return callingScript..";debug.info=unavailable" end
    local frames={}
    for level=3,8 do
        local ok,source,line,name,fn=pcall(function()
            return debug.info(level,"s"),debug.info(level,"l"),debug.info(level,"n"),debug.info(level,"f")
        end)
        if ok and (source~=nil or name~=nil) then
            local fingerprint=""
            if type(fn)=="function" then
                local constants=constantsList(fn)
                local selected={}
                local wanted={SetIsMouseLocked=true,SetMouseLockOffset=true,ShiftLockEnabled=true,
                    PCMovementEnabled=true,PCV500CameraOnlyLockEnabled=true,PrimaryPart=true,ToOrientation=true}
                for _,value in ipairs(constants) do if wanted[tostring(value)] then selected[#selected+1]=tostring(value) end end
                if #selected>0 then fingerprint="{"..table.concat(selected,",").."}" end
            end
            frames[#frames+1]=string.format("L%d[%s:%s:%s%s]",level,cleanText(source,80),cleanText(line,16),cleanText(name,55),fingerprint)
        end
    end
    return "script="..callingScript.." stack="..table.concat(frames," <- ")
end

local function vectorNear(a,b)
    return typeof(a)=="Vector3" and (a-b).Magnitude<=1e-5
end

local function eventOrigin(inside,caller,sameActive)
    if inside and caller=="game" and sameActive then return "Evade-CameraModule.Update-custom-block" end
    if not inside and caller=="executor" and sameActive then return "V500-render-callback-candidate" end
    if inside then return "inside-CameraModule.Update-"..caller..(sameActive and "-active" or "-other-self") end
    return "outside-CameraModule.Update-"..caller..(sameActive and "-active" or "-other-self")
end

local function appendSequence(name)
    if currentUpdate then
        currentUpdate.sequence[#currentUpdate.sequence+1]=name
    elseif #pendingBeforeUpdate<20 then
        pendingBeforeUpdate[#pendingBeforeUpdate+1]=name
    end
end

local function recordCall(kind,phase,self,value,before,after,caller,origin,stack,release,shift,sameActive)
    eventSerial+=1
    local frame=currentUpdate and currentUpdate.id or probeFrames+1
    local relative=currentUpdate and "inside-update" or "before-next-update"
    local changed=before~=after
    if typeof(before)=="Vector3" and typeof(after)=="Vector3" then changed=not vectorNear(before,after) end
    local important=frame<=10 or frame%120==0 or changed
        or kind=="SetIsMouseLocked" or kind=="SetMouseLockOffset"
    if important then
        addTrace(string.format(
            "E%05d F%04d %s %s:%s origin=%s caller=%s activeSelf=%s arg/return=%s before=%s after=%s shift=%s release=%s state=%s health=%s platform=%s %s",
            eventSerial,frame,relative,kind,phase,origin,caller,tostring(sameActive),cleanText(value,90),
            cleanText(before,90),cleanText(after,90),cleanText(shift.value,30),release.reason,
            cleanText(release.humanoidState,65),cleanText(release.health,25),cleanText(release.platformStand,20),stack
        ))
    end
end

local function packCall(original,...)
    return table.pack(pcall(original,...))
end

local function returnPacked(results)
    if not results[1] then error(results[2],0) end
    return table.unpack(results,2,results.n)
end

local function installHook(id,factory)
    local target=targets[id]
    if not target then return false,"target-missing" end
    if type(hookfunction)~="function" then return false,"hookfunction-unavailable" end
    local original
    local replacement=factory(function(...) return original(...) end)
    local ok,old=pcall(function() return hookfunction(target.fn,replacement) end)
    if not ok or type(old)~="function" then return false,cleanText(old,140) end
    original=old
    installedHooks[#installedHooks+1]={id=id,target=target.fn,original=old}
    addEvidence("HOOK",id.." installed")
    return true,"installed"
end

local function cameraUpdateFactory(callOriginal)
    return function(self,dt,...)
        if not probeRunning or suppressTrace then return callOriginal(self,dt,...) end
        cameraModuleUpdates+=1
        probeFrames+=1
        local active=getActiveController()
        if lastActiveController and active~=lastActiveController then activeControllerChanges+=1 end
        lastActiveController=active
        local before=snapshotState()
        local ctx={id=probeFrames,sequence=pendingBeforeUpdate,shift=readShiftState(),before=before}
        pendingBeforeUpdate={}
        currentUpdate=ctx
        ctx.sequence[#ctx.sequence+1]="CameraModule.Update:enter"
        if ctx.shift.found then
            if ctx.shift.value==true then updateShiftTrue+=1 else updateShiftFalse+=1 end
        else updateShiftMissing+=1 end
        if ctx.shift.primary then updatePrimaryPartPresent+=1 end
        local capture=ctx.id<=10 or ctx.id%120==0 or before.lock~=lastState and true or false
        if capture then
            addTrace(string.format(
                "F%04d CameraModule.Update enter event=%d lock=%s offset=%s shiftFound=%s shift=%s primary=%s release=%s active=%s dt=%s",
                ctx.id,eventSerial,cleanText(before.lock,30),cleanText(before.offset,80),tostring(ctx.shift.found),
                cleanText(ctx.shift.value,30),cleanText(ctx.shift.primary,70),before.releaseReason,cleanText(active,65),cleanText(dt,35)
            ))
        end
        local results=packCall(callOriginal,self,dt,...)
        local after=snapshotState()
        ctx.after=after
        ctx.sequence[#ctx.sequence+1]="CameraModule.Update:exit"
        local signature=table.concat(ctx.sequence,">")
        sequenceCounts[signature]=(sequenceCounts[signature] or 0)+1
        if capture or before.lock~=after.lock
            or (typeof(before.offset)=="Vector3" and typeof(after.offset)=="Vector3" and not vectorNear(before.offset,after.offset)) then
            addTrace(string.format(
                "F%04d CameraModule.Update exit event=%d ok=%s lock=%s offset=%s shift=%s sequence={%s}",
                ctx.id,eventSerial,tostring(results[1]),cleanText(after.lock,30),cleanText(after.offset,80),
                cleanText(after.shiftValue,30),signature
            ))
        end
        lastState=after.lock
        currentUpdate=nil
        return returnPacked(results)
    end
end

local function setLockFactory(callOriginal)
    return function(self,value,...)
        if not probeRunning or suppressTrace then return callOriginal(self,value,...) end
        setLockCalls+=1
        local inside=currentUpdate~=nil
        if inside then setLockInside+=1 else setLockOutside+=1 end
        local active=getActiveController()
        local sameActive=self==active
        if sameActive then setLockActiveSelf+=1 else setLockOtherSelf+=1 end
        if value==true then setLockTrue+=1 elseif value==false then setLockFalse+=1 end
        local caller=callerClass()
        if caller=="executor" then setLockExecutor+=1 elseif caller=="game" then setLockGame+=1 end
        local origin=eventOrigin(inside,caller,sameActive)
        local stack=callerStack()
        local release=releaseSnapshot()
        local shift=readShiftState()
        local before=rawget(self,"inMouseLockedMode")
        appendSequence("SetIsMouseLocked("..tostring(value)..","..origin..")")
        local results=packCall(callOriginal,self,value,...)
        local after=rawget(self,"inMouseLockedMode")
        if origin=="Evade-CameraModule.Update-custom-block" then
            customLockCalls+=1
            if value==true then customLockTrue+=1 elseif value==false then customLockFalse+=1 end
            if shift.found and shift.value==value then customLockShiftMatches+=1 else customLockShiftMismatches+=1 end
        elseif origin=="V500-render-callback-candidate" then
            v500CandidateLockCalls+=1
            if value==true then v500NormalLockCalls+=1 else v500ReleaseLockCalls+=1 end
            local expected=release.reason=="open"
            if value==expected then v500StateReasonMatches+=1 else v500StateReasonMismatches+=1 end
            beforeUpdateLockCalls+=1
            local frame=probeFrames+1
            local pair=v500FramePairs[frame] or {}
            pair.lock=value
            pair.reason=release.reason
            v500FramePairs[frame]=pair
        end
        lastLockWriter={event=eventSerial+1,origin=origin,value=value,before=before,after=after,
            release=release.reason,shift=shift.value,sameActive=sameActive,caller=caller,stack=stack}
        recordCall("SetIsMouseLocked","call",self,value,before,after,caller,origin,stack,release,shift,sameActive)
        return returnPacked(results)
    end
end

local function setOffsetFactory(callOriginal)
    return function(self,value,...)
        if not probeRunning or suppressTrace then return callOriginal(self,value,...) end
        setOffsetCalls+=1
        local inside=currentUpdate~=nil
        if inside then setOffsetInside+=1 else setOffsetOutside+=1 end
        local active=getActiveController()
        local sameActive=self==active
        if sameActive then setOffsetActiveSelf+=1 else setOffsetOtherSelf+=1 end
        if vectorNear(value,NORMAL_OFFSET) then setOffsetNormal+=1
        elseif vectorNear(value,ZERO_OFFSET) then setOffsetZero+=1 else setOffsetOther+=1 end
        local caller=callerClass()
        if caller=="executor" then setOffsetExecutor+=1 elseif caller=="game" then setOffsetGame+=1 end
        local origin=eventOrigin(inside,caller,sameActive)
        local stack=callerStack()
        local release=releaseSnapshot()
        local shift=readShiftState()
        local before=rawget(self,"mouseLockOffset")
        appendSequence("SetMouseLockOffset("..cleanText(value,45)..","..origin..")")
        local results=packCall(callOriginal,self,value,...)
        local after=rawget(self,"mouseLockOffset")
        if origin=="Evade-CameraModule.Update-custom-block" then customOffsetCalls+=1
        elseif origin=="V500-render-callback-candidate" then
            v500CandidateOffsetCalls+=1
            if vectorNear(value,NORMAL_OFFSET) then v500NormalOffsetCalls+=1 end
            if vectorNear(value,ZERO_OFFSET) then v500ZeroOffsetCalls+=1 end
            beforeUpdateOffsetCalls+=1
            local frame=probeFrames+1
            local pair=v500FramePairs[frame] or {}
            pair.offset=value
            pair.reason=release.reason
            if not pair.counted and pair.lock~=nil then
                if pair.lock==true and vectorNear(value,NORMAL_OFFSET) then
                    v500NormalPairFrames+=1
                    pair.counted=true
                elseif pair.lock==false and vectorNear(value,ZERO_OFFSET) then
                    v500ReleasePairFrames+=1
                    v500ReleaseReasons[pair.reason or "unknown"]=(v500ReleaseReasons[pair.reason or "unknown"] or 0)+1
                    pair.counted=true
                end
            end
            v500FramePairs[frame]=pair
        end
        lastOffsetWriter={event=eventSerial+1,origin=origin,value=value,before=before,after=after,
            release=release.reason,shift=shift.value,sameActive=sameActive,caller=caller,stack=stack}
        recordCall("SetMouseLockOffset","call",self,value,before,after,caller,origin,stack,release,shift,sameActive)
        return returnPacked(results)
    end
end

local function getterFactory(kind)
    return function(callOriginal)
        return function(self,...)
            if not probeRunning or suppressTrace then return callOriginal(self,...) end
            local inside=currentUpdate~=nil
            local active=getActiveController()
            local sameActive=self==active
            local caller=callerClass()
            local origin=eventOrigin(inside,caller,sameActive)
            local stack=callerStack()
            local release=releaseSnapshot()
            local shift=readShiftState()
            local before=kind=="lock" and rawget(self,"inMouseLockedMode") or rawget(self,"mouseLockOffset")
            if kind=="lock" then
                getLockCalls+=1
                if inside then getLockInside+=1 else getLockOutside+=1 end
                if sameActive then getLockActiveSelf+=1 else getLockOtherSelf+=1 end
                appendSequence("GetIsMouseLocked("..origin..")")
            else
                getOffsetCalls+=1
                if inside then getOffsetInside+=1 else getOffsetOutside+=1 end
                if sameActive then getOffsetActiveSelf+=1 else getOffsetOtherSelf+=1 end
                appendSequence("GetMouseLockOffset("..origin..")")
            end
            local results=packCall(callOriginal,self,...)
            local value=results[2]
            recordCall(kind=="lock" and "GetIsMouseLocked" or "GetMouseLockOffset","return",self,value,
                before,before,caller,origin,stack,release,shift,sameActive)
            return returnPacked(results)
        end
    end
end

local function discoverTargets()
    discoveryStatus="running"
    cameras=getCameras()
    targetController=getActiveController()
    registerTarget("CameraModule.Update",cameras,"Update")
    registerTarget("Controller.SetIsMouseLocked",targetController,"SetIsMouseLocked")
    registerTarget("Controller.SetMouseLockOffset",targetController,"SetMouseLockOffset")
    registerTarget("Controller.GetIsMouseLocked",targetController,"GetIsMouseLocked")
    registerTarget("Controller.GetMouseLockOffset",targetController,"GetMouseLockOffset")
    local update=targets["CameraModule.Update"]
    local confirmed,missing=false,REQUIRED_UPDATE_CONSTANTS
    if update then confirmed,missing=hasConstants(update.constants,REQUIRED_UPDATE_CONSTANTS) end
    targetEvidence.customBlockConfirmed=confirmed
    targetEvidence.customBlockMissing=table.concat(missing or {}," | ")
    addEvidence("CUSTOM-BLOCK","confirmed="..tostring(confirmed).." missing="..targetEvidence.customBlockMissing)
    discoveryStatus=#discoveryErrors==0 and "complete" or "partial"
end

local function installTargetHooks()
    local specs={
        {"CameraModule.Update",cameraUpdateFactory},
        {"Controller.SetIsMouseLocked",setLockFactory},
        {"Controller.SetMouseLockOffset",setOffsetFactory},
        {"Controller.GetIsMouseLocked",getterFactory("lock")},
        {"Controller.GetMouseLockOffset",getterFactory("offset")},
    }
    for _,spec in ipairs(specs) do
        local ok,detail=installHook(spec[1],spec[2])
        if not ok then addEvidence("HOOK",spec[1].." rejected="..detail) end
    end
end

local function restoreHooks()
    for index=#installedHooks,1,-1 do
        local hook=installedHooks[index]
        pcall(function() hookfunction(hook.target,hook.original) end)
    end
    installedHooks={}
end

local function resetCounters()
    probeFrames=0; eventSerial=0; traceErrors=0; traceLines={}; traceDropped=0
    pendingBeforeUpdate={}; sequenceCounts={}; currentUpdate=nil
    cameraModuleUpdates=0; updateShiftTrue=0; updateShiftFalse=0; updateShiftMissing=0; updatePrimaryPartPresent=0
    setLockCalls=0; setLockInside=0; setLockOutside=0; setLockActiveSelf=0; setLockOtherSelf=0
    setLockTrue=0; setLockFalse=0; setLockExecutor=0; setLockGame=0
    setOffsetCalls=0; setOffsetInside=0; setOffsetOutside=0; setOffsetActiveSelf=0; setOffsetOtherSelf=0
    setOffsetNormal=0; setOffsetZero=0; setOffsetOther=0; setOffsetExecutor=0; setOffsetGame=0
    getLockCalls=0; getLockInside=0; getLockOutside=0; getLockActiveSelf=0; getLockOtherSelf=0
    getOffsetCalls=0; getOffsetInside=0; getOffsetOutside=0; getOffsetActiveSelf=0; getOffsetOtherSelf=0
    customLockCalls=0; customLockShiftMatches=0; customLockShiftMismatches=0; customLockTrue=0; customLockFalse=0; customOffsetCalls=0
    v500CandidateLockCalls=0; v500CandidateOffsetCalls=0; v500NormalLockCalls=0; v500ReleaseLockCalls=0
    v500NormalOffsetCalls=0; v500ZeroOffsetCalls=0; v500StateReasonMatches=0; v500StateReasonMismatches=0
    beforeUpdateLockCalls=0; beforeUpdateOffsetCalls=0; activeControllerChanges=0; lastActiveController=nil
    v500FramePairs={}; v500NormalPairFrames=0; v500ReleasePairFrames=0; v500ReleaseReasons={}
    lastLockWriter=nil; lastOffsetWriter=nil; lastState=nil
end

local function startProbe()
    if probeRunning then return false,"already-running" end
    if #installedHooks==0 then
        local ok,hookError=pcall(installTargetHooks)
        if not ok or #installedHooks==0 then
            addEvidence("HOOK","restart-installation-error="..cleanText(hookError,180))
            return false,"hook-reinstall-failed"
        end
    end
    resetCounters()
    stateAtStart=snapshotState()
    stateAtStop=nil
    probeStartedAt=os.clock()
    probeDuration=0
    probeRunning=true
    addEvidence("PROBE","V608 lock-state writer trace started")
    return true,"started"
end

local function stopProbe()
    if not probeRunning then return true,"already-stopped" end
    if probeRunning then probeDuration=os.clock()-probeStartedAt end
    probeRunning=false
    currentUpdate=nil
    stateAtStop=snapshotState()
    restoreHooks()
    addEvidence("PROBE","stopped duration="..tostring(round(probeDuration,3)))
    return true,"stopped"
end

local function sequenceSummary()
    local rows={}
    for signature,count in pairs(sequenceCounts) do rows[#rows+1]={signature=signature,count=count} end
    table.sort(rows,function(a,b) return a.count>b.count end)
    local result={}
    for index=1,math.min(#rows,8) do result[#result+1]=rows[index].count.."x{"..rows[index].signature.."}" end
    return table.concat(result," | ")
end

local function writerText(writer)
    if not writer then return "none-observed" end
    return string.format("E%s %s value=%s before=%s after=%s release=%s shift=%s activeSelf=%s caller=%s",
        tostring(writer.event),writer.origin,cleanText(writer.value,80),cleanText(writer.before,80),cleanText(writer.after,80),
        writer.release,cleanText(writer.shift,25),tostring(writer.sameActive),writer.caller)
end

local function releaseReasonSummary()
    local rows={}
    for reason,count in pairs(v500ReleaseReasons) do rows[#rows+1]={reason=reason,count=count} end
    table.sort(rows,function(a,b) return a.count>b.count end)
    local result={}
    for _,row in ipairs(rows) do result[#result+1]=row.reason..":"..row.count end
    return table.concat(result," | ")
end

local function baseSafe()
    if type(baseDiagnostics)~="function" then return {} end
    suppressTrace=true
    local ok,value=pcall(baseDiagnostics)
    suppressTrace=false
    return ok and type(value)=="table" and value or {}
end

local function resolveConclusion(current)
    local customProven=customLockCalls>0 and customLockShiftMismatches==0
    local v500Cadence=cameraModuleUpdates>0
        and v500CandidateLockCalls>=math.floor(cameraModuleUpdates*0.75)
        and v500CandidateOffsetCalls>=math.floor(cameraModuleUpdates*0.75)
        and beforeUpdateLockCalls==v500CandidateLockCalls and beforeUpdateOffsetCalls==v500CandidateOffsetCalls
    local v500Proven=v500Cadence and v500StateReasonMismatches==0
    local finalLock=current.lock
    local finalOffset=current.offset
    if v500ReleasePairFrames>0 and v500Proven then
        return "proved: V500 CAMERA_PRE_BIND release branch wrote false + zero during collection; reasons="..releaseReasonSummary(),
            true,customProven,v500Proven,v500Cadence
    end
    if finalLock==false and vectorNear(finalOffset,ZERO_OFFSET) then
        if lastLockWriter and lastOffsetWriter
            and lastLockWriter.origin=="V500-render-callback-candidate"
            and lastOffsetWriter.origin=="V500-render-callback-candidate"
            and lastLockWriter.value==false and vectorNear(lastOffsetWriter.value,ZERO_OFFSET) then
            return "proved: V500 CAMERA_PRE_BIND release branch wrote false + zero; reason="..lastLockWriter.release,
                true,customProven,v500Proven,v500Cadence
        end
        if lastLockWriter and lastLockWriter.origin=="Evade-CameraModule.Update-custom-block"
            and lastLockWriter.value==false then
            return "partial: Evade CameraModule.Update wrote lock=false from ShiftLockEnabled=false; offset zero last writer="..writerText(lastOffsetWriter),
                lastOffsetWriter~=nil,customProven,v500Proven,v500Cadence
        end
        return "unresolved in this run: final false + zero was not preceded by both observed setters on active controller",
            false,customProven,v500Proven,v500Cadence
    end
    if finalLock==true and vectorNear(finalOffset,NORMAL_OFFSET) then
        return "V607 false/zero not reproduced: current run proves normal V500 true + (2,0.5,0) writer path",
            v500Proven,customProven,v500Proven,v500Cadence
    end
    return "mixed final state; use lastLockWriter/lastOffsetWriter and trace to identify the last active-controller writers",
        false,customProven,v500Proven,v500Cadence
end

local function stateValue(state,key)
    return state and state[key] or nil
end

getgenv().PCV608Diagnostics=function()
    local base=baseSafe()
    local current=(not probeRunning and stateAtStop) or snapshotState()
    local conclusion,explained,customProven,v500Proven,v500Cadence=resolveConclusion(current)
    local updateDetail=targetEvidence["CameraModule.Update"] or {}
    return {
        version="V608-LockStateWriterTrace",
        bridgeMode=getgenv().PCInputBridgeMode,
        probePurpose="explain-V606-to-V607-lock-and-offset-state-discrepancy",
        probeRunning=probeRunning,
        probeFrames=probeFrames,
        probeDuration=round(probeRunning and (os.clock()-probeStartedAt) or probeDuration,3),
        eventSerial=eventSerial,
        traceErrors=traceErrors,
        discoveryStatus=discoveryStatus,
        discoveryErrors=table.concat(discoveryErrors," | "),
        cameraModuleUpdateOrigin=updateDetail.origin,
        cameraModuleUpdateConstants=updateDetail.constants,
        customUpdateBlockConfirmed=targetEvidence.customBlockConfirmed,
        customUpdateBlockMissing=targetEvidence.customBlockMissing,
        customUpdateContainsShiftLockEnabled=targetEvidence.customBlockConfirmed,
        customUpdateContainsCharacterPrimaryPartToOrientationCFrameMathAbs=targetEvidence.customBlockConfirmed,
        cameraModuleUpdates=cameraModuleUpdates,
        sequenceSummary=sequenceSummary(),
        updateShiftTrue=updateShiftTrue,
        updateShiftFalse=updateShiftFalse,
        updateShiftMissing=updateShiftMissing,
        updatePrimaryPartPresent=updatePrimaryPartPresent,
        setIsMouseLockedCalls=setLockCalls,
        setIsMouseLockedInsideUpdate=setLockInside,
        setIsMouseLockedOutsideUpdate=setLockOutside,
        setIsMouseLockedActiveSelf=setLockActiveSelf,
        setIsMouseLockedOtherSelf=setLockOtherSelf,
        setIsMouseLockedTrue=setLockTrue,
        setIsMouseLockedFalse=setLockFalse,
        setIsMouseLockedExecutor=setLockExecutor,
        setIsMouseLockedGame=setLockGame,
        setMouseLockOffsetCalls=setOffsetCalls,
        setMouseLockOffsetInsideUpdate=setOffsetInside,
        setMouseLockOffsetOutsideUpdate=setOffsetOutside,
        setMouseLockOffsetActiveSelf=setOffsetActiveSelf,
        setMouseLockOffsetOtherSelf=setOffsetOtherSelf,
        setMouseLockOffsetNormal=setOffsetNormal,
        setMouseLockOffsetZero=setOffsetZero,
        setMouseLockOffsetOther=setOffsetOther,
        setMouseLockOffsetExecutor=setOffsetExecutor,
        setMouseLockOffsetGame=setOffsetGame,
        getIsMouseLockedCalls=getLockCalls,
        getIsMouseLockedInsideUpdate=getLockInside,
        getIsMouseLockedOutsideUpdate=getLockOutside,
        getIsMouseLockedActiveSelf=getLockActiveSelf,
        getIsMouseLockedOtherSelf=getLockOtherSelf,
        getMouseLockOffsetCalls=getOffsetCalls,
        getMouseLockOffsetInsideUpdate=getOffsetInside,
        getMouseLockOffsetOutsideUpdate=getOffsetOutside,
        getMouseLockOffsetActiveSelf=getOffsetActiveSelf,
        getMouseLockOffsetOtherSelf=getOffsetOtherSelf,
        customCameraUpdateLockCalls=customLockCalls,
        customCameraUpdateShiftMatches=customLockShiftMatches,
        customCameraUpdateShiftMismatches=customLockShiftMismatches,
        customCameraUpdateLockTrue=customLockTrue,
        customCameraUpdateLockFalse=customLockFalse,
        customCameraUpdateOffsetCalls=customOffsetCalls,
        customCameraUpdateWriterProven=customProven,
        v500CandidateLockCalls=v500CandidateLockCalls,
        v500CandidateOffsetCalls=v500CandidateOffsetCalls,
        v500NormalLockCalls=v500NormalLockCalls,
        v500ReleaseLockCalls=v500ReleaseLockCalls,
        v500NormalOffsetCalls=v500NormalOffsetCalls,
        v500ZeroOffsetCalls=v500ZeroOffsetCalls,
        v500NormalPairFrames=v500NormalPairFrames,
        v500ReleasePairFrames=v500ReleasePairFrames,
        v500ReleaseReasons=releaseReasonSummary(),
        v500StateReasonMatches=v500StateReasonMatches,
        v500StateReasonMismatches=v500StateReasonMismatches,
        v500CadenceMatchesCameraUpdate=v500Cadence,
        v500RuntimeWriterProven=v500Proven,
        activeControllerChanges=activeControllerChanges,
        lastLockWriter=writerText(lastLockWriter),
        lastOffsetWriter=writerText(lastOffsetWriter),
        lockAtStart=stateValue(stateAtStart,"lock"),
        offsetAtStart=stateValue(stateAtStart,"offset"),
        shiftLockAtStart=stateValue(stateAtStart,"shiftValue"),
        releaseReasonAtStart=stateValue(stateAtStart,"releaseReason"),
        lockAtStop=stateValue(stateAtStop,"lock"),
        offsetAtStop=stateValue(stateAtStop,"offset"),
        shiftLockAtStop=stateValue(stateAtStop,"shiftValue"),
        releaseReasonAtStop=stateValue(stateAtStop,"releaseReason"),
        currentLock=current.lock,
        currentOffset=current.offset,
        currentShiftLockFound=current.shiftFound,
        currentShiftLockValue=current.shiftValue,
        currentReleaseReason=current.releaseReason,
        currentHumanoidState=current.humanoidState,
        currentHealth=current.health,
        currentPlatformStand=current.platformStand,
        pcMovementEnabled=current.pcMovementEnabled,
        v500CameraOnlyLockEnabled=current.v500CameraOnlyLockEnabled,
        discrepancyExplained=explained,
        discrepancyConclusion=conclusion,
        v500StaticWriterConfirmed=true,
        v500StaticNormalWrite="Camera-2: SetIsMouseLocked(true) + SetMouseLockOffset(2,0.5,0)",
        v500StaticReleaseWrite="Camera-2: SetIsMouseLocked(false) + SetMouseLockOffset(0,0,0)",
        v20WriterActive=false,
        v20WriterInactiveReason="V500 unbinds __PCMovementV20NativeHardCenter",
        legacyPersistentWriterActive=false,
        legacyPersistentWriterInactiveReason="V500 unbinds __PCMovementPersistentLock",
        v606WritesLockState=false,
        v607WritesLockState=false,
        relayEnabled=base.relayEnabled,
        relayValidationReady=base.relayValidationReady,
        ownershipGateProven=base.ownershipGateProven,
        touchRoleConflicts=base.touchRoleConflicts,
        joystickMouseCrossovers=base.joystickMouseCrossovers,
        relayErrors=base.relayErrors,
        callbackErrors=base.callbackErrors,
        validationReady=probeFrames>=30 and traceErrors==0 and customProven and v500Proven,
        traceLines=#traceLines,
        traceDropped=traceDropped,
        evidenceLines=#evidence,
        evidenceDropped=evidenceDropped,
        observationalOnly=true,
        callsSetIsMouseLocked=false,
        callsSetMouseLockOffset=false,
        callsGetIsMouseLocked=false,
        callsGetMouseLockOffset=false,
        callsUpdateMouseBehavior=false,
        forcesPreferredInput=false,
        forcesMouseBehavior=false,
        forcesRotationType=false,
        writesCameraCFrame=false,
        writesRootPartCFrame=false,
        forcesAutoRotate=false,
        changesSensitivityGainPhysics=false,
        usesSyntheticUserInputObject=false,
        usesFireSignal=false,
        addsVirtualInput=false,
        preservesV604Ownership=true,
        fallbackV500Preserved=true,
    }
end

local REPORT_KEYS={
    "version","bridgeMode","probePurpose","probeRunning","probeFrames","probeDuration","eventSerial","traceErrors",
    "discoveryStatus","discoveryErrors","cameraModuleUpdateOrigin","cameraModuleUpdateConstants",
    "customUpdateBlockConfirmed","customUpdateBlockMissing","customUpdateContainsShiftLockEnabled",
    "customUpdateContainsCharacterPrimaryPartToOrientationCFrameMathAbs","cameraModuleUpdates","sequenceSummary",
    "updateShiftTrue","updateShiftFalse","updateShiftMissing","updatePrimaryPartPresent",
    "setIsMouseLockedCalls","setIsMouseLockedInsideUpdate","setIsMouseLockedOutsideUpdate",
    "setIsMouseLockedActiveSelf","setIsMouseLockedOtherSelf","setIsMouseLockedTrue","setIsMouseLockedFalse",
    "setIsMouseLockedExecutor","setIsMouseLockedGame","setMouseLockOffsetCalls","setMouseLockOffsetInsideUpdate",
    "setMouseLockOffsetOutsideUpdate","setMouseLockOffsetActiveSelf","setMouseLockOffsetOtherSelf",
    "setMouseLockOffsetNormal","setMouseLockOffsetZero","setMouseLockOffsetOther","setMouseLockOffsetExecutor",
    "setMouseLockOffsetGame","getIsMouseLockedCalls","getIsMouseLockedInsideUpdate","getIsMouseLockedOutsideUpdate",
    "getIsMouseLockedActiveSelf","getIsMouseLockedOtherSelf","getMouseLockOffsetCalls","getMouseLockOffsetInsideUpdate",
    "getMouseLockOffsetOutsideUpdate","getMouseLockOffsetActiveSelf","getMouseLockOffsetOtherSelf",
    "customCameraUpdateLockCalls","customCameraUpdateShiftMatches","customCameraUpdateShiftMismatches",
    "customCameraUpdateLockTrue","customCameraUpdateLockFalse",
    "customCameraUpdateOffsetCalls","customCameraUpdateWriterProven","v500CandidateLockCalls",
    "v500CandidateOffsetCalls","v500NormalLockCalls","v500ReleaseLockCalls","v500NormalOffsetCalls",
    "v500ZeroOffsetCalls","v500NormalPairFrames","v500ReleasePairFrames","v500ReleaseReasons",
    "v500StateReasonMatches","v500StateReasonMismatches","v500CadenceMatchesCameraUpdate",
    "v500RuntimeWriterProven","activeControllerChanges","lastLockWriter","lastOffsetWriter",
    "lockAtStart","offsetAtStart","shiftLockAtStart","releaseReasonAtStart","lockAtStop","offsetAtStop",
    "shiftLockAtStop","releaseReasonAtStop","currentLock","currentOffset","currentShiftLockFound",
    "currentShiftLockValue","currentReleaseReason","currentHumanoidState","currentHealth","currentPlatformStand",
    "pcMovementEnabled","v500CameraOnlyLockEnabled","discrepancyExplained","discrepancyConclusion",
    "v500StaticWriterConfirmed","v500StaticNormalWrite","v500StaticReleaseWrite","v20WriterActive",
    "v20WriterInactiveReason","legacyPersistentWriterActive","legacyPersistentWriterInactiveReason",
    "v606WritesLockState","v607WritesLockState","relayEnabled","relayValidationReady","ownershipGateProven",
    "touchRoleConflicts","joystickMouseCrossovers","relayErrors","callbackErrors","validationReady",
    "traceLines","traceDropped","evidenceLines","evidenceDropped","observationalOnly","callsSetIsMouseLocked",
    "callsSetMouseLockOffset","callsGetIsMouseLocked","callsGetMouseLockOffset","callsUpdateMouseBehavior",
    "forcesPreferredInput","forcesMouseBehavior","forcesRotationType","writesCameraCFrame","writesRootPartCFrame",
    "forcesAutoRotate","changesSensitivityGainPhysics","usesSyntheticUserInputObject","usesFireSignal",
    "addsVirtualInput","preservesV604Ownership","fallbackV500Preserved",
}

getgenv().PCV608Report=function(includeEvidence)
    local diagnostics=getgenv().PCV608Diagnostics()
    local lines={"=== PC MOVEMENT V608 REPORT ==="}
    for _,key in ipairs(REPORT_KEYS) do lines[#lines+1]=key.." = "..tostring(diagnostics[key]) end
    if includeEvidence~=false then
        lines[#lines+1]=""
        lines[#lines+1]="=== PC MOVEMENT V608 ORDERED LOCK TRACE ==="
        for _,line in ipairs(traceLines) do lines[#lines+1]=line end
        lines[#lines+1]=""
        lines[#lines+1]="=== PC MOVEMENT V608 TARGET EVIDENCE ==="
        for _,line in ipairs(evidence) do lines[#lines+1]=line end
        if type(baseReport)=="function" then
            local ok,text=pcall(baseReport,false)
            if ok then lines[#lines+1]=""; lines[#lines+1]=text end
        end
    end
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
    button.Size=UDim2.new(1,0,0,35)
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
    local base=baseSafe()
    relayButton.Text=base.relayEnabled and "RELAY V604: LIGADO" or "RELAY V604: DESLIGADO"
    relayButton.BackgroundColor3=base.relayEnabled and Color3.fromRGB(124,58,237) or Color3.fromRGB(71,85,105)
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
    panel.Size=UDim2.fromOffset(314,430)
    panel.Position=UDim2.new(1,-326,0.5,-215)
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
    stroke.Color=Color3.fromRGB(45,212,191)
    stroke.Thickness=1.5
    stroke.Parent=panel

    local title=Instance.new("TextLabel")
    title.Size=UDim2.new(1,-48,0,34)
    title.Position=UDim2.fromOffset(13,7)
    title.BackgroundTransparency=1
    title.Text="V608 • LOCK WRITER TRACE"
    title.TextColor3=Color3.fromRGB(94,234,212)
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
    instructions.Size=UDim2.new(1,0,0,82)
    instructions.BackgroundColor3=Color3.fromRGB(22,28,45)
    instructions.BorderSizePixel=0
    instructions.Text="1) Prove joystick+câmera e ligue o relay\n2) INICIAR; jogue normalmente 15s\n3) Se puder, inclua queda/downed/respawn\n4) PARAR e COPIAR antes de sair"
    instructions.TextColor3=Color3.fromRGB(226,232,240)
    instructions.TextSize=11
    instructions.TextWrapped=true
    instructions.TextXAlignment=Enum.TextXAlignment.Left
    instructions.Font=Enum.Font.Gotham
    instructions.Parent=body
    local instructionCorner=Instance.new("UICorner")
    instructionCorner.CornerRadius=UDim.new(0,8)
    instructionCorner.Parent=instructions

    local start=makeButton(body,"INICIAR",Color3.fromRGB(34,197,94),1)
    relayButton=makeButton(body,"RELAY V604: DESLIGADO",Color3.fromRGB(71,85,105),2)
    local stop=makeButton(body,"PARAR",Color3.fromRGB(245,158,11),3)
    local emergency=makeButton(body,"EMERGÊNCIA • RELAY OFF / V500",Color3.fromRGB(190,24,93),4)
    local copy=makeButton(body,"COPIAR REPORT COMPLETO",Color3.fromRGB(2,132,199),5)
    statusLabel=Instance.new("TextLabel")
    statusLabel.LayoutOrder=6
    statusLabel.Size=UDim2.new(1,0,0,28)
    statusLabel.BackgroundTransparency=1
    statusLabel.Text="Pronto. Observacional; nenhum estado será forçado."
    statusLabel.TextColor3=Color3.fromRGB(148,163,184)
    statusLabel.TextSize=10
    statusLabel.TextWrapped=true
    statusLabel.Font=Enum.Font.Gotham
    statusLabel.Parent=body

    uiConnections[#uiConnections+1]=start.Activated:Connect(function()
        local ok=startProbe()
        setStatus(ok and "Trace ativo. Jogue; inclua mudança de estado se ocorrer." or "Trace já está ativo.",
            ok and Color3.fromRGB(74,222,128) or Color3.fromRGB(250,204,21))
    end)
    uiConnections[#uiConnections+1]=relayButton.Activated:Connect(function()
        local base=baseSafe()
        local want=not base.relayEnabled
        if type(baseSetRelay)~="function" then
            setStatus("Relay indisponível; V500 permanece ativo.",Color3.fromRGB(251,113,133)); return
        end
        local ok,result=pcall(baseSetRelay,want)
        if not ok or result==false then
            setStatus("Relay recusado: prove joystick+câmera juntos.",Color3.fromRGB(250,204,21))
        else
            setStatus(want and "Relay V604 ligado." or "Relay OFF; V500 ativo.",Color3.fromRGB(196,181,253))
        end
        refreshRelayButton()
    end)
    uiConnections[#uiConnections+1]=stop.Activated:Connect(function()
        stopProbe()
        setStatus("Trace parado e congelado. Agora copie.",Color3.fromRGB(250,204,21))
    end)
    uiConnections[#uiConnections+1]=emergency.Activated:Connect(function()
        stopProbe()
        if type(baseSetRelay)=="function" then pcall(baseSetRelay,false) end
        refreshRelayButton()
        setStatus("Emergência: relay OFF; V500 preservado.",Color3.fromRGB(251,113,133))
    end)
    uiConnections[#uiConnections+1]=copy.Activated:Connect(function()
        stopProbe()
        local ok=copyToClipboard(getgenv().PCV608Report(true))
        setStatus(ok and "REPORT COPIADO. Agora pode sair e colar." or "Clipboard indisponível no Delta.",
            ok and Color3.fromRGB(74,222,128) or Color3.fromRGB(251,113,133))
    end)
    local expanded=true
    uiConnections[#uiConnections+1]=collapse.Activated:Connect(function()
        expanded=not expanded
        body.Visible=expanded
        panel.Size=expanded and UDim2.fromOffset(314,430) or UDim2.fromOffset(314,45)
        collapse.Text=expanded and "–" or "+"
    end)
    refreshRelayButton()
end

local discoverOk,discoverError=pcall(discoverTargets)
if not discoverOk then discoveryStatus="error:"..cleanText(discoverError,180); addEvidence("DISCOVERY",discoveryStatus) end
local hookOk,hookError=pcall(installTargetHooks)
if not hookOk then addEvidence("HOOK","installation-error="..cleanText(hookError,180)) end
local uiOk,uiError=pcall(createPanel)
if not uiOk then addEvidence("UI","creation-error="..cleanText(uiError,180)) end

getgenv().PCV608Start=startProbe
getgenv().PCV608Stop=function() stopProbe(); return getgenv().PCV608Report(false) end
getgenv().PCV608EmergencyV500=function()
    stopProbe()
    if type(baseSetRelay)=="function" then pcall(baseSetRelay,false) end
    refreshRelayButton()
    return true,"relay-disabled-v500-active"
end

getgenv().__PCMobileAimCleanup=function()
    probeRunning=false
    currentUpdate=nil
    for _,connection in ipairs(uiConnections) do pcall(function() connection:Disconnect() end) end
    uiConnections={}
    if screenGui then pcall(function() screenGui:Destroy() end) end
    screenGui=nil
    restoreHooks()
    getgenv().PCV608Start=nil
    getgenv().PCV608Stop=nil
    getgenv().PCV608EmergencyV500=nil
    getgenv().PCV608Diagnostics=nil
    getgenv().PCV608Report=nil
    if baseCleanup then pcall(baseCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

addEvidence("READY","V608 targeted lock-state writer trace ready; observational only")
warn("[V608] lock-state writer trace ready | observational only | use mobile panel")
