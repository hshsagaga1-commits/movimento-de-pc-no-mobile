local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

local oldCleanup=getgenv().__PCModeLockCleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end
local oldNativeVisualCleanup=getgenv().__PCRobloxNativeVisualV5Cleanup
if type(oldNativeVisualCleanup)=="function" then pcall(oldNativeVisualCleanup) end
local oldCleanVisualCleanup=getgenv().__PCRobloxCleanVisualV5Cleanup
if type(oldCleanVisualCleanup)=="function" then pcall(oldCleanVisualCleanup) end

-- Keep the known-working V5.5 input/controller path untouched.
local baseSource=game:HttpGet(ROOT.."PCModeLockV5_5.lua?_cb="..HttpService:GenerateGUID(false),true)
local baseChunk,baseError=loadstring(baseSource)
if not baseChunk then error(baseError) end
baseChunk()

-- Visual-only replacement using Roblox's exact fixed TouchThumbstick and
-- TouchJump assets/crops/small-screen layout rules.
local visualSource=game:HttpGet(ROOT.."PCRobloxNativeVisualV5.lua?_cb="..HttpService:GenerateGUID(false),true)
local visualChunk,visualError=loadstring(visualSource)
if not visualChunk then error(visualError) end
visualChunk()

local baseCleanup=getgenv().__PCModeLockCleanup
local visualCleanup=getgenv().__PCRobloxNativeVisualV5Cleanup

if type(getgenv().PCModeLock)=="table" then
    getgenv().PCModeLock.Version="5.7-exact-roblox-native-controls"
end

getgenv().__PCModeLockCleanup=function()
    if type(visualCleanup)=="function" then pcall(visualCleanup) end
    if type(baseCleanup)=="function" then pcall(baseCleanup) end
    getgenv().__PCModeLockCleanup=nil
end
