local _G = rawget(_G, "_G") or _G
local GLOBAL = rawget(_G, "GLOBAL") or _G
local rawget = rawget

local Asset = rawget(GLOBAL, "Asset")
local Prefab = rawget(GLOBAL, "Prefab")
local CreateEntity = rawget(GLOBAL, "CreateEntity")
local MakeObstaclePhysics = rawget(GLOBAL, "MakeObstaclePhysics")
local MakeHauntableWork = rawget(GLOBAL, "MakeHauntableWork")
local SpawnPrefab = rawget(GLOBAL, "SpawnPrefab")
local ACTIONS = rawget(GLOBAL, "ACTIONS")

local assets =
{
    Asset("ANIM", "anim/pig_house.zip"),
}

local prefabs =
{
    "cc_coal",
    "collapse_big",
}

local function OnHammered(inst, worker)
    if inst.components.lootdropper ~= nil then
        local drop_count = math.random(1, 3)
        for _ = 1, drop_count do
            inst.components.lootdropper:SpawnLootPrefab("cc_coal")
        end
    end

    if SpawnPrefab ~= nil then
        local fx = SpawnPrefab("collapse_big")
        if fx ~= nil then
            fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
            if fx.SetMaterial ~= nil then
                fx:SetMaterial("wood")
            end
        end
    end

    inst:Remove()
end

local function OnHit(inst, worker)
    inst.SoundEmitter:PlaySound("dontstarve/common/destroy_wood")
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddMiniMapEntity()
    inst.entity:AddNetwork()

    if MakeObstaclePhysics ~= nil then
        MakeObstaclePhysics(inst, 1)
    end

    inst.MiniMapEntity:SetIcon("pighouse.png")

    inst.AnimState:SetBank("pig_house")
    inst.AnimState:SetBuild("pig_house")
    inst.AnimState:PlayAnimation("burnt")

    inst:AddTag("structure")
    inst:AddTag("burnt")

    inst.entity:SetPristine()

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if TheWorld == nil or not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("lootdropper")

    inst:AddComponent("workable")
    if ACTIONS ~= nil and ACTIONS.HAMMER ~= nil then
        inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
    end
    inst.components.workable:SetWorkLeft(2)
    inst.components.workable:SetOnFinishCallback(OnHammered)
    inst.components.workable:SetOnWorkCallback(OnHit)

    inst:AddComponent("inspectable")

    if MakeHauntableWork ~= nil then
        MakeHauntableWork(inst)
    end

    return inst
end

return Prefab("cc_coalruin", fn, assets, prefabs)