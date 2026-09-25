local GLOBAL = rawget(_G, "GLOBAL") or _G
local rawget = GLOBAL.rawget

local Prefab = rawget(GLOBAL, "Prefab")
local Asset = rawget(GLOBAL, "Asset")
local MakeCharacterPhysics = rawget(GLOBAL, "MakeCharacterPhysics")
local FindPlayersInRange = rawget(GLOBAL, "FindPlayersInRange")
local SpawnPrefab = rawget(GLOBAL, "SpawnPrefab")
local math = rawget(GLOBAL, "math")
local table = rawget(GLOBAL, "table")
local ipairs = rawget(GLOBAL, "ipairs")
local FRAMES = rawget(GLOBAL, "FRAMES") or (1 / 30)
local DEGREES = rawget(GLOBAL, "DEGREES") or (math.pi / 180)
local COLLISION = rawget(GLOBAL, "COLLISION")
local GetTime = rawget(GLOBAL, "GetTime")
local TheSim = rawget(GLOBAL, "TheSim")
local TheWorld = rawget(GLOBAL, "TheWorld")

local ReduceAngle = rawget(GLOBAL, "ReduceAngle") or function(angle)
    while angle > 180 do angle = angle - 360 end
    while angle <= -180 do angle = angle + 360 end
    return angle
end

local assets = {
    Asset("ANIM", "anim/fused_shadeling_bomb.zip"),
}

local prefabs = {
    "shadeling_bomb_worm_segment",
    "shadeling_bomb_mounted",
    "shadeling_bomb_projectile",
    "fused_shadeling_bomb_death_fx",
    "fused_shadeling_bomb_scorch",
}

local function DoBombExplode(ix, iy, iz, radius, damage, attacker)
    local death_fx = SpawnPrefab("fused_shadeling_bomb_death_fx")
    if death_fx then death_fx.Transform:SetPosition(ix, iy, iz) end

    local scorch = SpawnPrefab("fused_shadeling_bomb_scorch")
    if scorch then scorch.Transform:SetPosition(ix, iy, iz) end

    local ents = TheSim:FindEntities(ix, iy, iz, radius, nil, { "INLIMBO", "FX", "DECOR" })
    for _, ent in ipairs(ents) do
        if ent and ent:IsValid() and ent ~= attacker then
            if ent:HasTag("player") and ent.components.combat then
                ent.components.combat:GetAttacked(attacker or ent, damage)
            elseif (ent:HasTag("shadeling_bomb_worm") or ent:HasTag("shadeling_bomb_worm_seg")) and ent.components.health then
                ent.components.health:DoDelta(-damage)
            end
        end
    end
end

local function ConstrainToBody(body, last_body, spacing)
    if last_body and last_body:IsValid() and body.Physics then
        body.Physics:P2PConstrainTo(last_body.entity)
        body.Physics:SetP2PConstrainPivots(spacing, 0, 0, 0, 0, 0)
        body.Physics:Stop()
    end
end

local function OnUpdateWormPhysics(inst, dt)
    if not (inst.sg and inst.sg:HasStateTag("moving")) then return end

    local spacing = inst._segment_spacing or 0.5
    local turnspeed = 300

    for i = 2, #inst.bodies do
        local body = inst.bodies[i]
        local lastbody = inst.bodies[i - 1]

        if body and body:IsValid() and lastbody and lastbody:IsValid() and body.Physics then
            local target_rot = body:GetAngleToPoint(lastbody.Transform:GetWorldPosition())
            local cur_rot = body.rot or body.Transform:GetRotation()
            local diff = ReduceAngle(target_rot - cur_rot)

            body.rot = cur_rot + diff * math.min(1.0, turnspeed * dt * DEGREES)
            body.Transform:SetRotation(body.rot)

            local rot_rad = body.rot * DEGREES
            body.Physics:SetP2PConstrainPivots(math.cos(rot_rad) * spacing, 0, -math.sin(rot_rad) * spacing, 0, 0, 0)
        end
    end
end

local function CascadeShiftBombs(head_inst)
    if not (head_inst and head_inst:IsValid() and head_inst.bodies) then return end

    local bodies = head_inst.bodies
    for i = 1, #bodies - 1 do
        if bodies[i] and bodies[i]:IsValid() and bodies[i].mounted_bomb == nil then
            for j = i + 1, #bodies do
                if bodies[j] and bodies[j]:IsValid() and bodies[j].mounted_bomb ~= nil then
                    local moving_bomb = bodies[j].mounted_bomb
                    bodies[j].mounted_bomb = nil

                    bodies[i].mounted_bomb = moving_bomb
                    moving_bomb.carrier = bodies[i]
                    break
                end
            end
        end
    end
end

local function RemoveSegmentFromChain(head_inst, dead_seg)
    if not (head_inst and head_inst:IsValid() and head_inst.bodies) then return end
    local bodies = head_inst.bodies
    local remove_idx = nil
    for idx, seg in ipairs(bodies) do
        if seg == dead_seg then
            remove_idx = idx
            break
        end
    end
    if remove_idx then
        table.remove(bodies, remove_idx)
        if bodies[remove_idx] and bodies[remove_idx - 1] then
            local spacing = head_inst._segment_spacing or 0.5
            ConstrainToBody(bodies[remove_idx], bodies[remove_idx - 1], spacing)
        end
    end
end

local function SetupHeadCapabilities(inst)
    inst.DoThrowBomb = function(self, target)
        if not (self.mounted_bomb and self.mounted_bomb:IsValid()) then return end

        local bomb = self.mounted_bomb
        self.mounted_bomb = nil
        bomb.carrier = nil
        bomb:Remove()

        local sp = self:GetPosition()
        local tp = target:GetPosition()
        local proj = SpawnPrefab("shadeling_bomb_projectile")
        if proj then
            proj.Transform:SetPosition(sp.x, sp.y + 0.8, sp.z)
            proj:Launch(sp, tp, 12.0, self._bomb_damage or 55, self._bomb_radius or 3.2, self)
        end

        self:DoTaskInTime(0.8, function()
            CascadeShiftBombs(self)
        end)
    end

    inst.ForEachSegmentControlled = function(self, fn, ...)
        if self.bodies then
            for i = 2, #self.bodies do
                local body = self.bodies[i]
                if body and body:IsValid() then fn(body, ...) end
            end
        end
    end
end

local function PromoteNextSegment(dead_head)
    if not (dead_head and dead_head.bodies) then return end

    local bodies = dead_head.bodies
    table.remove(bodies, 1)

    while #bodies > 0 and (bodies[1] == nil or not bodies[1]:IsValid()) do
        table.remove(bodies, 1)
    end

    if #bodies > 0 then
        local new_head = bodies[1]
        if new_head and new_head:IsValid() then
            if new_head.Physics then
                new_head.Physics:P2PConstrainTo(nil)
            end

            new_head:RemoveTag("shadeling_bomb_worm_seg")
            new_head:AddTag("shadeling_bomb_worm")
            new_head.bodies = bodies

            new_head:AddComponent("knownlocations")
            new_head.components.knownlocations:RememberLocation("spawnpoint", new_head:GetPosition())

            local combat = new_head.components.combat
            if combat then
                combat:SetDefaultDamage(0)
                combat:SetAttackPeriod(3.0)
                combat:SetRange(7.0, 9.0)
                combat:SetRetargetFunction(0.5, function(i)
                    local px, py, pz = i.Transform:GetWorldPosition()
                    if FindPlayersInRange then
                        local players = FindPlayersInRange(px, py, pz, 14, true)
                        for _, p in ipairs(players) do
                            if p and p:IsValid() and not (p.components.health and p.components.health:IsDead()) then
                                return p
                            end
                        end
                    end
                    return nil
                end)
                combat:SetKeepTargetFunction(function(i, t)
                    return i.components.combat:CanTarget(t) and i:IsNear(t, 20)
                end)
            end

            SetupHeadCapabilities(new_head)

            new_head:SetBrain(GLOBAL.require("brains/shadeling_bomb_worm_brain"))
            new_head:RestartBrain()

            new_head:ListenForEvent("death", function()
                if new_head.mounted_bomb and new_head.mounted_bomb:IsValid() then
                    new_head.mounted_bomb:Detonate()
                end
                PromoteNextSegment(new_head)
            end)
        end
    end
end

local function projectile_fn()
    local inst = GLOBAL.CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("fused_shadeling_bomb")
    inst.AnimState:SetBuild("fused_shadeling_bomb")
    inst.AnimState:PlayAnimation("ball_grow", true)
    inst.AnimState:Hide("bomb_body")

    inst:AddTag("FX")
    inst:AddTag("NOCLICK")

    inst.entity:SetPristine()
    if not (TheWorld and TheWorld.ismastersim) then return inst end

    inst.Launch = function(self, start_pos, target_pos, speed, damage, radius, owner)
        local dx = target_pos.x - start_pos.x
        local dz = target_pos.z - start_pos.z
        local dist = math.sqrt(dx * dx + dz * dz)
        local flight_time = math.clamp(dist / (speed or 12.0), 0.45, 1.2)
        local elapsed = 0
        local apex_height = 3.2

        inst:DoPeriodicTask(0, function(t)
            elapsed = elapsed + FRAMES
            local p = elapsed / flight_time
            if p >= 1.0 then
                t:Cancel()
                DoBombExplode(target_pos.x, 0, target_pos.z, radius or 3.2, damage or 55, owner)
                inst:Remove()
            else
                local cx = start_pos.x + dx * p
                local cz = start_pos.z + dz * p
                local cy = 4 * apex_height * p * (1 - p)
                inst.Transform:SetPosition(cx, cy, cz)
            end
        end)
    end

    inst.persists = false
    return inst
end

local function mounted_bomb_fn()
    local inst = GLOBAL.CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    -- 碰撞胶囊仅用于光标拾取与武器命中判定，清除 Mask 绝不阻挡底盘
    local physics = inst.entity:AddPhysics()
    physics:SetMass(1)
    physics:SetCapsule(0.4, 1.0)
    physics:SetCollisionGroup(COLLISION.CHARACTERS)
    physics:ClearCollisionMask()

    inst.AnimState:SetBank("fused_shadeling_bomb")
    inst.AnimState:SetBuild("fused_shadeling_bomb")
    inst.AnimState:PlayAnimation("ball_idle", true)
    inst.AnimState:Hide("bomb_body")
    inst.AnimState:SetDeltaTimeMultiplier(2.0)

    inst:AddTag("monster")
    inst:AddTag("hostile")
    inst:AddTag("shadeling_bomb_target")

    inst.entity:SetPristine()
    if not (TheWorld and TheWorld.ismastersim) then return inst end

    inst:AddComponent("inspectable")

    local health = inst:AddComponent("health")
    health:SetMaxHealth(100)

    local combat = inst:AddComponent("combat")
    combat.hiteffectsymbol = "marker"

    inst.Detonate = function(self)
        if self._exploded then return end
        self._exploded = true

        local bx, by, bz = self.Transform:GetWorldPosition()
        local carrier = self.carrier
        if carrier and carrier:IsValid() then
            carrier.mounted_bomb = nil
        end

        local damage = (carrier and carrier._bomb_damage) or 55
        local radius = (carrier and carrier._bomb_radius) or 3.2
        DoBombExplode(bx, by, bz, radius, damage, self)
        self:Remove()
    end

    inst:ListenForEvent("death", function()
        inst:Detonate()
    end)

    inst.persists = false
    return inst
end

local function create_chassis_common(tag)
    local inst = GLOBAL.CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddDynamicShadow()
    inst.entity:AddNetwork()

    inst.Transform:SetFourFaced()
    inst.DynamicShadow:SetSize(0.8, 0.4)

    inst.AnimState:SetBank("fused_shadeling_bomb")
    inst.AnimState:SetBuild("fused_shadeling_bomb")
    inst.AnimState:PlayAnimation("idle_2", true)
    inst.AnimState:Hide("RED")
    inst.AnimState:Hide("red_art")
    inst.AnimState:SetDeltaTimeMultiplier(2.0)

    -- 底盘不可被玩家直接平A选中
    inst:AddTag("monster")
    inst:AddTag("hostile")
    inst:AddTag("notarget")
    inst:AddTag("noattack")
    if tag then inst:AddTag(tag) end

    inst.entity:SetPristine()
    return inst
end

local function head_fn()
    local inst = create_chassis_common("shadeling_bomb_worm")
    MakeCharacterPhysics(inst, 10, 0.25)

    if not (TheWorld and TheWorld.ismastersim) then return inst end

    inst:AddComponent("inspectable")
    inst:AddComponent("knownlocations")

    local health = inst:AddComponent("health")
    health:SetMaxHealth(200)

    local combat = inst:AddComponent("combat")
    combat.canbeattackedfn = function() return false end
    combat:SetDefaultDamage(0)
    combat:SetAttackPeriod(3.0)
    combat:SetRange(7.0, 9.0)
    combat:SetRetargetFunction(0.5, function(i)
        local px, py, pz = i.Transform:GetWorldPosition()
        if FindPlayersInRange then
            local players = FindPlayersInRange(px, py, pz, 14, true)
            for _, p in ipairs(players) do
                if p and p:IsValid() and not (p.components.health and p.components.health:IsDead()) then
                    return p
                end
            end
        end
        return nil
    end)
    combat:SetKeepTargetFunction(function(i, t)
        return i.components.combat:CanTarget(t) and i:IsNear(t, 20)
    end)

    local locomotor = inst:AddComponent("locomotor")
    locomotor.walkspeed = 6.5
    locomotor.runspeed = 6.5
    locomotor:SetTriggersCreep(false)

    SetupHeadCapabilities(inst)

    inst:SetStateGraph("SGshadeling_bomb_worm")
    inst:SetBrain(GLOBAL.require("brains/shadeling_bomb_worm_brain"))

    local InitTuning = rawget(GLOBAL, "ApplyBombWormTuning")
    if InitTuning then InitTuning(inst) end

    inst:ListenForEvent("death", function()
        if inst.mounted_bomb and inst.mounted_bomb:IsValid() then
            inst.mounted_bomb:Detonate()
        end
        PromoteNextSegment(inst)
    end)

    inst:DoTaskInTime(0, function()
        inst.components.knownlocations:RememberLocation("spawnpoint", inst:GetPosition())
        inst.bodies = { inst }

        local spacing = inst._segment_spacing or 0.5
        local ix, iy, iz = inst.Transform:GetWorldPosition()
        local rot = inst.Transform:GetRotation() * DEGREES

        local head_bomb = SpawnPrefab("shadeling_bomb_mounted")
        if head_bomb then
            head_bomb.carrier = inst
            inst.mounted_bomb = head_bomb
            head_bomb.Transform:SetPosition(ix, iy + 0.35, iz)
        end

        local previous = inst
        for i = 1, 4 do
            local seg = SpawnPrefab("shadeling_bomb_worm_segment")
            if seg then
                local ox = -math.cos(rot) * (spacing * i)
                local oz = math.sin(rot) * (spacing * i)
                seg.Transform:SetPosition(ix + ox, iy, iz + oz)
                seg.head = inst
                seg.rot = inst.Transform:GetRotation()

                local seg_bomb = SpawnPrefab("shadeling_bomb_mounted")
                if seg_bomb then
                    seg_bomb.carrier = seg
                    seg.mounted_bomb = seg_bomb
                    seg_bomb.Transform:SetPosition(ix + ox, iy + 0.35, oz)
                end

                table.insert(inst.bodies, seg)
                ConstrainToBody(seg, previous, spacing)
                previous = seg
            end
        end

        inst:DoPeriodicTask(0, function()
            OnUpdateWormPhysics(inst, FRAMES)
            if inst.bodies then
                for _, b in ipairs(inst.bodies) do
                    if b and b:IsValid() and b.mounted_bomb and b.mounted_bomb:IsValid() then
                        local bx, by, bz = b.Transform:GetWorldPosition()
                        b.mounted_bomb.Transform:SetPosition(bx, by + 0.35, bz)
                        b.mounted_bomb.Transform:SetRotation(b.Transform:GetRotation())
                    end
                end
            end
        end)
    end)

    return inst
end

local function segment_fn()
    local inst = create_chassis_common("shadeling_bomb_worm_seg")

    MakeCharacterPhysics(inst, 5, 0.2)
    if inst.Physics then
        inst.Physics:ClearCollisionMask()
        inst.Physics:CollidesWith(COLLISION.WORLD)
    end

    if not (TheWorld and TheWorld.ismastersim) then return inst end

    local health = inst:AddComponent("health")
    health:SetMaxHealth(200)

    local combat = inst:AddComponent("combat")
    combat.canbeattackedfn = function() return false end

    local locomotor = inst:AddComponent("locomotor")
    locomotor.walkspeed = 6.5
    locomotor.runspeed = 6.5
    locomotor:SetTriggersCreep(false)

    inst:SetStateGraph("SGshadeling_bomb_worm")

    local InitTuning = rawget(GLOBAL, "ApplyBombWormTuning")
    if InitTuning then InitTuning(inst) end

    inst:ListenForEvent("death", function()
        if inst.mounted_bomb and inst.mounted_bomb:IsValid() then
            inst.mounted_bomb:Detonate()
        end
        if inst.head and inst.head:IsValid() then
            RemoveSegmentFromChain(inst.head, inst)
        end
    end)

    return inst
end

return Prefab("shadeling_bomb_worm", head_fn, assets, prefabs),
    Prefab("shadeling_bomb_worm_segment", segment_fn, assets),
    Prefab("shadeling_bomb_mounted", mounted_bomb_fn, assets),
    Prefab("shadeling_bomb_projectile", projectile_fn, assets)