local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")

local player=Players.LocalPlayer
local BIND_NAME="__PCMovementV20NativeHardCenter"

-- V20: go back to the proven V18 behavior and harden the CENTER through
-- Roblox's native camera/mouse-lock path. No AlignOrientation, no RootPart CFrame.
local src=game:HttpGet(
    "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV18.lua?_cb="
    ..HttpService:GenerateGUID(false),
    true
)
local fn,err=loadstring(src)
if not fn then error(err) end
fn()

local v18Cleanup=getgenv().__PCMobileAimCleanup
getgenv().PCMovementVersion="V20"
if getgenv().PCNativeHardCenterEnabled==nil then getgenv().PCNativeHardCenterEnabled=true end

pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local playerModule
local cameras
local userGameSettings
local oldMouseBehavior
local oldRotationType

pcall(function()
    oldMouseBehavior=UserInputService.MouseBehavior
end)
pcall(function()
    userGameSettings=UserSettings():GetService("UserGameSettings")
    oldRotationType=userGameSettings.RotationType
end)

local function getPlayerModule()
    if playerModule then return playerModule end
    pcall(function()
        local ps=player:FindFirstChild("PlayerScripts")
        local pm=ps and ps:FindFirstChild("PlayerModule")
        if pm then
            local m=require(pm)
            if type(m)=="table" then playerModule=m end
        end
    end)
    return playerModule
end

local function getCameras()
    if cameras then return cameras end
    local pm=getPlayerModule()
    pcall(function()
        if pm and type(pm.GetCameras)=="function" then cameras=pm:GetCameras() end
    end)
    return cameras
end

local function getActiveCameraController()
    local c=getCameras()
    if type(c)~="table" then return nil end
    local controller
    pcall(function()
        if type(c.GetActiveCameraController)=="function" then
            controller=c:GetActiveCameraController()
        end
    end)
    return controller
end

local function shouldRelease()
    if getgenv().PCMovementEnabled==false or getgenv().PCNativeHardCenterEnabled==false then
        return true
    end
    local char=player.Character
    local hum=char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health<=0 then return true end

    local platform=false
    pcall(function() platform=hum.PlatformStand end)
    if platform then return true end

    local state
    pcall(function() state=hum:GetState() end)
    return state==Enum.HumanoidStateType.Dead
        or state==Enum.HumanoidStateType.Physics
        or state==Enum.HumanoidStateType.Ragdoll
        or state==Enum.HumanoidStateType.FallingDown
end

local function forceMouseBehavior(value)
    pcall(function() UserInputService.MouseBehavior=value end)
    if sethiddenproperty then
        pcall(function() sethiddenproperty(UserInputService,"MouseBehavior",value) end)
    end
end

local function forceRotationType(value)
    if not userGameSettings then return end
    pcall(function() userGameSettings.RotationType=value end)
    if sethiddenproperty then
        pcall(function() sethiddenproperty(userGameSettings,"RotationType",value) end)
    end
end

-- Run just after Roblox camera update. V18/V9 still decides offset and emote framing;
-- this layer only makes the mouse-lock CENTER win every frame.
RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Camera.Value+3,function()
    if shouldRelease() then return end

    local controller=getActiveCameraController()
    if controller then
        if type(controller.SetIsMouseLocked)=="function" then
            pcall(function() controller:SetIsMouseLocked(true) end)
        end
        if type(controller.UpdateMouseBehavior)=="function" then
            pcall(function() controller:UpdateMouseBehavior() end)
        end
    end

    forceRotationType(Enum.RotationType.CameraRelative)
    forceMouseBehavior(Enum.MouseBehavior.LockCenter)
end)

getgenv().__PCMobileAimCleanup=function()
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

    if oldMouseBehavior~=nil then
        forceMouseBehavior(oldMouseBehavior)
    end
    if oldRotationType~=nil then
        forceRotationType(oldRotationType)
    end

    if v18Cleanup then pcall(v18Cleanup) end
    getgenv().__PCMobileAimCleanup=nil
end
