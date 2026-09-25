-- PCBuracoNativeMouseV1_1_ADOrder.lua
-- Practical Evade Legacy camera implementation.
--
-- Touch camera packets keep Roblox touch bookkeeping, but their native pan
-- contribution is suppressed. Their deltas are accumulated until immediately
-- before the next Roblox camera update and then injected at the native mouse
-- rotation stage. If this Delta build rejects a Lua proxy in OnMouseMoved,
-- V1.1 writes the equivalent measured mouse contribution to rotateInput,
-- which Roblox consumes normally in its own camera Update.
--
-- No Camera.CFrame / Focus / RootPart.CFrame writes. No smoothing. No forced
-- MouseBehavior, RotationType, FOV, zoom or mouse-lock offset.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local VERSION = "PC-BURACO-NATIVE-MOUSE-V1.1-AD-ORDER"
local WATCH_BIND = "__PCBuracoNativeMouseV11_Watch"
local DISPATCH_BIND = "__PCBuracoNativeMouseV11_Dispatch"
local DOT_GUI = "__PCBuracoNativeMouseV11_Dot"

if type(ENV.__PCBuracoNativeMouseV11Cleanup) == "function" then
    pcall(ENV.__PCBuracoNativeMouseV11Cleanup)
end

-- Keep the approved V1.1 camera path. Movement is V5.9-identical except\n-- the continuous digital W/A/S/D refresh runs at Input-1 instead of Input+8,\n-- so direction transitions are emitted before ControlModule reads movement.\n-- Buffered jump servicing remains at Input+8.
do
    local url = "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/41d76e4aee0c99368e0182d1623ad85953e9d3fe/PCModeLockV5_10_InputOrder.lua?_cb="
        .. HttpService:GenerateGUID(false)
    local source = game:HttpGet(url, true)
    local chunk, err = loadstring(source)
    if not chunk then error(err) end
    chunk()
end

local baseCleanup = ENV.__PCModeLockCleanup

-- Preserve the native Touch angular scale, but feed it through the mouse stage.
local GAIN_X = tonumber(ENV.PCBuracoMouseGainX) or 4.536017948763518
local GAIN_Y = tonumber(ENV.PCBuracoMouseGainY) or 2.131597261871922
local RIGHT_SPLIT = tonumber(ENV.PCBuracoCameraSplit) or 0.50
local DOT_ENABLED = ENV.PCBuracoDot ~= false

-- Measured Legacy mouse coefficients.
local MOUSE_RAD_X = (math.pi * 4) / 1920
local MOUSE_RAD_Y = (math.pi * 1.9) / 1200

local playerModule
local cameras
local activeController
local installedController
local installedHook
local pendingDelta = Vector2.zero
local gui

local cameraTouchPackets = 0
local bookkeepingPasses = 0
local mouseStageDispatches = 0
local rotateInputFallbacks = 0
local nativeFallbackPackets = 0
local hookInstalls = 0
local hookFailures = 0
local controllerChanges = 0
local lastRoute = "initializing"
local lastError = nil

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok then return value end
    return fallback
end

local function getPlayerModule()
    if type(playerModule) == "table" then return playerModule end
    local ps = player:FindFirstChild("PlayerScripts")
    local ms = ps and ps:FindFirstChild("PlayerModule")
    if not ms then return nil end
    playerModule = safe(function() return require(ms) end, nil)
    return type(playerModule) == "table" and playerModule or nil
end

local function getCameras()
    if type(cameras) == "table" then return cameras end
    local pm = getPlayerModule()
    if type(pm) ~= "table" then return nil end
    cameras = safe(function()
        if type(pm.GetCameras) == "function" then return pm:GetCameras() end
        return rawget(pm, "cameras")
    end, rawget(pm, "cameras"))
    return type(cameras) == "table" and cameras or nil
end

local function getActiveController()
    local cm = getCameras()
    if type(cm) ~= "table" then return nil end
    local c = rawget(cm, "activeCameraController")
    if type(c) ~= "table" and type(cm.GetActiveCameraController) == "function" then
        c = safe(function() return cm:GetActiveCameraController() end, nil)
    end
    return type(c) == "table" and c or nil
end

local function getMeta(t)
    local mt
    if type(getrawmetatable) == "function" then
        pcall(function() mt = getrawmetatable(t) end)
    end
    if type(mt) ~= "table" then
        pcall(function() mt = getmetatable(t) end)
    end
    return type(mt) == "table" and mt or nil
end

local function findMethod(root, name)
    local seen = {}
    local function visit(t, depth)
        if type(t) ~= "table" or depth > 14 or seen[t] then return nil end
        seen[t] = true

        local f = safe(function() return rawget(t, name) end, nil)
        if type(f) == "function" then
            return {fn=f, owner=t, name=name}
        end

        local idx = safe(function() return rawget(t, "__index") end, nil)
        if type(idx) == "table" then
            local r = visit(idx, depth + 1)
            if r then return r end
        end

        local mt = getMeta(t)
        if mt then
            local r = visit(mt, depth + 1)
            if r then return r end
        end
    end
    return visit(root, 0)
end

local function inputDelta(input)
    local d = safe(function() return input.Delta end, nil)
    if typeof(d) == "Vector3" then return Vector2.new(d.X, d.Y) end
    if typeof(d) == "Vector2" then return d end
    return nil
end

local function rightSide(input)
    local x = safe(function() return input.Position.X end, nil)
    local cam = workspace.CurrentCamera
    local w = cam and cam.ViewportSize.X or 1125
    return type(x) == "number" and x > w * RIGHT_SPLIT
end

local function isCameraTouch(controller, input)
    if type(controller) ~= "table" then return false end
    local map = rawget(controller, "fingerTouches")
    if type(map) ~= "table" then return false end

    local mapped = safe(function() return rawget(map, input) end, nil)
    if mapped ~= false then return false end

    local unsunk = rawget(controller, "numUnsunkTouches")
    if type(unsunk) == "number" and unsunk ~= 1 then return false end
    return true
end

local function restoreHook()
    local h = installedHook
    installedHook = nil
    installedController = nil
    if not h then return end

    if h.mode == "hookfunction" and type(hookfunction) == "function" then
        pcall(function() hookfunction(h.target, h.original) end)
    elseif h.mode == "rawset" then
        pcall(function() rawset(h.owner, h.name, h.original) end)
    end
end

local function installForController(controller)
    restoreHook()
    if type(controller) ~= "table" then
        lastRoute = "waiting-controller"
        return false
    end

    local target = findMethod(controller, "OnInputChanged")
    if not target then
        hookFailures += 1
        lastRoute = "OnInputChanged-missing"
        return false
    end

    local original

    local function replacement(self, input, processed, ...)
        local inputType = safe(function() return input.UserInputType end, nil)

        if self ~= getActiveController()
            or inputType ~= Enum.UserInputType.Touch
            or not rightSide(input)
            or not isCameraTouch(self, input) then
            nativeFallbackPackets += (inputType == Enum.UserInputType.Touch) and 1 or 0
            return original(self, input, processed, ...)
        end

        local d = inputDelta(input)
        if not d or d.Magnitude <= 1e-7 then
            return original(self, input, processed, ...)
        end

        local previousPan = rawget(self, "panEnabled")
        if previousPan == nil then
            nativeFallbackPackets += 1
            return original(self, input, processed, ...)
        end

        -- Keep fingerTouches / pinch / lifecycle state but remove Touch-pan.
        self.panEnabled = false
        local packed = table.pack(pcall(original, self, input, processed, ...))
        self.panEnabled = previousPan

        if not packed[1] then
            lastError = tostring(packed[2])
            error(packed[2], 0)
        end

        bookkeepingPasses += 1
        cameraTouchPackets += 1
        pendingDelta += d

        return table.unpack(packed, 2, packed.n)
    end

    if type(hookfunction) == "function" then
        local ok, old = pcall(function()
            return hookfunction(target.fn, replacement)
        end)
        if ok and type(old) == "function" then
            original = old
            installedHook = {mode="hookfunction", target=target.fn, original=old}
            installedController = controller
            hookInstalls += 1
            lastRoute = "touch-capture-installed"
            return true
        end
    end

    local previous = safe(function() return rawget(target.owner, target.name) end, nil)
    if type(previous) == "function" then
        original = previous
        local ok = pcall(function()
            rawset(target.owner, target.name, replacement)
        end)
        if ok then
            installedHook = {
                mode="rawset",
                owner=target.owner,
                name=target.name,
                original=previous,
            }
            installedController = controller
            hookInstalls += 1
            lastRoute = "touch-capture-installed-rawset"
            return true
        end
    end

    hookFailures += 1
    lastRoute = "touch-capture-hook-failed"
    return false
end

local function buildMouseProxy(dx, dy)
    local cam = workspace.CurrentCamera
    local center = cam and cam.ViewportSize * 0.5 or Vector2.zero
    return {
        UserInputType = Enum.UserInputType.MouseMovement,
        UserInputState = Enum.UserInputState.Change,
        KeyCode = Enum.KeyCode.Unknown,
        Delta = Vector3.new(dx, dy, 0),
        Position = Vector3.new(center.X, center.Y, 0),
    }
end

local function dispatchMouseStage(dx, dy)
    local controller = getActiveController()
    if type(controller) ~= "table" then return false end

    -- First try the real Legacy OnMouseMoved stage.
    local mouseTarget = findMethod(controller, "OnMouseMoved")
    if mouseTarget and type(mouseTarget.fn) == "function" then
        local before = rawget(controller, "rotateInput")
        local ok, err = pcall(function()
            mouseTarget.fn(controller, buildMouseProxy(dx, dy))
        end)
        local after = rawget(controller, "rotateInput")

        if ok and typeof(before) == "Vector2" and typeof(after) == "Vector2"
            and (after - before).Magnitude > 1e-8 then
            mouseStageDispatches += 1
            lastRoute = "frame-OnMouseMoved"
            return true
        end

        if not ok then lastError = tostring(err) end
    end

    -- Delta can accept the Lua proxy call but silently ignore it. Reproduce the
    -- measured output of the mouse stage at the exact same pipeline variable.
    local current = rawget(controller, "rotateInput")
    if typeof(current) == "Vector2" then
        local contribution = Vector2.new(
            -dx * MOUSE_RAD_X,
            -dy * MOUSE_RAD_Y
        )
        rawset(controller, "rotateInput", current + contribution)
        rotateInputFallbacks += 1
        lastRoute = "frame-mouse-output->rotateInput"
        return true
    end

    lastRoute = "rotateInput-unavailable"
    return false
end

local function dispatchPending()
    if pendingDelta.Magnitude <= 1e-7 then return end

    local d = pendingDelta
    pendingDelta = Vector2.zero

    -- d is physical Touch delta. Convert it to the equivalent mouse delta
    -- before entering the mouse-stage coefficient.
    dispatchMouseStage(d.X * GAIN_X, d.Y * GAIN_Y)
end

local function makeDot()
    if not DOT_ENABLED then return end

    local parent = CoreGui
    if type(gethui) == "function" then
        parent = safe(function() return gethui() end, CoreGui)
    end

    local old = parent and parent:FindFirstChild(DOT_GUI)
    if old then pcall(function() old:Destroy() end) end

    gui = Instance.new("ScreenGui")
    gui.Name = DOT_GUI
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999999
    gui.Parent = parent

    local dot = Instance.new("Frame")
    dot.Name = "BuracoDot"
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.Position = UDim2.fromScale(0.5, 0.5)
    dot.Size = UDim2.fromOffset(1, 1)
    dot.BorderSizePixel = 0
    dot.BackgroundColor3 = Color3.new(1, 1, 1)
    dot.Parent = gui
end

pcall(function() RunService:UnbindFromRenderStep(WATCH_BIND) end)
pcall(function() RunService:UnbindFromRenderStep(DISPATCH_BIND) end)

activeController = getActiveController()
if activeController then
    pcall(function() installForController(activeController) end)
end

RunService:BindToRenderStep(WATCH_BIND, Enum.RenderPriority.Camera.Value - 14, function()
    local controller = getActiveController()
    if controller ~= activeController then
        activeController = controller
        controllerChanges += 1
        pcall(function() installForController(controller) end)
    elseif controller and installedController ~= controller then
        pcall(function() installForController(controller) end)
    end
end)

-- The packet is injected before Roblox's own camera Update consumes rotateInput.
RunService:BindToRenderStep(
    DISPATCH_BIND,
    Enum.RenderPriority.Camera.Value - 10,
    dispatchPending
)

makeDot()

ENV.PCBuracoNativeMouseV11 = {
    Version = VERSION,
    GetState = function()
        return {
            version = VERSION,
            gainX = GAIN_X,
            gainY = GAIN_Y,
            cameraTouchPackets = cameraTouchPackets,
            bookkeepingPasses = bookkeepingPasses,
            mouseStageDispatches = mouseStageDispatches,
            rotateInputFallbacks = rotateInputFallbacks,
            nativeFallbackPackets = nativeFallbackPackets,
            hookInstalls = hookInstalls,
            hookFailures = hookFailures,
            controllerChanges = controllerChanges,
            lastRoute = lastRoute,
            lastError = lastError,
            activeController = tostring(getActiveController()),
            writesCameraCFrame = false,
            writesCameraFocus = false,
            writesRootPartCFrame = false,
            forcesMouseBehavior = false,
            forcesRotationType = false,
            forcesMouseLockOffset = false,
            smoothing = false,
        }
    end,
}

ENV.__PCBuracoNativeMouseV11Cleanup = function()
    pcall(function() RunService:UnbindFromRenderStep(WATCH_BIND) end)
    pcall(function() RunService:UnbindFromRenderStep(DISPATCH_BIND) end)
    restoreHook()
    pendingDelta = Vector2.zero

    if gui then
        pcall(function() gui:Destroy() end)
        gui = nil
    end

    if type(baseCleanup) == "function" then
        pcall(baseCleanup)
    end

    ENV.PCBuracoNativeMouseV11 = nil
    ENV.__PCBuracoNativeMouseV11Cleanup = nil
end

warn(string.format(
    "[%s] ready | route=%s | no Camera/Root CFrame writes",
    VERSION,
    lastRoute
))
