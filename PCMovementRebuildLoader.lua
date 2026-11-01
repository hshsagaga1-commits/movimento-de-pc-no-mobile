-- Optional remote loader. Use this OR the standalone AutoExecute, never both.
local url="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-movement-rebuild-20261101/PC_Movement_Rebuild_AUTOEXECUTE.lua"
local source=game:HttpGet(url.."?_cb="..game:GetService("HttpService"):GenerateGUID(false),true)
local chunk,reason=loadstring(source)
if not chunk then error("[PC Movement Rebuild] Bundle syntax: "..tostring(reason)) end
return chunk()
