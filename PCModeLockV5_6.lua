local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

local oldCleanup=getgenv().__PCModeLockCleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end
local oldVisualCleanup=getgenv().__PCRobloxCleanVisualV5Cleanup
if type(oldVisualCleanup)=="function" then pcall(oldVisualCleanup) end
local oldProbeCleanup=getgenv().__PCInputRouteProbeV54Cleanup
if type(oldProbeCleanup)=="function" then pcall(oldProbeCleanup) end

-- Keep the working V5.5 input path unchanged.
local baseSource=game:HttpGet(ROOT.."PCModeLockV5_5.lua?_cb="..HttpService:GenerateGUID(false),true)
local baseChunk,baseError=loadstring(baseSource)
if not baseChunk then error(baseError) end
baseChunk()

-- Cosmetic-only pass: Roblox-native touch sprites and no debug bars.
local visualSource=game:HttpGet(ROOT.."PCRobloxCleanVisualV5.lua?_cb="..HttpService:GenerateGUID(false),true)
local visualChunk,visualError=loadstring(visualSource)
if not visualChunk then error(visualError) end
visualChunk()

local baseCleanup=getgenv().__PCModeLockCleanup
local visualCleanup=getgenv().__PCRobloxCleanVisualV5Cleanup

if type(getgenv().PCModeLock)=="table" then
    getgenv().PCModeLock.Version="5.6-roblox-clean-hidden-debug"
end

getgenv().__PCModeLockCleanup=function()
    if type(visualCleanup)=="function" then pcall(visualCleanup) end
    if type(baseCleanup)=="function" then pcall(baseCleanup) end
    getgenv().__PCModeLockCleanup=nil
end
