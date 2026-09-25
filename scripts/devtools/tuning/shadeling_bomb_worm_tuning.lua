local GLOBAL = rawget(_G, "GLOBAL") or _G
local rawset = GLOBAL.rawset
local rawget = GLOBAL.rawget
local setmetatable = GLOBAL.setmetatable

local BombWormCore = {
    bombHealth     = 100,  -- 1. 背部炸弹生命值 (唯一受击血条)
    bombDamage     = 55,   -- 2. 爆炸范围伤害 (炸到底盘与玩家)
    bombRadius     = 3.2,  -- 3. 爆炸波及半径 (码)
    throwCooldown  = 3.0,  -- 4. 投弹冷却时间 (秒)
    keepDistMin    = 4.0,  -- 5. 安全拉扯距离 (玩家贴近小于此距离时后撤)
    keepDistMax    = 7.0,  -- 6. 理想投弹射程 (在此射程内停步架炮)
    chassisHealth  = 200,  -- 7. 虫体底盘生命值 (仅吃爆炸伤害)
    moveSpeed      = 6.5,  -- 8. 底盘行军移速
    animSpeed      = 2.0,  -- 9. 动画倍速
    segmentSpacing = 0.5,  -- 10. 节段铰链间距 (码)
}

rawset(GLOBAL, "BombWormCoreSettings", BombWormCore)

local Appliers = {
    bombHealth     = function(e, v) e._bomb_health = v end,
    bombDamage     = function(e, v) e._bomb_damage = v end,
    bombRadius     = function(e, v) e._bomb_radius = v end,
    throwCooldown  = function(e, v)
        if e.components.combat then e.components.combat:SetAttackPeriod(v) end
    end,
    keepDistMin    = function(e, v) e._keep_dist_min = v end,
    keepDistMax    = function(e, v)
        if e.components.combat then e.components.combat:SetRange(v, v + 2.0) end
    end,
    chassisHealth  = function(e, v)
        if e.components.health then
            local pct = e.components.health:GetPercent()
            e.components.health:SetMaxHealth(v)
            e.components.health:SetPercent(pct)
        end
    end,
    moveSpeed      = function(e, v)
        if e.components.locomotor then
            e.components.locomotor.walkspeed = v
            e.components.locomotor.runspeed = v
        end
    end,
    animSpeed      = function(e, v)
        if e.AnimState then e.AnimState:SetDeltaTimeMultiplier(v) end
    end,
    segmentSpacing = function(e, v) e._segment_spacing = v end,
}

local function ApplyBombWormTuning(inst)
    if not (inst and inst:IsValid()) then return end
    for key, fn in GLOBAL.pairs(Appliers) do
        if BombWormCore[key] ~= nil then
            fn(inst, BombWormCore[key])
        end
    end
end
rawset(GLOBAL, "ApplyBombWormTuning", ApplyBombWormTuning)

local function BroadcastUpdate(key, value)
    local Ents = rawget(GLOBAL, "Ents")
    if not Ents then return end
    local fn = Appliers[key]
    if not fn then return end

    for _, ent in GLOBAL.pairs(Ents) do
        if ent and ent:IsValid() and (ent:HasTag("shadeling_bomb_worm") or ent:HasTag("shadeling_bomb_worm_seg")) then
            fn(ent, value)
        end
    end
end

local BombWormProxy = setmetatable({}, {
    __index = function(_, k)
        return BombWormCore and BombWormCore[k]
    end,
    __newindex = function(_, k, v)
        v = GLOBAL.tonumber(v) or v
        if BombWormCore then
            BombWormCore[k] = v
        end
        BroadcastUpdate(k, v)
    end,
})

local InspectorRegistry = rawget(GLOBAL, "InspectorRegistry")
if InspectorRegistry then
    local Meta = {
        _title         = "深渊炸弹列车",
        _var_name      = "BombWormCore",
        bombHealth     = "1. 背部炸弹生命值",
        bombDamage     = "2. 爆炸范围伤害",
        bombRadius     = "3. 爆炸波及半径",
        throwCooldown  = "4. 投弹冷却时间 (秒)",
        keepDistMin    = "5. 最小拉扯距离 (码)",
        keepDistMax    = "6. 最佳架炮距离 (码)",
        chassisHealth  = "7. 底盘生命值",
        moveSpeed      = "8. 底盘行军移速",
        animSpeed      = "9. 动画倍速",
        segmentSpacing = "10. 节段轴距 (码)",
    }
    InspectorRegistry:Register("BombWormSettings", BombWormProxy, Meta)
end