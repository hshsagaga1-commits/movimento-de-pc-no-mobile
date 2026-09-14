-- MM2ShiftLockX9.lua
-- Read-only probe for understanding how MM2 mobile shift-lock actually works.
-- It does NOT force shift-lock, write Camera.CFrame, rotate the character, change speed,
-- hook callbacks, disable connections, or alter the game's camera behavior.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local DURATION = tonumber(getgenv().MM2X9Duration) or 15
local SAMPLE_HZ = 30
local SAMPLE_DT = 1 / SAMPLE_HZ

local report = {}
local function line(s)
    report[#report+1] = tostring(s)
end

local function val(v)
    local tv = typeof(v)
    if tv == "Vector2" then
        return string.format("%.6f,%.6f", v.X, v.Y)
    elseif tv == "Vector3" then
        return string.format("%.6f,%.6f,%.6f", v.X, v.Y, v.Z)
    elseif tv == "CFrame" then
        local p = v.Position
        return string.format("CFrame(%.3f,%.3f,%.3f)", p.X,p.Y,p.Z)
    elseif tv == "EnumItem" then
        return tostring(v)
    elseif tv == "Instance" then
        return v:GetFullName()
    elseif type(v) == "boolean" or type(v) == "number" or type(v) == "string" then
        return tostring(v)
    elseif v == nil then
        return "nil"
    end
    return "<" .. tv .. ">"
end

local function safeget(t, k)
    local out
    pcall(function() out = t[k] end)
    return out
end

local function tableKeys(t, limit)
    if type(t) ~= "table" then return "<not-table>" end
    local keys = {}
    for k in pairs(t) do
        keys[#keys+1] = tostring(k)
        if #keys >= (limit or 80) then break end
    end
    table.sort(keys)
    return table.concat(keys, ", ")
end

local function angleWrap(a)
    while a > math.pi do a -= 2*math.pi end
    while a < -math.pi do a += 2*math.pi end
    return a
end

local function yawPitchFromLook(look)
    local yaw = math.atan2(-look.X, -look.Z)
    local pitch = math.asin(math.clamp(look.Y, -1, 1))
    return yaw, pitch
end

local function yawFromCFrame(cf)
    local look = cf.LookVector
    return math.atan2(-look.X, -look.Z)
end

local function safeDebugSource(fn)
    local src = ""
    if debug and type(debug.info) == "function" then
        pcall(function() src = debug.info(fn, "s") or "" end)
    elseif debug and type(debug.getinfo) == "function" then
        pcall(function()
            local inf = debug.getinfo(fn)
            src = (inf and (inf.source or inf.short_src)) or ""
        end)
    end
    return tostring(src)
end

local function getUpvalues(fn)
    if not (debug and type(debug.getupvalues) == "function") then return nil end
    local uv
    pcall(function() uv = debug.getupvalues(fn) end)
    if type(uv) == "table" then return uv end
    return nil
end

local function referencesObject(fn, target, depth, seen)
    if type(fn) ~= "function" or target == nil or depth < 0 then return 0 end
    seen = seen or {}
    if seen[fn] then return 0 end
    seen[fn] = true
    local uv = getUpvalues(fn)
    if not uv then return 0 end
    local score = 0
    for _,v in pairs(uv) do
        if v == target then
            score += 100
        elseif type(v) == "function" and depth > 0 then
            score += math.min(40, referencesObject(v, target, depth-1, seen))
        end
    end
    return score
end

local playerModule, cameras, controls
pcall(function()
    local ps = player:FindFirstChild("PlayerScripts")
    local pm = ps and ps:FindFirstChild("PlayerModule")
    if pm then
        local required = require(pm)
        if type(required) == "table" then
            playerModule = required
            if type(required.GetCameras) == "function" then cameras = required:GetCameras() end
            if type(required.GetControls) == "function" then controls = required:GetControls() end
        end
    end
end)

local function activeCameraController()
    if type(cameras) ~= "table" then return nil end
    local c = rawget(cameras, "activeCameraController")
    if type(c) ~= "table" and type(cameras.GetActiveCameraController) == "function" then
        pcall(function() c = cameras:GetActiveCameraController() end)
    end
    return type(c) == "table" and c or nil
end

local function activeMouseLockController()
    if type(cameras) ~= "table" then return nil end
    local c = rawget(cameras, "activeMouseLockController")
    return type(c) == "table" and c or nil
end

local controller = activeCameraController()
local mouseLockController = activeMouseLockController()

line("=== MM2 SHIFT-LOCK X9 / READ-ONLY ===")
line("PlaceId = " .. tostring(game.PlaceId))
line("GameId = " .. tostring(game.GameId))
line("Duration = " .. tostring(DURATION))
line("")
line("[INPUT]")
line("TouchEnabled = " .. tostring(UIS.TouchEnabled))
line("MouseEnabled = " .. tostring(UIS.MouseEnabled))
line("KeyboardEnabled = " .. tostring(UIS.KeyboardEnabled))
line("PreferredInput = " .. val(safeget(UIS, "PreferredInput")))
line("LastInputType = " .. val(UIS:GetLastInputType()))
line("MouseBehavior = " .. val(UIS.MouseBehavior))
line("MouseDeltaSensitivity = " .. tostring(UIS.MouseDeltaSensitivity))

local userSettings
pcall(function() userSettings = UserSettings():GetService("UserGameSettings") end)
if userSettings then
    line("RotationType = " .. val(safeget(userSettings, "RotationType")))
    line("TouchCameraMovementMode = " .. val(safeget(userSettings, "TouchCameraMovementMode")))
    line("ComputerCameraMovementMode = " .. val(safeget(userSettings, "ComputerCameraMovementMode")))
    line("CameraSensitivity = " .. val(safeget(userSettings, "MouseSensitivity")))
    line("CameraYInvert = " .. val(safeget(userSettings, "CameraYInverted")))
end

line("")
line("[CAMERA]")
if camera then
    line("CameraType = " .. val(camera.CameraType))
    line("FOV = " .. tostring(camera.FieldOfView))
    line("ViewportSize = " .. val(camera.ViewportSize))
    line("CameraSubject = " .. val(camera.CameraSubject))
end

line("")
line("[PLAYER MODULE]")
line("playerModule = " .. tostring(type(playerModule) == "table"))
line("playerModule.keys = " .. tableKeys(playerModule, 80))
line("cameras.keys = " .. tableKeys(cameras, 120))
line("controls.keys = " .. tableKeys(controls, 120))

local fields = {
    "inMouseLockedMode","mouseLockOffset","rotateInput","panEnabled","keyPanEnabled",
    "fingerTouches","numUnsunkTouches","inputBeganConn","inputChangedConn","inputEndedConn",
    "cameraMovementMode","currentSubjectDistance","defaultSubjectDistance","ySensitivity",
    "userPanningCamera","userPanningTheCamera","isRightMouseDown","isMiddleMouseDown",
    "inFirstPerson","enabled","portraitMode","resetCameraAngle","currentSpeed"
}

line("")
line("[ACTIVE CAMERA CONTROLLER]")
line("exists = " .. tostring(type(controller) == "table"))
if type(controller) == "table" then
    line("keys = " .. tableKeys(controller, 180))
    for _,k in ipairs(fields) do
        local v = safeget(controller, k)
        if v ~= nil then line(k .. " = " .. val(v)) end
    end
end

line("")
line("[ACTIVE MOUSE-LOCK CONTROLLER]")
line("exists = " .. tostring(type(mouseLockController) == "table"))
if type(mouseLockController) == "table" then
    line("keys = " .. tableKeys(mouseLockController, 120))
    for _,k in ipairs({"enabled","isMouseLocked","savedMouseCursor","boundKeys"}) do
        local v = safeget(mouseLockController, k)
        if v ~= nil then line(k .. " = " .. val(v)) end
    end
    if type(mouseLockController.GetIsMouseLocked) == "function" then
        local x
        pcall(function() x = mouseLockController:GetIsMouseLocked() end)
        line("GetIsMouseLocked() = " .. val(x))
    end
    if type(mouseLockController.GetMouseLockOffset) == "function" then
        local x
        pcall(function() x = mouseLockController:GetMouseLockOffset() end)
        line("GetMouseLockOffset() = " .. val(x))
    end
end

-- Inspect InputChanged connections without disabling or hooking anything.
line("")
line("[UIS.InputChanged CONNECTION DISCOVERY]")
local candidates = {}
if type(getconnections) == "function" then
    local list
    pcall(function() list = getconnections(UIS.InputChanged) end)
    if type(list) == "table" then
        line("connectionCount = " .. tostring(#list))
        local target = type(controller)=="table" and safeget(controller,"inputChangedConn") or nil
        for i,c in ipairs(list) do
            local fn
            pcall(function() fn = c.Function end)
            if type(fn) == "function" then
                local score = 0
                local exact = false
                if target then
                    if c == target then exact = true end
                    for _,key in ipairs({"Connection","RBXScriptConnection","connection"}) do
                        local wrapped
                        pcall(function() wrapped = c[key] end)
                        if wrapped == target then exact = true end
                    end
                end
                if exact then score += 1000 end
                score += referencesObject(fn, controller, 2, {})
                score += math.floor(referencesObject(fn, mouseLockController, 2, {}) * 0.5)
                local src = safeDebugSource(fn)
                local lower = string.lower(src)
                if string.find(lower,"camera",1,true) then score += 25 end
                candidates[#candidates+1] = {i=i,score=score,exact=exact,src=src,fn=fn}
            end
        end
        table.sort(candidates,function(a,b) return a.score>b.score end)
        for i=1,math.min(10,#candidates) do
            local c = candidates[i]
            line(string.format("candidate[%d] index=%d score=%d exact=%s src=%s", i,c.i,c.score,tostring(c.exact),c.src))
            local uv = getUpvalues(c.fn)
            if uv then
                local summary = {}
                local n=0
                for name,v in pairs(uv) do
                    n += 1
                    if n>20 then break end
                    summary[#summary+1] = tostring(name) .. ":" .. typeof(v)
                end
                line("  upvalues = " .. table.concat(summary,", "))
            end
        end
    else
        line("getconnections failed")
    end
else
    line("getconnections unavailable")
end

-- Scan visible GUI near the physical center. This can reveal MM2's shift-lock dot/cursor/button implementation.
line("")
line("[CENTER GUI SCAN]")
local function scanGui(root, tag)
    if not root or not camera then return end
    local center = camera.ViewportSize/2
    local hits = {}
    local ok, descendants = pcall(function() return root:GetDescendants() end)
    if not ok or type(descendants) ~= "table" then return end
    for _,obj in ipairs(descendants) do
        if obj:IsA("GuiObject") and obj.Visible then
            local p,s
            pcall(function() p=obj.AbsolutePosition; s=obj.AbsoluteSize end)
            if p and s and s.X>0 and s.Y>0 then
                local c = p + s/2
                local dist = (c-center).Magnitude
                if dist <= 80 then
                    local image=""
                    local text=""
                    pcall(function() image=obj.Image or "" end)
                    pcall(function() text=obj.Text or "" end)
                    hits[#hits+1] = {dist=dist,obj=obj,image=image,text=text}
                end
            end
        end
    end
    table.sort(hits,function(a,b) return a.dist<b.dist end)
    for i=1,math.min(20,#hits) do
        local h=hits[i]
        line(string.format("%s centerGui[%d] dist=%.1f class=%s path=%s image=%s text=%s", tag,i,h.dist,h.obj.ClassName,h.obj:GetFullName(),tostring(h.image),tostring(h.text)))
    end
end
pcall(function() scanGui(player:FindFirstChildOfClass("PlayerGui"),"PlayerGui") end)
pcall(function() scanGui(CoreGui,"CoreGui") end)
pcall(function() if gethui then scanGui(gethui(),"gethui") end end)

line("")
line("[LIVE 15s MEASUREMENT]")
line("Keep MM2 shift-lock ON. During capture: stand still ~3s, do tiny camera motions, big flicks, left-right reversals, then walk/strafe while rotating.")

local char = player.Character
local root = char and char:FindFirstChild("HumanoidRootPart")
local humanoid = char and char:FindFirstChildOfClass("Humanoid")

local touchBegan, touchEnded, touchChanged = 0,0,0
local touchDX, touchDY = 0,0
local intervalDX, intervalDY = 0,0
local activeTouches = {}
local lockTransitions = 0
local lastLockState = nil

local conns = {}
conns[#conns+1] = UIS.InputBegan:Connect(function(input,processed)
    if input.UserInputType == Enum.UserInputType.Touch then
        touchBegan += 1
        activeTouches[input] = processed == true
    end
end)
conns[#conns+1] = UIS.InputEnded:Connect(function(input,processed)
    if input.UserInputType == Enum.UserInputType.Touch then
        touchEnded += 1
        activeTouches[input] = nil
    end
end)
conns[#conns+1] = UIS.InputChanged:Connect(function(input,processed)
    if input.UserInputType == Enum.UserInputType.Touch then
        touchChanged += 1
        local d = input.Delta
        touchDX += d.X
        touchDY += d.Y
        intervalDX += d.X
        intervalDY += d.Y
    end
end)

local samples = 0
local cameraYawTravel, cameraPitchTravel, rootYawTravel = 0,0,0
local sumXX, sumXYaw = 0,0
local sumYY, sumYPitch = 0,0
local coupledCamTravel, coupledRootTravel = 0,0
local lockFrames, unlockedFrames = 0,0
local relativeYawAbsSum, relativeYawSqSum, relativeYawN = 0,0,0
local maxCamYawStep, maxCamPitchStep = 0,0

local prevCamYaw, prevCamPitch, prevRootYaw
if camera then prevCamYaw,prevCamPitch = yawPitchFromLook(camera.CFrame.LookVector) end
if root then prevRootYaw = yawFromCFrame(root.CFrame) end

local started = os.clock()
local nextSample = started
while os.clock() - started < DURATION do
    RunService.RenderStepped:Wait()
    local now = os.clock()
    if now >= nextSample then
        nextSample = now + SAMPLE_DT
        camera = Workspace.CurrentCamera
        char = player.Character
        root = char and char:FindFirstChild("HumanoidRootPart")
        humanoid = char and char:FindFirstChildOfClass("Humanoid")
        controller = activeCameraController() or controller
        mouseLockController = activeMouseLockController() or mouseLockController

        local locked = nil
        if type(mouseLockController)=="table" then
            if type(mouseLockController.GetIsMouseLocked)=="function" then
                pcall(function() locked=mouseLockController:GetIsMouseLocked() end)
            end
            if locked==nil then locked = safeget(mouseLockController,"isMouseLocked") end
        end
        if locked==nil and type(controller)=="table" then locked = safeget(controller,"inMouseLockedMode") end
        if locked==true then lockFrames += 1 else unlockedFrames += 1 end
        if lastLockState~=nil and locked~=lastLockState then lockTransitions += 1 end
        lastLockState=locked

        if camera then
            local cy,cp = yawPitchFromLook(camera.CFrame.LookVector)
            if prevCamYaw then
                local dyaw = angleWrap(cy-prevCamYaw)
                local dpitch = angleWrap(cp-prevCamPitch)
                cameraYawTravel += math.abs(dyaw)
                cameraPitchTravel += math.abs(dpitch)
                maxCamYawStep = math.max(maxCamYawStep,math.abs(dyaw))
                maxCamPitchStep = math.max(maxCamPitchStep,math.abs(dpitch))
                if math.abs(intervalDX)>0.001 then
                    sumXX += intervalDX*intervalDX
                    sumXYaw += intervalDX*dyaw
                end
                if math.abs(intervalDY)>0.001 then
                    sumYY += intervalDY*intervalDY
                    sumYPitch += intervalDY*dpitch
                end
                if root and prevRootYaw then
                    local ry = yawFromCFrame(root.CFrame)
                    local dry = angleWrap(ry-prevRootYaw)
                    rootYawTravel += math.abs(dry)
                    if math.abs(dyaw)>0.0001 then
                        coupledCamTravel += math.abs(dyaw)
                        coupledRootTravel += math.abs(dry)
                    end
                    local rel = angleWrap(ry-cy)
                    relativeYawAbsSum += math.abs(rel)
                    relativeYawSqSum += rel*rel
                    relativeYawN += 1
                    prevRootYaw = ry
                elseif root then
                    prevRootYaw = yawFromCFrame(root.CFrame)
                end
            end
            prevCamYaw,prevCamPitch = cy,cp
        end
        intervalDX, intervalDY = 0,0
        samples += 1
    end
end

for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end

local xGain = sumXX>1e-9 and (sumXYaw/sumXX) or 0
local yGain = sumYY>1e-9 and (sumYPitch/sumYY) or 0
local coupling = coupledCamTravel>1e-9 and (coupledRootTravel/coupledCamTravel) or 0
local meanRel = relativeYawN>0 and (relativeYawAbsSum/relativeYawN) or 0
local rmsRel = relativeYawN>0 and math.sqrt(relativeYawSqSum/relativeYawN) or 0

line("samples = " .. tostring(samples))
line("touchBegan = " .. tostring(touchBegan))
line("touchChanged = " .. tostring(touchChanged))
line("touchEnded = " .. tostring(touchEnded))
line(string.format("touchDeltaSum = %.3f, %.3f",touchDX,touchDY))
line(string.format("cameraYawTravelDeg = %.3f",math.deg(cameraYawTravel)))
line(string.format("cameraPitchTravelDeg = %.3f",math.deg(cameraPitchTravel)))
line(string.format("rootYawTravelDeg = %.3f",math.deg(rootYawTravel)))
line(string.format("maxCameraYawStepDeg = %.3f",math.deg(maxCamYawStep)))
line(string.format("maxCameraPitchStepDeg = %.3f",math.deg(maxCamPitchStep)))
line(string.format("regression.cameraYawRadPerTouchPxX = %.9f",xGain))
line(string.format("regression.cameraPitchRadPerTouchPxY = %.9f",yGain))
line(string.format("characterCameraYawTravelCoupling = %.6f",coupling))
line(string.format("characterVsCameraYawMeanAbsDeg = %.3f",math.deg(meanRel)))
line(string.format("characterVsCameraYawRMSDeg = %.3f",math.deg(rmsRel)))
line("lockedFrames = " .. tostring(lockFrames))
line("unlockedFrames = " .. tostring(unlockedFrames))
line("lockTransitions = " .. tostring(lockTransitions))
if humanoid then
    line("Humanoid.AutoRotate = " .. tostring(humanoid.AutoRotate))
end

controller = activeCameraController() or controller
mouseLockController = activeMouseLockController() or mouseLockController
line("")
line("[FINAL STATE]")
line("MouseBehavior = " .. val(UIS.MouseBehavior))
line("PreferredInput = " .. val(safeget(UIS,"PreferredInput")))
line("LastInputType = " .. val(UIS:GetLastInputType()))
if userSettings then line("RotationType = " .. val(safeget(userSettings,"RotationType"))) end
if type(controller)=="table" then
    for _,k in ipairs({"inMouseLockedMode","mouseLockOffset","rotateInput","panEnabled","numUnsunkTouches","userPanningTheCamera","ySensitivity"}) do
        local v=safeget(controller,k)
        if v~=nil then line("controller."..k.." = "..val(v)) end
    end
end
if type(mouseLockController)=="table" then
    local locked
    pcall(function()
        locked=type(mouseLockController.GetIsMouseLocked)=="function" and mouseLockController:GetIsMouseLocked() or mouseLockController.isMouseLocked
    end)
    line("mouseLockController.locked = "..val(locked))
end

local final = table.concat(report,"\n")
getgenv().MM2ShiftLockX9Report = final
getgenv().MM2ShiftLockX9Data = {
    cameraYawRadPerTouchPxX=xGain,
    cameraPitchRadPerTouchPxY=yGain,
    characterCameraYawTravelCoupling=coupling,
    characterVsCameraYawMeanAbsDeg=math.deg(meanRel),
    characterVsCameraYawRMSDeg=math.deg(rmsRel),
    touchChanged=touchChanged,
    lockedFrames=lockFrames,
    unlockedFrames=unlockedFrames,
}

print(final)
warn("[MM2 X9] capture complete")

local copied=false
if type(setclipboard)=="function" then
    pcall(function() setclipboard(final); copied=true end)
elseif type(toclipboard)=="function" then
    pcall(function() toclipboard(final); copied=true end)
end

pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification",{
        Title="MM2 Shift-Lock X9",
        Text=copied and "Pronto: relatório copiado." or "Pronto: veja o console / MM2ShiftLockX9Report.",
        Duration=8,
    })
end)

return final
