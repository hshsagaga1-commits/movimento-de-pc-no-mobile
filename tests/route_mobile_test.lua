local Route=dofile("rebuild/KeyboardRoute.lua")
local rawIndex=function(object,key) return object.values[key] end
local currentIndex=rawIndex
game={}
hookmetamethod=function(_,kind,replacement)
    assert(kind=="__index")
    local previous=currentIndex;currentIndex=replacement;return previous
end
getrawmetatable=function() return {__index=currentIndex} end
checkcaller=function() return true end -- executor identity remains during activation
newcclosure=function(fn) return fn end
local uis=setmetatable({values={KeyboardEnabled=false,TouchEnabled=true}},
    {__index=function(object,key) return currentIndex(object,key) end})
local touch,keyboard={},{}
local active={enabled=false}
function active:Enable(value)
    if value and not uis.KeyboardEnabled then return false end
    self.enabled=value;return true
end
local controls={activeControlModule=touch,activeController={enabled=true}}
function controls:SwitchToController(module)
    self.activeControlModule=module
    self.activeController=module==keyboard and active or {enabled=true}
    if module==keyboard then active:Enable(true) end
end
local route=Route.new({Controls=controls,KeyboardModule=keyboard,TouchModules={touch},UserInputService=uis},{})
route:Start()
assert(route:IsReady(),"iOS activation did not observe transient keyboard capability")
assert(uis.KeyboardEnabled==false and uis.TouchEnabled==true,"facade leaked outside activation")
local owned=currentIndex
local later=function(object,key) return owned(object,key) end
hookmetamethod(game,"__index",later)
route:Stop()
assert(currentIndex==later,"Stop overwrote another component's newer hook")
assert(uis.KeyboardEnabled==false,"stopped wrapper invalidated its predecessor chain")
print("PASS: mobile capability activation, facade scope and later hook ownership")
