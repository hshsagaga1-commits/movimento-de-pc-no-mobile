-- Observation only: broader discovery is never a collider, force or movement motor.
local Grid = {}
local WORDS = {fence=true,fences=true,railing=true,railings=true,rail=true,
    handrail=true,grate=true,grid=true,grade=true,lattice=true,balustrade=true}
local function named(instance)
    local text = (instance.Name or ""):gsub("(%l)(%u)","%1 %2"):lower()
    for token in text:gmatch("%a+") do if WORDS[token] then return true end end
    return false
end
local function isBodyOfCharacter(part)
    local node=part.Parent
    for _=1,4 do
        if not node then break end
        if node.FindFirstChildOfClass and node:FindFirstChildOfClass("Humanoid") then return true end
        node=node.Parent
    end
    return false
end
local function broadFloor(part)
    local s=part.Size
    return s.Y <= 1 and s.X > 3 and s.Z > 3
end
local function barKind(part)
    if part.ClassName ~= "Part" then return nil end
    local s=part.Size
    local small,large=math.min(s.X,s.Z),math.max(s.X,s.Z)
    if s.Y >= 1.25 and small <= 0.65 and large <= 1 and s.Y >= large*2.5 then
        return "upright"
    end
    if s.Y <= 0.65 and small <= 0.65 and large >= 2.5 then return "horizontal" end
    return nil
end
local function parallel(a,b,kind)
    local av=a.CFrame and (kind=="upright" and a.CFrame.UpVector or
        (a.Size.X>a.Size.Z and a.CFrame.RightVector or a.CFrame.LookVector))
    local bv=b.CFrame and (kind=="upright" and b.CFrame.UpVector or
        (b.Size.X>b.Size.Z and b.CFrame.RightVector or b.CFrame.LookVector))
    if not av or not bv then return false end
    return math.abs(av.X*bv.X+av.Y*bv.Y+av.Z*bv.Z) > 0.94
end
local function repeatedRow(anchor,bars)
    local a,kind=anchor.part,anchor.kind
    local axis=kind=="upright" and a.CFrame.UpVector or
        (a.Size.X>a.Size.Z and a.CFrame.RightVector or a.CFrame.LookVector)
    local basis,best
    for _,candidate in ipairs(bars) do
        local b=candidate.part
        if b~=a and kind==candidate.kind and b.Parent==a.Parent and parallel(a,b,kind) then
            local x,y,z=b.Position.X-a.Position.X,b.Position.Y-a.Position.Y,b.Position.Z-a.Position.Z
            local squared=x*x+y*y+z*z
            if squared>=0.0225 and squared<=36 and math.abs(x*axis.X+y*axis.Y+z*axis.Z)<=0.75
                and (not best or squared<best) then
                local length=math.sqrt(squared)
                basis={x/length,y/length,z/length};best=squared
            end
        end
    end
    if not basis then return false end
    local projections={0}
    for _,candidate in ipairs(bars) do
        local b=candidate.part
        if b~=a and kind==candidate.kind and b.Parent==a.Parent and parallel(a,b,kind) then
            local x,y,z=b.Position.X-a.Position.X,b.Position.Y-a.Position.Y,b.Position.Z-a.Position.Z
            local projection=x*basis[1]+y*basis[2]+z*basis[3]
            local perpendicular=math.max(0,x*x+y*y+z*z-projection*projection)
            if math.abs(projection)<=6 and perpendicular<=0.0625 then
                local distinct=true
                for _,value in ipairs(projections) do
                    if math.abs(projection-value)<0.15 then distinct=false break end
                end
                if distinct then projections[#projections+1]=projection end
                if #projections>=3 then return true end
            end
        end
    end
    return false
end

function Grid.new(services,config)
    config=config or {}
    local self={character=nil,root=nil,bodies={},nearby={},inferred={},
        lastBroad=-math.huge,lastNarrow=-math.huge,queries=0,narrowReads=0,
        snapshot={contact=false,nearby=false,evidence="none"},stopped=false}
    local world=services.Workspace
    local overlap=OverlapParams.new()
    overlap.FilterType=Enum.RaycastFilterType.Exclude
    overlap.MaxParts=48
    pcall(function() overlap.RespectCanCollide=true end)
    local groups={}
    local function valid(part)
        return part and part.Parent and part.IsA and part:IsA("BasePart")
            and part.CanCollide and not isBodyOfCharacter(part)
    end
    local function label(part)
        if not valid(part) or broadFloor(part) or part:IsA("TrussPart") then return nil end
        local node=part
        for _=1,3 do
            if not node or node==world then break end
            if services.CollectionService then
                for _,tag in ipairs(config.GridTags or {"Fence","Railing","Grid"}) do
                    if services.CollectionService:HasTag(node,tag) then return "tag:"..tag end
                end
            end
            if named(node) then return "name" end
            node=node.Parent
        end
        if config.AllowInferredGrids ~= false and self.inferred[part] then return "repeated-bars" end
        return nil
    end
    local function collides(body,part,now)
        if not body.CanCollide or not part.CanCollide then return false end
        local a,b=body.CollisionGroup,part.CollisionGroup
        local key=a.."\0"..b
        local entry=groups[key]
        if entry and now-entry.at<0.5 then return entry.value end
        local ok,value=pcall(function()
            return services.PhysicsService:CollisionGroupsAreCollidable(a,b)
        end)
        local allowed=ok and value==true
        groups[key]={at=now,value=allowed}
        return allowed
    end
    function self:Bind(character,humanoid,root)
        self.character=character
        self.root=root
        self.bodies={}
        if character then
            for _,part in ipairs(character:GetChildren()) do
                if #self.bodies>=24 then break end
                if part.IsA and part:IsA("BasePart") then self.bodies[#self.bodies+1]=part end
            end
        end
        overlap.FilterDescendantsInstances=character and {character} or {}
        self.inferred={}
        self.nearby={}
        groups={}
        self.lastBroad=-math.huge
        self.lastNarrow=-math.huge
        self.snapshot={contact=false,nearby=false,evidence="none"}
    end
    function self:ContactNow(now)
        local state={contact=false,nearby=next(self.nearby)~=nil,evidence="none",at=now}
        if self.stopped or not self.root or not self.character then return state end
        local checked,bodyReads=0,0
        for _,body in ipairs(self.bodies) do
            if body.Parent==self.character and body.CanCollide then
                bodyReads=bodyReads+1
                if bodyReads>8 then break end
                self.narrowReads=self.narrowReads+1
                local ok,parts=pcall(function() return body:GetTouchingParts() end)
                if ok then
                    for _,part in ipairs(parts) do
                        checked=checked+1
                        if checked>48 then return state end
                        local evidence=label(part)
                        if evidence and collides(body,part,now) then
                            state.contact=true
                            state.part=part
                            state.body=body
                            state.evidence=evidence
                            return state
                        end
                    end
                end
            end
        end
        return state
    end
    function self:Sample(now,active)
        if self.stopped or not self.root or not active then
            self.snapshot={contact=false,nearby=false,evidence="none",at=now}
            return self.snapshot
        end
        if now-self.lastBroad>=1/12 then
            self.lastBroad=now
            self.queries=self.queries+1
            overlap.CollisionGroup=self.root.CollisionGroup
            local ok,parts=pcall(function()
                return world:GetPartBoundsInBox(self.root.CFrame,
                    Vector3.new(8,math.max(7,self.root.Size.Y+4),8),overlap)
            end)
            self.nearby={}
            self.inferred={}
            if ok then
                -- Only local candidates are compared, capped at 48; no map traversal.
                local bars={}
                for i,part in ipairs(parts) do
                    if i>48 then break end
                    if valid(part) then
                        local kind=barKind(part)
                        if kind then bars[#bars+1]={part=part,kind=kind} end
                    end
                end
                for _,a in ipairs(bars) do
                    if repeatedRow(a,bars) then self.inferred[a.part]=true end
                end
                for i,part in ipairs(parts) do
                    if i>48 then break end
                    local evidence=label(part)
                    if evidence then self.nearby[part]=evidence end
                end
            end
        end
        if now-self.lastNarrow>=1/20 then
            self.lastNarrow=now
            self.snapshot=self:ContactNow(now)
        end
        self.snapshot.nearby=next(self.nearby)~=nil
        return self.snapshot
    end
    function self:Stop()
        self.stopped=true
        self:Bind(nil,nil,nil)
    end
    return self
end
return Grid
