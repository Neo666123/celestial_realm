local GLOBAL = rawget(_G, "GLOBAL") or _G
local require = rawget(GLOBAL, "require")
local StateGraph = rawget(GLOBAL, "StateGraph")
local State = rawget(GLOBAL, "State")
local EventHandler = rawget(GLOBAL, "EventHandler")
local CommonHandlers = rawget(GLOBAL, "CommonHandlers")
local FrameEvent = rawget(GLOBAL, "FrameEvent")
local math = rawget(GLOBAL, "math")
local FRAMES = rawget(GLOBAL, "FRAMES") or (1 / 30)

require("stategraphs/commonstates")

local LOCOMOTE_VARIANCE = 6 * FRAMES

local function Segment_ClearMovementTasks(body)
    if body.start_moving_task then
        body.start_moving_task:Cancel()
        body.start_moving_task = nil
    end
    if body.stop_moving_task then
        body.stop_moving_task:Cancel()
        body.stop_moving_task = nil
    end
end

local function Segment_WalkForward(body, should_run)
    if body.components.locomotor then
        if should_run then
            body.components.locomotor:RunForward(true)
            body.components.locomotor:SetShouldRun(true)
        else
            body.components.locomotor:WalkForward(true)
            body.components.locomotor:SetShouldRun(false)
        end
    end
end

local function Segment_WalkForward_Delay(body, should_run)
    Segment_ClearMovementTasks(body)
    body.start_moving_task = body:DoTaskInTime(math.random() * LOCOMOTE_VARIANCE, Segment_WalkForward, should_run)
end

local function Segment_Stop(body)
    if body.components.locomotor then
        body.components.locomotor:Stop()
    end
end

local function Segment_Stop_Delay(body)
    Segment_ClearMovementTasks(body)
    body.stop_moving_task = body:DoTaskInTime(math.random() * LOCOMOTE_VARIANCE, Segment_Stop)
end

local actionhandlers = {}

local events = {
    EventHandler("locomote", function(inst)
        if not inst.sg:HasStateTag("busy") then
            local is_head = inst:HasTag("shadeling_worm_head")
            local is_moving = inst.sg:HasStateTag("moving")
            local is_running = inst.sg:HasStateTag("running")
            local wants_to_move = inst.components.locomotor and inst.components.locomotor:WantsToMoveForward()
            local should_run = inst.components.locomotor and inst.components.locomotor:WantsToRun()

            if is_moving and not wants_to_move then
                inst.sg:GoToState("idle")
                if is_head and inst.ForEachSegmentControlled then
                    inst:ForEachSegmentControlled(Segment_Stop_Delay)
                end
            elseif (not is_moving and wants_to_move) or (is_moving and wants_to_move and is_running ~= should_run) then
                inst.sg:GoToState(should_run and "run" or "walk")
                if is_head and inst.ForEachSegmentControlled then
                    inst:ForEachSegmentControlled(Segment_WalkForward_Delay, should_run)
                end
            end
        end
    end),

    CommonHandlers.OnDeath(),

    EventHandler("doattack", function(inst, data)
        if not inst.sg:HasStateTag("busy") and not (inst.components.health and inst.components.health:IsDead()) then
            inst.sg:GoToState("attack", data and data.target)
        end
    end),

    EventHandler("attacked", function(inst)
        if not (inst.sg:HasStateTag("busy") or (inst.components.health and inst.components.health:IsDead())) then
            inst.sg:GoToState("hit")
        end
    end),
}

local states = {
    State({
        name = "idle",
        tags = { "idle", "canrotate" },

        onenter = function(inst)
            if inst.components.locomotor then
                inst.components.locomotor:Stop()
                inst.components.locomotor:Clear()
            end
            inst.AnimState:PlayAnimation("idle_2", true)

            -- 巨荒蜈防掉队唤醒逻辑：头在跑而身在发呆时，立即拉入移动
            if inst.head and inst.head:IsValid() and inst.head.sg:HasStateTag("moving") then
                Segment_WalkForward(inst, inst.head.sg:HasStateTag("running"))
            end
        end,
    }),

    State({
        name = "walk",
        tags = { "moving", "canrotate" },

        onenter = function(inst)
            if inst.components.locomotor then
                inst.components.locomotor:WalkForward(true)
            end
            inst.AnimState:PlayAnimation("walk", true)
            inst.SoundEmitter:PlaySound("rifts2/parasitic_shadeling/dreadmite_walk", "walk")
            inst.sg:SetTimeout(inst.AnimState:GetCurrentAnimationLength())
        end,

        ontimeout = function(inst)
            inst.sg:GoToState("walk")
        end,

        onexit = function(inst)
            inst.SoundEmitter:KillSound("walk")
        end,
    }),

    State({
        name = "run",
        tags = { "moving", "running", "canrotate" },

        onenter = function(inst)
            if inst.components.locomotor then
                inst.components.locomotor:RunForward(true)
            end
            inst.AnimState:PlayAnimation("walk", true)
            inst.SoundEmitter:PlaySound("rifts2/parasitic_shadeling/dreadmite_walk", "walk")
            inst.sg:SetTimeout(inst.AnimState:GetCurrentAnimationLength())
        end,

        ontimeout = function(inst)
            inst.sg:GoToState("run")
        end,

        onexit = function(inst)
            inst.SoundEmitter:KillSound("walk")
        end,
    }),

    State({
        name = "attack",
        tags = { "attack", "busy" },

        onenter = function(inst, target)
            if inst.components.locomotor then
                inst.components.locomotor:Stop()
            end
            inst.AnimState:PlayAnimation("bounce")
            inst.SoundEmitter:PlaySound("daywalker/leech/leap")
            inst.sg.statemem.target = target
        end,

        timeline = {
            FrameEvent(8, function(inst)
                if inst.components.combat and inst.sg.statemem.target then
                    inst.components.combat:DoAttack(inst.sg.statemem.target)
                end
            end),
        },

        events = {
            EventHandler("animover", function(inst)
                inst.sg:GoToState("idle")
            end),
        },
    }),

    State({
        name = "hit",
        tags = { "busy", "hit" },

        onenter = function(inst)
            if inst.components.locomotor then
                inst.components.locomotor:Stop()
            end
            inst.AnimState:PlayAnimation("idle_ground")
            inst.SoundEmitter:PlaySound("daywalker/leech/die")
        end,

        events = {
            EventHandler("animover", function(inst)
                inst.sg:GoToState("idle")
            end),
        },
    }),

    State({
        name = "death",
        tags = { "busy" },

        onenter = function(inst)
            if inst.components.locomotor then
                inst.components.locomotor:Stop()
            end
            inst.AnimState:PlayAnimation("death_fx")
            inst.SoundEmitter:PlaySound("rifts2/parasitic_shadeling/dreadmite_explode")
            if inst.Physics then
                inst.Physics:SetActive(false)
            end
        end,

        events = {
            EventHandler("animover", function(inst)
                inst:Remove()
            end),
        },
    }),
}

return StateGraph("shadeling_worm", states, events, "idle", actionhandlers)