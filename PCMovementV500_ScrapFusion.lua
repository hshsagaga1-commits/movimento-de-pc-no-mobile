local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")

local okVIM,VirtualInputManager=pcall(function()
    return game:GetService("VirtualInputManager")
end)
if not okVIM then VirtualInputManager=nil end

local player=Players.LocalPlayer

local CAMERA_PRE_BIND="__PCMovementV500CameraOnlyPre"
local CAMERA_POST_BIND="__PCMovementV500CameraOnlyPost"
local VIM_BIND="__PCMovementV500VIMKeyboardMirror"
local NORMAL_OFFSET=Vector3.new(2,0.5,0)
local EMOTE_OFFSET=Vector3.zero

--[[
    V500 / SCRAP FUSION

    Base: V20_STABLE, preserving the V15 movement injection, native jump/crouch,
    collision, zoom, FOV and all known-good Legacy behavior.

    Useful pieces taken from the experiments/scripts:
      * V20/V9: real camera controller + shoulder offset + emote zero offset.
      * Universal shift-lock scripts: keep the camera-side lock idea, but REMOVE
        HumanoidRootPart.CFrame writes and REMOVE Humanoid.AutoRotate=false.
      * Keyboard-layout scripts: mirror the joystick's 8 directions as actual
        VirtualInputManager W/A/S/D events so game code can see keyboard input.
      * V26 lesson: do NOT replace touch rotation with a synthetic callback here.
        Native touch camera stays alive; this version isolates the PC-input pieces.

    Important: this version never writes RootPart.CFrame, Camera.CFrame, WalkSpeed,
    AssemblyLinearVelocity or Humanoid.AutoRotate.
]]

-- Load the stable checkpoint first.
local baseSource=game:HttpGet(
    "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV20_STABLE.lua?_cb="
    ..HttpService:GenerateGUID(false),
    true
)
local baseChunk,baseError=loadstring(baseSource)
if not baseChunk then error(baseError) end
baseChunk()

local baseCleanup=getgenv().__PCMobileAimCleanup

-- V20 and V9 both contain camera guards that force CameraRelative. Their movement/camera
-- foundations stay loaded, but V500 owns the final camera-only lock so the character is
-- not dragged into the shift-lock orientation.
pcall(function() RunService:UnbindFromRenderStep("__PCMovementV20NativeHardCenter") end)
pcall(function() RunService:UnbindFromRenderStep("__PCMovementPersistentLock") end)
pcall(function() RunService:UnbindFromRenderStep(CAMERA_PRE_BIND) end)
pcall(function() RunService:UnbindFromRenderStep(CAMERA_POST_BIND) end)
pcall(function() RunService:UnbindFromRenderStep(VIM_BIND) end)

getgenv().PCMovementVersion="V500-ScrapFusion"
getgenv().PCInputBridgeMode="camera-only-shiftlock+vim-keyboard-mirror"
if getgenv().PCV500CameraOnlyLockEnabled==nil then getgenv().PCV500CameraOnlyLockEnabled=true end
if getgenv().PCV500VIMMirrorEnabled==nil then getgenv().PCV500VIMMirrorEnabled=true end

local userGameSettings
local oldRotationType
local oldMouseBehavior
pcall(function()
    userGameSettings=UserSettings():GetService("UserGameSettings")
    oldRotationType=userGameSettings.RotationType
end)
pcall(function() oldMouseBehavior=UserInputService.MouseBehavior end)

local playerModule
local cameras
local controls
local touchController
local savedControllerStates=setmetatable({}, {__mode="k"})
local vimKeys={W=false,A=false,S=false,D=false}
local vimStarted=false
local vimAutoDisabled=false
local vimEvents=0
local lastPreferredInput
pcall(function() lastPreferredInput=UserInputService.PreferredInput end)

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

local function getControls()
    if type(controls)=="table" then return controls end
    local pm=getPlayerModule()
    if type(pm)~="table" then return nil end
    pcall(function()
        if type(pm.GetControls)=="function" then controls=pm:GetControls() end
        if type(controls)~="table" then controls=rawget(pm,"controls") end
    end)
    return controls
end

local function getActiveCameraController()
    local c=getCameras()
    if type(c)~="table" then return nil end
    local controller=rawget(c,"activeCameraController")
    if type(controller)~="table" and type(c.GetActiveCameraController)=="function" then
        pcall(function() controller=c:GetActiveCameraController() end)
    end
    return type(controller)=="table" and controller or nil
end

local function rememberController(controller)
    if type(controller)~="table" or savedControllerStates[controller] then return end
    local state={}
    pcall(function() state.inMouseLockedMode=controller.inMouseLockedMode end)
    pcall(function() state.mouseLockOffset=controller.mouseLockOffset end)
    pcall(function()
        if type(controller.GetIsMouseLocked)=="function" then
            state.methodLocked=controller:GetIsMouseLocked()
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
        if type(controller.SetIsMouseLocked)=="function" and state.methodLocked~=nil then
            controller:SetIsMouseLocked(state.methodLocked)
        elseif state.inMouseLockedMode~=nil then
            controller.inMouseLockedMode=state.inMouseLockedMode
        end
    end)
    pcall(function()
        local offset=state.methodOffset
        if offset==nil then offset=state.mouseLockOffset end
        if offset~=nil and type(controller.SetMouseLockOffset)=="function" then
            controller:SetMouseLockOffset(offset)
        elseif offset~=nil then
            controller.mouseLockOffset=offset
        end
    end)
end

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

local function shouldRelease()
    if getgenv().PCMovementEnabled==false or getgenv().PCV500CameraOnlyLockEnabled==false then
        return true
    end
    local character=player.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health<=0 then return true end
    local platform=false
    pcall(function() platform=humanoid.PlatformStand end)
    if platform then return true end
    local state
    pcall(function() state=humanoid:GetState() end)
    return state==Enum.HumanoidStateType.Dead
        or state==Enum.HumanoidStateType.Physics
        or state==Enum.HumanoidStateType.Ragdoll
        or state==Enum.HumanoidStateType.FallingDown
end

local function forceRotationMovementRelative()
    if not userGameSettings then return end
    pcall(function() userGameSettings.RotationType=Enum.RotationType.MovementRelative end)
    if sethiddenproperty then
        pcall(function() sethiddenproperty(userGameSettings,"RotationType",Enum.RotationType.MovementRelative) end)
    end
end

local function setCameraOnlyLock(controller,enabled,offset)
    if type(controller)~="table" then return end
    rememberController(controller)

    -- Deliberately DO NOT call controller:UpdateMouseBehavior(). That method is the bit that
    -- normally couples shift-lock to CameraRelative character behavior. V500 only wants the
    -- camera controller's locked state + shoulder offset.
    pcall(function()
        if type(controller.SetIsMouseLocked)=="function" then
            controller:SetIsMouseLocked(enabled)
        else
            controller.inMouseLockedMode=enabled
        end
    end)
    pcall(function()
        if type(controller.SetMouseLockOffset)=="function" then
            controller:SetMouseLockOffset(offset)
        else
            controller.mouseLockOffset=offset
        end
    end)
end

local function getAimGui()
    local parent=CoreGui
    pcall(function() if gethui then parent=gethui() end end)
    return parent and parent:FindFirstChild("PCMobileAim") or nil
end

local function touchPreferred()
    local preferred
    local ok=pcall(function() preferred=UserInputService.PreferredInput end)
    if ok and preferred~=nil then return preferred==Enum.PreferredInput.Touch end
    return UserInputService.TouchEnabled
end

local function captureTouchController()
    local c=getControls()
    if type(c)~="table" then return nil end
    if touchPreferred() then
        local active=rawget(c,"activeController")
        if type(active)=="table" and type(active.GetMoveVector)=="function" then
            touchController=active
        end
    end
    return touchController
end

local function rawTouchMoveVector()
    local controller=touchController or captureTouchController()
    local value
    if type(controller)=="table" and type(controller.GetMoveVector)=="function" then
        pcall(function() value=controller:GetMoveVector() end)
    end
    if typeof(value)=="Vector3" then return value end
    local c=getControls()
    if type(c)=="table" and type(c.GetMoveVector)=="function" then
        pcall(function() value=c:GetMoveVector() end)
    end
    return typeof(value)=="Vector3" and value or Vector3.zero
end

local function digitalVector(v)
    if typeof(v)~="Vector3" then return Vector3.zero end
    local magnitude=math.sqrt(v.X*v.X+v.Z*v.Z)
    if magnitude<0.18 then return Vector3.zero end
    local step=math.pi/4
    local angle=math.floor((math.atan2(v.X,-v.Z)/step)+0.5)*step
    return Vector3.new(math.round(math.sin(angle)),0,math.round(-math.cos(angle)))
end

local keyCodes={
    W=Enum.KeyCode.W,
    A=Enum.KeyCode.A,
    S=Enum.KeyCode.S,
    D=Enum.KeyCode.D,
}

local function sendVirtualKey(name,down)
    if vimKeys[name]==down then return true end
    if not VirtualInputManager then return false end
    local ok=pcall(function()
        VirtualInputManager:SendKeyEvent(down,keyCodes[name],false,game)
    end)
    if ok then
        vimKeys[name]=down
        vimStarted=true
        vimEvents+=1
        getgenv().PCV500VIMEvents=vimEvents
    end
    return ok
end

local function releaseVirtualKeys()
    for name,down in pairs(vimKeys) do
        if down then sendVirtualKey(name,false) end
    end
end

local function updateVirtualKeys(v)
    local d=digitalVector(v)
    local wanted={
        W=d.Z<0,
        S=d.Z>0,
        A=d.X<0,
        D=d.X>0,
    }
    for name,down in pairs(wanted) do
        sendVirtualKey(name,down)
    end
end

-- Camera-only shift lock. Offset is applied before Roblox's camera update; MovementRelative
-- is restored after it so the camera gets shift-lock geometry without forcing the character
-- to face the camera. Native touch pan/zoom remains untouched.
RunService:BindToRenderStep(CAMERA_PRE_BIND,Enum.RenderPriority.Camera.Value-2,function()
    local gui=getAimGui()
    if gui then gui.Enabled=getgenv().PCMovementEnabled~=false end

    local controller=getActiveCameraController()
    if not controller then return end
    if shouldRelease() then
        setCameraOnlyLock(controller,false,EMOTE_OFFSET)
        return
    end

    setCameraOnlyLock(controller,true,desiredOffset())
    forceRotationMovementRelative()
end)

RunService:BindToRenderStep(CAMERA_POST_BIND,Enum.RenderPriority.Camera.Value+4,function()
    if shouldRelease() then return end
    forceRotationMovementRelative()
end)

-- Mirror the joystick as actual W/A/S/D events. V15's known-good movement stays responsible
-- for physical movement; this mirror exists so Evade/client scripts that listen specifically
-- for keyboard input can take the same branch they use on PC.
RunService:BindToRenderStep(VIM_BIND,Enum.RenderPriority.Input.Value+1,function()
    if getgenv().PCMovementEnabled==false
        or getgenv().PCV500VIMMirrorEnabled==false
        or vimAutoDisabled
        or not VirtualInputManager then
        releaseVirtualKeys()
        return
    end

    -- If synthetic keys actually make Roblox abandon the touch controller, stop immediately;
    -- this prevents a VIM experiment from destroying the native joystick/UI session.
    if vimStarted then
        local preferred
        pcall(function() preferred=UserInputService.PreferredInput end)
        local c=getControls()
        local currentActive=type(c)=="table" and rawget(c,"activeController") or nil
        if preferred and preferred~=Enum.PreferredInput.Touch then
            vimAutoDisabled=true
            getgenv().PCV500VIMState="disabled-preferredinput-flip"
            releaseVirtualKeys()
            return
        end
        if touchController and currentActive and currentActive~=touchController and preferred==Enum.PreferredInput.Touch then
            -- A controller swap while still Touch can happen legitimately; recapture rather than fail.
            if type(currentActive)=="table" and type(currentActive.GetMoveVector)=="function" then
                touchController=currentActive
            end
        end
    end

    captureTouchController()
    updateVirtualKeys(rawTouchMoveVector())
    getgenv().PCV500VIMState="active"
end)

getgenv().PCV500Diagnostics=function()
    local controller=getActiveCameraController()
    local character=player.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    local result={
        version=getgenv().PCMovementVersion,
        bridgeMode=getgenv().PCInputBridgeMode,
        cameraControllerFound=type(controller)=="table",
        cameraOnlyLockEnabled=getgenv().PCV500CameraOnlyLockEnabled~=false,
        vimAvailable=VirtualInputManager~=nil,
        vimMirrorEnabled=getgenv().PCV500VIMMirrorEnabled~=false,
        vimState=getgenv().PCV500VIMState,
        vimEvents=vimEvents,
        vimAutoDisabled=vimAutoDisabled,
        preferredInput=tostring(UserInputService.PreferredInput),
        touchEnabled=UserInputService.TouchEnabled,
        keyboardEnabled=UserInputService.KeyboardEnabled,
        mouseEnabled=UserInputService.MouseEnabled,
        emoting=isEmoting(),
        desiredOffset=desiredOffset(),
        writesRootPartCFrame=false,
        writesCameraCFrame=false,
        forcesAutoRotate=false,
    }
    if humanoid then pcall(function() result.autoRotate=humanoid.AutoRotate end) end
    if userGameSettings then pcall(function() result.rotationType=tostring(userGameSettings.RotationType) end) end
    if controller then
        pcall(function() result.inMouseLockedMode=controller.inMouseLockedMode end)
        pcall(function() result.mouseLockOffset=controller.mouseLockOffset end)
        pcall(function() result.panEnabled=controller.panEnabled end)
    end
    result.keys={W=vimKeys.W,A=vimKeys.A,S=vimKeys.S,D=vimKeys.D}
    return result
end

getgenv().__PCMobileAimCleanup=function()
    releaseVirtualKeys()
    pcall(function() RunService:UnbindFromRenderStep(CAMERA_PRE_BIND) end)
    pcall(function() RunService:UnbindFromRenderStep(CAMERA_POST_BIND) end)
    pcall(function() RunService:UnbindFromRenderStep(VIM_BIND) end)

    for controller in pairs(savedControllerStates) do
        restoreController(controller)
    end

    if oldRotationType~=nil and userGameSettings then
        pcall(function() userGameSettings.RotationType=oldRotationType end)
    end
    if oldMouseBehavior~=nil then
        pcall(function() UserInputService.MouseBehavior=oldMouseBehavior end)
    end

    getgenv().PCV500Diagnostics=nil
    getgenv().PCV500VIMEvents=nil
    getgenv().PCV500VIMState=nil

    if baseCleanup then pcall(baseCleanup) end
    getgenv().__PCMobileAimCleanup=nil
end

warn("[V500] ScrapFusion loaded | V20 base + camera-only shift lock + VIM W/A/S/D mirror | NO HRP/Camera CFrame writes")
