--[[
================================================================================
【AI 架构规范与开发指示：数据驱动与 Inspector 联动协议】
================================================================================
致后续接手开发的 AI 协作者：
本项目已全面实行“数据中枢解耦（Data-Driven Decoupling）”架构。在编写或修改 Prefab、
StateGraph (SG)、Brain 及 Tuning 脚本时，必须严格遵守以下准则：

1. 【Prefab 零硬编码原则】
   - 严禁在 Prefab 脚本内部写死攻击力、移速、攻击范围、冷却时间（CD）、模型缩放等数值。
   - Prefab 仅负责挂载基础组件，并在实体初始化末端调用：
     ApplySpiderTuning(inst, "tag_name")
   - 新增属性时，绝对不要修改 Prefab 源码。

2. 【SG / Brain 自洽原则（禁止跨文件嗅探全局表）】
   - 严禁在 SG 或 Brain 中通过 rawget(GLOBAL, "SpiderXXXSettings") 跨文件强读配置表。
   - 基础战斗属性统一读取实体自身组件：
     例如：inst.components.combat.attackrange、inst.components.locomotor.runspeed
   - 技能专属 CD 统一读取实体黑板（Blackboard）：
     例如：inst._skill_interval、inst._charge_attack_range

3. 【参数扩展单点闭环（只改本文件）】
   新增任何参数或技能时，必须且仅需在本文件内执行三步闭环：
   ① 数值声明：在 Core 基础表内声明默认数值。
   ② 注入规则：在 Appliers 字典内注册组件修改闭包或黑板挂载规则。
   ③ 视图元数据：在 Meta 字典中声明对应中文描述，用于 Inspector 面板渲染。

4. 【热更新广播机制】
   - 所有暴露至 Inspector 的控制属性必须由 Proxy 元表派发。
   - 属性值改变时，通过 BroadcastUpdate 遍历 GLOBAL.Ents 精准热更存活实体，禁止全图物理搜寻。
================================================================================
]]

local GLOBAL = rawget(_G, "GLOBAL") or _G
local rawset = GLOBAL.rawset
local rawget = GLOBAL.rawget
local setmetatable = GLOBAL.setmetatable

-- ==========================================================
-- 1. 核心数值底表
-- ==========================================================
local SpiderWarriorCore = {
    skillInterval     = 5.0,  -- 1. 技能出招间隔 (秒)
    chargeAttackRange = 12.0, -- 2. 冲刺判定距离 (码)
    leapAttackRange   = 7.5,  -- 3. 大跳最大距离 (码)
    runSpeed          = 5.0,  -- 4. 奔跑移速
    scale             = 1.15, -- 5. 模型大小
}

local SpiderCore = {
    attackPeriod = 2.5, -- 1. 平A冷却 (秒)
    attackRange  = 0.4, -- 2. 攻击范围 (码)
    runSpeed     = 35,  -- 3. 奔跑移速
    scale        = 0.4, -- 4. 模型大小
    walkTime     = 1,   -- 5. 走动时长 (秒)
    stopTime     = 1,   -- 6. 停顿发呆时长 (秒)
}

rawset(GLOBAL, "SpiderWarriorCoreSettings", SpiderWarriorCore)
rawset(GLOBAL, "SpiderCoreSettings", SpiderCore)

-- ==========================================================
-- 2. 规则说明书：数值注入映射闭包
-- ==========================================================
local WarriorAppliers = {
    skillInterval     = function(e, v) e._skill_interval = v end,
    chargeAttackRange = function(e, v) e._charge_attack_range = v end,
    leapAttackRange   = function(e, v) e._leap_attack_range = v end,
    runSpeed          = function(e, v) if e.components.locomotor then e.components.locomotor.runspeed = v end end,
    scale             = function(e, v) if e.Transform then e.Transform:SetScale(v, v, v) end end,
}

local ScoutAppliers = {
    attackPeriod = function(e, v) if e.components.combat then e.components.combat:SetAttackPeriod(v) end end,
    attackRange  = function(e, v) if e.components.combat then e.components.combat:SetRange(v, v + 0.5) end end,
    runSpeed     = function(e, v) if e.components.locomotor then e.components.locomotor.runspeed = v end end,
    scale        = function(e, v) if e.Transform then e.Transform:SetScale(v, v, v) end end,
    walkTime     = function(e, v) e._walk_time = v end,
    stopTime     = function(e, v) e._stop_time = v end,
}

-- ==========================================================
-- 3. 全局自动注入函数
-- ==========================================================
local function ApplySpiderTuning(inst, tag)
    if not (inst and inst:IsValid()) then return end
    local is_warrior = (tag == "spider_warrior_plus")
    local core = is_warrior and SpiderWarriorCore or SpiderCore
    local appliers = is_warrior and WarriorAppliers or ScoutAppliers

    for key, fn in GLOBAL.pairs(appliers) do
        if core[key] ~= nil then
            fn(inst, core[key])
        end
    end
end
rawset(GLOBAL, "ApplySpiderTuning", ApplySpiderTuning)

-- ==========================================================
-- 4. 运行时广播刷新器
-- ==========================================================
local function BroadcastUpdate(tag, key, value)
    local Ents = rawget(GLOBAL, "Ents")
    if not Ents then return end
    local appliers = (tag == "spider_warrior_plus") and WarriorAppliers or ScoutAppliers
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
local SpiderWarriorProxy = setmetatable({}, {
    __index = function(_, k)
        return SpiderWarriorCore and SpiderWarriorCore[k]
    end,
    __newindex = function(_, k, v)
        v = GLOBAL.tonumber(v) or v
        if SpiderWarriorCore then
            SpiderWarriorCore[k] = v
        end
        BroadcastUpdate("spider_warrior_plus", k, v)
    end
})

local SpiderProxy = setmetatable({}, {
    __index = function(_, k)
        return SpiderCore and SpiderCore[k]
    end,
    __newindex = function(_, k, v)
        v = GLOBAL.tonumber(v) or v
        if SpiderCore then
            SpiderCore[k] = v
        end
        BroadcastUpdate("spider_plus_scout", k, v)
    end
})

local InspectorRegistry = rawget(GLOBAL, "InspectorRegistry")
if InspectorRegistry then
    local SpiderWarriorMeta = {
        _title            = "大蜘蛛 (战兵)",
        _var_name         = "SpiderWarriorCore",
        skillInterval     = "1. 技能出招间隔 (秒)",
        chargeAttackRange = "2. 冲刺判定距离 (码)",
        leapAttackRange   = "3. 大跳最大距离 (码)",
        runSpeed          = "4. 奔跑移速",
        scale             = "5. 模型大小",
    }

    local SpiderMeta = {
        _title       = "小蜘蛛 (侦察)",
        _var_name    = "SpiderCore",
        attackPeriod = "1. 平A冷却 (秒)",
        attackRange  = "2. 攻击范围 (码)",
        runSpeed     = "3. 奔跑移速",
        scale        = "4. 模型大小",
        walkTime     = "5. 走动时长 (秒)",
        stopTime     = "6. 停顿发呆时长 (秒)",
    }

    InspectorRegistry:Register("SpiderWarriorSettings", SpiderWarriorProxy, SpiderWarriorMeta)
    InspectorRegistry:Register("SpiderSettings", SpiderProxy, SpiderMeta)
end