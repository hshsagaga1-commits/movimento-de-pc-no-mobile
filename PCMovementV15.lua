local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local HttpService=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local player=Players.LocalPlayer

local src=game:HttpGet("https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovement.lua?_cb="..HttpService:GenerateGUID(false),true)
local fn,err=loadstring(src)
if not fn then error(err) end
fn()

local v9Cleanup=getgenv().__PCMobileAimCleanup
pcall(function() RunService:UnbindFromRenderStep("__PCMovementDigitalWASD") end)
getgenv().PCMovementVersion="V15"

local playerModule
local controls
local patched
local originalCalc
local camStats
local oldMouseEnabled
local hadMouseEnabled=false
local capturedMouse=false
local changingMouse=false
local connections={}

local function getControls()
    if controls then return controls end
    pcall(function()
        local ps=player:FindFirstChild("PlayerScripts")
        local pm=ps and ps:FindFirstChild("PlayerModule")
        if pm then
            playerModule=require(pm)
            if playerModule and type(playerModule.GetControls)=="function" then
                controls=playerModule:GetControls()
            end
        end
    end)
    return controls
end

local function touchPreferred()
    local value=false
    local ok=pcall(function() value=UIS.PreferredInput==Enum.PreferredInput.Touch end)
    if ok then return value end
    return UIS.TouchEnabled
end

local function digital(v)
    if typeof(v)~="Vector3" then return v end
    if math.sqrt(v.X*v.X+v.Z*v.Z)<=1e-4 then return Vector3.zero end
    local step=math.pi/4
    local a=math.floor((math.atan2(v.X,-v.Z)/step)+0.5)*step
    return Vector3.new(math.round(math.sin(a)),0,math.round(-math.cos(a)))
end

local function installMovement()
    local c=getControls()
    if not c or patched==c then return end
    if patched and originalCalc then pcall(function() patched.calculateRawMoveVector=originalCalc end) end
    if type(c.calculateRawMoveVector)~="function" then return end
    patched=c
    originalCalc=c.calculateRawMoveVector
    c.calculateRawMoveVector=function(self,humanoid,v)
        if getgenv().PCMovementEnabled~=false and getgenv().PCMovementDigitalInput~=false and touchPreferred() then
            v=digital(v)
        end
        return originalCalc(self,humanoid,v)
    end
end

local function setMouseIdentity()
    if getgenv().PCMovementEnabled==false then return end
    local ps=player:FindFirstChild("PlayerScripts")
    camStats=camStats or (ps and ps:FindFirstChild("CamStats"))
    if not camStats then return end
    if not capturedMouse then
        oldMouseEnabled=camStats:GetAttribute("MouseEnabled")
        hadMouseEnabled=oldMouseEnabled~=nil
        capturedMouse=true
    end
    changingMouse=true
    pcall(function() camStats:SetAttribute("MouseEnabled",true) end)
    changingMouse=false
end

installMovement()
setMouseIdentity()

RunService:BindToRenderStep("__PCMovementV15Watch",Enum.RenderPriority.Input.Value-2,function()
    installMovement()
    setMouseIdentity()
end)

task.spawn(function()
    local ps=player:WaitForChild("PlayerScripts",15)
    if not ps then return end
    camStats=ps:FindFirstChild("CamStats") or ps:WaitForChild("CamStats",10)
    if camStats then
        setMouseIdentity()
        table.insert(connections,camStats:GetAttributeChangedSignal("MouseEnabled"):Connect(function()
            if not changingMouse and getgenv().PCMovementEnabled~=false then task.defer(setMouseIdentity) end
        end))
    end
end)

getgenv().__PCMobileAimCleanup=function()
    pcall(function() RunService:UnbindFromRenderStep("__PCMovementV15Watch") end)
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if patched and originalCalc then pcall(function() patched.calculateRawMoveVector=originalCalc end) end
    if camStats and capturedMouse then
        changingMouse=true
        pcall(function()
            if hadMouseEnabled then camStats:SetAttribute("MouseEnabled",oldMouseEnabled) else camStats:SetAttribute("MouseEnabled",nil) end
        end)
        changingMouse=false
    end
    if v9Cleanup then pcall(v9Cleanup) end
    getgenv().__PCMobileAimCleanup=nil
end
