local _G = rawget(_G, "GLOBAL") or _G
local rawget = _G.rawget
local rawset = _G.rawset
local ipairs = _G.ipairs
local pairs = _G.pairs
local math = _G.math
local table = _G.table
local require = _G.require

local CelestialEngine = {}

local is_expanding = false
local expanded_size = 0
local cached_world_data = nil
local cached_realm_data = nil

local SYSTEM_OVERRIDE_KEYS = {
    season_start = true,
    start_location = true,
    world_size = true,
    islands = true,
    branching = true,
    loop = true,
    layout_mode = true,
    keep_disconnected_tiles = true,
    no_joining_islands = true,
    has_ocean = true,
    no_wormholes_to_disconnected_tiles = true,
    wormhole_prefab = true,
    specialevent = true,
    roads = true,
    boons = true,
    touchstone = true,
    traps = true,
    poi = true,
    protected = true,
    task_set = true,
}

local function GetWorldTiles()
    local WORLD_TILES = rawget(_G, "WORLD_TILES") or rawget(_G, "GROUND") or {}
    local meteor = rawget(WORLD_TILES, "METEOR") or 43
    local shellbeach = rawget(WORLD_TILES, "SHELLBEACH") or 42
    local cc_blackgold = rawget(WORLD_TILES, "CC_BLACKGOLD") or rawget(WORLD_TILES, "PEBBLEBEACH") or 41
    local impassable = rawget(WORLD_TILES, "IMPASSABLE") or 1
    local dirt = rawget(WORLD_TILES, "DIRT") or 2

    return {
        METEOR = meteor,
        CC_METEOR = shellbeach,
        CC_BLACKGOLD = dirt,
        IMPASSABLE = impassable,
        DIRT = dirt,
    }
end

local CHANCE_COLORS = {
    ["#8ea2a3"] = 0.70,
    ["#7bb5b8"] = 0.50,
    ["#7190ad"] = 0.50,
    ["#7a8b8c"] = 0.50,
    ["#626f70"] = 0.25,
}

local MUTATION_RULES = {
    ["#76a88c"] = { chance = 0.15, tile_key = "METEOR" },
    ["#518468"] = { chance = 0.15, tile_key = "METEOR" },
    ["#80761c"] = { chance = 0.20, tile_key = "CC_BLACKGOLD" },
    ["#998d24"] = { chance = 0.50, tile_key = "CC_BLACKGOLD" },
}

local function GenerateProcessedRealm()
    local tiles = GetWorldTiles()

    local map_ground = require("map/mapdata/map_ground_data")
    local map_mutation = require("map/mapdata/map_mutation_white_data")
    local map_bridge = require("map/mapdata/map_bridge_data")

    local ground_ps = map_ground:Unpack()
    local mutation_ps = map_mutation:Unpack()
    local bridge_ps = map_bridge:Unpack()

    local width = map_ground.width or 256
    local height = map_ground.height or 256

    -- 1. 地图 50% 概率完全相反（水平镜像判定）
    local is_flipped = (math.random() <= 0.5)

    local ground_raw = {}
    local mutation_raw = {}
    local bridge_raw = {}

    for y = 1, height do
        ground_raw[y] = {}
        mutation_raw[y] = {}
        bridge_raw[y] = {}
        for x = 1, width do
            local src_x = is_flipped and (width - x + 1) or x
            ground_raw[y][x] = ground_ps[y] and ground_ps[y][src_x]
            mutation_raw[y][x] = mutation_ps[y] and mutation_ps[y][src_x]
            bridge_raw[y][x] = bridge_ps[y] and bridge_ps[y][src_x]
        end
    end

    local final_tiles = {}
    for y = 1, height do
        final_tiles[y] = {}
        for x = 1, width do
            final_tiles[y][x] = tiles.IMPASSABLE
        end
    end

    -- 2. 基础确定性地皮填充
    for y = 1, height do
        for x = 1, width do
            local col = ground_raw[y][x]
            if col then
                if col == "#76a88c" or col == "#76a88c01" then
                    final_tiles[y][x] = tiles.METEOR
                elseif col == "#9bb2b3" then
                    final_tiles[y][x] = tiles.CC_METEOR
                elseif col == "#4e5959" then
                    final_tiles[y][x] = tiles.DIRT
                end
            end
        end
    end

    -- 3. 整片区域连通块伪随机判定（含 7bb5b8 与 7190ad 保底机制）
    local visited_chance = {}
    for y = 1, height do
        visited_chance[y] = {}
    end

    local chance_clusters = {}
    local guaranteed_pair_clusters = {}

    for y = 1, height do
        for x = 1, width do
            local col = ground_raw[y][x]
            if col and CHANCE_COLORS[col] and not visited_chance[y][x] then
                local chance_val = CHANCE_COLORS[col]
                local cluster = {
                    col = col,
                    chance = chance_val,
                    pixels = {},
                    spawn = false,
                }
                local queue = { { x = x, y = y } }
                local q_head = 1
                visited_chance[y][x] = true

                while q_head <= #queue do
                    local curr = queue[q_head]
                    q_head = q_head + 1
                    table.insert(cluster.pixels, curr)

                    local cx, cy = curr.x, curr.y
                    local neighbors = {
                        { x = cx + 1, y = cy },
                        { x = cx - 1, y = cy },
                        { x = cx,     y = cy + 1 },
                        { x = cx,     y = cy - 1 },
                    }

                    for i = 1, 4 do
                        local n = neighbors[i]
                        if n.x >= 1 and n.x <= width and n.y >= 1 and n.y <= height then
                            if not visited_chance[n.y][n.x] and ground_raw[n.y][n.x] == col then
                                visited_chance[n.y][n.x] = true
                                table.insert(queue, n)
                            end
                        end
                    end
                end

                table.insert(chance_clusters, cluster)
                if col == "#7bb5b8" or col == "#7190ad" then
                    table.insert(guaranteed_pair_clusters, cluster)
                end
            end
        end
    end

    -- 常规掷骰
    local guaranteed_spawn_count = 0
    for _, c in ipairs(chance_clusters) do
        if math.random() <= c.chance then
            c.spawn = true
            if c.col == "#7bb5b8" or c.col == "#7190ad" then
                guaranteed_spawn_count = guaranteed_spawn_count + 1
            end
        end
    end

    -- 针对 7bb5b8 与 7190ad 触发保底：二者均未随机到时强制必刷一个
    if guaranteed_spawn_count == 0 and #guaranteed_pair_clusters > 0 then
        local picked = guaranteed_pair_clusters[math.random(#guaranteed_pair_clusters)]
        picked.spawn = true
    end

    -- 应用地皮生成结果
    for _, c in ipairs(chance_clusters) do
        if c.spawn then
            for _, pt in ipairs(c.pixels) do
                final_tiles[pt.y][pt.x] = tiles.CC_METEOR
            end
        else
            for _, pt in ipairs(c.pixels) do
                final_tiles[pt.y][pt.x] = tiles.IMPASSABLE
            end
        end
    end

    -- 4. 变异层整岛连通块覆盖
    local visited_mut = {}
    for y = 1, height do
        visited_mut[y] = {}
    end

    for y = 1, height do
        for x = 1, width do
            local mut_col = mutation_raw[y][x]
            if mut_col and not visited_mut[y][x] and MUTATION_RULES[mut_col] then
                local rule = MUTATION_RULES[mut_col]
                local cluster = {}
                local queue = { { x = x, y = y } }
                local q_head = 1
                visited_mut[y][x] = true

                while q_head <= #queue do
                    local curr = queue[q_head]
                    q_head = q_head + 1
                    table.insert(cluster, curr)

                    local cx, cy = curr.x, curr.y
                    local neighbors = {
                        { x = cx + 1, y = cy },
                        { x = cx - 1, y = cy },
                        { x = cx,     y = cy + 1 },
                        { x = cx,     y = cy - 1 },
                    }

                    for i = 1, 4 do
                        local n = neighbors[i]
                        if n.x >= 1 and n.x <= width and n.y >= 1 and n.y <= height then
                            if not visited_mut[n.y][n.x] and mutation_raw[n.y][n.x] == mut_col then
                                visited_mut[n.y][n.x] = true
                                table.insert(queue, n)
                            end
                        end
                    end
                end

                if math.random() <= rule.chance then
                    local target_tile = tiles[rule.tile_key] or tiles.METEOR
                    for _, pt in ipairs(cluster) do
                        if final_tiles[pt.y][pt.x] ~= tiles.IMPASSABLE then
                            final_tiles[pt.y][pt.x] = target_tile
                        end
                    end
                end
            end
        end
    end

    -- 5. 桥桩识别、聚类与测距校验
    local raw_posts = {}
    local portal_candidates = {}

    for y = 1, height do
        for x = 1, width do
            local b_col = bridge_raw[y][x]
            if b_col then
                local low_col = b_col:lower()
                if low_col == "#008079" or low_col == "008079" then
                    table.insert(portal_candidates, { x = x, y = y })
                elseif low_col == "#e09b08" or low_col == "e09b08" then
                    table.insert(raw_posts, { x = x, y = y, is_prob = false, used = false })
                elseif low_col == "#a97609" or low_col == "a97609" then
                    table.insert(raw_posts, { x = x, y = y, is_prob = true, used = false })
                end
            end
        end
    end

    -- 间距 < 4 格聚类（禁止跨越虚空合并）
    local clusters = {}
    for _, pt in ipairs(raw_posts) do
        if not pt.used then
            pt.used = true
            local cluster = {
                pixels = { pt },
                is_prob = pt.is_prob,
                paired_cluster = nil,
                chosen = nil,
                spawn = false,
            }
            local queue = { pt }
            local q_head = 1

            while q_head <= #queue do
                local curr = queue[q_head]
                q_head = q_head + 1
                for _, other in ipairs(raw_posts) do
                    if not other.used and other.is_prob == cluster.is_prob then
                        local dist_sq = (other.x - curr.x)^2 + (other.y - curr.y)^2
                        if dist_sq < 16 then
                            local has_void_gap = false
                            if curr.x == other.x then
                                local minY, maxY = math.min(curr.y, other.y), math.max(curr.y, other.y)
                                for ty = minY + 1, maxY - 1 do
                                    if final_tiles[ty] and final_tiles[ty][curr.x] == tiles.IMPASSABLE then
                                        has_void_gap = true
                                        break
                                    end
                                end
                            elseif curr.y == other.y then
                                local minX, maxX = math.min(curr.x, other.x), math.max(curr.x, other.x)
                                for tx = minX + 1, maxX - 1 do
                                    if final_tiles[curr.y] and final_tiles[curr.y][tx] == tiles.IMPASSABLE then
                                        has_void_gap = true
                                        break
                                    end
                                end
                            end

                            if not has_void_gap then
                                other.used = true
                                table.insert(cluster.pixels, other)
                                table.insert(queue, other)
                            end
                        end
                    end
                end
            end

            local valid_land_pixels = {}
            for _, p in ipairs(cluster.pixels) do
                if final_tiles[p.y] and final_tiles[p.y][p.x] ~= tiles.IMPASSABLE then
                    local neighbors = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
                    local is_edge = false
                    for _, off in ipairs(neighbors) do
                        local nx, ny = p.x + off[1], p.y + off[2]
                        if nx < 1 or nx > width or ny < 1 or ny > height or final_tiles[ny][nx] == tiles.IMPASSABLE then
                            is_edge = true
                            break
                        end
                    end
                    if is_edge then
                        table.insert(valid_land_pixels, p)
                    end
                end
            end
            cluster.land_pixels = valid_land_pixels

            if #valid_land_pixels > 0 then
                table.insert(clusters, cluster)
            end
        end
    end

    local SCAN_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

    -- 判定点能否测距搭桥（虚空跨度 1~10 格内必须有陆地）
    local function CanBridgeToIsland(px, py)
        for _, d in ipairs(SCAN_DIRS) do
            local dx, dy = d[1], d[2]
            local start_x = px + dx
            local start_y = py + dy

            if start_x >= 1 and start_x <= width and start_y >= 1 and start_y <= height
                and final_tiles[start_y][start_x] == tiles.IMPASSABLE then
                for step = 1, 11 do
                    local tx = px + dx * step
                    local ty = py + dy * step
                    if tx < 1 or tx > width or ty < 1 or ty > height then break end

                    if final_tiles[ty][tx] ~= tiles.IMPASSABLE then
                        if step >= 2 and step <= 11 then
                            return true
                        end
                        break
                    end
                end
            end
        end
        return false
    end

    -- 针对 #a97609 概率桥桩：对向扫描匹配
    for _, c1 in ipairs(clusters) do
        if c1.is_prob and not c1.paired_cluster then
            for _, p1 in ipairs(c1.land_pixels) do
                for _, d in ipairs(SCAN_DIRS) do
                    local dx, dy = d[1], d[2]
                    local start_x = p1.x + dx
                    local start_y = p1.y + dy

                    if start_x >= 1 and start_x <= width and start_y >= 1 and start_y <= height
                        and final_tiles[start_y][start_x] == tiles.IMPASSABLE then
                        local void_count = 0
                        local matched_c2 = nil
                        local matched_p2 = nil

                        for step = 1, 11 do
                            local tx = p1.x + dx * step
                            local ty = p1.y + dy * step
                            if tx < 1 or tx > width or ty < 1 or ty > height then break end

                            if final_tiles[ty][tx] == tiles.IMPASSABLE then
                                void_count = void_count + 1
                            else
                                if void_count >= 1 and void_count <= 10 then
                                    for _, c2 in ipairs(clusters) do
                                        if c2 ~= c1 and c2.is_prob and not c2.paired_cluster then
                                            for _, p2 in ipairs(c2.land_pixels) do
                                                if p2.x == tx and p2.y == ty then
                                                    matched_c2 = c2
                                                    matched_p2 = p2
                                                    break
                                                end
                                            end
                                        end
                                        if matched_c2 then break end
                                    end
                                end
                                break
                            end
                        end

                        if matched_c2 and matched_p2 then
                            c1.paired_cluster = matched_c2
                            matched_c2.paired_cluster = c1
                            c1.chosen = p1
                            matched_c2.chosen = matched_p2
                            break
                        end
                    end
                end
                if c1.paired_cluster then break end
            end
        end
    end

    -- #a97609 成对成败判定（30% 概率成对刷，未配对则绝对不刷）
    for _, c in ipairs(clusters) do
        if c.is_prob and c.paired_cluster and not c.spawn then
            local partner = c.paired_cluster
            if math.random() <= 0.30 then
                c.spawn = true
                partner.spawn = true
            end
        end
    end

    -- 针对 #e09b08 常驻桥桩：测距通过才允许生成，无对岸岛屿则不占用刷新池
    for _, c in ipairs(clusters) do
        if not c.is_prob then
            for _, p in ipairs(c.land_pixels) do
                if CanBridgeToIsland(p.x, p.y) then
                    c.chosen = p
                    c.spawn = true
                    break
                end
            end
        end
    end

    local final_bridges = {}
    for _, c in ipairs(clusters) do
        if c.spawn and c.chosen then
            table.insert(final_bridges, {
                x = c.chosen.x,
                y = c.chosen.y,
            })
        end
    end

    -- 6. 传送门候选点 N 选 1
    local chosen_portal = nil
    if #portal_candidates > 0 then
        local valid_portals = {}
        for _, pt in ipairs(portal_candidates) do
            if final_tiles[pt.y] and final_tiles[pt.y][pt.x] ~= tiles.IMPASSABLE then
                table.insert(valid_portals, pt)
            end
        end
        if #valid_portals > 0 then
            chosen_portal = valid_portals[math.random(#valid_portals)]
        end
    end

    return {
        width = width,
        height = height,
        tiles = final_tiles,
        bridges = final_bridges,
        portal = chosen_portal,
    }
end

function CelestialEngine.Init(env)
    local AddGlobalClassPostConstruct = env.AddGlobalClassPostConstruct or _G.AddGlobalClassPostConstruct
    local WorldSim = rawget(_G, "WorldSim")

    local forest_map = _G.package.loaded["map/forest_map"]
    if not forest_map then return end

    if WorldSim then
        local idx = _G.getmetatable(WorldSim).__index
        local SetWorldSize_ = idx.SetWorldSize
        local ConvertToTileMap_ = idx.ConvertToTileMap

        idx.SetWorldSize = function(self, a, b)
            if is_expanding and expanded_size > 0 then
                SetWorldSize_(self, expanded_size, expanded_size)
            else
                SetWorldSize_(self, a, b)
            end
        end
        idx.ConvertToTileMap = function(self, x)
            if is_expanding and expanded_size > 0 then
                ConvertToTileMap_(self, expanded_size)
            else
                ConvertToTileMap_(self, x)
            end
        end
    end

    local old_Generate = forest_map.Generate
    forest_map.Generate = function(prefab, map_width, map_height, tasks, level, level_type)
        if prefab == "cave" then
            return old_Generate(prefab, map_width, map_height, tasks, level, level_type)
        end

        local realm_w = 256
        local realm_h = 256

        if is_expanding and cached_world_data then
            level.required_prefabs = {}
            level.set_pieces = {}
            level.ocean_prefill_setpieces = {}
            level.ocean_population = {}

            local orig_overrides = level.overrides or {}
            level.overrides = _G.setmetatable({}, {
                __index = function(t, k)
                    if orig_overrides[k] ~= nil then return orig_overrides[k] end
                    if SYSTEM_OVERRIDE_KEYS[k] then return nil end
                    return "never"
                end,
                __newindex = function(t, k, v) orig_overrides[k] = v end,
            })

            local savedata = old_Generate(prefab, map_width, map_height, tasks, level, level_type)
            if not savedata then
                is_expanding = false
                cached_world_data = nil
                cached_realm_data = nil
                return nil
            end

            local w, h = WorldSim:GetWorldSize()
            local orig_w = cached_world_data.width
            local mainland_offset = -(w - orig_w) * 2

            savedata.ents = {}
            for p_name, list in pairs(cached_world_data.mainland_ents) do
                savedata.ents[p_name] = savedata.ents[p_name] or {}
                for _, ent in ipairs(list) do
                    table.insert(savedata.ents[p_name], {
                        x = ent.x + mainland_offset,
                        z = ent.z + mainland_offset,
                        id = ent.id,
                        data = ent.data,
                        scenario = ent.scenario,
                    })
                end
            end

            savedata.map.roads = cached_world_data.roads
            for _, road in pairs(savedata.map.roads or {}) do
                for i = 2, #road do
                    road[i][1] = road[i][1] + mainland_offset
                    road[i][2] = road[i][2] + mainland_offset
                end
            end

            savedata.map.topology = cached_world_data.topology
            for _, node in ipairs(savedata.map.topology.nodes or {}) do
                node.x = node.x + mainland_offset
                node.y = node.y + mainland_offset
                if node.cent then
                    node.cent[1] = node.cent[1] + mainland_offset
                    node.cent[2] = node.cent[2] + mainland_offset
                end
                if node.poly then
                    for _, pt in ipairs(node.poly) do
                        pt[1] = pt[1] + mainland_offset
                        pt[2] = pt[2] + mainland_offset
                    end
                end
            end

            for y = 1, h do
                for x = 1, w do
                    WorldSim:SetTile(x, y, 1)
                end
            end

            for y = 1, cached_world_data.height do
                for x = 1, cached_world_data.width do
                    local t = cached_world_data.original_tiles[y] and cached_world_data.original_tiles[y][x]
                    if t then WorldSim:SetTile(x, y, t) end
                end
            end

            local base_x = orig_w + 10
            local base_y = 10

            if not cached_realm_data then
                cached_realm_data = GenerateProcessedRealm()
            end

            local realm = cached_realm_data
            for ry = 1, realm.height do
                for rx = 1, realm.width do
                    local tx = base_x + rx
                    local ty = base_y + ry
                    if tx <= w and ty <= h then
                        WorldSim:SetTile(tx, ty, realm.tiles[ry][rx])
                    end
                end
            end

            -- 生成桥桩实体（严格对齐官方地皮几何中心：(tx - w/2) * 4）
            savedata.ents["cc_brigdepost"] = savedata.ents["cc_brigdepost"] or {}
            for _, b in ipairs(realm.bridges) do
                local tx = base_x + b.x
                local ty = base_y + b.y
                if tx <= w and ty <= h and realm.tiles[b.y][b.x] ~= 1 then
                    local cx = (tx - w / 2.0) * 4
                    local cz = (ty - h / 2.0) * 4

                    table.insert(savedata.ents["cc_brigdepost"], {
                        x = cx,
                        z = cz,
                        data = {
                            tile_cx = cx,
                            tile_cz = cz,
                        },
                    })
                end
            end

            -- 生成天界出口传送门 (portal_exit)
            if realm.portal then
                local tx = base_x + realm.portal.x
                local ty = base_y + realm.portal.y
                local cx = (tx - w / 2.0) * 4
                local cz = (ty - h / 2.0) * 4
                savedata.ents["portal_exit"] = savedata.ents["portal_exit"] or {}
                table.insert(savedata.ents["portal_exit"], {
                    x = cx,
                    z = cz,
                })
            end

            local join_islands = not (level.overrides and level.overrides.no_joining_islands)
            savedata.map.tiles, savedata.map.tiledata, savedata.map.nav, savedata.map.adj, savedata.map.nodeidtilemap = WorldSim:GetEncodedMap(join_islands)
            if rawget(_G, "GetWorldTileMap") then
                savedata.map.world_tile_map = _G.GetWorldTileMap()
            end

            savedata.retrofit_nodeidtilemap = true
            is_expanding = false
            cached_world_data = nil
            cached_realm_data = nil
            return savedata
        end

        local savedata = old_Generate(prefab, map_width, map_height, tasks, level, level_type)
        if not savedata then return nil end

        local width, height = WorldSim:GetWorldSize()
        local original_tiles = {}
        for y = 1, height do
            original_tiles[y] = {}
            for x = 1, width do
                original_tiles[y][x] = WorldSim:GetTile(x, y)
            end
        end

        cached_world_data = {
            width = width,
            height = height,
            original_tiles = original_tiles,
            mainland_ents = savedata.ents or {},
            roads = savedata.map.roads,
            topology = savedata.map.topology,
        }

        is_expanding = true
        expanded_size = width + realm_w + 30
        if expanded_size % 2 ~= width % 2 then
            expanded_size = expanded_size + 1
        end
        return nil
    end

    AddGlobalClassPostConstruct("map/network", "Graph", function(self)
        local old_GlobalPostPopulate = self.GlobalPostPopulate
        self.GlobalPostPopulate = function(graph_self, entities, w, h)
            if is_expanding and cached_world_data then
                for y = 1, h do
                    for x = 1, w do WorldSim:SetTile(x, y, 1) end
                end
                local orig_tiles = cached_world_data.original_tiles
                for y = 1, cached_world_data.height do
                    for x = 1, cached_world_data.width do
                        if orig_tiles[y] and orig_tiles[y][x] then
                            WorldSim:SetTile(x, y, orig_tiles[y][x])
                        end
                    end
                end

                if not cached_realm_data then
                    cached_realm_data = GenerateProcessedRealm()
                end

                local realm = cached_realm_data
                local base_x = cached_world_data.width + 10
                local base_y = 10
                for ry = 1, realm.height do
                    for rx = 1, realm.width do
                        local tx = base_x + rx
                        local ty = base_y + ry
                        if tx <= w and ty <= h then
                            WorldSim:SetTile(tx, ty, realm.tiles[ry][rx])
                        end
                    end
                end
            end
            old_GlobalPostPopulate(graph_self, entities, w, h)
        end
    end)
end

return CelestialEngine