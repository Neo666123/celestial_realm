local _G = rawget(_G, "_G") or _G
local GLOBAL = rawget(_G, "GLOBAL") or _G
local rawget = rawget
local rawset = rawset

local Asset = rawget(GLOBAL, "Asset")
local Prefab = rawget(GLOBAL, "Prefab")
local CreateEntity = rawget(GLOBAL, "CreateEntity")
local MakeInventoryPhysics = rawget(GLOBAL, "MakeInventoryPhysics")
local MakeInventoryFloatable = rawget(GLOBAL, "MakeInventoryFloatable")
local MakeMediumBurnable = rawget(GLOBAL, "MakeMediumBurnable")
local MakeMediumPropagator = rawget(GLOBAL, "MakeMediumPropagator")
local MakeHauntableLaunchAndIgnite = rawget(GLOBAL, "MakeHauntableLaunchAndIgnite")
local TUNING = rawget(GLOBAL, "TUNING")

local FUELTYPE = rawget(GLOBAL, "FUELTYPE")
if FUELTYPE ~= nil and rawget(FUELTYPE, "CC_COAL") == nil then
    rawset(FUELTYPE, "CC_COAL", "CC_COAL")
end

local assets =
{
    Asset("ANIM", "anim/charcoal.zip"),
}

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    if MakeInventoryPhysics ~= nil then
        MakeInventoryPhysics(inst)
    end

    inst.AnimState:SetBank("charcoal")
    inst.AnimState:SetBuild("charcoal")
    inst.AnimState:PlayAnimation("idle")

    inst.pickupsound = "wood"

    inst:AddTag("molebait")

    if MakeInventoryFloatable ~= nil then
        MakeInventoryFloatable(inst, "med", 0.05, 0.6)
    end

    inst.entity:SetPristine()

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if TheWorld == nil or not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("stackable")
    local max_stack = TUNING and TUNING.STACK_SIZE_SMALLITEM or 40
    inst.components.stackable.maxsize = max_stack

    inst:AddComponent("fuel")
    local med_fuel = TUNING and TUNING.MED_FUEL or 180
    inst.components.fuel.fuelvalue = med_fuel
    inst.components.fuel.fueltype = (FUELTYPE and rawget(FUELTYPE, "CC_COAL")) or "CC_COAL"

    inst:AddComponent("tradable")
    inst:AddComponent("bait")

    local med_burntime = TUNING and TUNING.MED_BURNTIME or 10
    if MakeMediumBurnable ~= nil then
        MakeMediumBurnable(inst, med_burntime)
    end
    if MakeMediumPropagator ~= nil then
        MakeMediumPropagator(inst)
    end

    if MakeHauntableLaunchAndIgnite ~= nil then
        MakeHauntableLaunchAndIgnite(inst)
    end

    inst:AddComponent("inspectable")

    inst:AddComponent("inventoryitem")
    if inst.components.inventoryitem.ChangeImageName ~= nil then
        inst.components.inventoryitem:ChangeImageName("charcoal")
    end

    return inst
end

return Prefab("cc_coal", fn, assets)