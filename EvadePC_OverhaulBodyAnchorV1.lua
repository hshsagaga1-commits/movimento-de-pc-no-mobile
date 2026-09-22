-- Evade PC - Overhaul Emote Semi-Lock V1.2
-- PC-like framing for Overhaul:
--   * OUTSIDE emote: native Roblox/Evade camera is left alone.
--   * DURING emote: the character HEAD is kept at the screen center.
--   * World movement remains fully free; this only translates the camera so it
--     follows the moving head. It never freezes the character/root in world space.
--
-- This is intentionally NOT a permanent screen lock.
--
-- IMPORTANT:
--   * Overhaul only; never installs in Legacy.
--   * No smoothing / no delayed follow.
--   * Preserves camera rotation, FOV and zoom.
--   * Does not touch joystick, WASD, jump, Grid Assist or sensitivity.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local ENV=(type(getgenv)=="function" and getgenv()) or _G

local VERSION="EvadePC-OverhaulBodyAnchor-V1.3-emote-head-semilock-visible-1px-hole"
local EVADE_GAME_ID=3647333358
local LEGACY_PLACE_ID=96537472072550
local BIND_NAME="__EvadePCOverhaulBodyAnchorV1"
local HOLE_GUI_NAME="EvadePCOverhaulHole1px"

local TARGET_NORM=Vector2.new(0.50,0.50)
local MAX_TRANSLATION_PER_FRAME=3.5
local MIN_CAMERA_DISTANCE=0.85
local MIN_DEPTH=0.35

local old=ENV.__EvadePCOverhaulBodyAnchorV1Cleanup
if type(old)=="function" then pcall(old) end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local playerGui=player:WaitForChild("PlayerGui")
local previousHole=playerGui:FindFirstChild(HOLE_GUI_NAME)
if previousHole then previousHole:Destroy() end

if game.GameId~=EVADE_GAME_ID or game.PlaceId==LEGACY_PLACE_ID then
    local api={Version=VERSION,Installed=false,Reason="not-overhaul",PlaceId=game.PlaceId}
    ENV.EvadePCOverhaulBodyAnchorV1=api
    return api
end

local enabled=true
local character=nil
local humanoid=nil
local animator=nil
local head=nil

local corrections=0
local emoteFrames=0
local nativeFrames=0
local skippedFirstPerson=0
local skippedSubject=0
local lastErrorPixels=Vector2.zero
local lastTranslation=Vector3.zero
local lastEmoteTrack=nil
local activeEmote=false
local connections={}

-- Visible 1x1 px "buraco" at the exact camera target.
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

local LOCOMOTION_NAMES={
    idle=true,walk=true,run=true,running=true,jump=true,jumping=true,
    fall=true,falling=true,climb=true,climbing=true,swim=true,swimming=true,
    sit=true,seated=true
}

local function refreshCharacter(char)
    character=char
    humanoid=char and char:FindFirstChildOfClass("Humanoid") or nil
    animator=humanoid and humanoid:FindFirstChildOfClass("Animator") or nil
    head=char and char:FindFirstChild("Head") or nil
    activeEmote=false
    lastEmoteTrack=nil
end

local function ensureCharacter()
    local char=player.Character
    if char~=character then
        refreshCharacter(char)
    end

    if char then
        if not humanoid or humanoid.Parent~=char then
            humanoid=char:FindFirstChildOfClass("Humanoid")
        end
        if humanoid and (not animator or animator.Parent~=humanoid) then
            animator=humanoid:FindFirstChildOfClass("Animator")
        end
        if not head or head.Parent~=char then
            head=char:FindFirstChild("Head")
        end
    end

    return char and humanoid and head
end

local function subjectBelongsToCharacter(camera)
    local subject=camera.CameraSubject
    if not subject then return false end
    if subject==humanoid or subject==head then return true end
    if typeof(subject)=="Instance" and character and subject:IsDescendantOf(character) then
        return true
    end
    return false
end

local function normalizedTrackName(track)
    local name=""
    pcall(function()
        name=(track.Name or "").." "..((track.Animation and track.Animation.Name) or "")
    end)
    return string.lower(name)
end

local function looksLikeEmoteTrack(track)
    if not track or not track.IsPlaying then return false end

    local weight=0
    pcall(function() weight=track.WeightCurrent or 0 end)
    if weight<=0.01 then return false end

    local name=normalizedTrackName(track)

    -- Explicit emote names always win.
    if string.find(name,"emote",1,true)
        or string.find(name,"dance",1,true)
        or string.find(name,"taunt",1,true) then
        return true
    end

    -- Ignore ordinary locomotion even if a game gives it Action priority.
    for locomotionName in pairs(LOCOMOTION_NAMES) do
        if string.find(name,locomotionName,1,true) then
            return false
        end
    end

    -- Evade/custom emotes commonly run as Action-family tracks. Using the
    -- Action family as a fallback makes the semi-lock work even when the game
    -- exposes only generic AnimationTrack names.
    local priority=nil
    pcall(function() priority=track.Priority end)
    if priority==Enum.AnimationPriority.Action
        or priority==Enum.AnimationPriority.Action2
        or priority==Enum.AnimationPriority.Action3
        or priority==Enum.AnimationPriority.Action4 then
        return true
    end

    return false
end

local function detectEmote()
    if not animator then
        return false,nil
    end

    local tracks={}
    local ok=pcall(function()
        tracks=animator:GetPlayingAnimationTracks()
    end)
    if not ok then return false,nil end

    for _,track in ipairs(tracks) do
        if looksLikeEmoteTrack(track) then
            local name=normalizedTrackName(track)
            return true,name
        end
    end

    return false,nil
end

local function canOperate(camera)
    if not enabled or not camera or camera.CameraType==Enum.CameraType.Scriptable then
        return false
    end
    if not ensureCharacter() or humanoid.Health<=0 then
        return false
    end
    if not subjectBelongsToCharacter(camera) then
        skippedSubject+=1
        return false
    end

    local cameraDistance=(camera.CFrame.Position-camera.Focus.Position).Magnitude
    if cameraDistance<MIN_CAMERA_DISTANCE then
        skippedFirstPerson+=1
        return false
    end

    return true
end

local function centerHead(camera)
    local viewport=camera.ViewportSize
    if viewport.X<=1 or viewport.Y<=1 then return end

    local cf=camera.CFrame
    local localPoint=cf:PointToObjectSpace(head.Position)
    local depth=-localPoint.Z
    if depth<=MIN_DEPTH then return end

    local fov=math.rad(camera.FieldOfView)
    local focal=(viewport.Y*0.5)/math.tan(fov*0.5)
    if focal<=0 then return end

    local targetX=TARGET_NORM.X*viewport.X
    local targetY=TARGET_NORM.Y*viewport.Y

    local desiredX=(targetX-viewport.X*0.5)*depth/focal
    local desiredY=-(targetY-viewport.Y*0.5)*depth/focal

    local dx=localPoint.X-desiredX
    local dy=localPoint.Y-desiredY

    local delta=cf.RightVector*dx + cf.UpVector*dy
    if delta.Magnitude>MAX_TRANSLATION_PER_FRAME then
        delta=delta.Unit*MAX_TRANSLATION_PER_FRAME
    end

    local currentPoint=camera:WorldToViewportPoint(head.Position)
    lastErrorPixels=Vector2.new(currentPoint.X-targetX,currentPoint.Y-targetY)
    lastTranslation=delta

    if delta.Magnitude>0.0001 then
        -- Translate camera + focus together: orientation, FOV and zoom distance
        -- stay native. Because this is recomputed from the CURRENT head position
        -- every frame, the player can move W/A/S/D freely in world space.
        camera.CFrame=cf+delta
        camera.Focus=camera.Focus+delta
        corrections+=1
    end
end

connections[#connections+1]=player.CharacterAdded:Connect(function(char)
    refreshCharacter(char)
end)

refreshCharacter(player.Character)

RunService:BindToRenderStep(
    BIND_NAME,
    Enum.RenderPriority.Camera.Value+3,
    function()
        local camera=Workspace.CurrentCamera
        if not canOperate(camera) then
            activeEmote=false
            return
        end

        local emote,trackName=detectEmote()
        activeEmote=emote
        lastEmoteTrack=trackName

        if not emote then
            -- Critical behavior: outside an emote, DO NOTHING.
            -- The normal character remains outside the center exactly as the
            -- native Overhaul framing puts it.
            nativeFrames+=1
            lastErrorPixels=Vector2.zero
            lastTranslation=Vector3.zero
            return
        end

        emoteFrames+=1
        centerHead(camera)
    end
)

local api={
    Version=VERSION,
    Installed=true,
    SetEnabled=function(value)
        enabled=value~=false
        holeGui.Enabled=enabled
    end,
    GetState=function()
        return {
            enabled=enabled,
            activeEmote=activeEmote,
            lastEmoteTrack=lastEmoteTrack,
            targetNorm=TARGET_NORM,
            targetPart="Head",
            behavior="native-outside-emote/head-center-during-emote",
            corrections=corrections,
            emoteFrames=emoteFrames,
            nativeFrames=nativeFrames,
            skippedFirstPerson=skippedFirstPerson,
            skippedSubject=skippedSubject,
            lastErrorPixels=lastErrorPixels,
            lastTranslation=lastTranslation,
            maxTranslationPerFrame=MAX_TRANSLATION_PER_FRAME,
            writesCameraPosition=true,
            writesCameraRotation=false,
            locksWorldMovement=false,
            usesSmoothing=false,
            affectsLegacy=false,
        }
    end,
}

ENV.EvadePCOverhaulBodyAnchorV1=api
ENV.__EvadePCOverhaulBodyAnchorV1Cleanup=function()
    enabled=false
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

    for _,connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(connections)
    pcall(function() holeGui:Destroy() end)

    ENV.EvadePCOverhaulBodyAnchorV1=nil
    ENV.__EvadePCOverhaulBodyAnchorV1Cleanup=nil
end

return api
