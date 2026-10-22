-- Combined loader: PC movement/keyboard bridge + wall/edge Assist.
-- Keeps the existing modules and their order intact; loads both from this branch.
-- Use this single loader instead of running JoystickOnlyLoader and AssistOnlyLoader separately.
local HttpService=game:GetService("HttpService")
local Players=game:GetService("Players")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-camera-grid-v6/"

local function runModule(path)
    local source=game:HttpGet(ROOT..path.."?_cb="..HttpService:GenerateGUID(false),true)
    local chunk,err=loadstring(source)
    if not chunk then error("Failed to load "..path..": "..tostring(err)) end
    return chunk()
end

-- Start keyboard/joystick movement bridge first, so Assist can read the active chord.
runModule("PCModeLockV6.lua")
-- Then start wall/rail/edge assistance.
runModule("LegacyGridContactAssistV1.lua")

-- Explicit exclusion: this loader must never fetch, execute, modify, or repair the user's separate Evade/Legecy loader.
-- Excluded loader: https://raw.githubusercontent.com/StyearX/solasmotaryx/main/Evade/Legecy
-- Recovery below is restricted to PCKeyboardTouchBridgeV52Overlay, owned by Bloxtrap.
-- Bloxtrap-only UI recovery for Evade.
-- If the game's map/round transition destroys or partially rebuilds our own
-- movement overlay, wait for the UI to settle, then reload ONLY the movement
-- module. Never rerun LegacyGridContactAssistV1.lua or the excluded Evade/Legecy
-- loader. The recovery loop only looks for Bloxtrap-owned GUI objects.
local EVADE_GAME_ID=3647333358
local OVERLAY_NAME="PCKeyboardTouchBridgeV52Overlay"
local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local missingSince=nil
local lastRepairAt=-math.huge
local repairing=false

task.spawn(function()
    while true do
        task.wait(0.75)

        if game.GameId==EVADE_GAME_ID and not repairing then
            local overlay=playerGui:FindFirstChild(OVERLAY_NAME)
            local joystick=overlay and overlay:FindFirstChild("PCJoystick",true)
            local knob=joystick and joystick:FindFirstChild("Knob")
            local jumpButton=overlay and overlay:FindFirstChild("PCJump",true)
            local ready=overlay and overlay:IsA("ScreenGui")
                and joystick and knob and jumpButton

            if ready then
                missingSince=nil
            else
                missingSince=missingSince or os.clock()
                local missingLongEnough=os.clock()-missingSince>=1.25
                local cooldownPassed=os.clock()-lastRepairAt>=3.0

                if missingLongEnough and cooldownPassed then
                    repairing=true
                    lastRepairAt=os.clock()

                    local ok,err=pcall(function()
                        -- Repair only Bloxtrap's movement bridge + its own visuals.
                        runModule("PCModeLockV6.lua")
                    end)
                    if not ok then
                        warn("[Bloxtrap UI recovery] "..tostring(err))
                    end

                    task.wait(0.25)
                    repairing=false
                end
            end
        else
            missingSince=nil
        end
    end
end)
