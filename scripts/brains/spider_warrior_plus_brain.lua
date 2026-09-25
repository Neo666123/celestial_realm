local GLOBAL = rawget(_G, "GLOBAL") or _G
local Class = rawget(GLOBAL, "Class")
local Brain = rawget(GLOBAL, "Brain")
local PriorityNode = rawget(GLOBAL, "PriorityNode")
local WhileNode = rawget(GLOBAL, "WhileNode")
local ChaseAndAttack = rawget(GLOBAL, "ChaseAndAttack")
local Wander = rawget(GLOBAL, "Wander")
local ActionNode = rawget(GLOBAL, "ActionNode")
local BT = rawget(GLOBAL, "BT")
local Point = rawget(GLOBAL, "Point")
local GetTime = rawget(GLOBAL, "GetTime")
local PI = rawget(GLOBAL, "PI") or math.pi

require("behaviours/chaseandattack")
require("behaviours/wander")

local AI_ORBIT_RADIUS      = 6.0
local AI_LEAP_MIN_DIST     = 4.5
local AI_ORBIT_ANGULAR_SPD = 25.0

local SpiderWarriorPlusBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

-- 检查是否处于硬性出招间隔内
local function IsInSkillInterval(inst, cur_time)
    local interval = inst._skill_interval or 5.0
    return (cur_time - (inst._last_skill_finish_time or -100)) < interval
end

-- 1. 白冲判定：轮到冲刺 + 间隔结束 + 满足冲刺距离
local function CanDoWhiteCharge(inst)
    if inst.sg and inst.sg:HasStateTag("busy") then return false end
    local target = inst.components.combat and inst.components.combat.target
    if not (target and target:IsValid()) then return false end

    local next_skill = inst._next_skill or "charge"
    if next_skill ~= "charge" then return false end

    local cur_time = (GetTime and GetTime()) or 0
    if IsInSkillInterval(inst, cur_time) then return false end

    local max_dist = inst._charge_attack_range or 12.0
    local min_dist = 4.5
    local dsq = inst:GetDistanceSqToInst(target)

    return dsq >= (min_dist * min_dist) and dsq <= (max_dist * max_dist)
end

-- 2. 大跳判定：轮到大跳 + 间隔结束 + 满足大跳距离
local function CanDoWarriorLeap(inst)
    if inst.sg and inst.sg:HasStateTag("busy") then return false end
    local target = inst.components.combat and inst.components.combat.target
    if not (target and target:IsValid()) then return false end

    local next_skill = inst._next_skill or "charge"
    if next_skill ~= "leap" then return false end

    local cur_time = (GetTime and GetTime()) or 0
    if IsInSkillInterval(inst, cur_time) then return false end

    local max_dist = inst._leap_attack_range or 7.5
    local min_dist = 3.0
    local dsq = inst:GetDistanceSqToInst(target)

    return dsq >= (min_dist * min_dist) and dsq <= (max_dist * max_dist)
end

-- 3. 逼近判定：轮到大跳且出招间隔已就绪，但距离超出上限时主动逼近
local function ShouldApproachForLeap(inst)
    if inst.sg and inst.sg:HasStateTag("busy") then return false end
    local target = inst.components.combat and inst.components.combat.target
    if not (target and target:IsValid()) then return false end

    local next_skill = inst._next_skill or "charge"
    if next_skill ~= "leap" then return false end

    local cur_time = (GetTime and GetTime()) or 0
    if IsInSkillInterval(inst, cur_time) then return false end

    local max_dist = inst._leap_attack_range or 7.5
    return inst:GetDistanceSqToInst(target) > (max_dist * max_dist)
end

local function OrbitAndKeepDistance(inst)
    local target = inst.components.combat and inst.components.combat.target
    if not (target and target:IsValid()) or (inst.sg and inst.sg:HasStateTag("busy")) then
        return false
    end

    local px, py, pz = target.Transform:GetWorldPosition()
    local sx, sy, sz = inst.Transform:GetWorldPosition()
    local dx, dz = sx - px, sz - pz
    local current_dist = math.sqrt(dx * dx + dz * dz)
    if current_dist < 0.001 then return false end

    local current_angle = math.atan2(dz, dx)
    local orbit_dir = inst._orbit_dir or 1
    local next_angle = current_angle + orbit_dir * (AI_ORBIT_ANGULAR_SPD * (PI / 180))

    local target_radius = AI_ORBIT_RADIUS
    if current_dist < AI_LEAP_MIN_DIST then
        target_radius = AI_LEAP_MIN_DIST + 1.0
    end

    local dest_x = px + math.cos(next_angle) * target_radius
    local dest_z = pz + math.sin(next_angle) * target_radius

    if inst.components.locomotor then
        inst.components.locomotor:GoToPoint(Point(dest_x, 0, dest_z))
        return true
    end
    return false
end

function SpiderWarriorPlusBrain:OnStart()
    self.inst._orbit_dir = (math.random() < 0.5 and 1) or -1
    self.inst._next_skill = self.inst._next_skill or "charge"

    local root = PriorityNode({
        -- 节点 1：执行白冲，切入后下一次技能轮换为大跳
        WhileNode(function() return CanDoWhiteCharge(self.inst) end, "WhiteChargeTrigger",
            ActionNode(function()
                local target = self.inst.components.combat.target
                self.inst._next_skill = "leap"
                self.inst.sg:GoToState("white_charge_pre", target)
            end)
        ),

        -- 节点 2：执行大跳，切入后下一次技能轮换为白冲
        WhileNode(function() return CanDoWarriorLeap(self.inst) end, "WarriorLeapTrigger",
            ActionNode(function()
                local target = self.inst.components.combat.target
                self.inst._next_skill = "charge"
                self.inst.sg:GoToState("warrior_leap", target)
            end)
        ),

        -- 节点 3：轮到大跳但距离过远时，向目标靠拢
        WhileNode(function() return ShouldApproachForLeap(self.inst) end, "ApproachToLeap",
            ChaseAndAttack(self.inst, 12, 18)
        ),

        -- 节点 4：间隔冷却期或等待时机，全速环绕走位
        WhileNode(function()
            return self.inst.components.combat and self.inst.components.combat.target ~= nil
        end, "Orbiting",
            ActionNode(function()
                OrbitAndKeepDistance(self.inst)
            end)
        ),

        Wander(self.inst),
    }, 0.15)

    self.bt = BT(self.inst, root)
end

return SpiderWarriorPlusBrain