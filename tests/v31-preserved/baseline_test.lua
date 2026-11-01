local F=dofile('tests/v31-preserved/RobloxFixture.lua')
local E=dofile('tests/v31-preserved/Environment.lua')
local e=E.new(F)
game=e.game;workspace=e.world;getgenv=function() return e.env end
os={clock=function() return e.time end}
e.env.PCKeyboardTouchBridgeV52={GetState=function() return {chord='D',analogX=1,analogZ=0} end}
local fence=e:part('Fence');e.root.Touching={fence};e.parts={fence}
e.raycast=function(origin) return {Instance=fence,Position=Vector3.new(2,origin.Y,0),Normal=Vector3.new(-1,0,0)} end
local writes=0
e.root:GetPropertyChangedSignal('AssemblyLinearVelocity'):Connect(function() writes=writes+1 end)
dofile('LegacyGridContactAssistV31.lua')
e:step(0.05)
assert(writes>0,'controlled original contact must demonstrate its velocity writer')
e.env.__LegacyGridContactAssistV1Cleanup()
e.root.AssemblyLinearVelocity=Vector3.new(32,0,-40);writes=0
dofile('LegacyGridContactAssistV31Preserved.lua')
for i=1,20 do e:step(0.05) end
assert(writes==0,'tuned contact retained the original velocity motor')
e.env.__LegacyGridContactAssistV1Cleanup()
print('PASS: original Assist reproduces velocity correction; tuned Assist removes that writer in same contact fixture')
