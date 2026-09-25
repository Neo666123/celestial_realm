local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G
local CreateEntity = rawget(GLOBAL, "CreateEntity")
local Prefab = rawget(GLOBAL, "Prefab")
local Asset = rawget(GLOBAL, "Asset")
local SpawnPrefab = rawget(GLOBAL, "SpawnPrefab")
local Vector3 = rawget(GLOBAL, "Vector3")
local ACTIONS = rawget(GLOBAL, "ACTIONS")
local TUNING = rawget(GLOBAL, "TUNING")
local POPULATING = rawget(GLOBAL, "POPULATING")
local DEPLOYSPACING = rawget(GLOBAL, "DEPLOYSPACING")
local DEPLOYSPACING_RADIUS = rawget(GLOBAL, "DEPLOYSPACING_RADIUS")
local DEPLOYMODE = rawget(GLOBAL, "DEPLOYMODE")
local MakeInventoryPhysics = rawget(GLOBAL, "MakeInventoryPhysics")
local MakeInventoryFloatable = rawget(GLOBAL, "MakeInventoryFloatable")
local MakeSmallBurnable = rawget(GLOBAL, "MakeSmallBurnable")
local MakeSmallPropagator = rawget(GLOBAL, "MakeSmallPropagator")
local MakePlacer = rawget(GLOBAL, "MakePlacer")
local Ingredient = rawget(GLOBAL, "Ingredient")
local CONSTRUCTION_PLANS = rawget(GLOBAL, "CONSTRUCTION_PLANS")
local WORLD_TILES = rawget(GLOBAL, "WORLD_TILES")
local TempTile_HandleTileChange = rawget(GLOBAL, "TempTile_HandleTileChange")
local net_smallbyte = rawget(GLOBAL, "net_smallbyte")

if CONSTRUCTION_PLANS ~= nil and Ingredient ~= nil then
    CONSTRUCTION_PLANS["cc_brigdepost"] = {
        Ingredient("log", 2),
    }
end

local assets = {
    Asset("ANIM", "anim/dock_woodposts.zip"),
    Asset("ANIM", "anim/rope_bridge.zip"),
}

local prefabs = {
    "collapse_small",
    "log",
    "boards",
    "rope_bridge_fx",
    "construction_container",
}

local loot = {
    "log",
}

local CARDINAL_DIRS = {
    Vector3(1, 0, 0),
    Vector3(-1, 0, 0),
    Vector3(0, 0, 1),
    Vector3(0, 0, -1),
}

local function CheckPair(inst)
    if inst.is_bridge_built then
        return nil, nil
    end

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not (TheWorld and TheWorld.Map) or inst.tile_cx == nil or inst.tile_cz == nil then
        return nil, nil
    end
    local map = TheWorld.Map

    local cx = inst.tile_cx
    local cz = inst.tile_cz

    for _, dir in ipairs(CARDINAL_DIRS) do
        local spots = {}
        local pair_post = nil

        for step = 1, 11 do
            local test_x = cx + dir.x * step * 4
            local test_z = cz + dir.z * step * 4
            local tile = map:GetTileAtPoint(test_x, 0, test_z)

            if map:BridgeFilter_OceanAndVoid(tile) then
                table.insert(spots, Vector3(test_x, 0, test_z))
                if #spots > 10 then
                    break
                end
            else
                local entities = TheSim:FindEntities(test_x, 0, test_z, 2.5, { "cc_brigdepost" })
                for _, other in ipairs(entities) do
                    if other ~= inst and not other.is_bridge_built then
                        pair_post = other
                        break
                    end
                end
                break
            end
        end

        if pair_post ~= nil and #spots >= 1 and #spots <= 10 then
            spots.direction = dir
            return pair_post, spots
        end
    end

    return nil, nil
end

local function ApplySelfPlans(inst)
    local boards = inst.required_boards or 0
    local logs = inst.required_logs or 0
    local plans = {}
    if boards > 0 then
        table.insert(plans, Ingredient("boards", boards))
    end
    if logs > 0 then
        table.insert(plans, Ingredient("log", logs))
    end
    if #plans == 0 then
        table.insert(plans, Ingredient("log", 2))
    end

    if CONSTRUCTION_PLANS ~= nil then
        CONSTRUCTION_PLANS["cc_brigdepost"] = plans
    end
end

local function UpdateBridgeStatus(inst)
    if inst.is_bridge_built then
        return
    end

    local pair, spots = CheckPair(inst)

    if pair ~= nil and spots ~= nil then
        local distance = #spots
        local total_logs = distance * 2
        local num_boards = 0
        local num_logs = 0

        if distance <= 4 then
            num_boards = 0
            num_logs = total_logs
        else
            num_boards = math.floor(total_logs / 4)
            num_logs = total_logs % 4
        end

        inst.paired_post = pair
        inst._bridge_spots = spots
        inst.required_boards = num_boards
        inst.required_logs = num_logs
        inst._required_boards:set(num_boards)
        inst._required_logs:set(num_logs)

        inst:AddTag("constructionsite")
        if inst.components.constructionsite ~= nil then
            inst.components.constructionsite:Enable()
        end

        pair.paired_post = inst
        pair._bridge_spots = spots
        pair.required_boards = num_boards
        pair.required_logs = num_logs
        pair._required_boards:set(num_boards)
        pair._required_logs:set(num_logs)

        pair:AddTag("constructionsite")
        if pair.components.constructionsite ~= nil then
            pair.components.constructionsite:Enable()
        end
    else
        inst.paired_post = nil
        inst._bridge_spots = nil
        inst.required_boards = 0
        inst.required_logs = 0
        inst._required_boards:set(0)
        inst._required_logs:set(0)

        inst:RemoveTag("constructionsite")
        if inst.components.constructionsite ~= nil then
            inst.components.constructionsite:Disable()
        end
    end
end

local function BuildRopeBridge(inst, doer)
    local spots = inst._bridge_spots
    local other = inst.paired_post
    if not spots then
        return
    end

    inst.is_bridge_built = true
    inst:RemoveTag("constructionsite")
    inst:RemoveComponent("constructionsite")

    if other ~= nil and other:IsValid() then
        other.is_bridge_built = true
        other:RemoveTag("constructionsite")
        other:RemoveComponent("constructionsite")
    end

    local rot = (spots.direction.x > 0 and 0) or
                (spots.direction.x < 0 and 180) or
                (spots.direction.z > 0 and -90) or 90

    local TheWorld = rawget(GLOBAL, "TheWorld")
    local map = TheWorld and TheWorld.Map
    local ropebridgemanager = TheWorld and TheWorld.components.ropebridgemanager
    local bridge_tile = (WORLD_TILES and (WORLD_TILES.ROPE_BRIDGE or WORLD_TILES.MONKEY_DOCK)) or 201

    inst.original_tiles = {}

    for i, spot in ipairs(spots) do
        if map ~= nil then
            local tx, ty = map:GetTileCoordsAtPoint(spot.x, 0, spot.z)
            inst.original_tiles[tx .. "_" .. ty] = map:GetTile(tx, ty)
        end

        if ropebridgemanager ~= nil then
            local spawndata = {
                base_time = 0.2 * i,
                direction = spots.direction,
            }
            ropebridgemanager:QueueCreateRopeBridgeAtPoint(spot.x, spot.y, spot.z, spawndata)
        else
            local plank = SpawnPrefab("rope_bridge_fx")
            if plank ~= nil then
                plank.Transform:SetPosition(spot.x, 0, spot.z)
                plank.Transform:SetRotation(rot)
            end
            if map ~= nil then
                local tx, ty = map:GetTileCoordsAtPoint(spot.x, 0, spot.z)
                map:SetTile(tx, ty, bridge_tile)
            end
        end
    end

    if other ~= nil and other:IsValid() then
        other.original_tiles = inst.original_tiles
        other._bridge_spots = inst._bridge_spots
    end

    inst.AnimState:PlayAnimation("place" .. tostring(inst._post_id or 1))
    inst.AnimState:PushAnimation("idle" .. tostring(inst._post_id or 1), false)
    inst.SoundEmitter:PlaySound("monkeyisland/dock/post_place")

    if other ~= nil and other:IsValid() then
        other.AnimState:PlayAnimation("place" .. tostring(other._post_id or 1))
        other.AnimState:PushAnimation("idle" .. tostring(other._post_id or 1), false)
        other.SoundEmitter:PlaySound("monkeyisland/dock/post_place")
    end

    if doer ~= nil and doer.components.talker ~= nil then
        doer.components.talker:Say("索桥搭设完毕！")
    end
end

local function CollapseBridge(inst)
    if not inst.is_bridge_built or not inst._bridge_spots then
        return
    end

    local TheWorld = rawget(GLOBAL, "TheWorld")
    local map = TheWorld and TheWorld.Map
    local ropebridgemanager = TheWorld and TheWorld.components.ropebridgemanager
    local spots = inst._bridge_spots

    for _, spot in ipairs(spots) do
        if ropebridgemanager ~= nil then
            ropebridgemanager:QueueDestroyForRopeBridgeAtPoint(spot.x, 0, spot.z)
        else
            if map ~= nil then
                local tx, ty = map:GetTileCoordsAtPoint(spot.x, 0, spot.z)
                local old_tile = (inst.original_tiles and inst.original_tiles[tx .. "_" .. ty]) or WORLD_TILES.IMPASSABLE
                map:SetTile(tx, ty, old_tile)
                if TempTile_HandleTileChange ~= nil then
                    TempTile_HandleTileChange(spot.x, 0, spot.z, old_tile)
                end
            end
            local fxs = TheSim:FindEntities(spot.x, 0, spot.z, 2, { "FX" })
            for _, fx in ipairs(fxs) do
                if fx.prefab == "rope_bridge_fx" then
                    if fx.KillFX ~= nil then
                        fx:KillFX()
                    else
                        fx:Remove()
                    end
                end
            end
        end
    end

    if inst.SoundEmitter ~= nil then
        inst.SoundEmitter:PlaySound("rifts4/rope_bridge/break")
    end

    inst.is_bridge_built = false
    inst._bridge_spots = nil

    local other = inst.paired_post
    if other ~= nil and other:IsValid() then
        other.is_bridge_built = false
        other.paired_post = nil
        other._bridge_spots = nil
        other.original_tiles = nil
        other:DoTaskInTime(0.5, other.UpdateBridgeStatus)
    end
end

local function OnConstructed(inst, doer)
    ApplySelfPlans(inst)
    if inst.components.constructionsite ~= nil and inst.components.constructionsite:IsComplete() then
        BuildRopeBridge(inst, doer)
    end
end

local function OnStartConstruction(inst, doer)
    ApplySelfPlans(inst)
end

local function OnHammered(inst, worker)
    if inst.components.constructionsite ~= nil then
        inst.components.constructionsite:DropAllMaterials()
    end

    if inst.is_bridge_built then
        CollapseBridge(inst)
    end

    inst.components.lootdropper:DropLoot()

    local fx = SpawnPrefab("collapse_small")
    fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
    fx:SetMaterial("wood")

    local other = inst.paired_post
    inst:Remove()

    if other ~= nil and other:IsValid() then
        UpdateBridgeStatus(other)
    end
end

local function OnHit(inst)
    local idleanim = "idle" .. tostring(inst._post_id or 1)
    if inst.AnimState:IsCurrentAnimation(idleanim) or inst.AnimState:GetCurrentAnimationFrame() >= 15 then
        inst.AnimState:PlayAnimation("place" .. tostring(inst._post_id or 1))
        inst.AnimState:SetFrame(11)
        inst.AnimState:PushAnimation(idleanim, false)
    end
end

local function setpostid(inst, id)
    if inst._post_id == nil or (id ~= nil and inst._post_id ~= id) then
        inst._post_id = id or tostring(math.random(1, 3))
        inst.AnimState:PlayAnimation("idle" .. inst._post_id)
    end
end

local function place(inst)
    inst.SoundEmitter:PlaySound("monkeyisland/dock/post_place")
    inst.AnimState:PlayAnimation("place" .. tostring(inst._post_id or 1))
    inst.AnimState:PushAnimation("idle" .. tostring(inst._post_id or 1), false)
    inst:DoTaskInTime(0.1, UpdateBridgeStatus)
end

local function onsave(inst, data)
    data.post_id = inst._post_id
    data.is_bridge_built = inst.is_bridge_built
    data.required_boards = inst.required_boards
    data.required_logs = inst.required_logs
    data.tile_cx = inst.tile_cx
    data.tile_cz = inst.tile_cz
    data.bridge_spots = inst._bridge_spots
    data.original_tiles = inst.original_tiles
end

local function onload(inst, data)
    if data ~= nil then
        setpostid(inst, data.post_id)
        inst.is_bridge_built = data.is_bridge_built
        inst.required_boards = data.required_boards or 0
        inst.required_logs = data.required_logs or 0
        inst.tile_cx = data.tile_cx
        inst.tile_cz = data.tile_cz
        inst._bridge_spots = data.bridge_spots
        inst.original_tiles = data.original_tiles
    else
        setpostid(inst)
    end

    local TheWorld = rawget(GLOBAL, "TheWorld")
    local map = TheWorld and TheWorld.Map
    if (inst.tile_cx == nil or inst.tile_cz == nil) and map ~= nil then
        local x, _, z = inst.Transform:GetWorldPosition()
        local cx, _, cz = map:GetTileCenterPoint(x, 0, z)
        inst.tile_cx = cx
        inst.tile_cz = cz
    end

    if inst.is_bridge_built then
        inst:RemoveTag("constructionsite")
        inst:RemoveComponent("constructionsite")
    else
        inst:DoTaskInTime(0.5, UpdateBridgeStatus)
    end
end

local function getstatus(inst)
    if inst.is_bridge_built then
        return "BUILT"
    elseif inst.paired_post ~= nil then
        return "READY"
    end
    return "NEED_PAIR"
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()
    inst.entity:AddSoundEmitter()

    inst:SetDeploySmartRadius(DEPLOYSPACING_RADIUS[DEPLOYSPACING.LESS] / 2)

    inst.AnimState:SetBank("dock_woodposts")
    inst.AnimState:SetBuild("dock_woodposts")
    inst.AnimState:PlayAnimation("idle1")

    inst:AddTag("cc_brigdepost")

    inst._required_boards = net_smallbyte(inst.GUID, "cc_brigdepost._required_boards")
    inst._required_logs   = net_smallbyte(inst.GUID, "cc_brigdepost._required_logs")

    inst.entity:SetPristine()

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not (TheWorld and TheWorld.ismastersim) then
        return inst
    end

    inst.scrapbook_anim = "idle3"
    inst.is_bridge_built = false
    inst.required_boards = 0
    inst.required_logs = 0

    inst:AddComponent("inspectable")
    inst.components.inspectable.getstatus = getstatus

    inst:AddComponent("lootdropper")
    inst.components.lootdropper:SetLoot(loot)

    inst:AddComponent("workable")
    inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
    inst.components.workable:SetWorkLeft(3)
    inst.components.workable:SetOnFinishCallback(OnHammered)
    inst.components.workable:SetOnWorkCallback(OnHit)

    inst:AddComponent("constructionsite")
    inst.components.constructionsite:SetConstructionPrefab("construction_container")
    inst.components.constructionsite:SetOnConstructedFn(OnConstructed)
    inst.components.constructionsite:SetOnStartConstructionFn(OnStartConstruction)
    inst.components.constructionsite:Disable()

    local cs = inst.components.constructionsite
    local old_OnConstruct = cs.OnConstruct
    cs.OnConstruct = function(self, doer, items)
        ApplySelfPlans(inst)
        return old_OnConstruct(self, doer, items)
    end

    if not POPULATING then
        setpostid(inst)
    end

    inst:DoPeriodicTask(2.0, UpdateBridgeStatus)

    inst.place = place
    inst.UpdateBridgeStatus = UpdateBridgeStatus
    inst.CollapseBridge = CollapseBridge

    inst.OnSave = onsave
    inst.OnLoad = onload

    return inst
end

local function ondeploy(inst, pt, deployer)
    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not (TheWorld and TheWorld.Map) then return end
    local map = TheWorld.Map

    local cx, _, cz = map:GetTileCenterPoint(pt.x, 0, pt.z)

    local prop = SpawnPrefab("cc_brigdepost", inst.linked_skinname, inst.skin_id)
    if prop ~= nil then
        prop.Transform:SetPosition(cx, 0, cz)
        prop.tile_cx = cx
        prop.tile_cz = cz
        prop:place()
        inst:Remove()
    end
end

local function itemfn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)

    inst:AddTag("deploykititem")

    inst.AnimState:SetBank("dock_woodposts")
    inst.AnimState:SetBuild("dock_woodposts")
    inst.AnimState:PlayAnimation("item")

    MakeInventoryFloatable(inst, "med", 0.2, 0.75)

    inst.entity:SetPristine()

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not (TheWorld and TheWorld.ismastersim) then
        return inst
    end

    inst:AddComponent("inspectable")
    inst:AddComponent("inventoryitem")

    inst:AddComponent("deployable")
    inst.components.deployable.ondeploy = ondeploy
    inst.components.deployable:SetDeploySpacing(DEPLOYSPACING.LESS)
    inst.components.deployable:SetDeployMode(DEPLOYMODE.DEFAULT)

    inst:AddComponent("stackable")
    inst.components.stackable.maxsize = TUNING.STACK_SIZE_MEDITEM

    MakeSmallBurnable(inst, TUNING.MED_BURNTIME)
    MakeSmallPropagator(inst)

    return inst
end

local function placer_onupdatetransform(inst)
    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not (TheWorld and TheWorld.Map) then return end
    local map = TheWorld.Map

    local x, y, z = inst.Transform:GetWorldPosition()
    local cx, _, cz = map:GetTileCenterPoint(x, 0, z)

    inst.Transform:SetPosition(cx, 0, cz)

    local is_land = map:IsLandTileAtPoint(cx, 0, cz)
    local has_void_neighbor = false
    local offsets = { { 4, 0 }, { -4, 0 }, { 0, 4 }, { 0, -4 } }

    for _, off in ipairs(offsets) do
        local neighbor_tile = map:GetTileAtPoint(cx + off[1], 0, cz + off[2])
        if map:BridgeFilter_OceanAndVoid(neighbor_tile) then
            has_void_neighbor = true
            break
        end
    end

    if is_land and has_void_neighbor then
        inst.AnimState:SetAddColour(0.25, 0.75, 0.25, 0)
        inst.AnimState:SetMultColour(1, 1, 1, 1)
    else
        inst.AnimState:SetAddColour(0.75, 0.25, 0.25, 0)
        inst.AnimState:SetMultColour(1, 1, 1, 0.5)
    end
end

local function placer_postinit(inst)
    inst.components.placer.onupdatetransform = placer_onupdatetransform
end

return Prefab("cc_brigdepost", fn, assets, prefabs),
    Prefab("cc_brigdepost_item", itemfn, assets, prefabs),
    MakePlacer("cc_brigdepost_item_placer", "dock_woodposts", "dock_woodposts", "idle1", nil, nil, nil, nil, nil, nil, placer_postinit)