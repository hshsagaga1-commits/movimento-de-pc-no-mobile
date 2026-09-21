-- Evade PC Rebuild - Input V1
-- From-scratch mobile -> digital PC movement bridge.
-- Keeps the native Roblox thumbstick/HUD and does not use VirtualInputManager.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local VERSION = "EvadePCRebuild-Input-V1"
local EVADE_GAME_ID = 3647333358
local MOVE_BIND = "__EvadePCRebuildInputV1"
local DEADZONE = 0.14
local JUMP_BUFFER = 0.20

local previousCleanup = ENV.__EvadePCRebuildInputV1Cleanup
if type(previousCleanup) == "function" then
    pcall(previousCleanup)
end
pcall(function()
    RunService:UnbindFromRenderStep(MOVE_BIND)
end)

if game.GameId ~= EVADE_GAME_ID then
    local api = {
        Version = VERSION,
        Installed = false,
        Reason = "wrong-game",
        GameId = game.GameId,
    }
    ENV.EvadePCRebuildInputV1 = api
    return api
end

local playerModule = nil
local controls = nil
local character = nil
local humanoid = nil
local characterConnection = nil
local jumpConnection = nil
local heartbeatConnection = nil

local frames = 0
local moveWrites = 0
local controlReads = 0
local fallbackReads = 0
local jumpRequests = 0
local bufferedJumpWrites = 0
local jumpDeadline = -math.huge
local enabled = true

local function getControls()
    if type(controls) == "table" then
        return controls
    end

    local scripts = player:FindFirstChild("PlayerScripts")
    local moduleScript = scripts and scripts:FindFirstChild("PlayerModule")
    if not moduleScript then
        return nil
    end

    pcall(function()
        local module = require(moduleScript)
        if type(module) == "table" then
            playerModule = module
        end
    end)

    pcall(function()
        if type(playerModule) == "table" and type(playerModule.GetControls) == "function" then
            controls = playerModule:GetControls()
        end
    end)

    return type(controls) == "table" and controls or nil
end

local function attachCharacter(char)
    character = char
    humanoid = nil

    if char then
        humanoid = char:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            pcall(function()
                humanoid = char:WaitForChild("Humanoid", 8)
            end)
        end
    end
end

attachCharacter(player.Character)
characterConnection = player.CharacterAdded:Connect(attachCharacter)

local function getRawMoveVector()
    local controlModule = getControls()
    if type(controlModule) == "table" and type(controlModule.GetMoveVector) == "function" then
        local raw = nil
        local ok = pcall(function()
            raw = controlModule:GetMoveVector()
        end)

        if ok and typeof(raw) == "Vector3" then
            controlReads = controlReads + 1
            return Vector3.new(raw.X, 0, raw.Z), "controls"
        end
    end

    if humanoid then
        local world = humanoid.MoveDirection
        if typeof(world) == "Vector3" then
            local camera = Workspace.CurrentCamera
            if camera and world.Magnitude > 0.001 then
                local localDirection = camera.CFrame:VectorToObjectSpace(world)
                fallbackReads = fallbackReads + 1
                return Vector3.new(localDirection.X, 0, localDirection.Z), "humanoid"
            end
        end
    end

    return Vector3.zero, "zero"
end

local function snapToEightDirections(raw)
    local x = raw.X
    local z = raw.Z
    local magnitude = math.sqrt((x * x) + (z * z))

    if magnitude < DEADZONE then
        return Vector3.zero
    end

    local angle = math.atan2(x, -z)
    local step = math.pi / 4
    local snapped = math.floor((angle / step) + 0.5) * step

    return Vector3.new(
        math.sin(snapped),
        0,
        -math.cos(snapped)
    )
end

local function canOwnMovement()
    if not enabled or not humanoid or humanoid.Health <= 0 then
        return false
    end

    local platformStand = false
    pcall(function()
        platformStand = humanoid.PlatformStand
    end)
    if platformStand then
        return false
    end

    local state = nil
    pcall(function()
        state = humanoid:GetState()
    end)

    if state == Enum.HumanoidStateType.Dead
        or state == Enum.HumanoidStateType.Seated then
        return false
    end

    return true
end

RunService:BindToRenderStep(MOVE_BIND, Enum.RenderPriority.Input.Value + 8, function()
    frames = frames + 1

    if not canOwnMovement() then
        return
    end

    local raw = getRawMoveVector()
    local digital = snapToEightDirections(raw)

    pcall(function()
        player:Move(digital, true)
        moveWrites = moveWrites + 1
    end)
end)

local function requestJump()
    if not enabled then
        return
    end

    jumpRequests = jumpRequests + 1
    jumpDeadline = os.clock() + JUMP_BUFFER

    if humanoid and humanoid.Health > 0 then
        pcall(function()
            humanoid.Jump = true
        end)
    end
end

jumpConnection = UserInputService.JumpRequest:Connect(requestJump)

heartbeatConnection = RunService.Heartbeat:Connect(function()
    if not enabled or os.clock() > jumpDeadline then
        return
    end

    local h = humanoid
    if not h or h.Health <= 0 then
        return
    end

    local state = nil
    pcall(function()
        state = h:GetState()
    end)

    local grounded = false
    pcall(function()
        grounded = h.FloorMaterial ~= Enum.Material.Air
    end)

    if grounded
        or state == Enum.HumanoidStateType.Landed
        or state == Enum.HumanoidStateType.Running
        or state == Enum.HumanoidStateType.RunningNoPhysics then
        pcall(function()
            h.Jump = true
            bufferedJumpWrites = bufferedJumpWrites + 1
        end)
    end
end)

local api = {
    Version = VERSION,
    Installed = true,
    SetEnabled = function(value)
        enabled = value ~= false
        if not enabled then
            pcall(function()
                player:Move(Vector3.zero, true)
            end)
        end
    end,
    IsEnabled = function()
        return enabled
    end,
    GetState = function()
        return {
            frames = frames,
            moveWrites = moveWrites,
            controlReads = controlReads,
            fallbackReads = fallbackReads,
            jumpRequests = jumpRequests,
            bufferedJumpWrites = bufferedJumpWrites,
            hasHumanoid = humanoid ~= nil,
            hasControls = type(getControls()) == "table",
            touchEnabled = UserInputService.TouchEnabled,
        }
    end,
}

ENV.EvadePCRebuildInputV1 = api

ENV.__EvadePCRebuildInputV1Cleanup = function()
    enabled = false

    pcall(function()
        RunService:UnbindFromRenderStep(MOVE_BIND)
    end)

    if characterConnection then
        pcall(function()
            characterConnection:Disconnect()
        end)
    end
    if jumpConnection then
        pcall(function()
            jumpConnection:Disconnect()
        end)
    end
    if heartbeatConnection then
        pcall(function()
            heartbeatConnection:Disconnect()
        end)
    end

    pcall(function()
        player:Move(Vector3.zero, true)
    end)

    ENV.EvadePCRebuildInputV1 = nil
    ENV.__EvadePCRebuildInputV1Cleanup = nil
end

return api
