-- Diagnostico temporario com painel de toque; independente da V3.1 e do macro.
local HttpService=game:GetService("HttpService")
local pg=game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local env=getgenv()
local previous=pg:FindFirstChild("PCMovementV31ProbeLoading")
if previous then previous:Destroy() end
local token={}
env.__PCMovementV31MacroMobileLoadToken=token
local loading=Instance.new("ScreenGui")
loading.Name="PCMovementV31ProbeLoading"
loading.ResetOnSpawn=false
loading.IgnoreGuiInset=false
loading.DisplayOrder=900
loading.Parent=pg
local label=Instance.new("TextLabel")
label.Size=UDim2.fromOffset(164,28)
label.Position=UDim2.new(1,-174,0,68)
label.BackgroundColor3=Color3.fromRGB(21,30,43)
label.TextColor3=Color3.new(1,1,1)
label.TextSize=12
label.Text="DIAGNÓSTICO: CARREGANDO..."
label.Active=false
label.Parent=loading
local root="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-movement-v31-macro-probe-export-ios-20261102/"
local function fetch(name)
    local source=game:HttpGet(root..name.."?_cb="..HttpService:GenerateGUID(false),true)
    if env.__PCMovementV31MacroMobileLoadToken~=token then error("load superseded") end
    local chunk,err=loadstring(source)
    if not chunk then error(err) end
    return chunk()
end
local installed
local ok,err=pcall(function()
    installed=fetch("PCMovementV31MacroConflictProbe.lua")
    fetch("PCMovementV31MacroProbeMobileUI.lua")
end)
loading:Destroy()
if env.__PCMovementV31MacroMobileLoadToken==token then env.__PCMovementV31MacroMobileLoadToken=nil end
if not ok then
    if installed and type(installed.Stop)=="function" and env.PCMovementV31MacroProbe==installed then
        installed.Stop()
    end
    error(err)
end
