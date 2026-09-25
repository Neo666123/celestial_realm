local _G = rawget(_G, "_G") or _G
local GLOBAL = rawget(_G, "GLOBAL") or _G
local rawget = rawget
if require ~= nil then
    require("worldsettingsutil")
end

local Asset = rawget(GLOBAL, "Asset")
local Prefab = rawget(GLOBAL, "Prefab")
local CreateEntity = rawget(GLOBAL, "CreateEntity")
local SetSharedLootTable = rawget(GLOBAL, "SetSharedLootTable")
local MakeObstaclePhysics = rawget(GLOBAL, "MakeObstaclePhysics")
local RemovePhysicsColliders = rawget(GLOBAL, "RemovePhysicsColliders")
local MakeSnowCoveredPristine = rawget(GLOBAL, "MakeSnowCoveredPristine")
local MakeSnowCovered = rawget(GLOBAL, "MakeSnowCovered")
local FindEntity = rawget(GLOBAL, "FindEntity")
local WorldSettings_ChildSpawner_PreLoad = rawget(GLOBAL, "WorldSettings_ChildSpawner_PreLoad")
local WorldSettings_ChildSpawner_SpawnPeriod = rawget(GLOBAL, "WorldSettings_ChildSpawner_SpawnPeriod")
local WorldSettings_ChildSpawner_RegenPeriod = rawget(GLOBAL, "WorldSettings_ChildSpawner_RegenPeriod")

local assets =
{
    Asset("ANIM", "anim/hound_base.zip"),
    Asset("SOUND", "sound/hound.fsb"),
    Asset("MINIMAP_IMAGE", "hound_mound"),
}

local prefabs =
{
    "mutatedhound",
    "houndstooth",
    "boneshard",
    "moonrocknugget",
}

if SetSharedLootTable ~= nil then
    SetSharedLootTable("cc_moonhound_mound",
    {
        { "houndstooth",    1.00 },
        { "houndstooth",    1.00 },
        { "houndstooth",    1.00 },
        { "boneshard",      1.00 },
        { "boneshard",      1.00 },
        { "moonrocknugget", 0.50 },
    })
end

local function SpawnGuardHound(inst, attacker)
    if inst.components.childspawner == nil then
        return
    end

    local defender = inst.components.childspawner:SpawnChild(attacker, "mutatedhound")
    if defender ~= nil and attacker ~= nil and defender.components.combat ~= nil then
        defender.components.combat:SetTarget(attacker)
        defender.components.combat:BlankOutAttacks(1.5 + math.random() * 2)
    end
end

local function SpawnAllGuards(inst, attacker)
    if inst.components.health ~= nil and not inst.components.health:IsDead() and inst.components.childspawner ~= nil then
        inst.AnimState:PlayAnimation("hit")
        inst.AnimState:PushAnimation("idle", false)
        local num_to_release = inst.components.childspawner.childreninside
        for _ = 1, num_to_release do
            SpawnGuardHound(inst, attacker)
        end
    end
end

local function OnKilled(inst)
    if inst.components.childspawner ~= nil then
        inst.components.childspawner:ReleaseAllChildren()
    end

    if RemovePhysicsColliders ~= nil then
        RemovePhysicsColliders(inst)
    end

    inst.AnimState:PlayAnimation("death", false)
    inst.SoundEmitter:KillSound("loop")

    if inst.components.lootdropper ~= nil then
        inst.components.lootdropper:DropLoot(inst:GetPosition())
    end
end

local HAUNTTARGET_MUST_TAGS = { "_combat" }
local HAUNTTARGET_CANT_TAGS = { "wall", "playerghost", "houndmound", "hound", "houndfriend", "INLIMBO" }

local function OnHaunt(inst)
    local TUNING = rawget(GLOBAL, "TUNING")
    local haunt_half = TUNING and TUNING.HAUNT_CHANCE_HALF or 0.5

    if inst.components.childspawner == nil or
        not inst.components.childspawner:CanSpawn() or
        math.random() > haunt_half then
        return false
    end

    if FindEntity == nil then
        return false
    end

    local target = FindEntity(
        inst,
        25,
        function(guy)
            return inst.components.combat ~= nil and inst.components.combat:CanTarget(guy)
        end,
        HAUNTTARGET_MUST_TAGS,
        HAUNTTARGET_CANT_TAGS
    )

    if target ~= nil then
        SpawnAllGuards(inst, target)
        return true
    end

    return false
end

local function OnEntityWake(inst)
    if inst.components.childspawner ~= nil then
        inst.components.childspawner:StartSpawning()
    end
    inst.SoundEmitter:PlaySound("dontstarve/creatures/hound/mound_LP", "loop")
end

local function OnEntitySleep(inst)
    inst.SoundEmitter:KillSound("loop")
end

local function OnPreLoad(inst, data)
    local TUNING = rawget(GLOBAL, "TUNING")
    local release_time = TUNING and TUNING.HOUNDMOUND_RELEASE_TIME or 30
    local regen_time = TUNING and TUNING.HOUNDMOUND_REGEN_TIME or 120

    if WorldSettings_ChildSpawner_PreLoad ~= nil then
        WorldSettings_ChildSpawner_PreLoad(inst, data, release_time, regen_time)
    end
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddMiniMapEntity()
    inst.entity:AddNetwork()

    if MakeObstaclePhysics ~= nil then
        MakeObstaclePhysics(inst, 0.5)
    end

    inst.MiniMapEntity:SetIcon("hound_mound.png")

    inst.AnimState:SetBank("houndbase")
    inst.AnimState:SetBuild("hound_base")
    inst.AnimState:PlayAnimation("idle")

    inst:AddTag("structure")
    inst:AddTag("beaverchewable")
    inst:AddTag("houndmound")

    if MakeSnowCoveredPristine ~= nil then
        MakeSnowCoveredPristine(inst)
    end

    inst.entity:SetPristine()

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if TheWorld == nil or not TheWorld.ismastersim then
        return inst
    end

    local TUNING = rawget(GLOBAL, "TUNING")
    local regen_time = TUNING and TUNING.HOUNDMOUND_REGEN_TIME or 120
    local release_time = TUNING and TUNING.HOUNDMOUND_RELEASE_TIME or 30
    local min_hounds = TUNING and TUNING.HOUNDMOUND_HOUNDS_MIN or 2
    local max_hounds = TUNING and TUNING.HOUNDMOUND_HOUNDS_MAX or 4
    local enabled = true
    if TUNING and TUNING.HOUNDMOUND_ENABLED ~= nil then
        enabled = TUNING.HOUNDMOUND_ENABLED
    end

    inst:AddComponent("health")
    inst.components.health:SetMaxHealth(300)
    inst:ListenForEvent("death", OnKilled)

    inst:AddComponent("childspawner")
    inst.components.childspawner.childname = "mutatedhound"
    inst.components.childspawner:SetRegenPeriod(regen_time)
    inst.components.childspawner:SetSpawnPeriod(release_time)
    inst.components.childspawner:SetMaxChildren(math.random(min_hounds, max_hounds))

    if WorldSettings_ChildSpawner_SpawnPeriod ~= nil then
        WorldSettings_ChildSpawner_SpawnPeriod(inst, release_time, enabled)
    end
    if WorldSettings_ChildSpawner_RegenPeriod ~= nil then
        WorldSettings_ChildSpawner_RegenPeriod(inst, regen_time, enabled)
    end
    if not enabled then
        inst.components.childspawner.childreninside = 0
    end

    inst:AddComponent("lootdropper")
    inst.components.lootdropper:SetChanceLootTable("cc_moonhound_mound")

    inst:AddComponent("combat")
    inst.components.combat:SetOnHit(SpawnAllGuards)

    inst:AddComponent("hauntable")
    local haunt_small = TUNING and TUNING.HAUNT_SMALL or 0.25
    inst.components.hauntable:SetHauntValue(haunt_small)
    inst.components.hauntable:SetOnHauntFn(OnHaunt)

    inst:AddComponent("inspectable")

    inst.OnEntitySleep = OnEntitySleep
    inst.OnEntityWake = OnEntityWake

    if MakeSnowCovered ~= nil then
        MakeSnowCovered(inst)
    end

    inst.OnPreLoad = OnPreLoad

    return inst
end

return Prefab("cc_moonhound_mound", fn, assets, prefabs)