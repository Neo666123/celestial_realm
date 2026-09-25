local GLOBAL = rawget(_G, "GLOBAL") or _G
local rawget = GLOBAL.rawget
local rawset = GLOBAL.rawset

local TheInput = rawget(GLOBAL, "TheInput")
local State = rawget(GLOBAL, "State")
local FRAMES = rawget(GLOBAL, "FRAMES") or (1 / 30)
local DEGREES = rawget(GLOBAL, "DEGREES") or (math.pi / 180)
local COLLISION = rawget(GLOBAL, "COLLISION")
local SpawnPrefab = rawget(GLOBAL, "SpawnPrefab")
local math = rawget(GLOBAL, "math")

local TRENCH_DEPTH = -10.0

-- ==========================================================
-- 1. 地皮判定：隔离常规海洋 (允许虚空与深渊)
-- ==========================================================
local function IsNormalOceanTile(tile)
    if not tile then return false end
    local TileGroupManager = rawget(GLOBAL, "TileGroupManager")
    if not TileGroupManager then return false end

    if TileGroupManager:IsImpassableTile(tile) then
        return false
    end
    return TileGroupManager:IsOceanTile(tile)
end

-- ==========================================================
-- 2. 状态机：原生 onupdate 逐帧物理瞬移
-- ==========================================================
local function CreateJumpStates()
    local jump_down = State({
        name = "trench_jump_down",
        tags = { "busy", "nopredict", "airborn", "jumping" },

        onenter = function(inst)
            if inst.components.locomotor then
                inst.components.locomotor:Stop()
                inst.components.locomotor:Clear()
            end

            inst.AnimState:PlayAnimation("boat_jump_loop", true)
            inst.SoundEmitter:PlaySound("dontstarve/movement/bodyfall_dirt")

            if inst.Physics then
                inst.Physics:ClearCollisionMask()
            end

            local start_x, start_y, start_z = inst.Transform:GetWorldPosition()
            local rot = inst.Transform:GetRotation() * DEGREES
            local forward_x = math.cos(rot)
            local forward_z = -math.sin(rot)

            local mem = inst.sg.statemem
            mem.start_x = start_x
            mem.start_y = start_y
            mem.start_z = start_z
            mem.target_x = start_x + forward_x * 4.0
            mem.target_z = start_z + forward_z * 4.0
            mem.target_y = TRENCH_DEPTH
            mem.elapsed = 0
            mem.duration = 24 * FRAMES
            mem.apex = 2.0
        end,

        onupdate = function(inst, dt)
            local mem = inst.sg.statemem
            mem.elapsed = mem.elapsed + dt
            local p = math.min(1.0, mem.elapsed / mem.duration)

            local cur_x = mem.start_x + (mem.target_x - mem.start_x) * p
            local cur_z = mem.start_z + (mem.target_z - mem.start_z) * p
            local cur_y = mem.start_y + (mem.target_y - mem.start_y) * p + (4 * mem.apex * p * (1 - p))

            if inst.Physics then
                inst.Physics:Teleport(cur_x, cur_y, cur_z)
            else
                inst.Transform:SetPosition(cur_x, cur_y, cur_z)
            end

            if p >= 1.0 then
                inst:AddTag("in_trench")
                inst._last_valid_trench_x = mem.target_x
                inst._last_valid_trench_z = mem.target_z

                if inst.Physics then
                    inst.Physics:Teleport(mem.target_x, mem.target_y, mem.target_z)
                    inst.Physics:ClearCollisionMask()
                    inst.Physics:CollidesWith(COLLISION.CHARACTERS)
                    inst.Physics:CollidesWith(COLLISION.GIANTS)
                end

                local splash = SpawnPrefab("splash_sink")
                if splash then splash.Transform:SetPosition(mem.target_x, 0, mem.target_z) end
                inst.SoundEmitter:PlaySound("turnoftides/common/together/water/splash/medium")

                inst.sg:GoToState("idle")
            end
        end,

        onexit = function(inst)
            if inst:HasTag("in_trench") then
                if inst.Physics then
                    inst.Physics:ClearCollisionMask()
                    inst.Physics:CollidesWith(COLLISION.CHARACTERS)
                    inst.Physics:CollidesWith(COLLISION.GIANTS)
                end
            else
                if inst.Physics then
                    inst.Physics:ClearCollisionMask()
                    inst.Physics:CollidesWith(COLLISION.WORLD)
                    inst.Physics:CollidesWith(COLLISION.OBSTACLES)
                    inst.Physics:CollidesWith(COLLISION.SMALLOBSTACLES)
                    inst.Physics:CollidesWith(COLLISION.CHARACTERS)
                    inst.Physics:CollidesWith(COLLISION.GIANTS)
                end
            end
        end,
    })

    local jump_up = State({
        name = "trench_jump_up",
        tags = { "busy", "nopredict", "airborn", "jumping" },

        onenter = function(inst)
            if inst.components.locomotor then
                inst.components.locomotor:Stop()
                inst.components.locomotor:Clear()
            end

            inst.AnimState:PlayAnimation("boat_jump_loop", true)

            if inst.Physics then
                inst.Physics:ClearCollisionMask()
            end

            local start_x, start_y, start_z = inst.Transform:GetWorldPosition()
            local rot = inst.Transform:GetRotation() * DEGREES
            local forward_x = math.cos(rot)
            local forward_z = -math.sin(rot)

            local mem = inst.sg.statemem
            mem.start_x = start_x
            mem.start_y = start_y
            mem.start_z = start_z
            mem.target_x = start_x + forward_x * 4.0
            mem.target_z = start_z + forward_z * 4.0
            mem.target_y = 0
            mem.elapsed = 0
            mem.duration = 24 * FRAMES
            mem.apex = 12.0
        end,

        onupdate = function(inst, dt)
            local mem = inst.sg.statemem
            mem.elapsed = mem.elapsed + dt
            local p = math.min(1.0, mem.elapsed / mem.duration)

            local cur_x = mem.start_x + (mem.target_x - mem.start_x) * p
            local cur_z = mem.start_z + (mem.target_z - mem.start_z) * p
            local cur_y = mem.start_y + (mem.target_y - mem.start_y) * p + (4 * mem.apex * p * (1 - p))

            if inst.Physics then
                inst.Physics:Teleport(cur_x, cur_y, cur_z)
            else
                inst.Transform:SetPosition(cur_x, cur_y, cur_z)
            end

            if p >= 1.0 then
                inst:RemoveTag("in_trench")
                inst._last_valid_trench_x = nil
                inst._last_valid_trench_z = nil

                if inst.Physics then
                    inst.Physics:Teleport(mem.target_x, mem.target_y, mem.target_z)
                    inst.Physics:ClearCollisionMask()
                    inst.Physics:CollidesWith(COLLISION.WORLD)
                    inst.Physics:CollidesWith(COLLISION.OBSTACLES)
                    inst.Physics:CollidesWith(COLLISION.SMALLOBSTACLES)
                    inst.Physics:CollidesWith(COLLISION.CHARACTERS)
                    inst.Physics:CollidesWith(COLLISION.GIANTS)
                end

                inst.SoundEmitter:PlaySound("dontstarve/movement/bodyfall_dirt")
                inst.sg:GoToState("idle")
            end
        end,

        onexit = function(inst)
            if inst:HasTag("in_trench") then
                if inst.Physics then
                    inst.Physics:ClearCollisionMask()
                    inst.Physics:CollidesWith(COLLISION.CHARACTERS)
                    inst.Physics:CollidesWith(COLLISION.GIANTS)
                end
            else
                if inst.Physics then
                    inst.Physics:ClearCollisionMask()
                    inst.Physics:CollidesWith(COLLISION.WORLD)
                    inst.Physics:CollidesWith(COLLISION.OBSTACLES)
                    inst.Physics:CollidesWith(COLLISION.SMALLOBSTACLES)
                    inst.Physics:CollidesWith(COLLISION.CHARACTERS)
                    inst.Physics:CollidesWith(COLLISION.GIANTS)
                end
            end
        end,
    })

    return jump_down, jump_up
end

local s_down, s_up = CreateJumpStates()
AddStategraphState("wilson", s_down)
AddStategraphState("wilson", s_up)

local c_down, c_up = CreateJumpStates()
AddStategraphState("wilson_client", c_down)
AddStategraphState("wilson_client", c_up)

-- ==========================================================
-- 3. 溺亡与水体拦截
-- ==========================================================
AddComponentPostInit("drownable", function(self)
    local _ShouldDrown = self.ShouldDrown
    self.ShouldDrown = function(inst_self, ...)
        if inst_self.inst:HasTag("in_trench") then
            return false
        end
        local _, y = inst_self.inst.Transform:GetWorldPosition()
        if y < -0.5 then
            return false
        end
        return _ShouldDrown and _ShouldDrown(inst_self, ...)
    end

    local _ShouldFallInVoid = self.ShouldFallInVoid
    self.ShouldFallInVoid = function(inst_self, ...)
        if inst_self.inst:HasTag("in_trench") then
            return false
        end
        local _, y = inst_self.inst.Transform:GetWorldPosition()
        if y < -0.5 then
            return false
        end
        return _ShouldFallInVoid and _ShouldFallInVoid(inst_self, ...)
    end

    local _IsOverWater = self.IsOverWater
    self.IsOverWater = function(inst_self, ...)
        if inst_self.inst:HasTag("in_trench") then
            return false
        end
        local _, y = inst_self.inst.Transform:GetWorldPosition()
        if y < -0.5 then
            return false
        end
        return _IsOverWater and _IsOverWater(inst_self, ...)
    end
end)

-- ==========================================================
-- 4. 深度维护与常规海洋阻拦
-- ==========================================================
AddPlayerPostInit(function(inst)
    inst:DoPeriodicTask(0, function(player)
        local TheWorld = rawget(GLOBAL, "TheWorld")
        local net = rawget(GLOBAL, "TheNet")
        if not (TheWorld and (TheWorld.ismastersim or (net and net:GetIsServer()))) then
            return
        end

        if player:HasTag("in_trench") and not (player.sg and player.sg:HasStateTag("jumping")) then
            local x, y, z = player.Transform:GetWorldPosition()

            -- 踩到普通海洋时弹回上一个有效深渊坐标
            local tile = TheWorld.Map:GetTileAtPoint(x, 0, z)
            if IsNormalOceanTile(tile) then
                if player._last_valid_trench_x then
                    if player.Physics then
                        player.Physics:Teleport(player._last_valid_trench_x, TRENCH_DEPTH, player._last_valid_trench_z)
                    else
                        player.Transform:SetPosition(player._last_valid_trench_x, TRENCH_DEPTH, player._last_valid_trench_z)
                    end
                    if player.components.locomotor then
                        player.components.locomotor:Stop()
                    end
                end
            else
                player._last_valid_trench_x = x
                player._last_valid_trench_z = z
            end

            -- 深度锁死
            if math.abs(y - TRENCH_DEPTH) > 0.05 then
                if player.Physics then
                    player.Physics:Teleport(x, TRENCH_DEPTH, z)
                else
                    player.Transform:SetPosition(x, TRENCH_DEPTH, z)
                end
            end
        end
    end)
end)

-- ==========================================================
-- 5. 无条件自由切换跳跃
-- ==========================================================
local function ToggleTrenchJump(player)
    if not (player and player:IsValid()) then return end
    if player.sg and player.sg:HasStateTag("busy") then return end

    if player:HasTag("in_trench") then
        player.sg:GoToState("trench_jump_up")
        local ThePlayer = rawget(GLOBAL, "ThePlayer")
        if ThePlayer and ThePlayer == player and ThePlayer.EnableMovementPrediction then
            ThePlayer:EnableMovementPrediction(true)
        end
    else
        player.sg:GoToState("trench_jump_down")
        local ThePlayer = rawget(GLOBAL, "ThePlayer")
        if ThePlayer and ThePlayer == player and ThePlayer.EnableMovementPrediction then
            ThePlayer:EnableMovementPrediction(false)
        end
    end
end

AddModRPCHandler("TrenchTest", "DoJump", ToggleTrenchJump)

if TheInput then
    TheInput:AddKeyDownHandler(rawget(GLOBAL, "KEY_V") or 118, function()
        local ThePlayer = rawget(GLOBAL, "ThePlayer")
        if ThePlayer and ThePlayer.HUD and not ThePlayer.HUD:HasInputFocus() then
            local mod_rpc = rawget(GLOBAL, "MOD_RPC")
            if mod_rpc and mod_rpc["TrenchTest"] and mod_rpc["TrenchTest"]["DoJump"] then
                SendModRPCToServer(mod_rpc["TrenchTest"]["DoJump"])
            end
        end
    end)
end

rawset(GLOBAL, "c_trenchjump", function()
    local player = rawget(GLOBAL, "ThePlayer") or (rawget(GLOBAL, "AllPlayers") and rawget(GLOBAL, "AllPlayers")[1])
    if player then ToggleTrenchJump(player) end
end)