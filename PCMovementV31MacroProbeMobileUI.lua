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
panel.Size=UDim2.fromOffset(164,280)
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
local save=button("SaveLog","SALVAR LOG",118,Color3.fromRGB(71,95,138))
local show=button("ShowLog","VER LOG",150,Color3.fromRGB(63,104,123))
local stop=button("EndProbe","ENCERRAR",182,Color3.fromRGB(148,55,69))
local pathLabel=Instance.new("TextLabel")
pathLabel.Name="SavedPath"
pathLabel.Position=UDim2.fromOffset(8,214)
pathLabel.Size=UDim2.fromOffset(148,59)
pathLabel.BackgroundTransparency=1
pathLabel.TextColor3=Color3.fromRGB(190,208,224)
pathLabel.Font=Enum.Font.GothamBold
pathLabel.TextSize=10
pathLabel.TextWrapped=true
pathLabel.Text="Destino: ainda não salvo"
pathLabel.Parent=panel

local viewer=Instance.new("Frame")
viewer.Name="ReportViewer"
viewer.BackgroundColor3=Color3.fromRGB(21,30,43)
viewer.BorderSizePixel=0
viewer.Visible=false
viewer.ZIndex=30
viewer.Parent=gui
Instance.new("UICorner",viewer).CornerRadius=UDim.new(0,9)
local reportText=Instance.new("TextBox")
reportText.Name="ReportText"
reportText.Position=UDim2.fromOffset(8,8)
reportText.Size=UDim2.new(1,-16,1,-54)
reportText.BackgroundColor3=Color3.fromRGB(35,46,61)
reportText.TextColor3=Color3.new(1,1,1)
reportText.Font=Enum.Font.GothamBold
reportText.TextSize=11
reportText.TextXAlignment=Enum.TextXAlignment.Left
reportText.TextYAlignment=Enum.TextYAlignment.Top
reportText.TextEditable=true
reportText.ClearTextOnFocus=false
reportText.MultiLine=true
reportText.TextWrapped=false
reportText.Text=""
reportText.ZIndex=31
reportText.Parent=viewer
local function viewerButton(name,title,x,width)
    local b=Instance.new("TextButton")
    b.Name=name;b.Text=title
    b.Size=UDim2.fromOffset(width,30)
    b.Position=UDim2.new(0,x,1,-38)
    b.BackgroundColor3=Color3.fromRGB(51,70,92)
    b.TextColor3=Color3.new(1,1,1)
    b.Font=Enum.Font.GothamBold
    b.TextSize=11
    b.ZIndex=31
    b.Parent=viewer
    return b
end
local previousPage=viewerButton("PrevPage","<",8,30)
local nextPage=viewerButton("NextPage",">",44,30)
local closeViewer=viewerButton("CloseViewer","FECHAR",80,62)
local pageLabel=Instance.new("TextLabel")
pageLabel.Name="PageLabel"
pageLabel.Size=UDim2.fromOffset(55,30)
pageLabel.Position=UDim2.new(1,-63,1,-38)
pageLabel.BackgroundTransparency=1
pageLabel.TextColor3=Color3.new(1,1,1)
pageLabel.TextSize=12
pageLabel.ZIndex=31
pageLabel.Parent=viewer
local pages,pageIndex={},1
local function showPage()
    reportText.Text=pages[pageIndex] or ""
    pageLabel.Text=tostring(pageIndex).."/"..tostring(#pages)
end
local function splitReport(report)
    local parts={}
    local pos=1
    while pos<=#report do
        local last=math.min(#report,pos+11999)
        if last<#report then
            local lineEnd=report:sub(pos,last):match(".*()\n")
            if lineEnd and lineEnd>1 then last=pos+lineEnd-1 end
        end
        parts[#parts+1]=report:sub(pos,last)
        pos=last+1
    end
    if #parts==0 then parts[1]="" end
    return parts
end
local function positionViewer()
    local cam=workspace.CurrentCamera
    local viewport=cam and cam.ViewportSize or Vector2.new(896,414)
    local width=math.min(420,math.max(200,viewport.X*.5))
    local height=math.min(255,math.max(150,viewport.Y-90))
    viewer.Size=UDim2.fromOffset(width,height)
    viewer.Position=UDim2.new(.5,-width/2,0,18)
end
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
                positionViewer()
            end)
        end
        keepVisible(panel.AbsoluteSize.Y)
        positionViewer()
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
        local requested=probe.CopyReport()
        status.Text=requested and "CÓPIA SOLICITADA" or "ERRO AO COPIAR"
    end)
    connect(save.Activated,function()
        local filename="PCMovementV31MacroProbeLog.txt"
        if type(writefile)~="function" then
            status.Text="WRITEFILE INDISPONÍVEL"
            pathLabel.Text="Sem arquivo. Use VER LOG."
            return
        end
        local report=probe.GetReport()
        local saved=pcall(writefile,filename,report)
        if not saved then status.Text="ERRO AO SALVAR";return end
        pathLabel.Text="Nome: "..filename.."\nCaminho relativo: "..filename
        if type(readfile)=="function" then
            local ok,content=pcall(readfile,filename)
            status.Text=ok and content==report and "ARQUIVO VERIFICADO" or "ERRO: NÃO CONFIRMADO"
        else
            status.Text="SALVAMENTO SOLICITADO"
        end
    end)
    connect(show.Activated,function()
        pages=splitReport(probe.GetReport())
        pageIndex=1
        showPage()
        positionViewer()
        viewer.Visible=true
    end)
    connect(previousPage.Activated,function()
        if pageIndex>1 then pageIndex-=1;showPage() end
    end)
    connect(nextPage.Activated,function()
        if pageIndex<#pages then pageIndex+=1;showPage() end
    end)
    connect(closeViewer.Activated,function()
        viewer.Visible=false
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
