-- Pure input policy. No Roblox services, physics writes or animation assumptions.
local Core = {}
local KEY_ORDER = {"W", "A", "S", "D", "Space"}

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Core.chord(keys)
    local names = {}
    for _, name in ipairs(KEY_ORDER) do
        if keys[name] then names[#names + 1] = name end
    end
    return #names > 0 and table.concat(names, "+") or "-"
end

function Core.new(config)
    config = config or {}
    local self = {engaged=false, lastAir=-math.huge, lastGrid=-math.huge}
    function self:step(input, observed, now)
        local air = observed.grounded == false
        local valid = observed.alive == true and not observed.blocked
        if air and valid then self.lastAir = now end
        if observed.gridContact then self.lastGrid = now end
        local chain = valid and observed.grounded == true and observed.jumpIntent == true
            and now - self.lastAir <= 0.10
        local reverse = air and (observed.horizontalSpeed or 0) >= 1
            and (observed.forwardDot or 0) < -0.15
        local flags = {
            STANDING_GROUNDED=valid and observed.grounded == true and observed.crouched ~= true,
            CROUCH_GROUNDED=valid and observed.grounded == true and observed.crouched == true,
            AIRBORNE=valid and air,
            BHOP_AIRBORNE=valid and air and (observed.crouched == true or observed.jumpIntent == true),
            REVERSE_BHOP=valid and reverse,
            EMOTE_MOVEMENT=valid and observed.emote == true,
            GRID_CONTACT=valid and observed.gridContact == true,
            GRID_AIRBORNE=valid and air and now - self.lastGrid <= 0.18,
            LANDING_BUFFER=chain,
        }
        local lateral = air or observed.crouched == true or observed.emote == true
            or observed.gridContact == true or chain
        local primary = "STANDING_GROUNDED"
        for _, name in ipairs({"CROUCH_GROUNDED", "AIRBORNE", "BHOP_AIRBORNE",
            "REVERSE_BHOP", "EMOTE_MOVEMENT", "GRID_AIRBORNE", "GRID_CONTACT"}) do
            if flags[name] then primary = name end
        end
        if not valid then primary = "SUSPENDED" end

        local x = finite(input.x) and input.x or 0
        local z = finite(input.z) and input.z or 0
        local scale=math.max(1,math.sqrt(x*x+z*z))
        x,z=x/scale,z/scale
        local radius = math.sqrt(x*x + z*z)
        local threshold = self.engaged and 0.18 or 0.30
        self.engaged = valid and input.active == true and radius >= threshold
        local keys = {}
        if self.engaged then
            local side = x < 0 and "A" or "D"
            if config.SwapAD then side = side == "A" and "D" or "A" end
            if lateral then
                -- Physical keyboard directions remain camera-relative even in reverse.
                -- A centered thumb does not create W or synthetic forward momentum.
                if math.abs(x) >= 0.08 then keys[side] = true end
            elseif z > 0 and z >= math.abs(x) * 0.45 then
                keys.S = true
            else
                keys.W = true
                if math.abs(x) > math.max(0.08, math.max(0,-z) * 0.34) then
                    keys[side] = true
                end
            end
        end
        return {keys=keys, flags=flags, primary=primary, lateralOnly=lateral,
            intensity=math.min(1,radius), x=x, z=z}
    end
    return self
end

function Core.keys(send)
    local self = {pressed={}, events=0, failures=0}
    for _, name in ipairs(KEY_ORDER) do self.pressed[name] = false end
    local function change(name, down)
        local ok, accepted = pcall(send, name, down)
        if ok and accepted == true then
            self.pressed[name] = down
            self.events = self.events + 1
            return true
        end
        self.failures = self.failures + 1
        return false
    end
    function self:apply(desired)
        -- Remove obsolete longitudinal keys before entering a lateral-only mode.
        for _, name in ipairs({"W", "S"}) do
            if self.pressed[name] and not desired[name] then change(name,false) end
        end
        -- An A/D swap is one synchronous batch. Never queue a W+A+D sweep,
        -- insert a wait, or retain an intermediate chord for a rendered frame.
        for _, name in ipairs(KEY_ORDER) do
            if desired[name] and not self.pressed[name] then change(name,true) end
        end
        for _, name in ipairs({"A", "D", "Space"}) do
            if self.pressed[name] and not desired[name] then change(name,false) end
        end
        -- Failed releases remain pressed in the ledger until a later successful retry.
        return Core.chord(self.pressed)
    end
    return self
end

function Core.jump(config)
    config = config or {}
    local self = {held=false, pulses=0, pendingUntil=-math.huge,
        spaceUntil=-math.huge, lastPulse=-math.huge, lastIntent=-math.huge,
        manual=false, spentGround=false, lastReason="none"}
    function self:request(now)
        self.pendingUntil = now + 0.20
        self.lastIntent = now
        self.manual = true
    end
    function self:setHeld(held, now)
        if held and not self.held then self:request(now) end
        self.held = held == true
    end
    function self:hasIntent(now)
        return self.held or now <= self.pendingUntil
    end
    function self:cancel()
        self.held = false
        self.manual = false
        self.pendingUntil = -math.huge
        self.spaceUntil = -math.huge
        self.spentGround = false
    end
    function self:step(now, observed)
        if not observed.alive or observed.blocked then
            self:cancel()
            return false, "suspended"
        end
        if observed.grounded == false then self.spentGround = false end
        if now > self.pendingUntil then self.manual = false end
        local canPulse = observed.canJump ~= false and now - self.lastPulse >= 0.11
        local reason
        if canPulse and self.manual then
            reason = "manual"
        elseif canPulse and observed.grounded == true and not self.spentGround
            and self:hasIntent(now) then
            reason = observed.gridContact and config.ContactJump ~= false
                and "grid_contact" or "landing_buffer"
        end
        if reason then
            self.spaceUntil = now + 0.055
            self.lastPulse = now
            self.lastReason = reason
            self.manual = false
            self.pulses = self.pulses + 1
            if observed.grounded then self.spentGround = true end
        end
        return now < self.spaceUntil, reason
    end
    return self
end

function Core.log(capacity)
    local self = {enabled=false, size=0, next=1, entries={}, capacity=capacity or 180}
    function self:add(entry)
        if not self.enabled then return end
        self.entries[self.next] = entry
        self.next = self.next % self.capacity + 1
        self.size = math.min(self.capacity,self.size+1)
    end
    function self:read()
        local out = {}
        local start = self.size == self.capacity and self.next or 1
        for offset=0,self.size-1 do
            out[#out+1] = self.entries[(start+offset-1)%self.capacity+1]
        end
        return out
    end
    return self
end

return Core
