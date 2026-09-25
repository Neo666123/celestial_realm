local GLOBAL = rawget(_G, "GLOBAL") or _G
local Class = rawget(GLOBAL, "Class")
local Brain = rawget(GLOBAL, "Brain")
local PriorityNode = rawget(GLOBAL, "PriorityNode")
local WhileNode = rawget(GLOBAL, "WhileNode")
local BT = rawget(GLOBAL, "BT")
local ChaseAndAttack = rawget(GLOBAL, "ChaseAndAttack")
local RunAway = rawget(GLOBAL, "RunAway")
local Wander = rawget(GLOBAL, "Wander")
local FaceEntity = rawget(GLOBAL, "FaceEntity")
local GetTime = rawget(GLOBAL, "GetTime")
local FindClosestPlayerToInst = rawget(GLOBAL, "FindClosestPlayerToInst")
local math = rawget(GLOBAL, "math")

require("behaviours/chaseandattack")
require("behaviours/runaway")
require("behaviours/wander")
require("behaviours/faceentity")

local ShadelingScatterBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

local function GetPlayer(inst)
    if FindClosestPlayerToInst then
        local player = FindClosestPlayerToInst(inst, 20, true)
        if player and player:IsValid() then
            local health = player.components.health or (player.replica and player.replica.health)
            if health and not (health.IsDead and health:IsDead()) then
                return player
            end
        end
    end
    return nil
end

local function UpdateScatterStateMachine(inst)
    local cur_time = (GetTime and GetTime()) or 0
    if not inst._scatter_state then
        inst._scatter_state = (math.random() < 0.5) and "flee" or "wander"
        inst._state_end_time = cur_time + math.random(2.0, 4.0)
    end

    local player = GetPlayer(inst)

    -- 在静止观察模式下，若玩家突然冲过来（距离小于 4 码），小虫惊慌逃窜
    if inst._scatter_state == "observe" and player and inst:IsNear(player, 4.0) then
        inst._scatter_state = "flee"
        inst._state_end_time = cur_time + math.random(2.5, 4.5)
        return
    end

    if cur_time >= (inst._state_end_time or 0) then
        local next_state = "wander"
        local duration = 2.5

        if inst._scatter_state == "flee" then
            -- 逃开一段距离后，停下转头窥视玩家
            next_state = "observe"
            duration = math.random(2.0, 3.5)
        elseif inst._scatter_state == "observe" then
            -- 观察结束：有玩家则发起偷袭，否则游走散开
            if player and math.random() < 0.75 then
                next_state = "attack"
                duration = inst._attack_duration or 3.0
                if inst.components.combat then
                    inst.components.combat:SetTarget(player)
                end
            else
                next_state = "wander"
                duration = math.random(2.0, 4.0)
            end
        elseif inst._scatter_state == "wander" then
            -- 闲逛几秒后，突然索敌突击
            if player then
                next_state = "attack"
                duration = inst._attack_duration or 3.0
                if inst.components.combat then
                    inst.components.combat:SetTarget(player)
                end
            else
                next_state = "observe"
                duration = math.random(2.0, 3.0)
            end
        elseif inst._scatter_state == "attack" then
            -- 突击窗口结束（无论中没中），强行脱离索敌并迅速散开
            if inst.components.combat then
                inst.components.combat:DropTarget()
            end
            next_state = "flee"
            duration = math.random(3.0, 5.0)
        end

        inst._scatter_state = next_state
        inst._state_end_time = cur_time + duration
    end
end

function ShadelingScatterBrain:OnStart()
    local root = PriorityNode({
        -- 1. 逃跑态：四散逃避玩家
        WhileNode(function()
            UpdateScatterStateMachine(self.inst)
            return self.inst._scatter_state == "flee"
        end, "FleeFromPlayer",
            RunAway(self.inst, "player", self.inst._flee_dist or 8.0, (self.inst._flee_dist or 8.0) + 3.0)
        ),

        -- 2. 观察态：保持身位，正对玩家静止窥探
        WhileNode(function()
            return self.inst._scatter_state == "observe" and GetPlayer(self.inst) ~= nil
        end, "ObservePlayer",
            FaceEntity(self.inst, GetPlayer, function() return true end)
        ),

        -- 3. 突袭态：集中索敌突刺
        WhileNode(function()
            return self.inst._scatter_state == "attack"
                and self.inst.components.combat
                and self.inst.components.combat.target ~= nil
        end, "AttackPlayer",
            ChaseAndAttack(self.inst, 3.5, 8.0)
        ),

        -- 4. 游走态：无规则乱窜
        Wander(self.inst, function() return self.inst:GetPosition() end, 8.0),
    }, 0.2)

    self.bt = BT(self.inst, root)
end

return ShadelingScatterBrain