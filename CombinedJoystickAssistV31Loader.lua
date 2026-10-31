-- PC MOVEMENT + ASSIST V3.1 / Evade iOS
-- Keyboard: original V6 A <-> D staged sweeps are NOT modified.
-- Original V3 PC keys/joystick/visuals remain UNCHANGED.
-- Only grid adhesion and light impact-bounce module are upgraded.
-- To stop V3.1: getgenv().PCMovementAssistV31.Stop()

local HttpService=game:GetService("HttpService")
local Players=game:GetService("Players")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-movement-assist-v31-contact-hop/"
local env=getgenv()
local EVADE_GAME_ID=3647333358
local OVERLAY_NAME="PCKeyboardTouchBridgeV52Overlay"

-- Stop the previous V3.1, V3, V2 watchers and their installed modules.
local oldV31=env.PCMovementAssistV31
if type(oldV31)=="table" and type(oldV31.Stop)=="function" then
    pcall(oldV31.Stop)
end
local oldV3=env.PCMovementAssistV3
if type(oldV3)=="table" and type(oldV3.Stop)=="function" then
    pcall(oldV3.Stop)
end
local oldV2=env.PCMovementAssistV2
if type(oldV2)=="table" and type(oldV2.Stop)=="function" then
    pcall(oldV2.Stop)
end
env.__PCMovementAssistV2Token=nil
env.__PCMovementAssistV3Token=nil
env.__PCMovementAssistV31Token=nil

local function runModule(file)
    local url=ROOT..file.."?_cb="..HttpService:GenerateGUID(false)
    local source=game:HttpGet(url,true)
    local chunk,err=loadstring(source)
    if not chunk then
        error("[PC Movement V3.1] "..file..": "..tostring(err))
    end
    return chunk()
end

local ok,err=pcall(function()
    runModule("PCModeLockV3.lua")
    runModule("LegacyGridContactAssistV31.lua")
end)
if not ok then
    warn("[PC Movement V3.1] Failed to start: "..tostring(err))
    error(err)
end

local token={}
env.__PCMovementAssistV31Token=token

local function stop()
    if env.__PCMovementAssistV31Token~=token then return end
    env.__PCMovementAssistV31Token=nil
    local gridCleanup=env.__LegacyGridContactAssistV1Cleanup
    if type(gridCleanup)=="function" then pcall(gridCleanup) end
    local pcCleanup=env.__PCModeLockCleanup
    if type(pcCleanup)=="function" then pcall(pcCleanup) end
    if env.PCMovementAssistV31 and env.PCMovementAssistV31.Version=="3.1-strong-grid-contact-air-hop" then
        env.PCMovementAssistV31=nil
    end
end

env.PCMovementAssistV31={
    Version="3.1-strong-grid-contact-air-hop",
    Stop=stop,
    GetState=function()
        local bridge=env.PCKeyboardTouchBridgeV52
        local assist=env.LegacyGridContactAssistV1
        local bridgeState=nil
        local assistState=nil
        if type(bridge)=="table" and type(bridge.GetState)=="function" then
            local good,value=pcall(bridge.GetState)
            if good then bridgeState=value end
        end
        if type(assist)=="table" and type(assist.GetState)=="function" then
            local good,value=pcall(assist.GetState)
            if good then assistState=value end
        end
        return {version="3.1",bridge=bridgeState,assist=assistState}
    end
}

-- Recreate only our own Bloxtrap-like movement overlay after map/round resets.
-- The grid module stays alive; the user's separate Evade Legacy scripts are never run.
local playerGui=Players.LocalPlayer:WaitForChild("PlayerGui")
local missingSince=nil
local lastRepairAt=-math.huge
local repairing=false

task.spawn(function()
    while env.__PCMovementAssistV31Token==token do
        task.wait(0.75)
        if env.__PCMovementAssistV31Token~=token then break end

        if game.GameId==EVADE_GAME_ID and not repairing then
            local overlay=playerGui:FindFirstChild(OVERLAY_NAME)
            local stick=overlay and overlay:FindFirstChild("PCJoystick",true)
            local knob=stick and stick:FindFirstChild("Knob")
            local jump=overlay and overlay:FindFirstChild("PCJump",true)
            local ready=overlay and overlay:IsA("ScreenGui") and stick and knob and jump
            if ready then
                missingSince=nil
            else
                missingSince=missingSince or os.clock()
                if os.clock()-missingSince>=1.25 and os.clock()-lastRepairAt>=3.0 then
                    repairing=true
                    lastRepairAt=os.clock()
                    local repaired,message=pcall(function()
                        runModule("PCModeLockV3.lua")
                    end)
                    if not repaired then
                        warn("[PC Movement V3.1] Overlay repair: "..tostring(message))
                    end
                    task.wait(0.25)
                    repairing=false
                    missingSince=nil
                end
            end
        else
            missingSince=nil
        end
    end
end)
print("[PC Movement + Assist V3.1] Original V3 joystick and keys kept; rail adhesion + contact hop active.")
