local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local EVADE_GAME_ID=3647333358
local LEGACY_PLACE_ID=96537472072550
local BIND_NAME="__PCEvadeBodyViewV1"

local oldCleanup=getgenv().__PCEvadeBodyViewV1Cleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local mode="off"
if game.GameId==EVADE_GAME_ID then
    mode=(game.PlaceId==LEGACY_PLACE_ID) and "legacy" or "overhaul"
end

-- Overhaul PC reference: first person keeps substantially more of the lower body
-- in frame. We keep the real mobile HUD/input identity and only alter the final
-- rendered camera/body presentation.
local OVERHAUL_BASE_BACK=0.30
local OVERHAUL_DOWN_EXTRA=0.22
local FIRST_PERSON_HEAD_DISTANCE=1.35

-- Legacy PC reference: third person keeps the complete avatar readable instead
-- of letting a tight mobile framing swallow the legs/body. The minimum framing
-- distance is derived from the avatar bounds and vertical FOV, then collision-
-- clamped so the correction never deliberately pushes the camera through a wall.
local LEGACY_MIN_ACTIVE_DISTANCE=2.75
local LEGACY_MIN_FIT_DISTANCE=6.80
local LEGACY_MAX_FIT_DISTANCE=9.20
local LEGACY_FIT_HALF_FOV_FACTOR=0.72
local LEGACY_FIT_PADDING=1.04

local LOWER_BODY_NAMES={
    LowerTorso=true,
    LeftUpperLeg=true,
    LeftLowerLeg=true,
    LeftFoot=true,
    RightUpperLeg=true,
    RightLowerLeg=true,
    RightFoot=true,
    ["Left Leg"]=true,
    ["Right Leg"]=true,
    Torso=true,
}

local character=nil
local humanoid=nil
local head=nil
local root=nil
local characterConn=nil
local savedTransparency={}
local legacyRadiusMax=0
local frames=0
local firstPersonFrames=0
local overhaulRevealFrames=0
local legacyFitFrames=0
local collisionClamps=0
local lastTargetDistance=0
local lastAppliedDistance=0

local rayParams=RaycastParams.new()
rayParams.FilterType=Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater=true

local function restoreForcedVisibility()
    for part,value in pairs(savedTransparency) do
        if typeof(part)=="Instance" and part.Parent and part:IsA("BasePart") then
            pcall(function() part.LocalTransparencyModifier=value end)
        end
    end
    table.clear(savedTransparency)
end

local function bindCharacter(char)
    restoreForcedVisibility()
    character=char
    humanoid=char and char:FindFirstChildOfClass("Humanoid") or nil
    head=char and char:FindFirstChild("Head") or nil
    root=char and char:FindFirstChild("HumanoidRootPart") or nil
    legacyRadiusMax=0
    rayParams.FilterDescendantsInstances=char and {char} or {}

    if char then
        if not humanoid then
            pcall(function() humanoid=char:WaitForChild("Humanoid",5) end)
        end
        if not head then
            pcall(function() head=char:WaitForChild("Head",5) end)
        end
        if not root then
            pcall(function() root=char:WaitForChild("HumanoidRootPart",5) end)
        end
    end
end

bindCharacter(player.Character)
characterConn=player.CharacterAdded:Connect(bindCharacter)

local function forceVisible(predicate)
    if not character then
        restoreForcedVisibility()
        return
    end

    local wanted={}
    for _,obj in ipairs(character:GetDescendants()) do
        if obj:IsA("BasePart") and predicate(obj) then
            wanted[obj]=true
            if savedTransparency[obj]==nil then
                savedTransparency[obj]=obj.LocalTransparencyModifier
            end
            obj.LocalTransparencyModifier=0
        end
    end

    for part,value in pairs(savedTransparency) do
        if not wanted[part] then
            if typeof(part)=="Instance" and part.Parent and part:IsA("BasePart") then
                pcall(function() part.LocalTransparencyModifier=value end)
            end
            savedTransparency[part]=nil
        end
    end
end

local function isFirstPerson(camera)
    if not camera then return false end
    if player.CameraMode==Enum.CameraMode.LockFirstPerson then return true end
    if head and head.Parent then
        return (camera.CFrame.Position-head.Position).Magnitude<=FIRST_PERSON_HEAD_DISTANCE
    end
    return false
end

local function withPosition(cf,newPosition)
    return CFrame.fromMatrix(newPosition,cf.XVector,cf.YVector,cf.ZVector)
end

local function collisionAwarePosition(fromPosition,desiredPosition)
    local delta=desiredPosition-fromPosition
    local magnitude=delta.Magnitude
    if magnitude<=0.0001 then return desiredPosition end

    local hit=nil
    pcall(function() hit=Workspace:Raycast(fromPosition,delta,rayParams) end)
    if hit then
        collisionClamps+=1
        local safeDistance=math.max(0,hit.Distance-0.12)
        return fromPosition+delta.Unit*safeDistance
    end
    return desiredPosition
end

local function overhaulStep(camera)
    if not isFirstPerson(camera) then
        restoreForcedVisibility()
        return
    end

    firstPersonFrames+=1
    forceVisible(function(part)
        return LOWER_BODY_NAMES[part.Name]==true
    end)

    local cf=camera.CFrame
    local downFactor=math.clamp((-cf.LookVector.Y-0.05)/0.85,0,1)
    local back=OVERHAUL_BASE_BACK+OVERHAUL_DOWN_EXTRA*downFactor
    local desired=cf.Position-cf.LookVector*back
    local finalPosition=collisionAwarePosition(cf.Position,desired)
    local applied=(finalPosition-cf.Position).Magnitude

    if applied>0.001 then
        camera.CFrame=withPosition(cf,finalPosition)
        overhaulRevealFrames+=1
        lastAppliedDistance=applied
    end
end

local function legacyTargetDistance(camera)
    if not character then return LEGACY_MIN_FIT_DISTANCE,nil end

    local boxCF,boxSize=nil,nil
    local ok=pcall(function() boxCF,boxSize=character:GetBoundingBox() end)
    if not ok or not boxCF or not boxSize then
        local center=root and root.Position or (head and head.Position) or nil
        return LEGACY_MIN_FIT_DISTANCE,center
    end

    local radius=0.5*math.sqrt(boxSize.X*boxSize.X+boxSize.Y*boxSize.Y+boxSize.Z*boxSize.Z)
    legacyRadiusMax=math.max(legacyRadiusMax,radius)

    local fov=math.clamp(camera.FieldOfView,45,95)
    local halfFov=math.rad(fov*0.5)
    local fitHalfAngle=math.max(math.rad(18),halfFov*LEGACY_FIT_HALF_FOV_FACTOR)
    local fit=(legacyRadiusMax/math.tan(fitHalfAngle))*LEGACY_FIT_PADDING
    local target=math.clamp(fit,LEGACY_MIN_FIT_DISTANCE,LEGACY_MAX_FIT_DISTANCE)
    return target,boxCF.Position
end

local function legacyStep(camera)
    if isFirstPerson(camera) then
        firstPersonFrames+=1
        restoreForcedVisibility()
        return
    end

    forceVisible(function(part)
        return part.Name~="HumanoidRootPart"
    end)

    local target,center=legacyTargetDistance(camera)
    lastTargetDistance=target
    if not center then return end

    local cf=camera.CFrame
    local fromCenter=cf.Position-center
    local distance=fromCenter.Magnitude
    if distance<LEGACY_MIN_ACTIVE_DISTANCE or distance>=target or distance<=0.0001 then
        return
    end

    local desired=cf.Position+fromCenter.Unit*(target-distance)
    local finalPosition=collisionAwarePosition(cf.Position,desired)
    local applied=(finalPosition-cf.Position).Magnitude
    if applied>0.001 then
        camera.CFrame=withPosition(cf,finalPosition)
        legacyFitFrames+=1
        lastAppliedDistance=applied
    end
end

RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Camera.Value+2,function()
    frames+=1
    if mode=="off" then
        restoreForcedVisibility()
        return
    end

    if not character or character~=player.Character then
        bindCharacter(player.Character)
    end

    local camera=Workspace.CurrentCamera
    if not camera or not character then return end

    if mode=="overhaul" then
        overhaulStep(camera)
    elseif mode=="legacy" then
        legacyStep(camera)
    end
end)

getgenv().PCEvadeBodyViewV1={
    Version="1.0-overhaul-legs-legacy-full-body",
    Mode=mode,
    GetState=function()
        return {
            mode=mode,
            frames=frames,
            firstPersonFrames=firstPersonFrames,
            overhaulRevealFrames=overhaulRevealFrames,
            legacyFitFrames=legacyFitFrames,
            collisionClamps=collisionClamps,
            lastTargetDistance=lastTargetDistance,
            lastAppliedDistance=lastAppliedDistance,
            legacyRadiusMax=legacyRadiusMax,
        }
    end,
}

getgenv().__PCEvadeBodyViewV1Cleanup=function()
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    if characterConn then pcall(function() characterConn:Disconnect() end) end
    restoreForcedVisibility()
    getgenv().PCEvadeBodyViewV1=nil
    getgenv().__PCEvadeBodyViewV1Cleanup=nil
end
