local Players=game:GetService("Players")
local Workspace=game:GetService("Workspace")
local UserInputService=game:GetService("UserInputService")

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")

-- Exact assets/crops used by Roblox's own fixed TouchThumbstick + TouchJump.
local THUMBSTICK_SHEET="rbxasset://textures/ui/TouchControlsSheet.png"
local JUMP_SHEET="rbxasset://textures/ui/Input/TouchControlsSheetV2.png"

local oldCleanup=getgenv().__PCRobloxNativeVisualV5Cleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end

local overlay=playerGui:FindFirstChild("PCKeyboardTouchBridgeV52Overlay")
if not overlay then
    overlay=playerGui:WaitForChild("PCKeyboardTouchBridgeV52Overlay",3)
end
if not overlay then error("PCKeyboardTouchBridgeV52Overlay missing") end

local joystick=overlay:FindFirstChild("PCJoystick",true)
local knob=joystick and joystick:FindFirstChild("Knob")
local jumpButton=overlay:FindFirstChild("PCJump",true)
if not joystick or not knob or not jumpButton then
    error("native visual targets missing")
end

-- Remember original properties once so cleanup is exact even after resize events.
local original=setmetatable({}, {__mode="k"})
local function setProp(instance,property,value)
    if not instance then return end
    local perInstance=original[instance]
    if not perInstance then
        perInstance={}
        original[instance]=perInstance
    end
    if perInstance[property]==nil then
        local ok,current=pcall(function() return instance[property] end)
        if ok then perInstance[property]={present=true,value=current} end
    end
    pcall(function() instance[property]=value end)
end

local created={}
local connections={}
local hiddenGuiStates=setmetatable({}, {__mode="k"})

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

-- Remove the temporary custom look without touching its input connections.
setProp(joystick,"AnchorPoint",Vector2.new(0,0))
setProp(joystick,"BackgroundTransparency",1)
setProp(joystick,"Text","")
local joystickStroke=joystick:FindFirstChildOfClass("UIStroke")
if joystickStroke then setProp(joystickStroke,"Transparency",1) end

setProp(knob,"AnchorPoint",Vector2.new(0.5,0.5))
setProp(knob,"BackgroundTransparency",1)
local knobStroke=knob:FindFirstChildOfClass("UIStroke")
if knobStroke then setProp(knobStroke,"Transparency",1) end

setProp(jumpButton,"AnchorPoint",Vector2.new(0,0))
setProp(jumpButton,"BackgroundTransparency",1)
setProp(jumpButton,"Text","")
local jumpStroke=jumpButton:FindFirstChildOfClass("UIStroke")
if jumpStroke then setProp(jumpStroke,"Transparency",1) end

-- Roblox fixed thumbstick outer ring: TouchControlsSheet.png [0,0,220,220].
local outerImage=Instance.new("ImageLabel")
outerImage.Name="RobloxThumbstickOuter"
outerImage.BackgroundTransparency=1
outerImage.Image=THUMBSTICK_SHEET
outerImage.ImageRectOffset=Vector2.new(0,0)
outerImage.ImageRectSize=Vector2.new(220,220)
outerImage.ImageTransparency=0
outerImage.Position=UDim2.fromOffset(0,0)
outerImage.ZIndex=joystick.ZIndex
outerImage.Active=false
outerImage.Parent=joystick
created[#created+1]=outerImage

-- Roblox fixed thumbstick inner stick: same sheet [220,0,111,111].
local stickImage=Instance.new("ImageLabel")
stickImage.Name="RobloxThumbstickStick"
stickImage.BackgroundTransparency=1
stickImage.Image=THUMBSTICK_SHEET
stickImage.ImageRectOffset=Vector2.new(220,0)
stickImage.ImageRectSize=Vector2.new(111,111)
stickImage.ImageTransparency=0
stickImage.Size=UDim2.fromScale(1,1)
stickImage.Position=UDim2.fromScale(0,0)
stickImage.ZIndex=knob.ZIndex
stickImage.Active=false
stickImage.Parent=knob
created[#created+1]=stickImage

-- Roblox jump button: TouchControlsSheetV2.png regular [1,146,144,144].
local jumpImage=Instance.new("ImageLabel")
jumpImage.Name="RobloxJumpButton"
jumpImage.BackgroundTransparency=1
jumpImage.Image=JUMP_SHEET
jumpImage.ImageRectOffset=Vector2.new(1,146)
jumpImage.ImageRectSize=Vector2.new(144,144)
jumpImage.ImageTransparency=0
jumpImage.Size=UDim2.fromScale(1,1)
jumpImage.Position=UDim2.fromOffset(0,0)
jumpImage.ZIndex=jumpButton.ZIndex
jumpImage.Active=false
jumpImage.Parent=jumpButton
created[#created+1]=jumpImage

local function viewportSize()
    local camera=Workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(896,414)
end

local function applyNativeLayout()
    local viewport=viewportSize()
    local minAxis=math.min(viewport.X,viewport.Y)
    local isSmallScreen=minAxis<=500

    -- Exact TouchThumbstick ResizeThumbstick sizing/placement from PlayerModule.
    local thumbstickSize=isSmallScreen and 70 or 120
    local thumbstickPosition=isSmallScreen
        and UDim2.new(0,(thumbstickSize/2)-10,1,-thumbstickSize-20)
        or UDim2.new(0,thumbstickSize/2,1,-thumbstickSize*1.75)

    setProp(joystick,"Size",UDim2.fromOffset(thumbstickSize,thumbstickSize))
    setProp(joystick,"Position",thumbstickPosition)
    outerImage.Size=UDim2.fromOffset(thumbstickSize,thumbstickSize)

    setProp(knob,"Size",UDim2.fromOffset(thumbstickSize/2,thumbstickSize/2))
    -- Keep the idle center identical to Roblox. The bridge will move this Frame
    -- from the same center while the finger is held.
    if getgenv().PCKeyboardTouchBridgeV52 then
        local state=nil
        pcall(function() state=getgenv().PCKeyboardTouchBridgeV52.GetState() end)
        if type(state)~="table" or state.movementTouchActive~=true then
            knob.Position=UDim2.fromOffset(thumbstickSize/2,thumbstickSize/2)
        end
    else
        knob.Position=UDim2.fromOffset(thumbstickSize/2,thumbstickSize/2)
    end

    -- Exact TouchJump ResizeJumpButton sizing/placement from PlayerModule.
    local jumpButtonSize=isSmallScreen and 70 or 120
    local jumpPosition=isSmallScreen
        and UDim2.new(1,-(jumpButtonSize*1.5-10),1,-jumpButtonSize-20)
        or UDim2.new(1,-(jumpButtonSize*1.5-10),1,-jumpButtonSize*1.75)

    setProp(jumpButton,"Size",UDim2.fromOffset(jumpButtonSize,jumpButtonSize))
    setProp(jumpButton,"Position",jumpPosition)
end

applyNativeLayout()

-- Match Roblox's pressed jump sprite.
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

local cameraViewportConnection=nil
local function bindCameraViewport()
    if cameraViewportConnection then
        pcall(function() cameraViewportConnection:Disconnect() end)
        cameraViewportConnection=nil
    end
    local camera=Workspace.CurrentCamera
    if camera then
        cameraViewportConnection=camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyNativeLayout)
    end
    applyNativeLayout()
end
bindCameraViewport()
connections[#connections+1]=Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewport)

getgenv().PCRobloxNativeVisualV5={
    Version="5.7-exact-roblox-touchthumbstick-touchjump",
    GetState=function()
        local viewport=viewportSize()
        local isSmallScreen=math.min(viewport.X,viewport.Y)<=500
        return {
            thumbstickSheet=THUMBSTICK_SHEET,
            jumpSheet=JUMP_SHEET,
            isSmallScreen=isSmallScreen,
            nativeSize=isSmallScreen and 70 or 120,
            debugHidden=true,
        }
    end,
}

getgenv().__PCRobloxNativeVisualV5Cleanup=function()
    if cameraViewportConnection then
        pcall(function() cameraViewportConnection:Disconnect() end)
        cameraViewportConnection=nil
    end
    for _,connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(connections)

    for _,instance in ipairs(created) do
        pcall(function() instance:Destroy() end)
    end
    table.clear(created)

    for instance,properties in pairs(original) do
        if instance and instance.Parent then
            for property,snapshot in pairs(properties) do
                if snapshot.present then
                    pcall(function() instance[property]=snapshot.value end)
                end
            end
        end
    end

    for gui,wasEnabled in pairs(hiddenGuiStates) do
        if gui and gui.Parent then
            pcall(function() gui.Enabled=wasEnabled end)
        end
    end

    getgenv().PCRobloxNativeVisualV5=nil
    getgenv().__PCRobloxNativeVisualV5Cleanup=nil
end
