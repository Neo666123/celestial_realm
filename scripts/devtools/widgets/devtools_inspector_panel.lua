local GLOBAL = rawget(_G, "GLOBAL") or _G
local Widget = GLOBAL.require("widgets/widget")
local Image = GLOBAL.require("widgets/image")
local Text = GLOBAL.require("widgets/text")
local TextEdit = GLOBAL.require("widgets/textedit")
local TEMPLATES = GLOBAL.require("widgets/redux/templates")
local json = GLOBAL.json
local SAVE_FILE_NAME = "dev_inspector_panel_pos"

local InspectorPanel = GLOBAL.Class(Widget, function(self)
    Widget._ctor(self, "InspectorPanel")

    local w, h = 420, 560

    self:SetVAnchor(GLOBAL.ANCHOR_MIDDLE)
    self:SetHAnchor(GLOBAL.ANCHOR_MIDDLE)
    self:SetScaleMode(GLOBAL.SCALEMODE_PROPORTIONAL)
    self:SetClickable(true)

    self.bg = self:AddChild(Image("images/global.xml", "square.tex"))
    self.bg:SetTint(0, 0, 0, 0.85)
    self.bg:SetSize(w, h)

    self.title = self:AddChild(Text(GLOBAL.BUTTONFONT, 32))
    self.title:SetPosition(0, h / 2 - 30)
    self.title:SetColour(1, 1, 1, 1)
    self.title:SetString("属性调试器 (右键按住拖动)")

    self.header_states = {}

    -- 行组件初始化：只在此处绑定一次原生监听，彻底消除闭包嵌套与卡顿
    local function ItemCtor(context, index)
        local row = Widget("row-"..index)

        row.label = row:AddChild(Text(GLOBAL.BODYTEXTFONT, 22))
        row.label:SetHAlign(GLOBAL.ANCHOR_LEFT)
        row.label:SetRegionSize(210, 40)
        row.label:SetPosition(-80, 0)

        row.input_bg = row:AddChild(Image("images/global.xml", "square.tex"))
        row.input_bg:SetTint(0.15, 0.15, 0.15, 1)
        row.input_bg:SetSize(110, 30)
        row.input_bg:SetPosition(125, 0)

        row.input = row:AddChild(TextEdit(GLOBAL.BODYTEXTFONT, 22, ""))
        row.input:SetRegionSize(100, 30)
        row.input:SetPosition(125, 0)
        row.input:SetEditTextColour(1, 1, 1, 1)
        row.input:SetIdleTextColour(0.85, 0.85, 0.85, 1)
        row.input:SetEditCursorColour(1, 1, 1, 1)
        row.input:SetCharacterFilter("0123456789.-")

        row.input.OnMouseButton = function(w_self, button, down, x, y)
            if button == GLOBAL.MOUSEBUTTON_LEFT and not down then
                if not w_self.editing then
                    w_self:SetEditing(true)
                end
            end
            return true
        end

        -- 单点提交校验：值未改变绝不触发 Proxy 和全图广播
        local function CommitValue(w_self)
            local data = row.data
            if not (data and data.parent and data.key) then return end

            local old_val = data.parent[data.key]
            local new_val = GLOBAL.tonumber(w_self:GetString())

            if new_val ~= nil then
                if old_val ~= new_val then
                    data.parent[data.key] = new_val
                end
                w_self:SetString(GLOBAL.tostring(new_val))
            else
                w_self:SetString(GLOBAL.tostring(old_val))
            end
        end

        row.input.OnTextEntered = function()
            CommitValue(row.input)
            row.input:SetEditing(false)
        end

        row.input.OnLoseFocus = function()
            if row.input.editing then
                row.input:SetEditing(false)
                CommitValue(row.input)
            end
        end

        row.btn = row:AddChild(TEMPLATES.StandardButton(function() end, "", {110, 30}))
        row.btn:SetPosition(125, 0)

        return row
    end

    -- 纯净数据重塑：严禁在此处调用 SetEditing 或重复包装闭包
    local function ApplyFn(context, widget, data, index)
        widget.data = data
        if not data then
            widget:Hide()
            return
        end
        widget:Show()

        widget.input_bg:Hide()
        widget.input:Hide()
        widget.btn:Hide()

        if data.type == "header" then
            widget.label:SetColour(1, 0.82, 0.1, 1)
            widget.label:SetString((data.is_open and "▼ " or "▶ ") .. data.display_name)

            widget.btn:Show()
            widget.btn:SetText(data.is_open and "收起" or "展开")
            widget.btn:SetOnClick(function()
                self.header_states[data.raw_key] = not self.header_states[data.raw_key]
                self:RefreshData()
            end)

        elseif data.type == "number" then
            widget.label:SetColour(1, 1, 1, 1)
            widget.label:SetString("  " .. data.display_name)

            widget.input_bg:Show()
            widget.input:Show()
            widget.input:SetString(GLOBAL.tostring(data.parent[data.key]))

        elseif data.type == "boolean" then
            widget.label:SetColour(1, 1, 1, 1)
            widget.label:SetString("  " .. data.display_name)

            widget.btn:Show()
            widget.btn:SetText(data.parent[data.key] and "是 (True)" or "否 (False)")
            widget.btn:SetOnClick(function()
                data.parent[data.key] = not data.parent[data.key]
                widget.btn:SetText(data.parent[data.key] and "是 (True)" or "否 (False)")
            end)
        end
    end

    -- 视口调优：启用 end_offset = 1 并追加安全余量，杜绝末行切断
    self.scroll_list = self:AddChild(TEMPLATES.ScrollingGrid({}, {
        context = self,
        num_columns = 1,
        num_visible_rows = 9,
        item_ctor_fn = ItemCtor,
        apply_fn = ApplyFn,
        widget_width = 380,
        widget_height = 42,
        end_offset = 1,
        scissor_pad = 6,
    }))
    self.scroll_list:SetPosition(0, 15)

    self.dump_btn = self:AddChild(TEMPLATES.StandardButton(function()
        local Registry = GLOBAL.rawget(GLOBAL, "InspectorRegistry")
        if Registry then
            Registry:Dump()
            if GLOBAL.ThePlayer and GLOBAL.ThePlayer.components.talker then
                GLOBAL.ThePlayer.components.talker:Say("数据已导出至控制台 (~ 键查看)")
            end
        end
    end, "导出配置代码", {240, 36}))
    self.dump_btn:SetPosition(0, - h / 2 + 35)

    self:Hide()
    self:LoadPanelPosition()
end)

function InspectorPanel:RefreshData()
    local InspectorRegistry = GLOBAL.rawget(GLOBAL, "InspectorRegistry")
    if not InspectorRegistry then return end

    local all_data = InspectorRegistry:GetAll()
    local list_data = {}

    for module_name, table_ref in GLOBAL.pairs(all_data) do
        local meta = InspectorRegistry:GetMetadata(module_name)
        local module_title = meta._title or module_name

        if self.header_states[module_name] == nil then
            self.header_states[module_name] = true
        end
        local is_open = self.header_states[module_name]

        GLOBAL.table.insert(list_data, {
            type = "header",
            raw_key = module_name,
            display_name = module_title,
            is_open = is_open
        })

        if is_open then
            local keys = {}
            local seen = {}

            -- 1. 扫描实体实际拥有的键名
            for k, _ in GLOBAL.pairs(table_ref) do
                keys[#keys + 1] = k
                seen[k] = true
            end

            -- 2. 穿透扫描元数据键名，支撑代理虚表
            if meta then
                for k, _ in GLOBAL.pairs(meta) do
                    if GLOBAL.type(k) == "string" and k:sub(1, 1) ~= "_" and not seen[k] then
                        keys[#keys + 1] = k
                        seen[k] = true
                    end
                end
            end

            GLOBAL.table.sort(keys, function(a, b)
                local ma = (meta and meta[a]) or a
                local mb = (meta and meta[b]) or b
                return GLOBAL.tostring(ma) < GLOBAL.tostring(mb)
            end)

            for _, k in GLOBAL.ipairs(keys) do
                local v = table_ref[k]
                if GLOBAL.type(v) == "number" or GLOBAL.type(v) == "boolean" then
                    local label_display = (meta and meta[k]) or k
                    GLOBAL.table.insert(list_data, {
                        type = GLOBAL.type(v),
                        raw_key = k,
                        display_name = label_display,
                        parent = table_ref,
                        key = k
                    })
                end
            end
        end
    end

    self.scroll_list:SetItemsData(list_data)
end

function InspectorPanel:OnShow(was_hidden)
    InspectorPanel._base.OnShow(self, was_hidden)
    self:RefreshData()
end

function InspectorPanel:OnHide(was_visible)
    InspectorPanel._base.OnHide(self, was_visible)
    self:ClearFocus()
end

function InspectorPanel:LoadPanelPosition()
    GLOBAL.TheSim:GetPersistentString(SAVE_FILE_NAME, function(load_success, data)
        if load_success and data ~= nil and data ~= "" then
            local success, pos_data = GLOBAL.pcall(json.decode, data)
            if success and pos_data and pos_data.x and pos_data.y then
                self:SetPosition(pos_data.x, pos_data.y, 0)
            end
        end
    end)
end

function InspectorPanel:SavePanelPosition()
    local pos = self:GetPosition()
    GLOBAL.TheSim:SetPersistentString(SAVE_FILE_NAME, json.encode({ x = pos.x, y = pos.y }), false)
end

function InspectorPanel:StartDrag()
    if not self.followhandler then
        local mousepos = GLOBAL.TheInput:GetScreenPosition()
        self.m_startpos = mousepos
        self.p_startpos = self:GetPosition()

        self.followhandler = GLOBAL.TheInput:AddMoveHandler(function(x, y)
            local current_mouse = GLOBAL.Vector3(x, y, 0)
            local hud_scale = (GLOBAL.TheFrontEnd and GLOBAL.TheFrontEnd:GetHUDScale()) or 1
            local offset = (current_mouse - self.m_startpos) / hud_scale
            self:SetPosition(self.p_startpos + offset)

            if not GLOBAL.TheInput:IsMouseDown(GLOBAL.MOUSEBUTTON_RIGHT) then
                self:EndDrag()
            end
        end)
    end
end

function InspectorPanel:EndDrag()
    if self.followhandler then
        self.followhandler:Remove()
        self.followhandler = nil
    end
    self.m_startpos = nil
    self.p_startpos = nil
    self:SavePanelPosition()
end

-- 修复核心：事件派发链放行，优先保障子控件事件捕获
function InspectorPanel:OnControl(control, down)
    -- 1. 优先放行给子控件（Scrollbar 滑块拖动、ScrollingGrid 滚轮）
    if InspectorPanel._base.OnControl(self, control, down) then
        return true
    end

    -- 2. 面板自身右键按住拖拽移动位置
    if self.focus and control == GLOBAL.CONTROL_SECONDARY then
        if down then self:StartDrag() else self:EndDrag() end
        return true
    end

    -- 3. 仅在焦点处于面板内时阻断按键穿透，防止误触走位
    if self.focus and (control == GLOBAL.CONTROL_PRIMARY or control == GLOBAL.CONTROL_SECONDARY or control == GLOBAL.CONTROL_ACTION) then
        return true
    end

    return false
end

return InspectorPanel