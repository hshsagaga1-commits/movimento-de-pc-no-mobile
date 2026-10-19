-- Combined loader: PC movement/keyboard bridge + wall/edge Assist.
-- Keeps the existing modules and their order intact; loads both from this branch.
-- Use this single loader instead of running JoystickOnlyLoader and AssistOnlyLoader separately.
local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-camera-grid-v6/"

local function runModule(path)
    local source=game:HttpGet(ROOT..path.."?_cb="..HttpService:GenerateGUID(false),true)
    local chunk,err=loadstring(source)
    if not chunk then error("Failed to load "..path..": "..tostring(err)) end
    return chunk()
end

-- Start keyboard/joystick movement bridge first, so Assist can read the active chord.
runModule("PCModeLockV6.lua")
-- Then start wall/rail/edge assistance.
runModule("LegacyGridContactAssistV1.lua")
