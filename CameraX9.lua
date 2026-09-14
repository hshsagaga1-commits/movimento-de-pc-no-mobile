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

add("=== CAMERA X9 REPORT V3 ===",os.date("%Y-%m-%d %H:%M:%S"))
add("PCMovementVersion",getgenv().PCMovementVersion)
add("PCInputBridgeMode",getgenv().PCInputBridgeMode)
add("PCInputBridgeDiscovery",getgenv().PCInputBridgeDiscovery)
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

add("PlayerModule.keys",keys(playerModule))
add("Cameras.keys",keys(cameras))
add("Controller.exists",controller~=nil)
add("Controller.keys",keys(controller))
if controller then
    safe("Controller.inMouseLockedMode",function() return controller.inMouseLockedMode end)
    safe("Controller.mouseLockOffset",function() return controller.mouseLockOffset end)
    safe("Controller.rotateInput",function() return controller.rotateInput end)
    safe("Controller.ySensitivity",function() return controller.ySensitivity end)
    safe("Controller.panEnabled",function() return controller.panEnabled end)
    safe("Controller.numUnsunkTouches",function() return controller.numUnsunkTouches end)
    safe("Controller.isDynamicThumbstickEnabled",function() return controller.isDynamicThumbstickEnabled end)
    safe("Controller.cameraMovementMode",function() return controller.cameraMovementMode end)
    safe("Controller.currentSubjectDistance",function() return controller.currentSubjectDistance end)
    safe("Controller.currentSpeed",function() return controller.currentSpeed end)
end

if type(getconnections)=="function" then
    safe("UIS.InputChanged.connectionCount",function() return #getconnections(UIS.InputChanged) end)
    safe("UIS.InputBegan.connectionCount",function() return #getconnections(UIS.InputBegan) end)
end

local pg=player:FindFirstChildOfClass("PlayerGui")
local function thumbFrame()
    local tg=pg and pg:FindFirstChild("TouchGui")
    local tcf=tg and tg:FindFirstChild("TouchControlFrame")
    return tcf and tcf:FindFirstChild("DynamicThumbstickFrame")
end
local function inThumb(pos)
    local f=thumbFrame()
    if not f then return false end
    local a=f.AbsolutePosition
    local b=a+f.AbsoluteSize
    return pos.X>=a.X and pos.Y>=a.Y and pos.X<=b.X and pos.Y<=b.Y
end

add("--- 5 SECOND LEGACY ROTATEINPUT PROBE ---","")
add("Probe.instructions","swipe camera normally; joystick may stay held")

local touches={}
local dtInput=nil
local rawFrame=Vector2.zero
local touchEvents=0
local samples=0
local sx2,sxy,sy2,syy=0,0,0,0
local touchErrSum=0
local touchErrN=0
local sampleLines={}

local conns={}
table.insert(conns,UIS.InputBegan:Connect(function(input,gpe)
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    if dtInput==nil and not gpe and inThumb(input.Position) then
        dtInput=input
        return
    end
    touches[input]=gpe and true or false
end))

table.insert(conns,UIS.InputChanged:Connect(function(input,gpe)
    if input.UserInputType~=Enum.UserInputType.Touch or input==dtInput then return end
    if touches[input]==nil then touches[input]=gpe and true or false end
    local unsunk=0
    for _,sunk in pairs(touches) do if sunk==false then unsunk+=1 end end
    if unsunk==1 and touches[input]==false then
        local d=input.Delta
        rawFrame+=Vector2.new(d.X,d.Y)
        touchEvents+=1
    end
end))

table.insert(conns,UIS.InputEnded:Connect(function(input)
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    if input==dtInput then dtInput=nil end
    touches[input]=nil
end))

local bindName="__CameraX9V3Probe"
pcall(function() RunService:UnbindFromRenderStep(bindName) end)
RunService:BindToRenderStep(bindName,Enum.RenderPriority.Camera.Value-1,function()
    local raw=rawFrame
    rawFrame=Vector2.zero
    if not controller or typeof(controller.rotateInput)~="Vector2" or raw.Magnitude<0.001 then return end

    local rot=controller.rotateInput
    samples+=1
    sx2+=raw.X*raw.X
    sxy+=raw.X*rot.X
    sy2+=raw.Y*raw.Y
    syy+=raw.Y*rot.Y

    local vc=Workspace.CurrentCamera
    local vp=vc and vc.ViewportSize or Vector2.new(800,414)
    local predictedTouch=Vector2.new(
        raw.X/vp.X*(math.pi*2.25),
        raw.Y/vp.Y*(math.pi*2)*invertY
    )
    if predictedTouch.Magnitude>0.00001 then
        touchErrSum+=(rot-predictedTouch).Magnitude/predictedTouch.Magnitude
        touchErrN+=1
    end

    if #sampleLines<12 then
        table.insert(sampleLines,string.format("raw=(%.1f,%.1f) rotate=(%.5f,%.5f) touchPred=(%.5f,%.5f)",raw.X,raw.Y,rot.X,rot.Y,predictedTouch.X,predictedTouch.Y))
    end
end)

task.wait(5.1)
pcall(function() RunService:UnbindFromRenderStep(bindName) end)
for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end

local vp=(Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize) or Vector2.new(800,414)
local observedX=sx2>0 and sxy/sx2 or 0
local observedY=sy2>0 and syy/sy2 or 0
local oldTouchX=(math.pi*2.25)/vp.X
local oldTouchY=(math.pi*2)/vp.Y*invertY
local oldMouseX=(math.pi*4)/1920
local oldMouseY=(math.pi*1.9)/1200*invertY

add("Probe.touchEvents",touchEvents)
add("Probe.samples",samples)
add("Probe.observedRadPerPx.X",observedX)
add("Probe.observedRadPerPx.Y",observedY)
add("Probe.observedDegPerPx.X",math.deg(observedX))
add("Probe.observedDegPerPx.Y",math.deg(observedY))
add("Probe.oldTouchExpectedRadPerPx.X",oldTouchX)
add("Probe.oldTouchExpectedRadPerPx.Y",oldTouchY)
add("Probe.oldMouseExpectedRadPerCount.X",oldMouseX)
add("Probe.oldMouseExpectedRadPerCount.Y",oldMouseY)
add("Probe.observedVsOldTouch.X",oldTouchX~=0 and observedX/oldTouchX or 0)
add("Probe.observedVsOldTouch.Y",oldTouchY~=0 and observedY/oldTouchY or 0)
add("Probe.meanRelativeErrorVsOldTouch",touchErrN>0 and touchErrSum/touchErrN or -1)
add("Probe.mouseYXRatio",oldMouseX~=0 and oldMouseY/oldMouseX or 0)
add("Probe.touchYXRatio",oldTouchX~=0 and oldTouchY/oldTouchX or 0)
add("Probe.observedYXRatio",observedX~=0 and observedY/observedX or 0)
add("Probe.firstSamples",table.concat(sampleLines," | "))

local report=table.concat(lines,"\n")
print(report)
if setclipboard then pcall(setclipboard,report) end
getgenv().CameraX9Report=report
warn("[Camera X9 V3] pronto. Cola o relatório aqui.")
return report
