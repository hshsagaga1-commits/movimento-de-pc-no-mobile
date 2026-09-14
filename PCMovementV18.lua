local HttpService=game:GetService("HttpService")

-- V18 = V17 + one measured final adjustment.
-- Diagnostic comparison against the PC reference showed the remaining gap is
-- concentrated in tiny camera corrections / fast reversals, not movement or framing.
-- Scale ONLY V17's micro-polish layer by 18%; everything underneath stays identical.
local FINAL_POLISH_SCALE=1.18
getgenv().PCMouseMicroBoost=0.10*FINAL_POLISH_SCALE
getgenv().PCMouseReverseBoost=0.06*FINAL_POLISH_SCALE
getgenv().PCMouseFinalPolishScale=FINAL_POLISH_SCALE

local src=game:HttpGet(
    "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV17.lua?_cb="
    ..HttpService:GenerateGUID(false),
    true
)

local fn,err=loadstring(src)
if not fn then error(err) end
fn()

getgenv().PCMovementVersion="V18"
