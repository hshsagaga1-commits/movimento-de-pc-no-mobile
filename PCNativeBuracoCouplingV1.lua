-- PCNativeBuracoCouplingV1.lua
-- Native Legacy mouse-lock coupling layer for the V1.1 mouse-stage camera path.
--
-- This does NOT pin Head/Root to a screen pixel and does NOT write Camera.CFrame.
-- It restores the native states the PC path uses around CameraModule.Update and
-- exposes Evade's own CamStats.MouseEnabled flag so game-side PC logic can see
-- mouse identity while the physical input source remains Touch.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")

local player=Players.LocalPlayer
local ENV=(type(getgenv)=="function" and getgenv()) or _G

local VERSION="PC-NATIVE-BURACO-COUPLING-V1"
local LEGACY_PLACE_ID=96537472072550
local INPUT_BIND="__PCNativeBuracoCouplingV1_Input"
local PRE_BIND="__PCNativeBuracoCouplingV1_PreCamera"
local POST_BIND="__PCNativeBuracoCouplingV1_PostCamera"
local NORMAL_OFFSET=Vector3.new(2,0.5,0)

local oldCleanup=ENV.__PCNativeBuracoCouplingV1Cleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end
pcall(function() RunService:UnbindFromRenderStep(INPUT_BIND) end)
pcall(function() RunService:UnbindFromRenderStep(PRE_BIND) end)
pcall(function() RunService:UnbindFromRenderStep(POST_BIND) end)

if game.PlaceId~=LEGACY_PLACE_ID then
    return
end

local userGameSettings=nil
local oldRotationType=nil
local oldMouseBehavior=nil
pcall(function()
    userGameSettings=UserSettings():GetService("UserGameSettings")
    oldRotationType=userGameSettings.RotationType
end)
pcall(function() oldMouseBehavior=UserInputService.MouseBehavior end)

local playerModule=nil
local cameras=nil
local controllerSnapshots=setmetatable({}, {__mode="k"})
local valueSnapshots=setmetatable({}, {__mode="k"})
local camStats=nil
local camStatsCaptured=false
local oldCamStatsMouseEnabled=nil
local hadCamStatsMouseEnabled=false
local changingCamStats=false
local connections={}

local frames=0
local activeFrames=0
local controllerChanges=0
local updateMouseBehaviorCalls=0
local camStatsWrites=0
local shiftWrites=0
local offsetValueWrites=0
local rotationWrites=0
local mouseBehaviorWrites=0
local cameraModeWrites=0
local lastController=nil
local lastReason="starting"

local function getPlayerModule()
    if type(playerModule)=="table" then return playerModule end
    local ps=player:FindFirstChild("PlayerScripts")
    local pm=ps and ps:FindFirstChild("PlayerModule")
    if not pm then return nil end
    local ok,value=pcall(require,pm)
    if ok and type(value)=="table" then playerModule=value end
    return playerModule
end

local function getCameras()
    if type(cameras)=="table" then return cameras end
    local pm=getPlayerModule()
    if type(pm)~="table" then return nil end
    pcall(function()
        if type(pm.GetCameras)=="function" then cameras=pm:GetCameras() end
        if type(cameras)~="table" then cameras=rawget(pm,"cameras") end
    end)
    return type(cameras)=="table" and cameras or nil
end

local function getActiveController()
    local cm=getCameras()
    if type(cm)~="table" then return nil end
    local c=rawget(cm,"activeCameraController")
    if type(c)~="table" and type(cm.GetActiveCameraController)=="function" then
        pcall(function() c=cm:GetActiveCameraController() end)
    end
    return type(c)=="table" and c or nil
end

local function rememberValue(obj)
    if not obj or valueSnapshots[obj]~=nil then return end
    local ok,value=pcall(function() return obj.Value end)
    if ok then valueSnapshots[obj]=value end
end

local function snapshotController(c)
    if type(c)~="table" or controllerSnapshots[c] then return end
    local s={}
    pcall(function() s.rawLock=rawget(c,"inMouseLockedMode") end)
    pcall(function() s.rawOffset=rawget(c,"mouseLockOffset") end)
    pcall(function() s.rawMode=rawget(c,"cameraMovementMode") end)
    pcall(function()
        if type(c.GetIsMouseLocked)=="function" then s.lock=c:GetIsMouseLocked() end
    end)
    pcall(function()
        if type(c.GetMouseLockOffset)=="function" then s.offset=c:GetMouseLockOffset() end
    end)
    controllerSnapshots[c]=s
end

local function restoreController(c)
    local s=controllerSnapshots[c]
    if type(c)~="table" or type(s)~="table" then return end
    pcall(function()
        local value=s.lock
        if value==nil then value=s.rawLock end
        if value~=nil then
            if type(c.SetIsMouseLocked)=="function" then c:SetIsMouseLocked(value)
            else rawset(c,"inMouseLockedMode",value) end
        end
    end)
    pcall(function()
        local value=s.offset
        if value==nil then value=s.rawOffset end
        if value~=nil then
            if type(c.SetMouseLockOffset)=="function" then c:SetMouseLockOffset(value)
            else rawset(c,"mouseLockOffset",value) end
        end
    end)
    pcall(function()
        if s.rawMode~=nil and type(c.SetCameraMovementMode)=="function" then
            c:SetCameraMovementMode(s.rawMode)
        end
    end)
    pcall(function()
        if type(c.UpdateMouseBehavior)=="function" then c:UpdateMouseBehavior() end
    end)
end

local function getLegacyValues()
    local ps=player:FindFirstChild("PlayerScripts")
    if not ps then return nil,nil,nil end
    local shift=ps:FindFirstChild("ShiftLockEnabled")
    local offset=ps:FindFirstChild("MouseLockOffset")
    if shift and not shift:IsA("BoolValue") then shift=nil end
    if offset and not offset:IsA("Vector3Value") then offset=nil end
    local stats=ps:FindFirstChild("CamStats")
    return shift,offset,stats
end

local function applyCamStatsMouseIdentity()
    local _,_,stats=getLegacyValues()
    if not stats then return end
    camStats=stats
    if not camStatsCaptured then
        oldCamStatsMouseEnabled=stats:GetAttribute("MouseEnabled")
        hadCamStatsMouseEnabled=oldCamStatsMouseEnabled~=nil
        camStatsCaptured=true
    end
    if stats:GetAttribute("MouseEnabled")~=true then
        changingCamStats=true
        pcall(function() stats:SetAttribute("MouseEnabled",true) end)
        changingCamStats=false
        camStatsWrites+=1
    end
end

local function applyLegacyValues()
    local shift,offset=getLegacyValues()
    if shift then
        rememberValue(shift)
        if shift.Value~=true then
            pcall(function() shift.Value=true end)
            shiftWrites+=1
        end
    end
    if offset then
        rememberValue(offset)
        if offset.Value~=NORMAL_OFFSET then
            pcall(function() offset.Value=NORMAL_OFFSET end)
            offsetValueWrites+=1
        end
    end
end

local function aliveAndCameraOwned()
    local cam=workspace.CurrentCamera
    if not cam then return false,"no-camera" end
    if cam.CameraType==Enum.CameraType.Scriptable then return false,"scriptable" end
    local char=player.Character
    local hum=char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return false,"no-humanoid" end
    local health=0
    local state=nil
    pcall(function() health=hum.Health end)
    pcall(function() state=hum:GetState() end)
    if health<=0 or state==Enum.HumanoidStateType.Dead then return false,"dead" end
    return true,"active"
end

local function applyControllerNative(c)
    if type(c)~="table" then return end
    snapshotController(c)

    pcall(function()
        if type(c.SetCameraMovementMode)=="function" then
            c:SetCameraMovementMode(Enum.ComputerCameraMovementMode.Classic)
            cameraModeWrites+=1
        end
    end)

    pcall(function()
        if type(c.SetMouseLockOffset)=="function" then c:SetMouseLockOffset(NORMAL_OFFSET)
        else rawset(c,"mouseLockOffset",NORMAL_OFFSET) end
    end)

    pcall(function()
        if type(c.SetIsMouseLocked)=="function" then c:SetIsMouseLocked(true)
        else rawset(c,"inMouseLockedMode",true) end
    end)

    pcall(function()
        if type(c.UpdateMouseBehavior)=="function" then
            c:UpdateMouseBehavior()
            updateMouseBehaviorCalls+=1
        end
    end)
end

local function applyGlobalNativeState()
    if userGameSettings then
        local current=nil
        pcall(function() current=userGameSettings.RotationType end)
        if current~=Enum.RotationType.CameraRelative then
            pcall(function() userGameSettings.RotationType=Enum.RotationType.CameraRelative end)
            if type(sethiddenproperty)=="function" then
                pcall(function() sethiddenproperty(userGameSettings,"RotationType",Enum.RotationType.CameraRelative) end)
            end
            rotationWrites+=1
        end
    end

    if UserInputService.MouseBehavior~=Enum.MouseBehavior.LockCenter then
        pcall(function() UserInputService.MouseBehavior=Enum.MouseBehavior.LockCenter end)
        if type(sethiddenproperty)=="function" then
            pcall(function() sethiddenproperty(UserInputService,"MouseBehavior",Enum.MouseBehavior.LockCenter) end)
        end
        mouseBehaviorWrites+=1
    end
end

local function inputStep()
    applyCamStatsMouseIdentity()
end

local function nativeStep()
    frames+=1
    local ok,reason=aliveAndCameraOwned()
    if not ok then
        lastReason=reason
        return
    end

    local c=getActiveController()
    if type(c)~="table" then
        lastReason="no-controller"
        return
    end
    if c~=lastController then
        lastController=c
        controllerChanges+=1
        snapshotController(c)
    end

    applyCamStatsMouseIdentity()
    applyLegacyValues()
    applyControllerNative(c)
    applyGlobalNativeState()

    activeFrames+=1
    lastReason="native-pc-lock"
end

local function postStep()
    local ok=aliveAndCameraOwned()
    if not ok then return end
    local c=getActiveController()
    if type(c)~="table" then return end

    -- Evade's custom CameraModule tail can call SetIsMouseLocked after the
    -- controller update. Reassert the same native PC state after that tail,
    -- without moving the camera or character.
    applyLegacyValues()
    applyControllerNative(c)
    applyGlobalNativeState()
end

RunService:BindToRenderStep(INPUT_BIND,Enum.RenderPriority.Input.Value-3,inputStep)
RunService:BindToRenderStep(PRE_BIND,Enum.RenderPriority.Camera.Value-2,nativeStep)
RunService:BindToRenderStep(POST_BIND,Enum.RenderPriority.Camera.Value+6,postStep)

task.spawn(function()
    local ps=player:WaitForChild("PlayerScripts",15)
    if not ps then return end
    local stats=ps:FindFirstChild("CamStats") or ps:WaitForChild("CamStats",10)
    if not stats then return end
    camStats=stats
    applyCamStatsMouseIdentity()
    connections[#connections+1]=stats:GetAttributeChangedSignal("MouseEnabled"):Connect(function()
        if not changingCamStats then task.defer(applyCamStatsMouseIdentity) end
    end)
end)

ENV.PCNativeBuracoCouplingV1={
    Version=VERSION,
    GetState=function()
        local shift,offset,stats=getLegacyValues()
        local c=getActiveController()
        return {
            version=VERSION,
            frames=frames,
            activeFrames=activeFrames,
            lastReason=lastReason,
            controllerChanges=controllerChanges,
            updateMouseBehaviorCalls=updateMouseBehaviorCalls,
            camStatsWrites=camStatsWrites,
            shiftWrites=shiftWrites,
            offsetValueWrites=offsetValueWrites,
            rotationWrites=rotationWrites,
            mouseBehaviorWrites=mouseBehaviorWrites,
            cameraModeWrites=cameraModeWrites,
            camStatsMouseEnabled=stats and stats:GetAttribute("MouseEnabled") or nil,
            shiftLockValue=shift and shift.Value or nil,
            mouseLockOffsetValue=offset and offset.Value or nil,
            controllerLock=type(c)=="table" and rawget(c,"inMouseLockedMode") or nil,
            controllerOffset=type(c)=="table" and rawget(c,"mouseLockOffset") or nil,
            rotationType=userGameSettings and userGameSettings.RotationType or nil,
            mouseBehavior=UserInputService.MouseBehavior,
            writesCameraCFrame=false,
            writesCameraFocus=false,
            writesRootCFrame=false,
            writesHeadCFrame=false,
            forcesAutoRotate=false,
        }
    end,
}

ENV.__PCNativeBuracoCouplingV1Cleanup=function()
    pcall(function() RunService:UnbindFromRenderStep(INPUT_BIND) end)
    pcall(function() RunService:UnbindFromRenderStep(PRE_BIND) end)
    pcall(function() RunService:UnbindFromRenderStep(POST_BIND) end)

    for _,conn in ipairs(connections) do pcall(function() conn:Disconnect() end) end
    table.clear(connections)

    for c in pairs(controllerSnapshots) do restoreController(c) end

    for obj,value in pairs(valueSnapshots) do
        if obj and obj.Parent then pcall(function() obj.Value=value end) end
    end

    if camStats and camStatsCaptured then
        changingCamStats=true
        pcall(function()
            if hadCamStatsMouseEnabled then camStats:SetAttribute("MouseEnabled",oldCamStatsMouseEnabled)
            else camStats:SetAttribute("MouseEnabled",nil) end
        end)
        changingCamStats=false
    end

    if userGameSettings and oldRotationType~=nil then
        pcall(function() userGameSettings.RotationType=oldRotationType end)
    end
    if oldMouseBehavior~=nil then
        pcall(function() UserInputService.MouseBehavior=oldMouseBehavior end)
    end

    ENV.PCNativeBuracoCouplingV1=nil
    ENV.__PCNativeBuracoCouplingV1Cleanup=nil
end

warn("["..VERSION.."] native lock coupling active; no Camera/Root CFrame writes")
