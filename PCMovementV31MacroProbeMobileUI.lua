-- Temporary touch UI for the independent input probe. No virtual input.
local UIS=game:GetService("UserInputService")
local Players=game:GetService("Players")
local pg=Players.LocalPlayer:WaitForChild("PlayerGui")
local env=getgenv()
local probe=env.PCMovementV31MacroProbe
assert(type(probe)=="table" and type(probe.Mark)=="function","Load the probe first")
local old=env.__PCMovementV31MacroProbeMobileUICleanup
if type(old)=="function" then pcall(old) end

local connections={}
local gui=Instance.new("ScreenGui")
gui.Name="PCMovementV31MacroProbeMobileUI"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=false
gui.DisplayOrder=10021
gui.Parent=pg
local panel=Instance.new("Frame")
panel.Name="Panel"
panel.Size=UDim2.fromOffset(164,158)
panel.Position=UDim2.new(1,-310,0,68)
panel.BackgroundColor3=Color3.fromRGB(21,30,43)
panel.BorderSizePixel=0
panel.Active=true
panel.Parent=gui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,10)

local function button(name,title,y,color)
    local b=Instance.new("TextButton")
    b.Name=name;b.Text=title
    b.Size=UDim2.fromOffset(148,28)
    b.Position=UDim2.fromOffset(8,y)
    b.BackgroundColor3=color
    b.BorderSizePixel=0
    b.TextColor3=Color3.new(1,1,1)
    b.Font=Enum.Font.GothamBold
    b.TextSize=14
    b.Parent=panel
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6)
    return b
end
local header=button("DragHeader","DIAGNÓSTICO  ≡",2,Color3.fromRGB(51,70,92))
header.TextSize=12
local status=Instance.new("TextLabel")
status.Name="Status"
status.Position=UDim2.fromOffset(8,30)
status.Size=UDim2.fromOffset(148,23)
status.BackgroundTransparency=1
status.TextColor3=Color3.fromRGB(163,222,255)
status.Font=Enum.Font.GothamBold
status.TextSize=12
status.Text="INICIANDO..."
status.Parent=panel
local mark=button("MarkBug","MARCAR BUG",54,Color3.fromRGB(178,112,30))
local copy=button("CopyLog","COPIAR LOG",86,Color3.fromRGB(35,117,138))
local stop=button("EndProbe","ENCERRAR",118,Color3.fromRGB(148,55,69))
local save=button("SaveLog","SALVAR ARQUIVO",150,Color3.fromRGB(71,95,138))
save.Visible=false
local active=true
local dragging,dragStart,panelStart=nil,nil,nil
local function keepVisible(height)
    local cam=workspace.CurrentCamera
    local viewport=cam and cam.ViewportSize or Vector2.new(896,414)
    local pos=panel.AbsolutePosition
    local x=math.clamp(pos.X,viewport.X*.52,math.max(viewport.X*.52,viewport.X-172))
    local y=math.clamp(pos.Y,40,math.max(40,viewport.Y-height-8))
    local bridge=pg:FindFirstChild("PCKeyboardTouchBridgeV52Overlay")
    local jump=bridge and bridge:FindFirstChild("PCJump",true)
    if jump then
        local jp,js=jump.AbsolutePosition,jump.AbsoluteSize
        if x<jp.X+js.X+8 and x+panel.AbsoluteSize.X>jp.X-8
            and y<jp.Y+js.Y+8 and y+height>jp.Y-8 then
            local left=jp.X-panel.AbsoluteSize.X-8
            if left>=viewport.X*.52 then
                x=math.min(x,left)
            else
                y=math.min(y,jp.Y-height-8)
            end
        end
    end
    panel.Position=UDim2.new(panel.Position.X.Scale,panel.Position.X.Offset+x-pos.X,
        panel.Position.Y.Scale,panel.Position.Y.Offset+y-pos.Y)
end
local cleanup
cleanup=function()
    if not active then return end
    active=false
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    gui:Destroy()
    if env.__PCMovementV31MacroProbeMobileUICleanup==cleanup then
        env.__PCMovementV31MacroProbeMobileUICleanup=nil
        env.__PCMovementV31MacroProbeMobileUIOwner=nil
    end
end
local function connect(signal,fn)
    local c=signal:Connect(fn)
    connections[#connections+1]=c
    return c
end
local ok,message=pcall(function()
    local cameraConnection
    local function watchCamera()
        if cameraConnection then cameraConnection:Disconnect() end
        local cam=workspace.CurrentCamera
        if cam then
            cameraConnection=connect(cam:GetPropertyChangedSignal("ViewportSize"),function()
                keepVisible(panel.AbsoluteSize.Y)
            end)
        end
        keepVisible(panel.AbsoluteSize.Y)
    end
    connect(workspace:GetPropertyChangedSignal("CurrentCamera"),watchCamera)
    watchCamera()
    connect(header.InputBegan,function(input)
        if dragging or input.UserInputType~=Enum.UserInputType.Touch
            and input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
        dragging=input
        dragStart=input.Position
        panelStart=panel.Position
    end)
    connect(UIS.InputChanged,function(input)
        if input~=dragging then return end
        local delta=input.Position-dragStart
        panel.Position=UDim2.new(panelStart.X.Scale,panelStart.X.Offset+delta.X,
            panelStart.Y.Scale,panelStart.Y.Offset+delta.Y)
        keepVisible(panel.AbsoluteSize.Y)
    end)
    connect(UIS.InputEnded,function(input)
        if input==dragging then dragging,dragStart,panelStart=nil,nil,nil end
    end)
    connect(mark.Activated,function()
        if probe.Mark("emote involuntario") then status.Text="BUG MARCADO • registrando" end
    end)
    connect(copy.Activated,function()
        local copied=probe.CopyReport()
        if copied then
            status.Text="COPIADO!"
            save.Visible=false
            panel.Size=UDim2.fromOffset(164,158)
            keepVisible(panel.AbsoluteSize.Y)
        else
            local canSave=type(writefile)=="function"
            status.Text=canSave and "ERRO AO COPIAR • SALVE" or "ERRO AO COPIAR"
            save.Visible=canSave
            panel.Size=UDim2.fromOffset(164,canSave and 184 or 158)
            keepVisible(panel.AbsoluteSize.Y)
        end
    end)
    connect(save.Activated,function()
        if type(writefile)~="function" then status.Text="ARQUIVO INDISPONÍVEL";return end
        local saved=pcall(writefile,"PCMovementV31MacroProbeLog.txt",probe.GetReport())
        status.Text=saved and "SALVO: LOG.TXT" or "ERRO AO SALVAR"
    end)
    connect(stop.Activated,function()
        probe.Stop()
        cleanup()
    end)
end)
if not ok then cleanup();error(message) end
env.__PCMovementV31MacroProbeMobileUICleanup=cleanup
env.__PCMovementV31MacroProbeMobileUIOwner=probe
status.Text="ATIVO • registrando"
return {Stop=cleanup}
