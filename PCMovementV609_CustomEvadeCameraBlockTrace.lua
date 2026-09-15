local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")

local player=Players.LocalPlayer
local UI_NAME="PCMovementV609Panel"

--[[
    V609 / CUSTOM EVADE CAMERA BLOCK TRACE

    Accepted and not re-scanned:
      * V604 ownership/relay and V500 fail-open are proved.
      * V606 downstream BaseCamera composition is proved.
      * V607 MouseLockController boundary is closed.
      * V608 lock/offset writers and their ordering are closed.

    The only target is the custom tail inside CameraModule.Update identified by:
      PlayerScripts.ShiftLockEnabled, Character, PrimaryPart, ToOrientation,
      CFrame, math.abs and SetIsMouseLocked.

    V609 observes that exact Update, its active controller Update boundary, the
    custom SetIsMouseLocked call and the directly reachable `accelerate` upvalue.
    It never writes a CFrame, lock setting, input setting, gain or physics value.
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

getgenv().PCMovementVersion="V609-CustomEvadeCameraBlockTrace"
getgenv().PCInputBridgeMode="v609-observational-custom-evade-block-over-v604"

local cameras
local cameraModuleScript
local activeController
local targets={}
local targetEvidence={}
local installedHooks={}
local discoveryStatus="not-started"
local discoveryErrors={}
local decompileStatus="not-attempted"
local decompileSnippet=""
local decompileMarkerCount=0
local decompileSelectedScore=0
local updateInputTokens={}
local focusedBlockInputTokens={}
local staticBlockConfirmed=false
local staticBlockMissing={}
local staticPrimaryPartCFrameWriteHint=false
local staticCameraCFrameWriteHint=false
local accelerateFunction=nil
local accelerateEvidence="not-found"

local probeRunning=false
local suppressTrace=false
local probeStartedAt=0
local probeDuration=0
local probeFrames=0
local traceErrors=0
local traceLines={}
local traceDropped=0
local evidence={}
local evidenceDropped=0
local currentContext=nil
local stateAtStart=nil
local stateAtStop=nil

local cameraModuleUpdates=0
local controllerUpdates=0
local controllerUpdateErrors=0
local customSetterCalls=0
local customSetterActiveSelf=0
local customSetterOtherSelf=0
local customSetterShiftMatches=0
local customSetterShiftMismatches=0
local customSetterTrue=0
local customSetterFalse=0
local accelerateCalls=0
local accelerateInsideBlock=0
local accelerateOutsideBlock=0
local accelerateErrors=0
local shiftTrueFrames=0
local shiftFalseFrames=0
local shiftMissingFrames=0
local preferredTouchFrames=0
local preferredComputerFrames=0
local otherPreferredFrames=0

local rootChangedEntryToControllerExit=0
local rootChangedControllerExitToSetterEntry=0
local rootChangedSetterEntryToSetterExit=0
local rootChangedSetterExitToModuleExit=0
local rootChangedControllerExitToModuleExit=0
local rootPositionChangedInCustomTail=0
local rootRotationChangedInCustomTail=0
local rootYawChangedInCustomTail=0
local rootChangeShiftTrue=0
local rootChangeShiftFalse=0
local rootChangePreferredTouch=0
local rootChangePreferredComputer=0
local rootChangePreferredOther=0
local rootMatchesCameraYawAfter=0
local rootCameraYawSamples=0
local rootTailPositionDeltaMax=0
local rootTailRotationDeltaMax=0
local rootTailYawDeltaMax=0
local cameraChangedControllerExitToSetterEntry=0
local cameraChangedSetterExitToModuleExit=0
local cameraChangedControllerExitToModuleExit=0
local controllerReturnMatchesCameraAtSetter=0
local controllerReturnCameraSamples=0

local updateUpvalueSnapshots=0
local updateUpvalueChangeFrames=0
local updateUpvalueChangeCounts={}
local updateUpvalueLastBefore=""
local updateUpvalueLastAfter=""
local persistentVectorSamples=0
local persistentVectorChanges=0
local persistentVectorMatchesRoot=0
local persistentVectorMatchesCamera=0
local persistentVectorLast=nil
local localStackCaptures=0
local localStackUnavailable=0
local lastCustomLocals=""
local localSchemas={}

local lastSequence=""
local sequenceCounts={}
local lastAccelerateArgs=""
local lastAccelerateReturns=""
local lastStageSnapshot=""

local screenGui=nil
local statusLabel=nil
local relayButton=nil
local experimentButton=nil
local uiConnections={}

local REQUIRED_CONSTANTS={
    "PlayerScripts","ShiftLockEnabled","Character","PrimaryPart","ToOrientation","CFrame","math","abs",
}
local TOUCH_PC_TOKENS={
    "PreferredInput","UserInputService","LastInputType","Touch","KeyboardAndMouse","MouseMovement",
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
    if #evidence>=220 then evidenceDropped+=1; return end
    evidence[#evidence+1]=string.format("[%03d][%s] %s",#evidence+1,section,cleanText(message,1800))
end

local function addTrace(message,force)
    if #traceLines>=180 and not force then traceDropped+=1; return end
    if #traceLines>=220 then traceDropped+=1; return end
    traceLines[#traceLines+1]=cleanText(message,1600)
end

local function packCall(original,...)
    return table.pack(pcall(original,...))
end

local function returnPacked(results)
    if not results[1] then error(results[2],0) end
    return table.unpack(results,2,results.n)
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
        if type(value)=="function" then return {fn=value,owner=tbl,origin=origin.."."..name,depth=depth} end
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
        if (type(value)=="string" or type(value)=="number" or type(value)=="boolean") and #result<120 then
            result[#result+1]=cleanText(value,90)
        end
    end
    return result,table.concat(result," | ")
end

local function upvaluesTable(fn)
    local getter=(debug and debug.getupvalues) or getupvalues
    if type(getter)~="function" then return nil,"unavailable" end
    local ok,values=pcall(getter,fn)
    if not ok or type(values)~="table" then return nil,"error:"..cleanText(values,100) end
    return values,"ok"
end

local function valueSummary(value,depth)
    depth=depth or 0
    local kind=typeof(value)
    if kind=="CFrame" then
        local x,y,z=value:ToOrientation()
        return string.format("CFrame[p=%s rpy=(%.3f,%.3f,%.3f)]",cleanText(value.Position,75),math.deg(x),math.deg(y),math.deg(z))
    end
    if kind=="Vector3" or kind=="Vector2" then return kind.."["..cleanText(value,100).."]" end
    if kind=="Instance" then
        local full=cleanText(value,120)
        pcall(function() full=value:GetFullName() end)
        return "Instance["..full.."]"
    end
    if kind=="table" then
        local fields={}
        if depth<1 then
            pcall(function()
                for key,item in pairs(value) do
                    if #fields<18 then fields[#fields+1]=cleanText(key,45).."="..valueSummary(item,depth+1) end
                end
            end)
            table.sort(fields)
        end
        return "table{"..table.concat(fields,";").."}"
    end
    return kind.."["..cleanText(value,100).."]"
end

local function upvaluesSummary(values)
    if type(values)~="table" then return "unavailable" end
    local result={}
    for index,value in pairs(values) do
        if #result<24 then result[#result+1]=tostring(index).."="..valueSummary(value) end
    end
    return table.concat(result," | ")
end

local function findTokens(list,wanted)
    local present={}
    for _,value in ipairs(list) do present[tostring(value)]=true end
    local found,missing={},{}
    for _,token in ipairs(wanted) do
        if present[token] then found[#found+1]=token else missing[#missing+1]=token end
    end
    return found,missing
end

local function registerTarget(id,root,name)
    local target=type(root)=="table" and findMethod(root,name) or nil
    targets[id]=target
    if not target then
        discoveryErrors[#discoveryErrors+1]=id.." missing"
        addEvidence("TARGET",id.." missing")
        return
    end
    local constants,summary=constantsList(target.fn)
    local upvalues,status=upvaluesTable(target.fn)
    target.constants=constants
    target.upvalues=upvalues
    targetEvidence[id]={origin=target.origin,constants=summary,upvalues=upvaluesSummary(upvalues),upvalueStatus=status}
    addEvidence("TARGET",id.." origin="..target.origin.." constants={"..summary.."} upvalues={"..targetEvidence[id].upvalues.."}")
end

local function extractFocusedDecompile()
    if not cameraModuleScript then decompileStatus="CameraModule-script-missing"; return end
    local env=getgenv()
    local decompiler=env.decompile or decompile
    if type(decompiler)~="function" then decompileStatus="decompile-unavailable"; return end
    local ok,source=pcall(decompiler,cameraModuleScript)
    if not ok or type(source)~="string" then decompileStatus="decompile-error:"..cleanText(source,140); return end
    local lower=string.lower(source)
    local marker=nil
    local cursor=1
    while true do
        local found=string.find(lower,"shiftlockenabled",cursor,true)
        if not found then break end
        decompileMarkerCount+=1
        local candidateFirst=math.max(1,found-1800)
        local candidateLast=math.min(#source,found+2600)
        local candidate=string.sub(lower,candidateFirst,candidateLast)
        local score=0
        for _,token in ipairs(REQUIRED_CONSTANTS) do
            if string.find(candidate,string.lower(token),1,true) then score+=1 end
        end
        if string.find(candidate,"setismouselocked",1,true) then score+=8 end
        if string.find(candidate,"primarypart",1,true) and string.find(candidate,"toorientation",1,true) then score+=6 end
        if score>decompileSelectedScore then decompileSelectedScore=score; marker=found end
        cursor=found+1
    end
    if not marker then decompileStatus="source-returned-marker-missing"; return end
    local first=math.max(1,marker-1800)
    local last=math.min(#source,marker+2600)
    decompileSnippet=string.sub(source,first,last)
    decompileStatus="focused-best-window-captured"
    local snippetLower=string.lower(decompileSnippet)
    staticPrimaryPartCFrameWriteHint=string.find(snippetLower,"primarypart%s*%.%s*cframe%s*=")~=nil
    staticCameraCFrameWriteHint=string.find(snippetLower,"currentcamera%s*%.%s*cframe%s*=")~=nil
    for _,token in ipairs(TOUCH_PC_TOKENS) do
        if string.find(snippetLower,string.lower(token),1,true) then focusedBlockInputTokens[#focusedBlockInputTokens+1]=token end
    end
    addEvidence("DECOMPILE",string.format("focused ShiftLockEnabled window captured length=%d markers=%d score=%d",
        #decompileSnippet,decompileMarkerCount,decompileSelectedScore))
end

local function discoverFocusedBlock()
    discoveryStatus="running"
    locateObjects()
    registerTarget("CameraModule.Update",cameras,"Update")
    registerTarget("Controller.Update",activeController,"Update")
    registerTarget("Controller.SetIsMouseLocked",activeController,"SetIsMouseLocked")
    local update=targets["CameraModule.Update"]
    if update then
        local _,missing=findTokens(update.constants,REQUIRED_CONSTANTS)
        staticBlockMissing=missing
        staticBlockConfirmed=#missing==0
        updateInputTokens=select(1,findTokens(update.constants,TOUCH_PC_TOKENS))
        local values=update.upvalues
        if type(values)=="table" then
            for index,value in pairs(values) do
                if type(value)=="table" and type(rawget(value,"accelerate"))=="function" then
                    accelerateFunction=rawget(value,"accelerate")
                    local _,summary=constantsList(accelerateFunction)
                    local accelUpvalues,status=upvaluesTable(accelerateFunction)
                    accelerateEvidence=string.format("updateUpvalue=%s constants={%s} upvalues={%s} status=%s",
                        tostring(index),summary,upvaluesSummary(accelUpvalues),status)
                    addEvidence("ACCELERATE",accelerateEvidence)
                    break
                end
            end
        end
    end
    addEvidence("CUSTOM-BLOCK","confirmed="..tostring(staticBlockConfirmed).." missing="..table.concat(staticBlockMissing," | "))
    extractFocusedDecompile()
    discoveryStatus=#discoveryErrors==0 and "complete" or "partial"
end

local function readShift()
    local scripts=player:FindFirstChild("PlayerScripts")
    local shift=scripts and scripts:FindFirstChild("ShiftLockEnabled")
    local value
    if shift then pcall(function() value=shift.Value end) end
    return shift,value
end

local function cframeSnapshot()
    local character=player.Character
    local primary=character and character.PrimaryPart
    local camera=workspace.CurrentCamera
    local shift,shiftValue=readShift()
    local controller=getActiveController()
    local rootCFrame=nil
    if primary then pcall(function() rootCFrame=primary.CFrame end) end
    return {
        character=character,
        primary=primary,
        rootCFrame=rootCFrame,
        camera=camera,
        cameraCFrame=camera and camera.CFrame or nil,
        cameraFocus=camera and camera.Focus or nil,
        shift=shift,
        shiftValue=shiftValue,
        controller=controller,
        controllerLock=type(controller)=="table" and rawget(controller,"inMouseLockedMode") or nil,
        controllerOffset=type(controller)=="table" and rawget(controller,"mouseLockOffset") or nil,
        preferredInput=UserInputService.PreferredInput,
        lastInputType=UserInputService:GetLastInputType(),
    }
end

local function yaw(cf)
    if typeof(cf)~="CFrame" then return nil end
    local _,y=cf:ToOrientation()
    return math.deg(y)
end

local function angleDelta(a,b)
    if type(a)~="number" or type(b)~="number" then return nil end
    return (a-b+180)%360-180
end

local function cframeDelta(a,b)
    if typeof(a)~="CFrame" or typeof(b)~="CFrame" then return nil,nil,nil end
    local position=(a.Position-b.Position).Magnitude
    local relative=a:ToObjectSpace(b)
    local rx,ry,rz=relative:ToOrientation()
    local rotation=math.deg(math.sqrt(rx*rx+ry*ry+rz*rz))
    local yawDelta=math.abs(angleDelta(yaw(b),yaw(a)) or 0)
    return position,rotation,yawDelta
end

local function changedCFrame(a,b,positionThreshold,rotationThreshold)
    local p,r=cframeDelta(a,b)
    if p==nil then return false end
    return p>(positionThreshold or 1e-5) or r>(rotationThreshold or 1e-4)
end

local function snapshotText(stage,s)
    if not s then return stage.."=nil" end
    return string.format("%s{shift=%s preferred=%s lastInput=%s root=%s camera=%s lock=%s offset=%s}",stage,
        cleanText(s.shiftValue,20),cleanText(s.preferredInput,65),cleanText(s.lastInputType,65),
        valueSummary(s.rootCFrame),valueSummary(s.cameraCFrame),cleanText(s.controllerLock,25),cleanText(s.controllerOffset,65))
end

local function snapshotUpdateUpvalues()
    local target=targets["CameraModule.Update"]
    if not target then return nil,"target-missing" end
    local values,status=upvaluesTable(target.original or target.fn)
    if type(values)~="table" then return nil,status end
    local frozen={}
    for index,value in pairs(values) do
        local record={kind=typeof(value),value=value}
        if type(value)=="table" then
            record.fields={}
            pcall(function()
                local count=0
                for key,item in pairs(value) do
                    if count>=48 then break end
                    record.fields[key]=item
                    count+=1
                end
            end)
        end
        frozen[index]=record
    end
    return frozen,status
end

local function frozenUpvaluesSummary(values)
    if type(values)~="table" then return "unavailable" end
    local result={}
    for index,record in pairs(values) do
        if #result<24 then
            local text=valueSummary(record.value)
            if type(record.fields)=="table" then
                local fields={}
                for key,item in pairs(record.fields) do
                    if #fields<18 then fields[#fields+1]=cleanText(key,40).."="..valueSummary(item,1) end
                end
                table.sort(fields)
                text=text.." snapshotFields={"..table.concat(fields,";").."}"
            end
            result[#result+1]=tostring(index).."="..text
        end
    end
    return table.concat(result," | ")
end

local function valuesDiffer(beforeValue,afterValue)
    if typeof(beforeValue)~=typeof(afterValue) then return true end
    if typeof(beforeValue)=="Vector3" then return (beforeValue-afterValue).Magnitude>1e-6 end
    if typeof(beforeValue)=="CFrame" then return changedCFrame(beforeValue,afterValue,1e-6,1e-5) end
    return beforeValue~=afterValue
end

local function compareUpvalues(before,after,ctx)
    if type(before)~="table" or type(after)~="table" then return end
    updateUpvalueSnapshots+=1
    local changed=false
    for index,beforeRecord in pairs(before) do
        local afterRecord=after[index]
        local beforeValue=beforeRecord and beforeRecord.value
        local afterValue=afterRecord and afterRecord.value
        local different=afterRecord==nil or valuesDiffer(beforeValue,afterValue)
        if not different and type(beforeRecord.fields)=="table" and type(afterRecord.fields)=="table" then
            for key,beforeField in pairs(beforeRecord.fields) do
                if valuesDiffer(beforeField,afterRecord.fields[key]) then different=true; break end
            end
            if not different then
                for key in pairs(afterRecord.fields) do
                    if beforeRecord.fields[key]==nil then different=true; break end
                end
            end
        end
        if different then
            changed=true
            updateUpvalueChangeCounts[index]=(updateUpvalueChangeCounts[index] or 0)+1
        end
        if typeof(afterValue)=="Vector3" then
            persistentVectorSamples+=1
            if persistentVectorLast and (afterValue-persistentVectorLast).Magnitude>1e-6 then persistentVectorChanges+=1 end
            persistentVectorLast=afterValue
            local final=ctx and ctx.moduleExit
            if final and typeof(final.rootCFrame)=="CFrame" and (afterValue-final.rootCFrame.Position).Magnitude<0.01 then
                persistentVectorMatchesRoot+=1
            end
            if final and typeof(final.cameraCFrame)=="CFrame" and (afterValue-final.cameraCFrame.Position).Magnitude<0.01 then
                persistentVectorMatchesCamera+=1
            end
        end
    end
    if changed then updateUpvalueChangeFrames+=1 end
    updateUpvalueLastBefore=frozenUpvaluesSummary(before)
    updateUpvalueLastAfter=frozenUpvaluesSummary(after)
end

local function stackLocalsAtCustomCall()
    local getter=debug and debug.getstack
    local localGetter=debug and debug.getlocal
    if type(getter)~="function" and type(localGetter)~="function" then
        localStackUnavailable+=1
        return "debug.getstack/getlocal unavailable"
    end
    local frames={}
    for level=3,16 do
        local source,name,fn
        if debug and type(debug.info)=="function" then
            pcall(function()
                source=debug.info(level,"s")
                name=debug.info(level,"n")
                fn=debug.info(level,"f")
            end)
        end
        local sourceText=cleanText(source,100)
        local candidate=string.find(string.lower(sourceText),"cameramodule",1,true)~=nil
            or name=="Update" or (targets["CameraModule.Update"] and fn==targets["CameraModule.Update"].fn)
        if candidate then
            local locals={}
            if type(getter)=="function" then
                local ok,values=pcall(getter,level)
                if ok and type(values)=="table" then
                    for index,value in pairs(values) do
                        if #locals<36 then locals[#locals+1]=tostring(index).."="..valueSummary(value) end
                    end
                end
            end
            if #locals==0 and type(localGetter)=="function" then
                for index=1,36 do
                    local ok,localName,value=pcall(localGetter,level,index)
                    if not ok or localName==nil then break end
                    locals[#locals+1]=cleanText(localName,45).."="..valueSummary(value)
                end
            end
            if #locals>0 then
                table.sort(locals)
                frames[#frames+1]=string.format("L%d[%s:%s]{%s}",level,sourceText,cleanText(name,50),table.concat(locals," | "))
            end
        end
    end
    if #frames==0 then localStackUnavailable+=1; return "no CameraModule Update locals exposed" end
    localStackCaptures+=1
    local summary=table.concat(frames," <- ")
    lastCustomLocals=summary
    local schema=string.gsub(summary,"[%-%d%.]+","#")
    schema=cleanText(schema,600)
    localSchemas[schema]=(localSchemas[schema] or 0)+1
    return summary
end

local function installHook(id,factory)
    local target=targets[id]
    if not target then return false,"target-missing" end
    if type(hookfunction)~="function" then return false,"hookfunction-unavailable" end
    local original
    local replacement=factory(function(...) return original(...) end)
    local ok,old=pcall(function() return hookfunction(target.fn,replacement) end)
    if not ok or type(old)~="function" then return false,cleanText(old,160) end
    original=old
    target.original=old
    installedHooks[#installedHooks+1]={id=id,target=target.fn,original=old}
    addEvidence("HOOK",id.." installed")
    return true,"installed"
end

local function appendStage(ctx,name)
    if ctx then ctx.sequence[#ctx.sequence+1]=name end
end

local function cameraUpdateFactory(callOriginal)
    return function(self,dt,...)
        if not probeRunning or suppressTrace then return callOriginal(self,dt,...) end
        cameraModuleUpdates+=1
        probeFrames+=1
        local upvaluesBefore=select(1,snapshotUpdateUpvalues())
        local ctx={
            id=probeFrames,
            dt=dt,
            entry=cframeSnapshot(),
            upvaluesBefore=upvaluesBefore,
            sequence={"CameraModule.Update:enter"},
            capture=probeFrames<=10 or probeFrames%120==0,
        }
        currentContext=ctx
        if ctx.entry.shift then
            if ctx.entry.shiftValue==true then shiftTrueFrames+=1 else shiftFalseFrames+=1 end
        else shiftMissingFrames+=1 end
        if ctx.entry.preferredInput==Enum.PreferredInput.Touch then preferredTouchFrames+=1
        elseif ctx.entry.preferredInput==Enum.PreferredInput.KeyboardAndMouse then preferredComputerFrames+=1
        else otherPreferredFrames+=1 end
        if ctx.capture then addTrace("F"..string.format("%04d",ctx.id).." "..snapshotText("moduleEnter",ctx.entry)) end
        local results=packCall(callOriginal,self,dt,...)
        ctx.moduleExit=cframeSnapshot()
        appendStage(ctx,"CameraModule.Update:exit")
        local upvaluesAfter=select(1,snapshotUpdateUpvalues())
        compareUpvalues(ctx.upvaluesBefore,upvaluesAfter,ctx)
        local signature=table.concat(ctx.sequence,">")
        lastSequence=signature
        sequenceCounts[signature]=(sequenceCounts[signature] or 0)+1

        local tailStart=ctx.controllerExit or ctx.entry
        local tailEnd=ctx.moduleExit
        if changedCFrame(tailStart.rootCFrame,tailEnd.rootCFrame) then
            rootChangedControllerExitToModuleExit+=1
            if ctx.entry.shiftValue==true then rootChangeShiftTrue+=1 else rootChangeShiftFalse+=1 end
            if ctx.entry.preferredInput==Enum.PreferredInput.Touch then rootChangePreferredTouch+=1
            elseif ctx.entry.preferredInput==Enum.PreferredInput.KeyboardAndMouse then rootChangePreferredComputer+=1
            else rootChangePreferredOther+=1 end
            local p,r,y=cframeDelta(tailStart.rootCFrame,tailEnd.rootCFrame)
            rootTailPositionDeltaMax=math.max(rootTailPositionDeltaMax,p or 0)
            rootTailRotationDeltaMax=math.max(rootTailRotationDeltaMax,r or 0)
            rootTailYawDeltaMax=math.max(rootTailYawDeltaMax,y or 0)
            if (p or 0)>1e-5 then rootPositionChangedInCustomTail+=1 end
            if (r or 0)>1e-4 then rootRotationChangedInCustomTail+=1 end
            if (y or 0)>1e-4 then rootYawChangedInCustomTail+=1 end
        end
        if changedCFrame(tailStart.cameraCFrame,tailEnd.cameraCFrame) then cameraChangedControllerExitToModuleExit+=1 end
        if ctx.setterEntry and changedCFrame(tailStart.rootCFrame,ctx.setterEntry.rootCFrame) then
            rootChangedControllerExitToSetterEntry+=1
        end
        if ctx.setterEntry and ctx.setterExit and changedCFrame(ctx.setterEntry.rootCFrame,ctx.setterExit.rootCFrame) then
            rootChangedSetterEntryToSetterExit+=1
        end
        if ctx.setterExit and changedCFrame(ctx.setterExit.rootCFrame,tailEnd.rootCFrame) then
            rootChangedSetterExitToModuleExit+=1
        end
        if ctx.setterEntry and changedCFrame(tailStart.cameraCFrame,ctx.setterEntry.cameraCFrame) then
            cameraChangedControllerExitToSetterEntry+=1
        end
        if ctx.setterExit and changedCFrame(ctx.setterExit.cameraCFrame,tailEnd.cameraCFrame) then
            cameraChangedSetterExitToModuleExit+=1
        end
        if typeof(tailEnd.rootCFrame)=="CFrame" and typeof(tailEnd.cameraCFrame)=="CFrame" then
            rootCameraYawSamples+=1
            if math.abs(angleDelta(yaw(tailEnd.rootCFrame),yaw(tailEnd.cameraCFrame)) or 999)<0.15 then
                rootMatchesCameraYawAfter+=1
            end
        end
        if ctx.controllerReturnCFrame and ctx.setterEntry and typeof(ctx.setterEntry.cameraCFrame)=="CFrame" then
            controllerReturnCameraSamples+=1
            if not changedCFrame(ctx.controllerReturnCFrame,ctx.setterEntry.cameraCFrame,0.002,0.02) then
                controllerReturnMatchesCameraAtSetter+=1
            end
        end
        if ctx.capture or (changedCFrame(tailStart.rootCFrame,tailEnd.rootCFrame)
            and rootChangedControllerExitToModuleExit<=24) then
            lastStageSnapshot=snapshotText("controllerExit",tailStart).." -> "
                ..snapshotText("setterEntry",ctx.setterEntry).." -> "..snapshotText("moduleExit",tailEnd)
            addTrace("F"..string.format("%04d",ctx.id).." sequence={"..signature.."} "..lastStageSnapshot)
        end
        currentContext=nil
        if not results[1] then traceErrors+=1 end
        return returnPacked(results)
    end
end

local function controllerUpdateFactory(callOriginal)
    return function(self,dt,...)
        if not probeRunning or suppressTrace then return callOriginal(self,dt,...) end
        local ctx=currentContext
        local active=getActiveController()
        if not ctx or self~=active then return callOriginal(self,dt,...) end
        controllerUpdates+=1
        ctx.controllerEntry=cframeSnapshot()
        appendStage(ctx,"Controller.Update:enter")
        local results=packCall(callOriginal,self,dt,...)
        ctx.controllerExit=cframeSnapshot()
        ctx.controllerReturnCFrame=results[2]
        ctx.controllerReturnFocus=results[3]
        appendStage(ctx,"Controller.Update:exit")
        if changedCFrame(ctx.entry.rootCFrame,ctx.controllerExit.rootCFrame) then rootChangedEntryToControllerExit+=1 end
        if not results[1] then controllerUpdateErrors+=1 end
        return returnPacked(results)
    end
end

local function setLockFactory(callOriginal)
    return function(self,value,...)
        if not probeRunning or suppressTrace then return callOriginal(self,value,...) end
        local ctx=currentContext
        local active=getActiveController()
        local sameActive=self==active
        if not ctx or not sameActive then
            if ctx then customSetterOtherSelf+=1 end
            return callOriginal(self,value,...)
        end
        customSetterCalls+=1
        customSetterActiveSelf+=1
        if value==true then customSetterTrue+=1 elseif value==false then customSetterFalse+=1 end
        local _,shiftValue=readShift()
        if value==shiftValue then customSetterShiftMatches+=1 else customSetterShiftMismatches+=1 end
        ctx.setterEntry=cframeSnapshot()
        ctx.setterLocals=stackLocalsAtCustomCall()
        appendStage(ctx,"CustomBlock.SetIsMouseLocked("..tostring(value).."):enter")
        local results=packCall(callOriginal,self,value,...)
        ctx.setterExit=cframeSnapshot()
        appendStage(ctx,"CustomBlock.SetIsMouseLocked:exit")
        if ctx.capture or customSetterCalls<=8 then
            addTrace(string.format("F%04d customSetter arg=%s shift=%s locals={%s} %s -> %s",ctx.id,tostring(value),
                tostring(shiftValue),cleanText(ctx.setterLocals,1000),snapshotText("before",ctx.setterEntry),snapshotText("after",ctx.setterExit)))
        end
        return returnPacked(results)
    end
end

local function accelerateFactory(callOriginal)
    return function(...)
        if not probeRunning or suppressTrace then return callOriginal(...) end
        accelerateCalls+=1
        local ctx=currentContext
        if ctx then accelerateInsideBlock+=1; appendStage(ctx,"accelerate:enter") else accelerateOutsideBlock+=1 end
        local args=table.pack(...)
        local argParts={}
        for index=1,math.min(args.n,12) do argParts[#argParts+1]=tostring(index).."="..valueSummary(args[index]) end
        local results=packCall(callOriginal,...)
        local returnParts={}
        for index=2,math.min(results.n,13) do returnParts[#returnParts+1]=tostring(index-1).."="..valueSummary(results[index]) end
        lastAccelerateArgs=table.concat(argParts," | ")
        lastAccelerateReturns=table.concat(returnParts," | ")
        if ctx then appendStage(ctx,"accelerate:exit") end
        if not results[1] then accelerateErrors+=1 end
        if accelerateCalls<=8 or (ctx and ctx.capture) then
            addTrace(string.format("F%s accelerate args={%s} returns={%s} ok=%s",ctx and string.format("%04d",ctx.id) or "OUT",
                cleanText(lastAccelerateArgs,900),cleanText(lastAccelerateReturns,900),tostring(results[1])))
        end
        return returnPacked(results)
    end
end

local function installFocusedHooks()
    local specs={
        {"CameraModule.Update",cameraUpdateFactory},
        {"Controller.Update",controllerUpdateFactory},
        {"Controller.SetIsMouseLocked",setLockFactory},
    }
    for _,spec in ipairs(specs) do
        local ok,detail=installHook(spec[1],spec[2])
        if not ok then addEvidence("HOOK",spec[1].." rejected="..detail) end
    end
    if accelerateFunction then
        targets["CustomBlock.accelerate"]={fn=accelerateFunction,origin="CameraModule.Update direct upvalue table.accelerate"}
        local ok,detail=installHook("CustomBlock.accelerate",accelerateFactory)
        if not ok then addEvidence("HOOK","CustomBlock.accelerate rejected="..detail) end
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
    probeFrames=0; traceErrors=0; traceLines={}; traceDropped=0; currentContext=nil
    cameraModuleUpdates=0; controllerUpdates=0; controllerUpdateErrors=0
    customSetterCalls=0; customSetterActiveSelf=0; customSetterOtherSelf=0
    customSetterShiftMatches=0; customSetterShiftMismatches=0; customSetterTrue=0; customSetterFalse=0
    accelerateCalls=0; accelerateInsideBlock=0; accelerateOutsideBlock=0; accelerateErrors=0
    shiftTrueFrames=0; shiftFalseFrames=0; shiftMissingFrames=0
    preferredTouchFrames=0; preferredComputerFrames=0; otherPreferredFrames=0
    rootChangedEntryToControllerExit=0; rootChangedControllerExitToSetterEntry=0
    rootChangedSetterEntryToSetterExit=0; rootChangedSetterExitToModuleExit=0; rootChangedControllerExitToModuleExit=0
    rootPositionChangedInCustomTail=0; rootRotationChangedInCustomTail=0; rootYawChangedInCustomTail=0
    rootChangeShiftTrue=0; rootChangeShiftFalse=0; rootMatchesCameraYawAfter=0; rootCameraYawSamples=0
    rootChangePreferredTouch=0; rootChangePreferredComputer=0; rootChangePreferredOther=0
    rootTailPositionDeltaMax=0; rootTailRotationDeltaMax=0; rootTailYawDeltaMax=0
    cameraChangedControllerExitToSetterEntry=0; cameraChangedSetterExitToModuleExit=0; cameraChangedControllerExitToModuleExit=0
    controllerReturnMatchesCameraAtSetter=0; controllerReturnCameraSamples=0
    updateUpvalueSnapshots=0; updateUpvalueChangeFrames=0; updateUpvalueChangeCounts={}
    updateUpvalueLastBefore=""; updateUpvalueLastAfter=""; persistentVectorSamples=0; persistentVectorChanges=0
    persistentVectorMatchesRoot=0; persistentVectorMatchesCamera=0; persistentVectorLast=nil
    localStackCaptures=0; localStackUnavailable=0; lastCustomLocals=""; localSchemas={}
    lastSequence=""; sequenceCounts={}; lastAccelerateArgs=""; lastAccelerateReturns=""; lastStageSnapshot=""
end

local function startProbe()
    if probeRunning then return false,"already-running" end
    if #installedHooks==0 then
        local ok,hookError=pcall(installFocusedHooks)
        if not ok or #installedHooks==0 then
            addEvidence("HOOK","restart-error="..cleanText(hookError,180))
            return false,"hook-install-failed"
        end
    end
    resetCounters()
    stateAtStart=cframeSnapshot()
    stateAtStop=nil
    probeStartedAt=os.clock()
    probeDuration=0
    probeRunning=true
    addEvidence("PROBE","V609 custom Evade block trace started")
    return true,"started"
end

local function stopProbe()
    if not probeRunning then return true,"already-stopped" end
    probeDuration=os.clock()-probeStartedAt
    probeRunning=false
    currentContext=nil
    stateAtStop=cframeSnapshot()
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

local function countSummary(counts)
    local rows={}
    for key,count in pairs(counts) do rows[#rows+1]={key=tostring(key),count=count} end
    table.sort(rows,function(a,b) return a.count>b.count end)
    local result={}
    for index=1,math.min(#rows,10) do result[#result+1]=rows[index].key..":"..rows[index].count end
    return table.concat(result," | ")
end

local function localSchemaSummary()
    return countSummary(localSchemas)
end

local function sequenceSummary()
    return countSummary(sequenceCounts)
end

local function upvalueChangeSummary()
    return countSummary(updateUpvalueChangeCounts)
end

local function classification()
    local touchTokenFound=#focusedBlockInputTokens>0
    local setterProven=customSetterCalls>0 and customSetterActiveSelf==customSetterCalls
        and customSetterShiftMismatches==0
    local rootTailTransform=rootChangedControllerExitToModuleExit>0
        and rootRotationChangedInCustomTail>0
    local staticRootHint=staticPrimaryPartCFrameWriteHint
    local anchorTransform=rootTailTransform
    local stateParts={}
    if updateUpvalueSnapshots>0 then
        stateParts[#stateParts+1]="Update upvalues sampled="..updateUpvalueSnapshots
        stateParts[#stateParts+1]="changeFrames="..updateUpvalueChangeFrames
        stateParts[#stateParts+1]="changes="..upvalueChangeSummary()
    end
    if persistentVectorSamples>0 then
        stateParts[#stateParts+1]=string.format("persistent Vector3 samples=%d changes=%d rootMatches=%d cameraMatches=%d",
            persistentVectorSamples,persistentVectorChanges,persistentVectorMatchesRoot,persistentVectorMatchesCamera)
    end
    if accelerateCalls>0 then stateParts[#stateParts+1]="accelerate calls="..accelerateCalls end
    local stateText=#stateParts>0 and table.concat(stateParts,"; ") or "no persistent custom state proved"
    local writes={}
    if setterProven then writes[#writes+1]="controller.inMouseLockedMode via SetIsMouseLocked(ShiftLockEnabled.Value)" end
    if rootTailTransform then
        writes[#writes+1]=string.format("PrimaryPart CFrame changed in custom tail frames=%d rotationFrames=%d positionFrames=%d",
            rootChangedControllerExitToModuleExit,rootRotationChangedInCustomTail,rootPositionChangedInCustomTail)
    elseif staticRootHint then writes[#writes+1]="decompile hints PrimaryPart.CFrame write; runtime change not observed" end
    if staticCameraCFrameWriteHint then writes[#writes+1]="decompile hints CurrentCamera.CFrame write" end
    if updateUpvalueChangeFrames>0 then writes[#writes+1]="persistent Update upvalue state changed" end
    local writesText=#writes>0 and table.concat(writes,"; ") or "no block-specific write proved"
    local semantics
    if rootTailTransform then
        semantics=string.format("after Controller.Update, custom block reads ShiftLockEnabled/PrimaryPart orientation, calls SetIsMouseLocked, and changes PrimaryPart orientation in %d frames; yawChanged=%d maxYaw=%.5f",
            rootChangedControllerExitToModuleExit,rootYawChangedInCustomTail,rootTailYawDeltaMax)
    elseif setterProven then
        semantics="after Controller.Update, custom block transfers ShiftLockEnabled.Value to active controller; no PrimaryPart transform was observed in this run"
    else
        semantics="custom block signature found but runtime semantics not yet proved"
    end
    local divergence
    if touchTokenFound then
        divergence="direct Touch/PC token found in focused decompile window: "..table.concat(focusedBlockInputTokens," | ")
    elseif anchorTransform then
        divergence="block-specific PrimaryPart transform found without a direct Touch/PC branch; compare its condition/local values next"
    else
        divergence="no direct Touch-vs-PC branch or anchor-relevant transform proved inside this custom block"
    end
    return {
        customEvadeBlockSemantics=semantics,
        customEvadeBlockWrites=writesText,
        customEvadeBlockState=stateText,
        touchVsPCBranchFound=touchTokenFound,
        anchorRelevantTransformFound=anchorTransform,
        firstFunctionalDivergence=divergence,
        experimentEligible=false,
        experimentReason=anchorTransform and "blocked-until-transform-condition-and-state-are-proved-safe" or "blocked-no-safe-anchor-transform-proved",
    }
end

getgenv().PCV609Diagnostics=function()
    local base=baseSafe()
    local decision=classification()
    local update=targetEvidence["CameraModule.Update"] or {}
    local controllerUpdate=targetEvidence["Controller.Update"] or {}
    local frozen=(not probeRunning and stateAtStop) or cframeSnapshot()
    return {
        version="V609-CustomEvadeCameraBlockTrace",
        bridgeMode=getgenv().PCInputBridgeMode,
        probePurpose="reconstruct-only-custom-Evade-CameraModule.Update-block",
        probeRunning=probeRunning,
        probeFrames=probeFrames,
        probeDuration=round(probeRunning and (os.clock()-probeStartedAt) or probeDuration,3),
        traceErrors=traceErrors,
        discoveryStatus=discoveryStatus,
        discoveryErrors=table.concat(discoveryErrors," | "),
        staticBlockConfirmed=staticBlockConfirmed,
        staticBlockMissing=table.concat(staticBlockMissing," | "),
        cameraModuleUpdateOrigin=update.origin,
        cameraModuleUpdateConstants=update.constants,
        cameraModuleUpdateUpvalues=update.upvalues,
        controllerUpdateOrigin=controllerUpdate.origin,
        decompileStatus=decompileStatus,
        decompileMarkerCount=decompileMarkerCount,
        decompileSelectedScore=decompileSelectedScore,
        updateInputTokens=table.concat(updateInputTokens," | "),
        focusedBlockInputTokens=table.concat(focusedBlockInputTokens," | "),
        staticPrimaryPartCFrameWriteHint=staticPrimaryPartCFrameWriteHint,
        staticCameraCFrameWriteHint=staticCameraCFrameWriteHint,
        accelerateEvidence=accelerateEvidence,
        traceDropped=traceDropped,
        evidenceDropped=evidenceDropped,
        cameraModuleUpdates=cameraModuleUpdates,
        controllerUpdates=controllerUpdates,
        controllerUpdateErrors=controllerUpdateErrors,
        customSetterCalls=customSetterCalls,
        customSetterActiveSelf=customSetterActiveSelf,
        customSetterOtherSelf=customSetterOtherSelf,
        customSetterShiftMatches=customSetterShiftMatches,
        customSetterShiftMismatches=customSetterShiftMismatches,
        customSetterTrue=customSetterTrue,
        customSetterFalse=customSetterFalse,
        accelerateCalls=accelerateCalls,
        accelerateInsideBlock=accelerateInsideBlock,
        accelerateOutsideBlock=accelerateOutsideBlock,
        accelerateErrors=accelerateErrors,
        lastAccelerateArgs=lastAccelerateArgs,
        lastAccelerateReturns=lastAccelerateReturns,
        shiftTrueFrames=shiftTrueFrames,
        shiftFalseFrames=shiftFalseFrames,
        shiftMissingFrames=shiftMissingFrames,
        preferredTouchFrames=preferredTouchFrames,
        preferredComputerFrames=preferredComputerFrames,
        otherPreferredFrames=otherPreferredFrames,
        rootChangedEntryToControllerExit=rootChangedEntryToControllerExit,
        rootChangedControllerExitToSetterEntry=rootChangedControllerExitToSetterEntry,
        rootChangedSetterEntryToSetterExit=rootChangedSetterEntryToSetterExit,
        rootChangedSetterExitToModuleExit=rootChangedSetterExitToModuleExit,
        rootChangedControllerExitToModuleExit=rootChangedControllerExitToModuleExit,
        rootPositionChangedInCustomTail=rootPositionChangedInCustomTail,
        rootRotationChangedInCustomTail=rootRotationChangedInCustomTail,
        rootYawChangedInCustomTail=rootYawChangedInCustomTail,
        rootChangeShiftTrue=rootChangeShiftTrue,
        rootChangeShiftFalse=rootChangeShiftFalse,
        rootChangePreferredTouch=rootChangePreferredTouch,
        rootChangePreferredComputer=rootChangePreferredComputer,
        rootChangePreferredOther=rootChangePreferredOther,
        rootTailPositionDeltaMax=round(rootTailPositionDeltaMax,8),
        rootTailRotationDeltaMax=round(rootTailRotationDeltaMax,7),
        rootTailYawDeltaMax=round(rootTailYawDeltaMax,7),
        rootMatchesCameraYawAfter=rootMatchesCameraYawAfter,
        rootCameraYawSamples=rootCameraYawSamples,
        cameraChangedControllerExitToSetterEntry=cameraChangedControllerExitToSetterEntry,
        cameraChangedSetterExitToModuleExit=cameraChangedSetterExitToModuleExit,
        cameraChangedControllerExitToModuleExit=cameraChangedControllerExitToModuleExit,
        controllerReturnMatchesCameraAtSetter=controllerReturnMatchesCameraAtSetter,
        controllerReturnCameraSamples=controllerReturnCameraSamples,
        updateUpvalueSnapshots=updateUpvalueSnapshots,
        updateUpvalueChangeFrames=updateUpvalueChangeFrames,
        updateUpvalueChangeSummary=upvalueChangeSummary(),
        updateUpvalueLastBefore=updateUpvalueLastBefore,
        updateUpvalueLastAfter=updateUpvalueLastAfter,
        persistentVectorSamples=persistentVectorSamples,
        persistentVectorChanges=persistentVectorChanges,
        persistentVectorMatchesRoot=persistentVectorMatchesRoot,
        persistentVectorMatchesCamera=persistentVectorMatchesCamera,
        persistentVectorLast=persistentVectorLast,
        localStackCaptures=localStackCaptures,
        localStackUnavailable=localStackUnavailable,
        lastCustomLocals=lastCustomLocals,
        localSchemaSummary=localSchemaSummary(),
        lastSequence=lastSequence,
        sequenceSummary=sequenceSummary(),
        lastStageSnapshot=lastStageSnapshot,
        lockAtStart=stateAtStart and stateAtStart.controllerLock,
        shiftAtStart=stateAtStart and stateAtStart.shiftValue,
        lockAtStop=frozen and frozen.controllerLock,
        shiftAtStop=frozen and frozen.shiftValue,
        preferredInputAtStop=frozen and frozen.preferredInput,
        relayEnabled=base.relayEnabled,
        relayValidationReady=base.relayValidationReady,
        ownershipGateProven=base.ownershipGateProven,
        touchRoleConflicts=base.touchRoleConflicts,
        joystickMouseCrossovers=base.joystickMouseCrossovers,
        relayErrors=base.relayErrors,
        callbackErrors=base.callbackErrors,
        validationReady=probeFrames>=30 and traceErrors==0 and staticBlockConfirmed
            and customSetterCalls>0 and customSetterShiftMismatches==0,
        experimentReason=decision.experimentReason,
        observationalOnly=true,
        invokesCustomBlock=false,
        writesCameraCFrame=false,
        writesRootPartCFrame=false,
        forcesPreferredInput=false,
        forcesMouseBehavior=false,
        forcesRotationType=false,
        forcesAutoRotate=false,
        changesGainSensitivityPhysics=false,
        usesSyntheticUserInputObject=false,
        usesFireSignal=false,
        addsVirtualInput=false,
        preservesV604Ownership=true,
        fallbackV500Preserved=true,
        customEvadeBlockSemantics=decision.customEvadeBlockSemantics,
        customEvadeBlockWrites=decision.customEvadeBlockWrites,
        customEvadeBlockState=decision.customEvadeBlockState,
        touchVsPCBranchFound=decision.touchVsPCBranchFound,
        anchorRelevantTransformFound=decision.anchorRelevantTransformFound,
        firstFunctionalDivergence=decision.firstFunctionalDivergence,
        experimentEligible=decision.experimentEligible,
    }
end

local REPORT_KEYS={
    "version","bridgeMode","probePurpose","probeRunning","probeFrames","probeDuration","traceErrors",
    "discoveryStatus","discoveryErrors","staticBlockConfirmed","staticBlockMissing","cameraModuleUpdateOrigin",
    "cameraModuleUpdateConstants","cameraModuleUpdateUpvalues","controllerUpdateOrigin","decompileStatus",
    "decompileMarkerCount","decompileSelectedScore","traceDropped","evidenceDropped",
    "updateInputTokens","focusedBlockInputTokens","staticPrimaryPartCFrameWriteHint","staticCameraCFrameWriteHint","accelerateEvidence",
    "cameraModuleUpdates","controllerUpdates","controllerUpdateErrors","customSetterCalls","customSetterActiveSelf",
    "customSetterOtherSelf","customSetterShiftMatches","customSetterShiftMismatches","customSetterTrue","customSetterFalse",
    "accelerateCalls","accelerateInsideBlock","accelerateOutsideBlock","accelerateErrors","lastAccelerateArgs",
    "lastAccelerateReturns","shiftTrueFrames","shiftFalseFrames","shiftMissingFrames","preferredTouchFrames",
    "preferredComputerFrames","otherPreferredFrames","rootChangedEntryToControllerExit",
    "rootChangedControllerExitToSetterEntry","rootChangedSetterEntryToSetterExit","rootChangedSetterExitToModuleExit",
    "rootChangedControllerExitToModuleExit","rootPositionChangedInCustomTail","rootRotationChangedInCustomTail",
    "rootYawChangedInCustomTail","rootChangeShiftTrue","rootChangeShiftFalse","rootChangePreferredTouch",
    "rootChangePreferredComputer","rootChangePreferredOther","rootTailPositionDeltaMax",
    "rootTailRotationDeltaMax","rootTailYawDeltaMax","rootMatchesCameraYawAfter","rootCameraYawSamples",
    "cameraChangedControllerExitToSetterEntry","cameraChangedSetterExitToModuleExit",
    "cameraChangedControllerExitToModuleExit","controllerReturnMatchesCameraAtSetter","controllerReturnCameraSamples",
    "updateUpvalueSnapshots","updateUpvalueChangeFrames","updateUpvalueChangeSummary","updateUpvalueLastBefore",
    "updateUpvalueLastAfter","persistentVectorSamples","persistentVectorChanges","persistentVectorMatchesRoot",
    "persistentVectorMatchesCamera","persistentVectorLast","localStackCaptures","localStackUnavailable",
    "lastCustomLocals","localSchemaSummary","lastSequence","sequenceSummary","lastStageSnapshot",
    "lockAtStart","shiftAtStart","lockAtStop","shiftAtStop","preferredInputAtStop","relayEnabled",
    "relayValidationReady","ownershipGateProven","touchRoleConflicts","joystickMouseCrossovers","relayErrors",
    "callbackErrors","validationReady","experimentReason","observationalOnly","invokesCustomBlock",
    "writesCameraCFrame","writesRootPartCFrame","forcesPreferredInput","forcesMouseBehavior","forcesRotationType",
    "forcesAutoRotate","changesGainSensitivityPhysics","usesSyntheticUserInputObject","usesFireSignal",
    "addsVirtualInput","preservesV604Ownership","fallbackV500Preserved",
}

getgenv().PCV609Report=function(includeEvidence)
    local diagnostics=getgenv().PCV609Diagnostics()
    local lines={"=== PC MOVEMENT V609 REPORT ==="}
    for _,key in ipairs(REPORT_KEYS) do lines[#lines+1]=key.." = "..tostring(diagnostics[key]) end
    if includeEvidence~=false then
        if decompileSnippet~="" then
            lines[#lines+1]=""
            lines[#lines+1]="=== V609 FOCUSED DECOMPILE WINDOW ==="
            lines[#lines+1]=decompileSnippet
        end
        lines[#lines+1]=""
        lines[#lines+1]="=== V609 CUSTOM BLOCK RUNTIME TRACE ==="
        for _,line in ipairs(traceLines) do lines[#lines+1]=line end
        lines[#lines+1]=""
        lines[#lines+1]="=== V609 TARGET EVIDENCE ==="
        for _,line in ipairs(evidence) do lines[#lines+1]=line end
        if type(baseReport)=="function" then
            local ok,text=pcall(baseReport,false)
            if ok then lines[#lines+1]=""; lines[#lines+1]=text end
        end
    end
    lines[#lines+1]=""
    lines[#lines+1]="=== V609 REQUIRED DECISION ==="
    lines[#lines+1]="customEvadeBlockSemantics = "..tostring(diagnostics.customEvadeBlockSemantics)
    lines[#lines+1]="customEvadeBlockWrites = "..tostring(diagnostics.customEvadeBlockWrites)
    lines[#lines+1]="customEvadeBlockState = "..tostring(diagnostics.customEvadeBlockState)
    lines[#lines+1]="touchVsPCBranchFound = "..tostring(diagnostics.touchVsPCBranchFound)
    lines[#lines+1]="anchorRelevantTransformFound = "..tostring(diagnostics.anchorRelevantTransformFound)
    lines[#lines+1]="firstFunctionalDivergence = "..tostring(diagnostics.firstFunctionalDivergence)
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
    panel.Size=UDim2.fromOffset(314,455)
    panel.Position=UDim2.new(1,-326,0.5,-227)
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
    stroke.Color=Color3.fromRGB(251,146,60)
    stroke.Thickness=1.5
    stroke.Parent=panel

    local title=Instance.new("TextLabel")
    title.Size=UDim2.new(1,-48,0,34)
    title.Position=UDim2.fromOffset(13,7)
    title.BackgroundTransparency=1
    title.Text="V609 • EVADE BLOCK TRACE"
    title.TextColor3=Color3.fromRGB(253,186,116)
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
    instructions.Size=UDim2.new(1,0,0,88)
    instructions.BackgroundColor3=Color3.fromRGB(22,28,45)
    instructions.BorderSizePixel=0
    instructions.Text="1) Prove joystick+câmera e ligue o relay\n2) INICIAR; gire parado e andando\n3) Inclua momentos com ShiftLockEnabled true/false\n4) PARAR e COPIAR antes de sair"
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
    experimentButton=makeButton(body,"EXPERIMENTO: BLOQUEADO",Color3.fromRGB(55,65,81),4)
    local emergency=makeButton(body,"EMERGÊNCIA • RELAY OFF / V500",Color3.fromRGB(190,24,93),5)
    local copy=makeButton(body,"COPIAR REPORT COMPLETO",Color3.fromRGB(2,132,199),6)
    statusLabel=Instance.new("TextLabel")
    statusLabel.LayoutOrder=7
    statusLabel.Size=UDim2.new(1,0,0,28)
    statusLabel.BackgroundTransparency=1
    statusLabel.Text="Pronto. Probe observacional; experimento bloqueado."
    statusLabel.TextColor3=Color3.fromRGB(148,163,184)
    statusLabel.TextSize=10
    statusLabel.TextWrapped=true
    statusLabel.Font=Enum.Font.Gotham
    statusLabel.Parent=body

    uiConnections[#uiConnections+1]=start.Activated:Connect(function()
        local ok=startProbe()
        setStatus(ok and "Trace ativo. Gire parado e andando." or "Não iniciou: hooks indisponíveis.",
            ok and Color3.fromRGB(74,222,128) or Color3.fromRGB(251,113,133))
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
        setStatus("Trace parado, hooks restaurados. Agora copie.",Color3.fromRGB(250,204,21))
    end)
    uiConnections[#uiConnections+1]=experimentButton.Activated:Connect(function()
        setStatus("Bloqueado: primeiro o bloco precisa provar transformação segura.",Color3.fromRGB(250,204,21))
    end)
    uiConnections[#uiConnections+1]=emergency.Activated:Connect(function()
        stopProbe()
        if type(baseSetRelay)=="function" then pcall(baseSetRelay,false) end
        refreshRelayButton()
        setStatus("Emergência: relay OFF; V500 preservado.",Color3.fromRGB(251,113,133))
    end)
    uiConnections[#uiConnections+1]=copy.Activated:Connect(function()
        stopProbe()
        local ok=copyToClipboard(getgenv().PCV609Report(true))
        setStatus(ok and "REPORT COPIADO. Agora pode sair e colar." or "Clipboard indisponível no Delta.",
            ok and Color3.fromRGB(74,222,128) or Color3.fromRGB(251,113,133))
    end)
    local expanded=true
    uiConnections[#uiConnections+1]=collapse.Activated:Connect(function()
        expanded=not expanded
        body.Visible=expanded
        panel.Size=expanded and UDim2.fromOffset(314,455) or UDim2.fromOffset(314,45)
        collapse.Text=expanded and "–" or "+"
    end)
    refreshRelayButton()
end

local discoverOk,discoverError=pcall(discoverFocusedBlock)
if not discoverOk then discoveryStatus="error:"..cleanText(discoverError,180); addEvidence("DISCOVERY",discoveryStatus) end
local hookOk,hookError=pcall(installFocusedHooks)
if not hookOk then addEvidence("HOOK","installation-error="..cleanText(hookError,180)) end
local uiOk,uiError=pcall(createPanel)
if not uiOk then addEvidence("UI","creation-error="..cleanText(uiError,180)) end

getgenv().PCV609Start=startProbe
getgenv().PCV609Stop=function() stopProbe(); return getgenv().PCV609Report(false) end
getgenv().PCV609EmergencyV500=function()
    stopProbe()
    if type(baseSetRelay)=="function" then pcall(baseSetRelay,false) end
    refreshRelayButton()
    return true,"relay-disabled-v500-active"
end

getgenv().__PCMobileAimCleanup=function()
    probeRunning=false
    currentContext=nil
    for _,connection in ipairs(uiConnections) do pcall(function() connection:Disconnect() end) end
    uiConnections={}
    if screenGui then pcall(function() screenGui:Destroy() end) end
    screenGui=nil
    restoreHooks()
    getgenv().PCV609Start=nil
    getgenv().PCV609Stop=nil
    getgenv().PCV609EmergencyV500=nil
    getgenv().PCV609Diagnostics=nil
    getgenv().PCV609Report=nil
    if baseCleanup then pcall(baseCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

addEvidence("READY","V609 focused custom Evade CameraModule.Update block trace ready; observational only")
warn("[V609] custom Evade CameraModule.Update block trace ready | observational only | use mobile panel")
