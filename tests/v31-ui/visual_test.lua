local F=dofile('tests/v31-preserved/RobloxFixture.lua')
local E=dofile('tests/v31-preserved/Environment.lua')
local function execute(path)
 local e=E.new(F)
 game=e.game;workspace=e.world;getgenv=function() return e.env end
 os={clock=function() return e.time end}
 task={spawn=function(fn) return e:spawn(fn) end,delay=function() end}
 local clicks=0
 e.services.VirtualInputManager.SendMouseButtonEvent=function() clicks+=1 end
 dofile(path);dofile('PCRobloxNativeVisualV5.lua')
 local gui=e.pg:FindFirstChild('PCKeyboardTouchBridgeV52Overlay')
 local stick=gui:FindFirstChild('PCJoystick',true)
 local finger={UserInputType=Enum.UserInputType.Touch}
 local samples={}
 local function move(x,z)
  finger.Position=stick.AbsolutePosition+stick.AbsoluteSize/2+Vector2.new(x,z)
  if not e.env.PCKeyboardTouchBridgeV52.GetState().movementTouchActive then e.uis.InputBegan:fire(finger,false)
  else e.uis.InputChanged:fire(finger) end
  samples[#samples+1]=e.env.PCKeyboardTouchBridgeV52.GetState().chord
  e:step(0.02)
 end
 move(-30,0);move(30,0);move(-30,-30);e:step(0.02);e:step(0.02)
 move(0,-46);move(1,-46);move(0,46);move(500,0)
 e.uis.InputEnded:fire(finger)
 local jump=gui:FindFirstChild('PCJump',true)
 e.uis.InputBegan:fire({UserInputType=Enum.UserInputType.Touch,Position=jump.AbsolutePosition+jump.AbsoluteSize/2},false)
 for i=1,15 do e:step(1/60) end
 e.env.__PCKeyboardTouchBridgeV52Cleanup()
 local trace={}
 for _,event in ipairs(e.events) do trace[#trace+1]=event.key..':'..tostring(event.down)..':'..string.format('%.3f',event.time) end
 return table.concat(trace,','),table.concat(samples,','),clicks
end
local before,oldSamples,oldClicks=execute('reference/bridge.lua')
local after,newSamples,newClicks=execute('PCKeyboardTouchBridgeV3.lua')
assert(before==after and oldSamples==newSamples,'visual edit altered key sequence, timing or jump')
assert(oldClicks==0 and newClicks==0,'joystick unexpectedly synthesizes a mouse click')
local e=E.new(F)
game=e.game;workspace=e.world;getgenv=function() return e.env end
os={clock=function() return e.time end}
task={spawn=function(fn) return e:spawn(fn) end,delay=function() end}
dofile('PCKeyboardTouchBridgeV3.lua');dofile('PCRobloxNativeVisualV5.lua')
local stick=e.pg:FindFirstChild('PCKeyboardTouchBridgeV52Overlay'):FindFirstChild('PCJoystick',true)
local knob=stick:FindFirstChild('Knob')
for _,size in ipairs({70,120,200}) do
 stick.Size=UDim2.fromOffset(size,size)
 knob.Size=UDim2.fromOffset(size/2,size/2)
 local finger={UserInputType=Enum.UserInputType.Touch,Position=stick.AbsolutePosition+stick.AbsoluteSize/2}
 e.uis.InputBegan:fire(finger,false)
 local radius=size/2
 for _,delta in ipairs({Vector2.new(radius/2,0),Vector2.new(radius,0),Vector2.new(radius*4,0),Vector2.new(-radius*4,0),Vector2.new(0,-radius*4)}) do
  finger.Position=stick.AbsolutePosition+stick.AbsoluteSize/2+delta
  e.uis.InputChanged:fire(finger)
  for i=1,30 do e:step(1/60) end
  local target=delta.Magnitude>radius and delta.Unit*radius or delta
  assert(math.abs(knob.Position.X.Offset-(radius+target.X))<0.1,'wrong visual X clamp')
  assert(math.abs(knob.Position.Y.Offset-(radius+target.Y))<0.1,'wrong visual Y clamp')
  local state=e.env.PCKeyboardTouchBridgeV52.GetState()
  local logical=math.max(46,size*0.42)
  assert(math.abs(state.analogX-delta.X/logical)<0.0001,'logical radius changed with visual radius')
 end
 e.uis.InputEnded:fire(finger)
end
e.env.__PCKeyboardTouchBridgeV52Cleanup()
print('PASS: native-radius knob at 70/120/200px; outside drag preserved; exact same key/jump traces and no mouse clicks')
