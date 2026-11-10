-- ClassicNativeGridAssistV1.lua
-- Native mobile adaptation of V3.1 preserved/light grid diagnostics and facing.
-- Reads Humanoid.MoveDirection, NOT PC key chords. Does not force velocity or jumps.
-- Never writes facing when Humanoid.AutoRotate owns avatar orientation.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")
local PhysicsService=game:GetService("PhysicsService")
local HttpService=game:GetService("HttpService")

local player=Players.LocalPlayer
local EVADE_GAME_ID=3647333358
local env=getgenv()
local previousCleanup=env.__ClassicNativeGridAssistV1Cleanup
if type(previousCleanup)=="function" then pcall(previousCleanup) end

local enabled=game.GameId==EVADE_GAME_ID
local character,humanoid,root=nil,nil,nil
local characterConnection,heartbeatConnection=nil,nil

-- Eight azimuths at three heights; less work than the original PC sensor.
-- Local overlap fills the angular gaps; at most eight candidates are ray-checked.
local WALL_RADIUS=4.60
local WALL_RAYS=8
local WALL_HEIGHTS={-0.65,0.52,1.15}
local CONTACT_MAX_DISTANCE=2.85
local CONTACT_SCAN_INTERVAL=1/12
local CONTACT_GRACE_SECONDS=0.105 -- display/history only, never force or jump
local WALL_NORMAL_Y_MAX=0.54
local OVERLAP_SCAN_INTERVAL=0.12
local OVERLAP_RAY_LIMIT=8

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
pcall(function() rayParams.RespectCanCollide=true end)

local overlapParams=OverlapParams.new()
overlapParams.FilterType=Enum.RaycastFilterType.Exclude
overlapParams.MaxParts=48
pcall(function() overlapParams.RespectCanCollide=true end)

local radialDirections={}
for i=0,WALL_RAYS-1 do
    local angle=math.pi*2*i/WALL_RAYS
    radialDirections[#radialDirections+1]=Vector3.new(math.cos(angle),0,math.sin(angle))
end

local lastContact,cachedContact,currentContact=nil,nil,nil
local lastContactUntil,lastScanAt,lastOverlapAt=-math.huge,-math.huge,-math.huge
local lastHeartbeatAt=os.clock()
local lastChord="-"
local lastFacing=Vector3.zero
local noContactFrames,geometryContacts,scanCount,contactFrames=0,0,0,0
local rayCount,overlapCount,bodyQueryCount=0,0,0
local lastRayHitName,lastRayHitDistance="-",math.huge
local touchingParts,bodyParts={},{}
local lastBodyRefresh=-math.huge
local lastObservedY,lastNativePulses=nil,nil
local lastRealContactAt=-math.huge
local verticalChangesNearGrid=0
local config=type(env.PCMovementV31PreservedConfig)=="table" and env.PCMovementV31PreservedConfig or {}
local diagnostics=config.Diagnostics==true
local records,recordNext,recordSize={},1,0
local lastLogAt=-math.huge
local function record(kind,details)
    if not diagnostics then return end
    details=details or {}
    details.kind,details.time=kind,os.clock()
    records[recordNext]=details
    recordNext=recordNext%160+1
    recordSize=math.min(160,recordSize+1)
end
local function logs()
    local out={}
    local start=recordSize==160 and recordNext or 1
    for offset=0,recordSize-1 do out[#out+1]=records[(start+offset-1)%160+1] end
    return out
end

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
    if not part or not part:IsA("BasePart") or not part.CanCollide then return false,"non-solid" end
    if nameMatches(part,EXCLUDE_TOKENS) then return false,"boundary" end
    local ancestor=part.Parent
    for _=1,4 do
        if not ancestor then break end
        if ancestor:FindFirstChildOfClass("Humanoid") then return false,"character" end
        ancestor=ancestor.Parent
    end
    if part:IsA("TrussPart") then return false,"climbable" end
    local sz=part.Size
    local thin,wide=math.min(sz.X,sz.Z),math.max(sz.X,sz.Z)
    if sz.Y<=0.90 and thin>2.4 then return false,"floor" end
    if nameMatches(part,FENCE_TOKENS) then return true,"named" end
    local upright=sz.Y>=1.25 and sz.Y<=38
    local sensibleWidth=wide<=72
    if nameMatches(part,COLLISION_TOKENS) and upright and thin<=2.0 and sensibleWidth then
        return true,"hitbox"
    end
    local likelyFence=part.Material==Enum.Material.Metal
        or part.Material==Enum.Material.DiamondPlate
        or (part.Transparency>=0.12 and part.Transparency<=0.96)
    -- In V3.1 this followed the upright rejection and was unreachable.
    local horizontalRail=sz.Y<=0.65 and thin<=0.52 and wide>=1.40 and wide<=72
        and (likelyFence or part.Material==Enum.Material.Plastic)
    if horizontalRail then return true,"horizontal-rail" end
    if not upright or not sensibleWidth then return false,"none" end
    local shape=thin<=0.78 and (wide>=0.10 or sz.Y>=2.0)
    local plainSlat=thin<=0.42 and wide<=1.10 and sz.Y>=1.45
    -- MeshPart alone is not evidence: ordinary mesh walls used to match too.
    if shape and (likelyFence or plainSlat) then return true,"geometry" end
    if thin<=1.55 and part.Transparency>=0.96 then return true,"invisible-panel" end
    return false,"none"
end

local function readPhysicalContacts(now)
    touchingParts={}
    if not character then return end
    if now-lastBodyRefresh>=0.5 then
        lastBodyRefresh=now
        bodyParts={}
        for _,part in ipairs(character:GetChildren()) do
            if #bodyParts>=24 then break end
            if part:IsA("BasePart") then bodyParts[#bodyParts+1]=part end
        end
    end
    local reads,checked=0,0
    for _,body in ipairs(bodyParts) do
        if body.Parent==character and body.CanCollide then
            reads+=1
            if reads>4 then break end
            bodyQueryCount+=1
            local ok,parts=pcall(function() return body:GetTouchingParts() end)
            if ok then
                for _,part in ipairs(parts) do
                    checked+=1
                    if checked>48 then return end
                    local valid=isFenceLike(part)
                    if valid then
                        local got,collidable=pcall(function()
                            return PhysicsService:CollisionGroupsAreCollidable(body.CollisionGroup,part.CollisionGroup)
                        end)
                        if got and collidable then touchingParts[part]=true end
                    end
                end
            end
        end
    end
end

local function cast(origin,direction)
    rayCount+=1
    return Workspace:Raycast(origin,direction,rayParams)
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
    if root then
        pcall(function()
            rayParams.CollisionGroup=root.CollisionGroup
            overlapParams.CollisionGroup=root.CollisionGroup
        end)
    end
    lastContact=nil
    cachedContact=nil
    currentContact=nil
    touchingParts={}
    bodyParts={}
    lastBodyRefresh=-math.huge
    lastObservedY,lastNativePulses=nil,nil
    lastRealContactAt=-math.huge
    lastContactUntil=-math.huge
    lastScanAt=-math.huge
    lastOverlapAt=-math.huge
    lastChord="-"
    lastFacing=Vector3.zero

end
bindCharacter(player.Character)
characterConnection=player.CharacterAdded:Connect(bindCharacter)

local function readBridge()
    local boost = env.ClassicNativeBoostV1
    if type(boost) == "table" and type(boost.ReadInput) == "function" then
        local x, z = boost.ReadInput()
        return "CLASSIC", x, z, false, 0
    end
    return "NATIVE", 0, 0, false, 0
end

local function intentFromChord(_)
    -- The native controller already transformed input relative to the camera.
    -- Re-quantizing it as W/A/S/D would undo the benefit of the original stick.
    if not humanoid then return Vector3.zero end
    return flatUnit(humanoid.MoveDirection)
end

local function visualFacingIntent(desired, _, _, _, _)
    return desired
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
        held=false,
        touching=touchingParts[hit.Instance]==true,
        observedAt=lastScanAt
    }
end

local function bestContact()
    if not root then return nil end
    lastRayHitName,lastRayHitDistance="-",math.huge
    local now=os.clock()
    readPhysicalContacts(now)
    local rootPos=root.Position
    local best=nil
    -- Real collidable body contact is stronger evidence than a nearby ray.
    -- Top/edge contact on a narrow rail is included, without treating the floor as a grid.
    for part in pairs(touchingParts) do
        local valid,kind=isFenceLike(part)
        if valid then
            local point=part.Position
            pcall(function() point=part:GetClosestPointOnSurface(rootPos) end)
            local distance=(rootPos-point).Magnitude
            local candidate={normal=flatUnit(rootPos-point),distance=distance,instance=part,
                name=part:GetFullName(),mode=kind.."-body-contact",held=false,touching=true,
                observedAt=now,score=distance}
            if not best or candidate.score<best.score then best=candidate end
        end
    end
    if best then return best end
    for _,height in ipairs(WALL_HEIGHTS) do
        local origin=rootPos+Vector3.new(0,height,0)
        for _,direction in ipairs(radialDirections) do
            local candidate=candidateContact(cast(origin,direction*WALL_RADIUS),origin)
            if candidate then
                local score=candidate.distance
                if lastContact and candidate.normal:Dot(lastContact.normal)<0.70 then score+=0.16 end
                candidate.score=score
                if not best or score<best.score then best=candidate end
            end
        end
    end
    if now-lastOverlapAt<OVERLAP_SCAN_INTERVAL then return best end
    lastOverlapAt=now
    overlapCount+=1
    local ok,parts=pcall(function()
        return Workspace:GetPartBoundsInRadius(rootPos,WALL_RADIUS,overlapParams)
    end)
    if not ok or type(parts)~="table" then return best end
    local candidates={}
    for index,part in ipairs(parts) do
        if index>48 then break end
        local valid=isFenceLike(part)
        if valid then
            local got,point=pcall(function() return part:GetClosestPointOnSurface(rootPos) end)
            if got and typeof(point)=="Vector3" then
                local distance=(point-rootPos).Magnitude
                if distance>0.08 and distance<WALL_RADIUS then
                    candidates[#candidates+1]={part=part,point=point,distance=distance}
                end
            end
        end
    end
    table.sort(candidates,function(a,b) return a.distance<b.distance end)
    local origin=rootPos+Vector3.new(0,0.12,0)
    for index,item in ipairs(candidates) do
        if index>OVERLAP_RAY_LIMIT then break end
        local direction=item.point-origin
        if direction.Magnitude>0.08 then
            local hit=cast(origin,direction.Unit*(direction.Magnitude+0.14))
            if hit and hit.Instance==item.part then
                local candidate=candidateContact(hit,origin)
                if candidate then
                    candidate.mode=candidate.mode.."-overlap"
                    candidate.score=candidate.distance
                    if not best or candidate.score<best.score then best=candidate end
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
            if string.find(cachedContact.mode,"geometry",1,true)
                or string.find(cachedContact.mode,"invisible-panel",1,true) then
                geometryContacts+=1
            end
        end
    end
    if cachedContact and cachedContact.instance and cachedContact.instance.Parent
        and cachedContact.instance.CanCollide then return cachedContact end
    if lastContact and now<lastContactUntil then
        return {
            normal=lastContact.normal,
            distance=lastContact.distance,
            name=lastContact.name,
            mode=lastContact.mode,
            held=true,
            touching=false,
            observedAt=lastScanAt
        }
    end
    return nil
end

local function smoothFacing(desired,dt)
    if desired.Magnitude<0.5 or not root or root.Anchored
        or not humanoid or humanoid.AutoRotate then return end
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

-- Observe the real contact/jump sequence. The original bridge remains the only
-- Space sender; this module cannot fabricate an air hop or race its 200ms burst.
local function observeContact(contact,now,jumpPulses)
    local velocity=root.AssemblyLinearVelocity
    local confirmed=contact and not contact.held and contact.touching==true
    if confirmed then lastRealContactAt=now end
    if lastObservedY and velocity.Y-lastObservedY>=0.75 and now-lastRealContactAt<=0.20 then
        verticalChangesNearGrid+=1
        record("vertical_change_near_grid",{before=lastObservedY,after=velocity.Y,
            nativeJumpPulseChanged=lastNativePulses~=nil and jumpPulses~=lastNativePulses,
            grounded=humanoid.FloorMaterial~=Enum.Material.Air,source="unconfirmed"})
    end
    lastObservedY,lastNativePulses=velocity.Y,jumpPulses
    if diagnostics and now-lastLogAt>=0.15 then
        lastLogAt=now
        record("contact_sample",{chord=lastChord,horizontal=flat(velocity).Magnitude,vertical=velocity.Y,
            grounded=humanoid.FloorMaterial~=Enum.Material.Air,nearby=contact~=nil,
            contactConfirmed=confirmed and true or false,held=contact and contact.held or false,
            hit=contact and contact.name or "-",mode=contact and contact.mode or "none",jumpPulses=jumpPulses})
    end
end

heartbeatConnection=RunService.Heartbeat:Connect(function(dtFromHeartbeat)
    if not enabled then return end
    if character~=player.Character then bindCharacter(player.Character) end
    if not humanoid or not root or not root.Parent then return end
    if humanoid.Health<=0 or humanoid.Sit or root.Anchored then return end

    local now=os.clock()
    local dt=math.clamp(dtFromHeartbeat or now-lastHeartbeatAt,1/240,0.05)
    lastHeartbeatAt=now
    local chord,rawX,rawZ,sweepActive,jumpPulses=readBridge()
    local desired=intentFromChord(chord)
    lastChord=chord

    -- Only orientation gets analog polish. The input/key engine is untouched.
    local visual=visualFacingIntent(desired,chord,rawX,rawZ,sweepActive)
    if visual.Magnitude>0.05 then
        smoothFacing(visual,dt)
    else
        lastFacing=Vector3.zero
    end
    if desired.Magnitude<=0.05 then
        currentContact=nil
        return
    end

    local contact=getContact(now)
    currentContact=contact
    observeContact(contact,now,jumpPulses)
    if not contact then
        noContactFrames+=1
        return
    end
    contactFrames+=1 -- observation, not a velocity correction
end)

local api={
    Version="1.0-native-classic-light-contact",
    Enabled=enabled,
    SetDiagnostics=function(value) diagnostics=value==true return diagnostics end,
    GetLogs=logs,
    GetState=function()
        return {
            enabled=enabled,chord=lastChord,contactFrames=contactFrames,geometryContacts=geometryContacts,
            noContactFrames=noContactFrames,scanCount=scanCount,overlapPartLimit=overlapParams.MaxParts,
            mode=currentContact and currentContact.mode or "none",
            lastHitName=currentContact and currentContact.name or "-",
            lastRayHitName=lastRayHitName,lastRayHitDistance=lastRayHitDistance,
            lastNormal=currentContact and currentContact.normal or Vector3.zero,
            contactConfirmed=currentContact~=nil and not currentContact.held and currentContact.touching==true,
            contactSampleAge=lastScanAt~=-math.huge and math.max(0,os.clock()-lastScanAt) or nil,
            wallRadius=WALL_RADIUS,scanInterval=CONTACT_SCAN_INTERVAL,
            raysTotal=rayCount,overlapQueries=overlapCount,bodyQueries=bodyQueryCount,
            raycastBudgetPerScan=WALL_RAYS*#WALL_HEIGHTS+OVERLAP_RAY_LIMIT,
            horizontalWrites=0,verticalWrites=0,magnetFrames=0,
            microHopEnabled=false,contactHopEnabled=false,nativeJumpUnchanged=true,
            verticalChangesNearGrid=verticalChangesNearGrid,diagnostics=diagnostics,
            visualFacing="native-only-when-auto-rotate-disabled",physicsValidation="on-device-required"
        }
    end,
}
api.SetEnabled=function(value)
    enabled=(value==true and game.GameId==EVADE_GAME_ID)
    api.Enabled=enabled
    if not enabled then currentContact=nil end
    return enabled
end
api.ExportDiagnostics=function(filename)
    local function scalarState(name)
        local object=env[name]
        if type(object)~="table" or type(object.GetState)~="function" then return nil end
        local ok,value=pcall(object.GetState)
        if not ok or type(value)~="table" then return nil end
        local out={}
        for key,item in pairs(value) do
            local kind=type(item)
            if type(key)=="string" and (kind=="boolean" or kind=="string"
                or (kind=="number" and item==item and math.abs(item)<math.huge)) then
                out[key]=item
            end
        end
        return out
    end
    local state=api.GetState()
    state.lastNormal={x=state.lastNormal.X,y=state.lastNormal.Y,z=state.lastNormal.Z}
    if state.lastRayHitDistance==math.huge then state.lastRayHitDistance=nil end
    local json=HttpService:JSONEncode({state=state,events=logs(),
        boost=scalarState("ClassicNativeBoostV1")})
    filename=filename or "ClassicNative_Assist_Log.json"
    if type(writefile)=="function" then
        local ok,message=pcall(writefile,filename,json)
        if ok then return true,filename end
        return false,tostring(message),json
    end
    return false,"writefile unavailable",json
end
env.ClassicNativeGridAssistV1=api
local cleanup
cleanup=function()
    enabled=false
    api.Enabled=false
    if heartbeatConnection then pcall(function() heartbeatConnection:Disconnect() end) end
    if characterConnection then pcall(function() characterConnection:Disconnect() end) end
    if env.ClassicNativeGridAssistV1==api then env.ClassicNativeGridAssistV1=nil end
    if env.__ClassicNativeGridAssistV1Cleanup==cleanup then env.__ClassicNativeGridAssistV1Cleanup=nil end
end
env.__ClassicNativeGridAssistV1Cleanup=cleanup
