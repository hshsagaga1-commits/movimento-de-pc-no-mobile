-- Evade PC Rebuild - Legacy Body View V2
-- PC-style Legacy framing without velocity lag or bounding-box zoom.
-- Keeps Roblox/Evade camera orientation and only adjusts final camera distance
-- using a pitch curve. Collision-aware and Legacy-only.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local ENV=(type(getgenv)=="function" and getgenv()) or _G

local VERSION="EvadePCRebuild-LegacyBody-V2.5-v23-native-outside-soft-pitch-rail"
local LEGACY_PLACE_ID=96537472072550
local BIND_NAME="__EvadePCRebuildLegacyBodyV2"
local HOLE_GUI_NAME="EvadePCLegacyHole1px"

-- Extra distance added to the native camera distance.
-- Level/up ~= native. Moderate look-down exposes more body / "buraco".
-- Extreme look-down comes back toward native instead of endlessly zooming out.
local DOWN_START_DEG=8
local DOWN_PEAK_DEG=38
local DOWN_END_DEG=78
local PEAK_EXTRA_DISTANCE=1.55
local END_EXTRA_DISTANCE=0.18
local MAX_EXTRA_DISTANCE=1.70
local COLLISION_PADDING=0.14
local FIRST_PERSON_DISTANCE=1.45
local EMOTE_TARGET_NORM=Vector2.new(0.50,0.50)
local EMOTE_MIN_DEPTH=0.35
local EMOTE_ENTRY_X_FRAMES=4
local EMOTE_X_GAIN=0.45
local EMOTE_Y_GAIN=0.32
local EMOTE_Y_DEADZONE_PX=7
local EMOTE_MAX_TRANSLATION_PER_FRAME=1.05

local previous=ENV.__EvadePCRebuildLegacyBodyV2Cleanup
if type(previous)=="function" then pcall(previous) end
local previousV1=ENV.__EvadePCRebuildLegacyBodyV1Cleanup
if type(previousV1)=="function" then pcall(previousV1) end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

-- Retire the older velocity-lag Legacy camera experiment if it is still active.
local oldStyle=ENV.__EvadeLegacyPCStyleCamera
if type(oldStyle)=="table" then
    pcall(function()
        if oldStyle.baseCamera and oldStyle.originalGetSubjectPosition
            and oldStyle.baseCamera.GetSubjectPosition==oldStyle.wrapper then
            oldStyle.baseCamera.GetSubjectPosition=oldStyle.originalGetSubjectPosition
        end
    end)
    oldStyle.running=false
    ENV.__EvadeLegacyPCStyleCamera=nil
end

if game.PlaceId~=LEGACY_PLACE_ID then
    local api={
        Version=VERSION,
        Installed=false,
        Reason="wrong-place",
        PlaceId=game.PlaceId,
    }
    ENV.EvadePCRebuildLegacyBodyV2=api
    return api
end

local playerGui=player:WaitForChild("PlayerGui")
local previousHole=playerGui:FindFirstChild(HOLE_GUI_NAME)
if previousHole then previousHole:Destroy() end

local holeGui=Instance.new("ScreenGui")
holeGui.Name=HOLE_GUI_NAME
holeGui.ResetOnSpawn=false
holeGui.IgnoreGuiInset=true
holeGui.DisplayOrder=10040
holeGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
holeGui.Parent=playerGui

local hole=Instance.new("Frame")
hole.Name="Hole1px"
hole.AnchorPoint=Vector2.new(0.5,0.5)
hole.Position=UDim2.fromScale(0.5,0.5)
hole.Size=UDim2.fromOffset(1,1)
hole.BorderSizePixel=0
hole.BackgroundTransparency=0
hole.BackgroundColor3=Color3.new(1,1,1)
hole.ZIndex=100
hole.Parent=holeGui

local enabled=true
local character=nil
local humanoid=nil
local animator=nil
local root=nil
local head=nil
local characterConnection=nil

local playerModule=nil
local cameras=nil
local rayParams=RaycastParams.new()
rayParams.FilterType=Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater=true

local frames=0
local writes=0
local collisionClamps=0
local lastPitch=0
local lastNativeDistance=0
local lastTargetDistance=0
local lastExtra=0
local lastAppliedDelta=0
local activeEmote=false
local lastEmoteTrack=nil
local emoteFrames=0
local emoteCenterWrites=0
local emoteLastErrorPixels=Vector2.zero
local emoteLastTranslation=Vector3.zero
local emoteEntryPitch=nil
local emoteEntryFramesLeft=0
local emoteWasActive=false
local emoteRejectReason=nil

local function attachCharacter(char)
    character=char
    humanoid=char and char:FindFirstChildOfClass("Humanoid") or nil
    animator=humanoid and humanoid:FindFirstChildOfClass("Animator") or nil
    root=char and char:FindFirstChild("HumanoidRootPart") or nil
    head=char and char:FindFirstChild("Head") or nil

    if char then
        if not humanoid then pcall(function() humanoid=char:WaitForChild("Humanoid",6) end) end
        if humanoid and not animator then animator=humanoid:FindFirstChildOfClass("Animator") end
        if not root then pcall(function() root=char:WaitForChild("HumanoidRootPart",6) end) end
        if not head then pcall(function() head=char:WaitForChild("Head",6) end) end
        rayParams.FilterDescendantsInstances={char}
    else
        rayParams.FilterDescendantsInstances={}
    end
end

attachCharacter(player.Character)
characterConnection=player.CharacterAdded:Connect(attachCharacter)

local LOCOMOTION_NAMES={
    idle=true,walk=true,run=true,running=true,jump=true,jumping=true,
    fall=true,falling=true,climb=true,climbing=true,swim=true,swimming=true,
    sit=true,seated=true
}

local NON_EMOTE_ACTION_WORDS={
    "crouch","duck","crawl","slide","lantern","flashlight",
    "equip","unequip","hold","tool","item","carry","use","interact",
    "aim","reload","heal","drink","revive","downed","pickup","grab"
}

local function normalizedTrackName(track)
    local name=""
    pcall(function()
        name=(track.Name or "").." "..((track.Animation and track.Animation.Name) or "")
    end)
    return string.lower(name)
end

local function looksLikeEmoteTrack(track)
    if not track or not track.IsPlaying then return false,"not-playing" end

    local weight=0
    pcall(function() weight=track.WeightCurrent or 0 end)
    if weight<=0.01 then return false,"weight" end

    local name=normalizedTrackName(track)

    -- Explicit emote names are trusted.
    if string.find(name,"emote",1,true)
        or string.find(name,"dance",1,true)
        or string.find(name,"taunt",1,true) then
        return true,nil
    end

    for locomotionName in pairs(LOCOMOTION_NAMES) do
        if string.find(name,locomotionName,1,true) then
            return false,"locomotion"
        end
    end

    for _,word in ipairs(NON_EMOTE_ACTION_WORDS) do
        if string.find(name,word,1,true) then
            return false,"blocked:"..word
        end
    end

    -- Lantern/gear actions must never trigger the emote rail.
    if character and character:FindFirstChildOfClass("Tool") then
        return false,"tool-equipped"
    end

    -- Legacy Evade can expose actual emotes as generic Action tracks.
    local priority=nil
    pcall(function() priority=track.Priority end)
    if priority==Enum.AnimationPriority.Action
        or priority==Enum.AnimationPriority.Action2
        or priority==Enum.AnimationPriority.Action3
        or priority==Enum.AnimationPriority.Action4 then
        return true,nil
    end

    return false,"not-action"
end

local function detectEmote()
    if humanoid and (not animator or animator.Parent~=humanoid) then
        animator=humanoid:FindFirstChildOfClass("Animator")
    end
    if not animator then return false,nil,"animator-missing" end

    local tracks={}
    local ok=pcall(function()
        tracks=animator:GetPlayingAnimationTracks()
    end)
    if not ok then return false,nil,"tracks-failed" end

    local reason="none"
    for _,track in ipairs(tracks) do
        local yes,why=looksLikeEmoteTrack(track)
        if yes then
            return true,normalizedTrackName(track),nil
        end
        if why then reason=why end
    end

    return false,nil,reason
end

local function getPlayerModule()
    if type(playerModule)=="table" then return playerModule end
    local scripts=player:FindFirstChild("PlayerScripts")
    local moduleScript=scripts and scripts:FindFirstChild("PlayerModule")
    if not moduleScript then return nil end
    pcall(function()
        local value=require(moduleScript)
        if type(value)=="table" then playerModule=value end
    end)
    return playerModule
end

local function getCameras()
    if type(cameras)=="table" then return cameras end
    local module=getPlayerModule()
    if type(module)~="table" then return nil end
    pcall(function()
        if type(module.GetCameras)=="function" then
            cameras=module:GetCameras()
        else
            cameras=rawget(module,"cameras")
        end
    end)
    return type(cameras)=="table" and cameras or nil
end

local function getActiveController()
    local cm=getCameras()
    if type(cm)~="table" then return nil end
    local controller=nil
    pcall(function() controller=rawget(cm,"activeCameraController") end)
    if type(controller)~="table" and type(cm.GetActiveCameraController)=="function" then
        pcall(function() controller=cm:GetActiveCameraController() end)
    end
    return type(controller)=="table" and controller or nil
end

local function getNativeDistance(camera)
    local controller=getActiveController()
    local distance=nil

    if controller and type(controller.GetCameraToSubjectDistance)=="function" then
        pcall(function() distance=controller:GetCameraToSubjectDistance() end)
    end

    if type(distance)~="number" or distance<=0 then
        local focus=camera.Focus.Position
        distance=(camera.CFrame.Position-focus).Magnitude
    end

    return math.max(0,distance)
end

local function pitchDegrees(camera)
    local y=math.clamp(camera.CFrame.LookVector.Y,-1,1)
    return math.deg(math.asin(y))
end

local function extraForPitch(pitch)
    -- Roblox look-down has a negative LookVector.Y.
    local down=math.max(0,-pitch)

    if down<=DOWN_START_DEG then
        return 0
    end

    if down<=DOWN_PEAK_DEG then
        local t=(down-DOWN_START_DEG)/(DOWN_PEAK_DEG-DOWN_START_DEG)
        -- Smooth rise without temporal smoothing.
        t=t*t*(3-2*t)
        return PEAK_EXTRA_DISTANCE*t
    end

    if down<DOWN_END_DEG then
        local t=(down-DOWN_PEAK_DEG)/(DOWN_END_DEG-DOWN_PEAK_DEG)
        t=t*t*(3-2*t)
        return PEAK_EXTRA_DISTANCE+(END_EXTRA_DISTANCE-PEAK_EXTRA_DISTANCE)*t
    end

    return END_EXTRA_DISTANCE
end

local function firstPerson(camera,nativeDistance)
    if player.CameraMode==Enum.CameraMode.LockFirstPerson then return true end
    if nativeDistance<=FIRST_PERSON_DISTANCE then return true end
    if head and head.Parent then
        return (camera.CFrame.Position-head.Position).Magnitude<=FIRST_PERSON_DISTANCE
    end
    return false
end

local function withPosition(cf,position)
    return CFrame.fromMatrix(position,cf.XVector,cf.YVector,cf.ZVector)
end

local function resetEmoteRail()
    emoteEntryPitch=nil
    emoteEntryFramesLeft=0
    emoteLastErrorPixels=Vector2.zero
    emoteLastTranslation=Vector3.zero
end

local function applySoftPitchRail(camera,pitch)
    if not head or not head.Parent then return end

    local viewport=camera.ViewportSize
    if viewport.X<=1 or viewport.Y<=1 then return end

    local cf=camera.CFrame
    local localPoint=cf:PointToObjectSpace(head.Position)
    local depth=-localPoint.Z
    if depth<=EMOTE_MIN_DEPTH then return end

    local fov=math.rad(camera.FieldOfView)
    local focal=(viewport.Y*0.5)/math.tan(fov*0.5)
    if focal<=0 then return end

    local point,onScreen=camera:WorldToViewportPoint(head.Position)
    if not onScreen then return end

    if emoteEntryPitch==nil then
        emoteEntryPitch=pitch
        emoteEntryFramesLeft=EMOTE_ENTRY_X_FRAMES
    end

    -- The visible 1px dot is a REFERENCE, not a magnet.
    -- Looking up/down moves the virtual rail away from the dot by the exact
    -- angular camera change, so the character keeps the same framing relation
    -- without being hammered onto screen center.
    local pitchDelta=math.rad(pitch-emoteEntryPitch)
    local targetX=EMOTE_TARGET_NORM.X*viewport.X
    local targetY=(EMOTE_TARGET_NORM.Y*viewport.Y) + focal*math.tan(pitchDelta)
    targetY=math.clamp(targetY,viewport.Y*0.10,viewport.Y*0.90)

    local errorX=point.X-targetX
    local errorY=point.Y-targetY
    emoteLastErrorPixels=Vector2.new(errorX,errorY)

    -- Only center X briefly when the emote begins.
    -- After that the character may slide left/right freely.
    local pxX=0
    if emoteEntryFramesLeft>0 then
        pxX=errorX*EMOTE_X_GAIN
    end

    -- Y is a soft rail with deadzone, never a 1px hard lock.
    local pxY=0
    if math.abs(errorY)>EMOTE_Y_DEADZONE_PX then
        pxY=errorY*EMOTE_Y_GAIN
    end

    local dx=pxX*depth/focal
    local dy=-pxY*depth/focal
    local delta=cf.RightVector*dx + cf.UpVector*dy

    if delta.Magnitude>EMOTE_MAX_TRANSLATION_PER_FRAME then
        delta=delta.Unit*EMOTE_MAX_TRANSLATION_PER_FRAME
    end

    emoteLastTranslation=delta

    if delta.Magnitude>0.0001 then
        camera.CFrame=cf+delta
        camera.Focus=camera.Focus+delta
        emoteCenterWrites+=1
    end

    if emoteEntryFramesLeft>0 then
        emoteEntryFramesLeft-=1
    end
end

local function collisionClamp(anchor,desired)
    local delta=desired-anchor
    if delta.Magnitude<=0.0001 then return desired end

    local hit=nil
    pcall(function()
        hit=Workspace:Raycast(anchor,delta,rayParams)
    end)

    if hit then
        collisionClamps+=1
        local safe=math.max(0,hit.Distance-COLLISION_PADDING)
        return anchor+delta.Unit*safe
    end

    return desired
end

local function shouldRun(camera)
    if not enabled or not camera then return false end
    if camera.CameraType==Enum.CameraType.Scriptable then return false end
    if not character or not humanoid or humanoid.Health<=0 then return false end
    return true
end

RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Camera.Value+3,function()
    frames+=1

    local camera=Workspace.CurrentCamera
    if not shouldRun(camera) then
        activeEmote=false
        emoteWasActive=false
        resetEmoteRail()
        return
    end

    local nativeDistance=getNativeDistance(camera)
    if firstPerson(camera,nativeDistance) then
        activeEmote=false
        emoteWasActive=false
        resetEmoteRail()
        return
    end

    -- EXACT V2.3 no-emote framing path (the version reported good by the user).
    local pitch=pitchDegrees(camera)
    local extra=math.clamp(extraForPitch(pitch),0,MAX_EXTRA_DISTANCE)
    local target=nativeDistance+extra

    lastPitch=pitch
    lastNativeDistance=nativeDistance
    lastTargetDistance=target
    lastExtra=extra
    lastAppliedDelta=0

    if extra>0.001 then
        local anchor=camera.Focus.Position
        local cf=camera.CFrame
        local fromAnchor=cf.Position-anchor
        local currentDistance=fromAnchor.Magnitude

        if currentDistance>0.0001 then
            local direction=fromAnchor.Unit
            local desired=anchor+direction*target
            local finalPosition=collisionClamp(anchor,desired)
            local delta=(finalPosition-cf.Position).Magnitude

            lastAppliedDelta=delta
            if delta>0.001 then
                camera.CFrame=withPosition(cf,finalPosition)
                writes+=1
            end
        end
    end

    local emote,trackName,rejectReason=detectEmote()
    activeEmote=emote
    lastEmoteTrack=trackName
    emoteRejectReason=rejectReason

    if not emote then
        if emoteWasActive then
            resetEmoteRail()
        end
        emoteWasActive=false
        return
    end

    if not emoteWasActive then
        resetEmoteRail()
    end
    emoteWasActive=true
    emoteFrames+=1

    -- Same native Legacy distance stays active; only add the soft emote rail.
    applySoftPitchRail(camera,pitch)
end)

local api={
    Version=VERSION,
    Installed=true,
    SetEnabled=function(value)
        enabled=value~=false
        holeGui.Enabled=enabled
    end,
    IsEnabled=function() return enabled end,
    GetState=function()
        return {
            frames=frames,
            writes=writes,
            collisionClamps=collisionClamps,
            pitchDegrees=lastPitch,
            nativeDistance=lastNativeDistance,
            targetDistance=lastTargetDistance,
            extraDistance=lastExtra,
            lastAppliedDelta=lastAppliedDelta,
            activeEmote=activeEmote,
            lastEmoteTrack=lastEmoteTrack,
            emoteFrames=emoteFrames,
            emoteCenterWrites=emoteCenterWrites,
            emoteTargetNorm=EMOTE_TARGET_NORM,
            emoteTargetPart="Head",
            emoteHoleSizePixels=1,
            emoteMechanic="v23-native-outside/soft-pitch-aware-emote-rail",
            emoteBehavior="outside-identical-v23/entry-x-center/x-free/y-soft/pitch-adaptive",
            emoteRejectReason=emoteRejectReason,
            emoteEntryPitch=emoteEntryPitch,
            emoteEntryFramesLeft=emoteEntryFramesLeft,
            emoteLastErrorPixels=emoteLastErrorPixels,
            emoteLastTranslation=emoteLastTranslation,
            locksWorldMovement=false,
            usesBoundingBox=false,
            usesVelocityLag=false,
            writesOrientation=false,
            writesFOV=false,
        }
    end,
}

ENV.EvadePCRebuildLegacyBodyV2=api
ENV.__EvadePCRebuildLegacyBodyV2Cleanup=function()
    enabled=false
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    if characterConnection then pcall(function() characterConnection:Disconnect() end) end
    pcall(function() holeGui:Destroy() end)
    ENV.EvadePCRebuildLegacyBodyV2=nil
    ENV.__EvadePCRebuildLegacyBodyV2Cleanup=nil
end

return api
