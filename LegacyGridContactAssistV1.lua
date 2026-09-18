local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local EVADE_GAME_ID=3647333358
local CONTACT_RADIUS=3.10
local VERTICAL_NORMAL_Y_MAX=0.42
local INPUT_PRESSURE=0.36
local HOLD_INWARD_SPEED=1.20
local CONTACT_GRACE_SECONDS=0.18
local MIN_TANGENT_INPUT=0.20
local RAY_HEIGHT_OFFSETS={-0.45,0.00,0.45,0.90}

local env=getgenv()
local oldCleanup=env.__LegacyGridContactAssistV1Cleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end

local enabled=(game.GameId==EVADE_GAME_ID)
local character=nil
local humanoid=nil
local root=nil
local characterConnection=nil
local heartbeatConnection=nil

local rayParams=RaycastParams.new()
rayParams.FilterType=Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater=true

local lastNormal=Vector3.zero
local lastHitName="-"
local lastContactUntil=-math.huge
local lastHeight=0
local assistedFrames=0
local contactFrames=0
local noContactFrames=0

local function flat(v)
    return Vector3.new(v.X,0,v.Z)
end

local function flatUnit(v)
    local f=flat(v)
    if f.Magnitude<=1e-5 then return Vector3.zero end
    return f.Unit
end

local function bindCharacter(char)
    character=char
    humanoid=char and char:FindFirstChildOfClass("Humanoid") or nil
    root=char and char:FindFirstChild("HumanoidRootPart") or nil

    if char then
        if not humanoid then
            pcall(function() humanoid=char:WaitForChild("Humanoid",5) end)
        end
        if not root then
            pcall(function() root=char:WaitForChild("HumanoidRootPart",5) end)
        end
    end

    rayParams.FilterDescendantsInstances=char and {char} or {}
    lastNormal=Vector3.zero
    lastHitName="-"
    lastContactUntil=-math.huge
end

bindCharacter(player.Character)
characterConnection=player.CharacterAdded:Connect(bindCharacter)

local function nearestVerticalSurface()
    if not root then return nil end
    local best=nil

    for _,height in ipairs(RAY_HEIGHT_OFFSETS) do
        local origin=root.Position+Vector3.new(0,height,0)

        for i=0,23 do
            local angle=(math.pi*2)*(i/24)
            local direction=Vector3.new(math.cos(angle),0,math.sin(angle))*CONTACT_RADIUS
            local hit=nil
            pcall(function()
                hit=Workspace:Raycast(origin,direction,rayParams)
            end)

            if hit and math.abs(hit.Normal.Y)<=VERTICAL_NORMAL_Y_MAX then
                local normal=flatUnit(hit.Normal)
                if normal.Magnitude>0 then
                    local distance=(hit.Position-origin).Magnitude
                    if not best or distance<best.distance then
                        best={
                            hit=hit,
                            normal=normal,
                            distance=distance,
                            height=height,
                        }
                    end
                end
            end
        end
    end

    return best
end

local function getContact(now)
    local hit=nearestVerticalSurface()
    if hit then
        lastNormal=hit.normal
        lastContactUntil=now+CONTACT_GRACE_SECONDS
        lastHeight=hit.height
        lastHitName=hit.hit.Instance and hit.hit.Instance:GetFullName() or "?"
        return {
            normal=hit.normal,
            name=lastHitName,
            height=hit.height,
            fresh=true,
        }
    end

    if lastNormal.Magnitude>0 and now<=lastContactUntil then
        return {
            normal=lastNormal,
            name=lastHitName,
            height=lastHeight,
            fresh=false,
        }
    end

    return nil
end

local function applyInputPressure(contact)
    local move=flat(humanoid.MoveDirection)
    if move.Magnitude<=0.05 then return end

    local intended=move.Unit
    local normal=contact.normal
    local normalAmount=intended:Dot(normal)
    local tangent=intended-normal*normalAmount

    if tangent.Magnitude<MIN_TANGENT_INPUT then return end

    local output=tangent.Unit-normal*INPUT_PRESSURE
    if output.Magnitude>1 then output=output.Unit end

    pcall(function()
        player:Move(output,false)
    end)
end

local function applyPhysicalHold(contact)
    local velocity=root.AssemblyLinearVelocity
    local horizontal=flat(velocity)
    local normal=contact.normal
    local normalSpeed=horizontal:Dot(normal)

    -- Preserve all tangential speed and all vertical speed. We only prevent the
    -- root from separating from the fence: if its normal component is weaker
    -- than a tiny inward hold, replace only that one component.
    if normalSpeed>-HOLD_INWARD_SPEED then
        local tangent=horizontal-normal*normalSpeed
        local corrected=tangent-normal*HOLD_INWARD_SPEED
        pcall(function()
            root.AssemblyLinearVelocity=Vector3.new(corrected.X,velocity.Y,corrected.Z)
        end)
        assistedFrames+=1
    end
end

heartbeatConnection=RunService.Heartbeat:Connect(function()
    if not enabled then return end
    if character~=player.Character then bindCharacter(player.Character) end
    if not humanoid or not root or not root.Parent then return end
    if humanoid.Health<=0 then return end

    local now=os.clock()
    local contact=getContact(now)
    if not contact then
        noContactFrames+=1
        return
    end

    contactFrames+=1
    applyInputPressure(contact)
    applyPhysicalHold(contact)
end)

env.LegacyGridContactAssistV1={
    Version="2.0-direct-physical-grid-hold-standing-prone",
    Enabled=enabled,
    GetState=function()
        return {
            enabled=enabled,
            contactFrames=contactFrames,
            assistedFrames=assistedFrames,
            noContactFrames=noContactFrames,
            lastHitName=lastHitName,
            lastNormal=lastNormal,
            contactRadius=CONTACT_RADIUS,
            inputPressure=INPUT_PRESSURE,
            holdInwardSpeed=HOLD_INWARD_SPEED,
            contactGraceSeconds=CONTACT_GRACE_SECONDS,
            lastHeight=lastHeight,
        }
    end,
}

env.__LegacyGridContactAssistV1Cleanup=function()
    enabled=false
    if heartbeatConnection then pcall(function() heartbeatConnection:Disconnect() end) end
    if characterConnection then pcall(function() characterConnection:Disconnect() end) end
    env.LegacyGridContactAssistV1=nil
    env.__LegacyGridContactAssistV1Cleanup=nil
end
