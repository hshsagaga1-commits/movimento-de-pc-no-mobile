local Players=game:GetService("Players")
local RunService=game:GetService("RunService")

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")

local BIND_NAME="__PCKeyboardControllerWakeV5"
local GUI_NAME="PCKeyboardControllerWakeV5Status"

local oldCleanup=getgenv().__PCKeyboardControllerWakeV5Cleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
local oldGui=playerGui:FindFirstChild(GUI_NAME)
if oldGui then oldGui:Destroy() end

local playerModule=nil
local controls=nil
local wakeAttempts=0
local updateCalls=0
local directEnableCalls=0
local wakeErrors=0
local lastStatus="starting"

pcall(function()
    local scripts=player:FindFirstChild("PlayerScripts")
    local moduleScript=scripts and scripts:FindFirstChild("PlayerModule")
    if moduleScript then playerModule=require(moduleScript) end
    if type(playerModule)=="table" then
        if type(playerModule.GetControls)=="function" then controls=playerModule:GetControls() end
        if type(controls)~="table" then controls=rawget(playerModule,"controls") end
    end
end)

local gui=Instance.new("ScreenGui")
gui.Name=GUI_NAME
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.DisplayOrder=10040
gui.Parent=playerGui

local label=Instance.new("TextLabel")
label.Name="WakeStatus"
label.BackgroundColor3=Color3.new(0,0,0)
label.BackgroundTransparency=0.28
label.TextColor3=Color3.new(1,1,1)
label.BorderSizePixel=0
label.Position=UDim2.fromOffset(8,34)
label.Size=UDim2.fromOffset(620,24)
label.Font=Enum.Font.Code
label.TextSize=12
label.TextXAlignment=Enum.TextXAlignment.Left
label.Text=" PC CTRL WAKE starting..."
label.Parent=gui

local function readEnabled(controller)
    if type(controller)~="table" then return nil end
    local value=nil
    pcall(function()
        value=rawget(controller,"enabled")
        if value==nil then value=rawget(controller,"Enabled") end
    end)
    return value
end

local function ensureEnabled()
    if type(controls)~="table" then
        lastStatus="controls-missing"
        return
    end

    local activeController=rawget(controls,"activeController")
    local activeModule=rawget(controls,"activeControlModule")
    local controlsEnabled=rawget(controls,"controlsEnabled")
    if type(activeController)~="table" or type(activeModule)~="table" then
        lastStatus="active-pc-controller-missing"
        return
    end

    local before=readEnabled(activeController)
    if before==true then
        lastStatus="already-enabled"
        return
    end

    wakeAttempts+=1

    -- First use Roblox's own ControlModule activation path. This is the least
    -- invasive correction and mirrors what SwitchToController is supposed to do.
    if controlsEnabled~=false and type(controls.UpdateActiveControlModuleEnabled)=="function" then
        local ok=pcall(function()
            controls:UpdateActiveControlModuleEnabled()
        end)
        if ok then updateCalls+=1 else wakeErrors+=1 end
    end

    local afterUpdate=readEnabled(activeController)
    if afterUpdate==true then
        lastStatus="enabled-by-controlmodule"
        return
    end

    -- If the selected keyboard controller is still asleep even though global
    -- controls are not disabled, wake that exact active controller. We do not
    -- touch Player:Move, Humanoid CFrame, WalkSpeed, camera, or Touch routing.
    if controlsEnabled~=false and type(activeController.Enable)=="function" then
        local ok=pcall(function()
            activeController:Enable(true)
        end)
        if ok then directEnableCalls+=1 else wakeErrors+=1 end
    end

    local final=readEnabled(activeController)
    if final==true then
        lastStatus="enabled-directly"
    elseif controlsEnabled==false then
        lastStatus="global-controls-disabled"
    else
        lastStatus="enable-failed"
    end
end

RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Input.Value-1,function()
    ensureEnabled()

    local controller=nil
    local global=nil
    local enabled=nil
    if type(controls)=="table" then
        controller=rawget(controls,"activeController")
        global=rawget(controls,"controlsEnabled")
        enabled=readEnabled(controller)
    end

    label.Text=string.format(
        " PC CTRL WAKE:%s  ctrlEn:%s global:%s attempts:%d CM:%d direct:%d err:%d",
        lastStatus,tostring(enabled),tostring(global),wakeAttempts,updateCalls,directEnableCalls,wakeErrors
    )
end)

getgenv().PCKeyboardControllerWakeV5={
    Version="5.5-enable-selected-keyboard-controller",
    GetState=function()
        local controller=type(controls)=="table" and rawget(controls,"activeController") or nil
        return {
            status=lastStatus,
            controllerEnabled=readEnabled(controller),
            controlsEnabled=type(controls)=="table" and rawget(controls,"controlsEnabled") or nil,
            wakeAttempts=wakeAttempts,
            updateCalls=updateCalls,
            directEnableCalls=directEnableCalls,
            errors=wakeErrors,
        }
    end,
}

getgenv().__PCKeyboardControllerWakeV5Cleanup=function()
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    pcall(function() gui:Destroy() end)
    getgenv().PCKeyboardControllerWakeV5=nil
    getgenv().__PCKeyboardControllerWakeV5Cleanup=nil
end
