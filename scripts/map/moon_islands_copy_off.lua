GLOBAL.setmetatable(env, { __index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end })

local forest_map = package.loaded["map/forest_map"]
if not forest_map then
    return
end

local is_expanding = false
local expanded_size = 0
local saved_world_data = nil

-- 1. 动态自适应清理：过滤月岛 Task 并联动移除失效的 SetPiece
AddLevelPreInitAny(function(level)
    if level.location == "forest" then
        -- A. 过滤月岛 Task
        local task_lookup = {}
        if level.tasks then
            local filtered_tasks = {}
            for _, task_name in ipairs(level.tasks) do
                if not string.find(task_name, "MoonIsland") then
                    table.insert(filtered_tasks, task_name)
                    task_lookup[task_name] = true
                end
            end
            level.tasks = filtered_tasks
        end

        -- B. 动态比对：若 SetPiece 指定的 tasks 在主世界均不存在，直接移除（完美解决 BathbombedHotspring 等所有彩蛋）
        if level.set_pieces then
            for sp_name, sp_data in pairs(level.set_pieces) do
                if sp_data.tasks then
                    local has_valid_task = false
                    for _, req_task in ipairs(sp_data.tasks) do
                        if task_lookup[req_task] then
                            has_valid_task = true
                            break
                        end
                    end
                    if not has_valid_task then
                        level.set_pieces[sp_name] = nil
                    end
                end
            end
        end

        -- C. 清理主世界的强制天体实体质检（改由域外生成）
        if level.required_prefabs then
            local filtered_prefabs = {}
            for _, p in ipairs(level.required_prefabs) do
                if not string.find(p, "moon_altar") then
                    table.insert(filtered_prefabs, p)
                end
            end
            level.required_prefabs = filtered_prefabs
        end
    end
end)

-- 2. 劫持 WorldSim 尺寸
if rawget(GLOBAL, "WorldSim") then
    local idx = getmetatable(WorldSim).__index
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

-- 3. 双阶段生成与域外月岛注入
local old_Generate = forest_map.Generate
forest_map.Generate = function(prefab, map_width, map_height, tasks, level, level_type)
    if prefab == "cave" then
        return old_Generate(prefab, map_width, map_height, tasks, level, level_type)
    end

    if is_expanding and saved_world_data then
        -- 第二阶段：极速生成并合成域外月岛
        level.required_prefabs = {}
        level.set_pieces = {}
        level.ocean_prefill_setpieces = {}
        level.ocean_population = {}
        level.overrides = level.overrides or {}
        level.overrides.roads = "never"

        local savedata = old_Generate(prefab, map_width, map_height, tasks, level, level_type)
        if not savedata then
            is_expanding = false
            saved_world_data = nil
            return nil
        end

        local w, h = WorldSim:GetWorldSize()
        local orig_w = saved_world_data.width
        local mainland_offset = -(w - orig_w) * 2

        -- A. 平移主世界实体
        savedata.ents = {}
        for p_name, e_list in pairs(saved_world_data.ents or {}) do
            savedata.ents[p_name] = savedata.ents[p_name] or {}
            for _, ent in ipairs(e_list) do
                table.insert(savedata.ents[p_name], {
                    x = ent.x + mainland_offset,
                    z = ent.z + mainland_offset,
                    id = ent.id,
                    data = ent.data,
                    scenario = ent.scenario,
                })
            end
        end

        -- B. 在域外月岛中心注入天体祭坛、温泉与裂隙
        local moon_center_x = (orig_w + 24 - w / 2.0) * TILE_SCALE
        local moon_center_z = (24 - h / 2.0) * TILE_SCALE

        local moon_core_prefabs = {
            "moon_altar_rock_glass",
            "moon_altar_rock_seed",
            "moon_altar_rock_idol",
            "hotspring",
            "junk_pile_big",
        }
        for _, p_name in ipairs(moon_core_prefabs) do
            savedata.ents[p_name] = savedata.ents[p_name] or {}
            table.insert(savedata.ents[p_name], {
                x = moon_center_x + math.random(-6, 6),
                z = moon_center_z + math.random(-6, 6),
            })
        end

        savedata.ents["moon_fissure"] = savedata.ents["moon_fissure"] or {}
        for i = 1, 4 do
            table.insert(savedata.ents["moon_fissure"], {
                x = moon_center_x + math.random(-12, 12),
                z = moon_center_z + math.random(-12, 12),
            })
        end

        -- C. 平移主世界道路与拓扑
        savedata.map.roads = saved_world_data.roads
        for _, road in pairs(savedata.map.roads or {}) do
            for i = 2, #road do
                road[i][1] = road[i][1] + mainland_offset
                road[i][2] = road[i][2] + mainland_offset
            end
        end

        savedata.map.topology = saved_world_data.topology
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

        savedata.retrofit_nodeidtilemap = true
        is_expanding = false
        saved_world_data = nil
        print("[MoonVoid] 域外虚空月岛生成成功！")
        return savedata
    end

    -- 第一阶段：生成纯大陆与全覆盖原生海洋 Task
    local savedata = old_Generate(prefab, map_width, map_height, tasks, level, level_type)
    if not savedata then
        return nil
    end

    local width, height = WorldSim:GetWorldSize()
    local original_tiles = {}
    for y = 1, height do
        original_tiles[y] = {}
        for x = 1, width do
            original_tiles[y][x] = WorldSim:GetTile(x, y)
        end
    end

    saved_world_data = {
        width = width,
        height = height,
        original_tiles = original_tiles,
        ents = savedata.ents,
        roads = savedata.map.roads,
        topology = savedata.map.topology,
    }

    is_expanding = true
    expanded_size = width + 48
    if expanded_size % 2 ~= width % 2 then
        expanded_size = expanded_size + 1
    end

    return nil
end

-- 4. 铺设域外海岛地皮
AddGlobalClassPostConstruct("map/network", "Graph", function(self)
    local old_GlobalPostPopulate = self.GlobalPostPopulate
    self.GlobalPostPopulate = function(graph_self, entities, w, h)
        if is_expanding and saved_world_data then
            for y = 1, h do
                for x = 1, w do
                    WorldSim:SetTile(x, y, WORLD_TILES.IMPASSABLE)
                end
            end

            -- 还原主世界地皮
            local orig_tiles = saved_world_data.original_tiles
            for y = 1, saved_world_data.height do
                for x = 1, saved_world_data.width do
                    if orig_tiles[y] and orig_tiles[y][x] then
                        WorldSim:SetTile(x, y, orig_tiles[y][x])
                    end
                end
            end

            -- 绘制域外月岛地皮
            local center_tx = saved_world_data.width + 24
            local center_ty = 24
            local island_radius = 10

            for dy = -island_radius, island_radius do
                for dx = -island_radius, island_radius do
                    local dist_sq = dx * dx + dy * dy
                    if dist_sq <= island_radius * island_radius then
                        local target_tx = center_tx + dx
                        local target_ty = center_ty + dy
                        if target_tx <= w and target_ty <= h then
                            if dist_sq > (island_radius - 2) * (island_radius - 2) then
                                WorldSim:SetTile(target_tx, target_ty, WORLD_TILES.PEBBLEBEACH)
                            else
                                WorldSim:SetTile(target_tx, target_ty, WORLD_TILES.METEOR)
                            end
                        end
                    end
                end
            end
        end
        old_GlobalPostPopulate(graph_self, entities, w, h)
    end
end)