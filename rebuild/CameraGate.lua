-- Gate control fingers by identity, not screen halves. Never edit camera CFrame.
local Gate={}
function Gate.new(getController,owns)
    local self={controller=nil,hooks={},blocked={},methods=0,errors=0}
    function self:Restore(preserveTouches)
        for i=#self.hooks,1,-1 do
            local h=self.hooks[i]
            if rawget(h.owner,h.name)==h.wrapper then rawset(h.owner,h.name,h.previous) end
        end
        self.hooks={}
        if not preserveTouches then self.blocked={} end
        self.methods=0
    end
    function self:Refresh()
        local controller=getController()
        if controller==self.controller then return end
        self:Restore(true)
        self.controller=controller
        if type(controller)~="table" then return end
        for _,name in ipairs({"OnInputBegan","OnInputChanged","OnInputEnded"}) do
            local original=controller[name]
            if type(original)=="function" then
                local previous=rawget(controller,name)
                local wrapper=function(owner,input,...)
                    if owner==controller then
                        if name=="OnInputBegan" then
                            if owns(input,true) then self.blocked[input]=true return nil end
                        elseif self.blocked[input] or owns(input,false) then
                            self.blocked[input]=true
                            if name=="OnInputEnded" then self.blocked[input]=nil end
                            return nil
                        end
                    end
                    return original(owner,input,...)
                end
                rawset(controller,name,wrapper)
                self.hooks[#self.hooks+1]={owner=controller,name=name,previous=previous,wrapper=wrapper}
                self.methods=self.methods+1
            end
        end
    end
    function self:Stop() self:Restore(false) self.controller=nil end
    return self
end
return Gate
