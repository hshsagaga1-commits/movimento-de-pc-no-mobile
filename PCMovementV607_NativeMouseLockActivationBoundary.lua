local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local ContextActionService=game:GetService("ContextActionService")
local HttpService=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")

local player=Players.LocalPlayer
local UI_NAME="PCMovementV607Panel"

--[[
    V607 / NATIVE MOUSE-LOCK ACTIVATION BOUNDARY

    Accepted without re-testing:
      * V604 real-touch ownership/relay and V500 fail-open are proved.
      * V606 proved the downstream mouse-lock focus composition in 1416/1416
        frames (match ratio 1, residual approximately zero).
      * Root yaw, downstream offset composition and sensitivity are not scanned.

    V607 inspects only this boundary:

      platform/input selection
        -> CameraModule constructor / MouseLockController creation
        -> MouseLockController availability, binding, cursor and toggle event
        -> CameraModule.OnMouseLockToggled
        -> active camera controller Update boundary

    No MouseLockController is instantiated by V607. No native toggle callback is
    invoked. The experiment remains blocked unless a missing geometric stage is
    proved; this build contains no such mutation.
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

getgenv().PCMovementVersion="V607-NativeMouseLockActivationBoundary"
getgenv().PCInputBridgeMode="v607-focused-native-activation-trace-over-v604"

local userGameSettings
pcall(function() userGameSettings=UserSettings():GetService("UserGameSettings") end)

local playerModuleScript
local playerModule
local cameraModuleScript
local cameraModule
local controller
local mouseLockScript
local mouseLockClass
local mouseLockRequireStatus="not-attempted"
local inputActionInstance

local targets={}
local targetEvidence={}
local targetMethodsFound=0
local targetMethodsMissing={}
local discoveryStatus="not-started"
local installedHooks={}
local discoveryEvidence={}
local evidenceDropped=0

local probeRunning=false
local probeStartedAt=0
local probeDuration=0
local probeFrames=0
local traceErrors=0
local traceLines={}
local traceDropped=0
local currentFrame=nil

local cameraModuleUpdates=0
local controllerUpdateBoundaryHits=0
local onMouseLockToggledCalls=0
local onPreferredInputChangedCalls=0
local activateCameraControllerCalls=0
local getCameraControlChoiceCalls=0
local getCameraMovementModeCalls=0
local preferredInputChanges=0
local lastInputTypeChanges=0
local lastObservedPreferredInput=nil
local lastObservedInputType=nil
local lastCameraControlChoice=nil
local lastCameraMovementMode=nil
local lastActivationBeforeController=nil
local lastActivationAfterController=nil

local stateAtStart=nil
local stateAtStop=nil
local directChoiceAtStart=nil
local directChoiceAtStop=nil

local experimentEligible=false
local experimentEnabled=false
local experimentAttempts=0
local experimentRejected=0
local experimentReason="blocked-no-missing-geometric-stage-proved"

local screenGui=nil
local statusLabel=nil
local relayButton=nil
local uiConnections={}

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
    if #discoveryEvidence>=240 then
        evidenceDropped+=1
        return
    end
    discoveryEvidence[#discoveryEvidence+1]=string.format(
        "[%03d][%s] %s",#discoveryEvidence+1,section,cleanText(message,1000)
    )
end

local function addTrace(message)
    if #traceLines>=260 then
        traceDropped+=1
        return
    end
    traceLines[#traceLines+1]=message
end

local function packCall(original,...)
    return table.pack(pcall(original,...))
end

local function returnPacked(results)
    if not results[1] then error(results[2],0) end
    return table.unpack(results,2,results.n)
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
    return visit(root,0,"target")
end

local function getConstants(fn)
    local getter=(debug and debug.getconstants) or getconstants
    if type(getter)~="function" then return {},"unavailable" end
    local ok,values=pcall(getter,fn)
    if not ok or type(values)~="table" then return {},"error:"..cleanText(values,100) end
    local output={}
    for _,value in ipairs(values) do
        if (type(value)=="string" or type(value)=="number" or type(value)=="boolean") and #output<100 then
            output[#output+1]=cleanText(value,70)
        end
    end
    return output,"ok"
end

local function valueDetail(value,known)
    for name,knownValue in pairs(known) do
        if value==knownValue then return typeof(value).."="..name end
    end
    local kind=typeof(value)
    if kind=="Instance" then
        local full=cleanText(value,120)
        pcall(function() full=value:GetFullName() end)
        return "Instance:"..full
    end
    if kind=="table" then
        local keys={}
        pcall(function()
            for key in pairs(value) do if #keys<24 then keys[#keys+1]=cleanText(key,55) end end
        end)
        table.sort(keys)
        return "table:{"..table.concat(keys," | ").."}"
    end
    return kind..":"..cleanText(value,140)
end

local function getUpvalues(fn,known)
    local getter=(debug and debug.getupvalues) or getupvalues
    if type(getter)~="function" then return {},"unavailable" end
    local ok,values=pcall(getter,fn)
    if not ok or type(values)~="table" then return {},"error:"..cleanText(values,100) end
    local output={}
    for index,value in pairs(values) do
        if #output<60 then output[#output+1]=tostring(index).."="..valueDetail(value,known) end
    end
    return output,"ok"
end

local function getProtos(fn)
    local getter=(debug and debug.getprotos) or getprotos
    if type(getter)~="function" then return {},"unavailable" end
    local ok,values=pcall(getter,fn)
    if not ok or type(values)~="table" then return {},"error:"..cleanText(values,100) end
    local output={}
    for index,proto in pairs(values) do
        if type(proto)=="function" and #output<24 then
            local constants=getConstants(proto)
            output[#output+1]=tostring(index).."={"..table.concat(constants," | ").."}"
        end
    end
    return output,"ok"
end

local function joinedConstants(id)
    local detail=targetEvidence[id]
    if not detail then return "" end
    return string.lower(table.concat(detail.constants," ").." "..table.concat(detail.protos," "))
end

local function hasToken(id,token)
    return string.find(joinedConstants(id),string.lower(token),1,true)~=nil
end

local function registerTarget(id,root,name,known)
    local target=type(root)=="table" and findMethod(root,name) or nil
    targets[id]=target
    if not target then
        targetMethodsMissing[#targetMethodsMissing+1]=id
        addEvidence("TARGET",id.." missing")
        return
    end
    targetMethodsFound+=1
    local constants,constantStatus=getConstants(target.fn)
    local upvalues,upvalueStatus=getUpvalues(target.fn,known)
    local protos,protoStatus=getProtos(target.fn)
    targetEvidence[id]={
        origin=target.origin,
        constants=constants,
        constantsStatus=constantStatus,
        upvalues=upvalues,
        upvaluesStatus=upvalueStatus,
        protos=protos,
        protosStatus=protoStatus,
    }
    addEvidence("TARGET",string.format(
        "%s origin=%s constants={%s} upvalues={%s} protos={%s}",
        id,target.origin,table.concat(constants," | "),table.concat(upvalues," | "),table.concat(protos," | ")
    ))
end

local function locateRuntimeObjects()
    playerModuleScript=player:FindFirstChild("PlayerScripts")
        and player.PlayerScripts:FindFirstChild("PlayerModule")
    if playerModuleScript then
        pcall(function() playerModule=require(playerModuleScript) end)
        cameraModuleScript=playerModuleScript:FindFirstChild("CameraModule")
    end
    if type(playerModule)=="table" then
        pcall(function()
            if type(playerModule.GetCameras)=="function" then cameraModule=playerModule:GetCameras() end
            if type(cameraModule)~="table" then cameraModule=rawget(playerModule,"cameras") end
        end)
    end
    if type(cameraModule)=="table" then
        controller=rawget(cameraModule,"activeCameraController")
    end
    if cameraModuleScript then
        mouseLockScript=cameraModuleScript:FindFirstChild("MouseLockController")
        inputActionInstance=playerModuleScript:FindFirstChild("MouseLockSwitchAction",true)
        if mouseLockScript and mouseLockScript:IsA("ModuleScript") then
            local ok,value=pcall(require,mouseLockScript)
            if ok and type(value)=="table" then
                mouseLockClass=value
                mouseLockRequireStatus="module-table-obtained-without-calling-new"
            else
                mouseLockRequireStatus="require-failed:"..cleanText(value,160)
            end
        else
            mouseLockRequireStatus="module-script-missing"
        end
    end
end

local TARGET_SPECS={
    {"CameraModule.new","camera","new"},
    {"CameraModule.GetCameraControlChoice","camera","GetCameraControlChoice"},
    {"CameraModule.GetCameraMovementModeFromSettings","camera","GetCameraMovementModeFromSettings"},
    {"CameraModule.OnPreferredInputChanged","camera","OnPreferredInputChanged"},
    {"CameraModule.ActivateCameraController","camera","ActivateCameraController"},
    {"CameraModule.OnMouseLockToggled","camera","OnMouseLockToggled"},
    {"CameraModule.Update","camera","Update"},
    {"Controller.Update","controller","Update"},
    {"MouseLock.new","mouseLock","new"},
    {"MouseLock.UpdateMouseLockAvailability","mouseLock","UpdateMouseLockAvailability"},
    {"MouseLock.EnableMouseLock","mouseLock","EnableMouseLock"},
    {"MouseLock.BindContextActions","mouseLock","BindContextActions"},
    {"MouseLock.UnbindContextActions","mouseLock","UnbindContextActions"},
    {"MouseLock.OnBoundKeysObjectChanged","mouseLock","OnBoundKeysObjectChanged"},
    {"MouseLock.DoMouseLockSwitch","mouseLock","DoMouseLockSwitch"},
    {"MouseLock.OnMouseLockToggled","mouseLock","OnMouseLockToggled"},
    {"MouseLock.GetIsMouseLocked","mouseLock","GetIsMouseLocked"},
    {"MouseLock.GetMouseLockOffset","mouseLock","GetMouseLockOffset"},
    {"MouseLock.GetBindableToggleEvent","mouseLock","GetBindableToggleEvent"},
}

local function discoverFocusedBoundary()
    discoveryStatus="running"
    locateRuntimeObjects()
    local known={
        PlayerModule=playerModule,
        CameraModule=cameraModule,
        ActiveCameraController=controller,
        MouseLockClass=mouseLockClass,
        UserInputService=UserInputService,
        ContextActionService=ContextActionService,
        LocalPlayer=player,
    }
    for _,spec in ipairs(TARGET_SPECS) do
        local root=spec[2]=="camera" and cameraModule
            or spec[2]=="controller" and controller
            or spec[2]=="mouseLock" and mouseLockClass
        registerTarget(spec[1],root,spec[3],known)
    end
    discoveryStatus="complete"
end

local function controllerIdentity(value)
    if type(value)~="table" then return "nil" end
    local name="unknown"
    local method=findMethod(value,"GetModuleName")
    if method then pcall(function() name=method.fn(value) end) end
    return cleanText(value,70).."/"..cleanText(name,60)
end

local function stageRecord(name,phase,detail)
    if not probeRunning then return end
    if currentFrame then
        currentFrame.sequence+=1
        currentFrame.order[#currentFrame.order+1]=name..":"..phase
        if currentFrame.capture then
            addTrace(string.format(
                "F%04d.%02d %s %s %s",currentFrame.id,currentFrame.sequence,name,phase,cleanText(detail,700)
            ))
        end
    else
        addTrace(string.format("OUTSIDE %s %s %s",name,phase,cleanText(detail,700)))
    end
end

local function callerClass()
    if type(checkcaller)~="function" then return "unknown" end
    local ok,value=pcall(checkcaller)
    if not ok then return "unknown" end
    return value and "executor" or "game"
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
    installedHooks[#installedHooks+1]={id=id,target=target.fn,original=old}
    addEvidence("HOOK",id.." installed")
    return true,"installed"
end

local function cameraUpdateFactory(callOriginal)
    return function(self,dt,...)
        if not probeRunning then return callOriginal(self,dt,...) end
        cameraModuleUpdates+=1
        probeFrames+=1
        local frame={
            id=probeFrames,
            sequence=0,
            order={},
            capture=probeFrames<=10 or probeFrames%120==0,
        }
        currentFrame=frame
        stageRecord("CameraModule.Update","enter",string.format(
            "dt=%s PreferredInput=%s LastInputType=%s activeMouseLock=%s controller=%s MouseBehavior=%s",
            cleanText(dt,60),cleanText(UserInputService.PreferredInput,80),cleanText(UserInputService:GetLastInputType(),80),
            tostring(rawget(self,"activeMouseLockController")~=nil),controllerIdentity(rawget(self,"activeCameraController")),
            cleanText(UserInputService.MouseBehavior,80)
        ))
        local results=packCall(callOriginal,self,dt,...)
        stageRecord("CameraModule.Update","exit",string.format(
            "ok=%s activeMouseLock=%s controller=%s MouseBehavior=%s RotationType=%s",
            tostring(results[1]),tostring(rawget(self,"activeMouseLockController")~=nil),
            controllerIdentity(rawget(self,"activeCameraController")),cleanText(UserInputService.MouseBehavior,80),
            cleanText(userGameSettings and userGameSettings.RotationType,80)
        ))
        currentFrame=nil
        if not results[1] then traceErrors+=1 end
        return returnPacked(results)
    end
end

local function boundaryFactory(id,counterName)
    return function(callOriginal)
        return function(self,...)
            if not probeRunning then return callOriginal(self,...) end
            if counterName=="mouseLockToggle" then onMouseLockToggledCalls+=1
            elseif counterName=="preferred" then onPreferredInputChangedCalls+=1
            elseif counterName=="controllerUpdate" then controllerUpdateBoundaryHits+=1 end
            stageRecord(id,"enter","caller="..callerClass())
            local results=packCall(callOriginal,self,...)
            stageRecord(id,"exit","ok="..tostring(results[1]))
            return returnPacked(results)
        end
    end
end

local function choiceFactory(id,kind)
    return function(callOriginal)
        return function(self,...)
            if not probeRunning then return callOriginal(self,...) end
            if kind=="choice" then getCameraControlChoiceCalls+=1 else getCameraMovementModeCalls+=1 end
            stageRecord(id,"enter",string.format(
                "PreferredInput=%s LastInputType=%s TouchEnabled=%s",
                cleanText(UserInputService.PreferredInput,80),cleanText(UserInputService:GetLastInputType(),80),
                tostring(UserInputService.TouchEnabled)
            ))
            local results=packCall(callOriginal,self,...)
            if kind=="choice" then lastCameraControlChoice=results[2] else lastCameraMovementMode=results[2] end
            stageRecord(id,"exit","ok="..tostring(results[1]).." result="..cleanText(results[2],100))
            return returnPacked(results)
        end
    end
end

local function activateFactory(callOriginal)
    return function(self,...)
        if not probeRunning then return callOriginal(self,...) end
        activateCameraControllerCalls+=1
        local before=rawget(self,"activeCameraController")
        lastActivationBeforeController=controllerIdentity(before)
        stageRecord("ActivateCameraController","enter","before="..lastActivationBeforeController)
        local results=packCall(callOriginal,self,...)
        local after=rawget(self,"activeCameraController")
        lastActivationAfterController=controllerIdentity(after)
        controller=after
        stageRecord("ActivateCameraController","exit","ok="..tostring(results[1]).." after="..lastActivationAfterController)
        return returnPacked(results)
    end
end

local function installFocusedHooks()
    local specs={
        {"CameraModule.Update",cameraUpdateFactory},
        {"Controller.Update",boundaryFactory("Controller.Update","controllerUpdate")},
        {"CameraModule.OnMouseLockToggled",boundaryFactory("OnMouseLockToggled","mouseLockToggle")},
        {"CameraModule.OnPreferredInputChanged",boundaryFactory("OnPreferredInputChanged","preferred")},
        {"CameraModule.GetCameraControlChoice",choiceFactory("GetCameraControlChoice","choice")},
        {"CameraModule.GetCameraMovementModeFromSettings",choiceFactory("GetCameraMovementModeFromSettings","movement")},
        {"CameraModule.ActivateCameraController",activateFactory},
    }
    for _,spec in ipairs(specs) do
        local ok,reason=installHook(spec[1],spec[2])
        if not ok then addEvidence("HOOK",spec[1].." rejected="..reason) end
    end
end

local function boundActionSnapshot()
    local result={found=false,name="none",detail="none"}
    local ok,all=pcall(function() return ContextActionService:GetAllBoundActionInfo() end)
    if not ok or type(all)~="table" then
        result.detail="GetAllBoundActionInfo unavailable:"..cleanText(all,100)
        return result
    end
    local count=0
    for name,info in pairs(all) do
        count+=1
        local lower=string.lower(tostring(name))
        if string.find(lower,"mouselock",1,true) or string.find(lower,"shiftlock",1,true) then
            result.found=true
            result.name=tostring(name)
            result.detail=valueDetail(info,{})
            return result
        end
    end
    result.detail="no mouse-lock/shift-lock action among "..tostring(count).." bound actions"
    return result
end

local function inputActionSnapshot()
    local result={found=inputActionInstance~=nil,class="none",enabled=nil}
    if not inputActionInstance then return result end
    result.class=inputActionInstance.ClassName
    pcall(function() result.enabled=inputActionInstance.Enabled end)
    pcall(function() result.active=inputActionInstance.Active end)
    return result
end

local function safeProperty(object,name)
    local value
    pcall(function() value=object[name] end)
    return value
end

local function platformSnapshot()
    locateRuntimeObjects()
    local active=type(cameraModule)=="table" and rawget(cameraModule,"activeMouseLockController") or nil
    local action=boundActionSnapshot()
    local inputAction=inputActionSnapshot()
    local mouseIcon=nil
    pcall(function() mouseIcon=player:GetMouse().Icon end)
    return {
        preferredInput=UserInputService.PreferredInput,
        lastInputType=UserInputService:GetLastInputType(),
        touchEnabled=UserInputService.TouchEnabled,
        keyboardEnabled=UserInputService.KeyboardEnabled,
        mouseEnabled=UserInputService.MouseEnabled,
        mouseBehavior=UserInputService.MouseBehavior,
        rotationType=userGameSettings and safeProperty(userGameSettings,"RotationType") or nil,
        controlMode=userGameSettings and safeProperty(userGameSettings,"ControlMode") or nil,
        computerCameraMovementMode=userGameSettings and safeProperty(userGameSettings,"ComputerCameraMovementMode") or nil,
        touchCameraMovementMode=userGameSettings and safeProperty(userGameSettings,"TouchCameraMovementMode") or nil,
        computerMovementMode=userGameSettings and safeProperty(userGameSettings,"ComputerMovementMode") or nil,
        devEnableMouseLock=safeProperty(player,"DevEnableMouseLock"),
        devComputerCameraMode=safeProperty(player,"DevComputerCameraMode"),
        devTouchCameraMode=safeProperty(player,"DevTouchCameraMode"),
        devComputerMovementMode=safeProperty(player,"DevComputerMovementMode"),
        cameraMode=safeProperty(player,"CameraMode"),
        activeMouseLockController=active,
        activeMouseLockControllerFound=type(active)=="table",
        activeCameraController=controllerIdentity(type(cameraModule)=="table" and rawget(cameraModule,"activeCameraController") or nil),
        boundActionFound=action.found,
        boundActionName=action.name,
        boundActionDetail=action.detail,
        inputActionFound=inputAction.found,
        inputActionClass=inputAction.class,
        inputActionEnabled=inputAction.enabled,
        inputActionActive=inputAction.active,
        mouseIcon=mouseIcon,
        controllerInMouseLockedMode=type(controller)=="table" and rawget(controller,"inMouseLockedMode") or nil,
        controllerMouseLockOffset=type(controller)=="table" and rawget(controller,"mouseLockOffset") or nil,
    }
end

local function evaluateChoices()
    local result={}
    local choice=targets["CameraModule.GetCameraControlChoice"]
    local movement=targets["CameraModule.GetCameraMovementModeFromSettings"]
    if choice and type(cameraModule)=="table" then
        local ok,value=pcall(choice.fn,cameraModule)
        result.controlChoiceOk=ok
        result.controlChoice=value
    end
    if movement and type(cameraModule)=="table" then
        local ok,value=pcall(movement.fn,cameraModule)
        result.movementModeOk=ok
        result.movementMode=value
    end
    return result
end

local GEOMETRY_TOKENS={"cframe","focus","subject","primarypart","humanoidrootpart","toorientation","worldtoviewportpoint"}
local MOUSELOCK_IDS={
    "MouseLock.new","MouseLock.UpdateMouseLockAvailability","MouseLock.EnableMouseLock",
    "MouseLock.BindContextActions","MouseLock.UnbindContextActions","MouseLock.OnBoundKeysObjectChanged",
    "MouseLock.DoMouseLockSwitch","MouseLock.OnMouseLockToggled","MouseLock.GetIsMouseLocked",
    "MouseLock.GetMouseLockOffset","MouseLock.GetBindableToggleEvent",
}

local function mouseLockGeometryEvidence()
    local hits={}
    for _,id in ipairs(MOUSELOCK_IDS) do
        local text=joinedConstants(id)
        for _,token in ipairs(GEOMETRY_TOKENS) do
            if string.find(text,token,1,true) then hits[#hits+1]=id..":"..token end
        end
    end
    return hits
end

local function functionalClassification(state)
    local constructorGate=hasToken("CameraModule.new","touchenabled")
        and hasToken("CameraModule.new","activemouselockcontroller")
        and mouseLockScript~=nil
        and not state.activeMouseLockControllerFound
        and state.touchEnabled==true
    local geometryHits=mouseLockGeometryEvidence()
    local bindingFound=targets["MouseLock.BindContextActions"]~=nil
        or hasToken("MouseLock.EnableMouseLock","bindcontextactions")
        or hasToken("MouseLock.new","mouselockswitchaction")
        or inputActionInstance~=nil
    local toggleEventFound=targets["MouseLock.GetBindableToggleEvent"]~=nil
        or hasToken("MouseLock.OnMouseLockToggled","fire")
    local cursorFound=hasToken("MouseLock.OnMouseLockToggled","cursor")
        or hasToken("MouseLock.OnMouseLockToggled","icon")
    local cameraCallbackText=joinedConstants("CameraModule.OnMouseLockToggled")
    local callbackHasGeometry=false
    for _,token in ipairs(GEOMETRY_TOKENS) do
        if string.find(cameraCallbackText,token,1,true) then callbackHasGeometry=true end
    end
    local stateTransferOnly=targets["CameraModule.OnMouseLockToggled"]~=nil
        and string.find(cameraCallbackText,"getismouselocked",1,true)~=nil
        and not callbackHasGeometry
        and #geometryHits==0
    local divergence
    local answer
    if not constructorGate then
        divergence="constructor-touch-gate-not-proven-in-this-runtime"
        answer="runtime evidence is insufficient to explain activeMouseLockController absence"
    elseif #geometryHits>0 or callbackHasGeometry then
        divergence="unexpected-geometric-token-found-inside-native-mouse-lock-boundary"
        answer="native mouse-lock boundary contains geometry and must be reviewed before any experiment"
    elseif not stateTransferOnly then
        divergence="mouse-lock-callback-not-proven-state-transfer-only"
        answer="callback effects are not yet narrow enough for a safe conclusion"
    elseif state.mouseBehavior==Enum.MouseBehavior.Default then
        divergence="relative-pointer-capture-not-retained-on-touch-mousebehavior-default"
        answer="PC gains Shift binding, cursor/toggle state and real LockCenter relative-pointer capture; lock/offset transfer is already reproduced, so only relative capture remains functionally absent and it does not prove a missing screen-space transform"
    else
        divergence="no-functional-divergence-proved-after-state-transfer"
        answer="MouseLockController adds input/UI state only; no missing camera geometry is proved"
    end
    return {
        constructorTouchGateProven=constructorGate,
        bindingFound=bindingFound,
        toggleEventFound=toggleEventFound,
        cursorFound=cursorFound,
        stateTransferOnly=stateTransferOnly,
        geometryHits=geometryHits,
        firstFunctionalDivergence=divergence,
        answer=answer,
    }
end

local function resetProbe()
    probeDuration=0
    probeFrames=0
    traceErrors=0
    traceLines={}
    traceDropped=0
    currentFrame=nil
    cameraModuleUpdates=0
    controllerUpdateBoundaryHits=0
    onMouseLockToggledCalls=0
    onPreferredInputChangedCalls=0
    activateCameraControllerCalls=0
    getCameraControlChoiceCalls=0
    getCameraMovementModeCalls=0
    preferredInputChanges=0
    lastInputTypeChanges=0
    lastObservedPreferredInput=nil
    lastObservedInputType=nil
    lastCameraControlChoice=nil
    lastCameraMovementMode=nil
    lastActivationBeforeController=nil
    lastActivationAfterController=nil
    stateAtStart=nil
    stateAtStop=nil
    directChoiceAtStart=nil
    directChoiceAtStop=nil
end

local function startProbe()
    resetProbe()
    stateAtStart=platformSnapshot()
    directChoiceAtStart=evaluateChoices()
    probeStartedAt=os.clock()
    probeRunning=true
    addEvidence("PROBE","V607 focused activation-boundary trace started")
end

local function stopProbe()
    if probeRunning then
        probeRunning=false
        probeDuration=os.clock()-probeStartedAt
        stateAtStop=platformSnapshot()
        directChoiceAtStop=evaluateChoices()
        addEvidence("PROBE","stopped duration="..tostring(round(probeDuration,3)))
    elseif not stateAtStop then
        stateAtStop=platformSnapshot()
        directChoiceAtStop=evaluateChoices()
    end
end

local function baseSafe()
    if type(baseDiagnostics)~="function" then return {} end
    local ok,value=pcall(baseDiagnostics)
    return ok and type(value)=="table" and value or {}
end

local function targetSummary()
    local output={}
    for _,spec in ipairs(TARGET_SPECS) do
        local id=spec[1]
        local detail=targetEvidence[id]
        output[#output+1]=detail and (id.."@"..detail.origin) or (id.."@missing")
    end
    return table.concat(output," | ")
end

local function stateValue(state,key)
    return state and state[key] or nil
end

getgenv().PCV607Diagnostics=function()
    local current=platformSnapshot()
    local base=baseSafe()
    local classification=functionalClassification(stateAtStop or current)
    experimentEligible=false
    experimentEnabled=false
    experimentReason="blocked: native MouseLockController adds no missing geometric stage; "..classification.firstFunctionalDivergence
    return {
        version="V607-NativeMouseLockActivationBoundary",
        bridgeMode=getgenv().PCInputBridgeMode,
        probePurpose="prove-first-functional-PC-vs-Touch-difference-before-Controller.Update",
        probeRunning=probeRunning,
        probeFrames=probeFrames,
        probeDuration=round(probeRunning and (os.clock()-probeStartedAt) or probeDuration,3),
        traceErrors=traceErrors,
        discoveryStatus=discoveryStatus,
        targetMethodsFound=targetMethodsFound,
        targetMethodsMissing=table.concat(targetMethodsMissing," | "),
        targetSummary=targetSummary(),
        mouseLockModulePath=cleanText(mouseLockScript,140),
        mouseLockRequireStatus=mouseLockRequireStatus,
        cameraModuleNewConstants=table.concat(targetEvidence["CameraModule.new"] and targetEvidence["CameraModule.new"].constants or {}," | "),
        cameraModuleNewUpvalues=table.concat(targetEvidence["CameraModule.new"] and targetEvidence["CameraModule.new"].upvalues or {}," | "),
        cameraModuleNewProtos=table.concat(targetEvidence["CameraModule.new"] and targetEvidence["CameraModule.new"].protos or {}," | "),
        onMouseLockToggledConstants=table.concat(targetEvidence["CameraModule.OnMouseLockToggled"] and targetEvidence["CameraModule.OnMouseLockToggled"].constants or {}," | "),
        onMouseLockToggledUpvalues=table.concat(targetEvidence["CameraModule.OnMouseLockToggled"] and targetEvidence["CameraModule.OnMouseLockToggled"].upvalues or {}," | "),
        preferredInputStart=stateValue(stateAtStart,"preferredInput"),
        preferredInputStop=stateValue(stateAtStop,"preferredInput"),
        preferredInputCurrent=current.preferredInput,
        lastInputTypeStart=stateValue(stateAtStart,"lastInputType"),
        lastInputTypeStop=stateValue(stateAtStop,"lastInputType"),
        lastInputTypeCurrent=current.lastInputType,
        touchEnabled=current.touchEnabled,
        keyboardEnabled=current.keyboardEnabled,
        mouseEnabled=current.mouseEnabled,
        preferredInputChanges=preferredInputChanges,
        lastInputTypeChanges=lastInputTypeChanges,
        lastObservedPreferredInput=lastObservedPreferredInput,
        lastObservedInputType=lastObservedInputType,
        mouseBehavior=current.mouseBehavior,
        rotationType=current.rotationType,
        controlMode=current.controlMode,
        computerCameraMovementMode=current.computerCameraMovementMode,
        touchCameraMovementMode=current.touchCameraMovementMode,
        computerMovementMode=current.computerMovementMode,
        devEnableMouseLock=current.devEnableMouseLock,
        devComputerCameraMode=current.devComputerCameraMode,
        devTouchCameraMode=current.devTouchCameraMode,
        devComputerMovementMode=current.devComputerMovementMode,
        cameraMode=current.cameraMode,
        directCameraControlChoiceStart=directChoiceAtStart and directChoiceAtStart.controlChoice or nil,
        directCameraControlChoiceStop=directChoiceAtStop and directChoiceAtStop.controlChoice or nil,
        directCameraMovementModeStart=directChoiceAtStart and directChoiceAtStart.movementMode or nil,
        directCameraMovementModeStop=directChoiceAtStop and directChoiceAtStop.movementMode or nil,
        activeMouseLockControllerStart=stateValue(stateAtStart,"activeMouseLockControllerFound"),
        activeMouseLockControllerStop=stateValue(stateAtStop,"activeMouseLockControllerFound"),
        activeMouseLockControllerCurrent=current.activeMouseLockControllerFound,
        activeCameraController=current.activeCameraController,
        controllerInMouseLockedMode=current.controllerInMouseLockedMode,
        controllerMouseLockOffset=current.controllerMouseLockOffset,
        boundMouseLockActionStart=stateValue(stateAtStart,"boundActionFound"),
        boundMouseLockActionStop=stateValue(stateAtStop,"boundActionFound"),
        boundMouseLockActionCurrent=current.boundActionFound,
        boundMouseLockActionName=current.boundActionName,
        boundMouseLockActionDetail=current.boundActionDetail,
        inputActionInstanceFound=current.inputActionFound,
        inputActionInstanceClass=current.inputActionClass,
        inputActionInstanceEnabled=current.inputActionEnabled,
        inputActionInstanceActive=current.inputActionActive,
        mouseIcon=current.mouseIcon,
        cameraModuleUpdates=cameraModuleUpdates,
        controllerUpdateBoundaryHits=controllerUpdateBoundaryHits,
        onMouseLockToggledCalls=onMouseLockToggledCalls,
        onPreferredInputChangedCalls=onPreferredInputChangedCalls,
        activateCameraControllerCalls=activateCameraControllerCalls,
        getCameraControlChoiceCalls=getCameraControlChoiceCalls,
        getCameraMovementModeCalls=getCameraMovementModeCalls,
        lastCameraControlChoice=lastCameraControlChoice,
        lastCameraMovementMode=lastCameraMovementMode,
        lastActivationBeforeController=lastActivationBeforeController,
        lastActivationAfterController=lastActivationAfterController,
        constructorTouchGateProven=classification.constructorTouchGateProven,
        mouseLockBindingEffectFound=classification.bindingFound,
        mouseLockCursorEffectFound=classification.cursorFound,
        mouseLockToggleEventFound=classification.toggleEventFound,
        onMouseLockToggledStateTransferOnly=classification.stateTransferOnly,
        mouseLockGeometryHits=table.concat(classification.geometryHits," | "),
        mouseLockAddsCameraGeometry=#classification.geometryHits>0,
        v606DownstreamCompositionAccepted=true,
        v606CompositionFramesAccepted=1416,
        v606CompositionMatchRatioAccepted=1,
        v606CompositionResidualMaxAccepted=0.0000054,
        mouseLockControllerAbsenceExplainsAnchor=false,
        firstFunctionalDivergence=classification.firstFunctionalDivergence,
        decisiveAnswer=classification.answer,
        validationReady=probeFrames>=30 and traceErrors==0
            and classification.constructorTouchGateProven and classification.stateTransferOnly,
        experimentEligible=experimentEligible,
        experimentEnabled=experimentEnabled,
        experimentAttempts=experimentAttempts,
        experimentRejected=experimentRejected,
        experimentReason=experimentReason,
        relayEnabled=base.relayEnabled,
        relayValidationReady=base.relayValidationReady,
        ownershipGateProven=base.ownershipGateProven,
        touchRoleConflicts=base.touchRoleConflicts,
        joystickMouseCrossovers=base.joystickMouseCrossovers,
        relayErrors=base.relayErrors,
        callbackErrors=base.callbackErrors,
        traceLines=#traceLines,
        traceDropped=traceDropped,
        evidenceLines=#discoveryEvidence,
        evidenceDropped=evidenceDropped,
        instantiatesMouseLockController=false,
        invokesOnMouseLockToggled=false,
        callsUpdateMouseBehavior=false,
        forcesPreferredInput=false,
        forcesMouseBehavior=false,
        forcesRotationType=false,
        writesCameraCFrame=false,
        writesRootPartCFrame=false,
        forcesAutoRotate=false,
        changesSensitivity=false,
        changesGain=false,
        changesPhysics=false,
        usesSyntheticUserInputObject=false,
        usesFireSignal=false,
        addsVirtualInput=false,
        usesProcessedAsOwnershipGate=false,
        usesHalfScreenGate=false,
        preservesV604Ownership=true,
        fallbackV500Preserved=true,
    }
end

local REPORT_KEYS={
    "version","bridgeMode","probePurpose","probeRunning","probeFrames","probeDuration",
    "traceErrors","discoveryStatus","targetMethodsFound","targetMethodsMissing","targetSummary",
    "mouseLockModulePath","mouseLockRequireStatus","cameraModuleNewConstants",
    "cameraModuleNewUpvalues","cameraModuleNewProtos","onMouseLockToggledConstants",
    "onMouseLockToggledUpvalues","preferredInputStart","preferredInputStop",
    "preferredInputCurrent","lastInputTypeStart","lastInputTypeStop","lastInputTypeCurrent",
    "touchEnabled","keyboardEnabled","mouseEnabled","preferredInputChanges",
    "lastInputTypeChanges","lastObservedPreferredInput","lastObservedInputType",
    "mouseBehavior","rotationType","controlMode","computerCameraMovementMode",
    "touchCameraMovementMode","computerMovementMode","devEnableMouseLock",
    "devComputerCameraMode","devTouchCameraMode","devComputerMovementMode","cameraMode",
    "directCameraControlChoiceStart","directCameraControlChoiceStop",
    "directCameraMovementModeStart","directCameraMovementModeStop",
    "activeMouseLockControllerStart","activeMouseLockControllerStop",
    "activeMouseLockControllerCurrent","activeCameraController",
    "controllerInMouseLockedMode","controllerMouseLockOffset","boundMouseLockActionStart",
    "boundMouseLockActionStop","boundMouseLockActionCurrent","boundMouseLockActionName",
    "boundMouseLockActionDetail","inputActionInstanceFound","inputActionInstanceClass",
    "inputActionInstanceEnabled","inputActionInstanceActive","mouseIcon",
    "cameraModuleUpdates","controllerUpdateBoundaryHits","onMouseLockToggledCalls",
    "onPreferredInputChangedCalls","activateCameraControllerCalls",
    "getCameraControlChoiceCalls","getCameraMovementModeCalls","lastCameraControlChoice",
    "lastCameraMovementMode","lastActivationBeforeController","lastActivationAfterController",
    "constructorTouchGateProven","mouseLockBindingEffectFound","mouseLockCursorEffectFound",
    "mouseLockToggleEventFound","onMouseLockToggledStateTransferOnly","mouseLockGeometryHits",
    "mouseLockAddsCameraGeometry","v606DownstreamCompositionAccepted",
    "v606CompositionFramesAccepted","v606CompositionMatchRatioAccepted",
    "v606CompositionResidualMaxAccepted","mouseLockControllerAbsenceExplainsAnchor",
    "firstFunctionalDivergence","decisiveAnswer","validationReady","experimentEligible",
    "experimentEnabled","experimentAttempts","experimentRejected","experimentReason",
    "relayEnabled","relayValidationReady","ownershipGateProven","touchRoleConflicts",
    "joystickMouseCrossovers","relayErrors","callbackErrors","traceLines","traceDropped",
    "evidenceLines","evidenceDropped","instantiatesMouseLockController",
    "invokesOnMouseLockToggled","callsUpdateMouseBehavior","forcesPreferredInput","forcesMouseBehavior",
    "forcesRotationType","writesCameraCFrame","writesRootPartCFrame","forcesAutoRotate",
    "changesSensitivity","changesGain","changesPhysics","usesSyntheticUserInputObject","usesFireSignal",
    "addsVirtualInput","usesProcessedAsOwnershipGate","usesHalfScreenGate",
    "preservesV604Ownership","fallbackV500Preserved",
}

getgenv().PCV607Report=function(includeEvidence)
    local diagnostics=getgenv().PCV607Diagnostics()
    local lines={"=== PC MOVEMENT V607 REPORT ==="}
    for _,key in ipairs(REPORT_KEYS) do lines[#lines+1]=key.." = "..tostring(diagnostics[key]) end
    if includeEvidence~=false then
        lines[#lines+1]=""
        lines[#lines+1]="=== PC MOVEMENT V607 FOCUSED TARGET EVIDENCE ==="
        for _,spec in ipairs(TARGET_SPECS) do
            local id=spec[1]
            local detail=targetEvidence[id]
            if detail then
                lines[#lines+1]=id.." origin="..detail.origin
                lines[#lines+1]="  constants={"..table.concat(detail.constants," | ").."}"
                lines[#lines+1]="  upvalues={"..table.concat(detail.upvalues," | ").."}"
                lines[#lines+1]="  protos={"..table.concat(detail.protos," | ").."}"
            else
                lines[#lines+1]=id.." = missing"
            end
        end
        lines[#lines+1]=""
        lines[#lines+1]="=== PC MOVEMENT V607 PRE-CONTROLLER TRACE ==="
        for _,line in ipairs(traceLines) do lines[#lines+1]=line end
        lines[#lines+1]=""
        lines[#lines+1]="=== PC MOVEMENT V607 EVIDENCE ==="
        for _,line in ipairs(discoveryEvidence) do lines[#lines+1]=line end
        if type(baseReport)=="function" then
            local ok,text=pcall(baseReport,false)
            if ok then lines[#lines+1]=""; lines[#lines+1]=text end
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
    button.Size=UDim2.new(1,0,0,35)
    button.BackgroundColor3=color
    button.BorderSizePixel=0
    button.Text=text
    button.TextColor3=Color3.fromRGB(255,255,255)
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
    stroke.Color=Color3.fromRGB(34,211,238)
    stroke.Thickness=1.5
    stroke.Parent=panel

    local title=Instance.new("TextLabel")
    title.Size=UDim2.new(1,-48,0,34)
    title.Position=UDim2.fromOffset(13,7)
    title.BackgroundTransparency=1
    title.Text="V607 • NATIVE LOCK BOUNDARY"
    title.TextColor3=Color3.fromRGB(103,232,249)
    title.TextSize=14
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
    layout.Padding=UDim.new(0,5)
    layout.SortOrder=Enum.SortOrder.LayoutOrder
    layout.Parent=body

    local instructions=Instance.new("TextLabel")
    instructions.LayoutOrder=0
    instructions.Size=UDim2.new(1,0,0,72)
    instructions.BackgroundColor3=Color3.fromRGB(22,28,45)
    instructions.BorderSizePixel=0
    instructions.Text="1) Faça joystick+câmera e ligue o relay\n2) INICIE e jogue/gire por 20–30 segundos\n3) PARE; experimento deve continuar bloqueado\n4) COPIE antes de sair do Roblox"
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
    local stop=makeButton(body,"PARAR",Color3.fromRGB(245,158,11),2)
    relayButton=makeButton(body,"RELAY V604: DESLIGADO",Color3.fromRGB(71,85,105),3)
    local experiment=makeButton(body,"EXPERIMENTO OPT-IN: BLOQUEADO",Color3.fromRGB(55,65,81),4)
    local disableExperiment=makeButton(body,"DESLIGAR EXPERIMENTO",Color3.fromRGB(71,85,105),5)
    local emergency=makeButton(body,"EMERGÊNCIA • RELAY OFF / V500",Color3.fromRGB(190,24,93),6)
    local copy=makeButton(body,"COPIAR REPORT COMPLETO",Color3.fromRGB(2,132,199),7)
    statusLabel=Instance.new("TextLabel")
    statusLabel.LayoutOrder=8
    statusLabel.Size=UDim2.new(1,0,0,28)
    statusLabel.BackgroundTransparency=1
    statusLabel.Text="Pronto. Nenhuma mutação experimental ativa."
    statusLabel.TextColor3=Color3.fromRGB(148,163,184)
    statusLabel.TextSize=10
    statusLabel.TextWrapped=true
    statusLabel.Font=Enum.Font.Gotham
    statusLabel.Parent=body

    uiConnections[#uiConnections+1]=start.Activated:Connect(function()
        startProbe()
        setStatus("Trace ativo: jogue e gire normalmente.",Color3.fromRGB(74,222,128))
    end)
    uiConnections[#uiConnections+1]=stop.Activated:Connect(function()
        stopProbe()
        setStatus("Trace parado e congelado. Agora copie.",Color3.fromRGB(250,204,21))
    end)
    uiConnections[#uiConnections+1]=relayButton.Activated:Connect(function()
        local base=baseSafe()
        local want=not base.relayEnabled
        if type(baseSetRelay)~="function" then
            setStatus("Relay indisponível; V500 permanece ativo.",Color3.fromRGB(251,113,133))
            return
        end
        local ok,result=pcall(baseSetRelay,want)
        if not ok or result==false then
            setStatus("Relay recusado: prove joystick+câmera juntos.",Color3.fromRGB(250,204,21))
        else
            setStatus(want and "Relay V604 ligado." or "Relay OFF; V500 ativo.",Color3.fromRGB(196,181,253))
        end
        refreshRelayButton()
    end)
    uiConnections[#uiConnections+1]=experiment.Activated:Connect(function()
        experimentAttempts+=1
        experimentRejected+=1
        experimentEligible=false
        experimentEnabled=false
        setStatus("Bloqueado: MouseLockController não contém geometria ausente.",Color3.fromRGB(250,204,21))
        addEvidence("EXPERIMENT","rejected; no missing native geometric stage proved")
    end)
    uiConnections[#uiConnections+1]=disableExperiment.Activated:Connect(function()
        experimentEnabled=false
        setStatus("Experimento OFF. Nenhuma mutação estava ativa.",Color3.fromRGB(148,163,184))
    end)
    uiConnections[#uiConnections+1]=emergency.Activated:Connect(function()
        stopProbe()
        experimentEnabled=false
        if type(baseSetRelay)=="function" then pcall(baseSetRelay,false) end
        setStatus("Emergência: relay OFF; V500 preservado.",Color3.fromRGB(251,113,133))
        refreshRelayButton()
    end)
    uiConnections[#uiConnections+1]=copy.Activated:Connect(function()
        stopProbe()
        local ok=copyToClipboard(getgenv().PCV607Report(true))
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

uiConnections[#uiConnections+1]=UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
    if not probeRunning then return end
    preferredInputChanges+=1
    lastObservedPreferredInput=UserInputService.PreferredInput
    addTrace("EVENT PreferredInput="..cleanText(lastObservedPreferredInput,100))
end)

uiConnections[#uiConnections+1]=UserInputService.LastInputTypeChanged:Connect(function(inputType)
    if not probeRunning then return end
    lastInputTypeChanges+=1
    lastObservedInputType=inputType
    if lastInputTypeChanges<=40 then addTrace("EVENT LastInputType="..cleanText(inputType,100)) end
end)

local discoverOk,discoverError=pcall(discoverFocusedBoundary)
if not discoverOk then
    discoveryStatus="error:"..cleanText(discoverError,180)
    addEvidence("DISCOVERY",discoveryStatus)
else
    local hookOk,hookError=pcall(installFocusedHooks)
    if not hookOk then addEvidence("HOOK","installation-error="..cleanText(hookError,180)) end
end
local uiOk,uiError=pcall(createPanel)
if not uiOk then addEvidence("UI","creation-error="..cleanText(uiError,180)) end

getgenv().PCV607Start=function()
    startProbe()
    return true,"focused-trace-started"
end

getgenv().PCV607Stop=function()
    stopProbe()
    return getgenv().PCV607Report(false)
end

getgenv().PCV607DisableExperiment=function()
    experimentEnabled=false
    return true,"experiment-disabled-no-mutation-active"
end

getgenv().PCV607EmergencyV500=function()
    stopProbe()
    experimentEnabled=false
    if type(baseSetRelay)=="function" then pcall(baseSetRelay,false) end
    refreshRelayButton()
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
    for _,connection in ipairs(uiConnections) do pcall(function() connection:Disconnect() end) end
    uiConnections={}
    if screenGui then pcall(function() screenGui:Destroy() end) end
    screenGui=nil
    restoreHooks()
    getgenv().PCV607Start=nil
    getgenv().PCV607Stop=nil
    getgenv().PCV607DisableExperiment=nil
    getgenv().PCV607EmergencyV500=nil
    getgenv().PCV607Diagnostics=nil
    getgenv().PCV607Report=nil
    if baseCleanup then pcall(baseCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

addEvidence("READY","V607 focused native activation-boundary trace ready; no MouseLockController constructed")
warn("[V607] focused native mouse-lock activation trace ready | observational only | use mobile panel")
