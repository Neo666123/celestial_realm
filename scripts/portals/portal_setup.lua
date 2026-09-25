local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G
local TheSim = rawget(GLOBAL, "TheSim")

AddPrefabPostInit("world", function(inst)
    if not inst.ismastersim then return end

    inst.overworld_inventories = {}
    inst.celestial_inventories = {}

    local old_OnSave = inst.OnSave
    inst.OnSave = function(self, data)
        if old_OnSave then old_OnSave(self, data) end
        data.overworld_inventories = self.overworld_inventories
        data.celestial_inventories = self.celestial_inventories
    end

    local old_OnLoad = inst.OnLoad
    inst.OnLoad = function(self, data)
        if old_OnLoad then old_OnLoad(self, data) end
        if data then
            if data.overworld_inventories then
                self.overworld_inventories = data.overworld_inventories
            end
            if data.celestial_inventories then
                self.celestial_inventories = data.celestial_inventories
            end
        end
    end

    inst:DoTaskInTime(1.0, function()
        local portal = TheSim:FindFirstEntityWithTag("multiplayer_portal")
            or TheSim:FindFirstEntityWithTag("multiplayer_portal_moonrock")
        if portal and portal:IsValid() then
            local px, py, pz = portal.Transform:GetWorldPosition()
            local target_x = px + 3.5
            local target_z = pz
            local existing = TheSim:FindEntities(target_x, py, target_z, 2, { "portal_entrance" })
            if #existing == 0 then
                local door = GLOBAL.SpawnPrefab("portal_entrance")
                if door then
                    door.Transform:SetPosition(target_x, py, target_z)
                end
            end
        end
    end)
end)

local function SetupPortal(portal)
    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not TheWorld or not TheWorld.ismastersim then return end

    portal:DoTaskInTime(0.5, function()
        local px, py, pz = portal.Transform:GetWorldPosition()
        local target_x = px + 3.5
        local target_z = pz
        local existing = GLOBAL.TheSim:FindEntities(target_x, py, target_z, 2, { "portal_entrance" })
        if #existing == 0 then
            local door = GLOBAL.SpawnPrefab("portal_entrance")
            if door then
                door.Transform:SetPosition(target_x, py, target_z)
            end
        end
    end)
end

AddPrefabPostInit("multiplayer_portal", SetupPortal)
AddPrefabPostInit("multiplayer_portal_moonrock", SetupPortal)