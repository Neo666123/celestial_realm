local ConfigBlueprints = {

    -- 示例蓝图：微型神殿
    ["mini_shrine"] = {
        data_path = "map/mapdata/blueprints/bp_mini_shrine_data",
        solver = "4x4",

        -- 1. 地皮图层
        ground = {
            ["#76a88c"] = {
                tiers = {
                    [1] = { tile = "METEOR", dis = 1 },
                    [2] = { tile = "METEORCOAST_NOISE", dis = 1 },
                },
            },
        },

        -- 2. 实体/生物/复合节点图层
        prefab = {
            -- 示例 A：神殿宝箱（纯单体实体生成）
            ["#e09b08"] = {
                tiers = {
                    [1] = {
                        prefab = "chest",
                        dis = 0,
                        mode = "min",
                        count = 1,
                        chance = 0.0,
                        require_solid = true,
                    },
                },
            },

            -- 示例 B：神殿守护者（带间距排斥的群体实体）
            ["#008079"] = {
                tiers = {
                    [1] = {
                        prefab = "celestial_treant",
                        dis = 1,
                        mode = "min",
                        count = 2,
                        chance = 0.50,
                        spacing = 1.0,
                        jitter = 0.1,
                        require_solid = true,
                    },
                },
            },

            -- 示例 C：复合原子节点（同时配置 tile + prefab + blueprint）
            -- 当触发 blueprint 时，蓝图直接在此点盖章，并完全抑制宝箱生成，防止穿模
            ["#9b59b6"] = {
                tiers = {
                    [1] = {
                        tile = "METEOR",               -- 1. 先铺底地皮
                        prefab = "chest",              -- 2. 备用单体实体
                        blueprint = "sub_altar",       -- 3. 顶层子神殿蓝图（生效则完全覆盖抑制 chest）

                        dis = nil,
                        mode = "min",
                        count = 1,
                        chance = 0.0,
                        require_solid = true,
                    },
                },
            },
        },
    },

}

return ConfigBlueprints