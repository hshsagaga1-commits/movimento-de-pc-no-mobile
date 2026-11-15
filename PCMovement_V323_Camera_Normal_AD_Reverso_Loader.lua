-- PC Movement V3.2.3 / Normal camera / NO Grid Assist
-- Better A/D continuity + reverse-bhop input (experimental, not tested on iPhone).
local URL="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/refs/heads/feature/pc-movement-v323-normal-camera-ad-reverse-bhop-20261115/PC_Movement_V32.lua"
local env=getgenv()
if env.PCMovementV32 then
    if env.PCMovementV32.Version=="3.2.3-no-assist-normal-camera-ad-reverse-bhop" then
        return env.PCMovementV32
    end
    warn("[PC Movement V3.2.3] Another build is running; rejoin first.")
    return
end
local ok,source=pcall(function() return game:HttpGet(URL,true) end)
if not ok or type(source)~="string" then
    warn("[PC Movement V3.2.3] Download failed: "..tostring(source))
    return
end
local compile,message=loadstring(source)
if not compile then
    warn("[PC Movement V3.2.3] Compile error: "..tostring(message))
    return
end
local success,result=pcall(compile)
if not success then warn("[PC Movement V3.2.3] Startup error: "..tostring(result)) end
return success and result or nil
