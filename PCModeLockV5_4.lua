local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

local oldCleanup=getgenv().__PCModeLockCleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end
local oldProbeCleanup=getgenv().__PCInputRouteProbeV54Cleanup
if type(oldProbeCleanup)=="function" then pcall(oldProbeCleanup) end

local baseSource=game:HttpGet(ROOT.."PCModeLockV5_3.lua?_cb="..HttpService:GenerateGUID(false),true)
local baseChunk,baseError=loadstring(baseSource)
if not baseChunk then error(baseError) end
baseChunk()

local probeSource=game:HttpGet(ROOT.."PCInputRouteProbeV5_4.lua?_cb="..HttpService:GenerateGUID(false),true)
local probeChunk,probeError=loadstring(probeSource)
if not probeChunk then error(probeError) end
probeChunk()

local baseCleanup=getgenv().__PCModeLockCleanup
local probeCleanup=getgenv().__PCInputRouteProbeV54Cleanup
if type(getgenv().PCModeLock)=="table" then
    getgenv().PCModeLock.Version="5.4-route-probe-over-v5.3"
end

getgenv().__PCModeLockCleanup=function()
    if type(probeCleanup)=="function" then pcall(probeCleanup) end
    if type(baseCleanup)=="function" then pcall(baseCleanup) end
    getgenv().__PCModeLockCleanup=nil
end
