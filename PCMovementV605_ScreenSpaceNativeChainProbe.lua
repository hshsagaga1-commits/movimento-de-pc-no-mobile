local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")

local player=Players.LocalPlayer
local PRE_BIND="__PCMovementV605PreCameraSample"
local POST_BIND="__PCMovementV605PostCameraSample"
local UI_NAME="PCMovementV605Panel"

--[[
    V605 / SCREEN-SPACE + NATIVE CHAIN OBSERVATIONAL PROBE

    V604 is the validated input layer and remains untouched underneath this
    wrapper. V605 does not attempt to correct framing. It measures which native
    camera/control stages actually run while the character appears anchored or
    drifts in screen-space.

    Measurements are read-only:
      * camera yaw/pitch and character/root yaw;
      * camera <-> character yaw difference;
      * projected RootPart and torso position in viewport pixels/normalized space;
      * move vector, camera-relative flag, RotationType and AutoRotate state;
      * mouse-lock state/offset, camera subject/focus distances;
      * observed Touch/Mouse-route input.Delta -> rotateInput coefficients;
      * relevant PlayerModule functions plus runtime call counts and caller class.

    The only optional mutation exposed by the panel is the already-proved V604
    relay toggle. Emergency fallback disables that relay and returns camera Touch
    events to V500. V605 never writes Camera/RootPart CFrame, never forces
    AutoRotate, never calls UpdateMouseBehavior, and never creates input.
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

pcall(function() RunService:UnbindFromRenderStep(PRE_BIND) end)
pcall(function() RunService:UnbindFromRenderStep(POST_BIND) end)

getgenv().PCMovementVersion="V605-ScreenSpaceNativeChainProbe"
getgenv().PCInputBridgeMode="v605-observational-over-v604"
if getgenv().PCV605SampleInterval==nil then getgenv().PCV605SampleInterval=0.10 end

local playerModule
local cameras
local controls
local activeCameraController
local activeMovementController
local userGameSettings
pcall(function() userGameSettings=UserSettings():GetService("UserGameSettings") end)

local probeRunning=false
local currentPhase="PARADO"
local probeStartedAt=0
local probeFrames=0
local probeDuration=0
local samplesRecorded=0
local sampleErrors=0
local projectionErrors=0
local inputScalePolls=0
local lastSampleAt=0
local lastInputPollAt=0
local lastBaseEvent=0
local preRotateInput=nil
local latestFrame=nil
local previousFrame=nil
local previousRelayFrame={off=nil,on=nil}
local slowState:any={}
local slowStateAt=0
local transitionState={}
local stateTransitions=0
local evidence={}
local evidenceDropped=0
local sampleLines={}
local sampleLinesDropped=0
local screenGui=nil
local statusLabel=nil
local startButton=nil
local phaseButton=nil
local relayButton=nil
local uiConnections={}

local nativeScanStatus="not-started"
local nativeTablesVisited=0
local nativeTablesDeduped=0
local nativeFunctionsExamined=0
local nativeConstantsExamined=0
local nativeUpvaluesExamined=0
local nativeUpvalueFunctionsExamined=0
local nativeCandidatesFound=0
local nativeRelevantCandidates={}
local nativeConstantHits={}
local runtimeHooks={}
local runtimeHookErrors=0
local runtimeHookStatus="not-installed"

local sensitivity={
    touch={samples=0,xCount=0,yCount=0,xSum=0,ySum=0,xMin=math.huge,xMax=0,yMin=math.huge,yMax=0},
    mouse={samples=0,xCount=0,yCount=0,xSum=0,ySum=0,xMin=math.huge,xMax=0,yMin=math.huge,yMax=0},
    other={samples=0,xCount=0,yCount=0,xSum=0,ySum=0,xMin=math.huge,xMax=0,yMin=math.huge,yMax=0},
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
    local scale=10^(digits or 3)
    return math.floor(value*scale+0.5)/scale
end

local function addEvidence(section,message)
    if #evidence>=420 then
        evidenceDropped+=1
        return
    end
    evidence[#evidence+1]=string.format("[%03d][%s] %s",#evidence+1,section,cleanText(message,900))
end

local function addSampleLine(message)
    if #sampleLines>=240 then
        sampleLinesDropped+=1
        return
    end
    sampleLines[#sampleLines+1]=message
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

local function getActiveCameraController()
    local module=getCameras()
    if type(module)~="table" then return nil end
    local controller=rawget(module,"activeCameraController")
    if type(controller)~="table" and type(module.GetActiveCameraController)=="function" then
        pcall(function() controller=module:GetActiveCameraController() end)
    end
    return type(controller)=="table" and controller or nil
end

local function getActiveMovementController()
    local module=getControls()
    if type(module)~="table" then return nil end
    local controller=rawget(module,"activeController")
    if type(controller)~="table" then controller=rawget(module,"touchController") end
    return type(controller)=="table" and controller or nil
end

local function getMetatableSafe(tbl)
    local mt
    if type(getrawmetatable)=="function" then pcall(function() mt=getrawmetatable(tbl) end) end
    if type(mt)~="table" then pcall(function() mt=getmetatable(tbl) end) end
    return type(mt)=="table" and mt or nil
end

local function getConstants(fn)
    local getter=(debug and debug.getconstants) or getconstants
    if type(getter)~="function" then return {},"unavailable" end
    local ok,values=pcall(getter,fn)
    if not ok or type(values)~="table" then return {},"error" end
    local result={}
    for _,value in ipairs(values) do
        if type(value)=="string" or type(value)=="number" then
            nativeConstantsExamined+=1
            if #result<48 then result[#result+1]=cleanText(value,70) end
        end
    end
    return result,"ok"
end

local function getUpvalueSummary(fn,known)
    local getter=(debug and debug.getupvalues) or getupvalues
    if type(getter)~="function" then return {},"unavailable" end
    local ok,values=pcall(getter,fn)
    if not ok or type(values)~="table" then return {},"error" end
    local result={}
    for index,value in pairs(values) do
        nativeUpvaluesExamined+=1
        local label=tostring(index)..":"..typeof(value)
        for knownName,knownValue in pairs(known) do
            if value==knownValue then label=label.."="..knownName end
        end
        if type(value)=="string" or type(value)=="number" or type(value)=="boolean" then
            label=label..":"..cleanText(value,55)
        end
        if #result<28 then result[#result+1]=label end
    end
    return result,"ok"
end

local function rawUpvalues(fn)
    local getter=(debug and debug.getupvalues) or getupvalues
    if type(getter)~="function" then return nil end
    local ok,values=pcall(getter,fn)
    return ok and type(values)=="table" and values or nil
end

local KEYWORDS={
    "mouse","lock","offset","rotate","rotation","camera","subject","focus",
    "firstperson","movevector","movementrelative","camerarelative","autorotate",
    "humanoid","character","translation","anglechange","renderstepped","update",
}

local function relevantText(text)
    text=string.lower(text)
    for _,keyword in ipairs(KEYWORDS) do
        if string.find(text,keyword,1,true) then return true end
    end
    return false
end

local OBSERVE_METHODS={
    SetIsMouseLocked=true,
    GetIsMouseLocked=true,
    GetMouseLockOffset=true,
    SetMouseLockOffset=true,
    UpdateMouseBehavior=true,
    GetMoveVector=true,
    IsMoveVectorCameraRelative=true,
    OnRenderStepped=true,
    GetSubjectPosition=true,
    GetSubjectCFrame=true,
    CalculateNewLookCFrame=true,
    GetCameraToSubjectDistance=true,
    GetCameraLookVector=true,
    Update=true,
}

local function callerInfo()
    local caller="unavailable"
    if debug and type(debug.info)=="function" then
        pcall(function()
            local source,line,name=debug.info(3,"sln")
            caller=cleanText(source,90)..":"..tostring(line)..":"..cleanText(name,60)
        end)
    end
    return caller
end

local function installRuntimeObserver(candidate)
    if type(hookfunction)~="function" then return false,"hookfunction-unavailable" end
    if #runtimeHooks>=18 then return false,"hook-cap-reached" end
    local original
    local record={
        name=candidate.name,
        origin=candidate.origin,
        target=candidate.fn,
        expectedSelf=candidate.expectedSelf,
        calls=0,
        expectedSelfCalls=0,
        executorCalls=0,
        gameCalls=0,
        unknownCallerCalls=0,
        lastCaller="none",
    }
    local replacement=function(self,...)
        record.calls+=1
        if self==record.expectedSelf then record.expectedSelfCalls+=1 end
        local callerClass="unknown"
        if type(checkcaller)=="function" then
            local ok,value=pcall(checkcaller)
            if ok then callerClass=value and "executor" or "game" end
        end
        if callerClass=="executor" then record.executorCalls+=1
        elseif callerClass=="game" then record.gameCalls+=1
        else record.unknownCallerCalls+=1 end
        if record.calls==1 then
            record.lastCaller=callerInfo()
            addEvidence("RUNTIME-CALL",string.format(
                "%s origin=%s callerClass=%s caller=%s",
                record.name,record.origin,callerClass,record.lastCaller
            ))
        end
        return original(self,...)
    end
    local ok,old=pcall(function() return hookfunction(candidate.fn,replacement) end)
    if not ok or type(old)~="function" then return false,cleanText(old,140) end
    original=old
    record.original=old
    runtimeHooks[#runtimeHooks+1]=record
    return true,"installed"
end

local function scanNativeChain()
    nativeScanStatus="running"
    nativeTablesVisited=0
    nativeTablesDeduped=0
    nativeFunctionsExamined=0
    nativeConstantsExamined=0
    nativeUpvaluesExamined=0
    nativeUpvalueFunctionsExamined=0
    nativeCandidatesFound=0
    nativeRelevantCandidates={}
    nativeConstantHits={}

    activeCameraController=getActiveCameraController()
    activeMovementController=getActiveMovementController()
    local known={
        PlayerModule=getPlayerModule(),
        CameraModule=getCameras(),
        ControlModule=getControls(),
        ActiveCameraController=activeCameraController,
        ActiveMovementController=activeMovementController,
    }
    local roots={
        {name="CameraModule",value=known.CameraModule},
        {name="ActiveCameraController",value=known.ActiveCameraController},
        {name="ControlModule",value=known.ControlModule},
        {name="ActiveMovementController",value=known.ActiveMovementController},
    }
    local seenTables={}
    local seenFunctions={}
    local hookCandidates={}

    local inspectNestedFunction
    inspectNestedFunction=function(fn,origin,expectedSelf,depth)
        if type(fn)~="function" or depth>3 or seenFunctions[fn] then return end
        seenFunctions[fn]=origin
        nativeFunctionsExamined+=1
        nativeUpvalueFunctionsExamined+=1
        local constants,constantStatus=getConstants(fn)
        local upvalues,upvalueStatus=getUpvalueSummary(fn,known)
        local candidate={
            name="upvalue-function-"..tostring(depth),
            rawName=nil,
            origin=origin,
            fn=fn,
            expectedSelf=expectedSelf,
            constants=constants,
            upvalues=upvalues,
        }
        nativeCandidatesFound+=1
        if #nativeRelevantCandidates<64 then nativeRelevantCandidates[#nativeRelevantCandidates+1]=candidate end
        addEvidence("UPVALUE-FUNCTION",string.format(
            "origin=%s constantsStatus=%s constants={%s} upvaluesStatus=%s upvalues={%s}",
            origin,constantStatus,table.concat(constants," | "),upvalueStatus,table.concat(upvalues," | ")
        ))
        for _,constant in ipairs(constants) do
            local lower=string.lower(tostring(constant))
            if string.find(lower,"inputtranslationtocameraanglechange",1,true)
                or string.find(lower,"mousesensitivity",1,true)
                or string.find(lower,"camerarelative",1,true)
                or string.find(lower,"movementrelative",1,true)
                or string.find(lower,"autorotate",1,true) then
                nativeConstantHits[#nativeConstantHits+1]=origin.." -> "..constant
            end
        end
        local values=rawUpvalues(fn)
        if values then
            for index,value in pairs(values) do
                if type(value)=="function" then
                    inspectNestedFunction(value,origin.." -> upvalue["..tostring(index).."]",expectedSelf,depth+1)
                elseif type(value)=="table" and depth<=1 then
                    local count=0
                    pcall(function()
                        for key,nested in pairs(value) do
                            if type(nested)=="function" and relevantText(cleanText(key,80)) then
                                count+=1
                                if count<=12 then
                                    inspectNestedFunction(nested,origin.." -> upvalue["..tostring(index).."]."..cleanText(key,80),value,depth+1)
                                end
                            end
                        end
                    end)
                end
            end
        end
    end

    local function visit(tbl,depth,origin,expectedSelf)
        if type(tbl)~="table" or depth>12 then return end
        if seenTables[tbl] then
            nativeTablesDeduped+=1
            return
        end
        seenTables[tbl]=origin
        nativeTablesVisited+=1
        local entries={}
        local ok,err=pcall(function()
            for key,value in pairs(tbl) do entries[#entries+1]={key=key,value=value} end
        end)
        if not ok then
            addEvidence("NATIVE-TABLE",origin.." enumeration-error="..cleanText(err,150))
            return
        end
        table.sort(entries,function(a,b) return cleanText(a.key,80)<cleanText(b.key,80) end)
        addEvidence("NATIVE-TABLE",string.format("depth=%d origin=%s keys=%d",depth,origin,#entries))
        local indexTable=nil
        for _,entry in ipairs(entries) do
            if entry.key=="__index" and type(entry.value)=="table" then indexTable=entry.value end
            if type(entry.value)=="function" then
                nativeFunctionsExamined+=1
                if not seenFunctions[entry.value] then
                    seenFunctions[entry.value]=origin.."."..cleanText(entry.key,80)
                    local constants,constantStatus=getConstants(entry.value)
                    local upvalues,upvalueStatus=getUpvalueSummary(entry.value,known)
                    local combined=cleanText(entry.key,100).." "..table.concat(constants," ")
                    if relevantText(combined) then
                        nativeCandidatesFound+=1
                        local candidate={
                            name=cleanText(entry.key,90),
                            rawName=entry.key,
                            origin=origin.."."..cleanText(entry.key,90),
                            fn=entry.value,
                            expectedSelf=expectedSelf,
                            constants=constants,
                            upvalues=upvalues,
                        }
                        if #nativeRelevantCandidates<64 then
                            nativeRelevantCandidates[#nativeRelevantCandidates+1]=candidate
                        end
                        for _,constant in ipairs(constants) do
                            local lower=string.lower(tostring(constant))
                            if string.find(lower,"inputtranslationtocameraanglechange",1,true)
                                or string.find(lower,"mousesensitivity",1,true)
                                or string.find(lower,"camerarelative",1,true)
                                or string.find(lower,"movementrelative",1,true)
                                or string.find(lower,"autorotate",1,true) then
                                nativeConstantHits[#nativeConstantHits+1]=candidate.origin.." -> "..constant
                            end
                        end
                        addEvidence("NATIVE-FUNCTION",string.format(
                            "origin=%s constantsStatus=%s constants={%s} upvaluesStatus=%s upvalues={%s}",
                            candidate.origin,constantStatus,table.concat(constants," | "),
                            upvalueStatus,table.concat(upvalues," | ")
                        ))
                        if type(entry.key)=="string" and OBSERVE_METHODS[entry.key] then
                            hookCandidates[#hookCandidates+1]=candidate
                        end
                        local values=rawUpvalues(entry.value)
                        if values then
                            for index,value in pairs(values) do
                                if type(value)=="function" then
                                    inspectNestedFunction(
                                        value,candidate.origin.." -> upvalue["..tostring(index).."]",
                                        expectedSelf,1
                                    )
                                elseif type(value)=="table" then
                                    local nestedCount=0
                                    pcall(function()
                                        for key,nested in pairs(value) do
                                            if type(nested)=="function" and relevantText(cleanText(key,80)) then
                                                nestedCount+=1
                                                if nestedCount<=12 then
                                                    inspectNestedFunction(
                                                        nested,candidate.origin.." -> upvalue["..tostring(index).."]."..cleanText(key,80),
                                                        value,1
                                                    )
                                                end
                                            end
                                        end
                                    end)
                                end
                            end
                        end
                    end
                end
            end
        end
        local mt=getMetatableSafe(tbl)
        if mt then visit(mt,depth+1,origin.." -> getmetatable",expectedSelf) end
        if indexTable then visit(indexTable,depth+1,origin.." -> __index",expectedSelf) end
    end

    for _,root in ipairs(roots) do
        if type(root.value)=="table" then visit(root.value,0,root.name,root.value) end
    end

    runtimeHookStatus="installing"
    local hookedFunctions={}
    for _,candidate in ipairs(hookCandidates) do
        if not hookedFunctions[candidate.fn] and #runtimeHooks<18 then
            hookedFunctions[candidate.fn]=true
            local ok,detail=installRuntimeObserver(candidate)
            if not ok and detail~="hook-cap-reached" then
                runtimeHookErrors+=1
                addEvidence("RUNTIME-HOOK","rejected "..candidate.origin.." reason="..detail)
            end
        end
    end
    runtimeHookStatus=#runtimeHooks>0 and "installed-"..tostring(#runtimeHooks) or "none-installed"
    nativeScanStatus="complete"
    addEvidence("NATIVE-SUMMARY",string.format(
        "tables=%d deduped=%d functions=%d constants=%d upvalues=%d upvalueFunctions=%d candidates=%d hooks=%d",
        nativeTablesVisited,nativeTablesDeduped,nativeFunctionsExamined,
        nativeConstantsExamined,nativeUpvaluesExamined,nativeUpvalueFunctionsExamined,
        nativeCandidatesFound,#runtimeHooks
    ))
end

local function yawFromLook(look)
    return math.deg(math.atan2(-look.X,-look.Z))
end

local function pitchFromLook(look)
    return math.deg(math.asin(math.clamp(look.Y,-1,1)))
end

local function angleDelta(current,previous)
    local delta=(current-previous+180)%360-180
    return delta
end

local function newPhaseStats()
    return {
        frames=0,duration=0,validProjectionFrames=0,onScreenFrames=0,
        rootXMin=math.huge,rootXMax=-math.huge,rootYMin=math.huge,rootYMax=-math.huge,
        rootNormXMin=math.huge,rootNormXMax=-math.huge,rootNormYMin=math.huge,rootNormYMax=-math.huge,
        rootRadiusSum=0,rootRadiusMax=0,screenStepSum=0,screenStepMax=0,
        cameraYawTravel=0,rootYawTravel=0,cameraTurnFrames=0,
        rootFollowTravel=0,yawGapSum=0,yawGapMin=math.huge,yawGapMax=-math.huge,
        moveMagnitudeSum=0,cameraDistanceSum=0,cameraDistanceCount=0,
    }
end

local phaseStats={PARADO=newPhaseStats(),ANDANDO=newPhaseStats(),LIVRE=newPhaseStats()}
local relayStats={off=newPhaseStats(),on=newPhaseStats()}

local function resetPhaseStats()
    phaseStats={PARADO=newPhaseStats(),ANDANDO=newPhaseStats(),LIVRE=newPhaseStats()}
    relayStats={off=newPhaseStats(),on=newPhaseStats()}
    previousRelayFrame={off=nil,on=nil}
end

local function recordTransition(name,value)
    local text=cleanText(value,140)
    if transitionState[name]==nil then
        transitionState[name]=text
        addEvidence("STATE",name.." initial="..text)
    elseif transitionState[name]~=text then
        stateTransitions+=1
        addEvidence("STATE",name.." "..transitionState[name].." -> "..text)
        transitionState[name]=text
    end
end

local function readFrameState()
    local camera=workspace.CurrentCamera
    local character=player.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    local root=character and character:FindFirstChild("HumanoidRootPart")
    local torso=character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
    if not camera or not humanoid or not root then return nil,"camera/character unavailable" end

    local frame={}
    frame.time=os.clock()
    frame.camera=camera
    frame.character=character
    frame.humanoid=humanoid
    frame.root=root
    frame.torso=torso
    frame.cameraYaw=yawFromLook(camera.CFrame.LookVector)
    frame.cameraPitch=pitchFromLook(camera.CFrame.LookVector)
    frame.rootYaw=yawFromLook(root.CFrame.LookVector)
    frame.yawGap=angleDelta(frame.rootYaw,frame.cameraYaw)
    frame.viewport=camera.ViewportSize
    frame.cameraDistance=(camera.CFrame.Position-root.Position).Magnitude
    frame.focusDistance=(camera.CFrame.Position-camera.Focus.Position).Magnitude
    frame.moveDirection=humanoid.MoveDirection
    frame.moveMagnitude=humanoid.MoveDirection.Magnitude
    frame.autoRotate=humanoid.AutoRotate
    frame.cameraType=tostring(camera.CameraType)
    frame.cameraSubject=cleanText(camera.CameraSubject,100)
    frame.preRotateInput=preRotateInput
    frame.preferredInput=tostring(UserInputService.PreferredInput)
    pcall(function() frame.rotationType=tostring(userGameSettings.RotationType) end)
    pcall(function() frame.mouseSensitivity=userGameSettings.MouseSensitivity end)
    pcall(function() frame.nativeMouseDelta=UserInputService:GetMouseDelta() end)
    pcall(function() frame.rootVelocity=root.AssemblyLinearVelocity end)

    local controller=getActiveCameraController()
    local movement=getActiveMovementController()
    activeCameraController=controller
    activeMovementController=movement
    if type(controller)=="table" then
        pcall(function() frame.inMouseLockedMode=controller.inMouseLockedMode end)
        pcall(function() frame.mouseLockOffset=controller.mouseLockOffset end)
    end

    local refreshSlow=frame.time-slowStateAt>=0.10
        or slowState.controller~=controller or slowState.movement~=movement
    if refreshSlow then
        slowStateAt=frame.time
        slowState={controller=controller,movement=movement}
        if type(controller)=="table" then
            pcall(function()
                if type(controller.GetIsMouseLocked)=="function" then
                    slowState.getIsMouseLocked=controller:GetIsMouseLocked()
                end
            end)
            pcall(function()
                if type(controller.GetMouseLockOffset)=="function" then
                    slowState.getMouseLockOffset=controller:GetMouseLockOffset()
                end
            end)
        end
        if type(movement)=="table" then
            pcall(function()
                if type(movement.GetMoveVector)=="function" then slowState.moveVector=movement:GetMoveVector() end
            end)
            pcall(function()
                if type(movement.IsMoveVectorCameraRelative)=="function" then
                    slowState.moveVectorCameraRelative=movement:IsMoveVectorCameraRelative()
                end
            end)
        end
        if slowState.moveVector==nil then
            local controlModule=getControls()
            pcall(function()
                if type(controlModule)=="table" and type(controlModule.GetMoveVector)=="function" then
                    slowState.moveVector=controlModule:GetMoveVector()
                end
            end)
        end
    end
    frame.getIsMouseLocked=slowState.getIsMouseLocked
    frame.getMouseLockOffset=slowState.getMouseLockOffset
    frame.moveVector=slowState.moveVector
    frame.moveVectorCameraRelative=slowState.moveVectorCameraRelative

    local okRoot,rootPoint,rootOnScreen=pcall(function()
        return camera:WorldToViewportPoint(root.Position)
    end)
    if okRoot and typeof(rootPoint)=="Vector3" then
        frame.rootPoint=rootPoint
        frame.rootOnScreen=rootOnScreen
        frame.rootOffset=Vector2.new(rootPoint.X-frame.viewport.X/2,rootPoint.Y-frame.viewport.Y/2)
        frame.rootNorm=Vector2.new(frame.rootOffset.X/math.max(1,frame.viewport.X),frame.rootOffset.Y/math.max(1,frame.viewport.Y))
    else
        projectionErrors+=1
    end
    if torso then
        local okTorso,torsoPoint,torsoOnScreen=pcall(function()
            return camera:WorldToViewportPoint(torso.Position)
        end)
        if okTorso and typeof(torsoPoint)=="Vector3" then
            frame.torsoPoint=torsoPoint
            frame.torsoOnScreen=torsoOnScreen
            frame.torsoOffset=Vector2.new(torsoPoint.X-frame.viewport.X/2,torsoPoint.Y-frame.viewport.Y/2)
            frame.torsoNorm=Vector2.new(frame.torsoOffset.X/math.max(1,frame.viewport.X),frame.torsoOffset.Y/math.max(1,frame.viewport.Y))
        end
    end
    return frame,nil
end

local function updateStats(stats,frame,previous,dt)
    stats.frames+=1
    stats.duration+=dt
    stats.moveMagnitudeSum+=frame.moveMagnitude or 0
    if type(frame.cameraDistance)=="number" then
        stats.cameraDistanceSum+=frame.cameraDistance
        stats.cameraDistanceCount+=1
    end
    local gap=math.abs(frame.yawGap)
    stats.yawGapSum+=gap
    stats.yawGapMin=math.min(stats.yawGapMin,gap)
    stats.yawGapMax=math.max(stats.yawGapMax,gap)
    if frame.rootPoint and frame.rootOffset and frame.rootNorm then
        stats.validProjectionFrames+=1
        if frame.rootOnScreen then stats.onScreenFrames+=1 end
        stats.rootXMin=math.min(stats.rootXMin,frame.rootPoint.X)
        stats.rootXMax=math.max(stats.rootXMax,frame.rootPoint.X)
        stats.rootYMin=math.min(stats.rootYMin,frame.rootPoint.Y)
        stats.rootYMax=math.max(stats.rootYMax,frame.rootPoint.Y)
        stats.rootNormXMin=math.min(stats.rootNormXMin,frame.rootNorm.X)
        stats.rootNormXMax=math.max(stats.rootNormXMax,frame.rootNorm.X)
        stats.rootNormYMin=math.min(stats.rootNormYMin,frame.rootNorm.Y)
        stats.rootNormYMax=math.max(stats.rootNormYMax,frame.rootNorm.Y)
        stats.rootRadiusSum+=frame.rootOffset.Magnitude
        stats.rootRadiusMax=math.max(stats.rootRadiusMax,frame.rootOffset.Magnitude)
    end
    if previous then
        local cameraDelta=math.abs(angleDelta(frame.cameraYaw,previous.cameraYaw))
        local rootDelta=math.abs(angleDelta(frame.rootYaw,previous.rootYaw))
        stats.cameraYawTravel+=cameraDelta
        stats.rootYawTravel+=rootDelta
        if cameraDelta>=0.05 then
            stats.cameraTurnFrames+=1
            stats.rootFollowTravel+=rootDelta
        end
        if frame.rootPoint and previous.rootPoint then
            local step=(Vector2.new(frame.rootPoint.X,frame.rootPoint.Y)-Vector2.new(previous.rootPoint.X,previous.rootPoint.Y)).Magnitude
            stats.screenStepSum+=step
            stats.screenStepMax=math.max(stats.screenStepMax,step)
        end
    end
end

local function addScaleSample(route,delta,rotationDelta)
    local stats=sensitivity[route] or sensitivity.other
    stats.samples+=1
    if typeof(delta)~="Vector3" or typeof(rotationDelta)~="Vector2" then return end
    if math.abs(delta.X)>1e-6 then
        local coefficient=math.abs(rotationDelta.X/delta.X)
        stats.xCount+=1
        stats.xSum+=coefficient
        stats.xMin=math.min(stats.xMin,coefficient)
        stats.xMax=math.max(stats.xMax,coefficient)
    end
    if math.abs(delta.Y)>1e-6 then
        local coefficient=math.abs(rotationDelta.Y/delta.Y)
        stats.yCount+=1
        stats.ySum+=coefficient
        stats.yMin=math.min(stats.yMin,coefficient)
        stats.yMax=math.max(stats.yMax,coefficient)
    end
end

local function pollInputScale()
    local now=os.clock()
    if now-lastInputPollAt<0.05 then return end
    lastInputPollAt=now
    if type(baseDiagnostics)~="function" then return end
    local ok,d=pcall(baseDiagnostics)
    if not ok or type(d)~="table" then return end
    local event=tonumber(d.onInputChangedObservedEvents) or 0
    if event==lastBaseEvent then return end
    lastBaseEvent=event
    inputScalePolls+=1
    if d.lastTouchRole~="camera" then return end
    local before=d.rotateBefore
    local after=d.rotateAfter
    local delta=d.lastInputDelta
    if typeof(before)~="Vector2" or typeof(after)~="Vector2" then return end
    local route="other"
    if d.lastOnInputCalledOnMouseMoved==true then route="mouse"
    elseif d.lastOnInputCalledOnTouchChanged==true then route="touch" end
    addScaleSample(route,delta,after-before)
end

local function currentRelayState()
    return getgenv().PCV604RelayEnabled==true
end

local function updateStateTransitions(frame)
    recordTransition("RotationType",frame.rotationType)
    recordTransition("Humanoid.AutoRotate",frame.autoRotate)
    recordTransition("inMouseLockedMode",frame.inMouseLockedMode)
    recordTransition("GetIsMouseLocked",frame.getIsMouseLocked)
    recordTransition("mouseLockOffset",frame.mouseLockOffset)
    recordTransition("GetMouseLockOffset",frame.getMouseLockOffset)
    recordTransition("IsMoveVectorCameraRelative",frame.moveVectorCameraRelative)
    recordTransition("PreferredInput",frame.preferredInput)
    recordTransition("CameraType",frame.cameraType)
    recordTransition("CameraSubject",frame.cameraSubject)
    recordTransition("ActiveCameraController",activeCameraController)
    recordTransition("ActiveMovementController",activeMovementController)
end

local function samplePostCamera(dt)
    if not probeRunning then return end
    probeFrames+=1
    probeDuration+=dt
    local ok,err=pcall(function()
        local frame,frameError=readFrameState()
        if not frame then error(frameError) end
        latestFrame=frame
        updateStats(phaseStats[currentPhase],frame,previousFrame,dt)
        local relayKey=currentRelayState() and "on" or "off"
        updateStats(relayStats[relayKey],frame,previousRelayFrame[relayKey],dt)
        previousRelayFrame[relayKey]=frame
        updateStateTransitions(frame)
        pollInputScale()
        local interval=math.max(0.05,tonumber(getgenv().PCV605SampleInterval) or 0.10)
        if frame.time-lastSampleAt>=interval then
            lastSampleAt=frame.time
            samplesRecorded+=1
            local lockValue=frame.getIsMouseLocked
            if lockValue==nil then lockValue=frame.inMouseLockedMode end
            addSampleLine(string.format(
                "S%04d t=%.2f phase=%s camYaw=%.3f camPitch=%.3f rootYaw=%.3f gap=%.3f rootPx=%s rootNorm=%s torsoPx=%s moveMag=%.3f moveVector=%s cameraRelative=%s lock=%s offset=%s rotationType=%s autoRotate=%s cameraDist=%.3f focusDist=%.3f preRotate=%s mouseDelta=%s",
                samplesRecorded,frame.time-probeStartedAt,currentPhase,frame.cameraYaw,
                frame.cameraPitch,frame.rootYaw,frame.yawGap,cleanText(frame.rootPoint,80),
                cleanText(frame.rootNorm,80),cleanText(frame.torsoPoint,80),frame.moveMagnitude,
                cleanText(frame.moveVector,80),tostring(frame.moveVectorCameraRelative),
                tostring(lockValue),
                cleanText(frame.getMouseLockOffset or frame.mouseLockOffset,70),
                tostring(frame.rotationType),tostring(frame.autoRotate),frame.cameraDistance,
                frame.focusDistance,cleanText(frame.preRotateInput,70),cleanText(frame.nativeMouseDelta,70)
            ))
        end
        previousFrame=frame
    end)
    if not ok then
        sampleErrors+=1
        if sampleErrors<=12 then addEvidence("SAMPLE-ERROR",err) end
    end
end

local function resetMeasurement()
    probeFrames=0
    probeDuration=0
    samplesRecorded=0
    sampleErrors=0
    projectionErrors=0
    inputScalePolls=0
    lastSampleAt=0
    lastInputPollAt=0
    lastBaseEvent=0
    preRotateInput=nil
    latestFrame=nil
    previousFrame=nil
    slowState={}
    slowStateAt=0
    transitionState={}
    stateTransitions=0
    sampleLines={}
    sampleLinesDropped=0
    sensitivity={
        touch={samples=0,xCount=0,yCount=0,xSum=0,ySum=0,xMin=math.huge,xMax=0,yMin=math.huge,yMax=0},
        mouse={samples=0,xCount=0,yCount=0,xSum=0,ySum=0,xMin=math.huge,xMax=0,yMin=math.huge,yMax=0},
        other={samples=0,xCount=0,yCount=0,xSum=0,ySum=0,xMin=math.huge,xMax=0,yMin=math.huge,yMax=0},
    }
    resetPhaseStats()
    for _,record in ipairs(runtimeHooks) do
        record.calls=0
        record.expectedSelfCalls=0
        record.executorCalls=0
        record.gameCalls=0
        record.unknownCallerCalls=0
        record.lastCaller="none"
    end
end

local function startProbe()
    resetMeasurement()
    if type(baseDiagnostics)=="function" then
        pcall(function()
            local d=baseDiagnostics()
            lastBaseEvent=tonumber(d.onInputChangedObservedEvents) or 0
        end)
    end
    probeRunning=true
    probeStartedAt=os.clock()
    addEvidence("PROBE","measurement started phase="..currentPhase)
end

local function stopProbe()
    if probeRunning then
        probeRunning=false
        addEvidence("PROBE","measurement stopped duration="..tostring(round(probeDuration,3)))
    end
end

local function finiteOrNil(value)
    if value==math.huge or value==-math.huge then return nil end
    return round(value,5)
end

local function phaseSummary(prefix,stats,result)
    result[prefix.."Frames"]=stats.frames
    result[prefix.."Duration"]=round(stats.duration,3)
    result[prefix.."ValidProjectionFrames"]=stats.validProjectionFrames
    result[prefix.."OnScreenFrames"]=stats.onScreenFrames
    result[prefix.."RootScreenSpanX"]=stats.validProjectionFrames>0 and round(stats.rootXMax-stats.rootXMin,3) or nil
    result[prefix.."RootScreenSpanY"]=stats.validProjectionFrames>0 and round(stats.rootYMax-stats.rootYMin,3) or nil
    result[prefix.."RootNormSpanX"]=stats.validProjectionFrames>0 and round(stats.rootNormXMax-stats.rootNormXMin,6) or nil
    result[prefix.."RootNormSpanY"]=stats.validProjectionFrames>0 and round(stats.rootNormYMax-stats.rootNormYMin,6) or nil
    result[prefix.."RootRadiusMeanPx"]=stats.validProjectionFrames>0 and round(stats.rootRadiusSum/stats.validProjectionFrames,3) or nil
    result[prefix.."RootRadiusMaxPx"]=round(stats.rootRadiusMax,3)
    result[prefix.."ScreenStepMeanPx"]=stats.frames>1 and round(stats.screenStepSum/(stats.frames-1),5) or nil
    result[prefix.."ScreenStepMaxPx"]=round(stats.screenStepMax,3)
    result[prefix.."CameraYawTravelDeg"]=round(stats.cameraYawTravel,3)
    result[prefix.."RootYawTravelDeg"]=round(stats.rootYawTravel,3)
    result[prefix.."CameraTurnFrames"]=stats.cameraTurnFrames
    result[prefix.."RootFollowRatio"]=stats.cameraYawTravel>0 and round(stats.rootFollowTravel/stats.cameraYawTravel,6) or nil
    result[prefix.."YawGapMeanDeg"]=stats.frames>0 and round(stats.yawGapSum/stats.frames,3) or nil
    result[prefix.."YawGapMinDeg"]=finiteOrNil(stats.yawGapMin)
    result[prefix.."YawGapMaxDeg"]=finiteOrNil(stats.yawGapMax)
    result[prefix.."MoveMagnitudeMean"]=stats.frames>0 and round(stats.moveMagnitudeSum/stats.frames,5) or nil
    result[prefix.."CameraDistanceMean"]=stats.cameraDistanceCount>0 and round(stats.cameraDistanceSum/stats.cameraDistanceCount,3) or nil
    result[prefix.."ScreenDriftPerCameraDegree"]=stats.cameraYawTravel>0 and round(stats.screenStepSum/stats.cameraYawTravel,6) or nil
end

local function scaleSummary(prefix,stats,result)
    result[prefix.."Samples"]=stats.samples
    result[prefix.."XCount"]=stats.xCount
    result[prefix.."YCount"]=stats.yCount
    result[prefix.."XRadPerDeltaMean"]=stats.xCount>0 and round(stats.xSum/stats.xCount,9) or nil
    result[prefix.."YRadPerDeltaMean"]=stats.yCount>0 and round(stats.ySum/stats.yCount,9) or nil
    result[prefix.."XRadPerDeltaMin"]=stats.xCount>0 and round(stats.xMin,9) or nil
    result[prefix.."XRadPerDeltaMax"]=stats.xCount>0 and round(stats.xMax,9) or nil
    result[prefix.."YRadPerDeltaMin"]=stats.yCount>0 and round(stats.yMin,9) or nil
    result[prefix.."YRadPerDeltaMax"]=stats.yCount>0 and round(stats.yMax,9) or nil
    local xMean=stats.xCount>0 and stats.xSum/stats.xCount or nil
    local yMean=stats.yCount>0 and stats.ySum/stats.yCount or nil
    result[prefix.."YOverXRatio"]=xMean and xMean>0 and yMean and round(yMean/xMean,6) or nil
end

local function runtimeCallSummary()
    local lines={}
    for _,record in ipairs(runtimeHooks) do
        lines[#lines+1]=string.format(
            "%s{%s,total=%d,self=%d,executor=%d,game=%d,unknown=%d,caller=%s}",
            record.name,record.origin,record.calls,record.expectedSelfCalls,
            record.executorCalls,record.gameCalls,record.unknownCallerCalls,record.lastCaller
        )
    end
    return #lines>0 and table.concat(lines," | ") or "none"
end

local function candidateSummary()
    local lines={}
    for index,candidate in ipairs(nativeRelevantCandidates) do
        if index>32 then break end
        lines[#lines+1]=candidate.origin.."{constants="..table.concat(candidate.constants,",")..";upvalues="..table.concat(candidate.upvalues,",").."}"
    end
    return #lines>0 and table.concat(lines," | ") or "none"
end

local function v604DiagnosticsSafe()
    if type(baseDiagnostics)~="function" then return {} end
    local ok,value=pcall(baseDiagnostics)
    return ok and type(value)=="table" and value or {}
end

getgenv().PCV605Diagnostics=function()
    local base=v604DiagnosticsSafe()
    local result={
        version="V605-ScreenSpaceNativeChainProbe",
        bridgeMode=getgenv().PCInputBridgeMode,
        probePurpose="measure-native-PC-anchor-chain-no-framing-correction",
        probeRunning=probeRunning,
        currentPhase=currentPhase,
        probeFrames=probeFrames,
        probeDuration=round(probeDuration,3),
        samplesRecorded=samplesRecorded,
        sampleErrors=sampleErrors,
        projectionErrors=projectionErrors,
        inputScalePolls=inputScalePolls,
        stateTransitions=stateTransitions,
        nativeScanStatus=nativeScanStatus,
        nativeTablesVisited=nativeTablesVisited,
        nativeTablesDeduped=nativeTablesDeduped,
        nativeFunctionsExamined=nativeFunctionsExamined,
        nativeConstantsExamined=nativeConstantsExamined,
        nativeUpvaluesExamined=nativeUpvaluesExamined,
        nativeUpvalueFunctionsExamined=nativeUpvalueFunctionsExamined,
        nativeCandidatesFound=nativeCandidatesFound,
        nativeConstantHits=table.concat(nativeConstantHits," | "),
        nativeCandidateSummary=candidateSummary(),
        runtimeHookStatus=runtimeHookStatus,
        runtimeHooksInstalled=#runtimeHooks,
        runtimeHookErrors=runtimeHookErrors,
        runtimeCallSummary=runtimeCallSummary(),
        relayEnabled=base.relayEnabled,
        relayValidationReady=base.relayValidationReady,
        ownershipGateProven=base.ownershipGateProven,
        touchRoleConflicts=base.touchRoleConflicts,
        joystickMouseCrossovers=base.joystickMouseCrossovers,
        relayAttempts=base.relayAttempts,
        relayCompleted=base.relayCompleted,
        relayErrors=base.relayErrors,
        relaySameInputConfirmed=base.relaySameInputConfirmed,
        simultaneousJoystickCameraRelayed=base.simultaneousJoystickCameraRelayed,
        callbackErrors=base.callbackErrors,
        v604FallbackReason=base.fallbackReason,
        latestCameraYaw=latestFrame and round(latestFrame.cameraYaw,4) or nil,
        latestCameraPitch=latestFrame and round(latestFrame.cameraPitch,4) or nil,
        latestRootYaw=latestFrame and round(latestFrame.rootYaw,4) or nil,
        latestCameraRootYawDifference=latestFrame and round(latestFrame.yawGap,4) or nil,
        latestRootScreenPoint=latestFrame and latestFrame.rootPoint or nil,
        latestRootScreenNormalized=latestFrame and latestFrame.rootNorm or nil,
        latestTorsoScreenPoint=latestFrame and latestFrame.torsoPoint or nil,
        latestMoveVector=latestFrame and latestFrame.moveVector or nil,
        latestMoveDirection=latestFrame and latestFrame.moveDirection or nil,
        latestMoveVectorCameraRelative=latestFrame and latestFrame.moveVectorCameraRelative or nil,
        latestRotationType=latestFrame and latestFrame.rotationType or nil,
        latestAutoRotate=latestFrame and latestFrame.autoRotate or nil,
        latestInMouseLockedMode=latestFrame and latestFrame.inMouseLockedMode or nil,
        latestGetIsMouseLocked=latestFrame and latestFrame.getIsMouseLocked or nil,
        latestMouseLockOffset=latestFrame and (latestFrame.getMouseLockOffset or latestFrame.mouseLockOffset) or nil,
        latestMouseSensitivity=latestFrame and latestFrame.mouseSensitivity or nil,
        latestNativeMouseDelta=latestFrame and latestFrame.nativeMouseDelta or nil,
        latestCameraDistance=latestFrame and round(latestFrame.cameraDistance,4) or nil,
        latestFocusDistance=latestFrame and round(latestFrame.focusDistance,4) or nil,
        evidenceLines=#evidence,
        evidenceDropped=evidenceDropped,
        sampleLines=#sampleLines,
        sampleLinesDropped=sampleLinesDropped,
        usesV604ValidatedRelay=true,
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
        inputScaleCameraTouchesOnly=true,
    }
    phaseSummary("standing",phaseStats.PARADO,result)
    phaseSummary("moving",phaseStats.ANDANDO,result)
    phaseSummary("free",phaseStats.LIVRE,result)
    phaseSummary("relayOff",relayStats.off,result)
    phaseSummary("relayOn",relayStats.on,result)
    scaleSummary("touchRoute",sensitivity.touch,result)
    scaleSummary("mouseRoute",sensitivity.mouse,result)
    scaleSummary("otherRoute",sensitivity.other,result)
    return result
end

local REPORT_KEYS={
    "version","bridgeMode","probePurpose","probeRunning","currentPhase","probeFrames",
    "probeDuration","samplesRecorded","sampleErrors","projectionErrors","inputScalePolls",
    "stateTransitions","nativeScanStatus","nativeTablesVisited","nativeTablesDeduped",
    "nativeFunctionsExamined","nativeConstantsExamined","nativeUpvaluesExamined",
    "nativeUpvalueFunctionsExamined",
    "nativeCandidatesFound","nativeConstantHits","runtimeHookStatus","runtimeHooksInstalled",
    "runtimeHookErrors","runtimeCallSummary","relayEnabled","relayValidationReady",
    "ownershipGateProven","touchRoleConflicts","joystickMouseCrossovers","relayAttempts",
    "relayCompleted","relayErrors","relaySameInputConfirmed","simultaneousJoystickCameraRelayed",
    "callbackErrors","v604FallbackReason","latestCameraYaw","latestCameraPitch","latestRootYaw",
    "latestCameraRootYawDifference","latestRootScreenPoint","latestRootScreenNormalized",
    "latestTorsoScreenPoint","latestMoveVector","latestMoveDirection",
    "latestMoveVectorCameraRelative","latestRotationType","latestAutoRotate",
    "latestInMouseLockedMode","latestGetIsMouseLocked","latestMouseLockOffset",
    "latestMouseSensitivity","latestNativeMouseDelta","latestCameraDistance","latestFocusDistance",
    "standingFrames","standingDuration","standingValidProjectionFrames","standingOnScreenFrames",
    "standingRootScreenSpanX","standingRootScreenSpanY","standingRootNormSpanX",
    "standingRootNormSpanY","standingRootRadiusMeanPx","standingRootRadiusMaxPx",
    "standingScreenStepMeanPx","standingScreenStepMaxPx","standingCameraYawTravelDeg",
    "standingRootYawTravelDeg","standingCameraTurnFrames","standingRootFollowRatio",
    "standingYawGapMeanDeg","standingYawGapMinDeg","standingYawGapMaxDeg",
    "standingMoveMagnitudeMean","standingCameraDistanceMean","standingScreenDriftPerCameraDegree",
    "movingFrames","movingDuration","movingValidProjectionFrames","movingOnScreenFrames",
    "movingRootScreenSpanX","movingRootScreenSpanY","movingRootNormSpanX","movingRootNormSpanY",
    "movingRootRadiusMeanPx","movingRootRadiusMaxPx","movingScreenStepMeanPx",
    "movingScreenStepMaxPx","movingCameraYawTravelDeg","movingRootYawTravelDeg",
    "movingCameraTurnFrames","movingRootFollowRatio","movingYawGapMeanDeg",
    "movingYawGapMinDeg","movingYawGapMaxDeg","movingMoveMagnitudeMean",
    "movingCameraDistanceMean","movingScreenDriftPerCameraDegree",
    "freeFrames","freeDuration","freeValidProjectionFrames","freeOnScreenFrames",
    "freeRootScreenSpanX","freeRootScreenSpanY","freeRootNormSpanX","freeRootNormSpanY",
    "freeRootRadiusMeanPx","freeRootRadiusMaxPx","freeScreenStepMeanPx","freeScreenStepMaxPx",
    "freeCameraYawTravelDeg","freeRootYawTravelDeg","freeCameraTurnFrames","freeRootFollowRatio",
    "freeYawGapMeanDeg","freeYawGapMinDeg","freeYawGapMaxDeg","freeMoveMagnitudeMean",
    "freeCameraDistanceMean","freeScreenDriftPerCameraDegree",
    "relayOffFrames","relayOffDuration","relayOffRootScreenSpanX","relayOffRootScreenSpanY",
    "relayOffRootNormSpanX","relayOffRootNormSpanY","relayOffRootRadiusMeanPx",
    "relayOffScreenStepMeanPx","relayOffCameraYawTravelDeg","relayOffRootYawTravelDeg",
    "relayOffRootFollowRatio","relayOffYawGapMeanDeg","relayOffMoveMagnitudeMean",
    "relayOffScreenDriftPerCameraDegree",
    "relayOnFrames","relayOnDuration","relayOnRootScreenSpanX","relayOnRootScreenSpanY",
    "relayOnRootNormSpanX","relayOnRootNormSpanY","relayOnRootRadiusMeanPx",
    "relayOnScreenStepMeanPx","relayOnCameraYawTravelDeg","relayOnRootYawTravelDeg",
    "relayOnRootFollowRatio","relayOnYawGapMeanDeg","relayOnMoveMagnitudeMean",
    "relayOnScreenDriftPerCameraDegree",
    "touchRouteSamples","touchRouteXCount","touchRouteYCount","touchRouteXRadPerDeltaMean",
    "touchRouteYRadPerDeltaMean","touchRouteXRadPerDeltaMin","touchRouteXRadPerDeltaMax",
    "touchRouteYRadPerDeltaMin","touchRouteYRadPerDeltaMax","touchRouteYOverXRatio",
    "mouseRouteSamples","mouseRouteXCount","mouseRouteYCount","mouseRouteXRadPerDeltaMean",
    "mouseRouteYRadPerDeltaMean","mouseRouteXRadPerDeltaMin","mouseRouteXRadPerDeltaMax",
    "mouseRouteYRadPerDeltaMin","mouseRouteYRadPerDeltaMax","mouseRouteYOverXRatio",
    "evidenceLines","evidenceDropped","sampleLines","sampleLinesDropped",
    "usesV604ValidatedRelay","preservesV604Ownership","usesProcessedAsOwnershipGate",
    "usesHalfScreenGate","usesSyntheticUserInputObject","usesFireSignal","addsVirtualInput",
    "callsUpdateMouseBehavior","writesCameraCFrame","writesRootPartCFrame","forcesAutoRotate",
    "changesSensitivity","changesGain","changesPhysics","appliesScreenSpaceCorrection",
    "fallbackV500Preserved","inputScaleCameraTouchesOnly",
}

getgenv().PCV605Report=function(includeEvidence)
    local diagnostics=getgenv().PCV605Diagnostics()
    local lines={"=== PC MOVEMENT V605 REPORT ==="}
    for _,key in ipairs(REPORT_KEYS) do
        lines[#lines+1]=key.." = "..tostring(diagnostics[key])
    end
    if includeEvidence~=false then
        lines[#lines+1]=""
        lines[#lines+1]="=== PC MOVEMENT V605 NATIVE DISCOVERY ==="
        lines[#lines+1]=diagnostics.nativeCandidateSummary
        lines[#lines+1]=""
        lines[#lines+1]="=== PC MOVEMENT V605 STATE EVIDENCE ==="
        for _,line in ipairs(evidence) do lines[#lines+1]=line end
        lines[#lines+1]=""
        lines[#lines+1]="=== PC MOVEMENT V605 FRAME SAMPLES ==="
        for _,line in ipairs(sampleLines) do lines[#lines+1]=line end
        if type(baseReport)=="function" then
            local ok,baseText=pcall(baseReport,false)
            if ok then
                lines[#lines+1]=""
                lines[#lines+1]=baseText
            end
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
    local environment=getgenv()
    local candidates={environment.setclipboard,environment.toclipboard,setclipboard,toclipboard}
    for _,fn in ipairs(candidates) do
        if type(fn)=="function" then
            local ok=pcall(fn,text)
            if ok then return true,"clipboard" end
        end
    end
    local clipboard=environment.Clipboard
    if type(clipboard)=="table" then
        for _,name in ipairs({"set","Set","setclipboard"}) do
            if type(clipboard[name])=="function" then
                local ok=pcall(clipboard[name],text)
                if ok then return true,"Clipboard."..name end
            end
        end
    end
    return false,"clipboard API unavailable"
end

local function refreshButtons()
    if startButton then
        startButton.Text=probeRunning and "PARAR MEDIÇÃO" or "INICIAR MEDIÇÃO"
        startButton.BackgroundColor3=probeRunning and Color3.fromRGB(245,158,11) or Color3.fromRGB(34,197,94)
    end
    if phaseButton then
        phaseButton.Text="FASE: "..currentPhase
    end
    if relayButton then
        local d=v604DiagnosticsSafe()
        relayButton.Text=d.relayEnabled and "RELAY V604: LIGADO" or "RELAY V604: DESLIGADO"
        relayButton.BackgroundColor3=d.relayEnabled and Color3.fromRGB(139,92,246) or Color3.fromRGB(71,85,105)
    end
end

local function makeButton(parent,textValue,color,order)
    local button=Instance.new("TextButton")
    button.Name="Button"..tostring(order)
    button.LayoutOrder=order
    button.Size=UDim2.new(1,0,0,38)
    button.BackgroundColor3=color
    button.BorderSizePixel=0
    button.Text=textValue
    button.TextColor3=Color3.fromRGB(255,255,255)
    button.TextSize=14
    button.Font=Enum.Font.GothamBold
    button.AutoButtonColor=true
    button.Parent=parent
    local corner=Instance.new("UICorner")
    corner.CornerRadius=UDim.new(0,9)
    corner.Parent=button
    return button
end

local function createMobilePanel()
    local parent=CoreGui
    pcall(function() if gethui then parent=gethui() end end)
    if not parent then return end
    local old=parent:FindFirstChild(UI_NAME)
    if old then old:Destroy() end

    local gui=Instance.new("ScreenGui")
    gui.Name=UI_NAME
    gui.ResetOnSpawn=false
    gui.IgnoreGuiInset=false
    gui.DisplayOrder=999999
    gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    gui.Parent=parent
    screenGui=gui

    local panel=Instance.new("Frame")
    panel.Name="Panel"
    panel.Size=UDim2.fromOffset(310,352)
    panel.Position=UDim2.new(1,-322,0.5,-176)
    panel.BackgroundColor3=Color3.fromRGB(12,18,30)
    panel.BackgroundTransparency=0.06
    panel.BorderSizePixel=0
    panel.Active=true
    panel.Draggable=true
    panel.Parent=gui
    local panelCorner=Instance.new("UICorner")
    panelCorner.CornerRadius=UDim.new(0,14)
    panelCorner.Parent=panel
    local stroke=Instance.new("UIStroke")
    stroke.Color=Color3.fromRGB(56,189,248)
    stroke.Thickness=1.5
    stroke.Transparency=0.18
    stroke.Parent=panel

    local title=Instance.new("TextLabel")
    title.Size=UDim2.new(1,-48,0,34)
    title.Position=UDim2.fromOffset(14,8)
    title.BackgroundTransparency=1
    title.Text="V605 • PC ANCHOR PROBE"
    title.TextColor3=Color3.fromRGB(125,211,252)
    title.TextSize=16
    title.Font=Enum.Font.GothamBold
    title.TextXAlignment=Enum.TextXAlignment.Left
    title.Parent=panel

    local collapse=Instance.new("TextButton")
    collapse.Size=UDim2.fromOffset(30,30)
    collapse.Position=UDim2.new(1,-38,0,8)
    collapse.BackgroundColor3=Color3.fromRGB(30,41,59)
    collapse.BorderSizePixel=0
    collapse.Text="–"
    collapse.TextColor3=Color3.fromRGB(255,255,255)
    collapse.TextSize=20
    collapse.Font=Enum.Font.GothamBold
    collapse.Parent=panel
    local collapseCorner=Instance.new("UICorner")
    collapseCorner.CornerRadius=UDim.new(0,8)
    collapseCorner.Parent=collapse

    local body=Instance.new("Frame")
    body.Name="Body"
    body.Size=UDim2.new(1,-24,1,-50)
    body.Position=UDim2.fromOffset(12,44)
    body.BackgroundTransparency=1
    body.Parent=panel
    local layout=Instance.new("UIListLayout")
    layout.Padding=UDim.new(0,6)
    layout.SortOrder=Enum.SortOrder.LayoutOrder
    layout.Parent=body

    local instructions=Instance.new("TextLabel")
    instructions.LayoutOrder=0
    instructions.Size=UDim2.new(1,0,0,69)
    instructions.BackgroundColor3=Color3.fromRGB(22,32,50)
    instructions.BorderSizePixel=0
    instructions.Text="1) INICIE e arraste a câmera com relay OFF\n2) Faça joystick + câmera para provar ownership\n3) Ligue relay e repita PARADO; depois ANDANDO\n4) Pare e COPIE o relatório (tudo nesta sessão)"
    instructions.TextColor3=Color3.fromRGB(226,232,240)
    instructions.TextSize=11
    instructions.Font=Enum.Font.Gotham
    instructions.TextWrapped=true
    instructions.TextXAlignment=Enum.TextXAlignment.Left
    instructions.Parent=body
    local instructionCorner=Instance.new("UICorner")
    instructionCorner.CornerRadius=UDim.new(0,8)
    instructionCorner.Parent=instructions

    startButton=makeButton(body,"INICIAR MEDIÇÃO",Color3.fromRGB(34,197,94),1)
    phaseButton=makeButton(body,"FASE: PARADO",Color3.fromRGB(14,116,144),2)
    relayButton=makeButton(body,"RELAY V604: DESLIGADO",Color3.fromRGB(71,85,105),3)
    local emergencyButton=makeButton(body,"EMERGÊNCIA • VOLTAR AO V500",Color3.fromRGB(190,24,93),4)
    local copyButton=makeButton(body,"COPIAR REPORT",Color3.fromRGB(2,132,199),5)

    statusLabel=Instance.new("TextLabel")
    statusLabel.LayoutOrder=6
    statusLabel.Size=UDim2.new(1,0,0,30)
    statusLabel.BackgroundTransparency=1
    statusLabel.Text="Pronto. Relay começa desligado."
    statusLabel.TextColor3=Color3.fromRGB(148,163,184)
    statusLabel.TextSize=11
    statusLabel.Font=Enum.Font.Gotham
    statusLabel.TextWrapped=true
    statusLabel.Parent=body

    uiConnections[#uiConnections+1]=startButton.Activated:Connect(function()
        if probeRunning then
            stopProbe()
            setStatus("Medição parada. Agora copie o report.",Color3.fromRGB(250,204,21))
        else
            startProbe()
            setStatus("Medindo "..currentPhase.."… faça o movimento agora.",Color3.fromRGB(74,222,128))
        end
        refreshButtons()
    end)

    uiConnections[#uiConnections+1]=phaseButton.Activated:Connect(function()
        if currentPhase=="PARADO" then currentPhase="ANDANDO"
        elseif currentPhase=="ANDANDO" then currentPhase="LIVRE"
        else currentPhase="PARADO" end
        previousFrame=nil
        addEvidence("PHASE","changed to "..currentPhase)
        setStatus("Fase "..currentPhase.." selecionada.",Color3.fromRGB(125,211,252))
        refreshButtons()
    end)

    uiConnections[#uiConnections+1]=relayButton.Activated:Connect(function()
        local d=v604DiagnosticsSafe()
        if type(baseSetRelay)~="function" then
            setStatus("Relay V604 indisponível; V500 continua ativo.",Color3.fromRGB(251,113,133))
            return
        end
        local want=not d.relayEnabled
        local ok,result,detail=pcall(baseSetRelay,want)
        if not ok then
            setStatus("Erro ao alternar relay; V500 preservado.",Color3.fromRGB(251,113,133))
        elseif result==false then
            setStatus("Relay recusado: faça joystick + câmera juntos primeiro.",Color3.fromRGB(250,204,21))
        else
            setStatus(want and "Relay V604 ligado." or "Relay desligado; V500 ativo.",want and Color3.fromRGB(196,181,253) or Color3.fromRGB(148,163,184))
        end
        previousRelayFrame.off=nil
        previousRelayFrame.on=nil
        addEvidence("UI","relay request="..tostring(want).." result="..cleanText(result,80).." detail="..cleanText(detail,100))
        refreshButtons()
    end)

    uiConnections[#uiConnections+1]=emergencyButton.Activated:Connect(function()
        stopProbe()
        if type(baseSetRelay)=="function" then pcall(baseSetRelay,false) end
        previousRelayFrame.off=nil
        previousRelayFrame.on=nil
        setStatus("EMERGÊNCIA: relay OFF, V500 restaurado.",Color3.fromRGB(251,113,133))
        addEvidence("EMERGENCY","measurement stopped and V604 relay disabled; V500 active")
        refreshButtons()
    end)

    uiConnections[#uiConnections+1]=copyButton.Activated:Connect(function()
        stopProbe()
        refreshButtons()
        local report=getgenv().PCV605Report(true)
        local ok,method=copyToClipboard(report)
        setStatus(ok and "REPORT COPIADO. Pode sair e colar no ChatGPT." or "Clipboard indisponível: "..method,ok and Color3.fromRGB(74,222,128) or Color3.fromRGB(251,113,133))
    end)

    local expanded=true
    uiConnections[#uiConnections+1]=collapse.Activated:Connect(function()
        expanded=not expanded
        body.Visible=expanded
        panel.Size=expanded and UDim2.fromOffset(310,352) or UDim2.fromOffset(310,46)
        collapse.Text=expanded and "–" or "+"
    end)
end

RunService:BindToRenderStep(PRE_BIND,Enum.RenderPriority.Camera.Value-1,function()
    if not probeRunning then return end
    local controller=getActiveCameraController()
    preRotateInput=nil
    if type(controller)=="table" then pcall(function() preRotateInput=rawget(controller,"rotateInput") end) end
end)

RunService:BindToRenderStep(POST_BIND,Enum.RenderPriority.Camera.Value+10,samplePostCamera)

local scanOk,scanError=pcall(scanNativeChain)
if not scanOk then
    nativeScanStatus="error: "..cleanText(scanError,180)
    addEvidence("NATIVE-SCAN",nativeScanStatus)
end
local uiOk,uiError=pcall(createMobilePanel)
if not uiOk then addEvidence("UI","creation-error="..cleanText(uiError,180)) end

getgenv().PCV605Start=function(phase)
    if phase=="PARADO" or phase=="ANDANDO" or phase=="LIVRE" then currentPhase=phase end
    startProbe()
    refreshButtons()
    return true,"probe-started-"..currentPhase
end

getgenv().PCV605Stop=function()
    stopProbe()
    refreshButtons()
    return getgenv().PCV605Report(false)
end

getgenv().PCV605EmergencyV500=function()
    stopProbe()
    if type(baseSetRelay)=="function" then pcall(baseSetRelay,false) end
    refreshButtons()
    return true,"relay-disabled-v500-active"
end

local function restoreRuntimeHooks()
    for index=#runtimeHooks,1,-1 do
        local record=runtimeHooks[index]
        pcall(function() hookfunction(record.target,record.original) end)
    end
    runtimeHooks={}
end

getgenv().__PCMobileAimCleanup=function()
    probeRunning=false
    pcall(function() RunService:UnbindFromRenderStep(PRE_BIND) end)
    pcall(function() RunService:UnbindFromRenderStep(POST_BIND) end)
    for _,connection in ipairs(uiConnections) do pcall(function() connection:Disconnect() end) end
    uiConnections={}
    if screenGui then pcall(function() screenGui:Destroy() end) end
    screenGui=nil
    restoreRuntimeHooks()

    getgenv().PCV605Start=nil
    getgenv().PCV605Stop=nil
    getgenv().PCV605EmergencyV500=nil
    getgenv().PCV605Diagnostics=nil
    getgenv().PCV605Report=nil

    if baseCleanup then pcall(baseCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

addEvidence("READY","V605 observational probe ready; V604 relay starts disabled; mobile panel available")
refreshButtons()
warn("[V605] screen-space/native-chain probe ready | observational only | use the in-game mobile panel")
