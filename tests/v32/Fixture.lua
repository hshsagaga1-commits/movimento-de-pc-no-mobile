return function(F,E)
    local e=E.new(F)
    local baseNew=Instance.new
    local mt=getmetatable(e.pg)
    local baseParent,baseIndex=mt.__newindex,mt.__index
    mt.__newindex=function(node,key,value)
        local old=node.Parent
        if key=="Parent" and old~=value then
            if old then
                old.ChildRemoved:fire(node)
                local ancestor=old
                while ancestor do
                    ancestor.DescendantRemoving:fire(node)
                    ancestor=ancestor.Parent
                end
            end
            baseParent(node,key,value)
            if value then
                value.ChildAdded:fire(node)
                local ancestor=value
                while ancestor do
                    ancestor.DescendantAdded:fire(node)
                    ancestor=ancestor.Parent
                end
            end
        else
            baseParent(node,key,value)
        end
    end
    local overrides={
        SetAttribute=function(self,name,value)
            baseIndex(self,"SetAttribute")(self,name,value)
            self.AttributeChanged:fire(name)
        end,
        Destroy=function(self)
            self.Destroying:fire()
            baseIndex(self,"Destroy")(self)
            self.AncestryChanged:fire(self,nil)
        end,
    }
    mt.__index=function(obj,key) return overrides[key] or baseIndex(obj,key) end
    local function extend(obj)
        for _,name in ipairs({"ChildAdded","ChildRemoved","DescendantAdded","DescendantRemoving",
            "AttributeChanged","Destroying","AncestryChanged"}) do obj[name]=F.signal() end
        return obj
    end
    Instance.new=function(kind) return extend(baseNew(kind)) end
    for _,obj in ipairs({e.pg,e.player,e.world,e.camera,e.char,e.hum,e.root}) do extend(obj) end
    e.player.CharacterRemoving=F.signal()
    e.uis=Instance.new("UserInputService")
    e.uis.WindowFocusReleased=F.signal()
    e.uis.InputChanged=F.signal()
    e.uis.MouseIconEnabled=true
    e.services.UserInputService=e.uis
    e.services.ContextActionService={}
    Enum.RenderPriority.Last={Value=2000}
    Enum.Font.Code={Name="Code"}
    Enum.TextXAlignment={Left={Name="Left"}}
    Enum.KeyCode.LeftControl={Name="LeftControl"}
    Enum.PreferredInput={KeyboardAndMouse={Name="KeyboardAndMouse"}}
    game=e.game
    workspace=e.world
    getgenv=function() return e.env end
    local wallClock=os.clock
    os={clock=function() return e.time end}
    e.wallClock=wallClock
    local queued={}
    e.queued=queued
    task={
        spawn=function(fn) return e:spawn(fn) end,
        wait=function() return e.run.Heartbeat:Wait() end,
        delay=function(seconds,fn)
            local job={at=e.time+seconds,callback=fn}
            queued[job]=true
            return job
        end,
        cancel=function(job) queued[job]=nil end
    }
    local step=e.step
    function e:step(dt)
        step(self,dt)
        local ready={}
        for job in pairs(queued) do
            if job.at<=self.time then ready[#ready+1]=job end
        end
        for _,job in ipairs(ready) do
            if queued[job] then
                queued[job]=nil
                self:spawn(job.callback)
            end
        end
    end
    return e
end
