local HttpService=game:GetService("HttpService")
local url="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV614_ControlledYawPitchMatching.lua"
local revision="V614-TemporalPoseControlR2-FullClipboardR1"
local source=game:HttpGet(url.."?_rev="..revision.."&_cb="..HttpService:GenerateGUID(false),true)
local chunk,err=loadstring(source)
if not chunk then error(err) end
return chunk()
