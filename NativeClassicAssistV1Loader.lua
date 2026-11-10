-- Native Classic Lateral + Assist V1. No PC Movement, replacement joystick or jump macro.
local HttpService=game:GetService("HttpService")
local env=getgenv()
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/native-classic-lateral-assist-20261109/"
local old=env.NativeClassicAssistCombo
if type(old)=="table" and type(old.Stop)=="function" then pcall(old.Stop) end
-- Retire the preserved PC controller, if present, before using native TouchGui.
local oldPC=env.PCMovementAssistV31Preserved
if type(oldPC)=="table" and type(oldPC.Stop)=="function" then pcall(oldPC.Stop) end

local token={}
env.__NativeClassicComboToken=token
local native,assistCleanup=nil,nil
local api={Version="1.0-native-classic-lateral-assist"}
local active=true
local function own() return active and env.__NativeClassicComboToken==token end
local function loadModule(filename)
    local src=game:HttpGet(ROOT..filename.."?v="..HttpService:GenerateGUID(false),true)
    if not own() then error("native classic loader superseded") end
    local chunk,err=loadstring(src)
    if not chunk then error(filename.." syntax: "..tostring(err)) end
    local ok,value=pcall(chunk)
    if not ok then error(filename.." runtime: "..tostring(value)) end
    if not own() then error("native classic loader stopped during initialization") end
    return value
end
function api.Stop()
    if not active then return end
    active=false
    if env.__NativeClassicComboToken==token then env.__NativeClassicComboToken=nil end
    if type(assistCleanup)=="function" and env.__NativeClassicGridAssistCleanup==assistCleanup then pcall(assistCleanup) end
    if type(native)=="table" and type(native.Stop)=="function" then pcall(native.Stop) end
    if env.NativeClassicAssistCombo==api then env.NativeClassicAssistCombo=nil end
end
function api.SetEnabled(value)
    if not own() or not native then return false,"not active" end
    return native.SetEnabled(value)
end
function api.SetAssistEnabled(value)
    if not own() then return false,"not active" end
    local a=env.NativeClassicGridAssistV1
    if a and type(a.SetEnabled)=="function" then return a.SetEnabled(value) end
    return false,"Assist not loaded"
end
function api.GetState()
    local n=native and native.GetState and native.GetState() or nil
    local a=env.NativeClassicGridAssistV1
    local assist=a and a.GetState and a.GetState() or nil
    return {version=api.Version,active=own(),native=n,assist=assist}
end
function api.SetDiagnostics(value)
    local a=env.NativeClassicGridAssistV1
    if a and a.SetDiagnostics then return a.SetDiagnostics(value) end
    return false,"Assist not loaded"
end
function api.ExportDiagnostics(filename)
    local a=env.NativeClassicGridAssistV1
    if a and a.ExportDiagnostics then return a.ExportDiagnostics(filename) end
    return false,"Assist not loaded"
end
local ok,message=pcall(function()
    native=loadModule("NativeClassicLateralV1.lua")
    if type(native)~="table" or type(native.GetState)~="function" then error("native controller module missing API") end
    loadModule("NativeClassicGridAssistV1.lua")
    assistCleanup=env.__NativeClassicGridAssistCleanup
    if type(assistCleanup)~="function" then error("Assist failed to register cleanup") end
end)
if not ok then api.Stop() error("[NativeClassicAssist] "..tostring(message)) end
env.NativeClassicAssistCombo=api
print("[NativeClassicAssist] Ready. Disable old PC Movement AutoExecute and test on the native Classic Thumbstick.")
return api
