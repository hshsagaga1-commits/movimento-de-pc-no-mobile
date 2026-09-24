-- GamepadBuracoX9.lua
-- Read-only A/B forensic probe for Evade Legacy on iPhone/Delta.
-- Goal: observe what changes when Roblox switches Touch <-> Gamepad and correlate
-- that transition with the native "Buraco" camera composition.
--
-- IMPORTANT: this script does NOT write Camera.CFrame/Focus, RootPart.CFrame,
-- MouseBehavior, RotationType, PreferredInput, camera offsets, FOV, zoom, physics,
-- or character state. It only observes and reports.
--
-- Test:
--   1) Start on TOUCH and move/look around ~5 s.
--   2) Use the physical controller ~5 s.
--   3) Touch the screen again ~5 s.
--   4) STOP + COPY and paste the report back into ChatGPT.
-- The controller may remain connected the entire time.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local CoreGui = game:GetService("CoreGui")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local VERSION = "GAMEPAD-BURACO-X9-R1"
local UI_NAME = "__GamepadBuracoX9"
local BIND_PRE = "__GamepadBuracoX9_Pre"
local BIND_POST = "__GamepadBuracoX9_Post"

local MAX_SECONDS = math.clamp(tonumber(ENV.GamepadBuracoX9MaxSeconds) or 35, 15, 90)
local SAMPLE_HZ = math.clamp(tonumber(ENV.GamepadBuracoX9Hz) or 30, 10, 60)
local TIMELINE_HZ = math.clamp(tonumber(ENV.GamepadBuracoX9TimelineHz) or 5, 2, 15)
local SAMPLE_DT = 1 / SAMPLE_HZ
local TIMELINE_DT = 1 / TIMELINE_HZ

if type(ENV.__GamepadBuracoX9Cleanup) == "function" then
    pcall(ENV.__GamepadBuracoX9Cleanup)
end

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok then return value end
    return fallback
end

local UGS = safe(function() return UserSettings():GetService("UserGameSettings") end, nil)

local function str(v)
    if v == nil then return "nil" end
    local tv = typeof(v)
    if tv == "Vector2" then
        return string.format("(%.4f,%.4f)", v.X, v.Y)
    elseif tv == "Vector3" then
        return string.format("(%.4f,%.4f,%.4f)", v.X, v.Y, v.Z)
    elseif tv == "CFrame" then
        local p = v.Position
        return string.format("CFrame(%.4f,%.4f,%.4f)", p.X, p.Y, p.Z)
    elseif tv == "Instance" then
        return safe(function() return v:GetFullName() .. "<" .. v.ClassName .. ">" end, tostring(v))
    end
    return tostring(v)
end

local function round(n, d)
    if type(n) ~= "number" then return n end
    local p = 10 ^ (d or 5)
    return math.floor(n * p + (n >= 0 and 0.5 or -0.5)) / p
end

local function has(s, needle)
    return string.find(string.lower(tostring(s)), string.lower(needle), 1, true) ~= nil
end

local function sourceOf(fn)
    if type(fn) ~= "function" then return "nil" end
    if debug and type(debug.info) == "function" then
        return safe(function()
            local src = debug.info(fn, "s")
            local name = debug.info(fn, "n")
            return tostring(src or "?") .. "::" .. tostring(name or "?")
        end, "?")
    end
    if debug and type(debug.getinfo) == "function" then
        return safe(function()
            local i = debug.getinfo(fn)
            return tostring(i and (i.source or i.short_src) or "?") .. "::" .. tostring(i and i.name or "?")
        end, "?")
    end
    return "debug-unavailable"
end

local function inputClass()
    local preferred = safe(function() return UIS.PreferredInput end, nil)
    local ps = tostring(preferred)
    if has(ps, "gamepad") then return "GAMEPAD", ps end
    if has(ps, "touch") then return "TOUCH", ps end
    if has(ps, "keyboard") or has(ps, "mouse") then return "MOUSEKEY", ps end

    local last = safe(function() return UIS:GetLastInputType() end, nil)
    local ls = tostring(last)
    if has(ls, "gamepad") then return "GAMEPAD", ps end
    if has(ls, "touch") then return "TOUCH", ps end
    if has(ls, "keyboard") or has(ls, "mouse") then return "MOUSEKEY", ps end
    return "OTHER", ps
end

local pmCache = {instance=nil, module=nil, cameras=nil, controls=nil}
local function getPlayerModuleState()
    local playerScripts = player and player:FindFirstChild("PlayerScripts")
    local pm = playerScripts and playerScripts:FindFirstChild("PlayerModule")
    if not pm then return nil, nil, nil, nil end

    if pmCache.instance ~= pm or type(pmCache.module) ~= "table" then
        pmCache.instance = pm
        pmCache.module = safe(function() return require(pm) end, nil)
        pmCache.cameras = nil
        pmCache.controls = nil
    end

    local module = pmCache.module
    if type(module) ~= "table" then return module, nil, nil, nil end

    if type(pmCache.cameras) ~= "table" then
        pmCache.cameras = safe(function()
            if type(module.GetCameras) == "function" then return module:GetCameras() end
            return rawget(module, "cameras")
        end, rawget(module, "cameras"))
    end

    if type(pmCache.controls) ~= "table" then
        pmCache.controls = safe(function()
            if type(module.GetControls) == "function" then return module:GetControls() end
            return rawget(module, "controls")
        end, rawget(module, "controls"))
    end

    local cameras = pmCache.cameras
    local controls = pmCache.controls
    local cameraController = nil
    if type(cameras) == "table" then
        cameraController = rawget(cameras, "activeCameraController")
        if cameraController == nil and type(cameras.GetActiveCameraController) == "function" then
            cameraController = safe(function() return cameras:GetActiveCameraController() end, nil)
        end
    end

    return module, cameras, controls, cameraController
end

local interestingNeedles = {
    "camera","input","mouse","touch","gamepad","lock","offset","rotate","rotation",
    "subject","distance","first","person","mode","pan","controller","enabled","active",
    "zoom","focus","shift","yaw","pitch","movement"
}

local function interestingKey(k)
    local s = string.lower(tostring(k))
    for _, n in ipairs(interestingNeedles) do
        if string.find(s, n, 1, true) then return true end
    end
    return false
end

local function scalarDigest(t, maxItems)
    if type(t) ~= "table" then return "not-table" end
    local items = {}
    for k, v in pairs(t) do
        if interestingKey(k) then
            local tv = typeof(v)
            local vv = nil
            if type(v) == "boolean" or type(v) == "string" then
                vv = tostring(v)
            elseif type(v) == "number" then
                vv = tostring(round(v, 5))
            elseif tv == "EnumItem" or tv == "Vector2" or tv == "Vector3" then
                vv = str(v)
            elseif tv == "Instance" then
                vv = safe(function() return v.Name .. "<" .. v.ClassName .. ">" end, tostring(v))
            elseif type(v) == "function" then
                vv = "fn:" .. sourceOf(v)
            end
            if vv ~= nil then
                items[#items + 1] = tostring(k) .. "=" .. vv
            end
        end
    end
    table.sort(items)
    local limit = math.min(#items, maxItems or 36)
    local out = {}
    for i = 1, limit do out[#out + 1] = items[i] end
    if #items > limit then out[#out + 1] = "...+" .. tostring(#items - limit) end
    return table.concat(out, " | ")
end

local function getCameraModuleLockState(cameras, controller)
    local result = {}
    if type(cameras) == "table" then
        if type(cameras.GetIsMouseLocked) == "function" then
            result.moduleLocked = safe(function() return cameras:GetIsMouseLocked() end, nil)
        end
        if type(cameras.GetMouseLockOffset) == "function" then
            result.moduleOffset = safe(function() return cameras:GetMouseLockOffset() end, nil)
        end
    end
    if type(controller) == "table" then
        if type(controller.GetIsMouseLocked) == "function" then
            result.controllerLockedMethod = safe(function() return controller:GetIsMouseLocked() end, nil)
        end
        if type(controller.GetMouseLockOffset) == "function" then
            result.controllerOffsetMethod = safe(function() return controller:GetMouseLockOffset() end, nil)
        end
    end
    return result
end

local function getControlController(controls)
    if type(controls) ~= "table" then return nil end
    local c = rawget(controls, "activeController")
    if c ~= nil then return c end
    return safe(function()
        if type(controls.GetActiveController) == "function" then return controls:GetActiveController() end
        return nil
    end, nil)
end

local function captureState(includeDigests)
    local _, cameras, controls, controller = getPlayerModuleState()
    local controlController = getControlController(controls)
    local phase, preferredText = inputClass()
    local cam = Workspace.CurrentCamera
    local char = player and player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    local head = char and char:FindFirstChild("Head")
    local lock = getCameraModuleLockState(cameras, controller)

    local ugs = UGS

    local s = {
        phase = phase,
        preferredInput = preferredText,
        lastInputType = str(safe(function() return UIS:GetLastInputType() end, nil)),
        gamepadEnabled = safe(function() return UIS.GamepadEnabled end, nil),
        touchEnabled = safe(function() return UIS.TouchEnabled end, nil),
        mouseEnabled = safe(function() return UIS.MouseEnabled end, nil),
        keyboardEnabled = safe(function() return UIS.KeyboardEnabled end, nil),
        mouseBehavior = str(safe(function() return UIS.MouseBehavior end, nil)),
        connectedGamepads = safe(function()
            local t = UIS:GetConnectedGamepads()
            return type(t) == "table" and #t or 0
        end, -1),

        rotationType = ugs and str(safe(function() return ugs.RotationType end, nil)) or "nil",
        touchCameraMovementMode = ugs and str(safe(function() return ugs.TouchCameraMovementMode end, nil)) or "nil",
        computerCameraMovementMode = ugs and str(safe(function() return ugs.ComputerCameraMovementMode end, nil)) or "nil",

        playerCameraMode = str(safe(function() return player.CameraMode end, nil)),
        cameraType = cam and str(safe(function() return cam.CameraType end, nil)) or "nil",
        cameraSubject = cam and str(safe(function() return cam.CameraSubject end, nil)) or "nil",
        fov = cam and round(safe(function() return cam.FieldOfView end, nil), 4) or nil,

        cameraControllerId = tostring(controller),
        cameraControllerUpdate = type(controller) == "table" and sourceOf(rawget(controller, "Update")) or "nil",
        controller_inMouseLockedMode = type(controller) == "table" and rawget(controller, "inMouseLockedMode") or nil,
        controller_mouseLockOffset = type(controller) == "table" and rawget(controller, "mouseLockOffset") or nil,
        controller_cameraMovementMode = type(controller) == "table" and rawget(controller, "cameraMovementMode") or nil,
        controller_currentSubjectDistance = type(controller) == "table" and round(rawget(controller, "currentSubjectDistance"), 4) or nil,
        controller_panEnabled = type(controller) == "table" and rawget(controller, "panEnabled") or nil,
        controller_rotateInput = type(controller) == "table" and rawget(controller, "rotateInput") or nil,

        moduleLocked = lock.moduleLocked,
        moduleOffset = lock.moduleOffset,
        controllerLockedMethod = lock.controllerLockedMethod,
        controllerOffsetMethod = lock.controllerOffsetMethod,

        controlControllerId = tostring(controlController),
        controlControllerUpdate = type(controlController) == "table" and sourceOf(rawget(controlController, "Update")) or "nil",
        controlControllerEnabled = type(controlController) == "table" and rawget(controlController, "enabled") or nil,

        humanoidState = hum and str(safe(function() return hum:GetState() end, nil)) or "nil",
    }

    if cam then
        s.viewport = str(cam.ViewportSize)
        s.cameraCFrame = cam.CFrame
        s.cameraFocus = cam.Focus
        local rx, ry, rz = cam.CFrame:ToOrientation()
        s.cameraPitchDeg = round(math.deg(rx), 4)
        s.cameraYawDeg = round(math.deg(ry), 4)
        s.cameraRollDeg = round(math.deg(rz), 4)
    end

    if root and cam then
        local lp = cam.CFrame:PointToObjectSpace(root.Position)
        local sp, onScreen = cam:WorldToViewportPoint(root.Position)
        s.rootLocal = lp
        s.rootLocalX = round(lp.X, 6)
        s.rootLocalY = round(lp.Y, 6)
        s.rootLocalZ = round(lp.Z, 6)
        s.rootScreenXNorm = cam.ViewportSize.X > 0 and round(sp.X / cam.ViewportSize.X, 7) or nil
        s.rootScreenYNorm = cam.ViewportSize.Y > 0 and round(sp.Y / cam.ViewportSize.Y, 7) or nil
        s.rootScreenDX = s.rootScreenXNorm and round(s.rootScreenXNorm - 0.5, 7) or nil
        s.rootOnScreen = onScreen
        local _, rY = root.CFrame:ToOrientation()
        s.rootYawDeg = round(math.deg(rY), 4)
        if s.cameraYawDeg and s.rootYawDeg then
            local d = s.rootYawDeg - s.cameraYawDeg
            while d > 180 do d = d - 360 end
            while d < -180 do d = d + 360 end
            s.rootMinusCameraYawDeg = round(d, 4)
        end
    end

    if head and cam then
        local hp = cam.CFrame:PointToObjectSpace(head.Position)
        local sp = cam:WorldToViewportPoint(head.Position)
        s.headLocalX = round(hp.X, 6)
        s.headLocalY = round(hp.Y, 6)
        s.headLocalZ = round(hp.Z, 6)
        s.headScreenXNorm = cam.ViewportSize.X > 0 and round(sp.X / cam.ViewportSize.X, 7) or nil
        s.headScreenDX = s.headScreenXNorm and round(s.headScreenXNorm - 0.5, 7) or nil
    end

    if cam then
        local fp = cam.CFrame:PointToObjectSpace(cam.Focus.Position)
        s.focusLocalX = round(fp.X, 6)
        s.focusLocalY = round(fp.Y, 6)
        s.focusLocalZ = round(fp.Z, 6)
    end

    if type(controller) == "table" and type(controller.GetSubjectPosition) == "function" then
        local subjectPos = safe(function() return controller:GetSubjectPosition() end, nil)
        if typeof(subjectPos) == "Vector3" and cam then
            local sl = cam.CFrame:PointToObjectSpace(subjectPos)
            s.subjectLocalX = round(sl.X, 6)
            s.subjectLocalY = round(sl.Y, 6)
            s.subjectLocalZ = round(sl.Z, 6)
        end
    end

    if includeDigests then
        s.cameraControllerDigest = scalarDigest(controller, 48)
        s.camerasDigest = scalarDigest(cameras, 36)
        s.controlsDigest = scalarDigest(controls, 36)
        s.controlControllerDigest = scalarDigest(controlController, 36)
    end

    return s
end

local compactKeys = {
    "phase","preferredInput","lastInputType","connectedGamepads",
    "mouseBehavior","rotationType","touchCameraMovementMode","computerCameraMovementMode",
    "playerCameraMode","cameraType","cameraSubject",
    "cameraControllerId","cameraControllerUpdate",
    "controller_inMouseLockedMode","controller_mouseLockOffset","controller_cameraMovementMode",
    "moduleLocked","moduleOffset","controllerLockedMethod","controllerOffsetMethod",
    "controlControllerId","controlControllerUpdate","controlControllerEnabled",
    "rootLocalX","rootScreenDX","headLocalX","headScreenDX",
    "rootMinusCameraYawDeg","cameraYawDeg","cameraPitchDeg","focusLocalX","focusLocalY","focusLocalZ"
}

local function compactState(s)
    local out = {}
    for _, k in ipairs(compactKeys) do
        out[#out + 1] = k .. "=" .. str(s[k])
    end
    return table.concat(out, " | ")
end

local function stateDiff(a, b)
    if not a or not b then return "missing-state" end
    local out = {}
    for _, k in ipairs(compactKeys) do
        local av = str(a[k])
        local bv = str(b[k])
        if av ~= bv then
            out[#out + 1] = k .. ":" .. av .. "->" .. bv
        end
    end
    return #out > 0 and table.concat(out, " | ") or "NO_CHANGE"
end

local statFields = {
    "rootLocalX","rootLocalY","rootLocalZ","rootScreenDX",
    "headLocalX","headLocalY","headLocalZ","headScreenDX",
    "rootMinusCameraYawDeg","controller_currentSubjectDistance",
    "cameraPitchDeg","cameraYawDeg","focusLocalX","focusLocalY","focusLocalZ",
    "subjectLocalX","subjectLocalY","subjectLocalZ",
    "cameraUpdateYawDeltaDeg","cameraUpdatePitchDeltaDeg",
    "cameraUpdateRootLocalXDelta","cameraUpdateRootScreenDXDelta",
    "cameraUpdateHeadLocalXDelta","cameraUpdateHeadScreenDXDelta"
}

local function newStat()
    return {n = 0, sum = 0, sum2 = 0, min = math.huge, max = -math.huge}
end

local function pushStat(st, v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return end
    st.n = st.n + 1
    st.sum = st.sum + v
    st.sum2 = st.sum2 + v * v
    if v < st.min then st.min = v end
    if v > st.max then st.max = v end
end

local function statText(st)
    if not st or st.n == 0 then return "n=0" end
    local mean = st.sum / st.n
    local var = math.max(0, st.sum2 / st.n - mean * mean)
    return string.format("n=%d mean=%.7f sd=%.7f min=%.7f max=%.7f", st.n, mean, math.sqrt(var), st.min, st.max)
end

local reportData = nil
local captureRunning = false
local captureStart = 0
local currentPhase = nil
local lastState = nil
local frameIndex = 0
local lastSampleAt = -math.huge
local lastTimelineAt = -math.huge
local pendingTransitions = {}
local uiConnections = {}
local eventConnections = {}
local gui = nil
local statusLabel = nil
local phaseLabel = nil
local copyButton = nil
local preStateFrame = nil

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 4,
        })
    end)
end

local function event(kind, detail)
    if not captureRunning or not reportData then return end
    local t = os.clock() - captureStart
    if #reportData.events < 220 then
        reportData.events[#reportData.events + 1] = string.format("t=%.4f frame=%d %s %s", t, frameIndex, kind, detail or "")
    end
end

local function notePhaseInput(phase, inputType)
    if not reportData then return end
    local p = reportData.inputCounts[phase]
    if not p then
        p = {Touch = 0, Gamepad = 0, MouseKey = 0, Other = 0}
        reportData.inputCounts[phase] = p
    end
    local s = tostring(inputType)
    if has(s, "touch") then p.Touch = p.Touch + 1
    elseif has(s, "gamepad") then p.Gamepad = p.Gamepad + 1
    elseif has(s, "mouse") or has(s, "keyboard") then p.MouseKey = p.MouseKey + 1
    else p.Other = p.Other + 1 end
end

local function addPhaseStats(phase, s)
    if not reportData then return end
    local phaseStats = reportData.stats[phase]
    if not phaseStats then
        phaseStats = {}
        for _, k in ipairs(statFields) do phaseStats[k] = newStat() end
        reportData.stats[phase] = phaseStats
    end
    for _, k in ipairs(statFields) do pushStat(phaseStats[k], s[k]) end

    reportData.phaseFrames[phase] = (reportData.phaseFrames[phase] or 0) + 1
end

local function scheduleTransition(fromPhase, toPhase, preState, immediateState)
    local tr = {
        id = #reportData.transitions + 1,
        from = fromPhase,
        to = toPhase,
        startedAt = os.clock() - captureStart,
        startFrame = frameIndex,
        states = {
            ["pre"] = preState,
            ["0"] = immediateState,
        },
        offsets = {1, 2, 4, 8},
    }
    reportData.transitions[#reportData.transitions + 1] = tr
    pendingTransitions[#pendingTransitions + 1] = tr
    event("PHASE_CHANGE", tostring(fromPhase) .. "->" .. tostring(toPhase))
end

local function updatePendingTransitions(s)
    if #pendingTransitions == 0 then return end
    for i = #pendingTransitions, 1, -1 do
        local tr = pendingTransitions[i]
        local age = frameIndex - tr.startFrame
        for _, off in ipairs(tr.offsets) do
            local key = tostring(off)
            if age >= off and tr.states[key] == nil then
                tr.states[key] = (off == 8) and captureState(true) or s
            end
        end
        if age >= 8 then
            table.remove(pendingTransitions, i)
        end
    end
end

local function connectionMap(signal, name)
    if type(getconnections) ~= "function" then return {name .. ": getconnections unavailable"} end
    local list = safe(function() return getconnections(signal) end, nil)
    if type(list) ~= "table" then return {name .. ": unavailable"} end
    local out = {name .. ".count=" .. tostring(#list)}
    local limit = math.min(#list, 24)
    for i = 1, limit do
        local c = list[i]
        local fn = nil
        if type(c) == "table" or typeof(c) == "userdata" then
            fn = safe(function() return c.Function end, nil)
        end
        out[#out + 1] = string.format("%s[%d]=%s", name, i, sourceOf(fn))
    end
    return out
end

local function buildStaticMap()
    local lines = {}
    local function append(t)
        for _, v in ipairs(t) do lines[#lines + 1] = v end
    end
    append(connectionMap(UIS.LastInputTypeChanged, "UIS.LastInputTypeChanged"))
    local prefSignal = safe(function() return UIS:GetPropertyChangedSignal("PreferredInput") end, nil)
    if prefSignal then append(connectionMap(prefSignal, "UIS.PreferredInputChanged")) end
    append(connectionMap(UIS.InputBegan, "UIS.InputBegan"))
    append(connectionMap(UIS.InputChanged, "UIS.InputChanged"))
    local gp = safe(function() return UIS.GamepadConnected end, nil)
    if gp then append(connectionMap(gp, "UIS.GamepadConnected")) end
    return lines
end

local function startCapture()
    if captureRunning then return end

    reportData = {
        version = VERSION,
        startedWall = os.date("%Y-%m-%d %H:%M:%S"),
        placeId = game.PlaceId,
        gameId = game.GameId,
        maxSeconds = MAX_SECONDS,
        sampleHz = SAMPLE_HZ,
        timelineHz = TIMELINE_HZ,
        events = {},
        transitions = {},
        timeline = {},
        stats = {},
        phaseFrames = {},
        inputCounts = {},
        staticMap = buildStaticMap(),
        startState = nil,
        stopState = nil,
    }

    captureStart = os.clock()
    captureRunning = true
    frameIndex = 0
    lastSampleAt = -math.huge
    lastTimelineAt = -math.huge
    pendingTransitions = {}

    local s = captureState(true)
    currentPhase = s.phase
    lastState = s
    reportData.startState = s
    reportData.phaseDigests = {
        ["START_" .. tostring(currentPhase)] = {
            compact = compactState(s),
            cameraControllerDigest = s.cameraControllerDigest,
            camerasDigest = s.camerasDigest,
            controlsDigest = s.controlsDigest,
            controlControllerDigest = s.controlControllerDigest,
        }
    }

    event("START", "phase=" .. tostring(currentPhase))

    if statusLabel then
        statusLabel.Text = "GRAVANDO • Touch ~5s → controle ~5s → Touch ~5s"
    end
    notify("Buraco X9", "Gravando A/B. Touch → controle → Touch.", 4)

    task.spawn(function()
        local myStart = captureStart
        task.wait(MAX_SECONDS)
        if captureRunning and captureStart == myStart then
            if ENV.GamepadBuracoX9Stop then pcall(ENV.GamepadBuracoX9Stop, true) end
        end
    end)
end

local function stopCapture(autoStop)
    if not captureRunning then return ENV.GamepadBuracoX9Report and ENV.GamepadBuracoX9Report() or "" end

    local s = captureState(true)
    reportData.stopState = s
    event("STOP", "phase=" .. tostring(s.phase) .. (autoStop and " auto=true" or ""))
    reportData.duration = os.clock() - captureStart
    captureRunning = false

    if statusLabel then
        statusLabel.Text = autoStop and "AUTO-STOP • copie o relatório" or "PARADO • copie o relatório"
    end
    if copyButton then copyButton.Text = "COPIAR REPORT" end
    notify("Buraco X9", "Captura concluída. Toque em COPIAR REPORT.", 5)

    return true
end

local function formatReport()
    if not reportData then return "GAMEPAD BURACO X9: nenhuma captura ainda." end

    local lines = {}
    local function add(s) lines[#lines + 1] = tostring(s) end

    add("=== GAMEPAD BURACO X9 REPORT ===")
    add("version = " .. tostring(reportData.version))
    add("startedWall = " .. tostring(reportData.startedWall))
    add("placeId = " .. tostring(reportData.placeId))
    add("gameId = " .. tostring(reportData.gameId))
    add("duration = " .. tostring(round(reportData.duration or (os.clock() - captureStart), 4)))
    add("sampleHz = " .. tostring(reportData.sampleHz))
    add("timelineHz = " .. tostring(reportData.timelineHz))
    add("observationalOnly = true")
    add("writesCameraCFrame = false")
    add("writesCameraFocus = false")
    add("writesRootPartCFrame = false")
    add("forcesPreferredInput = false")
    add("forcesMouseBehavior = false")
    add("forcesRotationType = false")
    add("forcesMouseLock = false")
    add("changesGainSensitivityFOVZoomPhysics = false")
    add("")

    add("=== START STATE ===")
    add(compactState(reportData.startState or {}))
    add("")

    add("=== STOP STATE ===")
    add(compactState(reportData.stopState or lastState or {}))
    add("")

    add("=== PHASE COVERAGE ===")
    local phaseNames = {"TOUCH","GAMEPAD","MOUSEKEY","OTHER"}
    for _, phase in ipairs(phaseNames) do
        local frames = reportData.phaseFrames[phase] or 0
        local c = reportData.inputCounts[phase] or {Touch=0,Gamepad=0,MouseKey=0,Other=0}
        add(string.format("%s frames=%d inputEvents{Touch=%d Gamepad=%d MouseKey=%d Other=%d}",
            phase, frames, c.Touch or 0, c.Gamepad or 0, c.MouseKey or 0, c.Other or 0))
    end
    add("")

    add("=== BURACO KINEMATICS BY INPUT PHASE ===")
    for _, phase in ipairs(phaseNames) do
        local st = reportData.stats[phase]
        if st then
            add("[" .. phase .. "]")
            for _, k in ipairs(statFields) do
                add(k .. " = " .. statText(st[k]))
            end
        end
    end
    add("")

    add("=== TOUCH/GAMEPAD TRANSITIONS ===")
    add("transitionCount = " .. tostring(#reportData.transitions))
    for _, tr in ipairs(reportData.transitions) do
        add(string.format("-- transition #%d %s -> %s at t=%.4f frame=%d",
            tr.id, tostring(tr.from), tostring(tr.to), tr.startedAt or -1, tr.startFrame or -1))
        local pre = tr.states.pre
        for _, key in ipairs({"0","1","2","4","8"}) do
            local ss = tr.states[key]
            if ss then
                add("offset+" .. key .. ".diff = " .. stateDiff(pre, ss))
            else
                add("offset+" .. key .. ".diff = missing")
            end
        end
        if tr.states["8"] then
            local ss = tr.states["8"]
            add("offset+8.cameraControllerDigest = " .. tostring(ss.cameraControllerDigest))
            add("offset+8.camerasDigest = " .. tostring(ss.camerasDigest))
            add("offset+8.controlsDigest = " .. tostring(ss.controlsDigest))
            add("offset+8.controlControllerDigest = " .. tostring(ss.controlControllerDigest))
        end
    end
    add("")

    add("=== TIMELINE (5 Hz-ish, final camera geometry) ===")
    for _, line in ipairs(reportData.timeline) do add(line) end
    add("")

    add("=== INPUT / PHASE EVENTS ===")
    for _, line in ipairs(reportData.events) do add(line) end
    add("")

    add("=== STATIC CONNECTION MAP ===")
    for _, line in ipairs(reportData.staticMap) do add(line) end
    add("")

    add("=== START DIGESTS ===")
    if reportData.startState then
        add("cameraController = " .. tostring(reportData.startState.cameraControllerDigest))
        add("cameras = " .. tostring(reportData.startState.camerasDigest))
        add("controls = " .. tostring(reportData.startState.controlsDigest))
        add("controlController = " .. tostring(reportData.startState.controlControllerDigest))
    end
    add("")

    add("=== X9 DECISION TARGET ===")
    add("Question 1: Which internal state changes at the same transition where native Buraco appears?")
    add("Question 2: Does the active movement/control controller swap while camera controller stays same?")
    add("Question 3: Does mouse-lock/offset state change, or does Buraco emerge without a lock-state change?")
    add("Question 4: Are Gamepad camera-local Root/Head relationships stable in a way Touch is not?")
    add("Question 5: Which Gamepad properties can later be reproduced without the physical controller?")
    add("No automatic causal claim is made by this probe.")

    return table.concat(lines, "\n")
end

local function copyReport()
    local report = formatReport()
    local copied = false
    local clipboardFns = {}
    if type(ENV.setclipboard) == "function" then clipboardFns[#clipboardFns + 1] = ENV.setclipboard end
    if type(ENV.toclipboard) == "function" then clipboardFns[#clipboardFns + 1] = ENV.toclipboard end
    if type(setclipboard) == "function" then clipboardFns[#clipboardFns + 1] = setclipboard end
    if type(toclipboard) == "function" then clipboardFns[#clipboardFns + 1] = toclipboard end
    for _, fn in ipairs(clipboardFns) do
        local ok = pcall(fn, report)
        if ok then copied = true break end
    end
    if type(writefile) == "function" then
        pcall(writefile, "GamepadBuracoX9_Report.txt", report)
    end
    if statusLabel then
        statusLabel.Text = copied and "REPORT COPIADO ✓" or "Clipboard indisponível; arquivo tentado"
    end
    notify("Buraco X9", copied and "Relatório copiado." or "Clipboard indisponível; tente o arquivo.", 4)
    return report
end

local function capturePreGeometry()
    local cam = Workspace.CurrentCamera
    if not cam then return nil end

    local s = {}
    local rx, ry = cam.CFrame:ToOrientation()
    s.cameraPitchDeg = round(math.deg(rx), 4)
    s.cameraYawDeg = round(math.deg(ry), 4)

    local char = player and player.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    local head = char and char:FindFirstChild("Head")

    if root then
        local lp = cam.CFrame:PointToObjectSpace(root.Position)
        local sp = cam:WorldToViewportPoint(root.Position)
        s.rootLocalX = round(lp.X, 6)
        s.rootScreenDX = cam.ViewportSize.X > 0 and round(sp.X / cam.ViewportSize.X - 0.5, 7) or nil
    end

    if head then
        local hp = cam.CFrame:PointToObjectSpace(head.Position)
        local sp = cam:WorldToViewportPoint(head.Position)
        s.headLocalX = round(hp.X, 6)
        s.headScreenDX = cam.ViewportSize.X > 0 and round(sp.X / cam.ViewportSize.X - 0.5, 7) or nil
    end

    return s
end

local function angleDeltaDeg(a, b)
    if type(a) ~= "number" or type(b) ~= "number" then return nil end
    local d = a - b
    while d > 180 do d = d - 360 end
    while d < -180 do d = d + 360 end
    return round(d, 6)
end

local function numDelta(a, b)
    if type(a) ~= "number" or type(b) ~= "number" then return nil end
    return round(a - b, 7)
end

local function firstNonNil(a, b)
    if a ~= nil then return a end
    return b
end

local function renderPost()
    if not captureRunning then
        if phaseLabel then
            local p = inputClass()
            phaseLabel.Text = "INPUT ATUAL: " .. tostring(p)
        end
        return
    end

    frameIndex = frameIndex + 1
    local t = os.clock() - captureStart
    local s = captureState(false)

    if preStateFrame then
        s.cameraUpdateYawDeltaDeg = angleDeltaDeg(s.cameraYawDeg, preStateFrame.cameraYawDeg)
        s.cameraUpdatePitchDeltaDeg = angleDeltaDeg(s.cameraPitchDeg, preStateFrame.cameraPitchDeg)
        s.cameraUpdateRootLocalXDelta = numDelta(s.rootLocalX, preStateFrame.rootLocalX)
        s.cameraUpdateRootScreenDXDelta = numDelta(s.rootScreenDX, preStateFrame.rootScreenDX)
        s.cameraUpdateHeadLocalXDelta = numDelta(s.headLocalX, preStateFrame.headLocalX)
        s.cameraUpdateHeadScreenDXDelta = numDelta(s.headScreenDX, preStateFrame.headScreenDX)
    end

    if phaseLabel then phaseLabel.Text = "INPUT ATUAL: " .. tostring(s.phase) end

    if currentPhase ~= s.phase then
        local detailed = captureState(true)
        detailed.cameraUpdateYawDeltaDeg = s.cameraUpdateYawDeltaDeg
        detailed.cameraUpdatePitchDeltaDeg = s.cameraUpdatePitchDeltaDeg
        detailed.cameraUpdateRootLocalXDelta = s.cameraUpdateRootLocalXDelta
        detailed.cameraUpdateRootScreenDXDelta = s.cameraUpdateRootScreenDXDelta
        detailed.cameraUpdateHeadLocalXDelta = s.cameraUpdateHeadLocalXDelta
        detailed.cameraUpdateHeadScreenDXDelta = s.cameraUpdateHeadScreenDXDelta
        scheduleTransition(currentPhase, s.phase, lastState, detailed)
        s = detailed
        currentPhase = s.phase
    end

    updatePendingTransitions(s)

    if t - lastSampleAt >= SAMPLE_DT then
        lastSampleAt = t
        addPhaseStats(s.phase, s)
    end

    if t - lastTimelineAt >= TIMELINE_DT and #reportData.timeline < 240 then
        lastTimelineAt = t
        reportData.timeline[#reportData.timeline + 1] = string.format(
            "t=%.3f f=%d phase=%s pref=%s last=%s camCtrl=%s controlCtrl=%s lock=%s off=%s rootLX=%s rootDX=%s headLX=%s headDX=%s yawRel=%s pitch=%s",
            t,
            frameIndex,
            tostring(s.phase),
            tostring(s.preferredInput),
            tostring(s.lastInputType),
            tostring(s.cameraControllerId),
            tostring(s.controlControllerId),
            str(firstNonNil(s.controller_inMouseLockedMode, s.moduleLocked)),
            str(firstNonNil(s.controller_mouseLockOffset, s.moduleOffset)),
            str(s.rootLocalX),
            str(s.rootScreenDX),
            str(s.headLocalX),
            str(s.headScreenDX),
            str(s.rootMinusCameraYawDeg),
            str(s.cameraPitchDeg)
        )
    end

    lastState = s
end

local function renderPre()
    if captureRunning then
        preStateFrame = capturePreGeometry()
    else
        preStateFrame = nil
    end
end

local function connectEvents()
    local function connect(sig, fn)
        if sig then
            local c = safe(function() return sig:Connect(fn) end, nil)
            if c then eventConnections[#eventConnections + 1] = c end
        end
    end

    connect(UIS.LastInputTypeChanged, function(newType)
        event("LastInputTypeChanged", str(newType) .. " classified=" .. tostring(inputClass()))
    end)

    local prefSignal = safe(function() return UIS:GetPropertyChangedSignal("PreferredInput") end, nil)
    connect(prefSignal, function()
        event("PreferredInputChanged", str(safe(function() return UIS.PreferredInput end, nil)) .. " classified=" .. tostring(inputClass()))
    end)

    connect(safe(function() return UIS.GamepadConnected end, nil), function(gp)
        event("GamepadConnected", str(gp))
    end)

    connect(safe(function() return UIS.GamepadDisconnected end, nil), function(gp)
        event("GamepadDisconnected", str(gp))
    end)

    connect(UIS.InputBegan, function(input, gpe)
        if not captureRunning then return end
        local p = inputClass()
        notePhaseInput(p, input.UserInputType)
        local s = tostring(input.UserInputType)
        if has(s, "gamepad") or has(s, "touch") or has(s, "mouse") or has(s, "keyboard") then
            local key = safe(function() return input.KeyCode end, nil)
            event("InputBegan", s .. " key=" .. str(key) .. " gpe=" .. tostring(gpe))
        end
    end)

    connect(UIS.InputChanged, function(input, gpe)
        if not captureRunning then return end
        local p = inputClass()
        notePhaseInput(p, input.UserInputType)
        local s = tostring(input.UserInputType)
        if has(s, "gamepad") and #reportData.events < 180 then
            local key = safe(function() return input.KeyCode end, nil)
            local pos = safe(function() return input.Position end, nil)
            event("GamepadChanged", s .. " key=" .. str(key) .. " pos=" .. str(pos) .. " gpe=" .. tostring(gpe))
        end
    end)
end

local function makeButton(parent, textValue, order)
    local b = Instance.new("TextButton")
    b.LayoutOrder = order
    b.Size = UDim2.new(1, 0, 0, 38)
    b.BackgroundColor3 = Color3.fromRGB(32, 41, 58)
    b.BorderSizePixel = 0
    b.Text = textValue
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 9)
    c.Parent = b
    return b
end

local function createUI()
    local parent = CoreGui
    if type(gethui) == "function" then
        parent = safe(function() return gethui() end, CoreGui)
    end

    local old = parent and parent:FindFirstChild(UI_NAME)
    if old then pcall(function() old:Destroy() end) end

    gui = Instance.new("ScreenGui")
    gui.Name = UI_NAME
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 1000000
    gui.Parent = parent

    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(308, 255)
    panel.Position = UDim2.new(1, -320, 0.5, -128)
    panel.BackgroundColor3 = Color3.fromRGB(13, 18, 28)
    panel.BackgroundTransparency = 0.03
    panel.BorderSizePixel = 0
    panel.Active = true
    panel.Draggable = true
    panel.Parent = gui

    local pc = Instance.new("UICorner")
    pc.CornerRadius = UDim.new(0, 13)
    pc.Parent = panel

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -48, 0, 30)
    title.Position = UDim2.fromOffset(12, 8)
    title.BackgroundTransparency = 1
    title.Text = "BURACO X9 • GAMEPAD A/B"
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.Parent = panel

    local close = Instance.new("TextButton")
    close.Size = UDim2.fromOffset(30, 30)
    close.Position = UDim2.new(1, -38, 0, 7)
    close.BackgroundColor3 = Color3.fromRGB(45, 54, 70)
    close.BorderSizePixel = 0
    close.Text = "×"
    close.TextColor3 = Color3.new(1,1,1)
    close.TextSize = 18
    close.Font = Enum.Font.GothamBold
    close.Parent = panel
    local cc = Instance.new("UICorner")
    cc.CornerRadius = UDim.new(0, 8)
    cc.Parent = close

    local body = Instance.new("Frame")
    body.Size = UDim2.new(1, -24, 1, -48)
    body.Position = UDim2.fromOffset(12, 42)
    body.BackgroundTransparency = 1
    body.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = body

    local help = Instance.new("TextLabel")
    help.LayoutOrder = 0
    help.Size = UDim2.new(1, 0, 0, 58)
    help.BackgroundColor3 = Color3.fromRGB(23, 30, 43)
    help.BorderSizePixel = 0
    help.Text = "START → Touch ~5s → controle ~5s → Touch ~5s\nPode deixar o controle conectado. Não há correção de câmera."
    help.TextWrapped = true
    help.TextColor3 = Color3.fromRGB(220, 226, 235)
    help.Font = Enum.Font.Gotham
    help.TextSize = 11
    help.Parent = body
    local hc = Instance.new("UICorner")
    hc.CornerRadius = UDim.new(0, 8)
    hc.Parent = help

    phaseLabel = Instance.new("TextLabel")
    phaseLabel.LayoutOrder = 1
    phaseLabel.Size = UDim2.new(1, 0, 0, 24)
    phaseLabel.BackgroundTransparency = 1
    phaseLabel.Text = "INPUT ATUAL: " .. tostring(inputClass())
    phaseLabel.TextColor3 = Color3.fromRGB(160, 210, 255)
    phaseLabel.Font = Enum.Font.GothamBold
    phaseLabel.TextSize = 12
    phaseLabel.Parent = body

    local start = makeButton(body, "INICIAR A/B", 2)
    local stop = makeButton(body, "PARAR", 3)
    copyButton = makeButton(body, "COPIAR REPORT", 4)

    statusLabel = Instance.new("TextLabel")
    statusLabel.LayoutOrder = 5
    statusLabel.Size = UDim2.new(1, 0, 0, 28)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Pronto • probe somente leitura"
    statusLabel.TextWrapped = true
    statusLabel.TextColor3 = Color3.fromRGB(170, 180, 195)
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 10
    statusLabel.Parent = body

    uiConnections[#uiConnections + 1] = start.Activated:Connect(function()
        startCapture()
    end)

    uiConnections[#uiConnections + 1] = stop.Activated:Connect(function()
        stopCapture(false)
    end)

    uiConnections[#uiConnections + 1] = copyButton.Activated:Connect(function()
        if captureRunning then stopCapture(false) end
        copyReport()
    end)

    uiConnections[#uiConnections + 1] = close.Activated:Connect(function()
        if captureRunning then stopCapture(false) end
        if ENV.__GamepadBuracoX9Cleanup then pcall(ENV.__GamepadBuracoX9Cleanup) end
    end)
end

ENV.GamepadBuracoX9Start = startCapture
ENV.GamepadBuracoX9Stop = stopCapture
ENV.GamepadBuracoX9Report = formatReport
ENV.GamepadBuracoX9Copy = copyReport

connectEvents()

pcall(function()
    RunService:UnbindFromRenderStep(BIND_PRE)
    RunService:UnbindFromRenderStep(BIND_POST)
end)

RunService:BindToRenderStep(BIND_PRE, Enum.RenderPriority.Camera.Value - 2, renderPre)
RunService:BindToRenderStep(BIND_POST, Enum.RenderPriority.Camera.Value + 8, renderPost)

createUI()

ENV.__GamepadBuracoX9Cleanup = function()
    captureRunning = false
    pcall(function() RunService:UnbindFromRenderStep(BIND_PRE) end)
    pcall(function() RunService:UnbindFromRenderStep(BIND_POST) end)

    for _, c in ipairs(eventConnections) do pcall(function() c:Disconnect() end) end
    for _, c in ipairs(uiConnections) do pcall(function() c:Disconnect() end) end
    eventConnections = {}
    uiConnections = {}

    if gui then pcall(function() gui:Destroy() end) end
    gui = nil

    ENV.GamepadBuracoX9Start = nil
    ENV.GamepadBuracoX9Stop = nil
    ENV.GamepadBuracoX9Report = nil
    ENV.GamepadBuracoX9Copy = nil
    ENV.__GamepadBuracoX9Cleanup = nil
end

notify("Buraco X9", "Pronto. Faça Touch → controle → Touch.", 5)
warn("[" .. VERSION .. "] ready | observational only | Touch -> Gamepad -> Touch")
