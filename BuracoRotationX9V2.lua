-- BuracoRotationX9V2.lua
-- Read-only rotation-path probe for Evade Legacy.
-- Run twice in separate sessions:
--   A) TOUCH only, 3rd person only
--   B) GAMEPAD only, 3rd person only
-- Goal: find the first divergence in camera rotation behavior while Buraco geometry is already present.
--
-- DOES NOT write Camera.CFrame/Focus, RootPart.CFrame, MouseBehavior, RotationType,
-- PreferredInput, mouse-lock state/offset, sensitivity/gain, FOV, zoom, physics,
-- character state, or movement state.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local VERSION = "BURACO-ROTATION-X9-V2-R1"
local UI_NAME = "__BuracoRotationX9V2"
local BIND_PRE = "__BuracoRotationX9V2_Pre"
local BIND_POST = "__BuracoRotationX9V2_Post"

local MAX_SECONDS = math.clamp(tonumber(ENV.BuracoX9V2Seconds) or 20, 12, 35)
local SAMPLE_HZ = math.clamp(tonumber(ENV.BuracoX9V2Hz) or 30, 15, 60)
local SAMPLE_DT = 1 / SAMPLE_HZ

if type(ENV.__BuracoRotationX9V2Cleanup) == "function" then
    pcall(ENV.__BuracoRotationX9V2Cleanup)
end

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok then return value end
    return fallback
end

local UGS = safe(function()
    return UserSettings():GetService("UserGameSettings")
end, nil)

local function round(n, d)
    if type(n) ~= "number" then return n end
    local p = 10 ^ (d or 6)
    return math.floor(n * p + (n >= 0 and 0.5 or -0.5)) / p
end

local function str(v)
    if v == nil then return "nil" end
    local tv = typeof(v)
    if tv == "Vector2" then
        return string.format("(%.6f,%.6f)", v.X, v.Y)
    elseif tv == "Vector3" then
        return string.format("(%.6f,%.6f,%.6f)", v.X, v.Y, v.Z)
    elseif tv == "EnumItem" then
        return tostring(v)
    elseif tv == "Instance" then
        return safe(function() return v:GetFullName() .. "<" .. v.ClassName .. ">" end, tostring(v))
    end
    return tostring(v)
end

local function has(s, needle)
    return string.find(string.lower(tostring(s)), string.lower(needle), 1, true) ~= nil
end

local function sourceOf(fn)
    if type(fn) ~= "function" then return "nil" end
    if debug and type(debug.info) == "function" then
        return safe(function()
            return tostring(debug.info(fn, "s") or "?") .. "::" .. tostring(debug.info(fn, "n") or "?")
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
    local p = safe(function() return UIS.PreferredInput end, nil)
    local ps = tostring(p)
    if has(ps, "gamepad") then return "GAMEPAD" end
    if has(ps, "touch") then return "TOUCH" end
    if has(ps, "keyboard") or has(ps, "mouse") then return "MOUSEKEY" end

    local last = tostring(safe(function() return UIS:GetLastInputType() end, nil))
    if has(last, "gamepad") then return "GAMEPAD" end
    if has(last, "touch") then return "TOUCH" end
    if has(last, "keyboard") or has(last, "mouse") then return "MOUSEKEY" end
    return "OTHER"
end

local pmCache = {instance=nil, module=nil, cameras=nil, controls=nil}

local function getPlayerModuleState()
    local ps = player and player:FindFirstChild("PlayerScripts")
    local pm = ps and ps:FindFirstChild("PlayerModule")
    if not pm then return nil, nil, nil, nil, nil end

    if pmCache.instance ~= pm or type(pmCache.module) ~= "table" then
        pmCache.instance = pm
        pmCache.module = safe(function() return require(pm) end, nil)
        pmCache.cameras = nil
        pmCache.controls = nil
    end

    local module = pmCache.module
    if type(module) ~= "table" then return module, nil, nil, nil, nil end

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
    local camCtrl = nil
    local moveCtrl = nil

    if type(cameras) == "table" then
        camCtrl = rawget(cameras, "activeCameraController")
        if camCtrl == nil and type(cameras.GetActiveCameraController) == "function" then
            camCtrl = safe(function() return cameras:GetActiveCameraController() end, nil)
        end
    end

    if type(controls) == "table" then
        moveCtrl = rawget(controls, "activeController")
        if moveCtrl == nil and type(controls.GetActiveController) == "function" then
            moveCtrl = safe(function() return controls:GetActiveController() end, nil)
        end
    end

    return module, cameras, controls, camCtrl, moveCtrl
end

local function getLockState(cameras, controller)
    local locked = nil
    local offset = nil

    if type(controller) == "table" then
        locked = rawget(controller, "inMouseLockedMode")
        offset = rawget(controller, "mouseLockOffset")
        if locked == nil and type(controller.GetIsMouseLocked) == "function" then
            locked = safe(function() return controller:GetIsMouseLocked() end, nil)
        end
        if offset == nil and type(controller.GetMouseLockOffset) == "function" then
            offset = safe(function() return controller:GetMouseLockOffset() end, nil)
        end
    end

    if locked == nil and type(cameras) == "table" and type(cameras.GetIsMouseLocked) == "function" then
        locked = safe(function() return cameras:GetIsMouseLocked() end, nil)
    end
    if offset == nil and type(cameras) == "table" and type(cameras.GetMouseLockOffset) == "function" then
        offset = safe(function() return cameras:GetMouseLockOffset() end, nil)
    end

    return locked, offset
end

local function angleDeltaDeg(a, b)
    if type(a) ~= "number" or type(b) ~= "number" then return nil end
    local d = a - b
    while d > 180 do d = d - 360 end
    while d < -180 do d = d + 360 end
    return round(d, 7)
end

local function magnitude2(v)
    if typeof(v) ~= "Vector2" then return nil end
    return round(v.Magnitude, 7)
end

local function captureState()
    local _, cameras, controls, camCtrl, moveCtrl = getPlayerModuleState()
    local cam = Workspace.CurrentCamera
    local char = player and player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    local head = char and char:FindFirstChild("Head")
    local locked, offset = getLockState(cameras, camCtrl)

    local s = {
        phase = inputClass(),
        preferredInput = str(safe(function() return UIS.PreferredInput end, nil)),
        lastInputType = str(safe(function() return UIS:GetLastInputType() end, nil)),
        mouseBehavior = str(safe(function() return UIS.MouseBehavior end, nil)),
        rotationType = UGS and str(safe(function() return UGS.RotationType end, nil)) or "nil",

        playerCameraMode = str(safe(function() return player.CameraMode end, nil)),
        cameraType = cam and str(cam.CameraType) or "nil",
        cameraSubject = cam and str(cam.CameraSubject) or "nil",

        camCtrlId = tostring(camCtrl),
        camCtrlUpdate = type(camCtrl) == "table" and sourceOf(rawget(camCtrl, "Update")) or "nil",
        camCtrlRotateInput = type(camCtrl) == "table" and rawget(camCtrl, "rotateInput") or nil,
        camCtrlRotateMag = type(camCtrl) == "table" and magnitude2(rawget(camCtrl, "rotateInput")) or nil,
        camCtrlPanEnabled = type(camCtrl) == "table" and rawget(camCtrl, "panEnabled") or nil,
        camCtrlDistance = type(camCtrl) == "table" and round(rawget(camCtrl, "currentSubjectDistance"), 5) or nil,
        camCtrlMovementMode = type(camCtrl) == "table" and str(rawget(camCtrl, "cameraMovementMode")) or "nil",
        mouseLocked = locked,
        mouseLockOffset = offset,

        moveCtrlId = tostring(moveCtrl),
        moveCtrlUpdate = type(moveCtrl) == "table" and sourceOf(rawget(moveCtrl, "Update")) or "nil",
        moveCtrlEnabled = type(moveCtrl) == "table" and rawget(moveCtrl, "enabled") or nil,

        humanoidState = hum and str(safe(function() return hum:GetState() end, nil)) or "nil",
    }

    if cam then
        local rx, ry, rz = cam.CFrame:ToOrientation()
        s.cameraPitchDeg = round(math.deg(rx), 6)
        s.cameraYawDeg = round(math.deg(ry), 6)
        s.cameraRollDeg = round(math.deg(rz), 6)
        s.focusLocal = cam.CFrame:PointToObjectSpace(cam.Focus.Position)
    end

    if root and cam then
        local lp = cam.CFrame:PointToObjectSpace(root.Position)
        local sp = cam:WorldToViewportPoint(root.Position)
        s.rootLocalX = round(lp.X, 7)
        s.rootLocalY = round(lp.Y, 7)
        s.rootLocalZ = round(lp.Z, 7)
        if cam.ViewportSize.X > 0 then
            s.rootScreenDX = round(sp.X / cam.ViewportSize.X - 0.5, 8)
        end
        local _, rY = root.CFrame:ToOrientation()
        s.rootYawDeg = round(math.deg(rY), 6)
        s.rootMinusCameraYawDeg = angleDeltaDeg(s.rootYawDeg, s.cameraYawDeg)
    end

    if head and cam then
        local lp = cam.CFrame:PointToObjectSpace(head.Position)
        local sp = cam:WorldToViewportPoint(head.Position)
        s.headLocalX = round(lp.X, 7)
        if cam.ViewportSize.X > 0 then
            s.headScreenDX = round(sp.X / cam.ViewportSize.X - 0.5, 8)
        end
    end

    return s
end

local function newStat()
    return {n=0,sum=0,sum2=0,min=math.huge,max=-math.huge}
end

local function pushStat(st, v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return end
    st.n += 1
    st.sum += v
    st.sum2 += v * v
    if v < st.min then st.min = v end
    if v > st.max then st.max = v end
end

local function statText(st)
    if not st or st.n == 0 then return "n=0" end
    local mean = st.sum / st.n
    local var = math.max(0, st.sum2 / st.n - mean * mean)
    return string.format("n=%d mean=%.8f sd=%.8f min=%.8f max=%.8f",
        st.n, mean, math.sqrt(var), st.min, st.max)
end

local running = false
local startedAt = 0
local lastSampleAt = -math.huge
local frame = 0
local pre = nil
local gui = nil
local status = nil
local inputLabel = nil
local uiConnections = {}
local eventConnections = {}

local report = nil

local function newReport()
    return {
        version = VERSION,
        placeId = game.PlaceId,
        gameId = game.GameId,
        startedWall = os.date("%Y-%m-%d %H:%M:%S"),
        duration = 0,
        startState = nil,
        stopState = nil,
        samples = 0,
        thirdPersonSamples = 0,
        firstPersonSamples = 0,
        phaseCounts = {TOUCH=0,GAMEPAD=0,MOUSEKEY=0,OTHER=0},
        inputEvents = {TouchChanged=0,GamepadThumbstick2=0,MouseMovement=0,Other=0},
        events = {},
        timeline = {},
        stats = {
            yawStep = newStat(),
            pitchStep = newStat(),
            rotateX = newStat(),
            rotateY = newStat(),
            rotateMag = newStat(),
            rootLocalX = newStat(),
            rootScreenDX = newStat(),
            rootMinusCameraYawDeg = newStat(),
            headLocalX = newStat(),
            headScreenDX = newStat(),
            touchDeltaX = newStat(),
            touchDeltaY = newStat(),
            thumbstick2X = newStat(),
            thumbstick2Y = newStat(),
        },
        connectionMap = {},
    }
end

local function event(kind, detail)
    if not running or not report then return end
    if #report.events >= 120 then return end
    local t = os.clock() - startedAt
    report.events[#report.events + 1] =
        string.format("t=%.4f f=%d %s %s", t, frame, kind, detail or "")
end

local function compact(s)
    return table.concat({
        "phase=" .. tostring(s.phase),
        "preferred=" .. tostring(s.preferredInput),
        "last=" .. tostring(s.lastInputType),
        "mouseBehavior=" .. tostring(s.mouseBehavior),
        "rotationType=" .. tostring(s.rotationType),
        "cameraMode=" .. tostring(s.playerCameraMode),
        "cameraType=" .. tostring(s.cameraType),
        "camCtrl=" .. tostring(s.camCtrlId),
        "moveCtrl=" .. tostring(s.moveCtrlId),
        "lock=" .. str(s.mouseLocked),
        "offset=" .. str(s.mouseLockOffset),
        "distance=" .. str(s.camCtrlDistance),
        "rotateInput=" .. str(s.camCtrlRotateInput),
        "rootLX=" .. str(s.rootLocalX),
        "rootDX=" .. str(s.rootScreenDX),
        "yawRel=" .. str(s.rootMinusCameraYawDeg),
        "yaw=" .. str(s.cameraYawDeg),
        "pitch=" .. str(s.cameraPitchDeg),
    }, " | ")
end

local function buildConnectionMap()
    local out = {}
    if type(getconnections) ~= "function" then
        out[#out + 1] = "getconnections unavailable"
        return out
    end

    local signals = {
        {"UIS.InputBegan", UIS.InputBegan},
        {"UIS.InputChanged", UIS.InputChanged},
        {"UIS.InputEnded", UIS.InputEnded},
        {"UIS.LastInputTypeChanged", UIS.LastInputTypeChanged},
    }

    for _, item in ipairs(signals) do
        local name, sig = item[1], item[2]
        local conns = safe(function() return getconnections(sig) end, {})
        out[#out + 1] = name .. " connections=" .. tostring(type(conns) == "table" and #conns or -1)
        if type(conns) == "table" then
            local shown = 0
            for i, c in ipairs(conns) do
                local fn = safe(function() return c.Function end, nil)
                if type(fn) == "function" then
                    shown += 1
                    out[#out + 1] = string.format("%s[%d]=%s", name, i, sourceOf(fn))
                    if shown >= 12 then break end
                end
            end
        end
    end
    return out
end

local function notify(title, msg, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = msg,
            Duration = duration or 4
        })
    end)
end

local function stopCapture(auto)
    if not running then return end
    report.stopState = captureState()
    report.duration = os.clock() - startedAt
    event("STOP", "auto=" .. tostring(auto))
    running = false
    if status then status.Text = "PARADO • COPIAR REPORT" end
    notify("X9 V2", "Acabou. Copie o report.", 4)
end

local function startCapture()
    if running then return end
    report = newReport()
    report.connectionMap = buildConnectionMap()
    report.startState = captureState()
    startedAt = os.clock()
    lastSampleAt = -math.huge
    frame = 0
    pre = nil
    running = true

    if status then
        status.Text = "GRAVANDO 20s • FIQUE EM 3ª PESSOA"
    end

    notify("X9 V2", "3P somente. Faça esquerda/direita, cima/baixo e ande+gire.", 5)

    task.spawn(function()
        local token = startedAt
        task.wait(MAX_SECONDS)
        if running and startedAt == token then
            stopCapture(true)
        end
    end)
end

local function formatReport()
    if not report then return "BURACO X9 V2: nenhuma captura." end

    local lines = {}
    local function add(x) lines[#lines + 1] = tostring(x) end

    add("=== BURACO ROTATION X9 V2 REPORT ===")
    add("version = " .. tostring(report.version))
    add("startedWall = " .. tostring(report.startedWall))
    add("placeId = " .. tostring(report.placeId))
    add("gameId = " .. tostring(report.gameId))
    add("duration = " .. tostring(round(report.duration or 0, 4)))
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
    add(compact(report.startState or {}))
    add("")

    add("=== STOP STATE ===")
    add(compact(report.stopState or captureState()))
    add("")

    add("=== COVERAGE ===")
    add("samples = " .. tostring(report.samples))
    add("thirdPersonSamples = " .. tostring(report.thirdPersonSamples))
    add("firstPersonSamples = " .. tostring(report.firstPersonSamples))
    add(string.format("phaseCounts TOUCH=%d GAMEPAD=%d MOUSEKEY=%d OTHER=%d",
        report.phaseCounts.TOUCH or 0,
        report.phaseCounts.GAMEPAD or 0,
        report.phaseCounts.MOUSEKEY or 0,
        report.phaseCounts.OTHER or 0))
    add(string.format("inputEvents TouchChanged=%d GamepadThumbstick2=%d MouseMovement=%d Other=%d",
        report.inputEvents.TouchChanged or 0,
        report.inputEvents.GamepadThumbstick2 or 0,
        report.inputEvents.MouseMovement or 0,
        report.inputEvents.Other or 0))
    add("")

    add("=== ROTATION PIPELINE STATS ===")
    for _, key in ipairs({
        "yawStep","pitchStep","rotateX","rotateY","rotateMag",
        "touchDeltaX","touchDeltaY","thumbstick2X","thumbstick2Y",
        "rootLocalX","rootScreenDX","rootMinusCameraYawDeg","headLocalX","headScreenDX"
    }) do
        add(key .. " = " .. statText(report.stats[key]))
    end
    add("")

    add("=== TIMELINE ===")
    for _, line in ipairs(report.timeline) do add(line) end
    add("")

    add("=== INPUT EVENTS ===")
    for _, line in ipairs(report.events) do add(line) end
    add("")

    add("=== STATIC CONNECTION MAP ===")
    for _, line in ipairs(report.connectionMap) do add(line) end
    add("")

    add("=== INTERPRETATION TARGET ===")
    add("Compare this report against the other 3P-only session.")
    add("1) Same Buraco geometry? rootLocalX/lock/offset should be compared first.")
    add("2) Which source drives rotation: Touch delta vs Thumbstick2.")
    add("3) Compare camera yawStep/pitchStep per sample.")
    add("4) Compare active camera/movement controller identity and Update source.")
    add("5) Find the earliest pipeline difference before final Camera geometry.")
    add("No causal claim is made automatically by this probe.")

    return table.concat(lines, "\n")
end

local function copyReport()
    if running then stopCapture(false) end
    local txt = formatReport()
    local copied = false
    local fns = {}

    if type(ENV.setclipboard) == "function" then fns[#fns + 1] = ENV.setclipboard end
    if type(ENV.toclipboard) == "function" then fns[#fns + 1] = ENV.toclipboard end
    if type(setclipboard) == "function" then fns[#fns + 1] = setclipboard end
    if type(toclipboard) == "function" then fns[#fns + 1] = toclipboard end

    for _, fn in ipairs(fns) do
        if pcall(fn, txt) then
            copied = true
            break
        end
    end

    if type(writefile) == "function" then
        pcall(writefile, "BuracoRotationX9V2_Report.txt", txt)
    end

    if status then
        status.Text = copied and "REPORT COPIADO ✓" or "Arquivo tentado: BuracoRotationX9V2_Report.txt"
    end
    notify("X9 V2", copied and "Report copiado." or "Clipboard falhou; tente o arquivo.", 4)
    return txt
end

local function renderPre()
    if not running then
        pre = nil
        return
    end
    local s = captureState()
    pre = {
        yaw = s.cameraYawDeg,
        pitch = s.cameraPitchDeg,
        rotateInput = s.camCtrlRotateInput,
        rotateMag = s.camCtrlRotateMag,
        rootLocalX = s.rootLocalX,
        rootScreenDX = s.rootScreenDX,
    }
end

local function renderPost()
    local current = captureState()

    if inputLabel then
        inputLabel.Text = "INPUT: " .. tostring(current.phase) ..
            " • distância: " .. tostring(current.camCtrlDistance or "?")
    end

    if not running then return end

    frame += 1
    local t = os.clock() - startedAt

    if t - lastSampleAt >= SAMPLE_DT then
        lastSampleAt = t
        report.samples += 1
        report.phaseCounts[current.phase] = (report.phaseCounts[current.phase] or 0) + 1

        local dist = current.camCtrlDistance
        if type(dist) == "number" and dist <= 1.1 then
            report.firstPersonSamples += 1
        else
            report.thirdPersonSamples += 1
        end

        if pre then
            pushStat(report.stats.yawStep, angleDeltaDeg(current.cameraYawDeg, pre.yaw))
            pushStat(report.stats.pitchStep, angleDeltaDeg(current.cameraPitchDeg, pre.pitch))
        end

        if typeof(current.camCtrlRotateInput) == "Vector2" then
            pushStat(report.stats.rotateX, current.camCtrlRotateInput.X)
            pushStat(report.stats.rotateY, current.camCtrlRotateInput.Y)
            pushStat(report.stats.rotateMag, current.camCtrlRotateInput.Magnitude)
        end

        pushStat(report.stats.rootLocalX, current.rootLocalX)
        pushStat(report.stats.rootScreenDX, current.rootScreenDX)
        pushStat(report.stats.rootMinusCameraYawDeg, current.rootMinusCameraYawDeg)
        pushStat(report.stats.headLocalX, current.headLocalX)
        pushStat(report.stats.headScreenDX, current.headScreenDX)

        if #report.timeline < 120 then
            report.timeline[#report.timeline + 1] = string.format(
                "t=%.3f f=%d phase=%s dist=%s lock=%s off=%s rot=%s yawStep=%s pitchStep=%s rootLX=%s rootDX=%s yawRel=%s",
                t,
                frame,
                tostring(current.phase),
                str(current.camCtrlDistance),
                str(current.mouseLocked),
                str(current.mouseLockOffset),
                str(current.camCtrlRotateInput),
                str(pre and angleDeltaDeg(current.cameraYawDeg, pre.yaw) or nil),
                str(pre and angleDeltaDeg(current.cameraPitchDeg, pre.pitch) or nil),
                str(current.rootLocalX),
                str(current.rootScreenDX),
                str(current.rootMinusCameraYawDeg)
            )
        end
    end
end

local function connect(sig, fn)
    local c = safe(function() return sig:Connect(fn) end, nil)
    if c then eventConnections[#eventConnections + 1] = c end
end

connect(UIS.InputChanged, function(input, gpe)
    if not running or not report then return end

    local uit = tostring(input.UserInputType)
    local key = tostring(safe(function() return input.KeyCode end, nil))

    if has(uit, "touch") then
        report.inputEvents.TouchChanged += 1
        local d = safe(function() return input.Delta end, nil)
        if typeof(d) == "Vector3" then
            pushStat(report.stats.touchDeltaX, d.X)
            pushStat(report.stats.touchDeltaY, d.Y)
        elseif typeof(d) == "Vector2" then
            pushStat(report.stats.touchDeltaX, d.X)
            pushStat(report.stats.touchDeltaY, d.Y)
        end
        if #report.events < 60 then
            event("TouchChanged", "delta=" .. str(d) .. " pos=" .. str(safe(function() return input.Position end, nil)) .. " gpe=" .. tostring(gpe))
        end
    elseif has(uit, "gamepad") and has(key, "thumbstick2") then
        report.inputEvents.GamepadThumbstick2 += 1
        local p = safe(function() return input.Position end, nil)
        if typeof(p) == "Vector3" then
            pushStat(report.stats.thumbstick2X, p.X)
            pushStat(report.stats.thumbstick2Y, p.Y)
        elseif typeof(p) == "Vector2" then
            pushStat(report.stats.thumbstick2X, p.X)
            pushStat(report.stats.thumbstick2Y, p.Y)
        end
        if #report.events < 60 then
            event("Thumbstick2", "pos=" .. str(p) .. " gpe=" .. tostring(gpe))
        end
    elseif has(uit, "mousemovement") then
        report.inputEvents.MouseMovement += 1
    else
        report.inputEvents.Other += 1
    end
end)

connect(UIS.LastInputTypeChanged, function(newType)
    event("LastInputTypeChanged", str(newType) .. " phase=" .. inputClass())
end)

local function makeButton(parent, txt, order)
    local b = Instance.new("TextButton")
    b.LayoutOrder = order
    b.Size = UDim2.new(1, 0, 0, 38)
    b.BackgroundColor3 = Color3.fromRGB(31, 40, 57)
    b.BorderSizePixel = 0
    b.Text = txt
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
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
    panel.Size = UDim2.fromOffset(318, 250)
    panel.Position = UDim2.new(1, -330, 0.5, -125)
    panel.BackgroundColor3 = Color3.fromRGB(13, 18, 28)
    panel.BorderSizePixel = 0
    panel.Active = true
    panel.Draggable = true
    panel.Parent = gui

    local pc = Instance.new("UICorner")
    pc.CornerRadius = UDim.new(0, 13)
    pc.Parent = panel

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -24, 0, 30)
    title.Position = UDim2.fromOffset(12, 7)
    title.BackgroundTransparency = 1
    title.Text = "BURACO X9 V2 • ROTATION PATH"
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.new(1,1,1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.Parent = panel

    local body = Instance.new("Frame")
    body.Size = UDim2.new(1, -24, 1, -48)
    body.Position = UDim2.fromOffset(12, 41)
    body.BackgroundTransparency = 1
    body.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = body

    local help = Instance.new("TextLabel")
    help.LayoutOrder = 0
    help.Size = UDim2.new(1, 0, 0, 62)
    help.BackgroundColor3 = Color3.fromRGB(23, 30, 43)
    help.BorderSizePixel = 0
    help.TextWrapped = true
    help.Text = "UMA sessão por vez • SOMENTE 3ª PESSOA\nGire E/D, cima/baixo e depois ande + gire. ~20s."
    help.TextColor3 = Color3.fromRGB(220,226,235)
    help.Font = Enum.Font.Gotham
    help.TextSize = 11
    help.Parent = body
    local hc = Instance.new("UICorner")
    hc.CornerRadius = UDim.new(0, 8)
    hc.Parent = help

    inputLabel = Instance.new("TextLabel")
    inputLabel.LayoutOrder = 1
    inputLabel.Size = UDim2.new(1, 0, 0, 24)
    inputLabel.BackgroundTransparency = 1
    inputLabel.Text = "INPUT: " .. inputClass()
    inputLabel.TextColor3 = Color3.fromRGB(165, 210, 255)
    inputLabel.Font = Enum.Font.GothamBold
    inputLabel.TextSize = 12
    inputLabel.Parent = body

    local start = makeButton(body, "INICIAR 20s", 2)
    local stop = makeButton(body, "PARAR", 3)
    local copy = makeButton(body, "COPIAR REPORT", 4)

    status = Instance.new("TextLabel")
    status.LayoutOrder = 5
    status.Size = UDim2.new(1, 0, 0, 28)
    status.BackgroundTransparency = 1
    status.Text = "Pronto • somente leitura"
    status.TextColor3 = Color3.fromRGB(175,185,200)
    status.Font = Enum.Font.Gotham
    status.TextSize = 10
    status.Parent = body

    uiConnections[#uiConnections + 1] = start.Activated:Connect(startCapture)
    uiConnections[#uiConnections + 1] = stop.Activated:Connect(function() stopCapture(false) end)
    uiConnections[#uiConnections + 1] = copy.Activated:Connect(copyReport)
end

pcall(function()
    RunService:UnbindFromRenderStep(BIND_PRE)
    RunService:UnbindFromRenderStep(BIND_POST)
end)

RunService:BindToRenderStep(BIND_PRE, Enum.RenderPriority.Camera.Value - 2, renderPre)
RunService:BindToRenderStep(BIND_POST, Enum.RenderPriority.Camera.Value + 8, renderPost)

createUI()

ENV.BuracoRotationX9V2Start = startCapture
ENV.BuracoRotationX9V2Stop = stopCapture
ENV.BuracoRotationX9V2Report = formatReport
ENV.BuracoRotationX9V2Copy = copyReport

ENV.__BuracoRotationX9V2Cleanup = function()
    running = false
    pcall(function() RunService:UnbindFromRenderStep(BIND_PRE) end)
    pcall(function() RunService:UnbindFromRenderStep(BIND_POST) end)

    for _, c in ipairs(eventConnections) do pcall(function() c:Disconnect() end) end
    for _, c in ipairs(uiConnections) do pcall(function() c:Disconnect() end) end
    eventConnections = {}
    uiConnections = {}

    if gui then pcall(function() gui:Destroy() end) end
    gui = nil

    ENV.BuracoRotationX9V2Start = nil
    ENV.BuracoRotationX9V2Stop = nil
    ENV.BuracoRotationX9V2Report = nil
    ENV.BuracoRotationX9V2Copy = nil
    ENV.__BuracoRotationX9V2Cleanup = nil
end

notify("X9 V2", "Pronto. Rode uma sessão Touch 3P e outra Gamepad 3P.", 5)
warn("[" .. VERSION .. "] ready | observational only | 3P Touch OR 3P Gamepad")
