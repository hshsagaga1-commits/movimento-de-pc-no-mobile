local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")
local GuiService=game:GetService("GuiService")
local player=Players.LocalPlayer

local lines={}
local function add(k,v) table.insert(lines,tostring(k).." = "..tostring(v)) end
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

add("=== CAMERA X9 REPORT V4 ===",os.date("%Y-%m-%d %H:%M:%S"))
add("PCMovementVersion",getgenv().PCMovementVersion)
add("PCInputBridgeMode",getgenv().PCInputBridgeMode)
add("PCInputBridgeDiscovery",getgenv().PCInputBridgeDiscovery)
add("PCRelativeCenterEnabled",getgenv().PCRelativeCenterEnabled)
add("PCRelativeCenterControllerFound",getgenv().PCRelativeCenterControllerFound)
add("PCRelativeCenterPanBypassed",getgenv().PCRelativeCenterPanBypassed)
add("PCRelativeCenterInjectedEvents",getgenv().PCRelativeCenterInjectedEvents)
add("PCRelativeMouseGain",getgenv().PCRelativeMouseGain)
add("PCRelativeMouseVerticalScale",getgenv().PCRelativeMouseVerticalScale)
add("PCRelativeMouseCoeffX",getgenv().PCRelativeMouseCoeffX)
add("PCRelativeMouseCoeffY",getgenv().PCRelativeMouseCoeffY)
add("cap.getconnections",type(getconnections))
add("cap.hookfunction",type(hookfunction))
add("cap.getgc",type(getgc))
add("cap.debug.getupvalues",debug and type(debug.getupvalues) or "nil")

safe("TouchEnabled",function() return UIS.TouchEnabled end)
safe("MouseEnabled",function() return UIS.MouseEnabled end)
safe("KeyboardEnabled",function() return UIS.KeyboardEnabled end)
safe("PreferredInput",function() return UIS.PreferredInput end)
safe("MouseBehavior",function() return UIS.MouseBehavior end)
safe("MouseDeltaSensitivity",function() return UIS.MouseDeltaSensitivity end)
safe("GuiInset",function() local a,b=GuiService:GetGuiInset(); return tostring(a).." / "..tostring(b) end)

local cam=Workspace.CurrentCamera
safe("ViewportSize",function() return cam and cam.ViewportSize end)
safe("FOV",function() return cam and cam.FieldOfView end)
safe("CameraType",function() return cam and cam.CameraType end)

local ugs
pcall(function() ugs=UserSettings():GetService("UserGameSettings") end)
local invertY=1
if ugs then
    safe("RotationType",function() return ugs.RotationType end)
    safe("CameraSensitivity",function() return ugs.MouseSensitivity or ugs.CameraSensitivity end)
    safe("CameraYInvert",function() invertY=ugs:GetCameraYInvertValue(); return invertY end)
    safe("TouchCameraMovementMode",function() return ugs.TouchCameraMovementMode end)
end

local ps=player:FindFirstChild("PlayerScripts")
local pm=ps and ps:FindFirstChild("PlayerModule")
local playerModule
if pm then pcall(function() playerModule=require(pm) end) end
local cameras
pcall(function()
    if type(playerModule)=="table" and type(playerModule.GetCameras)=="function" then cameras=playerModule:GetCameras()
    elseif type(playerModule)=="table" then cameras=rawget(playerModule,"cameras") end
end)
local controller=type(cameras)=="table" and rawget(cameras,"activeCameraController") or nil
if not controller and type(cameras)=="table" and type(cameras.GetActiveCameraController)=="function" then
    pcall(function() controller=cameras:GetActiveCameraController() end)
end

add("PlayerModule.keys",keys(playerModule))
add("Cameras.keys",keys(cameras))
add("Controller.exists",controller~=nil)
add("Controller.keys",keys(controller))
if controller then
    safe("Controller.inMouseLockedMode",function() return controller.inMouseLockedMode end)
    safe("Controller.mouseLockOffset",function() return controller.mouseLockOffset end)
    safe("Controller.rotateInput",function() return controller.rotateInput end)
    safe("Controller.panEnabled",function() return controller.panEnabled end)
    safe("Controller.numUnsunkTouches",function() return controller.numUnsunkTouches end)
    safe("Controller.fingerTouches.count",function()
        local n=0
        if type(controller.fingerTouches)=="table" then for _ in pairs(controller.fingerTouches) do n+=1 end end
        return n
    end)
    safe("Controller.cameraMovementMode",function() return controller.cameraMovementMode end)
    safe("Controller.currentSubjectDistance",function() return controller.currentSubjectDistance end)
end

if type(getconnections)=="function" then
    safe("UIS.InputChanged.connectionCount",function() return #getconnections(UIS.InputChanged) end)
    safe("UIS.InputBegan.connectionCount",function() return #getconnections(UIS.InputBegan) end)
end

if type(getgenv().PCRelativeCenterDiagnostics)=="function" then
    local ok,d=pcall(getgenv().PCRelativeCenterDiagnostics)
    if ok and type(d)=="table" then
        add("V25Diag.panEnabled",d.panEnabled)
        add("V25Diag.panBypassed",d.panBypassed)
        add("V25Diag.mouseLocked",d.inMouseLockedMode)
        add("V25Diag.mouseLockOffset",d.mouseLockOffset)
        add("V25Diag.gain",d.gain)
        add("V25Diag.verticalScale",d.verticalScale)
        add("V25Diag.mouseCoeff",d.mouseCoeff)
        add("V25Diag.targetRadPerTouchPx",d.targetRadPerTouchPx)
        add("V25Diag.targetYX",d.targetYX)
        add("V25Diag.x9NativeRadPerTouchPx",d.x9NativeRadPerTouchPx)
        add("V25Diag.injectedEvents",d.injectedEvents)
    else
        add("V25Diag","ERROR")
    end
end

local pg=player:FindFirstChildOfClass("PlayerGui")
local function inThumb(pos)
    local tg=pg and pg:FindFirstChild("TouchGui")
    local tcf=tg and tg:FindFirstChild("TouchControlFrame")
    if not tcf then return false end
    for _,name in ipairs({"DynamicThumbstickFrame","ThumbstickFrame","TouchThumbstick"}) do
        local f=tcf:FindFirstChild(name,true)
        if f and f:IsA("GuiObject") and f.Visible then
            local a=f.AbsolutePosition
            local b=a+f.AbsoluteSize
            if pos.X>=a.X and pos.Y>=a.Y and pos.X<=b.X and pos.Y<=b.Y then return true end
        end
    end
    return false
end

add("--- 5 SECOND V25 RELATIVE-CENTER PROBE ---","")
add("Probe.instructions","swipe camera normally; joystick may stay held")

local touches={}
local rawFrame=Vector2.zero
local touchEvents=0
local samples=0
local sx2,sxy,sy2,syy=0,0,0,0
local sampleLines={}
local panTrueFrames=0
local panFalseFrames=0
local conns={}

table.insert(conns,UIS.InputBegan:Connect(function(input,gpe)
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    touches[input]=(not gpe) and (not inThumb(input.Position))
end))

table.insert(conns,UIS.InputChanged:Connect(function(input,gpe)
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    if touches[input]==nil then touches[input]=(not gpe) and (not inThumb(input.Position)) end

    local cameraTouch=touches[input]==true
    if controller and type(controller.fingerTouches)=="table" then
        local native=controller.fingerTouches[input]
        if native~=nil then cameraTouch=(native==false) end
    end

    local unsunk=nil
    if controller and type(controller.numUnsunkTouches)=="number" then unsunk=controller.numUnsunkTouches end
    if unsunk==nil then
        unsunk=0
        for _,v in pairs(touches) do if v==true then unsunk+=1 end end
    end

    if cameraTouch and unsunk==1 then
        local d=input.Delta
        rawFrame+=Vector2.new(d.X,d.Y)
        touchEvents+=1
    end
end))

table.insert(conns,UIS.InputEnded:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch then touches[input]=nil end
end))

local bindName="__CameraX9V4Probe"
pcall(function() RunService:UnbindFromRenderStep(bindName) end)
RunService:BindToRenderStep(bindName,Enum.RenderPriority.Camera.Value-1,function()
    if controller then
        if controller.panEnabled==false then panFalseFrames+=1 else panTrueFrames+=1 end
    end

    local raw=rawFrame
    rawFrame=Vector2.zero
    if not controller or typeof(controller.rotateInput)~="Vector2" or raw.Magnitude<0.001 then return end

    local rot=controller.rotateInput
    samples+=1
    sx2+=raw.X*raw.X
    sxy+=raw.X*rot.X
    sy2+=raw.Y*raw.Y
    syy+=raw.Y*rot.Y

    local gain=tonumber(getgenv().PCRelativeMouseGain) or 0
    local yScale=tonumber(getgenv().PCRelativeMouseVerticalScale) or 1
    local coeffX=tonumber(getgenv().PCRelativeMouseCoeffX) or ((math.pi*4)/1920)
    local coeffY=tonumber(getgenv().PCRelativeMouseCoeffY) or ((math.pi*1.9)/1200)
    local expected=Vector2.new(raw.X*coeffX*gain,raw.Y*coeffY*gain*yScale*invertY)

    if #sampleLines<14 then
        table.insert(sampleLines,string.format(
            "raw=(%.1f,%.1f) rotate=(%.5f,%.5f) expected=(%.5f,%.5f)",
            raw.X,raw.Y,rot.X,rot.Y,expected.X,expected.Y
        ))
    end
end)

task.wait(5.1)
pcall(function() RunService:UnbindFromRenderStep(bindName) end)
for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end

local observedX=sx2>0 and sxy/sx2 or 0
local observedY=sy2>0 and syy/sy2 or 0
local gain=tonumber(getgenv().PCRelativeMouseGain) or 0
local yScale=tonumber(getgenv().PCRelativeMouseVerticalScale) or 1
local coeffX=tonumber(getgenv().PCRelativeMouseCoeffX) or ((math.pi*4)/1920)
local coeffY=tonumber(getgenv().PCRelativeMouseCoeffY) or ((math.pi*1.9)/1200)
local expectedX=coeffX*gain
local expectedY=coeffY*gain*yScale*invertY

add("Probe.touchEvents",touchEvents)
add("Probe.samples",samples)
add("Probe.panFalseFrames",panFalseFrames)
add("Probe.panTrueFrames",panTrueFrames)
add("Probe.observedRadPerTouchPx.X",observedX)
add("Probe.observedRadPerTouchPx.Y",observedY)
add("Probe.expectedV25RadPerTouchPx.X",expectedX)
add("Probe.expectedV25RadPerTouchPx.Y",expectedY)
add("Probe.observedVsExpected.X",expectedX~=0 and observedX/expectedX or 0)
add("Probe.observedVsExpected.Y",expectedY~=0 and observedY/expectedY or 0)
add("Probe.observedYXRatio",observedX~=0 and observedY/observedX or 0)
add("Probe.expectedYXRatio",expectedX~=0 and expectedY/expectedX or 0)
add("Probe.firstSamples",table.concat(sampleLines," | "))

local report=table.concat(lines,"\n")
print(report)
if setclipboard then pcall(setclipboard,report) end
getgenv().CameraX9Report=report
warn("[Camera X9 V4] pronto. V25 verificado; cola o relatório aqui se precisar.")
return report
