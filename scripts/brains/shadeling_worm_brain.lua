local GLOBAL = rawget(_G, "GLOBAL") or _G
local Class = rawget(GLOBAL, "Class")
local Brain = rawget(GLOBAL, "Brain")
local PriorityNode = rawget(GLOBAL, "PriorityNode")
local BT = rawget(GLOBAL, "BT")
local ChaseAndAttack = rawget(GLOBAL, "ChaseAndAttack")
local Wander = rawget(GLOBAL, "Wander")

require("behaviours/chaseandattack")
require("behaviours/wander")

local ShadelingWormBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

local function GetHome(inst)
    local knownlocations = inst.components.knownlocations
    return (knownlocations and knownlocations:GetLocation("spawnpoint")) or inst:GetPosition()
end

function ShadelingWormBrain:OnStart()
    local chase_dist = self.inst._lose_target_dist or 24
    local root = PriorityNode({
        ChaseAndAttack(self.inst, 15, chase_dist),
        Wander(self.inst, GetHome, 12),
    }, 0.25)

    self.bt = BT(self.inst, root)
end

return ShadelingWormBrain