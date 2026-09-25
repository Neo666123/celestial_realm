local count = 0
print("\n==================== [BLUEPRINTS DUMP START] ====================")
print("# 饥荒全蓝图与制作材料速查表\n")

for _, v in pairs(AllRecipes) do
    local has_bp = Prefabs[v.name .. "_blueprint"] or Prefabs[v.name .. "_sketch"]
    local is_special_nounlock = v.nounlock and not (
        v.name:find("^wintercooking_") or 
        v.name:find("^hermitcrabtea_") or 
        v.name:find("^wanderingtradershop_") or 
        v.name:find("^carnivalgame_golf_") or
        v.name:find("^shellweaver_")
    )

    if has_bp or is_special_nounlock then
        local name_zh = STRINGS.NAMES[v.name:upper()] or v.name
        local ing_list = {}

        for _, ing in ipairs(v.ingredients or {}) do
            local ing_zh = STRINGS.NAMES[ing.type:upper()] or ing.type
            table.insert(ing_list, string.format("%dx %s(`%s`)", ing.amount, ing_zh, ing.type))
        end

        local ing_str = #ing_list > 0 and table.concat(ing_list, ", ") or "无消耗"
        print(string.format("- **%s** (`%s`): %s", name_zh, v.name, ing_str))
        count = count + 1
    end
end

print(string.format("\n> 统计蓝图/特殊配方数量: %d 个", count))
print("==================== [BLUEPRINTS DUMP END] ====================\n")

--dofile("C:/SteamLibrary/steamapps/common/Don't Starve Together/mods/celestial_realm/resources/debug.lua")