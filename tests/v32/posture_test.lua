local F=dofile("tests/v31-preserved/RobloxFixture.lua")
local E=dofile("tests/v31-preserved/Environment.lua")
local e=dofile("tests/v32/Fixture.lua")(F,E)
local low,source,changes
changes=0
local stop=factory("v32/Posture.lua")(function(value,signal)
    low,source=value,signal
    changes+=1
end)
assert(not low and source=="unknown")
e.char:SetAttribute("Crouching",true)
assert(low and source=="crouch:flag")
e.hum:SetAttribute("Emoting",true)
e.char:SetAttribute("Crouching",false)
assert(low and source=="emote:flag")
e.hum:SetAttribute("Emoting",false)
assert(not low and source=="standing:flag")

e.char:SetAttribute("Crouching",nil)
e.hum:SetAttribute("Emoting",nil)
local controls=Instance.new("Folder")
controls.Name="ControlsGui";controls.Parent=e.pg
local frame=Instance.new("Frame")
frame.Name="PCFrame";frame.Parent=controls
local stand=Instance.new("TextButton")
stand.Name="Stand";stand.Visible=false;stand.Parent=frame
assert(not low and source=="standing:hud")
stand.Visible=true
assert(low and source=="crouch:hud")
stand.Parent=nil
assert(not low and source=="unknown")
local flag=Instance.new("BoolValue")
flag.Name="IsCrouched";flag.Value=true;flag.Parent=e.hum
assert(low and source=="crouch:flag")
flag.Value=false
assert(not low)
flag.Parent=nil
assert(source=="unknown")

local scripts=Instance.new("Folder");scripts.Name="PlayerScripts";scripts.Parent=e.player
local events=Instance.new("Folder");events.Name="Events";events.Parent=scripts
local keybind=Instance.new("BindableEvent");keybind.Name="KeybindUsed";keybind.Event=F.signal();keybind.Parent=events
keybind.Event:fire("Jump",true)
assert(not low)
keybind.Event:fire("Crouch",true)
assert(low and source=="crouch:keybind")
keybind.Event:fire("Crouch",false)
assert(not low)
keybind.Event:fire("Crouch",true)
keybind.Parent=nil
assert(not low and source=="unknown","removed Legacy event left stale crouch state")

local animator=Instance.new("Animator")
animator.AnimationPlayed=F.signal()
animator.GetPlayingAnimationTracks=function() return {} end
animator.Parent=e.hum
local function track(name,animationName)
    local item=Instance.new("AnimationTrack")
    item.Name=name
    item.Animation={Name=animationName or "Animation"}
    item.Stopped=F.signal()
    item.IsPlaying=true
    item.Length=8
    item.Looped=true
    return item
end
local walk=track("ActionLongLoop","Sprint")
animator.AnimationPlayed:fire(walk)
assert(not low,"ordinary action track misclassified")
local emote=track("Animation","Emote Guitar")
local crouch=track("CrouchWalk")
animator.AnimationPlayed:fire(emote)
assert(low and source=="emote:animation")
animator.AnimationPlayed:fire(crouch)
emote.Stopped:fire()
assert(low and source=="crouch:animation")
crouch.Destroying:fire()
assert(not low and source=="unknown")
animator.AnimationPlayed:fire(emote)
e.hum:SetAttribute("Emoting",false)
assert(not low,"known false flag must override a stale track")
e.hum:SetAttribute("Emoting",nil)
assert(low)
e.player.CharacterRemoving:fire(e.char)
assert(not low)
local previous=changes
e.char:SetAttribute("Crouching",true)
emote.Stopped:fire()
assert(changes==previous,"old character observers kept running")
local replacement=Instance.new("Model")
e.player.Character=replacement
e.player.CharacterAdded:fire(replacement)
assert(not low)
local newHum=Instance.new("Humanoid")
newHum:SetAttribute("IsEmoting",true)
newHum.Parent=replacement
assert(low and source=="emote:flag","late humanoid was ignored")
stop()
previous=changes
newHum:SetAttribute("IsEmoting",false)
assert(changes==previous,"stop left a state listener")
print("PASS posture: flags, Legacy HUD, named animation, fallback, late humanoid, respawn and cleanup")
