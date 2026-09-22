-- Evade PC Rebuild - Legacy Emote State V2
-- The PC camera itself stays 100% native.
-- This file only:
--   1) draws the 1px reference dot;
--   2) detects real emotes;
--   3) asks LegacyCameraV2 to cancel the native 1.75-stud shoulder offset
--      while an emote is active, so the character sits on the center reference.
--
-- It NEVER writes Camera.CFrame / Focus / FOV / zoom.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local ENV=(type(getgenv)=="function" and getgenv()) or _G

local VERSION="EvadePCRebuild-LegacyBody-V2.6-native-camera-emote-offset-state"
local LEGACY_PLACE_ID=96537472072550
local BIND_NAME="__EvadePCRebuildLegacyBodyV2"
local HOLE_GUI_NAME="EvadePCLegacyHole1px"

local previous=ENV.__EvadePCRebuildLegacyBodyV2Cleanup
if type(previous)=="function" then pcall(previous) end
local previousV1=ENV.__EvadePCRebuildLegacyBodyV1Cleanup
if type(previousV1)=="function" then pcall(previousV1) end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

if game.PlaceId~=LEGACY_PLACE_ID then
    local api={Version=VERSION,Installed=false,Reason="wrong-place",PlaceId=game.PlaceId}
    ENV.EvadePCRebuildLegacyBodyV2=api
    return api
end

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
local activeEmote=false
local lastEmoteTrack=nil
local lastRejectReason="none"
local frames=0
local emoteFrames=0
local stateTransitions=0

local characterConnection=nil
local crouchButton=nil
local crouchConnection=nil
local crouchObserverRunning=true
local crouchButtonToggle=false

local LOCOMOTION_NAMES={
    idle=true,walk=true,run=true,running=true,jump=true,jumping=true,
    fall=true,falling=true,climb=true,climbing=true,swim=true,swimming=true,
    sit=true,seated=true
}

local NON_EMOTE_WORDS={
    "crouch","crouched","crouching","duck","crawl","slide",
    "lantern","flashlight","equip","unequip","hold","tool","item",
    "carry","use","interact","aim","reload","heal","drink","revive",
    "downed","pickup","grab"
}

local function attachCharacter(char)
    character=char
    humanoid=char and char:FindFirstChildOfClass("Humanoid") or nil
    animator=humanoid and humanoid:FindFirstChildOfClass("Animator") or nil
    activeEmote=false
    lastEmoteTrack=nil
    lastRejectReason="character-reset"
    crouchButtonToggle=false
end

attachCharacter(player.Character)
characterConnection=player.CharacterAdded:Connect(attachCharacter)

local function normalizedTrackName(track)
    local name=""
    pcall(function()
        name=(track.Name or "").." "..((track.Animation and track.Animation.Name) or "")
    end)
    return string.lower(name)
end

local function explicitEmoteName(name)
    return string.find(name,"emote",1,true)
        or string.find(name,"dance",1,true)
        or string.find(name,"taunt",1,true)
end

local function findBoolState(container,name)
    if not container then return nil end
    local direct=container:FindFirstChild(name)
    if direct and direct:IsA("BoolValue") then
        return direct.Value
    end
    local deep=container:FindFirstChild(name,true)
    if deep and deep:IsA("BoolValue") then
        return deep.Value
    end
    return nil
end

local function isCrouching()
    if character then
        for _,name in ipairs({"Crouching","Crouched","IsCrouching"}) do
            local attr=character:GetAttribute(name)
            if type(attr)=="boolean" then
                return attr
            end
            local value=findBoolState(character,name)
            if value~=nil then
                return value
            end
        end
    end

    for _,name in ipairs({"Crouching","Crouched","IsCrouching"}) do
        local attr=player:GetAttribute(name)
        if type(attr)=="boolean" then
            return attr
        end
        local value=findBoolState(player,name)
        if value~=nil then
            return value
        end
    end

    return crouchButtonToggle
end

local function looksLikeEmoteTrack(track)
    if not track or not track.IsPlaying then return false,"not-playing" end

    local weight=0
    pcall(function() weight=track.WeightCurrent or 0 end)
    if weight<=0.01 then return false,"weight" end

    local name=normalizedTrackName(track)

    -- Explicit emote/dance/taunt names always win.
    if explicitEmoteName(name) then
        return true,nil
    end

    for locomotionName in pairs(LOCOMOTION_NAMES) do
        if string.find(name,locomotionName,1,true) then
            return false,"locomotion"
        end
    end

    for _,word in ipairs(NON_EMOTE_WORDS) do
        if string.find(name,word,1,true) then
            return false,"blocked:"..word
        end
    end

    -- Tools and crouch are ordinary character state, never emote centering.
    if character and character:FindFirstChildOfClass("Tool") then
        return false,"tool-equipped"
    end
    if isCrouching() then
        return false,"crouching"
    end

    -- Legacy Evade sometimes exposes its emotes only as Action-family tracks.
    -- We keep that fallback, but only after all ordinary-action guards above.
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
    if character and (not humanoid or humanoid.Parent~=character) then
        humanoid=character:FindFirstChildOfClass("Humanoid")
    end
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

local function findNativeCrouch()
    local hud=playerGui:FindFirstChild("HUD")
    local right=hud and hud:FindFirstChild("Right")
    local mobile=right and right:FindFirstChild("Mobile")
    local crouch=mobile and mobile:FindFirstChild("Crouch")
    if crouch and crouch:IsA("GuiButton") then return crouch end

    for _,obj in ipairs(playerGui:GetDescendants()) do
        if obj.Name=="Crouch" and obj:IsA("GuiButton") then
            return obj
        end
    end
    return nil
end

local function bindCrouchObserver(button)
    if button==crouchButton then return end

    if crouchConnection then
        pcall(function() crouchConnection:Disconnect() end)
        crouchConnection=nil
    end

    crouchButton=button
    if crouchButton then
        -- Observation only. No scale, no animation, no cloned/replaced crouch.
        crouchConnection=crouchButton.Activated:Connect(function()
            crouchButtonToggle=not crouchButtonToggle
        end)
    end
end

task.spawn(function()
    while crouchObserverRunning do
        local found=findNativeCrouch()
        if found~=crouchButton then
            bindCrouchObserver(found)
        elseif crouchButton and not crouchButton.Parent then
            bindCrouchObserver(nil)
        end
        task.wait(0.5)
    end
end)

local function setCameraEmoteState(value)
    local cameraApi=ENV.EvadePCRebuildLegacyCameraV2
    if type(cameraApi)=="table" and type(cameraApi.SetEmoteCentered)=="function" then
        pcall(function()
            cameraApi.SetEmoteCentered(value==true)
        end)
    end
end

-- Detect BEFORE the native CameraModule update.
-- LegacyCameraV2 applies the requested native shoulder offset at Camera-1,
-- then Roblox itself computes the final camera at Camera priority.
RunService:BindToRenderStep(
    BIND_NAME,
    Enum.RenderPriority.Camera.Value-2,
    function()
        frames+=1

        if not enabled or not character or not humanoid or humanoid.Health<=0 then
            if activeEmote then
                activeEmote=false
                stateTransitions+=1
            end
            setCameraEmoteState(false)
            return
        end

        local emote,trackName,rejectReason=detectEmote()
        if emote~=activeEmote then
            stateTransitions+=1
        end

        activeEmote=emote
        lastEmoteTrack=trackName
        lastRejectReason=rejectReason or "none"

        if activeEmote then
            emoteFrames+=1
        end

        setCameraEmoteState(activeEmote)
    end
)

local api={
    Version=VERSION,
    Installed=true,
    SetEnabled=function(value)
        enabled=value~=false
        holeGui.Enabled=enabled
        if not enabled then
            activeEmote=false
            setCameraEmoteState(false)
        end
    end,
    IsEnabled=function() return enabled end,
    GetState=function()
        return {
            enabled=enabled,
            activeEmote=activeEmote,
            lastEmoteTrack=lastEmoteTrack,
            lastRejectReason=lastRejectReason,
            crouchGuard=isCrouching(),
            frames=frames,
            emoteFrames=emoteFrames,
            stateTransitions=stateTransitions,
            holeSizePixels=1,
            cameraMechanic="native-camera-only",
            normalOffset="1.75,0,0",
            emoteOffset="0,0,0",
            writesCameraCFrame=false,
            writesCameraFocus=false,
            writesFOV=false,
            writesZoom=false,
            changesCrouch=false,
        }
    end,
}

ENV.EvadePCRebuildLegacyBodyV2=api
ENV.__EvadePCRebuildLegacyBodyV2Cleanup=function()
    enabled=false
    crouchObserverRunning=false
    activeEmote=false
    setCameraEmoteState(false)

    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    if characterConnection then pcall(function() characterConnection:Disconnect() end) end
    if crouchConnection then pcall(function() crouchConnection:Disconnect() end) end
    pcall(function() holeGui:Destroy() end)

    ENV.EvadePCRebuildLegacyBodyV2=nil
    ENV.__EvadePCRebuildLegacyBodyV2Cleanup=nil
end

return api
