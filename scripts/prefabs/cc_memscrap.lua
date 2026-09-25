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

local GROUND_LIFETIME = 15
local FLICKER_START_TIME = 5

local function StopDissipate(inst)
    if inst._dissipate_task ~= nil then
        inst._dissipate_task:Cancel()
        inst._dissipate_task = nil
    end
    if inst._flicker_phase_task ~= nil then
        inst._flicker_phase_task:Cancel()
        inst._flicker_phase_task = nil
    end
    if inst._flicker_loop_task ~= nil then
        inst._flicker_loop_task:Cancel()
        inst._flicker_loop_task = nil
    end
    inst.AnimState:SetMultColour(0.5, 0.8, 1.0, 0.85)
end

local function StartDissipate(inst)
    StopDissipate(inst)

    inst._flicker_phase_task = inst:DoTaskInTime(math.max(0, GROUND_LIFETIME - FLICKER_START_TIME), function()
        local is_dim = false
        inst._flicker_loop_task = inst:DoPeriodicTask(0.15, function()
            is_dim = not is_dim
            if is_dim then
                inst.AnimState:SetMultColour(0.5, 0.8, 1.0, 0.2)
            else
                inst.AnimState:SetMultColour(0.5, 0.8, 1.0, 0.85)
            end
        end)
    end)

    inst._dissipate_task = inst:DoTaskInTime(GROUND_LIFETIME, function()
        local puff = SpawnPrefab("spawn_fx_small")
        if puff then
            local x, y, z = inst.Transform:GetWorldPosition()
            puff.Transform:SetPosition(x, y, z)
        end
        inst:Remove()
    end)
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

                -- 寻找该堆叠所在的槽位，整槽全部丢出
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

local function OnPutInInventory(inst, owner)
    StopDissipate(inst)
    CheckAndEjectFromContainer(inst, owner)
end

local function OnDropped(inst)
    StartDissipate(inst)
end

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
    inst.AnimState:SetMultColour(0.5, 0.8, 1.0, 0.85)

    inst.Light:SetRadius(0.5)
    inst.Light:SetFalloff(0.8)
    inst.Light:SetIntensity(0.5)
    inst.Light:SetColour(0.5, 0.8, 1.0)
    inst.Light:Enable(true)

    inst:AddTag("cc_memory_item")
    inst:AddTag("cc_memscrap")

    inst.entity:SetPristine()

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not TheWorld or not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inspectable")
    inst.components.inspectable:SetDescription("微弱的思绪残片，脱离意志后会迅速消散。")

    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem:ChangeImageName("alterguardianhatshard")
    inst.components.inventoryitem.keepondeath = false
    inst.components.inventoryitem:SetOnPutInInventoryFn(OnPutInInventory)
    inst.components.inventoryitem:SetOnDroppedFn(OnDropped)

    inst:AddComponent("stackable")
    inst.components.stackable.maxsize = TUNING and TUNING.STACK_SIZE_TINYITEM or 60

    MakeHauntableLaunch(inst)

    inst:DoTaskInTime(0, function()
        if not (inst.components.inventoryitem and inst.components.inventoryitem:IsHeld()) then
            StartDissipate(inst)
        end
    end)

    return inst
end

return Prefab("cc_memscrap", fn, assets)