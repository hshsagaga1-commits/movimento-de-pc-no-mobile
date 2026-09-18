-- CameraX9Compare.lua
-- Read-only comparative camera probe for Evade Overhaul mobile vs Legacy mobile.
-- Goal: observe the mechanism that keeps character composition stable in screen-space
-- without changing Camera.CFrame, Camera.Focus, character CFrame, input routing, gain,
-- PlayerModule, mouse-lock state, or any game behavior.
--
-- Same file must be used in both modes. The report records the real runtime ViewportSize,
-- normalized screen-space coordinates, camera-local geometry, render-phase camera writes,
-- input/mouse-lock state, and old/new PlayerModule architecture clues.
--
-- Compatibility rule: newer Overhaul APIs are optional. Missing legacy fields/methods are
-- reported as unavailable instead of failing the probe.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local ENV = (type(getgenv) == "function" and getgenv()) or _G

local VERSION = "X9-COMPARE-R1"
local LEGACY_PLACE_ID = 96537472072550
local DEFAULT_SECONDS = 14
local DEFAULT_HZ = 30
local duration = math.clamp(tonumber(ENV.CameraX9CompareSeconds) or DEFAULT_SECONDS, 5, 30)
local sampleHz = math.clamp(tonumber(ENV.CameraX9CompareHz) or DEFAULT_HZ, 10, 60)
local sampleDt = 1 / sampleHz
local deepScan = ENV.CameraX9DeepScan == true

local camera = Workspace.CurrentCamera
local lines = {}
local connections = {}
local finished = false
local startClock = os.clock()
local lastSample = -1e9
local sampleIndex = 0
local phaseFrame = 0

local function now()
    return os.clock() - startClock
end

local function safeText(v)
    if v == nil then return "nil" end
    local ok, s = pcall(function() return tostring(v) end)
    return ok and s or "<?>"
end

local function num(v, digits)
    if type(v) ~= "number" then return "nil" end
    return string.format("%." .. tostring(digits or 6) .. "f", v)
end

local function v2(v)
    if typeof(v) ~= "Vector2" then return "nil" end
    return string.format("%.4f,%.4f", v.X, v.Y)
end

local function v3(v)
    if typeof(v) ~= "Vector3" then return "nil" end
    return string.format("%.5f,%.5f,%.5f", v.X, v.Y, v.Z)
end

local function cfpos(cf)
    if typeof(cf) ~= "CFrame" then return "nil" end
    return v3(cf.Position)
end

local function add(s)
    lines[#lines+1] = tostring(s)
end

local function addKV(k, v)
    add(tostring(k) .. " = " .. safeText(v))
end

local function safeProp(obj, key)
    if obj == nil then return nil end
    local out
    pcall(function() out = obj[key] end)
    return out
end

local function safeMethod(obj, key, ...)
    if obj == nil then return nil end
    local fn = safeProp(obj, key)
    if type(fn) ~= "function" then return nil end
    local args = table.pack(...)
    local out
    local ok = pcall(function()
        out = fn(obj, table.unpack(args, 1, args.n))
    end)
    return ok and out or nil
end

local function keys(t, limit)
    if type(t) ~= "table" then return "<not-table>" end
    local a = {}
    for k in pairs(t) do
        a[#a+1] = tostring(k)
        if #a >= (limit or 160) then break end
    end
    table.sort(a)
    return table.concat(a, ",")
end

local function debugSource(fn)
    if type(fn) ~= "function" then return "nil" end
    local src, name, line = "?", "?", "?"
    if debug and type(debug.info) == "function" then
        pcall(function() src = debug.info(fn, "s") or "?" end)
        pcall(function() name = debug.info(fn, "n") or "?" end)
        pcall(function() line = debug.info(fn, "l") or "?" end)
    elseif debug and type(debug.getinfo) == "function" then
        pcall(function()
            local i = debug.getinfo(fn)
            if i then
                src = i.source or i.short_src or "?"
                name = i.name or "?"
                line = i.currentline or i.linedefined or "?"
            end
        end)
    end
    return string.format("src=%s name=%s line=%s", tostring(src), tostring(name), tostring(line))
end

local function findKeywords(fn)
    if not (debug and type(debug.getconstants) == "function") or type(fn) ~= "function" then
        return ""
    end
    local wanted = {
        ["Camera"]=true, ["CameraCFrame"]=true, ["MouseLock"]=true, ["ShiftLock"]=true,
        ["LockCenter"]=true, ["Focus"]=true, ["PrimaryPart"]=true, ["HumanoidRootPart"]=true,
        ["GetMouseDelta"]=true, ["Touch"]=true, ["RotationType"]=true, ["CameraOffset"]=true,
        ["MouseBehavior"]=true, ["CameraRelative"]=true,
    }
    local found = {}
    pcall(function()
        for _,c in ipairs(debug.getconstants(fn)) do
            if type(c) == "string" then
                for needle in pairs(wanted) do
                    if string.find(string.lower(c), string.lower(needle), 1, true) then
                        found[needle] = true
                    end
                end
            end
        end
    end)
    local out = {}
    for k in pairs(found) do out[#out+1] = k end
    table.sort(out)
    return table.concat(out, ",")
end

local function addConnection(c)
    if c then connections[#connections+1] = c end
    return c
end

local function notify(title, text, seconds)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = seconds or 5,
        })
    end)
end

local playerModule, cameras, controls
local function refreshPlayerModule()
    pcall(function()
        local ps = player:FindFirstChild("PlayerScripts")
        local pm = ps and ps:FindFirstChild("PlayerModule")
        if pm then
            local required = require(pm)
            if type(required) == "table" then
                playerModule = required
                if type(required.GetCameras) == "function" then
                    cameras = required:GetCameras()
                elseif type(rawget(required, "cameras")) == "table" then
                    cameras = rawget(required, "cameras")
                end
                if type(required.GetControls) == "function" then
                    controls = required:GetControls()
                elseif type(rawget(required, "controls")) == "table" then
                    controls = rawget(required, "controls")
                end
            end
        end
    end)
end
refreshPlayerModule()

local function getActiveCameraController()
    if type(cameras) ~= "table" then return nil end
    local c = rawget(cameras, "activeCameraController")
    if type(c) ~= "table" then
        c = safeMethod(cameras, "GetActiveCameraController")
    end
    return type(c) == "table" and c or nil
end

local function getMouseLockController()
    if type(cameras) ~= "table" then return nil end
    local c = rawget(cameras, "activeMouseLockController")
    if type(c) == "table" then return c end
    c = rawget(cameras, "mouseLockController")
    return type(c) == "table" and c or nil
end

local function getLockState(controller, lockController)
    local locked = safeMethod(controller, "GetIsMouseLocked")
    if type(locked) ~= "boolean" then locked = safeProp(controller, "inMouseLockedMode") end
    if type(locked) ~= "boolean" then locked = safeMethod(lockController, "GetIsMouseLocked") end
    if type(locked) ~= "boolean" then locked = safeProp(lockController, "isMouseLocked") end

    local offset = safeMethod(controller, "GetMouseLockOffset")
    if typeof(offset) ~= "Vector3" then offset = safeProp(controller, "mouseLockOffset") end
    if typeof(offset) ~= "Vector3" then offset = safeMethod(lockController, "GetMouseLockOffset") end
    return locked, offset
end

local function getCharacterParts()
    local char = player.Character
    if not char then return nil,nil,nil,nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    local head = char:FindFirstChild("Head")
    return char, hum, root, head
end

local function subjectPosition(cam, controller, root)
    local p = safeMethod(controller, "GetSubjectPosition")
    if typeof(p) == "Vector3" then return p, "controller.GetSubjectPosition" end

    local subject = cam and cam.CameraSubject
    if subject then
        if subject:IsA("BasePart") then
            return subject.Position, "CameraSubject.BasePart"
        elseif subject:IsA("Humanoid") then
            local r = subject.Parent and (subject.Parent:FindFirstChild("HumanoidRootPart") or subject.Parent.PrimaryPart)
            if r and r:IsA("BasePart") then return r.Position, "CameraSubject.HumanoidRoot" end
        elseif subject:IsA("Model") and subject.PrimaryPart then
            return subject.PrimaryPart.Position, "CameraSubject.ModelPrimary"
        end
    end
    if root and root:IsA("BasePart") then return root.Position, "root-fallback" end
    return nil, "nil"
end

local function project(cam, worldPos)
    if not cam or typeof(worldPos) ~= "Vector3" then return nil end
    local vp = cam.ViewportSize
    if vp.X <= 0 or vp.Y <= 0 then return nil end
    local p, onScreen = cam:WorldToViewportPoint(worldPos)
    return {
        x=p.X, y=p.Y, z=p.Z,
        u=p.X/vp.X, v=p.Y/vp.Y,
        cx=(p.X/vp.X)-0.5, cy=(p.Y/vp.Y)-0.5,
        on=onScreen,
    }
end

local function projText(p)
    if not p then return "nil" end
    return string.format(
        "u=%.6f,v=%.6f,cx=%.6f,cy=%.6f,z=%.5f,on=%s",
        p.u,p.v,p.cx,p.cy,p.z,tostring(p.on)
    )
end

local function cframeAngleDeg(a,b)
    if typeof(a) ~= "CFrame" or typeof(b) ~= "CFrame" then return nil end
    local rel = a:ToObjectSpace(b)
    local _, angle = rel:ToAxisAngle()
    return math.deg(math.abs(angle))
end

local function cframePosDelta(a,b)
    if typeof(a) ~= "CFrame" or typeof(b) ~= "CFrame" then return nil end
    return (a.Position-b.Position).Magnitude
end

local function yawPitch(cf)
    if typeof(cf) ~= "CFrame" then return nil,nil end
    local look = cf.LookVector
    local yaw = math.atan2(-look.X, -look.Z)
    local pitch = math.asin(math.clamp(look.Y,-1,1))
    return math.deg(yaw), math.deg(pitch)
end

local function statNew() return {n=0,mean=0,m2=0,min=math.huge,max=-math.huge} end
local function statAdd(s,x)
    if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then return end
    s.n += 1
    if x < s.min then s.min=x end
    if x > s.max then s.max=x end
    local d=x-s.mean
    s.mean += d/s.n
    s.m2 += d*(x-s.mean)
end
local function statLine(name,s)
    local sd = s.n > 1 and math.sqrt(math.max(0,s.m2/(s.n-1))) or 0
    if s.n == 0 then
        return name.." n=0"
    end
    return string.format("%s n=%d mean=%.8f sd=%.8f min=%.8f max=%.8f range=%.8f",
        name,s.n,s.mean,sd,s.min,s.max,s.max-s.min)
end

local stats = {
    rootCx=statNew(), rootCy=statNew(),
    headCx=statNew(), headCy=statNew(),
    focusCx=statNew(), focusCy=statNew(),
    subjectCx=statNew(), subjectCy=statNew(),
    camAxesCx=statNew(), camAxesCy=statNew(),
    rootLocalCx=statNew(), rootLocalCy=statNew(),
    prePostAngle=statNew(), postLateAngle=statNew(),
    prePostPos=statNew(), postLatePos=statNew(),
    camToRootLocalX=statNew(), camToRootLocalY=statNew(), camToRootLocalZ=statNew(),
    rootFocusDistance=statNew(), cameraSubjectDistance=statNew(),
    cframeWrites=statNew(), focusWrites=statNew(),
}

local preCF, postCF, lateCF
local preFocus, postFocus, lateFocus
local cframeWrites = 0
local focusWrites = 0
local totalCFrameChanges = 0
local totalFocusChanges = 0

if camera then
    addConnection(camera:GetPropertyChangedSignal("CFrame"):Connect(function()
        cframeWrites += 1
        totalCFrameChanges += 1
    end))
    addConnection(camera:GetPropertyChangedSignal("Focus"):Connect(function()
        focusWrites += 1
        totalFocusChanges += 1
    end))
end

local touchDelta = Vector2.zero
local cameraTouchDelta = Vector2.zero
local touchChanged = 0
local cameraTouchChanged = 0
local inputChangedTotal = 0

addConnection(UIS.InputChanged:Connect(function(input, gpe)
    inputChangedTotal += 1
    if input.UserInputType ~= Enum.UserInputType.Touch then return end
    touchChanged += 1
    local d = input.Delta
    touchDelta += Vector2.new(d.X,d.Y)

    local controller = getActiveCameraController()
    local fingerTouches = controller and safeProp(controller, "fingerTouches")
    if type(fingerTouches) == "table" then
        local native = fingerTouches[input]
        if native == false then
            cameraTouchChanged += 1
            cameraTouchDelta += Vector2.new(d.X,d.Y)
        end
    elseif not gpe then
        -- Classification unavailable on this generation. Keep a separate fallback only;
        -- the report marks it as unverified instead of treating it as native ownership.
    end
end))

local gui
local statusLabel
local copyButton
local stopButton

local function makeGui()
    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    local old = pg:FindFirstChild("CameraX9CompareGui")
    if old then old:Destroy() end

    gui = Instance.new("ScreenGui")
    gui.Name = "CameraX9CompareGui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = false
    gui.DisplayOrder = 100000
    gui.Parent = pg

    local frame = Instance.new("Frame")
    frame.Name = "Panel"
    frame.AnchorPoint = Vector2.new(0.5,0)
    frame.Position = UDim2.fromScale(0.5,0.03)
    frame.Size = UDim2.fromOffset(360,116)
    frame.BackgroundTransparency = 0.14
    frame.Parent = gui

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(10,8)
    title.Size = UDim2.new(1,-20,0,24)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.Text = "X9 CÂMERA • OVERHAUL ↔ LEGACY"
    title.TextWrapped = true
    title.Parent = frame

    statusLabel = Instance.new("TextLabel")
    statusLabel.BackgroundTransparency = 1
    statusLabel.Position = UDim2.fromOffset(10,34)
    statusLabel.Size = UDim2.new(1,-20,0,30)
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 13
    statusLabel.TextWrapped = true
    statusLabel.Text = "GRAVANDO • gire a câmera normalmente"
    statusLabel.Parent = frame

    stopButton = Instance.new("TextButton")
    stopButton.Position = UDim2.fromOffset(10,72)
    stopButton.Size = UDim2.new(0.48,-12,0,34)
    stopButton.Font = Enum.Font.GothamBold
    stopButton.TextSize = 13
    stopButton.Text = "PARAR"
    stopButton.Parent = frame

    copyButton = Instance.new("TextButton")
    copyButton.Position = UDim2.new(0.5,4,0,72)
    copyButton.Size = UDim2.new(0.5,-14,0,34)
    copyButton.Font = Enum.Font.GothamBold
    copyButton.TextSize = 13
    copyButton.Text = "COPIAR (ao terminar)"
    copyButton.AutoButtonColor = false
    copyButton.Active = false
    copyButton.Parent = frame
end
makeGui()

local function scanScriptNames()
    add("")
    add("[PLAYER_SCRIPTS_CAMERA_RELATED]")
    local ps = player:FindFirstChild("PlayerScripts")
    if not ps then
        add("PlayerScripts missing")
        return
    end
    local hits = 0
    for _,inst in ipairs(ps:GetDescendants()) do
        local n = string.lower(inst.Name)
        if string.find(n,"camera",1,true)
            or string.find(n,"mouse",1,true)
            or string.find(n,"shift",1,true)
            or string.find(n,"lock",1,true)
            or string.find(n,"control",1,true) then
            hits += 1
            add(string.format("%03d %s <%s>",hits,inst:GetFullName(),inst.ClassName))
            if hits >= 160 then
                add("...truncated...")
                break
            end
        end
    end
    add("cameraRelatedCount = "..tostring(hits))
end

local function connectionSnapshot(signal, label, cap)
    add("")
    add("["..label.."_CONNECTIONS]")
    if type(getconnections) ~= "function" then
        add("getconnections unavailable")
        return
    end
    local list
    local ok = pcall(function() list = getconnections(signal) end)
    if not ok or type(list) ~= "table" then
        add("getconnections failed")
        return
    end
    add("count = "..tostring(#list))
    for i,c in ipairs(list) do
        if i > (cap or 80) then add("...truncated..."); break end
        local fn
        pcall(function() fn = c.Function end)
        if type(fn) == "function" then
            add(string.format("%03d %s keywords=%s",i,debugSource(fn),findKeywords(fn)))
        else
            add(string.format("%03d function=unavailable",i))
        end
    end
end

local function controllerSnapshot()
    refreshPlayerModule()
    local controller = getActiveCameraController()
    local lockController = getMouseLockController()
    add("")
    add("[PLAYERMODULE_ARCHITECTURE]")
    addKV("playerModule.exists",type(playerModule)=="table")
    addKV("playerModule.keys",keys(playerModule,180))
    addKV("cameras.exists",type(cameras)=="table")
    addKV("cameras.keys",keys(cameras,220))
    addKV("controls.exists",type(controls)=="table")
    addKV("controls.keys",keys(controls,160))
    addKV("activeCameraController.exists",type(controller)=="table")
    addKV("activeCameraController.keys",keys(controller,240))
    addKV("mouseLockController.exists",type(lockController)=="table")
    addKV("mouseLockController.keys",keys(lockController,180))

    if type(controller)=="table" then
        for _,name in ipairs({
            "Update","GetSubjectPosition","GetCameraToSubjectDistance","GetIsMouseLocked",
            "GetMouseLockOffset","OnInputBegan","OnInputChanged","OnInputEnded","OnMouseMoved",
            "UpdateMouseBehavior","CalculateNewLookCFrame","GetCameraLookVector",
        }) do
            local fn = safeProp(controller,name)
            if type(fn)=="function" then
                add("controller."..name.." "..debugSource(fn).." keywords="..findKeywords(fn))
            end
        end
    end

    if type(lockController)=="table" then
        for _,name in ipairs({"GetIsMouseLocked","GetMouseLockOffset","UpdateMouseLockAvailability","OnMouseLockToggled"}) do
            local fn=safeProp(lockController,name)
            if type(fn)=="function" then
                add("mouseLockController."..name.." "..debugSource(fn).." keywords="..findKeywords(fn))
            end
        end
    end
end

local function deepCameraGCScan()
    add("")
    add("[OPTIONAL_DEEP_GC_CAMERA_SCAN]")
    if not deepScan then
        add("disabled (set getgenv().CameraX9DeepScan=true before loader to enable)")
        return
    end
    if type(getgc)~="function" or not (debug and type(debug.getconstants)=="function") then
        add("unavailable")
        return
    end
    local needles={"CameraCFrame","MouseLock","ShiftLock","LockCenter","GetMouseDelta","CameraOffset","RotationType","CameraRelative"}
    local objs
    local ok=pcall(function() objs=getgc(true) end)
    if not ok or type(objs)~="table" then add("getgc failed"); return end
    local hits=0
    for _,obj in ipairs(objs) do
        if type(obj)=="function" then
            local cs
            pcall(function() cs=debug.getconstants(obj) end)
            if type(cs)=="table" then
                local match={}
                for _,c in ipairs(cs) do
                    if type(c)=="string" then
                        local lc=string.lower(c)
                        for _,needle in ipairs(needles) do
                            if string.find(lc,string.lower(needle),1,true) then match[needle]=true end
                        end
                    end
                end
                if next(match) then
                    hits+=1
                    local a={}
                    for k in pairs(match) do a[#a+1]=k end
                    table.sort(a)
                    add(string.format("%03d %s match=%s",hits,debugSource(obj),table.concat(a,",")))
                    if hits>=80 then add("...truncated..."); break end
                end
            end
        end
    end
    add("deepHits = "..tostring(hits))
end

local function initialSnapshot()
    camera = Workspace.CurrentCamera
    add("=== CAMERA X9 OVERHAUL↔LEGACY / READ-ONLY ===")
    addKV("schema",VERSION)
    addKV("timestamp",os.date("%Y-%m-%d %H:%M:%S"))
    addKV("PlaceId",game.PlaceId)
    addKV("GameId",game.GameId)
    addKV("autoMode",game.PlaceId==LEGACY_PLACE_ID and "LEGACY_KNOWN_PLACE" or "NON_LEGACY_OR_UNKNOWN")
    addKV("durationSeconds",duration)
    addKV("sampleHz",sampleHz)
    addKV("deepScan",deepScan)
    add("")
    add("[DEVICE_INPUT]")
    addKV("TouchEnabled",safeProp(UIS,"TouchEnabled"))
    addKV("MouseEnabled",safeProp(UIS,"MouseEnabled"))
    addKV("KeyboardEnabled",safeProp(UIS,"KeyboardEnabled"))
    addKV("PreferredInput",safeProp(UIS,"PreferredInput"))
    addKV("LastInputType",UIS:GetLastInputType())
    addKV("MouseBehavior",safeProp(UIS,"MouseBehavior"))
    addKV("MouseDeltaSensitivity",safeProp(UIS,"MouseDeltaSensitivity"))
    add("")
    add("[CAMERA_INITIAL]")
    if camera then
        addKV("ViewportSize.ACTUAL_RUNTIME",camera.ViewportSize)
        addKV("FieldOfView",camera.FieldOfView)
        addKV("FieldOfViewMode",safeProp(camera,"FieldOfViewMode"))
        addKV("CameraType",camera.CameraType)
        addKV("CameraSubject",camera.CameraSubject and camera.CameraSubject:GetFullName() or "nil")
        addKV("CFrame.Position",camera.CFrame.Position)
        addKV("Focus.Position",camera.Focus.Position)
    end
    local ugs
    pcall(function() ugs=UserSettings():GetService("UserGameSettings") end)
    if ugs then
        add("")
        add("[USER_GAME_SETTINGS]")
        for _,k in ipairs({
            "RotationType","TouchCameraMovementMode","ComputerCameraMovementMode",
            "MouseSensitivity","GamepadCameraSensitivity","CameraYInverted",
        }) do
            addKV(k,safeProp(ugs,k))
        end
    end
    controllerSnapshot()
    scanScriptNames()
    connectionSnapshot(UIS.InputChanged,"UIS.InputChanged",80)
    connectionSnapshot(UIS.InputBegan,"UIS.InputBegan",60)
    connectionSnapshot(RunService.RenderStepped,"RunService.RenderStepped",100)
    add("")
    add("[SAMPLES]")
end

local function sample()
    camera = Workspace.CurrentCamera
    if not camera then return end
    local char,hum,root,head=getCharacterParts()
    local controller=getActiveCameraController()
    local lockController=getMouseLockController()
    local locked,offset=getLockState(controller,lockController)
    local subjectPos,subjectSource=subjectPosition(camera,controller,root)

    local rootP = root and project(camera,root.Position) or nil
    local headP = head and project(camera,head.Position) or nil
    local focusP = project(camera,camera.Focus.Position)
    local subjectP = project(camera,subjectPos)

    local hypCamAxes, hypRootLocal
    if typeof(offset)=="Vector3" and typeof(subjectPos)=="Vector3" then
        hypCamAxes = subjectPos
            + camera.CFrame.RightVector*offset.X
            + camera.CFrame.UpVector*offset.Y
            + camera.CFrame.LookVector*offset.Z
    end
    if typeof(offset)=="Vector3" and root and root:IsA("BasePart") then
        hypRootLocal = root.CFrame:PointToWorldSpace(offset)
    end
    local camAxesP=project(camera,hypCamAxes)
    local rootLocalP=project(camera,hypRootLocal)

    if rootP then statAdd(stats.rootCx,rootP.cx); statAdd(stats.rootCy,rootP.cy) end
    if headP then statAdd(stats.headCx,headP.cx); statAdd(stats.headCy,headP.cy) end
    if focusP then statAdd(stats.focusCx,focusP.cx); statAdd(stats.focusCy,focusP.cy) end
    if subjectP then statAdd(stats.subjectCx,subjectP.cx); statAdd(stats.subjectCy,subjectP.cy) end
    if camAxesP then statAdd(stats.camAxesCx,camAxesP.cx); statAdd(stats.camAxesCy,camAxesP.cy) end
    if rootLocalP then statAdd(stats.rootLocalCx,rootLocalP.cx); statAdd(stats.rootLocalCy,rootLocalP.cy) end

    local prePostA=cframeAngleDeg(preCF,postCF)
    local postLateA=cframeAngleDeg(postCF,lateCF)
    local prePostP=cframePosDelta(preCF,postCF)
    local postLateP=cframePosDelta(postCF,lateCF)
    statAdd(stats.prePostAngle,prePostA)
    statAdd(stats.postLateAngle,postLateA)
    statAdd(stats.prePostPos,prePostP)
    statAdd(stats.postLatePos,postLateP)
    statAdd(stats.cframeWrites,cframeWrites)
    statAdd(stats.focusWrites,focusWrites)

    local camLocal
    if root and root:IsA("BasePart") then
        camLocal = camera.CFrame:PointToObjectSpace(root.Position)
        statAdd(stats.camToRootLocalX,camLocal.X)
        statAdd(stats.camToRootLocalY,camLocal.Y)
        statAdd(stats.camToRootLocalZ,camLocal.Z)
        statAdd(stats.rootFocusDistance,(root.Position-camera.Focus.Position).Magnitude)
    end

    local distance=safeMethod(controller,"GetCameraToSubjectDistance")
    if type(distance)~="number" then distance=safeProp(controller,"currentSubjectDistance") end
    statAdd(stats.cameraSubjectDistance,distance)

    local yaw,pitch=yawPitch(camera.CFrame)
    local humOffset=hum and safeProp(hum,"CameraOffset") or nil
    local humState=hum and safeMethod(hum,"GetState") or nil
    local fingerCount=0
    local fingerTouches=controller and safeProp(controller,"fingerTouches")
    if type(fingerTouches)=="table" then for _ in pairs(fingerTouches) do fingerCount+=1 end end
    local unsunk=controller and safeProp(controller,"numUnsunkTouches") or nil
    local rotateInput=controller and safeProp(controller,"rotateInput") or nil
    local panEnabled=controller and safeProp(controller,"panEnabled") or nil

    sampleIndex+=1
    add(table.concat({
        string.format("S%04d",sampleIndex),
        "t="..num(now(),4),
        "frame="..tostring(phaseFrame),
        "vp="..v2(camera.ViewportSize),
        "yawDeg="..num(yaw,5),
        "pitchDeg="..num(pitch,5),
        "fov="..num(camera.FieldOfView,4),
        "camPos="..cfpos(camera.CFrame),
        "focusPos="..cfpos(camera.Focus),
        "root{"..projText(rootP).."}",
        "head{"..projText(headP).."}",
        "focus{"..projText(focusP).."}",
        "subject{"..projText(subjectP).."}",
        "subjectSource="..subjectSource,
        "camLocalRoot="..v3(camLocal),
        "humCameraOffset="..v3(humOffset),
        "humState="..safeText(humState),
        "locked="..safeText(locked),
        "lockOffset="..v3(offset),
        "hypCamAxes{"..projText(camAxesP).."}",
        "hypRootLocal{"..projText(rootLocalP).."}",
        "mouseBehavior="..safeText(safeProp(UIS,"MouseBehavior")),
        "preferredInput="..safeText(safeProp(UIS,"PreferredInput")),
        "lastInput="..safeText(UIS:GetLastInputType()),
        "rotateInput="..v2(rotateInput),
        "panEnabled="..safeText(panEnabled),
        "fingerTouches="..tostring(fingerCount),
        "unsunkTouches="..safeText(unsunk),
        "touchDelta="..v2(touchDelta),
        "cameraTouchDelta="..v2(cameraTouchDelta),
        "touchChanged="..tostring(touchChanged),
        "cameraTouchChanged="..tostring(cameraTouchChanged),
        "prePostAngDeg="..num(prePostA,6),
        "postLateAngDeg="..num(postLateA,6),
        "prePostPos="..num(prePostP,7),
        "postLatePos="..num(postLateP,7),
        "cframeWritesAfterPre="..tostring(cframeWrites),
        "focusWritesAfterPre="..tostring(focusWrites),
    }," "))

    touchDelta=Vector2.zero
    cameraTouchDelta=Vector2.zero
    touchChanged=0
    cameraTouchChanged=0
end

local bindPrefix="__CameraX9CompareR1_"..tostring(math.floor(os.clock()*100000))
local preName=bindPrefix.."_Pre"
local postName=bindPrefix.."_Post"
local lateName=bindPrefix.."_Late"

local camPriority=Enum.RenderPriority.Camera.Value
local latePriority=Enum.RenderPriority.Last.Value

local function bindPhases()
    pcall(function() RunService:UnbindFromRenderStep(preName) end)
    pcall(function() RunService:UnbindFromRenderStep(postName) end)
    pcall(function() RunService:UnbindFromRenderStep(lateName) end)

    RunService:BindToRenderStep(preName,camPriority-1,function()
        camera=Workspace.CurrentCamera
        phaseFrame+=1
        cframeWrites=0
        focusWrites=0
        if camera then
            preCF=camera.CFrame
            preFocus=camera.Focus
        end
    end)

    RunService:BindToRenderStep(postName,camPriority+1,function()
        camera=Workspace.CurrentCamera
        if camera then
            postCF=camera.CFrame
            postFocus=camera.Focus
        end
    end)

    RunService:BindToRenderStep(lateName,latePriority,function()
        camera=Workspace.CurrentCamera
        if camera then
            lateCF=camera.CFrame
            lateFocus=camera.Focus
        end
        local t=now()
        if t-lastSample>=sampleDt then
            lastSample=t
            sample()
            if statusLabel then
                local left=math.max(0,duration-t)
                statusLabel.Text=string.format("GRAVANDO • %.1fs restantes • gire a câmera",left)
            end
        end
    end)
end

local function unbindPhases()
    pcall(function() RunService:UnbindFromRenderStep(preName) end)
    pcall(function() RunService:UnbindFromRenderStep(postName) end)
    pcall(function() RunService:UnbindFromRenderStep(lateName) end)
end

local function copyText(text)
    local ok=false
    if type(setclipboard)=="function" then
        ok=pcall(function() setclipboard(text) end)
    elseif type(toclipboard)=="function" then
        ok=pcall(function() toclipboard(text) end)
    end
    return ok
end

local finalReport

local function finish(reason)
    if finished then return end
    finished=true
    unbindPhases()

    add("")
    add("[SUMMARY_NORMALIZED_SCREENSPACE]")
    for _,k in ipairs({
        "rootCx","rootCy","headCx","headCy","focusCx","focusCy","subjectCx","subjectCy",
        "camAxesCx","camAxesCy","rootLocalCx","rootLocalCy",
    }) do add(statLine(k,stats[k])) end

    add("")
    add("[SUMMARY_RENDER_PHASES]")
    for _,k in ipairs({
        "prePostAngle","postLateAngle","prePostPos","postLatePos",
        "cframeWrites","focusWrites",
    }) do add(statLine(k,stats[k])) end
    addKV("totalCameraCFramePropertyChanges",totalCFrameChanges)
    addKV("totalCameraFocusPropertyChanges",totalFocusChanges)

    add("")
    add("[SUMMARY_GEOMETRY]")
    for _,k in ipairs({
        "camToRootLocalX","camToRootLocalY","camToRootLocalZ",
        "rootFocusDistance","cameraSubjectDistance",
    }) do add(statLine(k,stats[k])) end

    add("")
    add("[FINAL_RUNTIME_STATE]")
    local controller=getActiveCameraController()
    local lockController=getMouseLockController()
    local locked,offset=getLockState(controller,lockController)
    addKV("activeCameraController.keys.final",keys(controller,240))
    addKV("mouseLockController.keys.final",keys(lockController,180))
    addKV("locked.final",locked)
    addKV("lockOffset.final",v3(offset))
    addKV("MouseBehavior.final",safeProp(UIS,"MouseBehavior"))
    addKV("PreferredInput.final",safeProp(UIS,"PreferredInput"))
    addKV("LastInputType.final",UIS:GetLastInputType())
    addKV("finishReason",reason or "duration")
    addKV("samples",sampleIndex)
    addKV("inputChangedTotal",inputChangedTotal)

    deepCameraGCScan()

    add("")
    add("[READ_ONLY_INVARIANTS]")
    add("cameraWritesByX9 = 0")
    add("characterWritesByX9 = 0")
    add("inputHooksByX9 = 0")
    add("connectionsDisabledByX9 = 0")
    add("playerModuleMutationByX9 = 0")
    add("NOTE hypCamAxes/hypRootLocal are observation-only candidate projections, not corrections.")

    finalReport=table.concat(lines,"\n")
    ENV.CameraX9CompareReport=finalReport
    ENV.CameraX9CompareData={
        version=VERSION,
        placeId=game.PlaceId,
        gameId=game.GameId,
        samples=sampleIndex,
        reportChars=#finalReport,
    }

    local fileName=string.format("CameraX9_%s_%d_%d.txt",
        game.PlaceId==LEGACY_PLACE_ID and "LEGACY" or "OTHER",
        game.PlaceId,
        os.time()
    )
    local wrote=false
    if type(writefile)=="function" then
        wrote=pcall(function() writefile(fileName,finalReport) end)
    end

    local copied=copyText(finalReport)
    if statusLabel then
        statusLabel.Text=string.format("PRONTO • %d amostras • %d chars",sampleIndex,#finalReport)
    end
    if stopButton then
        stopButton.Text="FINALIZADO"
        stopButton.Active=false
        stopButton.AutoButtonColor=false
    end
    if copyButton then
        copyButton.Active=true
        copyButton.AutoButtonColor=true
        copyButton.Text=copied and "COPIADO ✓" or "COPIAR REPORT"
        copyButton.MouseButton1Click:Connect(function()
            local ok=copyText(finalReport)
            copyButton.Text=ok and "COPIADO ✓" or "FALHOU"
            if ok then notify("Camera X9","Relatório copiado. Cole no ChatGPT.",5) end
        end)
    end
    notify("Camera X9 concluído",
        copied and "Relatório completo já foi copiado." or (wrote and (fileName.." salvo.") or "Use o botão COPIAR REPORT."),
        7
    )
    warn(string.format("[Camera X9 Compare] done samples=%d chars=%d copied=%s wrote=%s",
        sampleIndex,#finalReport,tostring(copied),tostring(wrote)))
end

if stopButton then
    stopButton.MouseButton1Click:Connect(function()
        finish("manual-stop")
    end)
end

initialSnapshot()
-- Start the timed capture only after static architecture discovery completes.
startClock=os.clock()
lastSample=-1e9
bindPhases()
notify("Camera X9",
    string.format("%.0fs: só gire a câmera normalmente. Não precisa correr.",duration),
    6
)

task.delay(duration,function()
    finish("duration")
end)

return {
    Stop=function() finish("api-stop") end,
    GetReport=function() return finalReport or table.concat(lines,"\n") end,
    Version=VERSION,
}
