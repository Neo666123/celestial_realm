local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G
local CreateEntity = rawget(GLOBAL, "CreateEntity")
local Prefab = rawget(GLOBAL, "Prefab")
local Asset = rawget(GLOBAL, "Asset")
local MakeInventoryPhysics = rawget(GLOBAL, "MakeInventoryPhysics")
local MakeInventoryFloatable = rawget(GLOBAL, "MakeInventoryFloatable")
local MakeHauntableLaunch = rawget(GLOBAL, "MakeHauntableLaunch")
local SpawnPrefab = rawget(GLOBAL, "SpawnPrefab")
local TUNING = rawget(GLOBAL, "TUNING")

local assets = {
    Asset("ANIM", "anim/alterguardianhatshard.zip"),
}

local function GetMemoryDef(memory_id)
    local cc_tuning = TUNING and rawget(TUNING, "CC")
    local mem_defs = cc_tuning and cc_tuning.MEMORIES
    if mem_defs and mem_defs[memory_id] then
        return mem_defs[memory_id]
    end
    -- 回退项：如果没配置，默认走 bridge
    return (mem_defs and mem_defs.bridge) or {
        recipes = { "cc_brigdepost_item", "boards" },
        name    = "筑桥者的记忆",
        desc    = "记录着跨越虚空的古老构件搭建方法。",
        talk    = "我感受到了……那是跨越深渊的记忆。",
        color   = { 0.3, 0.7, 1.0 },
    }
end

local function CheckAndEjectFromContainer(inst, owner)
    if not owner then return end

    if owner.components and owner.components.container then
        if owner.prefab ~= "dragonflychest" and not owner:HasTag("cc_memory_chest") then
            inst:DoTaskInTime(0, function()
                if not (owner:IsValid() and owner.components.container) then
                    return
                end

                local container = owner.components.container
                local drop_pos = owner:GetPosition()
                local grand_owner = owner.components.inventoryitem and owner.components.inventoryitem:GetGrandOwner()
                if grand_owner then
                    drop_pos = grand_owner:GetPosition()
                end

                local slot = container:GetItemSlot(inst)
                if slot ~= nil then
                    container:DropItemBySlot(slot, drop_pos)
                elseif inst:IsValid() and inst.components.inventoryitem and inst.components.inventoryitem:IsHeldBy(owner) then
                    local whole_item = container:RemoveItem(inst, true)
                    if whole_item then
                        whole_item.Transform:SetPosition(drop_pos.x, drop_pos.y, drop_pos.z)
                        if whole_item.components.inventoryitem then
                            whole_item.components.inventoryitem:OnDropped(true)
                        end
                        whole_item.prevcontainer = nil
                        whole_item.prevslot = nil
                        owner:PushEvent("dropitem", { item = whole_item })
                    end
                end

                if owner.SoundEmitter then
                    owner.SoundEmitter:PlaySound("dontstarve/common/destroy_stone")
                end

                local fx = SpawnPrefab("spawn_fx_small")
                if fx and drop_pos then
                    fx.Transform:SetPosition(drop_pos.x, drop_pos.y, drop_pos.z)
                end
            end)
        end
    end
end

local function DoTeachOrDecompose(inst, learner)
    if not (learner and learner:IsValid()) then
        return false
    end

    local builder = learner.components.builder
    if not builder then
        return false
    end

    local def = GetMemoryDef(inst.memory_id)
    local pool = def.recipes or {}
    local unlearned = {}

    for _, recname in ipairs(pool) do
        if not builder:KnowsRecipe(recname) and builder:CanLearn(recname) then
            table.insert(unlearned, recname)
        end
    end

    if #unlearned > 0 then
        local chosen = unlearned[math.random(#unlearned)]
        builder:UnlockRecipe(chosen)
        learner:PushEvent("learnrecipe", { teacher = inst, recipe = chosen })

        if def.talk and learner.components.talker then
            learner.components.talker:Say(def.talk)
        end

        if learner.SoundEmitter then
            learner.SoundEmitter:PlaySound("dontstarve/HUD/research_unlock")
        end
    else
        local inv = learner.components.inventory
        if inv then
            local scraps = SpawnPrefab("cc_memscrap")
            if scraps then
                if scraps.components.stackable then
                    scraps.components.stackable:SetStackSize(3)
                end
                if not inv:GiveItem(scraps) then
                    inv:DropItem(scraps, true, true)
                end
            end
        end

        if learner.components.talker then
            learner.components.talker:Say("记忆中的技艺已了然于胸，它化作了残片。")
        end

        if learner.SoundEmitter then
            learner.SoundEmitter:PlaySound("dontstarve/common/gem_shatter")
        end

        local fx = SpawnPrefab("spawn_fx_small")
        if fx then
            local x, y, z = learner.Transform:GetWorldPosition()
            fx.Transform:SetPosition(x, y, z)
        end
    end

    inst:Remove()
    return true
end

local function ApplyMemoryType(inst, memory_id)
    local def = GetMemoryDef(memory_id)
    inst.memory_id = memory_id

    if inst.components.named then
        inst.components.named:SetName(def.name or "未知的记忆")
    end
    if inst.components.inspectable then
        inst.components.inspectable:SetDescription(def.desc or "")
    end

    local c = def.color or { 1.0, 1.0, 1.0 }
    inst.AnimState:SetMultColour(c[1], c[2], c[3], 1.0)
    inst.Light:SetColour(c[1], c[2], c[3])
    inst.Light:Enable(true)
end

local function OnSave(inst, data)
    data.memory_id = inst.memory_id
end

local function OnLoad(inst, data)
    if data and data.memory_id then
        ApplyMemoryType(inst, data.memory_id)
    end
end

local function MakeMemoryBase(default_id)
    local function fn()
        local inst = CreateEntity()

        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddLight()
        inst.entity:AddNetwork()

        MakeInventoryPhysics(inst)
        MakeInventoryFloatable(inst, "small", 0.07, 0.73)

        inst.AnimState:SetBank("alterguardianhatshard")
        inst.AnimState:SetBuild("alterguardianhatshard")
        inst.AnimState:PlayAnimation("idle")
        inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")

        inst.Light:SetRadius(0.8)
        inst.Light:SetFalloff(0.7)
        inst.Light:SetIntensity(0.6)
        inst.Light:Enable(false)

        inst:AddTag("cc_memory_item")
        inst:AddTag("cc_memory")
        inst:AddTag("_named")

        inst.entity:SetPristine()

        local TheWorld = rawget(GLOBAL, "TheWorld")
        if not TheWorld or not TheWorld.ismastersim then
            return inst
        end

        inst:RemoveTag("_named")

        inst:AddComponent("named")
        inst:AddComponent("inspectable")

        inst:AddComponent("inventoryitem")
        inst.components.inventoryitem:ChangeImageName("alterguardianhatshard")
        inst.components.inventoryitem.keepondeath = true
        inst.components.inventoryitem:SetOnPutInInventoryFn(CheckAndEjectFromContainer)

        inst:AddComponent("teacher")
        inst.components.teacher.CanTeach = function(self, target)
            return target ~= nil and target.components.builder ~= nil
        end
        inst.components.teacher.Teach = function(self, target)
            return DoTeachOrDecompose(inst, target)
        end

        MakeHauntableLaunch(inst)

        inst.SetMemory = ApplyMemoryType
        inst.OnSave = OnSave
        inst.OnLoad = OnLoad

        ApplyMemoryType(inst, default_id or "bridge")

        return inst
    end
    return fn
end

return Prefab("cc_memory",    MakeMemoryBase("bridge"), assets),
       Prefab("cc_membridge", MakeMemoryBase("bridge"), assets),
       Prefab("cc_memstove",  MakeMemoryBase("stove"),  assets),
       Prefab("cc_memarmor",  MakeMemoryBase("armor"),  assets),
       Prefab("cc_memranger", MakeMemoryBase("ranger"), assets)