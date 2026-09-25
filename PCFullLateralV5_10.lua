local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")

local player=Players.LocalPlayer
local BIND_NAME="__PCFullLateralV510Watch"

local oldCleanup=getgenv().__PCFullLateralV510Cleanup
if type(oldCleanup)=="function" then pcall(oldCleanup) end
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local playerModule=nil
local controls=nil
local patchedControls=nil
local originalCalc=nil
local wrapper=nil
local patches=0
local lateralFrames=0
local fallbackFrames=0

local function getControls()
    if type(controls)=="table" then return controls end
    local ps=player:FindFirstChild("PlayerScripts")
    local pm=ps and ps:FindFirstChild("PlayerModule")
    if not pm then return nil end
    local ok,module=pcall(require,pm)
    if not ok or type(module)~="table" then return nil end
    playerModule=module
    local value=nil
    pcall(function()
        if type(module.GetControls)=="function" then value=module:GetControls() end
        if type(value)~="table" then value=rawget(module,"controls") end
    end)
    if type(value)=="table" then controls=value end
    return controls
end

local function bridgeActive()
    return type(getgenv().PCKeyboardTouchBridgeV52)=="table"
        and getgenv().PCFullLateralV510Enabled~=false
end

local function normalGroundState(humanoid)
    if not humanoid then return true end
    local state=nil
    pcall(function() state=humanoid:GetState() end)
    return state~=Enum.HumanoidStateType.Swimming
end

local function exactCameraRelativeDigital(v)
    local camera=Workspace.CurrentCamera
    if not camera then return nil end

    local right3=camera.CFrame.RightVector
    local look3=camera.CFrame.LookVector
    local right=Vector3.new(right3.X,0,right3.Z)
    local forward=Vector3.new(look3.X,0,look3.Z)
    if right.Magnitude<=1e-5 or forward.Magnitude<=1e-5 then return nil end
    right=right.Unit
    forward=forward.Unit

    local x=0
    if v.X>=0.5 then x=1 elseif v.X<=-0.5 then x=-1 end

    local z=0
    if v.Z>=0.5 then z=1 elseif v.Z<=-0.5 then z=-1 end

    if x==0 then return nil end

    -- Keyboard convention: W is Z=-1, so -z maps W onto camera forward.
    local world=right*x + forward*(-z)
    if world.Magnitude<=1e-5 then return nil end

    -- Pure A/D is exactly full camera-left/right. W+A / W+D (and rear
    -- diagonals) are normalized back to magnitude 1, matching a full digital
    -- keyboard vector instead of allowing camera pitch/yaw to attenuate it.
    return world.Unit
end

local function restore()
    if type(patchedControls)=="table" and type(originalCalc)=="function" then
        pcall(function()
            if rawget(patchedControls,"calculateRawMoveVector")==wrapper then
                patchedControls.calculateRawMoveVector=originalCalc
            end
        end)
    end
    patchedControls=nil
    originalCalc=nil
    wrapper=nil
end

local function install()
    local c=getControls()
    if type(c)~="table" then return false end

    local current=rawget(c,"calculateRawMoveVector")
    if type(current)~="function" then
        current=c.calculateRawMoveVector
    end
    if c==patchedControls and current==wrapper then return true end
    if type(current)~="function" then return false end

    restore()
    patchedControls=c
    originalCalc=current

    local thisWrapper
    thisWrapper=function(self,humanoid,v)
        if self==c and bridgeActive() and typeof(v)=="Vector3"
            and math.abs(v.X)>=0.5 and normalGroundState(humanoid) then
            local exact=exactCameraRelativeDigital(v)
            if exact then
                lateralFrames+=1
                return exact
            end
        end
        fallbackFrames+=1
        return originalCalc(self,humanoid,v)
    end
    wrapper=thisWrapper
    c.calculateRawMoveVector=thisWrapper
    patches+=1
    return true
end

install()

RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Input.Value-2,function()
    local c=getControls()
    if c~=patchedControls or (c and rawget(c,"calculateRawMoveVector")~=wrapper) then
        install()
    end
end)

getgenv().PCFullLateralV510={
    Version="5.10-full-camera-relative-lateral",
    GetState=function()
        return {
            enabled=getgenv().PCFullLateralV510Enabled~=false,
            patched=patchedControls~=nil,
            patches=patches,
            lateralFrames=lateralFrames,
            fallbackFrames=fallbackFrames,
            writesPlayerMove=false,
            writesRootCFrame=false,
            writesCameraCFrame=false,
        }
    end,
}

getgenv().__PCFullLateralV510Cleanup=function()
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    restore()
    getgenv().PCFullLateralV510=nil
    getgenv().__PCFullLateralV510Cleanup=nil
end
