local F={}
function F.signal()
    local s={listeners={}}
    function s:Connect(fn)
        local connection={Connected=true}
        function connection:Disconnect() self.Connected=false end
        self.listeners[#self.listeners+1]={connection,fn}
        return connection
    end
    function s:fire(...)
        for _,v in ipairs(self.listeners) do if v[1].Connected then v[2](...) end end
    end
    return s
end
local V={}
local function vector(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},V) end
V.__index=function(v,key)
    if key=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
    if key=="Unit" then return v/v.Magnitude end
    if key=="Lerp" then return function(a,b,t) return a+(b-a)*t end end
    if key=="Dot" then return function(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
end
V.__add=function(a,b) return vector(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
V.__sub=function(a,b) return vector(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
V.__mul=function(a,b) return vector(a.X*b,a.Y*b,a.Z*b) end
V.__div=function(a,b) return vector(a.X/b,a.Y/b,a.Z/b) end
V.__eq=function(a,b) return a.X==b.X and a.Y==b.Y and a.Z==b.Z end
local U={}
U.__eq=function(a,b)
    return a.X.Scale==b.X.Scale and a.X.Offset==b.X.Offset
        and a.Y.Scale==b.Y.Scale and a.Y.Offset==b.Y.Offset
end
local function udim2(xs,xo,ys,yo)
    return setmetatable({X={Scale=xs,Offset=xo},Y={Scale=ys,Offset=yo}},U)
end
function F.install()
    Vector2={new=vector,zero=vector(0,0)}
    Vector3={new=vector,zero=vector(0,0,0)}
    UDim2={new=udim2,fromOffset=function(x,y) return udim2(0,x,0,y) end,
        fromScale=function(x,y) return udim2(x,0,y,0) end}
    UDim={new=function(a,b) return {Scale=a,Offset=b} end}
    Color3={new=vector,fromRGB=vector}
    OverlapParams={new=function() return {} end}
    local function enum(values)
        local out={}
        for index,name in ipairs(values) do out[name]={Name=name,Value=index} end
        return out
    end
    Enum={Font=enum({"GothamBold"}),UserInputType=enum({"Touch","Keyboard"}),
        RaycastFilterType=enum({"Exclude"}),UserInputState=enum({"Begin","Change","End","Cancel"}),
        HumanoidStateType=enum({"Running","Landed","Jumping","Freefall","Seated","Swimming","Climbing","Dead","Physics","Ragdoll"}),
        Material=enum({"Air","Concrete"}),RenderPriority={Input={Value=100},Camera={Value=200}},
        KeyCode=enum({"W","A","S","D","Space"})}
    local methods={}
    local guiClasses={Frame=true,TextButton=true,ImageLabel=true,TextLabel=true}
    local mt={}
    mt.__index=function(obj,key)
        if methods[key] then return methods[key] end
        if key=="Parent" then return rawget(obj,"_parent") end
        if key=="AbsoluteSize" then
            if obj.ClassName=="ScreenGui" or obj.Name=="PlayerGui" then return vector(896,414) end
            local size=obj.Size or UDim2.fromOffset(0,0)
            local parent=obj.Parent and obj.Parent.AbsoluteSize or vector(896,414)
            return vector(parent.X*size.X.Scale+size.X.Offset,parent.Y*size.Y.Scale+size.Y.Offset)
        end
        if key=="AbsolutePosition" then
            local parent=obj.Parent and obj.Parent.AbsoluteSize or vector(896,414)
            local origin=obj.Parent and obj.Parent.AbsolutePosition or vector(0,0)
            local position=obj.Position or UDim2.fromOffset(0,0)
            local anchor=obj.AnchorPoint or vector(0,0)
            return vector(origin.X+parent.X*position.X.Scale+position.X.Offset-obj.AbsoluteSize.X*anchor.X,
                origin.Y+parent.Y*position.Y.Scale+position.Y.Offset-obj.AbsoluteSize.Y*anchor.Y)
        end
        return obj._props[key]
    end
    mt.__newindex=function(obj,key,value)
        if key=="Parent" then
            local old=rawget(obj,"_parent")
            if old then
                for i,c in ipairs(old._children) do if c==obj then table.remove(old._children,i) break end end
            end
            rawset(obj,"_parent",value)
            if value then value._children[#value._children+1]=obj end
        else obj._props[key]=value end
        if obj._signals[key] then obj._signals[key]:fire() end
    end
    function methods:IsA(kind)
        return kind==self.ClassName or kind=="Instance" or (kind=="GuiObject" and guiClasses[self.ClassName])
            or (kind=="BasePart" and self.ClassName=="Part")
    end
    function methods:GetChildren() return self._children end
    function methods:GetDescendants()
        local out={}
        local function visit(node) for _,c in ipairs(node._children) do out[#out+1]=c visit(c) end end
        visit(self)
        return out
    end
    function methods:FindFirstChild(name,recursive)
        for _,c in ipairs(recursive and self:GetDescendants() or self._children) do if c.Name==name then return c end end
    end
    function methods:WaitForChild(name) return self:FindFirstChild(name) end
    function methods:FindFirstChildOfClass(kind)
        for _,c in ipairs(self._children) do if c:IsA(kind) then return c end end
    end
    function methods:GetPropertyChangedSignal(name)
        if not self._signals[name] then self._signals[name]=F.signal() end
        return self._signals[name]
    end
    function methods:SetAttribute(name,value) self._attrs[name]=value end
    function methods:GetAttribute(name) return self._attrs[name] end
    function methods:GetAttributes() return self._attrs end
    function methods:GetFullName() return self.Name end
    function methods:GetTouchingParts() return self.Touching or {} end
    function methods:Destroy()
        local children={}; for _,c in ipairs(self._children) do children[#children+1]=c end
        for _,c in ipairs(children) do c:Destroy() end
        self.Parent=nil;self.Destroyed=true
    end
    function methods:Clone()
        local clone=Instance.new(self.ClassName)
        for k,v in pairs(self._props) do clone[k]=v end
        for k,v in pairs(self._attrs) do clone:SetAttribute(k,v) end
        for _,c in ipairs(self._children) do c:Clone().Parent=clone end
        return clone
    end
    Instance={new=function(kind)
        return setmetatable({_props={ClassName=kind,Name=kind,Visible=true,Enabled=true},
            _children={},_attrs={},_signals={}},mt)
    end}
    typeof=function(value)
        if getmetatable(value)==V then return value.Z==0 and "Vector2" or "Vector3" end
        return type(value)
    end
    warn=function() end
end
return F
