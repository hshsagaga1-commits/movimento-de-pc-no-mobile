local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/rebuild-zero-v1/"
local function run(path)
    local source=game:HttpGet(ROOT..path.."?_cb="..HttpService:GenerateGUID(false),true)
    local chunk,err=loadstring(source)
    if not chunk then error("[Evade PC Pack] compile failed in "..path..": "..tostring(err)) end
    local ok,result=pcall(chunk)
    if not ok then error("[Evade PC Pack] runtime failed in "..path..": "..tostring(result)) end
    return result
end

local camera=run("EvadePCRebuild_LegacyCameraV2.lua")
local body=run("EvadePCRebuild_LegacyBodyV2.lua")
local env=(type(getgenv)=="function" and getgenv()) or _G
local api={
    Version="EvadePC-LegacyCameraPack-V2",
    Camera=camera,
    Body=body,
    GetState=function()
        return {
            camera=type(env.EvadePCRebuildLegacyCameraV2)=="table" and env.EvadePCRebuildLegacyCameraV2.GetState and env.EvadePCRebuildLegacyCameraV2.GetState() or nil,
            body=type(env.EvadePCRebuildLegacyBodyV2)=="table" and env.EvadePCRebuildLegacyBodyV2.GetState and env.EvadePCRebuildLegacyBodyV2.GetState() or nil,
        }
    end,
}
env.EvadePCLegacyCameraPack=api
return api
