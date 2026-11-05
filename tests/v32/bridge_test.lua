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
move(45,0)
chord("W+D")
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

local jumpTouch={UserInputType=Enum.UserInputType.Touch,Position=jump.AbsolutePosition+jump.AbsoluteSize/2}
local function tap()
    e.uis.InputBegan:fire(jumpTouch,false)
    e.uis.InputEnded:fire(jumpTouch)
end
for burst=1,4 do
    local start=e.time
    tap()
    for i=1,14 do
        move(i%2==0 and -45 or 45,-34)
        e:step(1/60)
    end
    local last
    for _,event in ipairs(e.events) do
        if event.key=="Space" and event.time>=start then last=event end
    end
    assert(last and not last.down and last.time-start>=.199 and last.time-start<=.217)
end
tap()
tap()
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
for _,event in ipairs(e.events) do
    assert(table.find({"W","A","S","D","Space"},event.key),"unexpected synthetic key")
end
print("PASS bridge: standing/low sectors, sweeps, stationary remap, touch ownership, repeated 200 ms Space, cancel")
