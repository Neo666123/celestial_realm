local _G = rawget(_G, "_G") or _G
local GLOBAL = rawget(_G, "GLOBAL") or _G
local rawget = rawget

local AddPrefabPostInit = (env and env.AddPrefabPostInit) or rawget(GLOBAL, "AddPrefabPostInit")
local AddClassPostConstruct = (env and env.AddClassPostConstruct) or rawget(GLOBAL, "AddClassPostConstruct")
local SpawnPrefab = rawget(GLOBAL, "SpawnPrefab")

AddPrefabPostInit("rope_bridge_fx", function(inst)
    local function StripRopes()
        if inst.rope1 then
            inst.rope1:Hide()
            if inst.rope1.AnimState then
                inst.rope1.AnimState:ClearAllOverrideSymbols()
            end
        end
        if inst.rope2 then
            inst.rope2:Hide()
            if inst.rope2.AnimState then
                inst.rope2.AnimState:ClearAllOverrideSymbols()
            end
        end
    end

    inst:DoTaskInTime(0, StripRopes)
    inst:ListenForEvent("animdatadirty", StripRopes)
end)

local function GetTargetConstructionSite(doer)
    if not doer then return nil end
    if doer.components and doer.components.constructionbuilder then
        return doer.components.constructionbuilder.constructionsite
    end
    if doer.player_classified and doer.player_classified.GetConstructionSite then
        return doer.player_classified:GetConstructionSite()
    end
    return nil
end

AddClassPostConstruct("widgets/containerwidget", function(self)
    local old_Open = self.Open
    self.Open = function(self, container, doer)
        local cs = GetTargetConstructionSite(doer)
        if cs and cs:IsValid() and cs.prefab == "cc_brigdepost" then
            local boards = (cs._required_boards and cs._required_boards:value()) or 0
            local logs   = (cs._required_logs and cs._required_logs:value()) or 0

            local CONSTRUCTION_PLANS = rawget(GLOBAL, "CONSTRUCTION_PLANS")
            local Ingredient = rawget(GLOBAL, "Ingredient")

            if CONSTRUCTION_PLANS and Ingredient then
                local plans = {}
                if boards > 0 then
                    table.insert(plans, Ingredient("boards", boards))
                end
                if logs > 0 then
                    table.insert(plans, Ingredient("log", logs))
                end
                if #plans == 0 then
                    table.insert(plans, Ingredient("log", 2))
                end
                CONSTRUCTION_PLANS["cc_brigdepost"] = plans
            end
        end
        return old_Open(self, container, doer)
    end
end)

AddPrefabPostInit("firepit", function(inst)
    local TheWorld = rawget(GLOBAL, "TheWorld")
    if TheWorld == nil or not TheWorld.ismastersim then
        return
    end

    if inst.components.burnable ~= nil then
        local old_onextinguish = inst.components.burnable.onextinguish
        inst.components.burnable:SetOnExtinguishFn(function(target)
            if old_onextinguish ~= nil then
                old_onextinguish(target)
            end

            if SpawnPrefab ~= nil then
                local charcoal = SpawnPrefab("charcoal")
                if charcoal ~= nil then
                    local pos = target:GetPosition()
                    charcoal.Transform:SetPosition(pos:Get())
                end
            end
        end)
    end
end)
AddPrefabPostInit("firepit", function(inst)
    local TheWorld = rawget(GLOBAL, "TheWorld")
    if TheWorld == nil or not TheWorld.ismastersim then
        return
    end

    -- 允许火堆额外接收 cc_coal 作为燃料
    if inst.components.fueled ~= nil then
        local FUELTYPE = rawget(GLOBAL, "FUELTYPE")
        inst.components.fueled.secondary_fueltype = (FUELTYPE and rawget(FUELTYPE, "CC_COAL")) or "CC_COAL"
    end

    if inst.components.burnable ~= nil then
        local old_onextinguish = inst.components.burnable.onextinguish
        inst.components.burnable:SetOnExtinguishFn(function(target)
            if old_onextinguish ~= nil then
                old_onextinguish(target)
            end

            if SpawnPrefab ~= nil then
                local charcoal = SpawnPrefab("charcoal")
                if charcoal ~= nil then
                    local pos = target:GetPosition()
                    charcoal.Transform:SetPosition(pos:Get())
                end
            end
        end)
    end
end)