local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G
local CreateEntity = rawget(GLOBAL, "CreateEntity")
local Prefab = rawget(GLOBAL, "Prefab")
local Asset = rawget(GLOBAL, "Asset")
local MakeObstaclePhysics = rawget(GLOBAL, "MakeObstaclePhysics")
local COLLISION = rawget(GLOBAL, "COLLISION")
local SpawnPrefab = rawget(GLOBAL, "SpawnPrefab")
local Vector3 = rawget(GLOBAL, "Vector3")
local EQUIPSLOTS = rawget(GLOBAL, "EQUIPSLOTS")

local assets = {
    Asset("ANIM", "anim/vault_portal.zip"),
}

local EQUIP_ID_TO_SLOT = {
    [EQUIPSLOTS.HANDS] = 31,
    [EQUIPSLOTS.BODY]  = 32,
    [EQUIPSLOTS.HEAD]  = 33,
}

local EQUIP_SLOT_IDS = {
    [31] = EQUIPSLOTS.HANDS,
    [32] = EQUIPSLOTS.BODY,
    [33] = EQUIPSLOTS.HEAD,
}

local function ValidateRecipe(recname)
    local IsRecipeValid = rawget(GLOBAL, "IsRecipeValid")
    if IsRecipeValid then
        return IsRecipeValid(recname)
    end
    local AllRecipes = rawget(GLOBAL, "AllRecipes")
    return AllRecipes ~= nil and AllRecipes[recname] ~= nil
end

local function GetOrCreateVault(userid, vault_type)
    local TheSim = rawget(GLOBAL, "TheSim")
    local tag = "vault_" .. vault_type .. "_" .. tostring(userid)
    local vault = TheSim:FindFirstEntityWithTag(tag)
    if vault and vault:IsValid() then
        return vault
    end

    vault = SpawnPrefab("inventory_vault")
    if vault then
        vault.owner_userid = tostring(userid)
        vault.vault_type = vault_type
        vault:AddTag(tag)
        vault.Transform:SetPosition(0, -50, 0)
    end
    return vault
end

local function StashInventoryToVault(player, vault)
    local inv = player.components.inventory
    local container = vault and vault.components.container
    if not inv or not container then return end

    if inv.activeitem then
        inv:ReturnActiveItem()
    end
    if inv.activeitem then
        local act = inv.activeitem
        inv:SetActiveItem(nil)
        container:GiveItem(act, 34)
    end

    for eslot, slot_idx in pairs(EQUIP_ID_TO_SLOT) do
        local item = inv:Unequip(eslot, nil, true)
        if item and item:IsValid() then
            container:GiveItem(item, slot_idx)
        end
    end

    for slot = 1, inv.maxslots do
        local item = inv:RemoveItemBySlot(slot)
        if item and item:IsValid() then
            container:GiveItem(item, slot)
        end
    end
end

local function RestoreInventoryFromVault(player, vault)
    local inv = player.components.inventory
    local container = vault and vault.components.container
    if not inv or not container then return end

    for slot_idx, eslot in pairs(EQUIP_SLOT_IDS) do
        local item = container:RemoveItemBySlot(slot_idx)
        if item and item:IsValid() then
            inv:Equip(item)
        end
    end

    for slot = 1, inv.maxslots do
        local item = container:RemoveItemBySlot(slot)
        if item and item:IsValid() then
            inv:GiveItem(item, slot)
        end
    end

    for slot = 34, container.numslots do
        local item = container:RemoveItemBySlot(slot)
        if item and item:IsValid() then
            inv:GiveItem(item)
        end
    end
end

local function StashBuilderToVault(player, vault)
    local builder = player and player.components and player.components.builder
    if not (builder and vault) then
        return
    end

    local buffered = {}
    if builder.buffered_builds then
        for recname, is_buffered in pairs(builder.buffered_builds) do
            if is_buffered then
                buffered[recname] = true
            end
        end
    end
    vault.stored_buffered_builds = buffered
    for recname, _ in pairs(buffered) do
        builder:SetBuildBuffered(recname, false)
    end

    local recipes = {}
    if builder.recipes then
        for _, recname in ipairs(builder.recipes) do
            recipes[#recipes + 1] = recname
        end
    end
    vault.stored_recipes = recipes
    for _, recname in ipairs(recipes) do
        builder:RemoveRecipe(recname)
    end

    player:PushEvent("unlockrecipe")
    player:PushEvent("refreshcrafting")
end

local function RestoreBuilderFromVault(player, vault)
    local builder = player and player.components and player.components.builder
    if not (builder and vault) then
        return
    end

    local stored_recipes = vault.stored_recipes
    if stored_recipes then
        for _, recname in ipairs(stored_recipes) do
            if ValidateRecipe(recname) then
                builder:AddRecipe(recname)
            end
        end
        vault.stored_recipes = {}
    end

    local stored_buffered = vault.stored_buffered_builds
    if stored_buffered then
        for recname, is_buffered in pairs(stored_buffered) do
            if is_buffered and ValidateRecipe(recname) then
                builder:SetBuildBuffered(recname, true)
            end
        end
        vault.stored_buffered_builds = {}
    end

    player:PushEvent("unlockrecipe")
    player:PushEvent("refreshcrafting")
end

local function GetCelestialExitPosition()
    local TheSim = rawget(GLOBAL, "TheSim")
    if not TheSim then return nil end

    -- 优先寻找天界内由地图生成的 portal_exit
    local exit_gate = TheSim:FindFirstEntityWithTag("portal_exit")
    if exit_gate and exit_gate:IsValid() then
        local ex, _, ez = exit_gate.Transform:GetWorldPosition()
        return Vector3(ex, 0, ez)
    end

    -- 备用兼容旧版锚点
    local anchor = TheSim:FindFirstEntityWithTag("celestial_rift_anchor")
        or TheSim:FindFirstEntityWithTag("celestial_hall_anchor")
    if anchor and anchor:IsValid() then
        local ex, _, ez = anchor.Transform:GetWorldPosition()
        return Vector3(ex, 0, ez)
    end

    return nil
end

local function TransferPlayerToDomain(inst, doer)
    if not (doer and doer:IsValid() and doer:HasTag("player")) then
        return
    end

    local exit_pos = GetCelestialExitPosition()
    if not exit_pos then
        if doer.components.talker then
            doer.components.talker:Say("未能在天界定位到出口传送门(portal_exit)！")
        end
        return
    end

    local overworld_vault = GetOrCreateVault(doer.userid, "overworld")
    local celestial_vault = GetOrCreateVault(doer.userid, "celestial")

    StashInventoryToVault(doer, overworld_vault)
    RestoreInventoryFromVault(doer, celestial_vault)

    StashBuilderToVault(doer, overworld_vault)
    RestoreBuilderFromVault(doer, celestial_vault)

    doer:AddTag("in_celestial_realm")
    local builder = doer.components.builder
    if builder then
        if doer.prefab == "wickerbottom" then
            builder.science_bonus = 0
        end
        builder:EvaluateTechTrees()
    end

    -- 偏移 2 码落地，防止卡入 portal_exit 的碰撞体积
    local dest_x = exit_pos.x + 2.0
    local dest_y = exit_pos.y
    local dest_z = exit_pos.z

    local cur_pos = doer:GetPosition()
    local puff = SpawnPrefab("sand_puff")
    if puff then puff.Transform:SetPosition(cur_pos.x, cur_pos.y, cur_pos.z) end

    doer.Transform:SetPosition(dest_x, dest_y, dest_z)

    local arrive_fx = SpawnPrefab("spawn_fx_small")
    if arrive_fx then arrive_fx.Transform:SetPosition(dest_x, dest_y, dest_z) end

    if doer.SoundEmitter then
        doer.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_whoosh")
    end

    doer:PushEvent("techtreechange")
    doer:PushEvent("refreshcrafting")

    if doer.components.talker then
        doer.components.talker:Say("已跨越裂隙，科技与物资已切换为天界白板状态。")
    end
end

local function OnStartChanneling(inst, channeler)
    if not (inst.AnimState:IsCurrentAnimation("idle_on_loop") or inst.AnimState:IsCurrentAnimation("turn_on")) then
        inst.AnimState:PlayAnimation("turn_on")
        inst.AnimState:PushAnimation("idle_on_loop")
    end
    if not inst.SoundEmitter:PlayingSound("loop") then
        inst.SoundEmitter:PlaySound("rifts6/vault_portal/turn_on_powered_LP", "loop")
    end
    TransferPlayerToDomain(inst, channeler)
end

local function OnStopChanneling(inst, aborted, channeler)
    if not (inst.components.channelable:IsChanneling() or inst.AnimState:IsCurrentAnimation("idle_off")) then
        inst.AnimState:PlayAnimation("turn_off")
        inst.AnimState:PushAnimation("idle_off")
        inst.SoundEmitter:PlaySound("rifts6/vault_portal/turn_off")
    end
    inst.SoundEmitter:KillSound("loop")
end

local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    MakeObstaclePhysics(inst, 0.2)
    inst.Physics:ClearCollidesWith(COLLISION.GIANTS)

    inst.AnimState:SetBank("vault_portal")
    inst.AnimState:SetBuild("vault_portal")
    inst.AnimState:PlayAnimation("idle_off", true)

    inst.AnimState:SetMultColour(0.3, 0.85, 1.0, 1.0)
    inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")

    inst:AddTag("staysthroughvirtualrooms")
    inst:AddTag("portal_entrance")

    inst.entity:SetPristine()

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not TheWorld or not TheWorld.ismastersim then
        return inst
    end

    inst.persists = true
    inst:AddComponent("inspectable")
    inst:AddComponent("channelable")
    inst.components.channelable:SetChannelingFn(OnStartChanneling, OnStopChanneling)

    return inst
end

return Prefab("portal_entrance", fn, assets)