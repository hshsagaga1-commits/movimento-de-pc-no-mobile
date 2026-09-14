local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

local P = Players.LocalPlayer
local EXPECTED_PLACE = 96537472072550
local DURATION = 25
local SAMPLE_DT = 1/30
local FILE = "LegacyProbeV2.txt"
local t0 = os.clock()
local lastSample = -99
local done = false
local L, C = {}, {}
local char, hum, root, animator
local PM, controls, cameras

local function t() return os.clock()-t0 end
local function s(v) local ok,r=pcall(tostring,v); return ok and r or "<?>" end
local function n(v) return type(v)=="number" and string.format("%.5f",v) or "nil" end
local function v3(v) return typeof(v)=="Vector3" and string.format("%.4f,%.4f,%.4f",v.X,v.Y,v.Z) or "nil" end
local function v2(v) return (typeof(v)=="Vector2" or typeof(v)=="Vector3") and string.format("%.1f,%.1f",v.X,v.Y) or "nil" end
local function log(tag,msg) L[#L+1]=string.format("%.4f\t%s\t%s",t(),tag,msg or "") end
local function conn(x) if x then C[#C+1]=x end return x end
local function notify(a,b) pcall(function() StarterGui:SetCore("SendNotification",{Title=a,Text=b,Duration=6}) end) end

local function json(v)
    local ok,r=pcall(function() return HttpService:JSONEncode(v) end)
    return ok and r or s(v)
end

local function getPM()
    if PM then return PM end
    pcall(function()
        local m=P:WaitForChild("PlayerScripts",10):FindFirstChild("PlayerModule")
        if m then local r=require(m); if type(r)=="table" then PM=r end end
    end)
    return PM
end
local function getControls()
    if controls then return controls end
    local p=getPM(); pcall(function() if p and p.GetControls then controls=p:GetControls() end end)
    return controls
end
local function getCameras()
    if cameras then return cameras end
    local p=getPM(); pcall(function() if p and p.GetCameras then cameras=p:GetCameras() end end)
    return cameras
end
local function getCamController()
    local cm=getCameras(); local c
    pcall(function() if cm and cm.GetActiveCameraController then c=cm:GetActiveCameraController() end end)
    return c
end

local function bindChar(c)
    char=c; hum=c:WaitForChild("Humanoid",10); root=c:WaitForChild("HumanoidRootPart",10)
    animator=hum and (hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator",5))
    log("CHAR","path="..c:GetFullName())
    if hum then
        for _,p in ipairs({"WalkSpeed","HipHeight","AutoRotate","CameraOffset","JumpPower","JumpHeight"}) do
            pcall(function() conn(hum:GetPropertyChangedSignal(p):Connect(function() log("HUM_"..p,s(hum[p])) end)) end)
        end
        pcall(function() conn(hum.StateChanged:Connect(function(a,b) log("STATE",s(a).."->"..s(b)) end)) end)
    end
    if animator then
        pcall(function()
            conn(animator.AnimationPlayed:Connect(function(tr)
                local id=""; pcall(function() if tr.Animation then id=tr.Animation.AnimationId end end)
                log("ANIM_PLAY","name="..s(tr.Name).." id="..s(id).." priority="..s(tr.Priority).." len="..n(tr.Length).." speed="..n(tr.Speed).." loop="..s(tr.Looped))
                pcall(function() conn(tr.Stopped:Connect(function() log("ANIM_STOP","name="..s(tr.Name).." id="..s(id)) end)) end)
            end))
        end)
    end
end

local function dumpTree(inst,tag,depth)
    if not inst then log(tag,"MISSING") return end
    log(tag,"ROOT "..inst:GetFullName().." <"..inst.ClassName..">")
    local function dep(x)
        local d,p=0,x
        while p and p~=inst do d+=1;p=p.Parent end
        return d
    end
    for _,x in ipairs(inst:GetDescendants()) do
        local d=dep(x)
        if d<=depth then log(tag,string.rep("  ",d)..x.Name.." <"..x.ClassName..">") end
    end
end

local function hookEvent(x,label)
    if not x then log("EVENT",label.." MISSING") return end
    log("EVENT",label.." class="..x.ClassName.." path="..x:GetFullName())
    if x:IsA("BindableEvent") then
        conn(x.Event:Connect(function(...)
            local a=table.pack(...); local q={}
            for i=1,a.n do q[#q+1]=type(a[i])=="table" and json(a[i]) or s(a[i]) end
            log("EV_"..label,table.concat(q," | "))
        end))
    elseif x:IsA("RemoteEvent") then
        conn(x.OnClientEvent:Connect(function(...)
            local a=table.pack(...); local q={}
            for i=1,a.n do q[#q+1]=type(a[i])=="table" and json(a[i]) or s(a[i]) end
            log("REMOTE_"..label,table.concat(q," | "))
        end))
    end
end

local function dumpConnections(x,label)
    if not x or type(getconnections)~="function" then log("CONN",label.." unavailable") return end
    local sig
    if x:IsA("BindableEvent") then sig=x.Event elseif x:IsA("RemoteEvent") then sig=x.OnClientEvent end
    if not sig then return end
    local ok,ls=pcall(getconnections,sig); if not ok or type(ls)~="table" then return end
    log("CONN",label.." count="..#ls)
    for i,c in ipairs(ls) do
        local f; pcall(function() f=c.Function end)
        if type(f)=="function" then
            local src,name,line="?","?","?"
            pcall(function() src=debug.info(f,"s") end); pcall(function() name=debug.info(f,"n") end); pcall(function() line=debug.info(f,"l") end)
            log("CONN_FN",label.."["..i.."] src="..s(src).." name="..s(name).." line="..s(line))
            if debug and type(debug.getconstants)=="function" then
                pcall(function()
                    local o={}; for _,k in ipairs(debug.getconstants(f)) do if type(k)=="string" or type(k)=="number" or type(k)=="boolean" then o[#o+1]=s(k) end if #o>=120 then break end end
                    log("CONN_CONST",label.."["..i.."] "..table.concat(o," ; "))
                end)
            end
        end
    end
end

local interestingKeys={
    "Friction","friction","Acceleration","acceleration","AirAcceleration","airAcceleration","GroundAcceleration",
    "MaxSpeed","maxSpeed","Speed","speed","WalkSpeed","HipHeight","Gravity","JumpPower","JumpHeight","Crouch",
    "CrouchSpeed","SlideSpeed","TurnSpeed","Sensitivity","CameraOffset","CameraHeight","MaxVelocity","Velocity"
}
local keySet={} for _,k in ipairs(interestingKeys) do keySet[k]=true end

local function printableTable(tbl)
    local o={}; local count=0
    for k,v in pairs(tbl) do
        if type(k)=="string" and (keySet[k] or string.find(string.lower(k),"friction",1,true) or string.find(string.lower(k),"accel",1,true) or string.find(string.lower(k),"speed",1,true) or string.find(string.lower(k),"camera",1,true) or string.find(string.lower(k),"crouch",1,true)) then
            if type(v)=="number" or type(v)=="string" or type(v)=="boolean" or typeof(v)=="Vector3" or typeof(v)=="Vector2" then
                o[#o+1]=k.."="..s(v); count+=1
            elseif type(v)=="table" then
                local sub={}; local j=0
                for sk,sv in pairs(v) do if (type(sv)=="number" or type(sv)=="string" or type(sv)=="boolean") and j<20 then sub[#sub+1]=s(sk).."="..s(sv);j+=1 end end
                o[#o+1]=k.."={"..table.concat(sub,",").."}"; count+=1
            end
        end
    end
    return count>0 and table.concat(o," ; ") or nil
end

local function scanGC()
    if type(getgc)~="function" then log("GC","getgc unavailable") return end
    local ok,objs=pcall(getgc,true); if not ok or type(objs)~="table" then log("GC","failed") return end
    local tableHits,fnHits=0,0
    for _,o in ipairs(objs) do
        if type(o)=="table" then
            local okp,p=pcall(printableTable,o)
            if okp and p then tableHits+=1; log("GC_TABLE","#"..tableHits.." "..p); if tableHits>=150 then break end end
        end
    end
    if debug and type(debug.getconstants)=="function" then
        local needles={Crouch=true,crouch=true,UseKeybind=true,KeybindUsed=true,Movement=true,Friction=true,HipHeight=true,CameraOffset=true,Stand=true,MoveDirection=true}
        for _,o in ipairs(objs) do
            if type(o)=="function" then
                local okc,cs=pcall(debug.getconstants,o)
                if okc and type(cs)=="table" then
                    local match={}
                    for _,k in ipairs(cs) do if type(k)=="string" and needles[k] then match[k]=true end end
                    if next(match) then
                        fnHits+=1; local src,name,line="?","?","?";pcall(function()src=debug.info(o,"s")end);pcall(function()name=debug.info(o,"n")end);pcall(function()line=debug.info(o,"l")end)
                        local m={};for k in pairs(match) do m[#m+1]=k end;table.sort(m)
                        log("GC_FN","#"..fnHits.." match="..table.concat(m,",").." src="..s(src).." name="..s(name).." line="..s(line))
                        local q={};for _,k in ipairs(cs) do if type(k)=="string" or type(k)=="number" or type(k)=="boolean" then q[#q+1]=s(k) end if #q>=150 then break end end
                        log("GC_CONST",table.concat(q," ; "))
                        if fnHits>=150 then break end
                    end
                end
            end
        end
    end
    log("GC","tables="..tableHits.." functions="..fnHits)
end

local function hookTouch()
    local function guiAt(pos)
        local names={}
        pcall(function()
            for i,g in ipairs(GuiService:GetGuiObjectsAtPosition(pos.X,pos.Y)) do
                names[#names+1]=g:GetFullName().."<"..g.ClassName..">"; if i>=8 then break end
            end
        end)
        return table.concat(names," | ")
    end
    conn(UIS.InputBegan:Connect(function(input,gpe)
        if input.UserInputType==Enum.UserInputType.Touch then log("TOUCH_BEGIN","pos="..v2(input.Position).." gpe="..s(gpe).." gui="..guiAt(input.Position)) end
    end))
    conn(UIS.InputEnded:Connect(function(input,gpe)
        if input.UserInputType==Enum.UserInputType.Touch then log("TOUCH_END","pos="..v2(input.Position).." gpe="..s(gpe).." gui="..guiAt(input.Position)) end
    end))
end

local function hookStandGui()
    local pg=P:FindFirstChildOfClass("PlayerGui")
    local cg=pg and pg:FindFirstChild("ControlsGui",true)
    local pf=cg and cg:FindFirstChild("PCFrame",true)
    local st=pf and pf:FindFirstChild("Stand",true)
    if st and st:IsA("GuiObject") then
        log("GUI_STAND","found visible="..s(st.Visible).." path="..st:GetFullName())
        conn(st:GetPropertyChangedSignal("Visible"):Connect(function() log("GUI_STAND","visible="..s(st.Visible)) end))
    else log("GUI_STAND","not found") end
end

local function sample()
    if not hum or not root then return end
    local cam=Workspace.CurrentCamera;if not cam then return end
    local pitch,yaw,roll=0,0,0;pcall(function()pitch,yaw,roll=cam.CFrame:ToOrientation()end)
    local mv=Vector3.zero;local ctl=getControls();pcall(function()if ctl then mv=ctl:GetMoveVector()end end)
    local active="nil",rel="nil";pcall(function()if ctl and ctl.GetActiveController then local ac=ctl:GetActiveController();active=s(ac);if ac and ac.IsMoveVectorCameraRelative then rel=s(ac:IsMoveVectorCameraRelative())end end end)
    local cc=getCamController();local ml,off,dist,sub="nil","nil","nil","nil"
    pcall(function()if cc and cc.GetIsMouseLocked then ml=s(cc:GetIsMouseLocked())end end)
    pcall(function()if cc and cc.GetMouseLockOffset then off=v3(cc:GetMouseLockOffset())end end)
    pcall(function()if cc and cc.GetCameraToSubjectDistance then dist=n(cc:GetCameraToSubjectDistance())end end)
    pcall(function()if cc and cc.GetSubjectPosition then sub=v3(cc:GetSubjectPosition())end end)
    local vel=Vector3.zero;pcall(function()vel=root.AssemblyLinearVelocity end)
    local state="nil";pcall(function()state=hum:GetState().Name end)
    log("SAMPLE",table.concat({
        "cam="..v3(cam.CFrame.Position),"pitch="..n(math.deg(pitch)),"yaw="..n(math.deg(yaw)),"fov="..n(cam.FieldOfView),"mode="..s(cam.FieldOfViewMode),
        "root="..v3(root.Position),"vel="..v3(vel),"move="..v3(hum.MoveDirection),"control="..v3(mv),"activeCtl="..active,"relative="..rel,
        "ws="..n(hum.WalkSpeed),"hip="..n(hum.HipHeight),"state="..state,"floor="..s(hum.FloorMaterial),"mouseLock="..ml,"offset="..off,"dist="..dist,"subject="..sub
    }," "))
end

local function environment()
    log("PROBE","V2 place="..game.PlaceId.." expected="..EXPECTED_PLACE)
    log("DEVICE","touch="..s(UIS.TouchEnabled).." mouse="..s(UIS.MouseEnabled).." keyboard="..s(UIS.KeyboardEnabled).." preferred="..s(UIS.PreferredInput))
    local cam=Workspace.CurrentCamera;if cam then log("CAM_INIT","viewport="..v2(cam.ViewportSize).." fov="..n(cam.FieldOfView).." mode="..s(cam.FieldOfViewMode).." type="..s(cam.CameraType).." subject="..s(cam.CameraSubject))end
    local ugs;pcall(function()ugs=UserSettings():GetService("UserGameSettings")end)
    if ugs then pcall(function()log("UGS","RotationType="..s(ugs.RotationType).." TouchCam="..s(ugs.TouchCameraMovementMode).." MouseSens="..s(ugs.MouseSensitivity).." GamepadSens="..s(ugs.GamepadCameraSensitivity))end)end
    local ps=P:FindFirstChild("PlayerScripts");dumpTree(ps,"PS_TREE",6)
    local ev=ps and ps:FindFirstChild("Events");local kb=ev and ev:FindFirstChild("KeybindUsed");local te=ev and ev:FindFirstChild("temporary_events");local uk=te and te:FindFirstChild("UseKeybind")
    hookEvent(kb,"KeybindUsed");hookEvent(uk,"UseKeybind");dumpConnections(kb,"KeybindUsed");dumpConnections(uk,"UseKeybind")
    if te then
        for _,x in ipairs(te:GetChildren()) do if x:IsA("BindableEvent") or x:IsA("RemoteEvent") then log("TEMP_EVENT",x.Name.." <"..x.ClassName..">")end end
    end
    hookStandGui();hookTouch()
end

local function finish()
    if done then return end;done=true;log("PROBE","FINISH")
    for _,c in ipairs(C) do pcall(function()c:Disconnect()end)end
    local report=table.concat(L,"\n");local wrote=false
    if type(writefile)=="function" then wrote=pcall(function()writefile(FILE,report)end)end
    if type(setclipboard)=="function" then pcall(function()setclipboard(report)end)end
    notify("Legacy Probe V2 terminou",wrote and (FILE.." salvo + copiado") or "relatório copiado")
    print("[LEGACY_PROBE_V2_DONE] lines="..#L)
end

if P.Character then bindChar(P.Character)end;conn(P.CharacterAdded:Connect(bindChar))
environment();task.spawn(scanGC)
notify("Legacy Probe V2","25s: SEM script de movimento. Corra, vire, agache/levante 5x, pule e faça diagonais.")
print("[LEGACY_PROBE_V2_START]")
conn(RunService.RenderStepped:Connect(function()
    local q=t();if q-lastSample>=SAMPLE_DT then lastSample=q;sample()end;if q>=DURATION then finish()end
end))
task.delay(DURATION+2,finish)
