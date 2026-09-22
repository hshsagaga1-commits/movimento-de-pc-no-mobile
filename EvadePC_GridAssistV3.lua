-- Evade Grid Assist V3
-- Standalone grid/ledge contact helper.
-- Preserves existing tangential momentum and only corrects contact-normal velocity.
-- Rapid 180-degree W camera turns get a short PC-like momentum-preservation window.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local ENV=(type(getgenv)=="function" and getgenv()) or _G

local VERSION="EvadePC-GridAssist-V3-tangent-preserve-w-reverse"
local EVADE_GAME_ID=3647333358

local WALL_RADIUS=4.00
local WALL_RAYS=32
local WALL_NORMAL_Y_MAX=0.48
local WALL_HEIGHTS={-0.55,-0.10,0.35,0.80,1.25}

local EDGE_PROBE_RADIUS=2.15
local EDGE_SAMPLES=20
local EDGE_RAY_UP=2.75
local EDGE_RAY_DOWN=7.00
local EDGE_DROP_MIN=0.55

local WALL_INWARD_SPEED=5.25
local EDGE_INWARD_SPEED=4.25
local CONTACT_GRACE_SECONDS=0.24
local MIN_INPUT=0.10

local YAW_WINDOW_SECONDS=0.22
local REVERSE_TRIGGER_DEG=105
local REVERSE_HOLD_SECONDS=0.24
local PEAK_DECAY_PER_SECOND=0.85
local MIN_REVERSE_SPEED=6.0

local old=ENV.__EvadePCGridAssistV3Cleanup
if type(old)=="function" then pcall(old) end
local oldV2=ENV.__EvadePCGridAssistV2Cleanup
if type(oldV2)=="function" then pcall(oldV2) end

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
local lastCameraForward=nil
local yawWindowForward=nil
local yawWindowStart=os.clock()
local yawAccumDegrees=0
local recentTangentPeak=0
local reversePreserveUntil=-math.huge
local reversePreserveSpeed=0
local lastAssistClock=os.clock()
local reverseTriggers=0
local reverseFrames=0
local velocityWrites=0

local ACTIVE_CHORDS={
    ["W"]=true,
    ["W+A"]=true,
    ["W+D"]=true,
    ["A"]=true,
    ["D"]=true,
    ["S"]=true,
}

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
    lastCameraForward=nil
    yawWindowForward=nil
    yawWindowStart=os.clock()
    yawAccumDegrees=0
    recentTangentPeak=0
    reversePreserveUntil=-math.huge
    reversePreserveSpeed=0
    lastAssistClock=os.clock()
end

bindCharacter(player.Character)
characterConnection=player.CharacterAdded:Connect(bindCharacter)

local function readChord()
    local joystick=ENV.EvadePCJoystickV7 or ENV.EvadePCJoystickV6 or ENV.EvadePCJoystickV5 or ENV.EvadePCJoystickV4 or ENV.EvadePCJoystickV3 or ENV.EvadePCJoystickV2
    if type(joystick)=="table" and type(joystick.GetState)=="function" then
        local ok,state=pcall(joystick.GetState)
        if ok and type(state)=="table" then
            return tostring(state.chord or "-")
        end
    end
    return "-"
end

local function desiredMove(chord)
    local camera=Workspace.CurrentCamera
    local move=humanoid and flat(humanoid.MoveDirection) or Vector3.zero

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
        elseif chord=="S" then
            desired=-forward
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
        local sample=root.Position+radial*EDGE_PROBE_RADIUS
        local hit=downwardHit(sample)

        local isDrop=false
        local drop=EDGE_RAY_DOWN

        if not hit then
            isDrop=true
        else
            drop=centerY-hit.Position.Y
            if drop>=EDGE_DROP_MIN then isDrop=true end
        end

        if isDrop then
            outwardSum+=radial
            dropCount+=1
            nearestDrop=math.min(nearestDrop,drop)
        end
    end

    if dropCount==0 or outwardSum.Magnitude<=0.20 then return nil end

    return {
        normal=outwardSum.Unit,
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

local function updateReverseWindow(now,chord,contactNormal,tangentSpeed)
    local camera=Workspace.CurrentCamera
    local forward=camera and flatUnit(camera.CFrame.LookVector) or Vector3.zero

    local dt=math.max(0,now-lastAssistClock)
    lastAssistClock=now

    if recentTangentPeak>0 and dt>0 then
        recentTangentPeak*=math.exp(-PEAK_DECAY_PER_SECOND*dt)
    end
    recentTangentPeak=math.max(recentTangentPeak,tangentSpeed)

    if forward.Magnitude>0 then
        if not yawWindowForward
            or now-yawWindowStart>YAW_WINDOW_SECONDS then
            yawWindowStart=now
            yawWindowForward=forward
            yawAccumDegrees=0
        else
            local dot=math.clamp(yawWindowForward:Dot(forward),-1,1)
            yawAccumDegrees=math.deg(math.acos(dot))
        end
        lastCameraForward=forward
    end

    -- IMPORTANT: this is W-only. S never uses the reverse preservation route.
    if chord=="W"
        and yawAccumDegrees>=REVERSE_TRIGGER_DEG
        and recentTangentPeak>=MIN_REVERSE_SPEED then
        reversePreserveUntil=now+REVERSE_HOLD_SECONDS
        reversePreserveSpeed=recentTangentPeak
        reverseTriggers+=1

        -- Start a new yaw window from the flipped orientation so one turn cannot
        -- retrigger every frame.
        yawWindowStart=now
        yawWindowForward=forward.Magnitude>0 and forward or nil
        yawAccumDegrees=0
    elseif chord~="W" then
        reversePreserveUntil=-math.huge
        reversePreserveSpeed=0
        yawAccumDegrees=0
        yawWindowStart=now
        yawWindowForward=forward.Magnitude>0 and forward or nil
    end
end

local function applyAssist(contact,desired,chord,now)
    local velocity=root.AssemblyLinearVelocity
    local horizontal=flat(velocity)
    local normal=flatUnit(contact.normal)
    if normal.Magnitude<=0 then return end

    -- Split velocity into tangent + contact-normal components.
    -- Tangent is the speed the game already created: never rebuild/cap it.
    local normalSpeed=horizontal:Dot(normal)
    local tangent=horizontal-normal*normalSpeed
    local tangentSpeed=tangent.Magnitude

    updateReverseWindow(now,chord,normal,tangentSpeed)

    -- PC-style fast reverse: while W stays held and the camera turns ~180 degrees
    -- quickly, preserve the recent tangent magnitude but orient it to W's new
    -- camera-relative tangent. No S special-case exists here.
    if chord=="W" and now<=reversePreserveUntil and reversePreserveSpeed>0 then
        local desiredTangent=desired-normal*desired:Dot(normal)
        if desiredTangent.Magnitude>=MIN_INPUT then
            local targetSpeed=math.max(tangentSpeed,reversePreserveSpeed)
            tangent=desiredTangent.Unit*targetSpeed
            tangentSpeed=targetSpeed
            reverseFrames+=1
        end
    end

    -- Only correct the outward/insufficient inward component needed to stay in
    -- contact. If physics already has stronger inward velocity, preserve it.
    local inward=(contact.mode=="edge") and EDGE_INWARD_SPEED or WALL_INWARD_SPEED
    local correctedNormal=math.min(normalSpeed,-inward)
    local corrected=tangent+normal*correctedNormal

    if (corrected-horizontal).Magnitude<=0.001 then
        return
    end

    pcall(function()
        root.AssemblyLinearVelocity=Vector3.new(corrected.X,velocity.Y,corrected.Z)
        velocityWrites+=1
    end)

    assistedFrames+=1
end

heartbeatConnection=RunService.Heartbeat:Connect(function()
    if not enabled then return end
    if character~=player.Character then bindCharacter(player.Character) end
    if not humanoid or not root or not root.Parent or humanoid.Health<=0 then return end

    local chord=readChord()
    activeChord=chord
    local desired=desiredMove(chord)

    if not ACTIVE_CHORDS[chord] and desired.Magnitude<=0.05 then return end

    local contact=getContact(os.clock())
    if not contact then
        noContactFrames+=1
        return
    end

    if contact.mode=="edge" then edgeFrames+=1 else wallFrames+=1 end
    applyAssist(contact,desired,chord,os.clock())
end)

local api={
    Version=VERSION,
    SetEnabled=function(value) enabled=value~=false end,
    IsEnabled=function() return enabled end,
    GetState=function()
        return {
            chord=activeChord,
            mode=lastMode,
            assistedFrames=assistedFrames,
            wallFrames=wallFrames,
            edgeFrames=edgeFrames,
            noContactFrames=noContactFrames,
            lastHitName=lastHitName,
            lastNormal=lastNormal,
            lastHeight=lastHeight,
            yawAccumDegrees=yawAccumDegrees,
            recentTangentPeak=recentTangentPeak,
            reversePreserveRemaining=math.max(0,reversePreserveUntil-os.clock()),
            reversePreserveSpeed=reversePreserveSpeed,
            reverseTriggers=reverseTriggers,
            reverseFrames=reverseFrames,
            velocityWrites=velocityWrites,
            preservesTangentialVelocity=true,
            reverseRouteChord="W",
        }
    end,
}

ENV.EvadePCGridAssistV3=api
ENV.__EvadePCGridAssistV3Cleanup=function()
    enabled=false
    if heartbeatConnection then pcall(function() heartbeatConnection:Disconnect() end) end
    if characterConnection then pcall(function() characterConnection:Disconnect() end) end
    ENV.EvadePCGridAssistV3=nil
    ENV.__EvadePCGridAssistV3Cleanup=nil
end

return api
