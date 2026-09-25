local _G = rawget(_G, "_G") or _G
local GLOBAL = rawget(_G, "GLOBAL") or _G
local rawget = rawget

local Asset = rawget(GLOBAL, "Asset")
local Prefab = rawget(GLOBAL, "Prefab")
local CreateEntity = rawget(GLOBAL, "CreateEntity")
local SetSharedLootTable = rawget(GLOBAL, "SetSharedLootTable")
local MakeObstaclePhysics = rawget(GLOBAL, "MakeObstaclePhysics")
local MakeSnowCoveredPristine = rawget(GLOBAL, "MakeSnowCoveredPristine")
local MakeSnowCovered = rawget(GLOBAL, "MakeSnowCovered")
local MakeHauntableWork = rawget(GLOBAL, "MakeHauntableWork")
local SpawnPrefab = rawget(GLOBAL, "SpawnPrefab")
local ACTIONS = rawget(GLOBAL, "ACTIONS")
local TUNING = rawget(GLOBAL, "TUNING")

local assets =
{
    Asset("ANIM", "anim/petrified_tree_short.zip"),
    Asset("ANIM", "anim/petrified_tree.zip"),
    Asset("ANIM", "anim/petrified_tree_tall.zip"),
    Asset("MINIMAP_IMAGE", "petrified_tree"),
}

local prefabs =
{
    "rocks",
    "flint",
    "nitre",
    "goldnugget",
    "rock_break_fx",
}

if SetSharedLootTable ~= nil then
    SetSharedLootTable("cc_goldtree_loot",
    {
        { "rocks",      1.00 },
        { "rocks",      1.00 },
        { "rocks",      1.00 },
        { "goldnugget", 1.00 },
        { "flint",      1.00 },
        { "goldnugget", 0.25 },
        { "flint",      0.60 },
    })

    SetSharedLootTable("cc_petrifiedtree_loot",
    {
        { "rocks", 1.00 },
        { "rocks", 1.00 },
        { "rocks", 1.00 },
        { "nitre", 1.00 },
        { "flint", 1.00 },
        { "nitre", 0.25 },
        { "flint", 0.60 },
    })
end

local function OnWork(inst, worker, workleft)
    if workleft <= 0 then
        local pt = inst:GetPosition()
        if SpawnPrefab ~= nil then
            local fx = SpawnPrefab("rock_break_fx")
            if fx ~= nil then
                fx.Transform:SetPosition(pt.x, pt.y, pt.z)
            end
        end
        if inst.components.lootdropper ~= nil then
            inst.components.lootdropper:DropLoot(pt)
        end
        inst:Remove()
    else
        local total_work = TUNING and TUNING.ROCKS_MINE or 6
        local anim =
            (workleft < total_work / 3 and "low") or
            (workleft < total_work * 2 / 3 and "med") or
            "full"
        inst.AnimState:PlayAnimation(anim)
    end
end

local function ApplyTreeSize(inst, size)
    inst.treeSize = size
    if size == "short" then
        inst.AnimState:SetBank("petrified_tree_short")
        inst.AnimState:SetBuild("petrified_tree_short")
        if inst.Physics ~= nil then
            inst.Physics:SetCapsule(0.25, 2)
        end
    elseif size == "med" then
        inst.AnimState:SetBank("petrified_tree")
        inst.AnimState:SetBuild("petrified_tree")
        if inst.Physics ~= nil then
            inst.Physics:SetCapsule(0.65, 2)
        end
    else
        inst.AnimState:SetBank("petrified_tree_tall")
        inst.AnimState:SetBuild("petrified_tree_tall")
        if inst.Physics ~= nil then
            inst.Physics:SetCapsule(1.0, 2)
        end
    end
end

local function OnSave(inst, data)
    data.treeSize = inst.treeSize
end

local function OnLoad(inst, data)
    if data ~= nil and data.treeSize ~= nil then
        ApplyTreeSize(inst, data.treeSize)
    end
end

local function TreeFn(default_bank, default_build, default_radius, loot_table, is_random_size)
    local function fn()
        local inst = CreateEntity()

        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddSoundEmitter()
        inst.entity:AddMiniMapEntity()
        inst.entity:AddNetwork()

        if MakeObstaclePhysics ~= nil then
            MakeObstaclePhysics(inst, default_radius)
        end

        inst.MiniMapEntity:SetIcon("petrified_tree.png")

        inst.AnimState:SetBank(default_bank)
        inst.AnimState:SetBuild(default_build)
        inst.AnimState:PlayAnimation("full")

        if MakeSnowCoveredPristine ~= nil then
            MakeSnowCoveredPristine(inst)
        end

        inst:AddTag("boulder")
        inst:AddTag("rock")

        inst.entity:SetPristine()

        local TheWorld = rawget(GLOBAL, "TheWorld")
        if TheWorld == nil or not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("inspectable")
        inst.components.inspectable.nameoverride = "PETRIFIED_TREE"

        inst:AddComponent("lootdropper")
        inst.components.lootdropper:SetChanceLootTable(loot_table)

        inst:AddComponent("workable")
        if ACTIONS ~= nil and ACTIONS.MINE ~= nil then
            inst.components.workable:SetWorkAction(ACTIONS.MINE)
        end
        local mine_work = TUNING and TUNING.ROCKS_MINE or 6
        inst.components.workable:SetWorkLeft(mine_work)
        inst.components.workable:SetOnWorkCallback(OnWork)

        if MakeSnowCovered ~= nil then
            MakeSnowCovered(inst)
        end

        if MakeHauntableWork ~= nil then
            MakeHauntableWork(inst)
        end

        if is_random_size then
            local selected_size = math.random() < 0.5 and "med" or "tall"
            ApplyTreeSize(inst, selected_size)
            inst.OnSave = OnSave
            inst.OnLoad = OnLoad
        end

        return inst
    end
    return fn
end

return Prefab("cc_petrifiedtree", TreeFn("petrified_tree", "petrified_tree", 0.65, "cc_petrifiedtree_loot", true), assets, prefabs),
       Prefab("cc_petrifiedtree_med", TreeFn("petrified_tree", "petrified_tree", 0.65, "cc_petrifiedtree_loot", false), assets, prefabs),
       Prefab("cc_petrifiedtree_tall", TreeFn("petrified_tree_tall", "petrified_tree_tall", 1.0, "cc_petrifiedtree_loot", false), assets, prefabs),
       Prefab("cc_goldtree", TreeFn("petrified_tree_short", "petrified_tree_short", 0.25, "cc_goldtree_loot", false), assets, prefabs)