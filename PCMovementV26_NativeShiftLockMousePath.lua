local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local CoreGui=game:GetService("CoreGui")
local HttpService=game:GetService("HttpService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local BIND_NAME="__PCMovementV26NativeShiftLockGuard"
local NORMAL_OFFSET=Vector3.new(2,0.5,0)
local EMOTE_OFFSET=Vector3.zero
local SHIFT_CURSOR="rbxasset://textures/MouseLockedCursor.png"

-- V26: NATIVE SHIFT-LOCK / NATIVE MOUSE PATH
--
-- The PC references show that the white center mark is the shift-lock mouse cursor itself,
-- not merely a decorative crosshair. V26 therefore stops trying to imitate that state only
-- with a custom dot/rotateInput correction.
--
-- Architecture:
--   V20 stable movement/camera geometry
--     + real activeCameraController mouse-lock state
--     + exact Roblox MouseLockedCursor visual at screen center
--     + emote offset preserved: normal=(2,.5,0), emote=(0,0,0)
--     + camera InputChanged touch branch is intercepted ONLY to suppress its rotation
--     + the SAME native camera InputChanged callback is then called as MouseMovement
--
-- In the successful bridge mode the camera itself receives a mouse event path; V26 does not
-- write Camera.CFrame, RootPart.CFrame, WalkSpeed or physical velocity.

-- Load the known-good checkpoint first. It also cleans any previously running experiment.
local baseSource=game:HttpGet(
    "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV20_STABLE.lua?_cb="
    ..HttpService:GenerateGUID(false),
    true
)
local baseChunk,baseError=loadstring(baseSource)
if not baseChunk then error(baseError) end
baseChunk()

local baseCleanup=getgenv().__PCMobileAimCleanup

getgenv().PCMovementVersion="V26-NativeShiftLockMousePath"
getgenv().PCInputBridgeMode="discovering-native-camera-callback"
getgenv().PCInputBridgeDiscovery="pending"
if getgenv().PCNativeMousePathEnabled==nil then getgenv().PCNativeMousePathEnabled=true end

-- X9 V3 measured the V20/current-session touch angular response. These gains convert a
-- touch pixel into native mouse counts while preserving BOTH V20 axes. This means the first
-- V26 test changes the input/shift-lock semantics, not the camera speed at the same time.
local V20_TOUCH_RAD_X=0.029688168050806058
local V20_TOUCH_RAD_Y=0.010602966305655836
local LEGACY_MOUSE_RAD_X=(math.pi*4)/1920
local LEGACY_MOUSE_RAD_Y=(math.pi*1.9)/1200
local DEFAULT_GAIN_X=V20_TOUCH_RAD_X/LEGACY_MOUSE_RAD_X
local DEFAULT_GAIN_Y=V20_TOUCH_RAD_Y/LEGACY_MOUSE_RAD_Y

if getgenv().PCNativeMouseGainX==nil then getgenv().PCNativeMouseGainX=DEFAULT_GAIN_X end
if getgenv().PCNativeMouseGainY==nil then getgenv().PCNativeMouseGainY=DEFAULT_GAIN_Y end
getgenv().PCNativeMouseDefaultGainX=DEFAULT_GAIN_X
getgenv().PCNativeMouseDefaultGainY=DEFAULT_GAIN_Y

local userGameSettings
pcall(function() userGameSettings=UserSettings():GetService("UserGameSettings") end)

local playerModule
local cameras
local activeController
local activeCameraCallback
local activeCameraCallbackOriginal
local activeConnectionWrapper
local hookRecords={}
local connections={}
local nativeMouseEvents=0
local nativeMouseFailures=0
local discoveryScore=0
local nativeMouseLockController
local nativeMouseLockPrimed=false
local savedControllerStates=setmetatable({}, {__mode="k"})

local function getPlayerModule()
    if type(playerModule)=="table" then return playerModule end
    local ps=player:FindFirstChild("PlayerScripts")
    local pm=ps and ps:FindFirstChild("PlayerModule")
    if not pm then return nil end
    pcall(function()
        local value=require(pm)
        if type(value)=="table" then playerModule=value end
    end)
    return playerModule
end

local function getCameras()
    if type(cameras)=="table" then return cameras end
    local pm=getPlayerModule()
    if type(pm)~="table" then return nil end
    pcall(function()
        if type(pm.GetCameras)=="function" then cameras=pm:GetCameras() end
        if type(cameras)~="table" then cameras=rawget(pm,"cameras") end
    end)
    return cameras
end

local function getActiveController()
    local c=getCameras()
    if type(c)~="table" then return nil end
    local controller=rawget(c,"activeCameraController")
    if type(controller)~="table" and type(c.GetActiveCameraController)=="function" then
        pcall(function() controller=c:GetActiveCameraController() end)
    end
    if type(controller)=="table" then return controller end
    return nil
end

local function rememberController(controller)
    if type(controller)~="table" or savedControllerStates[controller] then return end
    local state={}
    pcall(function() state.inMouseLockedMode=controller.inMouseLockedMode end)
    pcall(function() state.mouseLockOffset=controller.mouseLockOffset end)
    pcall(function() state.panEnabled=controller.panEnabled end)
    pcall(function()
        if type(controller.GetIsMouseLocked)=="function" then
            state.methodMouseLocked=controller:GetIsMouseLocked()
        end
    end)
    pcall(function()
        if type(controller.GetMouseLockOffset)=="function" then
            state.methodOffset=controller:GetMouseLockOffset()
        end
    end)
    savedControllerStates[controller]=state
end

local function restoreController(controller)
    local state=savedControllerStates[controller]
    if not state then return end
    pcall(function()
        if type(controller.SetIsMouseLocked)=="function" and state.methodMouseLocked~=nil then
            controller:SetIsMouseLocked(state.methodMouseLocked)
        elseif state.inMouseLockedMode~=nil then
            controller.inMouseLockedMode=state.inMouseLockedMode
        end
    end)
    pcall(function()
        local offset=state.methodOffset or state.mouseLockOffset
        if type(controller.SetMouseLockOffset)=="function" and offset~=nil then
            controller:SetMouseLockOffset(offset)
        elseif offset~=nil then
            controller.mouseLockOffset=offset
        end
    end)
    pcall(function()
        if state.panEnabled~=nil then controller.panEnabled=state.panEnabled end
    end)
    pcall(function()
        if type(controller.UpdateMouseBehavior)=="function" then controller:UpdateMouseBehavior() end
    end)
end

-- Emote recognition copied from the V9 behavior that already matched the PC references.
local emoteAttributes={
    "IsEmoting","Emoting","EmotePlaying","PlayingEmote","DoingEmote",
    "IsDancing","Dancing","IsTaunting","Taunting",
}

local function hasTruthyAttribute(instance)
    if not instance then return false end
    for _,name in ipairs(emoteAttributes) do
        local ok,value=pcall(function() return instance:GetAttribute(name) end)
        if ok and (value==true or value==1) then return true end
    end
    return false
end

local function trackLooksLikeEmote(track)
    if not track then return false end
    local playing=false
    local weight=0
    local priority
    local looped=false
    local length=0
    local trackName=""
    local animationName=""
    pcall(function() playing=track.IsPlaying end)
    pcall(function() weight=track.WeightCurrent end)
    pcall(function() priority=track.Priority end)
    pcall(function() looped=track.Looped end)
    pcall(function() length=track.Length end)
    pcall(function() trackName=track.Name or "" end)
    pcall(function()
        local animation=track.Animation
        if animation then animationName=animation.Name or "" end
    end)
    if not playing or weight<=0.01 then return false end
    local name=string.lower(trackName.." "..animationName)
    if string.find(name,"emote",1,true)
        or string.find(name,"dance",1,true)
        or string.find(name,"taunt",1,true)
        or string.find(name,"march",1,true)
        or string.find(name,"broom",1,true)
        or string.find(name,"tank",1,true) then
        return true
    end
    local actionPriority=false
    if priority then
        pcall(function() actionPriority=priority.Value>=Enum.AnimationPriority.Action.Value end)
    end
    return actionPriority and ((looped and length>=0.8) or length>=2.5)
end

local function isEmoting()
    local character=player.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    if hasTruthyAttribute(character) or hasTruthyAttribute(humanoid) then return true end
    if not humanoid then return false end
    local tracks
    pcall(function()
        local animator=humanoid:FindFirstChildOfClass("Animator")
        tracks=animator and animator:GetPlayingAnimationTracks() or humanoid:GetPlayingAnimationTracks()
    end)
    if type(tracks)~="table" then return false end
    for _,track in ipairs(tracks) do
        if trackLooksLikeEmote(track) then return true end
    end
    return false
end

local function desiredOffset()
    return isEmoting() and EMOTE_OFFSET or NORMAL_OFFSET
end

-- Replace the old decorative 2x2 frame with Roblox's actual shift-lock cursor texture.
local aimGui
local shiftCursor
local function installShiftCursor()
    local parent=CoreGui
    pcall(function() if gethui then parent=gethui() end end)
    aimGui=parent and parent:FindFirstChild("PCMobileAim") or nil
    if not aimGui then
        aimGui=Instance.new("ScreenGui")
        aimGui.Name="PCMobileAim"
        aimGui.IgnoreGuiInset=true
        aimGui.ResetOnSpawn=false
        aimGui.DisplayOrder=1000000
        aimGui.Parent=parent
    end
    local old=aimGui:FindFirstChild("AimPoint")
    if old then pcall(function() old:Destroy() end) end
    shiftCursor=Instance.new("ImageLabel")
    shiftCursor.Name="AimPoint"
    shiftCursor.AnchorPoint=Vector2.new(0.5,0.5)
    shiftCursor.Position=UDim2.fromScale(0.5,0.5)
    shiftCursor.Size=UDim2.fromOffset(24,24)
    shiftCursor.BackgroundTransparency=1
    shiftCursor.BorderSizePixel=0
    shiftCursor.Image=SHIFT_CURSOR
    shiftCursor.ScaleType=Enum.ScaleType.Fit
    shiftCursor.ZIndex=1000000
    shiftCursor.Parent=aimGui
end
pcall(installShiftCursor)

local function findNativeMouseLockController()
    if type(nativeMouseLockController)=="table" then return nativeMouseLockController end
    local c=getCameras()
    if type(c)~="table" then return nil end
    local direct=rawget(c,"activeMouseLockController")
    if type(direct)=="table" then
        nativeMouseLockController=direct
        return direct
    end
    return nil
end

local function primeNativeMouseLock()
    local c=getCameras()
    local mlc=findNativeMouseLockController()
    if type(mlc)~="table" then return false end
    local changed=false
    pcall(function()
        if type(mlc.EnableMouseLock)=="function" then mlc:EnableMouseLock(true) end
        mlc.enabled=true
    end)
    local locked=false
    pcall(function()
        if type(mlc.GetIsMouseLocked)=="function" then locked=mlc:GetIsMouseLocked()
        else locked=mlc.isMouseLocked==true end
    end)
    if not locked then
        local toggled=false
        pcall(function()
            if type(mlc.OnMouseLockToggled)=="function" then
                mlc:OnMouseLockToggled()
                toggled=true
            end
        end)
        if not toggled then pcall(function() mlc.isMouseLocked=true end) end
        changed=true
    end
    pcall(function()
        if type(c.OnMouseLockToggled)=="function" then c:OnMouseLockToggled() end
    end)
    nativeMouseLockPrimed=true
    getgenv().PCNativeMouseLockControllerFound=true
    return true
end

local function enforceShiftLock(controller)
    if type(controller)~="table" then return false end
    rememberController(controller)
    local offset=desiredOffset()

    -- Use the controller methods first. The raw field writes are only compatibility fallbacks.
    local locked=false
    pcall(function()
        if type(controller.SetIsMouseLocked)=="function" then controller:SetIsMouseLocked(true)
        else controller.inMouseLockedMode=true end
        locked=controller.inMouseLockedMode==true
    end)
    pcall(function()
        if type(controller.SetMouseLockOffset)=="function" then controller:SetMouseLockOffset(offset)
        else controller.mouseLockOffset=offset end
    end)
    pcall(function()
        if type(controller.UpdateMouseBehavior)=="function" then controller:UpdateMouseBehavior() end
    end)
    if userGameSettings then
        pcall(function() userGameSettings.RotationType=Enum.RotationType.CameraRelative end)
    end
    -- iOS may report Default even after this; the controller's logical lock above is authoritative.
    pcall(function() UserInputService.MouseBehavior=Enum.MouseBehavior.LockCenter end)
    if sethiddenproperty then
        pcall(function() sethiddenproperty(UserInputService,"MouseBehavior",Enum.MouseBehavior.LockCenter) end)
    end
    return locked
end

local function safeConnectionFunction(connection)
    local fn
    pcall(function() fn=connection.Function end)
    if type(fn)=="function" then return fn end
    return nil
end

local function connectionEquals(connection,target)
    if connection==target then return true end
    local value
    for _,key in ipairs({"Connection","RBXScriptConnection","connection"}) do
        value=nil
        pcall(function() value=connection[key] end)
        if value~=nil and value==target then return true end
    end
    return false
end

local function safeSource(fn)
    local source=""
    if debug and type(debug.info)=="function" then
        pcall(function() source=debug.info(fn,"s") or "" end)
    elseif debug and type(debug.getinfo)=="function" then
        pcall(function()
            local info=debug.getinfo(fn)
            source=(info and (info.source or info.short_src)) or ""
        end)
    end
    return string.lower(tostring(source))
end

local function getUpvalues(fn)
    if not (debug and type(debug.getupvalues)=="function") then return nil end
    local values
    pcall(function() values=debug.getupvalues(fn) end)
    if type(values)=="table" then return values end
    return nil
end

local function referencesController(fn,controller,depth,seen)
    if type(fn)~="function" or depth<0 then return 0 end
    seen=seen or {}
    if seen[fn] then return 0 end
    seen[fn]=true
    local values=getUpvalues(fn)
    if not values then return 0 end
    local score=0
    for _,value in pairs(values) do
        if value==controller then
            score+=80
        elseif type(value)=="function" and depth>0 then
            score+=math.min(25,referencesController(value,controller,depth-1,seen))
        elseif type(value)=="table" and value==controller then
            score+=80
        end
    end
    return score
end

local function callbackScore(connection,fn,controller)
    local score=0
    local target
    pcall(function() target=controller.inputChangedConn end)
    if target and connectionEquals(connection,target) then score+=1000 end
    score+=referencesController(fn,controller,2,{})
    local source=safeSource(fn)
    if string.find(source,"camera",1,true) then score+=25 end
    if string.find(source,"player",1,true) then score+=5 end
    return score
end

local function cameraTouchIsUnsunk(controller,input,processed)
    if processed then return false end
    local classified
    pcall(function()
        if type(controller.fingerTouches)=="table" then
            classified=controller.fingerTouches[input]
        end
    end)
    if classified~=nil then return classified==false end
    return true
end

local function unsunkTouchCount(controller)
    local n
    pcall(function()
        if type(controller.numUnsunkTouches)=="number" then n=controller.numUnsunkTouches end
    end)
    if n~=nil then return n end
    pcall(function()
        if type(controller.fingerTouches)=="table" then
            local count=0
            for _,processed in pairs(controller.fingerTouches) do
                if processed==false then count+=1 end
            end
            n=count
        end
    end)
    return n
end

local function scaledMouseProxy(input)
    local delta=input.Delta
    local dx=delta and delta.X or 0
    local dy=delta and delta.Y or 0
    local gainX=tonumber(getgenv().PCNativeMouseGainX) or DEFAULT_GAIN_X
    local gainY=tonumber(getgenv().PCNativeMouseGainY) or DEFAULT_GAIN_Y
    return {
        UserInputType=Enum.UserInputType.MouseMovement,
        UserInputState=Enum.UserInputState.Change,
        KeyCode=Enum.KeyCode.Unknown,
        Delta=Vector3.new(dx*gainX,dy*gainY,0),
        Position=Vector3.new(0,0,0),
    }
end

local function restoreActiveHook()
    if activeCameraCallback and activeCameraCallbackOriginal and type(hookfunction)=="function" then
        pcall(function() hookfunction(activeCameraCallback,activeCameraCallbackOriginal) end)
    end
    activeCameraCallback=nil
    activeCameraCallbackOriginal=nil
    activeConnectionWrapper=nil
end

local function installNativeMousePath(controller)
    if type(controller)~="table" then return false end
    if type(getconnections)~="function" or type(hookfunction)~="function" then
        getgenv().PCInputBridgeMode="shift-lock-only-no-hook-capability"
        getgenv().PCInputBridgeDiscovery="missing-getconnections-or-hookfunction"
        return false
    end

    local target
    pcall(function() target=controller.inputChangedConn end)
    local bestConnection,bestFunction,bestScore=nil,nil,-1
    local list
    local ok=pcall(function() list=getconnections(UserInputService.InputChanged) end)
    if not ok or type(list)~="table" then return false end

    for _,connection in ipairs(list) do
        local fn=safeConnectionFunction(connection)
        if fn then
            local score=callbackScore(connection,fn,controller)
            if score>bestScore then
                bestConnection,bestFunction,bestScore=connection,fn,score
            end
        end
    end

    discoveryScore=bestScore
    getgenv().PCNativeMouseDiscoveryScore=bestScore

    -- 80 means either the callback directly/nestedly closes over this controller; 1000 is
    -- exact RBXScriptConnection matching. Do not hook a random UIS connection below this bar.
    if not bestFunction or bestScore<80 then
        getgenv().PCInputBridgeMode="shift-lock-only-safe-fallback"
        getgenv().PCInputBridgeDiscovery="camera-inputchanged-not-proven"
        return false
    end

    if activeCameraCallback==bestFunction and activeCameraCallbackOriginal then return true end
    restoreActiveHook()

    activeCameraCallback=bestFunction
    activeConnectionWrapper=bestConnection

    local original
    local replacement
    replacement=function(input,processed,...)
        if getgenv().PCMovementEnabled==false
            or getgenv().PCNativeMousePathEnabled==false
            or controller~=getActiveController() then
            return original(input,processed,...)
        end

        local inputType
        pcall(function() inputType=input.UserInputType end)
        if inputType~=Enum.UserInputType.Touch then
            return original(input,processed,...)
        end

        -- Let Roblox process the real touch lifecycle/pinch/UI state, but suppress ONLY the
        -- camera rotation from that touch during this exact callback invocation.
        local previousPan=true
        pcall(function()
            if controller.panEnabled~=nil then previousPan=controller.panEnabled end
            controller.panEnabled=false
        end)

        local touchResults=table.pack(pcall(original,input,processed,...))

        pcall(function() controller.panEnabled=previousPan end)

        if not touchResults[1] then
            nativeMouseFailures+=1
            getgenv().PCNativeMouseFailures=nativeMouseFailures
            error(touchResults[2],0)
        end

        -- Only a single unsunk camera finger becomes the virtual captured mouse. Two-finger
        -- touch remains Roblox pinch zoom; joystick/UI touches remain UI/joystick.
        if previousPan~=false
            and cameraTouchIsUnsunk(controller,input,processed)
            and unsunkTouchCount(controller)==1 then
            local d=input.Delta
            if d and (math.abs(d.X)>1e-6 or math.abs(d.Y)>1e-6) then
                local proxy=scaledMouseProxy(input)
                local mouseResults=table.pack(pcall(original,proxy,false))
                if mouseResults[1] then
                    nativeMouseEvents+=1
                    getgenv().PCNativeMouseEvents=nativeMouseEvents
                    getgenv().PCInputBridgeMode="native-camera-mousemovement-callback"
                    getgenv().PCInputBridgeDiscovery="exact-camera-callback-hooked"
                else
                    nativeMouseFailures+=1
                    getgenv().PCNativeMouseFailures=nativeMouseFailures
                    getgenv().PCInputBridgeMode="native-callback-proxy-failed"
                end
            end
        end

        return table.unpack(touchResults,2,touchResults.n)
    end

    local success,old=pcall(function() return hookfunction(bestFunction,replacement) end)
    if not success or type(old)~="function" then
        activeCameraCallback=nil
        activeConnectionWrapper=nil
        getgenv().PCInputBridgeMode="shift-lock-only-hook-failed"
        getgenv().PCInputBridgeDiscovery="hookfunction-failed"
        return false
    end

    original=old
    activeCameraCallbackOriginal=old
    table.insert(hookRecords,{target=bestFunction,original=old})
    getgenv().PCInputBridgeMode="native-camera-callback-hook-installed"
    getgenv().PCInputBridgeDiscovery="score-"..tostring(bestScore)
    return true
end

local lastController=nil
local lastHookAttempt=0
RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Camera.Value-3,function()
    local enabled=getgenv().PCMovementEnabled~=false
    if aimGui then aimGui.Enabled=enabled end
    if not enabled then return end

    if not nativeMouseLockPrimed then pcall(primeNativeMouseLock) end

    local controller=getActiveController()
    if type(controller)~="table" then
        getgenv().PCNativeShiftLockControllerFound=false
        return
    end
    getgenv().PCNativeShiftLockControllerFound=true
    enforceShiftLock(controller)

    if controller~=lastController then
        lastController=controller
        activeController=controller
        restoreActiveHook()
        lastHookAttempt=0
    end

    if not activeCameraCallbackOriginal and os.clock()-lastHookAttempt>0.5 then
        lastHookAttempt=os.clock()
        pcall(function() installNativeMousePath(controller) end)
    end
end)

-- Prime immediately.
activeController=getActiveController()
lastController=activeController
if activeController then
    rememberController(activeController)
    enforceShiftLock(activeController)
    pcall(function() installNativeMousePath(activeController) end)
end
pcall(primeNativeMouseLock)

getgenv().PCV26Diagnostics=function()
    local controller=getActiveController()
    local result={
        version=getgenv().PCMovementVersion,
        bridgeMode=getgenv().PCInputBridgeMode,
        discovery=getgenv().PCInputBridgeDiscovery,
        discoveryScore=discoveryScore,
        controllerFound=type(controller)=="table",
        callbackHooked=activeCameraCallbackOriginal~=nil,
        nativeMouseEvents=nativeMouseEvents,
        nativeMouseFailures=nativeMouseFailures,
        nativeMouseLockControllerFound=type(nativeMouseLockController)=="table",
        gainX=tonumber(getgenv().PCNativeMouseGainX) or DEFAULT_GAIN_X,
        gainY=tonumber(getgenv().PCNativeMouseGainY) or DEFAULT_GAIN_Y,
        emoting=isEmoting(),
        desiredOffset=desiredOffset(),
    }
    if type(controller)=="table" then
        pcall(function() result.inMouseLockedMode=controller.inMouseLockedMode end)
        pcall(function() result.mouseLockOffset=controller.mouseLockOffset end)
        pcall(function() result.panEnabled=controller.panEnabled end)
        pcall(function() result.numUnsunkTouches=controller.numUnsunkTouches end)
    end
    return result
end

getgenv().__PCMobileAimCleanup=function()
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    restoreActiveHook()
    for i=#hookRecords,1,-1 do
        local record=hookRecords[i]
        if record.target and record.original and type(hookfunction)=="function" then
            pcall(function() hookfunction(record.target,record.original) end)
        end
    end
    table.clear(hookRecords)
    for _,connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
    table.clear(connections)
    for controller in pairs(savedControllerStates) do restoreController(controller) end

    getgenv().PCV26Diagnostics=nil
    getgenv().PCNativeMouseEvents=nil
    getgenv().PCNativeMouseFailures=nil
    getgenv().PCNativeMouseDiscoveryScore=nil
    getgenv().PCNativeShiftLockControllerFound=nil
    getgenv().PCNativeMouseLockControllerFound=nil

    if baseCleanup then pcall(baseCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

warn(string.format(
    "[V26] native shift-lock ready | mode=%s | discovery=%s | gains=(%.3f, %.3f)",
    tostring(getgenv().PCInputBridgeMode),
    tostring(getgenv().PCInputBridgeDiscovery),
    tonumber(getgenv().PCNativeMouseGainX) or DEFAULT_GAIN_X,
    tonumber(getgenv().PCNativeMouseGainY) or DEFAULT_GAIN_Y
))
