local _G = rawget(_G, "GLOBAL") or _G
local rawget = _G.rawget
local ipairs = _G.ipairs
local pairs = _G.pairs
local math = _G.math
local string = _G.string or rawget(_G, "string")
local table = _G.table
local pcall = _G.pcall
local require = _G.require
local type = _G.type
local error = _G.error
local tostring = _G.tostring
local tonumber = _G.tonumber
local Contract = require("map/map_contract")

local MapRulesEngine = {}

-- 标准 4 邻域检测方向（右、左、下、上）
local SCAN_DIRS = {
    { 1, 0 },
    { -1, 0 },
    { 0, 1 },
    { 0, -1 },
}

local cached_blueprint_footprints = {}

-- ============================================================================
-- 板块一：空间拓扑基础组件与分辨率解算 (Spatial Topology & Grid Resizer)
-- ============================================================================

--- 将 4x4 像素块按中心采样解算为单块物理地块
function MapRulesEngine.UnpackGrid4x4(raw_grid, width, height, solver_mode)
    if solver_mode ~= "4x4" or not raw_grid then
        return raw_grid, width, height
    end

    local scaled_width = math.floor(width / 4)
    local scaled_height = math.floor(height / 4)
    local scaled_grid = {}

    for y = 1, scaled_height do
        scaled_grid[y] = {}
        for x = 1, scaled_width do
            local src_x = (x - 1) * 4 + 2
            local src_y = (y - 1) * 4 + 2
            scaled_grid[y][x] = raw_grid[src_y] and raw_grid[src_y][src_x]
        end
    end

    return scaled_grid, scaled_width, scaled_height
end

--- 通用 4 邻域 BFS 连通块提取
function MapRulesEngine.ExtractClusters(grid, width, height, match_func)
    local visited = {}
    for y = 1, height do
        visited[y] = {}
    end

    local clusters = {}

    for y = 1, height do
        for x = 1, width do
            local cell = grid[y] and grid[y][x]
            if cell and not visited[y][x] and match_func(cell) then
                local cluster = {
                    col = cell.color,
                    tier = cell.tier or 1,
                    pixels = {},
                }
                local queue = { { x = x, y = y } }
                local q_head = 1
                visited[y][x] = true

                while q_head <= #queue do
                    local curr = queue[q_head]
                    q_head = q_head + 1
                    table.insert(cluster.pixels, curr)

                    local cx, cy = curr.x, curr.y
                    for _, dir in ipairs(SCAN_DIRS) do
                        local nx, ny = cx + dir[1], cy + dir[2]
                        if nx >= 1 and nx <= width and ny >= 1 and ny <= height then
                            local n_cell = grid[ny] and grid[ny][nx]
                            if not visited[ny][nx] and n_cell and match_func(n_cell, cell) then
                                visited[ny][nx] = true
                                table.insert(queue, { x = nx, y = ny })
                            end
                        end
                    end
                end

                table.insert(clusters, cluster)
            end
        end
    end

    return clusters
end

local function ResolveClusterConfig(cluster, config_map)
    local col_lower = cluster.col and cluster.col:lower() or ""
    local conf = config_map[cluster.col] or config_map[col_lower]
    local tier_conf = conf and conf.tiers and (conf.tiers[cluster.tier] or conf.tiers[1])
    return tier_conf or conf or {}
end

function MapRulesEngine.MergeNearbyRandomPickClusters(clusters, config_map)
    local parents, families = {}, {}
    local function Find(index)
        while parents[index] ~= index do
            parents[index] = parents[parents[index]]
            index = parents[index]
        end
        return index
    end

    local function Union(a, b)
        a, b = Find(a), Find(b)
        if a ~= b then
            if a > b then a, b = b, a end
            parents[b] = a
        end
    end

    for index, cluster in ipairs(clusters) do
        local conf = ResolveClusterConfig(cluster, config_map)
        local distance = conf.merge_distance
        if conf.rule == "random_pick_one" and distance ~= nil then
            if type(distance) ~= "number" or distance ~= distance or distance == math.huge or distance < 0 then
                error("[CelestialMap] " .. tostring(cluster.col) .. ": merge_distance must be a finite, nonnegative number")
            end
            if distance > 0 then
                parents[index] = index
                local tiers = families[cluster.col]
                if not tiers then
                    tiers = {}
                    families[cluster.col] = tiers
                end
                local family = tiers[cluster.tier]
                if not family then
                    family = { buckets = {}, distance = distance }
                    tiers[cluster.tier] = family
                end

                -- 像素中心是整数坐标，半格小桶最多一个点；大桶宽取半径的一半，桶内必相连。
                local bucket_size = math.max(family.distance / 2, 0.5)
                local distance_sq = family.distance * family.distance
                for _, point in ipairs(cluster.pixels) do
                    local bx = math.floor(point.x / bucket_size)
                    local by = math.floor(point.y / bucket_size)
                    for nx = bx - 2, bx + 2 do
                        local column = family.buckets[nx]
                        if column then
                            for ny = by - 2, by + 2 do
                                local bucket = column[ny]
                                if bucket and Find(index) ~= Find(bucket.cluster) then
                                    for _, other in ipairs(bucket.points) do
                                        local dx, dy = point.x - other.x, point.y - other.y
                                        if dx * dx + dy * dy <= distance_sq then
                                            Union(index, bucket.cluster)
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                    local column = family.buckets[bx]
                    if not column then
                        column = {}
                        family.buckets[bx] = column
                    end
                    local bucket = column[by]
                    if not bucket then
                        bucket = { cluster = index, points = {} }
                        column[by] = bucket
                    end
                    table.insert(bucket.points, point)
                end
            end
        end
    end

    local member_counts = {}
    for index in ipairs(clusters) do
        local root = parents[index] and Find(index) or index
        member_counts[root] = (member_counts[root] or 0) + 1
    end

    local result, merged = {}, {}
    for index, cluster in ipairs(clusters) do
        local root = parents[index] and Find(index) or index
        if member_counts[root] == 1 then
            table.insert(result, cluster)
        else
            local group = merged[root]
            if not group then
                group = {}
                for key, value in pairs(cluster) do group[key] = value end
                group.pixels = {}
                merged[root] = group
                table.insert(result, group)
            end
            for _, point in ipairs(cluster.pixels) do table.insert(group.pixels, point) end
        end
    end
    return result
end

--- 检查指定点位是否为非虚空实体陆地
function MapRulesEngine.IsSolidGround(pt, final_tiles, impassable_tile)
    local tile = final_tiles[pt.y] and final_tiles[pt.y][pt.x]
    return tile ~= nil and tile ~= impassable_tile
end

--- 过滤出面向虚空的边缘陆地像素点
function MapRulesEngine.FilterEdgePixels(pixels, final_tiles, width, height, impassable_tile)
    local valid_edge = {}
    for _, p in ipairs(pixels) do
        if MapRulesEngine.IsSolidGround(p, final_tiles, impassable_tile) then
            local is_edge = false
            for _, off in ipairs(SCAN_DIRS) do
                local nx, ny = p.x + off[1], p.y + off[2]
                if nx < 1 or nx > width or ny < 1 or ny > height or final_tiles[ny][nx] == impassable_tile then
                    is_edge = true
                    break
                end
            end
            if is_edge then
                table.insert(valid_edge, p)
            end
        end
    end
    return valid_edge
end

--- 检查两点直线路径上是否跨越虚空裂隙
function MapRulesEngine.HasVoidGapBetween(final_tiles, p1, p2, impassable_tile)
    if p1.x == p2.x then
        local minY, maxY = math.min(p1.y, p2.y), math.max(p1.y, p2.y)
        for ty = minY + 1, maxY - 1 do
            if final_tiles[ty] and final_tiles[ty][p1.x] == impassable_tile then
                return true
            end
        end
    elseif p1.y == p2.y then
        local minX, maxX = math.min(p1.x, p2.x), math.max(p1.x, p2.x)
        for tx = minX + 1, maxX - 1 do
            if final_tiles[p1.y] and final_tiles[p1.y][tx] == impassable_tile then
                return true
            end
        end
    end
    return false
end

-- ============================================================================
-- 板块二：地皮决策与组保底组件 (Ground & Chance Solvers)
-- ============================================================================

--- 针对连通块群计算概率与成对保底
function MapRulesEngine.SolveClusterSpawns(clusters, config_map)
    local pair_groups = {}
    local pair_spawn_counts = {}

    for _, c in ipairs(clusters) do
        local tier_conf = ResolveClusterConfig(c, config_map)

        local chance = tier_conf.chance or 1.0
        c.spawn = (math.random() <= chance)
        c.tier_conf = tier_conf

        if tier_conf.pair_group then
            local gid = tier_conf.pair_group
            pair_groups[gid] = pair_groups[gid] or {}
            pair_spawn_counts[gid] = pair_spawn_counts[gid] or 0
            table.insert(pair_groups[gid], c)
            if c.spawn then
                pair_spawn_counts[gid] = pair_spawn_counts[gid] + 1
            end
        end
    end

    for gid, list in pairs(pair_groups) do
        if pair_spawn_counts[gid] == 0 and #list > 0 then
            local forced = list[math.random(#list)]
            forced.spawn = true
        end
    end
end

--- 执行地皮覆写
function MapRulesEngine.ApplyTilePainting(c, final_tiles, impassable_tile, resolve_tile_func)
    local conf = c.tier_conf
    if not conf or not conf.tile then return end

    local tid = resolve_tile_func(conf.tile)
    if not tid then return end

    for _, pt in ipairs(c.pixels) do
        if not conf.ignore_on_void or MapRulesEngine.IsSolidGround(pt, final_tiles, impassable_tile) then
            final_tiles[pt.y][pt.x] = tid
        end
    end
end

-- ============================================================================
-- 板块三：实体与布景散布组件 (Entity & Layout Spawners)
-- ============================================================================

--- 规则: random_pick_one (N 选 1 候选点生成单个实体)
function MapRulesEngine.ApplyRandomPickOne(pixels, final_tiles, tier_conf, impassable_tile, entities)
    local valid_pts = {}
    for _, pt in ipairs(pixels) do
        if not tier_conf.require_solid or MapRulesEngine.IsSolidGround(pt, final_tiles, impassable_tile) then
            table.insert(valid_pts, pt)
        end
    end

    if #valid_pts > 0 then
        local chosen = valid_pts[math.random(#valid_pts)]
        table.insert(entities, Contract.NewEntity(tier_conf.prefab, chosen.x, chosen.y, tier_conf))
    end
end

--- 规则: distributeprefab (密度漫灌散布物，每格独立掷骰)
function MapRulesEngine.ApplyDistributePrefabs(pixels, final_tiles, dist_table, impassable_tile, entities)
    if not dist_table then return end
    for _, pt in ipairs(pixels) do
        if MapRulesEngine.IsSolidGround(pt, final_tiles, impassable_tile) then
            for prefab_name, definition in pairs(dist_table) do
                local conf = type(definition) == "table" and definition or nil
                local density = conf and conf.density or definition
                if type(density) ~= "number" or density ~= density or density < 0 or density > 1 then
                    error("[CelestialMap] " .. tostring(prefab_name) .. ": density must be a number from 0 to 1")
                end
                if math.random() <= density then
                    table.insert(entities, Contract.NewEntity(prefab_name, pt.x, pt.y, conf))
                end
            end
        end
    end
end

--- 规则: countprefab (定量散布物，连通块内随机挑选 N 个不重复点位生成)
function MapRulesEngine.ApplyCountPrefabs(pixels, final_tiles, count_table, impassable_tile, entities)
    if not count_table then return end
    local valid_pts = {}
    for _, pt in ipairs(pixels) do
        if MapRulesEngine.IsSolidGround(pt, final_tiles, impassable_tile) then
            table.insert(valid_pts, pt)
        end
    end
    if #valid_pts == 0 then return end

    for prefab_name, definition in pairs(count_table) do
        local conf = type(definition) == "table" and definition or nil
        local target_count = conf and conf.count or definition
        if type(target_count) ~= "number" or target_count ~= target_count or target_count == math.huge
            or target_count < 0 or target_count ~= math.floor(target_count) then
            error("[CelestialMap] " .. tostring(prefab_name) .. ": count must be a finite, nonnegative integer")
        end
        for _ = 1, target_count do
            if #valid_pts == 0 then break end
            local idx = math.random(#valid_pts)
            local pt = valid_pts[idx]
            table.insert(entities, Contract.NewEntity(prefab_name, pt.x, pt.y, conf))
            table.remove(valid_pts, idx)
        end
    end
end

--- 规则: layout / layouts (连通块内嵌入局部子结构)
function MapRulesEngine.ApplyLayout(pixels, final_tiles, layout_conf, impassable_tile, entities, conf)
    if not layout_conf then return end
    local chosen_layout = nil
    if type(layout_conf) == "table" and #layout_conf > 0 then
        chosen_layout = layout_conf[math.random(#layout_conf)]
    elseif type(layout_conf) == "string" then
        chosen_layout = layout_conf
    end

    if not chosen_layout then return end

    local valid_pts = {}
    for _, pt in ipairs(pixels) do
        if MapRulesEngine.IsSolidGround(pt, final_tiles, impassable_tile) then
            table.insert(valid_pts, pt)
        end
    end

    if #valid_pts > 0 then
        local center_pt = valid_pts[math.random(#valid_pts)]
        table.insert(entities, Contract.NewEntity(chosen_layout, center_pt.x, center_pt.y, conf, "layout"))
    end
end

--- 规则: 常规实体生成（全面支持单体变异 single 与群体变异 cluster）
function MapRulesEngine.ApplyPrefabSpawning(c, final_tiles, impassable_tile, entities)
    local conf = c.tier_conf
    if not conf or not conf.prefab then return end

    local is_cluster_mutated = false
    if conf.mutation and conf.mutation.mode == "cluster" then
        is_cluster_mutated = (math.random() <= (conf.mutation.chance or 0.5))
    end

    for _, pt in ipairs(c.pixels) do
        if not conf.require_solid or MapRulesEngine.IsSolidGround(pt, final_tiles, impassable_tile) then
            local final_prefab = conf.prefab

            if conf.mutation then
                if conf.mutation.mode == "single" then
                    if math.random() <= (conf.mutation.chance or 0.5) then
                        final_prefab = conf.mutation.target_prefab or final_prefab
                    end
                elseif conf.mutation.mode == "cluster" then
                    if is_cluster_mutated then
                        final_prefab = conf.mutation.target_prefab or final_prefab
                    end
                end
            end

            if final_prefab then
                table.insert(entities, Contract.NewEntity(final_prefab, pt.x, pt.y, conf))
            end
        end
    end
end

-- ============================================================================
-- 板块四：虚空射线检测与成对桥梁 (Raycast & Bridge Solvers)
-- ============================================================================

--- 单向虚空射线检测对岸陆地跨距
function MapRulesEngine.ScanVoidRaycast(px, py, final_tiles, width, height, impassable_tile, min_gap, max_gap)
    for _, d in ipairs(SCAN_DIRS) do
        local dx, dy = d[1], d[2]
        local start_x = px + dx
        local start_y = py + dy

        if start_x >= 1 and start_x <= width and start_y >= 1 and start_y <= height
            and final_tiles[start_y][start_x] == impassable_tile then
            for step = 1, max_gap + 1 do
                local tx = px + dx * step
                local ty = py + dy * step
                if tx < 1 or tx > width or ty < 1 or ty > height then break end

                if final_tiles[ty][tx] ~= impassable_tile then
                    if step >= (min_gap + 1) and step <= (max_gap + 1) then
                        return true, { x = px, y = py }
                    end
                    break
                end
            end
        end
    end
    return false, nil
end

--- 双向射线对向成对握手匹配
function MapRulesEngine.MatchPairedBridges(clusters, final_tiles, width, height, impassable_tile, min_gap, max_gap)
    for _, c1 in ipairs(clusters) do
        if not c1.paired_cluster then
            for _, p1 in ipairs(c1.land_pixels) do
                for _, d in ipairs(SCAN_DIRS) do
                    local dx, dy = d[1], d[2]
                    local start_x = p1.x + dx
                    local start_y = p1.y + dy

                    if start_x >= 1 and start_x <= width and start_y >= 1 and start_y <= height
                        and final_tiles[start_y][start_x] == impassable_tile then
                        local void_count = 0
                        local matched_c2, matched_p2

                        for step = 1, max_gap + 1 do
                            local tx = p1.x + dx * step
                            local ty = p1.y + dy * step
                            if tx < 1 or tx > width or ty < 1 or ty > height then break end

                            if final_tiles[ty][tx] == impassable_tile then
                                void_count = void_count + 1
                            else
                                if void_count >= min_gap and void_count <= max_gap then
                                    for _, c2 in ipairs(clusters) do
                                        if c2 ~= c1 and not c2.paired_cluster then
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
end

-- ============================================================================
-- 板块五：静态蓝图精准足迹与防悬空放置 (Blueprint Solvers)
-- ============================================================================

--- 静态蓝图紧凑足迹分析器
function MapRulesEngine.AnalyzeBlueprintFootprint(bp_def, bp_name)
    if cached_blueprint_footprints[bp_name] then
        return cached_blueprint_footprints[bp_name]
    end

    local context = "blueprint " .. tostring(bp_name) .. " (" .. tostring(bp_def.data_path) .. ")"
    local ok, data_module = pcall(require, bp_def.data_path)
    if not ok or not data_module then
        error("[CelestialMap] " .. context .. ": could not load data module: " .. tostring(data_module))
    end
    Contract.ValidateBlueprint(data_module, context, bp_def.solver or "1x1")

    local raw_unpacked = data_module:Unpack()
    local raw_w = data_module.width or 256
    local raw_h = data_module.height or 256

    local ground_grid = nil
    local prefab_grid = nil

    if data_module.is_blueprint and type(raw_unpacked) == "table" and (raw_unpacked.ground or raw_unpacked.prefab) then
        ground_grid = raw_unpacked.ground
        prefab_grid = raw_unpacked.prefab
    else
        ground_grid = raw_unpacked
    end

    local g_grid, g_w, g_h = MapRulesEngine.UnpackGrid4x4(ground_grid, raw_w, raw_h, bp_def.solver)
    local p_grid, p_w, p_h = MapRulesEngine.UnpackGrid4x4(prefab_grid, raw_w, raw_h, bp_def.solver)

    local w = g_w or p_w or raw_w
    local h = g_h or p_h or raw_h

    local min_x, max_x = w, 1
    local min_y, max_y = h, 1
    local has_any_point = false

    local ground_points = {}
    if g_grid then
        for y = 1, h do
            for x = 1, w do
                local cell = g_grid[y] and g_grid[y][x]
                if cell and cell ~= 0 then
                    local col = (type(cell) == "table") and cell.color or cell
                    local tier = (type(cell) == "table") and cell.tier or 1
                    if col and col ~= "" then
                        table.insert(ground_points, { x = x, y = y, col = col:lower(), tier = tier })
                        has_any_point = true
                        if x < min_x then min_x = x end
                        if x > max_x then max_x = x end
                        if y < min_y then min_y = y end
                        if y > max_y then max_y = y end
                    end
                end
            end
        end
    end

    local prefab_points = {}
    local prefab_clusters = {}
    if p_grid then
        local p_clusters = MapRulesEngine.ExtractClusters(p_grid, w, h, function(c) return c ~= nil end)
        for cluster_id, c in ipairs(p_clusters) do
            table.insert(prefab_clusters, {
                id = cluster_id,
                col = c.col:lower(),
                tier = c.tier,
            })
            for _, pt in ipairs(c.pixels) do
                table.insert(prefab_points, {
                    x = pt.x,
                    y = pt.y,
                    col = c.col:lower(),
                    tier = c.tier,
                    cluster_id = cluster_id,
                })
                has_any_point = true
                if pt.x < min_x then min_x = pt.x end
                if pt.x > max_x then max_x = pt.x end
                if pt.y < min_y then min_y = pt.y end
                if pt.y > max_y then max_y = pt.y end
            end
        end
    end

    if not has_any_point then
        return nil
    end

    local cx = bp_def.center and bp_def.center.x or math.floor((min_x + max_x) / 2)
    local cy = bp_def.center and bp_def.center.y or math.floor((min_y + max_y) / 2)

    local offsets = {}
    local offset_keys = {}

    local function add_offset(ox, oy)
        local key = ox .. "_" .. oy
        if not offset_keys[key] then
            offset_keys[key] = true
            table.insert(offsets, { dx = ox, dy = oy })
        end
    end

    local ground_offsets = {}
    for _, pt in ipairs(ground_points) do
        local dx = pt.x - cx
        local dy = pt.y - cy
        table.insert(ground_offsets, { dx = dx, dy = dy, col = pt.col, tier = pt.tier })
        add_offset(dx, dy)
    end

    local prefab_offsets = {}
    for _, pt in ipairs(prefab_points) do
        local dx = pt.x - cx
        local dy = pt.y - cy
        table.insert(prefab_offsets, {
            dx = dx,
            dy = dy,
            col = pt.col,
            tier = pt.tier,
            cluster_id = pt.cluster_id,
        })
        add_offset(dx, dy)
    end

    local footprint = {
        name = bp_name,
        bp_def = bp_def,
        width = (max_x - min_x + 1),
        height = (max_y - min_y + 1),
        cx = cx,
        cy = cy,
        offsets = offsets,
        ground_points = ground_offsets,
        prefab_points = prefab_offsets,
        prefab_clusters = prefab_clusters,
    }

    cached_blueprint_footprints[bp_name] = footprint
    return footprint
end

--- 虚空安全校验
function MapRulesEngine.CanStampBlueprint(target_cx, target_cy, footprint, final_tiles, width, height, impassable_tile)
    for _, off in ipairs(footprint.offsets) do
        local wx = target_cx + off.dx
        local wy = target_cy + off.dy

        if wx < 1 or wx > width or wy < 1 or wy > height then
            return false
        end

        if final_tiles[wy][wx] == impassable_tile then
            return false
        end
    end
    return true
end

--- 将蓝图中的物理地皮与实体精准写入世界
function MapRulesEngine.StampBlueprint(target_cx, target_cy, footprint, final_tiles, entities, resolve_tile_func)
    local bp_def = footprint.bp_def or {}
    local ground_cfg = bp_def.ground or {}
    local prefab_cfg = bp_def.prefab or bp_def.palette or {}

    for _, pt in ipairs(footprint.ground_points or {}) do
        local wx = target_cx + pt.dx
        local wy = target_cy + pt.dy
        local col_lower = pt.col and pt.col:lower() or ""
        local col_cfg = ground_cfg[pt.col] or ground_cfg[col_lower]
        local tier_cfg = col_cfg and col_cfg.tiers and col_cfg.tiers[pt.tier] or (col_cfg and col_cfg.tiers and col_cfg.tiers[1]) or col_cfg

        if tier_cfg and tier_cfg.tile and resolve_tile_func then
            local tid = resolve_tile_func(tier_cfg.tile)
            if tid then
                final_tiles[wy][wx] = tid
            end
        end
    end

    local cluster_mutated = {}
    for _, cluster in ipairs(footprint.prefab_clusters or {}) do
        local col_lower = cluster.col and cluster.col:lower() or ""
        local col_cfg = prefab_cfg[cluster.col] or prefab_cfg[col_lower]
        local tier_cfg = col_cfg and col_cfg.tiers and col_cfg.tiers[cluster.tier] or (col_cfg and col_cfg.tiers and col_cfg.tiers[1]) or col_cfg
        if tier_cfg and tier_cfg.mutation and tier_cfg.mutation.mode == "cluster" then
            cluster_mutated[cluster.id] = (math.random() <= (tier_cfg.mutation.chance or 0.5))
        end
    end

    for _, pt in ipairs(footprint.prefab_points or {}) do
        local wx = target_cx + pt.dx
        local wy = target_cy + pt.dy
        local col_lower = pt.col and pt.col:lower() or ""
        local col_cfg = prefab_cfg[pt.col] or prefab_cfg[col_lower]
        local tier_cfg = col_cfg and col_cfg.tiers and col_cfg.tiers[pt.tier] or (col_cfg and col_cfg.tiers and col_cfg.tiers[1]) or col_cfg

        if tier_cfg then
            local spawn_chance = tier_cfg.chance or 1.0
            if math.random() <= spawn_chance then
                local final_prefab = tier_cfg.prefab

                if tier_cfg.mutation then
                    if tier_cfg.mutation.mode == "single" then
                        if math.random() <= (tier_cfg.mutation.chance or 0.5) then
                            final_prefab = tier_cfg.mutation.target_prefab or final_prefab
                        end
                    elseif tier_cfg.mutation.mode == "cluster" then
                        if cluster_mutated[pt.cluster_id] then
                            final_prefab = tier_cfg.mutation.target_prefab or final_prefab
                        end
                    end
                end

                if final_prefab then
                    table.insert(entities, Contract.NewEntity(final_prefab, wx, wy, tier_cfg))
                end
            end
        end
    end
end

--- 蓝图模式 A：连通块内随机选点放置
function MapRulesEngine.SpawnBlueprintInClusterRandom(pixels, bp_conf, final_tiles, width, height, impassable_tile, entities, resolve_tile_func)
    local bp_def = bp_conf.blueprint_def
    if not bp_def then return end

    local footprint = MapRulesEngine.AnalyzeBlueprintFootprint(bp_def, bp_conf.name)
    if not footprint then return end

    local target_count = bp_conf.count or 1
    local max_attempts = bp_conf.max_attempts or 40

    local valid_pts = {}
    for _, pt in ipairs(pixels) do
        if MapRulesEngine.IsSolidGround(pt, final_tiles, impassable_tile) then
            table.insert(valid_pts, pt)
        end
    end

    local spawned = 0
    while spawned < target_count and #valid_pts > 0 and max_attempts > 0 do
        max_attempts = max_attempts - 1
        local idx = math.random(#valid_pts)
        local center_pt = valid_pts[idx]

        if MapRulesEngine.CanStampBlueprint(center_pt.x, center_pt.y, footprint, final_tiles, width, height, impassable_tile) then
            MapRulesEngine.StampBlueprint(center_pt.x, center_pt.y, footprint, final_tiles, entities, resolve_tile_func)
            spawned = spawned + 1
        end
    end
end

--- 蓝图模式 B：指定锚点精准放置
function MapRulesEngine.SpawnBlueprintAtAnchor(anchor_x, anchor_y, bp_conf, final_tiles, width, height, impassable_tile, entities, resolve_tile_func)
    local bp_def = bp_conf.blueprint_def
    if not bp_def then return end

    local footprint = MapRulesEngine.AnalyzeBlueprintFootprint(bp_def, bp_conf.name)
    if not footprint then return end

    if bp_conf.require_solid then
        if not MapRulesEngine.CanStampBlueprint(anchor_x, anchor_y, footprint, final_tiles, width, height, impassable_tile) then
            return
        end
    end

    MapRulesEngine.StampBlueprint(anchor_x, anchor_y, footprint, final_tiles, entities, resolve_tile_func)
end

return MapRulesEngine
