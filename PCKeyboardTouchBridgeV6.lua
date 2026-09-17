local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

-- V6.2 keeps the proven V5.9 Space jump path and changes only joystick mapping.
local source=game:HttpGet(
    ROOT.."PCKeyboardTouchBridgeV5_2.lua?_cb="..HttpService:GenerateGUID(false),
    true
)

local function replaceOncePlain(text,needle,replacement,label)
    local first,last=text:find(needle,1,true)
    if not first then error("V6.2 patch failed: missing "..label) end
    if text:find(needle,last+1,true) then error("V6.2 patch failed: duplicate "..label) end
    return text:sub(1,first-1)..replacement..text:sub(last+1)
end

-- Preserve the known-working 200 ms Space burst from V5.9.
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

-- Persistent state has to live outside refreshKeys or A<->D resets every frame.
source=replaceOncePlain(
    source,
    "local function refreshKeys(now)\n",
    "local lateralLatch=nil\nlocal lateralLatchCenterDeadline=nil\n\nlocal function refreshKeys(now)\n",
    "persistent side-sweep state"
)

local oldRefresh=[[
    local x=updateAxis(axisX,latestX,now)
    local z=updateAxis(axisZ,latestZ,now)
    applyKeys({W=z<0,S=z>0,A=x<0,D=x>0})
]]
local newRefresh=[[
    local FORWARD_W_MAX_RATIO=0.34
    local FORWARD_DIAGONAL_MAX_RATIO=2.20
    local FORWARD_DIAGONAL_MIN_RADIUS=0.55
    local BACK_DIAGONAL_MIN_RATIO=0.65
    local BACK_DIAGONAL_MAX_RATIO=1.54
    local SIDE_SWEEP_MAX_ABS_Z=0.24
    local SIDE_SWAP_X=0.06
    local SIDE_SWEEP_CENTER_GRACE=0.12

    local function chooseDigitalChord(x,z)
        local ax=math.abs(x)
        local az=math.abs(z)
        local radius=math.sqrt(x*x+z*z)
        local horizontalKey=x<0 and "A" or "D"
        local inSideSweepCorridor=az<=SIDE_SWEEP_MAX_ABS_Z

        if lateralLatch then
            if not inSideSweepCorridor then
                lateralLatch=nil
                lateralLatchCenterDeadline=nil
            else
                if lateralLatch=="A" and x>=SIDE_SWAP_X then
                    lateralLatch="D"
                    lateralLatchCenterDeadline=nil
                    return {D=true}
                elseif lateralLatch=="D" and x<=-SIDE_SWAP_X then
                    lateralLatch="A"
                    lateralLatchCenterDeadline=nil
                    return {A=true}
                end

                if radius>=PRESS_THRESHOLD then
                    lateralLatchCenterDeadline=nil
                    return {[lateralLatch]=true}
                end

                if lateralLatchCenterDeadline==nil then
                    lateralLatchCenterDeadline=now+SIDE_SWEEP_CENTER_GRACE
                end
                if now<=lateralLatchCenterDeadline then
                    return {[lateralLatch]=true}
                end

                lateralLatch=nil
                lateralLatchCenterDeadline=nil
            end
        end

        if radius<PRESS_THRESHOLD then
            return {}
        end

        if az<=0.0001 then
            lateralLatch=horizontalKey
            lateralLatchCenterDeadline=nil
            return {[horizontalKey]=true}
        end

        -- Forward: small W zone, broad outer WA/WD zone, pure A/D on the sides.
        if z<0 then
            if ax<=0.0001 then return {W=true} end
            local ratio=ax/az

            if ratio<=FORWARD_W_MAX_RATIO then
                return {W=true}
            end

            if radius>=FORWARD_DIAGONAL_MIN_RADIUS and ratio<=FORWARD_DIAGONAL_MAX_RATIO then
                return {W=true,[horizontalKey]=true}
            end

            if ratio>FORWARD_DIAGONAL_MAX_RATIO then
                if inSideSweepCorridor then
                    lateralLatch=horizontalKey
                    lateralLatchCenterDeadline=nil
                end
                return {[horizontalKey]=true}
            end

            if ratio<=1 then return {W=true} end
            if inSideSweepCorridor then
                lateralLatch=horizontalKey
                lateralLatchCenterDeadline=nil
            end
            return {[horizontalKey]=true}
        end

        -- Backward keeps the already-tested V5.9 S/SA/SD split.
        if ax<=0.0001 then return {S=true} end
        local ratio=ax/az

        if ratio<BACK_DIAGONAL_MIN_RATIO then
            return {S=true}
        elseif ratio>BACK_DIAGONAL_MAX_RATIO then
            if inSideSweepCorridor then
                lateralLatch=horizontalKey
                lateralLatchCenterDeadline=nil
            end
            return {[horizontalKey]=true}
        end

        return {S=true,[horizontalKey]=true}
    end

    applyKeys(chooseDigitalChord(latestX,latestZ))
]]
source=replaceOncePlain(source,oldRefresh,newRefresh,"2D joystick zones")

local oldRelease=[[
local function releaseMovement()
    movementTouch=nil
    movementCenter=nil
    latestX=0
    latestZ=0
    resetAxis(axisX)
    resetAxis(axisZ)
    releaseKeys()
    knob.Position=UDim2.fromScale(0.5,0.5)
end
]]
local newRelease=[[
local function releaseMovement()
    movementTouch=nil
    movementCenter=nil
    latestX=0
    latestZ=0
    lateralLatch=nil
    lateralLatchCenterDeadline=nil
    resetAxis(axisX)
    resetAxis(axisZ)
    releaseKeys()
    knob.Position=UDim2.fromScale(0.5,0.5)
end
]]
source=replaceOncePlain(source,oldRelease,newRelease,"side latch release")

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
    getgenv().PCKeyboardTouchBridgeV52.Version="6.2-2d-zones-dry-side-sweep-space-jump"
end
