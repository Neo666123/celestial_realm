local _G = rawget(_G, "GLOBAL") or _G
local Contract = require("map/map_contract")
local math, type, pairs, ipairs = _G.math, _G.type, _G.pairs, _G.ipairs
local table, pcall, tostring = _G.table, _G.pcall, _G.tostring
local Writer = {}

local function IsFinite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function IsTile(n)
    return IsFinite(n) and n == math.floor(n)
end

function Writer.ToWorld(x, y, width, height)
    local scale = rawget(_G, "TILE_SCALE") or 4
    return (x - width / 2) * scale, (y - height / 2) * scale
end

function Writer.RealmTile(x, y, placement)
    return placement.base_x + x - 1, placement.base_y + y - 1
end

local function InCanvas(x, y, placement)
    return IsTile(x) and IsTile(y) and x >= 0 and y >= 0
        and x < placement.width and y < placement.height
end

local function InRealm(x, y, realm, placement)
    return x >= placement.base_x and y >= placement.base_y
        and x < placement.base_x + realm.width and y < placement.base_y + realm.height
end

local function AddWarning(realm, stats, code, ent, reason)
    local message = tostring(ent.layout or ent.prefab) .. " at (" .. tostring(ent.x) .. "," .. tostring(ent.y) .. "): " .. reason
    Contract.Diagnostic(realm.diagnostics, "warning", code, "engine", message, 1)
    stats.warnings[#stats.warnings + 1] = { code = code, message = message }
end

local function AddRecord(entities, prefab, record)
    entities[prefab] = entities[prefab] or {}
    table.insert(entities[prefab], record)
end

local function LayoutRadius(layout, prefabs)
    if layout.ground ~= nil then
        local size = #layout.ground
        if size == 0 then return nil, "layout.ground is empty" end
        for y = 1, size do
            if type(layout.ground[y]) ~= "table" or #layout.ground[y] ~= size then
                return nil, "native layout.ground must be square"
            end
            for x = 1, size do
                local value = layout.ground[y][x]
                if value ~= 0 and (not layout.ground_types or not IsFinite(layout.ground_types[value])) then
                    return nil, "layout.ground contains an unresolved tile"
                end
            end
        end
        return size / 2
    end
    if #prefabs == 0 then return nil, "layout has no ground or entities" end
    local xmin, ymin, xmax, ymax = math.huge, math.huge, -math.huge, -math.huge
    for _, prefab in ipairs(prefabs) do
        if not IsFinite(prefab.x) or not IsFinite(prefab.y) then
            return nil, "layout has invalid entity coordinates"
        end
        xmin, xmax = math.min(xmin, prefab.x), math.max(xmax, prefab.x)
        ymin, ymax = math.min(ymin, prefab.y), math.max(ymax, prefab.y)
    end
    return math.max(xmax - xmin, ymax - ymin) * (layout.scale or 1) / 2
end

local function NativeSaveRecord(properties)
    local record = {}
    for key, value in pairs(properties or {}) do
        if key == "data" and type(value) == "function" then value = value() end
        record[key] = Contract.Clone(value)
    end
    return record
end

local function ExpandLayout(ent, realm, world, entities, placement, stats, impassable)
    local name = ent.layout or ent.prefab
    local ok, result = pcall(function()
        local layouts = require("map/object_layout")
        local options = ent.layout_options or {}
        local layout = layouts.LayoutForDefinition(name, options.choices)
        if not layout then return { error = "unknown layout" } end
        if layout.scale ~= nil and (not IsFinite(layout.scale) or layout.scale <= 0) then
            return { error = "layout.scale must be positive" }
        end
        local prefabs = layouts.ConvertLayoutToEntitylist(layout)
        for _, prefab in ipairs(prefabs) do
            if prefab.properties and type(prefab.properties.data) == "function" then
                prefab.properties.data = prefab.properties.data()
            end
        end
        local radius, radius_error = LayoutRadius(layout, prefabs)
        if not radius then return { error = radius_error } end
        local anchor_x, anchor_y = Writer.RealmTile(ent.x, ent.y, placement)
        -- 标记表示布局中心；左下原点取整，偶数边长按原版规则偏移半格。
        local left, top = math.floor(anchor_x - radius), math.floor(anchor_y - radius)
        local staged = { tiles = {}, records = {}, safe = {} }
        local recorder = {}
        function recorder:SetTile(x, y, tile)
            staged.tiles[#staged.tiles + 1] = { x = x, y = y, tile = tile }
        end
        function recorder:MakeSafeFromDisconnect(x, y)
            staged.safe[#staged.safe + 1] = { x = x, y = y }
        end
        local add_fn = {
            args = { entitiesOut = staged.records, width = placement.width, height = placement.height },
            fn = function(prefab, xs, ys, index, out, width, height, _, properties)
                local x, y = xs[index], ys[index]
                local wx, wz = Writer.ToWorld(x, y, width, height)
                local input = { prefab = prefab, save_record = NativeSaveRecord(properties), metadata = ent.metadata }
                out[#out + 1] = { prefab = prefab, x = x, y = y, record = Contract.ToSaveRecord(input, wx, wz) }
            end,
        }
        layouts.ReserveAndPlaceLayout("POSITIONED", layout, prefabs, add_fn, { left, top }, recorder)
        return staged
    end)
    if not ok or result.error then
        stats.layouts_rejected = stats.layouts_rejected + 1
        AddWarning(realm, stats, "layout_expand_failed", ent, tostring(ok and result.error or result))
        return
    end

    for _, point in ipairs(result.tiles) do
        if not InCanvas(point.x, point.y, placement) or not InRealm(point.x, point.y, realm, placement)
            or not IsFinite(point.tile) then
            stats.layouts_rejected = stats.layouts_rejected + 1
            AddWarning(realm, stats, "layout_out_of_bounds", ent, "layout ground exceeds the realm or canvas")
            return
        end
        local tile = world:GetTile(point.x, point.y)
        if ent.require_solid ~= false and (tile == nil or tile == impassable) then
            stats.layouts_rejected = stats.layouts_rejected + 1
            AddWarning(realm, stats, "layout_on_void", ent, "layout ground footprint is not supported")
            return
        end
    end
    for _, point in ipairs(result.records) do
        if type(point.prefab) ~= "string" or point.prefab == "" or not IsFinite(point.x) or not IsFinite(point.y) then
            stats.layouts_rejected = stats.layouts_rejected + 1
            AddWarning(realm, stats, "layout_invalid_entity", ent, "layout has invalid entity data")
            return
        end
        local tx, ty = math.floor(point.x), math.floor(point.y)
        if not InCanvas(tx, ty, placement) or not InRealm(tx, ty, realm, placement) then
            stats.layouts_rejected = stats.layouts_rejected + 1
            AddWarning(realm, stats, "layout_out_of_bounds", ent, "layout entity exceeds the realm or canvas")
            return
        end
        local tile = world:GetTile(tx, ty)
        if ent.require_solid ~= false and (tile == nil or tile == impassable) then
            stats.layouts_rejected = stats.layouts_rejected + 1
            AddWarning(realm, stats, "layout_on_void", ent, "layout entity has no supporting ground")
            return
        end
    end

    -- 原版展开先写临时表；完整校验后一次提交，失败不留下半套地皮或实体。
    for _, point in ipairs(result.tiles) do
        world:SetTile(point.x, point.y, point.tile)
        realm.tiles[point.y - placement.base_y + 1][point.x - placement.base_x + 1] = point.tile
    end
    if world.MakeSafeFromDisconnect then
        for _, point in ipairs(result.safe) do world:MakeSafeFromDisconnect(point.x, point.y) end
    end
    for _, point in ipairs(result.records) do
        AddRecord(entities, point.prefab, point.record)
        stats.entities_written = stats.entities_written + 1
    end
    stats.layouts_written = stats.layouts_written + 1
end

function Writer.WriteRealm(realm, world, entities, placement)
    local tiles = rawget(_G, "WORLD_TILES") or rawget(_G, "GROUND") or {}
    local impassable = rawget(tiles, "IMPASSABLE") or 1
    local stats = { entities_written = 0, entities_rejected = 0, layouts_written = 0, layouts_rejected = 0, warnings = {} }
    realm.diagnostics = realm.diagnostics or {}
    realm.engine_stats = stats
    for _, ent in ipairs(realm.entities or {}) do
        if ent.kind == "layout" or ent.is_layout then
            if IsTile(ent.x) and IsTile(ent.y) and ent.x >= 1 and ent.y >= 1 and ent.x <= realm.width and ent.y <= realm.height then
                ExpandLayout(ent, realm, world, entities, placement, stats, impassable)
            else
                stats.layouts_rejected = stats.layouts_rejected + 1
                AddWarning(realm, stats, "layout_invalid_anchor", ent, "layout anchor is outside the realm")
            end
        end
    end
    for _, ent in ipairs(realm.entities or {}) do
        if ent.kind ~= "layout" and not ent.is_layout then
            local tx, ty = Writer.RealmTile(ent.x, ent.y, placement)
            local ix, iy = math.floor(tx), math.floor(ty)
            local tile = InCanvas(ix, iy, placement) and InRealm(ix, iy, realm, placement) and world:GetTile(ix, iy) or nil
            if tile ~= nil and (tile ~= impassable or ent.require_solid == false) then
                local x, z = Writer.ToWorld(tx, ty, placement.width, placement.height)
                AddRecord(entities, ent.prefab, Contract.ToSaveRecord(ent, x, z))
                stats.entities_written = stats.entities_written + 1
            else
                stats.entities_rejected = stats.entities_rejected + 1
                AddWarning(realm, stats, "entity_on_void_or_outside", ent, "entity has no supporting ground inside the realm")
            end
        end
    end
    return stats
end

return Writer
