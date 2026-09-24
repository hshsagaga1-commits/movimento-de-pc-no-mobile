-- BuracoRotationX9R2.lua
-- Final short read-only rotation-path probe for Evade Legacy on iPhone/Delta.
--
-- PURPOSE
--   Compare TWO SEPARATE 3rd-person runs:
--     A) Touch only
--     B) Physical Gamepad only
--   We already know both can share the same 3P geometry:
--     mouse-lock on, offset (2, 0.5, 0), Root local X ~= -2.
--   This probe therefore focuses on the ROTATION PIPELINE, not Buraco position.
--
-- IMPORTANT
--   Observational only. It does NOT write:
--     Camera.CFrame / Camera.Focus / RootPart.CFrame
--     PreferredInput / MouseBehavior / RotationType / mouse-lock / offsets
--     FOV / zoom / gain / sensitivity / physics / character state
--
-- TEST (repeat script once per input source)
--   1) Stay in THIRD PERSON for the whole run.
--   2) Tap START. There is a 1.5 s warmup.
--   3) For ~18 s: walk a little, rotate left/right, look up/down.
--   4) Do not enter first person.
--   5) Auto-stop -> COPY REPORT.
--
-- The report is intentionally compact. It records:
--   - raw camera-relevant Touch / Thumbstick2 cadence
--   - BaseCamera/controller rotateInput before and after camera update
--   - camera yaw/pitch delta across the camera render stage
--   - gamepadPanningCamera / pan flags / active controller identity
--   - subject/focus/Root camera-local geometry
--   - 3P validity and any controller swaps
--
-- VERSION: BURACO-ROTATION-X9-R2

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local VERSION = "BURACO-ROTATION-X9-R2"
local UI_NAME = "__BuracoRotationX9R2"
local BIND_PRE = "__BuracoRotationX9R2_Pre"
local BIND_POST = "__BuracoRotationX9R2_Post"

local WARMUP_SECONDS = 1.5
local CAPTURE_SECONDS = math.clamp(tonumber(ENV.BuracoRotationX9R2Seconds) or 18, 12, 30)
local SAMPLE_HZ = 30
local TIMELINE_HZ = 5
local SAMPLE_DT = 1 / SAMPLE_HZ
local TIMELINE_DT = 1 / TIMELINE_HZ

if type(ENV.__BuracoRotationX9R2Cleanup) == "function" then
    pcall(ENV.__BuracoRotationX9R2Cleanup)
end

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok then return value end
    return fallback
end

local function str(v)
    if v == nil then return "nil" end
    local tv = typeof(v)
    if tv == "Vector2" then
        return string.format("(%.5f,%.5f)", v.X, v.Y)
    elseif tv == "Vector3" then
        return string.format("(%.5f,%.5f,%.5f)", v.X, v.Y, v.Z)
    elseif tv == "EnumItem" then
        return tostring(v)
    elseif tv == "Instance" then
        return safe(function() return v:GetFullName() .. "<" .. v.ClassName .. ">" end, tostring(v))
    end
    return tostring(v)
end

local function round(n, d)
    if type(n) ~= "number" then return n end
    local p = 10 ^ (d or 6)
    if n >= 0 then
        return math.floor(n * p + 0.5) / p
    else
        return math.ceil(n * p - 0.5) / p
    end
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

local UGS = safe(function() return UserSettings():GetService("UserGameSettings") end, nil)

local pmCache = {inst=nil, module=nil, cameras=nil, controls=nil}

local function getPlayerModuleState()
    local ps = player and player:FindFirstChild("PlayerScripts")
    local pm = ps and ps:FindFirstChild("PlayerModule")
    if not pm then return nil,nil,nil,nil,nil end

    if pmCache.inst ~= pm or type(pmCache.module) ~= "table" then
        pmCache.inst = pm
        pmCache.module = safe(function() return require(pm) end, nil)
        pmCache.cameras = nil
        pmCache.controls = nil
    end

    local module = pmCache.module
    if type(module) ~= "table" then return module,nil,nil,nil,nil end

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
    local camController = nil
    local controlController = nil

    if type(cameras) == "table" then
        camController = rawget(cameras, "activeCameraController")
        if camController == nil and type(cameras.GetActiveCameraController) == "function" then
            camController = safe(function() return cameras:GetActiveCameraController() end, nil)
        end
    end

    if type(controls) == "table" then
        controlController = rawget(controls, "activeController")
        if controlController == nil and type(controls.GetActiveController) == "function" then
            controlController = safe(function() return controls:GetActiveController() end, nil)
        end
    end

    return module, cameras, controls, camController, controlController
end

local function preferredClass()
    local p = safe(function() return UIS.PreferredInput end, nil)
    local s = tostring(p)
    if has(s, "gamepad") then return "GAMEPAD" end
    if has(s, "touch") then return "TOUCH" end
    if has(s, "keyboard") or has(s, "mouse") then return "MOUSEKEY" end

    local last = tostring(safe(function() return UIS:GetLastInputType() end, nil))
    if has(last, "gamepad") then return "GAMEPAD" end
    if has(last, "touch") then return "TOUCH" end
    if has(last, "keyboard") or has(last, "mouse") then return "MOUSEKEY" end
    return "OTHER"
end

local function getControllerLock(cameras, controller)
    local locked, offset = nil, nil
    if type(controller) == "table" then
        if type(controller.GetIsMouseLocked) == "function" then
            locked = safe(function() return controller:GetIsMouseLocked() end, nil)
        end
        if type(controller.GetMouseLockOffset) == "function" then
            offset = safe(function() return controller:GetMouseLockOffset() end, nil)
        end
        if locked == nil then locked = rawget(controller, "inMouseLockedMode") end
        if offset == nil then offset = rawget(controller, "mouseLockOffset") end
    end
    if type(cameras) == "table" then
        if locked == nil and type(cameras.GetIsMouseLocked) == "function" then
            locked = safe(function() return cameras:GetIsMouseLocked() end, nil)
        end
        if offset == nil and type(cameras.GetMouseLockOffset) == "function" then
            offset = safe(function() return cameras:GetMouseLockOffset() end, nil)
        end
    end
    return locked, offset
end

local function cameraAngles(cf)
    if typeof(cf) ~= "CFrame" then return nil,nil end
    local x,y = cf:ToOrientation()
    return math.deg(x), math.deg(y)
end

local function angleDelta(a,b)
    if type(a) ~= "number" or type(b) ~= "number" then return nil end
    local d = a - b
    while d > 180 do d = d - 360 end
    while d < -180 do d = d + 360 end
    return d
end

local function findCameraCFrameValue()
    -- Read-only best-effort search. We do not assume a fixed Evade hierarchy.
    local root = Workspace:FindFirstChild("Game")
    if not root then return nil end
    local best = nil
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("CFrameValue") then
            local n = string.lower(d.Name)
            if n == "cameracframe" then
                return d
            elseif not best and string.find(n, "camera", 1, true) and string.find(n, "cframe", 1, true) then
                best = d
            end
        end
    end
    return best
end

local cameraCFrameValue = nil

local function isThirdPerson(controller)
    if player and tostring(player.CameraMode) == "Enum.CameraMode.LockFirstPerson" then
        return false, "Player.CameraMode=LockFirstPerson"
    end
    if type(controller) == "table" then
        if rawget(controller, "inFirstPerson") == true then
            return false, "controller.inFirstPerson=true"
        end
        local d = rawget(controller, "currentSubjectDistance")
        if type(d) == "number" and d <= 1.05 then
            return false, "subjectDistance<=1.05"
        end
    end
    return true, "ok"
end

local function captureCore()
    local _, cameras, controls, cc, mc = getPlayerModuleState()
    local cam = Workspace.CurrentCamera
    local char = player and player.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    local head = char and char:FindFirstChild("Head")

    local locked, offset = getControllerLock(cameras, cc)
    local third, thirdReason = isThirdPerson(cc)

    local s = {
        phase = preferredClass(),
        preferredInput = str(safe(function() return UIS.PreferredInput end, nil)),
        lastInputType = str(safe(function() return UIS:GetLastInputType() end, nil)),
        connectedGamepads = safe(function()
            local t = UIS:GetConnectedGamepads()
            return type(t) == "table" and #t or 0
        end, -1),

        mouseBehavior = str(safe(function() return UIS.MouseBehavior end, nil)),
        rotationType = UGS and str(safe(function() return UGS.RotationType end, nil)) or "nil",
        playerCameraMode = str(safe(function() return player.CameraMode end, nil)),
        cameraType = cam and str(cam.CameraType) or "nil",
        cameraSubject = cam and str(cam.CameraSubject) or "nil",

        cameraControllerId = tostring(cc),
        cameraControllerUpdate = type(cc) == "table" and sourceOf(rawget(cc, "Update")) or "nil",
        controlControllerId = tostring(mc),
        controlControllerUpdate = type(mc) == "table" and sourceOf(rawget(mc, "Update")) or "nil",

        locked = locked,
        offset = offset,
        inFirstPerson = type(cc) == "table" and rawget(cc, "inFirstPerson") or nil,
        currentSubjectDistance = type(cc) == "table" and rawget(cc, "currentSubjectDistance") or nil,
        cameraMovementMode = type(cc) == "table" and rawget(cc, "cameraMovementMode") or nil,
        panEnabled = type(cc) == "table" and rawget(cc, "panEnabled") or nil,
        userPanningCamera = type(cc) == "table" and rawget(cc, "userPanningCamera") or nil,
        userPanningTheCamera = type(cc) == "table" and rawget(cc, "userPanningTheCamera") or nil,
        gamepadPanningCamera = type(cc) == "table" and rawget(cc, "gamepadPanningCamera") or nil,
        rotateInput = type(cc) == "table" and rawget(cc, "rotateInput") or nil,
        keyPanEnabled = type(cc) == "table" and rawget(cc, "keyPanEnabled") or nil,

        isThirdPerson = third,
        thirdPersonReason = thirdReason,
    }

    if cam then
        s.cameraCFrame = cam.CFrame
        s.cameraFocus = cam.Focus
        s.cameraPitchDeg, s.cameraYawDeg = cameraAngles(cam.CFrame)

        local fp = cam.CFrame:PointToObjectSpace(cam.Focus.Position)
        s.focusLocalX = fp.X
        s.focusLocalY = fp.Y
        s.focusLocalZ = fp.Z
    end

    if root and cam then
        local p = cam.CFrame:PointToObjectSpace(root.Position)
        s.rootLocalX = p.X
        s.rootLocalY = p.Y
        s.rootLocalZ = p.Z
    end

    if head and cam then
        local p = cam.CFrame:PointToObjectSpace(head.Position)
        s.headLocalX = p.X
        s.headLocalY = p.Y
        s.headLocalZ = p.Z
    end

    if type(cc) == "table" and type(cc.GetSubjectPosition) == "function" and cam then
        local sp = safe(function() return cc:GetSubjectPosition() end, nil)
        if typeof(sp) == "Vector3" then
            local p = cam.CFrame:PointToObjectSpace(sp)
            s.subjectLocalX = p.X
            s.subjectLocalY = p.Y
            s.subjectLocalZ = p.Z
        end
    end

    if cameraCFrameValue and cameraCFrameValue.Parent then
        local v = safe(function() return cameraCFrameValue.Value end, nil)
        if typeof(v) == "CFrame" then
            s.evadeCameraCFrame = v
            s.evadePitchDeg, s.evadeYawDeg = cameraAngles(v)
        end
    end

    return s
end

local function digestController(c)
    if type(c) ~= "table" then return "not-table" end
    local keys = {
        "activeGamepad","cameraType","currentSubjectDistance","enabled",
        "gamepadPanningCamera","inFirstPerson","inMouseLockedMode",
        "keyPanEnabled","mouseLockOffset","panEnabled","rotateInput",
        "userPanningCamera","userPanningTheCamera","cameraMovementMode"
    }
    local out = {}
    for _,k in ipairs(keys) do
        local v = rawget(c,k)
        if v ~= nil then out[#out+1] = k .. "=" .. str(v) end
    end
    return table.concat(out, " | ")
end

local function snapshotDigest()
    local _, cameras, controls, cc, mc = getPlayerModuleState()
    return {
        cameraController = digestController(cc),
        controlController = digestController(mc),
        cameraControllerId = tostring(cc),
        controlControllerId = tostring(mc),
        camerasId = tostring(cameras),
        controlsId = tostring(controls),
    }
end

local function newStat()
    return {n=0,sum=0,sum2=0,min=math.huge,max=-math.huge}
end

local function push(st,v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return end
    st.n += 1
    st.sum += v
    st.sum2 += v*v
    if v < st.min then st.min = v end
    if v > st.max then st.max = v end
end

local function statText(st)
    if not st or st.n == 0 then return "n=0" end
    local mean = st.sum / st.n
    local variance = math.max(0, st.sum2 / st.n - mean*mean)
    return string.format("n=%d mean=%.7f sd=%.7f min=%.7f max=%.7f",
        st.n, mean, math.sqrt(variance), st.min, st.max)
end

local statNames = {
    "preRotateX","preRotateY","postRotateX","postRotateY",
    "rotateDeltaX","rotateDeltaY",
    "cameraYawDelta","cameraPitchDelta",
    "evadeYawDelta","evadePitchDelta",
    "rootLocalX","headLocalX","focusLocalX","subjectLocalX",
    "subjectDistance",
    "gamepadPanX","gamepadPanY",
}

local function makeStats()
    local t = {}
    for _,k in ipairs(statNames) do t[k] = newStat() end
    return t
end

local inputStats = {
    touchRightCount = 0,
    touchLeftCount = 0,
    touchRightDX = newStat(),
    touchRightDY = newStat(),
    touchRightDt = newStat(),
    touchLeftDX = newStat(),
    touchLeftDY = newStat(),
    gamepadThumb2Count = 0,
    gamepadThumb2X = newStat(),
    gamepadThumb2Y = newStat(),
    gamepadThumb2Dt = newStat(),
}
local lastTouchRightAt = nil
local lastGamepadThumb2At = nil

local running = false
local armed = false
local captureStart = 0
local frameIndex = 0
local pre = nil
local stats = makeStats()
local timeline = {}
local events = {}
local invalid3PFrames = 0
local valid3PFrames = 0
local controllerSwapCount = 0
local inputPhaseAtStart = "OTHER"
local startState = nil
local endState = nil
local startDigest = nil
local endDigest = nil
local lastControllerId = nil
local lastSampleAt = -math.huge
local lastTimelineAt = -math.huge
local connections = {}
local uiConnections = {}
local gui, statusLabel, inputLabel, copyButton

local function notify(text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Buraco X9 R2",
            Text = text,
            Duration = duration or 4,
        })
    end)
end

local function addEvent(s)
    if #events < 80 then
        events[#events+1] = string.format("t=%.4f f=%d %s", math.max(0, os.clock()-captureStart), frameIndex, s)
    end
end

local function resetRun()
    stats = makeStats()
    timeline = {}
    events = {}
    invalid3PFrames = 0
    valid3PFrames = 0
    controllerSwapCount = 0
    frameIndex = 0
    pre = nil
    lastControllerId = nil
    lastSampleAt = -math.huge
    lastTimelineAt = -math.huge
    inputStats = {
        touchRightCount = 0,
        touchLeftCount = 0,
        touchRightDX = newStat(),
        touchRightDY = newStat(),
        touchRightDt = newStat(),
        touchLeftDX = newStat(),
        touchLeftDY = newStat(),
        gamepadThumb2Count = 0,
        gamepadThumb2X = newStat(),
        gamepadThumb2Y = newStat(),
        gamepadThumb2Dt = newStat(),
    }
    lastTouchRightAt = nil
    lastGamepadThumb2At = nil
end

local function capturePre()
    if not running then pre = nil return end
    pre = captureCore()
end

local function v2xy(v)
    if typeof(v) == "Vector2" then return v.X,v.Y end
    if typeof(v) == "Vector3" then return v.X,v.Y end
    return nil,nil
end

local function postFrame()
    if not running then
        if inputLabel then inputLabel.Text = "INPUT: " .. preferredClass() end
        return
    end

    frameIndex += 1
    local now = os.clock()
    local t = now - captureStart
    local post = captureCore()

    if inputLabel then
        inputLabel.Text = "INPUT: " .. tostring(post.phase) .. " • 3P=" .. tostring(post.isThirdPerson)
    end

    if post.isThirdPerson then valid3PFrames += 1 else invalid3PFrames += 1 end

    if lastControllerId and lastControllerId ~= post.cameraControllerId then
        controllerSwapCount += 1
        addEvent("CAMERA_CONTROLLER_SWAP " .. tostring(lastControllerId) .. " -> " .. tostring(post.cameraControllerId))
    end
    lastControllerId = post.cameraControllerId

    if pre and t - lastSampleAt >= SAMPLE_DT then
        lastSampleAt = t
        local prx, pry = v2xy(pre.rotateInput)
        local pox, poy = v2xy(post.rotateInput)

        push(stats.preRotateX, prx)
        push(stats.preRotateY, pry)
        push(stats.postRotateX, pox)
        push(stats.postRotateY, poy)
        if prx and pox then push(stats.rotateDeltaX, pox-prx) end
        if pry and poy then push(stats.rotateDeltaY, poy-pry) end

        push(stats.cameraYawDelta, angleDelta(post.cameraYawDeg, pre.cameraYawDeg))
        push(stats.cameraPitchDelta, angleDelta(post.cameraPitchDeg, pre.cameraPitchDeg))
        push(stats.evadeYawDelta, angleDelta(post.evadeYawDeg, pre.evadeYawDeg))
        push(stats.evadePitchDelta, angleDelta(post.evadePitchDeg, pre.evadePitchDeg))

        push(stats.rootLocalX, post.rootLocalX)
        push(stats.headLocalX, post.headLocalX)
        push(stats.focusLocalX, post.focusLocalX)
        push(stats.subjectLocalX, post.subjectLocalX)
        push(stats.subjectDistance, post.currentSubjectDistance)

        local gpx,gpy = v2xy(post.gamepadPanningCamera)
        push(stats.gamepadPanX, gpx)
        push(stats.gamepadPanY, gpy)
    end

    if t - lastTimelineAt >= TIMELINE_DT and #timeline < 120 then
        lastTimelineAt = t
        local prx,pry = pre and v2xy(pre.rotateInput) or nil,nil
        local pox,poy = v2xy(post.rotateInput)
        local gpx,gpy = v2xy(post.gamepadPanningCamera)
        timeline[#timeline+1] = string.format(
            "t=%.3f f=%d phase=%s 3P=%s lock=%s off=%s dist=%s preRot=(%s,%s) postRot=(%s,%s) camD=(%s,%s) evadeD=(%s,%s) gpPan=(%s,%s) rootLX=%s focusLX=%s subjLX=%s",
            t, frameIndex, tostring(post.phase), tostring(post.isThirdPerson),
            str(post.locked), str(post.offset), str(round(post.currentSubjectDistance,4)),
            str(round(prx,6)), str(round(pry,6)), str(round(pox,6)), str(round(poy,6)),
            str(round(angleDelta(post.cameraYawDeg, pre and pre.cameraYawDeg),6)),
            str(round(angleDelta(post.cameraPitchDeg, pre and pre.cameraPitchDeg),6)),
            str(round(angleDelta(post.evadeYawDeg, pre and pre.evadeYawDeg),6)),
            str(round(angleDelta(post.evadePitchDeg, pre and pre.evadePitchDeg),6)),
            str(round(gpx,6)), str(round(gpy,6)),
            str(round(post.rootLocalX,6)), str(round(post.focusLocalX,6)), str(round(post.subjectLocalX,6))
        )
    end
end

local function connect(sig, fn)
    if not sig then return end
    local c = safe(function() return sig:Connect(fn) end, nil)
    if c then connections[#connections+1] = c end
end

local function recordInputChanged(input, gpe)
    if not running then return end
    local typ = tostring(input.UserInputType)
    local now = os.clock()
    local cam = Workspace.CurrentCamera
    local vw = cam and cam.ViewportSize.X or 0

    if has(typ, "touch") then
        local pos = safe(function() return input.Position end, nil)
        local delta = safe(function() return input.Delta end, nil)
        local x,y = v2xy(delta)
        local px = select(1, v2xy(pos))
        local right = type(px) == "number" and vw > 0 and px >= vw * 0.5
        if right then
            inputStats.touchRightCount += 1
            push(inputStats.touchRightDX, x)
            push(inputStats.touchRightDY, y)
            if lastTouchRightAt then push(inputStats.touchRightDt, now-lastTouchRightAt) end
            lastTouchRightAt = now
        else
            inputStats.touchLeftCount += 1
            push(inputStats.touchLeftDX, x)
            push(inputStats.touchLeftDY, y)
        end
    elseif has(typ, "gamepad") then
        local key = tostring(safe(function() return input.KeyCode end, nil))
        if has(key, "thumbstick2") then
            local pos = safe(function() return input.Position end, nil)
            local x,y = v2xy(pos)
            inputStats.gamepadThumb2Count += 1
            push(inputStats.gamepadThumb2X, x)
            push(inputStats.gamepadThumb2Y, y)
            if lastGamepadThumb2At then push(inputStats.gamepadThumb2Dt, now-lastGamepadThumb2At) end
            lastGamepadThumb2At = now
        end
    end
end

connect(UIS.InputChanged, recordInputChanged)
connect(UIS.LastInputTypeChanged, function(t)
    if running then addEvent("LastInputTypeChanged " .. str(t)) end
end)
local prefSig = safe(function() return UIS:GetPropertyChangedSignal("PreferredInput") end, nil)
connect(prefSig, function()
    if running then addEvent("PreferredInputChanged " .. str(safe(function() return UIS.PreferredInput end,nil))) end
end)

local function compactState(s)
    if not s then return "nil" end
    return table.concat({
        "phase="..tostring(s.phase),
        "preferredInput="..tostring(s.preferredInput),
        "lastInputType="..tostring(s.lastInputType),
        "connectedGamepads="..tostring(s.connectedGamepads),
        "mouseBehavior="..tostring(s.mouseBehavior),
        "rotationType="..tostring(s.rotationType),
        "playerCameraMode="..tostring(s.playerCameraMode),
        "cameraType="..tostring(s.cameraType),
        "cameraSubject="..tostring(s.cameraSubject),
        "cameraControllerId="..tostring(s.cameraControllerId),
        "cameraControllerUpdate="..tostring(s.cameraControllerUpdate),
        "controlControllerId="..tostring(s.controlControllerId),
        "controlControllerUpdate="..tostring(s.controlControllerUpdate),
        "locked="..str(s.locked),
        "offset="..str(s.offset),
        "inFirstPerson="..str(s.inFirstPerson),
        "subjectDistance="..str(round(s.currentSubjectDistance,5)),
        "cameraMovementMode="..str(s.cameraMovementMode),
        "panEnabled="..str(s.panEnabled),
        "userPanningCamera="..str(s.userPanningCamera),
        "userPanningTheCamera="..str(s.userPanningTheCamera),
        "gamepadPanningCamera="..str(s.gamepadPanningCamera),
        "rotateInput="..str(s.rotateInput),
        "rootLocalX="..str(round(s.rootLocalX,6)),
        "headLocalX="..str(round(s.headLocalX,6)),
        "focusLocalX="..str(round(s.focusLocalX,6)),
        "subjectLocalX="..str(round(s.subjectLocalX,6)),
        "isThirdPerson="..tostring(s.isThirdPerson),
        "thirdPersonReason="..tostring(s.thirdPersonReason),
    }, " | ")
end

local function formatReport()
    local lines = {}
    local function add(x) lines[#lines+1] = tostring(x) end

    add("=== BURACO ROTATION X9 R2 REPORT ===")
    add("version = " .. VERSION)
    add("placeId = " .. tostring(game.PlaceId))
    add("gameId = " .. tostring(game.GameId))
    add("captureSeconds = " .. tostring(CAPTURE_SECONDS))
    add("warmupSeconds = " .. tostring(WARMUP_SECONDS))
    add("observationalOnly = true")
    add("writesCameraCFrame = false")
    add("writesCameraFocus = false")
    add("writesRootPartCFrame = false")
    add("forcesPreferredInput = false")
    add("forcesMouseBehavior = false")
    add("forcesRotationType = false")
    add("forcesMouseLockOrOffset = false")
    add("changesGainSensitivityFOVZoomPhysics = false")
    add("")

    add("=== RUN IDENTITY ===")
    add("inputPhaseAtStart = " .. tostring(inputPhaseAtStart))
    add("valid3PFrames = " .. tostring(valid3PFrames))
    add("invalid3PFrames = " .. tostring(invalid3PFrames))
    add("controllerSwapCount = " .. tostring(controllerSwapCount))
    add("cameraCFrameValue = " .. str(cameraCFrameValue))
    add("")

    add("=== START STATE ===")
    add(compactState(startState))
    add("")
    add("=== END STATE ===")
    add(compactState(endState))
    add("")

    add("=== START/END CONTROLLER DIGEST ===")
    add("start.cameraController = " .. tostring(startDigest and startDigest.cameraController))
    add("start.controlController = " .. tostring(startDigest and startDigest.controlController))
    add("end.cameraController = " .. tostring(endDigest and endDigest.cameraController))
    add("end.controlController = " .. tostring(endDigest and endDigest.controlController))
    add("")

    add("=== RAW INPUT PATH ===")
    add("touchRightCount = " .. tostring(inputStats.touchRightCount))
    add("touchRightDX = " .. statText(inputStats.touchRightDX))
    add("touchRightDY = " .. statText(inputStats.touchRightDY))
    add("touchRightEventDt = " .. statText(inputStats.touchRightDt))
    add("touchLeftCount = " .. tostring(inputStats.touchLeftCount))
    add("touchLeftDX = " .. statText(inputStats.touchLeftDX))
    add("touchLeftDY = " .. statText(inputStats.touchLeftDY))
    add("gamepadThumb2Count = " .. tostring(inputStats.gamepadThumb2Count))
    add("gamepadThumb2X = " .. statText(inputStats.gamepadThumb2X))
    add("gamepadThumb2Y = " .. statText(inputStats.gamepadThumb2Y))
    add("gamepadThumb2EventDt = " .. statText(inputStats.gamepadThumb2Dt))
    add("")

    add("=== ROTATION PIPELINE STATS ===")
    for _,k in ipairs(statNames) do
        add(k .. " = " .. statText(stats[k]))
    end
    add("")

    add("=== TIMELINE 5 HZ ===")
    for _,line in ipairs(timeline) do add(line) end
    add("")

    add("=== EVENTS ===")
    for _,line in ipairs(events) do add(line) end
    add("")

    add("=== INTERPRETATION CONTRACT ===")
    add("This report does NOT claim that Gamepad equals PC.")
    add("Compare Touch and Gamepad only while valid3PFrames dominate and invalid3PFrames is near zero.")
    add("Shared lock/offset/rootLocalX geometry is not treated as the differentiator.")
    add("Primary target: first stage where raw input -> rotateInput -> camera delta -> final local geometry diverges.")
    add("No screen-error correction, no gain tuning, no RootPart/Camera CFrame forcing.")

    return table.concat(lines, "\n")
end

local function stopCapture(auto)
    if not running and not armed then return end
    armed = false
    if running then
        endState = captureCore()
        endDigest = snapshotDigest()
        running = false
        addEvent("STOP auto=" .. tostring(auto))
    end
    if statusLabel then
        statusLabel.Text = "PARADO • COPIE O REPORT"
    end
    if copyButton then copyButton.Text = "COPIAR REPORT" end
    notify("Captura acabou. Copie o report.", 4)
end

local function startCapture()
    if running or armed then return end
    resetRun()
    armed = true
    cameraCFrameValue = findCameraCFrameValue()

    if statusLabel then statusLabel.Text = "AQUECENDO 1.5s • FIQUE EM 3P" end
    notify("1.5 s de aquecimento. Fique em 3ª pessoa.", 3)

    task.spawn(function()
        task.wait(WARMUP_SECONDS)
        if not armed then return end

        inputPhaseAtStart = preferredClass()
        startState = captureCore()
        startDigest = snapshotDigest()
        captureStart = os.clock()
        running = true
        armed = false
        lastControllerId = startState.cameraControllerId
        addEvent("START phase=" .. tostring(inputPhaseAtStart))

        if statusLabel then
            statusLabel.Text = "GRAVANDO 18s • 3P • GIRE + ANDE"
        end
        notify("GRAVANDO. 3P: ande, esquerda/direita, cima/baixo.", 4)

        local token = captureStart
        task.wait(CAPTURE_SECONDS)
        if running and captureStart == token then
            stopCapture(true)
        end
    end)
end

local function copyReport()
    local report = formatReport()
    local copied = false
    local fns = {}
    if type(ENV.setclipboard) == "function" then fns[#fns+1] = ENV.setclipboard end
    if type(ENV.toclipboard) == "function" then fns[#fns+1] = ENV.toclipboard end
    if type(setclipboard) == "function" then fns[#fns+1] = setclipboard end
    if type(toclipboard) == "function" then fns[#fns+1] = toclipboard end
    for _,fn in ipairs(fns) do
        if pcall(fn, report) then copied = true break end
    end

    if type(writefile) == "function" then
        local suffix = tostring(inputPhaseAtStart or "UNKNOWN")
        pcall(writefile, "BuracoRotationX9R2_" .. suffix .. "_Report.txt", report)
    end

    if statusLabel then
        statusLabel.Text = copied and "REPORT COPIADO ✓" or "ARQUIVO TENTADO • clipboard indisponível"
    end
    notify(copied and "Report copiado." or "Clipboard indisponível; arquivo foi tentado.", 4)
    return report
end

local function makeButton(parent,textValue,order)
    local b = Instance.new("TextButton")
    b.LayoutOrder = order
    b.Size = UDim2.new(1,0,0,38)
    b.BackgroundColor3 = Color3.fromRGB(32,41,58)
    b.BorderSizePixel = 0
    b.Text = textValue
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0,9)
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
    panel.Size = UDim2.fromOffset(310,270)
    panel.Position = UDim2.new(1,-322,0.5,-135)
    panel.BackgroundColor3 = Color3.fromRGB(13,18,28)
    panel.BackgroundTransparency = 0.03
    panel.BorderSizePixel = 0
    panel.Active = true
    panel.Draggable = true
    panel.Parent = gui
    local pc = Instance.new("UICorner")
    pc.CornerRadius = UDim.new(0,13)
    pc.Parent = panel

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1,-48,0,30)
    title.Position = UDim2.fromOffset(12,8)
    title.BackgroundTransparency = 1
    title.Text = "BURACO X9 R2 • ROTAÇÃO"
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.new(1,1,1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.Parent = panel

    local close = Instance.new("TextButton")
    close.Size = UDim2.fromOffset(30,30)
    close.Position = UDim2.new(1,-38,0,7)
    close.BackgroundColor3 = Color3.fromRGB(45,54,70)
    close.BorderSizePixel = 0
    close.Text = "×"
    close.TextColor3 = Color3.new(1,1,1)
    close.TextSize = 18
    close.Font = Enum.Font.GothamBold
    close.Parent = panel
    local cc = Instance.new("UICorner")
    cc.CornerRadius = UDim.new(0,8)
    cc.Parent = close

    local body = Instance.new("Frame")
    body.Size = UDim2.new(1,-24,1,-48)
    body.Position = UDim2.fromOffset(12,42)
    body.BackgroundTransparency = 1
    body.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0,6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = body

    local help = Instance.new("TextLabel")
    help.LayoutOrder = 0
    help.Size = UDim2.new(1,0,0,66)
    help.BackgroundColor3 = Color3.fromRGB(23,30,43)
    help.BorderSizePixel = 0
    help.Text = "ÚLTIMO A/B • SÓ 3ª PESSOA\nRun 1 Touch • Run 2 Controle\n18s: ande + esquerda/direita + cima/baixo"
    help.TextWrapped = true
    help.TextColor3 = Color3.fromRGB(220,226,235)
    help.Font = Enum.Font.Gotham
    help.TextSize = 11
    help.Parent = body
    local hc = Instance.new("UICorner")
    hc.CornerRadius = UDim.new(0,8)
    hc.Parent = help

    inputLabel = Instance.new("TextLabel")
    inputLabel.LayoutOrder = 1
    inputLabel.Size = UDim2.new(1,0,0,24)
    inputLabel.BackgroundTransparency = 1
    inputLabel.Text = "INPUT: " .. preferredClass()
    inputLabel.TextColor3 = Color3.fromRGB(160,210,255)
    inputLabel.Font = Enum.Font.GothamBold
    inputLabel.TextSize = 12
    inputLabel.Parent = body

    local start = makeButton(body,"INICIAR 18s",2)
    local stop = makeButton(body,"PARAR",3)
    copyButton = makeButton(body,"COPIAR REPORT",4)

    statusLabel = Instance.new("TextLabel")
    statusLabel.LayoutOrder = 5
    statusLabel.Size = UDim2.new(1,0,0,28)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Pronto • somente leitura • 3P"
    statusLabel.TextWrapped = true
    statusLabel.TextColor3 = Color3.fromRGB(170,180,195)
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 10
    statusLabel.Parent = body

    uiConnections[#uiConnections+1] = start.Activated:Connect(startCapture)
    uiConnections[#uiConnections+1] = stop.Activated:Connect(function() stopCapture(false) end)
    uiConnections[#uiConnections+1] = copyButton.Activated:Connect(function()
        if running or armed then stopCapture(false) end
        copyReport()
    end)
    uiConnections[#uiConnections+1] = close.Activated:Connect(function()
        if running or armed then stopCapture(false) end
        if ENV.__BuracoRotationX9R2Cleanup then pcall(ENV.__BuracoRotationX9R2Cleanup) end
    end)
end

pcall(function()
    RunService:UnbindFromRenderStep(BIND_PRE)
    RunService:UnbindFromRenderStep(BIND_POST)
end)

RunService:BindToRenderStep(BIND_PRE, Enum.RenderPriority.Camera.Value - 2, capturePre)
RunService:BindToRenderStep(BIND_POST, Enum.RenderPriority.Camera.Value + 8, postFrame)

ENV.BuracoRotationX9R2Start = startCapture
ENV.BuracoRotationX9R2Stop = stopCapture
ENV.BuracoRotationX9R2Report = formatReport
ENV.BuracoRotationX9R2Copy = copyReport

createUI()

ENV.__BuracoRotationX9R2Cleanup = function()
    running = false
    armed = false
    pcall(function() RunService:UnbindFromRenderStep(BIND_PRE) end)
    pcall(function() RunService:UnbindFromRenderStep(BIND_POST) end)
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    for _,c in ipairs(uiConnections) do pcall(function() c:Disconnect() end) end
    connections = {}
    uiConnections = {}
    if gui then pcall(function() gui:Destroy() end) end
    gui = nil
    ENV.BuracoRotationX9R2Start = nil
    ENV.BuracoRotationX9R2Stop = nil
    ENV.BuracoRotationX9R2Report = nil
    ENV.BuracoRotationX9R2Copy = nil
    ENV.__BuracoRotationX9R2Cleanup = nil
end

notify("Pronto. Faça Touch 3P e Controle 3P em runs separados.", 5)
warn("[" .. VERSION .. "] ready | read-only | 3P only | 18 s per run")
