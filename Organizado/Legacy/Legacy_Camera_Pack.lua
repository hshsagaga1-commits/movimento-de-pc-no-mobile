-- Legacy - Camera Pack
local HttpService=game:GetService("HttpService")
local url="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/rebuild-zero-v1/Loader_LegacyCameraPackV2.lua"
local source=game:HttpGet(url.."?_cb="..HttpService:GenerateGUID(false),true)
local chunk,err=loadstring(source)
if not chunk then error("[Legacy - Camera Pack] "..tostring(err)) end
return chunk()
