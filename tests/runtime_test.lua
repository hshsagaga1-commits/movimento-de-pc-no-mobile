assert(loadfile("rebuild/Runtime.lua"),"REBUILD MISSING: one runtime owns all movement inputs")
local F=dofile("tests/RobloxFixture.lua");F.install()
local Runtime=dofile("rebuild/Runtime.lua")
local modules={}
for _,name in ipairs({"Core","GridSensor","Controls","KeyboardRoute","CameraGate"}) do
    modules[name]=dofile("rebuild/"..name..".lua")
end
local time=0
local pg=Instance.new("Folder");pg.Name="PlayerGui"
local player=Instance.new("Folder")
player.CharacterAdded=F.signal();player.CharacterRemoving=F.signal()
local char=Instance.new("Model");char.Name="PlayerCharacter";char.Parent=player
char.DescendantAdded=F.signal()
local root=Instance.new("Part");root.Name="HumanoidRootPart";root.Parent=char
root.Size=Vector3.new(2,2,1);root.CollisionGroup="Default";root.CanCollide=true
root.AssemblyLinearVelocity=Vector3.new(0,0,-45)
root.CFrame={LookVector=Vector3.new(0,0,-1),RightVector=Vector3.new(1,0,0),UpVector=Vector3.new(0,1,0)}
local hum=Instance.new("Humanoid");hum.Parent=char
hum.Health=100;hum.Sit=false;hum.PlatformStand=false;hum.FloorMaterial=Enum.Material.Concrete
hum.State=Enum.HumanoidStateType.Running
hum.GetState=function(self) return self.State end
hum.GetStateEnabled=function() return true end
player.Character=char
local input={InputBegan=F.signal(),InputChanged=F.signal(),InputEnded=F.signal(),
    WindowFocusReleased=F.signal(),WindowFocused=F.signal(),TextBoxFocused=F.signal(),TextBoxFocusReleased=F.signal()}
function input:GetFocusedTextBox() return self.focused end
local run={bound={}}
function run:BindToRenderStep(name,priority,fn) self.bound[name]=fn end
function run:UnbindFromRenderStep(name) self.bound[name]=nil end
local function frame(dt)
    time=time+(dt or 1/60)
    for _,fn in pairs(run.bound) do fn(dt or 1/60) end
end
local touchModule={};local keyboardModule={}
local keyboard={enabled=true,keys={}}
function keyboard:Enable(v)
    if self.enabled~=v then self.keys={} end
    self.enabled=v
end
local controls={activeControlModule=touchModule,activeController={enabled=true},controlsEnabled=true}
function controls:SwitchToController(module)
    self.activeControlModule=module
    self.activeController=module==keyboardModule and keyboard or {enabled=true}
end
local nativeCamera={}
function nativeCamera:OnInputBegan() end
function nativeCamera:OnInputChanged() end
function nativeCamera:OnInputEnded() end
local events={}
local services={player=player,playerGui=pg,UserInputService=input,RunService=run,
    Workspace={CurrentCamera={ViewportSize=Vector2.new(896,414),CFrame=root.CFrame}},
    VirtualInputManager={SendKeyEvent=function(_,down,key)
        events[#events+1]={key=key.Name,down=down};keyboard.keys[key.Name]=down
    end},
    Controls=controls,KeyboardModule=keyboardModule,TouchModules={touchModule},
    GetCameraController=function() return nativeCamera end,
    Clock=function() return time end,GameId=3647333358,
    CollectionService={HasTag=function() return false end},
    PhysicsService={CollisionGroupsAreCollidable=function() return true end}}
function services.Workspace:GetPartBoundsInBox() return {} end
local env={}
local api=Runtime.Start(modules,{},services,env)
local stick=pg:FindFirstChild("PCKeyboardTouchBridgeV52Overlay"):FindFirstChild("PCJoystick",true)
local finger={UserInputType=Enum.UserInputType.Touch,
    Position=stick.AbsolutePosition+stick.AbsoluteSize/2+Vector2.new(-30,-30)}
input.InputBegan:fire(finger,false)
assert(api.GetState().chord=="W+A","standing input must be immediate")
hum.FloorMaterial=Enum.Material.Air;hum.State=Enum.HumanoidStateType.Freefall
frame()
assert(api.GetState().chord=="A","air transition must release W")
finger.Position=stick.AbsolutePosition+stick.AbsoluteSize/2+Vector2.new(30,-30)
input.InputChanged:fire(finger)
assert(api.GetState().chord=="D","A/D reversal must finish in input event")
input.WindowFocusReleased:fire()
assert(api.GetState().chord=="-","background must release all keys")
input.WindowFocused:fire();frame()
assert(api.GetState().chord=="-","focus return must require a new physical touch")
input.InputBegan:fire(finger,false)
assert(api.GetState().chord=="D")
hum.Health=0;frame()
assert(api.GetState().chord=="-","death must release all keys")
hum.Health=100;hum.State=Enum.HumanoidStateType.Running;hum.FloorMaterial=Enum.Material.Concrete
frame()
assert(api.GetState().chord=="-","revival cannot reuse dead finger")
input.InputBegan:fire(finger,false)
assert(api.GetState().chord=="W+D")
api.SetEnabled(false)
assert(api.GetState().chord=="-")
api.SetEnabled(true);frame(0.3)
input.InputBegan:fire(finger,false)
assert(api.GetState().chord=="W+D")
stick.Position=UDim2.fromOffset(50,190)
local again=Runtime.Start(modules,{},services,env)
assert(env.PCMovementRebuild==again)
assert(pg:FindFirstChild("PCKeyboardTouchBridgeV52Overlay"):FindFirstChild("PCJoystick",true)==stick)
assert(stick.Position==UDim2.fromOffset(50,190))
local bindings=0;for _ in pairs(run.bound) do bindings=bindings+1 end
assert(bindings==1,"duplicate runtime render loop")
again.Stop()
assert(next(run.bound)==nil)
assert(pg:FindFirstChild("PCKeyboardTouchBridgeV52Overlay")==nil)
assert(env.PCMovementRebuild==nil)
local legacy=modules.Controls.new(services)
legacy.gui:SetAttribute("PCMovementRebuild",nil)
legacy.joystick.Position=UDim2.fromOffset(200,170)
legacy.joystick:SetAttribute("Locked",true)
env.PCMovementAssistV31={Stop=function() legacy.gui:Destroy() end}
local migrated=Runtime.Start(modules,{},services,env)
local migratedStick=pg:FindFirstChild("PCKeyboardTouchBridgeV52Overlay"):FindFirstChild("PCJoystick",true)
assert(migratedStick.Position==UDim2.fromOffset(200,170),"legacy watcher destroyed customized layout before migration")
assert(migratedStick:GetAttribute("Locked")==true)
finger.Position=migratedStick.AbsolutePosition+migratedStick.AbsoluteSize/2+Vector2.new(-25,-25)
input.InputBegan:fire(finger,false)
assert(migrated.GetState().observation.crouchSource=="unknown")
migrated.SetStateProvider(function() return {emote=true,crouched=false} end)
assert(migrated.GetState().chord=="A","explicit emote provider must select A/D only")
migrated.SetStateProvider(nil)
assert(migrated.GetState().chord=="W+A")
root.CanCollide=false
local torso=Instance.new("Part");torso.Name="UpperTorso";torso.Parent=char
torso.CanCollide=true;torso.CollisionGroup="Default";torso.Size=Vector3.new(2,2,1)
local fence=Instance.new("Part");fence.Name="Fence";fence.Parent=Instance.new("Model")
fence.CanCollide=true;fence.CollisionGroup="Default";fence.Size=Vector3.new(0.2,5,8)
torso.Touching={fence}
char.DescendantAdded:fire(torso)
frame(0.1)
assert(migrated.GetState().observation.gridContact==true,"late character body was not bound to grid sensor")
local jumpButton=pg:FindFirstChild("PCKeyboardTouchBridgeV52Overlay"):FindFirstChild("PCJump",true)
local jumpFinger={UserInputType=Enum.UserInputType.Touch,UserInputState=Enum.UserInputState.Begin,
    Position=jumpButton.AbsolutePosition+jumpButton.AbsoluteSize/2}
input.InputBegan:fire(jumpFinger,false)
assert(migrated.GetState().chord:find("Space"))
jumpFinger.UserInputState=Enum.UserInputState.Cancel
input.InputChanged:fire(jumpFinger)
assert(not migrated.GetState().chord:find("Space"),"cancelled jump kept Space down")
finger.UserInputState=Enum.UserInputState.End
frame(0.1)
assert(migrated.GetState().chord=="-","missed InputEnded kept movement alive")
local oldKnob=migratedStick:FindFirstChild("Knob")
oldKnob:Destroy();frame(0.3)
assert(pg:FindFirstChild("PCKeyboardTouchBridgeV52Overlay"):FindFirstChild("PCJoystick",true):FindFirstChild("Knob"),"missing knob was not repaired")
migrated.Stop()
local originalBind=run.BindToRenderStep
run.BindToRenderStep=function() error("injected startup bind failure") end
local success=pcall(Runtime.Start,modules,{},services,env)
assert(not success)
assert(env.PCMovementRebuild==nil,"failed startup left a running API")
for _,listener in ipairs(input.InputBegan.listeners) do
    assert(not listener[1].Connected,"failed startup left live input listener")
end
assert(controls.activeControlModule==touchModule,"failed startup kept Keyboard selected")
run.BindToRenderStep=originalBind
local goodGetter=services.GetCameraController
services.GetCameraController=function() error("injected camera startup failure") end
success=pcall(Runtime.Start,modules,{},services,env)
assert(not success and env.PCMovementRebuild==nil,"camera startup failure was not rolled back")
assert(next(run.bound)==nil)
services.GetCameraController=goodGetter
local resilient=Runtime.Start(modules,{},services,env)
local liveGui=pg:FindFirstChild("PCKeyboardTouchBridgeV52Overlay")
local liveJump=liveGui:FindFirstChild("PCJump",true)
local j1={UserInputType=Enum.UserInputType.Touch,UserInputState=Enum.UserInputState.Begin,
    Position=liveJump.AbsolutePosition+liveJump.AbsoluteSize/2}
local j2={UserInputType=Enum.UserInputType.Touch,UserInputState=Enum.UserInputState.Begin,Position=j1.Position}
input.InputBegan:fire(j1,false);input.InputBegan:fire(j2,false)
j1.UserInputState=Enum.UserInputState.Cancel;input.InputChanged:fire(j1)
frame(0.3)
assert(resilient.GetState().observation.jumpIntent==true,"cancelling one finger cleared another jump finger")
j2.UserInputState=Enum.UserInputState.End;frame(0.3)
assert(resilient.GetState().observation.jumpIntent==false,"missed jump End kept BHOP intent")
local liveStick=liveGui:FindFirstChild("PCJoystick",true)
local resumedFinger={UserInputType=Enum.UserInputType.Touch,UserInputState=Enum.UserInputState.Begin,
    Position=liveStick.AbsolutePosition+liveStick.AbsoluteSize/2+Vector2.new(-25,-25)}
input.InputBegan:fire(resumedFinger,false)
assert(keyboard.keys.A==true)
keyboard:Enable(false)
frame(0.3)
assert(keyboard.keys.A==true,"keyboard reactivation forgot held input; route must replay its key edges")
services.GetCameraController=function() error("injected callback failure") end
frame(0.3)
assert(env.PCMovementRebuild==nil and next(run.bound)==nil,"callback error failed to stop and release runtime")
assert(resilient.GetState().chord=="-")
services.GetCameraController=goodGetter
print("PASS: runtime immediate input, airborne transition, background/death, reload and cleanup")
