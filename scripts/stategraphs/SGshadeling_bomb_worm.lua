local GLOBAL = rawget(_G, "GLOBAL") or _G
local require = rawget(GLOBAL, "require")
local StateGraph = rawget(GLOBAL, "StateGraph")
local State = rawget(GLOBAL, "State")
local EventHandler = rawget(GLOBAL, "EventHandler")
local CommonHandlers = rawget(GLOBAL, "CommonHandlers")
local FrameEvent = rawget(GLOBAL, "FrameEvent")

require("stategraphs/commonstates")

local function Segment_WalkForward(body)
    if body.components.locomotor then
        body.components.locomotor:WalkForward(true)
    end
end

local function Segment_Stop(body)
    if body.components.locomotor then
        body.components.locomotor:Stop()
    end
end

local actionhandlers = {}

local events = {
    EventHandler("locomote", function(inst)
        if not inst.sg:HasStateTag("busy") then
            local is_moving = inst.sg:HasStateTag("moving")
            local wants_to_move = inst.components.locomotor and inst.components.locomotor:WantsToMoveForward()

            if is_moving and not wants_to_move then
                inst.sg:GoToState("idle")
                if inst.ForEachSegmentControlled then
                    inst:ForEachSegmentControlled(Segment_Stop)
                end
            elseif not is_moving and wants_to_move then
                inst.sg:GoToState("walk")
                if inst.ForEachSegmentControlled then
                    inst:ForEachSegmentControlled(Segment_WalkForward)
                end
            end
        end
    end),

    CommonHandlers.OnDeath(),

    EventHandler("doattack", function(inst, data)
        if not inst.sg:HasStateTag("busy") and not (inst.components.health and inst.components.health:IsDead()) then
            local target = (data and data.target) or (inst.components.combat and inst.components.combat.target)
            if target and target:IsValid() and inst.mounted_bomb and inst.mounted_bomb:IsValid() then
                inst.sg:GoToState("throw_pre", target)
            end
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
        name = "throw_pre",
        tags = { "busy", "attack" },

        onenter = function(inst, target)
            if inst.components.locomotor then
                inst.components.locomotor:Stop()
            end
            if inst.components.combat then
                inst.components.combat:StartAttack()
            end
            if inst.ForEachSegmentControlled then
                inst:ForEachSegmentControlled(Segment_Stop)
            end

            inst.AnimState:PlayAnimation("bounce")
            inst.SoundEmitter:PlaySound("daywalker/leech/leap")
            inst.sg.statemem.target = target
            if target and target:IsValid() then
                inst:ForceFacePoint(target.Transform:GetWorldPosition())
            end
        end,

        timeline = {
            FrameEvent(6, function(inst)
                if inst.DoThrowBomb and inst.sg.statemem.target and inst.sg.statemem.target:IsValid() then
                    inst:DoThrowBomb(inst.sg.statemem.target)
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

return StateGraph("shadeling_bomb_worm", states, events, "idle", actionhandlers)