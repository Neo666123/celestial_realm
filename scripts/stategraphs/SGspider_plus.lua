local GLOBAL = rawget(_G, "GLOBAL") or _G
local require = GLOBAL.require
local StateGraph = GLOBAL.StateGraph
local State = GLOBAL.State
local EventHandler = GLOBAL.EventHandler
local TimeEvent = GLOBAL.TimeEvent
local ActionHandler = GLOBAL.ActionHandler
local ACTIONS = GLOBAL.ACTIONS
local FRAMES = GLOBAL.FRAMES
local PI = GLOBAL.PI
local RemovePhysicsColliders = GLOBAL.RemovePhysicsColliders
local math = GLOBAL.math
local TheSim = rawget(GLOBAL, "TheSim")
local easing = require("easing")

require("stategraphs/commonstates")

local function SoundPath(inst, event)
    if inst.SoundPath then return inst:SoundPath(event) end
    return "dontstarve/creatures/spiderwarrior/" .. event
end

local actionhandlers =
{
    ActionHandler(ACTIONS.EAT, "eat"),
    ActionHandler(ACTIONS.GOHOME, "eat"),
    ActionHandler(ACTIONS.INVESTIGATE, "investigate"),
}

local events =
{
    GLOBAL.CommonHandlers.OnSleep(),
    GLOBAL.CommonHandlers.OnFreeze(),
    GLOBAL.CommonHandlers.OnDeath(),

    EventHandler("attacked", function(inst, data)
        if inst.components.health and not inst.components.health:IsDead() then
            if not inst.sg:HasAnyStateTag("attack", "busy", "charging") then
                inst.sg:GoToState("hit")
            end
        end
    end),

    EventHandler("doattack", function(inst, data)
        if not (inst.sg:HasStateTag("busy") or inst.components.health:IsDead()) then
            if data and data.target and data.target:IsValid() then
                if inst:HasTag("spider_warrior_plus") then
                    -- 大蜘蛛全权由行为树决策交替出招，阻断引擎原生平 A 响应
                    if inst.components.combat then
                        inst.components.combat.lastdoattacktime = (GLOBAL.GetTime and GLOBAL.GetTime()) or 0
                    end
                else
                    inst.sg:GoToState("attack", data.target)
                end
            end
        end
    end),

    EventHandler("locomote", function(inst)
        if not inst.sg:HasStateTag("busy") then
            local is_moving = inst.sg:HasStateTag("moving")
            local wants_to_move = inst.components.locomotor:WantsToMoveForward()
            if not inst.sg:HasStateTag("attack") and is_moving ~= wants_to_move then
                if wants_to_move then
                    inst.sg:GoToState("premoving")
                else
                    inst.sg:GoToState("idle", "walk_pst")
                end
            end
        end
    end),
}

local states =
{
    State{
        name = "idle",
        tags = {"idle", "canrotate"},
        ontimeout = function(inst) inst.sg:GoToState("taunt") end,
        onenter = function(inst, start_anim)
            inst.Physics:Stop()
            if math.random() < 0.3 then
                inst.sg:SetTimeout(math.random() * 2 + 2)
            end
            if start_anim then
                inst.AnimState:PlayAnimation(start_anim)
                inst.AnimState:PushAnimation("idle", true)
            else
                inst.AnimState:PlayAnimation("idle", true)
            end
        end,
    },

    State{
        name = "taunt",
        tags = {"busy"},
        onenter = function(inst)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("taunt")
            inst.SoundEmitter:PlaySound(SoundPath(inst, "scream"))
        end,
        events = { EventHandler("animover", function(inst) inst.sg:GoToState("idle") end) },
    },

    State{
        name = "premoving",
        tags = {"moving", "canrotate"},
        onenter = function(inst)
            inst.components.locomotor:WalkForward()
            inst.AnimState:PlayAnimation("walk_pre")
        end,
        events = { EventHandler("animover", function(inst) inst.sg:GoToState("moving") end) },
    },

    State{
        name = "moving",
        tags = {"moving", "canrotate"},
        onenter = function(inst)
            inst.components.locomotor:RunForward()
            inst.AnimState:PushAnimation("walk_loop")
        end,
        events = { EventHandler("animover", function(inst) inst.sg:GoToState("moving") end) },
    },

    State{
        name = "attack",
        tags = {"attack", "busy"},
        onenter = function(inst, target)
            inst.Physics:Stop()
            inst.components.combat:StartAttack()
            inst.AnimState:PlayAnimation("atk")
            inst.sg.statemem.target = target
        end,
        timeline = {
            TimeEvent(10 * FRAMES, function(inst) inst.SoundEmitter:PlaySound(SoundPath(inst, "Attack")) end),
            TimeEvent(20 * FRAMES, function(inst) inst.components.combat:DoAttack(inst.sg.statemem.target) end),
        },
        events = { EventHandler("animover", function(inst) inst.sg:GoToState("idle") end) },
    },

    State{
        name = "hit",
        tags = {"busy", "hit"},
        onenter = function(inst)
            inst.AnimState:PlayAnimation("hit")
            inst.Physics:Stop()
            inst.SoundEmitter:PlaySound(SoundPath(inst, "hit_response"))
        end,
        events = { EventHandler("animover", function(inst) inst.sg:GoToState("idle") end) },
    },

    State{
        name = "death",
        tags = {"busy"},
        onenter = function(inst)
            inst.SoundEmitter:PlaySound(SoundPath(inst, "die"))
            inst.AnimState:PlayAnimation("death")
            inst.Physics:Stop()
            RemovePhysicsColliders(inst)
            inst:DropDeathLoot()
        end,
        events = { EventHandler("animover", function(inst) inst.sg:GoToState("corpse") end) },
    },

    State{
        name = "warrior_leap",
        tags = { "attack", "canrotate", "busy", "jumping" },
        onenter = function(inst, target)
            inst.components.locomotor:Stop()
            inst.components.locomotor:EnableGroundSpeedMultiplier(false)
            inst.components.combat:StartAttack()
            inst.AnimState:PlayAnimation("warrior_atk")
            inst.sg.statemem.target = target
            if target and target:IsValid() then inst:ForceFacePoint(target.Transform:GetWorldPosition()) end
        end,
        onexit = function(inst)
            inst.components.locomotor:Stop()
            inst.components.locomotor:EnableGroundSpeedMultiplier(true)
            inst.Physics:ClearMotorVelOverride()
            inst.Physics:Stop()
            -- 大跳动作结束，打上时间戳作为出招间隔计时起点
            inst._last_skill_finish_time = (GLOBAL.GetTime and GLOBAL.GetTime()) or 0
        end,
        timeline = {
            TimeEvent(0 * FRAMES, function(inst) inst.SoundEmitter:PlaySound(SoundPath(inst, "Jump")) end),
            TimeEvent(8 * FRAMES, function(inst) inst.Physics:SetMotorVelOverride(20, 0, 0) end),
            TimeEvent(9 * FRAMES, function(inst) inst.SoundEmitter:PlaySound(SoundPath(inst, "Attack")) end),
            TimeEvent(19 * FRAMES, function(inst)
                if inst.sg.statemem.target and inst.sg.statemem.target:IsValid() then
                    inst.components.combat:DoAttack(inst.sg.statemem.target)
                end
            end),
            TimeEvent(20 * FRAMES, function(inst)
                inst.Physics:ClearMotorVelOverride()
                inst.Physics:Stop()
            end),
        },
        events = { EventHandler("animover", function(inst) inst.sg:GoToState("taunt") end) },
    },

    State{
        name = "white_charge_pre",
        tags = { "busy", "charging" },

        onenter = function(inst, target)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("taunt")
            inst.SoundEmitter:PlaySound(SoundPath(inst, "scream"))
            inst.sg.statemem.target = target
            inst.sg.statemem.elapsed = 0
            inst.sg.statemem.duration = 18 * FRAMES
        end,

        onupdate = function(inst, dt)
            inst.sg.statemem.elapsed = inst.sg.statemem.elapsed + dt
            local t = math.min(1.0, inst.sg.statemem.elapsed / inst.sg.statemem.duration)
            inst.AnimState:SetAddColour(t, t, t, 0)

            local target = inst.sg.statemem.target
            if target and target:IsValid() and t < 0.85 then
                inst:ForceFacePoint(target.Transform:GetWorldPosition())
            end

            if inst.sg.statemem.elapsed >= inst.sg.statemem.duration then
                inst.sg:GoToState("white_charge_dash", inst.sg.statemem.target)
            end
        end,

        onexit = function(inst)
            if inst.sg.currentstate.name ~= "white_charge_dash" then
                inst.AnimState:SetAddColour(0, 0, 0, 0)
            end
        end,
    },

    State{
        name = "white_charge_dash",
        tags = { "attack", "busy", "jumping", "charging" },

        onenter = function(inst, target)
            inst.AnimState:PlayAnimation("warrior_atk")
            inst.SoundEmitter:PlaySound(SoundPath(inst, "Jump"))
            inst.SoundEmitter:PlaySound(SoundPath(inst, "Attack"))

            inst.sg.statemem.target = target
            inst.sg.statemem.elapsed = 0
            inst.sg.statemem.has_hit = false

            -- 根据与目标的实际物理间距，动态线性缩放初始推力与持续帧数
            local dist = (target and target:IsValid()) and math.sqrt(inst:GetDistanceSqToInst(target)) or 6.0
            local scale = math.clamp(dist / 6.0, 0.75, 2.2)

            inst.sg.statemem.duration = math.floor(12 * math.clamp(scale, 0.85, 1.4)) * FRAMES
            inst.sg.statemem.start_speed = 32.0 * scale
            inst.sg.statemem.end_speed = 6.0 * scale

            inst.components.locomotor:EnableGroundSpeedMultiplier(false)
        end,

        onupdate = function(inst, dt)
            inst.sg.statemem.elapsed = inst.sg.statemem.elapsed + dt
            local t = math.min(inst.sg.statemem.elapsed, inst.sg.statemem.duration)

            local speed = easing.outQuad(t, inst.sg.statemem.start_speed, inst.sg.statemem.end_speed - inst.sg.statemem.start_speed, inst.sg.statemem.duration)
            inst.Physics:SetMotorVelOverride(speed, 0, 0)

            if not inst.sg.statemem.has_hit then
                local px, py, pz = inst.Transform:GetWorldPosition()
                local rot_rad = inst.Transform:GetRotation() * (PI / 180)
                local cos_theta, sin_theta = math.cos(rot_rad), math.sin(rot_rad)

                local ents = TheSim:FindEntities(px, py, pz, 3.0, { "_combat", "_health" }, { "spider", "INLIMBO", "FX" })
                for _, ent in ipairs(ents) do
                    local health = ent.components.health or (ent.replica and ent.replica.health)
                    if ent:IsValid() and health and not (health.IsDead and health:IsDead()) then
                        local tx, _, tz = ent.Transform:GetWorldPosition()
                        local dx, dz = tx - px, tz - pz
                        local forward_dist = dx * cos_theta - dz * sin_theta
                        local side_dist = math.abs(dx * sin_theta + dz * cos_theta)

                        if forward_dist >= 0 and forward_dist <= 2.8 and side_dist <= 1.4 then
                            inst.sg.statemem.has_hit = true
                            if inst.components.combat then
                                inst.components.combat:DoAttack(ent)
                            end
                            inst.SoundEmitter:PlaySound("turnoftides/creatures/together/spider_moon/break")
                            inst.sg:GoToState("white_charge_pst", true)
                            return
                        end
                    end
                end
            end

            if inst.sg.statemem.elapsed >= inst.sg.statemem.duration then
                inst.sg:GoToState("white_charge_pst", false)
            end
        end,

        onexit = function(inst)
            inst.components.locomotor:EnableGroundSpeedMultiplier(true)
            inst.Physics:ClearMotorVelOverride()
            inst.Physics:Stop()
            inst.AnimState:SetAddColour(0, 0, 0, 0)
        end,
    },

    State{
        name = "white_charge_pst",
        tags = { "busy" },

        onenter = function(inst, hit_target)
            inst.Physics:Stop()
            inst.AnimState:SetAddColour(0, 0, 0, 0)
            -- 冲刺动作结束，打上时间戳作为出招间隔计时起点
            inst._last_skill_finish_time = (GLOBAL.GetTime and GLOBAL.GetTime()) or 0

            if hit_target then
                inst.AnimState:PlayAnimation("atk")
                inst.sg:SetTimeout(8 * FRAMES)
            else
                inst.AnimState:PlayAnimation("idle")
                inst.sg:SetTimeout(12 * FRAMES)
            end
        end,

        ontimeout = function(inst)
            inst.sg:GoToState("idle")
        end,
    },
}

GLOBAL.CommonStates.AddSleepStates(states)
GLOBAL.CommonStates.AddFrozenStates(states)
GLOBAL.CommonStates.AddCorpseStates(states)
GLOBAL.CommonStates.AddInitState(states, "idle")

return StateGraph("spider_plus", states, events, "init", actionhandlers)