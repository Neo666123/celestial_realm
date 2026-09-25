local ConfigLayouts = {
    schema_version = 1,
    layer_type = "layouts", -- 标明这是实体布局图层
    unknown_color_policy = "warn",
    reserved_colors = {},

    -- ------------------------------------------------------------------------
    -- 1. 草地生态散布 (合并了旧版的 mask + 种类分配)
    -- ------------------------------------------------------------------------
    -- 矮草带：纯刷 short_grass
    ["#83a656"] = {
        tiers = {
            [1] = {
                dis = 1,
                prefab = {
                    distribute = { ["short_grass"] = 1.0 },
                    density = 0.15, -- 作用于 1x1 物理子格
                },
            },
        },
    },

    -- 雪草带：纯刷 snow_grass
    ["#547c8c"] = {
        tiers = {
            [1] = {
                dis = 1,
                prefab = {
                    distribute = { ["snow_grass"] = 1.0 },
                    density = 0.15,
                },
            },
        },
    },

    -- 混合草带：按 1:1 比例混刷矮草与雪草
    ["#7d548c"] = {
        tiers = {
            [1] = {
                dis = 1,
                prefab = {
                    distribute = {
                        ["short_grass"] = 0.5,
                        ["snow_grass"] = 0.5,
                    },
                    density = 0.20,
                },
            },
        },
    },

    -- ------------------------------------------------------------------------
    -- 2. 桥桩特种规则 (保留射线物理检测)
    -- ------------------------------------------------------------------------
    -- 常驻桥桩：射线探测 1~10 格虚空对岸
    ["#e09b08"] = {
        tiers = {
            [1] = {
                prefab = "cc_brigdepost",
                rule = "raycast_bridge",
                dis=2,
                min_gap = 1,
                max_gap = 10,
            },
        },
    },

    -- 概率成对桥桩：双向握手，30% 几率成对生成
    ["#a97609"] = {
        tiers = {
            [1] = {
                prefab = "cc_brigdepost",
                rule = "paired_bridge",
                min_gap = 1,
                max_gap = 10,
                dis=2,
                pair_chance = 0.30,
            },
        },
    },

    -- ------------------------------------------------------------------------
    -- 3. 全局核心设施
    -- ------------------------------------------------------------------------
    -- 天界传送门：全图候选点合为大组 (dis = nil)，纯定量保底刷新 1 个
    ["#008079"] = {
        tiers = {
            [1] = {
                dis = nil,
                prefab = {
                    count = { ["portal_exit"] = 1 },
                },
            },
        },
    },
}

return ConfigLayouts