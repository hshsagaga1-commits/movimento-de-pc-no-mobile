local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")

local player=Players.LocalPlayer
local BIND_NAME="__PCCameraTouchRightHalfGateV5"
local SPLIT=0.50

local oldCleanup=getgenv().__PCCameraTouchRightHalfGateV5Cleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local playerModule=nil
local cameras=nil
local activeController=nil
local installedHooks={}
local blockedTouches=setmetatable({}, {__mode="k"})
local rightTouches=setmetatable({}, {__mode="k"})
local leftBeginsBlocked=0
local leftChangesBlocked=0
local leftEndsBlocked=0
local rightBeginsPassed=0
local rightChangesPassed=0
local rightEndsPassed=0
local installErrors=0
local reinstallCount=0

local function viewportWidth()
    local camera=workspace.CurrentCamera
    return camera and camera.ViewportSize.X or 1108
end

local function isTouch(input)
    local t=nil
    pcall(function() t=input.UserInputType end)
    return t==Enum.UserInputType.Touch
end

local function inputX(input)
    local x=nil
    pcall(function() x=input.Position.X end)
    return x
end

local function onLeftHalf(input)
    local x=inputX(input)
    return type(x)=="number" and x<=viewportWidth()*SPLIT
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
        if type(tbl)~="table" or depth>14 or seen[tbl] then return nil end
        seen[tbl]=true
        local own=nil
        pcall(function() own=rawget(tbl,name) end)
        if type(own)=="function" then
            return {fn=own,owner=tbl,name=name}
        end
        local index=nil
        pcall(function() index=rawget(tbl,"__index") end)
        local found=nil
        if type(index)=="table" then
            found=visit(index,depth+1)
            if found then return found end
        end
        local mt=getMeta(tbl)
        if mt then
            found=visit(mt,depth+1)
            if found then return found end
        end
        return nil
    end
    return visit(root,0)
end

local function getCameras()
    if type(cameras)=="table" then return cameras end
    local scripts=player:FindFirstChild("PlayerScripts")
    local moduleScript=scripts and scripts:FindFirstChild("PlayerModule")
    if not moduleScript then return nil end
    if type(playerModule)~="table" then
        pcall(function() playerModule=require(moduleScript) end)
    end
    if type(playerModule)~="table" then return nil end
    pcall(function()
        if type(playerModule.GetCameras)=="function" then cameras=playerModule:GetCameras() end
        if type(cameras)~="table" then cameras=rawget(playerModule,"cameras") end
    end)
    return cameras
end

local function getActiveController()
    local module=getCameras()
    if type(module)~="table" then return nil end
    local controller=nil
    pcall(function() controller=rawget(module,"activeCameraController") end)
    if type(controller)~="table" and type(module.GetActiveCameraController)=="function" then
        pcall(function() controller=module:GetActiveCameraController() end)
    end
    return type(controller)=="table" and controller or nil
end

local function restoreHooks()
    for i=#installedHooks,1,-1 do
        local h=installedHooks[i]
        if h.mode=="hookfunction" and type(hookfunction)=="function" then
            pcall(function() hookfunction(h.target,h.original) end)
        elseif h.mode=="rawset" and type(h.owner)=="table" and type(h.original)=="function" then
            pcall(function() rawset(h.owner,h.name,h.original) end)
        end
    end
    table.clear(installedHooks)
end

local function installOne(target,replacementFactory)
    if not target or type(target.fn)~="function" then return false end

    if type(hookfunction)=="function" then
        local original=nil
        local replacement=replacementFactory(function(...)
            return original(...)
        end)
        local ok,old=pcall(function() return hookfunction(target.fn,replacement) end)
        if ok and type(old)=="function" then
            original=old
            installedHooks[#installedHooks+1]={mode="hookfunction",target=target.fn,original=old}
            return true
        end
    end

    local previous=nil
    pcall(function() previous=rawget(target.owner,target.name) end)
    if type(previous)=="function" then
        local replacement=replacementFactory(previous)
        local ok=pcall(function() rawset(target.owner,target.name,replacement) end)
        if ok then
            installedHooks[#installedHooks+1]={mode="rawset",owner=target.owner,name=target.name,original=previous}
            return true
        end
    end

    installErrors+=1
    return false
end

local function installForController(controller)
    restoreHooks()
    blockedTouches=setmetatable({}, {__mode="k"})
    rightTouches=setmetatable({}, {__mode="k"})
    if type(controller)~="table" then return false end

    local began=findMethod(controller,"OnInputBegan")
    local changed=findMethod(controller,"OnInputChanged")
    local ended=findMethod(controller,"OnInputEnded")

    local beganOk=installOne(began,function(callOriginal)
        return function(self,input,...)
            if self==getActiveController() and isTouch(input) then
                if onLeftHalf(input) then
                    blockedTouches[input]=true
                    rightTouches[input]=nil
                    leftBeginsBlocked+=1
                    return nil
                else
                    rightTouches[input]=true
                    blockedTouches[input]=nil
                    rightBeginsPassed+=1
                end
            end
            return callOriginal(self,input,...)
        end
    end)

    local changedOk=installOne(changed,function(callOriginal)
        return function(self,input,...)
            if self==getActiveController() and isTouch(input) then
                if blockedTouches[input] then
                    leftChangesBlocked+=1
                    return nil
                end

                -- Defensive fallback: if Changed arrives before Began was observed,
                -- classify from its current position. A left-half touch must never
                -- enter camera rotation.
                if rightTouches[input]~=true and onLeftHalf(input) then
                    blockedTouches[input]=true
                    leftChangesBlocked+=1
                    return nil
                end

                -- A camera touch that began on the right may temporarily cross the
                -- split. Freeze camera rotation while it is physically on the left,
                -- but keep its original Began/Ended lifecycle so BaseCamera can clean up.
                if rightTouches[input]==true and onLeftHalf(input) then
                    leftChangesBlocked+=1
                    return nil
                end

                rightChangesPassed+=1
            end
            return callOriginal(self,input,...)
        end
    end)

    local endedOk=installOne(ended,function(callOriginal)
        return function(self,input,...)
            if self==getActiveController() and isTouch(input) then
                if blockedTouches[input] then
                    blockedTouches[input]=nil
                    rightTouches[input]=nil
                    leftEndsBlocked+=1
                    return nil
                end
                if rightTouches[input] then
                    rightTouches[input]=nil
                    rightEndsPassed+=1
                    return callOriginal(self,input,...)
                end
            end
            return callOriginal(self,input,...)
        end
    end)

    reinstallCount+=1
    return beganOk and changedOk and endedOk
end

activeController=getActiveController()
if activeController then
    pcall(function() installForController(activeController) end)
end

RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Camera.Value-6,function()
    local controller=getActiveController()
    if controller~=activeController then
        activeController=controller
        pcall(function() installForController(activeController) end)
    end
end)

getgenv().PCCameraTouchRightHalfGateV5={
    Version="5.3-camera-touch-right-half-only",
    Split=SPLIT,
    GetState=function()
        return {
            installedHooks=#installedHooks,
            reinstallCount=reinstallCount,
            installErrors=installErrors,
            leftBeginsBlocked=leftBeginsBlocked,
            leftChangesBlocked=leftChangesBlocked,
            leftEndsBlocked=leftEndsBlocked,
            rightBeginsPassed=rightBeginsPassed,
            rightChangesPassed=rightChangesPassed,
            rightEndsPassed=rightEndsPassed,
        }
    end,
}

getgenv().__PCCameraTouchRightHalfGateV5Cleanup=function()
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    restoreHooks()
    blockedTouches=setmetatable({}, {__mode="k"})
    rightTouches=setmetatable({}, {__mode="k"})
    getgenv().PCCameraTouchRightHalfGateV5=nil
    getgenv().__PCCameraTouchRightHalfGateV5Cleanup=nil
end
