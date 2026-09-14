local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")
local GuiService=game:GetService("GuiService")
local player=Players.LocalPlayer

local lines={}
local function add(k,v)
    table.insert(lines,tostring(k).." = "..tostring(v))
end
local function safe(k,f)
    local ok,v=pcall(f)
    add(k,ok and v or ("ERROR: "..tostring(v)))
end
local function keys(t)
    if type(t)~="table" then return tostring(t) end
    local a={}
    for k in pairs(t) do table.insert(a,tostring(k)) end
    table.sort(a)
    return table.concat(a,", ")
end

add("=== CAMERA X9 REPORT ===",os.date("%Y-%m-%d %H:%M:%S"))
add("PCMovementVersion",getgenv().PCMovementVersion)
add("PCInputBridgeMode",getgenv().PCInputBridgeMode)
add("PCInputBridgeEnabled",getgenv().PCInputBridgeEnabled)
add("PCInputBridgeSensitivity",getgenv().PCInputBridgeSensitivity)
add("PCNativeHardCenterEnabled",getgenv().PCNativeHardCenterEnabled)
add("PCVirtualMouseEnabled",getgenv().PCVirtualMouseEnabled)

safe("TouchEnabled",function() return UIS.TouchEnabled end)
safe("MouseEnabled",function() return UIS.MouseEnabled end)
safe("KeyboardEnabled",function() return UIS.KeyboardEnabled end)
safe("PreferredInput",function() return UIS.PreferredInput end)
safe("MouseBehavior",function() return UIS.MouseBehavior end)
safe("MouseDeltaSensitivity",function() return UIS.MouseDeltaSensitivity end)
safe("ViewportSize",function() return Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize end)
safe("FOV",function() return Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfView end)
safe("FOVMode",function() return Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfViewMode end)
safe("CameraType",function() return Workspace.CurrentCamera and Workspace.CurrentCamera.CameraType end)
safe("CameraSubject",function() return Workspace.CurrentCamera and Workspace.CurrentCamera.CameraSubject end)
safe("CameraCFrame",function() return Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame end)
safe("CameraFocus",function() return Workspace.CurrentCamera and Workspace.CurrentCamera.Focus end)
safe("GuiInset",function() local a,b=GuiService:GetGuiInset(); return tostring(a).." / "..tostring(b) end)

local ugs
pcall(function() ugs=UserSettings():GetService("UserGameSettings") end)
if ugs then
    safe("RotationType",function() return ugs.RotationType end)
    safe("CameraSensitivity",function() return ugs.MouseSensitivity or ugs.CameraSensitivity end)
    safe("CameraYInvert",function() return ugs:GetCameraYInvertValue() end)
    safe("ComputerCameraMovementMode",function() return ugs.ComputerCameraMovementMode end)
    safe("TouchCameraMovementMode",function() return ugs.TouchCameraMovementMode end)
end

local ps=player:FindFirstChild("PlayerScripts")
local camStats=ps and ps:FindFirstChild("CamStats")
if camStats then
    safe("CamStats.Attributes",function()
        local a=camStats:GetAttributes(); local out={}
        for k,v in pairs(a) do table.insert(out,k..":"..tostring(v)) end
        table.sort(out); return table.concat(out,", ")
    end)
else add("CamStats","MISSING") end

local pm=ps and ps:FindFirstChild("PlayerModule")
local playerModule
if pm then pcall(function() playerModule=require(pm) end) end
add("PlayerModule.keys",keys(playerModule))
local cameras
pcall(function() if playerModule and playerModule.GetCameras then cameras=playerModule:GetCameras() end end)
add("Cameras.keys",keys(cameras))
local controller
pcall(function() if cameras and cameras.GetActiveCameraController then controller=cameras:GetActiveCameraController() end end)
add("ActiveCameraController",controller)
add("ActiveCameraController.keys",keys(controller))
if controller then
    safe("Controller.IsMouseLocked",function() return controller:GetIsMouseLocked() end)
    safe("Controller.MouseLockOffset",function() return controller:GetMouseLockOffset() end)
    safe("Controller.CameraDistance",function() return controller:GetCameraToSubjectDistance() end)
end

local ci
pcall(function()
    local cm=pm and pm:FindFirstChild("CameraModule")
    local m=cm and cm:FindFirstChild("CameraInput")
    if m then ci=require(m) end
end)
add("CameraInput.keys",keys(ci))
if ci then
    safe("CameraInput.RotationActivated",function() return ci.getRotationActivated and ci.getRotationActivated() end)
    safe("CameraInput.getRotation.fn",function() return ci.getRotation end)
end

local char=player.Character
local hum=char and char:FindFirstChildOfClass("Humanoid")
if hum then
    safe("Humanoid.AutoRotate",function() return hum.AutoRotate end)
    safe("Humanoid.CameraOffset",function() return hum.CameraOffset end)
    safe("Humanoid.MoveDirection",function() return hum.MoveDirection end)
    safe("Humanoid.State",function() return hum:GetState() end)
end
if char then
    safe("Character.Crouching",function() return char:GetAttribute("Crouching") end)
    local movement=char:FindFirstChild("Movement")
    if movement and movement:IsA("ModuleScript") then
        local mt
        pcall(function() mt=require(movement) end)
        add("LegacyMovement.keys",keys(mt))
    else add("LegacyMovement","MISSING") end
end

add("--- 3 SECOND LIVE SAMPLE ---","")
local samples={}
local start=os.clock()
local lastCF=Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame
local frames=0
local totalYaw,totalPitch=0,0
local maxYaw,maxPitch=0,0
local conn
conn=RunService.RenderStepped:Connect(function()
    if os.clock()-start>=3 then conn:Disconnect(); return end
    local cam=Workspace.CurrentCamera
    if cam and lastCF then
        local rel=lastCF:ToObjectSpace(cam.CFrame)
        local x,y=rel:ToEulerAnglesYXZ()
        local ay,ap=math.abs(y),math.abs(x)
        totalYaw+=ay; totalPitch+=ap
        maxYaw=math.max(maxYaw,ay); maxPitch=math.max(maxPitch,ap)
        frames+=1; lastCF=cam.CFrame
    end
end)
task.wait(3.15)
add("Sample.frames",frames)
add("Sample.avgYawDeg",frames>0 and math.deg(totalYaw/frames) or 0)
add("Sample.avgPitchDeg",frames>0 and math.deg(totalPitch/frames) or 0)
add("Sample.maxYawDeg",math.deg(maxYaw))
add("Sample.maxPitchDeg",math.deg(maxPitch))

local report=table.concat(lines,"\n")
print(report)
if setclipboard then pcall(setclipboard,report) end
getgenv().CameraX9Report=report
warn("[Camera X9] relatório pronto. Foi copiado para o clipboard se o executor permitir. Se não, copie do console ou execute: setclipboard(getgenv().CameraX9Report)")
return report
