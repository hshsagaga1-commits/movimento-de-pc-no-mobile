local F=dofile('tests/v31-preserved/RobloxFixture.lua')
local E=dofile('tests/v31-preserved/Environment.lua')
local e=E.new(F)
game=e.game;workspace=e.world;getgenv=function() return e.env end
os={clock=function() return e.time end}
local pcLoads,originalLoads,lightLoads,pcStops=0,0,0,0
local ids={};local n=0
local function source(fn) n=n+1;ids[tostring(n)]=fn;return tostring(n) end
local originalRoot='https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/ce4eb8b6deb47e0690301bd38f1b78eb0e19dcaa/'
e.game.HttpGet=function(_,url,cache)
 assert(url:find('?_cb=',1,true),'module fetch did not bypass cache')
 if url:find('CombinedJoystickAssistV31PreservedLoader.lua',1,true) then
  assert(url:find('/feature/pc%-movement%-v31%-preserved%-20261101/'))
  return source(function() return dofile('CombinedJoystickAssistV31PreservedLoader.lua') end)
 elseif url:find('PCModeLockV3.lua',1,true) then
  assert(url:sub(1,#originalRoot)==originalRoot,'PC bootstrap was not the original V3.1 snapshot')
  return source(function()
   pcLoads=pcLoads+1
   e.env.__PCModeLockCleanup=function() pcStops=pcStops+1 end
  end)
 elseif url:find('LegacyGridContactAssistV31Preserved.lua',1,true) then
  return source(function()
   lightLoads=lightLoads+1
   if e.failLight then error('injected light module failure') end
   e.env.__LegacyGridContactAssistV1Cleanup=function() e.env.LegacyGridContactAssistV1=nil end
   e.env.LegacyGridContactAssistV1={SetDiagnostics=function() return true end,GetState=function() return {} end}
  end)
 elseif url:find('LegacyGridContactAssistV31.lua',1,true) then
  assert(url:sub(1,#originalRoot)==originalRoot)
  return source(function()
   originalLoads=originalLoads+1
   e.env.__LegacyGridContactAssistV1Cleanup=function() e.env.LegacyGridContactAssistV1=nil end
  end)
 end
 error('unexpected module '..url)
end
loadstring=function(text) return assert(ids[text],text) end
task={spawn=function(fn) e.watcher=fn end,wait=function() end}
warn=function() end
local stoppedRebuild=false
e.env.PCMovementRebuild={Stop=function() stoppedRebuild=true end}
dofile('PC_Movement_V31_Preserved_AUTOEXECUTE.lua')
local api=e.env.PCMovementAssistV31Preserved
assert(stoppedRebuild and pcLoads==1 and lightLoads==1)
assert(e.env.PCMovementAssistV31==api,'old V3.1 API must still address the new loader owner')
assert(api.SetAssistMode('original')==true)
assert(originalLoads==1 and pcLoads==1 and pcStops==0,'Assist rollback reinstalled or stopped PC/UI')
assert(api.SetAssistMode('light')==true and lightLoads==2)
e.failLight=true
assert(api.SetAssistMode('light')==false)
assert(originalLoads==2 and pcLoads==1,'failed light update did not restore original assist alone')
api.Stop()
assert(pcStops==1 and e.env.PCMovementAssistV31Preserved==nil)
assert(e.env.PCMovementAssistV31==nil and e.env.LegacyGridContactAssistV1==nil,'Stop left stale original globals')
print('PASS: preserved loader starts original PC path, replaces only assist, bypasses cache and rolls back without touching UI')
