/**
 * ui/ui_plugin_window.js
 * 纯净 Photoshop 扩展悬浮窗 (支持拖拽移动、最小化折叠、插件热切换与第三方脚本注入)
 */

export class PluginWindow {
    constructor(pluginManager, hostAPI) {
        this.pm = pluginManager;
        this.api = hostAPI;
        this.pm.setHostAPI(hostAPI);

        this.container = null;
        this.activeTab = "color_replacer";
        this.isMinimized = false;
        this.isVisible = false;

        this.posX = 320;
        this.posY = 80;
        this.isDragging = false;
        this.dragOffsetX = 0;
        this.dragOffsetY = 0;

        this.initDOM();
    }

    initDOM() {
        const win = document.createElement("div");
        win.id = "ps-plugin-window";
        win.style.cssText = `
            position: absolute;
            left: ${this.posX}px;
            top: ${this.posY}px;
            width: 320px;
            background: rgba(22, 24, 28, 0.95);
            border: 1px solid #374151;
            border-radius: 8px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.6);
            backdrop-filter: blur(10px);
            z-index: 100;
            display: none;
            flex-direction: column;
            overflow: hidden;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            user-select: none;
        `;

        // 1. 窗口标题栏 (支持拖拽)
        const header = document.createElement("div");
        header.style.cssText = `
            padding: 8px 12px;
            background: #1f232b;
            border-bottom: 1px solid #2d3139;
            display: flex;
            justify-content: space-between;
            align-items: center;
            cursor: move;
        `;
        header.innerHTML = `
            <div style="display:flex; align-items:center; gap:6px;">
                <span style="font-size:12px;">🧩</span>
                <span style="font-size:12px; font-weight:600; color:#f1f5f9;">扩展插件面板</span>
            </div>
            <div style="display:flex; gap:6px;">
                <button class="win-btn-min" style="background:none; border:none; color:#94a3b8; cursor:pointer; font-size:12px;" title="最小化/还原">_</button>
                <button class="win-btn-close" style="background:none; border:none; color:#ef4444; cursor:pointer; font-size:12px; font-weight:700;" title="关闭">×</button>
            </div>
        `;

        header.onmousedown = (e) => {
            if (e.target.tagName === "BUTTON") return;
            this.isDragging = true;
            this.dragOffsetX = e.clientX - win.offsetLeft;
            this.dragOffsetY = e.clientY - win.offsetTop;
        };

        window.addEventListener("mousemove", (e) => {
            if (!this.isDragging) return;
            const maxW = window.innerWidth - win.offsetWidth;
            const maxH = window.innerHeight - win.offsetHeight;
            this.posX = Math.max(0, Math.min(maxW, e.clientX - this.dragOffsetX));
            this.posY = Math.max(0, Math.min(maxH, e.clientY - this.dragOffsetY));
            win.style.left = `${this.posX}px`;
            win.style.top = `${this.posY}px`;
        });

        window.addEventListener("mouseup", () => { this.isDragging = false; });

        header.querySelector(".win-btn-close").onclick = () => this.hide();
        header.querySelector(".win-btn-min").onclick = () => this.toggleMinimize();

        win.appendChild(header);

        // 2. 插件选择选项卡
        const tabList = document.createElement("div");
        tabList.className = "plugin-tab-bar";
        tabList.style.cssText = "display:flex; background:#181a1e; border-bottom:1px solid #2d3139; padding:4px 8px; gap:4px; overflow-x:auto;";
        win.appendChild(tabList);

        // 3. 插件挂载工作区
        const body = document.createElement("div");
        body.className = "plugin-body-area";
        body.style.cssText = "padding:12px; min-height:160px;";
        win.appendChild(body);

        this.container = win;
        document.body.appendChild(win);
        this.renderTabs();
    }

    renderTabs() {
        const tabList = this.container.querySelector(".plugin-tab-bar");
        tabList.innerHTML = "";

        const all = this.pm.getAllPlugins();
        all.forEach(p => {
            const isCur = (p.id === this.activeTab);
            const btn = document.createElement("button");
            btn.style.cssText = `padding:3px 8px; font-size:10px; border-radius:4px; border:none; cursor:pointer; background:${isCur ? '#2563eb' : '#22252a'}; color:${isCur ? '#fff' : '#94a3b8'};`;
            btn.innerHTML = `${p.icon || '📦'} ${p.name}`;
            btn.onclick = () => {
                this.activeTab = p.id;
                this.renderTabs();
                this.renderActivePlugin();
            };
            tabList.appendChild(btn);
        });

        // 允许额外新增第三方自定义脚本的专属 Tab
        const addTabBtn = document.createElement("button");
        const isAdd = (this.activeTab === "__add_new");
        addTabBtn.style.cssText = `padding:3px 8px; font-size:10px; border-radius:4px; border:1px dashed #4b5563; cursor:pointer; background:${isAdd ? '#0284c7' : 'transparent'}; color:#38bdf8;`;
        addTabBtn.innerText = "+ 载入脚本";
        addTabBtn.onclick = () => {
            this.activeTab = "__add_new";
            this.renderTabs();
            this.renderCustomScriptLoader();
        };
        tabList.appendChild(addTabBtn);

        this.renderActivePlugin();
    }

    renderActivePlugin() {
        const body = this.container.querySelector(".plugin-body-area");
        if (this.activeTab === "__add_new") {
            this.renderCustomScriptLoader();
            return;
        }

        const plugin = this.pm.getPlugin(this.activeTab);
        if (plugin && plugin.render) {
            plugin.render(body, this.api);
        } else {
            body.innerHTML = `<div style="color:#64748b; font-size:11px;">未选中有效插件</div>`;
        }
    }

    // 自定义插件输入载入界面
    renderCustomScriptLoader() {
        const body = this.container.querySelector(".plugin-body-area");
        body.innerHTML = `
            <div style="display:flex; flex-direction:column; gap:6px; font-size:11px;">
                <div style="color:#94a3b8;">在下方粘贴自定义扩展插件 JS 代码：</div>
                <textarea id="custom-plug-code" style="width:100%; height:110px; background:#111; color:#a7f3d0; border:1px solid #374151; font-family:monospace; font-size:10px; padding:6px; border-radius:4px;" placeholder="pluginManager.register({ id: 'my_tool', name: '我的插件', icon: '⚡', render: (el, api) => { el.innerHTML = 'Hello!'; } });"></textarea>
                <button id="btn-run-custom-plug" style="padding:5px; background:#059669; font-weight:600;">注入并运行扩展插件</button>
            </div>
        `;

        body.querySelector("#btn-run-custom-plug").onclick = () => {
            const code = body.querySelector("#custom-plug-code").value.trim();
            if (!code) return;
            try {
                const runFn = new Function("pluginManager", "api", code);
                runFn(this.pm, this.api);
                alert("插件注入成功！已加入扩展栏。");
                this.renderTabs();
            } catch (err) {
                alert("插件代码执行失败: " + err.message);
            }
        };
    }

    show() {
        this.container.style.display = "flex";
        this.isVisible = true;
        this.renderTabs();
    }

    hide() {
        this.container.style.display = "none";
        this.isVisible = false;
    }

    toggle() {
        if (this.isVisible) this.hide();
        else this.show();
    }

    toggleMinimize() {
        const body = this.container.querySelector(".plugin-body-area");
        const tabs = this.container.querySelector(".plugin-tab-bar");
        this.isMinimized = !this.isMinimized;
        body.style.display = this.isMinimized ? "none" : "block";
        tabs.style.display = this.isMinimized ? "none" : "flex";
    }
}