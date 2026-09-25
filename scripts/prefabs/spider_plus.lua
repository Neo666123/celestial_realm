local GLOBAL = rawget(_G, "GLOBAL") or _G

local Prefab = rawget(GLOBAL, "Prefab")
local Asset = rawget(GLOBAL, "Asset")
local MakeCharacterPhysics = rawget(GLOBAL, "MakeCharacterPhysics")
local FindPlayersInRange = rawget(GLOBAL, "FindPlayersInRange")

local assets = {
    Asset("ANIM", "anim/ds_spider_basic.zip"),
    Asset("ANIM", "anim/spider_build.zip"),
    Asset("ANIM", "anim/ds_spider_warrior.zip"),
    Asset("ANIM", "anim/spider_warrior_build.zip"),
    Asset("SOUND", "sound/spider.fsb"),
}

local function RetargetFn(inst)
    local px, py, pz = inst.Transform:GetWorldPosition()
    if FindPlayersInRange then
        local players = FindPlayersInRange(px, py, pz, inst._target_dist or 16, true)
        for _, player in ipairs(players) do
            if player and player:IsValid() then
                local health = player.components.health or (player.replica and player.replica.health)
                if health and not (health.IsDead and health:IsDead()) then
                    return player
                end
            end
        end
    end
    return nil
end

local function KeepTargetFn(inst, target)
    if not (target and target:IsValid()) then return false end
    local health = target.components.health or (target.replica and target.replica.health)
    if health and (health.IsDead and health:IsDead()) then return false end
    return inst:IsNear(target, inst._lose_target_dist or 24)
end

local function SoundPath(inst, event)
    local creature = inst._sound_name or "spider"
    return "dontstarve/creatures/" .. creature .. "/" .. event
end

local function create_common(bank, build, tag, custom_init)
    local inst = GLOBAL.CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddDynamicShadow()
    inst.entity:AddNetwork()

    MakeCharacterPhysics(inst, 10, 0.5)

    inst.DynamicShadow:SetSize(1.5, 0.5)
    inst.Transform:SetFourFaced()

    inst:AddTag("monster")
    inst:AddTag("hostile")
    inst:AddTag("spider")
    inst:AddTag("spider_plus")
    if tag then inst:AddTag(tag) end

    inst.AnimState:SetBank(bank)
    inst.AnimState:SetBuild(build)
    inst.AnimState:PlayAnimation("idle", true)

    inst.SoundPath = SoundPath

    if custom_init then custom_init(inst) end

    inst.entity:SetPristine()

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not (TheWorld and TheWorld.ismastersim) then
        return inst
    end

    inst:AddComponent("locomotor")
    inst.components.locomotor:SetSlowMultiplier(1.0)
    inst.components.locomotor:SetTriggersCreep(false)
    inst.components.locomotor.pathcaps = { ignorecreep = true }

    inst:AddComponent("combat")
    inst.components.combat.hiteffectsymbol = "body"
    inst.components.combat:SetKeepTargetFunction(KeepTargetFn)

    inst:AddComponent("health")
    inst:AddComponent("inspectable")

    inst:SetStateGraph("SGspider_plus")

    return inst
end

local function create_spider_plus()
    local inst = create_common("spider", "spider_build", "spider_plus_scout", function(i)
        i.DynamicShadow:SetSize(1.0, 0.4)
        i.AnimState:SetDeltaTimeMultiplier(1.5)
    end)

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not (TheWorld and TheWorld.ismastersim) then return inst end

    inst._sound_name = "spider"
    inst._target_dist = 16
    inst._lose_target_dist = 24
    inst.components.health:SetMaxHealth(150)
    inst.components.combat:SetDefaultDamage(15)
    inst.components.combat:SetRetargetFunction(1, RetargetFn)

    -- 一键把调参表的所有参数灌入自身
    local InitTuning = rawget(GLOBAL, "ApplySpiderTuning")
    if InitTuning then InitTuning(inst, "spider_plus_scout") end

    inst:SetBrain(GLOBAL.require("brains/spider_plus_brain"))
    return inst
end

local function create_warrior_plus()
    local inst = create_common("spider", "spider_warrior_build", "spider_warrior_plus", nil)

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not (TheWorld and TheWorld.ismastersim) then return inst end

    inst._sound_name = "spiderwarrior"
    inst._target_dist = 18
    inst._lose_target_dist = 26
    inst.components.health:SetMaxHealth(400)
    inst.components.combat:SetDefaultDamage(30)
    inst.components.combat:SetRetargetFunction(1, RetargetFn)

    -- 一键把调参表的所有参数灌入自身
    local InitTuning = rawget(GLOBAL, "ApplySpiderTuning")
    if InitTuning then InitTuning(inst, "spider_warrior_plus") end

    inst:SetBrain(GLOBAL.require("brains/spider_warrior_plus_brain"))
    return inst
end

return Prefab("spider+", create_spider_plus, assets),
       Prefab("spider_warrior+", create_warrior_plus, assets)