local Runtime={}
local BIND="__PCMovementRebuild"
local GUI="PCKeyboardTouchBridgeV52Overlay"
local CROUCH={"Crouching","Crouched","IsCrouching","IsCrouched"}
local EMOTE={"IsEmoting","Emoting","EmotePlaying","PlayingEmote","DoingEmote"}

local function defaultServices()
    local services={GameId=game.GameId}
    for _,name in ipairs({"Players","RunService","UserInputService","VirtualInputManager",
        "Workspace","CollectionService","PhysicsService","HttpService","GuiService"}) do
        services[name]=game:GetService(name)
    end
    services.player=services.Players.LocalPlayer
    services.playerGui=services.player:WaitForChild("PlayerGui")
    return services
end
local function disconnect(list)
    for _,connection in ipairs(list) do pcall(function() connection:Disconnect() end) end
end
local function enumName(value)
    local ok,name=pcall(function() return value.Name end)
    return ok and name or tostring(value)
end

function Runtime.Start(modules,config,services,env)
    config=config or {}
    services=services or defaultServices()
    env=env or getgenv()
    if config.OnlyEvade~=false and services.GameId~=3647333358 then
        error("[PC Movement Rebuild] This configuration targets Evade. No controls were changed.")
    end
    local player,pg=services.player,services.playerGui
    local run,uis=services.RunService,services.UserInputService
    local now=services.Clock or os.clock
    local prior=env.PCMovementRebuild
    if type(prior)=="table" and type(prior.Stop)=="function" then prior.Stop(true) end

    -- Snapshot presentation before a legacy composite Stop destroys its overlay.
    local oldGui=pg:FindFirstChild(GUI)
    local migrated
    if oldGui and oldGui:GetAttribute("PCMovementRebuild")~=true then
        pcall(function() migrated=oldGui:Clone() end)
    end

    -- Cancel old recovery watchers before removing any overlay. Do not load them.
    for _,version in ipairs({"V2","V3","V31"}) do
        env["__PCMovementAssist"..version.."Token"]=nil
        local old=env["PCMovementAssist"..version]
        if type(old)=="table" and type(old.Stop)=="function" then pcall(old.Stop) end
    end
    local cleanupErrors={}
    for _,name in ipairs({"__LegacyGridContactAssistV1Cleanup","__PCModeLockCleanup",
        "__PCKeyboardTouchBridgeV52Cleanup","__PCKeyboardTouchBridgeV5Cleanup",
        "__PCIndependentJoystickCleanup","__PCSelectiveWASDCleanup","__PCClassicNativeKeysV3Cleanup",
        "__PCClassicNativeKeysCleanup","__PCClassicWASDCleanup","__PCCrouchToggleV59Cleanup",
        "__PCCameraTouchRightHalfGateV5Cleanup","__PCKeyboardControllerWakeV5Cleanup",
        "__PCRobloxNativeVisualV5Cleanup","__PCRobloxCleanVisualV5Cleanup"}) do
        if type(env[name])=="function" then
            local ok,message=pcall(env[name])
            if not ok then cleanupErrors[#cleanupErrors+1]=name..": "..tostring(message) end
        end
    end
    env.LegacyGridContactAssistV1=nil -- V3.1's cleanup had a mismatched version guard.
    for _,name in ipairs({"__LegacyGridContactAssistV1","__PCKeyboardTouchBridgeV52",
        "__PCModeLockV5Watch","__PCCameraTouchRightHalfGateV5","__PCKeyboardControllerWakeV5",BIND}) do
        pcall(function() run:UnbindFromRenderStep(name) end)
    end
    if migrated then
        if not pg:FindFirstChild(GUI) then migrated.Parent=pg else migrated:Destroy() end
    end

    local Core=modules.Core
    local policy=Core.new(config)
    local jump=Core.jump(config)
    local log=Core.log(180)
    log.enabled=config.Diagnostics==true
    local presentation=modules.Controls.new(services)
    local route=modules.KeyboardRoute.new(services,env)
    local grid=modules.GridSensor.new(services,config)
    local connections,charConnections={},{}
    local running,enabled,focused=true,true,true
    local movementTouch,movementCenter,movementRadius=nil,nil,46
    local jumpTouches,controlTouches={},{}
    local analogX,analogZ=0,0
    local character,humanoid,root
    local valueObjects,tracks={},{}
    local currentAnimator,animatorConnection
    local standIndicator
    local lastMaintenance,lastIndicator,lastLog=-math.huge,-math.huge,-math.huge
    local lastResult,lastObservation,lastChord=nil,nil,"-"
    local lastSpeed,lastSpeedTime=nil,nil
    local layoutSaved={}
    local provider=config.StateProvider
    local ticks,maxTickMS,changes=0,0,0
    local senderFailures=0
    local routeGeneration=-1
    local replayPending=false
    local ledger=Core.keys(function(key,down)
        local ok=pcall(function()
            services.VirtualInputManager:SendKeyEvent(down,Enum.KeyCode[key],false,game)
        end)
        if not ok then senderFailures=senderFailures+1 end
        return ok
    end)
    -- A failed Stop release is retained for the next start; no delayed old task
    -- is allowed to release keys belonging to a newer runtime.
    if type(env.__PCMovementPendingRelease)=="table" then
        for key,held in pairs(env.__PCMovementPendingRelease) do
            if held then ledger.pressed[key]=true end
        end
        ledger:apply({})
        env.__PCMovementPendingRelease=nil
    end
    local function connect(signal,fn,list)
        if signal then
            local connection=signal:Connect(fn)
            local target=list or connections
            target[#target+1]=connection
            return connection
        end
    end
    local function event(kind,details)
        if not log.enabled then return end
        details=details or {}
        details.kind,details.time=kind,now()
        log:add(details)
    end
    local function clearInput()
        movementTouch,movementCenter=nil,nil
        analogX,analogZ=0,0
        jumpTouches,controlTouches={},{}
        jump:cancel()
        policy.engaged=false
        presentation:ResetKnob()
        presentation:SetJumpPressed(false)
        ledger:apply({})
    end
    local function releaseTouch(input,cancelled)
        controlTouches[input]=nil
        if input==movementTouch then
            movementTouch,movementCenter=nil,nil
            analogX,analogZ=0,0
            policy.engaged=false
            presentation:ResetKnob()
        end
        if jumpTouches[input] then
            jumpTouches[input]=nil
            local held=next(jumpTouches)~=nil
            jump:setHeld(held,now())
            if cancelled and not held then jump:cancel() end
            presentation:SetJumpPressed(held)
        end
    end
    local function cacheValue(object)
        if object:IsA("BoolValue") then
            for _,names in ipairs({CROUCH,EMOTE}) do
                for _,name in ipairs(names) do
                    if object.Name==name then valueObjects[name]=object end
                end
            end
        end
    end
    local allowedAnimations={}
    for key,value in pairs(config.EmoteAnimationIds or {}) do
        local id=type(value)=="boolean" and key or value
        allowedAnimations[tostring(id):match("%d+$") or tostring(id)]=true
    end
    local function attachAnimator()
        local animator=humanoid and humanoid:FindFirstChildOfClass("Animator")
        if animator==currentAnimator then return end
        if animatorConnection then animatorConnection:Disconnect() end
        currentAnimator=animator
        tracks={}
        if animator then
            local ok,list=pcall(function() return animator:GetPlayingAnimationTracks() end)
            if ok then for _,track in ipairs(list) do tracks[track]=true end end
            animatorConnection=connect(animator.AnimationPlayed,function(track) tracks[track]=true end,charConnections)
        end
    end
    local function bindCharacter(char)
        clearInput()
        disconnect(charConnections);charConnections={}
        currentAnimator,animatorConnection=nil,nil
        character=char
        humanoid=char and char:FindFirstChildOfClass("Humanoid") or nil
        root=char and char:FindFirstChild("HumanoidRootPart") or nil
        valueObjects,tracks={},{}
        if char then
            for _,object in ipairs(char:GetDescendants()) do cacheValue(object) end
            connect(char.DescendantAdded,function(object)
                cacheValue(object)
                if object.Name=="HumanoidRootPart" or object:IsA("Humanoid")
                    or (object:IsA("BasePart") and object.Parent==char) then
                    humanoid=char:FindFirstChildOfClass("Humanoid")
                    root=char:FindFirstChild("HumanoidRootPart")
                    grid:Bind(char,humanoid,root)
                end
                if object:IsA("Animator") or object:IsA("Humanoid") then attachAnimator() end
            end,charConnections)
        end
        attachAnimator()
        grid:Bind(char,humanoid,root)
        policy=Core.new(config)
        lastSpeed,lastSpeedTime=nil,nil
        event("character_bound",{present=char~=nil})
    end
    local function readFlag(names)
        for _,object in ipairs({character or false,humanoid or false,player}) do
            if object then
                for _,name in ipairs(names) do
                    local value=object:GetAttribute(name)
                    if type(value)=="boolean" then return value,"attribute:"..object.Name.."."..name end
                end
            end
        end
        for _,name in ipairs(names) do
            local value=valueObjects[name]
            if value and value.Parent then return value.Value,"BoolValue:"..name end
        end
        return nil,"unknown"
    end
    local function stateSignals(t)
        local crouched,crouchSource=readFlag(CROUCH)
        local emote,emoteSource=readFlag(EMOTE)
        if provider then
            local ok,value=pcall(provider,{character=character,humanoid=humanoid,root=root,player=player})
            if ok and type(value)=="table" then
                if type(value.crouched)=="boolean" then crouched,crouchSource=value.crouched,"provider" end
                if type(value.emote)=="boolean" then emote,emoteSource=value.emote,"provider" end
            elseif not ok then event("state_provider_error",{message=tostring(value)}) end
        end
        if t-lastIndicator>=0.5 then
            lastIndicator=t
            local controlsGui=pg:FindFirstChild("ControlsGui",true)
            local frame=controlsGui and controlsGui:FindFirstChild("PCFrame",true)
            standIndicator=frame and frame:FindFirstChild("Stand",true)
        end
        if crouched==nil and config.UseLegacyStandIndicator~=false and standIndicator and standIndicator.Parent
            and standIndicator:IsA("GuiObject") then
            crouched,crouchSource=standIndicator.Visible,"ControlsGui/PCFrame/Stand.Visible (convention)"
        end
        if emote==nil and next(allowedAnimations) then
            local playing=false
            for track in pairs(tracks) do
                if not track.IsPlaying then tracks[track]=nil
                elseif track.Animation then
                    local id=tostring(track.Animation.AnimationId):match("%d+$")
                    if id and allowedAnimations[id] then playing=true end
                end
            end
            emote,emoteSource=playing,"configured-animation-ids"
        end
        return crouched,crouchSource,emote,emoteSource
    end
    local function getCameraController()
        if services.GetCameraController then return services.GetCameraController() end
        local module=route.playerModule
        if type(module)~="table" then return nil end
        local ok,cameras=pcall(function() return module:GetCameras() end)
        if not ok or type(cameras)~="table" then return nil end
        local active=rawget(cameras,"activeCameraController")
        if active then return active end
        if type(cameras.GetActiveCameraController)=="function" then return cameras:GetActiveCameraController() end
        return nil
    end
    local gate=modules.CameraGate.new(getCameraController,function(input,began)
        if input.UserInputType~=Enum.UserInputType.Touch or not enabled then return false end
        return controlTouches[input]==true or (began and presentation:Contains(input.Position)~=nil)
    end)
    local function observe(t)
        local valid=humanoid and root and root.Parent and humanoid.Health>0
        local state=valid and enumName(humanoid:GetState()) or "Missing"
        local airborne=state=="Jumping" or state=="Freefall"
        local grounded=valid and not airborne and humanoid.FloorMaterial~=Enum.Material.Air or false
        local blocked=not enabled or not focused or not route:IsReady() or uis:GetFocusedTextBox()~=nil
            or (valid and (humanoid.Sit or humanoid.PlatformStand or root.Anchored))
            or state=="Swimming" or state=="Dead" or state=="Ragdoll" or state=="Physics"
        if services.GuiService then
            local ok,opened=pcall(function() return services.GuiService.MenuIsOpen end)
            blocked=blocked or (ok and opened==true)
        end
        local crouched,crouchSource,emote,emoteSource=stateSignals(t)
        local contact=grid:Sample(t,valid and enabled and not blocked and (movementTouch~=nil or jump:hasIntent(t)))
        local vx,vy,vz=0,0,0
        if valid then
            local velocity=root.AssemblyLinearVelocity
            vx,vy,vz=velocity.X,velocity.Y,velocity.Z
        end
        local speed=math.sqrt(vx*vx+vz*vz)
        local forwardDot=0
        local camera=services.Workspace.CurrentCamera
        if camera and speed>0.001 then
            local forward=camera.CFrame.LookVector
            local length=math.sqrt(forward.X*forward.X+forward.Z*forward.Z)
            if length>0.001 then forwardDot=(vx*forward.X+vz*forward.Z)/(speed*length) end
        end
        local canJump=true
        if valid then
            local ok,value=pcall(function() return humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) end)
            if ok then canJump=value end
        end
        return {alive=valid and true or false,grounded=grounded,blocked=blocked and true or false,
            nativeState=state,crouched=crouched,crouchSource=crouchSource,emote=emote,emoteSource=emoteSource,
            horizontalSpeed=speed,verticalSpeed=vy,forwardDot=forwardDot,canJump=canJump,
            gridContact=contact.contact,gridNearby=contact.nearby,gridEvidence=contact.evidence,
            gridPart=contact.part and contact.part:GetFullName() or nil,gridAge=t-(contact.at or t),
            jumpIntent=jump:hasIntent(t)}
    end
    local function saveLayout()
        layoutSaved={}
        for name,object in pairs({joystick=presentation.joystick,jump=presentation.jump,knob=presentation.knob}) do
            layoutSaved[name]={Position=object.Position,Size=object.Size,AnchorPoint=object.AnchorPoint,
                attributes=object:GetAttributes()}
        end
    end
    local function maintain(t)
        if t-lastMaintenance<0.25 then return end
        lastMaintenance=t
        if not route.running then route:Start() else route:Refresh() end
        if route:IsReady() and routeGeneration~=route.generation then
            routeGeneration=route.generation
            replayPending=true
            event("keyboard_route_reactivated",{generation=routeGeneration})
        end
        gate:Refresh()
        for track in pairs(tracks) do if not track.IsPlaying then tracks[track]=nil end end
        if not presentation.gui.Parent or not presentation.joystick.Parent or not presentation.jump.Parent
            or not presentation.knob.Parent then
            clearInput()
            presentation:Stop(false)
            presentation=modules.Controls.new(services)
            for name,saved in pairs(layoutSaved) do
                local object=presentation[name]
                object.Position,object.Size,object.AnchorPoint=saved.Position,saved.Size,saved.AnchorPoint
                for key,value in pairs(saved.attributes) do object:SetAttribute(key,value) end
            end
            event("overlay_recreated")
        else
            local camera=services.Workspace.CurrentCamera
            if camera then presentation:Layout(camera.ViewportSize) end
            saveLayout()
        end
    end
    local function update(dt)
        if not running then return end
        local started=now()
        -- InputEnded can be missed while the app loses focus or controllers reset.
        -- Reconcile the actual InputObject state before issuing any held input.
        for input in pairs(controlTouches) do
            if input.UserInputState==Enum.UserInputState.End or input.UserInputState==Enum.UserInputState.Cancel then
                releaseTouch(input,input.UserInputState==Enum.UserInputState.Cancel)
            end
        end
        maintain(started)
        local observed=observe(started)
        if not observed.alive or observed.blocked then clearInput() end
        local result=policy:step({active=movementTouch~=nil,x=analogX,z=analogZ},observed,started)
        -- Revalidate current body contact at the exact opportunity to request a
        -- buffered native jump. Cached discovery never grants an air/nearby hop.
        local jumpObserved={alive=observed.alive,blocked=observed.blocked,grounded=observed.grounded,
            canJump=observed.canJump,gridContact=false}
        if observed.grounded and jump:hasIntent(started) and not jump.spentGround
            and started-jump.lastPulse>=0.11 then
            jumpObserved.gridContact=grid:ContactNow(started).contact
        end
        local space,reason=jump:step(started,jumpObserved)
        result.keys.Space=space
        if replayPending then
            -- Keyboard:Enable resets its directional fields. Replay held edges
            -- after activation, retrying failed releases before claiming success.
            ledger:apply({})
            replayPending=Core.chord(ledger.pressed)~="-"
            if replayPending then result.keys={} end
        end
        local chord=ledger:apply(result.keys)
        if chord~=lastChord then
            changes=changes+1
            event("input_changed",{from=lastChord,to=chord,state=result.primary,x=analogX,z=analogZ})
            lastChord=chord
        end
        if reason then event("native_jump_request",{reason=reason,grounded=observed.grounded,
            realGridContact=jumpObserved.gridContact,acceptedByGame="unconfirmed"}) end
        if log.enabled and started-lastLog>=0.10 then
            lastLog=started
            event("sample",{state=result.primary,flags=result.flags,chord=chord,x=analogX,z=analogZ,
                horizontal=observed.horizontalSpeed,vertical=observed.verticalSpeed,
                grid=observed.gridContact,nearby=observed.gridNearby,evidence=observed.gridEvidence,
                part=observed.gridPart,crouchSource=observed.crouchSource,emoteSource=observed.emoteSource})
            if lastSpeed and lastSpeed-observed.horizontalSpeed>6
                and observed.horizontalSpeed<lastSpeed*0.82 then
                event("speed_drop",{before=lastSpeed,after=observed.horizontalSpeed,
                    interval=started-lastSpeedTime,chord=chord,state=result.primary,
                    route=route.status,transportFailures=ledger.failures,ourPhysicsWrites=0,
                    cause="unattributed: game physics, input response or another script"})
            end
            lastSpeed,lastSpeedTime=observed.horizontalSpeed,started
        end
        presentation:Step(dt)
        lastResult,lastObservation=result,observed
        ticks=ticks+1
        maxTickMS=math.max(maxTickMS,(now()-started)*1000)
    end
    local function move(position)
        if not movementCenter then return end
        local point=Vector2.new(position.X,position.Y)
        local delta=point-movementCenter
        analogX,analogZ=delta.X/movementRadius,delta.Y/movementRadius
        presentation:SetKnob(delta)
    end
    local api={Version="rebuild-1.0-native-input"}
    local function guardedUpdate(dt)
        local ok,message=pcall(update,dt)
        if not ok then
            event("runtime_error",{message=tostring(message)})
            pcall(clearInput)
            pcall(api.Stop,true)
            warn("[PC Movement Rebuild] Stopped after runtime error: "..tostring(message))
        end
        return ok,message
    end
    function api.GetState()
        return {version=api.Version,enabled=enabled,running=running,chord=Core.chord(ledger.pressed),
            state=lastResult and lastResult.primary or "STARTING",flags=lastResult and lastResult.flags or {},
            analogX=analogX,analogZ=analogZ,observation=lastObservation,
            route=route:GetState(),cameraMethods=gate.methods,diagnostics=log.enabled,
            counters={ticks=ticks,keyEvents=ledger.events,keyFailures=ledger.failures,jumpPulses=jump.pulses,
                inputChanges=changes,broadQueries=grid.queries,narrowReads=grid.narrowReads,maxTickMS=maxTickMS},
            oldCleanupErrors=cleanupErrors,physicsWrites=0}
    end
    function api.SetEnabled(value)
        enabled=value~=false
        clearInput()
        route:SetEnabled(enabled)
        guardedUpdate(0)
        return enabled
    end
    function api.IsEnabled() return enabled and running end
    function api.SetSwapAD(value) config.SwapAD=value==true guardedUpdate(0) end
    function api.SetStateProvider(fn)
        assert(fn==nil or type(fn)=="function","StateProvider must be a function or nil")
        provider=fn;guardedUpdate(0)
    end
    function api.SetDiagnostics(value) log.enabled=value==true return log.enabled end
    function api.GetLogs() return log:read() end
    function api.Probe()
        local result={state=api.GetState(),attributes={},boolValues={},animations={}}
        for _,object in ipairs({player,character or false,humanoid or false}) do
            if object then result.attributes[object.Name]=object:GetAttributes() end
        end
        for name,object in pairs(valueObjects) do
            if object.Parent then result.boolValues[name]=object.Value end
        end
        for track in pairs(tracks) do
            if track.IsPlaying and track.Animation then
                result.animations[#result.animations+1]={name=track.Name,id=track.Animation.AnimationId}
            end
        end
        return result
    end
    function api.ExportDiagnostics(filename)
        local payload={probe=api.Probe(),events=log:read()}
        local json=services.HttpService:JSONEncode(payload)
        filename=filename or "PCMovementRebuild_Log.json"
        if type(writefile)=="function" then
            local ok,message=pcall(writefile,filename,json)
            if not ok then return false,tostring(message),json end
            return true,filename
        end
        return false,"writefile unavailable",json
    end
    function api.Stop(retainUI)
        if not running then return end
        running=false
        clearInput()
        disconnect(connections);disconnect(charConnections)
        run:UnbindFromRenderStep(BIND)
        gate:Stop();grid:Stop();route:Stop()
        ledger:apply({})
        if Core.chord(ledger.pressed)~="-" then
            env.__PCMovementPendingRelease=ledger.pressed
            warn("[PC Movement Rebuild] Key release failed; retained for next start.")
        end
        presentation:Stop(retainUI==true)
        for _,name in ipairs({"PCMovementRebuild","PCModeLock","PCKeyboardTouchBridgeV52",
            "LegacyGridContactAssistV1","__PCModeLockCleanup","__PCKeyboardTouchBridgeV52Cleanup",
            "__LegacyGridContactAssistV1Cleanup"}) do
            if name=="PCMovementRebuild" then
                if env[name]==api then env[name]=nil end
            elseif env.PCMovementRebuild==nil then env[name]=nil end
        end
    end
    connect(player.CharacterAdded,bindCharacter)
    connect(player.CharacterRemoving,function() bindCharacter(nil) end)
    connect(uis.InputBegan,function(input)
        if not running or not enabled or not focused or input.UserInputType~=Enum.UserInputType.Touch
            or uis:GetFocusedTextBox() then return end
        local control=presentation:Contains(input.Position)
        if control=="joystick" and not movementTouch then
            movementTouch=input;controlTouches[input]=true
            movementCenter=presentation.joystick.AbsolutePosition+presentation.joystick.AbsoluteSize/2
            movementRadius=math.max(46,math.min(presentation.joystick.AbsoluteSize.X,
                presentation.joystick.AbsoluteSize.Y)*0.42)
            move(input.Position);guardedUpdate(0)
        elseif control=="jump" then
            jumpTouches[input]=true;controlTouches[input]=true
            jump:setHeld(true,now());presentation:SetJumpPressed(true);guardedUpdate(0)
        end
    end)
    connect(uis.InputChanged,function(input)
        if controlTouches[input] then
            if input.UserInputState==Enum.UserInputState.Cancel or input.UserInputState==Enum.UserInputState.End then
                releaseTouch(input,input.UserInputState==Enum.UserInputState.Cancel)
            elseif input==movementTouch then move(input.Position) end
            guardedUpdate(0)
        end
    end)
    connect(uis.InputEnded,function(input)
        if controlTouches[input] then
            releaseTouch(input,input.UserInputState==Enum.UserInputState.Cancel)
            guardedUpdate(0)
        end
    end)
    connect(uis.WindowFocusReleased,function() focused=false clearInput() end)
    connect(uis.WindowFocused,function() focused=true clearInput() end)
    connect(uis.TextBoxFocused,clearInput)
    local initialized,message=pcall(function()
        route:Start()
        bindCharacter(player.Character)
        saveLayout()
        run:BindToRenderStep(BIND,Enum.RenderPriority.Input.Value-2,guardedUpdate)
        update(0)
    end)
    if not initialized then
        pcall(api.Stop,true)
        error("[PC Movement Rebuild] Initialization rolled back: "..tostring(message))
    end
    -- Publish only a fully initialized runtime. Failure paths release their
    -- listeners, route and keys through the same idempotent Stop.
    env.PCMovementRebuild=api
    env.PCModeLock={Version=api.Version,SetEnabled=api.SetEnabled,IsEnabled=api.IsEnabled,GetState=api.GetState}
    env.PCKeyboardTouchBridgeV52={Version=api.Version,GetState=function()
        local keys={}
        for _,name in ipairs({"W","A","S","D"}) do keys[name]=ledger.pressed[name] end
        return {chord=Core.chord(keys),analogX=analogX,analogZ=analogZ,
            movementTouchActive=movementTouch~=nil,movementTouch=movementTouch,
            keyEvents=ledger.events,jumpPulses=jump.pulses,sweepActive=false,
            directPlayerMove=false,visibleJoystick=true}
    end}
    env.LegacyGridContactAssistV1={Version=api.Version,GetState=function()
        return {contact=lastObservation and lastObservation.gridContact or false,physicsWrites=0}
    end}
    env.__PCModeLockCleanup=api.Stop
    env.__PCKeyboardTouchBridgeV52Cleanup=api.Stop
    env.__LegacyGridContactAssistV1Cleanup=api.Stop
    return api
end
return Runtime
