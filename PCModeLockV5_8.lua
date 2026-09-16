local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

local oldCleanup=getgenv().__PCModeLockCleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end

-- Start from the current working V5.7 stack (PC lock + controller wake +
-- right-half camera gate + exact Roblox visual).
local baseSource=game:HttpGet(ROOT.."PCModeLockV5_7.lua?_cb="..HttpService:GenerateGUID(false),true)
local baseChunk,baseError=loadstring(baseSource)
if not baseChunk then error(baseError) end
baseChunk()

-- Replace only the keyboard-touch bridge so a normal single jump sends
-- Space-down immediately and releases Space 60 ms later.
local visualCleanup=getgenv().__PCRobloxNativeVisualV5Cleanup
if type(visualCleanup)=="function" then pcall(visualCleanup) end

local bridgeCleanup=getgenv().__PCKeyboardTouchBridgeV52Cleanup
if type(bridgeCleanup)=="function" then pcall(bridgeCleanup) end

local bridgeSource=game:HttpGet(ROOT.."PCKeyboardTouchBridgeV5_8.lua?_cb="..HttpService:GenerateGUID(false),true)
local bridgeChunk,bridgeError=loadstring(bridgeSource)
if not bridgeChunk then error(bridgeError) end
bridgeChunk()

-- Re-apply the exact native Roblox visual to the newly-created overlay.
local visualSource=game:HttpGet(ROOT.."PCRobloxNativeVisualV5.lua?_cb="..HttpService:GenerateGUID(false),true)
local visualChunk,visualError=loadstring(visualSource)
if not visualChunk then error(visualError) end
visualChunk()

local baseCleanup=getgenv().__PCModeLockCleanup
local newBridgeCleanup=getgenv().__PCKeyboardTouchBridgeV52Cleanup
local newVisualCleanup=getgenv().__PCRobloxNativeVisualV5Cleanup

if type(getgenv().PCModeLock)=="table" then
    getgenv().PCModeLock.Version="5.8-zero-delay-60ms-space-hold"
end

getgenv().__PCModeLockCleanup=function()
    if type(newVisualCleanup)=="function" then pcall(newVisualCleanup) end
    if type(newBridgeCleanup)=="function" then pcall(newBridgeCleanup) end
    if type(baseCleanup)=="function" then pcall(baseCleanup) end
    getgenv().__PCModeLockCleanup=nil
end
