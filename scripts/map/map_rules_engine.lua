local GLOBAL = rawget(_G, "GLOBAL") or _G
local rawget = rawget
local ipairs = rawget(GLOBAL, "ipairs")
local pairs = rawget(GLOBAL, "pairs")
local math = rawget(GLOBAL, "math")
local string = rawget(GLOBAL, "string")
local table = rawget(GLOBAL, "table")
local pcall = rawget(GLOBAL, "pcall")
local require = rawget(GLOBAL, "require")
local type = rawget(GLOBAL, "type")
local error = rawget(GLOBAL, "error")
local tostring = rawget(GLOBAL, "tostring")
local tonumber = rawget(GLOBAL, "tonumber")

local Contract = require("map/map_contract")

local MapRulesEngine = {}

local SUB_DIV = 4

local SCAN_DIRS = {
    { 1, 0 },
    { -1, 0 },
    { 0, 1 },
    { 0, -1 },
}

local cached_blueprint_footprints = {}

-- ============================================================================
-- 1. 空间拓扑与打组
-- ============================================================================

function MapRulesEngine.UnpackGrid(raw_grid, width, height, solver_mode)
    if not raw_grid then return raw_grid, width, height end

    local scale = 1
    if type(solver_mode) == "string" then
        local matched = string.match(solver_mode, "^(%d+)x%d+$")
        scale = tonumber(matched) or 1
    elseif type(solver_mode) == "number" then
        scale = math.floor(solver_mode)
    end

    if scale <= 1 then
        return raw_grid, width, height
    end

    local scaled_width = math.floor(width / scale)
    local scaled_height = math.floor(height / scale)
    local scaled_grid = {}
    local center_offset = math.ceil(scale / 2)

    for y = 1, scaled_height do
        scaled_grid[y] = {}
        for x = 1, scaled_width do
            local src_x = (x - 1) * scale + center_offset
            local src_y = (y - 1) * scale + center_offset
            scaled_grid[y][x] = raw_grid[src_y] and raw_grid[src_y][src_x]
        end
    end

    return scaled_grid, scaled_width, scaled_height
end

local function BuildOffsets(dis)
    local offsets = {}
    local step = dis or 1
    for dy = -step, step do
        for dx = -step, step do
            if dx ~= 0 or dy ~= 0 then
                if math.max(math.abs(dx), math.abs(dy)) <= step then
                    table.insert(offsets, { dx, dy })
                end
            end
        end
    end
    return offsets
end

function MapRulesEngine.ExtractClusters(grid, width, height, match_func, dis)
    local visited = {}
    for y = 1, height do
        visited[y] = {}
    end

    local clusters = {}

    if dis == 0 then
        for y = 1, height do
            for x = 1, width do
                local cell = grid[y] and grid[y][x]
                if cell and match_func(cell) then
                    table.insert(clusters, {
                        col = cell.color,
                        tier = cell.tier or 1,
                        pixels = { { x = x, y = y } },
                    })
                end
            end
        end
        return clusters
    end

    if dis == nil then
        local merged_by_key = {}
        for y = 1, height do
            for x = 1, width do
                local cell = grid[y] and grid[y][x]
                if cell and match_func(cell) then
                    local key = tostring(cell.color) .. "_" .. tostring(cell.tier or 1)
                    if not merged_by_key[key] then
                        merged_by_key[key] = {
                            col = cell.color,
                            tier = cell.tier or 1,
                            pixels = {},
                        }
                        table.insert(clusters, merged_by_key[key])
                    end
                    table.insert(merged_by_key[key].pixels, { x = x, y = y })
                end
            end
        end
        return clusters
    end

    local search_offsets = BuildOffsets(dis)
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

                    for _, off in ipairs(search_offsets) do
                        local nx = curr.x + off[1]
                        local ny = curr.y + off[2]
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

function MapRulesEngine.IsSolidGround(pt, final_tiles, impassable_tile)
    local tile = final_tiles[pt.y] and final_tiles[pt.y][pt.x]
    return tile ~= nil and tile ~= impassable_tile
end

-- ============================================================================
-- 2. 抽签工具
-- ============================================================================

local function PickWeighted(distribute_table)
    if not distribute_table or type(distribute_table) ~= "table" then
        return nil
    end

    local total = 0.0
    for _, w in pairs(distribute_table) do
        if type(w) == "number" and w > 0 then
            total = total + w
        end
    end

    if total <= 0 then return nil end

    local roll = math.random() * total
    local acc = 0.0
    for name, w in pairs(distribute_table) do
        if type(w) == "number" and w > 0 then
            acc = acc + w
            if roll <= acc then
                return name
            end
        end
    end

    return nil
end

local function PopRandomPoint(pool)
    local len = #pool
    if len == 0 then return nil end
    local idx = math.random(len)
    local pt = pool[idx]
    pool[idx] = pool[len]
    pool[len] = nil
    return pt
end

-- ============================================================================
-- 3. 蓝图拓印
-- ============================================================================

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

    local g_grid, g_w, g_h = MapRulesEngine.UnpackGrid(ground_grid, raw_w, raw_h, bp_def.solver)
    local p_grid, p_w, p_h = MapRulesEngine.UnpackGrid(prefab_grid, raw_w, raw_h, bp_def.solver)

    local w = g_w or p_w or raw_w
    local h = g_h or p_h or raw_h

    local min_x, max_x = w, 1
    local min_y, max_y = h, 1
    local ground_points = {}
    local prefab_points = {}

    if g_grid then
        for y = 1, h do
            for x = 1, w do
                local cell = g_grid[y] and g_grid[y][x]
                if cell and cell ~= 0 then
                    local col = (type(cell) == "table") and cell.color or cell
                    local tier = (type(cell) == "table") and cell.tier or 1
                    if col and col ~= "" then
                        table.insert(ground_points, { x = x, y = y, col = col:lower(), tier = tier })
                        if x < min_x then min_x = x end
                        if x > max_x then max_x = x end
                        if y < min_y then min_y = y end
                        if y > max_y then max_y = y end
                    end
                end
            end
        end
    end

    if p_grid then
        for y = 1, h do
            for x = 1, w do
                local cell = p_grid[y] and p_grid[y][x]
                if cell and cell ~= 0 then
                    local col = (type(cell) == "table") and cell.color or cell
                    local tier = (type(cell) == "table") and cell.tier or 1
                    if col and col ~= "" then
                        table.insert(prefab_points, { x = x, y = y, col = col:lower(), tier = tier })
                        if x < min_x then min_x = x end
                        if x > max_x then max_x = x end
                        if y < min_y then min_y = y end
                        if y > max_y then max_y = y end
                    end
                end
            end
        end
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
        table.insert(prefab_offsets, { dx = dx, dy = dy, col = pt.col, tier = pt.tier })
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
    }

    cached_blueprint_footprints[bp_name] = footprint
    return footprint
end

function MapRulesEngine.CanStampBlueprint(target_cx, target_cy, footprint, final_tiles, width, height, impassable_tile)
    for _, off in ipairs(footprint.offsets) do
        local wx = target_cx + off.dx
        local wy = target_cy + off.dy
        if wx < 1 or wx > width or wy < 1 or wy > height then return false end
        if final_tiles[wy][wx] == impassable_tile then return false end
    end
    return true
end

function MapRulesEngine.StampBlueprint(target_cx, target_cy, footprint, final_tiles, entities, resolve_tile_func)
    local bp_def = footprint.bp_def or {}
    local ground_cfg = bp_def.ground or {}
    local prefab_cfg = bp_def.prefab or bp_def.palette or {}

    for _, pt in ipairs(footprint.ground_points or {}) do
        local wx = target_cx + pt.dx
        local wy = target_cy + pt.dy
        local col_cfg = ground_cfg[pt.col]
        local tier_cfg = col_cfg and col_cfg.tiers and col_cfg.tiers[pt.tier] or col_cfg

        if tier_cfg and tier_cfg.tile and resolve_tile_func then
            local tid = resolve_tile_func(tier_cfg.tile)
            if tid then final_tiles[wy][wx] = tid end
        end
    end

    for _, pt in ipairs(footprint.prefab_points or {}) do
        local wx = target_cx + pt.dx
        local wy = target_cy + pt.dy
        local col_cfg = prefab_cfg[pt.col]
        local tier_cfg = col_cfg and col_cfg.tiers and col_cfg.tiers[pt.tier] or col_cfg

        if tier_cfg and tier_cfg.prefab then
            local spawn_chance = tier_cfg.chance or 1.0
            if math.random() <= spawn_chance then
                table.insert(entities, Contract.NewEntity(tier_cfg.prefab, wx, wy, tier_cfg))
            end
        end
    end
end

-- ============================================================================
-- 4. 复合节点解算 (Tile -> Blueprint -> Prefab)
-- ============================================================================

function MapRulesEngine.ApplyCompositeCluster(c, final_tiles, impassable_tile, entities, width, height, resolve_tile_func, bp_dict)
    local conf = c.tier_conf
    if not conf or conf.rule then return end

    if conf.chance and math.random() > conf.chance then
        return
    end

    local require_solid = (conf.require_solid ~= false)

    -- 1. 地皮
    local tile_cfg = conf.tile or conf.tiles
    if tile_cfg and resolve_tile_func then
        -- 纯粹依据色块卡片的 require_solid：为 true 时只变异已有陆地，虚空直接忽略；为 false 时允许向虚空铺地造岛
        local tile_solid = require_solid
        if type(tile_cfg) == "table" and tile_cfg.require_solid ~= nil then
            tile_solid = (tile_cfg.require_solid ~= false)
        end

        if type(tile_cfg) == "string" then
            local tid = resolve_tile_func(tile_cfg)
            if tid and tid ~= impassable_tile then
                for _, pt in ipairs(c.pixels) do
                    if not tile_solid or MapRulesEngine.IsSolidGround(pt, final_tiles, impassable_tile) then
                        final_tiles[pt.y][pt.x] = tid
                    end
                end
            end
        elseif type(tile_cfg) == "table" then
            if tile_cfg.distribute then
                for _, pt in ipairs(c.pixels) do
                    if not tile_solid or MapRulesEngine.IsSolidGround(pt, final_tiles, impassable_tile) then
                        local chosen_name = PickWeighted(tile_cfg.distribute)
                        if chosen_name then
                            local tid = resolve_tile_func(chosen_name)
                            if tid and tid ~= impassable_tile then
                                final_tiles[pt.y][pt.x] = tid
                            end
                        end
                    end
                end
            elseif tile_cfg.count then
                local valid_pool = {}
                for _, pt in ipairs(c.pixels) do
                    if not tile_solid or MapRulesEngine.IsSolidGround(pt, final_tiles, impassable_tile) then
                        table.insert(valid_pool, pt)
                    end
                end
                for t_name, t_num in pairs(tile_cfg.count) do
                    local tid = resolve_tile_func(t_name)
                    if tid and tid ~= impassable_tile then
                        for _ = 1, t_num do
                            local pt = PopRandomPoint(valid_pool)
                            if not pt then break end
                            final_tiles[pt.y][pt.x] = tid
                        end
                    end
                end
            end
        end
    end

    local occupied = {}

    -- 2. 蓝图
    local bp_cfg = conf.blueprints or conf.blueprint
    if bp_cfg and bp_dict then
        local bp_solid = require_solid
        if type(bp_cfg) == "table" and bp_cfg.require_solid ~= nil then
            bp_solid = (bp_cfg.require_solid ~= false)
        end

        local bp_plan = {}
        if type(bp_cfg) == "string" then
            table.insert(bp_plan, { name = bp_cfg, count = 1 })
        elseif type(bp_cfg) == "table" then
            if bp_cfg.count then
                if type(bp_cfg.count) == "table" then
                    for b_name, b_count in pairs(bp_cfg.count) do
                        table.insert(bp_plan, { name = b_name, count = b_count })
                    end
                elseif type(bp_cfg.count) == "number" and bp_cfg.name then
                    table.insert(bp_plan, { name = bp_cfg.name, count = bp_cfg.count })
                end
            elseif bp_cfg.name then
                table.insert(bp_plan, { name = bp_cfg.name, count = 1 })
            end
        end

        local valid_anchors = {}
        for _, pt in ipairs(c.pixels) do
            if not bp_solid or MapRulesEngine.IsSolidGround(pt, final_tiles, impassable_tile) then
                table.insert(valid_anchors, pt)
            end
        end

        for _, plan in ipairs(bp_plan) do
            local bp_def = bp_dict[plan.name]
            if bp_def then
                local footprint = MapRulesEngine.AnalyzeBlueprintFootprint(bp_def, plan.name)
                if footprint then
                    local stamped = 0
                    while stamped < plan.count and #valid_anchors > 0 do
                        local anchor = PopRandomPoint(valid_anchors)
                        local can_stamp = true
                        if bp_solid then
                            can_stamp = MapRulesEngine.CanStampBlueprint(anchor.x, anchor.y, footprint, final_tiles, width, height, impassable_tile)
                        end
                        if can_stamp then
                            MapRulesEngine.StampBlueprint(anchor.x, anchor.y, footprint, final_tiles, entities, resolve_tile_func)
                            stamped = stamped + 1
                            for _, off in ipairs(footprint.offsets) do
                                local ox = anchor.x + off.dx
                                local oy = anchor.y + off.dy
                                occupied[oy] = occupied[oy] or {}
                                occupied[oy][ox] = true
                            end
                        end
                    end
                end
            end
        end
    end

    -- 3. 实体
    local pf_cfg = conf.prefabs or conf.prefab
    if pf_cfg then
        local pf_solid = require_solid
        if type(pf_cfg) == "table" and pf_cfg.require_solid ~= nil then
            pf_solid = (pf_cfg.require_solid ~= false)
        end

        if type(pf_cfg) == "string" then
            local available = {}
            for _, pt in ipairs(c.pixels) do
                if not (occupied[pt.y] and occupied[pt.y][pt.x]) then
                    if not pf_solid or MapRulesEngine.IsSolidGround(pt, final_tiles, impassable_tile) then
                        table.insert(available, pt)
                    end
                end
            end
            local chosen = PopRandomPoint(available)
            if chosen then
                table.insert(entities, Contract.NewEntity(pf_cfg, chosen.x, chosen.y, conf))
            end
        elseif type(pf_cfg) == "table" then
            if pf_cfg.count then
                local available = {}
                for _, pt in ipairs(c.pixels) do
                    if not (occupied[pt.y] and occupied[pt.y][pt.x]) then
                        if not pf_solid or MapRulesEngine.IsSolidGround(pt, final_tiles, impassable_tile) then
                            table.insert(available, pt)
                        end
                    end
                end

                if type(pf_cfg.count) == "table" then
                    for p_name, p_num in pairs(pf_cfg.count) do
                        for _ = 1, p_num do
                            local pt = PopRandomPoint(available)
                            if not pt then break end
                            table.insert(entities, Contract.NewEntity(p_name, pt.x, pt.y, pf_cfg))
                        end
                    end
                elseif type(pf_cfg.count) == "number" and pf_cfg.distribute then
                    for _ = 1, pf_cfg.count do
                        local pt = PopRandomPoint(available)
                        if not pt then break end
                        local chosen_name = PickWeighted(pf_cfg.distribute)
                        if chosen_name then
                            table.insert(entities, Contract.NewEntity(chosen_name, pt.x, pt.y, pf_cfg))
                        end
                    end
                end
            end

            if pf_cfg.distribute and (pf_cfg.density or not pf_cfg.count) then
                local density = pf_cfg.density or 0.1
                for _, pt in ipairs(c.pixels) do
                    if not (occupied[pt.y] and occupied[pt.y][pt.x]) then
                        if not pf_solid or MapRulesEngine.IsSolidGround(pt, final_tiles, impassable_tile) then
                            for sy = 1, SUB_DIV do
                                for sx = 1, SUB_DIV do
                                    if math.random() <= density then
    local chosen_name = PickWeighted(pf_cfg.distribute)
    if chosen_name then
        local sub_x = (pt.x - 1) + (sx - 0.5) / SUB_DIV
        local sub_y = (pt.y - 1) + (sy - 0.5) / SUB_DIV
        table.insert(entities, Contract.NewEntity(chosen_name, sub_x, sub_y, pf_cfg))
    end
end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- 5. 桥梁与射线
-- ============================================================================

function MapRulesEngine.FilterEdgePixels(pixels, final_tiles, width, height, impassable_tile)
    local valid_edge = {}
    for _, p in ipairs(pixels) do
        if MapRulesEngine.IsSolidGround(p, final_tiles, impassable_tile) then
            local is_edge = false
            for _, off in ipairs(SCAN_DIRS) do
                local nx = p.x + off[1]
                local ny = p.y + off[2]
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

function MapRulesEngine.MatchPairedBridges(clusters, final_tiles, width, height, impassable_tile, min_gap, max_gap)
    for _, c in ipairs(clusters) do
        if not c.land_pixels then
            c.land_pixels = MapRulesEngine.FilterEdgePixels(c.pixels, final_tiles, width, height, impassable_tile)
        end
    end

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

function MapRulesEngine.ProcessBridges(clusters, final_tiles, width, height, impassable_tile, entities)
    local bridge_clusters = {}
    for _, c in ipairs(clusters) do
        local conf = c.tier_conf
        if conf and (conf.rule == "raycast_bridge" or conf.rule == "paired_bridge") then
            c.land_pixels = MapRulesEngine.FilterEdgePixels(c.pixels, final_tiles, width, height, impassable_tile)
            if #c.land_pixels > 0 then
                table.insert(bridge_clusters, c)
            end
        end
    end

    if #bridge_clusters == 0 then return end

    MapRulesEngine.MatchPairedBridges(bridge_clusters, final_tiles, width, height, impassable_tile, 1, 10)

    for _, c in ipairs(bridge_clusters) do
        if c.tier_conf.rule == "paired_bridge" and c.paired_cluster and not c.spawn then
            local chance = c.tier_conf.pair_chance or 0.30
            if math.random() <= chance then
                c.spawn = true
                c.paired_cluster.spawn = true
            end
        end
    end

    for _, c in ipairs(bridge_clusters) do
        if c.tier_conf.rule == "raycast_bridge" then
            local min_gap = c.tier_conf.min_gap or 1
            local max_gap = c.tier_conf.max_gap or 10
            for _, p in ipairs(c.land_pixels) do
                local ok, pt = MapRulesEngine.ScanVoidRaycast(p.x, p.y, final_tiles, width, height, impassable_tile, min_gap, max_gap)
                if ok then
                    c.chosen = pt
                    c.spawn = true
                    break
                end
            end
        end
    end

    for _, c in ipairs(bridge_clusters) do
        if c.spawn and c.chosen and c.tier_conf.prefab then
            table.insert(entities, Contract.NewEntity(c.tier_conf.prefab, c.chosen.x, c.chosen.y, c.tier_conf))
        end
    end
end

return MapRulesEngine