local GLOBAL = rawget(_G, "GLOBAL") or _G
local TheSim = rawget(GLOBAL, "TheSim")
local TheInput = rawget(GLOBAL, "TheInput")
local FRAMES = rawget(GLOBAL, "FRAMES") or (1 / 30)
local TimeEvent = rawget(GLOBAL, "TimeEvent")
local EventHandler = rawget(GLOBAL, "EventHandler")
local State = rawget(GLOBAL, "State")

local MOUSEBUTTON_LEFT  = rawget(GLOBAL, "MOUSEBUTTON_LEFT") or 1000
local MOUSEBUTTON_RIGHT = rawget(GLOBAL, "MOUSEBUTTON_RIGHT") or 1001
local CONTROL_PRIMARY   = rawget(GLOBAL, "CONTROL_PRIMARY") or 0
local CONTROL_SECONDARY = rawget(GLOBAL, "CONTROL_SECONDARY") or 1
local CONTROL_ATTACK    = rawget(GLOBAL, "CONTROL_ATTACK") or 2
local CONTROL_ACTION    = rawget(GLOBAL, "CONTROL_ACTION") or 14

local KEY_SHIFT = rawget(GLOBAL, "KEY_SHIFT") or 400
local KEY_SPACE = rawget(GLOBAL, "KEY_SPACE") or 32
local KEY_W     = rawget(GLOBAL, "KEY_W") or 119
local KEY_A     = rawget(GLOBAL, "KEY_A") or 97
local KEY_S     = rawget(GLOBAL, "KEY_S") or 115
local KEY_D     = rawget(GLOBAL, "KEY_D") or 100
local KEY_UP    = rawget(GLOBAL, "KEY_UP") or 273
local KEY_DOWN  = rawget(GLOBAL, "KEY_DOWN") or 274
local KEY_LEFT  = rawget(GLOBAL, "KEY_LEFT") or 276
local KEY_RIGHT = rawget(GLOBAL, "KEY_RIGHT") or 275
local KEY_Z     = rawget(GLOBAL, "KEY_Z") or 122

local CAMERASHAKE = rawget(GLOBAL, "CAMERASHAKE")
local EQUIPSLOTS  = rawget(GLOBAL, "EQUIPSLOTS") or { HANDS = "hands" }
local GetTime     = rawget(GLOBAL, "GetTime")
local PI          = rawget(GLOBAL, "PI") or math.pi

-- ==========================================================
-- 【核心战斗参数配置】
-- ==========================================================
local DASH_CD              = 1.5
local DASH_DMG_MULT        = 0.5
local HEAVY_DMG_MULT       = 5.0

local ATTACK_RANGE_TILES   = 0.75
local HIT_DISTANCE         = ATTACK_RANGE_TILES * 4
local HIT_SIDE_HALF_WIDTH  = 1.2

local HEAVY_RANGE_TILES    = 1.5
local HEAVY_HIT_DISTANCE   = HEAVY_RANGE_TILES * 4
local HEAVY_SIDE_HALF_WIDTH= 2.5
local HEAVY_KNOCKBACK_INIT = 16.0
local HEAVY_KNOCKBACK_FRIC = 0.75

local PARRY_ACTIVE_FRAMES  = 12
local PARRY_ANGLE_TOLERANCE= 135
local PARRY_INVINC_TIME    = 0.5

local INTERRUPT_FRAME      = 9

local SLASH_SPEED_INIT     = 13.5
local SLASH_FRICTION       = 0.70

local DASH_SPEED_INIT      = 32.4
local DASH_FRICTION        = 0.70

local BOUNCE_SPEED_INIT    = 46.0
local BOUNCE_FRICTION      = 0.72

local HITSTOP_FRAMES_FIRST = 2
local HITSTOP_FRAMES_COMBO = 4
local COMBO_WINDOW         = 0.5
local SCREEN_ATTACK_RADIUS = 650

local FLASH_WHITE_FRAMES   = 2
local FLASH_FADE_FRAMES    = 3

local CHAIN_IGNORE_LIST = {
    ["beehive"] = true, ["wasphive"] = true,
    ["terrorbeak"] = true, ["crawlinghorror"] = true,
}

-- ==========================================================
-- 核心验证与空间几何工具
-- ==========================================================
local function IsValidGlasscutter(player)
    if not (player and player:IsValid()) then return false end
    local hand_item = nil
    if player.replica and player.replica.inventory then
        hand_item = player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    elseif player.components and player.components.inventory then
        hand_item = player.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    end
    if not hand_item then return false end
    return hand_item.prefab == "glasscutter"
        or hand_item.prefab == ""
        or hand_item.prefab == "champion_glasscutter_charged"
        or hand_item:HasTag("glasscutter")
end

local function TableContains(tbl, item)
    if not tbl then return false end
    for _, v in pairs(tbl) do
        if v == item then return true end
    end
    return false
end

local function GetAngleDifference(angle1, angle2)
    return math.abs(math.deg(math.atan2(math.sin(math.rad(angle1 - angle2)), math.cos(math.rad(angle1 - angle2)))))
end

local function GetInputTargetPos(player)
    local px, py, pz = player.Transform:GetWorldPosition()
    local raw_w = TheInput:IsKeyDown(KEY_W) or TheInput:IsKeyDown(KEY_UP)
    local raw_s = TheInput:IsKeyDown(KEY_S) or TheInput:IsKeyDown(KEY_DOWN)
    local raw_a = TheInput:IsKeyDown(KEY_A) or TheInput:IsKeyDown(KEY_LEFT)
    local raw_d = TheInput:IsKeyDown(KEY_D) or TheInput:IsKeyDown(KEY_RIGHT)

    local is_w, is_s, is_a, is_d = raw_a, raw_d, raw_s, raw_w
    local u, v = 0, 0
    if is_d then u = u + 1 end
    if is_a then u = u - 1 end
    if is_w then v = v + 1 end
    if is_s then v = v - 1 end

    if u == 0 and v == 0 then
        local rot_rad = player.Transform:GetRotation() * (PI / 180)
        return px + math.cos(rot_rad) * 10, pz - math.sin(rot_rad) * 10
    end

    local TheCamera = rawget(GLOBAL, "TheCamera")
    local heading_rad = ((TheCamera and TheCamera:GetHeading()) or 0) * (PI / 180)
    local cos_h, sin_h = math.cos(heading_rad), math.sin(heading_rad)

    return px + (-u * cos_h + v * sin_h) * 10, pz + (-u * sin_h - v * cos_h) * 10
end

local function GetMouseTargetPos(player)
    if TheInput and TheInput.GetWorldPosition then
        local pt = TheInput:GetWorldPosition()
        if pt and pt.x and pt.z then
            return pt.x, pt.z
        end
    end
    return GetInputTargetPos(player)
end

local function FlashEntityWhite(ent)
    if not (ent and ent:IsValid() and ent.AnimState) then return end
    if ent._white_flash_task then
        ent._white_flash_task:Cancel()
        ent._white_flash_task = nil
    end

    ent.AnimState:SetAddColour(1, 1, 1, 0)
    local current_step = 0
    ent._white_flash_task = ent:DoPeriodicTask(FRAMES, function(e)
        if not (e and e:IsValid() and e.AnimState) then
            if e and e._white_flash_task then
                e._white_flash_task:Cancel()
                e._white_flash_task = nil
            end
            return
        end
        current_step = current_step + 1
        if current_step <= FLASH_WHITE_FRAMES then
            e.AnimState:SetAddColour(1, 1, 1, 0)
        elseif current_step <= (FLASH_WHITE_FRAMES + FLASH_FADE_FRAMES) then
            local val = math.max(0, 1 - (current_step - FLASH_WHITE_FRAMES) / FLASH_FADE_FRAMES)
            e.AnimState:SetAddColour(val, val, val, 0)
        else
            e.AnimState:SetAddColour(0, 0, 0, 0)
            if e._white_flash_task then
                e._white_flash_task:Cancel()
                e._white_flash_task = nil
            end
        end
    end)
end

local function DoForwardStep(inst, is_dash)
    if inst._step_task then inst._step_task:Cancel() inst._step_task = nil end
    local speed = is_dash and DASH_SPEED_INIT or SLASH_SPEED_INIT
    local friction = is_dash and DASH_FRICTION or SLASH_FRICTION
    local frames_left = 5

    inst._step_task = inst:DoPeriodicTask(FRAMES, function(p)
        if not (p and p:IsValid()) or frames_left <= 0 then
            if p and p._step_task then p._step_task:Cancel() p._step_task = nil end
            if p.Physics then p.Physics:ClearMotorVelOverride() p.Physics:Stop() end
            return
        end
        if p.Physics then p.Physics:SetMotorVelOverride(speed, 0, 0) end
        speed = speed * friction
        frames_left = frames_left - 1
    end)
end

local function ApplyElectrocuteEffects(target, damage, doer, weapon)
    if not (target and target:IsValid()) then return end
    local SpawnElectricHitSparks = rawget(GLOBAL, "SpawnElectricHitSparks")
    if SpawnElectricHitSparks then SpawnElectricHitSparks(doer, target, true) end

    if not target:HasTag("electric_immune") then
        target:PushEvent("electrocute")
        if target.components.locomotor then
            target.components.locomotor:SetExternalSpeedMultiplier(target, "cc_paralyze", 0)
            target:DoTaskInTime(1.5, function(t)
                if t:IsValid() and t.components.locomotor then
                    t.components.locomotor:RemoveExternalSpeedMultiplier(t, "cc_paralyze")
                end
            end)
        end
    end
    if damage > 0 and target.components.combat and target.components.health and not target.components.health:IsDead() then
        target.components.combat:GetAttacked(doer, damage, weapon)
    end
end

local function TriggerChainLightningLeaps(doer, weapon, first_target)
    local electrocuted = { first_target }
    doer:DoTaskInTime(0.4, function()
        if not first_target:IsValid() then return end
        local x, y, z = first_target.Transform:GetWorldPosition()
        local ents = TheSim:FindEntities(x, y, z, 3.0, {"_combat", "_health"}, {"player", "INLIMBO", "FX", "NOCLICK", "DECOR", "wall"})
        for _, ent in ipairs(ents) do
            if ent:IsValid() and not TableContains(electrocuted, ent) and not CHAIN_IGNORE_LIST[ent.prefab] then
                ApplyElectrocuteEffects(ent, 68, doer, weapon)
                table.insert(electrocuted, ent)
                doer:DoTaskInTime(0.4, function()
                    if not ent:IsValid() then return end
                    local x2, y2, z2 = ent.Transform:GetWorldPosition()
                    local ents2 = TheSim:FindEntities(x2, y2, z2, 3.0, {"_combat", "_health"}, {"player", "INLIMBO", "FX", "NOCLICK", "DECOR", "wall"})
                    for _, ent2 in ipairs(ents2) do
                        if ent2:IsValid() and not TableContains(electrocuted, ent2) and not CHAIN_IGNORE_LIST[ent2.prefab] then
                            ApplyElectrocuteEffects(ent2, 42.5, doer, weapon)
                            break
                        end
                    end
                end)
                break
            end
        end
    end)
end

local function DoEntityKnockback(target, attacker, knockback_speed)
    if not (target and target:IsValid() and attacker and attacker:IsValid()) then return end

    local px, py, pz = attacker.Transform:GetWorldPosition()
    local tx, ty, tz = target.Transform:GetWorldPosition()
    local dx, dz = tx - px, tz - pz
    local len = math.sqrt(dx * dx + dz * dz)

    if len > 0.001 then
        dx, dz = dx / len, dz / len
    else
        local rot = attacker.Transform:GetRotation() * (PI / 180)
        dx, dz = math.cos(rot), -math.sin(rot)
    end

    local cur_speed = knockback_speed
    if target:HasTag("epic") or (target.components.health and target.components.health.maxhealth > 1500) then
        cur_speed = cur_speed * 0.3
    end

    if target._cc_knockback_task then
        target._cc_knockback_task:Cancel()
        target._cc_knockback_task = nil
    end

    local TheWorld = rawget(GLOBAL, "TheWorld")
    local Vector3 = rawget(GLOBAL, "Vector3")

    target._cc_knockback_task = target:DoPeriodicTask(FRAMES, function(ent)
        if not (ent and ent:IsValid()) then
            if ent and ent._cc_knockback_task then
                ent._cc_knockback_task:Cancel()
                ent._cc_knockback_task = nil
            end
            return
        end

        local x, y, z = ent.Transform:GetWorldPosition()
        local nx = x + dx * cur_speed * FRAMES
        local nz = z + dz * cur_speed * FRAMES

        if TheWorld and TheWorld.Map and TheWorld.Map:IsPassableAtPoint(nx, 0, nz)
           and Vector3 and not (TheWorld.Map.IsPointNearHole and TheWorld.Map:IsPointNearHole(Vector3(nx, 0, nz))) then
            ent.Transform:SetPosition(nx, y, nz)
        else
            cur_speed = 0
        end

        cur_speed = cur_speed * HEAVY_KNOCKBACK_FRIC

        if cur_speed < 0.2 then
            if ent._cc_knockback_task then
                ent._cc_knockback_task:Cancel()
                ent._cc_knockback_task = nil
            end
        end
    end)
end

local function DoPlayerBounceRecoil(player)
    if not (player and player:IsValid()) then return end
    if player._step_task then player._step_task:Cancel() player._step_task = nil end
    if player._bounce_task then player._bounce_task:Cancel() player._bounce_task = nil end

    local speed = BOUNCE_SPEED_INIT
    player._bounce_task = player:DoPeriodicTask(FRAMES, function(p)
        if not (p and p:IsValid()) or speed < 0.8 then
            if p and p._bounce_task then p._bounce_task:Cancel() p._bounce_task = nil end
            if p.Physics then p.Physics:ClearMotorVelOverride() p.Physics:Stop() end
            return
        end
        if p.Physics then p.Physics:SetMotorVelOverride(-speed, 0, 0) end
        speed = speed * BOUNCE_FRICTION
    end)
end

local function DoBoxHitCheck(inst, damage_mult, freeze_frames, custom_dist, custom_half_width, knockback_speed, is_client)
    local dist = custom_dist or HIT_DISTANCE
    local half_w = custom_half_width or HIT_SIDE_HALF_WIDTH

    local px, py, pz = inst.Transform:GetWorldPosition()
    local rot_rad = inst.Transform:GetRotation() * (PI / 180)
    local cos_theta, sin_theta = math.cos(rot_rad), math.sin(rot_rad)
    local hit_targets = {}

    -- 1. 实体生物战斗检测
    local ents = TheSim:FindEntities(px, py, pz, dist + 3.0, { "_combat" }, { "player", "companion", "INLIMBO" })
    for _, ent in ipairs(ents) do
        local health = ent.components.health or (ent.replica and ent.replica.health)
        if ent:IsValid() and health and not (health.IsDead and health:IsDead()) then
            local tx, _, tz = ent.Transform:GetWorldPosition()
            local dx, dz = tx - px, tz - pz
            local forward_dist = dx * cos_theta - dz * sin_theta
            local side_dist = math.abs(dx * sin_theta + dz * cos_theta)
            local target_radius = (ent.GetPhysicsRadius and ent:GetPhysicsRadius(0)) or 0.5

            if (forward_dist - target_radius) <= dist and forward_dist >= -0.5
               and (side_dist - target_radius) <= half_w then

                if not is_client then
                    if inst.components.combat then
                        inst.components.combat.ignorehitrange = true
                        inst.components.combat:DoAttack(ent, nil, nil, nil, damage_mult)
                        inst.components.combat.ignorehitrange = false
                    end
                    if knockback_speed and knockback_speed > 0 then
                        DoEntityKnockback(ent, inst, knockback_speed)
                    end
                end

                FlashEntityWhite(ent)
                table.insert(hit_targets, ent)
            end
        end
    end

    -- 2. 通用可斩击物体检测 (统一支持 "slashable" 与原版 "cuttable_grass")
    local object_hit = false
    local is_grass_hit = false
    local cut_count = 0
    local slashables = TheSim:FindEntities(px, py, pz, dist + 2.0, nil, { "INLIMBO", "FX" }, { "slashable", "cuttable_grass" })

    for _, obj in ipairs(slashables) do
        if obj:IsValid() then
            local ox, _, oz = obj.Transform:GetWorldPosition()
            local dx, dz = ox - px, oz - pz
            local forward_dist = dx * cos_theta - dz * sin_theta
            local side_dist = math.abs(dx * sin_theta + dz * cos_theta)

            if forward_dist <= dist and forward_dist >= -0.5 and side_dist <= half_w then
                object_hit = true
                local is_grass = obj:HasTag("cuttable_grass")
                if is_grass then
                    is_grass_hit = true
                end

                if not is_client and obj.OnHitBySlash then
                    local is_destroyed = obj:OnHitBySlash(inst, damage_mult)
                    if is_grass and is_destroyed then
                        cut_count = cut_count + 1
                    end
                end
            end
        end
    end

    -- 3. 掉落物直塞背包 (仅对草生效)
    if cut_count > 0 and not is_client and inst.components.inventory then
        for _ = 1, cut_count do
            if math.random() <= 0.40 then
                local loot = SpawnPrefab("cutgrass")
                if loot then
                    inst.components.inventory:GiveItem(loot)
                end
            end
        end
    end

    -- 4. 受击反馈 (顿帧卡肉、音效、理智回复)
    if #hit_targets > 0 or object_hit then
        if not is_client and damage_mult == 1.0 and inst.components.sanity and #hit_targets > 0 then
            inst.components.sanity:DoDelta(8)
        end

        if inst.SoundEmitter then
            if damage_mult and damage_mult >= HEAVY_DMG_MULT then
                inst.SoundEmitter:PlaySound("dontstarve/sanity/sanity_sponge_use")
            else
                inst.SoundEmitter:PlaySound("rifts/lunarthrall/attack", nil, 0.4)
            end
            if is_grass_hit then
                inst.SoundEmitter:PlaySound("dontstarve/wilson/pickup_reeds")
            end
        end

        inst.AnimState:Pause()
        inst.sg.statemem.hitstop_active = true
        inst.sg:SetTimeout((26 + freeze_frames) * FRAMES)

        inst:DoTaskInTime(freeze_frames * FRAMES, function(p)
            if p and p:IsValid() and p.sg and p.sg:HasStateTag("attack") then
                p.AnimState:Resume()
                local remain_frames = math.max(1, INTERRUPT_FRAME - 5)
                p:DoTaskInTime(remain_frames * FRAMES, function(pi)
                    if pi and pi:IsValid() and pi.sg then
                        pi.sg:RemoveStateTag("busy")
                        pi.sg:AddStateTag("can_combo")
                    end
                end)
            end
        end)
    end
    return (#hit_targets > 0) or object_hit
end

local function SetupAttackAnim(inst, data, is_dash, anim_name)
    data = data or {}
    anim_name = anim_name or "small_atk"

    if inst.components.locomotor then inst.components.locomotor:Stop() end
    if data.tx and data.tz then inst:ForceFacePoint(data.tx, 0, data.tz) end

    if inst.SoundEmitter then
        inst.SoundEmitter:PlaySound("dontstarve/wilson/attack_weapon")
    end

    inst.AnimState:AddOverrideBuild("new_atk")
    inst.AnimState:PlayAnimation(anim_name)
    inst.AnimState:SetSymbolLightOverride("test", 1)

    DoForwardStep(inst, is_dash)
    inst.sg:SetTimeout(26 * FRAMES)
end

local function CleanupAttackState(inst, is_client)
    if inst._step_task then inst._step_task:Cancel() inst._step_task = nil end
    if inst.Physics then inst.Physics:ClearMotorVelOverride() inst.Physics:Stop() end

    if not is_client and inst.components.combat then
        inst.components.combat.ignorehitrange = false
        if inst.sg.statemem.old_GetAttacked then
            inst.components.combat.GetAttacked = inst.sg.statemem.old_GetAttacked
            inst.sg.statemem.old_GetAttacked = nil
        end
    end

    inst.AnimState:Resume()
    inst.AnimState:ClearOverrideBuild("new_atk")
    inst.AnimState:SetSymbolLightOverride("test", 0)
end

local function GetAttackEvents()
    return {
        EventHandler("locomote", function(inst)
            if not inst.sg:HasStateTag("busy") then
                local loco = inst.components.locomotor
                if loco and (loco:WantsToMoveForward() or loco:WantsToRun()) then
                    inst.sg:GoToState(loco:WantsToRun() and "run_start" or "walk_start")
                end
            end
        end),
        EventHandler("animover", function(inst)
            if inst.AnimState:AnimDone() then inst.sg:GoToState("idle") end
        end),
    }
end

-- ==========================================================
-- 状态机注册 (Wilson & Wilson_Client)
-- ==========================================================
local function RegisterCombatStates(sg_name, is_client)
    AddStategraphPostInit(sg_name, function(sg)

        -- 1. 普通斩击 (装配 small_atk)
        sg.states["custom_slash"] = State({
            name = "custom_slash",
            tags = { "attack", "busy", "notalking" },

            onenter = function(inst, data)
                local cur_time = (GetTime and GetTime()) or 0
                inst.sg.statemem.is_combo = (cur_time - (inst._last_slash_time or 0)) <= COMBO_WINDOW
                inst._last_slash_time = cur_time
                SetupAttackAnim(inst, data, false, "small_atk")
            end,

            timeline = {
                TimeEvent(5 * FRAMES, function(inst)
                    local freeze = inst.sg.statemem.is_combo and HITSTOP_FRAMES_COMBO or HITSTOP_FRAMES_FIRST
                    DoBoxHitCheck(inst, 1.0, freeze, nil, nil, nil, is_client)
                end),
                TimeEvent(INTERRUPT_FRAME * FRAMES, function(inst)
                    if not inst.sg.statemem.hitstop_active then
                        inst.sg:RemoveStateTag("busy")
                        inst.sg:AddStateTag("can_combo")
                    end
                end),
            },

            events = GetAttackEvents(),
            onexit = function(inst) CleanupAttackState(inst, is_client) end,
            ontimeout = function(inst) inst.sg:GoToState("idle") end,
        })

        -- 2. 空格冲刺 (装配 small_atk)
        local function ExecuteParryClash(inst, target_ent)
            if inst.sg.statemem.clash_done then return end
            inst.sg.statemem.clash_done = true
            inst.sg.statemem.parry_active = false

            inst:ShakeCamera(CAMERASHAKE.SIDE, 0.1, 0.03, 0.3)
            if inst.SoundEmitter then
                inst.SoundEmitter:PlaySound("turnoftides/creatures/together/spider_moon/break")
            end

            if inst.components.health then
                inst.components.health:SetInvincible(true)
                inst:DoTaskInTime(PARRY_INVINC_TIME, function(p)
                    if p and p:IsValid() and p.components.health then
                        p.components.health:SetInvincible(false)
                    end
                end)
            end

            if not is_client then
                if inst.components.sanity then
                    inst.components.sanity:DoDelta(16)
                end

                inst._parry_clash_count = (inst._parry_clash_count or 0) + 1
                if inst._parry_clash_count >= 2 then
                    inst._parry_clash_count = 0
                    if inst.components.starblight then
                        inst.components.starblight:DoDelta(-1)
                    end
                end
            end

            local weapon = inst.components.combat and inst.components.combat:GetWeapon() or nil
            ApplyElectrocuteEffects(target_ent, 92.5, inst, weapon)
            TriggerChainLightningLeaps(inst, weapon, target_ent)
            FlashEntityWhite(target_ent)
            
            DoPlayerBounceRecoil(inst)

            inst.AnimState:Pause()
            inst.sg:SetTimeout(24 * FRAMES)
            inst:DoTaskInTime(4 * FRAMES, function(p)
                if p and p:IsValid() and p.sg and p.sg.currentstate.name == "custom_dash_atk" then
                    p.AnimState:Resume()
                end
            end)
        end

        sg.states["custom_dash_atk"] = State({
            name = "custom_dash_atk",
            tags = { "attack", "busy", "notalking" },

            onenter = function(inst, data)
                SetupAttackAnim(inst, data, true, "small_atk")
                inst.sg.statemem.parry_active = true
                inst.sg.statemem.current_frame = 0
                inst.sg.statemem.clash_done = false

                if not is_client and inst.components.combat then
                    inst.sg.statemem.old_GetAttacked = inst.components.combat.GetAttacked
                    inst.components.combat.GetAttacked = function(self, attacker, damage, weapon, stimuli, ...)
                        if inst.sg.statemem.parry_active and not inst.sg.statemem.clash_done and attacker ~= nil and attacker:IsValid() then
                            local my_angle = inst.Transform:GetRotation()
                            local diff = GetAngleDifference(inst:GetAngleToPoint(attacker.Transform:GetWorldPosition()), my_angle)
                            local dist_sq = inst:GetDistanceSqToInst(attacker)
                            local in_range = dist_sq <= (HIT_DISTANCE * HIT_DISTANCE)

                            if diff <= PARRY_ANGLE_TOLERANCE and in_range then
                                ExecuteParryClash(inst, attacker)
                                return true
                            end
                        end
                        return inst.sg.statemem.old_GetAttacked(self, attacker, damage, weapon, stimuli, ...)
                    end
                end
            end,

            onupdate = function(inst)
                inst.sg.statemem.current_frame = (inst.sg.statemem.current_frame or 0) + 1
                if inst.sg.statemem.current_frame > PARRY_ACTIVE_FRAMES then
                    inst.sg.statemem.parry_active = false
                end
            end,

            timeline = {
                TimeEvent(5 * FRAMES, function(inst)
                    if not inst.sg.statemem.clash_done then
                        DoBoxHitCheck(inst, DASH_DMG_MULT, HITSTOP_FRAMES_FIRST, nil, nil, nil, is_client)
                    end
                end),
                TimeEvent(INTERRUPT_FRAME * FRAMES, function(inst)
                    if not inst.sg.statemem.hitstop_active then
                        inst.sg:RemoveStateTag("busy")
                        inst.sg:AddStateTag("can_combo")
                    end
                end),
            },

            events = GetAttackEvents(),
            onexit = function(inst) CleanupAttackState(inst, is_client) end,
            ontimeout = function(inst) inst.sg:GoToState("idle") end,
        })

        -- 3. 右键蓄力
        sg.states["custom_charge"] = State({
            name = "custom_charge",
            tags = { "busy", "charging", "notalking" },

            onenter = function(inst, data)
                data = data or {}
                if inst.components.locomotor then inst.components.locomotor:Stop() end
                if data.tx and data.tz then inst:ForceFacePoint(data.tx, 0, data.tz) end

                inst.AnimState:PlayAnimation("jump_lag", true)
                inst.sg.statemem.target_pos = data
                inst.sg.statemem.charge_time = 0
            end,

            onupdate = function(inst, dt)
                local ThePlayer = rawget(GLOBAL, "ThePlayer")
                if ThePlayer and inst == ThePlayer and TheInput then
                    local is_held = TheInput:IsMouseDown(MOUSEBUTTON_RIGHT) or TheInput:IsControlPressed(CONTROL_SECONDARY)
                    if not is_held then
                        inst.sg:GoToState("idle")
                        local mod_rpc = rawget(GLOBAL, "MOD_RPC")
                        local SendRpc = rawget(GLOBAL, "SendModRPCToServer")
                        if SendRpc and mod_rpc and mod_rpc["CustomCombat"] and mod_rpc["CustomCombat"]["CancelCharge"] then
                            SendRpc(mod_rpc["CustomCombat"]["CancelCharge"])
                        end
                        return
                    end

                    local raw_w = TheInput:IsKeyDown(KEY_W) or TheInput:IsKeyDown(KEY_UP)
                    local raw_s = TheInput:IsKeyDown(KEY_S) or TheInput:IsKeyDown(KEY_DOWN)
                    local raw_a = TheInput:IsKeyDown(KEY_A) or TheInput:IsKeyDown(KEY_LEFT)
                    local raw_d = TheInput:IsKeyDown(KEY_D) or TheInput:IsKeyDown(KEY_RIGHT)
                    if raw_w or raw_s or raw_a or raw_d then
                        local tx, tz = GetInputTargetPos(inst)
                        inst:ForceFacePoint(tx, 0, tz)
                        inst.sg.statemem.target_pos = { tx = tx, tz = tz }
                    end
                end

                inst.sg.statemem.charge_time = (inst.sg.statemem.charge_time or 0) + (dt or FRAMES)
                if inst.sg.statemem.charge_time >= 1.0 then
                    local data = inst.sg.statemem.target_pos
                    if not (data and data.tx and data.tz) then
                        local tx, tz = GetInputTargetPos(inst)
                        data = { tx = tx, tz = tz }
                    end

                    if ThePlayer and inst == ThePlayer and TheInput then
                        local TheWorld = rawget(GLOBAL, "TheWorld")
                        if not (TheWorld and TheWorld.ismastersim) then
                            local mod_rpc = rawget(GLOBAL, "MOD_RPC")
                            local SendRpc = rawget(GLOBAL, "SendModRPCToServer")
                            if SendRpc and mod_rpc and mod_rpc["CustomCombat"] and mod_rpc["CustomCombat"]["Heavy"] then
                                SendRpc(mod_rpc["CustomCombat"]["Heavy"], data.tx, data.tz)
                            end
                        end
                    end
                    inst.sg:GoToState("custom_heavy", data)
                end
            end,

            onexit = function(inst) inst.AnimState:Resume() end,
        })

        -- 4. 蓄力重斩 (保持装配 new_atk)
        sg.states["custom_heavy"] = State({
            name = "custom_heavy",
            tags = { "attack", "busy", "notalking" },

            onenter = function(inst, data)
                if not is_client and inst.components.sanity then
                    inst.components.sanity:DoDelta(-40)
                end
                SetupAttackAnim(inst, data, false, "new_atk")
            end,

            timeline = {
                TimeEvent(5 * FRAMES, function(inst)
                    DoBoxHitCheck(inst, HEAVY_DMG_MULT, HITSTOP_FRAMES_COMBO, HEAVY_HIT_DISTANCE, HEAVY_SIDE_HALF_WIDTH, HEAVY_KNOCKBACK_INIT, is_client)
                end),
                TimeEvent(INTERRUPT_FRAME * FRAMES, function(inst)
                    if not inst.sg.statemem.hitstop_active then
                        inst.sg:RemoveStateTag("busy")
                        inst.sg:AddStateTag("can_combo")
                    end
                end),
            },

            events = GetAttackEvents(),
            onexit = function(inst) CleanupAttackState(inst, is_client) end,
            ontimeout = function(inst) inst.sg:GoToState("idle") end,
        })

        -- 5. 长按 Z 蓄力回魂 (消除侵蚀条)
        sg.states["custom_focus"] = State({
            name = "custom_focus",
            tags = { "busy", "focusing", "notalking" },

            onenter = function(inst)
                if inst.components.locomotor then inst.components.locomotor:Stop() end
                inst.AnimState:PlayAnimation("jump_lag", true)
                inst.sg.statemem.focus_time = 0
                if inst.SoundEmitter then
                    inst.SoundEmitter:PlaySound("dontstarve/common/telebase_hum", "focus_loop")
                end
            end,

            onupdate = function(inst, dt)
                local ThePlayer = rawget(GLOBAL, "ThePlayer")
                if ThePlayer and inst == ThePlayer and TheInput then
                    local is_held = TheInput:IsKeyDown(KEY_Z)
                    if not is_held then
                        inst.sg:GoToState("idle")
                        local mod_rpc = rawget(GLOBAL, "MOD_RPC")
                        local SendRpc = rawget(GLOBAL, "SendModRPCToServer")
                        if SendRpc and mod_rpc and mod_rpc["CustomCombat"] and mod_rpc["CustomCombat"]["CancelFocus"] then
                            SendRpc(mod_rpc["CustomCombat"]["CancelFocus"])
                        end
                        return
                    end
                end

                inst.sg.statemem.focus_time = (inst.sg.statemem.focus_time or 0) + (dt or FRAMES)
                if inst.sg.statemem.focus_time >= 1.0 then
                    if ThePlayer and inst == ThePlayer and TheInput then
                        local TheWorld = rawget(GLOBAL, "TheWorld")
                        if not (TheWorld and TheWorld.ismastersim) then
                            local mod_rpc = rawget(GLOBAL, "MOD_RPC")
                            local SendRpc = rawget(GLOBAL, "SendModRPCToServer")
                            if SendRpc and mod_rpc and mod_rpc["CustomCombat"] and mod_rpc["CustomCombat"]["FocusSuccess"] then
                                SendRpc(mod_rpc["CustomCombat"]["FocusSuccess"])
                            end
                        end
                    end

                    if not is_client then
                        if inst.components.sanity and inst.components.sanity.current >= 40 then
                            inst.components.sanity:DoDelta(-40)
                            if inst.components.starblight then
                                inst.components.starblight:DoDelta(-1)
                            end
                        end
                    end

                    if inst.SoundEmitter then
                        inst.SoundEmitter:PlaySound("dontstarve/sanity/sanity_sponge_use")
                    end
                    FlashEntityWhite(inst)

                    local keep_focusing = false
                    if ThePlayer and inst == ThePlayer and TheInput and TheInput:IsKeyDown(KEY_Z) then
                        local san_val = (inst.replica and inst.replica.sanity and inst.replica.sanity:GetCurrent())
                                     or (inst.components.sanity and inst.components.sanity.current) or 0
                        local cur_lvl = (inst._starblight_level and inst._starblight_level:value())
                                     or (inst.components.starblight and inst.components.starblight:GetLevel()) or 0
                        if san_val >= 40 and cur_lvl > 0 then
                            keep_focusing = true
                        end
                    end

                    if keep_focusing then
                        inst.sg.statemem.focus_time = 0
                    else
                        inst.sg:GoToState("idle")
                    end
                end
            end,

            onexit = function(inst)
                if inst.SoundEmitter then
                    inst.SoundEmitter:KillSound("focus_loop")
                end
                inst.AnimState:Resume()
            end,
        })
    end)
end

RegisterCombatStates("wilson", false)
RegisterCombatStates("wilson_client", true)

-- ==========================================================
-- 网络远程过程调用 (RPC) 注册
-- ==========================================================
local function CheckCanAttack(player)
    if not (player and player:IsValid() and IsValidGlasscutter(player)) then return false end
    local is_busy = player:HasTag("busy") or (player.sg and player.sg:HasStateTag("busy"))
    local can_combo = player.sg and player.sg:HasStateTag("can_combo")
    return not is_busy or can_combo
end

AddModRPCHandler("CustomCombat", "Slash", function(player, tx, tz)
    if CheckCanAttack(player) then
        player.sg:GoToState("custom_slash", { tx = tx, tz = tz })
    end
end)

AddModRPCHandler("CustomCombat", "DashAtk", function(player, tx, tz)
    if CheckCanAttack(player) then
        player.sg:GoToState("custom_dash_atk", { tx = tx, tz = tz })
    end
end)

AddModRPCHandler("CustomCombat", "Charge", function(player, tx, tz)
    if player and player:IsValid() and IsValidGlasscutter(player) and not player.sg:HasStateTag("busy") then
        if player.components.sanity and player.components.sanity.current >= 40 then
            player.sg:GoToState("custom_charge", { tx = tx, tz = tz })
        end
    end
end)

AddModRPCHandler("CustomCombat", "Heavy", function(player, tx, tz)
    if player and player:IsValid() and IsValidGlasscutter(player) then
        if player.components.sanity and player.components.sanity.current >= 40 then
            player.sg:GoToState("custom_heavy", { tx = tx, tz = tz })
        end
    end
end)

AddModRPCHandler("CustomCombat", "CancelCharge", function(player)
    if player and player:IsValid() and player.sg and player.sg:HasStateTag("charging") then
        player.sg:GoToState("idle")
    end
end)

AddModRPCHandler("CustomCombat", "FocusStart", function(player)
    if player and player:IsValid() and IsValidGlasscutter(player) and not player.sg:HasStateTag("busy") then
        local san = player.components.sanity and player.components.sanity.current or 0
        local lvl = player.components.starblight and player.components.starblight:GetLevel() or 0
        if san >= 40 and lvl > 0 then
            player.sg:GoToState("custom_focus")
        end
    end
end)

AddModRPCHandler("CustomCombat", "CancelFocus", function(player)
    if player and player:IsValid() and player.sg and player.sg:HasStateTag("focusing") then
        player.sg:GoToState("idle")
    end
end)

AddModRPCHandler("CustomCombat", "FocusSuccess", function(player)
    if player and player:IsValid() and IsValidGlasscutter(player) and player.sg and player.sg:HasStateTag("focusing") then
        if player.components.sanity and player.components.sanity.current >= 40 then
            player.components.sanity:DoDelta(-40)
            if player.components.starblight then
                player.components.starblight:DoDelta(-1)
            end
        end
    end
end)

-- ==========================================================
-- 拦截官方控制器交互
-- ==========================================================
local function TriggerSlash(player)
    if not (player and player:IsValid()) then return false end
    if player.sg and player.sg:HasStateTag("charging") then return false end
    if not CheckCanAttack(player) then return false end

    local tx, tz = GetMouseTargetPos(player)
    player.sg:GoToState("custom_slash", { tx = tx, tz = tz })

    local mod_rpc = rawget(GLOBAL, "MOD_RPC")
    local SendRpc = rawget(GLOBAL, "SendModRPCToServer")
    if SendRpc and mod_rpc and mod_rpc["CustomCombat"] and mod_rpc["CustomCombat"]["Slash"] then
        SendRpc(mod_rpc["CustomCombat"]["Slash"], tx, tz)
    end
    return true
end

AddComponentPostInit("playercontroller", function(self)
    local _DoActionAuto = self.DoActionAuto
    self.DoActionAuto = function(s, ...)
        if not TheInput:IsKeyDown(KEY_SHIFT) and IsValidGlasscutter(s.inst) then return end
        if _DoActionAuto then return _DoActionAuto(s, ...) end
    end

    local _DoAttackButton = self.DoAttackButton
    self.DoAttackButton = function(s, ...)
        if not TheInput:IsKeyDown(KEY_SHIFT) and IsValidGlasscutter(s.inst) then
            TriggerSlash(s.inst)
            return
        end
        if _DoAttackButton then return _DoAttackButton(s, ...) end
    end

    local _OnControl = self.OnControl
    self.OnControl = function(s, control, down, ...)
        if (control == CONTROL_ACTION or control == CONTROL_SECONDARY) then
            if not TheInput:IsKeyDown(KEY_SHIFT) and IsValidGlasscutter(s.inst) then return end
        end
        if control == CONTROL_ATTACK then
            if not TheInput:IsKeyDown(KEY_SHIFT) and IsValidGlasscutter(s.inst) then
                if down then
                    TriggerSlash(s.inst)
                end
                return
            end
        end
        if _OnControl then return _OnControl(s, control, down, ...) end
    end

    local _OnRightClick = self.OnRightClick
    if _OnRightClick then
        self.OnRightClick = function(s, ...)
            if not TheInput:IsKeyDown(KEY_SHIFT) and IsValidGlasscutter(s.inst) then return end
            return _OnRightClick(s, ...)
        end
    end
end)

-- ==========================================================
-- 客户端全局按键与输入捕获
-- ==========================================================
if TheInput then
    if TheInput.AddKeyDownHandler and KEY_Z then
        TheInput:AddKeyDownHandler(KEY_Z, function()
            local ThePlayer = rawget(GLOBAL, "ThePlayer")
            if not (ThePlayer and ThePlayer:IsValid()) then return end
            if TheInput:IsKeyDown(KEY_SHIFT) or not IsValidGlasscutter(ThePlayer) then return end
            if TheInput:GetHUDEntityUnderMouse() ~= nil then return end
            if not CheckCanAttack(ThePlayer) then return end

            local san_replica = ThePlayer.replica and ThePlayer.replica.sanity
            if san_replica and san_replica:GetCurrent() < 40 then return end

            local net_level = ThePlayer._starblight_level
            local level = net_level and net_level:value() or 0
            if level <= 0 then return end

            ThePlayer.sg:GoToState("custom_focus")

            local mod_rpc = rawget(GLOBAL, "MOD_RPC")
            local SendRpc = rawget(GLOBAL, "SendModRPCToServer")
            if SendRpc and mod_rpc and mod_rpc["CustomCombat"] and mod_rpc["CustomCombat"]["FocusStart"] then
                SendRpc(mod_rpc["CustomCombat"]["FocusStart"])
            end
        end)
    end

    if TheInput.AddKeyDownHandler and KEY_SPACE then
        TheInput:AddKeyDownHandler(KEY_SPACE, function()
            local ThePlayer = rawget(GLOBAL, "ThePlayer")
            if not (ThePlayer and ThePlayer:IsValid()) then return end
            if TheInput:IsKeyDown(KEY_SHIFT) or not IsValidGlasscutter(ThePlayer) then return end
            if TheInput:GetHUDEntityUnderMouse() ~= nil then return end

            local cur_time = (GetTime and GetTime()) or 0
            if (cur_time - (ThePlayer._last_custom_dash_time or 0)) < DASH_CD then return end
            if not CheckCanAttack(ThePlayer) then return end

            ThePlayer._last_custom_dash_time = cur_time
            local tx, tz = GetInputTargetPos(ThePlayer)
            ThePlayer.sg:GoToState("custom_dash_atk", { tx = tx, tz = tz })

            local mod_rpc = rawget(GLOBAL, "MOD_RPC")
            local SendRpc = rawget(GLOBAL, "SendModRPCToServer")
            if SendRpc and mod_rpc and mod_rpc["CustomCombat"] and mod_rpc["CustomCombat"]["DashAtk"] then
                SendRpc(mod_rpc["CustomCombat"]["DashAtk"], tx, tz)
            end
        end)
    end

    if TheInput.AddMouseButtonHandler then
        TheInput:AddMouseButtonHandler(function(button, down, x, y)
            local ThePlayer = rawget(GLOBAL, "ThePlayer")
            if not (ThePlayer and ThePlayer:IsValid()) then return false end
            if TheInput:IsKeyDown(KEY_SHIFT) or not IsValidGlasscutter(ThePlayer) then return false end
            if TheInput:GetHUDEntityUnderMouse() ~= nil then return false end

            local mod_rpc = rawget(GLOBAL, "MOD_RPC")
            local SendRpc = rawget(GLOBAL, "SendModRPCToServer")

            if button == MOUSEBUTTON_RIGHT then
                if down then
                    if not CheckCanAttack(ThePlayer) then return false end
                    local san_replica = ThePlayer.replica and ThePlayer.replica.sanity
                    if san_replica and san_replica:GetCurrent() < 40 then
                        return false
                    end

                    local tx, tz = GetInputTargetPos(ThePlayer)
                    ThePlayer.sg:GoToState("custom_charge", { tx = tx, tz = tz })

                    if SendRpc and mod_rpc and mod_rpc["CustomCombat"] and mod_rpc["CustomCombat"]["Charge"] then
                        SendRpc(mod_rpc["CustomCombat"]["Charge"], tx, tz)
                    end
                    return true
                else
                    if ThePlayer.sg and ThePlayer.sg:HasStateTag("charging") then
                        ThePlayer.sg:GoToState("idle")
                        if SendRpc and mod_rpc and mod_rpc["CustomCombat"] and mod_rpc["CustomCombat"]["CancelCharge"] then
                            SendRpc(mod_rpc["CustomCombat"]["CancelCharge"])
                        end
                        return true
                    end
                end
                return false
            end

            if button == MOUSEBUTTON_LEFT and down then
                return TriggerSlash(ThePlayer)
            end

            return false
        end)
    end
end

