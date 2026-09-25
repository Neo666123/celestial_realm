local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G
local CreateEntity = rawget(GLOBAL, "CreateEntity") or CreateEntity
local Prefab = rawget(GLOBAL, "Prefab") or Prefab
local Asset = rawget(GLOBAL, "Asset") or Asset
local SpawnPrefab = rawget(GLOBAL, "SpawnPrefab") or SpawnPrefab
local TheWorld = rawget(GLOBAL, "TheWorld")

local assets = {
    Asset("ANIM", "anim/grass.zip"),
    Asset("ANIM", "anim/grass1.zip"),
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
    inst.AnimState:SetDeltaTimeMultiplier(3.0)

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
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("grass")
    inst.AnimState:SetBuild("grass1")
    inst.AnimState:PlayAnimation("idle", true)

    local total_frames = inst.AnimState:GetCurrentAnimationNumFrames()
    if total_frames and total_frames > 0 then
        inst.AnimState:SetFrame(math.random(total_frames) - 1)
    end

    inst:AddTag("NOBLOCK")
    inst:AddTag("plant")
    inst:AddTag("cuttable_grass")
    inst:AddTag("slashable")
    inst:AddTag("short_grass")

    inst.entity:SetPristine()

    local world = TheWorld or rawget(GLOBAL, "TheWorld")
    if not (world and world.ismastersim) then
        return inst
    end

    local color = 0.75 + math.random() * 0.25
    inst.AnimState:SetMultColour(color, color, color, 1)

    inst:AddComponent("inspectable")

    inst:AddComponent("pickable")
    inst.components.pickable.picksound = "dontstarve/wilson/pickup_reeds"
    inst.components.pickable.canbepicked = true
    inst.components.pickable.quickpick = false
    inst.components.pickable.onpickedfn = function(grass_inst, picker)
        if math.random() <= 0.40 then
            local loot = SpawnPrefab("cutgrass")
            if loot then
                if picker and picker.components.inventory then
                    picker.components.inventory:GiveItem(loot, nil, grass_inst:GetPosition())
                else
                    local gx, gy, gz = grass_inst.Transform:GetWorldPosition()
                    loot.Transform:SetPosition(gx, gy, gz)
                end
            end
        end

        grass_inst:RemoveComponent("pickable")
        grass_inst:RemoveTag("cuttable_grass")
        grass_inst:RemoveTag("slashable")

        grass_inst.AnimState:PlayAnimation("picking")
        grass_inst:ListenForEvent("animover", grass_inst.Remove)
    end

    inst.OnSteppedOn = function(grass_inst)
        if not grass_inst.AnimState:IsCurrentAnimation("rustle")
           and not grass_inst.AnimState:IsCurrentAnimation("picking") then
            grass_inst.AnimState:PlayAnimation("rustle")
            grass_inst.AnimState:PushAnimation("idle", true)
        end
    end

    inst.OnHitBySlash = function(grass_inst, doer)
        local fx = SpawnPrefab("short_grass_fx")
        if fx then
            fx.Transform:SetPosition(grass_inst.Transform:GetWorldPosition())
        end
        grass_inst:Remove()
        return true
    end

    inst.persists = false
    return inst
end

return Prefab("short_grass", fn, assets, prefabs),
       Prefab("short_grass_fx", fx_fn, assets)