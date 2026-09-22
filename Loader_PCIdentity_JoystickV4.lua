local HttpService=game:GetService("HttpService")

local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/rebuild-zero-v1/"

local function run(path)
    local source=game:HttpGet(ROOT..path.."?_cb="..HttpService:GenerateGUID(false),true)
    local chunk,err=loadstring(source)
    if not chunk then
        error("[Evade PC Combo] compile failed in "..path..": "..tostring(err))
    end
    local ok,result=pcall(chunk)
    if not ok then
        error("[Evade PC Combo] runtime failed in "..path..": "..tostring(result))
    end
    return result
end

local identity=run("EvadePC_IdentityV1.lua")
local joystick=run("EvadePC_JoystickV7.lua")

local env=(type(getgenv)=="function" and getgenv()) or _G
local api={
    Version="EvadePC-Identity+Joystick-V5",
    Identity=identity,
    Joystick=joystick,
    GetState=function()
        local state={}
        if type(env.EvadePCIdentityV1)=="table"
            and type(env.EvadePCIdentityV1.GetState)=="function" then
            state.identity=env.EvadePCIdentityV1.GetState()
        end
        if type(env.EvadePCJoystickV7)=="table"
            and type(env.EvadePCJoystickV7.GetState)=="function" then
            state.joystick=env.EvadePCJoystickV7.GetState()
        end
        return state
    end,
}

env.EvadePCIdentityJoystick=api
return api
