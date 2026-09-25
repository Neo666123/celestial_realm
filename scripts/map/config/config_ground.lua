local ConfigGround = {
    schema_version = 1,
    layer_type = "ground", -- 标明这是基础地面图层
    unknown_color_policy = "warn",
    reserved_colors = {},

    -- 常驻月岩地皮 (100% 出现)
    ["#76a88c"] = {
        tiers = {
            [1] = {
                tile = "METEOR",
                dis = 1,
                require_solid = false,
            },
        },
    },
    -- 常驻月岩地皮 (100% 出现)
    ["#9bb2b3"] = {
        tiers = {
            [1] = {
                tile = "CC_METEOR",
                dis = 1,
                require_solid = false,
            },
        },
    },


    -- 基础泥土地皮 (允许向虚空铺设)
    ["#4e5959"] = {
        tiers = {
            [1] = {
                tile = "DIRT",
                dis = nil,
                require_solid = false,
            },
        },
    },

    -- 浮岛色号：70% 几率在虚空生成 CC_METEOR
    ["#8ea2a3"] = {
        tiers = {
            [1] = {
                tile = "CC_METEOR",
                chance = 0.70,
                dis = 1,
                require_solid = false,
            },
        },
    },

    -- 浮岛色号：50% 几率在虚空生成 CC_METEOR
    ["#7a8b8c"] = {
        tiers = {
            [1] = {
                tile = "CC_METEOR",
                chance = 0.50,
                dis = 1,
                require_solid = false,
            },
        },
    },

    -- 浮岛色号：25% 几率在虚空生成 CC_METEOR
    ["#626f70"] = {
        tiers = {
            [1] = {
                tile = "CC_METEOR",
                chance = 0.25,
                dis = 1,
                require_solid = false,
            },
        },
    },

    -- 双子岛 A & B
    ["#7bb5b8"] = {
        tiers = {
            [1] = {
                tile = "CC_METEOR",
                chance = 0.50,
                dis = 3,
                require_solid = false,
            },
        },
    },
    ["#7190ad"] = {
        tiers = {
            [1] = {
                tile = "CC_METEOR",
                chance = 0.50,
                dis = 3,
                require_solid = false,
            },
        },
    },
}

return ConfigGround