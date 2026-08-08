local url = "https://cdn.jsdelivr.net/gh/nott3ti/t3ti-haze@main/t3ti_haze_bundle.lua"
local okGet, src = pcall(function()
    return game:HttpGet(url)
end)
if not okGet or type(src) ~= "string" or #src < 100 then
    error("[T3ti] HttpGet failed: " .. tostring(src))
end
local loader = loadstring or load
local fn, err = loader(src)
if not fn then
    error("[T3ti] compile failed: " .. tostring(err))
end
fn()
