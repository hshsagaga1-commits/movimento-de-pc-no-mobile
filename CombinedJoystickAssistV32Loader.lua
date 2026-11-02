-- V3.2: proven V3.1 PC input/visuals with an isolated, reversible Assist.
-- Roll back Assist alone: getgenv().PCMovementAssistV31Preserved.SetAssistMode("original")
local HttpService=game:GetService("HttpService")
local Players=game:GetService("Players")
local ORIGINAL="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/ce4eb8b6deb47e0690301bd38f1b78eb0e19dcaa/"
local VISUAL="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-movement-v31-ui-fixes-20261102/"
local TUNED="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-movement-v32-v31-preserved-20261102/"
local env=getgenv()
local EVADE_GAME_ID=3647333358
local OVERLAY_NAME="PCKeyboardTouchBridgeV52Overlay"

-- Retire the incompatible reconstruction before running the exact old PC path.
if type(env.PCMovementRebuild)=="table" and type(env.PCMovementRebuild.Stop)=="function" then
    env.PCMovementRebuild.Stop()
end
local previous=env.PCMovementAssistV31Preserved
if type(previous)=="table" and type(previous.Stop)=="function" then previous.Stop() end
for _,name in ipairs({"PCMovementAssistV31","PCMovementAssistV3","PCMovementAssistV2"}) do
    local old=env[name]
    if type(old)=="table" and type(old.Stop)=="function" then pcall(old.Stop) end
end
env.__PCMovementAssistV2Token=nil
env.__PCMovementAssistV3Token=nil
env.__PCMovementAssistV31Token=nil
local token={}
env.__PCMovementV31PreservedToken=token
local active=true
local mode="starting"
local busy=false
local ownedPC,ownedGrid,ownedGridApi,ownedCursor
local api={Version="3.2-preserved-pc-light-contact"}

local function ownsGeneration()
    return active and env.__PCMovementV31PreservedToken==token
end
local function runModule(root,file)
    local source=game:HttpGet(root..file.."?_cb="..HttpService:GenerateGUID(false),true)
    if not ownsGeneration() then error("V3.1 preserved load cancelled") end
    local chunk,message=loadstring(source)
    if not chunk then error("[V3.1 preserved] "..file..": "..tostring(message)) end
    -- The unchanged native bootstrap can yield in its own HTTP/WaitForChild.
    -- Keep another preserved loader from installing over that half-built stack.
    local waitingSince=os.clock()
    while env.__PCMovementV31PreservedInstall do
        if not ownsGeneration() then error("V3.1 preserved load cancelled") end
        if os.clock()-waitingSince>15 then error("Previous V3.1 installation is still finishing; retry after it stops") end
        task.wait(0.05)
    end
    if not ownsGeneration() then error("V3.1 preserved load cancelled") end
    local lease={owner=token}
    env.__PCMovementV31PreservedInstall=lease
    local slot=file=="PCModeLockV3.lua" and "__PCModeLockCleanup"
        or (file=="PCCursorVisualV31.lua" and "__PCCursorVisualV31Cleanup" or "__LegacyGridContactAssistV1Cleanup")
    local before=env[slot]
    local beforeApi=env.LegacyGridContactAssistV1
    local ok,value=pcall(chunk)
    if not ok or not ownsGeneration() then
        local installed=env[slot]
        if type(installed)=="function" and installed~=before then pcall(installed) end
        if slot=="__LegacyGridContactAssistV1Cleanup" and env.LegacyGridContactAssistV1~=beforeApi then
            env.LegacyGridContactAssistV1=nil -- original V3.1 cleanup leaves a stale table
        end
    end
    if env.__PCMovementV31PreservedInstall==lease then env.__PCMovementV31PreservedInstall=nil end
    if not ownsGeneration() then error("V3.1 preserved load cancelled after module initialization") end
    if not ok then error(value) end
    return value
end
local function loadAssist(target)
    if target=="original" then runModule(ORIGINAL,"LegacyGridContactAssistV31.lua")
    elseif target=="v31" then runModule(VISUAL,"LegacyGridContactAssistV31Preserved.lua")
    else runModule(TUNED,"LegacyGridContactAssistV32.lua") end
    ownedGrid=env.__LegacyGridContactAssistV1Cleanup
    ownedGridApi=env.LegacyGridContactAssistV1
    mode=target
end
function api.SetAssistMode(target)
    if not active then return false,"stopped" end
    if target~="original" and target~="light" and target~="v31" then
        return false,"use original, v31 or light"
    end
    if busy then return false,"assist switch in progress" end
    busy=true
    local ok,message=pcall(loadAssist,target)
    if not ok and active and env.__PCMovementV31PreservedToken==token then
        local restored,reason=pcall(loadAssist,"v31")
        if not restored then
            mode="failed"
            warn("[V3.1 preserved] Assist rollback failed: "..tostring(reason))
        else warn("[V3.2] Assist failed; working V3.1 light Assist restored: "..tostring(message)) end
    end
    busy=false
    return ok,message
end
function api.GetState()
    local function read(name)
        local object=env[name]
        if type(object)=="table" and type(object.GetState)=="function" then
            local ok,value=pcall(object.GetState)
            if ok then return value end
        end
    end
    return {version="3.2",build=api.Version,assistMode=mode,originalPCBootstrap=true,
        bridge=read("PCKeyboardTouchBridgeV52"),assist=read("LegacyGridContactAssistV1"),
        pcLock=read("PCModeLock"),keyboardWake=read("PCKeyboardControllerWakeV5"),
        cursor=read("PCCursorVisualV31")}
end
function api.SetCursorHidden(value)
    if not ownsGeneration() then return false,"stopped" end
    local cursor=env.PCCursorVisualV31
    if type(cursor)=="table" and type(cursor.SetEnabled)=="function" then return cursor.SetEnabled(value) end
    return false,"cursor visual layer unavailable"
end
function api.SetDiagnostics(value)
    local assist=env.LegacyGridContactAssistV1
    if type(assist)=="table" and type(assist.SetDiagnostics)=="function" then return assist.SetDiagnostics(value) end
    return false,"diagnostics are available in light mode"
end
function api.ExportDiagnostics(filename)
    local assist=env.LegacyGridContactAssistV1
    if type(assist)=="table" and type(assist.ExportDiagnostics)=="function" then return assist.ExportDiagnostics(filename) end
    return false,"diagnostics are available in light mode"
end
function api.Stop()
    if not active then return end
    active=false
    if env.__PCMovementV31PreservedToken==token then env.__PCMovementV31PreservedToken=nil end
    if type(ownedCursor)=="function" and env.__PCCursorVisualV31Cleanup==ownedCursor then pcall(ownedCursor) end
    if type(ownedGrid)=="function" and env.__LegacyGridContactAssistV1Cleanup==ownedGrid then pcall(ownedGrid) end
    if env.LegacyGridContactAssistV1==ownedGridApi then env.LegacyGridContactAssistV1=nil end
    if type(ownedPC)=="function" and env.__PCModeLockCleanup==ownedPC then pcall(ownedPC) end
    if env.PCMovementAssistV31Preserved==api then env.PCMovementAssistV31Preserved=nil end
    if env.PCMovementAssistV31==api then env.PCMovementAssistV31=nil end
end

local ok,message=pcall(function()
    runModule(VISUAL,"PCModeLockV3.lua") -- exact working PC bootstrap/visual bridge
    ownedPC=env.__PCModeLockCleanup
    local cursorOk,cursorMessage=pcall(runModule,VISUAL,"PCCursorVisualV31.lua")
    if cursorOk then ownedCursor=env.__PCCursorVisualV31Cleanup
    else warn("[V3.1 preserved] Cursor appearance unavailable; PC controls kept: "..tostring(cursorMessage)) end
    local loaded=api.SetAssistMode("light")
    if not loaded and mode~="v31" then error("neither Assist variant could load") end
end)
if not ok then api.Stop() error(message) end
env.PCMovementAssistV31Preserved=api
env.PCMovementAssistV31=api

-- Same V3.1 overlay recovery timing; always reload the original PC bootstrap.
local playerGui=Players.LocalPlayer:WaitForChild("PlayerGui")
local missingSince=nil
local lastRepairAt=-math.huge
local repairing=false
task.spawn(function()
    while active and env.__PCMovementV31PreservedToken==token do
        task.wait(0.75)
        if not active or env.__PCMovementV31PreservedToken~=token then break end
        if game.GameId==EVADE_GAME_ID and not repairing then
            local overlay=playerGui:FindFirstChild(OVERLAY_NAME)
            local stick=overlay and overlay:FindFirstChild("PCJoystick",true)
            local knob=stick and stick:FindFirstChild("Knob")
            local jump=overlay and overlay:FindFirstChild("PCJump",true)
            local ready=overlay and overlay:IsA("ScreenGui") and stick and knob and jump
            if ready then missingSince=nil
            else
                missingSince=missingSince or os.clock()
                if os.clock()-missingSince>=1.25 and os.clock()-lastRepairAt>=3.0 then
                    repairing=true
                    lastRepairAt=os.clock()
                    local repaired,reason=pcall(function()
                        runModule(VISUAL,"PCModeLockV3.lua")
                        ownedPC=env.__PCModeLockCleanup
                    end)
                    if not repaired then warn("[V3.1 preserved] Original overlay repair: "..tostring(reason)) end
                    task.wait(0.25)
                    repairing=false
                    missingSince=nil
                end
            end
        else missingSince=nil end
    end
end)
print("[V3.2] Original PC keyboard, joystick, jump and camera loaded; Assist mode: "..mode)
return api
