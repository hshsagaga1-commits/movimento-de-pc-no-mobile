local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

local source=game:HttpGet(
    ROOT.."PCKeyboardTouchBridgeV5_9.lua?_cb="..HttpService:GenerateGUID(false),
    true
)

local function replaceOncePlain(text,needle,replacement,label)
    local first,last=text:find(needle,1,true)
    if not first then error("V5.10 input-order patch failed: missing "..label) end
    if text:find(needle,last+1,true) then error("V5.10 input-order patch failed: duplicate "..label) end
    return text:sub(1,first-1)..replacement..text:sub(last+1)
end

-- V5.9 preserves the V5.2 render-step line in the generated bridge.
-- Move only that refresh from Input+8 (108) to Input-1 (99), so digital
-- W/A/S/D transitions are emitted before Roblox ControlModule reads its
-- movement vector at Input (100). No chord logic, gain, latch, jump,
-- camera, CFrame, AutoRotate, or movement-controller behavior is changed.
local anchor=[[
source=replaceOncePlain(source,oldCleanup,newCleanup,"cleanup burst cancellation")

local chunk,loadError=loadstring(source)
]]
local replacement=[[
source=replaceOncePlain(source,oldCleanup,newCleanup,"cleanup burst cancellation")

source=replaceOncePlain(
    source,
    "RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Input.Value+8,function()",
    "RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Input.Value-1,function()",
    "movement refresh render priority"
)

local chunk,loadError=loadstring(source)
]]
source=replaceOncePlain(source,anchor,replacement,"V5.9 compile anchor")

local chunk,loadError=loadstring(source)
if not chunk then error(loadError) end
chunk()

if type(getgenv().PCKeyboardTouchBridgeV52)=="table" then
    getgenv().PCKeyboardTouchBridgeV52.Version="5.10-pre-controlmodule-input-order"
end
