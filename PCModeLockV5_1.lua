local HttpService=game:GetService("HttpService")

local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

-- Install the proven V5 facade/controller lock first.
local lockSource=game:HttpGet(ROOT.."PCModeLockV5.lua?_cb="..HttpService:GenerateGUID(false),true)
local lockChunk,lockError=loadstring(lockSource)
if not lockChunk then error(lockError) end
lockChunk()

-- V5.0 also loaded the previous bridge, which wrote Player:Move at the end of
-- each frame. Once the real keyboard controller is locked active that becomes a
-- second locomotion writer. Remove it completely before installing the
-- keyboard-only bridge.
local oldMovementCleanup=getgenv().__PCIndependentJoystickCleanup
if type(oldMovementCleanup)=="function" then
    pcall(oldMovementCleanup)
end

local bridgeSource=game:HttpGet(ROOT.."PCKeyboardTouchBridgeV5.lua?_cb="..HttpService:GenerateGUID(false),true)
local bridgeChunk,bridgeError=loadstring(bridgeSource)
if not bridgeChunk then error(bridgeError) end
bridgeChunk()

local lockCleanup=getgenv().__PCModeLockCleanup
local bridgeCleanup=getgenv().__PCKeyboardTouchBridgeV5Cleanup

if type(getgenv().PCModeLock)=="table" then
    getgenv().PCModeLock.Version="5.1-pc-lock-keyboard-only-no-direct-move"
end

-- Chain cleanup so rerunning V5.1 cannot leave the keyboard-only bridge behind.
getgenv().__PCModeLockCleanup=function()
    if type(bridgeCleanup)=="function" then pcall(bridgeCleanup) end
    if type(lockCleanup)=="function" then pcall(lockCleanup) end
    getgenv().__PCModeLockCleanup=nil
end
