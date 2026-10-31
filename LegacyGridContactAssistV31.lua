-- PC MOVEMENT + ASSIST V3.1 / Evade mobile
-- V3 untouched: stronger fence adhesion and a controlled light contact-hop.
-- Original keyboard mapping and staged A-D transitions live in the V6 bridge.
-- This module only handles visual facing + conditional fence-contact physics.
-- A movement AWAY from the fence immediately releases the magnetic correction.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local EVADE_GAME_ID=3647333358
local env=getgenv()
local previousCleanup=env.__LegacyGridContactAssistV1Cleanup
if type(previousCleanup)=="function" then pcall(previousCleanup) end

local enabled=game.GameId==EVADE_GAME_ID
local character,humanoid,root=nil,nil,nil
local characterConnection,heartbeatConnection=nil,nil

-- Keep 360-degree coverage but fewer probes than V1 (112 vs 160 per scan).
local WALL_RADIUS=4.10
local WALL_RAYS=28
local WALL_HEIGHTS={-0.65,-0.08,0.52,1.15}
local CONTACT_MAX_DISTANCE=2.85
local CONTACT_SCAN_INTERVAL=1/30
local CONTACT_GRACE_SECONDS=0.105
local WALL_NORMAL_Y_MAX=0.54

-- Contact behavior: inward adhesion along walls, NEVER against outward input.
local MAGNET_INWARD_SPEED=2.75
local MAGNET_SPEED_CAP=4.6
local MAGNET_RESPONSE=0.038
-- Light contact-hop: approx. 0.17-0.18 s of flight at normal Roblox gravity.
-- Only a nearby eligible rail impact can trigger, never a general movement change.
local CONTACT_HOP_ENABLED=true
local HOP_MAX_CONTACT_DISTANCE=2.12
local HOP_TARGET_AIRTIME=0.175
local HOP_OUTWARD_SPEED=2.6
local HOP_RELEASE_SECONDS=0.085
local HOP_COOLDOWN_SECONDS=0.42
local HOP_REARM_LOST_SECONDS=0.15
local WALK_SEED_FACTOR=0.92
local MICRO_HOP_ENABLED=true -- preserve original small contact-hop mechanic
local MICRO_HOP_SPEED=4.25
local MICRO_HOP_COOLDOWN=0.14

local FENCE_TOKENS={
    "fence","grid","grate","railing","rail","gate","cage",
    "cerca","grade","chainlink","chain_link","barricade","netting",
    "wirefence","fencing"
}
local COLLISION_TOKENS={"invisible","collision","clip","hitbox","barrier","blocker"}
local EXCLUDE_TOKENS={"boundary","border","mapedge","map_edge","worldedge","void",
    "killplane","kill_plane","outofbounds","out_of_bounds"}

local rayParams=RaycastParams.new()
rayParams.FilterType=Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater=true

local overlapParams=OverlapParams.new()
overlapParams.FilterType=Enum.RaycastFilterType.Exclude
overlapParams.MaxParts=48

local radialDirections={}
for i=0,WALL_RAYS-1 do
    local angle=math.pi*2*i/WALL_RAYS
    radialDirections[#radialDirections+1]=Vector3.new(math.cos(angle),0,math.sin(angle))
end

local lastContact=nil
local cachedContact=nil
local lastContactUntil=-math.huge
local lastScanAt=-math.huge
local lastOverlapAt=-math.huge
local lastHeartbeatAt=os.clock()
local lastMicroHopAt=-math.huge
local lastContactHopAt=-math.huge
local lastNearFenceAt=-math.huge
local nextMagnetAt=-math.huge
local hopArmed=true
local contactHopCount=0
local groundContactHops=0
local airContactHops=0
local outwardReleases=0
local lastChord="-"
local lastFacing=Vector3.zero
local assistedFrames=0
local magnetFrames=0
local reversalFrames=0
local noContactFrames=0
local geometryContacts=0
local scanCount=0
local lastRayHitName="-"
local lastRayHitDistance=math.huge

local function flat(v)
    return Vector3.new(v.X,0,v.Z)
end
local function flatUnit(v)
    local f=flat(v)
    return f.Magnitude>1e-5 and f.Unit or Vector3.zero
end
local function nameMatches(part,tokens)
    local node=part
    for _=1,7 do
        if not node then break end
        local name=string.lower(node.Name or "")
        for _,token in ipairs(tokens) do
            if string.find(name,token,1,true) then return true end
        end
        node=node.Parent
    end
    return false
end

-- Name recognition first, then a conservative geometric fallback for unnamed
-- thin slats/panels. Collision volumes are restricted by shape and size.
local function isFenceLike(part)
    if not part or not part:IsA("BasePart") then return false,"none" end
    if nameMatches(part,EXCLUDE_TOKENS) then return false,"boundary" end
    if nameMatches(part,FENCE_TOKENS) then return true,"named" end
    local sz=part.Size
    local thin=math.min(sz.X,sz.Z)
    local wide=math.max(sz.X,sz.Z)
    local upright=sz.Y>=1.25 and sz.Y<=38
    local sensibleWidth=wide<=72
    local solid=part.CanCollide
    if nameMatches(part,COLLISION_TOKENS) and solid
        and upright and thin<=2.0 and sensibleWidth then
        return true,"hitbox"
    end
    if not solid or not upright or not sensibleWidth then return false,"none" end

    -- Thin solid vertical columns, metal grates, mesh fences, translucent rails
    -- and slim collision panels with generic names such as "Part".
    local shape=thin<=0.78 and (wide>=0.10 or sz.Y>=2.0)
    local plainSlat=thin<=0.42 and wide<=1.10 and sz.Y>=1.45
    local likelyFence=part:IsA("MeshPart")
        or part.Material==Enum.Material.Metal
        or part.Material==Enum.Material.DiamondPlate
        or (part.Transparency>=0.12 and part.Transparency<=0.96)
    if shape and (likelyFence or plainSlat) then return true,"geometry" end
    -- Thin horizontal rails may form a fence even without a useful part name.
    local horizontalRail=sz.Y<=0.65 and thin<=0.52 and wide>=1.40
        and wide<=72 and (likelyFence or part.Material==Enum.Material.Plastic)
    if horizontalRail then return true,"horizontal-rail" end

    if thin<=1.55 and part.Transparency>=0.96 then
        return true,"invisible-panel"
    end
    return false,"none"
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
    overlapParams.FilterDescendantsInstances=char and {char} or {}
    lastContact=nil
    cachedContact=nil
    lastContactUntil=-math.huge
    lastScanAt=-math.huge
    lastOverlapAt=-math.huge
    lastChord="-"
    lastFacing=Vector3.zero
    lastContactHopAt=-math.huge
    lastMicroHopAt=-math.huge
    lastNearFenceAt=-math.huge
    nextMagnetAt=-math.huge
    hopArmed=true
end
bindCharacter(player.Character)
characterConnection=player.CharacterAdded:Connect(bindCharacter)

local function readBridge()
    local b=env.PCKeyboardTouchBridgeV52
    if type(b)=="table" and type(b.GetState)=="function" then
        local ok,state=pcall(b.GetState)
        if ok and type(state)=="table" then
            return tostring(state.chord or "-"),
                tonumber(state.analogX) or 0,
                tonumber(state.analogZ) or 0,
                state.sweepActive==true
        end
    end
    return "-",0,0,false
end

local function intentFromChord(chord)
    local cam=Workspace.CurrentCamera
    if not cam then return flatUnit(humanoid.MoveDirection) end
    local forward=flatUnit(cam.CFrame.LookVector)
    local right=flatUnit(cam.CFrame.RightVector)
    local x,z=0,0
    -- Preserve exact PC key chords from the ORIGINAL bridge.
    if string.find(chord,"W",1,true) then z+=1 end
    if string.find(chord,"S",1,true) then z-=1 end
    if string.find(chord,"A",1,true) then x-=1 end
    if string.find(chord,"D",1,true) then x+=1 end
    local wanted=forward*z+right*x
    if wanted.Magnitude>1e-5 then return wanted.Unit end
    return flatUnit(humanoid.MoveDirection)
end

local function visualFacingIntent(desired,chord,analogX,analogZ,sweepActive)
    if sweepActive then return desired end -- original A/D sweep stays exact
    if chord~="W+A" and chord~="W+D" and chord~="A+S" and chord~="S+D" then
        return desired -- pure A/D/W/S stay pure
    end
    local cam=Workspace.CurrentCamera
    if not cam then return desired end
    local a=flatUnit(flatUnit(cam.CFrame.RightVector)*analogX
        -flatUnit(cam.CFrame.LookVector)*analogZ)
    if a.Magnitude<0.1 or desired:Dot(a)<0.65 then return desired end
    return flatUnit(desired*0.72+a*0.28)
end

local function candidateContact(hit,origin)
    if not hit then return nil end
    local valid,kind=isFenceLike(hit.Instance)
    local dist=(hit.Position-origin).Magnitude
    if dist<lastRayHitDistance then
        lastRayHitDistance=dist
        lastRayHitName=hit.Instance and hit.Instance:GetFullName() or "?"
    end
    if not valid or dist>CONTACT_MAX_DISTANCE
        or math.abs(hit.Normal.Y)>WALL_NORMAL_Y_MAX then return nil end
    local normal=flatUnit(hit.Normal)
    if normal.Magnitude<0.2 then return nil end
    -- Ensure the normal points from the wall toward the player.
    if normal:Dot(flat(origin-hit.Position))<0 then normal=-normal end
    return {
        normal=normal,
        distance=dist,
        instance=hit.Instance,
        name=hit.Instance:GetFullName(),
        mode=kind,
        held=false
    }
end

local function bestContact()
    if not root then return nil end
    lastRayHitName="-"
    lastRayHitDistance=math.huge
    local best=nil
    local rootPos=root.Position
    for _,height in ipairs(WALL_HEIGHTS) do
        local origin=rootPos+Vector3.new(0,height,0)
        for _,dir in ipairs(radialDirections) do
            local hit=Workspace:Raycast(origin,dir*WALL_RADIUS,rayParams)
            local candidate=candidateContact(hit,origin)
            if candidate then
                -- Tiny preference for a stable contact normal at crowded corners.
                local score=candidate.distance
                if lastContact and candidate.normal:Dot(lastContact.normal)<0.70 then
                    score+=0.16
                end
                if not best or score<best.score then
                    candidate.score=score
                    best=candidate
                end
            end
        end
    end
    if best then return best end

    -- Overlap fallback: narrow rails and slats between the radial rays.
    -- Rate-limit the broader shape query on mobile to avoid FPS drops.
    if os.clock()-lastOverlapAt<0.055 then return nil end
    lastOverlapAt=os.clock()
    -- Confirm a direct unobstructed ray before using a nearby part.
    local ok,parts=pcall(function()
        return Workspace:GetPartBoundsInRadius(rootPos,WALL_RADIUS,overlapParams)
    end)
    if not ok or type(parts)~="table" then return nil end
    for _,part in ipairs(parts) do
        local valid,kind=isFenceLike(part)
        if valid then
            local got,point=pcall(function()
                return part:GetClosestPointOnSurface(rootPos)
            end)
            if got and typeof(point)=="Vector3" then
                local diff=flat(rootPos-point)
                local dist=diff.Magnitude
                if dist>0.08 and dist<CONTACT_MAX_DISTANCE
                    and math.abs(rootPos.Y-point.Y)<=2.7 then
                    local origin=rootPos+Vector3.new(0,0.12,0)
                    local direction=point-origin
                    if direction.Magnitude>0.08 then
                        local hit=Workspace:Raycast(origin,direction.Unit*(direction.Magnitude+0.14),rayParams)
                        if hit and hit.Instance==part then
                            local normal=flatUnit(hit.Normal)
                            if normal.Magnitude<0.2 then normal=diff.Unit end
                            if normal:Dot(diff)<0 then normal=-normal end
                            local candidate={
                                normal=normal,
                                distance=dist,
                                instance=part,
                                name=part:GetFullName(),
                                mode=kind.."-overlap",
                                held=false,
                                score=dist
                            }
                            if not best or candidate.score<best.score then best=candidate end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function getContact(now)
    if now-lastScanAt>=CONTACT_SCAN_INTERVAL then
        lastScanAt=now
        scanCount+=1
        cachedContact=bestContact()
        if cachedContact then
            lastContact=cachedContact
            lastContactUntil=now+CONTACT_GRACE_SECONDS
            if cachedContact.mode=="geometry" or cachedContact.mode=="geometry-overlap"
                or cachedContact.mode=="invisible-panel"
                or cachedContact.mode=="invisible-panel-overlap" then
                geometryContacts+=1
            end
        end
    end
    if cachedContact then return cachedContact end
    if lastContact and now<lastContactUntil then
        return {
            normal=lastContact.normal,
            distance=lastContact.distance,
            name=lastContact.name,
            mode=lastContact.mode,
            held=true
        }
    end
    return nil
end

local function smoothFacing(desired,dt)
    if desired.Magnitude<0.5 or not root or root.Anchored then return end
    local target=desired.Unit
    -- Smooth only facing. Do not filter the physics input or the old A/D keys.
    -- In a complete about-face, the avatar turns faster instead of feeling heavy.
    local forward=flatUnit(root.CFrame.LookVector)
    local dot=forward.Magnitude>0 and forward:Dot(target) or 1
    local response=dot<-0.55 and 0.050 or 0.067
    local alpha=1-math.exp(-dt/response)
    local frame=CFrame.lookAt(root.Position,root.Position+target)
    pcall(function()
        root.CFrame=root.CFrame:Lerp(frame,alpha)
    end)
end

local function applyAssist(contact,desired,changed,dt,now)
    if desired.Magnitude<=0.05 or not root or not humanoid then return end
    local normal=contact.normal
    if not normal or normal.Magnitude<0.5 then return end

    -- CRITICAL V3 fix: if the thumb points AWAY, never oppose its movement.
    local away=desired:Dot(normal)
    if away>0.12 then
        outwardReleases+=1
        return
    end

    local current=root.AssemblyLinearVelocity
    local horizontal=flat(current)
    local currentNormalSpeed=horizontal:Dot(normal)
    local tangentVelocity=horizontal-normal*currentNormalSpeed
    local desiredTangent=desired-normal*away
    local tangentMagnitude=desiredTangent.Magnitude

    local correctedTangent=tangentVelocity
    local reversing=false
    if tangentMagnitude>0.10 then
        local along=desiredTangent.Unit
        reversing=tangentVelocity.Magnitude>0.12
            and tangentVelocity:Dot(along)<-0.12
        local targetSpeed=math.max(tangentVelocity.Magnitude,
            math.max(0,humanoid.WalkSpeed)*WALK_SEED_FACTOR)
        local targetTangent=along*targetSpeed
        -- Full response when reversing along a fence: no old-direction brake.
        local response=humanoid.FloorMaterial==Enum.Material.Air and 0.07 or 0.045
        local steerAlpha=reversing and 1 or (1-math.exp(-dt/response))
        if contact.held then steerAlpha*=0.65 end
        correctedTangent=tangentVelocity:Lerp(targetTangent,steerAlpha)
        if reversing then reversalFrames+=1 end
    end

    -- A small inward hold to keep contact with the rail while sliding.
    -- This is NEVER applied when the player deliberately moves outward.
    local heldScale=contact.held and 0.48 or 1
    local dynamicHold=math.min(MAGNET_SPEED_CAP,
        MAGNET_INWARD_SPEED+horizontal.Magnitude*0.035)
    -- A brief release after the light impact lets the player visibly detach
    -- from the grid before the adhesion reconnects.
    if now<nextMagnetAt then dynamicHold=0 end
    local targetNormalSpeed=-dynamicHold*heldScale
    local normalAlpha=1-math.exp(-dt/MAGNET_RESPONSE)
    local correctedNormal=currentNormalSpeed
    if now>=nextMagnetAt and correctedNormal>targetNormalSpeed then
        correctedNormal+=(targetNormalSpeed-correctedNormal)*normalAlpha
    end
    local corrected=correctedTangent+normal*correctedNormal

    -- No speed multiplication on direction switches. Prevent magnet spikes.
    local oldSpeed=horizontal.Magnitude
    local allowed=math.max(oldSpeed,humanoid.WalkSpeed*1.06)+0.75
    if corrected.Magnitude>allowed and corrected.Magnitude>0 then
        corrected=corrected.Unit*allowed
    end

    if (corrected-horizontal).Magnitude>=0.025 then
        pcall(function()
            root.AssemblyLinearVelocity=Vector3.new(corrected.X,current.Y,corrected.Z)
        end)
        assistedFrames+=1
        magnetFrames+=1
    end

    -- Original small hop preserved, but not when stepping away from the fence.
    if MICRO_HOP_ENABLED and changed and not contact.held
        and humanoid.FloorMaterial~=Enum.Material.Air
        and now-lastMicroHopAt>=MICRO_HOP_COOLDOWN
        and now-lastContactHopAt>=HOP_COOLDOWN_SECONDS then
        local v=root.AssemblyLinearVelocity
        pcall(function()
            root.AssemblyLinearVelocity=Vector3.new(v.X,MICRO_HOP_SPEED,v.Z)
        end)
        lastMicroHopAt=now
    end
end


-- Arms after leaving the actual near-contact area, not after a key release.
-- This prevents repeated boosts while the avatar remains pressed against a rail.
local function considerContactHop(contact,desired,now)
    if not CONTACT_HOP_ENABLED or not root or not humanoid then return end
    local near=contact and not contact.held
        and type(contact.distance)=="number"
        and contact.distance<=HOP_MAX_CONTACT_DISTANCE

    if not near then
        if now-lastNearFenceAt>=HOP_REARM_LOST_SECONDS then
            hopArmed=true
        end
        return
    end
    lastNearFenceAt=now
    if not hopArmed or now-lastContactHopAt<HOP_COOLDOWN_SECONDS then return end
    if desired.Magnitude<0.15 then return end

    local normal=contact.normal
    if not normal or normal.Magnitude<0.5 then return end
    local inwardIntent=desired:Dot(normal)
    if inwardIntent>=-0.18 then return end

    local velocity=root.AssemblyLinearVelocity
    local horizontal=flat(velocity)
    local inwardVelocity=horizontal:Dot(normal)
    local horizontalSpeed=horizontal.Magnitude
    local grounded=humanoid.FloorMaterial~=Enum.Material.Air

    -- Ground impacts can be slow after collision. Air contacts must be moving
    -- toward the rail, so sliding nearby does not repeatedly grant an air jump.
    if grounded then
        if horizontalSpeed<1.8 then return end
    elseif inwardVelocity>=-0.35 or horizontalSpeed<3.0 then
        return
    end

    local gravity=math.max(60,Workspace.Gravity)
    local targetY=math.clamp(gravity*(HOP_TARGET_AIRTIME*0.5),10.0,19.5)
    -- Never boost an already-strong upward jump.
    if velocity.Y>=targetY-1.25 then return end

    -- Detach just slightly, stay in air briefly, then let the magnet reconnect.
    -- The outward nudge is small enough to avoid flinging the player.
    local nextHorizontal=horizontal-normal*inwardVelocity
        +normal*HOP_OUTWARD_SPEED
    local impulseApplied=pcall(function()
        root.AssemblyLinearVelocity=Vector3.new(
            nextHorizontal.X,
            math.max(velocity.Y,targetY),
            nextHorizontal.Z
        )
    end)
    if not impulseApplied then return end
    lastContactHopAt=now
    lastMicroHopAt=now
    nextMagnetAt=now+HOP_RELEASE_SECONDS
    hopArmed=false
    contactHopCount+=1
    if grounded then groundContactHops+=1 else airContactHops+=1 end
end

heartbeatConnection=RunService.Heartbeat:Connect(function(dtFromHeartbeat)
    if not enabled then return end
    if character~=player.Character then bindCharacter(player.Character) end
    if not humanoid or not root or not root.Parent then return end
    if humanoid.Health<=0 or humanoid.Sit or root.Anchored then return end

    local now=os.clock()
    local dt=math.clamp(dtFromHeartbeat or now-lastHeartbeatAt,1/240,0.05)
    lastHeartbeatAt=now
    local chord,rawX,rawZ,sweepActive=readBridge()
    local desired=intentFromChord(chord)
    local changed=(chord~=lastChord and lastChord~="-" and chord~="-")
    lastChord=chord

    -- Only orientation gets analog polish. The input/key engine is untouched.
    local visual=visualFacingIntent(desired,chord,rawX,rawZ,sweepActive)
    if visual.Magnitude>0.05 then
        smoothFacing(visual,dt)
    else
        lastFacing=Vector3.zero
    end
    if desired.Magnitude<=0.05 then
        considerContactHop(nil,desired,now)
        return
    end

    local contact=getContact(now)
    considerContactHop(contact,desired,now)
    if not contact then
        noContactFrames+=1
        return
    end
    applyAssist(contact,desired,changed,dt,now)
end)

env.LegacyGridContactAssistV1={
    Version="5.1-v31-strong-grip-contact-air-hop",
    Enabled=enabled,
    GetState=function()
        return {
            enabled=enabled,
            chord=lastChord,
            assistedFrames=assistedFrames,
            magnetFrames=magnetFrames,
            reversalFrames=reversalFrames,
            geometryContacts=geometryContacts,
            noContactFrames=noContactFrames,
            scanCount=scanCount,
            overlapPartLimit=overlapParams.MaxParts,
            mode=lastContact and lastContact.mode or "none",
            lastHitName=lastContact and lastContact.name or "-",
            lastRayHitName=lastRayHitName,
            lastRayHitDistance=lastRayHitDistance,
            lastNormal=lastContact and lastContact.normal or Vector3.zero,
            wallRadius=WALL_RADIUS,
            scanInterval=CONTACT_SCAN_INTERVAL,
            microHopEnabled=MICRO_HOP_ENABLED,
            contactHopEnabled=CONTACT_HOP_ENABLED,
            contactHopCount=contactHopCount,
            groundContactHops=groundContactHops,
            airContactHops=airContactHops,
            hopTargetAirtime=HOP_TARGET_AIRTIME,
            hopReleaseSeconds=HOP_RELEASE_SECONDS,
            magnetInwardSpeed=MAGNET_INWARD_SPEED,
            magnetSpeedCap=MAGNET_SPEED_CAP,
            outwardReleases=outwardReleases,
            hopArmed=hopArmed
        }
    end,
}

env.__LegacyGridContactAssistV1Cleanup=function()
    enabled=false
    if heartbeatConnection then pcall(function() heartbeatConnection:Disconnect() end) end
    if characterConnection then pcall(function() characterConnection:Disconnect() end) end
    if env.LegacyGridContactAssistV1 and
        env.LegacyGridContactAssistV1.Version=="5.0-v3-full-grid-adhesion-reversal-fix" then
        env.LegacyGridContactAssistV1=nil
    end
    env.__LegacyGridContactAssistV1Cleanup=nil
end
