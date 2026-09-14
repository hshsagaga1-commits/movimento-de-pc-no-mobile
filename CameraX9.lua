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
    if ok then add(k,v) else add(k,"ERROR: "..tostring(v)) end
end
local function keys(t)
    if type(t)~="table" then return tostring(t) end
    local a={}
    for k in pairs(t) do table.insert(a,tostring(k)) end
    table.sort(a)
    return table.concat(a,", ")
end
local function methodKeys(t)
    local out={}
    local seen={}
    local function harvest(x)
        if type(x)~="table" then return end
        for k,v in pairs(x) do
            if type(v)=="function" and not seen[k] then
                seen[k]=true
                table.insert(out,tostring(k))
            end
        end
    end
    harvest(t)
    harvest(getmetatable(t))
    table.sort(out)
    return table.concat(out,", ")
end

local function getUpvalueValues(f)
    local out={}
    if type(f)~="function" then return out end

    if debug and type(debug.getupvalues)=="function" then
        local ok,res=pcall(debug.getupvalues,f)
        if ok and type(res)=="table" then for _,v in pairs(res) do table.insert(out,v) end end
    end
    if #out==0 and type(getupvalues)=="function" then
        local ok,res=pcall(getupvalues,f)
        if ok and type(res)=="table" then for _,v in pairs(res) do table.insert(out,v) end end
    end
    local single=(debug and debug.getupvalue) or getupvalue
    if #out==0 and type(single)=="function" then
        for i=1,80 do
            local ok,a,b=pcall(single,f,i)
            if not ok or (a==nil and b==nil) then break end
            local v=(type(a)=="string") and b or a
            if v~=nil then table.insert(out,v) end
        end
    end
    return out
end

local function looksLikeCameraInput(t)
    return type(t)=="table"
        and type(rawget(t,"getRotation"))=="function"
        and (type(rawget(t,"getZoomDelta"))=="function" or type(rawget(t,"getRotationActivated"))=="function")
end

local function findCameraInputFromController(controller)
    if type(controller)~="table" then return nil,"controller-not-table" end
    local visitedFns={}
    local visitedTables={}
    local function walk(v,depth)
        if depth>12 then return nil end
        if looksLikeCameraInput(v) then return v end
        if type(v)=="function" then
            if visitedFns[v] then return nil end
            visitedFns[v]=true
            for _,uv in ipairs(getUpvalueValues(v)) do
                local found=walk(uv,depth+1)
                if found then return found end
            end
        elseif type(v)=="table" then
            if visitedTables[v] then return nil end
            visitedTables[v]=true
            for _,child in pairs(v) do
                if type(child)=="function" or type(child)=="table" then
                    local found=walk(child,depth+1)
                    if found then return found end
                end
            end
            local mt=getmetatable(v)
            if type(mt)=="table" then
                local found=walk(mt,depth+1)
                if found then return found end
            end
        end
        return nil
    end
    if type(controller.Update)=="function" then
        local found=walk(controller.Update,0)
        if found then return found,"controller.Update-upvalues" end
    end
    local found=walk(controller,0)
    if found then return found,"controller-recursive" end
    return nil,"not-found"
end

add("=== CAMERA X9 REPORT V2 ===",os.date("%Y-%m-%d %H:%M:%S"))
add("PCMovementVersion",getgenv().PCMovementVersion)
add("PCInputBridgeMode",getgenv().PCInputBridgeMode)
add("PCInputBridgeDiscovery",getgenv().PCInputBridgeDiscovery)
add("PCInputBridgeEnabled",getgenv().PCInputBridgeEnabled)
add("PCInputBridgeSensitivity",getgenv().PCInputBridgeSensitivity)
add("PCNativeHardCenterEnabled",getgenv().PCNativeHardCenterEnabled)
add("PCVirtualMouseEnabled",getgenv().PCVirtualMouseEnabled)
add("debug.getupvalues",debug and type(debug.getupvalues) or "nil")
add("debug.getupvalue",debug and type(debug.getupvalue) or "nil")
add("global.getupvalues",type(getupvalues))
add("global.getupvalue",type(getupvalue))

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
pcall(function()
    if type(playerModule)=="table" and type(playerModule.GetCameras)=="function" then cameras=playerModule:GetCameras()
    elseif type(playerModule)=="table" then cameras=rawget(playerModule,"cameras") end
end)
add("Cameras.keys",keys(cameras))
add("Cameras.methods",methodKeys(cameras))

local controller=type(cameras)=="table" and rawget(cameras,"activeCameraController") or nil
if controller==nil then
    pcall(function()
        if cameras and type(cameras.GetActiveCameraController)=="function" then controller=cameras:GetActiveCameraController() end
    end)
end
add("ActiveCameraController",controller)
add("ActiveCameraController.keys",keys(controller))
add("ActiveCameraController.methods",methodKeys(controller))
add("ActiveCameraController.metatable.keys",keys(type(controller)=="table" and getmetatable(controller) or nil))
if controller then
    safe("Controller.inMouseLockedMode",function() return controller.inMouseLockedMode end)
    safe("Controller.mouseLockOffset",function() return controller.mouseLockOffset end)
    safe("Controller.GetIsMouseLocked",function() return type(controller.GetIsMouseLocked)=="function" and controller:GetIsMouseLocked() or "METHOD_MISSING" end)
    safe("Controller.GetMouseLockOffset",function() return type(controller.GetMouseLockOffset)=="function" and controller:GetMouseLockOffset() or "METHOD_MISSING" end)
    safe("Controller.CameraDistance",function() return type(controller.GetCameraToSubjectDistance)=="function" and controller:GetCameraToSubjectDistance() or "METHOD_MISSING" end)
end

local directCI
pcall(function()
    local cm=pm and pm:FindFirstChild("CameraModule")
    local m=cm and cm:FindFirstChild("CameraInput")
    if m then directCI=require(m) end
end)
add("DirectCameraInput.keys",keys(directCI))

local discoveredCI,discovery=findCameraInputFromController(controller)
add("DiscoveredCameraInput.discovery",discovery)
add("DiscoveredCameraInput.keys",keys(discoveredCI))
if discoveredCI then
    safe("DiscoveredCameraInput.RotationActivated",function() return discoveredCI.getRotationActivated and discoveredCI.getRotationActivated() end)
    safe("DiscoveredCameraInput.getRotation.fn",function() return discoveredCI.getRotation end)
end

if pm then
    local desc={}
    for _,d in ipairs(pm:GetDescendants()) do
        table.insert(desc,d:GetFullName().." ["..d.ClassName.."]")
        if #desc>=80 then table.insert(desc,"...TRUNCATED..."); break end
    end
    add("PlayerModule.descendants",table.concat(desc," | "))
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
warn("[Camera X9 V2] relatório pronto e copiado pro clipboard se permitido.")
return report
