/**
 * controllers/stroke_controller.js
 * 纯画布笔触交互控制器
 * 职责：调度 PaintEngine, SelectionEngine 与 CanvasView 的鼠标事件流与图元操作
 */

export class StrokeController {
    constructor({ workspace, paintEngine, selectionEngine, viewport, onStateCommit, onRefreshUI }) {
        this.ws = workspace;
        this.pe = paintEngine;
        this.se = selectionEngine;
        this.vp = viewport;
        this.onStateCommit = onStateCommit; // 产生改动前提交历史快照
        this.onRefreshUI = onRefreshUI;     // 通知 UI 控制器刷新
    }

    handleStrokeStart(tileX, tileY, toolType) {
        const curLayer = this.ws.getActiveLayer();
        if (!curLayer) return;

        // 1. 套索 Q：开始圈选
        if (toolType === "lasso") {
            this.se.startLasso(tileX, tileY);
            this.vp.isDirty = true;
            return;
        }

        // 2. 选择/移动 E：拔起平移选区
        if (toolType === "select") {
            if (this.se.hasSelection() && this.se.isSelected(tileX, tileY)) {
                this.onStateCommit();
                this.se.liftSelection(curLayer);
                this.pe.syncUniqueColors(curLayer);
                this.vp.invalidateBake();
                this.vp.isDirty = true;
                return;
            }
            if (this.se.floatingPiece) {
                this.se.isMovingFloating = true;
                return;
            }
            if (this.se.hasSelection()) {
                this.se.clearSelection();
                this.vp.isDirty = true;
                return;
            }
            this.vp.pickTileColor(tileX, tileY);
            return;
        }

        // 3. 吸管
        if (toolType === "picker") {
            const picked = this.pe.pickTopmostColor(this.ws.layerStack, tileX, tileY);
            if (picked) {
                this.pe.setColor(picked);
                this.onRefreshUI({ syncActiveRuleColor: picked });
            }
            return;
        }

        // 4. 油漆桶
        if (toolType === "bucket") {
            this.onStateCommit();
            if (this.se.selectedPixels.size > 0 && this.se.isSelected(tileX, tileY)) {
                this.se.fillSelected(curLayer, this.pe.currentColor);
                this.pe.syncUniqueColors(curLayer);
            } else {
                this.pe.floodFill(curLayer, tileX, tileY, this.vp.offscreenCtx);
            }
            this.vp.invalidateBake();
            this.onRefreshUI({ full: true });
            return;
        }

        // 5. 普通画笔 / 橡皮落笔
        this.onStateCommit();
        this.pe.drawSinglePoint(curLayer, tileX, tileY, this.vp.offscreenCtx);
        this.vp.isDirty = true;
    }

    handleStrokeMove(fromX, fromY, toX, toY) {
        const curLayer = this.ws.getActiveLayer();
        if (!curLayer) return;

        if (this.pe.currentTool === "lasso") {
            this.se.addLassoPoint(toX, toY);
            this.vp.isDirty = true;
            return;
        }

        if (this.pe.currentTool === "select") {
            if (this.se.floatingPiece && this.se.isMovingFloating) {
                this.se.floatingPiece.x += (toX - fromX);
                this.se.floatingPiece.y += (toY - fromY);
                this.vp.isDirty = true;
            }
            return;
        }

        if (this.pe.currentTool === "picker" || this.pe.currentTool === "bucket") return;

        this.pe.drawContinuousStroke(curLayer, fromX, fromY, toX, toY, this.vp.offscreenCtx);
        this.vp.isDirty = true;
    }

    handleStrokeEnd() {
        const curLayer = this.ws.getActiveLayer();
        if (!curLayer) return;

        if (this.pe.currentTool === "lasso") {
            this.se.finishLasso(curLayer.width, curLayer.height);
            this.vp.isDirty = true;
            return;
        }

        if (this.pe.currentTool === "select") {
            if (this.se.isMovingFloating && this.se.floatingPiece) {
                this.se.commitFloatingAndReselect(curLayer);
                this.pe.syncUniqueColors(curLayer);
                this.vp.invalidateBake();
                this.onRefreshUI({ full: true });
            }
            return;
        }

        this.onRefreshUI({ toolbarOnly: true });
    }
}