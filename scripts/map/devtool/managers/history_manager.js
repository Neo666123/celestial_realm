/**
 * managers/history_manager.js
 * 专职管理全局撤回与重做历史快照栈 (Memento 模式双向链栈)
 */

export class HistoryManager {
    constructor(maxSteps = 30) {
        this.undoStack = [];
        this.redoStack = [];
        this.maxSteps = maxSteps;
    }

    deepCloneGrid(grid, width, height) {
        if (!grid) return null;
        const cloned = Array.from({ length: height + 1 }, () => new Array(width + 1).fill(null));
        for (let y = 1; y <= height; y++) {
            const row = grid[y];
            if (!row) continue;
            for (let x = 1; x <= width; x++) {
                const cell = row[x];
                if (cell && typeof cell === "object") {
                    cloned[y][x] = { color: cell.color, tier: cell.tier || 1 };
                } else {
                    cloned[y][x] = cell;
                }
            }
        }
        return cloned;
    }

    /**
     * 生成当前工作区的不可变深拷贝快照
     */
    createSnapshot(layerStack, unassignedLua, activeLayerIndex, selectedLayerIndices, activeColor) {
        return {
            layerStack: (layerStack || []).map(l => ({
                id: l.id,
                name: l.name,
                fileBaseName: l.fileBaseName,
                visible: l.visible,
                opacity: l.opacity,
                width: l.width,
                height: l.height,
                uniqueColors: [...(l.uniqueColors || [])],
                grid: this.deepCloneGrid(l.grid, l.width, l.height),
                luaList: (l.luaList || []).map(item => ({
                    id: item.id,
                    name: item.name,
                    rules: JSON.parse(JSON.stringify(item.rules || {}))
                }))
            })),
            unassignedLua: (unassignedLua || []).map(item => ({
                id: item.id,
                name: item.name,
                rules: JSON.parse(JSON.stringify(item.rules || {}))
            })),
            activeLayerIndex: activeLayerIndex ?? 0,
            selectedLayerIndices: selectedLayerIndices ? [...selectedLayerIndices] : [],
            activeColor: activeColor || null
        };
    }

    /**
     * 记录新操作快照
     * 一旦发生新的主动改动，根据标准撤回逻辑，必须清空 redoStack
     */
    push(layerStack, unassignedLua, activeLayerIndex, selectedLayerIndices, activeColor) {
        try {
            const snapshot = this.createSnapshot(layerStack, unassignedLua, activeLayerIndex, selectedLayerIndices, activeColor);
            this.undoStack.push(snapshot);
            if (this.undoStack.length > this.maxSteps) {
                this.undoStack.shift();
            }
            // 新操作入栈，打断重做链
            this.redoStack = [];
        } catch (err) {
            console.warn("快照备份失败:", err);
        }
    }

    /**
     * 撤回操作：将当前状态保存至 redoStack，并弹出返回上一历史快照
     */
    undo(layerStack, unassignedLua, activeLayerIndex, selectedLayerIndices, activeColor) {
        if (!this.canUndo()) return null;
        try {
            if (layerStack) {
                const currentSnap = this.createSnapshot(layerStack, unassignedLua, activeLayerIndex, selectedLayerIndices, activeColor);
                this.redoStack.push(currentSnap);
                if (this.redoStack.length > this.maxSteps) {
                    this.redoStack.shift();
                }
            }
            return this.undoStack.pop();
        } catch (err) {
            console.warn("撤回操作失败:", err);
            return null;
        }
    }

    /**
     * 重做操作：将当前状态保存至 undoStack，并弹出返回下一个快照
     */
    redo(layerStack, unassignedLua, activeLayerIndex, selectedLayerIndices, activeColor) {
        if (!this.canRedo()) return null;
        try {
            if (layerStack) {
                const currentSnap = this.createSnapshot(layerStack, unassignedLua, activeLayerIndex, selectedLayerIndices, activeColor);
                this.undoStack.push(currentSnap);
                if (this.undoStack.length > this.maxSteps) {
                    this.undoStack.shift();
                }
            }
            return this.redoStack.pop();
        } catch (err) {
            console.warn("重做操作失败:", err);
            return null;
        }
    }

    /**
     * 兼容旧接口的简单弹出
     */
    pop() {
        if (this.undoStack.length === 0) return null;
        return this.undoStack.pop();
    }

    canUndo() {
        return this.undoStack.length > 0;
    }

    canRedo() {
        return this.redoStack.length > 0;
    }

    clear() {
        this.undoStack = [];
        this.redoStack = [];
    }
}