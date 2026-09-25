local rawget = rawget
local rawset = rawset
local GLOBAL = rawget(_G, "GLOBAL") or _G
local TUNING = rawget(GLOBAL, "TUNING")

local CC_TUNING = {}

-- ==========================================================
-- 1. 记忆系统配置 (配方、文本、抽取权重)
-- ==========================================================
CC_TUNING.MEMORIES = {
    bridge = {
        recipes = { "cc_brigdepost_item", "boards" },
        name    = "筑桥者的记忆",
        desc    = "记录着跨越虚空的古老构件搭建方法。",
        talk    = "我感受到了……那是跨越深渊的记忆。",
        color   = { 0.3, 0.7, 1.0 },
        weight  = 40,
    },
    stove = {
        recipes = { "cc_stove" },
        name    = "乐观主义者的记忆",
        desc    = "记录着在严寒中保存微温的陶炉图纸。",
        talk    = "一点微弱的余温……足以活下去。",
        color   = { 1.0, 0.6, 0.2 },
        weight  = 30,
    },
    armor = {
        recipes = { "armorwood", "armormarble" },
        name    = "胆小鬼的记忆",
        desc    = "记录着用大理石与坚木封闭身躯的防护图纸。",
        talk    = "只要足够坚硬，就不会再受伤害……",
        color   = { 0.75, 0.75, 0.75 },
        weight  = 20,
    },
    ranger = {
        recipes = { "cc_sword" },
        name    = "巡林者的记忆",
        desc    = "记录着劈开雪草与灵巧斩击的剑刃技法。",
        talk    = "剑刃划开风雪的声音……如此清晰。",
        color   = { 0.3, 1.0, 0.5 },
        weight  = 10,
    },
}

-- ==========================================================
-- 2. 陶罐类型与专属奖池配置
-- ==========================================================
CC_TUNING.POTS = {
    -- 普通陶罐
    normal = {
        shards = { min = 1, max = 2 },
        loot_pool = {
            { item = "goldnugget", chance = 0.45, count = { min = 1, max = 1 } },
            {
                chance = 0.30,
                pool = { "flint", "rocks", "twigs", "cutgrass" },
                count = { min = 1, max = 2 },
            },
        },
        memory_chance = 0.15,
    },

    -- 桥梁专属罐
    bridge = {
        shards = { min = 1, max = 3 },
        guaranteed = {
            { item = "cc_membridge", count = 1 },
        },
        loot_pool = {
            { item = "rocks", chance = 0.80, count = { min = 2, max = 4 } },
        },
        memory_chance = 0.0,
    },

    -- 木质陶罐
    wood = {
        shards = { min = 1, max = 2 },
        guaranteed = {
            { item = "boards", count = { min = 1, max = 2 } },
            { item = "log",    count = { min = 2, max = 4 } },
        },
        loot_pool = {},
        memory_chance = 0.05,
    },
}
local rawget = rawget
local rawset = rawset
local GLOBAL = rawget(_G, "GLOBAL") or _G
local TUNING = rawget(GLOBAL, "TUNING")

local CC_TUNING = (TUNING and rawget(TUNING, "CC")) or {}

-- ==========================================================
-- 3. 草类交互、阻力与通用滞留 Buff 接口
-- ==========================================================
CC_TUNING.GRASS = {
    DETECT_RADIUS = 0.9, -- 检测脚底判定半径

    TYPES = {
       -- 1. 雪草：减速 75% (保留 25% 移速)；滞留降温至 1 度锁定 3 秒，满 3 秒后跌入 0 度并锁死在 -20 度
        ["snow_grass"] = {
            speed_mult = 0.25,
            storm_walk = true,
            tag = "snow_grass",
            linger = {
                duration = 3.0,     -- 滞留触发时长（秒）
                interval = 0.2,     -- 高频结算间隔（0.2 秒）
                fn = function(player, dt)
                    local temp_cmp = player.components.temperature
                    if not temp_cmp then return end

                    local tracker = (player._grass_linger_tracker and player._grass_linger_tracker["snow_grass"]) or player
                    local now = (rawget(GLOBAL, "GetTime") and GLOBAL.GetTime()) or 0
                    local cur_temp = temp_cmp:GetCurrent()

                    -- 1. 已跌入 0 度或更低：持续死锁在 -20 度
                    if cur_temp <= 0 then
                        temp_cmp:SetTemperature(-20)
                        tracker.temp1_start_time = nil
                        return
                    end

                    -- 2. 1 度锁定倒计时阶段（锁定 3 秒缓冲）
                    if tracker.temp1_start_time then
                        if (now - tracker.temp1_start_time) < 3.0 then
                            temp_cmp:SetTemperature(1)
                            return
                        else
                            -- 3 秒锁定到期：进入 0 度并直接死锁在 -20 度
                            temp_cmp:SetTemperature(-20)
                            tracker.temp1_start_time = nil
                            return
                        end
                    end

                    -- 3. 正常降温阶段：向 1 度逼近
                    local drop_step = 3
                    if (cur_temp - drop_step) <= 1 then
                        -- 降温触碰或跌破 1 度：强行截断在 1 度并启动 3 秒计时
                        temp_cmp:SetTemperature(1)
                        tracker.temp1_start_time = now
                    else
                        temp_cmp:DoDelta(-drop_step)
                    end
                end,
            },
        },
        -- 2. 矮草：减速 50% (保留 50% 移速)，不触发深雪步态，无负面 Buff
        ["short_grass"] = {
            speed_mult = 0.50,
            storm_walk = false,
            tag = "short_grass",
            linger = nil,
        },

        -- ================= 预留新草空位 =================
        -- 预留空位 1：高深草丛（示例：减速 40%，停留过久触发精神流失）
        ["tall_grass"] = {
            speed_mult = 0.60,
            storm_walk = false,
            tag = "tall_grass",
            linger = {
                duration = 5.0,
                interval = 2.0,
                fn = function(player, dt)
                    if player.components.sanity then
                        player.components.sanity:DoDelta(-2)
                    end
                end,
            },
        },

        -- 预留空位 2：棘刺草（示例：减速 60%，停留直接划伤扣血）
        ["thorn_grass"] = {
            speed_mult = 0.40,
            storm_walk = false,
            tag = "thorn_grass",
            linger = {
                duration = 1.5,
                interval = 1.0,
                fn = function(player, dt)
                    if player.components.health and not player.components.health:IsDead() then
                        player.components.health:DoDelta(-5, nil, "thorn_grass")
                    end
                end,
            },
        },

        -- 3. 默认/未定义草的回退参数
        ["default"] = {
            speed_mult = 0.70,
            storm_walk = false,
            linger = nil,
        },
    },
}

if TUNING then
    rawset(TUNING, "CC", CC_TUNING)
end

return CC_TUNING