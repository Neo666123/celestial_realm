local ConfigMutation = {
    schema_version = 1,
    layer_type = "mutation", -- 关键：标明这是变异图层
    unknown_color_policy = "warn",
    reserved_colors = {},

    -- 白区岛屿月岛变异：整块岛屿 15% 几率触发覆盖，未命中保持底层地皮
    ["#76a88c"] = {
        tiers = {
            [1] = {
                tile = "METEOR",
                chance = 0.15,
                dis = 1,
            },
        },
    },
    ["#518468"] = {
        tiers = {
            [1] = {
                tile = "METEOR",
                chance = 0.15,
                dis = 1,
            },
        },
    },

    -- 黑金地皮变异：整块岛屿 20% 几率触发覆盖
    ["#80761c"] = {
        tiers = {
            [1] = {
                tile = "CC_BLACKGOLD",
                chance = 0.20,
                dis = 1,
            },
        },
    },

    -- 黑金地皮高几率变异：整块岛屿 50% 几率触发覆盖
    ["#998d24"] = {
        tiers = {
            [1] = {
                tile = "CC_BLACKGOLD",
                chance = 0.50,
                dis = 1,
            },
        },
    },
}

return ConfigMutation