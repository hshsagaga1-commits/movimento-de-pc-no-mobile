local F=dofile('tests/v31-preserved/RobloxFixture.lua')
local E=dofile('tests/v31-preserved/Environment.lua')
local e=E.new(F)
game=e.game;workspace=e.world;getgenv=function() return e.env end
os={clock=function() return e.time end}
warn=function() end
local ids,n={},0
local pcLoads,pcStops,gridStops=0,0,0
local pauseLight,pausePC,pauseOriginal=false,false,false
local function source(fn) n=n+1;ids[tostring(n)]=fn;return tostring(n) end
loadstring=function(value) return assert(ids[value]) end
task={spawn=function(fn) e.watcher=fn end,wait=function(seconds)
 e.time+=seconds or 0;return coroutine.yield('wait')
end}
e.game.HttpGet=function(_,url)
 if url:find('PCModeLockV3.lua',1,true) then
  return source(function()
   pcLoads+=1
   if pausePC then coroutine.yield('pc-paused') end
   e.env.__PCModeLockCleanup=function() pcStops+=1 end
  end)
 elseif url:find('LegacyGridContactAssistV31Preserved.lua',1,true) then
  return source(function()
   if pauseLight then coroutine.yield('light-paused') end
   local api={GetState=function() return {} end}
   e.env.LegacyGridContactAssistV1=api
   e.env.__LegacyGridContactAssistV1Cleanup=function()
    gridStops+=1
    if e.env.LegacyGridContactAssistV1==api then e.env.LegacyGridContactAssistV1=nil end
   end
  end)
 elseif url:find('LegacyGridContactAssistV31.lua',1,true) then
  return source(function()
   if pauseOriginal then coroutine.yield('original-paused') end
   e.env.LegacyGridContactAssistV1={GetState=function() return {} end}
   -- The real original has a mismatched cleanup version guard and leaves its API.
   e.env.__LegacyGridContactAssistV1Cleanup=function() gridStops+=1 end
  end)
 end
 error('unexpected URL '..url)
end
local function resume(thread,...)
 local ok,value=coroutine.resume(thread,...);assert(ok,value);return value
end
local api=dofile('CombinedJoystickAssistV31PreservedLoader.lua')
pauseLight=true
local switchResult
local switching=coroutine.create(function() switchResult=api.SetAssistMode('light') end)
assert(resume(switching)=='light-paused')
api.Stop()
resume(switching)
assert(switchResult==false,'a stopped owner reported successful Assist install')
assert(e.env.LegacyGridContactAssistV1==nil,'a yielded Assist resurrected after Stop')
assert(e.env.PCMovementAssistV31Preserved==nil)
pauseLight=false
local originalApi=dofile('CombinedJoystickAssistV31PreservedLoader.lua')
pauseOriginal=true
local originalResult
local originalSwitch=coroutine.create(function() originalResult=originalApi.SetAssistMode('original') end)
assert(resume(originalSwitch)=='original-paused')
originalApi.Stop();resume(originalSwitch)
assert(originalResult==false and e.env.LegacyGridContactAssistV1==nil,'cancelled original Assist left its stale API')
pauseOriginal=false
local repairingApi=dofile('CombinedJoystickAssistV31PreservedLoader.lua')
local watcher=coroutine.create(e.watcher)
pausePC=true
local event
for i=1,6 do
 event=resume(watcher)
 if event=='pc-paused' then break end
end
assert(event=='pc-paused','test did not reach an in-flight original PC repair')
local before=pcLoads
pausePC=false
local replacement
local replacing=coroutine.create(function() replacement=dofile('CombinedJoystickAssistV31PreservedLoader.lua') end)
assert(resume(replacing)=='wait','replacement must await cleanup of the older yielded PC bootstrap')
assert(pcLoads==before,'replacement bootstrapped PC concurrently with cancelled repair')
resume(watcher) -- finishes the cancelled bootstrap and discards its installation
resume(replacing)
assert(coroutine.status(replacing)=='dead')
assert(replacement==e.env.PCMovementAssistV31Preserved)
assert(pcLoads==before+1)
if coroutine.status(watcher)~='dead' then resume(watcher) end
assert(replacement==e.env.PCMovementAssistV31Preserved,'old watcher touched its replacement')
replacement.Stop()
assert(e.env.LegacyGridContactAssistV1==nil)
assert(e.env.__PCMovementV31PreservedInstall==nil)
print('PASS: yielded Assist cancellation and serialized PC repair/reexecution cannot resurrect old owners')
