-- OverhaulCameraServiceX9Loader.lua
local HttpService=game:GetService("HttpService")
local url="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/camera-x9-overhaul-legacy/OverhaulCameraServiceX9.lua?_cb="
    ..HttpService:GenerateGUID(false)
return loadstring(game:HttpGet(url,true))()
