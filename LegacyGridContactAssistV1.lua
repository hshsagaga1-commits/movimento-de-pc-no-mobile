local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local EVADE_GAME_ID=3647333358

-- Vertical wall/rail contact.
local WALL_RADIUS=4.00
local WALL_RAYS=32
local WALL_NORMAL_Y_MAX=0.48
local WALL_HEIGHTS={-0.55,-0.10,0.35,0.80,1.25}

-- Ledge/grid-edge contact. The reference video is mostly an edge/curb contact,
-- not a flat vertical wall, so horizontal-normal-only probes miss it.
local EDGE_PROBE_RADIUS=2.15
local EDGE_SAMPLES=20
local EDGE_RAY_UP=2.75
local EDGE_RAY_DOWN=7.00
local EDGE_DROP_MIN=0.55

-- Hold only modifies character physics; it never calls Player:Move and never
-- captures/touches the joystick GUI.
local WALL_INWARD_SPEED=5.25
local EDGE_INWARD_SPEED=4.25
local CONTACT_GRACE_SECONDS=0.24
local MIN_PROJECTED_INPUT=0.10
local SEED_SPEED_FACTOR=0.92

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
local lastMode="none"
local lastContactUntil=-math.huge
local lastHeight=0
local assistedFrames=0
local wallFrames=0
local edgeFrames=0
local noContactFrames=0
local activeChord="-"

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
        if not humanoid then pcall(function() humanoid=char:WaitForChild("Humanoid",5) end) end
        if not root then pcall(function() root=char:WaitForChild("HumanoidRootPart",5) end) end
    end
    rayParams.FilterDescendantsInstances=char and {char} or {}
    lastNormal=Vector3.zero
    lastHitName="-"
    lastMode="none"
    lastContactUntil=-math.huge
end

bindCharacter(player.Character)
characterConnection=player.CharacterAdded:Connect(bindCharacter)

local function readChord()
    local bridge=env.PCKeyboardTouchBridgeV52
    if type(bridge)=="table" and type(bridge.GetState)=="function" then
        local ok,state=pcall(bridge.GetState)
        if ok and type(state)=="table" then
            return tostring(state.chord or "-")
        end
    end
    return "-"
end

local ACTIVE_CHORDS={
    ["A"]=true,
    ["D"]=true,
    ["W"]=true,
    ["W+A"]=true,
    ["W+D"]=true,
}

local function desiredMove(chord)
    local camera=Workspace.CurrentCamera
    local move=flat(humanoid.MoveDirection)

    -- The bridge exposes the exact PC chord. Rebuild its world direction from
    -- camera axes so A/D pure and W/WA/WD all keep working even while crouched.
    if camera and ACTIVE_CHORDS[chord] then
        local forward=flatUnit(camera.CFrame.LookVector)
        local right=flatUnit(camera.CFrame.RightVector)
        local desired=Vector3.zero
        if chord=="W" then
            desired=forward
        elseif chord=="A" then
            desired=-right
        elseif chord=="D" then
            desired=right
        elseif chord=="W+A" then
            desired=forward-right
        elseif chord=="W+D" then
            desired=forward+right
        end
        if desired.Magnitude>1e-5 then return desired.Unit end
    end

    if move.Magnitude>0.05 then return move.Unit end
    return Vector3.zero
end

local function findWallContact()
    if not root then return nil end
    local best=nil

    for _,height in ipairs(WALL_HEIGHTS) do
        local origin=root.Position+Vector3.new(0,height,0)
        for i=0,WALL_RAYS-1 do
            local angle=(math.pi*2)*(i/WALL_RAYS)
            local direction=Vector3.new(math.cos(angle),0,math.sin(angle))*WALL_RADIUS
            local hit=Workspace:Raycast(origin,direction,rayParams)

            if hit and math.abs(hit.Normal.Y)<=WALL_NORMAL_Y_MAX then
                local normal=flatUnit(hit.Normal)
                if normal.Magnitude>0 then
                    local distance=(hit.Position-origin).Magnitude
                    if not best or distance<best.distance then
                        best={
                            normal=normal,
                            distance=distance,
                            name=hit.Instance and hit.Instance:GetFullName() or "?",
                            height=height,
                            mode="wall",
                        }
                    end
                end
            end
        end
    end

    return best
end

local function downwardHit(position)
    local origin=position+Vector3.new(0,EDGE_RAY_UP,0)
    return Workspace:Raycast(origin,Vector3.new(0,-EDGE_RAY_DOWN,0),rayParams)
end

local function findEdgeContact()
    if not root then return nil end

    local center=downwardHit(root.Position)
    if not center then return nil end
    local centerY=center.Position.Y

    local outwardSum=Vector3.zero
    local dropCount=0
    local nearestDrop=math.huge

    for i=0,EDGE_SAMPLES-1 do
        local angle=(math.pi*2)*(i/EDGE_SAMPLES)
        local radial=Vector3.new(math.cos(angle),0,math.sin(angle))
        local samplePosition=root.Position+radial*EDGE_PROBE_RADIUS
        local hit=downwardHit(samplePosition)

        local isDrop=false
        local dropAmount=EDGE_RAY_DOWN

        if not hit then
            isDrop=true
        else
            dropAmount=centerY-hit.Position.Y
            if dropAmount>=EDGE_DROP_MIN then isDrop=true end
        end

        if isDrop then
            outwardSum+=radial
            dropCount+=1
            nearestDrop=math.min(nearestDrop,dropAmount)
        end
    end

    if dropCount==0 or outwardSum.Magnitude<=0.20 then return nil end

    local outward=outwardSum.Unit
    return {
        normal=outward,
        distance=EDGE_PROBE_RADIUS,
        name=center.Instance and center.Instance:GetFullName() or "?",
        height=centerY,
        mode="edge",
        dropCount=dropCount,
        drop=nearestDrop,
    }
end

local function chooseContact()
    local wall=findWallContact()
    local edge=findEdgeContact()

    -- Prefer a real nearby wall/rail. Otherwise use the ledge detector from the
    -- reference clip (curb/grid edge with a drop beside the player).
    if wall and wall.distance<=2.60 then return wall end
    if edge then return edge end
    return wall
end

local function getContact(now)
    local contact=chooseContact()
    if contact then
        lastNormal=contact.normal
        lastContactUntil=now+CONTACT_GRACE_SECONDS
        lastHeight=contact.height or 0
        lastHitName=contact.name or "?"
        lastMode=contact.mode or "?"
        return contact
    end

    if lastNormal.Magnitude>0 and now<=lastContactUntil then
        return {
            normal=lastNormal,
            name=lastHitName,
            height=lastHeight,
            mode=lastMode,
            held=true,
        }
    end

    return nil
end

local function applyAssist(contact,desired)
    local velocity=root.AssemblyLinearVelocity
    local horizontal=flat(velocity)
    local normal=contact.normal

    -- Same motor for every supported chord. W is camera-forward; A/D are that
    -- exact same behavior rotated 90 degrees; WA/WD are the normalized diagonal.
    -- Do not project A/D onto the grid tangent: that was the bug that could turn
    -- pure side input into almost zero movement.
    local speed=horizontal.Magnitude
    local walkSeed=math.max(0,humanoid.WalkSpeed*SEED_SPEED_FACTOR)
    if speed<walkSeed then speed=walkSeed end

    local drive=Vector3.zero
    if desired.Magnitude>=MIN_PROJECTED_INPUT then
        drive=desired.Unit*speed
    elseif horizontal.Magnitude>0.05 then
        drive=horizontal
    end

    local inward=(contact.mode=="edge") and EDGE_INWARD_SPEED or WALL_INWARD_SPEED

    -- Keep the requested direction intact and add only contact pressure.
    -- Therefore:
    -- W   = forward motor + hold
    -- A   = same motor rotated left + hold
    -- D   = same motor rotated right + hold
    -- WA/WD = same motor on the diagonal + hold
    local corrected=drive-normal*inward

    pcall(function()
        root.AssemblyLinearVelocity=Vector3.new(corrected.X,velocity.Y,corrected.Z)
    end)
    assistedFrames+=1
end

heartbeatConnection=RunService.Heartbeat:Connect(function()
    if not enabled then return end
    if character~=player.Character then bindCharacter(player.Character) end
    if not humanoid or not root or not root.Parent then return end
    if humanoid.Health<=0 then return end

    local chord=readChord()
    activeChord=chord
    local desired=desiredMove(chord)

    -- Explicitly support the requested PC chords. If the bridge is not loaded,
    -- Humanoid.MoveDirection is still accepted as a fallback.
    if not ACTIVE_CHORDS[chord] and desired.Magnitude<=0.05 then return end

    local now=os.clock()
    local contact=getContact(now)
    if not contact then
        noContactFrames+=1
        return
    end

    if contact.mode=="edge" then edgeFrames+=1 else wallFrames+=1 end
    applyAssist(contact,desired)
end)

env.LegacyGridContactAssistV1={
    Version="3.1-same-motor-rotated-W-A-D-WA-WD",
    Enabled=enabled,
    GetState=function()
        return {
            enabled=enabled,
            chord=activeChord,
            mode=lastMode,
            assistedFrames=assistedFrames,
            wallFrames=wallFrames,
            edgeFrames=edgeFrames,
            noContactFrames=noContactFrames,
            lastHitName=lastHitName,
            lastNormal=lastNormal,
            lastHeight=lastHeight,
            wallRadius=WALL_RADIUS,
            edgeProbeRadius=EDGE_PROBE_RADIUS,
            wallInwardSpeed=WALL_INWARD_SPEED,
            edgeInwardSpeed=EDGE_INWARD_SPEED,
            contactGraceSeconds=CONTACT_GRACE_SECONDS,
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
