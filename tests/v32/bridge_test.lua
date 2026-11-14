local F=dofile("tests/v31-preserved/RobloxFixture.lua")
local E=dofile("tests/v31-preserved/Environment.lua")
local e=E.new(F)
game=e.game
workspace=e.world
getgenv=function() return e.env end
os={clock=function() return e.time end}
task={spawn=function(fn) return e:spawn(fn) end,delay=function() end}
e.uis.WindowFocusReleased=F.signal()
e.player.CharacterRemoving=F.signal()

local baseline=TEST_BASELINE
local setPosture
if baseline then
    dofile("PCKeyboardTouchBridgeV3.lua")
else
    factory("v32/Bridge.lua")(function(onChange)
        setPosture=onChange
        return function() end
    end)
end
local bridge=e.env.PCKeyboardTouchBridgeV52
local gui=e.pg:FindFirstChild("PCKeyboardTouchBridgeV52Overlay")
local stick=gui:FindFirstChild("PCJoystick")
local jump=gui:FindFirstChild("PCJump")
local center=stick.AbsolutePosition+stick.AbsoluteSize/2
local touch={UserInputType=Enum.UserInputType.Touch}
local function move(x,z,begin)
    touch.Position=center+Vector2.new(x,z)
    if begin then e.uis.InputBegan:fire(touch,false) else e.uis.InputChanged:fire(touch) end
end
local function chord(expected)
    local got=bridge.GetState().chord
    assert(got==expected,"expected "..expected..", got "..got)
end
move(-45,0,true)
chord("W+A")
local swapStart=#e.events
move(45,0)
chord("W+D")
assert(#e.events==swapStart+2 and e.events[swapStart+1].key=="D" and e.events[swapStart+1].down
    and e.events[swapStart+2].key=="A" and not e.events[swapStart+2].down,"standing side swap lost press-before-release")
move(1,-45)
chord("W")
move(0,45)
chord("S")
move(-45,45)
chord("A+S")
move(45,45)
chord("S+D")
move(-45,-34)
chord("W+A")
move(45,-34)
chord("W+A+D")
e:step(.02)
chord("W+D")
move(-45,-34)
chord("W+A+D")
setPosture(true,"crouch")
chord("A")
move(45,-34)
chord("A+D")
e:step(.02)
chord("D")
move(-45,0)
chord("A")
move(45,0)
chord("D")
move(0,45)
chord("S")
move(-45,45)
chord("A+S")
move(45,45)
chord("S+D")
move(1,-45)
chord("W+A+D")
move(0,-45)
chord("W")
move(-45,0)
setPosture(false,"standing")
chord("W+A")
setPosture(true,"emote")
chord("A")
setPosture(false,"standing")
chord("W+A")
move(1,0)
chord("W+A")
e:step(.02)
chord("-")
move(-45,0)
local camera={UserInputType=Enum.UserInputType.Touch,Position=Vector2.new(700,120)}
e.uis.InputBegan:fire(camera,false)
e.uis.InputChanged:fire(camera)
e.uis.InputEnded:fire(camera)
assert(bridge.OwnsTouch(touch) and not bridge.OwnsTouch(camera))
chord("W+A")
local nativeEvents=0
local listener=e.uis.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Keyboard then nativeEvents+=1 end
end)
local beforeKeyboard=#e.events
e.uis.InputBegan:fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode={Name="E"}},false)
assert(nativeEvents==1 and #e.events==beforeKeyboard and bridge.GetState().chord=="W+A")
listener:Disconnect()

local jumpTouch={UserInputType=Enum.UserInputType.Touch,Position=jump.AbsolutePosition+jump.AbsoluteSize/2}
local function tap()
    e.uis.InputBegan:fire(jumpTouch,false)
    e.uis.InputEnded:fire(jumpTouch)
end
for burst=1,4 do
    local first=#e.events
    e.uis.InputBegan:fire(jumpTouch,false)
    assert(bridge.GetState().jumpActive,"Space must go down immediately")
    assert(bridge.OwnsTouch(jumpTouch),"jump finger must be owned by the bridge")
    e:step(1/60)
    e.uis.InputEnded:fire(jumpTouch)
    assert(not bridge.GetState().jumpActive,"Space must release on finger up")
    local downs,ups=0,0
    for i=first+1,#e.events do
        local event=e.events[i]
        if event.key=="Space" then
            if event.down then downs+=1 else ups+=1 end
        end
    end
    assert(downs==1 and ups==1,"one tap must emit exactly one Space down/up")
end
e.uis.InputBegan:fire(jumpTouch,false)
e:step(.16)
assert(bridge.GetState().jumpActive,"Space hold should follow finger, not 200 ms timer")
e.uis.WindowFocusReleased:fire()
assert(not bridge.GetState().jumpActive,"focus loss must release held Space")
assert(#e.waiters==0,"jump spawned a waiting task")
e.uis.WindowFocusReleased:fire()
chord("-")
local count=#e.events
e:step(.25)
assert(#e.events==count,"cancelled jump produced late events")
move(45,0,true)
e.player.CharacterRemoving:fire(e.char)
chord("-")
e.env.__PCKeyboardTouchBridgeV52Cleanup()
assert(next(e.bound)==nil and #e.waiters==0)
assert(not e.env.PCKeyboardTouchBridgeV52)
for _,signal in pairs({e.uis.InputBegan,e.uis.InputChanged,e.uis.InputEnded,e.uis.WindowFocusReleased,e.run.Heartbeat}) do
    for _,entry in ipairs(signal.listeners) do assert(not entry[1].Connected) end
end
local vim=e.services.VirtualInputManager
local realSend=vim.SendKeyEvent
local failures=0
vim.SendKeyEvent=function(self,down,key,...)
    if key.Name=="A" and not down and failures==0 then failures+=1 error("injection temporarily unavailable") end
    realSend(self,down,key,...)
end
local module=factory("v32/Bridge.lua")
bridge=module(function() return function() end end)
gui=e.pg:FindFirstChild("PCKeyboardTouchBridgeV52Overlay")
stick=gui:FindFirstChild("PCJoystick")
center=stick.AbsolutePosition+stick.AbsoluteSize/2
move(-45,0,true)
move(45,0)
chord("W+A+D")
e:step(.035)
chord("W+D")
e.env.__PCKeyboardTouchBridgeV52Cleanup()
for _,event in ipairs(e.events) do
    assert(table.find({"W","A","S","D","Space"},event.key),"unexpected synthetic key")
end
print("PASS bridge: standing/low sectors, sweeps, touch ownership, finger-held Space, immediate release, cancel")
