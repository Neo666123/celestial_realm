local _G = rawget(_G, "GLOBAL") or _G
local TheSim = rawget(_G, "TheSim")
local SpawnPrefab = rawget(_G, "SpawnPrefab")
local ACTIONS = rawget(_G, "ACTIONS")

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

-- 2. 传送门双向绑定与虫洞直达 Tiled 大厅
AddPrefabPostInit("world", function(inst)
    if not inst.ismastersim then return end

    inst:DoTaskInTime(3, function()
        local TheWorld = rawget(_G, "TheWorld")
        if not TheWorld then return end

        local existing_mainland = TheSim:FindFirstEntityWithTag("rift_mainland_wormhole")
        local existing_hall = TheSim:FindFirstEntityWithTag("rift_hall_wormhole")

        if existing_mainland and existing_hall then
            if existing_mainland.components.teleporter and existing_hall.components.teleporter then
                existing_mainland.components.teleporter:Target(existing_hall)
                existing_hall.components.teleporter:Target(existing_mainland)
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

        -- 获取 Tiled 圣殿大厅的锚点
        local hall_anchor = TheSim:FindFirstEntityWithTag("celestial_hall_anchor")

        if portal and hall_anchor then
            local px, _, pz = portal.Transform:GetWorldPosition()
            local hx, _, hz = hall_anchor.Transform:GetWorldPosition()

            local w_mainland = SpawnPrefab("wormhole")
            local w_hall = SpawnPrefab("wormhole")

            if w_mainland and w_hall then
                w_mainland:AddTag("rift_mainland_wormhole")
                w_hall:AddTag("rift_hall_wormhole")

                w_mainland.Transform:SetPosition(px + 4, 0, pz)
                w_hall.Transform:SetPosition(hx + 4, 0, hz)

                w_mainland.components.teleporter:Target(w_hall)
                w_hall.components.teleporter:Target(w_mainland)
            end
        end
    end)
end)