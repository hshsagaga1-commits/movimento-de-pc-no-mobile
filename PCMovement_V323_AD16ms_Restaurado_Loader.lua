-- PC Movement V3.2.3 / Restored original 16ms A-D turn / No Assist
-- Original camera, original left/right transition and reverse-hop experiment.
local URL="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/refs/heads/feature/pc-movement-v323-ad-sweep-restored-20261115/PC_Movement_V32.lua"
local env=getgenv()
if env.PCMovementV32 then
    if env.PCMovementV32.Version=="3.2.3-sweep-restored-no-assist" then
        return env.PCMovementV32
    end
    warn("[PC Movement] Rejoin Evade before switching builds.")
    return
end
local ok,source=pcall(function() return game:HttpGet(URL,true) end)
if not ok or type(source)~="string" then
    warn("[PC Movement] Download failed: "..tostring(source))
    return
end
local compile,message=loadstring(source)
if not compile then warn("[PC Movement] Compile failed: "..tostring(message)) return end
local success,result=pcall(compile)
if not success then warn("[PC Movement] Startup failed: "..tostring(result)) end
return success and result or nil
