local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

local oldCleanup=getgenv().__PCModeLockCleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end
local oldCrouchCleanup=getgenv().__PCCrouchToggleV59Cleanup
if type(oldCrouchCleanup)=="function" then pcall(oldCrouchCleanup) end

-- Start from the current working V5.7 stack (PC lock + controller wake +
-- right-half camera gate + exact Roblox visual).
local baseSource=game:HttpGet(ROOT.."PCModeLockV5_7.lua?_cb="..HttpService:GenerateGUID(false),true)
local baseChunk,baseError=loadstring(baseSource)
if not baseChunk then error(baseError) end
baseChunk()

-- Replace only the keyboard-touch bridge. One tap jumps immediately, then the
-- bridge sends a fresh Space edge every Heartbeat for 200 ms so landing can be
-- caught on the earliest frame. Movement is mapped to PC-style digital sectors:
-- broad W/A/D/S zones and deliberately narrow diagonal W+A/W+D zones.
local visualCleanup=getgenv().__PCRobloxNativeVisualV5Cleanup
if type(visualCleanup)=="function" then pcall(visualCleanup) end

local bridgeCleanup=getgenv().__PCKeyboardTouchBridgeV52Cleanup
if type(bridgeCleanup)=="function" then pcall(bridgeCleanup) end

local bridgeSource=game:HttpGet(ROOT.."PCKeyboardTouchBridgeV5_9.lua?_cb="..HttpService:GenerateGUID(false),true)
local bridgeChunk,bridgeError=loadstring(bridgeSource)
if not bridgeChunk then error(bridgeError) end
bridgeChunk()

-- Re-apply the exact native Roblox joystick/jump visual to the newly-created overlay.
local visualSource=game:HttpGet(ROOT.."PCRobloxNativeVisualV5.lua?_cb="..HttpService:GenerateGUID(false),true)
local visualChunk,visualError=loadstring(visualSource)
if not visualChunk then error(visualError) end
visualChunk()

-- Crouch stays native: no clone and no replacement of Evade's toggle behavior.
-- The helper only adds the short PC-like pressed visual while the finger is down.
local crouchSource=game:HttpGet(ROOT.."PCCrouchToggleV5_9.lua?_cb="..HttpService:GenerateGUID(false),true)
local crouchChunk,crouchError=loadstring(crouchSource)
if not crouchChunk then error(crouchError) end
crouchChunk()

local baseCleanup=getgenv().__PCModeLockCleanup
local newBridgeCleanup=getgenv().__PCKeyboardTouchBridgeV52Cleanup
local newVisualCleanup=getgenv().__PCRobloxNativeVisualV5Cleanup
local newCrouchCleanup=getgenv().__PCCrouchToggleV59Cleanup

if type(getgenv().PCModeLock)=="table" then
    getgenv().PCModeLock.Version="5.9-zero-delay-200ms-digital-sectors-narrow-diagonals-native-crouch"
end

getgenv().__PCModeLockCleanup=function()
    if type(newCrouchCleanup)=="function" then pcall(newCrouchCleanup) end
    if type(newVisualCleanup)=="function" then pcall(newVisualCleanup) end
    if type(newBridgeCleanup)=="function" then pcall(newBridgeCleanup) end
    if type(baseCleanup)=="function" then pcall(baseCleanup) end
    getgenv().__PCModeLockCleanup=nil
end
