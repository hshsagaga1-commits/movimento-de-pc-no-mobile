local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local EXPECTED_PLACE = 96537472072550
local RECORD_SECONDS = 22
local SAMPLE_HZ = 30
local SAMPLE_STEP = 1 / SAMPLE_HZ
local OUT_FILE = "LegacyProbe.txt"

local lines = {}
local connections = {}
local startClock = os.clock()
local lastSample = -1e9
local finished = false
local character, humanoid, root, animator
local controls, cameras
local playerModule
local activeController

local function now()
    return os.clock() - startClock
end

local function safe(v)
    if v == nil then return "nil" end
    local ok, s = pcall(function() return tostring(v) end)
    return ok and s or "<?>"
end

local function fmtNum(v)
    if type(v) ~= "number" then return "nil" end
    return string.format("%.5f", v)
end

local function vec2(v)
    if typeof(v) ~= "Vector2" then return "nil" end
    return string.format("%.4f,%.4f", v.X, v.Y)
end

local function vec3(v)
    if typeof(v) ~= "Vector3" then return "nil" end
    return string.format("%.4f,%.4f,%.4f", v.X, v.Y, v.Z)
end

local function log(tag, text)
    lines[#lines + 1] = string.format("%.4f\t%s\t%s", now(), tag, text or "")
end

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = 5,
        })
    end)
end

local function addConnection(c)
    if c then connections[#connections + 1] = c end
    return c
end

local function getPlayerModule()
    if playerModule then return playerModule end
    pcall(function()
        local ps = player:FindFirstChild("PlayerScripts")
        local pm = ps and ps:FindFirstChild("PlayerModule")
        if pm then
            local r = require(pm)
            if type(r) == "table" then playerModule = r end
        end
    end)
    return playerModule
end

local function getControls()
    if controls then return controls end
    local pm = getPlayerModule()
    pcall(function()
        if pm and type(pm.GetControls) == "function" then controls = pm:GetControls() end
    end)
    return controls
end

local function getCameras()
    if cameras then return cameras end
    local pm = getPlayerModule()
    pcall(function()
        if pm and type(pm.GetCameras) == "function" then cameras = pm:GetCameras() end
    end)
    return cameras
end

local function getActiveController()
    local cm = getCameras()
    local controller
    pcall(function()
        if cm and type(cm.GetActiveCameraController) == "function" then
            controller = cm:GetActiveCameraController()
        end
    end)
    activeController = controller or activeController
    return controller
end

local function bindCharacter(char)
    character = char
    humanoid = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
    root = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 10)
    animator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5))
    log("CHAR", "bound=" .. char:GetFullName())

    if humanoid then
        local props = {"WalkSpeed", "HipHeight", "AutoRotate", "JumpPower", "JumpHeight", "CameraOffset"}
        for _, prop in ipairs(props) do
            pcall(function()
                addConnection(humanoid:GetPropertyChangedSignal(prop):Connect(function()
                    local value = humanoid[prop]
                    log("HUM_" .. prop, safe(value))
                end))
            end)
        end
        pcall(function()
            addConnection(humanoid.StateChanged:Connect(function(oldState, newState)
                log("HUM_STATE", safe(oldState) .. " -> " .. safe(newState))
            end))
        end)
    end

    if animator then
        pcall(function()
            addConnection(animator.AnimationPlayed:Connect(function(track)
                local animId = ""
                pcall(function()
                    if track.Animation then animId = track.Animation.AnimationId end
                end)
                log("ANIM_PLAY", table.concat({
                    "name=" .. safe(track.Name),
                    "id=" .. safe(animId),
                    "priority=" .. safe(track.Priority),
                    "length=" .. fmtNum(track.Length),
                    "speed=" .. fmtNum(track.Speed),
                    "looped=" .. safe(track.Looped),
                }, " "))
                pcall(function()
                    addConnection(track.Stopped:Connect(function()
                        log("ANIM_STOP", "name=" .. safe(track.Name) .. " id=" .. safe(animId))
                    end))
                end)
            end))
        end)
    end
end

local function dumpTree(rootInst, tag, maxDepth)
    if not rootInst then
        log(tag, "MISSING")
        return
    end
    local baseDepth = 0
    local function depthOf(inst)
        local d, p = 0, inst
        while p and p ~= rootInst do d += 1; p = p.Parent end
        return d
    end
    log(tag, "ROOT " .. rootInst:GetFullName() .. " <" .. rootInst.ClassName .. ">")
    for _, inst in ipairs(rootInst:GetDescendants()) do
        local d = depthOf(inst)
        if d <= maxDepth then
            log(tag, string.rep("  ", d) .. inst.Name .. " <" .. inst.ClassName .. ">")
        end
    end
end

local function connectBindable(inst, label)
    if not inst then return end
    if inst:IsA("BindableEvent") then
        addConnection(inst.Event:Connect(function(...)
            local a = table.pack(...)
            local parts = {}
            for i = 1, a.n do
                if type(a[i]) == "table" then
                    local ok, json = pcall(function() return HttpService:JSONEncode(a[i]) end)
                    parts[#parts+1] = ok and json or safe(a[i])
                else
                    parts[#parts+1] = safe(a[i])
                end
            end
            log("EVENT_" .. label, table.concat(parts, " | "))
        end))
    elseif inst:IsA("RemoteEvent") then
        addConnection(inst.OnClientEvent:Connect(function(...)
            local a = table.pack(...)
            local parts = {}
            for i = 1, a.n do parts[#parts+1] = safe(a[i]) end
            log("REMOTE_" .. label, table.concat(parts, " | "))
        end))
    end
end

local function findPath(rootInst, path)
    local cur = rootInst
    for part in string.gmatch(path, "[^/]+") do
        cur = cur and cur:FindFirstChild(part)
    end
    return cur
end

local function inspectConnections(inst, label)
    if not inst or type(getconnections) ~= "function" then
        log("CONNECTIONS", label .. " getconnections=unavailable")
        return
    end
    local signal
    pcall(function()
        if inst:IsA("BindableEvent") then signal = inst.Event
        elseif inst:IsA("RemoteEvent") then signal = inst.OnClientEvent end
    end)
    if not signal then return end
    local ok, list = pcall(getconnections, signal)
    if not ok or type(list) ~= "table" then return end
    log("CONNECTIONS", label .. " count=" .. tostring(#list))
    for i, c in ipairs(list) do
        local fn
        pcall(function() fn = c.Function end)
        if type(fn) == "function" then
            local src, name, line = "?", "?", "?"
            pcall(function() src = debug.info(fn, "s") end)
            pcall(function() name = debug.info(fn, "n") end)
            pcall(function() line = debug.info(fn, "l") end)
            log("CONN_FN", string.format("%s[%d] src=%s name=%s line=%s", label, i, safe(src), safe(name), safe(line)))
            if debug and type(debug.getconstants) == "function" then
                pcall(function()
                    local cs = debug.getconstants(fn)
                    local out = {}
                    for _, v in ipairs(cs) do
                        if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
                            out[#out+1] = safe(v)
                        end
                        if #out >= 80 then break end
                    end
                    log("CONN_CONST", label .. "[" .. i .. "] " .. table.concat(out, " ; "))
                end)
            end
        end
    end
end

local function scanGC()
    if type(getgc) ~= "function" or not debug or type(debug.getconstants) ~= "function" then
        log("GC", "getgc/debug.getconstants unavailable")
        return
    end
    local needles = {
        Crouch=true, crouch=true, KeybindUsed=true, UseKeybind=true, Stand=true,
        HipHeight=true, CameraOffset=true, MoveDirection=true, WalkSpeed=true,
    }
    local ok, objs = pcall(getgc, true)
    if not ok or type(objs) ~= "table" then
        log("GC", "getgc failed")
        return
    end
    local hits = 0
    for _, obj in ipairs(objs) do
        if type(obj) == "function" then
            local okc, cs = pcall(debug.getconstants, obj)
            if okc and type(cs) == "table" then
                local matched = {}
                for _, c in ipairs(cs) do
                    if type(c) == "string" and needles[c] then matched[c] = true end
                end
                if next(matched) then
                    hits += 1
                    local src, name, line = "?", "?", "?"
                    pcall(function() src = debug.info(obj, "s") end)
                    pcall(function() name = debug.info(obj, "n") end)
                    pcall(function() line = debug.info(obj, "l") end)
                    local keys = {}
                    for k in pairs(matched) do keys[#keys+1] = k end
                    table.sort(keys)
                    log("GC_FN", "match=" .. table.concat(keys, ",") .. " src=" .. safe(src) .. " name=" .. safe(name) .. " line=" .. safe(line))
                    local printable = {}
                    for _, c in ipairs(cs) do
                        if type(c) == "string" or type(c) == "number" or type(c) == "boolean" then
                            printable[#printable+1] = safe(c)
                        end
                        if #printable >= 120 then break end
                    end
                    log("GC_CONST", table.concat(printable, " ; "))
                    if hits >= 120 then break end
                end
            end
        end
    end
    log("GC", "hits=" .. tostring(hits))
end

local function watchStandGui()
    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    local controlsGui = pg:FindFirstChild("ControlsGui", true)
    if not controlsGui then
        log("GUI", "ControlsGui not found")
        return
    end
    local pcFrame = controlsGui:FindFirstChild("PCFrame", true)
    local stand = pcFrame and pcFrame:FindFirstChild("Stand", true)
    if stand and stand:IsA("GuiObject") then
        log("GUI", "Stand found visible=" .. safe(stand.Visible) .. " path=" .. stand:GetFullName())
        addConnection(stand:GetPropertyChangedSignal("Visible"):Connect(function()
            log("GUI_STAND_VISIBLE", safe(stand.Visible))
        end))
    else
        log("GUI", "ControlsGui exists but PCFrame/Stand missing")
    end
end

local function sample()
    local cam = Workspace.CurrentCamera
    if not cam or not humanoid or not root then return end

    local pitch, yaw, roll = 0, 0, 0
    pcall(function() pitch, yaw, roll = cam.CFrame:ToOrientation() end)

    local controlMove = Vector3.zero
    local controlRelative = "nil"
    local c = getControls()
    if c then
        pcall(function() controlMove = c:GetMoveVector() end)
        pcall(function()
            if type(c.GetActiveController) == "function" then
                local ac = c:GetActiveController()
                if ac and type(ac.IsMoveVectorCameraRelative) == "function" then
                    controlRelative = safe(ac:IsMoveVectorCameraRelative())
                end
            end
        end)
    end

    local controller = getActiveController()
    local mouseLocked, lockOffset, cameraDistance, subjectPos = "nil", "nil", "nil", "nil"
    if controller then
        pcall(function()
            if type(controller.GetIsMouseLocked) == "function" then mouseLocked = safe(controller:GetIsMouseLocked()) end
        end)
        pcall(function()
            if type(controller.GetMouseLockOffset) == "function" then lockOffset = vec3(controller:GetMouseLockOffset()) end
        end)
        pcall(function()
            if type(controller.GetCameraToSubjectDistance) == "function" then cameraDistance = fmtNum(controller:GetCameraToSubjectDistance()) end
        end)
        pcall(function()
            if type(controller.GetSubjectPosition) == "function" then subjectPos = vec3(controller:GetSubjectPosition()) end
        end)
    end

    local vel = Vector3.zero
    pcall(function() vel = root.AssemblyLinearVelocity end)
    local state = "nil"
    pcall(function() state = humanoid:GetState().Name end)

    log("SAMPLE", table.concat({
        "camPos=" .. vec3(cam.CFrame.Position),
        "pitch=" .. fmtNum(math.deg(pitch)),
        "yaw=" .. fmtNum(math.deg(yaw)),
        "fov=" .. fmtNum(cam.FieldOfView),
        "fovMode=" .. safe(cam.FieldOfViewMode),
        "camType=" .. safe(cam.CameraType),
        "subject=" .. safe(cam.CameraSubject and cam.CameraSubject:GetFullName()),
        "rootPos=" .. vec3(root.Position),
        "rootVel=" .. vec3(vel),
        "moveDir=" .. vec3(humanoid.MoveDirection),
        "controlMove=" .. vec3(controlMove),
        "controlRelative=" .. controlRelative,
        "walkSpeed=" .. fmtNum(humanoid.WalkSpeed),
        "hipHeight=" .. fmtNum(humanoid.HipHeight),
        "state=" .. state,
        "floor=" .. safe(humanoid.FloorMaterial),
        "mouseLocked=" .. mouseLocked,
        "lockOffset=" .. lockOffset,
        "camDist=" .. cameraDistance,
        "subjectPos=" .. subjectPos,
    }, " "))
end

local function dumpEnvironment()
    log("PROBE", "version=2 placeId=" .. tostring(game.PlaceId) .. " expected=" .. tostring(EXPECTED_PLACE))
    log("DEVICE", "TouchEnabled=" .. safe(UserInputService.TouchEnabled) .. " MouseEnabled=" .. safe(UserInputService.MouseEnabled) .. " KeyboardEnabled=" .. safe(UserInputService.KeyboardEnabled))
    local cam = Workspace.CurrentCamera
    if cam then
        log("CAM_INIT", "viewport=" .. vec2(cam.ViewportSize) .. " fov=" .. fmtNum(cam.FieldOfView) .. " mode=" .. safe(cam.FieldOfViewMode) .. " type=" .. safe(cam.CameraType))
    end
    local ugs
    pcall(function() ugs = UserSettings():GetService("UserGameSettings") end)
    if ugs then
        pcall(function() log("UGS", "RotationType=" .. safe(ugs.RotationType)) end)
        pcall(function() log("UGS", "TouchCameraMovementMode=" .. safe(ugs.TouchCameraMovementMode)) end)
        pcall(function() log("UGS", "MouseSensitivity=" .. safe(ugs.MouseSensitivity)) end)
        pcall(function() log("UGS", "GamepadCameraSensitivity=" .. safe(ugs.GamepadCameraSensitivity)) end)
    end

    local ps = player:FindFirstChild("PlayerScripts")
    dumpTree(ps, "PLAYER_SCRIPTS", 5)

    local events = ps and ps:FindFirstChild("Events")
    if events then
        local keybindUsed = events:FindFirstChild("KeybindUsed")
        local temp = events:FindFirstChild("temporary_events")
        local useKeybind = temp and temp:FindFirstChild("UseKeybind")
        log("EVENT_PATH", "KeybindUsed=" .. safe(keybindUsed and keybindUsed.ClassName) .. " UseKeybind=" .. safe(useKeybind and useKeybind.ClassName))
        connectBindable(keybindUsed, "KeybindUsed")
        connectBindable(useKeybind, "UseKeybind")
        inspectConnections(keybindUsed, "KeybindUsed")
        inspectConnections(useKeybind, "UseKeybind")
    else
        log("EVENT_PATH", "Events missing")
    end

    watchStandGui()
end

local function finish()
    if finished then return end
    finished = true
    log("PROBE", "FINISH")

    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end

    local report = table.concat(lines, "\n")
    local wrote = false
    if type(writefile) == "function" then
        wrote = pcall(function() writefile(OUT_FILE, report) end)
    end
    if type(setclipboard) == "function" then
        pcall(function() setclipboard(report) end)
    end

    notify("Legacy Probe terminou", wrote and (OUT_FILE .. " salvo + relatório copiado") or "Relatório copiado para a área de transferência")
    print("[LEGACY_PROBE_DONE] lines=" .. tostring(#lines) .. " file=" .. OUT_FILE)
end

if player.Character then bindCharacter(player.Character) end
addConnection(player.CharacterAdded:Connect(bindCharacter))

dumpEnvironment()
task.spawn(scanGC)

notify("Legacy Probe", "22s: corra, vire a câmera, agache/levante várias vezes e pule. NÃO execute o movement script junto.")
print("[LEGACY_PROBE_START] " .. tostring(RECORD_SECONDS) .. " seconds")

addConnection(RunService.RenderStepped:Connect(function()
    local t = now()
    if t - lastSample >= SAMPLE_STEP then
        lastSample = t
        sample()
    end
    if t >= RECORD_SECONDS then
        finish()
    end
end))

task.delay(RECORD_SECONDS + 2, finish)
