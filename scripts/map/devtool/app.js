/**
 * app.js
 * 纯调度中枢 (Pure Orchestrator)
 */

import { ConfigStore } from "./core/config_store.js";
import { PaintEngine } from "./core/paint_engine.js";
import { SelectionEngine } from "./core/selection_engine.js";
import { pluginManager } from "./core/plugin_system.js";
import { CanvasView } from "./ui/canvas_view.js";
import { PluginWindow } from "./ui/ui_plugin_window.js";

import { HistoryManager } from "./managers/history_manager.js";
import { HotkeyManager } from "./managers/hotkey_manager.js";
import { WorkspaceManager } from "./managers/workspace_manager.js";
import { SimulationManager } from "./managers/simulation_manager.js";

import { HistoryController } from "./controllers/history_controller.js";
import { StrokeController } from "./controllers/stroke_controller.js";
import { FileController } from "./controllers/file_controller.js";
import { UIController } from "./controllers/ui_controller.js";
import { ViewportController } from "./controllers/viewport_controller.js";

// ============================================================================
// 一、单例装配与注入
// ============================================================================
const workspace = new WorkspaceManager();
const configStore = new ConfigStore();
const paintEngine = new PaintEngine();
const selectionEngine = new SelectionEngine();
const historyManager = new HistoryManager(30);
const simulation = new SimulationManager();

paintEngine.setSelectionEngine(selectionEngine);

// 声明外部占位，防范构造期暂时性死区 (TDZ)
let uiController = null;
let strokeController = null;
let viewportController = null;

// 数据变动中枢调度：精准支持 rerenderPanels 控制
function notifyDataChanged(options = {}) {
    const rerenderPanels = options.rerenderPanels !== false;

    viewport.setIconMap(simulation.extractActiveIconMap(workspace.layerStack));
    const simResult = simulation.runSimulation(workspace.layerStack, workspace.currentSeed);
    viewport.setLayerStack(workspace.layerStack, simResult);
    viewport.invalidateBake();
    workspace.saveCache();

    if (uiController) {
        uiController.refreshAll(rerenderPanels);
    }
}

const historyController = new HistoryController({
    workspace,
    historyManager,
    onApplyChange: notifyDataChanged
});

// ============================================================================
// 二、视口与专职控制器组装
// ============================================================================
const canvasEl = document.getElementById("viewport-canvas");
const viewport = new CanvasView(canvasEl, {
    selectionEngine,
    onHover: (data) => viewportController?.handleHover(data),
    onSelect: (colorHex, layerName) => viewportController?.handleSelect(colorHex, layerName),
    onRightClickToggleTool: () => viewportController?.handleRightClickToggle(),
    onStrokeStart: (tx, ty, tool) => strokeController?.handleStrokeStart(tx, ty, tool),
    onStrokeMove: (fx, fy, tx, ty) => strokeController?.handleStrokeMove(fx, fy, tx, ty),
    onStrokeEnd: () => strokeController?.handleStrokeEnd()
});

viewportController = new ViewportController({
    workspace,
    paintEngine,
    viewport,
    onLayerSelectRequest: (targetIdx) => {
        workspace.activeLayerIndex = targetIdx;
        workspace.selectedLayerIndices = [targetIdx];
        workspace.lastClickedLayerIndex = targetIdx;
        uiController.refreshLayerUI();
    },
    onRefreshToolbar: () => uiController.refreshToolbarUI(),
    onUpdatePanels: (rerender) => uiController.updatePanels(rerender)
});

uiController = new UIController({
    workspace,
    paintEngine,
    simulationManager: simulation,
    viewport,
    historyController,
    onDataChanged: notifyDataChanged,
    onTogglePlugins: () => pluginWindow.toggle()
});

strokeController = new StrokeController({
    workspace,
    paintEngine,
    selectionEngine,
    viewport,
    onStateCommit: () => historyController.pushSnapshot(),
    onRefreshUI: (opt) => {
        // 吸管吸色时同步更新规则卡片面板
        if (opt?.syncActiveRuleColor && window.__ruleCardHelpers) {
            window.__ruleCardHelpers.toggleColor(opt.syncActiveRuleColor, true);
            uiController.updatePanels(true);
        }
        if (opt?.full) {
            notifyDataChanged({ rerenderPanels: true });
        } else {
            workspace.saveCache();
            uiController.refreshToolbarUI();
        }
    }
});

new FileController({
    workspace,
    configStore,
    simulationManager: simulation,
    onStateCommit: () => historyController.pushSnapshot(),
    onDataChanged: notifyDataChanged
});

// ============================================================================
// 三、快捷键与宿主环境
// ============================================================================
new HotkeyManager({
    isSimulated: () => viewport.isSimulated,
    onToggleSimulate: () => {
        const cb = document.getElementById("cb-simulate");
        if (cb) {
            cb.checked = !cb.checked;
            cb.dispatchEvent(new Event("change"));
        }
    },
    onUndo: () => historyController.undo(),
    onRedo: () => historyController.redo(),
    onSelectTool: (tool) => {
        paintEngine.setTool(tool);
        viewport.setPaintToolState(tool, paintEngine.brushSize);
        uiController.refreshToolbarUI();
    },
    onClearSelection: () => {
        selectionEngine.clearSelection();
        viewport.isDirty = true;
    },
    onDoubleFillSelection: () => {
        const cur = workspace.getActiveLayer();
        if (selectionEngine.selectedPixels.size > 0 && cur) {
            historyController.pushSnapshot();
            selectionEngine.fillSelected(cur, paintEngine.currentColor);
            paintEngine.syncUniqueColors(cur);
            notifyDataChanged({ rerenderPanels: true });
        }
    },
    onSetSize: (size) => {
        paintEngine.setSize(size);
        viewport.setPaintToolState(paintEngine.currentTool, size);
        uiController.refreshToolbarUI();
    },
    onCopy: () => {
        const cur = workspace.getActiveLayer();
        if (cur && selectionEngine.copy(cur)) console.log("已复制选区像素");
    },
    onPaste: () => {
        if (selectionEngine.paste(viewport.hoveredTile?.x || 10, viewport.hoveredTile?.y || 10)) {
            paintEngine.setTool("select");
            viewport.setPaintToolState("select", paintEngine.brushSize);
            uiController.refreshToolbarUI();
            viewport.isDirty = true;
        }
    },
    onCommitFloating: () => {
        const cur = workspace.getActiveLayer();
        if (selectionEngine.floatingPiece && cur) {
            historyController.pushSnapshot();
            selectionEngine.commitFloating(cur);
            paintEngine.syncUniqueColors(cur);
            notifyDataChanged({ rerenderPanels: true });
        }
    },
    onFlipH: () => { selectionEngine.flipH(); viewport.isDirty = true; },
    onFlipV: () => { selectionEngine.flipV(); viewport.isDirty = true; },
    onDeleteSelected: () => {
        const cur = workspace.getActiveLayer();
        if (cur) {
            historyController.pushSnapshot();
            selectionEngine.deleteSelected(cur);
            paintEngine.syncUniqueColors(cur);
            notifyDataChanged({ rerenderPanels: true });
        }
    },
    onAltRelease: () => {
        viewport.setPaintToolState(paintEngine.currentTool, paintEngine.brushSize);
        uiController.refreshToolbarUI();
    }
});

const hostAPI = {
    getLayerStack: () => workspace.layerStack,
    getActiveLayer: () => workspace.getActiveLayer(),
    getActiveIndex: () => workspace.activeLayerIndex,
    getConfigStore: () => configStore,
    getSelection: () => selectionEngine,
    getPaintEngine: () => paintEngine,
    getViewport: () => viewport,
    getSimulationData: () => simulation.simulationResultCache,
    pushHistory: () => historyController.pushSnapshot(),
    invalidateBake: () => viewport.invalidateBake(),
    saveWorkspace: () => workspace.saveCache(),
    syncColors: (layer) => paintEngine.syncUniqueColors(layer),
    refreshUI: () => notifyDataChanged({ rerenderPanels: true }),
    notify: (msg) => alert(msg)
};
const pluginWindow = new PluginWindow(pluginManager, hostAPI);

window.__syncBrushColor = (hex) => {
    if (hex) {
        paintEngine.setColor(hex);
        uiController.refreshToolbarUI();
    }
};

// 启动初始渲染
uiController.refreshAll(true);