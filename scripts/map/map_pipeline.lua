local GLOBAL = rawget(_G, "GLOBAL") or _G
local rawget = rawget
local ipairs = rawget(GLOBAL, "ipairs")
local pairs = rawget(GLOBAL, "pairs")
local math = rawget(GLOBAL, "math")
local table = rawget(GLOBAL, "table")
local pcall = rawget(GLOBAL, "pcall")
local require = rawget(GLOBAL, "require")
local type = rawget(GLOBAL, "type")
local error = rawget(GLOBAL, "error")
local tostring = rawget(GLOBAL, "tostring")
local print = rawget(GLOBAL, "print")

local RulesEngine = require("map/map_rules_engine")
local Contract = require("map/map_contract")
local TileMap = require("map/config/tile_map")

local MapPipeline = {}

MapPipeline.FLIP_HORIZONTAL = true

MapPipeline.LAYERS = {
    {
        name = "ground",
        data_path = "map/mapdata/map_ground_data",
        config_path = "map/config/config_ground",
        solver = "1x1",
        required = true,
    },
    {
        name = "mutation",
        data_path = "map/mapdata/map_mutation_white_data",
        config_path = "map/config/config_mutation",
        solver = "1x1",
        required = true,
        depends_on = { "ground" },
    },
    {
        name = "layouts",
        data_path = "map/mapdata/map_layout1_data",
        config_path = "map/config/config_layouts",
        solver = "1x1",
        required = true,
        depends_on = { "ground", "mutation" },
    },
}

local function ResolveWorldTile(tile_key)
    return TileMap.ResolveTile(tile_key)
end

local function ResolveTierConfig(col, tier, config_map)
    if not col or not config_map then return nil end
    local col_lower = col:lower()
    local conf = config_map[col] or config_map[col_lower]
    if not conf then return nil end
    return conf.tiers and (conf.tiers[tier] or conf.tiers[1]) or conf
end

local function ProcessLayer(grid, config_map, bp_dict, final_tiles, width, height, impassable_tile, entities)
    if not grid then return end

    -- 数据清洗
    for y = 1, height do
        local row = grid[y]
        if row then
            for x = 1, width do
                local cell = row[x]
                if cell ~= nil then
                    if type(cell) == "string" then
                        row[x] = { color = cell, tier = 1 }
                    elseif type(cell) == "table" and not cell.color then
                        row[x] = { color = cell[1] or "#76a88c", tier = cell.tier or 1 }
                    end
                end
            end
        end
    end

    -- 扫描网格中存在的色号与 Tier
    local present_types = {}
    for y = 1, height do
        local row = grid[y]
        if row then
            for x = 1, width do
                local cell = row[x]
                if cell and cell.color then
                    local key = cell.color:lower() .. "_" .. (cell.tier or 1)
                    if not present_types[key] then
                        present_types[key] = { color = cell.color:lower(), tier = cell.tier or 1 }
                    end
                end
            end
        end
    end

    -- 按各自分配的 dis 距离容差提取连通组
    local clusters = {}
    for _, item in pairs(present_types) do
        local tier_conf = ResolveTierConfig(item.color, item.tier, config_map)
        if tier_conf then
            local dis = tier_conf.dis
            local match_func = function(c)
                if not c or not c.color then return false end
                return c.color:lower() == item.color and (c.tier or 1) == item.tier
            end
            local sub_clusters = RulesEngine.ExtractClusters(grid, width, height, match_func, dis)
            for _, c in ipairs(sub_clusters) do
                c.tier_conf = tier_conf
                table.insert(clusters, c)
            end
        end
    end

    -- 复合节点派发（顺序执行铺地 -> 实体 -> 蓝图抑制）
    for _, c in ipairs(clusters) do
        RulesEngine.ApplyCompositeCluster(c, final_tiles, impassable_tile, entities, width, height, ResolveWorldTile, bp_dict)
    end

    -- 桥梁与射线判定
    RulesEngine.ProcessBridges(clusters, final_tiles, width, height, impassable_tile, entities)
end

local function LoadModule(path, required, layer, diagnostics, loader)
    if type(path) ~= "string" or path == "" then error("[CelestialMap] " .. layer .. ": module path is required") end
    local ok, value = pcall(loader, path)
    if ok and type(value) == "table" then return value end
    local message = path .. ": " .. tostring(value)
    local missing_name = not ok and string.match(tostring(value), "module '([^']+)' not found")
    local missing = (ok and value == nil) or missing_name == path
    if required ~= false or not missing then error("[CelestialMap] " .. layer .. ": " .. message) end
    Contract.Diagnostic(diagnostics, "warning", "optional_layer_missing", layer, message)
end

function MapPipeline.PreparePipeline(options)
    options = options or {}
    local prepared = { layers = {}, diagnostics = {}, width = 0, height = 0, prepared = true }
    local loader = options.load_module or require
    local completed, registered = {}, {}

    for _, info in ipairs(options.layers or MapPipeline.LAYERS) do
        if type(info.name) ~= "string" or registered[info.name] then error("[CelestialMap] layer name missing or duplicated") end
        registered[info.name] = true
        local enabled = info.enabled ~= false
        if not enabled then
            Contract.Diagnostic(prepared.diagnostics, "info", "layer_disabled", info.name, info.reason or "explicitly disabled")
        else
            for _, dependency in ipairs(info.depends_on or {}) do
                if not completed[dependency] then error("[CelestialMap] " .. info.name .. ": dependency must load first: " .. dependency) end
            end
            local module = info.data or LoadModule(info.data_path, info.required, info.name, prepared.diagnostics, loader)
            if module then
                local config = info.config or LoadModule(info.config_path, info.required, info.name, prepared.diagnostics, loader)
                if config then
                    local solver = info.solver or "1x1"
                    local w, h = Contract.ValidateData(module, info.name, solver, prepared.diagnostics)
                    local rules, reserved, policy = Contract.NormalizeConfig(config, info.name, prepared.diagnostics)
                    local raw_grid = module:Unpack()
                    local grid = RulesEngine.UnpackGrid(raw_grid, module.width, module.height, solver)
                    grid = Contract.NormalizeGrid(grid, w, h, rules, reserved, policy, info.name, prepared.diagnostics)
                    local ox, oy = info.offset_x or 0, info.offset_y or 0
                    if type(ox) ~= "number" or type(oy) ~= "number" or ox < 0 or oy < 0 or ox >= math.huge or oy >= math.huge or ox ~= math.floor(ox) or oy ~= math.floor(oy) then
                        error("[CelestialMap] " .. info.name .. ": offsets must be nonnegative integer tile counts")
                    end
                    prepared.layers[#prepared.layers + 1] = { name = info.name, grid = grid, config = rules, width = w, height = h, offset_x = ox, offset_y = oy }
                    prepared.width, prepared.height = math.max(prepared.width, ox + w), math.max(prepared.height, oy + h)
                    completed[info.name] = true
                end
            end
        end
    end

    if #prepared.layers == 0 then error("[CelestialMap] no enabled, valid layers") end

    for _, axis in ipairs({ "width", "height" }) do
        local value = options[axis]
        if value ~= nil then
            if type(value) ~= "number" or value ~= math.floor(value) or value < prepared[axis] or value == math.huge then
                error("[CelestialMap] canvas " .. axis .. " must contain every layer")
            end
            prepared[axis] = value
        end
    end

    prepared.flip_horizontal = options.flip_horizontal
    if prepared.flip_horizontal == nil then prepared.flip_horizontal = MapPipeline.FLIP_HORIZONTAL end
    prepared.blueprints = options.blueprints
    if prepared.blueprints == nil then
        prepared.blueprints = LoadModule("map/config/config_blueprints", false, "blueprints", prepared.diagnostics, loader)
    end

    return prepared
end

function MapPipeline.ExecutePipeline(prepared)
    prepared = prepared or MapPipeline.PreparePipeline()
    if not prepared.prepared then error("[CelestialMap] ExecutePipeline expects PreparePipeline output") end
    local WORLD_TILES = rawget(_G, "WORLD_TILES") or rawget(_G, "GROUND") or {}
    local impassable_tile = rawget(WORLD_TILES, "IMPASSABLE") or 1
    local width, height = prepared.width, prepared.height
    local final_tiles, entities, stats = {}, {}, {}

    for y = 1, height do
        final_tiles[y] = {}
        for x = 1, width do final_tiles[y][x] = impassable_tile end
    end

    for _, layer in ipairs(prepared.layers) do
        local grid = {}
        for y = 1, height do grid[y] = {} end
        for y = 1, layer.height do
            for x = 1, layer.width do
                local target_x = x + layer.offset_x
                if prepared.flip_horizontal then target_x = width - target_x + 1 end
                grid[y + layer.offset_y][target_x] = layer.grid[y][x]
            end
        end
        local before = #entities
        ProcessLayer(grid, layer.config, prepared.blueprints, final_tiles, width, height, impassable_tile, entities)
        stats[#stats + 1] = { name = layer.name, width = layer.width, height = layer.height, entities = #entities - before }
    end

    local result = Contract.ValidateResult({
        schema_version = Contract.SCHEMA_VERSION,
        coordinate_system = Contract.OUTPUT_COORDINATES,
        width = width, height = height, tiles = final_tiles, entities = entities,
        diagnostics = Contract.Clone(prepared.diagnostics), stats = stats,
    })

    for _, diagnostic in ipairs(result.diagnostics) do
        print("[CelestialMap][" .. diagnostic.severity .. "][" .. diagnostic.layer .. "] " .. diagnostic.code .. " " .. diagnostic.message .. (diagnostic.count and (" pixels=" .. diagnostic.count) or ""))
    end
    for _, stat in ipairs(stats) do
        print("[CelestialMap][layer] " .. stat.name .. " " .. stat.width .. "x" .. stat.height .. " entities=" .. stat.entities)
    end

    return result
end

return MapPipeline