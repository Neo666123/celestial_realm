/**
 * managers/workspace_manager.js
 * 工作区数据与缓存状态管理中心
 * 职责：负责图层栈管理、未分配 Lua 脚本、选区索引维护以及 IndexedDB 会话缓存
 */

export class WorkspaceManager {
    constructor() {
        this.layerStack = [];
        this.unassignedLua = [];
        this.activeLayerIndex = -1;
        this.selectedLayerIndices = [];
        this.lastClickedLayerIndex = -1;
        this.currentSeed = 12345;
    }

    getActiveLayer() {
        return (this.activeLayerIndex >= 0 && this.activeLayerIndex < this.layerStack.length)
            ? this.layerStack[this.activeLayerIndex]
            : null;
    }

    addBlankLayer() {
        const w = this.layerStack.length > 0 ? this.layerStack[0].width : 256;
        const h = this.layerStack.length > 0 ? this.layerStack[0].height : 256;
        const emptyGrid = Array.from({ length: h + 1 }, () => Array(w + 1).fill("empty"));
        const newName = `layer_new_${this.layerStack.length + 1}`;

        const newLayer = {
            id: Date.now() + "_" + Math.random().toString(36).substr(2, 5),
            name: newName,
            fileBaseName: newName,
            visible: true,
            opacity: 1.0,
            grid: emptyGrid,
            width: w,
            height: h,
            uniqueColors: [],
            luaList: []
        };

        this.layerStack.push(newLayer);
        this.activeLayerIndex = this.layerStack.length - 1;
        this.selectedLayerIndices = [this.activeLayerIndex];
        this.lastClickedLayerIndex = this.activeLayerIndex;
        return newLayer;
    }

    // ------------------------------------------------------------------------
    // IndexedDB 状态缓存与还原
    // ------------------------------------------------------------------------
    openWorkspaceDB() {
        return new Promise((resolve, reject) => {
            const req = indexedDB.open("CelestialMapDB", 2);
            req.onupgradeneeded = () => {
                const db = req.result;
                if (!db.objectStoreNames.contains("store")) db.createObjectStore("store");
            };
            req.onsuccess = () => resolve(req.result);
            req.onerror = () => reject(req.error);
        });
    }

    async saveCache() {
        try {
            const cacheData = {
                layerStack: this.layerStack.map(l => ({
                    name: l.name,
                    fileBaseName: l.fileBaseName,
                    visible: l.visible,
                    opacity: l.opacity,
                    width: l.width,
                    height: l.height,
                    uniqueColors: l.uniqueColors,
                    grid: l.grid,
                    luaList: l.luaList || []
                })),
                unassignedLua: this.unassignedLua,
                activeLayerIndex: this.activeLayerIndex,
                currentSeed: this.currentSeed,
                timestamp: Date.now()
            };
            const db = await this.openWorkspaceDB();
            const tx = db.transaction("store", "readwrite");
            tx.objectStore("store").put(cacheData, "last_session");
        } catch (e) {
            console.error("缓存写入失败:", e);
        }
    }

    async restoreCache() {
        const db = await this.openWorkspaceDB();
        return new Promise((resolve, reject) => {
            const tx = db.transaction("store", "readonly");
            const req = tx.objectStore("store").get("last_session");
            req.onsuccess = () => {
                const data = req.result;
                if (!data || !data.layerStack || data.layerStack.length === 0) {
                    return resolve(null);
                }
                this.layerStack = data.layerStack;
                this.unassignedLua = data.unassignedLua || [];
                this.activeLayerIndex = data.activeLayerIndex !== undefined ? data.activeLayerIndex : 0;
                this.selectedLayerIndices = [this.activeLayerIndex];
                this.lastClickedLayerIndex = this.activeLayerIndex;
                if (data.currentSeed) this.currentSeed = data.currentSeed;
                resolve(data);
            };
            req.onerror = () => reject(req.error);
        });
    }
}