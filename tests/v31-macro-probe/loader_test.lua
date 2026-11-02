-- The optional loader must not fetch the working joystick or the external macro.
local F=dofile('tests/v31-preserved/RobloxFixture.lua')
local E=dofile('tests/v31-preserved/Environment.lua')
local e=E.new(F)
game=e.game;workspace=e.world;getgenv=function() return e.env end
os={clock=function() return e.time end}
local make=Instance.new
Instance.new=function(kind)
 local obj=make(kind)
 if kind=='TextButton' then obj.Activated=F.signal() end
 return obj
end
Enum.UserInputType.MouseButton1={Name='MouseButton1'}
local fetched={}
e.game.HttpGet=function(_,url)
 fetched[#fetched+1]=url
 assert(e.pg:FindFirstChild('PCMovementV31ProbeLoading'),'loading indicator missing during download')
 assert(url:find('feature/pc-movement-v31-macro-probe-mobile-20261102/PCMovementV31MacroConflictProbe.lua?_cb=',1,true)
  or url:find('feature/pc-movement-v31-macro-probe-mobile-20261102/PCMovementV31MacroProbeMobileUI.lua?_cb=',1,true),
     'loader fetched a movement module or an unexpected branch')
 return url:find('ProbeMobileUI.lua',1,true) and 'ui-source' or 'probe-source'
end
loadstring=function(source)
 if source=='probe-source' then return function() return dofile('PCMovementV31MacroConflictProbe.lua') end end
 if source=='ui-source' then return function() return dofile('PCMovementV31MacroProbeMobileUI.lua') end end
 error('unexpected module')
end
dofile('PCMovementV31MacroProbe_AUTOEXECUTE.lua')
local first=e.env.PCMovementV31MacroProbe
assert(first and first.GetState().active and #fetched==2 and
 e.pg:FindFirstChild('PCMovementV31MacroProbeMobileUI') and
 not e.pg:FindFirstChild('PCMovementV31ProbeLoading'),'mobile diagnostic did not finish loading')
dofile('PCMovementV31MacroProbe_AUTOEXECUTE.lua')
local second=e.env.PCMovementV31MacroProbe
assert(first.GetState().active==false and second.GetState().active==true and #fetched==4,
    'reexecution duplicated the old listeners')
second.Stop()
assert(e.env.PCMovementV31MacroProbe==nil and not e.pg:FindFirstChild('PCMovementV31MacroProbeMobileUI'))
print('PASS: startup indicator, mobile UI loader, no joystick/macro fetch, clean reexecution')
