local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

local source=game:HttpGet(
    ROOT.."PCKeyboardTouchBridgeV5_2.lua?_cb="..HttpService:GenerateGUID(false),
    true
)

local function replaceOncePlain(text,needle,replacement,label)
    local first,last=text:find(needle,1,true)
    if not first then
        error("V5.9 patch failed: missing "..label)
    end
    if text:find(needle,last+1,true) then
        error("V5.9 patch failed: duplicate "..label)
    end
    return text:sub(1,first-1)..replacement..text:sub(last+1)
end

-- Temporary diagnostic hold: Space-down is still immediate (0 ms added delay),
-- but Space stays down for 2000 ms so it is obvious whether this wrapper loaded.
source=replaceOncePlain(
    source,
    "local SPACE_PULSE_SECONDS=0.055",
    "local SPACE_PULSE_SECONDS=2.000",
    "55 ms Space pulse constant"
)

-- W-biased forward sector. The V5.2 bridge treats X and Z independently, so
-- a small sideways finger drift can accidentally add A/D while pushing forward.
-- When forward input clearly dominates, suppress that small lateral component;
-- intentional diagonals still pass once lateral input is > 60% of forward input.
local oldRefresh=[[
    local x=updateAxis(axisX,latestX,now)
    local z=updateAxis(axisZ,latestZ,now)
    applyKeys({W=z<0,S=z>0,A=x<0,D=x>0})
]]

local newRefresh=[[
    local z=updateAxis(axisZ,latestZ,now)
    local forwardStrength=math.max(0,-latestZ)
    local lateralStrength=math.abs(latestX)
    local preferPureW=(z<0 and forwardStrength>=PRESS_THRESHOLD and lateralStrength<=forwardStrength*0.60)
    local x
    if preferPureW then
        resetAxis(axisX)
        x=0
    else
        x=updateAxis(axisX,latestX,now)
    end
    applyKeys({W=z<0,S=z>0,A=x<0,D=x>0})
]]

source=replaceOncePlain(source,oldRefresh,newRefresh,"refreshKeys forward mapping")

local chunk,loadError=loadstring(source)
if not chunk then error(loadError) end
chunk()

if type(getgenv().PCKeyboardTouchBridgeV52)=="table" then
    getgenv().PCKeyboardTouchBridgeV52.Version="5.9-test-zero-delay-2000ms-space-hold-forward-W-bias"
end
