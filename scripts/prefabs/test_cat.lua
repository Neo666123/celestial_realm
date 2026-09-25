local _G = rawget(_G, "GLOBAL") or _G
local CreateEntity = rawget(_G, "CreateEntity") or CreateEntity
local Asset = rawget(_G, "Asset") or Asset
local Prefab = rawget(_G, "Prefab") or Prefab

local assets = {
    Asset("ANIM", "anim/DeathCat.zip"),
}

local function PlayCycle(inst)
    inst.AnimState:PlayAnimation("animation", false)
    inst.AnimState:PushAnimation("pre", false)
    inst.AnimState:PushAnimation("snarling", false)
    inst.AnimState:PushAnimation("pst", false)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("bank0")
    inst.AnimState:SetBuild("DeathCat")

    inst.entity:SetPristine()

    local TheWorld = rawget(_G, "TheWorld")
    if TheWorld and not TheWorld.ismastersim then
        return inst
    end

    inst:ListenForEvent("animqueueover", PlayCycle)
    PlayCycle(inst)

    return inst
end

return Prefab("test_cat", fn, assets)