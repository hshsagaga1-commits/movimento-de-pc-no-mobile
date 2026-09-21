-- Evade PC Rebuild - Legacy Body View V1
-- Keeps the native camera orientation and only pushes the final Legacy camera
-- backward enough to keep the avatar readable. Collision-aware.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local VERSION = "EvadePCRebuild-LegacyBody-V1"
local LEGACY_PLACE_ID = 96537472072550
local BIND_NAME = "__EvadePCRebuildLegacyBodyV1"

local MIN_ACTIVE_DISTANCE = 2.75
local MIN_TARGET_DISTANCE = 6.80
local MAX_TARGET_DISTANCE = 9.20
local FIT_HALF_FOV_FACTOR = 0.72
local FIT_PADDING = 1.04
local BOUNDS_REFRESH = 0.35

local previousCleanup = ENV.__EvadePCRebuildLegacyBodyV1Cleanup
if type(previousCleanup) == "function" then
    pcall(previousCleanup)
end
pcall(function()
    RunService:UnbindFromRenderStep(BIND_NAME)
end)

if game.PlaceId ~= LEGACY_PLACE_ID then
    local api = {
        Version = VERSION,
        Installed = false,
        Reason = "wrong-place",
        PlaceId = game.PlaceId,
    }
    ENV.EvadePCRebuildLegacyBodyV1 = api
    return api
end

local character = nil
local humanoid = nil
local head = nil
local root = nil
local characterConnection = nil

local enabled = true
local cachedRadius = 0
local cachedCenter = nil
local nextBoundsRefresh = 0

local frames = 0
local pushes = 0
local collisionClamps = 0
local lastTargetDistance = 0
local lastAppliedDistance = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function attachCharacter(char)
    character = char
    humanoid = nil
    head = nil
    root = nil
    cachedRadius = 0
    cachedCenter = nil
    nextBoundsRefresh = 0

    if char then
        humanoid = char:FindFirstChildOfClass("Humanoid")
        head = char:FindFirstChild("Head")
        root = char:FindFirstChild("HumanoidRootPart")

        if not humanoid then
            pcall(function()
                humanoid = char:WaitForChild("Humanoid", 8)
            end)
        end
        if not head then
            pcall(function()
                head = char:WaitForChild("Head", 8)
            end)
        end
        if not root then
            pcall(function()
                root = char:WaitForChild("HumanoidRootPart", 8)
            end)
        end

        rayParams.FilterDescendantsInstances = {char}
    else
        rayParams.FilterDescendantsInstances = {}
    end
end

attachCharacter(player.Character)
characterConnection = player.CharacterAdded:Connect(attachCharacter)

local function isFirstPerson(camera)
    if not camera then
        return false
    end

    if player.CameraMode == Enum.CameraMode.LockFirstPerson then
        return true
    end

    if head and head.Parent then
        return (camera.CFrame.Position - head.Position).Magnitude <= 1.35
    end

    return false
end

local function refreshBounds()
    if not character or os.clock() < nextBoundsRefresh then
        return
    end

    nextBoundsRefresh = os.clock() + BOUNDS_REFRESH

    local boxCF = nil
    local boxSize = nil
    local ok = pcall(function()
        boxCF, boxSize = character:GetBoundingBox()
    end)

    if ok and boxCF and boxSize then
        cachedCenter = boxCF.Position
        cachedRadius = 0.5 * math.sqrt(
            (boxSize.X * boxSize.X)
            + (boxSize.Y * boxSize.Y)
            + (boxSize.Z * boxSize.Z)
        )
    else
        cachedCenter = root and root.Position or nil
        cachedRadius = math.max(cachedRadius, 3)
    end
end

local function targetDistance(camera)
    refreshBounds()

    local radius = math.max(cachedRadius, 2.75)
    local fov = math.clamp(camera.FieldOfView, 45, 95)
    local halfFov = math.rad(fov * 0.5)
    local fitHalfAngle = math.max(math.rad(18), halfFov * FIT_HALF_FOV_FACTOR)
    local fit = (radius / math.tan(fitHalfAngle)) * FIT_PADDING

    return math.clamp(fit, MIN_TARGET_DISTANCE, MAX_TARGET_DISTANCE)
end

local function withPosition(cf, position)
    return CFrame.fromMatrix(position, cf.XVector, cf.YVector, cf.ZVector)
end

local function collisionAwarePosition(fromPosition, desiredPosition)
    local delta = desiredPosition - fromPosition
    if delta.Magnitude <= 0.0001 then
        return desiredPosition
    end

    local hit = nil
    pcall(function()
        hit = Workspace:Raycast(fromPosition, delta, rayParams)
    end)

    if hit then
        collisionClamps = collisionClamps + 1
        local safeDistance = math.max(0, hit.Distance - 0.12)
        return fromPosition + (delta.Unit * safeDistance)
    end

    return desiredPosition
end

RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, function()
    frames = frames + 1

    if not enabled or not character or not humanoid or humanoid.Health <= 0 then
        return
    end

    local camera = Workspace.CurrentCamera
    if not camera
        or camera.CameraType == Enum.CameraType.Scriptable
        or isFirstPerson(camera) then
        return
    end

    refreshBounds()
    local center = cachedCenter or (root and root.Position)
    if not center then
        return
    end

    local cf = camera.CFrame
    local fromCenter = cf.Position - center
    local currentDistance = fromCenter.Magnitude
    local target = targetDistance(camera)

    lastTargetDistance = target

    if currentDistance < MIN_ACTIVE_DISTANCE
        or currentDistance >= target
        or currentDistance <= 0.0001 then
        return
    end

    local desired = cf.Position + (fromCenter.Unit * (target - currentDistance))
    local finalPosition = collisionAwarePosition(cf.Position, desired)
    local applied = (finalPosition - cf.Position).Magnitude

    if applied > 0.001 then
        camera.CFrame = withPosition(cf, finalPosition)
        pushes = pushes + 1
        lastAppliedDistance = applied
    end
end)

local api = {
    Version = VERSION,
    Installed = true,
    SetEnabled = function(value)
        enabled = value ~= false
    end,
    GetState = function()
        return {
            frames = frames,
            pushes = pushes,
            collisionClamps = collisionClamps,
            lastTargetDistance = lastTargetDistance,
            lastAppliedDistance = lastAppliedDistance,
            cachedRadius = cachedRadius,
        }
    end,
}

ENV.EvadePCRebuildLegacyBodyV1 = api

ENV.__EvadePCRebuildLegacyBodyV1Cleanup = function()
    enabled = false

    pcall(function()
        RunService:UnbindFromRenderStep(BIND_NAME)
    end)

    if characterConnection then
        pcall(function()
            characterConnection:Disconnect()
        end)
    end

    ENV.EvadePCRebuildLegacyBodyV1 = nil
    ENV.__EvadePCRebuildLegacyBodyV1Cleanup = nil
end

return api
