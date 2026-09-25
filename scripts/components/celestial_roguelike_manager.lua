local rawget = rawget
local ipairs = ipairs
local table = table
local math = math
local string = string

local GLOBAL = rawget(_G, "GLOBAL") or _G
local TILE_SCALE = rawget(GLOBAL, "TILE_SCALE") or 4
local SpawnPrefab = rawget(GLOBAL, "SpawnPrefab")
local defs = require("roguelike/celestial_roguelike_defs")
local DEFS = defs -- 兼容全文大小写混用的情况
local RoomComp = require("components/celestial_roguelike_room")

-- 3 槽位配置表（每个槽位拥有两套不同的地形变体，切房时动态重塑）
local SLOTS = {
    { id = "small",  variants = { "small_1", "small_2" },   off_x = 0,    off_z = 0,  door_z = 16 },
    { id = "medium", variants = { "medium_1", "medium_2" }, off_x = -130, off_z = 60, door_z = 24 },
    { id = "large",  variants = { "large_1", "large_2" },   off_x = -260, off_z = 0,  door_z = 24 },
}

local CelestialRoguelikeManager = Class(function(self, inst)
    self.inst = inst
    self.current_slot_idx = 1
    self.base_x = nil
    self.base_z = nil

    self.slots_data = {}
    self.doors = {}

    self.room_controller = RoomComp(self.inst)

    self.inst:ListenForEvent("ms_celestial_roguelike_door_activated", function(world, data)
        self:OnDoorActivated(data.door, data.doer)
    end, self.inst)

    self.inst:DoTaskInTime(0, function() self:InitVoidArchipelago() end)
end)

function CelestialRoguelikeManager:InitBaseAnchor()
    local TheWorld = rawget(GLOBAL, "TheWorld")
    local map = TheWorld.Map
    local topology = map.topology or (map.GetTopology and map:GetTopology())

    local celestial_island_x, celestial_island_z

    if topology and topology.nodes and topology.ids then
        for idx, id in ipairs(topology.ids) do
            if string.find(id, "Rift_Celestial") then
                local node = topology.nodes[idx]
                if node then
                    celestial_island_x = node.x
                    celestial_island_z = node.y
                    break
                end
            end
        end
    end

    if celestial_island_x and celestial_island_z then
        local dir_x = -celestial_island_x
        local dir_z = -celestial_island_z
        local len = math.sqrt(dir_x * dir_x + dir_z * dir_z)
        if len > 0 then
            self.base_x = celestial_island_x + (dir_x / len) * 100
            self.base_z = celestial_island_z + (dir_z / len) * 100
        else
            self.base_x = celestial_island_x - 100
            self.base_z = celestial_island_z - 100
        end
    else
        local w, h = map:GetWorldSize()
        self.base_x = (w * 0.5 - 40) * TILE_SCALE
        self.base_z = (h * 0.5 - 40) * TILE_SCALE
    end
    print(string.format("[CelestialRoguelike] Island Cluster anchored near Celestial Domain at (%.1f, %.1f)", self.base_x, self.base_z))
end

function CelestialRoguelikeManager:InitVoidArchipelago()
    self:InitBaseAnchor()

    for idx, slot in ipairs(SLOTS) do
        local sx = self.base_x + slot.off_x
        local sz = self.base_z + slot.off_z
        self.slots_data[idx] = {
            x = sx,
            z = sz,
            variants = slot.variants,
            cur_variant_idx = 1,
            door_z = slot.door_z,
        }

        local first_variant = slot.variants[1]
        if defs[first_variant] and defs[first_variant].TerraformRoomAtXZ then
            defs[first_variant].TerraformRoomAtXZ(self.inst, sx, sz)
        end

        local door = SpawnPrefab("celestial_roguelike_door")
        door.Transform:SetPosition(sx, 0, sz + slot.door_z)
        door.slot_index = idx
        table.insert(self.doors, door)
    end

    -- 初始化首发小岛内容
    local first_slot = self.slots_data[1]
    self.room_controller:SetAnchor(first_slot.x, first_slot.z)
    self.room_controller:LayoutNewRoom(first_slot.variants[1])
end

function CelestialRoguelikeManager:OnDoorActivated(door, doer)
    local cur_slot = self.slots_data[self.current_slot_idx]

    -- 1. 清理当前槽位的旧实体
    self.room_controller:SetAnchor(cur_slot.x, cur_slot.z)
    self.room_controller:UnloadRoom(false)

    -- 2. 推进至下一个槽位，并轮转该槽位的地形变体
    self.current_slot_idx = (self.current_slot_idx % #SLOTS) + 1
    local next_slot = self.slots_data[self.current_slot_idx]
    next_slot.cur_variant_idx = (next_slot.cur_variant_idx % #next_slot.variants) + 1
    local next_variant_id = next_slot.variants[next_slot.cur_variant_idx]

    -- 3. 施加新地形形态并分发生态资源
    self.room_controller:SetAnchor(next_slot.x, next_slot.z)
    self.room_controller:LayoutNewRoom(next_variant_id)

    if door and door:IsValid() and door.components.channelable then
        door.components.channelable:StopChanneling(true)
    end

    local fx = SpawnPrefab("vault_portal_fx")
    if fx and doer and doer:IsValid() then
        fx.Transform:SetPosition(doer.Transform:GetWorldPosition())
    end

    if doer and doer:IsValid() then
        if doer.Physics then
            doer.Physics:Teleport(next_slot.x, 0, next_slot.z)
        else
            doer.Transform:SetPosition(next_slot.x, 0, next_slot.z)
        end
        if doer.SnapCamera then
            doer:SnapCamera()
        end
    end
end

function CelestialRoguelikeManager:TeleportPlayerToArena(player)
    if not player then return end
    if not self.base_x or not self.base_z then self:InitBaseAnchor() end

    local slot1 = self.slots_data[1] or { x = self.base_x, z = self.base_z }
    if player.Physics then
        player.Physics:Teleport(slot1.x, 0, slot1.z)
    else
        player.Transform:SetPosition(slot1.x, 0, slot1.z)
    end
    if player.SnapCamera then player:SnapCamera() end
end

return CelestialRoguelikeManager