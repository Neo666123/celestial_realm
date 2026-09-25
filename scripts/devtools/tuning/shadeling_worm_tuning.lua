local GLOBAL = rawget(_G, "GLOBAL") or _G
local rawset = GLOBAL.rawset
local rawget = GLOBAL.rawget
local setmetatable = GLOBAL.setmetatable

-- ==========================================================
-- 1. 核心数值底表
-- ==========================================================
local WormHeadCore = {
    animSpeed      = 2,     -- 7. 动画倍速 (默认2.0)
    attackPeriod   = 1.5,   -- 3. 攻击间隔 (秒)
    attackRange    = 1.2,   -- 4. 攻击判定范围 (码)
    damage         = 20,    -- 2. 撕咬伤害
    loseTargetDist = 14,    -- 12. 脱战距离 (码)
    maxHealth      = 350,   -- 1. 头部生命值
    moveSpeed      = 8,     -- 5. 爬行移速
    scale          = 0.9,   -- 6. 头部大小
    segmentCount   = 7,     -- 8. 身体节数
    segmentSpacing = 0.5,   -- 9. 关节轴距 (码)
    targetDist     = 14,    -- 11. 索敌距离 (码)
    turnSpeed      = 300,   -- 10. 转向角速度
}

local WormSegmentCore = {
    scale          = 0.85,  -- 1. 躯干节模型大小
    animSpeed      = 2.0,   -- 2. 动画播放倍速
    scatterSpeed   = 7.0,   -- 3. 散开后的疾跑移速
    fleeDist       = 8.0,   -- 4. 观察/逃逸安全距离 (码)
    attackDuration = 3.0,   -- 5. 突刺追击持续时长 (秒)
}

rawset(GLOBAL, "WormHeadCoreSettings", WormHeadCore)
rawset(GLOBAL, "WormSegmentCoreSettings", WormSegmentCore)

-- ==========================================================
-- 2. 规则说明书：数值注入映射闭包
-- ==========================================================
local HeadAppliers = {
    maxHealth = function(e, v)
        if e.components.health then
            local current_pct = e.components.health:GetPercent()
            e.components.health:SetMaxHealth(v)
            e.components.health:SetPercent(current_pct)
        end
    end,
    damage = function(e, v)
        if e.components.combat then e.components.combat:SetDefaultDamage(v) end
    end,
    attackPeriod = function(e, v)
        if e.components.combat then e.components.combat:SetAttackPeriod(v) end
    end,
    attackRange = function(e, v)
        if e.components.combat then e.components.combat:SetRange(v, v + 0.5) end
    end,
    moveSpeed = function(e, v)
        if e.components.locomotor then
            e.components.locomotor.walkspeed = v
            e.components.locomotor.runspeed = v
        end
    end,
    scale = function(e, v)
        if e.Transform then e.Transform:SetScale(v, v, v) end
    end,
    animSpeed = function(e, v)
        if e.AnimState then e.AnimState:SetDeltaTimeMultiplier(v) end
    end,
    segmentCount   = function(e, v) e._segment_count = GLOBAL.math.floor(v) end,
    segmentSpacing = function(e, v) e._segment_spacing = v end,
    turnSpeed      = function(e, v) e._turn_speed = v end,
    targetDist     = function(e, v) e._target_dist = v end,
    loseTargetDist = function(e, v) e._lose_target_dist = v end,
}

local SegmentAppliers = {
    scale = function(e, v)
        if e.Transform then e.Transform:SetScale(v, v, v) end
    end,
    animSpeed = function(e, v)
        if e.AnimState then e.AnimState:SetDeltaTimeMultiplier(v) end
    end,
    scatterSpeed = function(e, v)
        if e.components.locomotor then
            e.components.locomotor.walkspeed = v
            e.components.locomotor.runspeed = v
        end
    end,
    fleeDist       = function(e, v) e._flee_dist = v end,
    attackDuration = function(e, v) e._attack_duration = v end,
}

-- ==========================================================
-- 3. 全局自动注入函数
-- ==========================================================
local function ApplyWormTuning(inst, tag)
    if not (inst and inst:IsValid()) then return end
    local is_head = (tag == "shadeling_worm_head")
    local core = is_head and WormHeadCore or WormSegmentCore
    local appliers = is_head and HeadAppliers or SegmentAppliers

    for key, fn in GLOBAL.pairs(appliers) do
        if core[key] ~= nil then
            fn(inst, core[key])
        end
    end
end
rawset(GLOBAL, "ApplyWormTuning", ApplyWormTuning)

-- ==========================================================
-- 4. 运行时广播刷新器
-- ==========================================================
local function BroadcastUpdate(tag, key, value)
    local Ents = rawget(GLOBAL, "Ents")
    if not Ents then return end
    local appliers = (tag == "shadeling_worm_head") and HeadAppliers or SegmentAppliers
    local fn = appliers[key]
    if not fn then return end

    for _, ent in GLOBAL.pairs(Ents) do
        if ent and ent:IsValid() and ent:HasTag(tag) then
            fn(ent, value)
        end
    end
end

-- ==========================================================
-- 5. 挂载代理并注册 Inspector
-- ==========================================================
local WormHeadProxy = setmetatable({}, {
    __index = function(_, k)
        return WormHeadCore and WormHeadCore[k]
    end,
    __newindex = function(_, k, v)
        v = GLOBAL.tonumber(v) or v
        if WormHeadCore then
            WormHeadCore[k] = v
        end
        BroadcastUpdate("shadeling_worm_head", k, v)
    end,
})

local WormSegmentProxy = setmetatable({}, {
    __index = function(_, k)
        return WormSegmentCore and WormSegmentCore[k]
    end,
    __newindex = function(_, k, v)
        v = GLOBAL.tonumber(v) or v
        if WormSegmentCore then
            WormSegmentCore[k] = v
        end
        BroadcastUpdate("shadeling_worm_segment", k, v)
    end,
})

local InspectorRegistry = rawget(GLOBAL, "InspectorRegistry")
if InspectorRegistry then
    local HeadMeta = {
        _title         = "深渊盲蚕 (头部中枢)",
        _var_name      = "WormHeadCore",
        maxHealth      = "1. 头部生命值",
        damage         = "2. 撕咬伤害",
        attackPeriod   = "3. 攻击间隔 (秒)",
        attackRange    = "4. 攻击判定范围 (码)",
        moveSpeed      = "5. 爬行移速",
        scale          = "6. 头部大小",
        animSpeed      = "7. 动画倍速 (默认2.0)",
        segmentCount   = "8. 身体节数",
        segmentSpacing = "9. 关节轴距 (码)",
        turnSpeed      = "10. 转向角速度",
        targetDist     = "11. 索敌距离 (码)",
        loseTargetDist = "12. 脱战距离 (码)",
    }

    local SegmentMeta = {
        _title         = "深渊盲蚕 (躯干节散开)",
        _var_name      = "WormSegmentCore",
        scale          = "1. 躯干节大小",
        animSpeed      = "2. 动画倍速 (默认2.0)",
        scatterSpeed   = "3. 散开后狂奔移速",
        fleeDist       = "4. 逃逸/观察距离 (码)",
        attackDuration = "5. 突刺追击持续时长 (秒)",
    }

    InspectorRegistry:Register("WormHeadSettings", WormHeadProxy, HeadMeta)
    InspectorRegistry:Register("WormSegmentSettings", WormSegmentProxy, SegmentMeta)
end