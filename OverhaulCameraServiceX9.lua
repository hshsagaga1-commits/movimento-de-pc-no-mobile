-- OverhaulCameraServiceX9.lua
-- Read-only forensic probe for Evade Overhaul's live CameraService.
-- PURPOSE: identify the exact camera/composition mechanism used on mobile without
-- mutating Camera.CFrame, Camera.Focus, character CFrames, input, PlayerModule,
-- MouseLock, RenderStep connections, or game state.
--
-- Designed for Delta/iPhone. Produces one clipboard report + optional file.
-- It inspects the already-running RenderStepped callback sourced from
-- ReplicatedStorage.Services.Client.CameraService, then correlates the live
-- camera/root geometry for a short capture.
--
-- This probe intentionally does NOT require() CameraService, to avoid module-init
-- side effects. It uses existing live closures only.

local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local StarterGui=game:GetService("StarterGui")

local player=Players.LocalPlayer
local ENV=(type(getgenv)=="function" and getgenv()) or _G

local VERSION="OVERHAUL-CAMERASERVICE-X9-R1"
local DURATION=math.clamp(tonumber(ENV.OverhaulCameraServiceX9Seconds) or 10,5,20)
local SAMPLE_HZ=math.clamp(tonumber(ENV.OverhaulCameraServiceX9Hz) or 30,10,60)
local SAMPLE_DT=1/SAMPLE_HZ
local TARGET_SOURCE="ReplicatedStorage.Services.Client.CameraService"

local out={}
local conns={}
local finished=false
local started=os.clock()
local lastSample=-1e9
local samples=0

local function now() return os.clock()-started end
local function add(s) out[#out+1]=tostring(s) end
local function txt(v)
    if v==nil then return "nil" end
    local tv=typeof(v)
    if tv=="Vector2" then return string.format("Vector2(%.6f,%.6f)",v.X,v.Y) end
    if tv=="Vector3" then return string.format("Vector3(%.6f,%.6f,%.6f)",v.X,v.Y,v.Z) end
    if tv=="CFrame" then
        local p=v.Position
        return string.format("CFramePos(%.6f,%.6f,%.6f)",p.X,p.Y,p.Z)
    end
    if tv=="Instance" then return v:GetFullName().." <"..v.ClassName..">" end
    local ok,s=pcall(tostring,v)
    return ok and s or "<?>"
end
local function num(v,d)
    if type(v)~="number" then return "nil" end
    return string.format("%."..tostring(d or 7).."f",v)
end
local function safeprop(o,k)
    if o==nil then return nil end
    local v
    pcall(function() v=o[k] end)
    return v
end
local function notify(title,text,d)
    pcall(function()
        StarterGui:SetCore("SendNotification",{Title=title,Text=text,Duration=d or 5})
    end)
end
local function dbginfo(fn,what)
    if type(fn)~="function" then return nil end
    local r
    if debug and type(debug.info)=="function" then
        pcall(function() r=debug.info(fn,what) end)
    elseif debug and type(debug.getinfo)=="function" then
        pcall(function()
            local i=debug.getinfo(fn)
            if not i then return end
            if what=="s" then r=i.source or i.short_src
            elseif what=="n" then r=i.name
            elseif what=="l" then r=i.currentline or i.linedefined end
        end)
    end
    return r
end
local function sourceOf(fn) return tostring(dbginfo(fn,"s") or "") end
local function fnLabel(fn)
    return string.format("src=%s name=%s line=%s",
        tostring(dbginfo(fn,"s") or "?"),
        tostring(dbginfo(fn,"n") or "?"),
        tostring(dbginfo(fn,"l") or "?"))
end

local function getConstants(fn)
    if not (debug and type(debug.getconstants)=="function") then return nil end
    local t
    pcall(function() t=debug.getconstants(fn) end)
    return type(t)=="table" and t or nil
end
local function getUpvalues(fn)
    if not (debug and type(debug.getupvalues)=="function") then return nil end
    local t
    pcall(function() t=debug.getupvalues(fn) end)
    return type(t)=="table" and t or nil
end
local function getProtos(fn)
    if not (debug and type(debug.getprotos)=="function") then return nil end
    local t
    pcall(function() t=debug.getprotos(fn) end)
    return type(t)=="table" and t or nil
end

local interestingKeyNeedles={
    "camera","offset","shift","lock","center","focus","root","subject","character",
    "mouse","touch","input","yaw","pitch","rotate","position","cframe","distance",
    "view","spring","smooth","lerp","delta","follow","primary","humanoid"
}
local function interestingKey(k)
    local s=string.lower(tostring(k))
    for _,n in ipairs(interestingKeyNeedles) do
        if string.find(s,n,1,true) then return true end
    end
    return false
end
local function suspiciousNumber(v)
    if type(v)~="number" then return false end
    local a=math.abs(v)
    return math.abs(a-2)<0.000001 or math.abs(a-0.5)<0.000001
        or math.abs(a-6)<0.000001 or math.abs(a-90)<0.000001
end

local seenTables={}
local seenFns={}
local function dumpTable(t,path,depth,budget)
    if type(t)~="table" or depth<0 or budget.n<=0 then return end
    if seenTables[t] then
        add(path.." = <table cycle/ref>")
        return
    end
    seenTables[t]=true

    local entries={}
    for k,v in pairs(t) do entries[#entries+1]={k,v} end
    table.sort(entries,function(a,b) return tostring(a[1])<tostring(b[1]) end)

    for _,kv in ipairs(entries) do
        if budget.n<=0 then add(path.." ...TABLE_BUDGET_EXHAUSTED"); break end
        local k,v=kv[1],kv[2]
        local tv=typeof(v)
        local keep=interestingKey(k) or tv=="Vector2" or tv=="Vector3" or tv=="CFrame"
            or suspiciousNumber(v) or type(v)=="function"
        if keep then
            budget.n-=1
            if type(v)=="function" then
                add(string.format("%s[%s] = function %s",path,tostring(k),fnLabel(v)))
                if depth>0 and string.find(string.lower(sourceOf(v)),"cameraservice",1,true) then
                    -- Function details are dumped separately by dumpFunction.
                end
            elseif type(v)=="table" and depth>0 then
                add(string.format("%s[%s] = <table>",path,tostring(k)))
                dumpTable(v,path.."."..tostring(k),depth-1,budget)
            else
                add(string.format("%s[%s] = %s",path,tostring(k),txt(v)))
            end
        end
    end
end

local function constantText(v)
    local tv=typeof(v)
    if type(v)=="string" then return string.format("%q",v) end
    if type(v)=="number" or type(v)=="boolean" then return tostring(v) end
    if tv=="Vector2" or tv=="Vector3" or tv=="CFrame" or tv=="EnumItem" then return txt(v) end
    return "<"..tv..">"
end

local function dumpFunction(fn,id,depth)
    if type(fn)~="function" or seenFns[fn] then return end
    seenFns[fn]=true
    add("")
    add(string.format("[FUNCTION %s] %s",id,fnLabel(fn)))

    local cs=getConstants(fn)
    if cs then
        add("constants.count = "..tostring(#cs))
        local printed=0
        for i,v in ipairs(cs) do
            local keep=type(v)=="string" or suspiciousNumber(v)
            if keep then
                printed+=1
                add(string.format("C%03d = %s",i,constantText(v)))
                if printed>=180 then add("constants ...TRUNCATED"); break end
            end
        end
    else
        add("constants = unavailable")
    end

    local uv=getUpvalues(fn)
    if uv then
        local count=0
        for _ in pairs(uv) do count+=1 end
        add("upvalues.count = "..tostring(count))
        local budget={n=180}
        local arr={}
        for k,v in pairs(uv) do arr[#arr+1]={k,v} end
        table.sort(arr,function(a,b) return tostring(a[1])<tostring(b[1]) end)
        for _,kv in ipairs(arr) do
            local k,v=kv[1],kv[2]
            local tv=typeof(v)
            if type(v)=="function" then
                add(string.format("U[%s] = function %s",tostring(k),fnLabel(v)))
            elseif type(v)=="table" then
                add(string.format("U[%s] = <table>",tostring(k)))
                dumpTable(v,"U["..tostring(k).."]",2,budget)
            elseif tv=="Instance" or tv=="Vector2" or tv=="Vector3" or tv=="CFrame"
                or type(v)=="number" or type(v)=="boolean" or type(v)=="string" then
                add(string.format("U[%s] = %s",tostring(k),txt(v)))
            else
                add(string.format("U[%s] = <%s>",tostring(k),tv))
            end
        end
    else
        add("upvalues = unavailable")
    end

    if depth>0 then
        local ps=getProtos(fn)
        if ps then
            add("protos.count = "..tostring(#ps))
            for i,p in ipairs(ps) do
                if type(p)=="function" then
                    dumpFunction(p,id..".P"..tostring(i),depth-1)
                end
                if i>=80 then add("protos ...TRUNCATED"); break end
            end
        else
            add("protos = unavailable")
        end
    end
end

local targetFns={}
local function addTarget(fn,why)
    if type(fn)~="function" then return end
    for _,e in ipairs(targetFns) do if e.fn==fn then return end end
    targetFns[#targetFns+1]={fn=fn,why=why}
end

local function discoverFromRenderStepped()
    add("")
    add("[DISCOVERY RenderStepped]")
    if type(getconnections)~="function" then
        add("getconnections unavailable")
        return
    end
    local list
    pcall(function() list=getconnections(RunService.RenderStepped) end)
    if type(list)~="table" then add("getconnections failed"); return end
    add("connections.count = "..tostring(#list))
    for i,c in ipairs(list) do
        local fn
        pcall(function() fn=c.Function end)
        if type(fn)=="function" then
            local src=sourceOf(fn)
            add(string.format("%03d %s",i,fnLabel(fn)))
            if string.find(string.lower(src),"cameraservice",1,true) then
                addTarget(fn,"RenderStepped#"..tostring(i))
            end
        else
            add(string.format("%03d function=unavailable",i))
        end
    end
end

local function discoverFromGC()
    add("")
    add("[DISCOVERY getgc CameraService functions]")
    if type(getgc)~="function" then add("getgc unavailable"); return end
    local objs
    local ok=pcall(function() objs=getgc(true) end)
    if not ok or type(objs)~="table" then add("getgc failed"); return end
    local hits=0
    for _,obj in ipairs(objs) do
        if type(obj)=="function" then
            local src=sourceOf(obj)
            if string.find(string.lower(src),"cameraservice",1,true) then
                hits+=1
                add(string.format("%03d %s",hits,fnLabel(obj)))
                addTarget(obj,"getgc#"..tostring(hits))
                if hits>=140 then add("...TRUNCATED"); break end
            end
        end
    end
    add("getgcCameraServiceHits = "..tostring(hits))
end

local cameraServiceModule
pcall(function()
    local services=ReplicatedStorage:FindFirstChild("Services")
    local client=services and services:FindFirstChild("Client")
    cameraServiceModule=client and client:FindFirstChild("CameraService")
end)

local function discoverScriptClosure()
    add("")
    add("[DISCOVERY module closure without require]")
    add("CameraServiceModule = "..txt(cameraServiceModule))
    local gsc=rawget(ENV,"getscriptclosure") or getscriptclosure
    if type(gsc)=="function" and cameraServiceModule then
        local closure
        local ok=pcall(function() closure=gsc(cameraServiceModule) end)
        add("getscriptclosure.ok = "..tostring(ok))
        add("getscriptclosure.type = "..type(closure))
        if type(closure)=="function" then
            addTarget(closure,"getscriptclosure")
        end
    else
        add("getscriptclosure unavailable")
    end
end

local stat={}
local function newStat() return {n=0,mean=0,m2=0,min=math.huge,max=-math.huge} end
for _,k in ipairs({
    "rootLocalX","rootLocalY","rootLocalZ","rootCx","rootCy","focusCx","focusCy",
    "cameraYaw","cameraPitch","rootFocusDist"
}) do stat[k]=newStat() end
local function addStat(s,x)
    if type(x)~="number" or x~=x or x==math.huge or x==-math.huge then return end
    s.n+=1
    if x<s.min then s.min=x end
    if x>s.max then s.max=x end
    local d=x-s.mean
    s.mean+=d/s.n
    s.m2+=d*(x-s.mean)
end
local function statLine(k)
    local s=stat[k]
    if s.n==0 then return k.." n=0" end
    local sd=s.n>1 and math.sqrt(math.max(0,s.m2/(s.n-1))) or 0
    return string.format("%s n=%d mean=%.9f sd=%.9f min=%.9f max=%.9f range=%.9f",
        k,s.n,s.mean,sd,s.min,s.max,s.max-s.min)
end

local function project(cam,p)
    if not cam or typeof(p)~="Vector3" then return nil end
    local vp=cam.ViewportSize
    if vp.X<=0 or vp.Y<=0 then return nil end
    local q,on=cam:WorldToViewportPoint(p)
    return {u=q.X/vp.X,v=q.Y/vp.Y,cx=q.X/vp.X-.5,cy=q.Y/vp.Y-.5,z=q.Z,on=on}
end
local function ptxt(p)
    if not p then return "nil" end
    return string.format("u=%.6f,v=%.6f,cx=%.6f,cy=%.6f,z=%.5f,on=%s",
        p.u,p.v,p.cx,p.cy,p.z,tostring(p.on))
end
local function yawPitch(cf)
    local l=cf.LookVector
    return math.deg(math.atan2(-l.X,-l.Z)),math.deg(math.asin(math.clamp(l.Y,-1,1)))
end

local function sample()
    local cam=Workspace.CurrentCamera
    local char=player.Character
    local hum=char and char:FindFirstChildOfClass("Humanoid")
    local root=char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    if not cam or not root or not root:IsA("BasePart") then return end

    local localRoot=cam.CFrame:PointToObjectSpace(root.Position)
    local rp=project(cam,root.Position)
    local fp=project(cam,cam.Focus.Position)
    local yaw,pitch=yawPitch(cam.CFrame)
    local focusDist=(root.Position-cam.Focus.Position).Magnitude

    addStat(stat.rootLocalX,localRoot.X)
    addStat(stat.rootLocalY,localRoot.Y)
    addStat(stat.rootLocalZ,localRoot.Z)
    if rp then addStat(stat.rootCx,rp.cx); addStat(stat.rootCy,rp.cy) end
    if fp then addStat(stat.focusCx,fp.cx); addStat(stat.focusCy,fp.cy) end
    addStat(stat.cameraYaw,yaw)
    addStat(stat.cameraPitch,pitch)
    addStat(stat.rootFocusDist,focusDist)

    samples+=1
    add(string.format(
        "S%04d t=%.4f vp=%s fov=%.4f camLocalRoot=%s root{%s} focus{%s} yaw=%.5f pitch=%.5f humCameraOffset=%s MouseBehavior=%s PreferredInput=%s LastInput=%s",
        samples,now(),txt(cam.ViewportSize),cam.FieldOfView,txt(localRoot),ptxt(rp),ptxt(fp),
        yaw,pitch,txt(hum and hum.CameraOffset or nil),txt(UIS.MouseBehavior),
        txt(safeprop(UIS,"PreferredInput")),txt(UIS:GetLastInputType())
    ))
end

local gui,status,copyButton,stopButton
local function makeGui()
    local pg=player:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    local old=pg:FindFirstChild("OverhaulCameraServiceX9Gui")
    if old then old:Destroy() end
    gui=Instance.new("ScreenGui")
    gui.Name="OverhaulCameraServiceX9Gui"
    gui.ResetOnSpawn=false
    gui.DisplayOrder=100000
    gui.Parent=pg

    local f=Instance.new("Frame")
    f.AnchorPoint=Vector2.new(.5,0)
    f.Position=UDim2.fromScale(.5,.03)
    f.Size=UDim2.fromOffset(370,116)
    f.BackgroundTransparency=.12
    f.Parent=gui

    local title=Instance.new("TextLabel")
    title.BackgroundTransparency=1
    title.Position=UDim2.fromOffset(8,6)
    title.Size=UDim2.new(1,-16,0,24)
    title.Font=Enum.Font.GothamBold
    title.TextSize=14
    title.Text="X9 • CAMERASERVICE OVERHAUL"
    title.Parent=f

    status=Instance.new("TextLabel")
    status.BackgroundTransparency=1
    status.Position=UDim2.fromOffset(8,32)
    status.Size=UDim2.new(1,-16,0,32)
    status.Font=Enum.Font.Gotham
    status.TextSize=13
    status.TextWrapped=true
    status.Text="PERÍCIA ESTÁTICA..."
    status.Parent=f

    stopButton=Instance.new("TextButton")
    stopButton.Position=UDim2.fromOffset(8,74)
    stopButton.Size=UDim2.new(.48,-10,0,34)
    stopButton.Font=Enum.Font.GothamBold
    stopButton.TextSize=13
    stopButton.Text="PARAR"
    stopButton.Parent=f

    copyButton=Instance.new("TextButton")
    copyButton.Position=UDim2.new(.5,2,0,74)
    copyButton.Size=UDim2.new(.5,-10,0,34)
    copyButton.Font=Enum.Font.GothamBold
    copyButton.TextSize=13
    copyButton.Text="COPIAR (ao terminar)"
    copyButton.Active=false
    copyButton.AutoButtonColor=false
    copyButton.Parent=f
end
makeGui()

local finalReport
local function copy(s)
    if type(setclipboard)=="function" then return pcall(function() setclipboard(s) end) end
    if type(toclipboard)=="function" then return pcall(function() toclipboard(s) end) end
    return false
end

local function finish(reason)
    if finished then return end
    finished=true
    add("")
    add("[RUNTIME SUMMARY]")
    for _,k in ipairs({"rootLocalX","rootLocalY","rootLocalZ","rootCx","rootCy","focusCx","focusCy","cameraYaw","cameraPitch","rootFocusDist"}) do
        add(statLine(k))
    end
    add("finishReason = "..tostring(reason))
    add("samples = "..tostring(samples))
    add("")
    add("[READ_ONLY INVARIANTS]")
    add("Camera.CFrame writes by X9 = 0")
    add("Camera.Focus writes by X9 = 0")
    add("character CFrame writes by X9 = 0")
    add("input hooks by X9 = 0")
    add("RenderStepped connections disabled by X9 = 0")
    add("CameraService require() calls by X9 = 0")

    finalReport=table.concat(out,"\n")
    ENV.OverhaulCameraServiceX9Report=finalReport
    ENV.OverhaulCameraServiceX9Data={
        version=VERSION,
        samples=samples,
        chars=#finalReport,
        targetFunctions=#targetFns,
    }

    local wrote=false
    if type(writefile)=="function" then
        wrote=pcall(function()
            writefile("OverhaulCameraServiceX9.txt",finalReport)
        end)
    end
    local copied=copy(finalReport)
    if status then status.Text=string.format("PRONTO • %d funcs • %d samples • %d chars",#targetFns,samples,#finalReport) end
    if stopButton then stopButton.Text="FINALIZADO"; stopButton.Active=false; stopButton.AutoButtonColor=false end
    if copyButton then
        copyButton.Active=true
        copyButton.AutoButtonColor=true
        copyButton.Text=copied and "COPIADO ✓" or "COPIAR REPORT"
        copyButton.MouseButton1Click:Connect(function()
            local ok=copy(finalReport)
            copyButton.Text=ok and "COPIADO ✓" or "FALHOU"
        end)
    end
    notify("CameraService X9",copied and "Relatório copiado." or (wrote and "Relatório salvo. Use COPIAR." or "Use COPIAR REPORT."),7)
    warn(string.format("[OverhaulCameraServiceX9] done funcs=%d samples=%d chars=%d",#targetFns,samples,#finalReport))
end
if stopButton then stopButton.MouseButton1Click:Connect(function() finish("manual-stop") end) end

add("=== OVERHAUL CAMERASERVICE X9 / READ-ONLY ===")
add("schema = "..VERSION)
add("timestamp = "..os.date("%Y-%m-%d %H:%M:%S"))
add("PlaceId = "..tostring(game.PlaceId))
add("GameId = "..tostring(game.GameId))
add("durationSeconds = "..tostring(DURATION))
add("sampleHz = "..tostring(SAMPLE_HZ))
add("ViewportSize = "..txt(Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or nil))
add("TouchEnabled = "..tostring(UIS.TouchEnabled))
add("MouseBehavior = "..txt(UIS.MouseBehavior))
add("PreferredInput = "..txt(safeprop(UIS,"PreferredInput")))
add("cap.getconnections = "..type(getconnections))
add("cap.getgc = "..type(getgc))
add("cap.getscriptclosure = "..type((rawget(ENV,"getscriptclosure") or getscriptclosure)))
add("cap.debug.getconstants = "..tostring(debug and type(debug.getconstants) or "nil"))
add("cap.debug.getupvalues = "..tostring(debug and type(debug.getupvalues) or "nil"))
add("cap.debug.getprotos = "..tostring(debug and type(debug.getprotos) or "nil"))

discoverFromRenderStepped()
discoverFromGC()
discoverScriptClosure()

add("")
add("[TARGET FUNCTION COUNT]")
add("targetFunctions = "..tostring(#targetFns))
for i,e in ipairs(targetFns) do
    add(string.format("target[%d].why = %s",i,e.why))
    add(string.format("target[%d].fn = %s",i,fnLabel(e.fn)))
end

for i,e in ipairs(targetFns) do
    dumpFunction(e.fn,"T"..tostring(i),3)
end

-- Static inspection can take time on mobile. Start the timed camera capture only now.
started=os.clock()
lastSample=-1e9
if status then status.Text="GRAVANDO • gire a câmera forte por 10s" end
notify("CameraService X9","Agora gire a câmera forte para os lados e cima/baixo.",6)

local hb
hb=RunService.RenderStepped:Connect(function()
    if finished then if hb then hb:Disconnect() end return end
    local t=now()
    if t-lastSample>=SAMPLE_DT then
        lastSample=t
        sample()
        if status then
            status.Text=string.format("GRAVANDO • %.1fs restantes • gire a câmera",math.max(0,DURATION-t))
        end
    end
    if t>=DURATION then
        if hb then hb:Disconnect() end
        finish("duration")
    end
end)
conns[#conns+1]=hb

task.delay(DURATION+2,function() finish("timeout-fallback") end)

return {
    Version=VERSION,
    Stop=function() finish("api-stop") end,
    GetReport=function() return finalReport or table.concat(out,"\n") end,
}
