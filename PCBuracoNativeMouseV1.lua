-- PCBuracoNativeMouseV1.lua
-- Practical camera build for Evade Legacy mobile.
--
-- Architecture:
--   physical right-side Touch -> preserve BaseCamera touch bookkeeping
--   -> suppress only native Touch pan contribution
--   -> batch that real Touch delta to the next camera frame
--   -> send a REAL engine MouseMovement delta through VirtualInputManager
--   -> Roblox/Legacy native mouse camera path consumes it
--
-- This intentionally does NOT reconstruct the Buraco visually and does NOT
-- write Camera.CFrame, Camera.Focus, RootPart.CFrame, Humanoid.AutoRotate,
-- FOV, zoom, mouse-lock offset, RotationType or MouseBehavior.
--
-- It boots the already-approved PC movement/joystick V5.9 first.
--
-- Evidence-backed default gains:
--   Touch X ~= 1.7010067 deg / touch-pixel
--   Touch Y ~= 0.6075052 deg / touch-pixel
--   Legacy mouse X ~= 0.375 deg / mouse-delta
--   Legacy mouse Y ~= 0.285 deg / mouse-delta
-- Therefore:
--   X gain ~= 4.53601795
--   Y gain ~= 2.13159726
-- These preserve the current native Touch angular scale while changing the
-- input semantic + timing path to MouseMovement. No smoothing is added.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local VERSION = "PC-BURACO-NATIVE-MOUSE-V1"
local WATCH_BIND = "__PCBuracoNativeMouseV1_Watch"
local DISPATCH_BIND = "__PCBuracoNativeMouseV1_Dispatch"
local DOT_GUI = "__PCBuracoNativeMouseV1_Dot"

if type(ENV.__PCBuracoNativeMouseV1Cleanup) == "function" then
    pcall(ENV.__PCBuracoNativeMouseV1Cleanup)
end

-- Approved movement/joystick base.
do
    local url = "https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/PCModeLockV5_9.lua?_cb="
        .. HttpService:GenerateGUID(false)
    local source = game:HttpGet(url, true)
    local chunk, err = loadstring(source)
    if not chunk then error(err) end
    chunk()
end

local baseCleanup = ENV.__PCModeLockCleanup

local GAIN_X = tonumber(ENV.PCBuracoMouseGainX) or 4.536017948763518
local GAIN_Y = tonumber(ENV.PCBuracoMouseGainY) or 2.131597261871922
local RIGHT_SPLIT = tonumber(ENV.PCBuracoCameraSplit) or 0.50
local DOT_ENABLED = ENV.PCBuracoDot ~= false

local playerModule
local cameras
local activeController
local installedHook
local installedController
local installedMouseTarget
local pendingDelta = Vector2.zero

local engineRelativeRoute = true
local engineRelativeFailures = 0
local engineRelativeDispatches = 0
local directMouseDispatches = 0
local cameraTouchPackets = 0
local cameraTouchPixels = Vector2.zero
local touchBookkeepingPasses = 0
local nativeFallbackPackets = 0
local hookInstalls = 0
local hookFailures = 0
local controllerChanges = 0
local lastRoute = "initializing"
local lastError = nil
local gui = nil

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok then return value end
    return fallback
end

local function inputType(input)
    return safe(function() return input.UserInputType end, nil)
end

local function inputDelta(input)
    local d = safe(function() return input.Delta end, nil)
    if typeof(d) == "Vector3" then
        return Vector2.new(d.X, d.Y)
    elseif typeof(d) == "Vector2" then
        return d
    end
    return nil
end

local function inputX(input)
    return safe(function() return input.Position.X end, nil)
end

local function viewportWidth()
    local cam = workspace.CurrentCamera
    return cam and cam.ViewportSize.X or 1125
end

local function rightSide(input)
    local x = inputX(input)
    return type(x) == "number" and x > viewportWidth() * RIGHT_SPLIT
end

local function getPlayerModule()
    if type(playerModule) == "table" then return playerModule end
    local scripts = player:FindFirstChild("PlayerScripts")
    local moduleScript = scripts and scripts:FindFirstChild("PlayerModule")
    if not moduleScript then return nil end
    playerModule = safe(function() return require(moduleScript) end, nil)
    return type(playerModule) == "table" and playerModule or nil
end

local function getCameras()
    if type(cameras) == "table" then return cameras end
    local pm = getPlayerModule()
    if type(pm) ~= "table" then return nil end
    cameras = safe(function()
        if type(pm.GetCameras) == "function" then
            return pm:GetCameras()
        end
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

local function getMeta(tbl)
    local mt
    if type(getrawmetatable) == "function" then
        pcall(function() mt = getrawmetatable(tbl) end)
    end
    if type(mt) ~= "table" then
        pcall(function() mt = getmetatable(tbl) end)
    end
    return type(mt) == "table" and mt or nil
end

local function findMethod(root, name)
    local seen = {}
    local function visit(tbl, depth)
        if type(tbl) ~= "table" or depth > 14 or seen[tbl] then return nil end
        seen[tbl] = true

        local fn = safe(function() return rawget(tbl, name) end, nil)
        if type(fn) == "function" then
            return {fn = fn, owner = tbl, name = name}
        end

        local index = safe(function() return rawget(tbl, "__index") end, nil)
        if type(index) == "table" then
            local found = visit(index, depth + 1)
            if found then return found end
        end

        local mt = getMeta(tbl)
        if mt then
            local found = visit(mt, depth + 1)
            if found then return found end
        end
        return nil
    end
    return visit(root, 0)
end

local function restoreHook()
    local h = installedHook
    installedHook = nil
    installedController = nil
    installedMouseTarget = nil

    if not h then return end
    if h.mode == "hookfunction" and type(hookfunction) == "function" then
        pcall(function() hookfunction(h.target, h.original) end)
    elseif h.mode == "rawset" and type(h.owner) == "table" and type(h.original) == "function" then
        pcall(function() rawset(h.owner, h.name, h.original) end)
    end
end

local function cameraTouchProved(controller, input)
    if type(controller) ~= "table" then return false, nil end

    local fingerTouches = rawget(controller, "fingerTouches")
    local mapped = nil
    if type(fingerTouches) == "table" then
        mapped = safe(function() return rawget(fingerTouches, input) end, nil)
    end

    local unsunk = rawget(controller, "numUnsunkTouches")
    local camera = type(fingerTouches) == "table" and mapped == false
    return camera, unsunk
end

local function returnPacked(p)
    if not p[1] then error(p[2], 0) end
    return table.unpack(p, 2, p.n)
end

local function buildMouseProxy(dx, dy)
    local center = Vector2.zero
    local cam = workspace.CurrentCamera
    if cam then center = cam.ViewportSize * 0.5 end
    return {
        UserInputType = Enum.UserInputType.MouseMovement,
        UserInputState = Enum.UserInputState.Change,
        KeyCode = Enum.KeyCode.Unknown,
        Delta = Vector3.new(dx, dy, 0),
        Position = Vector3.new(center.X, center.Y, 0),
    }
end

local function installForController(controller)
    restoreHook()

    if type(controller) ~= "table" then
        lastRoute = "waiting-active-camera-controller"
        return false
    end

    local onInputChanged = findMethod(controller, "OnInputChanged")
    local onMouseMoved = findMethod(controller, "OnMouseMoved")
    if not onInputChanged then
        hookFailures += 1
        lastRoute = "OnInputChanged-missing"
        return false
    end

    installedMouseTarget = onMouseMoved
    local original

    local function replacement(self, input, processed, ...)
        if self ~= getActiveController()
            or inputType(input) ~= Enum.UserInputType.Touch
            or not rightSide(input) then
            return original(self, input, processed, ...)
        end

        local cameraTouch, unsunk = cameraTouchProved(self, input)
        if not cameraTouch or (type(unsunk) == "number" and unsunk ~= 1) then
            nativeFallbackPackets += 1
            return original(self, input, processed, ...)
        end

        local d = inputDelta(input)
        if not d or d.Magnitude <= 1e-7 then
            return original(self, input, processed, ...)
        end

        -- Preserve all Touch lifecycle/bookkeeping while removing only the
        -- native one-finger pan contribution. This is the V604-proven stage.
        local previousPan = rawget(self, "panEnabled")
        if previousPan == nil then
            nativeFallbackPackets += 1
            return original(self, input, processed, ...)
        end

        self.panEnabled = false
        local results = table.pack(pcall(original, self, input, processed, ...))
        self.panEnabled = previousPan

        if not results[1] then
            lastError = tostring(results[2])
            return returnPacked(results)
        end

        touchBookkeepingPasses += 1
        cameraTouchPackets += 1
        cameraTouchPixels += d
        pendingDelta += d

        return table.unpack(results, 2, results.n)
    end

    if type(hookfunction) == "function" then
        local ok, old = pcall(function()
            local repl
            repl = function(...)
                return replacement(...)
            end
            return hookfunction(onInputChanged.fn, repl)
        end)
        if ok and type(old) == "function" then
            original = old
            installedHook = {
                mode = "hookfunction",
                target = onInputChanged.fn,
                original = old,
            }
            installedController = controller
            hookInstalls += 1
            lastRoute = "hooked-touch->engine-mouse-delta"
            return true
        end
    end

    local previous = safe(function() return rawget(onInputChanged.owner, onInputChanged.name) end, nil)
    if type(previous) == "function" then
        original = previous
        local ok = pcall(function()
            rawset(onInputChanged.owner, onInputChanged.name, replacement)
        end)
        if ok then
            installedHook = {
                mode = "rawset",
                owner = onInputChanged.owner,
                name = onInputChanged.name,
                original = previous,
            }
            installedController = controller
            hookInstalls += 1
            lastRoute = "raw-hook-touch->engine-mouse-delta"
            return true
        end
    end

    hookFailures += 1
    lastRoute = "camera-hook-failed"
    return false
end

local function sendEngineMouseDelta(dx, dy)
    if not engineRelativeRoute then return false end

    local send = safe(function() return VirtualInputManager.SendMouseMoveDeltaEvent end, nil)
    if type(send) ~= "function" then
        engineRelativeRoute = false
        lastRoute = "engine-relative-method-unavailable"
        return false
    end

    local collectors = {game, CoreGui, player:FindFirstChildOfClass("PlayerGui")}
    for _, collector in ipairs(collectors) do
        if collector then
            local ok = pcall(function()
                VirtualInputManager:SendMouseMoveDeltaEvent(dx, dy, collector)
            end)
            if ok then
                engineRelativeDispatches += 1
                lastRoute = "engine-relative-MouseMovement"
                return true
            end
        end
    end

    engineRelativeFailures += 1
    if engineRelativeFailures >= 2 then
        engineRelativeRoute = false
        lastRoute = "engine-relative-failed->direct-frame-mouse"
    end
    return false
end

local function sendDirectMouseDelta(dx, dy)
    local controller = getActiveController()
    if type(controller) ~= "table" then return false end

    local target = installedMouseTarget
    if not target or installedController ~= controller then
        target = findMethod(controller, "OnMouseMoved")
        installedMouseTarget = target
    end
    if not target or type(target.fn) ~= "function" then
        lastRoute = "direct-OnMouseMoved-missing"
        return false
    end

    local proxy = buildMouseProxy(dx, dy)
    local ok, err = pcall(function()
        target.fn(controller, proxy)
    end)
    if ok then
        directMouseDispatches += 1
        lastRoute = "frame-batched-direct-OnMouseMoved"
        return true
    end

    lastError = tostring(err)
    lastRoute = "direct-OnMouseMoved-error"
    return false
end

local function dispatchPending()
    if pendingDelta.Magnitude <= 1e-7 then return end

    local d = pendingDelta
    pendingDelta = Vector2.zero

    local dx = d.X * GAIN_X
    local dy = d.Y * GAIN_Y

    -- Preferred path: a genuine engine-level relative MouseMovement packet.
    -- Fallback: still frame-batched, but calls the proven Legacy OnMouseMoved
    -- stage directly if the executor blocks the hidden VIM method.
    if not sendEngineMouseDelta(dx, dy) then
        sendDirectMouseDelta(dx, dy)
    end
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
    installForController(activeController)
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

-- Feed the accumulated physical Touch delta immediately before Roblox's camera
-- update. This removes the old synchronous Touch-callback relay timing.
RunService:BindToRenderStep(DISPATCH_BIND, Enum.RenderPriority.Camera.Value - 10, dispatchPending)

makeDot()

ENV.PCBuracoNativeMouseV1 = {
    Version = VERSION,
    GetState = function()
        return {
            version = VERSION,
            gainX = GAIN_X,
            gainY = GAIN_Y,
            rightSplit = RIGHT_SPLIT,
            engineRelativeRoute = engineRelativeRoute,
            engineRelativeFailures = engineRelativeFailures,
            engineRelativeDispatches = engineRelativeDispatches,
            directMouseDispatches = directMouseDispatches,
            cameraTouchPackets = cameraTouchPackets,
            cameraTouchPixels = cameraTouchPixels,
            touchBookkeepingPasses = touchBookkeepingPasses,
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

ENV.__PCBuracoNativeMouseV1Cleanup = function()
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

    ENV.PCBuracoNativeMouseV1 = nil
    ENV.__PCBuracoNativeMouseV1Cleanup = nil
end

warn(string.format(
    "[%s] ready | route=%s | gain=(%.6f, %.6f) | no Camera/Root CFrame writes",
    VERSION, lastRoute, GAIN_X, GAIN_Y
))
