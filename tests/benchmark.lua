local Core=dofile("rebuild/Core.lua")
local engine=Core.new({})
local ledger=Core.keys(function() return true end)
local input={active=true,x=-1,z=-1}
local observed={alive=true,grounded=false,horizontalSpeed=55,forwardDot=-0.5}
local start=os.clock()
for i=1,100000 do
    input.x=i%2==0 and -1 or 1
    ledger:apply(engine:step(input,observed,i/60).keys)
end
print(string.format("Offline core benchmark: 100000 state/input updates in %.3f s (desktop host; not iPhone measurement)",os.clock()-start))
