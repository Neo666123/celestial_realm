local _G = rawget(_G, "GLOBAL") or _G
local rawget = _G.rawget
local WORLD_TILES = rawget(_G, "WORLD_TILES") or rawget(_G, "GROUND") or {}

local TileMap = {
    -- 基础地面映射
    ["IMPASSABLE"]        = rawget(WORLD_TILES, "IMPASSABLE") or 1,
    ["DIRT"]              = rawget(WORLD_TILES, "DIRT") or 2,
    ["SAVANNA"]           = rawget(WORLD_TILES, "SAVANNA") or 3,
    ["GRASS"]             = rawget(WORLD_TILES, "GRASS") or 4,
    ["FOREST"]            = rawget(WORLD_TILES, "FOREST") or 5,
    ["MARSH"]             = rawget(WORLD_TILES, "MARSH") or 6,
    ["ROCKY"]             = rawget(WORLD_TILES, "ROCKY") or 7,
    ["TILES"]             = rawget(WORLD_TILES, "TILES") or 10,
    ["CARPET"]            = rawget(WORLD_TILES, "CARPET") or 11,
    ["BRICK"]             = rawget(WORLD_TILES, "BRICK") or 13,

    -- 官方特种地皮
    ["METEOR"]            = rawget(WORLD_TILES, "METEOR") or 43,
    ["PEBBLEBEACH"]       = rawget(WORLD_TILES, "PEBBLEBEACH") or 41,
    ["SHELLBEACH"]        = rawget(WORLD_TILES, "SHELLBEACH") or 42,
    ["METEORCOAST_NOISE"] = rawget(WORLD_TILES, "METEORCOAST_NOISE") or 44,

    -- 自定义别名映射
    ["CC_METEOR"]         = rawget(WORLD_TILES, "SHELLBEACH") or 42,  -- 珍珠海滩
    ["CC_BLACKGOLD"]      = rawget(WORLD_TILES, "PEBBLEBEACH") or 41, -- 黑金卵石海滩
}

-- 统一解析地皮数字 ID
function TileMap.ResolveTile(tile_key)
    if not tile_key then return nil end
    local upper_key = string.upper(tile_key)
    return TileMap[upper_key] or rawget(WORLD_TILES, upper_key) or TileMap["IMPASSABLE"]
end

return TileMap