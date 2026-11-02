-- A broken probe that changes movement, loses the camera finger, hides an
-- overlapping macro GUI or keeps listeners alive will fail this test.
local F=dofile('tests/v31-preserved/RobloxFixture.lua')
local E=dofile('tests/v31-preserved/Environment.lua')
local e=E.new(F)
game=e.game;workspace=e.world;getgenv=function() return e.env end
os={clock=function() return e.time end}
Enum.UserInputType.MouseButton1={Name='MouseButton1'}
Enum.UserInputType.MouseMovement={Name='MouseMovement'}
Enum.KeyCode.G={Name='G'}

local macro=Instance.new('TextButton');macro.Name='ExternalMacroButton';macro.Parent=e.pg
local camera=Instance.new('TextButton');camera.Name='CameraArea';camera.Parent=e.pg
local guiHitCalls=0
local core=Instance.new('Folder');core.Name='CoreGui'
local coreMacro=Instance.new('TextButton');coreMacro.Name='ExternalCoreMacro';coreMacro.Parent=core
local coreHitCalls=0
core.GetGuiObjectsAtPosition=function()
 coreHitCalls+=1
 return {coreMacro}
end
e.services.CoreGui=core
e.pg.GetGuiObjectsAtPosition=function(_,x)
 guiHitCalls+=1
 if x==111 then return {macro,e.pg:FindFirstChild('PCKeyboardTouchBridgeV52Overlay'):FindFirstChild('PCJoystick',true)} end
 if x==700 then return {camera} end
 return {}
end

dofile('PCKeyboardTouchBridgeV3.lua')
local baseEvents=#e.events
dofile('PCMovementV31MacroConflictProbe.lua')
local probe=e.env.PCMovementV31MacroProbe
assert(probe and probe.GetReport and probe.Mark and probe.CopyReport and probe.Stop,'probe API unavailable')
local stick=e.pg:FindFirstChild('PCKeyboardTouchBridgeV52Overlay'):FindFirstChild('PCJoystick',true)
local movement={UserInputType=Enum.UserInputType.Touch,Position=Vector2.new(111,stick.AbsolutePosition.Y+20)}
-- Start on a real stick pixel while another visible button is above it.
assert(movement.Position.X>=stick.AbsolutePosition.X and movement.Position.X<=stick.AbsolutePosition.X+stick.AbsoluteSize.X)
e.uis.InputBegan:fire(movement,false)
local cameraFinger={UserInputType=Enum.UserInputType.Touch,Position=Vector2.new(700,140)}
e.uis.InputBegan:fire(cameraFinger,true)
movement.Position=Vector2.new(111,stick.AbsolutePosition.Y-24)
e.uis.InputChanged:fire(movement,false)
e:step(.10)
e.uis.InputBegan:fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode=Enum.KeyCode.W},false)
e.uis.InputBegan:fire({UserInputType=Enum.UserInputType.MouseButton1,Position=Vector2.new(450,200)},true)
e.uis.InputEnded:fire(cameraFinger,true)
probe.Mark('emote appeared')
local report=probe.GetReport()
local sent=e.env.PCKeyboardTouchBridgeV52.GetState().keyEvents
assert(sent>0 and report:find('keysSent='..sent,1,true),'synthetic keys sent by the bridge were not observable')
assert(report:find('ExternalMacroButton,PCKeyboardTouchBridgeV52Overlay/PCJoystick',1,true),'topmost GUI over stick was lost')
assert(report:find('core=ExternalCoreMacro',1,true),'macro UI under CoreGui was not observed')
assert(report:find('CameraArea',1,true),'other finger was lost')
assert(report:find('owner=joystick',1,true) and report:find('owner=other',1,true),'finger identity was conflated')
assert(report:find('type=Keyboard key=W',1,true),'key input omitted')
assert(report:find('type=MouseButton1',1,true),'mouse button input omitted')
assert(report:find('emote appeared',1,true),'manual event marker omitted')
assert(guiHitCalls==2,'GUI hit testing ran outside touch beginnings')
assert(coreHitCalls==2,'CoreGui hit testing ran outside touch beginnings')
local beforeCopy=#e.events
local clipboard
setclipboard=function(value) clipboard=value end
assert(probe.CopyReport()==true and clipboard==probe.GetReport(),'copy did not preserve exact report')
assert(#e.events==beforeCopy and #e.events>baseEvents,'probe sent inputs or disabled the working bridge')

local center=stick.AbsolutePosition+stick.AbsoluteSize/2
movement.Position=center+Vector2.new(-55,-15)
e.uis.InputChanged:fire(movement,false)
local leftCount=e.env.PCKeyboardTouchBridgeV52.GetState().keyEvents
movement.Position=center+Vector2.new(55,-15)
e.uis.InputChanged:fire(movement,false)
local rightCount=e.env.PCKeyboardTouchBridgeV52.GetState().keyEvents
assert(rightCount>leftCount,'test did not exercise a rapid keyboard transition')
local fastReport=probe.GetReport()
assert(fastReport:find('keysSent='..leftCount,1,true) and fastReport:find('keysSent='..rightCount,1,true),
    'rapid A/D transition was omitted by touch move throttling')

-- At high touch-move volume, trace and GUI query cost remain bounded.
for i=1,4000 do e.uis.InputChanged:fire(movement,false) end
assert(probe.GetState().entries<=320,'input ring grew without bound')
assert(guiHitCalls==2,'high-frequency movement hit-tested UI')
assert(coreHitCalls==2,'high-frequency movement hit-tested CoreGui')
for i=1,330 do probe.Mark('marker '..i) end
assert(probe.GetState().entries==320 and
    not probe.GetReport():find('MARK marker 1 (',1,true) and
    probe.GetReport():find('MARK marker 330 (',1,true),'ring did not evict oldest events')
local active=probe.GetState().entries
probe.Stop();probe.Stop()
e.uis.InputBegan:fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode=Enum.KeyCode.G},false)
assert(probe.GetState().entries==active,'stopped probe still recorded input')
assert(e.env.PCMovementV31MacroProbe==nil,'stopped probe left global owner')
dofile('PCMovementV31MacroConflictProbe.lua')
assert(e.env.PCMovementV31MacroProbe.GetState().entries==0,'reload retained stale trace')
e.env.PCMovementV31MacroProbe.Stop()
e.env.__PCKeyboardTouchBridgeV52Cleanup()
print('PASS: bounded, read-only input trace; joystick/camera finger separation; GUI overlap; key/mouse records; cleanup')
