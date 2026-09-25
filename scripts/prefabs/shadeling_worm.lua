local GLOBAL = rawget(_G, "GLOBAL") or _G
local rawget = GLOBAL.rawget

local Prefab = rawget(GLOBAL, "Prefab")
local Asset = rawget(GLOBAL, "Asset")
local MakeCharacterPhysics = rawget(GLOBAL, "MakeCharacterPhysics")
local FindPlayersInRange = rawget(GLOBAL, "FindPlayersInRange")
local FindClosestPlayerToInst = rawget(GLOBAL, "FindClosestPlayerToInst")
local SetSharedLootTable = rawget(GLOBAL, "SetSharedLootTable")
local SpawnPrefab = rawget(GLOBAL, "SpawnPrefab")
local math = rawget(GLOBAL, "math")
local table = rawget(GLOBAL, "table")
local FRAMES = rawget(GLOBAL, "FRAMES") or (1 / 30)
local DEGREES = rawget(GLOBAL, "DEGREES") or (math.pi / 180)
local COLLISION = rawget(GLOBAL, "COLLISION")
local GetTime = rawget(GLOBAL, "GetTime")

local ReduceAngle = rawget(GLOBAL, "ReduceAngle") or function(angle)
    while angle > 180 do angle = angle - 360 end
    while angle <= -180 do angle = angle + 360 end
    return angle
end

local assets = {
    Asset("ANIM", "anim/fused_shadeling_bomb.zip"),
}

local prefabs = {
    "shadeling_worm_segment",
    "horrorfuel",
}

SetSharedLootTable("shadeling_worm", {
    { "horrorfuel", 1.00 },
    { "horrorfuel", 0.50 },
})

local function RetargetFn(inst)
    local px, py, pz = inst.Transform:GetWorldPosition()
    if FindPlayersInRange then
        local players = FindPlayersInRange(px, py, pz, inst._target_dist or 14, true)
        for _, player in ipairs(players) do
            if player and player:IsValid() then
                local health = player.components.health or (player.replica and player.replica.health)
                if health and not (health.IsDead and health:IsDead()) then
                    return player
                end
            end
        end
    end
    return nil
end

local function KeepTargetFn(inst, target)
    if not (target and target:IsValid()) then return false end
    local health = target.components.health or (target.replica and target.replica.health)
    if health and (health.IsDead and health:IsDead()) then return false end
    return inst:IsNear(target, inst._lose_target_dist or 14)
end

local function ConstrainToBody(body, last_body, spacing)
    if last_body and last_body:IsValid() and body.Physics then
        body.Physics:P2PConstrainTo(last_body.entity)
        body.Physics:SetP2PConstrainPivots(spacing, 0, 0, 0, 0, 0)
        body.Physics:Stop()
    end
end

local function OnUpdateWormPhysics(inst, dt)
    if not (inst.sg and inst.sg:HasStateTag("moving")) then
        return
    end

    local spacing = inst._segment_spacing or 0.5
    local turnspeed = inst._turn_speed or 300

    for i = 2, #inst.bodies do
        local body = inst.bodies[i]
        local lastbody = inst.bodies[i - 1]

        if body and body:IsValid() and lastbody and lastbody:IsValid() and body.Physics and not body._is_scattered then
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

local function ForEachSegmentControlled(inst, fn, ...)
    if inst.bodies then
        for i = 2, #inst.bodies do
            local body = inst.bodies[i]
            if body and body:IsValid() and not body._is_scattered then
                fn(body, ...)
            end
        end
    end
end

-- 散开节段的睡眠/超出范围销毁逻辑
local function OnScatterSleep(inst)
    if inst._is_scattered then
        inst:Remove()
    end
end

local function CheckScatterCleanup(inst)
    if not inst._is_scattered then return end

    if inst:IsAsleep() then
        inst:Remove()
        return
    end

    if FindClosestPlayerToInst then
        local player = FindClosestPlayerToInst(inst, 35, true)
        if not player then
            inst:Remove()
        end
    end
end

local function OnHeadDeath(inst)
    if inst.bodies then
        local cur_time = (GetTime and GetTime()) or 0
        for i = 2, #inst.bodies do
            local seg = inst.bodies[i]
            if seg and seg:IsValid() and not (seg.components.health and seg.components.health:IsDead()) then
                seg._is_scattered = true
                seg.persists = false
                seg.leader = nil
                seg.head = nil

                -- 1. 彻底解绑铰链并恢复阻挡
                if seg.Physics then
                    seg.Physics:P2PConstrainTo(nil)
                    seg.Physics:ClearCollisionMask()
                    seg.Physics:CollidesWith(COLLISION.WORLD)
                    seg.Physics:CollidesWith(COLLISION.OBSTACLES)
                    seg.Physics:CollidesWith(COLLISION.SMALLOBSTACLES)
                    seg.Physics:CollidesWith(COLLISION.CHARACTERS)
                    seg.Physics:CollidesWith(COLLISION.GIANTS)
                end

                -- 2. 独立战斗参数
                if seg.components.combat then
                    seg.components.combat.redirectdamagefn = nil
                    seg.components.combat:SetDefaultDamage(15)
                    seg.components.combat:SetAttackPeriod(1.8)
                    seg.components.combat:SetRange(1.0, 1.5)
                end

                -- 3. 错峰分化
                if i % 2 == 0 then
                    seg._scatter_state = "flee"
                    seg._state_end_time = cur_time + math.random(2.5, 4.5)
                else
                    seg._scatter_state = "wander"
                    seg._state_end_time = cur_time + math.random(1.5, 3.0)
                end

                -- 4. 挂载分散 AI
                seg:SetBrain(GLOBAL.require("brains/shadeling_scatter_brain"))
                seg:RestartBrain()

                -- 5. 命中与受击即刻逃离
                seg:ListenForEvent("onhitother", function(s)
                    s._scatter_state = "flee"
                    s._state_end_time = ((GetTime and GetTime()) or 0) + math.random(3.0, 4.5)
                    if s.components.combat then s.components.combat:DropTarget() end
                end)

                seg:ListenForEvent("attacked", function(s)
                    s._scatter_state = "flee"
                    s._state_end_time = ((GetTime and GetTime()) or 0) + math.random(3.0, 5.0)
                    if s.components.combat then s.components.combat:DropTarget() end
                end)

                -- 6. 超出渲染与离线防卡房监听
                seg:ListenForEvent("entitysleep", OnScatterSleep)
                seg:DoPeriodicTask(3.0, CheckScatterCleanup)

                if seg:IsAsleep() then
                    seg:Remove()
                end
            end
        end
    end
end

local function OnHeadRemove(inst)
    if inst.bodies then
        for i = 2, #inst.bodies do
            local seg = inst.bodies[i]
            if seg and seg:IsValid() and not seg._is_scattered then
                if seg.Physics then
                    seg.Physics:P2PConstrainTo(nil)
                end
                seg:Remove()
            end
        end
    end
end

local function SpawnWormSegments(inst)
    inst.bodies = { inst }
    local previous = inst
    local ix, iy, iz = inst.Transform:GetWorldPosition()
    local count = inst._segment_count or 7
    local spacing = inst._segment_spacing or 0.5
    local rot = inst.Transform:GetRotation() * DEGREES

    for i = 1, count do
        local segment = SpawnPrefab("shadeling_worm_segment")
        if segment then
            local offset_x = -math.cos(rot) * (spacing * i)
            local offset_z = math.sin(rot) * (spacing * i)
            segment.Transform:SetPosition(ix + offset_x, iy, iz + offset_z)

            segment.leader = previous
            segment.head = inst
            segment.segment_index = i
            segment.rot = inst.Transform:GetRotation()

            table.insert(inst.bodies, segment)
            ConstrainToBody(segment, previous, spacing)
            previous = segment
        end
    end
end

local function SegmentDamageRedirect(inst, attacker, damage, weapon, stimuli)
    if inst.head and inst.head:IsValid() and not (inst.head.components.health and inst.head.components.health:IsDead()) then
        return inst.head
    end
    return nil
end

local function create_common_body(tag)
    local inst = GLOBAL.CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddDynamicShadow()
    inst.entity:AddNetwork()

    inst.Transform:SetFourFaced()
    inst.DynamicShadow:SetSize(0.8, 0.4)

    inst:AddTag("monster")
    inst:AddTag("hostile")
    inst:AddTag("shadow_aligned")
    inst:AddTag("shadeling_worm")
    if tag then inst:AddTag(tag) end

    inst.AnimState:SetBank("fused_shadeling_bomb")
    inst.AnimState:SetBuild("fused_shadeling_bomb")
    inst.AnimState:PlayAnimation("idle_2")
    inst.AnimState:Hide("RED")
    inst.AnimState:SetDeltaTimeMultiplier(2.0)

    inst.entity:SetPristine()
    return inst
end

local function create_head()
    local inst = create_common_body("shadeling_worm_head")

    MakeCharacterPhysics(inst, 10, 0.25)

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not (TheWorld and TheWorld.ismastersim) then
        return inst
    end

    inst:AddComponent("inspectable")
    inst:AddComponent("knownlocations")

    local health = inst:AddComponent("health")
    health:SetMaxHealth(350)

    local combat = inst:AddComponent("combat")
    combat:SetDefaultDamage(20)
    combat:SetAttackPeriod(1.5)
    combat:SetRange(1.2, 1.7)
    combat:SetRetargetFunction(1.0, RetargetFn)
    combat:SetKeepTargetFunction(KeepTargetFn)

    local locomotor = inst:AddComponent("locomotor")
    locomotor.walkspeed = 8.0
    locomotor.runspeed = 8.0
    locomotor:SetTriggersCreep(false)
    locomotor.pathcaps = { ignorecreep = true }

    local lootdropper = inst:AddComponent("lootdropper")
    lootdropper:SetChanceLootTable("shadeling_worm")

    inst.ForEachSegmentControlled = ForEachSegmentControlled

    inst:SetStateGraph("SGshadeling_worm")
    inst:SetBrain(GLOBAL.require("brains/shadeling_worm_brain"))

    local InitTuning = rawget(GLOBAL, "ApplyWormTuning")
    if InitTuning then InitTuning(inst, "shadeling_worm_head") end

    inst:ListenForEvent("death", OnHeadDeath)
    inst:ListenForEvent("onremove", OnHeadRemove)

    inst:DoPeriodicTask(0, function()
        OnUpdateWormPhysics(inst, FRAMES)
    end)

    inst:DoTaskInTime(0, function()
        inst.components.knownlocations:RememberLocation("spawnpoint", inst:GetPosition())
        SpawnWormSegments(inst)
    end)

    return inst
end

local function create_segment()
    local inst = create_common_body("shadeling_worm_segment")

    MakeCharacterPhysics(inst, 5, 0.2)
    if inst.Physics then
        inst.Physics:ClearCollisionMask()
        inst.Physics:CollidesWith(COLLISION.WORLD)
    end

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not (TheWorld and TheWorld.ismastersim) then
        return inst
    end

    local health = inst:AddComponent("health")
    health:SetMaxHealth(100)

    local combat = inst:AddComponent("combat")
    combat.redirectdamagefn = SegmentDamageRedirect

    local locomotor = inst:AddComponent("locomotor")
    locomotor.walkspeed = 8.0
    locomotor.runspeed = 8.0
    locomotor:SetTriggersCreep(false)
    locomotor.pathcaps = { ignorecreep = true }

    inst:SetStateGraph("SGshadeling_worm")

    local InitTuning = rawget(GLOBAL, "ApplyWormTuning")
    if InitTuning then InitTuning(inst, "shadeling_worm_segment") end

    return inst
end

return Prefab("shadeling_worm", create_head, assets, prefabs),
    Prefab("shadeling_worm_segment", create_segment, assets)