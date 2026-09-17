local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local env=getgenv()

local oldCleanup=env.__PCCrouchToggleV59Cleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end

local enabled=true
local button=nil
local pressScale=nil
local buttonConnections={}
local globalConnections={}
local originalScale=1

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

local function clearButton()
    for _,c in ipairs(buttonConnections) do pcall(function() c:Disconnect() end) end
    table.clear(buttonConnections)

    if pressScale and pressScale.Parent then
        pcall(function() pressScale.Scale=originalScale end)
        pcall(function() pressScale:Destroy() end)
    end

    pressScale=nil
    button=nil
    originalScale=1
end

local function setPressedVisual(isPressed)
    if not pressScale or not pressScale.Parent then return end
    pressScale.Scale=isPressed and (originalScale*0.92) or originalScale
end

local function bindNativeButton(native)
    if not enabled or not native or native==button then return end
    clearButton()

    button=native

    -- Do NOT clone, hide, replace, or fire crouch ourselves. The Evade mobile
    -- button keeps its own toggle behavior exactly as shipped by the game.
    pressScale=Instance.new("UIScale")
    pressScale.Name="PCCrouchPressVisualV59"
    pressScale.Scale=1
    pressScale.Parent=native
    originalScale=1

    buttonConnections[#buttonConnections+1]=native.InputBegan:Connect(function(input)
        if input.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
        setPressedVisual(true)
    end)

    buttonConnections[#buttonConnections+1]=native.InputEnded:Connect(function(input)
        if input.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
        setPressedVisual(false)
    end)

    buttonConnections[#buttonConnections+1]=native.AncestryChanged:Connect(function(_,parent)
        if not parent then
            clearButton()
        end
    end)
end

task.spawn(function()
    while enabled do
        local native=findNativeCrouch()
        if native and native~=button then
            bindNativeButton(native)
        elseif button and not button.Parent then
            clearButton()
        end
        task.wait(0.5)
    end
end)

globalConnections[#globalConnections+1]=UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        setPressedVisual(false)
    end
end)

env.PCCrouchToggleV59={
    Version="5.9-native-mobile-toggle-pc-press-visual",
    UsesNativeBehavior=true,
}

env.__PCCrouchToggleV59Cleanup=function()
    enabled=false
    clearButton()
    for _,c in ipairs(globalConnections) do pcall(function() c:Disconnect() end) end
    table.clear(globalConnections)
    env.PCCrouchToggleV59=nil
    env.__PCCrouchToggleV59Cleanup=nil
end
