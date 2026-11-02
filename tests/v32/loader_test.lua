local F=dofile('tests/v31-preserved/RobloxFixture.lua')
local E=dofile('tests/v31-preserved/Environment.lua')
local e=E.new(F)
game=e.game;workspace=e.world;getgenv=function() return e.env end
os={clock=function() return e.time end};warn=function() end
Enum.RenderPriority.Last={Value=2000}
local uis=Instance.new('UserInputService');uis.MouseIconEnabled=true
uis.MouseEnabled=true;uis.TouchEnabled=true;e.services.UserInputService=uis
local pcLoads,pcStops,lightLoads,cursorLoads=0,0,0,0
local ids,n={},0
local function source(fn) n+=1;ids[tostring(n)]=fn;return tostring(n) end
loadstring=function(value) return assert(ids[value]) end
task={spawn=function(fn) e.watcher=fn end,wait=function() end}
local UIROOT='https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-movement-v32-v31-preserved-20261102/'
local VISUALROOT='https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-movement-v31-ui-fixes-20261102/'
local ORIGINAL='https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/ce4eb8b6deb47e0690301bd38f1b78eb0e19dcaa/'
e.game.HttpGet=function(_,url)
 assert(url:find('?_cb=',1,true),'missing cache buster')
 if url:find('CombinedJoystickAssistV32Loader.lua',1,true) then
  assert(url:sub(1,#UIROOT)==UIROOT)
  return source(function() return dofile('CombinedJoystickAssistV32Loader.lua') end)
 elseif url:find('PCModeLockV3.lua',1,true) then
  assert(url:sub(1,#VISUALROOT)==VISUALROOT,'PC bootstrap no longer uses working V3.1 visuals')
  return source(function() pcLoads+=1;e.env.__PCModeLockCleanup=function() pcStops+=1 end end)
 elseif url:find('PCCursorVisualV31.lua',1,true) then
  assert(url:sub(1,#VISUALROOT)==VISUALROOT,'cursor module no longer uses working V3.1')
  cursorLoads+=1
  return source(function()
   if e.failCursor then error('injected cursor-only failure') end
   return dofile('PCCursorVisualV31.lua')
  end)
 elseif url:find('LegacyGridContactAssistV32.lua',1,true) then
  return source(function()
   assert(url:sub(1,#UIROOT)==UIROOT,'V3.2 Assist not fetched from isolated branch')
   lightLoads+=1
   if e.failV32 then error('injected V3.2 Assist failure') end
   e.env.LegacyGridContactAssistV1={GetState=function() return {} end}
   e.env.__LegacyGridContactAssistV1Cleanup=function() e.env.LegacyGridContactAssistV1=nil end
  end)
 elseif url:find('LegacyGridContactAssistV31Preserved.lua',1,true) then
  assert(url:sub(1,#VISUALROOT)==VISUALROOT,'fallback did not use working V3.1 light Assist')
  return source(function()
   e.env.LegacyGridContactAssistV1={GetState=function() return {fallback=true} end}
   e.env.__LegacyGridContactAssistV1Cleanup=function() e.env.LegacyGridContactAssistV1=nil end
  end)
 elseif url:find('LegacyGridContactAssistV31.lua',1,true) then
  assert(url:sub(1,#ORIGINAL)==ORIGINAL)
  return source(function()
   e.env.LegacyGridContactAssistV1={GetState=function() return {} end}
   e.env.__LegacyGridContactAssistV1Cleanup=function() e.env.LegacyGridContactAssistV1=nil end
  end)
 end
 error('unexpected URL '..url)
end
dofile('PC_Movement_V32_AUTOEXECUTE.lua')
local api=e.env.PCMovementAssistV31Preserved
assert(api and pcLoads==1 and cursorLoads==1 and lightLoads==1)
assert(uis.MouseIconEnabled==false)
api.SetCursorHidden(false);assert(uis.MouseIconEnabled==true)
api.SetCursorHidden(true);assert(uis.MouseIconEnabled==false)
assert(api.SetAssistMode('original')==true)
assert(pcLoads==1 and pcStops==0 and cursorLoads==1,'Assist switch reinstalled PC or cursor')
api.Stop()
assert(pcStops==1 and uis.MouseIconEnabled==true and next(e.bound)==nil)
dofile('PC_Movement_V32_AUTOEXECUTE.lua')
local replacement=e.env.PCMovementAssistV31Preserved
assert(api.SetCursorHidden(false)==false and uis.MouseIconEnabled==false,'stopped API changed its replacement cursor')
replacement.Stop()
e.failCursor=true
dofile('PC_Movement_V32_AUTOEXECUTE.lua')
local stillWorking=e.env.PCMovementAssistV31Preserved
assert(stillWorking and pcLoads==3,'cursor-only failure broke the working PC stack')
assert(e.env.PCCursorVisualV31==nil)
stillWorking.Stop()
e.failCursor=false;e.failV32=true
dofile('PC_Movement_V32_AUTOEXECUTE.lua')
local fallback=e.env.PCMovementAssistV31Preserved
assert(fallback and fallback.GetState().assistMode=='v31' and
 fallback.GetState().assist.fallback==true,'V3.2 failure loaded the heavy original Assist instead of working V3.1 light')
fallback.Stop()
print('PASS: visual-only bootstrap routing, cursor lifecycle, unchanged Assist switching, cursor failure keeps PC controls')
