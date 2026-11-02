-- The optional loader must not fetch the working joystick or the external macro.
local F=dofile('tests/v31-preserved/RobloxFixture.lua')
local E=dofile('tests/v31-preserved/Environment.lua')
local e=E.new(F)
game=e.game;workspace=e.world;getgenv=function() return e.env end
os={clock=function() return e.time end}
local fetched={}
e.game.HttpGet=function(_,url)
 fetched[#fetched+1]=url
 assert(url:find('feature/pc-movement-v31-macro-input-diagnostics-20261102/PCMovementV31MacroConflictProbe.lua?_cb=',1,true),
     'loader fetched a movement module or an unexpected branch')
 return 'probe-source'
end
loadstring=function(source)
 assert(source=='probe-source')
 return function() return dofile('PCMovementV31MacroConflictProbe.lua') end
end
dofile('PCMovementV31MacroProbe_AUTOEXECUTE.lua')
local first=e.env.PCMovementV31MacroProbe
assert(first and first.GetState().active and #fetched==1,'standalone diagnostic did not install')
dofile('PCMovementV31MacroProbe_AUTOEXECUTE.lua')
local second=e.env.PCMovementV31MacroProbe
assert(first.GetState().active==false and second.GetState().active==true and #fetched==2,
    'reexecution duplicated the old listeners')
second.Stop()
assert(e.env.PCMovementV31MacroProbe==nil)
print('PASS: standalone cache-busting probe loader, no joystick/macro fetch, clean reexecution')
