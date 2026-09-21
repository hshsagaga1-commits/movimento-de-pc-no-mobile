-- Evade PC Identity V1
-- Standalone. Makes Roblox's Lua control stack use/read keyboard+mouse state.
-- Does not own movement, camera, grid, body view or lag switch.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local VirtualInputManager=game:GetService("VirtualInputManager")

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local ENV=(type(getgenv)=="function" and getgenv()) or _G

local VERSION="EvadePC-Identity-V1"
local BIND_NAME="__EvadePCIdentityV1"

local old=ENV.__EvadePCIdentityV1Cleanup
if type(old)=="function" then pcall(old) end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local enabled=true
local controls=nil
local touchModule=nil
local keyboardModule=nil
local facadeInstalled=false
local switchHookInstalled=false
local switchHookMode="none"
local previousIndex=nil
local previousNamecall=nil
local switchOwner=nil
local switchPrevious=nil
local switchTarget=nil
local switchOriginal=nil
local blockedTouchSwitches=0
local forcedKeyboardRestores=0
local spoofReads=0
local lastError="none"

local function clean(v)
    local ok,s=pcall(tostring,v)
    return ok and s or "<?>"
end

local function getMeta(tbl)
    local mt=nil
    if type(getrawmetatable)=="function" then pcall(function() mt=getrawmetatable(tbl) end) end
    if type(mt)~="table" then pcall(function() mt=getmetatable(tbl) end) end
    return type(mt)=="table" and mt or nil
end

local function findMethod(root,name)
    local seen={}
    local function visit(tbl,depth)
        if type(tbl)~="table" or seen[tbl] or depth>12 then return nil end
        seen[tbl]=true

        local own=nil
        pcall(function() own=rawget(tbl,name) end)
        if type(own)=="function" then return {owner=tbl,fn=own,name=name} end

        local index=nil
        pcall(function() index=rawget(tbl,"__index") end)
        if type(index)=="table" then
            local found=visit(index,depth+1)
            if found then return found end
        end

        local mt=getMeta(tbl)
        if mt then
            local found=visit(mt,depth+1)
            if found then return found end
        end
        return nil
    end
    return visit(root,0)
end

local function locateControls()
    local scripts=player:FindFirstChild("PlayerScripts")
    local pm=scripts and scripts:FindFirstChild("PlayerModule")
    if not pm then return false,"PlayerModule-missing" end

    local ok,module=pcall(require,pm)
    if not ok or type(module)~="table" then return false,"PlayerModule-require:"..clean(module) end

    local value=nil
    local okControls=pcall(function()
        if type(module.GetControls)=="function" then
            value=module:GetControls()
        else
            value=rawget(module,"controls")
        end
    end)
    if not okControls or type(value)~="table" then return false,"controls-unavailable" end

    controls=value
    touchModule=rawget(controls,"activeControlModule")
    return true,"ok"
end

local function callerIsExecutor()
    if type(checkcaller)~="function" then return false end
    local ok,v=pcall(checkcaller)
    return ok and v==true
end

local function installFacade()
    if type(hookmetamethod)~="function"
        or type(checkcaller)~="function"
        or type(getnamecallmethod)~="function" then
        return false,"hook-api-unavailable"
    end

    local wrap=type(newcclosure)=="function" and newcclosure or function(fn) return fn end

    local indexReplacement
    indexReplacement=wrap(function(self,key)
        if enabled and self==UserInputService and not callerIsExecutor() then
            if key=="PreferredInput" then
                spoofReads+=1
                return Enum.PreferredInput.KeyboardAndMouse
            elseif key=="TouchEnabled" then
                spoofReads+=1
                return false
            elseif key=="KeyboardEnabled" then
                spoofReads+=1
                return true
            elseif key=="MouseEnabled" then
                spoofReads+=1
                return true
            elseif key=="GamepadEnabled" then
                spoofReads+=1
                return false
            end
        end
        return previousIndex(self,key)
    end)

    local okIndex,oldIndex=pcall(function()
        return hookmetamethod(game,"__index",indexReplacement)
    end)
    if not okIndex or type(oldIndex)~="function" then
        return false,"index-hook-failed"
    end
    previousIndex=oldIndex

    local namecallReplacement
    namecallReplacement=wrap(function(self,...)
        if enabled and self==UserInputService and not callerIsExecutor() then
            local method=getnamecallmethod()
            if method=="GetLastInputType" then
                spoofReads+=1
                return Enum.UserInputType.Keyboard
            elseif method=="GetPlatform" then
                local win=nil
                pcall(function() win=Enum.Platform.Windows end)
                if win then
                    spoofReads+=1
                    return win
                end
            end
        end
        return previousNamecall(self,...)
    end)

    local okName,oldName=pcall(function()
        return hookmetamethod(game,"__namecall",namecallReplacement)
    end)
    if not okName or type(oldName)~="function" then
        pcall(function() hookmetamethod(game,"__index",previousIndex) end)
        previousIndex=nil
        return false,"namecall-hook-failed"
    end

    previousNamecall=oldName
    facadeInstalled=true
    return true,"ok"
end

local function getUpvalues(fn)
    local getter=(debug and debug.getupvalues) or getupvalues
    if type(getter)~="function" then return nil end
    local ok,values=pcall(getter,fn)
    return ok and type(values)=="table" and values or nil
end

local function discoverKeyboardFromMap()
    if type(controls)~="table" then return nil end
    local target=findMethod(controls,"SelectComputerMovementModule")
    if not target then return nil end
    local values=getUpvalues(target.fn)
    if not values then return nil end

    for _,value in pairs(values) do
        if type(value)=="table" then
            local candidate=nil
            pcall(function() candidate=value[Enum.UserInputType.Keyboard] end)
            if type(candidate)=="table" and candidate~=touchModule then
                return candidate
            end
        end
    end
    return nil
end

local function seedKeyboard()
    if type(controls)~="table" then return nil end

    pcall(function()
        VirtualInputManager:SendKeyEvent(true,Enum.KeyCode.LeftControl,false,game)
        task.wait(0.03)
        VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.LeftControl,false,game)
    end)

    for _=1,12 do
        task.wait(0.025)
        local active=rawget(controls,"activeControlModule")
        if type(active)=="table" and active~=touchModule then
            return active
        end
    end
    return nil
end

local function discoverKeyboard()
    keyboardModule=discoverKeyboardFromMap()
    if keyboardModule then return true end

    keyboardModule=seedKeyboard()
    if keyboardModule then return true end

    local target=findMethod(controls,"OnComputerMovementModeChange")
    if target then
        pcall(function() target.fn(controls) end)
        task.wait(0.04)
        local active=rawget(controls,"activeControlModule")
        if type(active)=="table" and active~=touchModule then
            keyboardModule=active
            return true
        end
    end
    return false
end

local function forceKeyboard()
    if type(controls)~="table" or type(keyboardModule)~="table" then return false end
    if rawget(controls,"activeControlModule")==keyboardModule then return true end

    local target=findMethod(controls,"SwitchToController")
    local fn=switchOriginal or (target and target.fn)
    if type(fn)~="function" then return false end

    local ok=pcall(function() fn(controls,keyboardModule) end)
    if ok then forcedKeyboardRestores+=1 end
    return ok
end

local function installSwitchGate()
    local target=findMethod(controls,"SwitchToController")
    if not target then return false,"SwitchToController-missing" end
    switchTarget=target.fn

    if type(hookfunction)=="function" then
        local original=nil
        local replacement
        replacement=function(self,module,...)
            if enabled and self==controls and touchModule and module==touchModule then
                blockedTouchSwitches+=1
                if rawget(self,"activeControlModule")~=keyboardModule then
                    return original(self,keyboardModule,...)
                end
                return nil
            end
            return original(self,module,...)
        end

        local ok,oldfn=pcall(function() return hookfunction(target.fn,replacement) end)
        if ok and type(oldfn)=="function" then
            original=oldfn
            switchOriginal=oldfn
            switchHookInstalled=true
            switchHookMode="hookfunction"
            return true,"hookfunction"
        end
    end

    switchOwner=target.owner
    switchPrevious=rawget(switchOwner,target.name)
    if type(switchPrevious)~="function" then return false,"rawset-unavailable" end
    switchOriginal=switchPrevious

    rawset(switchOwner,target.name,function(self,module,...)
        if enabled and self==controls and touchModule and module==touchModule then
            blockedTouchSwitches+=1
            if rawget(self,"activeControlModule")~=keyboardModule then
                return switchOriginal(self,keyboardModule,...)
            end
            return nil
        end
        return switchOriginal(self,module,...)
    end)

    switchHookInstalled=true
    switchHookMode="rawset"
    return true,"rawset"
end

local okControls,status=locateControls()
if not okControls then
    lastError=status
else
    local okFacade,facadeStatus=installFacade()
    if not okFacade then lastError=facadeStatus end

    if not discoverKeyboard() then
        lastError="keyboard-module-not-found"
    else
        forceKeyboard()
        local okGate,gateStatus=installSwitchGate()
        if not okGate then lastError=gateStatus end
    end
end

RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Last.Value-1,function()
    if not enabled then return end

    -- Keep the real mobile HUD visible; only the control owner is PC.
    local touchGui=playerGui:FindFirstChild("TouchGui")
    if touchGui and touchGui:IsA("ScreenGui") then
        touchGui.Enabled=true
    end

    if type(controls)=="table" and type(keyboardModule)=="table" then
        if touchModule and rawget(controls,"activeControlModule")==touchModule then
            forceKeyboard()
        end
    end
end)

local api={
    Version=VERSION,
    SetEnabled=function(value)
        enabled=value~=false
        if enabled then forceKeyboard() end
    end,
    IsEnabled=function() return enabled end,
    GetState=function()
        local active=type(controls)=="table" and rawget(controls,"activeControlModule") or nil
        return {
            facadeInstalled=facadeInstalled,
            switchHookInstalled=switchHookInstalled,
            switchHookMode=switchHookMode,
            keyboardModuleFound=type(keyboardModule)=="table",
            touchModuleFound=type(touchModule)=="table",
            activeIsKeyboard=active~=nil and active==keyboardModule,
            blockedTouchSwitches=blockedTouchSwitches,
            forcedKeyboardRestores=forcedKeyboardRestores,
            spoofReads=spoofReads,
            lastError=lastError,
        }
    end,
}

ENV.EvadePCIdentityV1=api
ENV.__EvadePCIdentityV1Cleanup=function()
    enabled=false
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

    if switchHookInstalled then
        if switchHookMode=="hookfunction"
            and type(hookfunction)=="function"
            and type(switchTarget)=="function"
            and type(switchOriginal)=="function" then
            pcall(function() hookfunction(switchTarget,switchOriginal) end)
        elseif switchHookMode=="rawset"
            and type(switchOwner)=="table"
            and type(switchPrevious)=="function" then
            pcall(function() rawset(switchOwner,"SwitchToController",switchPrevious) end)
        end
    end

    if facadeInstalled and type(hookmetamethod)=="function" then
        if type(previousNamecall)=="function" then
            pcall(function() hookmetamethod(game,"__namecall",previousNamecall) end)
        end
        if type(previousIndex)=="function" then
            pcall(function() hookmetamethod(game,"__index",previousIndex) end)
        end
    end

    ENV.EvadePCIdentityV1=nil
    ENV.__EvadePCIdentityV1Cleanup=nil
end

return api
