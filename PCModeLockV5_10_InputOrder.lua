local HttpService=game:GetService("HttpService")
local CLASSIC_ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"
local ORDER_ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/f7f6f8f7d14a71775814d37d2a8c4c6d37d45c09/"

local oldCleanup=getgenv().__PCModeLockCleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end
local oldCrouchCleanup=getgenv().__PCCrouchToggleV59Cleanup
if type(oldCrouchCleanup)=="function" then pcall(oldCrouchCleanup) end

-- Preserve V5.9 architecture. Only the keyboard-touch bridge scheduling changes:\n-- continuous W/A/S/D refresh runs at Input-1; buffered jump service remains Input+8.\n-- The V5.5 keyboard-controller wake helper also runs at Input-1, so callback order\n-- between wake and movement refresh at that same priority is not guaranteed.
local baseSource=game:HttpGet(
    CLASSIC_ROOT.."PCModeLockV5_7.lua?_cb="..HttpService:GenerateGUID(false),
    true
)
local baseChunk,baseError=loadstring(baseSource)
if not baseChunk then error(baseError) end
baseChunk()

local visualCleanup=getgenv().__PCRobloxNativeVisualV5Cleanup
if type(visualCleanup)=="function" then pcall(visualCleanup) end

local bridgeCleanup=getgenv().__PCKeyboardTouchBridgeV52Cleanup
if type(bridgeCleanup)=="function" then pcall(bridgeCleanup) end

local bridgeSource=game:HttpGet(
    ORDER_ROOT.."PCKeyboardTouchBridgeV5_10_InputOrder.lua?_cb="..HttpService:GenerateGUID(false),
    true
)
local bridgeChunk,bridgeError=loadstring(bridgeSource)
if not bridgeChunk then error(bridgeError) end
bridgeChunk()

-- Reapply exact Roblox mobile visuals to the recreated bridge.
local visualSource=game:HttpGet(
    CLASSIC_ROOT.."PCRobloxNativeVisualV5.lua?_cb="..HttpService:GenerateGUID(false),
    true
)
local visualChunk,visualError=loadstring(visualSource)
if not visualChunk then error(visualError) end
visualChunk()

-- Keep the same native crouch helper as V5.9.
local crouchSource=game:HttpGet(
    CLASSIC_ROOT.."PCCrouchToggleV5_9.lua?_cb="..HttpService:GenerateGUID(false),
    true
)
local crouchChunk,crouchError=loadstring(crouchSource)
if not crouchChunk then error(crouchError) end
crouchChunk()

local baseCleanup=getgenv().__PCModeLockCleanup
local newBridgeCleanup=getgenv().__PCKeyboardTouchBridgeV52Cleanup
local newVisualCleanup=getgenv().__PCRobloxNativeVisualV5Cleanup
local newCrouchCleanup=getgenv().__PCCrouchToggleV59Cleanup

if type(getgenv().PCModeLock)=="table" then
    getgenv().PCModeLock.Version="5.10-v5.9-pre-controlmodule-ad-order-split-jump-buffer"
end

getgenv().__PCModeLockCleanup=function()
    if type(newCrouchCleanup)=="function" then pcall(newCrouchCleanup) end
    if type(newVisualCleanup)=="function" then pcall(newVisualCleanup) end
    if type(newBridgeCleanup)=="function" then pcall(newBridgeCleanup) end
    if type(baseCleanup)=="function" then pcall(baseCleanup) end
    getgenv().__PCModeLockCleanup=nil
end
