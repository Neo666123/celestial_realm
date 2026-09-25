local CelestialEngine = {}
local _G = rawget(_G, "GLOBAL") or _G

local is_expanding = false
local expanded_size = 0
local cached_world_data = nil
local pass1_expand_offset = 0

local function IsPointInPoly(px, pz, poly)
    if not poly or #poly < 3 then return false end
    local inside = false
    local j = #poly
    for i = 1, #poly do
        local xi, zi = poly[i][1], poly[i][2]
        local xj, zj = poly[j][1], poly[j][2]
        if ((zi > pz) ~= (zj > pz)) and (px < (xj - xi) * (pz - zi) / (zj - zi) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

local function IsVoidTask(task_id, prefixes)
    for _, prefix in ipairs(prefixes) do
        if string.find(task_id, prefix) ~= nil then
            return true
        end
    end
    return false
end

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

function CelestialEngine.Init(env, custom_tasks, void_prefixes)
    custom_tasks = custom_tasks or { "Rift_Celestial_Domain" }
    void_prefixes = void_prefixes or { "Rift_Celestial" }

    local AddLevelPreInitAny = env.AddLevelPreInitAny or _G.AddLevelPreInitAny
    local AddGlobalClassPostConstruct = env.AddGlobalClassPostConstruct or _G.AddGlobalClassPostConstruct
    local WorldSim = rawget(_G, "WorldSim")
    local TILE_SCALE = rawget(_G, "TILE_SCALE") or 4
    local WORLD_TILES = rawget(_G, "WORLD_TILES")

    local forest_map = _G.package.loaded["map/forest_map"]
    if not forest_map then return end

    AddLevelPreInitAny(function(level)
        if level.location == "forest" and level.tasks then
            for _, task_name in ipairs(custom_tasks) do
                if not table.contains(level.tasks, task_name) then
                    table.insert(level.tasks, task_name)
                end
            end
        end
    end)

    if WorldSim then
        local idx = getmetatable(WorldSim).__index
        local SetWorldSize_ = idx.SetWorldSize
        local ConvertToTileMap_ = idx.ConvertToTileMap

        idx.SetWorldSize = function(self, a, b)
            if is_expanding and expanded_size > 0 then
                SetWorldSize_(self, expanded_size, expanded_size)
            elseif pass1_expand_offset > 0 then
                SetWorldSize_(self, a + pass1_expand_offset, b + pass1_expand_offset)
            else
                SetWorldSize_(self, a, b)
            end
        end
        idx.ConvertToTileMap = function(self, x)
            if is_expanding and expanded_size > 0 then
                ConvertToTileMap_(self, expanded_size)
            elseif pass1_expand_offset > 0 then
                ConvertToTileMap_(self, x + pass1_expand_offset)
            else
                ConvertToTileMap_(self, x)
            end
        end
    end

    local old_Generate = forest_map.Generate
    forest_map.Generate = function(prefab, map_width, map_height, tasks, level, level_type)
        if prefab == "cave" then return old_Generate(prefab, map_width, map_height, tasks, level, level_type) end

        -- [[ 第二阶段：扩容、地皮无损还原与虚空拼接 ]] --
        if is_expanding and cached_world_data then
            pass1_expand_offset = 0
            
            level.required_prefabs = {}
            level.set_pieces = {}
            level.ocean_prefill_setpieces = {}
            level.ocean_population = {}

            local orig_overrides = level.overrides or {}
            level.overrides = setmetatable({}, {
                __index = function(t, k)
                    if orig_overrides[k] ~= nil then
                        return orig_overrides[k]
                    end
                    if SYSTEM_OVERRIDE_KEYS[k] then
                        return nil
                    end
                    return "never"
                end,
                __newindex = function(t, k, v)
                    orig_overrides[k] = v
                end,
            })

            local savedata = old_Generate(prefab, map_width, map_height, tasks, level, level_type)
            if not savedata then
                is_expanding = false
                cached_world_data = nil
                return nil
            end

            local w, h = WorldSim:GetWorldSize()
            local orig_w = cached_world_data.width
            local mainland_offset = -(w - orig_w) * 2

            local target_base_tx = orig_w + 10
            local target_base_ty = 10
            local delta_x = (target_base_tx - cached_world_data.min_tx - (w - orig_w) / 2) * TILE_SCALE
            local delta_z = (target_base_ty - cached_world_data.min_ty - (w - orig_w) / 2) * TILE_SCALE

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
            for p_name, list in pairs(cached_world_data.void_ents) do
                savedata.ents[p_name] = savedata.ents[p_name] or {}
                for _, ent in ipairs(list) do
                    table.insert(savedata.ents[p_name], {
                        x = ent.x + delta_x,
                        z = ent.z + delta_z,
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
            for idx, node in ipairs(savedata.map.topology.nodes or {}) do
                local node_id = savedata.map.topology.ids[idx] or ""
                local is_void = IsVoidTask(node_id, void_prefixes)
                local off_x = is_void and delta_x or mainland_offset
                local off_z = is_void and delta_z or mainland_offset

                node.x = node.x + off_x
                node.y = node.y + off_z
                if node.cent then node.cent[1] = node.cent[1] + off_x; node.cent[2] = node.cent[2] + off_z end
                if node.poly then
                    for _, pt in ipairs(node.poly) do
                        pt[1] = pt[1] + off_x
                        pt[2] = pt[2] + off_z
                    end
                end
            end

            if cached_world_data.crater_center then
                savedata.map.topology.celestial_crater_center = {
                    x = cached_world_data.crater_center.x + mainland_offset,
                    z = cached_world_data.crater_center.z + mainland_offset,
                }
            end

            for y = 1, cached_world_data.height do
                for x = 1, cached_world_data.width do
                    local t = cached_world_data.original_tiles[y] and cached_world_data.original_tiles[y][x]
                    if t then WorldSim:SetTile(x, y, t) end
                end
            end

            local base_x = cached_world_data.width + 10
            local base_y = 10
            for _, pt in ipairs(cached_world_data.void_tiles) do
                local tx, ty = base_x + pt.x, base_y + pt.y
                if tx <= w and ty <= h then WorldSim:SetTile(tx, ty, pt.tile) end
            end

            local join_islands = not (level.overrides and level.overrides.no_joining_islands)
            savedata.map.tiles, savedata.map.tiledata, savedata.map.nav, savedata.map.adj, savedata.map.nodeidtilemap = WorldSim:GetEncodedMap(join_islands)
            if rawget(_G, "GetWorldTileMap") then savedata.map.world_tile_map = _G.GetWorldTileMap() end

            savedata.retrofit_nodeidtilemap = true
            is_expanding = false
            cached_world_data = nil
            return savedata
        end

        -- [[ 第一阶段：精准采样与浅海邻域膨胀抹平 ]] --
        pass1_expand_offset = 50
        local savedata = old_Generate(prefab, map_width, map_height, tasks, level, level_type)
        pass1_expand_offset = 0
        
        if not savedata then return nil end

        local width, height = WorldSim:GetWorldSize()
        local void_polys = {}

        for idx, node_id in ipairs(savedata.map.topology.ids or {}) do
            if IsVoidTask(node_id, void_prefixes) then
                local node = savedata.map.topology.nodes[idx]
                if node and node.poly then table.insert(void_polys, node.poly) end
            end
        end

        if #void_polys == 0 then return savedata end

        local function IsInVoidIsland(wx, wz)
            for _, poly in ipairs(void_polys) do
                if IsPointInPoly(wx, wz, poly) then return true end
            end
            return false
        end

        local original_tiles = {}
        local raw_void_tiles = {}
        local actual_min_tx, actual_max_tx = math.huge, -math.huge
        local actual_min_ty, actual_max_ty = math.huge, -math.huge

        for y = 1, height do
            original_tiles[y] = {}
            for x = 1, width do
                local tile = WorldSim:GetTile(x, y)
                original_tiles[y][x] = tile

                local wx = (x - width / 2.0) * TILE_SCALE
                local wz = (y - height / 2.0) * TILE_SCALE

                if IsInVoidIsland(wx, wz) then
                    if tile == WORLD_TILES.FUNGUSMOON then
                        table.insert(raw_void_tiles, { x = x, y = y, tile = tile })
                        if x < actual_min_tx then actual_min_tx = x end
                        if x > actual_max_tx then actual_max_tx = x end
                        if y < actual_min_ty then actual_min_ty = y end
                        if y > actual_max_ty then actual_max_ty = y end
                        original_tiles[y][x] = WORLD_TILES.OCEAN_ROUGH
                    end
                end
            end
        end

        if #raw_void_tiles == 0 then return savedata end

        local DILATION_RADIUS = 4
        for _, pt in ipairs(raw_void_tiles) do
            for dy = -DILATION_RADIUS, DILATION_RADIUS do
                for dx = -DILATION_RADIUS, DILATION_RADIUS do
                    if dx * dx + dy * dy <= DILATION_RADIUS * DILATION_RADIUS then
                        local nx, ny = pt.x + dx, pt.y + dy
                        if nx >= 1 and nx <= width and ny >= 1 and ny <= height then
                            local t = original_tiles[ny] and original_tiles[ny][nx]
                            if t == WORLD_TILES.OCEAN_COASTAL or t == WORLD_TILES.OCEAN_SWELL or t == WORLD_TILES.OCEAN_BRINEPOOL_SHORE then
                                original_tiles[ny][nx] = WORLD_TILES.OCEAN_ROUGH
                            end
                        end
                    end
                end
            end
        end

        local void_tiles = {}
        for _, pt in ipairs(raw_void_tiles) do
            table.insert(void_tiles, {
                x = pt.x - actual_min_tx,
                y = pt.y - actual_min_ty,
                tile = pt.tile,
            })
        end

        local span_x = actual_max_tx - actual_min_tx + 1
        local span_y = actual_max_ty - actual_min_ty + 1
        local crater_tx = (actual_min_tx + actual_max_tx) / 2.0
        local crater_ty = (actual_min_ty + actual_max_ty) / 2.0
        local crater_center = {
            x = (crater_tx - width / 2.0) * TILE_SCALE,
            z = (crater_ty - height / 2.0) * TILE_SCALE,
        }

        local mainland_ents = {}
        local void_ents = {}
        for prefab_name, ent_list in pairs(savedata.ents or {}) do
            for _, ent in ipairs(ent_list) do
                if IsInVoidIsland(ent.x, ent.z) then
                    void_ents[prefab_name] = void_ents[prefab_name] or {}
                    table.insert(void_ents[prefab_name], ent)
                else
                    mainland_ents[prefab_name] = mainland_ents[prefab_name] or {}
                    table.insert(mainland_ents[prefab_name], ent)
                end
            end
        end

        cached_world_data = {
            width = width, height = height, min_tx = actual_min_tx, min_ty = actual_min_ty,
            span_x = span_x, span_y = span_y, crater_center = crater_center,
            void_tiles = void_tiles, original_tiles = original_tiles,
            mainland_ents = mainland_ents, void_ents = void_ents,
            roads = savedata.map.roads, topology = savedata.map.topology,
        }

        is_expanding = true
        expanded_size = width + span_x + 20
        if expanded_size % 2 ~= width % 2 then expanded_size = expanded_size + 1 end
        return nil
    end

    AddGlobalClassPostConstruct("map/network", "Graph", function(self)
        local old_GlobalPostPopulate = self.GlobalPostPopulate
        self.GlobalPostPopulate = function(graph_self, entities, w, h)
            if is_expanding and cached_world_data then
                for y = 1, h do
                    for x = 1, w do WorldSim:SetTile(x, y, WORLD_TILES.IMPASSABLE) end
                end
                local orig_tiles = cached_world_data.original_tiles
                for y = 1, cached_world_data.height do
                    for x = 1, cached_world_data.width do
                        if orig_tiles[y] and orig_tiles[y][x] then WorldSim:SetTile(x, y, orig_tiles[y][x]) end
                    end
                end
                local base_x = cached_world_data.width + 10
                local base_y = 10
                for _, pt in ipairs(cached_world_data.void_tiles) do
                    local tx, ty = base_x + pt.x, base_y + pt.y
                    if tx <= w and ty <= h then WorldSim:SetTile(tx, ty, pt.tile) end
                end
            end
            old_GlobalPostPopulate(graph_self, entities, w, h)
        end
    end)
end

return CelestialEngine