local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

local source=game:HttpGet(
    ROOT.."PCKeyboardTouchBridgeV5_9.lua?_cb="..HttpService:GenerateGUID(false),
    true
)

local function replaceOncePlain(text,needle,replacement,label)
    local first,last=text:find(needle,1,true)
    if not first then error("V5.10 input-order patch failed: missing "..label) end
    if text:find(needle,last+1,true) then error("V5.10 input-order patch failed: duplicate "..label) end
    return text:sub(1,first-1)..replacement..text:sub(last+1)
end

-- V5.9 preserves the V5.2 combined render-step in the generated bridge.
-- Split it so continuous W/A/S/D refresh runs at Input-1 (99), before
-- Roblox ControlModule reads movement at Input (100), while the existing
-- buffered-jump service stays at Input+8 (108). Chord logic, latch, jump
-- timings, camera, CFrame, AutoRotate and movement-controller behavior stay
-- unchanged.
local anchor=[[
source=replaceOncePlain(source,oldCleanup,newCleanup,"cleanup burst cancellation")

local chunk,loadError=loadstring(source)
]]
local replacement=[=[
source=replaceOncePlain(source,oldCleanup,newCleanup,"cleanup burst cancellation")

source=replaceOncePlain(
    source,
    [[RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Input.Value+8,function()
    local now=os.clock()
    refreshKeys(now)
    if pendingJumpDeadline then
        if now>pendingJumpDeadline then
            pendingJumpDeadline=nil
        elseif now-lastJumpPulse>=JUMP_MIN_INTERVAL then
            pulseJump()
        end
    end
end)]],
    [[local JUMP_BIND_NAME=BIND_NAME.."__Jump"
pcall(function() RunService:UnbindFromRenderStep(JUMP_BIND_NAME) end)

RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Input.Value-1,function()
    refreshKeys(os.clock())
end)

RunService:BindToRenderStep(JUMP_BIND_NAME,Enum.RenderPriority.Input.Value+8,function()
    local now=os.clock()
    if pendingJumpDeadline then
        if now>pendingJumpDeadline then
            pendingJumpDeadline=nil
        elseif now-lastJumpPulse>=JUMP_MIN_INTERVAL then
            pulseJump()
        end
    end
end)]],
    "split movement refresh and jump buffer render priorities"
)

source=replaceOncePlain(
    source,
    "pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)\n    pcall(function() VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Space,false,game) end)",
    "pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)\n    pcall(function() RunService:UnbindFromRenderStep(JUMP_BIND_NAME) end)\n    pcall(function() VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Space,false,game) end)",
    "cleanup jump-buffer render bind"
)

local chunk,loadError=loadstring(source)
]=]
source=replaceOncePlain(source,anchor,replacement,"V5.9 compile anchor")

local chunk,loadError=loadstring(source)
if not chunk then error(loadError) end
chunk()

if type(getgenv().PCKeyboardTouchBridgeV52)=="table" then
    getgenv().PCKeyboardTouchBridgeV52.Version="5.10-pre-controlmodule-ad-order-jump-buffer-input+8"
end
