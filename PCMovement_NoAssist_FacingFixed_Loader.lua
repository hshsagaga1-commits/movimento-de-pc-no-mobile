-- PC Movement V3.2.2 - NO Assist + Independent Facing Fix
-- Loads only the experimental branch; stable branches are untouched.
local URL="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/refs/heads/feature/pc-movement-v322-no-assist-independent-facing-fix-20261115/PC_Movement_V32.lua"
local env=getgenv()
if env.PCMovementV32 and env.PCMovementV32.Version~="3.2.2-no-assist-facing-fixed" then
    warn("[PC Movement] Another build is running. Rejoin before testing this build.")
    return
end
local ok,code=pcall(function() return game:HttpGet(URL,true) end)
if not ok or type(code)~="string" then
    warn("[PC Movement] Could not download script: "..tostring(code))
    return
end
local compile,err=loadstring(code)
if not compile then warn("[PC Movement] Compile failed: "..tostring(err)) return end
local success,result=pcall(compile)
if not success then warn("[PC Movement] Start failed: "..tostring(result)) end
