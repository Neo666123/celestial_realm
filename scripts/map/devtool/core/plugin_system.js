/**
 * core/plugin_system.js
 * 纯净扩展插件宿主系统 (Photoshop Extension 架构)：
 * 1. 颜色批量替换器 (Color Batch Replacer)
 * 2. 地图实体与地皮统计仪 (Analytics)
 * 3. 卡片配置克隆器 (Card Config Cloner) - 支持复制属性通道与 data 到其他卡片
 */

export class PluginManager {
    constructor() {
        this.plugins = new Map();
        this.activePluginId = null;
        this.hostAPI = null;
    }

    setHostAPI(api) {
        this.hostAPI = api;
    }

    register(pluginDef) {
        if (!pluginDef || !pluginDef.id) return false;
        this.plugins.set(pluginDef.id, pluginDef);
        if (pluginDef.onInit && this.hostAPI) {
            pluginDef.onInit(this.hostAPI);
        }
        return true;
    }

    unregister(pluginId) {
        const p = this.plugins.get(pluginId);
        if (p && p.onDestroy) p.onDestroy();
        this.plugins.delete(pluginId);
    }

    getAllPlugins() {
        return Array.from(this.plugins.values());
    }

    getPlugin(pluginId) {
        return this.plugins.get(pluginId);
    }
}

export const pluginManager = new PluginManager();

// ----------------------------------------------------------------------------
// 插件 1：卡片配置克隆器 (Card Config Cloner)
// ----------------------------------------------------------------------------
pluginManager.register({
    id: "card_cloner",
    name: "配置卡片克隆",
    icon: "📋",
    description: "将当前或指定卡片的配置项 (地皮/预制体/蓝图/Data) 一键克隆到其他色号",
    render: (mountEl, api) => {
        const layer = api.getActiveLayer();
        const configStore = api.getConfigStore();
        if (!layer) {
            mountEl.innerHTML = `<div style="color:#94a3b8; font-size:11px;">请先在左侧选定一个图层。</div>`;
            return;
        }

        const rules = configStore.getRules(layer.name) || {};
        const colors = Object.keys(rules);

        mountEl.innerHTML = `
            <div style="display:flex; flex-direction:column; gap:8px; font-size:11px;">
                <div style="display:flex; align-items:center; justify-content:space-between;">
                    <span>来源色号:</span>
                    <select id="clone-src-col" style="width:130px; font-family:monospace;">
                        ${colors.map(c => `<option value="${c}">${c}</option>`).join("")}
                    </select>
                </div>
                <div style="display:flex; align-items:center; justify-content:space-between;">
                    <span>目标色号:</span>
                    <input type="text" id="clone-tar-col" placeholder="#xxxxxx" style="width:130px; font-family:monospace; text-align:center;">
                </div>
                <div style="background:#16181b; padding:6px; border-radius:4px; display:flex; flex-direction:column; gap:4px;">
                    <span style="color:#94a3b8; font-weight:600;">克隆通道选项:</span>
                    <label style="display:flex; align-items:center; gap:4px; cursor:pointer;"><input type="checkbox" id="chk-cp-base" checked> Dis / Chance / 防悬空</label>
                    <label style="display:flex; align-items:center; gap:4px; cursor:pointer;"><input type="checkbox" id="chk-cp-tile" checked> 地皮通道 (Tile)</label>
                    <label style="display:flex; align-items:center; gap:4px; cursor:pointer;"><input type="checkbox" id="chk-cp-pf" checked> 预制体通道 (Prefab)</label>
                    <label style="display:flex; align-items:center; gap:4px; cursor:pointer;"><input type="checkbox" id="chk-cp-bp" checked> 蓝图建筑 (Blueprints)</label>
                    <label style="display:flex; align-items:center; gap:4px; cursor:pointer;"><input type="checkbox" id="chk-cp-data" checked> 自定义数据 (Data)</label>
                </div>
                <button id="btn-exec-clone" style="padding:6px; background:#0284c7; font-weight:600;">执行克隆覆盖</button>
            </div>
        `;

        const curActiveColor = (window.__ruleCardHelpers && window.__ruleCardHelpers.getActiveColor()) || colors[0];
        if (curActiveColor) {
            const sel = mountEl.querySelector("#clone-src-col");
            if (sel) sel.value = curActiveColor;
        }

        mountEl.querySelector("#btn-exec-clone").onclick = () => {
            const srcCol = mountEl.querySelector("#clone-src-col").value;
            const tarCol = mountEl.querySelector("#clone-tar-col").value.trim().toLowerCase();

            if (!srcCol || !tarCol || !tarCol.startsWith("#")) {
                alert("请输入合法的目标 Hex 色号 (如 #ff0055)！");
                return;
            }

            const srcConf = rules[srcCol];
            if (!srcConf) {
                alert("来源卡片配置不存在！");
                return;
            }

            api.pushHistory();

            const srcT1 = (srcConf.tiers && srcConf.tiers[1]) ? srcConf.tiers[1] : srcConf;
            rules[tarCol] = rules[tarCol] || { tiers: { 1: {} } };
            const tarT1 = rules[tarCol].tiers ? rules[tarCol].tiers[1] : rules[tarCol];

            if (mountEl.querySelector("#chk-cp-base").checked) {
                tarT1.dis = srcT1.dis;
                tarT1.chance = srcT1.chance;
                tarT1.require_solid = srcT1.require_solid;
            }
            if (mountEl.querySelector("#chk-cp-tile").checked && srcT1.tile) {
                tarT1.tile = JSON.parse(JSON.stringify(srcT1.tile));
            }
            if (mountEl.querySelector("#chk-cp-pf").checked && srcT1.prefab) {
                tarT1.prefab = JSON.parse(JSON.stringify(srcT1.prefab));
                if (srcT1.icons) tarT1.icons = JSON.parse(JSON.stringify(srcT1.icons));
            }
            if (mountEl.querySelector("#chk-cp-bp").checked) {
                if (srcT1.blueprint) tarT1.blueprint = srcT1.blueprint;
                if (srcT1.blueprints) tarT1.blueprints = JSON.parse(JSON.stringify(srcT1.blueprints));
            }
            if (mountEl.querySelector("#chk-cp-data").checked && srcT1.data) {
                tarT1.data = JSON.parse(JSON.stringify(srcT1.data));
            }

            if (window.__ruleCardHelpers) {
                window.__ruleCardHelpers.setActiveColor(tarCol);
            }

            api.refreshUI();
            alert(`已成功将 [${srcCol}] 的配置克隆到 [${tarCol}]！`);
        };
    }
});

// ----------------------------------------------------------------------------
// 插件 2：颜色批量替换器
// ----------------------------------------------------------------------------
pluginManager.register({
    id: "color_replacer",
    name: "颜色批量替换",
    icon: "🎨",
    description: "将当前图层或全选区内的某种颜色一键批量替换为新颜色",
    render: (mountEl, api) => {
        mountEl.innerHTML = `
            <div style="display:flex; flex-direction:column; gap:8px; font-size:11px;">
                <div style="display:flex; align-items:center; justify-content:space-between;">
                    <span>原色 (需替换):</span>
                    <input type="text" id="plug-rep-old" placeholder="#xxxxxx" style="width:90px; text-align:center;">
                </div>
                <div style="display:flex; align-items:center; justify-content:space-between;">
                    <span>目标新颜色:</span>
                    <input type="text" id="plug-rep-new" placeholder="#xxxxxx" style="width:90px; text-align:center;">
                </div>
                <label style="display:flex; align-items:center; gap:4px; cursor:pointer;">
                    <input type="checkbox" id="plug-rep-sel-only"> 仅作用于当前选区内部
                </label>
                <button id="plug-rep-btn" style="padding:6px; background:#2563eb; font-weight:600;">执行批量替换</button>
            </div>
        `;

        const curLayer = api.getActiveLayer();
        if (curLayer && curLayer.uniqueColors && curLayer.uniqueColors[0]) {
            mountEl.querySelector("#plug-rep-old").value = curLayer.uniqueColors[0];
        }
        const paintEngine = api.getPaintEngine();
        if (paintEngine) {
            mountEl.querySelector("#plug-rep-new").value = paintEngine.currentColor;
        }

        mountEl.querySelector("#plug-rep-btn").onclick = () => {
            const oldCol = mountEl.querySelector("#plug-rep-old").value.trim().toLowerCase();
            const newCol = mountEl.querySelector("#plug-rep-new").value.trim().toLowerCase();
            const selOnly = mountEl.querySelector("#plug-rep-sel-only").checked;
            const layer = api.getActiveLayer();

            if (!layer || !oldCol || !newCol) {
                alert("请输入完整有效的 Hex 色号！");
                return;
            }

            api.pushHistory();
            const selEngine = api.getSelection();
            let count = 0;

            for (let y = 1; y <= layer.height; y++) {
                const row = layer.grid[y];
                if (!row) continue;
                for (let x = 1; x <= layer.width; x++) {
                    if (selOnly && !selEngine.isSelected(x, y)) continue;
                    const cell = row[x];
                    const c = (typeof cell === "object") ? cell?.color : cell;
                    if (c && c.toLowerCase() === oldCol) {
                        if (typeof cell === "object") cell.color = newCol;
                        else row[x] = newCol;
                        count++;
                    }
                }
            }

            api.syncColors(layer);
            api.invalidateBake();
            api.refreshUI();
            alert(`替换完成！共修改了 ${count} 个像素。`);
        };
    }
});

// ----------------------------------------------------------------------------
// 插件 3：地图实体统计仪
// ----------------------------------------------------------------------------
pluginManager.register({
    id: "map_analytics",
    name: "地图实体与地皮统计",
    icon: "📊",
    description: "实时统计当前生成结果中的实体落地总数",
    render: (mountEl, api) => {
        const sim = api.getSimulationData();
        if (!sim || !sim.entities) {
            mountEl.innerHTML = `<div style="color:#94a3b8; font-size:11px;">请先开启“地图生成模拟”以计算数据。</div>`;
            return;
        }

        const counts = {};
        sim.entities.forEach(e => { counts[e.prefab] = (counts[e.prefab] || 0) + 1; });

        let listHtml = "";
        for (const [name, num] of Object.entries(counts)) {
            listHtml += `<div style="display:flex; justify-content:space-between; margin-bottom:3px;"><span style="color:#cbd5e1;">${name}:</span><span style="font-weight:700; color:#38bdf8;">${num} 个</span></div>`;
        }

        mountEl.innerHTML = `
            <div style="font-size:11px; max-height:220px; overflow-y:auto; padding-right:2px;">
                <div style="font-weight:700; color:#60a5fa; margin-bottom:6px;">落地实体总数: ${sim.entities.length}</div>
                ${listHtml || '<div style="color:#64748b;">无实体落地</div>'}
            </div>
        `;
    }
});