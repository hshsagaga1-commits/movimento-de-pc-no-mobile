-- Evade PC Rebuild Loader V1
-- Clean loader: no old module dependency, cache-busted on every run.

local HttpService = game:GetService("HttpService")

local ENV = (type(getgenv) == "function" and getgenv()) or _G
local VERSION = "EvadePCRebuild-Loader-V1"
local LEGACY_PLACE_ID = 96537472072550
local ROOT = "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/rebuild-zero-v1/"

local function safeCleanupFunction(name)
    local fn = ENV[name]
    if type(fn) == "function" then
        pcall(fn)
    end
end

-- Kill the old runtime stacks so they cannot fight the rebuild.
for _, name in ipairs({
    "__EvadePCRebuildLegacyBodyV1Cleanup",
    "__EvadePCRebuildLegacyCameraV1Cleanup",
    "__EvadePCRebuildInputV1Cleanup",
    "__PCEvadeBodyViewV1Cleanup",
    "__PCModeLockCleanup",
    "__PCKeyboardTouchBridgeV52Cleanup",
    "__PCRobloxNativeVisualV5Cleanup",
    "__PCCrouchToggleV59Cleanup",
    "__PCMobileAimCleanup",
}) do
    safeCleanupFunction(name)
end

for _, key in ipairs({
    "EvadeLegacyPCBuraco",
    "LegacyBuracoCompatV1",
    "LegacyBuracoCompatV2",
}) do
    local api = ENV[key]
    if type(api) == "table" and type(api.Cleanup) == "function" then
        pcall(api.Cleanup)
    end
end

local function runFile(path)
    local url = ROOT
        .. path
        .. "?_rev="
        .. VERSION
        .. "&_cb="
        .. HttpService:GenerateGUID(false)

    local source = game:HttpGet(url, true)
    local chunk, loadError = loadstring(source)

    if not chunk then
        error("[EvadePCRebuild] compile failed in " .. path .. ": " .. tostring(loadError))
    end

    local ok, result = pcall(chunk)
    if not ok then
        error("[EvadePCRebuild] runtime failed in " .. path .. ": " .. tostring(result))
    end

    return result
end

local input = runFile("EvadePCRebuild_InputV1.lua")
local camera = nil
local body = nil

if game.PlaceId == LEGACY_PLACE_ID then
    camera = runFile("EvadePCRebuild_LegacyCameraV1.lua")
    body = runFile("EvadePCRebuild_LegacyBodyV1.lua")
end

local api = {
    Version = VERSION,
    Input = input,
    Camera = camera,
    Body = body,
    Legacy = game.PlaceId == LEGACY_PLACE_ID,
    Reload = function()
        return runFile("EvadePCRebuild_LoaderV1.lua")
    end,
    GetState = function()
        local state = {
            version = VERSION,
            legacy = game.PlaceId == LEGACY_PLACE_ID,
        }

        if type(ENV.EvadePCRebuildInputV1) == "table"
            and type(ENV.EvadePCRebuildInputV1.GetState) == "function" then
            state.input = ENV.EvadePCRebuildInputV1.GetState()
        end

        if type(ENV.EvadePCRebuildLegacyCameraV1) == "table"
            and type(ENV.EvadePCRebuildLegacyCameraV1.GetState) == "function" then
            state.camera = ENV.EvadePCRebuildLegacyCameraV1.GetState()
        end

        if type(ENV.EvadePCRebuildLegacyBodyV1) == "table"
            and type(ENV.EvadePCRebuildLegacyBodyV1.GetState) == "function" then
            state.body = ENV.EvadePCRebuildLegacyBodyV1.GetState()
        end

        return state
    end,
}

ENV.EvadePCRebuild = api
return api
