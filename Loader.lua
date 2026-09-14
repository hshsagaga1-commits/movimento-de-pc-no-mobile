local HttpService=game:GetService("HttpService")
local url="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV26_NativeShiftLockMousePath.lua"
local source=game:HttpGet(url.."?_cb="..HttpService:GenerateGUID(false),true)
local chunk,err=loadstring(source)
if not chunk then error(err) end
local result=chunk()

-- If this executor refuses a table-backed synthetic MouseMovement object, immediately
-- stop the bridge so Roblox's original touch camera resumes instead of leaving camera pan suppressed.
task.spawn(function()
    for _=1,150 do
        if getgenv().PCInputBridgeMode=="native-callback-proxy-failed" then
            getgenv().PCNativeMousePathEnabled=false
            getgenv().PCInputBridgeMode="shift-lock-only-proxy-safe-fallback"
            getgenv().PCInputBridgeDiscovery="proxy-rejected-touch-restored"
            warn("[V26] native mouse proxy rejected; original touch rotation restored safely")
            return
        end
        task.wait(0.1)
    end
end)

return result
