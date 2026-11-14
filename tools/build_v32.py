#!/usr/bin/env python3
"""Bundle the actual V3.1 dependencies, pinned by commit, and the adaptive bridge."""
import argparse
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "62269b83bb05f3fd5eca76f5eeb7102555afc241"
CLASSIC = "3a50d72845066091cec9c7752768a1708d6c40c3"
UI = "a48741ca0f7b86f7a2c2631778ee5a86691b180f"
ORIGINAL = "ce4eb8b6deb47e0690301bd38f1b78eb0e19dcaa"
BRIDGE = "54b0a87ec5bdc7a9ebcfe27569f22f2c5d718217"
OUTPUT = ROOT / "PC_Movement_V32.lua"


def snapshot(commit, path):
    return subprocess.check_output(["git", "show", f"{commit}:{path}"], cwd=ROOT, text=True)


def replace(source, old, new, count=1):
    if source.count(old) != count:
        raise ValueError(f"Source drift for {old!r}: expected {count}, got {source.count(old)}")
    return source.replace(old, new)


def take(source, first, last):
    start = source.index(first)
    return source[start:source.index(last, start)]


def lock_source():
    source = snapshot(CLASSIC, "PCModeLockV5.lua")
    source = replace(source, 'local Players =', 'local shouldContinue = ...\nlocal Players =')
    source = replace(source, "local switchOwnerPrevious", "local switchOwnerPrevious, switchOwnerReplacement")
    source = replace(source, '    rawset(switchOwner, target.name, replacement)', '    rawset(switchOwner, target.name, replacement)\n    switchOwnerReplacement = replacement')
    source = replace(source, '            and type(switchOwnerPrevious) == "function" then',
                     '            and type(switchOwnerPrevious) == "function" and rawget(switchOwner, "SwitchToController") == switchOwnerReplacement then')
    source = replace(source, "local touchController", "local initialModule")
    source = replace(source, '    touchController = rawget(controls, "activeController")', """    initialModule = touchModule
    if type(controls.SelectTouchModule) == "function" then
        local ok, selected = pcall(controls.SelectTouchModule, controls)
        if ok and type(selected) == "table" then touchModule = selected end
    end""")
    source = replace(source, 'type(candidate) == "table" and candidate ~= touchModule', 'type(candidate) == "table"')
    source = replace(source, '    if keyboardModule then\n        return true, "upvalue-map"', """    if keyboardModule then
        if touchModule == keyboardModule then touchModule = nil end
        return true, "upvalue-map" """.rstrip())
    source = replace(source, "local function seedKeyboardInput()", """local function seedCancelled()
    if shouldContinue() then return false end
    local selected = rawget(controls, "activeControlModule")
    if type(selected) == "table" and selected ~= initialModule and selected ~= touchModule then
        keyboardModule = selected -- cleanup can restore the controller selected before the seed
    end
    return true
end

local function seedKeyboardInput()""")
    source = replace(source, "    for _ = 1, 10 do\n        task.wait(0.025)", """    if seedCancelled() then return false end
    for _ = 1, 10 do
        task.wait(0.025)
        if seedCancelled() then return false end""")
    source = replace(source, '    if seedKeyboardInput() then\n        return true, "synthetic-keyboard-selection"\n    end', '    if seedKeyboardInput() then\n        return true, "synthetic-keyboard-selection"\n    end\n    if not shouldContinue() then return false, "cancelled" end')
    source = replace(source, "    local keyboardOk, keyboardStatus = discoverKeyboardModule()", "    local keyboardOk, keyboardStatus = discoverKeyboardModule()\n    if not shouldContinue() then return end")
    source = replace(source, '    if statusGui then\n', """    if type(controls) == "table" and keyboardModule and initialModule ~= keyboardModule
        and rawget(controls, "activeControlModule") == keyboardModule then
        local switch = switchOriginal or switchOwnerPrevious or controls.SwitchToController
        if type(switch) == "function" then pcall(switch, controls, initialModule) end
    end

    if statusGui then
""")
    source = replace(source, 'local HttpService = game:GetService("HttpService")\n', "")
    source = replace(source, take(source, "local BASE_URL", "-- Clean a previous"), "")
    source = replace(source, take(source, "-- Load the latest left-half joystick", "local controlsOk"), "")
    source = replace(source, take(source, '    if type(baseCleanup) == "function" then', "    getgenv().PCModeLock = nil"), "")
    source = replace(source, "local facadeInstalled = false", "local facadeInstalled = false\nlocal facadeActive = true")
    source = replace(source, "if lockEnabled and self == UserInputService", "if lockEnabled and facadeActive and self == UserInputService", 2)
    old_restore = take(source, "    if facadeInstalled and type(hookmetamethod)", "    if type(controls)")
    source = replace(source, old_restore, "    restoreInputFacade()\n\n")
    source = replace(source, "local function getUpvalues(fn)", """local facadeRestored = false
local function restoreInputFacade()
    if not facadeInstalled or facadeRestored then return end
    -- Restore at the bootstrap boundary. Stop must not overwrite a later hook.
    facadeRestored = true
    if previousNamecall then pcall(hookmetamethod, game, "__namecall", previousNamecall) end
    if previousIndex then pcall(hookmetamethod, game, "__index", previousIndex) end
end

local function getUpvalues(fn)""")
    source = replace(source, 'local oldStatus =', 'facadeActive = false\nrestoreInputFacade()\nlocal oldStatus =')
    source = replace(source, 'facadeInstalled and "ON" or "OFF"', 'facadeInstalled and "PASS" or "OFF"')
    source = replace(source, 'local statusGui = Instance.new', 'statusGui = Instance.new')
    source = replace(source, "local controlsOk,", "local statusGui\nlocal controlsOk,")
    cleanup = source[source.index("getgenv().__PCModeLockCleanup = function()"):]
    source = replace(source, cleanup, "")
    source = replace(source, "local statusGui\nlocal controlsOk,", "local statusGui\n"+cleanup+"\nlocal controlsOk,")
    source = replace(source, "local controlsOk, controlsStatus = locateControls()",
                     "local controlsOk, controlsStatus = locateControls()\nif not shouldContinue() then return end")
    source = replace(source, "    local controllerState", "    if not statusGui.Enabled then return end\n    local controllerState")
    source = replace(source, "    statusLabel.Text = string.format(", """    if controllerState == displayedController and blockedTouchSwitches == displayedSwitches then return end
    displayedController, displayedSwitches = controllerState, blockedTouchSwitches
    statusLabel.Text = string.format(""")
    source = replace(source, "RunService:BindToRenderStep(LOCK_BIND", "local displayedController, displayedSwitches\nRunService:BindToRenderStep(LOCK_BIND")
    source = replace(source, 'Version = "5.0-input-facade-controlmodule-pc-lock"', 'Version = "3.2-preserved-pc-lock"')
    return source


def wake_source():
    source = snapshot(CLASSIC, "PCKeyboardControllerWakeV5.lua")
    source = replace(source, "local function ensureEnabled()", """local lastAttemptController
local nextWakeAt=-math.huge
local function ensureEnabled()""")
    source = replace(source, '    if before==true then\n        lastStatus="already-enabled"', """    if before==true then
        nextWakeAt=-math.huge
        lastStatus="already-enabled" """.rstrip())
    source = replace(source, "    wakeAttempts+=1", """    if controlsEnabled==false then
        nextWakeAt=-math.huge
        lastStatus="global-controls-disabled"
        return
    end
    local now=os.clock()
    if activeController==lastAttemptController and now<nextWakeAt then return end
    lastAttemptController,nextWakeAt=activeController,now+0.125
    wakeAttempts+=1""")
    source = replace(source, "RunService:BindToRenderStep(BIND_NAME", "local displayedStatus,displayedEnabled,displayedGlobal,displayedAttempts\nRunService:BindToRenderStep(BIND_NAME")
    source = replace(source, "    ensureEnabled()\n", "    ensureEnabled()\n    if not gui.Enabled then return end\n")
    source = replace(source, "    label.Text=string.format(", """    if displayedStatus==lastStatus and displayedEnabled==enabled and displayedGlobal==global
        and displayedAttempts==wakeAttempts then return end
    displayedStatus,displayedEnabled,displayedGlobal,displayedAttempts=lastStatus,enabled,global,wakeAttempts
    label.Text=string.format(""")
    return source


def camera_source():
    source = snapshot(CLASSIC, "CameraTouchRightHalfGateV5.lua")
    source = replace(source, "local installedHooks={}", "local installedHooks={}\nlocal hookEpoch=0")
    source = replace(source, "local function restoreHooks()\n", "local function restoreHooks()\n    hookEpoch+=1\n")
    source = replace(source, "            pcall(function() rawset(h.owner,h.name,h.original) end)",
                     "            if rawget(h.owner,h.name)==h.replacement then pcall(rawset,h.owner,h.name,h.original) end")
    source = replace(source, 'name=target.name,original=previous}', 'name=target.name,original=previous,replacement=replacement}')
    source = replace(source, "    local began=findMethod", "    local epoch=hookEpoch\n    local began=findMethod")
    source = replace(source, "if self==getActiveController() and isTouch(input) then",
                     "if epoch==hookEpoch and self==getActiveController() and isTouch(input) then", 3)
    source = replace(source, take(source, "local activeTouches", "local inputConnections"), "")
    source = replace(source, take(source, '    if type(bridge)=="table"', "local function isBlockedTouch"),
                     '    return type(bridge)=="table" and type(bridge.OwnsTouch)=="function" and bridge.OwnsTouch(input)\nend\n\n')
    source = replace(source, take(source, "    if not activeTouches[input]", "    -- Block only"), "")
    source = replace(source, take(source, "        if activeTouches[input]", "    end\nend)"), "")
    source = replace(source, "    table.clear(activeTouches)\n    activeTouchCount=0\n", "")
    source = replace(source, "local function getMeta(tbl)", """inputConnections[#inputConnections+1]=UserInputService.WindowFocusReleased:Connect(function()
    table.clear(blockedTouches)
    table.clear(blockedTouchIds)
end)

local function getMeta(tbl)""")
    source = replace(source, '    local controller=nil\n    pcall(function() controller=rawget(module,"activeCameraController") end)',
                     '    local controller=rawget(module,"activeCameraController")')
    return source


def visual_source():
    source = snapshot(CLASSIC, "PCRobloxNativeVisualV5.lua")
    cleanup = source[source.index("getgenv().__PCRobloxNativeVisualV5Cleanup=function()"):]
    source = replace(source, cleanup, "")
    source = replace(source, "local cameraViewportConnection=nil\n", "")
    return replace(source, "local function hideDebugGui", "local cameraViewportConnection\n"+cleanup+"\nlocal function hideDebugGui")


def original_assist_source():
    source = snapshot(ORIGINAL, "LegacyGridContactAssistV31.lua")
    source = replace(source, 'env.LegacyGridContactAssistV1.Version=="5.0-v3-full-grid-adhesion-reversal-fix"', 'env.LegacyGridContactAssistV1.Version=="5.1-v31-strong-grip-contact-air-hop"')
    return nonblocking_character(source)


def nonblocking_character(source):
    source = replace(source, take(source, "    if char then\n        if not humanoid", "    rayParams.FilterDescendantsInstances"), "")
    return replace(source, "    if not humanoid or not root or not root.Parent then return end", """    if character and (not humanoid or humanoid.Parent~=character or not root or root.Parent~=character) then
        local nextHum=character:FindFirstChildOfClass("Humanoid")
        local nextRoot=character:FindFirstChild("HumanoidRootPart")
        if nextHum~=humanoid or nextRoot~=root then bindCharacter(character) end
    end
    if not humanoid or not root then return end""")


def cursor_source():
    source = snapshot(UI, "PCCursorVisualV31.lua")
    source = replace(source, 'local RunService=game:GetService("RunService")\n', "")
    source = replace(source, 'local BIND="__PCCursorVisualV31"\n', "")
    source = replace(source, "    pcall(function() RunService:UnbindFromRenderStep(BIND) end)\n", "")
    source = replace(source, "    RunService:BindToRenderStep(BIND,Enum.RenderPriority.Last.Value+1,enforce)\n", "")
    return source


def assist_source():
    source = snapshot(BASE, "LegacyGridContactAssistV31Preserved.lua")
    source = replace(source, "local function readPhysicalContacts(now)", """local classification={}
local function classify(part)
    if not part then return false end
    local kind=classification[part]
    if kind==nil then
        local valid,label=isFenceLike(part)
        kind=valid and label or false
        classification[part]=kind
    end
    return kind~=false,kind
end

local function readPhysicalContacts(now)""")
    source = replace(source, "local valid=isFenceLike(part)", "local valid=classify(part)", 2)
    source = replace(source, "local valid,kind=isFenceLike(part)", "local valid,kind=classify(part)")
    source = replace(source, "local valid,kind=isFenceLike(hit.Instance)", "local valid,kind=classify(hit.Instance)")
    source = replace(source, "    local now=os.clock()\n    readPhysicalContacts(now)", "    local now=os.clock()\n    table.clear(classification)\n    readPhysicalContacts(now)")
    source = replace(source, "local touchingParts,bodyParts={},{}", "local touchingParts,bodyParts,candidates={},{},{}")
    source = replace(source, "    touchingParts={}", "    table.clear(touchingParts)", 2)
    source = replace(source, "bodyParts={}\n", "table.clear(bodyParts)\n", 2)
    source = replace(source, "    local candidates={}\n", "")
    source = replace(source, "    table.sort(candidates,function(a,b) return a.distance<b.distance end)", "    table.sort(candidates,nearer)")
    source = replace(source, "local function bestContact()", """local function nearer(a,b)
    return a.distance<b.distance
end

local function bestContact()""")
    source = replace(source, "    return best\nend\n\nlocal function getContact", "    table.clear(candidates)\n    return best\nend\n\nlocal function getContact")
    source = replace(source, take(source, "    if type(b)==", '    return "-",0,0,false,0'),
                     '    if type(b)=="table" and type(b.ReadMovement)=="function" then return b.ReadMovement() end\n')
    source = replace(source, "local lastRayHitName,lastRayHitDistance", "local lastRayHit,lastRayHitDistance")
    source = replace(source, 'lastRayHit,lastRayHitDistance="-",math.huge', 'lastRayHit,lastRayHitDistance=nil,math.huge')
    source = replace(source, 'lastRayHitName=hit.Instance and hit.Instance:GetFullName() or "?"', 'lastRayHit=hit.Instance')
    source = replace(source, 'lastRayHitName,lastRayHitDistance="-",math.huge', 'lastRayHit,lastRayHitDistance=nil,math.huge')
    source = replace(source, 'lastRayHitName=lastRayHitName,lastRayHitDistance=', 'lastRayHitName=lastRayHit and lastRayHit:GetFullName() or "-",lastRayHitDistance=')
    source = nonblocking_character(source)
    source = replace(source, "    lastContact=nil\n", "    lastContact=nil\n    lastRayHit,lastRayHitDistance=nil,math.huge\n")
    source = replace(source, '        record("vertical_change_near_grid",{', '        if diagnostics then record("vertical_change_near_grid",{')
    source = replace(source, 'grounded=humanoid.FloorMaterial~=Enum.Material.Air,source="unconfirmed"})', 'grounded=humanoid.FloorMaterial~=Enum.Material.Air,source="unconfirmed"}) end')
    source = replace(source, "local diagnostics=config.Diagnostics==true", """local v32Config=env.PCMovementV32Config
if type(v32Config)=="table" then config=v32Config end
local profile=config.Profile==true and debug.profilebegin and debug.profileend
local diagnostics=config.Diagnostics==true""")
    source = replace(source, "        cachedContact=bestContact()", """        if profile then debug.profilebegin("PC Movement V3.2 / Assist scan") end
        cachedContact=bestContact()
        table.clear(classification)
        if profile then debug.profileend() end""")
    source = replace(source, "local CONTACT_SCAN_INTERVAL=1/20\n", "local CONTACT_SCAN_INTERVAL=1/20\nlocal CONTACT_SCAN_INTERVAL_SLOW=1/10 -- halve expensive grid probes during sustained frame drops\n")
    source = replace(source, "local OVERLAP_SCAN_INTERVAL=0.075\n", "local OVERLAP_SCAN_INTERVAL=0.075\nlocal OVERLAP_SCAN_INTERVAL_SLOW=0.14\n")
    source = replace(source, "local lastHeartbeatAt=os.clock()\n", "local lastHeartbeatAt=os.clock()\nlocal slowFrameScore,slowScan=0,false\n")
    source = replace(source, "if now-lastOverlapAt<OVERLAP_SCAN_INTERVAL then return best end", "if now-lastOverlapAt<(slowScan and OVERLAP_SCAN_INTERVAL_SLOW or OVERLAP_SCAN_INTERVAL) then return best end")
    source = replace(source, "if now-lastScanAt>=CONTACT_SCAN_INTERVAL then", "if now-lastScanAt>=(slowScan and CONTACT_SCAN_INTERVAL_SLOW or CONTACT_SCAN_INTERVAL) then")
    source = replace(source, "    local dot=forward.Magnitude>0 and forward:Dot(target) or 1\n", "    local dot=forward.Magnitude>0 and forward:Dot(target) or 1\n    if dot>0.999 then return end -- avoid redundant root CFrame writes when already aligned\n")
    source = replace(source, "    local dt=math.clamp(dtFromHeartbeat or now-lastHeartbeatAt,1/240,0.05)\n    lastHeartbeatAt=now\n",
                            "    local dt=math.clamp(dtFromHeartbeat or now-lastHeartbeatAt,1/240,0.05)\n    lastHeartbeatAt=now\n"
                            "    -- Use hysteresis so occasional frame spikes do not constantly change scan cadence.\n"
                            "    if dtFromHeartbeat and dtFromHeartbeat>1/34 then\n"
                            "        slowFrameScore=math.min(4,slowFrameScore+1)\n"
                            "    elseif dtFromHeartbeat and dtFromHeartbeat<1/42 then\n"
                            "        slowFrameScore=math.max(0,slowFrameScore-1)\n"
                            "    end\n"
                            "    slowScan=slowFrameScore>=2\n")
    source = replace(source, "-- Space sender; this module cannot fabricate an air hop or race its 200ms burst.", "-- Space sender; this module cannot fabricate an air hop or race jump input.")
    source = replace(source, 'Version="3.2-preserved-light-contact"', 'Version="3.2.1-adaptive-light-contact"')
    return source


def render():
    def local_source(name):
        return (ROOT / "v32" / f"{name}.lua").read_text()

    sources = {
        "lock": lock_source(),
        "camera": camera_source(),
        "wake": wake_source(),
        "visual": visual_source(),
        "posture": local_source("Posture"),
        "bridge": local_source("Bridge"),
        "assist": assist_source(),
        "originalAssist": original_assist_source(),
        "cursor": cursor_source(),
    }
    assert snapshot(BRIDGE, "PCKeyboardTouchBridgeV3.lua") == snapshot(BASE, "PCKeyboardTouchBridgeV3.lua")
    output = [
        "-- PC Movement V3.2. Generated by tools/build_v32.py. Edit the source modules instead.",
        f"-- V3.1 preserved: {BASE}",
        f"-- V3.1 actual native stack: {CLASSIC}",
        f"-- V3.1 visual corrections: {UI}",
        "local modules={}",
    ]
    for name, source in sources.items():
        if name in {"bridge", "posture"}:
            output += [f"modules.{name}=(function()", source.rstrip(), "end)()"]
        else:
            output += [f"modules.{name}=function(...)", source.rstrip(), "end"]
    output += ["local start=(function()", local_source("Session").rstrip(), "end)()", "return start(modules)", ""]
    return "\n".join(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = render()
    if args.check:
        if OUTPUT.read_text() != result:
            raise SystemExit("Bundle stale. Run python3 tools/build_v32.py.")
    else:
        OUTPUT.write_text(result)
