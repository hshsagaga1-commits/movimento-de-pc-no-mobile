-- Evade PC - Overhaul Body Anchor V1
-- Keeps the character's native camera anchor at a stable screen-space point.
-- Designed for PC-like emote hop/dash framing: the camera point stays put while
-- the character animation/body moves around it.
--
-- IMPORTANT:
--   * Overhaul only; never installs in Legacy.
--   * No smoothing / no delayed follow.
--   * Preserves camera rotation, FOV and zoom.
--   * Applies translation only, after Roblox's native camera step.
--   * Does not touch joystick, WASD, jump, Grid Assist or sensitivity.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local ENV=(type(getgenv)=="function" and getgenv()) or _G

local VERSION="EvadePC-OverhaulBodyAnchor-V1-screen-hole-lock"
local EVADE_GAME_ID=3647333358
local LEGACY_PLACE_ID=96537472072550
local BIND_NAME="__EvadePCOverhaulBodyAnchorV1"

local CAPTURE_FRAMES=12
local MAX_TRANSLATION_PER_FRAME=3.0
local MIN_CAMERA_DISTANCE=0.85
local MIN_DEPTH=0.35

local old=ENV.__EvadePCOverhaulBodyAnchorV1Cleanup
if type(old)=="function" then pcall(old) end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

if game.GameId~=EVADE_GAME_ID or game.PlaceId==LEGACY_PLACE_ID then
    local api={Version=VERSION,Installed=false,Reason="not-overhaul",PlaceId=game.PlaceId}
    ENV.EvadePCOverhaulBodyAnchorV1=api
    return api
end

local enabled=true
local character=nil
local humanoid=nil
local root=nil
local targetNorm=nil
local captureCountdown=CAPTURE_FRAMES
local corrections=0
local recaptures=0
local skippedFirstPerson=0
local skippedSubject=0
local lastErrorPixels=Vector2.zero
local lastTranslation=Vector3.zero
local connections={}

local function refreshCharacter(char)
    character=char
    humanoid=char and char:FindFirstChildOfClass("Humanoid") or nil
    root=char and char:FindFirstChild("HumanoidRootPart") or nil
    targetNorm=nil
    captureCountdown=CAPTURE_FRAMES
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
        if not root or root.Parent~=char then
            root=char:FindFirstChild("HumanoidRootPart")
        end
    end

    return char and humanoid and root
end

local function subjectBelongsToCharacter(camera)
    local subject=camera.CameraSubject
    if not subject then return false end
    if subject==humanoid or subject==root then return true end
    if typeof(subject)=="Instance" and character and subject:IsDescendantOf(character) then
        return true
    end
    return false
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

local function captureTarget(camera)
    local viewport=camera.ViewportSize
    if viewport.X<=1 or viewport.Y<=1 then return false end

    local point,onScreen=camera:WorldToViewportPoint(root.Position)
    if not onScreen or point.Z<=MIN_DEPTH then return false end

    targetNorm=Vector2.new(
        math.clamp(point.X/viewport.X,0,1),
        math.clamp(point.Y/viewport.Y,0,1)
    )
    recaptures+=1
    lastErrorPixels=Vector2.zero
    lastTranslation=Vector3.zero
    return true
end

local function applyAnchor(camera)
    local viewport=camera.ViewportSize
    if not targetNorm or viewport.X<=1 or viewport.Y<=1 then return end

    local cf=camera.CFrame
    local localPoint=cf:PointToObjectSpace(root.Position)
    local depth=-localPoint.Z
    if depth<=MIN_DEPTH then return end

    local fov=math.rad(camera.FieldOfView)
    local focal=(viewport.Y*0.5)/math.tan(fov*0.5)
    if focal<=0 then return end

    local targetX=targetNorm.X*viewport.X
    local targetY=targetNorm.Y*viewport.Y

    local desiredX=(targetX-viewport.X*0.5)*depth/focal
    local desiredY=-(targetY-viewport.Y*0.5)*depth/focal

    local dx=localPoint.X-desiredX
    local dy=localPoint.Y-desiredY

    -- Translation only. Rotation and camera distance are left untouched.
    local delta=cf.RightVector*dx + cf.UpVector*dy
    local magnitude=delta.Magnitude
    if magnitude>MAX_TRANSLATION_PER_FRAME then
        delta=delta.Unit*MAX_TRANSLATION_PER_FRAME
    end

    local currentPoint=camera:WorldToViewportPoint(root.Position)
    lastErrorPixels=Vector2.new(currentPoint.X-targetX,currentPoint.Y-targetY)
    lastTranslation=delta

    if delta.Magnitude>0.0001 then
        camera.CFrame=cf+delta
        camera.Focus=camera.Focus+delta
        corrections+=1
    end
end

connections[#connections+1]=player.CharacterAdded:Connect(function(char)
    refreshCharacter(char)
end)

connections[#connections+1]=Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    targetNorm=nil
    captureCountdown=CAPTURE_FRAMES
end)

refreshCharacter(player.Character)

RunService:BindToRenderStep(
    BIND_NAME,
    Enum.RenderPriority.Camera.Value+3,
    function()
        local camera=Workspace.CurrentCamera
        if not canOperate(camera) then return end

        if not targetNorm then
            if captureCountdown>0 then
                captureCountdown-=1
                return
            end
            captureTarget(camera)
            return
        end

        applyAnchor(camera)
    end
)

local api={
    Version=VERSION,
    Installed=true,
    SetEnabled=function(value)
        enabled=value~=false
    end,
    Recapture=function()
        targetNorm=nil
        captureCountdown=CAPTURE_FRAMES
    end,
    GetState=function()
        return {
            enabled=enabled,
            targetNorm=targetNorm,
            captureCountdown=captureCountdown,
            corrections=corrections,
            recaptures=recaptures,
            skippedFirstPerson=skippedFirstPerson,
            skippedSubject=skippedSubject,
            lastErrorPixels=lastErrorPixels,
            lastTranslation=lastTranslation,
            maxTranslationPerFrame=MAX_TRANSLATION_PER_FRAME,
            writesCameraPosition=true,
            writesCameraRotation=false,
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

    ENV.EvadePCOverhaulBodyAnchorV1=nil
    ENV.__EvadePCOverhaulBodyAnchorV1Cleanup=nil
end

return api
