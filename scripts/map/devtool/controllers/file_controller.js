/**
 * controllers/file_controller.js
 * 文件 I/O 交互控制器
 * 职责：批量 PNG 图像加载、Lua 脚本配置导入解析与批量导出触发
 */

import { parseImageLayer, loadImageDataFromSource } from "../core/image_loader.js";
import { ExportManager } from "../managers/export_manager.js";

export class FileController {
    constructor({ workspace, configStore, simulationManager, onStateCommit, onDataChanged }) {
        this.ws = workspace;
        this.cfg = configStore;
        this.sim = simulationManager;
        this.onStateCommit = onStateCommit;
        this.onDataChanged = onDataChanged;
        this.bindEvents();
    }

    bindEvents() {
        // 1. 批量 PNG 导入
        const batchInput = document.getElementById("batch-file-input");
        const btnBatchPng = document.getElementById("btn-batch-png");
        if (btnBatchPng && batchInput) {
            btnBatchPng.onclick = () => batchInput.click();
            batchInput.onchange = async (e) => {
                const files = Array.from(e.target.files || []);
                if (files.length === 0) return;

                this.onStateCommit();
                for (const f of files) {
                    const base = f.name.replace(/\.[^/.]+$/, "");
                    const parsed = parseImageLayer(await loadImageDataFromSource(f));
                    this.ws.layerStack.push({
                        id: Date.now() + "_" + Math.random().toString(36).substr(2, 5),
                        name: base,
                        fileBaseName: base,
                        visible: true,
                        opacity: 1.0,
                        grid: parsed.grid,
                        width: parsed.width,
                        height: parsed.height,
                        uniqueColors: parsed.uniqueColors,
                        luaList: []
                    });
                }

                if (this.ws.activeLayerIndex === -1 && this.ws.layerStack.length > 0) {
                    this.ws.activeLayerIndex = 0;
                    this.ws.selectedLayerIndices = [0];
                    this.ws.lastClickedLayerIndex = 0;
                }

                this.onDataChanged();
                batchInput.value = "";
            };
        }

        // 2. 批量 Lua 导入
        const luaInput = document.getElementById("lua-file-input");
        const btnImportLua = document.getElementById("btn-import-lua");
        if (btnImportLua && luaInput) {
            btnImportLua.onclick = () => luaInput.click();
            luaInput.onchange = async (e) => {
                const files = Array.from(e.target.files || []);
                if (files.length === 0) return;

                this.onStateCommit();
                for (const f of files) {
                    const text = await f.text();
                    const tempKey = "import_" + Date.now();
                    this.cfg.importLuaConfig(text, tempKey);
                    const rules = this.cfg.getRules(tempKey);

                    const luaItem = {
                        id: "lua_" + Date.now() + "_" + Math.random().toString(36).substr(2, 4),
                        name: f.name,
                        rules: rules
                    };

                    const base = f.name.replace(/\.[^/.]+$/, "").toLowerCase().replace(/^config_/, "").replace(/_config$/, "");
                    const matched = this.ws.layerStack.find(l => l.name.toLowerCase().includes(base) || base.includes(l.name.toLowerCase()));

                    if (matched) {
                        matched.luaList = matched.luaList || [];
                        matched.luaList.push(luaItem);
                    } else {
                        this.ws.unassignedLua.push(luaItem);
                    }
                }

                this.onDataChanged();
                luaInput.value = "";
            };
        }

        // 3. 批量导出
        const btnBatchExport = document.getElementById("btn-batch-export");
        if (btnBatchExport) {
            btnBatchExport.onclick = () => {
                const targets = this.ws.selectedLayerIndices.length > 0
                    ? this.ws.selectedLayerIndices
                    : (this.ws.activeLayerIndex !== -1 ? [this.ws.activeLayerIndex] : []);

                if (targets.length === 0) return alert("请先选择图层！");

                const expPNG = document.getElementById("exp-chk-png")?.checked;
                const expConfig = document.getElementById("exp-chk-config")?.checked;
                const expData = document.getElementById("exp-chk-data")?.checked;
                if (!expPNG && !expConfig && !expData) return alert("请至少勾选一个导出项！");

                ExportManager.batchExport(
                    targets,
                    this.ws.layerStack,
                    this.cfg,
                    (layer) => this.sim.getMergedRulesForLayer(layer),
                    { expPNG, expConfig, expData }
                );
            };
        }
    }
}