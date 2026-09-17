local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local EVADE_GAME_ID=3647333358
local LEGACY_PLACE_ID=96537472072550
local BIND_NAME="__PCEvadeBodyViewV2"

local oldCleanup=getgenv().__PCEvadeBodyViewV2Cleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local mode="off"
if game.GameId==EVADE_GAME_ID then
    mode=(game.PlaceId==LEGACY_PLACE_ID) and "legacy" or "overhaul"
end

-- Overhaul: keep Roblox/Evade's native first-person distance. The V1 backward
-- LookVector zoom was the source of the "camera above/behind the head" feel.
-- V2 only lowers the final rendered viewpoint and forces lower-body visibility.
local FIRST_PERSON_HEAD_DISTANCE=1.35
local OVERHAUL_BASE_DOWN=0.62
local OVERHAUL_DOWN_EXTRA=0.18

-- Legacy: add only a small pitch-dependent amount to the native third-person
-- distance. The curve grows through the useful downward-body-view range, then
-- comes back in at extreme downward pitch like the PC reference.
local LEGACY_FIRST_PERSON_DISTANCE=1.70
local LEGACY_ANCHORS={
    {0.00,0.00},
    {0.25,0.35},
    {0.55,1.15},
    {0.80,0.75},
    {1.00,0.20},
}

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
local frames=0
local overhaulFrames=0
local legacyFrames=0
local collisionClamps=0
local lastLegacyDelta=0
local lastDownAmount=0
local lastOverhaulDown=0

local rayParams=RaycastParams.new()
rayParams.FilterType=Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater=true

local function smoothstep(t)
    t=math.clamp(t,0,1)
    return t*t*(3-2*t)
end

local function curveSample(x)
    x=math.clamp(x,0,1)
    for i=1,#LEGACY_ANCHORS-1 do
        local a=LEGACY_ANCHORS[i]
        local b=LEGACY_ANCHORS[i+1]
        if x<=b[1] then
            local span=b[1]-a[1]
            local alpha=span>0 and smoothstep((x-a[1])/span) or 0
            return a[2]+(b[2]-a[2])*alpha
        end
    end
    return LEGACY_ANCHORS[#LEGACY_ANCHORS][2]
end

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
    rayParams.FilterDescendantsInstances=char and {char} or {}

    if char then
        if not humanoid then pcall(function() humanoid=char:WaitForChild("Humanoid",5) end) end
        if not head then pcall(function() head=char:WaitForChild("Head",5) end) end
        if not root then pcall(function() root=char:WaitForChild("HumanoidRootPart",5) end) end
    end
end

bindCharacter(player.Character)
characterConn=player.CharacterAdded:Connect(bindCharacter)

local function forceLowerBodyVisible()
    if not character then
        restoreForcedVisibility()
        return
    end

    local wanted={}
    for _,obj in ipairs(character:GetDescendants()) do
        if obj:IsA("BasePart") and LOWER_BODY_NAMES[obj.Name] then
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

local function isFirstPerson(camera,limit)
    if player.CameraMode==Enum.CameraMode.LockFirstPerson then return true end
    if camera and head and head.Parent then
        return (camera.CFrame.Position-head.Position).Magnitude<=limit
    end
    return false
end

local function withPosition(cf,newPosition)
    return CFrame.fromMatrix(newPosition,cf.XVector,cf.YVector,cf.ZVector)
end

local function overhaulStep(camera)
    if not isFirstPerson(camera,FIRST_PERSON_HEAD_DISTANCE) then
        restoreForcedVisibility()
        return
    end

    forceLowerBodyVisible()

    local cf=camera.CFrame
    local downAmount=math.clamp(-cf.LookVector.Y,0,1)
    local drop=OVERHAUL_BASE_DOWN+OVERHAUL_DOWN_EXTRA*downAmount
    local offset=Vector3.new(0,-drop,0)

    camera.CFrame=withPosition(cf,cf.Position+offset)
    pcall(function() camera.Focus=camera.Focus+offset end)

    overhaulFrames+=1
    lastDownAmount=downAmount
    lastOverhaulDown=drop
end

local function legacyCenter()
    if root and root.Parent then
        return root.Position+Vector3.new(0,1.45,0)
    end
    if head and head.Parent then return head.Position end
    return nil
end

local function legacyStep(camera)
    restoreForcedVisibility()
    if isFirstPerson(camera,LEGACY_FIRST_PERSON_DISTANCE) then return end

    local center=legacyCenter()
    if not center then return end

    local cf=camera.CFrame
    local radial=cf.Position-center
    local distance=radial.Magnitude
    if distance<=0.001 then return end

    local downAmount=math.clamp(-cf.LookVector.Y,0,1)
    local extra=curveSample(downAmount)
    lastDownAmount=downAmount
    lastLegacyDelta=extra
    if extra<=0.001 then return end

    local targetDistance=distance+extra
    local desired=center+radial.Unit*targetDistance
    local finalPosition=desired

    local hit=nil
    pcall(function() hit=Workspace:Raycast(center,desired-center,rayParams) end)
    if hit then
        local safeDistance=math.max(distance,math.min(targetDistance,hit.Distance-0.12))
        finalPosition=center+radial.Unit*safeDistance
        if safeDistance<targetDistance-0.001 then collisionClamps+=1 end
    end

    if (finalPosition-cf.Position).Magnitude>0.001 then
        camera.CFrame=withPosition(cf,finalPosition)
        legacyFrames+=1
    end
end

RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Camera.Value+2,function()
    frames+=1
    if mode=="off" then
        restoreForcedVisibility()
        return
    end

    if character~=player.Character then bindCharacter(player.Character) end
    local camera=Workspace.CurrentCamera
    if not camera or not character then return end

    if mode=="overhaul" then
        overhaulStep(camera)
    else
        legacyStep(camera)
    end
end)

getgenv().PCEvadeBodyViewV2={
    Version="2.0-low-first-person-pitch-aware-legacy",
    Mode=mode,
    GetState=function()
        return {
            mode=mode,
            frames=frames,
            overhaulFrames=overhaulFrames,
            legacyFrames=legacyFrames,
            collisionClamps=collisionClamps,
            lastDownAmount=lastDownAmount,
            lastOverhaulDown=lastOverhaulDown,
            lastLegacyDelta=lastLegacyDelta,
        }
    end,
}

getgenv().__PCEvadeBodyViewV2Cleanup=function()
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    if characterConn then pcall(function() characterConn:Disconnect() end) end
    restoreForcedVisibility()
    getgenv().PCEvadeBodyViewV2=nil
    getgenv().__PCEvadeBodyViewV2Cleanup=nil
end
