local rawget = rawget
local ipairs = ipairs
local pairs = pairs
local table = table
local math = math
local string = string

local GLOBAL = rawget(_G, "GLOBAL") or _G
local Class = rawget(GLOBAL, "Class") or Class
local TILE_SCALE = rawget(GLOBAL, "TILE_SCALE") or 4
local SpawnPrefab = rawget(GLOBAL, "SpawnPrefab")
local WORLD_TILES = rawget(GLOBAL, "WORLD_TILES")
local defs = require("roguelike/celestial_roguelike_defs")
local DEFS = defs

local SAVE_RADIUS = 35
local SAVE_NO_TAGS = { "playerghost", "INLIMBO" }
local SAVE_CONTAINER_TAGS = { "_container" }

-- 3 槽位配置表（每个槽位拥有两套不同的地形变体，切房时动态重塑）
local SLOTS = {
    { id = "small",  variants = { "small_1", "small_2" },   off_x = 0,    off_z = 0,  door_z = 16 },
    { id = "medium", variants = { "medium_1", "medium_2" }, off_x = -130, off_z = 60, door_z = 24 },
    { id = "large",  variants = { "large_1", "large_2" },   off_x = -260, off_z = 0,  door_z = 24 },
}

local CelestialRoguelikeRoom = Class(function(self, inst)
    self.inst = inst
    self.roomid = nil
    self.anchor_x = 0
    self.anchor_z = 0
end)

function CelestialRoguelikeRoom:SetAnchor(x, z)
    self.anchor_x = x
    self.anchor_z = z
end

function CelestialRoguelikeRoom:GetCurrentRoomId()
    return self.roomid
end

function CelestialRoguelikeRoom:LayoutNewRoom(id)
    local def = defs[id]
    if def == nil then return end

    self.roomid = id
    local x, z = self.anchor_x, self.anchor_z

    -- 重新画笔涂写地皮（重塑岛屿地形）
    if def.TerraformRoomAtXZ then
        def.TerraformRoomAtXZ(self.inst, x, z)
    end

    -- 重新分发实体与资源
    if def.LayoutNewRoomAtXZ then
        rawset(GLOBAL, "POPULATING", true)
        def.LayoutNewRoomAtXZ(self.inst, x, z)
        rawset(GLOBAL, "POPULATING", false)
    end
end

local function _inroom(ent, map, tile_x, tile_y)
    local x1, _, z1 = ent.Transform:GetWorldPosition()
    local tx, ty = map:GetTileCoordsAtPoint(x1, 0, z1)
    if math.abs(tx - tile_x) <= 24 and math.abs(ty - tile_y) <= 24 then
        return true
    end
    local tile = map:GetTile(tx, ty)
    if WORLD_TILES then
        return tile == WORLD_TILES.FUNGUSMOON
            or tile == WORLD_TILES.METEOR
            or tile == WORLD_TILES.PEBBLEBEACH
            or (tile == WORLD_TILES.IMPASSABLE and map:IsVisualGroundAtPoint(x1, 0, z1))
    end
    return false
end

local _SKIP = 1
local _SAVE = 2
local _KEEP = 3

local function _getunloadaction(ent, map, tile_x, tile_y)
    if not ent:IsValid() or ent.entity:GetParent() or ent:HasTag("staysthroughvirtualrooms") then
        return _SKIP
    end

    local owner = ent
    while true do
        local nextowner =
            (owner.components.spell and owner.components.spell.target) or
            (owner.components.formationleader and owner.components.formationleader.target) or
            (owner.components.follower and owner.components.follower:GetLeader()) or
            (owner.components.inventoryitem and owner.components.inventoryitem.owner)

        if nextowner and nextowner:IsValid() then
            owner = nextowner
        else
            break
        end
    end

    if owner ~= ent and owner.entity:GetParent() or not _inroom(owner, map, tile_x, tile_y) then
        return _SKIP
    elseif owner.isplayer or (
            owner:HasAnyTag("irreplaceable", "followsthroughvirtualrooms") or
            (owner.components.migrationpetowner and owner.components.migrationpetowner:GetPet())
        ) and not owner:HasAnyTag("forcedtosavethroughvirtualrooms") then
        return _KEEP
    end
    return _SAVE
end

function CelestialRoguelikeRoom:UnloadRoom(save)
    local def = defs[self.roomid]
    if def == nil then return end

    self.roomid = nil
    local x, z = self.anchor_x, self.anchor_z
    local TheWorld = rawget(GLOBAL, "TheWorld")
    local TheSim = rawget(GLOBAL, "TheSim")
    local map = TheWorld.Map
    local tile_x, tile_y = map:GetTileCoordsAtPoint(x, 0, z)

    local recbyguid, refs, toremove
    if save then
        save = { ents = {} }
        recbyguid = {}
        refs = {}
        toremove = {}
    end

    for _, v in ipairs(TheSim:FindEntities(x, 0, z, SAVE_RADIUS, nil, SAVE_NO_TAGS, SAVE_CONTAINER_TAGS)) do
        if _getunloadaction(v, map, tile_x, tile_y) == _SAVE then
            local container = v.components.inventory or v.components.container
            if container then
                container:DropEverythingWithTag("irreplaceable")
            end
        end
    end

    rawset(GLOBAL, "POPULATING", true)

    local ents = TheSim:FindEntities(x, 0, z, SAVE_RADIUS, nil, SAVE_NO_TAGS)
    local keepidx = 0
    for i = 1, #ents do
        local v = ents[i]
        ents[i] = nil

        local unloadaction = _getunloadaction(v, map, tile_x, tile_y)
        if unloadaction == _SAVE then
            if save then
                table.insert(toremove, v)
                if v.persists and v.prefab then
                    local record, new_refs = v:GetSaveRecord()
                    record.prefab = nil

                    if new_refs then
                        refs[v.GUID] = v
                        for _, guid in pairs(new_refs) do
                            refs[guid] = v
                        end
                    end

                    recbyguid[v.GUID] = record
                    if save.ents[v.prefab] == nil then
                        save.ents[v.prefab] = {}
                    end
                    table.insert(save.ents[v.prefab], record)
                end
            else
                v:Remove()
            end
        elseif unloadaction == _KEEP then
            keepidx = keepidx + 1
            ents[keepidx] = v
        end
    end

    if refs then
        for guid, v in pairs(refs) do
            local record = recbyguid[guid]
            if record then
                record.id = guid
            end
        end
    end

    if toremove then
        for _, v in ipairs(toremove) do
            v:Remove()
        end
    end

    rawset(GLOBAL, "POPULATING", false)

    return save, ents
end

return CelestialRoguelikeRoom