local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G

local net_smallbyte = rawget(GLOBAL, "net_smallbyte")
local TheWorld = rawget(GLOBAL, "TheWorld")

local Starblight = Class(function(self, inst)
    self.inst = inst
    self.max_level = 5
    self.current_level = 0

    -- 双端网络同步变量 (0 ~ 5)，直接挂在 inst 上供客户端 UI 读取
    self._net_level = net_smallbyte(inst.GUID, "starblight.level", "starblight_level_dirty")
    self._net_level:set(0)
    inst._starblight_level = self._net_level

    if not TheWorld.ismastersim then
        return
    end

    self._on_attacked = function(owner, data)
        if owner:HasTag("playerghost") then return end
        if data and data.damage and data.damage > 0 then
            self:DoDelta(1)
        end
    end
    self.inst:ListenForEvent("attacked", self._on_attacked)

    self._on_death = function()
        self:SetLevel(0)
    end
    self.inst:ListenForEvent("death", self._on_death)
end)

function Starblight:OnRemoveFromEntity()
    if self._on_attacked then
        self.inst:RemoveEventCallback("attacked", self._on_attacked)
    end
    if self._on_death then
        self.inst:RemoveEventCallback("death", self._on_death)
    end
end

function Starblight:GetLevel()
    return self.current_level
end

function Starblight:SetLevel(level)
    local old_level = self.current_level
    self.current_level = math.clamp(level, 0, self.max_level)

    self._net_level:set(self.current_level)

    self.inst:PushEvent("starblight_delta", {
        old_level = old_level,
        new_level = self.current_level,
        max_level = self.max_level,
    })

    if self.inst.components.health then
        self.inst.components.health:ForceUpdateHUD(false)
    end

    if self.current_level >= self.max_level then
        self:TriggerSuffocationDeath()
    end
end

function Starblight:DoDelta(delta)
    self:SetLevel(self.current_level + delta)
end

function Starblight:TriggerSuffocationDeath()
    local health = self.inst.components.health
    if health and not health:IsDead() then
        health.deathcause = "STARBLIGHT_SUFFOCATION"
        health:Kill()
    end
end

function Starblight:GetAvailablePercentCap()
    return math.max(0, 1 - (self.current_level * 0.2))
end

function Starblight:OnSave()
    return {
        level = self.current_level > 0 and self.current_level or nil,
    }
end

function Starblight:OnLoad(data)
    if data and data.level then
        self:SetLevel(data.level)
    end
end

return Starblight