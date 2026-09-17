local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")
local StarterGui=game:GetService("StarterGui")

local player=Players.LocalPlayer
local LEGACY_PLACE_ID=96537472072550
local SAMPLE_INTERVAL=0.05
local DURATION=15
local CONTACT_RADIUS=3.25
local VERTICAL_NORMAL_Y_MAX=0.38

local oldCleanup=getgenv().__LegacyGridProbeV1Cleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end

local running=true
local started=os.clock()
local lastSample=-math.huge
local lastSpeed=nil
local lines={}
local connection=nil
local charConn=nil
local character=nil
local humanoid=nil
local root=nil

local rayParams=RaycastParams.new()
rayParams.FilterType=Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater=true

local function safeNotify(text)
    pcall(function()
        StarterGui:SetCore("SendNotification",{Title="Legacy Grid Probe",Text=text,Duration=5})
    end)
end

local function fmt(v)
    if typeof(v)=="Vector3" then
        return string.format("%.3f,%.3f,%.3f",v.X,v.Y,v.Z)
    end
    if type(v)=="number" then return string.format("%.4f",v) end
    return tostring(v)
end

local function safeProperty(inst,name,fallback)
    if not inst then return fallback end
    local ok,value=pcall(function() return inst[name] end)
    return ok and tostring(value) or fallback
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
end

local function chord()
    local bridge=getgenv().PCKeyboardTouchBridgeV52
    if type(bridge)=="table" and type(bridge.GetState)=="function" then
        local ok,state=pcall(bridge.GetState)
        if ok and type(state)=="table" and state.chord then return tostring(state.chord) end
    end
    return "?"
end

local function crouchState()
    local pg=player:FindFirstChildOfClass("PlayerGui")
    local controlsGui=pg and pg:FindFirstChild("ControlsGui",true)
    local pcFrame=controlsGui and controlsGui:FindFirstChild("PCFrame",true)
    local stand=pcFrame and pcFrame:FindFirstChild("Stand",true)
    if stand and stand:IsA("GuiObject") then
        return stand.Visible and "crouched" or "standing"
    end
    return "unknown"
end

local function nearestVerticalHit(origin)
    local best=nil
    for i=0,11 do
        local angle=(math.pi*2)*(i/12)
        local dir=Vector3.new(math.cos(angle),0,math.sin(angle))*CONTACT_RADIUS
        local hit=nil
        pcall(function() hit=Workspace:Raycast(origin,dir,rayParams) end)
        if hit and math.abs(hit.Normal.Y)<=VERTICAL_NORMAL_Y_MAX then
            local distance=(hit.Position-origin).Magnitude
            if not best or distance<best.distance then
                best={
                    hit=hit,
                    distance=distance,
                    direction=dir.Unit,
                }
            end
        end
    end
    return best
end

local function finish(reason)
    if not running then return end
    running=false
    if connection then pcall(function() connection:Disconnect() end) end
    if charConn then pcall(function() charConn:Disconnect() end) end
    table.insert(lines,"END\treason="..tostring(reason))
    local report=table.concat(lines,"\n")
    getgenv().LegacyGridProbeReport=report
    if setclipboard then pcall(setclipboard,report) end
    safeNotify("Finalizado. Relatório copiado quando possível.")
end

getgenv().__LegacyGridProbeV1Cleanup=function()
    finish("cleanup")
    getgenv().__LegacyGridProbeV1Cleanup=nil
end

if game.PlaceId~=LEGACY_PLACE_ID then
    table.insert(lines,"ERROR\twrong_place="..tostring(game.PlaceId))
    finish("not_legacy")
    return
end

bindCharacter(player.Character)
charConn=player.CharacterAdded:Connect(bindCharacter)
table.insert(lines,"HEADER\tversion=1.1 duration="..DURATION.." contactRadius="..CONTACT_RADIUS)
table.insert(lines,"FIELDS\tt,chord,moveDirection,velocity,horizontalSpeed,speedDelta,cameraLook,cameraRight,hitName,hitClass,hitMaterial,hitCanCollide,hitTransparency,hitNormal,hitDistance,rayDirection,crouch,hipHeight,walkSpeed")
safeNotify("15s: usa a grade como no PC; em pé, agachado e ao contrário se der.")

connection=RunService.Heartbeat:Connect(function()
    if not running then return end
    local now=os.clock()
    if now-started>=DURATION then
        finish("duration")
        return
    end
    if now-lastSample<SAMPLE_INTERVAL then return end
    lastSample=now

    if character~=player.Character then bindCharacter(player.Character) end
    if not root or not humanoid or not root.Parent then return end

    local camera=Workspace.CurrentCamera
    if not camera then return end

    local velocity=root.AssemblyLinearVelocity
    local horizontalSpeed=Vector3.new(velocity.X,0,velocity.Z).Magnitude
    local speedDelta=lastSpeed and (horizontalSpeed-lastSpeed) or 0
    lastSpeed=horizontalSpeed

    local origin=root.Position+Vector3.new(0,0.8,0)
    local near=nearestVerticalHit(origin)
    local hitName="-"
    local hitClass="-"
    local hitMaterial="-"
    local hitCanCollide="-"
    local hitTransparency="-"
    local hitNormal=Vector3.zero
    local hitDistance=-1
    local rayDirection=Vector3.zero

    if near then
        local inst=near.hit.Instance
        hitName=inst and inst:GetFullName() or "?"
        hitClass=inst and inst.ClassName or "?"
        hitMaterial=tostring(near.hit.Material)
        hitCanCollide=safeProperty(inst,"CanCollide","n/a")
        hitTransparency=safeProperty(inst,"Transparency","n/a")
        hitNormal=near.hit.Normal
        hitDistance=near.distance
        rayDirection=near.direction
    end

    local fields={
        string.format("%.3f",now-started),
        chord(),
        fmt(humanoid.MoveDirection),
        fmt(velocity),
        fmt(horizontalSpeed),
        fmt(speedDelta),
        fmt(camera.CFrame.LookVector),
        fmt(camera.CFrame.RightVector),
        hitName,
        hitClass,
        hitMaterial,
        hitCanCollide,
        hitTransparency,
        fmt(hitNormal),
        fmt(hitDistance),
        fmt(rayDirection),
        crouchState(),
        fmt(humanoid.HipHeight),
        fmt(humanoid.WalkSpeed),
    }
    table.insert(lines,"S\t"..table.concat(fields,"\t"))
end)

getgenv().LegacyGridProbeV1={
    Version="1.1-safe-surface-properties",
    Stop=function() finish("manual") end,
    GetReport=function() return table.concat(lines,"\n") end,
}
