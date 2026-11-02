local F=dofile('tests/v31-preserved/RobloxFixture.lua')
local E=dofile('tests/v31-preserved/Environment.lua')
local e=E.new(F)
game=e.game;workspace=e.world;getgenv=function() return e.env end
os={clock=function() return e.time end}
local make=Instance.new
Instance.new=function(kind)
 local obj=make(kind)
 if kind=='TextButton' then obj.Activated=F.signal() end
 return obj
end
Enum.UserInputType.MouseButton1={Name='MouseButton1'}
setclipboard=function() end
dofile('PCKeyboardTouchBridgeV3.lua')
local probe=dofile('PCMovementV31MacroConflictProbe.lua')
local ui=dofile('PCMovementV31MacroProbeMobileUI.lua')
local gui=e.pg:FindFirstChild('PCMovementV31MacroProbeMobileUI')
assert(gui and ui and gui.ResetOnSpawn==false,'mobile panel not visible after startup')
local panel=gui:FindFirstChild('Panel')
local status=gui:FindFirstChild('Status',true)
local mark=gui:FindFirstChild('MarkBug',true)
local copy=gui:FindFirstChild('CopyLog',true)
local close=gui:FindFirstChild('EndProbe',true)
local save=gui:FindFirstChild('SaveLog',true)
local header=gui:FindFirstChild('DragHeader',true)
assert(status.Text:find('ATIVO') and mark and copy and close and save and header)
assert(save.Visible==false,'save option visible before a clipboard failure')
local stick=e.pg:FindFirstChild('PCKeyboardTouchBridgeV52Overlay'):FindFirstChild('PCJoystick',true)
local jump=e.pg:FindFirstChild('PCKeyboardTouchBridgeV52Overlay'):FindFirstChild('PCJump',true)
local function overlaps(a,b)
 local ap,as,bp,bs=a.AbsolutePosition,a.AbsoluteSize,b.AbsolutePosition,b.AbsoluteSize
 return ap.X<bp.X+bs.X and ap.X+as.X>bp.X and ap.Y<bp.Y+bs.Y and ap.Y+as.Y>bp.Y
end
assert(panel.AbsolutePosition.X>stick.AbsolutePosition.X+stick.AbsoluteSize.X,'mobile panel covers joystick')
assert(not overlaps(panel,jump),'mobile panel covers PCJump')
local touch={UserInputType=Enum.UserInputType.Touch,Position=stick.AbsolutePosition+stick.AbsoluteSize/2}
e.uis.InputBegan:fire(touch,false)
assert(e.env.PCKeyboardTouchBridgeV52.GetState().movementTouch==touch,'UI stole joystick finger')
local p=panel.Position
local drag={UserInputType=Enum.UserInputType.Touch,Position=header.AbsolutePosition+Vector2.new(10,10)}
header.InputBegan:fire(drag)
drag.Position=drag.Position+Vector2.new(-40,15)
e.uis.InputChanged:fire(drag,false)
e.uis.InputEnded:fire(drag,false)
assert(panel.Position~=p,'header drag did not move panel')
assert(e.env.PCKeyboardTouchBridgeV52.GetState().movementTouch==touch,'drag disrupted movement touch')
local secondDrag={UserInputType=Enum.UserInputType.Touch,Position=header.AbsolutePosition+Vector2.new(10,10)}
header.InputBegan:fire(secondDrag)
secondDrag.Position=secondDrag.Position+Vector2.new(-800,250)
e.uis.InputChanged:fire(secondDrag,false)
e.uis.InputEnded:fire(secondDrag,false)
assert(panel.AbsolutePosition.X>=e.camera.ViewportSize.X*.52 and
    panel.AbsolutePosition.Y+panel.AbsoluteSize.Y<=e.camera.ViewportSize.Y,
    'drag can place the interface over the joystick or off screen')
mark.Activated:fire()
assert(probe.GetReport():find('MARK emote involuntario',1,true),'tap failed to mark the event')
local copied
setclipboard=function(value) copied=value end
copy.Activated:fire()
assert(copied==probe.GetReport() and status.Text:find('COPIADO'),'copy did not confirm success')
local filename,content
writefile=function(path,text) filename=path;content=text end
setclipboard=function() error('clipboard refused') end
copy.Activated:fire()
assert(status.Text:find('ERRO') and save.Visible,'clipboard error did not reveal save fallback')
assert(panel.AbsolutePosition.Y+panel.AbsoluteSize.Y<=e.camera.ViewportSize.Y,'save fallback moved off screen')
assert(not overlaps(panel,jump),'save fallback is hidden behind PCJump')
panel.Position=UDim2.fromOffset(715,180)
-- Simulate an orientation change with a panel dragged to the former bottom.
e.camera.ViewportSize=Vector2.new(390,844)
panel.Position=UDim2.fromOffset(210,640)
e.camera.ViewportSize=Vector2.new(896,414)
assert(panel.AbsolutePosition.Y+panel.AbsoluteSize.Y<=e.camera.ViewportSize.Y,
 'rotation stranded buttons outside the landscape viewport')
assert(not overlaps(panel,jump),'rotation left panel over PCJump')
save.Activated:fire()
assert(filename=='PCMovementV31MacroProbeLog.txt' and content==probe.GetReport() and status.Text:find('SALVO'),
 'save fallback failed')
local keys=e.env.PCKeyboardTouchBridgeV52.GetState().keyEvents
close.Activated:fire()
assert(gui.Parent==nil and e.env.PCMovementV31MacroProbe==nil,'close did not remove both UI and probe')
assert(e.env.PCKeyboardTouchBridgeV52 and e.env.PCKeyboardTouchBridgeV52.GetState().keyEvents==keys,
 'close altered the working V3.1')
e.env.__PCKeyboardTouchBridgeV52Cleanup()
print('PASS: touch buttons, drag, joystick ownership, clipboard confirmation, file fallback and cleanup')
