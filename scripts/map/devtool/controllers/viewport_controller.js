/**
 * controllers/viewport_controller.js
 * 专职视口交互与悬浮属性检查控制器
 */

export class ViewportController {
    constructor({ workspace, paintEngine, viewport, onLayerSelectRequest, onRefreshToolbar, onUpdatePanels }) {
        this.ws = workspace;
        this.pe = paintEngine;
        this.vp = viewport;
        this.onLayerSelectRequest = onLayerSelectRequest;
        this.onRefreshToolbar = onRefreshToolbar;
        this.onUpdatePanels = onUpdatePanels; // 注入更新面板回调

        this.elCoord = document.getElementById("insp-coord");
        this.elTile = document.getElementById("insp-tile");
        this.elColor = document.getElementById("insp-color");
        this.elEntities = document.getElementById("insp-entities");
    }

    handleHover(data) {
        if (!data) return;
        if (this.elCoord) this.elCoord.innerText = `X: ${data.x}, Y: ${data.y}`;
        if (this.elTile) this.elTile.innerText = `ID: ${data.tileId}`;
        if (this.elColor) this.elColor.innerText = `${data.rawColor} (Tier ${data.rawTier})`;
        if (this.elEntities) {
            this.elEntities.innerText = (data.entities && data.entities.length > 0)
                ? data.entities.map(e => e.prefab).join(", ")
                : "无";
        }
    }

    handleSelect(colorHex, layerName) {
        if (!colorHex) return;

        if (layerName) {
            const targetIdx = this.ws.layerStack.findIndex(l => l.name === layerName);
            if (targetIdx !== -1 && targetIdx !== this.ws.activeLayerIndex) {
                if (this.onLayerSelectRequest) this.onLayerSelectRequest(targetIdx);
            }
        }

        if (window.__ruleCardHelpers) {
            window.__ruleCardHelpers.toggleColor(colorHex, true);
        }

        // 对齐原版：选中地皮后刷新面板展示对应色卡
        if (this.onUpdatePanels) {
            this.onUpdatePanels(true);
        }

        const target = document.getElementById(`rule-card-${colorHex.replace("#", "").toLowerCase()}`);
        if (target) {
            target.scrollIntoView({ behavior: "smooth", block: "center" });
            target.classList.add("highlight");
            setTimeout(() => target.classList.remove("highlight"), 1200);
        }
    }

    handleRightClickToggle() {
        this.pe.togglePrevTool();
        this.vp.setPaintToolState(this.pe.currentTool, this.pe.brushSize);
        if (this.onRefreshToolbar) this.onRefreshToolbar();
    }
}