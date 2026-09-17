local HttpService=game:GetService("HttpService")
local ROOT="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/classic-wasd-experiment/"

local source=game:HttpGet(
    ROOT.."PCModeLockV5.lua?_cb="..HttpService:GenerateGUID(false),
    true
)

local function replaceOncePlain(text,needle,replacement,label)
    local first,last=text:find(needle,1,true)
    if not first then error("HUD-mobile PC lock patch failed: missing "..label) end
    if text:find(needle,last+1,true) then error("HUD-mobile PC lock patch failed: duplicate "..label) end
    return text:sub(1,first-1)..replacement..text:sub(last+1)
end

local function replaceExactCount(text,needle,replacement,expected,label)
    local count=0
    local cursor=1
    while true do
        local first,last=text:find(needle,cursor,true)
        if not first then break end
        count+=1
        text=text:sub(1,first-1)..replacement..text:sub(last+1)
        cursor=first+#replacement
    end
    if count~=expected then
        error(string.format("HUD-mobile PC lock patch failed: %s count %d ~= %d",label,count,expected))
    end
    return text
end

-- The facade is only needed during bootstrap so ControlModule reveals/selects
-- the keyboard module. After that, the SwitchToController lock keeps movement
-- on keyboard while the rest of the game sees the real mobile/touch device.
source=replaceOncePlain(
    source,
    "local facadeInstalled = false\nlocal switchLockInstalled = false",
    "local facadeInstalled = false\nlocal facadeActive = true\nlocal switchLockInstalled = false",
    "facade state"
)

source=replaceExactCount(
    source,
    "if lockEnabled and self == UserInputService and not callerIsExecutor() then",
    "if lockEnabled and facadeActive and self == UserInputService and not callerIsExecutor() then",
    2,
    "UserInputService facade guards"
)

source=replaceOncePlain(
    source,
    "end\n\nlocal oldStatus = playerGui:FindFirstChild(STATUS_GUI)",
    "end\n\n-- Bootstrap is over. From this point HUD/game scripts see real TouchEnabled,\n-- PreferredInput, GetLastInputType and platform values again. Movement stays\n-- keyboard-locked through SwitchToController + the render-step watcher.\nfacadeActive = false\n\nlocal oldStatus = playerGui:FindFirstChild(STATUS_GUI)",
    "post-bootstrap facade release"
)

source=replaceOncePlain(
    source,
    "facadeInstalled and \"ON\" or \"OFF\"",
    "(facadeInstalled and facadeActive) and \"BOOT\" or \"PASS\"",
    "status facade label"
)

source=replaceOncePlain(
    source,
    "facadeInstalled = facadeInstalled,\n            switchLockInstalled = switchLockInstalled,",
    "facadeInstalled = facadeInstalled,\n            facadeActive = facadeActive,\n            switchLockInstalled = switchLockInstalled,",
    "state facadeActive"
)

source=replaceOncePlain(
    source,
    "Version = \"5.0-input-facade-controlmodule-pc-lock\"",
    "Version = \"5.0-bootstrap-facade-mobile-hud-keyboard-lock\"",
    "version"
)

local chunk,loadError=loadstring(source)
if not chunk then error(loadError) end
return chunk()
