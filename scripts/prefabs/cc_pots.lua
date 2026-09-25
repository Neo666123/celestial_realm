local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G
local CreateEntity = rawget(GLOBAL, "CreateEntity")
local Prefab = rawget(GLOBAL, "Prefab")
local Asset = rawget(GLOBAL, "Asset")
local SpawnPrefab = rawget(GLOBAL, "SpawnPrefab")
local Vector3 = rawget(GLOBAL, "Vector3")
local COLLISION = rawget(GLOBAL, "COLLISION")
local EQUIPSLOTS = rawget(GLOBAL, "EQUIPSLOTS")
local ACTIONS = rawget(GLOBAL, "ACTIONS")
local TUNING = rawget(GLOBAL, "TUNING")
local TheSim = rawget(GLOBAL, "TheSim")
local MakeInventoryPhysics = rawget(GLOBAL, "MakeInventoryPhysics")
local MakeInventoryFloatable = rawget(GLOBAL, "MakeInventoryFloatable")

local assets = {
    Asset("ANIM", "anim/ruins_vase.zip"),
}

local prefabs = {
    "potshard",
    "cc_memory",
    "collapse_small",
}

local function ReticuleTargetFn()
    local ThePlayer = rawget(GLOBAL, "ThePlayer")
    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not (ThePlayer and TheWorld and TheWorld.Map) then return Vector3() end
    local ground = TheWorld.Map
    local pos = Vector3()
    for r = 6.5, 3.5, -0.25 do
        pos.x, pos.y, pos.z = ThePlayer.entity:LocalToWorldSpace(r, 0, 0)
        if ground:IsPassableAtPoint(pos:Get()) and not ground:IsGroundTargetBlocked(pos) then
            return pos
        end
    end
    return pos
end

local function GetWeightedRandomMemory()
    local cc_tuning = TUNING and rawget(TUNING, "CC")
    local memories = cc_tuning and cc_tuning.MEMORIES
    if not memories then return "bridge" end

    local total_weight = 0
    for _, def in pairs(memories) do
        total_weight = total_weight + (def.weight or 10)
    end

    local rnd = math.random() * total_weight
    local cur = 0
    for id, def in pairs(memories) do
        cur = cur + (def.weight or 10)
        if rnd <= cur then
            return id
        end
    end
    return "bridge"
end

local function DropPotLoot(inst, x, y, z)
    local cc_tuning = TUNING and rawget(TUNING, "CC")
    local pot_cfg = (cc_tuning and cc_tuning.POTS and cc_tuning.POTS[inst.pot_type])
                 or (cc_tuning and cc_tuning.POTS and cc_tuning.POTS.normal)

    local function SpawnItem(prefab_name, count)
        count = count or 1
        for _ = 1, count do
            local loot = SpawnPrefab(prefab_name)
            if loot ~= nil then
                loot.Transform:SetPosition(x, y, z)
                if loot.components.inventoryitem ~= nil then
                    loot.components.inventoryitem:OnDropped(true)
                end
            end
        end
    end

    local s_min = (pot_cfg and pot_cfg.shards and pot_cfg.shards.min) or 1
    local s_max = (pot_cfg and pot_cfg.shards and pot_cfg.shards.max) or 2
    SpawnItem("potshard", math.random(s_min, s_max))

    if not pot_cfg then return end

    if pot_cfg.guaranteed then
        for _, g in ipairs(pot_cfg.guaranteed) do
            local c = type(g.count) == "table" and math.random(g.count.min, g.count.max) or (g.count or 1)
            SpawnItem(g.item, c)
        end
    end

    if pot_cfg.loot_pool then
        for _, entry in ipairs(pot_cfg.loot_pool) do
            if math.random() <= (entry.chance or 0) then
                local item_name = entry.item
                if entry.pool then
                    item_name = entry.pool[math.random(#entry.pool)]
                end
                local c = type(entry.count) == "table" and math.random(entry.count.min, entry.count.max) or (entry.count or 1)
                if item_name then
                    SpawnItem(item_name, c)
                end
            end
        end
    end

    if pot_cfg.memory_chance and math.random() <= pot_cfg.memory_chance then
        local mem_id = GetWeightedRandomMemory()
        local memory_item = SpawnPrefab("cc_memory")
        if memory_item then
            if memory_item.SetMemory then
                memory_item:SetMemory(mem_id)
            end
            memory_item.Transform:SetPosition(x, y, z)
            if memory_item.components.inventoryitem then
                memory_item.components.inventoryitem:OnDropped(true)
            end
        end
    end
end

local function ShatterPot(inst, attacker, is_thrown)
    if inst._shattered then return end
    inst._shattered = true

    local x, y, z = inst.Transform:GetWorldPosition()

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if TheWorld and TheWorld.SoundEmitter then
        TheWorld.SoundEmitter:PlaySound("dontstarve/common/destroy_pot")
    elseif inst.SoundEmitter then
        inst.SoundEmitter:PlaySound("dontstarve/common/destroy_pot")
    end

    local fx = SpawnPrefab("collapse_small")
    if fx then
        fx.Transform:SetPosition(x, y, z)
    end

    if is_thrown and TheSim then
        local ents = TheSim:FindEntities(x, y, z, 2.5, { "_combat" }, { "player", "companion", "INLIMBO", "playerghost" })
        for _, ent in ipairs(ents) do
            local health = ent.components.health or (ent.replica and ent.replica.health)
            if ent:IsValid() and health and not (health.IsDead and health:IsDead()) and ent.components.combat then
                ent.components.combat:GetAttacked(attacker or inst, 98)
            end
        end
    end

    DropPotLoot(inst, x, y, z)
    inst:Remove()
end

local function onequip(inst, owner)
    owner.AnimState:OverrideSymbol("swap_object", "ruins_vase", "idle")
    owner.AnimState:Show("ARM_carry")
    owner.AnimState:Hide("ARM_normal")
end

local function onunequip(inst, owner)
    owner.AnimState:Hide("ARM_carry")
    owner.AnimState:Show("ARM_normal")
end

local function onthrown(inst)
    inst:AddTag("NOCLICK")
    inst.persists = false
    inst.AnimState:PlayAnimation("idle", true)

    if inst.Physics then
        inst.Physics:SetMass(1)
        inst.Physics:SetCapsule(0.2, 0.2)
        inst.Physics:SetFriction(0)
        inst.Physics:SetDamping(0)
        inst.Physics:ClearCollisionMask()
        local world_col = COLLISION and rawget(COLLISION, "WORLD")
        if world_col then
            inst.Physics:CollidesWith(world_col)
        end
    end
end

local function onhit(inst, attacker, target)
    ShatterPot(inst, attacker, true)
end

local function MakeGroundPotPrefab(prefab_name, pot_type, item_prefab_name)
    local function fn()
        local inst = CreateEntity()

        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddSoundEmitter()
        inst.entity:AddNetwork()

        inst.AnimState:SetBank("ruins_vase")
        inst.AnimState:SetBuild("ruins_vase")
        inst.AnimState:PlayAnimation("idle", true)

        inst:AddTag("slashable")
        inst:AddTag("pot")

        inst.entity:SetPristine()

        local TheWorld = rawget(GLOBAL, "TheWorld")
        if not (TheWorld and TheWorld.ismastersim) then
            return inst
        end

        inst.pot_type = pot_type

        inst:AddComponent("inspectable")

        inst:AddComponent("pickable")
        inst.components.pickable.picksound = "dontstarve/wilson/pickup_plants"
        inst.components.pickable:SetUp(nil, 0)
        inst.components.pickable.canbepicked = true
        inst.components.pickable.onpickedfn = function(pot_inst, picker)
            local item = SpawnPrefab(item_prefab_name)
            if item then
                if picker and picker.components.inventory then
                    picker.components.inventory:GiveItem(item)
                else
                    local px, py, pz = pot_inst.Transform:GetWorldPosition()
                    item.Transform:SetPosition(px, py, pz)
                end
            end
            pot_inst:Remove()
            return true
        end

        inst:AddComponent("workable")
        local act_hammer = ACTIONS and rawget(ACTIONS, "HAMMER")
        if act_hammer then
            inst.components.workable:SetWorkAction(act_hammer)
            inst.components.workable:SetWorkLeft(1)
            inst.components.workable:SetOnFinishCallback(function(pot_inst, worker)
                ShatterPot(pot_inst, worker, false)
            end)
        end

        inst.OnHitBySlash = function(pot_inst, doer)
            ShatterPot(pot_inst, doer, false)
            return true
        end

        return inst
    end

    return Prefab(prefab_name, fn, assets, prefabs)
end

local function MakeItemPotPrefab(prefab_name, pot_type)
    local function fn()
        local inst = CreateEntity()

        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddSoundEmitter()
        inst.entity:AddNetwork()

        MakeInventoryPhysics(inst)
        if inst.Physics then
            inst.Physics:ClearCollisionMask()
            local world_col = COLLISION and rawget(COLLISION, "WORLD")
            if world_col then
                inst.Physics:CollidesWith(world_col)
            end
        end

        inst.AnimState:SetBank("ruins_vase")
        inst.AnimState:SetBuild("ruins_vase")
        inst.AnimState:PlayAnimation("idle", true)

        inst:AddTag("slashable")
        inst:AddTag("pot")
        inst:AddTag("projectile")
        inst:AddTag("weapon")

        inst:AddComponent("reticule")
        inst.components.reticule.targetfn = ReticuleTargetFn
        inst.components.reticule.twinstickcheckscheme = true
        inst.components.reticule.twinstickmode = 1
        inst.components.reticule.twinstickrange = 8
        inst.components.reticule.ease = true

        MakeInventoryFloatable(inst, "med", 0.05, 0.65)

        inst.entity:SetPristine()

        local TheWorld = rawget(GLOBAL, "TheWorld")
        if not (TheWorld and TheWorld.ismastersim) then
            return inst
        end

        inst.pot_type = pot_type

        inst:AddComponent("inspectable")

        inst:AddComponent("inventoryitem")
        inst.components.inventoryitem.canbepickedup = true
        inst.components.inventoryitem:ChangeImageName("alterguardianhatshard")

        inst:AddComponent("equippable")
        local hand_slot = (EQUIPSLOTS and rawget(EQUIPSLOTS, "HANDS")) or "hands"
        inst.components.equippable.equipslot = hand_slot
        inst.components.equippable:SetOnEquip(onequip)
        inst.components.equippable:SetOnUnequip(onunequip)

        inst:AddComponent("weapon")
        inst.components.weapon:SetDamage(0)
        inst.components.weapon:SetRange(8, 10)

        inst:AddComponent("complexprojectile")
        inst.components.complexprojectile:SetHorizontalSpeed(15)
        inst.components.complexprojectile:SetGravity(-35)
        inst.components.complexprojectile:SetLaunchOffset(Vector3(0.25, 1, 0))
        inst.components.complexprojectile:SetOnLaunch(onthrown)
        inst.components.complexprojectile:SetOnHit(onhit)

        inst.OnHitBySlash = function(pot_inst, doer)
            ShatterPot(pot_inst, doer, false)
            return true
        end

        return inst
    end

    return Prefab(prefab_name, fn, assets, prefabs)
end

-- ==========================================================
-- 快速构造接口与静态导出 (对齐 cc_memory 规范)
-- ==========================================================
local function MakeGroundPot(pot_type)
    return MakeGroundPotPrefab("cc_pot_" .. pot_type, pot_type, "cc_pot_" .. pot_type .. "_item")
end

local function MakeItemPot(pot_type)
    return MakeItemPotPrefab("cc_pot_" .. pot_type .. "_item", pot_type)
end

return -- 通用基础回退罐
       MakeGroundPotPrefab("cc_pot", "normal", "cc_pot_normal_item"),

       -- 1. 普通陶罐 (地面 & 物品)
       MakeGroundPot("normal"),
       MakeItemPot("normal"),

       -- 2. 桥梁陶罐 (地面 & 物品)
       MakeGroundPot("bridge"),
       MakeItemPot("bridge"),

       -- 3. 木质陶罐 (地面 & 物品)
       MakeGroundPot("wood"),
       MakeItemPot("wood")

       -- ================= 快速增加预制体通道 =================
       -- 以后需要新增型号，在 cc_tuning.lua 填完奖池后，直接在下方追加一行即可：
       -- MakeGroundPot("mineral"), MakeItemPot("mineral")