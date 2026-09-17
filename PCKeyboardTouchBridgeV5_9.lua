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

-- One tap = immediate jump attempt, then a fresh Space up/down transition on
-- every Heartbeat for 200 ms. This acts as a short jump buffer: as soon as the
-- game allows jumping after landing, the next frame already carries a new
-- Space-down event instead of waiting for a coarse retry interval.
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
local JUMP_BURST_SECONDS=0.200
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

    local function burstPulse()
        if not enabled or token~=jumpBurstToken then return end
        lastJumpPulse=os.clock()
        pendingJumpDeadline=nil
        jumpPulses+=1
        pcall(function()
            VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Space,false,game)
            VirtualInputManager:SendKeyEvent(true,Enum.KeyCode.Space,false,game)
        end)
    end

    burstPulse()

    task.spawn(function()
        while enabled and token==jumpBurstToken and os.clock()<deadline do
            RunService.Heartbeat:Wait()
            if not enabled or token~=jumpBurstToken or os.clock()>=deadline then break end
            burstPulse()
        end

        if token==jumpBurstToken then
            pcall(function()
                VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Space,false,game)
            end)
        end
    end)
end
]]
source=replaceOncePlain(source,oldRequest,newRequest,"requestJump frame-buffer behavior")

-- PC-style digital sectors. The joystick position only chooses a keyboard chord;
-- once a sector is selected, A/D/W/S are full digital key presses, not analog force.
-- Diagonal sectors are intentionally narrow so W, A and D dominate most of the ring.
local oldRefresh=[[
    local x=updateAxis(axisX,latestX,now)
    local z=updateAxis(axisZ,latestZ,now)
    applyKeys({W=z<0,S=z>0,A=x<0,D=x>0})
]]
local newRefresh=[[
    local DIGITAL_DIAGONAL_MIN_RATIO=0.82
    local DIGITAL_DIAGONAL_MAX_RATIO=1.22

    local function chooseDigitalChord(x,z)
        local ax=math.abs(x)
        local az=math.abs(z)
        local strongest=math.max(ax,az)

        if strongest<PRESS_THRESHOLD then
            resetAxis(axisX)
            resetAxis(axisZ)
            return {}
        end

        local verticalKey=z<0 and "W" or "S"
        local horizontalKey=x<0 and "A" or "D"

        if az<=0.0001 then
            return {[horizontalKey]=true}
        end

        if ax<=0.0001 then
            return {[verticalKey]=true}
        end

        local lateralToVertical=ax/az

        if lateralToVertical<DIGITAL_DIAGONAL_MIN_RATIO then
            return {[verticalKey]=true}
        elseif lateralToVertical>DIGITAL_DIAGONAL_MAX_RATIO then
            return {[horizontalKey]=true}
        end

        return {[verticalKey]=true,[horizontalKey]=true}
    end

    applyKeys(chooseDigitalChord(latestX,latestZ))
]]
source=replaceOncePlain(source,oldRefresh,newRefresh,"refreshKeys digital sector mapping")

local oldCleanup=[[
getgenv().__PCKeyboardTouchBridgeV52Cleanup=function()
    enabled=false
    releaseMovement()
    pendingJumpDeadline=nil
    pendingSpaceReleaseToken+=1
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
]]
local newCleanup=[[
getgenv().__PCKeyboardTouchBridgeV52Cleanup=function()
    enabled=false
    releaseMovement()
    pendingJumpDeadline=nil
    jumpBurstToken+=1
    pendingSpaceReleaseToken+=1
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
]]
source=replaceOncePlain(source,oldCleanup,newCleanup,"cleanup burst cancellation")

local chunk,loadError=loadstring(source)
if not chunk then error(loadError) end
chunk()

if type(getgenv().PCKeyboardTouchBridgeV52)=="table" then
    getgenv().PCKeyboardTouchBridgeV52.Version="5.9-zero-delay-200ms-frame-buffer-digital-sectors-narrow-diagonals"
end
