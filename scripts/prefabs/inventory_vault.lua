local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G
local CreateEntity = rawget(GLOBAL, "CreateEntity")
local Prefab = rawget(GLOBAL, "Prefab")

local function OnSave(inst, data)
    data.owner_userid = inst.owner_userid
    data.vault_type = inst.vault_type
    data.stored_recipes = inst.stored_recipes
    data.stored_buffered_builds = inst.stored_buffered_builds
end

local function OnLoad(inst, data)
    if data then
        inst.owner_userid = data.owner_userid
        inst.vault_type = data.vault_type
        inst.stored_recipes = data.stored_recipes or {}
        inst.stored_buffered_builds = data.stored_buffered_builds or {}
        if inst.owner_userid and inst.vault_type then
            inst:AddTag("vault_" .. inst.vault_type .. "_" .. inst.owner_userid)
        end
    end
end

local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()

    inst:AddTag("NOCLICK")
    inst:AddTag("NOBLOCK")
    inst:AddTag("CLASSIFIED")

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not TheWorld or not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("container")
    inst.components.container.numslots = 50
    inst.components.container.ignorescangoincontainer = true
    inst.components.container.canbeopened = false

    inst.stored_recipes = {}
    inst.stored_buffered_builds = {}

    inst.OnSave = OnSave
    inst.OnLoad = OnLoad
    inst.persists = true

    return inst
end

return Prefab("inventory_vault", fn)