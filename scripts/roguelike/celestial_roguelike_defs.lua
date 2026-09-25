local rawget = rawget
local pairs = pairs
local ipairs = ipairs
local math = math
local table = table

local GLOBAL = rawget(_G, "GLOBAL") or _G
local WORLD_TILES = rawget(GLOBAL, "WORLD_TILES")
local TileGroupManager = rawget(GLOBAL, "TileGroupManager")
local TempTile_HandleTileChange = rawget(GLOBAL, "TempTile_HandleTileChange")
local SpawnPrefab = rawget(GLOBAL, "SpawnPrefab")
local TheWorld = rawget(GLOBAL, "TheWorld")

local defs = {}
local TILE_SIZE = 4

local RESOURCE_POOLS = {
    OUTER = {
        "grass",
        "sapling_moon",
        "rock_avocado_bush",
        "trap_starfish",
        "bullkelp_beachedroot",
    },
    MID = {
        "moonglass_rock",
        "rock_moon",
        "lunar_island_rocks",
        "moon_tree",
        "moon_fissure",
    },
    CORE = {
        "carrat_planted",
        "carrat",
        "fruitdragon",
        "moonspiderden",
    },
}

local Terraformer = Class(function(self, radius)
    self.radius = radius or 6
    self.min_c = -self.radius
    self.max_c = self.radius
    self.min_r = -self.radius
    self.max_r = self.radius
    self.grid = {}
end)

function Terraformer:Set(col, row, tile_id)
    local key = string.format("%d,%d", col, row)
    self.grid[key] = tile_id
end

function Terraformer:ApplyAtXZ(x, z)
    local map = TheWorld.Map
    local map_w, map_h = map:GetWorldSize()
    local tile_x, tile_y = map:GetTileCoordsAtPoint(x, 0, z)

    for r = self.min_r, self.max_r do
        for c = self.min_c, self.max_c do
            local key = string.format("%d,%d", c, r)
            local target_tile = self.grid[key] or WORLD_TILES.IMPASSABLE
            local tx = tile_x + c
            local ty = tile_y + r

            if tx >= 0 and tx < map_w and ty >= 0 and ty < map_h then
                local old_tile = map:GetTile(tx, ty)
                if old_tile ~= target_tile then
                    map:SetTile(tx, ty, target_tile)
                    local x1, y1, z1 = map:GetTileCenterPoint(tx, ty)
                    if TempTile_HandleTileChange then
                        TempTile_HandleTileChange(x1, y1, z1, old_tile)
                    end
                end
            end
        end
    end
end

local function Shuffle(tbl)
    for i = #tbl, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
end

local function GetRandomItem(tbl)
    return tbl[math.random(#tbl)]
end

local function DistributeTieredResources(center_x, center_z, scan_radius, outer_target, mid_target, core_target)
    local map = TheWorld.Map
    local map_w, map_h = map:GetWorldSize()
    local tile_x, tile_y = map:GetTileCoordsAtPoint(center_x, 0, center_z)

    local outer_points = {}
    local mid_points = {}
    local core_points = {}

    for r = -scan_radius, scan_radius do
        for c = -scan_radius, scan_radius do
            local tx = tile_x + c
            local ty = tile_y + r

            if tx >= 0 and tx < map_w and ty >= 0 and ty < map_h then
                local tile = map:GetTile(tx, ty)
                local wx, wy, wz = map:GetTileCenterPoint(tx, ty)

                if tile == WORLD_TILES.PEBBLEBEACH then
                    table.insert(outer_points, { x = wx, z = wz })
                elseif tile == WORLD_TILES.METEOR then
                    table.insert(mid_points, { x = wx, z = wz })
                elseif tile == WORLD_TILES.FUNGUSMOON then
                    table.insert(core_points, { x = wx, z = wz })
                end
            end
        end
    end

    Shuffle(outer_points)
    local actual_outer = math.min(outer_target, #outer_points)
    for i = 1, actual_outer do
        local pt = outer_points[i]
        local ent = SpawnPrefab(GetRandomItem(RESOURCE_POOLS.OUTER))
        if ent then ent.Transform:SetPosition(pt.x, 0, pt.z) end
    end

    Shuffle(mid_points)
    local actual_mid = math.min(mid_target, #mid_points)
    for i = 1, actual_mid do
        local pt = mid_points[i]
        local ent = SpawnPrefab(GetRandomItem(RESOURCE_POOLS.MID))
        if ent then ent.Transform:SetPosition(pt.x, 0, pt.z) end
    end

    Shuffle(core_points)
    local actual_core = math.min(core_target, #core_points)
    for i = 1, actual_core do
        local pt = core_points[i]
        local ent = SpawnPrefab(GetRandomItem(RESOURCE_POOLS.CORE))
        if ent then ent.Transform:SetPosition(pt.x, 0, pt.z) end
    end
end

--------------------------------------------------------------------------
-- 1. 小岛槽位 (Slot Small)
--------------------------------------------------------------------------
-- 小岛形态 A：八边形紧凑圆台 + 外圈随机散落礁石
defs["small_1"] = {}
defs.small_1.TerraformRoomAtXZ = function(inst, x, z)
    local tf = Terraformer(7)
    for r = -2, 2 do
        for c = -2, 2 do
            tf:Set(c, r, WORLD_TILES.FUNGUSMOON)
        end
    end
    for r = -4, 4 do
        for c = -4, 4 do
            if math.abs(c) > 2 or math.abs(r) > 2 then
                if not (math.abs(c) == 4 and math.abs(r) == 4) then
                    tf:Set(c, r, WORLD_TILES.METEOR)
                end
            end
        end
    end
    local candidate_scatter = {
        {-5, 0}, {5, 0}, {0, -5}, {0, 5},
        {-5, 1}, {-5, -1}, {5, 1}, {5, -1},
        {1, -5}, {-1, -5}, {1, 5}, {-1, 5},
        {-5, 3}, {5, 3}, {-5, -3}, {5, -3},
    }
    Shuffle(candidate_scatter)
    for i = 1, 8 do
        local off = candidate_scatter[i]
        tf:Set(off[1], off[2], WORLD_TILES.PEBBLEBEACH)
    end
    -- 确保传送门基底稳固
    for w = -1, 1 do tf:Set(w, 4, WORLD_TILES.METEOR) end
    tf:ApplyAtXZ(x, z)
end
defs.small_1.LayoutNewRoomAtXZ = function(inst, x, z)
    DistributeTieredResources(x, z, 7, 8, 3, 1)
end

-- 小岛形态 B：微型十字跳台廊道
defs["small_2"] = {}
defs.small_2.TerraformRoomAtXZ = function(inst, x, z)
    local tf = Terraformer(7)
    for r = -1, 1 do
        for c = -1, 1 do
            tf:Set(c, r, WORLD_TILES.FUNGUSMOON)
        end
    end
    for i = 2, 4 do
        for w = -1, 1 do
            tf:Set(w, i, WORLD_TILES.METEOR)
            tf:Set(w, -i, WORLD_TILES.METEOR)
            tf:Set(i, w, WORLD_TILES.METEOR)
            tf:Set(-i, w, WORLD_TILES.METEOR)
        end
    end
    local candidate_scatter = {
        {-3, 3}, {3, 3}, {-3, -3}, {3, -3},
        {-4, 2}, {4, 2}, {-4, -2}, {4, -2},
        {-2, 4}, {2, 4}, {-2, -4}, {2, -4},
        {0, 5}, {0, -5}, {5, 0}, {-5, 0},
    }
    Shuffle(candidate_scatter)
    for i = 1, 8 do
        local off = candidate_scatter[i]
        tf:Set(off[1], off[2], WORLD_TILES.PEBBLEBEACH)
    end
    -- 确保传送门基底稳固
    for w = -1, 1 do tf:Set(w, 4, WORLD_TILES.METEOR) end
    tf:ApplyAtXZ(x, z)
end
defs.small_2.LayoutNewRoomAtXZ = function(inst, x, z)
    DistributeTieredResources(x, z, 7, 8, 3, 1)
end

--------------------------------------------------------------------------
-- 2. 中岛槽位 (Slot Medium)
--------------------------------------------------------------------------
-- 中岛形态 A：开阔十字连廊与四方卫台
defs["medium_1"] = {}
defs.medium_1.TerraformRoomAtXZ = function(inst, x, z)
    local tf = Terraformer(11)
    for r = -2, 2 do
        for c = -2, 2 do
            tf:Set(c, r, WORLD_TILES.FUNGUSMOON)
        end
    end
    for i = 3, 7 do
        for w = -2, 2 do
            tf:Set(w, i, WORLD_TILES.METEOR); tf:Set(w, -i, WORLD_TILES.METEOR)
            tf:Set(i, w, WORLD_TILES.METEOR); tf:Set(-i, w, WORLD_TILES.METEOR)
        end
    end
    for i = 8, 9 do
        for w = -1, 1 do
            tf:Set(w, i, WORLD_TILES.PEBBLEBEACH); tf:Set(w, -i, WORLD_TILES.PEBBLEBEACH)
            tf:Set(i, w, WORLD_TILES.PEBBLEBEACH); tf:Set(-i, w, WORLD_TILES.PEBBLEBEACH)
        end
    end
    local candidate_reefs = {
        {-5, 5}, {-6, 5}, {-5, 6}, {5, 5}, {6, 5}, {5, 6},
        {-5, -5}, {-6, -5}, {-5, -6}, {5, -5}, {6, -5}, {5, -6},
        {-8, 3}, {8, 3}, {-8, -3}, {8, -3},
    }
    Shuffle(candidate_reefs)
    for i = 1, 10 do
        local off = candidate_reefs[i]
        tf:Set(off[1], off[2], WORLD_TILES.PEBBLEBEACH)
    end
    -- 确保传送门基底稳固
    for w = -2, 2 do tf:Set(w, 6, WORLD_TILES.METEOR) end
    tf:ApplyAtXZ(x, z)
end
defs.medium_1.LayoutNewRoomAtXZ = function(inst, x, z)
    DistributeTieredResources(x, z, 11, 14, 6, 3)
end

-- 中岛形态 B：南北双子连岛（石桥贯通双平台）
defs["medium_2"] = {}
defs.medium_2.TerraformRoomAtXZ = function(inst, x, z)
    local tf = Terraformer(11)
    -- 中间窄桥
    for r = -2, 2 do
        for c = -1, 1 do
            tf:Set(c, r, WORLD_TILES.METEOR)
        end
    end
    tf:Set(0, 0, WORLD_TILES.FUNGUSMOON)

    -- 北岛平台 (包含门)
    for r = 3, 7 do
        for c = -4, 4 do
            if not (math.abs(c) == 4 and (r == 3 or r == 7)) then
                if math.abs(c) <= 2 and (r >= 4 and r <= 6) then
                    tf:Set(c, r, WORLD_TILES.FUNGUSMOON)
                else
                    tf:Set(c, r, WORLD_TILES.METEOR)
                end
            end
        end
    end

    -- 南岛平台
    for r = -7, -3 do
        for c = -4, 4 do
            if not (math.abs(c) == 4 and (r == -3 or r == -7)) then
                if math.abs(c) <= 2 and (r <= -4 and r >= -6) then
                    tf:Set(c, r, WORLD_TILES.FUNGUSMOON)
                else
                    tf:Set(c, r, WORLD_TILES.METEOR)
                end
            end
        end
    end

    local candidate_scatter = {
        {-6, 5}, {6, 5}, {-6, -5}, {6, -5},
        {-5, 8}, {5, 8}, {-5, -8}, {5, -8},
        {0, 8}, {0, -8}, {-3, 0}, {3, 0},
    }
    Shuffle(candidate_scatter)
    for i = 1, 8 do
        local off = candidate_scatter[i]
        tf:Set(off[1], off[2], WORLD_TILES.PEBBLEBEACH)
    end
    -- 确保传送门基底稳固
    for w = -2, 2 do tf:Set(w, 6, WORLD_TILES.METEOR) end
    tf:ApplyAtXZ(x, z)
end
defs.medium_2.LayoutNewRoomAtXZ = function(inst, x, z)
    DistributeTieredResources(x, z, 11, 14, 6, 3)
end

--------------------------------------------------------------------------
-- 3. 大岛槽位 (Slot Large)
--------------------------------------------------------------------------
-- 大岛形态 A：实心半月弯弧群岛
defs["large_1"] = {}
defs.large_1.TerraformRoomAtXZ = function(inst, x, z)
    local tf = Terraformer(19)
    for r = -16, 16 do
        for c = -16, 16 do
            local d_sq = (c / 15) ^ 2 + (r / 14) ^ 2
            if d_sq <= 1.0 then
                local is_bay = (c < -6 and math.abs(r) < 6)
                if not is_bay then
                    local dist = math.sqrt(c * c + r * r)
                    if dist <= 5 then
                        tf:Set(c, r, WORLD_TILES.FUNGUSMOON)
                    elseif dist <= 11 then
                        tf:Set(c, r, WORLD_TILES.METEOR)
                    else
                        tf:Set(c, r, WORLD_TILES.PEBBLEBEACH)
                    end
                end
            end
        end
    end

    local outer_reefs = {
        {16, 0}, {16, 1}, {16, -1},
        {14, 7}, {13, 8}, {14, -7}, {13, -8},
        {0, 15}, {1, 15}, {-1, 15},
        {0, -15}, {1, -15}, {-1, -15},
        {-10, 12}, {-10, -12},
    }
    Shuffle(outer_reefs)
    for i = 1, 12 do
        local pt = outer_reefs[i]
        tf:Set(pt[1], pt[2], WORLD_TILES.PEBBLEBEACH)
    end
    -- 确保传送门基底稳固
    for w = -2, 2 do tf:Set(w, 6, WORLD_TILES.METEOR) end
    tf:ApplyAtXZ(x, z)
end
defs.large_1.LayoutNewRoomAtXZ = function(inst, x, z)
    DistributeTieredResources(x, z, 18, 24, 14, 5)
    local statue = SpawnPrefab("archive_moon_statue")
    if statue then statue.Transform:SetPosition(x, 0, z) end
end

-- 大岛形态 B：天体双环天池岛 (中心神圣内岛 + 四桥 + 外围环形巨岩)
defs["large_2"] = {}
defs.large_2.TerraformRoomAtXZ = function(inst, x, z)
    local tf = Terraformer(19)

    -- 1. 中心月菌丝神圣浮台
    for r = -4, 4 do
        for c = -4, 4 do
            if (c * c + r * r) <= 18 then
                tf:Set(c, r, WORLD_TILES.FUNGUSMOON)
            end
        end
    end

    -- 2. 四方天体石桥（北桥直通传送门）
    for i = 4, 10 do
        for w = -1, 1 do
            tf:Set(w, i, WORLD_TILES.METEOR)
            tf:Set(w, -i, WORLD_TILES.METEOR)
            tf:Set(i, w, WORLD_TILES.METEOR)
            tf:Set(-i, w, WORLD_TILES.METEOR)
        end
    end

    -- 3. 外围环形巨岩环带 (陨坑边缘)
    for r = -16, 16 do
        for c = -16, 16 do
            local dist = math.sqrt(c * c + r * r)
            if dist >= 10 and dist <= 15 then
                if dist <= 13 then
                    tf:Set(c, r, WORLD_TILES.METEOR)
                else
                    tf:Set(c, r, WORLD_TILES.PEBBLEBEACH)
                end
            end
        end
    end

    -- 4. 环外散落浮石
    local outer_reefs = {
        {16, 5}, {17, 0}, {16, -5},
        {-16, 5}, {-17, 0}, {-16, -5},
        {5, 16}, {0, 17}, {-5, 16},
        {5, -16}, {0, -17}, {-5, -16},
    }
    Shuffle(outer_reefs)
    for i = 1, 10 do
        local pt = outer_reefs[i]
        tf:Set(pt[1], pt[2], WORLD_TILES.PEBBLEBEACH)
    end
    -- 确保传送门基底稳固
    for w = -2, 2 do tf:Set(w, 6, WORLD_TILES.METEOR) end
    tf:ApplyAtXZ(x, z)
end
defs.large_2.LayoutNewRoomAtXZ = function(inst, x, z)
    DistributeTieredResources(x, z, 18, 24, 14, 5)
    local s1 = SpawnPrefab("archive_moon_statue")
    if s1 then s1.Transform:SetPosition(x - 2 * TILE_SIZE, 0, z) end
    local s2 = SpawnPrefab("archive_moon_statue")
    if s2 then s2.Transform:SetPosition(x + 2 * TILE_SIZE, 0, z) end
end

return defs