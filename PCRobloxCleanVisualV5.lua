local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local TOUCH_SHEET="rbxasset://textures/ui/Input/TouchControlsSheetV2.png"

local oldCleanup=getgenv().__PCRobloxCleanVisualV5Cleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end

local created={}
local connections={}
local hiddenGuiStates={}

local function remember(instance,property)
    return {instance=instance,property=property,value=instance[property]}
end

local changed={}
local function set(instance,property,value)
    if not instance then return end
    changed[#changed+1]=remember(instance,property)
    instance[property]=value
end

local function hideDebugGui(name)
    local gui=playerGui:FindFirstChild(name)
    if gui and gui:IsA("ScreenGui") then
        hiddenGuiStates[gui]=gui.Enabled
        gui.Enabled=false
    end
end

for _,name in ipairs({
    "PCModeLockV5Status",
    "PCKeyboardControllerWakeV5Status",
    "PCInputRouteProbeV54",
}) do
    hideDebugGui(name)
end

local overlay=playerGui:FindFirstChild("PCKeyboardTouchBridgeV52Overlay")
if not overlay then
    overlay=playerGui:WaitForChild("PCKeyboardTouchBridgeV52Overlay",3)
end
if not overlay then
    error("PCKeyboardTouchBridgeV52Overlay missing")
end

local joystick=overlay:FindFirstChild("PCJoystick",true)
local knob=joystick and joystick:FindFirstChild("Knob")
local jumpButton=overlay:FindFirstChild("PCJump",true)

if not joystick or not knob or not jumpButton then
    error("PC clean visual targets missing")
end

-- Keep all existing input behavior. This file changes appearance only.
set(joystick,"BackgroundTransparency",1)
set(joystick,"Size",UDim2.fromOffset(122,122))
set(joystick,"Position",UDim2.new(0,36,1,-30))

local joystickStroke=joystick:FindFirstChildOfClass("UIStroke")
if joystickStroke then
    set(joystickStroke,"Transparency",1)
end

local baseImage=Instance.new("ImageLabel")
baseImage.Name="RobloxNativeBase"
baseImage.BackgroundTransparency=1
baseImage.Image=TOUCH_SHEET
baseImage.ImageRectOffset=Vector2.new(1,1)
baseImage.ImageRectSize=Vector2.new(144,144)
baseImage.ImageTransparency=0.34
baseImage.Size=UDim2.fromScale(1,1)
baseImage.Position=UDim2.fromScale(0,0)
baseImage.ZIndex=joystick.ZIndex
baseImage.Active=false
baseImage.Parent=joystick
created[#created+1]=baseImage

set(knob,"BackgroundTransparency",1)
set(knob,"Size",UDim2.fromOffset(54,54))

local knobImage=Instance.new("ImageLabel")
knobImage.Name="RobloxNativeKnob"
knobImage.BackgroundTransparency=1
knobImage.Image=TOUCH_SHEET
knobImage.ImageRectOffset=Vector2.new(1,1)
knobImage.ImageRectSize=Vector2.new(144,144)
knobImage.ImageTransparency=0.08
knobImage.Size=UDim2.fromScale(1,1)
knobImage.Position=UDim2.fromScale(0,0)
knobImage.ZIndex=knob.ZIndex
knobImage.Active=false
knobImage.Parent=knob
created[#created+1]=knobImage

local knobStroke=knob:FindFirstChildOfClass("UIStroke")
if knobStroke then
    set(knobStroke,"Transparency",1)
end

-- Use Roblox's own touch jump sprite instead of the temporary text arrow.
set(jumpButton,"Text","")
set(jumpButton,"BackgroundTransparency",1)
set(jumpButton,"Size",UDim2.fromOffset(86,86))
set(jumpButton,"Position",UDim2.new(1,-52,1,-122))

local jumpStroke=jumpButton:FindFirstChildOfClass("UIStroke")
if jumpStroke then
    set(jumpStroke,"Transparency",1)
end

local jumpImage=Instance.new("ImageLabel")
jumpImage.Name="RobloxNativeJump"
jumpImage.BackgroundTransparency=1
jumpImage.Image=TOUCH_SHEET
jumpImage.ImageRectOffset=Vector2.new(1,146)
jumpImage.ImageRectSize=Vector2.new(144,144)
jumpImage.ImageTransparency=0.05
jumpImage.Size=UDim2.fromScale(1,1)
jumpImage.Position=UDim2.fromScale(0,0)
jumpImage.ZIndex=jumpButton.ZIndex
jumpImage.Active=false
jumpImage.Parent=jumpButton
created[#created+1]=jumpImage

connections[#connections+1]=jumpButton.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch then
        jumpImage.ImageRectOffset=Vector2.new(146,146)
    end
end)
connections[#connections+1]=jumpButton.InputEnded:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch then
        jumpImage.ImageRectOffset=Vector2.new(1,146)
    end
end)

getgenv().PCRobloxCleanVisualV5={
    Version="5.6-roblox-clean-hidden-debug",
    GetState=function()
        return {
            joystickStyled=joystick.Parent~=nil,
            jumpStyled=jumpButton.Parent~=nil,
            debugHidden=true,
            touchSheet=TOUCH_SHEET,
        }
    end,
}

getgenv().__PCRobloxCleanVisualV5Cleanup=function()
    for _,connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(connections)

    for _,instance in ipairs(created) do
        pcall(function() instance:Destroy() end)
    end
    table.clear(created)

    for index=#changed,1,-1 do
        local item=changed[index]
        if item.instance then
            pcall(function() item.instance[item.property]=item.value end)
        end
    end
    table.clear(changed)

    for gui,wasEnabled in pairs(hiddenGuiStates) do
        if gui and gui.Parent then
            pcall(function() gui.Enabled=wasEnabled end)
        end
    end

    getgenv().PCRobloxCleanVisualV5=nil
    getgenv().__PCRobloxCleanVisualV5Cleanup=nil
end
