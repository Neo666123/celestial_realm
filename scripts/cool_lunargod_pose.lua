local GLOBAL = rawget(_G, "GLOBAL") or _G
local TheInput = rawget(GLOBAL, "TheInput")
local EventHandler = rawget(GLOBAL, "EventHandler")
local State = rawget(GLOBAL, "State")

local MOUSEBUTTON_LEFT = rawget(GLOBAL, "MOUSEBUTTON_LEFT") or 1000
local CONTROL_PRIMARY  = rawget(GLOBAL, "CONTROL_PRIMARY") or 0

-- 配置项：Build名与你的动画动作名
local OVERRIDE_BUILD_NAME = "very_cool"
local OVERRIDE_ANIM_NAME  = "very_cool" -- 请改为在 Spriter 或工具内实际导出的动画名称

-- ==========================================================
-- 空间坐标与状态检查工具
-- ==========================================================
local function IsWilson(player)
    return player and player:IsValid() and player.prefab == "wilson"
end

local function CanPlayCustomAnim(player)
    if not IsWilson(player) then
        return false
    end
    if player:HasTag("playerghost") then
        return false
    end
    if player.sg and (player.sg:HasStateTag("busy") or player.sg:HasStateTag("dead")) then
        return false
    end
    return true
end

local function GetMouseTargetPos(player)
    if TheInput and TheInput.GetWorldPosition then
        local pt = TheInput:GetWorldPosition()
        if pt and pt.x and pt.z then
            return pt.x, pt.z
        end
    end
    local px, _, pz = player.Transform:GetWorldPosition()
    return px, pz
end

-- ==========================================================
-- 状态机注册 (Wilson 主机与客户端客机预测)
-- ==========================================================
local function RegisterWilsonAnimState(sg_name)
    AddStategraphPostInit(sg_name, function(sg)
        sg.states["custom_wilson_anim"] = State({
            name = "custom_wilson_anim",
            tags = { "busy", "pausepredict" },

            onenter = function(inst, data)
                data = data or {}
                if inst.components.locomotor then
                    inst.components.locomotor:Stop()
                end

                if data.tx and data.tz then
                    inst:ForceFacePoint(data.tx, 0, data.tz)
                end

                inst.AnimState:AddOverrideBuild(OVERRIDE_BUILD_NAME)
                inst.AnimState:PlayAnimation(OVERRIDE_ANIM_NAME)
            end,

            events = {
                EventHandler("animover", function(inst)
                    if inst.AnimState:AnimDone() then
                        inst.sg:GoToState("idle")
                    end
                end),
            },

            onexit = function(inst)
                inst.AnimState:ClearOverrideBuild(OVERRIDE_BUILD_NAME)
            end,
        })
    end)
end

RegisterWilsonAnimState("wilson")
RegisterWilsonAnimState("wilson_client")

-- ==========================================================
-- 网络 RPC 注册
-- ==========================================================
AddModRPCHandler("WilsonCustomAnim", "TriggerAnim", function(player, tx, tz)
    if CanPlayCustomAnim(player) then
        player.sg:GoToState("custom_wilson_anim", { tx = tx, tz = tz })
    end
end)

local function ExecuteCustomAnim(player)
    if not CanPlayCustomAnim(player) then
        return false
    end

    local tx, tz = GetMouseTargetPos(player)
    player.sg:GoToState("custom_wilson_anim", { tx = tx, tz = tz })

    local mod_rpc = rawget(GLOBAL, "MOD_RPC")
    local SendRpc = rawget(GLOBAL, "SendModRPCToServer")
    if SendRpc and mod_rpc and mod_rpc["WilsonCustomAnim"] and mod_rpc["WilsonCustomAnim"]["TriggerAnim"] then
        SendRpc(mod_rpc["WilsonCustomAnim"]["TriggerAnim"], tx, tz)
    end
    return true
end

-- ==========================================================
-- 拦截控制器与输入
-- ==========================================================
AddComponentPostInit("playercontroller", function(self)
    local _OnControl = self.OnControl
    self.OnControl = function(s, control, down, ...)
        if control == CONTROL_PRIMARY and down and IsWilson(s.inst) then
            if TheInput and TheInput:GetHUDEntityUnderMouse() == nil then
                if ExecuteCustomAnim(s.inst) then
                    return true
                end
            end
        end
        if _OnControl then
            return _OnControl(s, control, down, ...)
        end
    end
end)

if TheInput and TheInput.AddMouseButtonHandler then
    TheInput:AddMouseButtonHandler(function(button, down, x, y)
        local ThePlayer = rawget(GLOBAL, "ThePlayer")
        if button == MOUSEBUTTON_LEFT and down and IsWilson(ThePlayer) then
            if TheInput:GetHUDEntityUnderMouse() ~= nil then
                return false
            end
            if ExecuteCustomAnim(ThePlayer) then
                return true
            end
        end
        return false
    end)
end