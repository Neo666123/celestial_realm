/**
 * core/selection_engine.js
 * 纯算法选区引擎：
 * 1. 射线法多边形栅格化 (Point-in-Polygon)
 * 2. 选区像素自动提取拔起 (Lift) 与平移落印 (Commit & Reselect)
 * 3. 选区浮动切片拖拽、H/V 翻转与剪贴板 (Ctrl+C / Ctrl+V)
 */

export class SelectionEngine {
    constructor() {
        this.selectedPixels = new Set(); // 存储 "x_y" 键
        this.polygonPath = [];            // 套索绘制中的临时点 [{x, y}]
        this.clipboard = null;            // 剪贴板缓存
        this.floatingPiece = null;        // 浮动待落印切片 { x, y, items: [{dx, dy, cell}] }
        this.isMovingFloating = false;
    }

    hasSelection() {
        return this.selectedPixels.size > 0 || this.floatingPiece !== null;
    }

    isSelected(x, y) {
        if (this.selectedPixels.size === 0) return false;
        return this.selectedPixels.has(`${x}_${y}`);
    }

    clearSelection() {
        this.selectedPixels.clear();
        this.polygonPath = [];
        this.floatingPiece = null;
        this.isMovingFloating = false;
    }

    startLasso(x, y) {
        this.polygonPath = [{ x, y }];
    }

    addLassoPoint(x, y) {
        const last = this.polygonPath[this.polygonPath.length - 1];
        if (!last || last.x !== x || last.y !== y) {
            this.polygonPath.push({ x, y });
        }
    }

    finishLasso(width, height) {
        if (this.polygonPath.length < 3) {
            this.polygonPath = [];
            return;
        }

        let minX = width, maxX = 1, minY = height, maxY = 1;
        for (const pt of this.polygonPath) {
            if (pt.x < minX) minX = pt.x;
            if (pt.x > maxX) maxX = pt.x;
            if (pt.y < minY) minY = pt.y;
            if (pt.y > maxY) maxY = pt.y;
        }

        minX = Math.max(1, minX);
        maxX = Math.min(width, maxX);
        minY = Math.max(1, minY);
        maxY = Math.min(height, maxY);

        // 射线交叉法将多边形栅格化为像素坐标
        for (let y = minY; y <= maxY; y++) {
            for (let x = minX; x <= maxX; x++) {
                if (this.isPointInPoly(x, y, this.polygonPath)) {
                    this.selectedPixels.add(`${x}_${y}`);
                }
            }
        }
        this.polygonPath = [];
    }

    isPointInPoly(x, y, poly) {
        let inside = false;
        for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
            const xi = poly[i].x, yi = poly[i].y;
            const xj = poly[j].x, yj = poly[j].y;
            const intersect = ((yi > y) !== (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
            if (intersect) inside = !inside;
        }
        return inside;
    }

    /**
     * 核心：将选区内的像素从原网格中拔起，变为浮动切片，原位挖空为透明
     */
    liftSelection(layer) {
        if (this.selectedPixels.size === 0 || !layer || !layer.grid) return false;
        let minX = Infinity, minY = Infinity;

        this.selectedPixels.forEach(key => {
            const [x, y] = key.split("_").map(Number);
            if (x < minX) minX = x;
            if (y < minY) minY = y;
        });

        const items = [];
        this.selectedPixels.forEach(key => {
            const [x, y] = key.split("_").map(Number);
            const cell = layer.grid[y] && layer.grid[y][x];
            items.push({
                dx: x - minX,
                dy: y - minY,
                cell: (cell && typeof cell === "object") ? { color: cell.color, tier: cell.tier || 1 } : cell
            });
            if (layer.grid[y]) {
                layer.grid[y][x] = "empty";
            }
        });

        this.floatingPiece = {
            x: minX,
            y: minY,
            items: items
        };
        this.selectedPixels.clear();
        this.isMovingFloating = true;
        return true;
    }

    /**
     * 核心：移动结束落笔，将浮动切片盖印到新坐标，并将选区蚂蚁线同步更新到新位置
     */
    commitFloatingAndReselect(layer) {
        if (!this.floatingPiece || !layer || !layer.grid) return;
        const { x, y, items } = this.floatingPiece;
        this.selectedPixels.clear();

        for (const it of items) {
            const px = x + it.dx;
            const py = y + it.dy;
            if (px >= 1 && px <= layer.width && py >= 1 && py <= layer.height) {
                if (it.cell && it.cell !== "empty") {
                    layer.grid[py][px] = it.cell;
                }
                this.selectedPixels.add(`${px}_${py}`);
            }
        }
        this.floatingPiece = null;
        this.isMovingFloating = false;
    }

    copy(layer) {
        if (this.selectedPixels.size === 0 || !layer || !layer.grid) return false;
        const items = [];
        let minX = Infinity, minY = Infinity;

        this.selectedPixels.forEach(key => {
            const [x, y] = key.split("_").map(Number);
            if (x < minX) minX = x;
            if (y < minY) minY = y;
        });

        this.selectedPixels.forEach(key => {
            const [x, y] = key.split("_").map(Number);
            const cell = layer.grid[y] && layer.grid[y][x];
            if (cell && cell !== "empty") {
                items.push({
                    dx: x - minX,
                    dy: y - minY,
                    cell: (typeof cell === "object") ? { color: cell.color, tier: cell.tier || 1 } : cell
                });
            }
        });

        if (items.length === 0) return false;
        this.clipboard = items;
        return true;
    }

    paste(targetX, targetY) {
        if (!this.clipboard || this.clipboard.length === 0) return false;
        this.floatingPiece = {
            x: targetX || 10,
            y: targetY || 10,
            items: JSON.parse(JSON.stringify(this.clipboard))
        };
        this.selectedPixels.clear();
        return true;
    }

    commitFloating(layer) {
        this.commitFloatingAndReselect(layer);
    }

    flipH() {
        const target = this.floatingPiece ? this.floatingPiece.items : null;
        if (!target) return;
        let maxDx = 0;
        target.forEach(it => { if (it.dx > maxDx) maxDx = it.dx; });
        target.forEach(it => { it.dx = maxDx - it.dx; });
    }

    flipV() {
        const target = this.floatingPiece ? this.floatingPiece.items : null;
        if (!target) return;
        let maxDy = 0;
        target.forEach(it => { if (it.dy > maxDy) maxDy = it.dy; });
        target.forEach(it => { it.dy = maxDy - it.dy; });
    }

    deleteSelected(layer) {
        if (!layer || !layer.grid) return;
        if (this.selectedPixels.size > 0) {
            this.selectedPixels.forEach(key => {
                const [x, y] = key.split("_").map(Number);
                if (layer.grid[y]) layer.grid[y][x] = "empty";
            });
            this.clearSelection();
        } else if (this.floatingPiece) {
            this.floatingPiece = null;
            this.isMovingFloating = false;
        } else {
            for (let y = 1; y <= layer.height; y++) {
                if (layer.grid[y]) layer.grid[y].fill("empty");
            }
        }
    }

    fillSelected(layer, color) {
        if (!layer || !layer.grid || this.selectedPixels.size === 0) return;
        this.selectedPixels.forEach(key => {
            const [x, y] = key.split("_").map(Number);
            if (layer.grid[y] && x >= 1 && x <= layer.width) {
                layer.grid[y][x] = { color: color, tier: 1 };
            }
        });
    }
}