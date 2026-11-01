local F=dofile('tests/v31-preserved/RobloxFixture.lua')
local E=dofile('tests/v31-preserved/Environment.lua')
local e=E.new(F)
game=e.game;workspace=e.world;getgenv=function() return e.env end
os={clock=function() return e.time end}
local chord='A';local pulses=0
e.env.PCKeyboardTouchBridgeV52={GetState=function()
 return {chord=chord,analogX=chord=='A' and -1 or 1,analogZ=0,jumpPulses=pulses}
end}
local fence=e:part('Fence')
e.root.Touching={fence};e.parts={fence}
e.raycast=function(origin,direction)
 return {Instance=fence,Position=Vector3.new(2,origin.Y,0),Normal=Vector3.new(-1,0,0)}
end
local writes=0
e.root:GetPropertyChangedSignal('AssemblyLinearVelocity'):Connect(function() writes=writes+1 end)
dofile('LegacyGridContactAssistV31Preserved.lua')
local api=e.env.LegacyGridContactAssistV1
assert(api and api.Version:find('preserved'))
local exported,reason,text=api.ExportDiagnostics()
assert(exported==false and type(text)=='string','diagnostics before the first sample must still be serializable')
for i=1,60 do chord=i%2==0 and 'A' or 'D'; e:step(1/60) end
assert(writes==0,'contact/reversal wrote artificial character velocity')
assert(api.GetState().contactConfirmed==true,'actual body/grid contact not distinguished')
assert(e.rays<=700,'raycasts exceeded the bounded 40 per 20Hz scan budget')
assert(e.queries<=15,'overlap query rate exceeded mobile budget')
e.root.Touching={};e:step(0.1)
assert(api.GetState().contactConfirmed==false,'proximity became real contact')
e.parts={}
for i=1,48 do e.parts[i]=e:part('Fence'..i,Vector3.new(0.2,4,1),Vector3.new(2+i/100,2,0)) end
local startRays=e.rays
for i=1,60 do
 local before=e.rays;e:step(1/60)
 assert(e.rays-before<=40,'a frame exceeded the per-scan ray ceiling')
end
assert(e.rays-startRays<=840,'crowded nearby grids caused unbounded ray work')
local bar=e:part('Part',Vector3.new(6,0.3,0.3))
bar.Material=Enum.Material.Plastic;e.parts={bar};e.root.Touching={bar};e:step(0.1)
assert(api.GetState().mode:find('horizontal%-rail'),'unnamed horizontal railing was rejected as not upright')
local floor=e:part('GridFloor',Vector3.new(20,0.3,20))
e.parts={floor};e.root.Touching={floor};e.raycast=function(origin)
 return {Instance=floor,Position=Vector3.new(2,origin.Y,0),Normal=Vector3.new(-1,0,0)}
end
e:step(0.2)
assert(not api.GetState().contactConfirmed,'floor mislabeled as collidable grid')
fence.CanCollide=false;e.parts={fence};e.root.Touching={fence};e:step(0.2)
assert(not api.GetState().contactConfirmed,'named noncollidable decoration became physical contact')
fence.CanCollide=true;e.parts={fence};e.root.Touching={fence};e:step(0.2)
api.SetDiagnostics(true)
e.root.AssemblyLinearVelocity=Vector3.new(32,5,-40);pulses=pulses+1;e:step(0.05)
assert(#api.GetLogs()>0)
e.env.__LegacyGridContactAssistV1Cleanup()
assert(e.env.LegacyGridContactAssistV1==nil,'cleanup left stale V3.1 API')
local before=e.rays;e:step(0.1);assert(e.rays==before,'cleanup left contact loop running')
print('PASS: tuned V3.1 assist: no velocity writes/reversal braking, physical contact distinction, query budget, logs and cleanup')
