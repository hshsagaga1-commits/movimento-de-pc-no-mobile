-- Evade Scroll Jump 2X | Independente | Delta iOS
-- Um toque no JumpButton -> pulo nativo + segunda tentativa apos 50 ms
-- Nao modifica joystick, camera, movimento ou sensibilidade.
-- A segunda tentativa pode ser ignorada pelo jogo se o personagem estiver no ar.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local INTERVAL = 0.05
local env = (type(getgenv) == "function" and getgenv()) or _G

if env.EvadeScrollJump2X and type(env.EvadeScrollJump2X.stop) == "function" then
    env.EvadeScrollJump2X.stop()
end

local active = true
local connections = {}
local registered = setmetatable({}, { __mode = "k" })

local function bindJumpButton(button)
    if not button:IsA("GuiButton") or button.Name ~= "JumpButton" or registered[button] then
        return
    end

    registered[button] = true
    local lastPress = -math.huge

    local connection = button.MouseButton1Down:Connect(function()
        if not active then return end

        local now = os.clock()
        if now - lastPress < 0.10 then return end
        lastPress = now

        -- O primeiro salto continua pelo controle padrao do Roblox.
        task.delay(INTERVAL, function()
            if not active then return end
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 then return end

            -- Segunda tentativa de comando de pulo.
            humanoid.Jump = false
            RunService.Heartbeat:Wait()
            if active and humanoid.Parent and humanoid.Health > 0 then
                humanoid.Jump = true
            end
        end)
    end)
    table.insert(connections, connection)
end

for _, descendant in ipairs(playerGui:GetDescendants()) do
    bindJumpButton(descendant)
end

table.insert(connections, playerGui.DescendantAdded:Connect(bindJumpButton))

env.EvadeScrollJump2X = {
    stop = function()
        active = false
        for _, connection in ipairs(connections) do
            connection:Disconnect()
        end
        table.clear(connections)
    end
}

print("[Evade Scroll Jump 2X] Ativado: 50 ms, sem alterar joystick/camera")
