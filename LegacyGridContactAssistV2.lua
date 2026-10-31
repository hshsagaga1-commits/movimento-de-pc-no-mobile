-- PC Movement + Assist V2 / less intrusive grid contact assist
-- No forced character rotation, no micro-hop by default, smooth contact corrections.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local EVADE_GAME_ID=3647333358

-- Vertical wall/rail contact.
local WALL_RADIUS=4.00
local WALL_RAYS=24
local WALL_NORMAL_Y_MAX=0.48
local WALL_HEIGHTS={-0.35,0.35,1.05}

-- Ledge/grid-edge contact. The reference video is mostly an edge/curb contact,
-- not a flat vertical wall, so horizontal-normal-only probes miss it.
local EDGE_PROBE_RADIUS=2.15
local EDGE_SAMPLES=20
local EDGE_RAY_UP=2.75
local EDGE_RAY_DOWN=7.00
local EDGE_DROP_MIN=0.55

-- Hold only modifies character physics; it never calls Player:Move and never
-- captures/touches the joystick GUI.
local CONTACT_GRACE_SECONDS=0.10
local MIN_PROJECTED_INPUT=0.10
local SEED_SPEED_FACTOR=0.92
local DIRECTION_CHANGE_SPEED_FACTOR=1.0

-- Tiny vertical pulse on a grounded direction reversal while contact is held.
-- 4.25 studs/s gives a very small hop, not a normal full jump.
local MICRO_HOP_ENABLED=false -- preserve original hop mechanic, opt-in only
local MICRO_HOP_SPEED=4.25
local MICRO_HOP_COOLDOWN=0.14

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
local lastRayHitName="-"
local lastRayHitDistance=math.huge
local lastRayHitRecognized=false
local lastRayHitSize="-"
local lastMode="none"
local lastContactUntil=-math.huge
local lastHeight=0
local assistedFrames=0
local wallFrames=0
local edgeFrames=0
local noContactFrames=0
local activeChord="-"
local smoothedDirection=Vector3.zero
local lastHeartbeatAt=os.clock()
local lastMicroHopAt=-math.huge
local lastContactScanAt=-math.huge
local cachedContact=nil

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
    lastRayHitName="-"
    lastRayHitDistance=math.huge
    lastRayHitRecognized=false
    lastRayHitSize="-"
    lastMode="none"
    lastContactUntil=-math.huge
    cachedContact=nil
    lastContactScanAt=-math.huge
    smoothedDirection=Vector3.zero
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
    ["W+A+D"]=true,
    ["W+A"]=true,
    ["W+D"]=true,
    ["S"]=true,
    ["S+A"]=true,
    ["S+D"]=true,
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
        elseif chord=="W+A+D" then
            -- A and D cancel, W remains the intended direction.
            desired=forward
        elseif chord=="S" then
            desired=-forward
        elseif chord=="S+A" then
            desired=-forward-right
        elseif chord=="S+D" then
            desired=-forward+right
        end
        if desired.Magnitude>1e-5 then return desired.Unit end
    end

    if move.Magnitude>0.05 then return move.Unit end
    return Vector3.zero
end

-- Grid collision may be a separate invisible hitbox, so recognize both
-- named fence/grid pieces and small collision/barrier parts near them.
-- Explicit map-boundary names are rejected to avoid activating at the map edge.
local FENCE_NAME_TOKENS={"fence","grid","grate","railing","rail","gate","mesh","cage","cerca","grade"}
local INVISIBLE_BARRIER_TOKENS={"invisible","barrier","collision","clip","hitbox","blocker"}
local MAP_BOUNDARY_TOKENS={"boundary","border","mapedge","map_edge","worldedge","void","killplane","kill_plane"}

local function hasNameToken(instance,tokens)
    local current=instance
    for _=1,6 do
        if not current then break end
        local name=string.lower(current.Name or "")
        for _,token in ipairs(tokens) do
            if string.find(name,token,1,true) then return true end
        end
        current=current.Parent
    end
    return false
end

local function isFenceLike(instance)
    if not instance then return false end
    if hasNameToken(instance,MAP_BOUNDARY_TOKENS) then return false end
    if hasNameToken(instance,FENCE_NAME_TOKENS) then return true end

    -- Separate invisible collision volumes are often named generically.
    -- Accept these only when they are reasonably sized, not giant map blockers.
    if hasNameToken(instance,INVISIBLE_BARRIER_TOKENS) then
        local part=instance:IsA("BasePart") and instance or nil
        if not part then return false end
        local size=part.Size
        local largest=math.max(size.X,size.Y,size.Z)
        local smallest=math.min(size.X,size.Y,size.Z)
        return largest<=24 and smallest<=3
    end
    return false
end

local function findWallContact()
    if not root then return nil end
    local best=nil
    lastRayHitDistance=math.huge
    lastRayHitName="-"
    lastRayHitRecognized=false
    lastRayHitSize="-"

    for _,height in ipairs(WALL_HEIGHTS) do
        local origin=root.Position+Vector3.new(0,height,0)
        for i=0,WALL_RAYS-1 do
            local angle=(math.pi*2)*(i/WALL_RAYS)
            local direction=Vector3.new(math.cos(angle),0,math.sin(angle))*WALL_RADIUS
            local hit=Workspace:Raycast(origin,direction,rayParams)

            -- Diagnostics: record nearest ray hit even if the name filter rejects it.
            if hit then
                local hitDistance=(hit.Position-origin).Magnitude
                if hitDistance<lastRayHitDistance then
                    lastRayHitDistance=hitDistance
                    lastRayHitName=hit.Instance and hit.Instance:GetFullName() or "?"
                    lastRayHitRecognized=isFenceLike(hit.Instance)
                    if hit.Instance and hit.Instance:IsA("BasePart") then
                        local size=hit.Instance.Size
                        lastRayHitSize=string.format("%.1f,%.1f,%.1f",size.X,size.Y,size.Z)
                    else
                        lastRayHitSize="-"
                    end
                end
            end

            if hit and isFenceLike(hit.Instance) and math.abs(hit.Normal.Y)<=WALL_NORMAL_Y_MAX then
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
    local fence=findWallContact()
    -- No generic wall or ledge activation: only a named grid/fence within reach.
    if fence and fence.distance<=2.60 then return fence end
    return nil
end

-- Run the expensive wall/edge raycast sweep at 30 Hz instead of every
-- Heartbeat. Keep the complete probe layout; only spread the scan frequency.
local CONTACT_SCAN_INTERVAL=1/24

local function getContact(now)
    if now-lastContactScanAt>=CONTACT_SCAN_INTERVAL then
        lastContactScanAt=now
        cachedContact=chooseContact()
        if cachedContact then
            lastNormal=cachedContact.normal
            lastContactUntil=now+CONTACT_GRACE_SECONDS
            lastHeight=cachedContact.height or 0
            lastHitName=cachedContact.name or "?"
            lastMode=cachedContact.mode or "?"
        end
    end

    if cachedContact then
        return cachedContact
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

local function applyAssist(contact,desired,directionChanged)
    if not root or not humanoid or contact.held then return end
    if desired.Magnitude<MIN_PROJECTED_INPUT then return end

    local velocity=root.AssemblyLinearVelocity
    local horizontal=flat(velocity)
    local speed=horizontal.Magnitude
    local walkSpeed=math.max(0,humanoid.WalkSpeed)
    if walkSpeed<=0 then return end

    -- Do not pull the character back toward a rail after the player turns away.
    if contact.normal and desired:Dot(contact.normal)>0.15 then return end

    -- Preserve real airborne momentum. Strong horizontal speed is not replaced
    -- just because a fence happens to be next to the character.
    if humanoid.FloorMaterial==Enum.Material.Air and speed>walkSpeed*1.25 then return end

    local seed=walkSpeed*SEED_SPEED_FACTOR
    if not directionChanged and speed>=seed then return end

    -- Stabilize contact input without the old 1.22x direction-change spike.
    -- Never target more than the existing speed or ordinary WalkSpeed.
    local allowedSpeed=math.max(speed,walkSpeed)
    local targetSpeed=math.min(allowedSpeed,math.max(speed,seed))
    local target=desired.Unit*targetSpeed
    local alpha=directionChanged and 0.68 or 0.38
    local corrected=horizontal:Lerp(target,alpha)
    if corrected.Magnitude>allowedSpeed and corrected.Magnitude>0 then
        corrected=corrected.Unit*allowedSpeed
    end

    if (corrected-horizontal).Magnitude<0.025 then return end
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
    local previousChord=activeChord
    activeChord=chord
    local targetDirection=desiredMove(chord)
    local now=os.clock()
    local dt=math.clamp(now-lastHeartbeatAt,0,0.05)
    lastHeartbeatAt=now

    -- Read the current camera-relative direction directly. No delayed rotation
    -- smoothing in the physics motor: the thumb and the controller agree now.
    -- Leave avatar facing and camera ownership to the normal Roblox controller.
    local desired=targetDirection
    smoothedDirection=targetDirection
    if desired.Magnitude<=0.05 then return end

    local directionChanged=previousChord~=chord
        and ACTIVE_CHORDS[previousChord]==true
        and ACTIVE_CHORDS[chord]==true

    local contact=getContact(now)
    if not contact then
        noContactFrames+=1
        return
    end

    if contact.mode=="edge" then edgeFrames+=1 else wallFrames+=1 end

    -- Reproduce the PC's barely-visible grid hop on a direction change.
    -- Only trigger while touching a detected wall/edge and standing on ground;
    -- no keyboard/joystick input is generated or modified by this block.
    local changedDirection=previousChord~=chord
        and ACTIVE_CHORDS[previousChord]==true
        and ACTIVE_CHORDS[chord]==true
    local grounded=humanoid.FloorMaterial~=Enum.Material.Air
    if MICRO_HOP_ENABLED and changedDirection and grounded and now-lastMicroHopAt>=MICRO_HOP_COOLDOWN then
        local v=root.AssemblyLinearVelocity
        pcall(function()
            root.AssemblyLinearVelocity=Vector3.new(v.X,MICRO_HOP_SPEED,v.Z)
        end)
        lastMicroHopAt=now
    end

    applyAssist(contact,desired,directionChanged)
end)

env.LegacyGridContactAssistV1={
    Version="4.0-v2-mobile-contact-stability",
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
            lastRayHitName=lastRayHitName,
            lastRayHitDistance=lastRayHitDistance,
            lastRayHitRecognized=lastRayHitRecognized,
            lastRayHitSize=lastRayHitSize,
            lastNormal=lastNormal,
            lastHeight=lastHeight,
            wallRadius=WALL_RADIUS,
            edgeProbeRadius=EDGE_PROBE_RADIUS,
            contactGraceSeconds=CONTACT_GRACE_SECONDS,
            wallRays=WALL_RAYS,
            scanInterval=CONTACT_SCAN_INTERVAL,
            microHopEnabled=MICRO_HOP_ENABLED,
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
