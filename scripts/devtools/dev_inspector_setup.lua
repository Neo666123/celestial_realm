local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G

local InspectorPanel = require("devtools/widgets/devtools_inspector_panel")

-- 1. 挂靠至玩家 HUD
AddClassPostConstruct("screens/playerhud", function(self)
    self.dev_inspector_panel = self:AddChild(InspectorPanel())
    self.dev_inspector_panel:SetVAnchor(GLOBAL.ANCHOR_MIDDLE)
    self.dev_inspector_panel:SetHAnchor(GLOBAL.ANCHOR_MIDDLE)
    self.dev_inspector_panel:SetPosition(0, 0)
end)

-- 2. F8 快捷键热键呼出
GLOBAL.TheInput:AddKeyHandler(function(key, down)
    if key == GLOBAL.KEY_F8 and not down then
        local caller = GLOBAL.ThePlayer
        if caller and caller.HUD and caller.HUD.dev_inspector_panel and not caller.HUD:HasInputFocus() then
            if caller.HUD.dev_inspector_panel.shown then
                caller.HUD.dev_inspector_panel:Hide()
            else
                caller.HUD.dev_inspector_panel:Show()
            end
        end
    end
end)

-- 3. /inspector 控制台指令
AddUserCommand("inspector", {
    prettyname = "Dev Inspector",
    desc = "Show or Hide Dev Inspector",
    permission = GLOBAL.COMMAND_PERMISSION.USER,
    slash = true,
    usermenu = false,
    servermenu = false,
    params = {},
    vote = false,
    serverfn = function(params, caller)
        if caller and caller.HUD and caller.HUD.dev_inspector_panel then
            if caller.HUD.dev_inspector_panel.shown then
                caller.HUD.dev_inspector_panel:Hide()
            else
                caller.HUD.dev_inspector_panel:Show()
            end
        end
    end,
})