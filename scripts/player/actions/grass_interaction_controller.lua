local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G
local TheSim = rawget(GLOBAL, "TheSim")
local TUNING = rawget(GLOBAL, "TUNING")
local ACTIONS = rawget(GLOBAL, "ACTIONS")
local FRAMES = rawget(GLOBAL, "FRAMES") or (1 / 30)
local AddPlayerPostInit = (env and env.AddPlayerPostInit) or rawget(GLOBAL, "AddPlayerPostInit") or AddPlayerPostInit
local AddStategraphPostInit = (env and env.AddStategraphPostInit) or rawget(GLOBAL, "AddStategraphPostInit") or AddStategraphPostInit

local DEFAULT_DETECT_RADIUS = 0.9
local DEFAULT_TYPES = {
    ["snow_grass"] = { speed_mult = 0.25, storm_walk = true },
    ["short_grass"] = { speed_mult = 0.50, storm_walk = false },
    ["default"] = { speed_mult = 0.70, storm_walk = false },
}

local function GetGrassConfig(grass, type_configs)
    if not (grass and grass:IsValid()) then return nil end
    local prefab = grass.prefab
    if prefab and type_configs[prefab] then
        return type_configs[prefab], prefab
    end
    for key, cfg in pairs(type_configs) do
        if cfg.tag and grass:HasTag(cfg.tag) then
            return cfg, key
        end
    end
    return type_configs["default"], "default"
end

local function HookStormVision(player)
    if player._has_celestial_storm_hook then return end
    player._has_celestial_storm_hook = true

    local old_IsInAnyStormOrCloud = player.IsInAnyStormOrCloud
    player.IsInAnyStormOrCloud = function(inst, ...)
        if inst._in_celestial_storm_grass then
            return true
        end
        if old_IsInAnyStormOrCloud then
            return old_IsInAnyStormOrCloud(inst, ...)
        end
        return false
    end
end

local function HookDoubleSpeedPick(sg)
    local dolongaction_state = sg.states and sg.states["dolongaction"]
    if not dolongaction_state then return end

    local old_enter = dolongaction_state.onenter
    dolongaction_state.onenter = function(p, timeout)
        local ba = p:GetBufferedAction()
        local act_pick = ACTIONS and rawget(ACTIONS, "PICK")
        if ba and act_pick and ba.action == act_pick and ba.target and ba.target:HasTag("short_grass") then
            timeout = 0.5
            p.AnimState:SetDeltaTimeMultiplier(2.0)
            p._short_grass_fast_picking = true
        end
        if old_enter then
            old_enter(p, timeout)
        end
    end

    local old_exit = dolongaction_state.onexit
    dolongaction_state.onexit = function(p)
        if p._short_grass_fast_picking then
            p.AnimState:SetDeltaTimeMultiplier(1.0)
            p._short_grass_fast_picking = nil
        end
        if old_exit then
            old_exit(p)
        end
    end
end

AddStategraphPostInit("wilson", HookDoubleSpeedPick)
AddStategraphPostInit("wilson_client", HookDoubleSpeedPick)

AddPlayerPostInit(function(inst)
    inst._in_celestial_grass = false
    inst._in_celestial_storm_grass = false
    inst._stepped_grass_cache = {}
    inst._grass_linger_tracker = {}
    HookStormVision(inst)

    -- 5 帧周期检测
    local dt = 5 * FRAMES

    inst:DoPeriodicTask(dt, function(player)
        if not (player and player:IsValid()) then return end

        local cc_tuning = TUNING and rawget(TUNING, "CC")
        local grass_tuning = cc_tuning and cc_tuning.GRASS
        local detect_radius = (grass_tuning and grass_tuning.DETECT_RADIUS) or DEFAULT_DETECT_RADIUS
        local type_configs = (grass_tuning and grass_tuning.TYPES) or DEFAULT_TYPES

        local px, _, pz = player.Transform:GetWorldPosition()
        local grasses = TheSim:FindEntities(px, 0, pz, detect_radius, { "cuttable_grass" }, { "INLIMBO", "FX" })

        local current_grass_map = {}
        local active_grass_types = {}
        local min_speed_mult = 1.0
        local has_storm_walk = false

        for _, g in ipairs(grasses) do
            if g:IsValid() then
                current_grass_map[g] = true
                local cfg, type_key = GetGrassConfig(g, type_configs)
                if cfg then
                    active_grass_types[type_key] = cfg
                    local mult = cfg.speed_mult or 1.0
                    if mult < min_speed_mult then
                        min_speed_mult = mult
                    end
                    if cfg.storm_walk then
                        has_storm_walk = true
                    end
                end
            end
        end

        local TheWorld = rawget(GLOBAL, "TheWorld")
        local is_mastersim = TheWorld and TheWorld.ismastersim

        if #grasses > 0 then
            player._in_celestial_grass = true
            player._in_celestial_storm_grass = has_storm_walk

            if player.components and player.components.locomotor then
                player.components.locomotor:SetExternalSpeedMultiplier(player, "celestial_grass_slow", min_speed_mult)
            end
            if player.locomotor then
                player.locomotor:SetExternalSpeedMultiplier(player, "celestial_grass_slow", min_speed_mult)
            end

            if is_mastersim then
                for type_key, cfg in pairs(active_grass_types) do
                    if cfg.linger and cfg.linger.fn then
                        local tracker = player._grass_linger_tracker[type_key] or { time = 0, last_tick = 0 }
                        tracker.time = tracker.time + dt

                        local duration = cfg.linger.duration or 3.0
                        if tracker.time >= duration then
                            local interval = cfg.linger.interval
                            if interval then
                                if (tracker.time - tracker.last_tick) >= interval then
                                    tracker.last_tick = tracker.time
                                    cfg.linger.fn(player, dt)
                                end
                            else
                                cfg.linger.fn(player, dt)
                            end
                        end
                        player._grass_linger_tracker[type_key] = tracker
                    end
                end
            end

            local is_moving = false
            if player.sg then
                is_moving = player.sg:HasStateTag("moving") or player.sg:HasStateTag("running")
            elseif player.Physics then
                local vx, _, vz = player.Physics:GetMotorVel()
                is_moving = (vx ~= 0 or vz ~= 0)
            end

            if is_moving then
                for _, grass in ipairs(grasses) do
                    if grass:IsValid() and grass.AnimState then
                        if not player._stepped_grass_cache[grass] then
                            player._stepped_grass_cache[grass] = true
                            if not grass.AnimState:IsCurrentAnimation("rustle") then
                                grass.AnimState:PlayAnimation("rustle")
                                grass.AnimState:PushAnimation("idle", true)
                            end
                        end
                    end
                end
            end
        else
            player._in_celestial_grass = false
            player._in_celestial_storm_grass = false

            if player.components and player.components.locomotor then
                player.components.locomotor:RemoveExternalSpeedMultiplier(player, "celestial_grass_slow")
            end
            if player.locomotor then
                player.locomotor:RemoveExternalSpeedMultiplier(player, "celestial_grass_slow")
            end
        end

        for type_key, _ in pairs(player._grass_linger_tracker) do
            if not active_grass_types[type_key] then
                player._grass_linger_tracker[type_key] = nil
            end
        end

        for cached_grass, _ in pairs(player._stepped_grass_cache) do
            if not current_grass_map[cached_grass] then
                player._stepped_grass_cache[cached_grass] = nil
            end
        end
    end)
end)