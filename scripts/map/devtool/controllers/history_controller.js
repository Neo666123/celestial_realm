/**
 * controllers/history_controller.js
 * 专职撤回与重做事务控制器 (带版本安全降级)
 */

export class HistoryController {
    constructor({ workspace, historyManager, onApplyChange }) {
        this.ws = workspace;
        this.hm = historyManager;
        this.onApplyChange = onApplyChange;

        this.bindButtons();
    }

    pushSnapshot() {
        const activeColor = window.__ruleCardHelpers ? window.__ruleCardHelpers.getActiveColor() : null;
        this.hm.push(
            this.ws.layerStack,
            this.ws.unassignedLua,
            this.ws.activeLayerIndex,
            this.ws.selectedLayerIndices,
            activeColor
        );
        this.updateUIState();
    }

    undo() {
        if (!this.canUndo()) {
            alert("已到达最早操作记录，无法继续撤回！");
            return;
        }
        const activeColor = window.__ruleCardHelpers ? window.__ruleCardHelpers.getActiveColor() : null;

        let prevSnapshot = null;
        if (typeof this.hm.undo === "function") {
            prevSnapshot = this.hm.undo(
                this.ws.layerStack,
                this.ws.unassignedLua,
                this.ws.activeLayerIndex,
                this.ws.selectedLayerIndices,
                activeColor
            );
        } else if (typeof this.hm.pop === "function") {
            prevSnapshot = this.hm.pop();
        }

        if (prevSnapshot) {
            this.applySnapshot(prevSnapshot);
        }
    }

    redo() {
        if (!this.canRedo()) {
            alert("已是最新操作记录，无法继续重做！");
            return;
        }
        const activeColor = window.__ruleCardHelpers ? window.__ruleCardHelpers.getActiveColor() : null;
        if (typeof this.hm.redo === "function") {
            const nextSnapshot = this.hm.redo(
                this.ws.layerStack,
                this.ws.unassignedLua,
                this.ws.activeLayerIndex,
                this.ws.selectedLayerIndices,
                activeColor
            );
            if (nextSnapshot) {
                this.applySnapshot(nextSnapshot);
            }
        }
    }

    canUndo() {
        return typeof this.hm.canUndo === "function" ? this.hm.canUndo() : (this.hm.undoStack && this.hm.undoStack.length > 0);
    }

    canRedo() {
        return typeof this.hm.canRedo === "function" ? this.hm.canRedo() : false;
    }

    applySnapshot(snapshot) {
        if (!snapshot) return;

        this.ws.layerStack = snapshot.layerStack;
        this.ws.unassignedLua = snapshot.unassignedLua || [];
        this.ws.activeLayerIndex = snapshot.activeLayerIndex;
        this.ws.selectedLayerIndices = snapshot.selectedLayerIndices ? [...snapshot.selectedLayerIndices] : [];
        this.ws.lastClickedLayerIndex = snapshot.activeLayerIndex;

        if (window.__ruleCardHelpers && snapshot.activeColor) {
            window.__ruleCardHelpers.setActiveColor(snapshot.activeColor);
        }

        if (this.onApplyChange) {
            this.onApplyChange({ rerenderPanels: true });
        }
        this.updateUIState();
    }

    bindButtons() {
        const btnUndo = document.getElementById("btn-undo");
        const btnRedo = document.getElementById("btn-redo");
        if (btnUndo) btnUndo.onclick = () => this.undo();
        if (btnRedo) btnRedo.onclick = () => this.redo();
        this.updateUIState();
    }

    updateUIState() {
        const btnUndo = document.getElementById("btn-undo");
        const btnRedo = document.getElementById("btn-redo");

        const ableUndo = this.canUndo();
        const ableRedo = this.canRedo();

        if (btnUndo) {
            btnUndo.disabled = !ableUndo;
            btnUndo.style.opacity = ableUndo ? "1" : "0.4";
            btnUndo.style.cursor = ableUndo ? "pointer" : "not-allowed";
        }
        if (btnRedo) {
            btnRedo.disabled = !ableRedo;
            btnRedo.style.opacity = ableRedo ? "1" : "0.4";
            btnRedo.style.cursor = ableRedo ? "pointer" : "not-allowed";
        }
    }
}