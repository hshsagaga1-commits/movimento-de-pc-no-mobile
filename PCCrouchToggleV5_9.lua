local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local env=getgenv()

local oldCleanup=env.__PCCrouchToggleV59Cleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end

local enabled=true
local crouched=false
local pressed=false
local originalButton=nil
local cloneButton=nil
local pressScale=nil
local buttonConnections={}
local globalConnections={}

local function fireCrouch(down)
    local scripts=player:FindFirstChild("PlayerScripts")
    local events=scripts and scripts:FindFirstChild("Events")
    local keybind=events and events:FindFirstChild("KeybindUsed")
    if not keybind then return false end
    return pcall(function()
        keybind:Fire("Crouch",down)
    end)
end

local function setPressedVisual(isPressed)
    if not cloneButton then return end
    if not pressScale or not pressScale.Parent then
        pressScale=cloneButton:FindFirstChild("PCCrouchPressScale")
        if not pressScale then
            pressScale=Instance.new("UIScale")
            pressScale.Name="PCCrouchPressScale"
            pressScale.Scale=1
            pressScale.Parent=cloneButton
        end
    end
    pressScale.Scale=isPressed and 0.92 or 1
end

local function findNativeCrouch()
    local hud=playerGui:FindFirstChild("HUD")
    local right=hud and hud:FindFirstChild("Right")
    local mobile=right and right:FindFirstChild("Mobile")
    local crouch=mobile and mobile:FindFirstChild("Crouch")
    if crouch and crouch:IsA("GuiObject") then return crouch end
    for _,obj in ipairs(playerGui:GetDescendants()) do
        if obj.Name=="Crouch" and obj:IsA("GuiObject") then
            return obj
        end
    end
    return nil
end

local function disconnectButton()
    for _,c in ipairs(buttonConnections) do pcall(function() c:Disconnect() end) end
    table.clear(buttonConnections)
    if cloneButton then pcall(function() cloneButton:Destroy() end) end
    cloneButton=nil
    pressScale=nil
    if originalButton and originalButton.Parent then
        pcall(function() originalButton.Visible=true end)
    end
    originalButton=nil
end

local function bindButton(button)
    if not enabled or not button or button==originalButton then return end
    disconnectButton()
    originalButton=button

    local clone=button:Clone()
    clone.Name="PCCrouchToggleButton"
    clone.Visible=true
    clone.Active=true
    clone.ZIndex=math.max(button.ZIndex+1,50)
    for _,desc in ipairs(clone:GetDescendants()) do
        if desc:IsA("LocalScript") or desc:IsA("Script") then desc:Destroy() end
        if desc:IsA("GuiObject") then desc.ZIndex=math.max(desc.ZIndex,clone.ZIndex) end
    end
    if clone:IsA("GuiButton") then clone.AutoButtonColor=false end
    clone.Parent=button.Parent
    cloneButton=clone
    button.Visible=false

    buttonConnections[#buttonConnections+1]=clone.InputBegan:Connect(function(input)
        if not enabled or pressed then return end
        if input.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
        pressed=true
        setPressedVisual(true)
        crouched=not crouched
        fireCrouch(crouched)
    end)

    buttonConnections[#buttonConnections+1]=clone.InputEnded:Connect(function(input)
        if input.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
        pressed=false
        setPressedVisual(false)
    end)

    buttonConnections[#buttonConnections+1]=clone.AncestryChanged:Connect(function(_,parent)
        if not parent then
            cloneButton=nil
            pressScale=nil
        end
    end)
end

task.spawn(function()
    while enabled do
        local native=findNativeCrouch()
        if native and native~=originalButton then
            bindButton(native)
        elseif originalButton and not originalButton.Parent then
            disconnectButton()
        end
        task.wait(0.5)
    end
end)

globalConnections[#globalConnections+1]=player.CharacterAdded:Connect(function()
    crouched=false
    pressed=false
    setPressedVisual(false)
    task.defer(function() fireCrouch(false) end)
end)

env.PCCrouchToggleV59={
    Version="5.9-pc-key-state-mobile-toggle",
    IsCrouched=function() return crouched end,
    IsPressed=function() return pressed end,
}

env.__PCCrouchToggleV59Cleanup=function()
    enabled=false
    pressed=false
    if crouched then pcall(function() fireCrouch(false) end) end
    crouched=false
    disconnectButton()
    for _,c in ipairs(globalConnections) do pcall(function() c:Disconnect() end) end
    table.clear(globalConnections)
    env.PCCrouchToggleV59=nil
    env.__PCCrouchToggleV59Cleanup=nil
end
