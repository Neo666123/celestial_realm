/**
 * ui/ui_rule_card.js
 * 规则卡片组件：
 * 1. 桥梁特种规则彻底合并进预制体 (Prefab) 通道，支持选择模式
 * 2. 移除任何写死的桥桩默认名和默认图标
 * 3. 完整支持地皮、预制体复合、蓝图建筑与自定义 Data 字典
 */

let activeColorKey = null;
let currentMode = "focus";
const expandedFoldSet = new Set();
let isCardCollapsedInFocus = false;

window.__ruleCardHelpers = {
    setMode: (mode) => { currentMode = mode === "expand" ? "expand" : "focus"; },
    getMode: () => currentMode,
    setActiveColor: (colHex) => {
        activeColorKey = colHex ? colHex.toLowerCase() : null;
        isCardCollapsedInFocus = false;
    },
    getActiveColor: () => activeColorKey,
    toggleColor: (colHex, forceOpen = false) => {
        const key = colHex.toLowerCase();
        activeColorKey = key;
        isCardCollapsedInFocus = false;
        if (currentMode === "expand") expandedFoldSet.delete(key);
    }
};

export function renderRuleCards(container, currentLayer, rules, onChange, onRenameColor) {
    container.innerHTML = "";
    const colors = Object.keys(rules);

    if (colors.length === 0 && (!currentLayer.uniqueColors || currentLayer.uniqueColors.length === 0)) {
        container.innerHTML = `<div style="font-size:12px; color:#6b7280; text-align:center; padding:12px; background:rgba(24,27,32,0.9); border-radius:6px;">当前图层暂无规则，可从下方添加或导入 Lua</div>`;
        return;
    }

    if (!activeColorKey || (!rules[activeColorKey] && colors.length > 0)) {
        activeColorKey = colors.length > 0 ? colors[0].toLowerCase() : null;
    }

    // 1. 顶部色块导航栏
    if (currentMode === "focus") {
        const navBar = document.createElement("div");
        navBar.style.cssText = "display:flex; flex-wrap:wrap; gap:4px; padding:6px 8px; margin-bottom:6px; background:rgba(22,24,28,0.94); border:1px solid #31353d; border-radius:6px; backdrop-filter:blur(8px); box-shadow:0 4px 12px rgba(0,0,0,0.4);";

        colors.forEach(col => {
            const colLower = col.toLowerCase();
            const isCur = (colLower === activeColorKey);
            const conf = rules[col];
            const t1 = (conf.tiers && conf.tiers[1]) ? conf.tiers[1] : conf;
            const iconChar = (t1 && t1.icons) ? Object.values(t1.icons).map(v => typeof v === 'object' ? v.char : v).filter(Boolean)[0] : "";

            const pill = document.createElement("div");
            pill.style.cssText = `display:flex; align-items:center; gap:4px; padding:2px 7px; border-radius:12px; cursor:pointer; border:1px solid ${isCur ? '#3b82f6' : '#333'}; background:${isCur ? '#1e293b' : '#181a1e'}; font-size:11px;`;
            pill.innerHTML = `
                <span style="width:8px; height:8px; border-radius:50%; background:${col}; display:inline-block;"></span>
                <span style="color:${isCur ? '#fff' : '#94a3b8'}; font-family:monospace; font-weight:${isCur ? '700' : '400'};">${col}</span>
                ${iconChar ? `<span style="font-size:10px;">${iconChar}</span>` : ''}
            `;
            pill.onclick = () => {
                if (window.__syncBrushColor) window.__syncBrushColor(colLower);
                activeColorKey = colLower;
                isCardCollapsedInFocus = false;
                renderRuleCards(container, currentLayer, rules, onChange, onRenameColor);
            };
            navBar.appendChild(pill);
        });

        // 自动探测新色号
        const unconfigured = (currentLayer.uniqueColors || []).filter(c => c && !rules[c.toLowerCase()]);
        unconfigured.forEach(unCol => {
            const addPill = document.createElement("div");
            addPill.style.cssText = "display:flex; align-items:center; gap:4px; padding:2px 7px; border-radius:12px; cursor:pointer; border:1px dashed #f59e0b; background:#292318; font-size:11px; color:#fde047;";
            addPill.innerHTML = `<span style="width:8px; height:8px; border-radius:50%; background:${unCol};"></span><span>+ ${unCol} (未配置)</span>`;
            addPill.title = "检测到画布有此新绘制色号，点击一键生成配置卡片";
            addPill.onclick = () => {
                const cKey = unCol.toLowerCase();
                rules[cKey] = { tiers: { 1: { dis: 1, chance: 1.0, require_solid: true, tile: "METEOR" } } };
                if (window.__syncBrushColor) window.__syncBrushColor(cKey);
                activeColorKey = cKey;
                isCardCollapsedInFocus = false;
                if (onChange) onChange(true);
            };
            navBar.appendChild(addPill);
        });

        container.appendChild(navBar);
    }

    // 2. 渲染规则卡片
    colors.forEach(col => {
        const colKey = col.toLowerCase();
        const isFocused = (colKey === activeColorKey);
        if (currentMode === "focus" && !isFocused) return;

        const conf = rules[col];
        const tier1 = (conf.tiers && conf.tiers[1]) ? conf.tiers[1] : conf;
        tier1.icons = tier1.icons || {};

        const isCollapsed = (currentMode === "focus") ? isCardCollapsedInFocus : expandedFoldSet.has(colKey);
        const card = document.createElement("div");
        card.className = "rule-card" + (isFocused ? " highlight" : "");
        card.id = `rule-card-${col.replace("#", "").toLowerCase()}`;

        const badgesHtml = buildSummaryBadges(tier1);

        const header = document.createElement("div");
        header.className = "rule-card-header";
        header.style.cssText = "display:flex; justify-content:space-between; align-items:center; padding:6px 8px; background:#1f232b; user-select:none; cursor:pointer; border-bottom: " + (isCollapsed ? "none" : "1px solid #2a2e37") + ";";

        header.innerHTML = `
            <div style="display:flex; align-items:center; gap:6px; overflow:hidden; flex:1;">
                <span class="btn-toggle-fold" style="font-size:10px; color:#94a3b8; width:12px; text-align:center;">${isCollapsed ? "▶" : "▼"}</span>
                <input type="color" class="color-picker" value="${col.length === 7 ? col : '#ffffff'}" style="width:18px; height:18px; padding:0; border:none; background:none; cursor:pointer;">
                <input type="text" class="color-hex-input" value="${col}" style="width:70px; font-family:monospace; font-size:11px; font-weight:700; background:#111; border:1px solid #333; color:#fff; text-align:center;">
                <div class="summary-tags" style="display:flex; align-items:center; gap:4px; overflow:hidden; margin-left:4px;">
                    ${badgesHtml}
                </div>
            </div>
            <button class="btn-danger btn-sm btn-del-rule" style="padding:1px 6px; font-size:10px; margin-left:6px;">删除</button>
        `;

        header.onclick = (e) => {
            if (e.target.closest(".color-picker") || e.target.closest(".color-hex-input") || e.target.closest(".btn-del-rule")) return;
            if (window.__syncBrushColor) window.__syncBrushColor(colKey);

            if (currentMode === "focus") {
                isCardCollapsedInFocus = !isCardCollapsedInFocus;
            } else {
                if (expandedFoldSet.has(colKey)) expandedFoldSet.delete(colKey);
                else expandedFoldSet.add(colKey);
            }
            renderRuleCards(container, currentLayer, rules, onChange, onRenameColor);
        };

        const hexInput = header.querySelector(".color-hex-input");
        const colorPicker = header.querySelector(".color-picker");

        const applyColorChange = (newHex) => {
            const clean = (newHex.startsWith("#") ? newHex : "#" + newHex).toLowerCase();
            if (clean === colKey) return;
            if (onRenameColor) onRenameColor(colKey, clean);
        };

        hexInput.onkeydown = (e) => { if (e.key === "Enter") applyColorChange(hexInput.value.trim()); };
        hexInput.onblur = () => applyColorChange(hexInput.value.trim());
        colorPicker.onchange = (e) => applyColorChange(e.target.value);

        header.querySelector(".btn-del-rule").onclick = (e) => {
            e.stopPropagation();
            delete rules[col];
            if (activeColorKey === colKey) activeColorKey = null;
            onChange(true);
        };

        card.appendChild(header);

        const body = document.createElement("div");
        body.className = "rule-card-body";
        body.style.cssText = "padding:8px; display: " + (isCollapsed ? "none" : "block") + ";";

        body.innerHTML = `
            <div class="form-row">
                <span>Dis (拓扑打组):</span>
                <div style="display:flex; gap:4px; align-items:center;">
                    <input type="number" class="ipt-dis-num" min="0" placeholder="数值" value="${tier1.dis !== null && tier1.dis !== undefined ? tier1.dis : ''}" style="width:50px;" ${tier1.dis === null ? 'disabled' : ''}>
                    <select class="ipt-dis-select" style="width:75px;">
                        <option value="custom" ${tier1.dis !== null && ![0, 1, 2, 3].includes(tier1.dis) ? 'selected' : ''}>自定义</option>
                        <option value="1" ${tier1.dis === 1 ? 'selected' : ''}>1 (4邻域)</option>
                        <option value="0" ${tier1.dis === 0 ? 'selected' : ''}>0 (点独立)</option>
                        <option value="2" ${tier1.dis === 2 ? 'selected' : ''}>2 (跨1格)</option>
                        <option value="3" ${tier1.dis === 3 ? 'selected' : ''}>3 (跨2格)</option>
                        <option value="nil" ${tier1.dis === null ? 'selected' : ''}>nil (全图)</option>
                    </select>
                </div>
            </div>

            <div class="form-row">
                <span>Chance (几率):</span>
                <input type="number" step="0.05" min="0" max="1" class="ipt-chance" value="${tier1.chance !== undefined ? tier1.chance : 1.0}" style="width:75px;">
            </div>

            <div class="form-row">
                <span>Require Solid (防悬空):</span>
                <input type="checkbox" class="ipt-solid" ${tier1.require_solid !== false ? "checked" : ""}>
            </div>

            <div class="channels-list"></div>

            <div class="form-row" style="margin-top:8px; border-top:1px dashed #2d3139; padding-top:6px;">
                <select class="sel-add-channel" style="flex:1;">
                    <option value="">[+ 添加属性通道 ▾]</option>
                    ${!tier1.tile ? '<option value="tile">+ 地皮通道 (tile)</option>' : ''}
                    ${!tier1.prefab ? '<option value="prefab">+ 预制体/桥梁通道 (prefab)</option>' : ''}
                    ${!tier1.blueprint && !tier1.blueprints ? '<option value="blueprint">+ 蓝图建筑通道 (blueprints)</option>' : ''}
                    ${!tier1.data ? '<option value="data">+ 自定义数据通道 (data)</option>' : ''}
                </select>
            </div>
        `;

        const channelsContainer = body.querySelector(".channels-list");

        // A. 地皮通道
        if (tier1.tile) {
            const block = document.createElement("div");
            block.className = "channel-block";
            const isDist = typeof tier1.tile === "object" && tier1.tile.distribute;

            block.innerHTML = `
                <div class="channel-title">
                    <span>地皮通道 (Tile)</span>
                    <button class="btn-danger btn-sm btn-del-channel">×</button>
                </div>
                <div class="form-row">
                    <span>模式:</span>
                    <select class="tile-mode">
                        <option value="string" ${!isDist ? "selected" : ""}>单值铺满</option>
                        <option value="distribute" ${isDist ? "selected" : ""}>权重混铺</option>
                    </select>
                </div>
                <div class="tile-content-area"></div>
            `;
            block.querySelector(".btn-del-channel").onclick = () => { delete tier1.tile; onChange(true); };
            block.querySelector(".tile-mode").onchange = (e) => {
                tier1.tile = e.target.value === "string" ? "METEOR" : { distribute: { METEOR: 0.7, PEBBLEBEACH: 0.3 } };
                onChange(true);
            };
            const contentArea = block.querySelector(".tile-content-area");
            if (!isDist) {
                contentArea.innerHTML = `<div class="form-row"><span>地皮名:</span><input type="text" class="tile-single-val" value="${typeof tier1.tile === 'string' ? tier1.tile : 'METEOR'}" style="flex:1;" placeholder="METEOR 或 IMPASSABLE(挖空)"></div>`;
                contentArea.querySelector(".tile-single-val").onchange = (e) => { tier1.tile = e.target.value.trim(); onChange(false); };
            } else {
                renderTileDistributeEditor(contentArea, tier1.tile.distribute, () => onChange(false), () => onChange(true));
            }
            channelsContainer.appendChild(block);
        }

        // B. 预制体通道 (彻底收编桥梁规则，去除互斥与写死)
        if (tier1.prefab) {
            const block = document.createElement("div");
            block.className = "channel-block";

            const hasRule = !!tier1.rule;
            const pfName = typeof tier1.prefab === "string" ? tier1.prefab : "";
            const iconCfg = getIconEntry(tier1.icons, pfName);

            block.innerHTML = `
                <div class="channel-title">
                    <span>预制体通道 (Prefab)</span>
                    <button class="btn-danger btn-sm btn-del-channel">×</button>
                </div>
                <div class="form-row">
                    <span>生成规则:</span>
                    <select class="pf-rule-select">
                        <option value="standard" ${!hasRule ? 'selected' : ''}>常规散布 (定量/漫灌)</option>
                        <option value="raycast_bridge" ${tier1.rule === 'raycast_bridge' ? 'selected' : ''}>单向射线桥 (raycast_bridge)</option>
                        <option value="paired_bridge" ${tier1.rule === 'paired_bridge' ? 'selected' : ''}>双向成对桥 (paired_bridge)</option>
                    </select>
                </div>
                <div class="pf-dynamic-content"></div>
            `;

            block.querySelector(".btn-del-channel").onclick = () => {
                delete tier1.prefab;
                delete tier1.rule;
                delete tier1.min_gap;
                delete tier1.max_gap;
                delete tier1.pair_chance;
                onChange(true);
            };

            const dynContent = block.querySelector(".pf-dynamic-content");

            // 规则切换
            block.querySelector(".pf-rule-select").onchange = (e) => {
                const val = e.target.value;
                if (val === "standard") {
                    delete tier1.rule;
                    delete tier1.min_gap;
                    delete tier1.max_gap;
                    delete tier1.pair_chance;
                    if (typeof tier1.prefab === "string") {
                        tier1.prefab = { count: { [tier1.prefab || "chest"]: 1 } };
                    }
                } else {
                    tier1.rule = val;
                    tier1.prefab = typeof tier1.prefab === "string" ? tier1.prefab : Object.keys(tier1.prefab?.count || {})[0] || "my_prefab";
                    tier1.min_gap = 1;
                    tier1.max_gap = 10;
                    if (val === "paired_bridge") tier1.pair_chance = 0.30;
                    else delete tier1.pair_chance;
                }
                onChange(true);
            };

            if (hasRule) {
                // 桥梁等特种规则模式：单实体 + 跨距参数
                dynContent.innerHTML = `
                    <div class="form-row">
                        <span>预制体名:</span>
                        <input type="text" class="pf-single-name" value="${pfName}" style="flex:1;" placeholder="预制体名">
                        <input type="text" class="pf-icon" placeholder="图标" value="${iconCfg.char}" style="width:40px; text-align:center;">
                        <input type="number" min="8" max="48" class="pf-size" placeholder="字号" value="${iconCfg.size}" style="width:38px; text-align:center;">
                    </div>
                    <div class="form-row">
                        <span>间隙 (Gap):</span>
                        <div style="display:flex; gap:4px; align-items:center;">
                            <input type="number" min="1" class="pf-min-gap" value="${tier1.min_gap || 1}" style="width:45px;" title="最小虚空距离">
                            <span>~</span>
                            <input type="number" min="1" class="pf-max-gap" value="${tier1.max_gap || 10}" style="width:45px;" title="最大虚空距离">
                        </div>
                    </div>
                    ${tier1.rule === 'paired_bridge' ? `
                    <div class="form-row">
                        <span>成对概率 (Pair Chance):</span>
                        <input type="number" step="0.05" min="0" max="1" class="pf-pair-chance" value="${tier1.pair_chance !== undefined ? tier1.pair_chance : 0.3}" style="width:65px;">
                    </div>` : ''}
                `;

                dynContent.querySelector(".pf-single-name").onchange = (e) => {
                    const oldN = pfName;
                    const val = e.target.value.trim();
                    tier1.prefab = val;
                    if (tier1.icons[oldN]) {
                        tier1.icons[val] = tier1.icons[oldN];
                        delete tier1.icons[oldN];
                    }
                    onChange(false);
                };
                dynContent.querySelector(".pf-icon").oninput = (e) => {
                    if (tier1.prefab) setIconChar(tier1.icons, tier1.prefab, e.target.value.trim());
                    onChange(false);
                };
                dynContent.querySelector(".pf-size").oninput = (e) => {
                    if (tier1.prefab) setIconSize(tier1.icons, tier1.prefab, parseInt(e.target.value, 10) || 14);
                    onChange(false);
                };
                dynContent.querySelector(".pf-min-gap").onchange = (e) => { tier1.min_gap = parseInt(e.target.value, 10) || 1; onChange(false); };
                dynContent.querySelector(".pf-max-gap").onchange = (e) => { tier1.max_gap = parseInt(e.target.value, 10) || 10; onChange(false); };
                const pairIpt = dynContent.querySelector(".pf-pair-chance");
                if (pairIpt) pairIpt.onchange = (e) => { tier1.pair_chance = parseFloat(e.target.value) || 0.3; onChange(false); };
            } else {
                // 常规定量/漫灌模式
                if (typeof tier1.prefab === "string") {
                    tier1.prefab = { count: { [tier1.prefab]: 1 } };
                }
                const hasCount = !!tier1.prefab.count;
                const hasDist = !!tier1.prefab.distribute;

                dynContent.innerHTML = `
                    <div class="pf-sections" style="display:flex; flex-direction:column; gap:6px;"></div>
                    <div class="form-row" style="margin-top:6px; gap:4px;">
                        ${!hasCount ? '<button class="btn-secondary btn-sm btn-add-count-mode" style="flex:1;">+ 定量/保底</button>' : ''}
                        ${!hasDist ? '<button class="btn-secondary btn-sm btn-add-dist-mode" style="flex:1;">+ 密度漫灌</button>' : ''}
                    </div>
                `;

                const sectionsBox = dynContent.querySelector(".pf-sections");

                if (hasCount) {
                    const countBox = document.createElement("div");
                    countBox.style.cssText = "background:#191c22; border:1px solid #292d36; border-radius:4px; padding:6px;";
                    countBox.innerHTML = `
                        <div style="font-size:11px; font-weight:600; color:#f472b6; margin-bottom:4px; display:flex; justify-content:space-between;">
                            <span>📦 定量抽取 / 保底 (Count)</span>
                            <button class="btn-del-count-mode" style="background:none; border:none; color:#94a3b8; cursor:pointer; font-size:12px;">×</button>
                        </div>
                        <div class="count-list-mount"></div>
                    `;
                    countBox.querySelector(".btn-del-count-mode").onclick = () => {
                        delete tier1.prefab.count;
                        if (!tier1.prefab.distribute) delete tier1.prefab;
                        onChange(true);
                    };
                    renderPrefabCountEditor(countBox.querySelector(".count-list-mount"), tier1.prefab.count, tier1.icons, () => onChange(false), () => onChange(true));
                    sectionsBox.appendChild(countBox);
                }

                if (hasDist) {
                    const distBox = document.createElement("div");
                    distBox.style.cssText = "background:#191c22; border:1px solid #292d36; border-radius:4px; padding:6px;";
                    distBox.innerHTML = `
                        <div style="font-size:11px; font-weight:600; color:#34d399; margin-bottom:4px; display:flex; justify-content:space-between;">
                            <span>🌾 密度漫灌 (Distribute)</span>
                            <button class="btn-del-dist-mode" style="background:none; border:none; color:#94a3b8; cursor:pointer; font-size:12px;">×</button>
                        </div>
                        <div class="dist-list-mount"></div>
                    `;
                    distBox.querySelector(".btn-del-dist-mode").onclick = () => {
                        delete tier1.prefab.distribute;
                        delete tier1.prefab.density;
                        if (!tier1.prefab.count) delete tier1.prefab;
                        onChange(true);
                    };
                    renderPrefabDistributeEditor(distBox.querySelector(".dist-list-mount"), tier1.prefab, tier1.icons, () => onChange(false), () => onChange(true));
                    sectionsBox.appendChild(distBox);
                }

                const btnAddCount = dynContent.querySelector(".btn-add-count-mode");
                if (btnAddCount) btnAddCount.onclick = () => { tier1.prefab.count = { chest: 1 }; onChange(true); };
                const btnAddDist = dynContent.querySelector(".btn-add-dist-mode");
                if (btnAddDist) btnAddDist.onclick = () => { tier1.prefab.distribute = { short_grass: 0.6, sapling: 0.4 }; tier1.prefab.density = 0.15; onChange(true); };
            }

            channelsContainer.appendChild(block);
        }

        // C. 蓝图通道
        if (tier1.blueprint || tier1.blueprints) {
            const block = document.createElement("div");
            block.className = "channel-block";
            const bpName = tier1.blueprint || (tier1.blueprints ? tier1.blueprints.name : "");
            const bpCount = tier1.blueprints ? tier1.blueprints.count : 1;
            const iconCfg = getIconEntry(tier1.icons, bpName);

            block.innerHTML = `
                <div class="channel-title">
                    <span>蓝图建筑通道 (Blueprints)</span>
                    <button class="btn-danger btn-sm btn-del-channel">×</button>
                </div>
                <div class="form-row">
                    <span>蓝图名:</span>
                    <input type="text" class="bp-name" value="${bpName}" style="flex:1;">
                    <input type="text" class="bp-icon" placeholder="图标" value="${iconCfg.char}" style="width:40px; text-align:center;">
                    <input type="number" min="8" max="48" class="bp-size" placeholder="字号" value="${iconCfg.size}" style="width:38px; text-align:center;">
                </div>
                <div class="form-row">
                    <span>数量:</span>
                    <input type="number" min="1" class="bp-count" value="${bpCount}" style="width:70px;">
                </div>
            `;
            block.querySelector(".btn-del-channel").onclick = () => { delete tier1.blueprint; delete tier1.blueprints; onChange(true); };
            block.querySelector(".bp-name").onchange = (e) => {
                const oldName = bpName;
                const val = e.target.value.trim();
                if (tier1.blueprints) tier1.blueprints.name = val;
                else tier1.blueprint = val;
                if (tier1.icons[oldName]) {
                    tier1.icons[val] = tier1.icons[oldName];
                    delete tier1.icons[oldName];
                }
                onChange(false);
            };
            block.querySelector(".bp-icon").oninput = (e) => {
                const curName = tier1.blueprint || (tier1.blueprints ? tier1.blueprints.name : "");
                if (curName) setIconChar(tier1.icons, curName, e.target.value.trim());
                onChange(false);
            };
            block.querySelector(".bp-size").oninput = (e) => {
                const curName = tier1.blueprint || (tier1.blueprints ? tier1.blueprints.name : "");
                if (curName) setIconSize(tier1.icons, curName, parseInt(e.target.value, 10) || 14);
                onChange(false);
            };
            block.querySelector(".bp-count").onchange = (e) => {
                tier1.blueprints = {
                    name: tier1.blueprint || (tier1.blueprints ? tier1.blueprints.name : "mini_shrine"),
                    count: parseInt(e.target.value, 10) || 1
                };
                delete tier1.blueprint;
                onChange(false);
            };
            channelsContainer.appendChild(block);
        }

        // D. 自定义 Data 数据通道
        if (tier1.data) {
            const block = document.createElement("div");
            block.className = "channel-block";
            block.innerHTML = `
                <div class="channel-title">
                    <span>自定义数据 (Data Table)</span>
                    <button class="btn-danger btn-sm btn-del-channel">×</button>
                </div>
                <div class="data-entries-list" style="display:flex; flex-direction:column; gap:4px; margin-bottom:6px;"></div>
                <button class="btn-secondary btn-sm btn-add-data-kv" style="width:100%; border:1px dashed #4b5563;">+ 添加自定义键值对</button>
            `;

            block.querySelector(".btn-del-channel").onclick = () => { delete tier1.data; onChange(true); };
            const entriesList = block.querySelector(".data-entries-list");

            Object.entries(tier1.data).forEach(([dKey, dVal]) => {
                const row = document.createElement("div");
                row.style.cssText = "display:flex; gap:4px; align-items:center;";
                row.innerHTML = `
                    <input type="text" class="dt-key" value="${dKey}" style="width:75px;" placeholder="Key">
                    <input type="text" class="dt-val" value="${dVal}" style="flex:1;" placeholder="Value">
                    <button class="btn-danger btn-sm btn-del-kv" style="padding:1px 5px;">×</button>
                `;
                row.querySelector(".dt-key").onchange = (e) => {
                    const newK = e.target.value.trim();
                    if (newK && newK !== dKey) {
                        tier1.data[newK] = tier1.data[dKey];
                        delete tier1.data[dKey];
                        onChange(false);
                    }
                };
                row.querySelector(".dt-val").onchange = (e) => {
                    const val = e.target.value.trim();
                    tier1.data[dKey] = !isNaN(Number(val)) && val !== "" ? Number(val) : (val === "true" ? true : (val === "false" ? false : val));
                    onChange(false);
                };
                row.querySelector(".btn-del-kv").onclick = () => {
                    delete tier1.data[dKey];
                    onChange(true);
                };
                entriesList.appendChild(row);
            });

            block.querySelector(".btn-add-data-kv").onclick = () => {
                const newK = "param_" + (Object.keys(tier1.data).length + 1);
                tier1.data[newK] = "val";
                onChange(true);
            };

            channelsContainer.appendChild(block);
        }

        // 添加通道入口
        body.querySelector(".sel-add-channel").onchange = (e) => {
            const val = e.target.value;
            if (!val) return;
            if (val === "tile") tier1.tile = "METEOR";
            if (val === "prefab") tier1.prefab = { count: { chest: 1 } };
            if (val === "blueprint") tier1.blueprints = { name: "mini_shrine", count: 1 };
            if (val === "data") tier1.data = { scenario: "chest_trap" };
            onChange(true);
        };

        const iptDisNum = body.querySelector(".ipt-dis-num");
        const selDis = body.querySelector(".ipt-dis-select");
        selDis.onchange = (e) => {
            const val = e.target.value;
            if (val === "nil") {
                tier1.dis = null;
                iptDisNum.value = "";
                iptDisNum.disabled = true;
            } else if (val === "custom") {
                iptDisNum.disabled = false;
                iptDisNum.focus();
            } else {
                iptDisNum.disabled = false;
                tier1.dis = parseInt(val, 10);
                iptDisNum.value = tier1.dis;
            }
            onChange(false);
        };
        iptDisNum.oninput = (e) => {
            const num = parseInt(e.target.value, 10);
            if (!isNaN(num) && num >= 0) {
                tier1.dis = num;
                selDis.value = [0, 1, 2, 3].includes(num) ? String(num) : "custom";
            } else {
                tier1.dis = null;
                selDis.value = "nil";
            }
            onChange(false);
        };

        body.querySelector(".ipt-chance").onchange = (e) => { tier1.chance = parseFloat(e.target.value); onChange(false); };
        body.querySelector(".ipt-solid").onchange = (e) => { tier1.require_solid = e.target.checked; onChange(false); };

        card.appendChild(body);
        container.appendChild(card);
    });
}

function renderTileDistributeEditor(container, distMap, onDataChange, onRebuild) {
    container.innerHTML = "";
    const list = document.createElement("div");
    list.style.cssText = "display:flex; flex-direction:column; gap:4px; margin-top:4px;";

    Object.keys(distMap).forEach(tileName => {
        const row = document.createElement("div");
        row.style.cssText = "display:flex; gap:4px; align-items:center;";
        row.innerHTML = `
            <input type="text" class="item-name" value="${tileName}" style="flex:1;" placeholder="地皮名">
            <input type="number" step="0.05" min="0" max="1" class="item-val" value="${distMap[tileName]}" style="width:48px;" placeholder="权重">
            <button class="btn-danger btn-sm btn-del-item" style="padding:1px 5px;">×</button>
        `;
        row.querySelector(".item-name").onchange = (e) => {
            const newName = e.target.value.trim();
            if (newName && newName !== tileName) {
                distMap[newName] = distMap[tileName];
                delete distMap[tileName];
                onRebuild();
            }
        };
        row.querySelector(".item-val").onchange = (e) => {
            distMap[tileName] = parseFloat(e.target.value) || 0;
            onDataChange();
        };
        row.querySelector(".btn-del-item").onclick = () => { delete distMap[tileName]; onRebuild(); };
        list.appendChild(row);
    });

    const addBtn = document.createElement("button");
    addBtn.className = "btn-secondary btn-sm";
    addBtn.style.cssText = "margin-top:4px; width:100%; border:1px dashed #4b5563;";
    addBtn.innerText = "+ 添加混铺条目";
    addBtn.onclick = () => { distMap["METEOR_" + (Object.keys(distMap).length + 1)] = 0.5; onRebuild(); };

    container.appendChild(list);
    container.appendChild(addBtn);
}

function renderPrefabCountEditor(container, countMap, iconsMap, onDataChange, onRebuild) {
    container.innerHTML = "";
    const list = document.createElement("div");
    list.style.cssText = "display:flex; flex-direction:column; gap:4px; margin-top:4px;";

    Object.keys(countMap).forEach(pfName => {
        const iconCfg = getIconEntry(iconsMap, pfName);
        const row = document.createElement("div");
        row.style.cssText = "display:flex; gap:4px; align-items:center;";
        row.innerHTML = `
            <input type="text" class="item-name" value="${pfName}" style="flex:1;" placeholder="预制体名">
            <input type="number" min="1" step="1" class="item-val" value="${countMap[pfName]}" style="width:40px;" placeholder="数量">
            <input type="text" class="item-icon" value="${iconCfg.char}" style="width:40px; text-align:center;" placeholder="图标">
            <input type="number" min="8" max="48" class="item-size" value="${iconCfg.size}" style="width:38px; text-align:center;" placeholder="字号">
            <button class="btn-danger btn-sm btn-del-item" style="padding:1px 5px;">×</button>
        `;
        row.querySelector(".item-name").onchange = (e) => {
            const newName = e.target.value.trim();
            if (newName && newName !== pfName) {
                countMap[newName] = countMap[pfName];
                delete countMap[pfName];
                if (iconsMap[pfName]) {
                    iconsMap[newName] = iconsMap[pfName];
                    delete iconsMap[pfName];
                }
                onRebuild();
            }
        };
        row.querySelector(".item-val").onchange = (e) => {
            countMap[pfName] = parseInt(e.target.value, 10) || 1;
            onDataChange();
        };
        row.querySelector(".item-icon").oninput = (e) => {
            setIconChar(iconsMap, pfName, e.target.value.trim());
            onDataChange();
        };
        row.querySelector(".item-size").oninput = (e) => {
            setIconSize(iconsMap, pfName, parseInt(e.target.value, 10) || 14);
            onDataChange();
        };
        row.querySelector(".btn-del-item").onclick = () => {
            delete countMap[pfName];
            delete iconsMap[pfName];
            onRebuild();
        };
        list.appendChild(row);
    });

    const addBtn = document.createElement("button");
    addBtn.className = "btn-secondary btn-sm";
    addBtn.style.cssText = "margin-top:4px; width:100%; border:1px dashed #4b5563;";
    addBtn.innerText = "+ 添加定量条目";
    addBtn.onclick = () => {
        const k = "chest_" + (Object.keys(countMap).length + 1);
        countMap[k] = 1;
        onRebuild();
    };

    container.appendChild(list);
    container.appendChild(addBtn);
}

function renderPrefabDistributeEditor(container, pfObj, iconsMap, onDataChange, onRebuild) {
    container.innerHTML = "";
    pfObj.distribute = pfObj.distribute || {};

    const densityRow = document.createElement("div");
    densityRow.className = "form-row";
    densityRow.style.cssText = "margin-bottom:4px;";
    densityRow.innerHTML = `
        <span>密度 (Density):</span>
        <input type="number" step="0.05" min="0" max="1" class="pf-density-val" value="${pfObj.density !== undefined ? pfObj.density : 0.2}" style="width:60px;">
    `;
    densityRow.querySelector(".pf-density-val").onchange = (e) => {
        pfObj.density = parseFloat(e.target.value) || 0.1;
        onDataChange();
    };
    container.appendChild(densityRow);

    const list = document.createElement("div");
    list.style.cssText = "display:flex; flex-direction:column; gap:4px;";

    Object.keys(pfObj.distribute).forEach(pfName => {
        const iconCfg = getIconEntry(iconsMap, pfName);
        const row = document.createElement("div");
        row.style.cssText = "display:flex; gap:4px; align-items:center;";
        row.innerHTML = `
            <input type="text" class="item-name" value="${pfName}" style="flex:1;" placeholder="预制体名">
            <input type="number" step="0.05" min="0" max="1" class="item-val" value="${pfObj.distribute[pfName]}" style="width:44px;" placeholder="权重">
            <input type="text" class="item-icon" value="${iconCfg.char}" style="width:40px; text-align:center;" placeholder="图标">
            <input type="number" min="8" max="48" class="item-size" value="${iconCfg.size}" style="width:38px; text-align:center;" placeholder="字号">
            <button class="btn-danger btn-sm btn-del-item" style="padding:1px 5px;">×</button>
        `;
        row.querySelector(".item-name").onchange = (e) => {
            const newName = e.target.value.trim();
            if (newName && newName !== pfName) {
                pfObj.distribute[newName] = pfObj.distribute[pfName];
                delete pfObj.distribute[pfName];
                if (iconsMap[pfName]) {
                    iconsMap[newName] = iconsMap[pfName];
                    delete iconsMap[pfName];
                }
                onRebuild();
            }
        };
        row.querySelector(".item-val").onchange = (e) => {
            pfObj.distribute[pfName] = parseFloat(e.target.value) || 0;
            onDataChange();
        };
        row.querySelector(".item-icon").oninput = (e) => {
            setIconChar(iconsMap, pfName, e.target.value.trim());
            onDataChange();
        };
        row.querySelector(".item-size").oninput = (e) => {
            setIconSize(iconsMap, pfName, parseInt(e.target.value, 10) || 14);
            onDataChange();
        };
        row.querySelector(".btn-del-item").onclick = () => {
            delete pfObj.distribute[pfName];
            delete iconsMap[pfName];
            onRebuild();
        };
        list.appendChild(row);
    });

    const addBtn = document.createElement("button");
    addBtn.className = "btn-secondary btn-sm";
    addBtn.style.cssText = "margin-top:4px; width:100%; border:1px dashed #4b5563;";
    addBtn.innerText = "+ 添加漫灌条目";
    addBtn.onclick = () => {
        const k = "short_grass_" + (Object.keys(pfObj.distribute).length + 1);
        pfObj.distribute[k] = 0.5;
        onRebuild();
    };

    container.appendChild(list);
    container.appendChild(addBtn);
}

function getIconEntry(iconsMap, key) {
    if (!iconsMap || !iconsMap[key]) return { char: "", size: 14 };
    const val = iconsMap[key];
    if (typeof val === "object") return { char: val.char || "", size: val.size || 14 };
    return { char: String(val), size: 14 };
}

function setIconChar(iconsMap, key, char) {
    const entry = getIconEntry(iconsMap, key);
    iconsMap[key] = { char: char, size: entry.size };
}

function setIconSize(iconsMap, key, size) {
    const entry = getIconEntry(iconsMap, key);
    iconsMap[key] = { char: entry.char, size: size };
}

function buildSummaryBadges(tier1) {
    const badges = [];
    if (tier1.icons && Object.keys(tier1.icons).length > 0) {
        const iconList = Object.values(tier1.icons).map(v => typeof v === "object" ? v.char : v).filter(Boolean);
        if (iconList.length > 0) badges.push(`<span style="background:#0284c7; color:#f0f9ff; font-weight:700; padding:0 4px; border-radius:3px; font-size:10px;">🏷️ ${iconList.join(" ")}</span>`);
    }
    if (tier1.tile) {
        const tStr = typeof tier1.tile === "string" ? tier1.tile : "混铺(" + Object.keys(tier1.tile.distribute || {}).length + ")";
        badges.push(`<span style="background:#1e3a8a; color:#bfdbfe; padding:0 4px; border-radius:3px; font-size:10px;">地皮: ${tStr}</span>`);
    }
    if (tier1.prefab) {
        if (tier1.rule) {
            badges.push(`<span style="background:#713f12; color:#fef08a; padding:0 4px; border-radius:3px; font-size:10px;">规则: ${tier1.rule}</span>`);
        } else if (typeof tier1.prefab === "object") {
            const parts = [];
            if (tier1.prefab.count && Object.keys(tier1.prefab.count).length > 0) parts.push("定量(" + Object.keys(tier1.prefab.count).length + ")");
            if (tier1.prefab.distribute && Object.keys(tier1.prefab.distribute).length > 0) parts.push("漫灌(" + Object.keys(tier1.prefab.distribute).length + ")");
            badges.push(`<span style="background:#831843; color:#fbcfe8; padding:0 4px; border-radius:3px; font-size:10px;">实体: ${parts.join("+") || "已配置"}</span>`);
        } else {
            badges.push(`<span style="background:#831843; color:#fbcfe8; padding:0 4px; border-radius:3px; font-size:10px;">实体: ${tier1.prefab}</span>`);
        }
    }
    if (tier1.blueprint || tier1.blueprints) {
        const bpName = tier1.blueprint || (tier1.blueprints ? tier1.blueprints.name : "建筑");
        badges.push(`<span style="background:#581c87; color:#e9d5ff; padding:0 4px; border-radius:3px; font-size:10px;">蓝图: ${bpName}</span>`);
    }
    if (tier1.data && Object.keys(tier1.data).length > 0) badges.push(`<span style="background:#065f46; color:#a7f3d0; padding:0 4px; border-radius:3px; font-size:10px;">Data(${Object.keys(tier1.data).length})</span>`);

    return badges.join("");
}