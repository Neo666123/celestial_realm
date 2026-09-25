local _G = rawget(_G, "GLOBAL") or _G
local rawget, setmetatable, getmetatable = _G.rawget, _G.setmetatable, _G.getmetatable
local ipairs, pairs, table, math = _G.ipairs, _G.pairs, _G.table, _G.math
local pcall, error, print = _G.pcall, _G.error, _G.print

local MapPipeline = require("map/map_pipeline")
local Contract = require("map/map_contract")
local EntityWriter = require("map/map_entity_writer")
local CelestialEngine = {}

local is_expanding = false
local expanded_size = 0
local cached_world_data = nil
local cached_realm_data = nil
local prepared_realm = nil
local initialized = false

local SYSTEM_OVERRIDE_KEYS = {
    season_start = true, start_location = true, world_size = true,
    islands = true, branching = true, loop = true, layout_mode = true,
    keep_disconnected_tiles = true, no_joining_islands = true, has_ocean = true,
    no_wormholes_to_disconnected_tiles = true, wormhole_prefab = true,
    specialevent = true, roads = true, boons = true, touchstone = true,
    traps = true, poi = true, protected = true, task_set = true,
}

local function ResetExpansion()
    is_expanding = false
    expanded_size = 0
    cached_world_data = nil
    cached_realm_data = nil
    prepared_realm = nil
end

local function WithTemporaryLevel(old_generate, prefab, map_width, map_height, tasks, level, level_type)
    local previous = {
        set_pieces = level.set_pieces,
        ocean_prefill_setpieces = level.ocean_prefill_setpieces,
        ocean_population = level.ocean_population,
        overrides = level.overrides,
    }
    local overrides = Contract.Clone(level.overrides or {})
    level.set_pieces = {}
    level.ocean_prefill_setpieces = {}
    level.ocean_population = {}
    level.overrides = setmetatable({}, {
        __index = function(_, key)
            if overrides[key] ~= nil then return overrides[key] end
            return not SYSTEM_OVERRIDE_KEYS[key] and "never" or nil
        end,
        __newindex = function(_, key, value) overrides[key] = value end,
    })
    local ok, result = pcall(old_generate, prefab, map_width, map_height, tasks, level, level_type)
    level.set_pieces = previous.set_pieces
    level.ocean_prefill_setpieces = previous.ocean_prefill_setpieces
    level.ocean_population = previous.ocean_population
    level.overrides = previous.overrides
    if not ok then
        ResetExpansion()
        error(result, 0)
    end
    return result
end

function CelestialEngine.Init(env)
    if initialized then return end
    local WorldSim = rawget(_G, "WorldSim")
    local package = rawget(_G, "package")
    local forest_map = package and package.loaded and package.loaded["map/forest_map"]
    local AddGlobalClassPostConstruct = env.AddGlobalClassPostConstruct or rawget(_G, "AddGlobalClassPostConstruct")
    if not forest_map or not WorldSim or not AddGlobalClassPostConstruct then return end
    initialized = true

    local idx = getmetatable(WorldSim).__index
    local SetWorldSize_ = idx.SetWorldSize
    local ConvertToTileMap_ = idx.ConvertToTileMap
    idx.SetWorldSize = function(self, width, height)
        if is_expanding and expanded_size > 0 then
            return SetWorldSize_(self, expanded_size, expanded_size)
        end
        return SetWorldSize_(self, width, height)
    end
    idx.ConvertToTileMap = function(self, size)
        return ConvertToTileMap_(self, is_expanding and expanded_size > 0 and expanded_size or size)
    end

    local old_Generate = forest_map.Generate
    forest_map.Generate = function(prefab, map_width, map_height, tasks, level, level_type)
        if prefab == "cave" then
            return old_Generate(prefab, map_width, map_height, tasks, level, level_type)
        end
        if is_expanding and cached_world_data then
            local savedata = WithTemporaryLevel(old_Generate, prefab, map_width, map_height, tasks, level, level_type)
            if not savedata then
                ResetExpansion()
                return nil
            end
            local width, height = WorldSim:GetWorldSize()
            local scale = rawget(_G, "TILE_SCALE") or 4
            local offset_x = -(width - cached_world_data.width) * scale / 2
            local offset_z = -(height - cached_world_data.height) * scale / 2
            savedata.map.roads = Contract.Clone(cached_world_data.roads or {})
            for _, road in pairs(savedata.map.roads) do
                for i = 2, #road do
                    road[i][1] = road[i][1] + offset_x
                    road[i][2] = road[i][2] + offset_z
                end
            end
            savedata.map.topology = Contract.Clone(cached_world_data.topology or {})
            for _, node in ipairs(savedata.map.topology.nodes or {}) do
                if node.x then node.x = node.x + offset_x end
                if node.y then node.y = node.y + offset_z end
                if node.cent then
                    node.cent[1] = node.cent[1] + offset_x
                    node.cent[2] = node.cent[2] + offset_z
                end
                for _, point in ipairs(node.poly or {}) do
                    point[1] = point[1] + offset_x
                    point[2] = point[2] + offset_z
                end
            end

            -- 追加天界专属拓扑节点（按官方规范格式写入冒号，供 gamelogic.lua:564 解析与 retrofit 重算）
            local placement_base_x = cached_world_data.width + 10
            local placement_base_y = 10
            local realm_w = (prepared_realm and prepared_realm.width) or (cached_realm_data and cached_realm_data.width) or 0
            local realm_h = (prepared_realm and prepared_realm.height) or (cached_realm_data and cached_realm_data.height) or 0

            local min_wx = (placement_base_x - width / 2) * scale
            local min_wz = (placement_base_y - height / 2) * scale
            local max_wx = (placement_base_x + realm_w - width / 2) * scale
            local max_wz = (placement_base_y + realm_h - height / 2) * scale
            local cent_x = (min_wx + max_wx) / 2
            local cent_z = (min_wz + max_wz) / 2

            local celestial_node = {
                c = 1,
                cent = { cent_x, cent_z },
                x = cent_x,
                y = cent_z,
                poly = {
                    { min_wx, min_wz },
                    { max_wx, min_wz },
                    { max_wx, max_wz },
                    { min_wx, max_wz },
                },
                tags = { "celestial_realm" },
                type = 0,
                val = 1,
                area = (max_wx - min_wx) * (max_wz - min_wz),
            }

            savedata.map.topology.nodes = savedata.map.topology.nodes or {}
            savedata.map.topology.ids = savedata.map.topology.ids or {}
            table.insert(savedata.map.topology.nodes, celestial_node)
            table.insert(savedata.map.topology.ids, "Celestial:Main")

            local join_islands = not (level.overrides and level.overrides.no_joining_islands)
            savedata.map.tiles, savedata.map.tiledata, savedata.map.nav, savedata.map.adj, savedata.map.nodeidtilemap = WorldSim:GetEncodedMap(join_islands)
            savedata.map.width, savedata.map.height = width, height
            if rawget(_G, "GetWorldTileMap") then savedata.map.world_tile_map = _G.GetWorldTileMap() end
            savedata.retrofit_nodeidtilemap = true
            ResetExpansion()
            return savedata
        end

        local savedata = old_Generate(prefab, map_width, map_height, tasks, level, level_type)
        if not savedata then return nil end
        local width, height = WorldSim:GetWorldSize()
        local original_tiles = {}
        for y = 0, height - 1 do
            original_tiles[y + 1] = {}
            for x = 0, width - 1 do
                original_tiles[y + 1][x + 1] = WorldSim:GetTile(x, y)
            end
        end
        prepared_realm = MapPipeline.PreparePipeline()
        cached_world_data = {
            width = width, height = height, original_tiles = original_tiles,
            mainland_ents = savedata.ents or {}, roads = savedata.map.roads,
            topology = savedata.map.topology,
        }
        expanded_size = math.max(width + prepared_realm.width + 30, height, prepared_realm.height + 30)
        is_expanding = true
        return nil
    end

    AddGlobalClassPostConstruct("map/network", "Graph", function(self)
        local old_GlobalPostPopulate = self.GlobalPostPopulate
        self.GlobalPostPopulate = function(graph_self, entities, width, height)
            if is_expanding and cached_world_data then
                if not cached_realm_data then
                    cached_realm_data = MapPipeline.ExecutePipeline(prepared_realm)
                    Contract.ValidateResult(cached_realm_data)
                end
                local realm = cached_realm_data
                local tiles = rawget(_G, "WORLD_TILES") or rawget(_G, "GROUND") or {}
                local impassable = rawget(tiles, "IMPASSABLE") or 1
                for y = 0, height - 1 do
                    for x = 0, width - 1 do WorldSim:SetTile(x, y, impassable) end
                end
                for y = 0, cached_world_data.height - 1 do
                    for x = 0, cached_world_data.width - 1 do
                        WorldSim:SetTile(x, y, cached_world_data.original_tiles[y + 1][x + 1])
                    end
                end
                local placement = {
                    base_x = cached_world_data.width + 10, base_y = 10,
                    width = width, height = height,
                }
                if placement.base_x + realm.width > width or placement.base_y + realm.height > height then
                    error("[CelestialEngine] realm exceeds the allocated canvas")
                end
                for y = 1, realm.height do
                    for x = 1, realm.width do
                        WorldSim:SetTile(placement.base_x + x - 1, placement.base_y + y - 1, realm.tiles[y][x])
                    end
                end
                for key in pairs(entities) do entities[key] = nil end
                local scale = rawget(_G, "TILE_SCALE") or 4
                local offset_x = -(width - cached_world_data.width) * scale / 2
                local offset_z = -(height - cached_world_data.height) * scale / 2
                for prefab, list in pairs(cached_world_data.mainland_ents) do
                    entities[prefab] = {}
                    for _, ent in ipairs(list) do
                        local record = Contract.Clone(ent)
                        record.x = ent.x + offset_x
                        record.z = ent.z + offset_z
                        table.insert(entities[prefab], record)
                    end
                end
                local stats = EntityWriter.WriteRealm(realm, WorldSim, entities, placement)
                print("[CelestialEngine] realm", realm.width, realm.height, "entities", stats.entities_written,
                    "rejected", stats.entities_rejected, "layouts", stats.layouts_written, "layout_rejected", stats.layouts_rejected)
                for _, warning in ipairs(stats.warnings) do
                    print("[CelestialEngine]", warning.code, warning.message)
                end
            end
            return old_GlobalPostPopulate(graph_self, entities, width, height)
        end
    end)
end

return CelestialEngine