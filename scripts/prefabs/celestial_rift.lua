local assets = {
    Asset("ANIM", "anim/lunar_rift_portal.zip"),
    Asset("ANIM", "anim/lunar_rift_portal_small.zip"),
}

local AMBIENT_SOUND_PATH = "rifts/portal/rift_portal_allstage"
local AMBIENT_SOUND_LOOP_NAME = "lunarrift_portal_ambience"
local AMBIENT_SOUND_PARAM_NAME = "param00"

local function OnPortalSleep(inst)
    inst.SoundEmitter:KillSound(AMBIENT_SOUND_LOOP_NAME)
end

local function OnPortalWake(inst)
    inst.SoundEmitter:PlaySound(AMBIENT_SOUND_PATH, AMBIENT_SOUND_LOOP_NAME)
    inst.SoundEmitter:SetParameter(AMBIENT_SOUND_LOOP_NAME, AMBIENT_SOUND_PARAM_NAME, 0.8)
end

local function SafeLeave(inst, doer)
    if doer and doer:IsValid() and doer.components.talker then
        doer.components.talker:Say("111")
    end
end

local function LinkRifts(inst, mainland_rift)
    if not (mainland_rift and mainland_rift:IsValid()) then return end

    if not mainland_rift.components.teleporter then
        mainland_rift:AddComponent("teleporter")
        mainland_rift.components.teleporter.offset = 4
        mainland_rift.components.teleporter.saveenabled = false
        mainland_rift.components.teleporter.onActivate = SafeLeave
    end

    inst:ReturnToScene()
    inst.AnimState:PlayAnimation("stage_3_appear")
    inst.AnimState:PushAnimation("stage_3_loop", true)

    inst.components.teleporter:SetEnabled(true)
    mainland_rift.components.teleporter:SetEnabled(true)

    mainland_rift.components.teleporter:Target(inst)
    inst.components.teleporter:Target(mainland_rift)
    print("[CelestialRift] 裂隙双向通道已激活！")
end

local function OnRiftAddedToPool(inst, data)
    if data and data.rift and (data.rift.prefab == "lunarrift_portal" or data.rift:HasTag("lunarrift_portal")) then
        LinkRifts(inst, data.rift)
    end
end

local function OnRiftClosed(inst, data)
    inst.components.teleporter:SetEnabled(false)
    inst.components.teleporter:Target(nil)
    inst.AnimState:PlayAnimation("stage_3_disappear")
    inst:DoTaskInTime(0.5, function()
        inst:RemoveFromScene()
    end)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddLight()
    inst.entity:AddNetwork()

    MakeObstaclePhysics(inst, 3.2)
    inst.Physics:SetCylinder(3.2, 6)

    local animstate = inst.AnimState
    animstate:SetBank("lunar_rift_portal")
    animstate:SetBuild("lunar_rift_portal")
    animstate:AddOverrideBuild("lunar_rift_portal_small")
    animstate:SetOrientation(ANIM_ORIENTATION.OnGroundFixed)
    animstate:SetLayer(LAYER_BACKGROUND)
    animstate:SetSortOrder(2)

    inst:SetDeploySmartRadius(3.5)
    inst.AnimState:SetLightOverride(1)
    inst.Light:SetIntensity(0.7)
    inst.Light:SetRadius(2.5)
    inst.Light:SetFalloff(0.8)
    inst.Light:SetColour(119 / 255, 255 / 255, 255 / 255)
    inst.Light:Enable(true)

    inst:AddTag("ignorewalkableplatforms")
    inst:AddTag("scarytoprey")
    inst:AddTag("lunarrift_portal")
    
    inst:AddTag("teleporter") 
    inst:AddTag("celestial_rift_anchor")

    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end

    inst:AddComponent("inspectable")
    inst:AddComponent("teleporter")
    inst.components.teleporter.offset = 4
    inst.components.teleporter:SetEnabled(false)
    inst.components.teleporter.onActivate = SafeLeave
    inst.components.teleporter.saveenabled = false

    inst.OnEntitySleep = OnPortalSleep
    inst.OnEntityWake = OnPortalWake

    -- 默认隐藏，等待主大陆裂隙被激活后触发显示
    inst:RemoveFromScene()

    inst.OnRiftAddedToPool = function(world, data) OnRiftAddedToPool(inst, data) end
    inst.OnRiftClosed = function(world, data) OnRiftClosed(inst, data) end

    inst:ListenForEvent("ms_riftaddedtopool", inst.OnRiftAddedToPool, TheWorld)
    inst:ListenForEvent("ms_riftremovedfrompool", inst.OnRiftClosed, TheWorld)

    -- 如果游戏加载时主世界裂隙已存在，直接连通
    inst:DoTaskInTime(2, function()
        if TheWorld.components.riftspawner then
            local rifts = TheWorld.components.riftspawner:GetRiftsOfPrefab("lunarrift_portal")
            if rifts and rifts[1] then
                LinkRifts(inst, rifts[1])
            end
        end
    end)

    return inst
end

return Prefab("celestial_rift", fn, assets)