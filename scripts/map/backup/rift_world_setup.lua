local _G = rawget(_G, "GLOBAL") or _G
local TheSim = rawget(_G, "TheSim")
local SpawnPrefab = rawget(_G, "SpawnPrefab")
local ACTIONS = rawget(_G, "ACTIONS")
local PI2 = rawget(_G, "PI2") or (math.pi * 2)

-- 1. 动作交互文本
local STRINGS = rawget(_G, "STRINGS")
if STRINGS and STRINGS.ACTIONS and STRINGS.ACTIONS.JUMPIN then
    STRINGS.ACTIONS.JUMPIN.LUNAR_RIFT = "进入裂隙"
end

if ACTIONS and ACTIONS.JUMPIN then
    local old_action_str = ACTIONS.JUMPIN.strfn
    ACTIONS.JUMPIN.strfn = function(act)
        if act.target and (act.target.prefab == "lunarrift_portal" or act.target.prefab == "celestial_rift") then
            return "LUNAR_RIFT"
        end
        return old_action_str and old_action_str(act) or nil
    end
end

-- 2. 原版月亮裂隙双向绑定
AddPrefabPostInit("lunarrift_portal", function(inst)
    inst:AddTag("teleporter")
    local TheWorld = rawget(_G, "TheWorld")
    if TheWorld and not TheWorld.ismastersim then return end

    if not inst.components.teleporter then
        inst:AddComponent("teleporter")
        inst.components.teleporter.offset = 4
        inst.components.teleporter.saveenabled = false
    end

    inst:DoTaskInTime(1, function()
        local c_rift = TheSim:FindFirstEntityWithTag("celestial_rift_anchor")
        if c_rift and c_rift:IsValid() then
            c_rift:ReturnToScene()
            c_rift.components.teleporter:SetEnabled(true)
            inst.components.teleporter:SetEnabled(true)
            inst.components.teleporter:Target(c_rift)
            c_rift.components.teleporter:Target(inst)
        end
    end)
end)

-- 3. 强制在空洞正中心生成完整冰岛
AddComponentPostInit("sharkboimanager", function(self)
    local old_TryToPlaceOceanArena = self.TryToPlaceOceanArena
    self.TryToPlaceOceanArena = function(sbm_self)
        local TheWorld = rawget(_G, "TheWorld")
        if TheWorld and TheWorld.topology and TheWorld.topology.celestial_crater_center then
            local target = TheWorld.topology.celestial_crater_center
            if sbm_self.arena == nil then
                if sbm_self:PlaceOceanArenaAtPosition(target.x, 0, target.z) then
                    return true
                end
            end
        end
        return old_TryToPlaceOceanArena(sbm_self)
    end
end)

-- 4. 外部宽环礁石群落与大门双向虫洞
AddPrefabPostInit("world", function(inst)
    if not inst.ismastersim then return end

    inst:DoTaskInTime(3, function()
        local TheWorld = rawget(_G, "TheWorld")
        if not TheWorld then return end
        local _map = TheWorld.Map

        -- A. 外圈大范围礁石与海洋生态播散
        if TheWorld.topology and TheWorld.topology.celestial_crater_center and not TheWorld:HasTag("rift_crater_ecology_spawned") then
            TheWorld:AddTag("rift_crater_ecology_spawned")
            local center = TheWorld.topology.celestial_crater_center

            local function SpawnClump(clump_x, clump_z, prefabs_pool, count, spread_radius)
                for _ = 1, count do
                    local offset_angle = math.random() * PI2
                    local offset_dist = math.random() * spread_radius
                    local px = clump_x + math.cos(offset_angle) * offset_dist
                    local pz = clump_z + math.sin(offset_angle) * offset_dist

                    if _map:IsOceanAtPoint(px, 0, pz, false) then
                        local nearby = TheSim:FindEntities(px, 0, pz, 3.0)
                        if #nearby == 0 then
                            local chosen_prefab = prefabs_pool[math.random(#prefabs_pool)]
                            local ent = SpawnPrefab(chosen_prefab)
                            if ent then
                                ent.Transform:SetPosition(px, 0, pz)
                            end
                        end
                    end
                end
            end

            local function GetOuterRingPoint(min_dist, max_dist)
                for _ = 1, 35 do
                    local angle = math.random() * PI2
                    local dist = math.random(min_dist, max_dist)
                    local rx = center.x + math.cos(angle) * dist
                    local rz = center.z + math.sin(angle) * dist

                    if _map:IsOceanAtPoint(rx, 0, rz, false) then
                        return rx, rz
                    end
                end
                return nil, nil
            end

            local wx, wz = GetOuterRingPoint(55, 75)
            if wx and wz then
                local tree = SpawnPrefab("watertree_pillar")
                if tree then
                    tree.Transform:SetPosition(wx, 0, wz)
                end
            end

            local ROCK_PREFABS = {
                "seastack", "seastack", "seastack",
                "oceanrock", "oceanrock", "oceanrock_sharp",
            }
            for _ = 1, 14 do
                local cx, cz = GetOuterRingPoint(42, 85)
                if cx and cz then
                    SpawnClump(cx, cz, ROCK_PREFABS, math.random(3, 5), 6.0)
                end
            end

            local PLANT_PREFABS = { "waterplant" }
            for _ = 1, 4 do
                local cx, cz = GetOuterRingPoint(45, 75)
                if cx and cz then
                    SpawnClump(cx, cz, PLANT_PREFABS, math.random(2, 3), 4.5)
                end
            end

            local KELP_PREFABS = { "bullkelp_plant" }
            for _ = 1, 3 do
                local cx, cz = GetOuterRingPoint(45, 80)
                if cx and cz then
                    SpawnClump(cx, cz, KELP_PREFABS, math.random(3, 4), 5.0)
                end
            end
        end

        -- B. 绚丽之门双向虫洞连接
        local existing_mainland = TheSim:FindFirstEntityWithTag("rift_mainland_wormhole")
        local existing_void = TheSim:FindFirstEntityWithTag("rift_void_wormhole")

        if existing_mainland and existing_void then
            if existing_mainland.components.teleporter and existing_void.components.teleporter then
                existing_mainland.components.teleporter:Target(existing_void)
                existing_void.components.teleporter:Target(existing_mainland)
            end
            return
        end

        local portal = TheSim:FindFirstEntityWithTag("multiplayer_portal")
        if not portal then
            local Ents = rawget(_G, "Ents") or {}
            for _, ent in pairs(Ents) do
                if (ent.prefab == "multiplayer_portal" or ent.prefab == "spawnpoint_master") and ent:IsValid() then
                    portal = ent
                    break
                end
            end
        end

        local island_anchor = TheSim:FindFirstEntityWithTag("celestial_rift_anchor")
        if not island_anchor then
            local Ents = rawget(_G, "Ents") or {}
            for _, ent in pairs(Ents) do
                if ent:IsValid() and (ent.prefab == "celestial_rift" or ent.prefab == "moon_altar_rock_seed" or ent.prefab == "archive_moon_statue") then
                    local ex, _, _ = ent.Transform:GetWorldPosition()
                    if ex > 300 then
                        island_anchor = ent
                        if ent.prefab ~= "celestial_rift" then
                            local cr = SpawnPrefab("celestial_rift")
                            if cr then
                                cr.Transform:SetPosition(ent.Transform:GetWorldPosition())
                                island_anchor = cr
                            end
                        end
                        break
                    end
                end
            end
        end

        if portal and island_anchor then
            local px, _, pz = portal.Transform:GetWorldPosition()
            local ix, _, iz = island_anchor.Transform:GetWorldPosition()

            local w_mainland = SpawnPrefab("wormhole")
            local w_void = SpawnPrefab("wormhole")

            if w_mainland and w_void then
                w_mainland:AddTag("rift_mainland_wormhole")
                w_void:AddTag("rift_void_wormhole")

                w_mainland.Transform:SetPosition(px + 4, 0, pz)
                w_void.Transform:SetPosition(ix + 4, 0, iz)

                w_mainland.components.teleporter:Target(w_void)
                w_void.components.teleporter:Target(w_mainland)
            end
        end
    end)
end)