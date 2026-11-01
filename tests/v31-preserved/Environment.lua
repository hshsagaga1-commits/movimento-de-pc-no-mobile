local E={}
function E.new(F)
    F.install()
    Enum.Material.Metal={Name="Metal"}
    Enum.Material.Plastic={Name="Plastic"}
    Enum.Material.DiamondPlate={Name="DiamondPlate"}
    local e={time=0,env={},events={},waiters={},delays={},bound={},rays=0,queries=0,parts={}}
    e.pg=Instance.new("Folder");e.pg.Name="PlayerGui"
    e.player=Instance.new("Folder");e.player.Name="Player";e.pg.Parent=e.player
    e.player.CharacterAdded=F.signal()
    e.player.WaitForChild=function(_,name) if name=="PlayerGui" then return e.pg end end
    e.uis={InputBegan=F.signal(),InputChanged=F.signal(),InputEnded=F.signal()}
    e.run={Heartbeat=F.signal()}
    e.run.Heartbeat.Wait=function() e.waiters[#e.waiters+1]=coroutine.running();return coroutine.yield() end
    function e.run:BindToRenderStep(name,priority,fn) e.bound[name]=fn end
    function e.run:UnbindFromRenderStep(name) e.bound[name]=nil end
    e.world=Instance.new("Folder");e.world.Name="Workspace";e.world.Gravity=196.2
    e.camera=Instance.new("Camera");e.camera.ViewportSize=Vector2.new(896,414)
    local function cf(position,look)
        return {Position=position,LookVector=look or Vector3.new(0,0,-1),RightVector=Vector3.new(1,0,0),
            Lerp=function(_,target) return target end}
    end
    CFrame={lookAt=function(position,target) return cf(position,(target-position).Unit) end}
    e.camera.CFrame=cf(Vector3.zero);e.world.CurrentCamera=e.camera
    e.char=Instance.new("Model");e.char.Name="Character";e.char.Parent=e.world
    e.root=Instance.new("Part");e.root.Name="HumanoidRootPart";e.root.Parent=e.char
    e.root.Size=Vector3.new(2,2,1);e.root.Position=Vector3.new(0,2,0);e.root.CanCollide=true
    e.root.CollisionGroup="Default";e.root.CFrame=cf(e.root.Position)
    e.root.AssemblyLinearVelocity=Vector3.new(32,0,-40)
    e.hum=Instance.new("Humanoid");e.hum.Parent=e.char;e.hum.Name="Humanoid"
    e.hum.Health=100;e.hum.WalkSpeed=16;e.hum.Sit=false;e.hum.MoveDirection=Vector3.new(0,0,-1)
    e.hum.FloorMaterial=Enum.Material.Concrete
    e.hum.GetState=function() return Enum.HumanoidStateType.Running end
    e.player.Character=e.char
    e.physics={CollisionGroupsAreCollidable=function() return true end}
    e.tags={HasTag=function() return false end}
    e.http={GenerateGUID=function() return "fresh-"..tostring(e.time) end,
        JSONEncode=function(_,value)
            local seen={}
            local function visit(item)
                if type(item)=="number" then assert(item==item and math.abs(item)<math.huge,'non-finite JSON number')
                elseif type(item)=="table" then
                    assert(not seen[item],'JSON cycle or Roblox object')
                    seen[item]=true
                    for _,child in pairs(item) do visit(child) end
                    seen[item]=nil
                end
            end
            visit(value)
            return "{\"test\":true}"
        end}
    e.world.Raycast=function(_,origin,direction,params)
        e.rays=e.rays+1
        if e.raycast then return e.raycast(origin,direction,params) end
    end
    e.world.GetPartBoundsInRadius=function()
        e.queries=e.queries+1;return e.parts
    end
    e.services={Players={LocalPlayer=e.player},UserInputService=e.uis,RunService=e.run,
        Workspace=e.world,PhysicsService=e.physics,CollectionService=e.tags,HttpService=e.http,
        VirtualInputManager={SendKeyEvent=function(_,down,key)
            e.events[#e.events+1]={key=key.Name,down=down,time=e.time}
        end}}
    e.game={GameId=3647333358,GetService=function(_,name) assert(e.services[name],name);return e.services[name] end}
    function e:part(name,size,position)
        local p=Instance.new("Part");p.Name=name;p.Parent=self.world;p.Size=size or Vector3.new(0.3,5,8)
        p.Position=position or Vector3.new(2,2,0);p.CanCollide=true;p.Material=Enum.Material.Metal
        p.Transparency=0;p.CollisionGroup="Default"
        p.GetClosestPointOnSurface=function() return p.Position end
        return p
    end
    function e:step(dt)
        self.time=self.time+(dt or 1/60)
        local waiting=self.waiters;self.waiters={}
        for _,thread in ipairs(waiting) do
            local ok,reason=coroutine.resume(thread);assert(ok,reason)
        end
        self.run.Heartbeat:fire(dt or 1/60)
        for _,fn in pairs(self.bound) do fn(dt or 1/60) end
    end
    function e:spawn(fn)
        local thread=coroutine.create(fn)
        local ok,reason=coroutine.resume(thread);assert(ok,reason)
        return thread
    end
    return e
end
return E
