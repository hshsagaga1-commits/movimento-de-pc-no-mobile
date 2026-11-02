-- Cursor appearance only. Never changes input capability, position or behavior.
local UserInputService=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local Players=game:GetService("Players")
local env=getgenv()
local BIND="__PCCursorVisualV31"
local previousCleanup=env.__PCCursorVisualV31Cleanup
if type(previousCleanup)=="function" then previousCleanup() end

local previous=UserInputService.MouseIconEnabled
assert(type(previous)=="boolean","MouseIconEnabled unavailable")
local running,hidden=true,true
local connections={}
local resets=0
local lastError=nil
local function enforce()
    if not running or not hidden then return end
    local ok,message=pcall(function()
        if UserInputService.MouseIconEnabled then
            UserInputService.MouseIconEnabled=false
            resets+=1
        end
    end)
    if not ok then lastError=tostring(message) end
end
local function restore()
    if UserInputService.MouseIconEnabled==false then UserInputService.MouseIconEnabled=previous end
end
local api={}
function api.SetEnabled(value)
    if not running then return false,"stopped" end
    hidden=value~=false
    if hidden then enforce() else pcall(restore) end
    return hidden
end
function api.GetState()
    return {enabled=running and hidden,visualOnly=true,mouseIconEnabled=UserInputService.MouseIconEnabled,
        hiddenResets=resets,lastError=lastError}
end
local cleanup
cleanup=function()
    if not running then return end
    running=false
    for _,connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
    pcall(function() RunService:UnbindFromRenderStep(BIND) end)
    pcall(restore)
    if env.PCCursorVisualV31==api then env.PCCursorVisualV31=nil end
    if env.__PCCursorVisualV31Cleanup==cleanup then env.__PCCursorVisualV31Cleanup=nil end
end
api.Stop=cleanup
local ok,message=pcall(function()
    connections[#connections+1]=UserInputService:GetPropertyChangedSignal("MouseIconEnabled"):Connect(enforce)
    connections[#connections+1]=Players.LocalPlayer.CharacterAdded:Connect(enforce)
    RunService:BindToRenderStep(BIND,Enum.RenderPriority.Last.Value+1,enforce)
    enforce()
end)
if not ok then cleanup() error(message) end
env.PCCursorVisualV31=api
env.__PCCursorVisualV31Cleanup=cleanup
return api
