-- The packer passes the preserved components as local functions. No module fetches.
return function(modules)
    local env=getgenv()
    if env.PCMovementV32 then return env.PCMovementV32 end
    if env.__PCMovementV31PreservedInstall then
        return nil,"A instalação anterior de PC Movement ainda está em andamento."
    end

    local player=game:GetService("Players").LocalPlayer
    local api={Version="3.2-adaptive"}
    local state="starting"
    local phaseBusy=true
    local stopRequested=false
    local lease={}
    local stopSlots={}
    local playerGui,overlay,repairJob,repairConnection
    local repairs,repairFailures=0,0
    local assistMode="starting"
    local cursorError
    local LEGACY_OWNERS={"PCMovementAssistV31Preserved","PCMovementAssistV31","PCMovementAssistV3",
        "PCMovementAssistV2","PCMovementRebuild"}
    local LEGACY_SLOTS={"__PCCursorVisualV31Cleanup","__PCModeLockCleanup","__PCRobloxNativeVisualV5Cleanup",
        "__PCKeyboardTouchBridgeV52Cleanup","__PCKeyboardControllerWakeV5Cleanup",
        "__PCCameraTouchRightHalfGateV5Cleanup","__LegacyGridContactAssistV1Cleanup",
        "__PCCrouchToggleV59Cleanup","__PCIndependentJoystickCleanup","__PCKeyboardTouchBridgeV5Cleanup",
        "__PCSelectiveWASDCleanup","__PCClassicNativeKeysV3Cleanup","__PCClassicNativeKeysCleanup","__PCClassicWASDCleanup"}
    local LOCK="__PCModeLockCleanup"
    local WAKE="__PCKeyboardControllerWakeV5Cleanup"
    local CAMERA="__PCCameraTouchRightHalfGateV5Cleanup"
    local BRIDGE="__PCKeyboardTouchBridgeV52Cleanup"
    local VISUAL="__PCRobloxNativeVisualV5Cleanup"
    local CURSOR="__PCCursorVisualV31Cleanup"
    local ASSIST="__LegacyGridContactAssistV1Cleanup"
    local OVERLAY="PCKeyboardTouchBridgeV52Overlay"

    local function disconnectSlot(slot)
        local owned=stopSlots[slot]
        stopSlots[slot]=nil
        if owned and env[slot]==owned then
            local ok,message=pcall(owned)
            if not ok then warn("[PC Movement V3.2] cleanup "..slot..": "..tostring(message)) end
        end
    end

    local function freeLease()
        if env.__PCMovementV31PreservedInstall==lease then env.__PCMovementV31PreservedInstall=nil end
    end

    local function teardown()
        if repairConnection then repairConnection:Disconnect() repairConnection=nil end
        if repairJob then task.cancel(repairJob) repairJob=nil end
        for _,slot in ipairs({CURSOR,ASSIST,VISUAL,BRIDGE,CAMERA,WAKE,LOCK}) do disconnectSlot(slot) end
        overlay=nil
        freeLease()
        if env.PCMovementV32==api then env.PCMovementV32=nil end
        if env.PCMovementAssistV31Preserved==api then env.PCMovementAssistV31Preserved=nil end
        if env.PCMovementAssistV31==api then env.PCMovementAssistV31=nil end
        state="stopped"
    end

    function api.Stop()
        if stopRequested then return end
        stopRequested=true
        state="stopping"
        if not phaseBusy then teardown() end
    end

    local function checkActive()
        if stopRequested then error("instalação cancelada",0) end
    end

    local function install(slot,init,...)
        checkActive()
        local before=env[slot]
        local ok,message=pcall(init,...)
        if type(env[slot])=="function" and env[slot]~=before then stopSlots[slot]=env[slot] end
        if not ok then error(message,0) end
        checkActive()
    end

    local function installOverlay()
        disconnectSlot(VISUAL)
        disconnectSlot(BRIDGE)
        install(BRIDGE,modules.bridge,modules.posture)
        install(VISUAL,modules.visual)
        overlay=playerGui:FindFirstChild(OVERLAY)
    end

    local function installAssist(target)
        disconnectSlot(ASSIST)
        install(ASSIST,target=="original" and modules.originalAssist or modules.assist)
        assistMode=target
    end

    local function callComponent(slot,name,method,...)
        if not stopSlots[slot] or env[slot]~=stopSlots[slot] then return nil end
        local object=env[name]
        if type(object)=="table" and type(object[method])=="function" then
            return object[method](...)
        end
    end

    function api.GetState()
        return {version="3.2",build=api.Version,status=state,repairs=repairs,repairFailures=repairFailures,
            assistMode=assistMode,cursorError=cursorError,bridge=callComponent(BRIDGE,"PCKeyboardTouchBridgeV52","GetState"),
            assist=callComponent(ASSIST,"LegacyGridContactAssistV1","GetState"),pcLock=callComponent(LOCK,"PCModeLock","GetState"),
            keyboardWake=callComponent(WAKE,"PCKeyboardControllerWakeV5","GetState"),
            cameraGate=callComponent(CAMERA,"PCCameraTouchRightHalfGateV5","GetState")}
    end

    function api.SetCursorHidden(value)
        return callComponent(CURSOR,"PCCursorVisualV31","SetEnabled",value)
    end
    function api.SetDiagnostics(value)
        return callComponent(ASSIST,"LegacyGridContactAssistV1","SetDiagnostics",value)
    end
    function api.ExportDiagnostics(filename)
        return callComponent(ASSIST,"LegacyGridContactAssistV1","ExportDiagnostics",filename or "PCMovement_V32_Log.json")
    end
    function api.SetAssistMode(target)
        if state~="running" or phaseBusy or game.GameId~=3647333358 then return false,"assist unavailable" end
        if target~="light" and target~="original" then return false,"use light or original" end
        if target==assistMode then return true end
        phaseBusy=true
        env.__PCMovementV31PreservedInstall=lease
        local previous=assistMode
        local ok,message=pcall(installAssist,target)
        if not ok and not stopRequested then
            local restored,reason=pcall(installAssist,previous)
            if not restored then
                disconnectSlot(ASSIST)
                assistMode="failed"
                warn("[PC Movement V3.2] Assist rollback: "..tostring(reason))
            end
        end
        phaseBusy=false
        freeLease()
        if stopRequested then teardown() end
        return ok,message
    end

    local function overlayReady()
        if not overlay or overlay.Parent~=playerGui then return false end
        local stick=overlay:FindFirstChild("PCJoystick")
        return stick and stick:FindFirstChild("Knob") and overlay:FindFirstChild("PCJump")
    end

    local function scheduleRepair(delay)
        if repairJob or state~="running" then return end
        repairJob=task.delay(delay,function()
            repairJob=nil
            if state~="running" or overlayReady() then return end
            if phaseBusy then scheduleRepair(0.25) return end
            phaseBusy=true
            env.__PCMovementV31PreservedInstall=lease
            local ok,message=pcall(installOverlay)
            phaseBusy=false
            freeLease()
            if stopRequested then teardown() return end
            if ok then
                repairs+=1
                repairFailures=0
            else
                disconnectSlot(VISUAL)
                disconnectSlot(BRIDGE)
                repairFailures+=1
                warn("[PC Movement V3.2] UI repair: "..tostring(message))
                if repairFailures<3 then scheduleRepair(3) end
            end
        end)
    end

    env.PCMovementV32=api
    env.__PCMovementV31PreservedInstall=lease
    local ok,message=pcall(function()
        for _,name in ipairs(LEGACY_OWNERS) do
            local owner=env[name]
            if type(owner)=="table" and type(owner.Stop)=="function" then pcall(owner.Stop) end
        end
        env.__PCMovementAssistV2Token=nil
        env.__PCMovementAssistV3Token=nil
        env.__PCMovementAssistV31Token=nil
        for _,slot in ipairs(LEGACY_SLOTS) do
            if type(env[slot])=="function" then pcall(env[slot]) end
        end
        env.PCMovementAssistV31Preserved=api
        env.PCMovementAssistV31=api

        playerGui=assert(player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui",15),"PlayerGui unavailable")
        for _,object in ipairs(playerGui:GetDescendants()) do
            if object:IsA("UIScale") and object.Name=="PCCrouchPressVisualV59" then object:Destroy() end
        end
        install(LOCK,modules.lock,function() return not stopRequested end)
        install(CAMERA,modules.camera)
        install(WAKE,modules.wake)
        installOverlay()
        if game.GameId==3647333358 then
            installAssist("light")
        else
            assistMode="not-applicable"
        end
        local cursorOK,reason=pcall(install,CURSOR,modules.cursor)
        if not cursorOK then
            checkActive()
            disconnectSlot(CURSOR)
            cursorError=tostring(reason)
            warn("[PC Movement V3.2] cursor: "..cursorError)
        end
        repairConnection=playerGui.DescendantRemoving:Connect(function(node)
            if not overlay then return end
            if node==overlay or (node.Parent==overlay and (node.Name=="PCJoystick" or node.Name=="PCJump"))
                or (node.Name=="Knob" and node.Parent and node.Parent.Parent==overlay) then
                scheduleRepair(1.25)
            end
        end)
    end)
    phaseBusy=false
    freeLease()
    if not ok or stopRequested then
        teardown()
        if stopRequested then return nil,"instalação cancelada" end
        error(message,0)
    end
    state="running"
    return api
end
