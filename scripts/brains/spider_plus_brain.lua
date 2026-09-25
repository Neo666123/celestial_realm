local GLOBAL = rawget(_G, "GLOBAL") or _G
local Class = rawget(GLOBAL, "Class")
local Brain = rawget(GLOBAL, "Brain")
local PriorityNode = rawget(GLOBAL, "PriorityNode")
local WhileNode = rawget(GLOBAL, "WhileNode")
local ActionNode = rawget(GLOBAL, "ActionNode")
local ChaseAndAttack = rawget(GLOBAL, "ChaseAndAttack")
local Wander = rawget(GLOBAL, "Wander")
local BT = rawget(GLOBAL, "BT")
local GetTime = rawget(GLOBAL, "GetTime")

require("behaviours/chaseandattack")
require("behaviours/wander")

local SpiderPlusBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

-- 追击周期时序控制：交替走停
local function ShouldStopMoving(inst)
    local target = inst.components.combat and inst.components.combat.target
    if not (target and target:IsValid()) then
        inst._move_phase = nil
        inst._phase_start_time = nil
        return false
    end

    local cur_time = (GetTime and GetTime()) or 0
    local walk_time = inst._walk_time or 1.0
    local stop_time = inst._stop_time or 0.5

    if not inst._move_phase then
        inst._move_phase = "walk"
        inst._phase_start_time = cur_time
    end

    local elapsed = cur_time - inst._phase_start_time

    if inst._move_phase == "walk" then
        if elapsed >= walk_time then
            inst._move_phase = "stop"
            inst._phase_start_time = cur_time
        end
    elseif inst._move_phase == "stop" then
        if elapsed >= stop_time then
            inst._move_phase = "walk"
            inst._phase_start_time = cur_time
        end
    end

    return inst._move_phase == "stop"
end

function SpiderPlusBrain:OnStart()
    local root = PriorityNode({
        -- 停顿阶段：制动截流，让状态机自然回滚至 idle
        WhileNode(function() return ShouldStopMoving(self.inst) end, "PauseMoving",
            ActionNode(function()
                if self.inst.components.locomotor then
                    self.inst.components.locomotor:Stop()
                end
            end)
        ),
        ChaseAndAttack(self.inst, 15, 20),
        Wander(self.inst),
    }, 0.2)

    self.bt = BT(self.inst, root)
end

return SpiderPlusBrain