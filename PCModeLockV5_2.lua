local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

local oldCleanup=getgenv().__PCModeLockCleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end

-- Bootstrap ControlModule as PC, then expose the real mobile/touch identity back
-- to game HUD scripts while keeping the keyboard movement controller locked.
local lockSource=game:HttpGet(ROOT.."PCModeLockV5_HUDMobile.lua?_cb="..HttpService:GenerateGUID(false),true)
local lockChunk,lockError=loadstring(lockSource)
if not lockChunk then error(lockError) end
lockChunk()

-- Remove the bridge bundled inside V5.0. Its direct Player:Move writer is not
-- wanted while the real keyboard controller is locked active.
local bundledCleanup=getgenv().__PCIndependentJoystickCleanup
if type(bundledCleanup)=="function" then pcall(bundledCleanup) end

local bridgeSource=game:HttpGet(ROOT.."PCKeyboardTouchBridgeV5_2.lua?_cb="..HttpService:GenerateGUID(false),true)
local bridgeChunk,bridgeError=loadstring(bridgeSource)
if not bridgeChunk then error(bridgeError) end
bridgeChunk()

local lockCleanup=getgenv().__PCModeLockCleanup
local bridgeCleanup=getgenv().__PCKeyboardTouchBridgeV52Cleanup

if type(getgenv().PCModeLock)=="table" then
    getgenv().PCModeLock.Version="5.2-mobile-hud-pc-movement-visible-joystick"
end

getgenv().__PCModeLockCleanup=function()
    if type(bridgeCleanup)=="function" then pcall(bridgeCleanup) end
    if type(lockCleanup)=="function" then pcall(lockCleanup) end
    getgenv().__PCModeLockCleanup=nil
end
