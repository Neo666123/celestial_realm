local CelestialIslands = {}
local _G = rawget(_G, "GLOBAL") or _G

CelestialIslands.CustomTasks = {
    "Rift_Celestial_Domain",
}

CelestialIslands.VoidTaskPrefixes = {
    "Rift_Celestial",
}

function CelestialIslands.Init(env)
    local AddRoom = env.AddRoom or _G.AddRoom
    local AddTask = env.AddTask or _G.AddTask
    local WORLD_TILES = _G.WORLD_TILES
    local KEYS = _G.KEYS

    -- 1. 外围裂隙海滩
    AddRoom("Rift_Mush_Beach", {
        colour = { r = 0.1, g = 0.1, b = 0.8, a = 0.9 },
        value = WORLD_TILES.FUNGUSMOON,
        contents = {
            countprefabs = {
                moonspiderden = 1,
                archive_moon_statue = 1,
            },
            distributepercent = 0.18,
            distributeprefabs = {
                trap_starfish = 0.75,
                bullkelp_beachedroot = 1.25,
                lunar_island_rocks = 0.5,
                evergreen = 0.2,
            },
        },
    })

    -- 2. 裂隙真菌林
    AddRoom("Rift_Mush_Forest", {
        colour = { r = 0.1, g = 0.1, b = 0.8, a = 0.9 },
        value = WORLD_TILES.FUNGUSMOON,
        contents = {
            countprefabs = {
                champion = function(area) return math.max(1, math.floor(area / 60)) end,
                archive_moon_statue = 1,
            },
            distributepercent = 0.22,
            distributeprefabs = {
                evergreen = 0.6,
                sapling_moon = 0.3,
                carrat_planted = 0.15,
                moon_fissure = 0.1,
            },
        },
    })

    -- 3. 裂隙深层真菌腹地
    AddRoom("Rift_Mush_DeepForest", {
        colour = { r = 0.1, g = 0.1, b = 0.8, a = 0.9 },
        value = WORLD_TILES.FUNGUSMOON,
        contents = {
            countprefabs = {
                champion = 1,
                archive_moon_statue = 1,
            },
            distributepercent = 0.25,
            distributeprefabs = {
                evergreen = 0.7,
                sapling_moon = 0.4,
                moon_fissure = 0.2,
            },
        },
    })

    -- 4. 裂隙分支哨所
    AddRoom("Rift_Celestial_Outpost", {
        colour = { r = 0.2, g = 0.2, b = 0.9, a = 0.9 },
        value = WORLD_TILES.FUNGUSMOON,
        contents = {
            countprefabs = {
                champion = 2,
                archive_moon_statue = 1,
            },
            distributepercent = 0.15,
            distributeprefabs = {
                moon_fissure = 0.8,
                evergreen = 0.3,
            },
        },
    })

    -- 5. 天体核心主战场
    AddRoom("Rift_Celestial_Arena", {
        colour = { r = 0.3, g = 0.1, b = 0.9, a = 0.9 },
        value = WORLD_TILES.FUNGUSMOON,
        contents = {
            countprefabs = {
                moon_altar_rock_seed = 1,
                champion = 2,
                archive_moon_statue = 2,
            },
            distributepercent = 0.15,
            distributeprefabs = {
                moon_fissure = 1.0,
            },
        },
    })

    -- 6. 裂隙天域任务（纯净 15 间配置，无虚空 Cove 干扰）
    AddTask("Rift_Celestial_Domain", {
        locks = {},
        keys_given = { KEYS.ISLAND_TIER2 },
        region_id = "rift_island",
        level_set_piece_blocker = true,
        room_tags = { "RoadPoison", "nohunt", "nohasslers", "lunacyarea", "not_mainland" },
        room_choices = {
            ["Rift_Mush_Beach"] = 4,
            ["Rift_Mush_Forest"] = 5,
            ["Rift_Mush_DeepForest"] = 3,
            ["Rift_Celestial_Outpost"] = 2,
            ["Rift_Celestial_Arena"] = 1,
        },
        room_bg = WORLD_TILES.FUNGUSMOON,
        background_room = "Rift_Mush_Forest",
        make_loop = false,
        crosslink_factor = 2,
        colour = { r = 0.3, g = 0.4, b = 0.8, a = 1 },
    })
end

return CelestialIslands