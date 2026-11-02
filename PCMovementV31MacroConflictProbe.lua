-- Optional, read-only input trace. Run temporarily alongside the working V3.1.
-- It cannot see inside an obfuscated macro or prove which callback it executes.
local UIS=game:GetService("UserInputService")
local Players=game:GetService("Players")
local pg=Players.LocalPlayer:WaitForChild("PlayerGui")
local hasCoreGui,coreGui=pcall(function() return game:GetService("CoreGui") end)
if not hasCoreGui then coreGui=nil end
local env=getgenv()
local old=env.__PCMovementV31MacroProbeCleanup
if type(old)=="function" then pcall(old) end

local CAPACITY=320
local started=os.clock()
local ring,head,count={},1,0
local active=true
local connections={}
local ids=setmetatable({},{__mode="k"})
local nextId=0
local lastChangeAt={}
local lastMovementState={}
local joystickFinger=nil
local api={}

local function bridgeState()
    local bridge=env.PCKeyboardTouchBridgeV52
    if type(bridge)=="table" and type(bridge.GetState)=="function" then
        local ok,value=pcall(bridge.GetState)
        if ok and type(value)=="table" then return value end
    end
    return {}
end
local function append(line)
    ring[head]=string.format("%.3fs %s",os.clock()-started,line)
    head=head%CAPACITY+1
    count=math.min(CAPACITY,count+1)
end
local function inputName(value)
    return value and tostring(value.Name) or "?"
end
local function point(input)
    local pos=input.Position
    if not pos then return "-" end
    return tostring(math.floor(pos.X+0.5))..","..tostring(math.floor(pos.Y+0.5))
end
local function guiAt(input,container)
    local pos=input.Position
    if not pos then return "-" end
    if not container then return "unavailable" end
    local ok,items=pcall(function() return container:GetGuiObjectsAtPosition(pos.X,pos.Y) end)
    if not ok or type(items)~="table" then return "unavailable" end
    if #items==0 then return "-" end
    local out={}
    for i=1,math.min(3,#items) do
        local path={}
        local obj=items[i]
        for _=1,6 do
            if not obj or obj==container then break end
            table.insert(path,1,tostring(obj.Name))
            obj=obj.Parent
        end
        out[#out+1]=table.concat(path,"/")
    end
    return table.concat(out,",")
end
local function fingerId(input)
    local id=ids[input]
    if not id then nextId+=1;id=nextId;ids[input]=id end
    return tostring(id)
end
local function record(phase,input,processed)
    if not active or not input then return end
    local kind=inputName(input.UserInputType)
    local state=bridgeState()
    if state.movementTouch then joystickFinger=state.movementTouch end
    local owner="-"
    local id="-"
    if kind=="Touch" then
        id=fingerId(input)
        owner=(input==state.movementTouch or input==joystickFinger) and "joystick" or "other"
    end
    local isTouch=kind=="Touch"
    local isKeyboard=kind=="Keyboard"
    local isMouseButton=kind=="MouseButton1" or kind=="MouseButton2"
    local isMouseMove=kind=="MouseMovement"
    if not (isTouch or isKeyboard or isMouseButton or isMouseMove) then return end
    if phase=="change" then
        if not (isTouch or isMouseMove) then return end
        local group=kind..":"..owner
        local now=os.clock()
        local previous=lastMovementState[group]
        local changed=not previous or previous.chord~=state.chord
            or previous.keysSent~=state.keyEvents or previous.jumpPulses~=state.jumpPulses
        if lastChangeAt[group] and now-lastChangeAt[group]<0.08 and not changed then return end
        lastChangeAt[group]=now
        lastMovementState[group]={chord=state.chord,keysSent=state.keyEvents,jumpPulses=state.jumpPulses}
    end
    local key=isKeyboard and inputName(input.KeyCode) or "-"
    local hit=phase=="begin" and isTouch and guiAt(input,pg) or "-"
    local coreHit=phase=="begin" and isTouch and guiAt(input,coreGui) or "-"
    append(string.format("%s type=%s key=%s finger=%s owner=%s pos=%s processed=%s chord=%s keysSent=%s jumpPulses=%s gui=%s core=%s",
        phase,kind,key,id,owner,point(input),tostring(processed),tostring(state.chord or "-"),
        tostring(state.keyEvents or "?"),tostring(state.jumpPulses or "?"),hit,coreHit))
    if phase=="end" and input==joystickFinger then joystickFinger=nil end
end

function api.Mark(label)
    if not active then return false end
    local safe=tostring(label or "emote appeared"):gsub("[\r\n]"," "):sub(1,80)
    append("MARK "..safe.." (manual; time of call, not measured activation)")
    return true
end
function api.GetReport()
    local lines={"V3.1 macro input probe | local input timeline | no macro handler instrumentation",
        "Events are observations; a key or touch near MARK does not prove causality."}
    for i=1,count do
        lines[#lines+1]=ring[(head-count+i-2)%CAPACITY+1]
    end
    return table.concat(lines,"\n")
end
function api.GetState()
    return {active=active,entries=count,capacity=CAPACITY,readOnly=true}
end
function api.CopyReport()
    local copy=type(setclipboard)=="function" and setclipboard
        or (type(toclipboard)=="function" and toclipboard)
    if not copy then return false,"Clipboard unavailable; run print(getgenv().PCMovementV31MacroProbe.GetReport())" end
    local ok,message=pcall(copy,api.GetReport())
    if not ok then return false,tostring(message) end
    return true
end
local cleanup
cleanup=function()
    if not active then return end
    active=false
    if env.__PCMovementV31MacroProbeMobileUIOwner==api
        and type(env.__PCMovementV31MacroProbeMobileUICleanup)=="function" then
        pcall(env.__PCMovementV31MacroProbeMobileUICleanup)
    end
    for _,connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
    table.clear(connections)
    if env.PCMovementV31MacroProbe==api then env.PCMovementV31MacroProbe=nil end
    if env.__PCMovementV31MacroProbeCleanup==cleanup then env.__PCMovementV31MacroProbeCleanup=nil end
end
api.Stop=cleanup
local ok,message=pcall(function()
    connections[#connections+1]=UIS.InputBegan:Connect(function(input,processed) record("begin",input,processed) end)
    connections[#connections+1]=UIS.InputChanged:Connect(function(input,processed) record("change",input,processed) end)
    connections[#connections+1]=UIS.InputEnded:Connect(function(input,processed) record("end",input,processed) end)
end)
if not ok then cleanup();error(message) end
env.PCMovementV31MacroProbe=api
env.__PCMovementV31MacroProbeCleanup=cleanup
return api
