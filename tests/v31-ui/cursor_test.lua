local F=dofile('tests/v31-preserved/RobloxFixture.lua')
local E=dofile('tests/v31-preserved/Environment.lua')
local e=E.new(F)
game=e.game;workspace=e.world;getgenv=function() return e.env end
Enum.RenderPriority.Last={Value=2000}
local uis=Instance.new('UserInputService')
uis.MouseIconEnabled=true;uis.MouseEnabled=true;uis.TouchEnabled=true
uis.MouseBehavior='LockCenter';uis.MouseDeltaSensitivity=0.7
e.services.UserInputService=uis
dofile('PCCursorVisualV31.lua')
local api=e.env.PCCursorVisualV31
assert(api and uis.MouseIconEnabled==false,'cursor was not hidden')
assert(uis.MouseEnabled==true and uis.TouchEnabled==true and uis.MouseBehavior=='LockCenter' and uis.MouseDeltaSensitivity==0.7)
uis.MouseIconEnabled=true
assert(uis.MouseIconEnabled==false,'game cursor reset was not corrected')
e.player.CharacterAdded:fire(e.char)
e:step(1/60)
assert(uis.MouseIconEnabled==false)
assert(#e.events==0,'cursor layer emitted virtual input')
api.SetEnabled(false)
assert(uis.MouseIconEnabled==true,'disabling visual hide did not restore preference')
api.SetEnabled(true)
assert(uis.MouseIconEnabled==false)
dofile('PCCursorVisualV31.lua')
local current=e.env.PCCursorVisualV31
assert(current~=api,'reload did not replace cursor owner')
local bindings=0;for _ in pairs(e.bound) do bindings+=1 end
assert(bindings==1,'cursor reload duplicated render guard')
e.env.__PCCursorVisualV31Cleanup()
assert(uis.MouseIconEnabled==true and next(e.bound)==nil)
uis.MouseIconEnabled=false;e:step(1/60)
assert(uis.MouseIconEnabled==false,'stopped cursor layer still changed state')
uis.MouseIconEnabled=true
local bind=e.services.RunService.BindToRenderStep
e.services.RunService.BindToRenderStep=function() error('injected render binding failure') end
assert(pcall(dofile,'PCCursorVisualV31.lua')==false,'cursor setup failure did not propagate')
assert(uis.MouseIconEnabled==true and e.env.PCCursorVisualV31==nil,'partial cursor setup was not restored')
uis.MouseIconEnabled=false
assert(uis.MouseIconEnabled==false,'failed setup left an active property connection')
e.services.RunService.BindToRenderStep=bind
print('PASS: cursor visual-only property, persistence, disable/restore, reload and cleanup')
