local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

local oldCleanup=getgenv().__PCModeLockCleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end
local oldWakeCleanup=getgenv().__PCKeyboardControllerWakeV5Cleanup
if type(oldWakeCleanup)=="function" then pcall(oldWakeCleanup) end
local oldProbeCleanup=getgenv().__PCInputRouteProbeV54Cleanup
if type(oldProbeCleanup)=="function" then pcall(oldProbeCleanup) end

-- Keep the current architecture: PC lock + visible keyboard-only joystick/jump
-- + camera Touch restricted to the right half.
local baseSource=game:HttpGet(ROOT.."PCModeLockV5_3.lua?_cb="..HttpService:GenerateGUID(false),true)
local baseChunk,baseError=loadstring(baseSource)
if not baseChunk then error(baseError) end
baseChunk()

-- Runtime evidence from V5.4 showed UIS received W/A/S/D and Space while the
-- selected PC activeController stayed enabled=false. Wake only that selected
-- controller; do not add Player:Move or alter the camera path.
local wakeSource=game:HttpGet(ROOT.."PCKeyboardControllerWakeV5.lua?_cb="..HttpService:GenerateGUID(false),true)
local wakeChunk,wakeError=loadstring(wakeSource)
if not wakeChunk then error(wakeError) end
wakeChunk()

local baseCleanup=getgenv().__PCModeLockCleanup
local wakeCleanup=getgenv().__PCKeyboardControllerWakeV5Cleanup

if type(getgenv().PCModeLock)=="table" then
    getgenv().PCModeLock.Version="5.5-enable-selected-keyboard-controller"
end

getgenv().__PCModeLockCleanup=function()
    if type(wakeCleanup)=="function" then pcall(wakeCleanup) end
    if type(baseCleanup)=="function" then pcall(baseCleanup) end
    getgenv().__PCModeLockCleanup=nil
end
