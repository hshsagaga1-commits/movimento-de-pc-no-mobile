-- Native Classic Lateral V2 | Evade iOS | active Classic TouchThumbstick only
-- Never changes native TouchGui, layout, camera, jump or physical velocity.
-- A/D get full command at 20% radius; reversal from 6.5% AFTER center.
-- Original controls pass through for diagonal, forward/back and release.
-- This is a candidate requiring a real-device test.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local player=Players.LocalPlayer
local env=getgenv()
local EVADE_GAME_ID=3647333358

local previous=env.NativeClassicLateralV2
if type(previous)=="table" and type(previous.Stop)=="function" then pcall(previous.Stop) end

local CONFIG={
    FullLateralThreshold=0.20, -- 20% of the physical stick radius yields full side input
    ReversalThreshold=0.065,  -- accept fresh opposite intent shortly after strong strafe
    StrongSideThreshold=0.55,
    ReversalWindow=0.11,    -- seconds; no continued forcing after this expires
    PureSideRatio=0.42,     -- avoid changing genuine diagonals
    ScanInterval=0.25,
    StrongSideMemory=0.75,
}
local active=true
local enabled=true
local controls=nil
local thumbstickClass=nil
local attached=nil
local originalMethod=nil
local originalOwnMethod=nil
local lastTouch=nil
local lastStrongSide=0
local lastStrongAt=-math.huge
local reversalUntil=-math.huge
local reversals=0
local enhancedFrames=0
local installCount=0
local hookErrors=0
local lastScan=-math.huge
local lastX,lastZ,lastOutX,lastOutZ=0,0,0,0
local lastActive=false
local lastError="not initialized"
local scanConnection=nil
local api={Version="2.0-native-classic-lateral"}

local function sign(v)
    return v<0 and -1 or 1
end
local function resetTracking()
    lastTouch=nil
    lastStrongSide=0
    lastStrongAt=-math.huge
    reversalUntil=-math.huge
    lastX,lastZ,lastOutX,lastOutZ=0,0,0,0
    lastActive=false
end
local function restoreController()
    if attached and originalMethod and rawget(attached,"GetMoveVector")~=originalOwnMethod then
        -- Do not overwrite a different script's newer replacement.
        if rawget(attached,"GetMoveVector")==api._hook then
            pcall(function() attached.GetMoveVector=originalOwnMethod end)
        end
    end
    attached=nil
    originalMethod=nil
    originalOwnMethod=nil
    api._hook=nil
    resetTracking()
end
local function locateControls()
    -- Only the LIVE PlayerScripts controller can drive the real thumbstick.
    local scripts=player:FindFirstChildOfClass("PlayerScripts")
        or player:FindFirstChild("PlayerScripts")
    local module=scripts and scripts:FindFirstChild("PlayerModule")
    if not module or not module:IsA("ModuleScript") then
        return nil,nil,"live PlayerScripts.PlayerModule unavailable"
    end
    local ok,pm=pcall(require,module)
    if not ok or type(pm)~="table" or type(pm.GetControls)~="function" then
        return nil,nil,"PlayerModule.GetControls unavailable"
    end
    local okControls,control=pcall(pm.GetControls,pm)
    if not okControls or type(control)~="table"
        or type(control.GetActiveController)~="function" then
        return nil,nil,"ControlModule unavailable"
    end
    local cm=module:FindFirstChild("ControlModule")
    local child=cm and cm:FindFirstChild("TouchThumbstick")
    if not child or not child:IsA("ModuleScript") then
        return nil,nil,"classic TouchThumbstick unavailable"
    end
    local okClass,klass=pcall(require,child)
    if not okClass or type(klass)~="table" then
        return nil,nil,"classic module require failed"
    end
    return control,klass,nil
end
local function isClassic(control,klass,controller)
    return controller~=nil
        and control.activeControlModule==klass
        and controller.enabled==true
        and controller.thumbstickFrame~=nil
        and controller.thumbstickFrame.Parent~=nil
        and controller.thumbstickFrame.Visible==true
end
local function sampleRaw(controller)
    local touch=controller.moveTouchObject
    local frame=controller.thumbstickFrame
    if not touch or not frame or not frame.Parent then return nil,nil,nil end
    local ok,x,z=pcall(function()
        local position=touch.Position
        local center=frame.AbsolutePosition+frame.AbsoluteSize/2
        local radius=math.max(1,frame.AbsoluteSize.X/2)
        return (position.X-center.X)/radius,(position.Y-center.Y)/radius
    end)
    if not ok or type(x)~="number" or type(z)~="number" then return nil,nil,nil end
    return math.clamp(x,-1.5,1.5),math.clamp(z,-1.5,1.5),touch
end
local function enhance(native,x,z,touch)
    if touch~=lastTouch then
        resetTracking()
        lastTouch=touch
    end
    lastX,lastZ=x,z
    local ax,az=math.abs(x),math.abs(z)
    -- A true diagonal must remain exactly native; no phantom 100% A/D.
    if ax<CONFIG.ReversalThreshold or az>ax*CONFIG.PureSideRatio then
        lastOutX,lastOutZ=native.X,native.Z
        return native
    end
    local side=x<0 and -1 or 1
    local now=os.clock()
    -- Predict NOTHING: activation happens only after finger crosses
    -- center and has passed 6.5% on the physically opposite side.
    if lastStrongSide~=0 and side~=lastStrongSide
        and now-lastStrongAt<=CONFIG.StrongSideMemory then
        reversalUntil=now+CONFIG.ReversalWindow
        reversals+=1
        lastStrongSide=side
        lastStrongAt=now
    end
    local full=ax>=CONFIG.FullLateralThreshold or now<=reversalUntil
    if not full then
        lastOutX,lastOutZ=native.X,native.Z
        return native
    end
    if ax>=CONFIG.FullLateralThreshold then
        lastStrongSide=side
        lastStrongAt=now
    end
    enhancedFrames+=1
    lastOutX,lastOutZ=side,0
    return Vector3.new(side,0,0)
end
local function install(controller)
    restoreController()
    if not controller or type(controller.GetMoveVector)~="function" then return false end
    local before=controller.GetMoveVector
    local okOwn,own=pcall(rawget,controller,"GetMoveVector")
    if not okOwn then lastError="native method ownership unavailable" return false end
    local hook=function(self,...)
        local native=before(self,...)
        if not active or not enabled or game.GameId~=EVADE_GAME_ID
            or attached~=self or typeof(native)~="Vector3" then return native end
        if not controls or not isClassic(controls,thumbstickClass,self) then
            resetTracking()
            return native
        end
        local x,z,touch=sampleRaw(self)
        if not touch then
            resetTracking()
            return native
        end
        lastActive=true
        local good,value=pcall(enhance,native,x,z,touch)
        if good and typeof(value)=="Vector3" then return value end
        hookErrors+=1
        lastError="enhancer error: "..tostring(value)
        return native
    end
    local ok,err=pcall(function() controller.GetMoveVector=hook end)
    if not ok then lastError=tostring(err) return false end
    attached=controller
    originalMethod=before
    originalOwnMethod=own
    api._hook=hook
    installCount+=1
    lastError=nil
    return true
end
local function scan()
    if not active then return end
    if not enabled or game.GameId~=EVADE_GAME_ID then
        if attached then restoreController() end
        return
    end
    if not controls then
        controls,thumbstickClass,lastError=locateControls()
        if not controls then return end
    end
    local ok,current=pcall(function() return controls:GetActiveController() end)
    if not ok or not isClassic(controls,thumbstickClass,current) then
        if attached then restoreController() end
        return
    end
    local ownOk,owned=pcall(rawget,current,"GetMoveVector")
    if not ownOk then lastError="method ownership unavailable" return end
    if current~=attached or owned~=api._hook then install(current) end
end
scanConnection=RunService.Heartbeat:Connect(function()
    local now=os.clock()
    if now-lastScan>=CONFIG.ScanInterval then lastScan=now scan() end
end)
scan()
function api.GetState()
    return {
        version=api.Version,enabled=enabled,installed=attached~=nil,
        active=lastActive,rawX=lastX,rawZ=lastZ,processedX=lastOutX,processedZ=lastOutZ,
        reversals=reversals,enhancedFrames=enhancedFrames,installCount=installCount,
        hookErrors=hookErrors,
        threshold=CONFIG.FullLateralThreshold,reason=lastError or "ok",
        touchController="classic"
    }
end
function api.SetEnabled(value)
    enabled=value~=false
    if not enabled then restoreController()
    else scan() end
    return enabled
end
function api.Stop()
    if not active then return end
    active=false
    if scanConnection then scanConnection:Disconnect() scanConnection=nil end
    restoreController()
    if env.NativeClassicLateralV2==api then env.NativeClassicLateralV2=nil end
end
env.NativeClassicLateralV2=api
print("[NativeClassicLateralV2] Native classic input enhancer initialized; "..tostring(lastError or "ready"))
return api
