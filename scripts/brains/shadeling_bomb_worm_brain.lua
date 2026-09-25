local GLOBAL = rawget(_G, "GLOBAL") or _G
local Class = rawget(GLOBAL, "Class")
local Brain = rawget(GLOBAL, "Brain")
local PriorityNode = rawget(GLOBAL, "PriorityNode")
local WhileNode = rawget(GLOBAL, "WhileNode")
local BT = rawget(GLOBAL, "BT")
local ChaseAndAttack = rawget(GLOBAL, "ChaseAndAttack")
local RunAway = rawget(GLOBAL, "RunAway")
local Wander = rawget(GLOBAL, "Wander")

require("behaviours/chaseandattack")
require("behaviours/runaway")
require("behaviours/wander")

local ShadelingBombWormBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

local function GetTarget(inst)
    return inst.components.combat and inst.components.combat.target
end

local function ShouldKeepDistance(inst)
    local target = GetTarget(inst)
    if not (target and target:IsValid()) then return false end
    local min_dist = inst._keep_dist_min or 4.0
    return inst:GetDistanceSqToInst(target) < (min_dist * min_dist)
end

function ShadelingBombWormBrain:OnStart()
    local min_dist = self.inst._keep_dist_min or 4.0
    local root = PriorityNode({
        -- 1. 贴脸防御：玩家过于接近时，全队后撤拉开身位
        WhileNode(function() return ShouldKeepDistance(self.inst) end, "KeepSafeDistance",
            RunAway(self.inst, "player", min_dist, min_dist + 2.0)
        ),

        -- 2. 架炮巡航：向射程边界靠近，进入 7 码后停步进入 throw_pre 投弹
        ChaseAndAttack(self.inst, 15, 25),

        -- 3. 脱战漫游
        Wander(self.inst, function()
            local known = self.inst.components.knownlocations
            return (known and known:GetLocation("spawnpoint")) or self.inst:GetPosition()
        end, 12),
    }, 0.25)

    self.bt = BT(self.inst, root)
end

return ShadelingBombWormBrain