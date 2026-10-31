-- PC MOVEMENT + ASSIST V2 (Evade / iOS)
-- Standalone loader. Keeps the original V6 files untouched.
-- Stop: getgenv().PCMovementAssistV2.Stop()

local HttpService=game:GetService("HttpService")
local Players=game:GetService("Players")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-movement-assist-v2-20261031/"
local EVADE_GAME_ID=3647333358
local OVERLAY_NAME="PCKeyboardTouchBridgeV52Overlay"
local env=getgenv()

-- Cancel previous V2 UI-repair watcher before recreating it.
env.__PCMovementAssistV2Token=nil

local function runModule(name)
    local url=ROOT..name.."?_cb="..HttpService:GenerateGUID(false)
    local source=game:HttpGet(url,true)
    local chunk,err=loadstring(source)
    if not chunk then error("[PC Assist V2] "..name.." compile error: "..tostring(err)) end
    return chunk()
end

-- Order matters: keyboard chord state first, grid-contact assistance second.
local loaded,loadError=pcall(function()
    runModule("PCModeLockV2.lua")
    runModule("LegacyGridContactAssistV2.lua")
end)
if not loaded then
    warn("[PC Assist V2] Load failed: "..tostring(loadError))
    error(loadError)
end

local token={}
env.__PCMovementAssistV2Token=token

local function stop()
    if env.__PCMovementAssistV2Token~=token then return end
    env.__PCMovementAssistV2Token=nil
    local assistCleanup=env.__LegacyGridContactAssistV1Cleanup
    if type(assistCleanup)=="function" then pcall(assistCleanup) end
    local movementCleanup=env.__PCModeLockCleanup
    if type(movementCleanup)=="function" then pcall(movementCleanup) end
    env.PCMovementAssistV2=nil
end

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local missingSince=nil
local lastRepairAt=-math.huge
local repairing=false

env.PCMovementAssistV2={
    Version="2.0-motion-refinement-20261031",
    Stop=stop,
    GetState=function()
        local bridge=env.PCKeyboardTouchBridgeV52
        local assist=env.LegacyGridContactAssistV1
        local bridgeState=type(bridge)=="table" and type(bridge.GetState)=="function"
            and bridge.GetState() or nil
        local assistState=type(assist)=="table" and type(assist.GetState)=="function"
            and assist.GetState() or nil
        return {version="2.0",bridge=bridgeState,assist=assistState}
    end,
}

-- Only repair our Bloxtrap-style movement overlay after a map/round reset.
-- Never load any external Evade Legacy scripts or touch unrelated GUIs.
task.spawn(function()
    while env.__PCMovementAssistV2Token==token do
        task.wait(0.75)
        if env.__PCMovementAssistV2Token~=token then break end

        if game.GameId==EVADE_GAME_ID and not repairing then
            local overlay=playerGui:FindFirstChild(OVERLAY_NAME)
            local joystick=overlay and overlay:FindFirstChild("PCJoystick",true)
            local knob=joystick and joystick:FindFirstChild("Knob")
            local jumpButton=overlay and overlay:FindFirstChild("PCJump",true)
            local ready=overlay and overlay:IsA("ScreenGui") and joystick and knob and jumpButton
            if ready then
                missingSince=nil
            else
                missingSince=missingSince or os.clock()
                if os.clock()-missingSince>=1.25 and os.clock()-lastRepairAt>=3.0 then
                    repairing=true
                    lastRepairAt=os.clock()
                    local ok,err=pcall(function()
                        runModule("PCModeLockV2.lua")
                    end)
                    if not ok then warn("[PC Assist V2] UI repair failed: "..tostring(err)) end
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

print("[PC Movement + Assist V2] Loaded successfully")
