local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G
local CreateEntity = rawget(GLOBAL, "CreateEntity")
local Prefab = rawget(GLOBAL, "Prefab")
local Asset = rawget(GLOBAL, "Asset")
local MakeObstaclePhysics = rawget(GLOBAL, "MakeObstaclePhysics")
local COLLISION = rawget(GLOBAL, "COLLISION")

local assets = {
    Asset("ANIM", "anim/vault_portal.zip"),
}

local function OnStartChanneling(inst, channeler)
    if not (inst.AnimState:IsCurrentAnimation("idle_on_loop") or inst.AnimState:IsCurrentAnimation("turn_on")) then
        inst.AnimState:PlayAnimation("turn_on")
        inst.AnimState:PushAnimation("idle_on_loop")
    end
    if not inst.SoundEmitter:PlayingSound("loop") then
        inst.SoundEmitter:PlaySound("rifts6/vault_portal/turn_on_powered_LP", "loop")
    end

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if TheWorld then
        TheWorld:PushEvent("ms_celestial_roguelike_door_activated", { door = inst, doer = channeler })
    end
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

    inst:AddTag("staysthroughvirtualrooms")

    inst.entity:SetPristine()

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not TheWorld or not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false

    inst:AddComponent("inspectable")
    inst:AddComponent("channelable")
    inst.components.channelable:SetChannelingFn(OnStartChanneling, OnStopChanneling)

    return inst
end

return Prefab("celestial_roguelike_door", fn, assets)