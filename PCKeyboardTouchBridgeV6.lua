local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

-- Build on the last approved V5.9 bridge and change only the digital sector map.
-- Jump/crouch/camera behavior is intentionally untouched here.
local source=game:HttpGet(
    ROOT.."PCKeyboardTouchBridgeV5_9.lua?_cb="..HttpService:GenerateGUID(false),
    true
)

local function replaceOncePlain(text,needle,replacement,label)
    local first,last=text:find(needle,1,true)
    if not first then error("V6 patch failed: missing "..label) end
    if text:find(needle,last+1,true) then error("V6 patch failed: duplicate "..label) end
    return text:sub(1,first-1)..replacement..text:sub(last+1)
end

-- Upper-half angular ownership, measured from straight-forward W:
--   W pure:  +/-18 degrees = ~20% of the upper semicircle
--   WA/WD:   18..45 degrees on each side = ~30% combined
--   A/D:     45..90 degrees on each side = ~50% combined
-- tan(18 deg) ~= 0.32492, tan(45 deg) = 1.0.
source=replaceOncePlain(
    source,
    "local DIGITAL_DIAGONAL_MIN_RATIO=0.65\n    local DIGITAL_DIAGONAL_MAX_RATIO=1.54",
    "local DIGITAL_DIAGONAL_MIN_RATIO=0.32492\n    local DIGITAL_DIAGONAL_MAX_RATIO=1.00",
    "digital sector ratios"
)

source=source:gsub(
    "5%.9%-zero%-delay%-200ms%-digital%-sectors%-wider%-diagonals%-lateral%-latch",
    "6.0-zero-delay-200ms-20w-30diag-50lateral-lateral-latch",
    1
)

local chunk,loadError=loadstring(source)
if not chunk then error(loadError) end
chunk()

if type(getgenv().PCKeyboardTouchBridgeV52)=="table" then
    getgenv().PCKeyboardTouchBridgeV52.Version="6.0-zero-delay-200ms-20w-30diag-50lateral-lateral-latch"
end
