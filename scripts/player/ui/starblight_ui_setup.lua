local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G

local UIAnim = rawget(GLOBAL, "require")("widgets/uianim")

-- 1. 注册纯净组件名 starblight
AddPlayerPostInit(function(inst)
    inst:AddComponent("starblight")
end)

-- 2. 注入血球 UI
AddClassPostConstruct("widgets/healthbadge", function(self)
    local owner = self.owner
    if not owner then return end

    local starblight_fx = self.underNumber:AddChild(UIAnim())
    starblight_fx:GetAnimState():SetBank("status_starblight")
    starblight_fx:GetAnimState():SetBuild("status_starblight")
    starblight_fx:GetAnimState():AnimateWhilePaused(false)
    starblight_fx:SetClickable(false)
    starblight_fx:SetScale(1, 1, 1)
    starblight_fx:Hide()
    self.starblight_fx = starblight_fx

    if self.circleframe2 then
        self.circleframe2:MoveToFront()
    end
    if self.sanityarrow then
        self.sanityarrow:MoveToFront()
    end

    local function UpdateStarblightVisual(level)
        if not self.starblight_fx then return end
        if level and level > 0 then
            self.starblight_fx:Show()
            local anim_index = math.clamp(level - 1, 0, 4)
            self.starblight_fx:GetAnimState():PlayAnimation("starblight_" .. tostring(anim_index), true)
        else
            self.starblight_fx:Hide()
        end
    end

    self.inst:ListenForEvent("starblight_level_dirty", function()
        local net_level = owner._starblight_level
        local level = net_level and net_level:value() or 0
        UpdateStarblightVisual(level)

        if owner.replica and owner.replica.health then
            local current = owner.replica.health:GetCurrent()
            local max = owner.replica.health:Max()
            local penalty = owner.replica.health:GetPenaltyPercent()
            self:SetPercent(current / max, max, penalty)
        end
    end, owner)

    local old_SetPercent = self.SetPercent
    self.SetPercent = function(badge_inst, val, max, penaltypercent)
        local net_level = owner._starblight_level
        local level = net_level and net_level:value() or 0

        local clamped_val = val
        if level > 0 then
            local cap_percent = math.max(0, 1 - (level * 0.2))
            clamped_val = math.min(val, cap_percent)
        end

        return old_SetPercent(badge_inst, clamped_val, max, penaltypercent)
    end
end)