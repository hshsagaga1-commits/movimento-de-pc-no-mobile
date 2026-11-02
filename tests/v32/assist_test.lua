local F=dofile('tests/v31-preserved/RobloxFixture.lua')
local E=dofile('tests/v31-preserved/Environment.lua')
local e=E.new(F)
game=e.game;workspace=e.world;getgenv=function() return e.env end
os={clock=function() return e.time end}
local chord='D'
e.env.PCKeyboardTouchBridgeV52={GetState=function()
 return {chord=chord,analogX=1,analogZ=0,jumpPulses=0}
end}
local rail=e:part('Part',Vector3.new(6,0.3,0.3))
rail.Material=Enum.Material.Plastic
e.parts={rail};e.root.Touching={}
e.raycast=function(origin)
 return {Instance=rail,Position=Vector3.new(2,origin.Y,0),Normal=Vector3.new(0,1,0)}
end
local velocityWrites=0
e.root:GetPropertyChangedSignal('AssemblyLinearVelocity'):Connect(function() velocityWrites+=1 end)
dofile('LegacyGridContactAssistV32.lua')
local assist=e.env.LegacyGridContactAssistV1
e:step(0.06)
assert(assist.GetState().mode:find('horizontal%-rail'),
 'top of a thin collidable rail was missed by near-contact detection')
assert(assist.GetState().contactConfirmed==false,
 'a ray to the top of a rail was incorrectly labeled physical contact')
rail.Position=Vector3.new(0,1.8,0)
rail.GetClosestPointOnSurface=function() return rail.Position end
e.raycast=function(_,direction)
 if math.abs(direction.Y)<0.01 then return nil end
 return {Instance=rail,Position=rail.Position,Normal=Vector3.new(0,1,0)}
end
e:step(0.2)
assert(assist.GetState().mode:find('horizontal%-rail'),
 'centered rail below the avatar was lost because its horizontal normal is zero')
assert(assist.GetState().contactConfirmed==false,'centered nearby rail became physical contact')
local before=e.root.CFrame
e.hum.FloorMaterial=Enum.Material.Air
e:step(0.06)
assert(e.root.CFrame==before,'pure A/D air movement forced avatar facing during reverse BHOP')
e.hum.FloorMaterial=Enum.Material.Concrete
e:step(0.06)
assert(e.root.CFrame~=before,'grounded V3.1 facing was removed')
assert(velocityWrites==0,'V3.2 introduced an artificial speed or vertical impulse')
assist.SetDiagnostics(true)
e.root.Touching={rail};e:step(0.06)
chord='-'
e.root.AssemblyLinearVelocity=Vector3.new(32,5,-40)
e:step(0.06)
assert(assist.GetState().verticalChangesNearGrid>=1,
 'release of the stick hid the vertical change after real rail contact')
assist.GetState().diagnostics=false
e.env.__LegacyGridContactAssistV1Cleanup()
print('PASS: top rail opportunity, no false contact, A/D reverse BHOP facing, unchanged velocity, release trace')
