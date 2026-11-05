-- Read game-owned signals. The bridge never toggles crouch or fires an emote.
local EVADE_GAME_ID=3647333358
local FLAGS={
    Crouching="crouch",IsCrouching="crouch",Crouched="crouch",IsCrouched="crouch",
    Emoting="emote",IsEmoting="emote",EmotePlaying="emote",PlayingEmote="emote",
    DoingEmote="emote",IsDancing="emote",Dancing="emote",IsTaunting="emote",Taunting="emote",
}
local EMOTE_NAMES={
    ["broom of dom"]=true,["rockin' stride"]=true,["rockin stride"]=true,["zombie stride"]=true,
}

local function animationKind(name)
    name=string.lower((string.gsub(name,"(%l)(%u)","%1 %2")))
    if name=="crouch" or name=="crouching" or name=="crouch idle" or name=="crouch walk" or name=="crouch move" then
        return "crouch"
    end
    if name=="emote" or name=="dance" or name=="taunt" or EMOTE_NAMES[name]
        or string.match(name,"^emote[%s_:%-]") then
        return "emote"
    end
end

local function disconnect(connections)
    for _,connection in ipairs(connections) do connection:Disconnect() end
    table.clear(connections)
end

return function(onChange)
    local player=game:GetService("Players").LocalPlayer
    local gui=assert(player:FindFirstChild("PlayerGui"))
    local session,charSignals,humSignals,animSignals,hudSignals={},{},{},{},{}
    local charFlags,humFlags,tracks={},{},{}
    local character,humanoid,animator,stand
    local keybind,legacyHeld,keybindConnection
    local crouchTracks,emoteTracks=0,0
    local lastSource
    local active=true

    local function readFlag(kind)
        local seen=false
        for name,category in pairs(FLAGS) do
            if category==kind then
                local c=character and character:GetAttribute(name)
                local h=humanoid and humanoid:GetAttribute(name)
                local cValue=charFlags[name]
                local hValue=humFlags[name]
                local cv=cValue and cValue.object.Value
                local hv=hValue and hValue.object.Value
                if c==true or c==1 or h==true or h==1 or cv==true or hv==true then return true end
                if c==false or c==0 or h==false or h==0 or cv==false or hv==false then seen=true end
            end
        end
        if seen then return false end
    end

    local function publish()
        if not active then return end
        local source="unknown"
        if character then
            local crouched=readFlag("crouch")
            local emoting=readFlag("emote")
            if crouched then source="crouch:flag"
            elseif emoting then source="emote:flag"
            elseif crouched==nil and stand and stand.Visible then source="crouch:hud"
            elseif crouched==nil and crouchTracks>0 then source="crouch:animation"
            elseif crouched==nil and legacyHeld==true then source="crouch:keybind"
            elseif emoting==nil and emoteTracks>0 then source="emote:animation"
            elseif crouched==false or emoting==false then source="standing:flag"
            elseif stand then source="standing:hud"
            end
        end
        if source~=lastSource then
            lastSource=source
            onChange(source:sub(1,7)=="crouch:" or source:sub(1,6)=="emote:",source)
        end
    end

    local function trackAnimation(track)
        if tracks[track] then return end
        local kind=animationKind(track.Name)
        if not kind and track.Animation then kind=animationKind(track.Animation.Name) end
        if not kind then return end
        if kind=="crouch" then crouchTracks+=1 else emoteTracks+=1 end
        local connections={}
        tracks[track]=connections
        local function ended()
            if tracks[track]~=connections then return end
            tracks[track]=nil
            disconnect(connections)
            if kind=="crouch" then crouchTracks-=1 else emoteTracks-=1 end
            publish()
        end
        connections[1]=track.Stopped:Connect(ended)
        connections[2]=track.Destroying:Connect(ended)
    end

    local function bindAnimator(value)
        if animator==value then return end
        disconnect(animSignals)
        for _,connections in pairs(tracks) do disconnect(connections) end
        table.clear(tracks)
        crouchTracks,emoteTracks=0,0
        animator=value
        if animator then
            animSignals[1]=animator.AnimationPlayed:Connect(function(track)
                trackAnimation(track)
                publish()
            end)
            local ok,playing=pcall(animator.GetPlayingAnimationTracks,animator)
            if ok then
                for _,track in ipairs(playing) do
                    if track.IsPlaying then trackAnimation(track) end
                end
            end
        end
    end

    local function detachFlags(values)
        for _,entry in pairs(values) do entry.connection:Disconnect() end
        table.clear(values)
    end

    local function bindFlags(owner,connections,values,onChild)
        if not owner then return end
        local function addFlag(child)
            if FLAGS[child.Name] and child:IsA("BoolValue") and not values[child.Name] then
                values[child.Name]={object=child,connection=child:GetPropertyChangedSignal("Value"):Connect(publish)}
            end
        end
        connections[#connections+1]=owner.AttributeChanged:Connect(function(name)
            if FLAGS[name] then publish() end
        end)
        connections[#connections+1]=owner.ChildAdded:Connect(function(child)
            addFlag(child)
            if onChild(child,false) or FLAGS[child.Name] then publish() end
        end)
        connections[#connections+1]=owner.ChildRemoved:Connect(function(child)
            local entry=values[child.Name]
            if entry and entry.object==child then
                entry.connection:Disconnect()
                values[child.Name]=nil
            end
            if onChild(child,true) or entry then publish() end
        end)
        for _,child in ipairs(owner:GetChildren()) do addFlag(child) end
    end

    local function bindHumanoid(value)
        if humanoid==value then return end
        disconnect(humSignals)
        detachFlags(humFlags)
        humanoid=value
        bindAnimator(value and value:FindFirstChildOfClass("Animator"))
        bindFlags(value,humSignals,humFlags,function(child,removing)
            if child:IsA("Animator") then
                if not removing and not animator then bindAnimator(child)
                elseif removing and child==animator then bindAnimator(nil) end
                return true
            end
            return false
        end)
    end

    local function bindCharacter(value)
        disconnect(charSignals)
        detachFlags(charFlags)
        character=value
        legacyHeld=nil
        bindHumanoid(value and value:FindFirstChildOfClass("Humanoid"))
        bindFlags(value,charSignals,charFlags,function(child,removing)
            if child:IsA("Humanoid") then
                if not removing and not humanoid then bindHumanoid(child)
                elseif removing and child==humanoid then bindHumanoid(nil) end
                return true
            end
            return false
        end)
        publish()
    end

    local function refreshHud(excluded)
        local controls=gui:FindFirstChild("ControlsGui",true)
        local frame=controls and controls:FindFirstChild("PCFrame",true)
        local value=frame and frame:FindFirstChild("Stand",true)
        -- DescendantRemoving can fire before the old hierarchy is unlinked.
        if excluded and value then
            local node=value
            while node do
                if node==excluded then value=nil break end
                node=node.Parent
            end
        end
        if value and not value:IsA("GuiObject") then value=nil end
        if stand==value then return end
        disconnect(hudSignals)
        stand=value
        if stand then hudSignals[1]=stand:GetPropertyChangedSignal("Visible"):Connect(publish) end
        publish()
    end

    local function refreshKeybind(excluded)
        local scripts=player:FindFirstChild("PlayerScripts")
        local events=scripts and scripts:FindFirstChild("Events")
        local value=events and events:FindFirstChild("KeybindUsed")
        if value and (excluded==scripts or excluded==events or excluded==value or not value:IsA("BindableEvent")) then
            value=nil
        end
        if keybind==value then return end
        if keybindConnection then keybindConnection:Disconnect() keybindConnection=nil end
        keybind,legacyHeld=value,nil
        if keybind then
            keybindConnection=keybind.Event:Connect(function(action,held)
                if active and character and action=="Crouch" and type(held)=="boolean" then
                    legacyHeld=held
                    publish()
                end
            end)
        end
        publish()
    end

    if game.GameId==EVADE_GAME_ID then
        local function isKeybindNode(node)
            return node.Name=="PlayerScripts" or node.Name=="Events" or node.Name=="KeybindUsed"
        end
        session[#session+1]=player.DescendantAdded:Connect(function(node)
            if isKeybindNode(node) then refreshKeybind() end
        end)
        session[#session+1]=player.DescendantRemoving:Connect(function(node)
            if isKeybindNode(node) then refreshKeybind(node) end
        end)
        refreshKeybind()
        local function isHudNode(node)
            return node.Name=="ControlsGui" or node.Name=="PCFrame" or node.Name=="Stand"
        end
        session[#session+1]=gui.DescendantAdded:Connect(function(node)
            if isHudNode(node) then refreshHud() end
        end)
        session[#session+1]=gui.DescendantRemoving:Connect(function(node)
            if isHudNode(node) then refreshHud(node) end
        end)
        refreshHud()
    end
    session[#session+1]=player.CharacterAdded:Connect(bindCharacter)
    session[#session+1]=player.CharacterRemoving:Connect(function(value)
        if character==value then bindCharacter(nil) end
    end)
    bindCharacter(player.Character)

    return function()
        if not active then return end
        active=false
        disconnect(session)
        disconnect(hudSignals)
        if keybindConnection then keybindConnection:Disconnect() keybindConnection=nil end
        keybind,stand=nil,nil
        bindCharacter(nil)
    end
end
