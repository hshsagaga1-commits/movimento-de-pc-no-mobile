local HttpService=game:GetService("HttpService")
local STABLE="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"
local FEATURE="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-camera-grid-v6/"

local oldCleanup=getgenv().__PCModeLockCleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end
local oldCrouchCleanup=getgenv().__PCCrouchToggleV59Cleanup
if type(oldCrouchCleanup)=="function" then pcall(oldCrouchCleanup) end

-- Base movement stack only: bootstrap keyboard controller, restore real mobile
-- HUD identity, keep camera touch off the joystick half, and wake the selected
-- keyboard controller. No body-view or sensitivity module is loaded here.
local baseSource=game:HttpGet(STABLE.."PCModeLockV5_7.lua?_cb="..HttpService:GenerateGUID(false),true)
local baseChunk,baseError=loadstring(baseSource)
if not baseChunk then error(baseError) end
baseChunk()

-- Replace only the movement bridge with V6.2 joystick mapping while keeping the
-- proven V5.9 Space jump path.
local visualCleanup=getgenv().__PCRobloxNativeVisualV5Cleanup
if type(visualCleanup)=="function" then pcall(visualCleanup) end
local bridgeCleanup=getgenv().__PCKeyboardTouchBridgeV52Cleanup
if type(bridgeCleanup)=="function" then pcall(bridgeCleanup) end

local bridgeSource=game:HttpGet(FEATURE.."PCKeyboardTouchBridgeV6.lua?_cb="..HttpService:GenerateGUID(false),true)
local bridgeChunk,bridgeError=loadstring(bridgeSource)
if not bridgeChunk then error(bridgeError) end
bridgeChunk()

-- Exact Roblox-native joystick/jump visuals for the recreated V6 bridge.
local visualSource=game:HttpGet(STABLE.."PCRobloxNativeVisualV5.lua?_cb="..HttpService:GenerateGUID(false),true)
local visualChunk,visualError=loadstring(visualSource)
if not visualChunk then error(visualError) end
visualChunk()

-- Crouch remains Evade-native; helper adds only the pressed visual feedback.
local crouchSource=game:HttpGet(STABLE.."PCCrouchToggleV5_9.lua?_cb="..HttpService:GenerateGUID(false),true)
local crouchChunk,crouchError=loadstring(crouchSource)
if not crouchChunk then error(crouchError) end
crouchChunk()

local baseCleanup=getgenv().__PCModeLockCleanup
local newBridgeCleanup=getgenv().__PCKeyboardTouchBridgeV52Cleanup
local newVisualCleanup=getgenv().__PCRobloxNativeVisualV5Cleanup
local newCrouchCleanup=getgenv().__PCCrouchToggleV59Cleanup

if type(getgenv().PCModeLock)=="table" then
    getgenv().PCModeLock.Version="6.2-mobile-hud-2d-zones-space-jump"
end

getgenv().__PCModeLockCleanup=function()
    if type(newCrouchCleanup)=="function" then pcall(newCrouchCleanup) end
    if type(newVisualCleanup)=="function" then pcall(newVisualCleanup) end
    if type(newBridgeCleanup)=="function" then pcall(newBridgeCleanup) end
    if type(baseCleanup)=="function" then pcall(baseCleanup) end
    getgenv().__PCModeLockCleanup=nil
end
