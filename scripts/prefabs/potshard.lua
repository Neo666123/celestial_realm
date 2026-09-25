local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G
local CreateEntity = rawget(GLOBAL, "CreateEntity")
local Prefab = rawget(GLOBAL, "Prefab")
local Asset = rawget(GLOBAL, "Asset")
local TUNING = rawget(GLOBAL, "TUNING")
local MakeInventoryPhysics = rawget(GLOBAL, "MakeInventoryPhysics")
local MakeInventoryFloatable = rawget(GLOBAL, "MakeInventoryFloatable")
local MakeHauntableLaunch = rawget(GLOBAL, "MakeHauntableLaunch")

local assets = {
    Asset("ANIM", "anim/thulecite_pieces.zip"),
}

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank("thulecite_pieces")
    inst.AnimState:SetBuild("thulecite_pieces")
    inst.AnimState:PlayAnimation("anim")

    inst.pickupsound = "rock"

    MakeInventoryFloatable(inst, "small", 0.15, 0.9)

    inst.entity:SetPristine()

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not (TheWorld and TheWorld.ismastersim) then
        return inst
    end

    inst:AddComponent("inspectable")

    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem:ChangeImageName("thulecite_pieces")

    inst:AddComponent("stackable")
    local max_size = (TUNING and rawget(TUNING, "STACK_SIZE_SMALLITEM")) or 40
    inst.components.stackable.maxsize = max_size

    if MakeHauntableLaunch then
        MakeHauntableLaunch(inst)
    end

    return inst
end

return Prefab("potshard", fn, assets)