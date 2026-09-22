local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/rebuild-zero-v1/"
local function run(path)
    local source=game:HttpGet(ROOT..path.."?_cb="..HttpService:GenerateGUID(false),true)
    local chunk,err=loadstring(source)
    if not chunk then error("[Evade PC] compile failed in "..path..": "..tostring(err)) end
    local ok,result=pcall(chunk)
    if not ok then error("[Evade PC] runtime failed in "..path..": "..tostring(result)) end
    return result
end

return run("Loader_OverhaulCameraV1.lua")
