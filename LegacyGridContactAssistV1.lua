local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local LEGACY_PLACE_ID=96537472072550
local BIND_NAME="__LegacyGridContactAssistV1"
local CONTACT_RADIUS=2.60
local VERTICAL_NORMAL_Y_MAX=0.38
local PRESSURE_MIN=0.28
local AWAY_THRESHOLD=0.12
local MIN_TANGENT=0.40

local oldCleanup=getgenv().__LegacyGridContactAssistV1Cleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local enabled=game.PlaceId==LEGACY_PLACE_ID
local character=nil
local humanoid=nil
local root=nil
local charConn=nil
local frames=0
local assistedFrames=0
local noContactFrames=0
local awayFrames=0
local lastHitName="-"
local lastHitNormal=Vector3.zero
local lastInput=Vector3.zero
local lastOutput=Vector3.zero

local rayParams=RaycastParams.new()
rayParams.FilterType=Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater=true

local function bindCharacter(char)
    character=char
    humanoid=char and char:FindFirstChildOfClass("Humanoid") or nil
    root=char and char:FindFirstChild("HumanoidRootPart") or nil
    if char then
        if not humanoid then pcall(function() humanoid=char:WaitForChild("Humanoid",5) end) end
        if not root then pcall(function() root=char:WaitForChild("HumanoidRootPart",5) end) end
    end
    rayParams.FilterDescendantsInstances=char and {char} or {}
end

bindCharacter(player.Character)
charConn=player.CharacterAdded:Connect(bindCharacter)

local function currentChord()
    local bridge=getgenv().PCKeyboardTouchBridgeV52
    if type(bridge)=="table" and type(bridge.GetState)=="function" then
        local ok,state=pcall(bridge.GetState)
        if ok and type(state)=="table" then return tostring(state.chord or "-") end
    end
    return "?"
end

local function flatUnit(v)
    local flat=Vector3.new(v.X,0,v.Z)
    if flat.Magnitude<=1e-5 then return Vector3.zero end
    return flat.Unit
end

local function chooseSurface(origin,intended)
    local best=nil
    for i=0,15 do
        local angle=(math.pi*2)*(i/16)
        local rayDir=Vector3.new(math.cos(angle),0,math.sin(angle))*CONTACT_RADIUS
        local hit=nil
        pcall(function() hit=Workspace:Raycast(origin,rayDir,rayParams) end)
        if hit and math.abs(hit.Normal.Y)<=VERTICAL_NORMAL_Y_MAX then
            local normal=flatUnit(hit.Normal)
            if normal.Magnitude>0 then
                local dot=intended:Dot(normal)
                local tangent=intended-normal*dot
                local tangentMagnitude=tangent.Magnitude
                if dot<=AWAY_THRESHOLD and tangentMagnitude>=MIN_TANGENT then
                    local distance=(hit.Position-origin).Magnitude
                    local score=distance-(math.min(1,tangentMagnitude)*0.18)
                    if not best or score<best.score then
                        best={
                            hit=hit,
                            normal=normal,
                            dot=dot,
                            tangent=tangent,
                            tangentMagnitude=tangentMagnitude,
                            distance=distance,
                            score=score,
                        }
                    end
                end
            end
        end
    end
    return best
end

local function assistedDirection(intended,candidate)
    if not candidate then return nil,"no_contact" end
    if candidate.dot>AWAY_THRESHOLD then return nil,"away" end
    if candidate.tangentMagnitude<MIN_TANGENT then return nil,"low_tangent" end

    local inward=math.max(0,-candidate.dot)
    if inward>=PRESSURE_MIN then
        return intended,"already_inward"
    end

    local desired=candidate.tangent-candidate.normal*PRESSURE_MIN
    if desired.Magnitude<=1e-5 then return nil,"degenerate" end
    if desired.Magnitude>1 then desired=desired.Unit end
    return desired,"assist"
end

RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Input.Value+12,function()
    frames+=1
    if not enabled then return end
    if character~=player.Character then bindCharacter(player.Character) end
    if not humanoid or not root or not root.Parent then return end

    local chord=currentChord()
    if chord=="-" then return end

    local rawMove=Vector3.new(humanoid.MoveDirection.X,0,humanoid.MoveDirection.Z)
    local magnitude=math.min(1,rawMove.Magnitude)
    if magnitude<=0.05 then return end
    local intended=rawMove.Unit
    lastInput=intended

    local origin=root.Position+Vector3.new(0,0.65,0)
    local candidate=chooseSurface(origin,intended)
    if not candidate then
        noContactFrames+=1
        lastHitName="-"
        return
    end

    lastHitName=candidate.hit.Instance and candidate.hit.Instance:GetFullName() or "?"
    lastHitNormal=candidate.normal

    local adjusted,reason=assistedDirection(intended,candidate)
    if not adjusted then
        if reason=="away" then awayFrames+=1 end
        return
    end

    if reason=="assist" then
        local output=adjusted*magnitude
        lastOutput=output
        assistedFrames+=1
        pcall(function() player:Move(output,false) end)
    end
end)

getgenv().LegacyGridContactAssistV1={
    Version="1.0-contact-normal-command-bias-no-speed-boost",
    Enabled=enabled,
    GetState=function()
        return {
            enabled=enabled,
            frames=frames,
            assistedFrames=assistedFrames,
            noContactFrames=noContactFrames,
            awayFrames=awayFrames,
            lastHitName=lastHitName,
            lastHitNormal=lastHitNormal,
            lastInput=lastInput,
            lastOutput=lastOutput,
            pressureMin=PRESSURE_MIN,
            contactRadius=CONTACT_RADIUS,
        }
    end,
}

getgenv().__LegacyGridContactAssistV1Cleanup=function()
    enabled=false
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    if charConn then pcall(function() charConn:Disconnect() end) end
    getgenv().LegacyGridContactAssistV1=nil
    getgenv().__LegacyGridContactAssistV1Cleanup=nil
end
