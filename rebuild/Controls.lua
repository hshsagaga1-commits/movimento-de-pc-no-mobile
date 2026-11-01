-- Original V3/V6 control names, sprites and layout. No movement/key logic here.
local Controls={}
local GUI_NAME="PCKeyboardTouchBridgeV52Overlay"
local function create(class,name,parent,properties)
    local object=Instance.new(class)
    object.Name=name
    for key,value in pairs(properties or {}) do object[key]=value end
    object.Parent=parent
    return object
end
local function round(object)
    create("UICorner","UICorner",object,{CornerRadius=UDim.new(1,0)})
    create("UIStroke","UIStroke",object,{Thickness=3,Transparency=1})
end
function Controls.new(services)
    local self={offset=Vector2.zero,target=Vector2.zero,auto={},stopped=false}
    local pg=services.playerGui
    local gui=pg:FindFirstChild(GUI_NAME)
    local stick=gui and gui:FindFirstChild("PCJoystick",true)
    local knob=stick and stick:FindFirstChild("Knob")
    local jump=gui and gui:FindFirstChild("PCJump",true)
    local reused=gui and stick and knob and jump
    if not reused then
        if gui then gui:Destroy() end
        gui=create("ScreenGui",GUI_NAME,pg,{ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=10020})
        stick=create("TextButton","PCJoystick",gui,{Text="",AutoButtonColor=false,Active=true,
            BackgroundColor3=Color3.fromRGB(55,55,55),BackgroundTransparency=1,
            BorderSizePixel=0,AnchorPoint=Vector2.new(0,0),ZIndex=20})
        round(stick)
        knob=create("Frame","Knob",stick,{BackgroundColor3=Color3.fromRGB(205,205,205),
            BackgroundTransparency=1,BorderSizePixel=0,AnchorPoint=Vector2.new(0.5,0.5),
            Position=UDim2.fromScale(0.5,0.5),ZIndex=21})
        create("UICorner","UICorner",knob,{CornerRadius=UDim.new(1,0)})
        jump=create("TextButton","PCJump",gui,{Text="",AutoButtonColor=false,Active=true,
            Font=Enum.Font.GothamBold,TextSize=35,TextColor3=Color3.fromRGB(225,225,225),
            BackgroundColor3=Color3.fromRGB(55,55,55),BackgroundTransparency=1,
            BorderSizePixel=0,AnchorPoint=Vector2.new(0,0),ZIndex=20})
        round(jump)
    end
    self.gui,self.joystick,self.knob,self.jump=gui,stick,knob,jump
    gui:SetAttribute("PCMovementRebuild",true)
    local outer=stick:FindFirstChild("RobloxThumbstickOuter") or create("ImageLabel","RobloxThumbstickOuter",stick,{
        BackgroundTransparency=1,Image="rbxasset://textures/ui/TouchControlsSheet.png",
        ImageRectOffset=Vector2.new(0,0),ImageRectSize=Vector2.new(220,220),
        Size=UDim2.fromScale(1,1),Position=UDim2.fromOffset(0,0),ZIndex=stick.ZIndex,Active=false})
    if not knob:FindFirstChild("RobloxThumbstickStick") then
        create("ImageLabel","RobloxThumbstickStick",knob,{BackgroundTransparency=1,
            Image="rbxasset://textures/ui/TouchControlsSheet.png",ImageRectOffset=Vector2.new(220,0),
            ImageRectSize=Vector2.new(111,111),Size=UDim2.fromScale(1,1),
            Position=UDim2.fromScale(0,0),ZIndex=knob.ZIndex,Active=false})
    end
    self.jumpImage=jump:FindFirstChild("RobloxJumpButton") or create("ImageLabel","RobloxJumpButton",jump,{
        BackgroundTransparency=1,Image="rbxasset://textures/ui/Input/TouchControlsSheetV2.png",
        ImageRectOffset=Vector2.new(1,146),ImageRectSize=Vector2.new(144,144),Size=UDim2.fromScale(1,1),
        Position=UDim2.fromOffset(0,0),ZIndex=jump.ZIndex,Active=false})
    local function layoutFor(viewport)
        local size=math.min(viewport.X,viewport.Y)<=500 and 70 or 120
        return size, size==70 and UDim2.new(0,size/2-10,1,-size-20)
            or UDim2.new(0,size/2,1,-size*1.75),
            UDim2.new(1,-(size*1.5-10),1,size==70 and -size-20 or -size*1.75)
    end
    local function autoLayout(object,size,position)
        local last=self.auto[object]
        if last and (object.Size~=last.size or object.Position~=last.position) then
            self.auto[object]=nil -- External layout editor owns it from now on.
            return
        end
        if not last then return end
        object.Size=UDim2.fromOffset(size,size)
        object.Position=position
        self.auto[object]={size=object.Size,position=object.Position}
    end
    local viewport=services.Workspace.CurrentCamera and services.Workspace.CurrentCamera.ViewportSize
        or Vector2.new(896,414)
    local size,stickPosition,jumpPosition=layoutFor(viewport)
    for _,row in ipairs({{stick,stickPosition},{jump,jumpPosition}}) do
        local object,position=row[1],row[2]
        if not reused or (object.Size==UDim2.fromOffset(size,size) and object.Position==position) then
            object.Size=UDim2.fromOffset(size,size)
            object.Position=position
            self.auto[object]={size=object.Size,position=object.Position}
        end
    end
    if not reused then knob.Size=UDim2.fromOffset(size/2,size/2) end
    function self:Layout(newViewport)
        local newSize,stickPos,jumpPos=layoutFor(newViewport)
        local wasAuto=self.auto[stick]~=nil
        autoLayout(stick,newSize,stickPos)
        autoLayout(jump,newSize,jumpPos)
        if wasAuto and self.auto[stick] then knob.Size=UDim2.fromOffset(newSize/2,newSize/2) end
        -- Image scales with its externally resized parent, not a stale pixel size.
        outer.Size=UDim2.fromScale(1,1)
    end
    function self:Contains(position)
        if self.stopped or not gui.Parent or not gui.Enabled then return nil end
        for _,row in ipairs({{stick,"joystick"},{jump,"jump"}}) do
            local object=row[1]
            if object.Parent and object.Visible then
                local p,s=object.AbsolutePosition,object.AbsoluteSize
                if position.X>=p.X and position.X<=p.X+s.X and position.Y>=p.Y and position.Y<=p.Y+s.Y then
                    return row[2]
                end
            end
        end
        return nil
    end
    function self:SetKnob(offset)
        local limit=math.max(1,math.min(stick.AbsoluteSize.X,stick.AbsoluteSize.Y)*0.42)*0.62
        self.target=offset.Magnitude>limit and offset.Unit*limit or offset
    end
    function self:Step(dt)
        if self.stopped or not knob.Parent then return end
        local alpha=1-math.exp(-math.max(0,math.min(0.05,dt or 1/60))/0.040)
        self.offset=self.offset:Lerp(self.target,alpha)
        if (self.offset-self.target).Magnitude<0.06 then self.offset=self.target end
        knob.Position=UDim2.fromOffset(stick.AbsoluteSize.X/2+self.offset.X,stick.AbsoluteSize.Y/2+self.offset.Y)
    end
    function self:ResetKnob()
        self.offset,self.target=Vector2.zero,Vector2.zero
        knob.Position=UDim2.fromScale(0.5,0.5)
    end
    function self:SetJumpPressed(value)
        if self.jumpImage and self.jumpImage.Parent then
            self.jumpImage.ImageRectOffset=Vector2.new(value and 146 or 1,146)
        end
    end
    function self:Stop(retain)
        self:ResetKnob()
        self:SetJumpPressed(false)
        self.stopped=true
        if not retain then gui:Destroy() end
    end
    self:ResetKnob()
    return self
end
return Controls
