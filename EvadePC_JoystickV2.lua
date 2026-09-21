-- Evade PC Joystick V2
-- Standalone. Physical touch is only a sensor; movement is emitted as keyboard keys.
-- Chords: W, W+A, W+D, S, A, D. No S+A / S+D.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local VirtualInputManager=game:GetService("VirtualInputManager")

local player=Players.LocalPlayer
local ENV=(type(getgenv)=="function" and getgenv()) or _G

local VERSION="EvadePC-Joystick-V2-six-sector"
local BIND_NAME="__EvadePCJoystickV2"
local MOVE_X_MAX=0.52
local MOVE_Y_MIN=0.42
local PRESS_RADIUS=0.18
local W_RATIO_MAX=0.30
local DIAG_RATIO_MAX=1.70
local JUMP_BURST=0.20

local old=ENV.__EvadePCJoystickV2Cleanup
if type(old)=="function" then pcall(old) end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local enabled=true
local touch=nil
local origin=nil
local latest=Vector2.zero
local pressed={W=false,A=false,S=false,D=false}
local chord="-"
local connections={}
local jumpToken=0
local keyEvents=0
local movementCaptures=0
local movementUpdates=0
local jumpRequests=0

local KEYS={
    W=Enum.KeyCode.W,
    A=Enum.KeyCode.A,
    S=Enum.KeyCode.S,
    D=Enum.KeyCode.D,
}

local function viewport()
    local cam=workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(1108,512)
end

local function sendKey(name,down)
    local key=KEYS[name]
    if not key then return false end
    local ok=pcall(function()
        VirtualInputManager:SendKeyEvent(down,key,false,game)
    end)
    if ok then keyEvents+=1 end
    return ok
end

local function rebuildChord()
    local out={}
    if pressed.W then out[#out+1]="W" end
    if pressed.A then out[#out+1]="A" end
    if pressed.D then out[#out+1]="D" end
    if pressed.S then out[#out+1]="S" end
    chord=#out>0 and table.concat(out,"+") or "-"
end

local function apply(desired)
    desired=desired or {}
    for _,name in ipairs({"W","A","D","S"}) do
        if pressed[name] and not desired[name] then
            sendKey(name,false)
            pressed[name]=false
        end
    end
    for _,name in ipairs({"W","A","D","S"}) do
        if desired[name] and not pressed[name] then
            if sendKey(name,true) then pressed[name]=true end
        end
    end
    rebuildChord()
end

local function releaseMovement()
    touch=nil
    origin=nil
    latest=Vector2.zero
    apply({})
end

local function normalizedDelta(position)
    if not origin then return Vector2.zero end
    local size=viewport()
    local radius=math.max(54,math.min(size.X,size.Y)*0.18)
    local d=(position-origin)/radius
    if d.Magnitude>1 then d=d.Unit end
    return d
end

local function classify(v)
    local x=v.X
    local z=v.Y
    local mag=v.Magnitude
    if mag<PRESS_RADIUS then return {} end

    local ax=math.abs(x)
    local az=math.abs(z)

    -- Backward half owns only S; there are intentionally no SA/SD chords.
    if z>0.18 and z>=-0.20+ax*0.34 then
        return {S=true}
    end

    -- Upper / side half: narrow W, wide WA/WD, then pure A/D.
    if z<0 then
        local ratio=ax/math.max(-z,0.0001)
        if ratio<=W_RATIO_MAX then
            return {W=true}
        elseif ratio<=DIAG_RATIO_MAX then
            return x<0 and {W=true,A=true} or {W=true,D=true}
        end
    end

    if x<0 then return {A=true} end
    if x>0 then return {D=true} end
    return z<0 and {W=true} or {S=true}
end

local function movementArea(p)
    local size=viewport()
    return p.X<=size.X*MOVE_X_MAX and p.Y>=size.Y*MOVE_Y_MIN
end

connections[#connections+1]=UserInputService.InputBegan:Connect(function(input,gpe)
    if not enabled or touch~=nil then return end
    if input.UserInputType~=Enum.UserInputType.Touch then return end
    local p=Vector2.new(input.Position.X,input.Position.Y)
    if not movementArea(p) then return end

    touch=input
    origin=p
    latest=Vector2.zero
    movementCaptures+=1
end)

connections[#connections+1]=UserInputService.InputChanged:Connect(function(input)
    if not enabled or input~=touch then return end
    local p=Vector2.new(input.Position.X,input.Position.Y)
    latest=normalizedDelta(p)
    movementUpdates+=1
end)

connections[#connections+1]=UserInputService.InputEnded:Connect(function(input)
    if input==touch then releaseMovement() end
end)

local function burstSpace()
    if not enabled then return end
    jumpRequests+=1
    jumpToken+=1
    local token=jumpToken
    local deadline=os.clock()+JUMP_BURST

    task.spawn(function()
        while enabled and token==jumpToken and os.clock()<deadline do
            pcall(function()
                VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Space,false,game)
                VirtualInputManager:SendKeyEvent(true,Enum.KeyCode.Space,false,game)
            end)
            RunService.Heartbeat:Wait()
        end
        if token==jumpToken then
            pcall(function()
                VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Space,false,game)
            end)
        end
    end)
end

connections[#connections+1]=UserInputService.JumpRequest:Connect(burstSpace)

-- Native mobile JumpButton can remain visible even while ControlModule is PC.
task.spawn(function()
    local pg=player:WaitForChild("PlayerGui",8)
    if not pg then return end
    for _=1,80 do
        if not enabled then return end
        local jump=pg:FindFirstChild("JumpButton",true)
        if jump and jump:IsA("GuiButton") then
            connections[#connections+1]=jump.InputBegan:Connect(function(input)
                if enabled and input.UserInputType==Enum.UserInputType.Touch then
                    burstSpace()
                end
            end)
            return
        end
        task.wait(0.1)
    end
end)

RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Input.Value+8,function()
    if not enabled then
        apply({})
        return
    end
    if touch then
        apply(classify(latest))
    else
        apply({})
    end
end)

local api={
    Version=VERSION,
    SetEnabled=function(value)
        enabled=value~=false
        if not enabled then releaseMovement() end
    end,
    IsEnabled=function() return enabled end,
    GetState=function()
        return {
            chord=chord,
            touchActive=touch~=nil,
            captures=movementCaptures,
            updates=movementUpdates,
            keyEvents=keyEvents,
            jumpRequests=jumpRequests,
            sectors={"W","W+A","W+D","S","A","D"},
        }
    end,
}

ENV.EvadePCJoystickV2=api
ENV.__EvadePCJoystickV2Cleanup=function()
    enabled=false
    jumpToken+=1
    releaseMovement()
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    pcall(function() VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Space,false,game) end)
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    ENV.EvadePCJoystickV2=nil
    ENV.__EvadePCJoystickV2Cleanup=nil
end

return api
