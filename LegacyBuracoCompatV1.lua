-- LegacyBuracoCompatV1.lua
-- EXPERIMENTAL compatibility layer for Evade Legacy mobile.
--
-- Goal:
--   Preserve the old Legacy mouse-lock camera geometry at the FINAL rendered camera
--   stage, using the Legacy camera's own subject + MouseLockOffset as the source of truth.
--
-- What it changes:
--   * Camera.CFrame POSITION only, along Camera.RightVector.
--   * Camera.Focus by the exact same world-space translation.
--
-- What it does NOT change:
--   * Camera rotation / FOV / zoom distance.
--   * Character / HumanoidRootPart CFrame.
--   * WalkSpeed / movement / joystick / input routing.
--   * PlayerModule / CameraModule code.
--   * MouseLockOffset / ShiftLock state.
--   * Any V614 / main experiment.
--
-- Why X only:
--   The comparative X9 measured the strongest common invariant as camera-local X ~= -2
--   studs in both Legacy and Overhaul. Vertical behavior is intentionally left untouched
--   so jumps, crouch, slopes, animation, camera bob and game-specific vertical composition
--   remain native.
--
-- Safety:
--   Runs only in the known Legacy PlaceId, only on the local player's active Custom camera,
--   only while the old camera reports mouse-lock (or its Legacy fallback says ShiftLock ON),
--   and refuses large corrections instead of snapping the camera.
--
-- Tap the small "BURACO: ON" button to disable/enable instantly.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local Workspace=game:GetService("Workspace")
local StarterGui=game:GetService("StarterGui")

local player=Players.LocalPlayer
local ENV=(type(getgenv)=="function" and getgenv()) or _G

local VERSION="LegacyBuracoCompatV1-R1"
local LEGACY_PLACE_ID=96537472072550

-- Optional pre-run tuning:
-- getgenv().LegacyBuracoCompatConfig = {
--     Gain=1.0,
--     Deadzone=0.0005,
--     MaxStep=0.45,
--     MaxError=1.25,
--     MinDepth=2.5,
--     FallbackOffsetX=2.0,
--     RequireLock=true,
--     ShowButton=true,
-- }
local userConfig=type(ENV.LegacyBuracoCompatConfig)=="table" and ENV.LegacyBuracoCompatConfig or {}
local CFG={
    Gain=math.clamp(tonumber(userConfig.Gain) or 1.0,0.05,1.0),
    Deadzone=math.clamp(tonumber(userConfig.Deadzone) or 0.0005,0,0.05),
    MaxStep=math.clamp(tonumber(userConfig.MaxStep) or 0.45,0.02,1.0),
    MaxError=math.clamp(tonumber(userConfig.MaxError) or 1.25,0.10,3.0),
    MinDepth=math.clamp(tonumber(userConfig.MinDepth) or 2.5,1.0,10.0),
    FallbackOffsetX=math.clamp(tonumber(userConfig.FallbackOffsetX) or 2.0,-4.0,4.0),
    RequireLock=userConfig.RequireLock~=false,
    ShowButton=userConfig.ShowButton~=false,
}

local function notify(title,text,duration)
    pcall(function()
        StarterGui:SetCore("SendNotification",{
            Title=title,
            Text=text,
            Duration=duration or 5,
        })
    end)
end

-- Clean up an older copy before installing this one.
local previous=ENV.LegacyBuracoCompatV1
if type(previous)=="table" and type(previous.Cleanup)=="function" then
    pcall(previous.Cleanup)
end

if game.PlaceId~=LEGACY_PLACE_ID then
    notify("Legacy Buraco Compat","Este arquivo é só para o Evade Legacy. Nenhuma alteração foi aplicada.",7)
    return {
        Version=VERSION,
        Installed=false,
        Reason="wrong-place",
        PlaceId=game.PlaceId,
    }
end

local state={
    Enabled=true,
    Active=false,
    Reason="starting",
    Frames=0,
    ActiveFrames=0,
    Corrections=0,
    SmallEnough=0,
    LargeErrorRejects=0,
    NoLockFrames=0,
    NoSubjectFrames=0,
    WrongCameraFrames=0,
    LastTargetX=nil,
    LastLocalX=nil,
    LastErrorBefore=nil,
    LastErrorAfter=nil,
    LastStep=nil,
    LastSource=nil,
    LastOffsetSource=nil,
    LastLockSource=nil,
    LastError=nil,
}

local connections={}
local bindName="__LegacyBuracoCompatV1_FinalGeometry"

local playerModule
local cameras

local function safeProp(obj,key)
    if obj==nil then return nil end
    local v
    pcall(function() v=obj[key] end)
    return v
end

local function getPlayerModule()
    if type(playerModule)=="table" then return playerModule end
    pcall(function()
        local ps=player:FindFirstChild("PlayerScripts")
        local pm=ps and ps:FindFirstChild("PlayerModule")
        if pm then
            local r=require(pm) -- PlayerModule is already live; require returns its cached table.
            if type(r)=="table" then
                playerModule=r
                if type(r.GetCameras)=="function" then
                    cameras=r:GetCameras()
                elseif type(rawget(r,"cameras"))=="table" then
                    cameras=rawget(r,"cameras")
                end
            end
        end
    end)
    return playerModule
end

local function getCameras()
    getPlayerModule()
    if type(cameras)=="table" then return cameras end
    if type(playerModule)=="table" and type(playerModule.GetCameras)=="function" then
        pcall(function() cameras=playerModule:GetCameras() end)
    end
    return cameras
end

local function getActiveController()
    local cm=getCameras()
    if type(cm)~="table" then return nil end

    local controller=rawget(cm,"activeCameraController")
    if type(controller)=="table" then return controller end

    if type(cm.GetActiveCameraController)=="function" then
        pcall(function() controller=cm:GetActiveCameraController() end)
    end
    return type(controller)=="table" and controller or nil
end

local function getLegacyValues()
    local ps=player:FindFirstChild("PlayerScripts")
    if not ps then return nil,nil end

    local shift=ps:FindFirstChild("ShiftLockEnabled")
    local offset=ps:FindFirstChild("MouseLockOffset")

    if shift and not shift:IsA("BoolValue") then shift=nil end
    if offset and not offset:IsA("Vector3Value") then offset=nil end

    return shift,offset
end

local function resolveLocked(controller)
    if type(controller)=="table" then
        if type(controller.GetIsMouseLocked)=="function" then
            local value
            local ok=pcall(function() value=controller:GetIsMouseLocked() end)
            if ok and type(value)=="boolean" then
                return value,"controller.GetIsMouseLocked"
            end
        end

        local field=safeProp(controller,"inMouseLockedMode")
        if type(field)=="boolean" then
            return field,"controller.inMouseLockedMode"
        end
    end

    local shiftValue=getLegacyValues()
    if shiftValue then
        return shiftValue.Value,"PlayerScripts.ShiftLockEnabled"
    end

    if UIS.MouseBehavior==Enum.MouseBehavior.LockCenter then
        return true,"UIS.MouseBehavior.LockCenter"
    end

    local ugs
    pcall(function() ugs=UserSettings():GetService("UserGameSettings") end)
    if ugs and safeProp(ugs,"RotationType")==Enum.RotationType.CameraRelative then
        return true,"UserGameSettings.RotationType"
    end

    return false,"no-lock-signal"
end

local function resolveOffsetX(controller)
    if type(controller)=="table" then
        if type(controller.GetMouseLockOffset)=="function" then
            local offset
            local ok=pcall(function() offset=controller:GetMouseLockOffset() end)
            if ok and typeof(offset)=="Vector3" and math.abs(offset.X)>1e-5 then
                return offset.X,"controller.GetMouseLockOffset"
            end
        end

        local field=safeProp(controller,"mouseLockOffset")
        if typeof(field)=="Vector3" and math.abs(field.X)>1e-5 then
            return field.X,"controller.mouseLockOffset"
        end
    end

    local _,offsetValue=getLegacyValues()
    if offsetValue and typeof(offsetValue.Value)=="Vector3" and math.abs(offsetValue.Value.X)>1e-5 then
        return offsetValue.Value.X,"PlayerScripts.MouseLockOffset"
    end

    return CFG.FallbackOffsetX,"fallback"
end

local function characterParts()
    local char=player.Character
    if not char then return nil,nil,nil end

    local hum=char:FindFirstChildOfClass("Humanoid")
    local root=char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    if not root or not root:IsA("BasePart") then root=nil end

    return char,hum,root
end

local function cameraSubjectBelongsToCharacter(camera,char,hum)
    local subject=camera.CameraSubject
    if subject==nil then return false end
    if hum and subject==hum then return true end
    if char and subject:IsDescendantOf(char) then return true end
    return false
end

local function resolveAnchor(controller,hum,root)
    if type(controller)=="table" and type(controller.GetSubjectPosition)=="function" then
        local pos
        local ok=pcall(function() pos=controller:GetSubjectPosition() end)
        if ok and typeof(pos)=="Vector3" then
            return pos,"controller.GetSubjectPosition"
        end
    end

    if root then
        return root.Position,"HumanoidRootPart"
    end

    return nil,"none"
end

local button
local gui
local lastUiUpdate=0

local function updateButton(force)
    if not button then return end
    local t=os.clock()
    if not force and t-lastUiUpdate<0.20 then return end
    lastUiUpdate=t

    if not state.Enabled then
        button.Text="BURACO: OFF"
    elseif state.Active then
        button.Text="BURACO: ON"
    else
        button.Text="BURACO: ESPERA"
    end
end

local function installGui()
    if not CFG.ShowButton then return end
    local pg=player:FindFirstChildOfClass("PlayerGui")
    if not pg then return end

    local old=pg:FindFirstChild("LegacyBuracoCompatV1Gui")
    if old then old:Destroy() end

    gui=Instance.new("ScreenGui")
    gui.Name="LegacyBuracoCompatV1Gui"
    gui.ResetOnSpawn=false
    gui.IgnoreGuiInset=false
    gui.DisplayOrder=99999
    gui.Parent=pg

    button=Instance.new("TextButton")
    button.Name="Toggle"
    button.AnchorPoint=Vector2.new(0.5,0)
    button.Position=UDim2.new(0.5,0,0,62)
    button.Size=UDim2.fromOffset(132,32)
    button.BackgroundTransparency=0.22
    button.Font=Enum.Font.GothamBold
    button.TextSize=13
    button.Text="BURACO: ESPERA"
    button.Parent=gui

    local corner=Instance.new("UICorner")
    corner.CornerRadius=UDim.new(0,9)
    corner.Parent=button

    connections[#connections+1]=button.MouseButton1Click:Connect(function()
        state.Enabled=not state.Enabled
        state.Active=false
        state.Reason=state.Enabled and "waiting" or "disabled"
        updateButton(true)
        notify("Legacy Buraco Compat",state.Enabled and "Ligado." or "Desligado.",3)
    end)
end

local function correctionFrame()
    state.Frames+=1
    state.Active=false

    if not state.Enabled then
        state.Reason="disabled"
        updateButton(false)
        return
    end

    local camera=Workspace.CurrentCamera
    local char,hum,root=characterParts()

    if not camera
        or camera.CameraType~=Enum.CameraType.Custom
        or not char
        or not hum
        or not root
        or hum.Health<=0
        or not cameraSubjectBelongsToCharacter(camera,char,hum) then

        state.WrongCameraFrames+=1
        state.Reason="camera/character gate"
        updateButton(false)
        return
    end

    local controller=getActiveController()

    if CFG.RequireLock then
        local locked,lockSource=resolveLocked(controller)
        state.LastLockSource=lockSource
        if locked~=true then
            state.NoLockFrames+=1
            state.Reason="mouse-lock off"
            updateButton(false)
            return
        end
    end

    local anchor,source=resolveAnchor(controller,hum,root)
    if typeof(anchor)~="Vector3" then
        state.NoSubjectFrames+=1
        state.Reason="no subject position"
        updateButton(false)
        return
    end

    local offsetX,offsetSource=resolveOffsetX(controller)
    local targetX=-offsetX

    -- Sanity gate: the Legacy mouse-lock offset is expected to be a small lateral value.
    if type(targetX)~="number" or math.abs(targetX)>4.0 then
        state.Reason="invalid target"
        state.LastError="targetX out of range: "..tostring(targetX)
        updateButton(false)
        return
    end

    local beforeCF=camera.CFrame
    local beforeFocus=camera.Focus
    local localAnchor=beforeCF:PointToObjectSpace(anchor)
    local depth=-localAnchor.Z

    if depth<CFG.MinDepth then
        state.Reason="too close / first person"
        updateButton(false)
        return
    end

    local errorBefore=localAnchor.X-targetX

    state.LastTargetX=targetX
    state.LastLocalX=localAnchor.X
    state.LastErrorBefore=errorBefore
    state.LastSource=source
    state.LastOffsetSource=offsetSource

    if math.abs(errorBefore)<=CFG.Deadzone then
        state.Active=true
        state.ActiveFrames+=1
        state.SmallEnough+=1
        state.LastStep=0
        state.LastErrorAfter=errorBefore
        state.Reason="locked/native already exact"
        updateButton(false)
        return
    end

    if math.abs(errorBefore)>CFG.MaxError then
        state.LargeErrorRejects+=1
        state.Reason="large error rejected"
        state.LastError="rejected error="..tostring(errorBefore)
        updateButton(false)
        return
    end

    local correction=math.clamp(errorBefore*CFG.Gain,-CFG.MaxStep,CFG.MaxStep)
    local shift=beforeCF.RightVector*correction
    local translate=CFrame.new(shift)

    local ok,err=pcall(function()
        -- Translate the entire final camera rig sideways without touching its rotation.
        -- Moving Focus by the same vector preserves the game's camera orientation/focus relation.
        camera.CFrame=translate*beforeCF
        camera.Focus=translate*beforeFocus
    end)

    if not ok then
        state.LastError=tostring(err)
        state.Reason="camera write failed"
        updateButton(false)
        return
    end

    local afterLocal=camera.CFrame:PointToObjectSpace(anchor)
    local errorAfter=afterLocal.X-targetX

    -- Fail closed if another camera writer reacted in a way that made the geometry worse.
    if math.abs(errorAfter)>math.abs(errorBefore)+0.002 then
        pcall(function()
            camera.CFrame=beforeCF
            camera.Focus=beforeFocus
        end)
        state.LastError="post-write error worsened; rolled back"
        state.Reason="rollback"
        updateButton(false)
        return
    end

    state.Active=true
    state.ActiveFrames+=1
    state.Corrections+=1
    state.LastStep=correction
    state.LastErrorAfter=errorAfter
    state.Reason="corrected final lateral geometry"
    updateButton(false)
end

local cleaned=false
local function cleanup()
    if cleaned then return end
    cleaned=true
    pcall(function() RunService:UnbindFromRenderStep(bindName) end)
    for _,c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    if gui then pcall(function() gui:Destroy() end) end
    state.Enabled=false
    state.Active=false
    state.Reason="cleaned"
end

local api={
    Version=VERSION,
    Installed=true,
    Config=CFG,
    State=state,
    Enable=function()
        state.Enabled=true
        state.Reason="waiting"
        updateButton(true)
    end,
    Disable=function()
        state.Enabled=false
        state.Active=false
        state.Reason="disabled"
        updateButton(true)
    end,
    Cleanup=cleanup,
    GetStats=function()
        local copy={}
        for k,v in pairs(state) do copy[k]=v end
        return copy
    end,
}

ENV.LegacyBuracoCompatV1=api

installGui()

pcall(function() RunService:UnbindFromRenderStep(bindName) end)
RunService:BindToRenderStep(
    bindName,
    Enum.RenderPriority.Last.Value+100,
    correctionFrame
)

notify(
    "Legacy Buraco Compat V1",
    "Ligado. Mantém a geometria lateral antiga no estágio final da câmera. Toque BURACO: ON para desligar.",
    7
)

return api
