-- Independent facing ONLY. Zero grid queries, velocity writes or camera changes.
-- Snapshots camera heading ONCE at joystick touch start and keeps it fixed.
return function()
    local Players=game:GetService("Players")
    local RunService=game:GetService("RunService")
    local Workspace=game:GetService("Workspace")
    local player=Players.LocalPlayer
    local env=getgenv()
    local BIND_NAME="__PCMovementIndependentFacingV322"
    local CLEANUP="__PCMovementIndependentFacingV322Cleanup"
    local previous=env[CLEANUP]
    if type(previous)=="function" then pcall(previous) end
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

    local active=true
    local enabled=true
    local touchActive=false
    local anchorForward,anchorRight=nil,nil
    local anchorYaw=nil
    local trackedHumanoid,tracedRoot=nil,nil
    local autoRotateOriginal=nil
    local autoRotateOwned=false
    local frames,writes,skipped=0,0,0
    local function flatUnit(v)
        local a=Vector3.new(v.X,0,v.Z)
        return a.Magnitude>1e-5 and a.Unit or Vector3.zero
    end
    local function restoreAutoRotate()
        if autoRotateOwned and trackedHumanoid and trackedHumanoid.Parent
            and trackedHumanoid.AutoRotate==false then
            pcall(function() trackedHumanoid.AutoRotate=autoRotateOriginal end)
        end
        autoRotateOwned=false
        autoRotateOriginal=nil
    end
    local function reset()
        restoreAutoRotate()
        touchActive=false
        anchorForward,anchorRight=nil,nil
        anchorYaw=nil
    end
    local function characterParts()
        local character=player.Character
        if not character then return nil,nil end
        return character:FindFirstChildOfClass("Humanoid"),character:FindFirstChild("HumanoidRootPart")
    end
    local function captureAnchor(root)
        local camera=Workspace.CurrentCamera
        local forward=flatUnit(camera and camera.CFrame.LookVector or root.CFrame.LookVector)
        if forward.Magnitude<0.5 then forward=flatUnit(root.CFrame.LookVector) end
        if forward.Magnitude<0.5 then return false end
        anchorForward=forward
        anchorRight=Vector3.new(-forward.Z,0,forward.X)
        anchorYaw=math.deg(math.atan2(-forward.X,-forward.Z))
        return true
    end
    local function beginTouch(humanoid,root)
        touchActive=true
        captureAnchor(root)
        -- Native AutoRotate otherwise competes with manual facing on mobile.
        autoRotateOriginal=humanoid.AutoRotate
        if autoRotateOriginal then
            local ok=pcall(function() humanoid.AutoRotate=false end)
            autoRotateOwned=ok and humanoid.AutoRotate==false
        else
            autoRotateOwned=false
        end
    end
    local function stepFacing(dt)
        if not active then return end
        frames+=1
        local humanoid,root=characterParts()
        if humanoid~=trackedHumanoid or root~=tracedRoot then
            reset()
            trackedHumanoid,tracedRoot=humanoid,root
        end
        if not humanoid or not root or humanoid.Health<=0 or humanoid.Sit
            or humanoid.PlatformStand or root.Anchored then
            if touchActive then reset() end
            return
        end
        local bridge=env.PCKeyboardTouchBridgeV52
        if type(bridge)~="table" or type(bridge.ReadMovement)~="function" then
            if touchActive then reset() end
            return
        end
        local chord,x,z,_,_,isTouching=bridge.ReadMovement()
        if not enabled or not isTouching then
            if touchActive then reset() end
            return
        end
        if not touchActive then beginTouch(humanoid,root) end
        if not anchorForward or not anchorRight then
            if not captureAnchor(root) then return end
        end
        if type(x)~="number" or type(z)~="number"
            or chord=="-" or x*x+z*z<0.30*0.30 then
            skipped+=1
            return
        end
        -- Joystick right is always 90 degrees right of the captured heading,
        -- regardless of later camera movement. WASD chords are untouched.
        local desired=flatUnit(anchorRight*x-anchorForward*z)
        if desired.Magnitude<0.5 then return end
        local current=flatUnit(root.CFrame.LookVector)
        local dot=current.Magnitude>0 and current:Dot(desired) or 1
        if dot>0.999 then return end
        local response=dot<-0.55 and 0.038 or 0.048
        local alpha=1-math.exp(-math.clamp(dt or 1/60,1/240,0.05)/response)
        local target=CFrame.lookAt(root.Position,root.Position+desired)
        local ok=pcall(function()
            root.CFrame=root.CFrame:Lerp(target,alpha)
        end)
        if ok then writes+=1 end
    end
    RunService:BindToRenderStep(BIND_NAME,Enum.RenderPriority.Character.Value+1,stepFacing)
    local api={
        Version="3.2.2-independent-facing-only",
        SetEnabled=function(value)
            enabled=value==true
            if not enabled then reset() end
            return enabled
        end,
        GetState=function()
            return {enabled=enabled,touchActive=touchActive,anchorYaw=anchorYaw,
                autoRotateOwned=autoRotateOwned,frames=frames,writes=writes,
                skipped=skipped,gridQueries=0,velocityWrites=0,
                mode="joystick-fixed-camera-snapshot"}
        end
    }
    env.PCMovementIndependentFacingV322=api
    local cleanup
    cleanup=function()
        if not active then return end
        active=false
        RunService:UnbindFromRenderStep(BIND_NAME)
        reset()
        if env[CLEANUP]==cleanup then env[CLEANUP]=nil end
        if env.PCMovementIndependentFacingV322==api then
            env.PCMovementIndependentFacingV322=nil
        end
    end
    env[CLEANUP]=cleanup
end
