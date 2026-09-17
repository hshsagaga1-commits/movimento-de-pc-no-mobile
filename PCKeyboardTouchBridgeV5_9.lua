local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

local source=game:HttpGet(
    ROOT.."PCKeyboardTouchBridgeV5_2.lua?_cb="..HttpService:GenerateGUID(false),
    true
)

local function replaceOncePlain(text,needle,replacement,label)
    local first,last=text:find(needle,1,true)
    if not first then error("V5.9 patch failed: missing "..label) end
    if text:find(needle,last+1,true) then error("V5.9 patch failed: duplicate "..label) end
    return text:sub(1,first-1)..replacement..text:sub(last+1)
end

-- Keep the proven short Space pulse. A tap now starts a 2 second repeat burst:
-- first pulse is immediate, then fresh down/up pulses repeat every 110 ms.
local oldJumpState=[[
local lastJumpPulse=-math.huge
local pendingJumpDeadline=nil
local pendingSpaceReleaseToken=0
local movementCaptures=0
]]
local newJumpState=[[
local lastJumpPulse=-math.huge
local pendingJumpDeadline=nil
local pendingSpaceReleaseToken=0
local jumpBurstToken=0
local JUMP_BURST_SECONDS=2.000
local JUMP_BURST_INTERVAL=0.110
local movementCaptures=0
]]
source=replaceOncePlain(source,oldJumpState,newJumpState,"jump burst state")

local oldRequest=[[
local function requestJump()
    if not enabled then return end
    jumpRequests+=1
    local now=os.clock()
    if now-lastJumpPulse>=JUMP_MIN_INTERVAL then
        pulseJump()
    else
        pendingJumpDeadline=now+JUMP_BUFFER_SECONDS
        bufferedJumpCount+=1
    end
end
]]
local newRequest=[[
local function requestJump()
    if not enabled then return end
    jumpRequests+=1
    jumpBurstToken+=1
    local token=jumpBurstToken
    local deadline=os.clock()+JUMP_BURST_SECONDS

    -- 0 ms response: first jump pulse happens immediately on touch.
    pulseJump()

    task.spawn(function()
        while enabled and token==jumpBurstToken and os.clock()<deadline do
            task.wait(JUMP_BURST_INTERVAL)
            if not enabled or token~=jumpBurstToken or os.clock()>=deadline then break end
            pulseJump()
        end
    end)
end
]]
source=replaceOncePlain(source,oldRequest,newRequest,"requestJump burst behavior")

-- W-biased forward sector. Small sideways finger drift no longer adds A/D while
-- forward clearly dominates; intentional diagonals still pass at >60% lateral.
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

local oldCleanupLine=[[
    pendingSpaceReleaseToken+=1
]]
local newCleanupLine=[[
    jumpBurstToken+=1
    pendingSpaceReleaseToken+=1
]]
source=replaceOncePlain(source,oldCleanupLine,newCleanupLine,"cleanup burst cancellation")

local chunk,loadError=loadstring(source)
if not chunk then error(loadError) end
chunk()

if type(getgenv().PCKeyboardTouchBridgeV52)=="table" then
    getgenv().PCKeyboardTouchBridgeV52.Version="5.9-zero-delay-2s-repeat-burst-forward-W-bias"
end
