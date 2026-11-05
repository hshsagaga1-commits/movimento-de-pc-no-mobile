local F=dofile("tests/v31-preserved/RobloxFixture.lua")
local E=dofile("tests/v31-preserved/Environment.lua")
local e=dofile("tests/v32/Fixture.lua")(F,E)
local function count(t)
    local n=0
    for _ in pairs(t) do n+=1 end
    return n
end
local function connections(signal)
    local n=0
    for _,entry in pairs(signal.listeners) do if entry[1].Connected then n+=1 end end
    return n
end
local cameraCalls={begin=0,changed=0,ended=0}
local camera={
    OnInputBegan=function() cameraCalls.begin+=1 end,
    OnInputChanged=function() cameraCalls.changed+=1 end,
    OnInputEnded=function() cameraCalls.ended+=1 end,
}
local originalChanged=camera.OnInputChanged
local controls={activeControlModule={},activeController={enabled=true},controlsEnabled=true,
    SelectComputerMovementModule=function() end}
local touchModule=controls.activeControlModule
function controls:SelectTouchModule() return touchModule end
function controls:SwitchToController(module)
    self.activeControlModule=module
    self.activeController={enabled=true}
end
local keyboard={}
local playerModule={GetControls=function() return controls end,
    GetCameras=function() return {activeCameraController=camera} end}
local scripts=Instance.new("Folder");scripts.Name="PlayerScripts";scripts.Parent=e.player
local module=Instance.new("ModuleScript");module.Name="PlayerModule";module.Parent=scripts
require=function(asset) assert(asset==module);return playerModule end
getupvalues=function() return {{[Enum.UserInputType.Keyboard]=keyboard}} end
local function install() return dofile("PC_Movement_V32.lua") end
local overlayName="PCKeyboardTouchBridgeV52Overlay"
local function overlay() return e.pg:FindFirstChild(overlayName) end
local api=install()
assert(controls.activeControlModule==keyboard and api.GetState().status=="running")
assert(api.GetState().pcLock.switchLockInstalled)
controls:SwitchToController(touchModule)
assert(controls.activeControlModule==keyboard,"keyboard controller route lost")
assert(e.uis.MouseIconEnabled==false)
e.uis.MouseIconEnabled=true
assert(e.uis.MouseIconEnabled==false,"cursor came back")
local original=overlay()
local bindings=count(e.bound)
local heartbeat=connections(e.run.Heartbeat)
local began=connections(e.uis.InputBegan)
local total=e:liveConnections()
local function finger(control)
    return {UserInputType=Enum.UserInputType.Touch,Position=control.AbsolutePosition+control.AbsoluteSize/2}
end
local function runGesture()
    local stick=overlay():FindFirstChild("PCJoystick")
    local jump=overlay():FindFirstChild("PCJump")
    assert(stick.Size==UDim2.fromOffset(70,70))
    assert(jump.Size==UDim2.fromOffset(70,70))
    local movement=finger(stick)
    local other={UserInputType=Enum.UserInputType.Touch,Position=Vector2.new(700,70)}
    camera:OnInputBegan(movement)
    e.uis.InputBegan:fire(movement)
    e.uis.InputBegan:fire(other)
    camera:OnInputBegan(other)
    movement.Position=movement.Position+Vector2.new(300,0)
    other.Position=Vector2.new(120,40)
    e.uis.InputChanged:fire(movement)
    camera:OnInputChanged(movement)
    camera:OnInputChanged(other)
    assert(api.GetState().bridge.chord=="W+D")
    for i=1,30 do e:step(1/60) end
    assert(stick:FindFirstChild("Knob").Position.X.Offset==70,"knob center did not reach visible edge")
    camera:OnInputEnded(movement)
    camera:OnInputEnded(other)
    e.uis.InputEnded:fire(movement)
    e.uis.InputEnded:fire(other)
    e.uis.InputBegan:fire(finger(jump))
end
runGesture()
assert(cameraCalls.begin==1 and cameraCalls.changed==1 and cameraCalls.ended==1)
assert(connections(e.run.Heartbeat)==heartbeat+1)
for i=1,40 do assert(install()==api and overlay()==original) end
assert(count(e.bound)==bindings and connections(e.uis.InputBegan)==began and e:liveConnections()==total+1)
api.Stop()
assert(overlay()==nil and count(e.bound)==0 and connections(e.run.Heartbeat)==0)
assert(e.uis.MouseIconEnabled==true and camera.OnInputChanged==originalChanged)
assert(connections(e.uis.InputBegan)==0 and count(e.queued)==0)
local events=#e.events
e:step(.5)
assert(#e.events==events)
for _=1,20 do
    api=install()
    assert(overlay() and count(e.bound)==bindings and connections(e.run.Heartbeat)==heartbeat)
    assert(connections(e.uis.InputBegan)==began)
    api.Stop()
    assert(not overlay() and count(e.bound)==0 and connections(e.run.Heartbeat)==0 and e:liveConnections()==0)
end
api=install()
local removed=overlay()
removed:Destroy()
assert(count(e.queued)==1,"no overlay repair queued")
e:step(1.26)
assert(overlay() and overlay()~=removed and api.GetState().repairs==1)
assert(count(e.bound)==bindings and connections(e.uis.InputBegan)==began and e:liveConnections()==total)
overlay():Destroy()
assert(count(e.queued)==1)
api.Stop()
assert(count(e.queued)==0)
e:step(4)
assert(not overlay())

api=install()
local held=finger(overlay():FindFirstChild("PCJoystick"))
held.Position=held.Position+Vector2.new(-25,0)
e.uis.InputBegan:fire(held)
assert(api.GetState().bridge.chord=="W+A")
e.char:SetAttribute("Crouching",true)
assert(api.GetState().bridge.chord=="A")
local oldChar=e.char
e.player.CharacterRemoving:fire(oldChar)
assert(api.GetState().bridge.chord=="-")
local nextChar=Instance.new("Model")
nextChar.Parent=e.world
e.player.Character=nextChar
e.player.CharacterAdded:fire(nextChar)
e:step(.02)
assert(#e.waiters==0,"Assist waited for late character children inside a frame")
local hum=Instance.new("Humanoid")
hum.Parent=nextChar
assert(api.SetAssistMode("original") and api.GetState().assistMode=="original")
assert(api.SetAssistMode("light") and api.GetState().assistMode=="light")
assert(api.SetAssistMode("original"))
api.Stop()
assert(e.env.LegacyGridContactAssistV1==nil)
assert(count(e.bound)==0 and connections(e.run.Heartbeat)==0 and not overlay())

-- Exercise the original LeftControl keyboard discovery fallback while it yields.
local previousLookup=getupvalues
getupvalues=nil
local cancelled=e:spawn(install)
assert(coroutine.status(cancelled)=="suspended" and e.events[#e.events].down)
local waiting=e.env.PCMovementV32
assert(install()==waiting)
waiting.Stop()
assert(install()==waiting and waiting.GetState().status=="stopping")
e:step(.035)
assert(coroutine.status(cancelled)=="dead" and e.env.PCMovementV32==nil)
assert(e.events[#e.events].key=="LeftControl" and not e.events[#e.events].down)
assert(not overlay() and count(e.bound)==0 and #e.waiters==0 and e:liveConnections()==0)
getupvalues=previousLookup
e.game.GameId=1
api=install()
assert(api.GetState().assistMode=="not-applicable" and connections(e.run.Heartbeat)==0)
assert(waiting.SetCursorHidden(true)==nil,"old API mutated a later session")
api.Stop()
print("PASS bundle: controller/camera, native UI, cursor, 40 reentries, 20 stop/start cycles, repair and cancellation")
