local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G
local CreateEntity = rawget(GLOBAL, "CreateEntity") or CreateEntity
local Prefab = rawget(GLOBAL, "Prefab") or Prefab
local Asset = rawget(GLOBAL, "Asset") or Asset
local SpawnPrefab = rawget(GLOBAL, "SpawnPrefab") or SpawnPrefab
local TheWorld = rawget(GLOBAL, "TheWorld")

local assets = {
    Asset("ANIM", "anim/white_grass.zip"),
}

local prefabs = {
    "cutgrass",
    "short_grass_fx",
}

local function fx_fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("grass")
    inst.AnimState:SetBuild("grass1")
    inst.AnimState:PlayAnimation("grass_part")
    inst.AnimState:SetFinalOffset(1)
    inst.AnimState:SetDeltaTimeMultiplier(3.0) -- 与 snowgrass 对齐加速 3 倍

    inst:AddTag("FX")
    inst:AddTag("NOCLICK")

    inst.entity:SetPristine()

    local world = TheWorld or rawget(GLOBAL, "TheWorld")
    if not (world and world.ismastersim) then
        return inst
    end

    inst:ListenForEvent("animover", inst.Remove)
    inst.persists = false
    return inst
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("white_grass")
    inst.AnimState:SetBuild("white_grass")
    inst.AnimState:PlayAnimation("idle", true)

    local total_frames = inst.AnimState:GetCurrentAnimationNumFrames()
    if total_frames and total_frames > 0 then
        inst.AnimState:SetFrame(math.random(total_frames) - 1)
    end

    inst:AddTag("NOCLICK")
    inst:AddTag("NOBLOCK")
    inst:AddTag("cuttable_grass")
    inst:AddTag("slashable")

    inst.entity:SetPristine()

    local world = TheWorld or rawget(GLOBAL, "TheWorld")
    if not (world and world.ismastersim) then
        return inst
    end

    local color = 0.85 + math.random() * 0.15
    inst.AnimState:SetMultColour(color, color, color, 1)

    inst.hits_left = 1

    -- 踩踏摇晃接口：只播放一次 rustle，播完回到循环 idle
    inst.OnSteppedOn = function(grass_inst)
        if not grass_inst.AnimState:IsCurrentAnimation("rustle") then
            grass_inst.AnimState:PlayAnimation("rustle")
            grass_inst.AnimState:PushAnimation("idle", true)
        end
    end

    inst.OnHitBySlash = function(grass_inst, doer)
        grass_inst.hits_left = (grass_inst.hits_left or 1) - 1
        if grass_inst.hits_left <= 0 then
            local fx = SpawnPrefab("snow_grass_fx")
            if fx then
                fx.Transform:SetPosition(grass_inst.Transform:GetWorldPosition())
            end
            grass_inst:Remove()
            return true
        end
        return false
    end

    inst.persists = false
    return inst
end

return Prefab("snow_grass", fn, assets, prefabs),
       Prefab("snow_grass_fx", fx_fn, assets)