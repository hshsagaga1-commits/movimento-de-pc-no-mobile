-- ClassicNativeBoostAssistLoader.lua
-- Native stock Classic Thumbstick + optional V3.1-derived light grid Assist.
-- Do NOT run the old PC Movement AutoExecute alongside this.
local HttpService=game:GetService("HttpService")
local env=getgenv()
local root="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/mobile-classic-boost-assist-20261109/"

if type(env.__ClassicNativeBoostAssistLoaderCleanup)=="function" then
    pcall(env.__ClassicNativeBoostAssistLoaderCleanup)
end

-- End only recognizable older PC Movement packages. The new script never
-- boots the PC keyboard bridge, camera, fake stick, or jump-button overlay.
for _,name in ipairs({
    "PCMovementAssistV31Preserved", "PCMovementAssistV31",
    "PCMovementAssistV3", "PCMovementAssistV2", "PCMovementRebuild"
}) do
    local old=env[name]
    if type(old)=="table" and type(old.Stop)=="function" then
        pcall(old.Stop)
    end
end

local active=true
local token={}
env.__ClassicNativeBoostAssistToken=token
local boost,assist
local boostCleanup,assistCleanup
local function isCurrent()
    return active and env.__ClassicNativeBoostAssistToken==token
end
-- Serialized lease prevents a re-execution from adopting an old half-built module.
local function loadModule(name, cleanupSlot)
    local source=game:HttpGet(root..name.."?cache="..HttpService:GenerateGUID(false),true)
    if not isCurrent() then error("Classic Native install cancelled") end
    local chunk,why=loadstring(source)
    if not chunk then error(name..": "..tostring(why)) end

    local start=os.clock()
    while env.__ClassicNativeBoostAssistInstallLease do
        if not isCurrent() then error("Classic Native install superseded") end
        if os.clock()-start>15 then error("Previous Classic Native installation did not finish") end
        task.wait(0.05)
    end
    if not isCurrent() then error("Classic Native install cancelled") end
    local lease={owner=token}
    env.__ClassicNativeBoostAssistInstallLease=lease
    local before=env[cleanupSlot]
    local ok,object=pcall(chunk)
    local after=env[cleanupSlot]
    if not ok or not isCurrent() then
        if type(after)=="function" and after~=before then pcall(after) end
    end
    if env.__ClassicNativeBoostAssistInstallLease==lease then
        env.__ClassicNativeBoostAssistInstallLease=nil
    end
    if not isCurrent() then error("Classic Native install superseded") end
    if not ok then error(name..": "..tostring(object)) end
    return object,after
end

local api={Version="1.0-native-classic-assist"}
function api.GetState()
    local b=type(boost)=="table" and type(boost.GetState)=="function" and boost.GetState() or nil
    local a=type(assist)=="table" and type(assist.GetState)=="function" and assist.GetState() or nil
    return {version=api.Version,active=isCurrent(),boost=b,assist=a}
end
function api.SetBoost(value)
    return boost and boost.SetEnabled and boost.SetEnabled(value)
end
function api.SetLateral(startAt,fullAt)
    if not boost or not boost.SetLateral then return false,"boost not loaded" end
    return boost.SetLateral(startAt,fullAt)
end
function api.SetAssist(value)
    return assist and assist.SetEnabled and assist.SetEnabled(value)
end
function api.SetDiagnostics(value)
    return assist and assist.SetDiagnostics and assist.SetDiagnostics(value)
end
function api.ExportDiagnostics(filename)
    if not assist or not assist.ExportDiagnostics then
        return false,"assist not loaded"
    end
    return assist.ExportDiagnostics(filename)
end
function api.Stop()
    if not active then return end
    active=false
    if env.__ClassicNativeBoostAssistToken==token then
        env.__ClassicNativeBoostAssistToken=nil
    end
    if type(assistCleanup)=="function" and env.__ClassicNativeGridAssistV1Cleanup==assistCleanup then
        pcall(assistCleanup)
    end
    if type(boostCleanup)=="function" and env.__ClassicNativeBoostV1Cleanup==boostCleanup then
        pcall(boostCleanup)
    end
    if env.ClassicNativeBoostAssist==api then env.ClassicNativeBoostAssist=nil end
    if env.__ClassicNativeBoostAssistLoaderCleanup==api.Stop then
        env.__ClassicNativeBoostAssistLoaderCleanup=nil
    end
end
env.__ClassicNativeBoostAssistLoaderCleanup=api.Stop

local ok,message=pcall(function()
    boost,boostCleanup=loadModule("ClassicNativeBoostV1.lua","__ClassicNativeBoostV1Cleanup")
    assist,assistCleanup=loadModule("ClassicNativeGridAssistV1.lua","__ClassicNativeGridAssistV1Cleanup")
end)
if not ok then
    api.Stop()
    error("[ClassicNativeBoostAssist] install failed: "..tostring(message))
end
env.ClassicNativeBoostAssist=api
print("[ClassicNativeBoostAssist] Loaded; status: "
    ..tostring(boost.GetState().status)
    ..". Stock joystick/jump/camera are retained. Run GetState() to confirm active.")
return api
