local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

-- V6.1 starts from the last stable bridge implementation, then changes only:
--   1) joystick chord ownership (2D direction + radius zones),
--   2) persistent side-sweep A<->D handoff,
--   3) jump delivery (native mobile Humanoid.Jump instead of synthetic Space).
-- Camera/body/grid/crouch behavior stays outside this bridge.
local source=game:HttpGet(
    ROOT.."PCKeyboardTouchBridgeV5_2.lua?_cb="..HttpService:GenerateGUID(false),
    true
)

local function replaceOncePlain(text,needle,replacement,label)
    local first,last=text:find(needle,1,true)
    if not first then error("V6.1 patch failed: missing "..label) end
    if text:find(needle,last+1,true) then error("V6.1 patch failed: duplicate "..label) end
    return text:sub(1,first-1)..replacement..text:sub(last+1)
end

-- Keep the approved 200 ms landing buffer, but route every pulse like a native
-- mobile jump. Evade therefore does not receive a synthetic PC Space press from
-- the touch jump button, while movement remains on the keyboard-controller path.
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

local oldPulse=[[
local function pulseJump()
    lastJumpPulse=os.clock()
    pendingJumpDeadline=nil
    jumpPulses+=1
    pcall(function()
        VirtualInputManager:SendKeyEvent(true,Enum.KeyCode.Space,false,game)
    end)
    pendingSpaceReleaseToken+=1
    local token=pendingSpaceReleaseToken
    task.delay(SPACE_PULSE_SECONDS,function()
        if token~=pendingSpaceReleaseToken then return end
        pcall(function()
            VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Space,false,game)
        end)
    end)
end
]]
local newPulse=[[
local function pulseJump()
    lastJumpPulse=os.clock()
    pendingJumpDeadline=nil
    jumpPulses+=1

    local character=player.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.Jump=true
    end
end
]]
source=replaceOncePlain(source,oldPulse,newPulse,"native mobile jump pulse")

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

    pulseJump()

    task.spawn(function()
        while enabled and token==jumpBurstToken and os.clock()<deadline do
            RunService.Heartbeat:Wait()
            if not enabled or token~=jumpBurstToken or os.clock()>=deadline then break end
            pulseJump()
        end
    end)
end
]]
source=replaceOncePlain(source,oldRequest,newRequest,"200 ms native jump burst")

-- The previous V5.9/V6 patch declared lateralLatch inside refreshKeys, so it was
-- recreated as nil every frame. That made a real A->D handoff impossible to
-- persist. V6.1 keeps the latch outside refreshKeys and limits it to a narrow
-- horizontal corridor, so intentional W/WA/WD motion releases it immediately.
--
-- Forward ownership is genuinely 2D:
--   * radial dead/near-center area avoids accidental diagonals,
--   * W owns a narrow top cone,
--   * WA/WD own a broad outer-ring cone,
--   * A/D own the side cone.
local oldRefresh=[[
local function refreshKeys(now)
    if not enabled or movementTouch==nil then
        resetAxis(axisX)
        resetAxis(axisZ)
        releaseKeys()
        return
    end
    local x=updateAxis(axisX,latestX,now)
    local z=updateAxis(axisZ,latestZ,now)
    applyKeys({W=z<0,S=z>0,A=x<0,D=x>0})
end
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
local lateralLatch=nil
local lateralLatchCenterDeadline=nil

local function chooseDigitalChord(x,z,now)
    local ax=math.abs(x)
    local az=math.abs(z)
    local radius=math.sqrt(x*x+z*z)
    local horizontalKey=x<0 and "A" or "D"
    local inSideSweepCorridor=az<=SIDE_SWEEP_MAX_ABS_Z

    -- Preserve a lateral keyboard handoff while the thumb crosses the physical
    -- center. A short grace window prevents the joystick deadzone from emitting
    -- neutral/W between A and D, but still lets a deliberate held center become
    -- neutral after 120 ms.
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

    -- Forward half: narrow W, broad outer WA/WD, then pure A/D on the sides.
    if z<0 then
        if ax<=0.0001 then
            return {W=true}
        end

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

        -- Same diagonal angle close to the center remains cardinal until the
        -- thumb reaches the outer diagonal zone.
        if ratio<=1 then
            return {W=true}
        end
        if inSideSweepCorridor then
            lateralLatch=horizontalKey
            lateralLatchCenterDeadline=nil
        end
        return {[horizontalKey]=true}
    end

    -- Backward half keeps the already-tested V5.9 S/SA/SD ownership.
    if ax<=0.0001 then
        return {S=true}
    end

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

local function refreshKeys(now)
    if not enabled or movementTouch==nil then
        lateralLatch=nil
        lateralLatchCenterDeadline=nil
        resetAxis(axisX)
        resetAxis(axisZ)
        releaseKeys()
        return
    end

    applyKeys(chooseDigitalChord(latestX,latestZ,now))
end
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
    pcall(function() VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Space,false,game) end)
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    pcall(function() gui:Destroy() end)
    getgenv().PCKeyboardTouchBridgeV52=nil
    getgenv().__PCKeyboardTouchBridgeV52Cleanup=nil
end
]]
local newCleanup=[[
getgenv().__PCKeyboardTouchBridgeV52Cleanup=function()
    enabled=false
    releaseMovement()
    pendingJumpDeadline=nil
    jumpBurstToken+=1
    pendingSpaceReleaseToken+=1
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    pcall(function() gui:Destroy() end)
    getgenv().PCKeyboardTouchBridgeV52=nil
    getgenv().__PCKeyboardTouchBridgeV52Cleanup=nil
end
]]
source=replaceOncePlain(source,oldCleanup,newCleanup,"cleanup without synthetic Space")

local chunk,loadError=loadstring(source)
if not chunk then error(loadError) end
chunk()

if type(getgenv().PCKeyboardTouchBridgeV52)=="table" then
    getgenv().PCKeyboardTouchBridgeV52.Version="6.1-2d-zones-dry-side-sweep-native-mobile-jump"
end
