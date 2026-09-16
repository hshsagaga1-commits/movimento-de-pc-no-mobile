local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

local oldCleanup=getgenv().__PCModeLockCleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end
local oldGateCleanup=getgenv().__PCCameraTouchRightHalfGateV5Cleanup
if type(oldGateCleanup)=="function" then pcall(oldGateCleanup) end

-- Install PC lock + visible keyboard-only joystick/jump from V5.2.
local baseSource=game:HttpGet(ROOT.."PCModeLockV5_2.lua?_cb="..HttpService:GenerateGUID(false),true)
local baseChunk,baseError=loadstring(baseSource)
if not baseChunk then error(baseError) end
baseChunk()

-- Then gate BaseCamera itself: physical Touch from the left half is invisible to
-- the camera stack, while right-half Touch keeps the normal camera lifecycle.
local gateSource=game:HttpGet(ROOT.."CameraTouchRightHalfGateV5.lua?_cb="..HttpService:GenerateGUID(false),true)
local gateChunk,gateError=loadstring(gateSource)
if not gateChunk then error(gateError) end
gateChunk()

local baseCleanup=getgenv().__PCModeLockCleanup
local gateCleanup=getgenv().__PCCameraTouchRightHalfGateV5Cleanup

if type(getgenv().PCModeLock)=="table" then
    getgenv().PCModeLock.Version="5.3-pc-lock-visible-joystick-camera-right-half"
end

getgenv().__PCModeLockCleanup=function()
    if type(gateCleanup)=="function" then pcall(gateCleanup) end
    if type(baseCleanup)=="function" then pcall(baseCleanup) end
    getgenv().__PCModeLockCleanup=nil
end
