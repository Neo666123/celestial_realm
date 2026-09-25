/**
 * controllers/ui_controller.js
 * 纯 UI 渲染联动控制器
 */

import { renderToolbar } from "../ui/ui_toolbar.js";
import { renderLayerStackUI } from "../ui/ui_layers.js";
import { renderRuleCards } from "../ui/ui_rule_card.js";
import { ExportManager } from "../managers/export_manager.js";

export class UIController {
    constructor({ workspace, paintEngine, simulationManager, viewport, historyController, onDataChanged, onTogglePlugins }) {
        this.ws = workspace;
        this.pe = paintEngine;
        this.sim = simulationManager;
        this.vp = viewport;
        this.hc = historyController;
        this.onDataChanged = onDataChanged;
        this.onTogglePlugins = onTogglePlugins;

        this.toolbarContainer = document.getElementById("toolbar-container");
        this.seedSlider = document.getElementById("seed-slider");
        this.seedInput = document.getElementById("seed-input");

        this.bindGlobalWidgets();
    }

    refreshAll(rerenderPanels = true) {
        this.refreshLayerUI();
        this.updatePanels(rerenderPanels);
        this.refreshToolbarUI();
        if (this.hc) this.hc.updateUIState();
    }

    refreshToolbarUI() {
        if (!this.toolbarContainer) return;
        this.toolbarContainer.dataset.simulated = this.vp.isSimulated ? "1" : "";
        renderToolbar(this.toolbarContainer, this.pe, {
            layerStack: this.ws.layerStack,
            onToolChange: (tool) => {
                this.vp.setPaintToolState(tool, this.pe.brushSize);
                this.updateToolIndicator();
            },
            onColorChange: (color) => {
                this.pe.setColor(color);
                this.vp.isDirty = true;
            },
            onSizeChange: (size) => {
                this.vp.setPaintToolState(this.pe.currentTool, size);
                this.vp.isDirty = true;
            },
            onTogglePlugins: this.onTogglePlugins
        });
        this.updateToolIndicator();
    }

    updateToolIndicator() {
        const el = document.getElementById("floating-tool-indicator");
        if (el) {
            const nameMap = { brush: "画笔", eraser: "橡皮", select: "选择/移动", lasso: "套索", bucket: "填充", picker: "吸管" };
            el.innerText = `当前: ${nameMap[this.pe.currentTool] || this.pe.currentTool} (${this.pe.brushSize}px) | 右键快切 ${nameMap[this.pe.prevTool] || this.pe.prevTool}`;
        }
    }

    refreshLayerUI() {
        const cntEl = document.getElementById("exp-selected-count");
        if (cntEl) cntEl.innerText = Math.max(1, this.ws.selectedLayerIndices.length);

        renderLayerStackUI(
            document.getElementById("layers-list"),
            this.ws.layerStack,
            this.ws.unassignedLua,
            this.ws.activeLayerIndex,
            this.ws.selectedLayerIndices,
            {
                onSelectLayer: (idx, keyState) => {
                    if (keyState && keyState.shiftKey && this.ws.lastClickedLayerIndex !== -1) {
                        const min = Math.min(this.ws.lastClickedLayerIndex, idx);
                        const max = Math.max(this.ws.lastClickedLayerIndex, idx);
                        const range = [];
                        for (let i = min; i <= max; i++) range.push(i);
                        this.ws.selectedLayerIndices = Array.from(new Set([...this.ws.selectedLayerIndices, ...range]));
                    } else if (keyState && keyState.ctrlKey) {
                        const pos = this.ws.selectedLayerIndices.indexOf(idx);
                        if (pos !== -1) {
                            if (this.ws.selectedLayerIndices.length > 1) this.ws.selectedLayerIndices.splice(pos, 1);
                        } else {
                            this.ws.selectedLayerIndices.push(idx);
                        }
                    } else {
                        this.ws.selectedLayerIndices = [idx];
                    }

                    this.ws.activeLayerIndex = idx;
                    this.ws.lastClickedLayerIndex = idx;
                    this.updatePanels(true);
                    this.refreshLayerUI();
                    this.refreshToolbarUI();
                },
                onChange: () => {
                    this.hc.pushSnapshot();
                    this.onDataChanged({ rerenderPanels: true });
                },
                onOpacityChange: () => this.vp.invalidateBake(),
                onMoveLua: (src, target) => {
                    this.hc.pushSnapshot();
                    let item = null;
                    if (src.from === "unassigned") item = this.ws.unassignedLua.splice(src.luaIdx, 1)[0];
                    else if (src.from === "layer" && this.ws.layerStack[src.layerIdx]) item = this.ws.layerStack[src.layerIdx].luaList.splice(src.luaIdx, 1)[0];
                    if (!item) return;

                    if (target.to === "unassigned") this.ws.unassignedLua.push(item);
                    else if (target.to === "layer" && this.ws.layerStack[target.targetLayerIdx]) this.ws.layerStack[target.targetLayerIdx].luaList.push(item);

                    this.onDataChanged({ rerenderPanels: true });
                },
                onDeleteLua: (meta) => {
                    this.hc.pushSnapshot();
                    if (meta.from === "unassigned") this.ws.unassignedLua.splice(meta.luaIdx, 1);
                    else if (meta.from === "layer" && this.ws.layerStack[meta.layerIdx]) this.ws.layerStack[meta.layerIdx].luaList.splice(meta.luaIdx, 1);

                    this.onDataChanged({ rerenderPanels: true });
                },
                onAddBlankLayer: () => {
                    this.hc.pushSnapshot();
                    this.ws.addBlankLayer();
                    this.onDataChanged({ rerenderPanels: true });
                },
                onMergeLayers: () => {
                    if (this.ws.selectedLayerIndices.length < 2) return;
                    const mergeLua = confirm(`已多选 ${this.ws.selectedLayerIndices.length} 个图层！\n\n是否同时合并对应图层的 Lua 规则？`);
                    this.hc.pushSnapshot();

                    const { newLayer, sortedIndices } = ExportManager.mergeLayers(
                        this.ws.layerStack,
                        this.ws.selectedLayerIndices,
                        mergeLua,
                        (l) => this.sim.getMergedRulesForLayer(l)
                    );

                    const minPos = sortedIndices[0];
                    for (let i = sortedIndices.length - 1; i >= 0; i--) {
                        this.ws.layerStack.splice(sortedIndices[i], 1);
                    }
                    this.ws.layerStack.splice(minPos, 0, newLayer);

                    this.ws.activeLayerIndex = minPos;
                    this.ws.selectedLayerIndices = [minPos];
                    this.ws.lastClickedLayerIndex = minPos;

                    this.onDataChanged({ rerenderPanels: true });
                }
            }
        );
    }

    updatePanels(rerenderList = true) {
        const rulesContainer = document.getElementById("rules-container");
        const titleEl = document.getElementById("rules-panel-title");

        const cur = this.ws.getActiveLayer();
        if (!cur) {
            titleEl.innerText = "图层规则属性";
            rulesContainer.innerHTML = `<div style="font-size:12px; color:#6b7280; text-align:center; padding:12px; background:rgba(24,27,32,0.9); border-radius:6px;">请先在左侧选择图层</div>`;
            return;
        }

        titleEl.innerText = `规则: ${cur.name}`;

        if (rerenderList) {
            const mergedRules = this.sim.getMergedRulesForLayer(cur);
            renderRuleCards(
                rulesContainer,
                cur,
                mergedRules,
                // 回调 1: 关键修复 —— 尊重 needRerender 参数，打字改数字时绝对不重构 DOM
                (needRerender) => {
                    this.hc.pushSnapshot();
                    if (cur.luaList && cur.luaList.length > 0) cur.luaList[0].rules = mergedRules;
                    else cur.luaList = [{ id: "lua_" + Date.now(), name: `config_${cur.fileBaseName}.lua`, rules: mergedRules }];

                    this.vp.setIconMap(this.sim.extractActiveIconMap(this.ws.layerStack));
                    if (needRerender) {
                        this.updatePanels(true);
                    }
                    this.onDataChanged({ rerenderPanels: false });
                },
                // 回调 2: 色号置换
                (oldHex, newHex) => {
                    if (!newHex || oldHex === newHex) return;
                    this.hc.pushSnapshot();
                    if (mergedRules[oldHex]) {
                        mergedRules[newHex] = mergedRules[oldHex];
                        delete mergedRules[oldHex];
                    }
                    if (cur.luaList && cur.luaList.length > 0) cur.luaList[0].rules = mergedRules;

                    if (cur.grid) {
                        for (let y = 1; y <= cur.height; y++) {
                            const row = cur.grid[y];
                            if (!row) continue;
                            for (let x = 1; x <= cur.width; x++) {
                                const c = row[x];
                                const curCol = (typeof c === "object") ? c?.color : c;
                                if (curCol && curCol.toLowerCase() === oldHex.toLowerCase()) {
                                    if (typeof c === "object") c.color = newHex;
                                    else row[x] = newHex;
                                }
                            }
                        }
                    }

                    const set = new Set(cur.uniqueColors.map(c => c.toLowerCase() === oldHex.toLowerCase() ? newHex.toLowerCase() : c.toLowerCase()));
                    cur.uniqueColors = Array.from(set);

                    if (window.__ruleCardHelpers) window.__ruleCardHelpers.setActiveColor(newHex);
                    this.updatePanels(true);
                    this.onDataChanged({ rerenderPanels: true });
                }
            );
        }
    }

    setSeed(val) {
        this.ws.currentSeed = parseInt(val, 10) || 12345;
        if (this.seedSlider) this.seedSlider.value = this.ws.currentSeed;
        if (this.seedInput) this.seedInput.value = this.ws.currentSeed;
        this.onDataChanged({ rerenderPanels: false });
    }

    bindGlobalWidgets() {
        const btnModeFocus = document.getElementById("btn-mode-focus");
        const btnModeExpand = document.getElementById("btn-mode-expand");
        if (btnModeFocus && btnModeExpand) {
            btnModeFocus.onclick = () => {
                btnModeFocus.className = "btn-sm btn-active";
                btnModeExpand.className = "btn-sm btn-secondary";
                if (window.__ruleCardHelpers) window.__ruleCardHelpers.setMode("focus");
                this.updatePanels(true);
            };
            btnModeExpand.onclick = () => {
                btnModeExpand.className = "btn-sm btn-active";
                btnModeFocus.className = "btn-sm btn-secondary";
                if (window.__ruleCardHelpers) window.__ruleCardHelpers.setMode("expand");
                this.updatePanels(true);
            };
        }

        if (this.seedSlider) this.seedSlider.oninput = (e) => this.setSeed(e.target.value);
        if (this.seedInput) this.seedInput.onchange = (e) => this.setSeed(e.target.value);
        const btnRandSeed = document.getElementById("btn-random-seed");
        if (btnRandSeed) btnRandSeed.onclick = () => this.setSeed(Math.floor(Math.random() * 10000));

        // 统一在此处绑定模拟开关，避免 app.js 重复绑定
        const cbSimulate = document.getElementById("cb-simulate");
        if (cbSimulate) {
            cbSimulate.onchange = (e) => {
                this.vp.isSimulated = e.target.checked;
                if (this.vp.isSimulated) {
                    const simResult = this.sim.runSimulation(this.ws.layerStack, this.ws.currentSeed);
                    this.vp.setLayerStack(this.ws.layerStack, simResult);
                }
                this.vp.invalidateBake();
                this.refreshToolbarUI();
            };
        }

        // 统一在此处绑定恢复缓存，恢复后对齐种子控件回显
        const btnRestoreCache = document.getElementById("btn-restore-cache");
        if (btnRestoreCache) {
            btnRestoreCache.onclick = async () => {
                try {
                    this.hc.pushSnapshot();
                    const data = await this.ws.restoreCache();
                    if (!data) return alert("未找到历史记录！");
                    if (data.currentSeed) {
                        this.setSeed(data.currentSeed);
                    } else {
                        this.onDataChanged({ rerenderPanels: true });
                    }
                    alert("成功恢复工作台！");
                } catch (err) {
                    alert("读取缓存失败: " + err.message);
                }
            };
        }
    }
}