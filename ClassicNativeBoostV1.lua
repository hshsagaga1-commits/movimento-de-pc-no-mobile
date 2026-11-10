-- ClassicNativeBoostV1.lua
-- Does not create a joystick, replace TouchGui, synthesize keys, or call Player:Move.
-- Wraps GetMoveVector ONLY for the stock TouchThumbstick controller.
-- A native PlayerModule update may require a new compatibility adapter.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local env = getgenv()

if type(env.__ClassicNativeBoostV1Cleanup) == "function" then
    pcall(env.__ClassicNativeBoostV1Cleanup)
end

local config = {
    SideStart = 0.08,
    SideFullAt = 0.58,
    Enabled = true,
}
local running = true
local controls = nil
local attached = nil
local originalMethod = nil
local originalOwnMethod = nil
local wrapper = nil
local checks, calls, boostedCalls, errors = 0, 0, 0, 0
local status = "waiting-for-native-controls"
local rawMove, shapedMove = Vector3.zero, Vector3.zero

local function shapeMove(move)
    if typeof(move) ~= "Vector3" then return move end
    local x, z = move.X, move.Z
    if x ~= x or z ~= z then return move end
    local absX = math.abs(x)
    local newX = 0
    if absX > config.SideStart then
        local strength = math.clamp(
            (absX - config.SideStart) / (config.SideFullAt - config.SideStart),
            0, 1
        )
        -- Independent lateral saturation: -X -> +X has no 0.2s hold or key latch.
        newX = (x > 0 and 1 or -1) * strength
    end
    local result = Vector3.new(newX, move.Y, z)
    local horizontal = Vector3.new(result.X, 0, result.Z)
    if horizontal.Magnitude > 1 then
        horizontal = horizontal.Unit
        result = Vector3.new(horizontal.X, move.Y, horizontal.Z)
    end
    return result
end

local function isNativeClassic(c)
    if type(c) ~= "table" or not c.enabled then return false end
    if not controls or controls.activeController ~= c then return false end
    local activeModule = controls.activeControlModule
    -- Do not confuse TouchThumbstick (Classic) with DynamicThumbstick.
    return typeof(activeModule) == "Instance"
        and activeModule.Name == "TouchThumbstick"
end

local function detach()
    if attached and wrapper and attached.GetMoveVector == wrapper then
        -- Preserve whether the old method was inherited from its metatable.
        pcall(function() attached.GetMoveVector = originalOwnMethod end)
    end
    attached = nil
    originalMethod = nil
    originalOwnMethod = nil
    wrapper = nil
end

local function attach(c)
    if attached == c and c.GetMoveVector == wrapper then return true end
    detach()
    if type(c) ~= "table" or type(c.GetMoveVector) ~= "function" then return false end
    local base = c.GetMoveVector
    local own = rawget(c, "GetMoveVector")
    local hooked
    hooked = function(self, ...)
        calls += 1
        local move = base(self, ...)
        if not running or not config.Enabled or not isNativeClassic(self) then
            return move
        end
        rawMove = move
        local shaped = shapeMove(move)
        shapedMove = shaped
        if typeof(move) == "Vector3" and shaped ~= move then
            boostedCalls += 1
        end
        return shaped
    end
    local ok = pcall(function() c.GetMoveVector = hooked end)
    if not ok or c.GetMoveVector ~= hooked then
        errors += 1
        return false
    end
    attached, originalMethod, originalOwnMethod, wrapper = c, base, own, hooked
    return true
end

local function locateControls()
    local scripts = player:FindFirstChild("PlayerScripts")
    local module = scripts and scripts:FindFirstChild("PlayerModule")
    if not module or not module:IsA("ModuleScript") then
        return nil, "player-module-not-ready"
    end
    local ok, playerModule = pcall(require, module)
    if not ok or type(playerModule) ~= "table" then
        return nil, "player-module-require-failed"
    end
    if type(playerModule.GetControls) ~= "function" then
        return nil, "unsupported-input-action-player-module"
    end
    local good, candidate = pcall(playerModule.GetControls, playerModule)
    if not good or type(candidate) ~= "table" then
        return nil, "get-controls-failed"
    end
    return candidate, nil
end

local function refresh()
    if not running then return end
    checks += 1
    local found, reason = locateControls()
    if not found then
        detach()
        controls = nil
        status = reason
        return
    end
    controls = found
    local candidate = controls.activeController
    if not candidate or not isNativeClassic(candidate) then
        detach()
        status = "waiting-for-classic-thumbstick"
        return
    end
    if attached and attached.GetMoveVector ~= wrapper then
        -- Another script changed the method. Never steal its hook or stomp its cleanup.
        attached, wrapper, originalMethod, originalOwnMethod = nil, nil, nil, nil
        status = "hook-was-replaced"
        return
    end
    if attach(candidate) then status = config.Enabled and "active" or "paused"
    else status = "hook-install-failed" end
end

local api = {
    Version = "1.0-native-classic-no-pc-movement",
    SetEnabled = function(value)
        config.Enabled = value == true
        status = config.Enabled and "awaiting-refresh" or "paused"
        return config.Enabled
    end,
    SetLateral = function(sideStart, sideFullAt)
        if type(sideStart) ~= "number" or type(sideFullAt) ~= "number"
            or sideStart ~= sideStart or sideFullAt ~= sideFullAt
            or sideStart < 0 or sideFullAt > 1 or sideFullAt - sideStart < 0.1 then
            return false, "use 0 <= SideStart < SideFullAt <= 1, separated by >= 0.1"
        end
        config.SideStart, config.SideFullAt = sideStart, sideFullAt
        return true
    end,
    GetState = function()
        return {
            version = "1.0", status = status, enabled = config.Enabled,
            sideStart = config.SideStart, sideFullAt = config.SideFullAt,
            nativeClassic = attached ~= nil,
            rawX = rawMove.X, rawZ = rawMove.Z,
            processedX = shapedMove.X, processedZ = shapedMove.Z,
            checks = checks, calls = calls, boostedCalls = boostedCalls,
            errors = errors, input = tostring(UserInputService.PreferredInput),
        }
    end,
    -- No temporary state table on Assist Heartbeat.
    ReadInput = function() return shapedMove.X, shapedMove.Z end,
    ShapeForTest = shapeMove,
}
local cleanup
cleanup = function()
    running = false
    detach()
    controls = nil
    status = "stopped"
    if env.ClassicNativeBoostV1 == api then env.ClassicNativeBoostV1 = nil end
    if env.__ClassicNativeBoostV1Cleanup == cleanup then
        env.__ClassicNativeBoostV1Cleanup = nil
    end
end
api.Stop = cleanup
env.ClassicNativeBoostV1 = api
env.__ClassicNativeBoostV1Cleanup = cleanup

refresh()
task.spawn(function()
    while running do
        task.wait(0.45)
        if running then
            local ok, message = pcall(refresh)
            if not ok then
                errors += 1
                status = "refresh-error"
                warn("[ClassicNativeBoostV1] " .. tostring(message))
            end
        end
    end
end)
return api
