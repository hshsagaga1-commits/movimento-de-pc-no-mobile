local HttpService=game:GetService("HttpService")
local url="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV21_InputBridge.lua"
local source=game:HttpGet(url.."?_cb="..HttpService:GenerateGUID(false),true)
local chunk,err=loadstring(source)
if not chunk then error(err) end
return chunk()
