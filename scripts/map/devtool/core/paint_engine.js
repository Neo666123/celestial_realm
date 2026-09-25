/**
 * core/paint_engine.js
 * 纯算法像素绘图引擎：
 * 1. Bresenham 连续线段插值 (防鼠标甩太快漏点)
 * 2. 1~9 档方块像素笔刷与橡皮擦除
 * 3. 选区遮罩限制：有选区时涂抹严格限制在选区内
 * 4. 四邻域 BFS 油漆桶泛洪填充
 * 5. 离线 Canvas 增量修补
 */

export class PaintEngine {
    constructor() {
        this.currentTool = "brush"; // "brush" | "eraser" | "select" | "lasso" | "bucket" | "picker"
        this.prevTool = "eraser";
        this.brushSize = 1;
        this.currentColor = "#76a88c";
        this.selectionEngine = null;
    }

    setSelectionEngine(engine) {
        this.selectionEngine = engine;
    }

    setTool(tool) {
        if (tool !== this.currentTool) {
            this.prevTool = this.currentTool;
            this.currentTool = tool;
        }
    }

    togglePrevTool() {
        const temp = this.currentTool;
        this.currentTool = this.prevTool;
        this.prevTool = temp;
    }

    setSize(size) {
        this.brushSize = Math.max(1, Math.min(9, parseInt(size, 10) || 1));
    }

    setColor(hex) {
        if (hex && hex.startsWith("#")) {
            this.currentColor = hex.toLowerCase();
        }
    }

    getLinePoints(x0, y0, x1, y1) {
        const points = [];
        const dx = Math.abs(x1 - x0);
        const dy = Math.abs(y1 - y0);
        const sx = (x0 < x1) ? 1 : -1;
        const sy = (y0 < y1) ? 1 : -1;
        let err = dx - dy;
        let cx = x0;
        let cy = y0;

        while (true) {
            points.push({ x: cx, y: cy });
            if (cx === x1 && cy === y1) break;
            const e2 = 2 * err;
            if (e2 > -dy) {
                err -= dy;
                cx += sx;
            }
            if (e2 < dx) {
                err += dx;
                cy += sy;
            }
        }
        return points;
    }

    applyStamp(layer, centerX, centerY, size, cellValue, offscreenCtx) {
        if (!layer || !layer.grid) return;
        const { width, height, grid } = layer;
        const half = Math.floor(size / 2);

        for (let dy = -half; dy < size - half; dy++) {
            for (let dx = -half; dx < size - half; dx++) {
                const px = centerX + dx;
                const py = centerY + dy;

                if (px >= 1 && px <= width && py >= 1 && py <= height) {
                    // 选区保护：如果存在选区，圈外像素受绝对保护，禁止涂抹
                    if (this.selectionEngine && this.selectionEngine.hasSelection() && !this.selectionEngine.isSelected(px, py)) {
                        continue;
                    }

                    if (cellValue === "empty") {
                        grid[py][px] = "empty";
                        if (offscreenCtx) {
                            offscreenCtx.fillStyle = "#0c0d0e";
                            offscreenCtx.fillRect(px - 1, py - 1, 1, 1);
                        }
                    } else {
                        grid[py][px] = { color: cellValue.color, tier: cellValue.tier || 1 };
                        if (offscreenCtx) {
                            offscreenCtx.fillStyle = cellValue.color;
                            offscreenCtx.fillRect(px - 1, py - 1, 1, 1);
                        }
                    }
                }
            }
        }
    }

    drawContinuousStroke(layer, fromX, fromY, toX, toY, offscreenCtx) {
        const points = this.getLinePoints(fromX, fromY, toX, toY);
        const isEraser = (this.currentTool === "eraser");
        const cellVal = isEraser ? "empty" : { color: this.currentColor, tier: 1 };

        for (let i = 0; i < points.length; i++) {
            const pt = points[i];
            this.applyStamp(layer, pt.x, pt.y, this.brushSize, cellVal, offscreenCtx);
        }
        this.syncUniqueColors(layer);
    }

    drawSinglePoint(layer, x, y, offscreenCtx) {
        const isEraser = (this.currentTool === "eraser");
        const cellVal = isEraser ? "empty" : { color: this.currentColor, tier: 1 };
        this.applyStamp(layer, x, y, this.brushSize, cellVal, offscreenCtx);
        this.syncUniqueColors(layer);
    }

    floodFill(layer, startX, startY, offscreenCtx) {
        if (!layer || !layer.grid) return;
        const { width, height, grid } = layer;
        if (startX < 1 || startX > width || startY < 1 || startY > height) return;

        const startCell = grid[startY] && grid[startY][startX];
        const targetColor = (startCell && typeof startCell === "object") ? startCell.color.toLowerCase() : "empty";
        const fillColor = this.currentColor.toLowerCase();

        if (targetColor === fillColor) return;

        const visited = Array.from({ length: height + 1 }, () => new Uint8Array(width + 1));
        const queue = [{ x: startX, y: startY }];
        visited[startY][startX] = 1;

        const dirs = [
            { dx: 1, dy: 0 },
            { dx: -1, dy: 0 },
            { dx: 0, dy: 1 },
            { dx: 0, dy: -1 },
        ];

        let head = 0;
        while (head < queue.length) {
            const { x, y } = queue[head++];

            grid[y][x] = { color: this.currentColor, tier: 1 };
            if (offscreenCtx) {
                offscreenCtx.fillStyle = this.currentColor;
                offscreenCtx.fillRect(x - 1, y - 1, 1, 1);
            }

            for (let i = 0; i < dirs.length; i++) {
                const nx = x + dirs[i].dx;
                const ny = y + dirs[i].dy;

                if (nx >= 1 && nx <= width && ny >= 1 && ny <= height && !visited[ny][nx]) {
                    const nCell = grid[ny] && grid[ny][nx];
                    const nColor = (nCell && typeof nCell === "object") ? nCell.color.toLowerCase() : "empty";

                    if (nColor === targetColor) {
                        visited[ny][nx] = 1;
                        queue.push({ x: nx, y: ny });
                    }
                }
            }
        }
        this.syncUniqueColors(layer);
    }

    pickTopmostColor(layerStack, x, y) {
        for (let i = layerStack.length - 1; i >= 0; i--) {
            const layer = layerStack[i];
            if (!layer.visible || !layer.grid) continue;
            const cell = layer.grid[y] && layer.grid[y][x];
            const col = (cell && typeof cell === "object") ? cell.color : cell;
            if (col && col !== "empty" && col.startsWith("#")) {
                this.setColor(col);
                return col.toLowerCase();
            }
        }
        return null;
    }

    syncUniqueColors(layer) {
        if (!layer || !layer.grid) return;
        const set = new Set();
        for (let y = 1; y <= layer.height; y++) {
            const row = layer.grid[y];
            if (!row) continue;
            for (let x = 1; x <= layer.width; x++) {
                const cell = row[x];
                const col = (cell && typeof cell === "object") ? cell.color : cell;
                if (col && col !== "empty" && col.startsWith("#")) {
                    set.add(col.toLowerCase());
                }
            }
        }
        layer.uniqueColors = Array.from(set);
    }
}