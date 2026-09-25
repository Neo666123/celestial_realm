local GLOBAL = rawget(_G, "GLOBAL") or _G
local rawset = GLOBAL.rawset
local rawget = GLOBAL.rawget
local pairs = GLOBAL.pairs
local ipairs = GLOBAL.ipairs
local type = GLOBAL.type
local table = GLOBAL.table

local InspectorRegistry = {
    _configs = {},
    _metadata = {},
    _initial_snapshots = {}
}

function InspectorRegistry:Register(componentName, configTable, metadata)
    if type(componentName) ~= "string" or type(configTable) ~= "table" then
        return
    end
    self._configs[componentName] = configTable
    self._metadata[componentName] = metadata or {}

    -- 固化初始数据快照，作为后续导出的比对基准
    local snapshot = {}
    local seen = {}
    for k, _ in pairs(configTable) do
        snapshot[k] = configTable[k]
        seen[k] = true
    end
    if metadata then
        for k, _ in pairs(metadata) do
            if type(k) == "string" and k:sub(1, 1) ~= "_" and not seen[k] then
                snapshot[k] = configTable[k]
                seen[k] = true
            end
        end
    end
    self._initial_snapshots[componentName] = snapshot
end

function InspectorRegistry:Get(componentName)
    return self._configs[componentName]
end

function InspectorRegistry:GetMetadata(componentName)
    return self._metadata[componentName] or {}
end

function InspectorRegistry:GetAll()
    return self._configs
end

-- 双段式比对导出器：直接生成符合替换规范的标准文本块
function InspectorRegistry:Dump(componentName)
    local print = GLOBAL.print
    local tostring = GLOBAL.tostring
    local string = GLOBAL.string

    local function BuildTableString(var_name, data_source, meta, keys)
        local lines = {}
        lines[#lines + 1] = string.format("local %s = {", var_name)
        for _, k in ipairs(keys) do
            local v = data_source[k]
            if v ~= nil and (type(v) == "number" or type(v) == "boolean" or type(v) == "string") then
                local val_str = type(v) == "string" and string.format('"%s"', v) or tostring(v)
                local comment = (meta and meta[k]) and string.format("  -- %s", meta[k]) or ""
                lines[#lines + 1] = string.format("    %-16s = %s,%s", tostring(k), val_str, comment)
            end
        end
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function DumpTbl(name, current_tbl, meta, initial_tbl)
        local var_name = (meta and meta._var_name) or (name:find("Settings$") and name:gsub("Settings$", "Core") or name)
        local title = (meta and meta._title) or name

        local keys = {}
        local seen = {}
        for k, _ in pairs(current_tbl) do
            keys[#keys + 1] = k
            seen[k] = true
        end
        if meta then
            for k, _ in pairs(meta) do
                if type(k) == "string" and k:sub(1, 1) ~= "_" and not seen[k] then
                    keys[#keys + 1] = k
                    seen[k] = true
                end
            end
        end
        table.sort(keys)

        print(string.format("\n-- >>>>>>>>>>>>>>>>>> 【%s】 <<<<<<<<<<<<<<<<<<", title))
        print("-- 需要替换的段落（当前未修改代码）：")
        print(BuildTableString(var_name, initial_tbl or current_tbl, meta, keys))
        print("\n-- 修改替换后的完整段落：")
        print(BuildTableString(var_name, current_tbl, meta, keys))
        print("----------------------------------------------------------------------")
    end

    print("\n======================= 【INSPECTOR 配置导出】 =======================")
    if componentName then
        if self._configs[componentName] then
            DumpTbl(componentName, self._configs[componentName], self._metadata[componentName], self._initial_snapshots[componentName])
        end
    else
        for name, tbl in pairs(self._configs) do
            DumpTbl(name, tbl, self._metadata[name], self._initial_snapshots[name])
        end
    end
    print("======================================================================\n")
end

rawset(GLOBAL, "InspectorRegistry", InspectorRegistry)
return InspectorRegistry