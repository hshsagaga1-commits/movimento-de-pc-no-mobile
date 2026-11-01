assert(loadfile("rebuild/GridSensor.lua"), "REBUILD MISSING: physical grid observer")
local Grid = dofile("rebuild/GridSensor.lua")
local Gate = dofile("rebuild/CameraGate.lua")
local Route = dofile("rebuild/KeyboardRoute.lua")
local count = 0
local function test(name, fn)
    local ok, reason=pcall(fn)
    if not ok then error(name .. ": " .. tostring(reason),0) end
    count=count+1
end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function signal()
    local s={listeners={}}
    function s:Connect(fn)
        local c={Connected=true}
        function c:Disconnect() self.Connected=false end
        self.listeners[#self.listeners+1]={c,fn}
        return c
    end
    function s:fire(...)
        for _, v in ipairs(self.listeners) do if v[1].Connected then v[2](...) end end
    end
    return s
end
local function vec(x,y,z) return {X=x,Y=y,Z=z} end
Vector3={new=vec}
OverlapParams={new=function() return {} end}
Enum={RaycastFilterType={Exclude="Exclude"},UserInputType={Keyboard="Keyboard"}}
local function part(name,size,parent,kind)
    local p={Name=name,Size=size or vec(0.25,4,0.25),Parent=parent,CanCollide=true,
        CollisionGroup="Default",ClassName=kind or "Part",touching={},
        Position=vec(0,0,0),CFrame={UpVector=vec(0,1,0),RightVector=vec(1,0,0),LookVector=vec(0,0,-1)}}
    function p:IsA(t) return t=="BasePart" or t==self.ClassName end
    function p:GetFullName() return self.Name end
    function p:GetTouchingParts() return self.touching end
    function p:GetAttribute() return nil end
    function p:FindFirstChildOfClass() return nil end
    return p
end
local function gridFixture()
    local char={Name="Character",Parent={}}
    function char:GetChildren() return self.children or {} end
    function char:FindFirstChildOfClass(t) if t=="Humanoid" then return {} end end
    local body=part("Torso",vec(2,2,1),char)
    char.children={body}
    local root=part("HumanoidRootPart",vec(2,2,1),char)
    root.CFrame={}
    local world={parts={},queries=0}
    function world:GetPartBoundsInBox() self.queries=self.queries+1 return self.parts end
    local tags={}
    local services={Workspace=world,CollectionService={HasTag=function(_,p,t)
        return tags[p]==t
    end},PhysicsService={CollisionGroupsAreCollidable=function() return true end}}
    local grid=Grid.new(services,{})
    grid:Bind(char,{},root)
    return grid,world,body,char,tags
end

test("nearby fence is not current physical contact",function()
    local grid,world=gridFixture()
    world.parts={part("Fence",vec(0.2,5,8),{})}
    local state=grid:Sample(0,true)
    eq(state.nearby,true)
    eq(state.contact,false)
    eq(grid:ContactNow(0).contact,false)
end)
test("actual collidable body contact is recognized and ends immediately on fresh query",function()
    local grid,world,body=gridFixture()
    local fence=part("Railing",vec(8,0.3,0.3),{})
    world.parts={fence}
    body.touching={fence}
    grid:Sample(0,true)
    eq(grid:ContactNow(0).contact,true)
    body.touching={}
    eq(grid:ContactNow(0.001).contact,false)
end)
test("ordinary floor walls and noncollidable grid decoration do not count",function()
    local grid,world,body=gridFixture()
    local floor=part("Grid",vec(12,0.2,12),{})
    local wall=part("Wall",vec(12,8,1),{})
    local decorative=part("Fence",vec(0.2,4,8),{})
    decorative.CanCollide=false
    world.parts={floor,wall,decorative}
    body.touching=world.parts
    grid:Sample(0,true)
    eq(grid:ContactNow(0).contact,false)
end)
test("anonymous mesh and truss are not silently classified as fences",function()
    local grid,world,body=gridFixture()
    world.parts={part("MeshPart",vec(0.3,6,8),{},"MeshPart"),part("Ladder",vec(2,8,2),{},"TrussPart")}
    body.touching=world.parts
    grid:Sample(0,true)
    eq(grid:ContactNow(0).contact,false)
end)
test("repeated anonymous bars provide geometric evidence without velocity writes",function()
    local grid,world,body=gridFixture()
    local parent={}
    world.parts={part("Part",nil,parent),part("Part",nil,parent),part("Part",nil,parent)}
    world.parts[1].Position=vec(-1,0,0)
    world.parts[3].Position=vec(1,0,0)
    body.touching={world.parts[1]}
    grid:Sample(0,true)
    local state=grid:ContactNow(0)
    eq(state.contact,true)
    eq(state.evidence,"repeated-bars")
end)
test("parallel furniture legs in a triangle are not a grid row",function()
    local grid,world,body=gridFixture()
    local parent={}
    world.parts={part("Part",nil,parent),part("Part",nil,parent),part("Part",nil,parent)}
    world.parts[1].Position=vec(-1,0,0)
    world.parts[2].Position=vec(1,0,0)
    world.parts[3].Position=vec(0,0,2)
    body.touching={world.parts[1]}
    grid:Sample(0,true)
    eq(grid:ContactNow(0).contact,false)
end)
test("body parts arriving after spawn can participate in contact",function()
    local grid,world,body,char=gridFixture()
    local fence=part("Fence",vec(0.2,4,8),{})
    body.CanCollide=false
    local torso=part("UpperTorso",vec(2,2,1),char)
    torso.touching={fence};char.children[#char.children+1]=torso
    world.parts={fence}
    grid:Bind(char,{},grid.root)
    grid:Sample(0,true)
    eq(grid:ContactNow(0).contact,true)
end)
test("broad queries are rate limited independently of frame rate",function()
    local grid,world=gridFixture()
    for i=0,239 do grid:Sample(i/120,true) end
    assert(world.queries<=25,"broad queries exceeded 12 Hz budget")
    local before=world.queries
    for i=240,360 do grid:Sample(i/120,false) end
    eq(world.queries,before)
end)
test("respawn clears all old physical contacts",function()
    local grid,world,body,char=gridFixture()
    local fence=part("Fence",vec(0.2,4,8),{})
    world.parts={fence};body.touching={fence}
    grid:Sample(0,true)
    eq(grid:ContactNow(0).contact,true)
    grid:Bind(nil,nil,nil)
    eq(grid:ContactNow(0.01).contact,false)
end)
test("camera gate tracks whole finger lifetime without a screen-half cutoff",function()
    local calls={}
    local controller={}
    for _,name in ipairs({"OnInputBegan","OnInputChanged","OnInputEnded"}) do
        controller[name]=function(_,input) calls[#calls+1]=name..input.id end
    end
    local captured={}
    local gate=Gate.new(function() return controller end,function(input) return captured[input] end)
    gate:Refresh()
    local stick={id="stick"};local camera={id="camera"}
    captured[stick]=true
    controller:OnInputBegan(stick)
    controller:OnInputBegan(camera)
    captured[stick]=nil
    controller:OnInputChanged(stick)
    controller:OnInputChanged(camera)
    controller:OnInputEnded(stick)
    controller:OnInputEnded(camera)
    eq(table.concat(calls,","),"OnInputBegancamera,OnInputChangedcamera,OnInputEndedcamera")
    gate:Stop()
    controller:OnInputBegan(stick)
    eq(#calls,4)
end)
test("keyboard route respects global game disable and restores original controller",function()
    local touch={};local keyboard={}
    local touchController={enabled=true}
    function touchController:Enable(v) self.enabled=v end
    local keys={enabled=false}
    function keys:Enable(v) self.enabled=v return true end
    local controls={activeControlModule=touch,activeController=touchController,controlsEnabled=true}
    function controls:SwitchToController(module)
        self.activeControlModule=module
        self.activeController=module==keyboard and keys or touchController
        self.activeController:Enable(self.controlsEnabled)
    end
    local route=Route.new({Controls=controls,KeyboardModule=keyboard,TouchModules={touch}}, {})
    route:Start()
    eq(route:IsReady(),true)
    controls.controlsEnabled=false
    keys.enabled=false
    route:Refresh()
    eq(route:IsReady(),false)
    eq(keys.enabled,false)
    controls.controlsEnabled=true
    route:Refresh()
    eq(route:IsReady(),true)
    route:Stop()
    eq(controls.activeControlModule,touch)
end)
test("camera replacement retains suppression for an already captured finger",function()
    local calls=0
    local function camera()
        return {OnInputBegan=function() calls=calls+1 end,
            OnInputChanged=function() calls=calls+1 end,OnInputEnded=function() calls=calls+1 end}
    end
    local current=camera()
    local finger={}
    local gate=Gate.new(function() return current end,function(input) return input==finger end)
    gate:Refresh();current:OnInputBegan(finger)
    current=camera();gate:Refresh()
    current:OnInputChanged(finger);current:OnInputEnded(finger)
    eq(calls,0)
    gate:Stop()
end)
test("disabled flag contract is honored at start and after reenable",function()
    local touch,keyboard={},{}
    local active={enabled=false,Enable=function(self,v) self.enabled=v end}
    local controls={disabled=true,activeControlModule=touch,activeController={enabled=false}}
    function controls:SwitchToController(module)
        self.activeControlModule=module
        self.activeController=module==keyboard and active or {enabled=false}
        if not self.disabled then self.activeController:Enable(true) end
    end
    local route=Route.new({Controls=controls,KeyboardModule=keyboard,TouchModules={touch}}, {})
    route:Start()
    eq(route:IsReady(),false)
    eq(controls.activeControlModule,touch)
    controls.disabled=false;route:Refresh()
    eq(route:IsReady(),true)
    controls.disabled=true;active.enabled=false;route:Refresh()
    eq(route:IsReady(),false)
    eq(active.enabled,false)
    route:Stop()
end)
print("PASS: "..count.." adapter behavior tests")
