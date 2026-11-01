-- Select the existing Roblox Keyboard controller; never call Player/Humanoid:Move.
local Route={}
local function globallyDisabled(controls)
    return rawget(controls,"controlsEnabled")==false or rawget(controls,"disabled")==true
end
function Route.new(services,env)
    local self={controls=services.Controls,keyboard=services.KeyboardModule,
        touchModules=services.TouchModules or {},running=false,enabled=true,
        status="not-started",restores=0,errors=0,facadeActive=false,generation=0}
    local originalModule,originalController,previousSwitch,wrappedSwitch
    local hadOwnSwitch=false
    local previousIndex,indexWrapper
    local uis=services.UserInputService
    local function activate(fn)
        self.facadeActive=true
        local ok,message=pcall(fn)
        self.facadeActive=false
        if not ok then self.errors=self.errors+1 self.status=tostring(message) end
        return ok
    end
    local function installFacade()
        if type(hookmetamethod)~="function" or not uis then return end
        local closure=type(newcclosure)=="function" and newcclosure or function(fn) return fn end
        indexWrapper=closure(function(object,key)
            -- Activation is synchronous and scoped. PlayerModule may inherit the
            -- executor's caller identity, so caller identity cannot gate this read.
            if self.facadeActive and object==uis then
                if key=="KeyboardEnabled" or key=="MouseEnabled" then return true end
                if key=="TouchEnabled" or key=="GamepadEnabled" then return false end
            end
            return previousIndex(object,key)
        end)
        local ok,value=pcall(function() return hookmetamethod(game,"__index",indexWrapper) end)
        if ok and type(value)=="function" then previousIndex=value else indexWrapper=nil end
    end
    local function discover()
        if self.controls and self.keyboard then return true end
        local player=services.player
        local scripts=player and player:FindFirstChild("PlayerScripts")
        local playerScript=scripts and scripts:FindFirstChild("PlayerModule")
        if not playerScript then self.status="PlayerModule-missing" return false end
        local ok,module=pcall(require,playerScript)
        if not ok or type(module)~="table" then self.status="PlayerModule-unavailable" return false end
        self.playerModule=module
        local good,controls=pcall(function() return module:GetControls() end)
        if not good or type(controls)~="table" then self.status="controls-unavailable" return false end
        self.controls=controls
        local controlScript=playerScript:FindFirstChild("ControlModule")
        local keyboardScript=controlScript and controlScript:FindFirstChild("Keyboard")
        local loaded,keyboard=pcall(function() return keyboardScript and require(keyboardScript) end)
        if not loaded or type(keyboard)~="table" then self.status="Keyboard-module-unavailable" return false end
        self.keyboard=keyboard
        for _,name in ipairs({"TouchThumbstick","DynamicThumbstick"}) do
            local child=controlScript:FindFirstChild(name)
            if child then
                local success,touch=pcall(require,child)
                if success and type(touch)=="table" then self.touchModules[#self.touchModules+1]=touch end
            end
        end
        return true
    end
    local function isTouch(module)
        for _,touch in ipairs(self.touchModules) do if touch==module then return true end end
        return false
    end
    function self:IsReady()
        local c=self.controls
        local active=c and rawget(c,"activeController")
        return self.running and self.enabled and c~=nil and not globallyDisabled(c)
            and rawget(c,"activeControlModule")==self.keyboard
            and type(active)=="table" and rawget(active,"enabled")==true
    end
    function self:Refresh()
        if not self.running or not self.enabled or not self.controls then return end
        local c=self.controls
        if globallyDisabled(c) then self.status="game-controls-disabled" return end
        local current=rawget(c,"activeControlModule")
        -- Do not override vehicle, scripted, nil/menu or unrelated controllers.
        if current~=self.keyboard and not isTouch(current) then self.status="other-controller" return end
        local before=rawget(c,"activeController")
        local wasEnabled=type(before)=="table" and rawget(before,"enabled")==true
        activate(function()
            if current~=self.keyboard then
                previousSwitch(c,self.keyboard)
                self.restores=self.restores+1
            end
            local active=rawget(c,"activeController")
            if rawget(c,"activeControlModule")==self.keyboard and type(active)=="table"
                and rawget(active,"enabled")~=true and type(active.Enable)=="function" then
                active:Enable(true)
            end
        end)
        if self:IsReady() and (current~=self.keyboard or rawget(c,"activeController")~=before or not wasEnabled) then
            self.generation=self.generation+1
        end
        self.status=self:IsReady() and "keyboard-ready" or "keyboard-not-enabled"
    end
    function self:Start()
        if self.running then return self:IsReady() end
        if not discover() then return false end
        local c=self.controls
        originalModule=rawget(c,"activeControlModule")
        originalController=rawget(c,"activeController")
        hadOwnSwitch=rawget(c,"SwitchToController")~=nil
        previousSwitch=c.SwitchToController
        if type(previousSwitch)~="function" then self.status="SwitchToController-missing" return false end
        installFacade()
        self.running=true
        wrappedSwitch=function(owner,module,...)
            if owner==c and self.running and self.enabled and isTouch(module) then
                if globallyDisabled(c) then return previousSwitch(owner,module,...) end
                if rawget(c,"activeControlModule")==self.keyboard then return nil end
                local arguments={...}
                activate(function()
                    previousSwitch(owner,self.keyboard,(table.unpack or unpack)(arguments))
                end)
                self.generation=self.generation+1
                return nil
            end
            return previousSwitch(owner,module,...)
        end
        rawset(c,"SwitchToController",wrappedSwitch)
        -- Explicit initial selection also works when PlayerModule starts with nil.
        if not globallyDisabled(c) then
            activate(function() previousSwitch(c,self.keyboard) end)
            self.generation=self.generation+1
        end
        self:Refresh()
        return self:IsReady()
    end
    function self:SetEnabled(value)
        self.enabled=value~=false
        if not self.enabled and self.running and originalModule then
            pcall(previousSwitch,self.controls,originalModule)
        elseif self.enabled then self:Refresh() end
    end
    function self:GetState()
        return {ready=self:IsReady(),status=self.status,facadeActive=self.facadeActive,
            facadeInstalled=previousIndex~=nil,restores=self.restores,errors=self.errors}
    end
    function self:Stop()
        self.running=false
        self.facadeActive=false
        local c=self.controls
        if c and rawget(c,"SwitchToController")==wrappedSwitch then
            rawset(c,"SwitchToController",hadOwnSwitch and previousSwitch or nil)
        end
        if c and previousSwitch and originalModule and rawget(c,"activeControlModule")==self.keyboard then
            pcall(previousSwitch,c,originalModule)
            if originalController and rawget(c,"activeController")==originalController
                and globallyDisabled(c) and type(originalController.Enable)=="function" then
                pcall(originalController.Enable,originalController,false)
            end
        end
        if previousIndex and type(hookmetamethod)=="function" then
            local owned=false
            if type(getrawmetatable)=="function" then
                local ok,meta=pcall(getrawmetatable,game)
                owned=ok and type(meta)=="table" and rawget(meta,"__index")==indexWrapper
            end
            if owned then pcall(function() hookmetamethod(game,"__index",previousIndex) end) end
            -- A later hook may delegate to this inactive wrapper. Retain its
            -- predecessor; never remove someone else's hook or turn a chain nil.
        end
    end
    return self
end
return Route
