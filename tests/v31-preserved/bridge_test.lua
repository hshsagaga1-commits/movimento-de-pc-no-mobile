local F=dofile('tests/v31-preserved/RobloxFixture.lua')
local E=dofile('tests/v31-preserved/Environment.lua')
local e=E.new(F)
game=e.game;workspace=e.world;getgenv=function() return e.env end
os={clock=function() return e.time end}
task={spawn=function(fn) return e:spawn(fn) end,delay=function() end}
dofile('PCKeyboardTouchBridgeV3.lua')
dofile('PCRobloxNativeVisualV5.lua')
local gui=e.pg:FindFirstChild('PCKeyboardTouchBridgeV52Overlay')
local stick=gui:FindFirstChild('PCJoystick',true)
local jump=gui:FindFirstChild('PCJump',true)
assert(stick.Size==UDim2.fromOffset(70,70))
local finger={UserInputType=Enum.UserInputType.Touch,Position=stick.AbsolutePosition+stick.AbsoluteSize/2+Vector2.new(-30,0)}
e.uis.InputBegan:fire(finger,false)
assert(e.env.PCKeyboardTouchBridgeV52.GetState().chord=='A','original pure lateral A changed')
finger.Position=stick.AbsolutePosition+stick.AbsoluteSize/2+Vector2.new(30,0)
e.uis.InputChanged:fire(finger)
assert(e.env.PCKeyboardTouchBridgeV52.GetState().chord=='D','original immediate A/D side swap changed')
finger.Position=stick.AbsolutePosition+stick.AbsoluteSize/2+Vector2.new(0,-46)
e.uis.InputChanged:fire(finger)
assert(e.env.PCKeyboardTouchBridgeV52.GetState().chord=='W')
finger.Position=stick.AbsolutePosition+stick.AbsoluteSize/2+Vector2.new(1,-46)
e.uis.InputChanged:fire(finger)
assert(e.env.PCKeyboardTouchBridgeV52.GetState().chord=='W+A+D','original near-forward chord changed')
finger.Position=stick.AbsolutePosition+stick.AbsoluteSize/2+Vector2.new(46,0)
e.uis.InputChanged:fire(finger)
finger.Position=stick.AbsolutePosition+stick.AbsoluteSize/2+Vector2.new(-36.8,-36.8)
e.uis.InputChanged:fire(finger)
assert(e.env.PCKeyboardTouchBridgeV52.GetState().chord=='W+D','original staged turn entry changed')
e:step(0.02)
assert(e.env.PCKeyboardTouchBridgeV52.GetState().chord=='W+A+D','original staged A/D overlap changed')
e:step(0.02)
assert(e.env.PCKeyboardTouchBridgeV52.GetState().chord=='W+A','original staged A/D destination changed')
e:step(0.02)
finger.Position=stick.AbsolutePosition+stick.AbsoluteSize/2+Vector2.new(500,0)
e.uis.InputChanged:fire(finger)
for i=1,30 do e:step(1/60) end
local knob=stick:FindFirstChild('Knob')
local rightmost=knob.Position.X.Offset+knob.AbsoluteSize.X/2
assert(rightmost>80,'original knob may visibly extend beyond 70px ring')
e.uis.InputEnded:fire(finger)
local jumpFinger={UserInputType=Enum.UserInputType.Touch,Position=jump.AbsolutePosition+jump.AbsoluteSize/2}
e.uis.InputBegan:fire(jumpFinger,false)
local began=e.time
for i=1,15 do e:step(1/60) end
local downs=0;local last
for _,event in ipairs(e.events) do
    if event.key=='Space' then last=event; if event.down then downs=downs+1 end end
end
assert(downs>=8,'original 200ms jump burst was replaced')
assert(last and not last.down and last.time-began<=0.23,'Space not released after original burst')
e.env.__PCKeyboardTouchBridgeV52Cleanup()
assert(e.env.PCKeyboardTouchBridgeV52==nil)
print('PASS: actual untouched V3 bridge/visuals: A/D swap, original chords, knob beyond circle and 200ms jump')
