--[[GLOBAL.setmetatable(env, { __index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end })

local CelestialEngine = require("worldgen/celestial_engine")
local CelestialIslands = require("worldgen/celestial_islands")

CelestialIslands.Init(env)
CelestialEngine.Init(env, CelestialIslands.CustomTasks, CelestialIslands.VoidTaskPrefixes)]]

GLOBAL.setmetatable(env, {
    __index = function(t, k)
        return GLOBAL.rawget(GLOBAL, k)
    end,
})

local CelestialEngine = require("map/celestial_engine")
if CelestialEngine and CelestialEngine.Init then
    CelestialEngine.Init(env)
end