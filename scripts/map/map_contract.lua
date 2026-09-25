local Contract = {}

Contract.SCHEMA_VERSION = 1
Contract.INPUT_COORDINATES = "pixel_grid_1based"
Contract.OUTPUT_COORDINATES = "tile_grid_1based"

local function Fail(context, message)
    error("[CelestialMap] " .. context .. ": " .. message, 2)
end

local function IsFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function PositiveInteger(value)
    return IsFinite(value) and value >= 1 and value == math.floor(value)
end

function Contract.Clone(value, seen)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "string" then return value end
    if kind == "number" and IsFinite(value) then return value end
    if kind ~= "table" then Fail("save data", "only finite, serializable values are supported") end
    seen = seen or {}
    if seen[value] then Fail("save data", "cyclic tables are not supported") end
    seen[value] = true
    local copy = {}
    for k, v in pairs(value) do
        if type(k) ~= "string" and type(k) ~= "number" then Fail("save data", "invalid table key") end
        if type(k) == "number" and not IsFinite(k) then Fail("save data", "table keys must be finite") end
        copy[k] = Contract.Clone(v, seen)
    end
    seen[value] = nil
    return copy
end

function Contract.Diagnostic(diagnostics, severity, code, layer, message, count)
    diagnostics[#diagnostics + 1] = {
        severity = severity, code = code, layer = layer, message = message, count = count,
    }
end

function Contract.CheckVersion(value, context, diagnostics)
    if value.schema_version == nil then
        if diagnostics then
            Contract.Diagnostic(diagnostics, "info", "legacy_schema", context, "unversioned input adapted to schema 1")
        end
    elseif value.schema_version ~= Contract.SCHEMA_VERSION then
        Fail(context, "unsupported schema_version " .. tostring(value.schema_version))
    end
end

function Contract.ValidateData(module, context, solver, diagnostics)
    if type(module) ~= "table" then Fail(context, "data module must return a table") end
    Contract.CheckVersion(module, context, diagnostics)
    if module.coordinate_system ~= nil and module.coordinate_system ~= Contract.INPUT_COORDINATES then
        Fail(context, "expected coordinate_system " .. Contract.INPUT_COORDINATES)
    end
    if module.cell_format ~= nil and module.cell_format ~= "color_tier" then Fail(context, "unsupported cell_format") end
    if module.encoding ~= nil and module.encoding ~= "rle_palette" then Fail(context, "unsupported encoding") end
    if not PositiveInteger(module.width) or not PositiveInteger(module.height) then
        Fail(context, "width and height must be positive integers")
    end
    if module.total_pixels ~= nil and module.total_pixels ~= module.width * module.height then
        Fail(context, "total_pixels does not match dimensions")
    end
    if module.is_blueprint then Fail(context, "a blueprint package cannot be used as a single map layer") end
    if type(module.Unpack) ~= "function" then Fail(context, "Unpack method is required") end
    if solver ~= "1x1" and solver ~= "4x4" then Fail(context, "solver must be 1x1 or 4x4") end
    local scale = solver == "4x4" and 4 or 1
    if module.width % scale ~= 0 or module.height % scale ~= 0 then
        Fail(context, "4x4 input dimensions must be multiples of 4; refusing to crop pixels")
    end
    if module.rle_data ~= nil then
        if type(module.rle_data) ~= "string" or type(module.palette) ~= "table" then Fail(context, "invalid RLE/palette") end
        local total = 0
        for token in string.gmatch(module.rle_data, "[^;]+") do
            local id, count = string.match(token, "^(%d+):(%d+)$")
            id, count = tonumber(id), tonumber(count)
            if not id or not count or count < 1 then Fail(context, "invalid RLE run " .. token) end
            if id ~= 0 and module.palette[id] == nil then Fail(context, "RLE references missing palette id " .. id) end
            total = total + count
            if total > module.width * module.height then Fail(context, "RLE exceeds declared dimensions") end
        end
        if total ~= module.width * module.height then Fail(context, "RLE pixel count does not match dimensions") end
    end
    return module.width / scale, module.height / scale
end

function Contract.NormalizeColor(color)
    if type(color) ~= "string" or color == "" then Fail("color", "expected a nonempty string") end
    color = string.lower(color)
    if string.sub(color, 1, 1) ~= "#" then
        color = "#" .. color
    end
    return color
end

function Contract.ValidateBlueprint(module, context, solver)
    if type(module) ~= "table" then Fail(context, "blueprint module must return a table") end
    if not module.is_blueprint then return Contract.ValidateData(module, context, solver or "1x1") end
    Contract.CheckVersion(module, context)
    if type(module.Unpack) ~= "function" or type(module.layers) ~= "table" then Fail(context, "blueprint requires layers and Unpack") end
    local width, height
    for name, layer in pairs(module.layers) do
        if type(layer) ~= "table" then Fail(context, "invalid blueprint layer " .. tostring(name)) end
        local input = {
            schema_version = module.schema_version, coordinate_system = module.coordinate_system,
            cell_format = module.cell_format, encoding = module.encoding,
            width = module.width, height = module.height, total_pixels = module.total_pixels,
            palette = layer.palette, rle_data = layer.rle_data, Unpack = module.Unpack,
        }
        width, height = Contract.ValidateData(input, context .. "/" .. name, solver or "1x1")
    end
    if not width then Fail(context, "blueprint has no layers") end
    return width, height
end

local CONFIG_META = {
    schema_version = true, rules = true, reserved_colors = true, unknown_color_policy = true,
}

function Contract.NormalizeConfig(config, context, diagnostics)
    if type(config) ~= "table" then Fail(context, "config must return a table") end
    Contract.CheckVersion(config, context, diagnostics)
    local source = config.rules or config
    if type(source) ~= "table" then Fail(context, "rules must be a table") end
    local rules, reserved = {}, {}
    for color, conf in pairs(source) do
        if not CONFIG_META[color] then
            local key = Contract.NormalizeColor(color)
            if type(conf) ~= "table" then Fail(context, "rule for " .. key .. " must be a table") end
            if rules[key] then Fail(context, "duplicate normalized color " .. key) end
            rules[key] = conf
            local function CheckRule(rule)
                if type(rule) ~= "table" then Fail(context, "tier rule must be a table") end
                if rule.merge_distance ~= nil and (not IsFinite(rule.merge_distance) or rule.merge_distance < 0) then
                    Fail(context, "merge_distance must be a finite, nonnegative number")
                end
            end
            if conf.tiers then
                if type(conf.tiers) ~= "table" then Fail(context, "tiers must be a table") end
                for tier, rule in pairs(conf.tiers) do
                    if not PositiveInteger(tier) then Fail(context, "tier must be a positive integer") end
                    CheckRule(rule)
                end
            else
                CheckRule(conf)
            end
        end
    end
    for color, reason in pairs(config.reserved_colors or {}) do
        local key = Contract.NormalizeColor(color)
        if rules[key] then Fail(context, "reserved color also has an active rule: " .. key) end
        reserved[key] = reason
    end
    local policy = config.unknown_color_policy or "warn"
    if policy ~= "warn" and policy ~= "error" then Fail(context, "unknown_color_policy must be warn or error") end
    return rules, reserved, policy
end

function Contract.NormalizeGrid(grid, width, height, rules, reserved, policy, context, diagnostics)
    if type(grid) ~= "table" then Fail(context, "Unpack must return a grid") end
    for y, row in pairs(grid) do
        if not PositiveInteger(y) or y > height or type(row) ~= "table" then Fail(context, "grid row outside declared dimensions") end
        for x in pairs(row) do
            if not PositiveInteger(x) or x > width then Fail(context, "grid cell outside declared dimensions") end
        end
    end
    local result, unknown, placeholders = {}, {}, {}
    for y = 1, height do
        if grid[y] ~= nil and type(grid[y]) ~= "table" then Fail(context, "grid row must be a table") end
        result[y] = {}
        for x = 1, width do
            local cell = grid[y] and grid[y][x]
            if cell ~= nil then
                local color, tier
                if type(cell) == "string" then color, tier = cell, 1
                elseif type(cell) == "table" then color, tier = cell.color or cell[1], cell.tier or 1
                else Fail(context, "invalid cell at " .. x .. "," .. y) end
                color = Contract.NormalizeColor(color)
                if not PositiveInteger(tier) then Fail(context, "invalid tier at " .. x .. "," .. y) end
                if rules[color] then
                    result[y][x] = { color = color, tier = tier }
                elseif reserved[color] ~= nil then
                    placeholders[color] = (placeholders[color] or 0) + 1
                else
                    unknown[color] = (unknown[color] or 0) + 1
                end
            end
        end
    end
    local function Report(counts, severity, code)
        local keys = {}
        for key in pairs(counts) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local message = key .. (code == "reserved_color" and (": " .. tostring(reserved[key])) or ": no configured rule")
            if severity == "error" then Fail(context, message) end
            Contract.Diagnostic(diagnostics, severity, code, context, message, counts[key])
        end
    end
    Report(placeholders, "info", "reserved_color")
    Report(unknown, policy == "error" and "error" or "warning", "unknown_color")
    return result
end

local SAVE_FIELDS = { "data", "id", "scenario", "rotation", "skinname", "skin_id", "refs" }

function Contract.NewEntity(prefab, x, y, conf, kind)
    conf = conf or {}
    local ent = { prefab = prefab, x = x, y = y, kind = kind or "prefab", require_solid = conf.require_solid }
    if conf.save_record ~= nil then ent.save_record = Contract.Clone(conf.save_record) end
    for _, key in ipairs(SAVE_FIELDS) do
        if conf[key] ~= nil then ent[key] = Contract.Clone(conf[key]) end
    end
    if conf.metadata ~= nil then ent.metadata = Contract.Clone(conf.metadata) end
    if kind == "layout" then
        ent.layout, ent.is_layout = prefab, true
        ent.layout_options = Contract.Clone(conf.layout_options or {})
    end
    return ent
end

function Contract.ToSaveRecord(ent, world_x, world_z)
    local record = Contract.Clone(ent.save_record or {})
    if type(record) ~= "table" then Fail("entity", "save_record must be a table") end
    for _, key in ipairs(SAVE_FIELDS) do
        if ent[key] ~= nil then record[key] = Contract.Clone(ent[key]) end
    end
    record.x, record.z = world_x, world_z
    if record.data ~= nil and type(record.data) ~= "table" then Fail("entity", "data must be a table") end
    record.data = record.data or {}
    if record.rotation ~= nil then
        if not IsFinite(record.rotation) then Fail("entity", "rotation must be finite") end
        if record.data.savedrotation ~= nil and type(record.data.savedrotation) ~= "table" then Fail("entity", "savedrotation must be a table") end
        -- 原版通过savedrotation组件加载朝向，顶层rotation仅作为配置便捷写法。
        record.data.savedrotation = record.data.savedrotation or {}
        record.data.savedrotation.rotation = record.rotation
    end
    -- 桥桩等现有预制体依赖世界坐标；只更新这两个字段，保留其余存档数据。
    record.data.tile_cx, record.data.tile_cz = world_x, world_z
    if ent.metadata ~= nil then record.data.celestial_metadata = Contract.Clone(ent.metadata) end
    return record
end

function Contract.ValidateResult(result)
    if type(result) ~= "table" or result.schema_version ~= Contract.SCHEMA_VERSION then Fail("result", "unsupported result schema") end
    if result.coordinate_system ~= Contract.OUTPUT_COORDINATES then Fail("result", "invalid coordinate system") end
    if not PositiveInteger(result.width) or not PositiveInteger(result.height) then Fail("result", "invalid dimensions") end
    if type(result.tiles) ~= "table" or type(result.entities) ~= "table" then Fail("result", "tiles and entities are required") end
    for y = 1, result.height do
        if type(result.tiles[y]) ~= "table" then Fail("result", "missing tile row " .. y) end
        for x = 1, result.width do
            if not IsFinite(result.tiles[y][x]) then Fail("result", "missing or invalid tile at " .. x .. "," .. y) end
        end
    end
    -- map_contract.lua: ValidateResult
for index, ent in ipairs(result.entities) do
    if type(ent) ~= "table" or type(ent.prefab) ~= "string" or ent.prefab == "" then 
        Fail("entity " .. index, "prefab/layout name required") 
    end
    -- 适配最小物理子格精度范围 [1, width + 1)
    if not IsFinite(ent.x) or not IsFinite(ent.y) 
        or ent.x < 1 or ent.x >= result.width + 1 
        or ent.y < 1 or ent.y >= result.height + 1 then
        Fail("entity " .. index, "position outside realm bounds")
    end
    if ent.kind ~= nil and ent.kind ~= "prefab" and ent.kind ~= "layout" then 
        Fail("entity " .. index, "unknown kind") 
    end
    Contract.ToSaveRecord(ent, 0, 0)
end
    return result
end

return Contract
