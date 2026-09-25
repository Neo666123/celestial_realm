local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G
local AddClassPostConstruct = (env and env.AddClassPostConstruct) or rawget(GLOBAL, "AddClassPostConstruct")
local AddPlayerPostInit = (env and env.AddPlayerPostInit) or rawget(GLOBAL, "AddPlayerPostInit")
local AddPrefabPostInit = (env and env.AddPrefabPostInit) or rawget(GLOBAL, "AddPrefabPostInit")

local BLOCKED_RECIPES = {
    ["researchlab"]           = true, -- 1本 科学机
    ["researchlab2"]          = true, -- 2本 炼金引擎
    ["researchlab4"]          = true, -- 3本 灵子分解器
    ["researchlab3"]          = true, -- 4本 暗影操纵仪
    ["book_research_station"] = true, -- 万物百科
}

local CELESTIAL_REALM_RADIUS_SQ = 600 * 600

local function ApplyCelestialRestrictions(player)
    player:AddTag("in_celestial_realm")
    local builder = player.components and player.components.builder
    if builder then
        if player.prefab == "wickerbottom" then
            builder.science_bonus = 0
        end
        builder:EvaluateTechTrees()
    end
    player:PushEvent("techtreechange")
    player:PushEvent("refreshcrafting")
end

-- 1. 动态替换制作栏详情页文本与锁定制作按钮
AddClassPostConstruct("widgets/redux/craftingmenu_details", function(self)
    -- Hook 详情面板生成：动态劫持描述文本，渲染后即刻还原，不污染全局配置
    local old_PopulateRecipeDetailPanel = self.PopulateRecipeDetailPanel
    self.PopulateRecipeDetailPanel = function(details_widget, data, skin_name)
        local owner = details_widget.owner
        local recipe = data and data.recipe
        local is_blocked = owner and owner:HasTag("in_celestial_realm") and recipe and BLOCKED_RECIPES[recipe.name]

        local key = nil
        local old_desc_str = nil
        local STRINGS = rawget(GLOBAL, "STRINGS")

        if is_blocked and STRINGS and STRINGS.RECIPE_DESC then
            key = string.upper(recipe.description or recipe.product)
            old_desc_str = STRINGS.RECIPE_DESC[key]
            STRINGS.RECIPE_DESC[key] = "它在天界不起作用。"
        end

        old_PopulateRecipeDetailPanel(details_widget, data, skin_name)

        if is_blocked and key and STRINGS and STRINGS.RECIPE_DESC then
            STRINGS.RECIPE_DESC[key] = old_desc_str
        end
    end

    -- Hook 制作按钮：在天界查看违禁设施时强行隐藏制作按钮，展示阻断提示
    local old_UpdateBuildButton = self.UpdateBuildButton
    self.UpdateBuildButton = function(details_widget, from_pin_slot)
        local owner = details_widget.owner
        local recipe = details_widget.data and details_widget.data.recipe

        if owner and owner:HasTag("in_celestial_realm") and recipe and BLOCKED_RECIPES[recipe.name] then
            local teaser = details_widget.build_button_root and details_widget.build_button_root.teaser
            local button = details_widget.build_button_root and details_widget.build_button_root.button

            if teaser and button then
                teaser:SetSize(20)
                teaser:UpdateOriginalSize()
                teaser:SetMultilineTruncatedString("天界法则排斥此科技设施", 2, (details_widget.panel_width / 2) * 0.8, nil, false, true)
                teaser:Show()
                button:Hide()
                return
            end
        end

        if old_UpdateBuildButton then
            old_UpdateBuildButton(details_widget, from_pin_slot)
        end
    end
end)

-- 2. 配方物理放置拦截
local function RegisterCanBuildLocks()
    local AllRecipes = rawget(GLOBAL, "AllRecipes")
    if not AllRecipes then return end

    for recname, _ in pairs(BLOCKED_RECIPES) do
        local recipe = AllRecipes[recname]
        if recipe then
            local old_canbuild = recipe.canbuild
            recipe.canbuild = function(rec, builder, pt, rotation, station, skin)
                if builder and builder:HasTag("in_celestial_realm") then
                    return false, "CELESTIAL_BLOCKED"
                end
                if old_canbuild then
                    return old_canbuild(rec, builder, pt, rotation, station, skin)
                end
                return true
            end
        end
    end
end

-- 3. 万物百科实体拦截（天界阅读直接无效）
AddPrefabPostInit("book_research_station", function(inst)
    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not TheWorld or not TheWorld.ismastersim then
        return
    end

    if inst.components and inst.components.book then
        local old_onread = inst.components.book.onread
        inst.components.book.onread = function(book_inst, reader)
            if reader and reader:HasTag("in_celestial_realm") then
                if reader.components.talker then
                    reader.components.talker:Say("它在天界毫无反应。")
                end
                return false, "CELESTIAL_BLOCKED"
            end
            if old_onread then
                return old_onread(book_inst, reader)
            end
            return false
        end
    end
end)

-- 4. 科技台组件拦截（天界范围内强制失效断电）
AddClassPostConstruct("components/prototyper", function(self)
    local old_CanUsePrototyper = self.CanUsePrototyper
    self.CanUsePrototyper = function(proto, doer)
        if (doer and doer:HasTag("in_celestial_realm")) or (proto.inst and proto.inst:HasTag("in_celestial_realm")) then
            return false
        end
        if old_CanUsePrototyper then
            return old_CanUsePrototyper(proto, doer)
        end
        return true
    end

    local old_GetTechTrees = self.GetTechTrees
    self.GetTechTrees = function(proto)
        if proto.inst and proto.inst:HasTag("in_celestial_realm") then
            local TECH = rawget(GLOBAL, "TECH")
            return TECH and TECH.NONE or {}
        end
        if old_GetTechTrees then
            return old_GetTechTrees(proto)
        end
        return {}
    end
end)

-- 5. 玩家状态持久化与锚点检测
AddPlayerPostInit(function(inst)
    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not TheWorld or not TheWorld.ismastersim then
        return
    end

    RegisterCanBuildLocks()

    local old_OnSave = inst.OnSave
    inst.OnSave = function(player, data)
        if old_OnSave then
            old_OnSave(player, data)
        end
        if player:HasTag("in_celestial_realm") then
            data.in_celestial_realm = true
        end
    end

    local old_OnLoad = inst.OnLoad
    inst.OnLoad = function(player, data)
        if old_OnLoad then
            old_OnLoad(player, data)
        end
        if data and data.in_celestial_realm then
            ApplyCelestialRestrictions(player)
        end
    end

    inst:DoTaskInTime(0, function(player)
        if not (player and player:IsValid()) then return end
        if player:HasTag("in_celestial_realm") then return end

        local TheSim = rawget(GLOBAL, "TheSim")
        local anchor = TheSim:FindFirstEntityWithTag("celestial_rift_anchor")
            or TheSim:FindFirstEntityWithTag("celestial_hall_anchor")

        if anchor and anchor:IsValid() then
            if player:GetDistanceSqToInst(anchor) <= CELESTIAL_REALM_RADIUS_SQ then
                ApplyCelestialRestrictions(player)
            end
        end
    end)
end)