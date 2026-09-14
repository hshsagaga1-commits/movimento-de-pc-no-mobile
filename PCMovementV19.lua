local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local HttpService=game:GetService("HttpService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local BIND_NAME="__PCMovementV19HardAim"

-- V19: V18 intact + real center-axis body lock.
-- The on-screen dot is no longer only decorative: the character yaw is physically
-- aligned to the camera-center ray using AlignOrientation (no RootPart.CFrame writes).
local src=game:HttpGet(
    "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV18.lua?_cb="
    ..HttpService:GenerateGUID(false),
    true
)
local fn,err=loadstring(src)
if not fn then error(err) end
fn()

local v18Cleanup=getgenv().__PCMobileAimCleanup
getgenv().PCMovementVersion="V19"
if getgenv().PCHardAimLockEnabled==nil then getgenv().PCHardAimLockEnabled=true end

pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local connections={}
local character
local humanoid
local root
local attachment
local align
local savedAutoRotate

local emoteAttributes={
    "IsEmoting","Emoting","EmotePlaying","PlayingEmote","DoingEmote",
    "IsDancing","Dancing","IsTaunting","Taunting"
}

local function hasTruthyAttribute(instance)
    if not instance then return false end
    for _,name in ipairs(emoteAttributes) do
        local ok,value=pcall(function() return instance:GetAttribute(name) end)
        if ok and (value==true or value==1) then return true end
    end
    return false
end

local function trackLooksLikeEmote(track)
    if not track then return false end
    local playing=false
    local weight=0
    local priority
    local looped=false
    local length=0
    local name=""
    pcall(function() playing=track.IsPlaying end)
    pcall(function() weight=track.WeightCurrent end)
    pcall(function() priority=track.Priority end)
    pcall(function() looped=track.Looped end)
    pcall(function() length=track.Length end)
    pcall(function()
        name=string.lower((track.Name or "").." "..((track.Animation and track.Animation.Name) or ""))
    end)
    if not playing or weight<=0.01 then return false end
    if string.find(name,"emote",1,true)
        or string.find(name,"dance",1,true)
        or string.find(name,"taunt",1,true)
        or string.find(name,"march",1,true)
        or string.find(name,"broom",1,true)
        or string.find(name,"tank",1,true) then
        return true
    end
    local action=false
    if priority then
        pcall(function() action=priority.Value>=Enum.AnimationPriority.Action.Value end)
    end
    return action and ((looped and length>=0.8) or length>=2.5)
end

local function isEmoting()
    if hasTruthyAttribute(character) or hasTruthyAttribute(humanoid) then return true end
    if not humanoid then return false end
    local tracks
    pcall(function()
        local animator=humanoid:FindFirstChildOfClass("Animator")
        tracks=animator and animator:GetPlayingAnimationTracks() or humanoid:GetPlayingAnimationTracks()
    end)
    if type(tracks)~="table" then return false end
    for _,track in ipairs(tracks) do
        if trackLooksLikeEmote(track) then return true end
    end
    return false
end

local function shouldRelease()
    if getgenv().PCMovementEnabled==false or getgenv().PCHardAimLockEnabled==false then return true end
    if not humanoid or humanoid.Health<=0 or not root or not root.Parent then return true end
    if isEmoting() then return true end
    local platform=false
    pcall(function() platform=humanoid.PlatformStand end)
    if platform then return true end
    local state
    pcall(function() state=humanoid:GetState() end)
    return state==Enum.HumanoidStateType.Dead
        or state==Enum.HumanoidStateType.Physics
        or state==Enum.HumanoidStateType.Ragdoll
        or state==Enum.HumanoidStateType.FallingDown
end

local function destroyLock()
    if humanoid and savedAutoRotate~=nil then
        pcall(function() humanoid.AutoRotate=savedAutoRotate end)
    end
    savedAutoRotate=nil
    if align then pcall(function() align:Destroy() end) end
    if attachment then pcall(function() attachment:Destroy() end) end
    align=nil
    attachment=nil
end

local function createLock()
    if not root or not root.Parent or not humanoid then return end
    if align and align.Parent==root and attachment and attachment.Parent==root then return end
    destroyLock()

    pcall(function() savedAutoRotate=humanoid.AutoRotate end)

    attachment=Instance.new("Attachment")
    attachment.Name="__PCHardAimAttachment"
    attachment.Parent=root

    align=Instance.new("AlignOrientation")
    align.Name="__PCHardAimOrientation"
    align.Mode=Enum.OrientationAlignmentMode.OneAttachment
    align.Attachment0=attachment
    align.RigidityEnabled=true
    align.MaxTorque=math.huge
    align.MaxAngularVelocity=math.huge
    align.Responsiveness=200
    align.Parent=root
end

local function attachCharacter(char)
    destroyLock()
    character=char
    humanoid=char:WaitForChild("Humanoid",10)
    root=char:WaitForChild("HumanoidRootPart",10)
    if humanoid and root then createLock() end
end

if player.Character then task.spawn(attachCharacter,player.Character) end
table.insert(connections,player.CharacterAdded:Connect(function(char)
    task.spawn(attachCharacter,char)
end))

table.insert(connections,player.CharacterRemoving:Connect(function()
    destroyLock()
    character=nil
    humanoid=nil
    root=nil
end))

RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Camera.Value+1,function()
    if not humanoid or not root then return end
    if not align or not align.Parent then createLock() end
    if not align then return end

    if shouldRelease() then
        align.Enabled=false
        if savedAutoRotate~=nil then pcall(function() humanoid.AutoRotate=savedAutoRotate end) end
        return
    end

    -- PC shift-lock feel: the center aim ray owns character yaw.
    -- Pitch is deliberately discarded so movement physics remain upright.
    local camera=Workspace.CurrentCamera
    if not camera then return end
    local look=camera.CFrame.LookVector
    local flat=Vector3.new(look.X,0,look.Z)
    if flat.Magnitude<1e-4 then return end

    align.Enabled=true
    pcall(function() humanoid.AutoRotate=false end)
    flat=flat.Unit
    align.CFrame=CFrame.lookAt(Vector3.zero,flat,Vector3.yAxis)
end)

getgenv().__PCMobileAimCleanup=function()
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    destroyLock()
    if v18Cleanup then pcall(v18Cleanup) end
    getgenv().__PCMobileAimCleanup=nil
end
