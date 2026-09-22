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

local identity=run("EvadePC_IdentityV1.lua")
local joystick=run("EvadePC_JoystickV7.lua")
local env=(type(getgenv)=="function" and getgenv()) or _G
local api={
    Version="EvadePC-PCControls-V1",
    Identity=identity,
    Joystick=joystick,
    GetState=function()
        return {
            identity=type(env.EvadePCIdentityV1)=="table" and env.EvadePCIdentityV1.GetState and env.EvadePCIdentityV1.GetState() or nil,
            joystick=type(env.EvadePCJoystickV7)=="table" and env.EvadePCJoystickV7.GetState and env.EvadePCJoystickV7.GetState() or nil,
        }
    end,
}
env.EvadePCControls=api
return api
