local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

-- Preserve the proven V5.2 bridge behavior exactly, changing only the Space hold
-- from 55 ms to 100 ms. There is no added delay before Space-down: the existing
-- requestJump() path still calls pulseJump() immediately for a normal single tap.
local source=game:HttpGet(
    ROOT.."PCKeyboardTouchBridgeV5_2.lua?_cb="..HttpService:GenerateGUID(false),
    true
)

local replacements
source,replacements=source:gsub(
    "local SPACE_PULSE_SECONDS=0%.055",
    "local SPACE_PULSE_SECONDS=0.100",
    1
)

if replacements~=1 then
    error("V5.9 jump timing patch failed: expected exactly one 55 ms Space pulse constant")
end

local chunk,loadError=loadstring(source)
if not chunk then error(loadError) end
chunk()

if type(getgenv().PCKeyboardTouchBridgeV52)=="table" then
    getgenv().PCKeyboardTouchBridgeV52.Version="5.9-zero-delay-100ms-space-hold"
end
