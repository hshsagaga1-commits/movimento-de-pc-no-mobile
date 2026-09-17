local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

local oldBodyCleanup=getgenv().__PCEvadeBodyViewV1Cleanup
if type(oldBodyCleanup)=="function" then pcall(oldBodyCleanup) end

local baseSource=game:HttpGet(ROOT.."PCModeLockV5_9.lua?_cb="..HttpService:GenerateGUID(false),true)
local baseChunk,baseError=loadstring(baseSource)
if not baseChunk then error(baseError) end
baseChunk()

local baseCleanup=getgenv().__PCModeLockCleanup

local bodySource=game:HttpGet(ROOT.."PCEvadeBodyViewV1.lua?_cb="..HttpService:GenerateGUID(false),true)
local bodyChunk,bodyError=loadstring(bodySource)
if not bodyChunk then error(bodyError) end
bodyChunk()

local bodyCleanup=getgenv().__PCEvadeBodyViewV1Cleanup
if type(getgenv().PCModeLock)=="table" then
    getgenv().PCModeLock.Version="5.9-bodyview-overhaul-legs-legacy-fullbody"
end

getgenv().__PCModeLockCleanup=function()
    if type(bodyCleanup)=="function" then pcall(bodyCleanup) end
    if type(baseCleanup)=="function" then pcall(baseCleanup) end
    getgenv().__PCModeLockCleanup=nil
end
