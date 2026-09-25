/**
 * ui/canvas_view.js
 * 纯视口渲染器 (调度相机变换、离线烘焙与多通道 Overlay 绘制)
 */

import { ViewportCamera } from "./viewport_camera.js";
import { ViewportBaker } from "./viewport_baker.js";

export class CanvasView {
    constructor(canvasElement, options = {}) {
        this.canvas = canvasElement;
        this.ctx = canvasElement.getContext("2d");

        // 装配相机与烘焙子模块
        this.camera = new ViewportCamera({ initialScale: 16, minScale: 2, maxScale: 128 });
        this.baker = new ViewportBaker();

        this.layerStack = [];
        this.mapData = null;
        this.iconMap = {};
        this.selectedTile = null;
        this.hoveredTile = null;
        this.isSimulated = true;

        // 交互输入状态
        this.isDragging = false;
        this.isRightMouseDown = false;
        this.dragStartX = 0;
        this.dragStartY = 0;
        this.lastMouseX = 0;
        this.lastMouseY = 0;

        this.isPainting = false;
        this.lastPaintTileX = null;
        this.lastPaintTileY = null;
        this.activePaintTool = "brush";
        this.activePaintSize = 1;

        // 回调订阅
        this.selectionEngine = options.selectionEngine || null;
        this.onHoverCallback = options.onHover || null;
        this.onSelectCallback = options.onSelect || null;
        this.onRightClickToggleTool = options.onRightClickToggleTool || null;
        this.onStrokeStart = options.onStrokeStart || null;
        this.onStrokeMove = options.onStrokeMove || null;
        this.onStrokeEnd = options.onStrokeEnd || null;

        this.isDirty = true;
        this.bindEvents();
        this.startRenderLoop();
    }

    // ------------------------------------------------------------------------
    // 兼容外层属性访问代理 (确保外部零破坏)
    // ------------------------------------------------------------------------
    get scale() { return this.camera.scale; }
    set scale(v) { this.camera.scale = v; }
    get panX() { return this.camera.panX; }
    set panX(v) { this.camera.panX = v; }
    get panY() { return this.camera.panY; }
    set panY(v) { this.camera.panY = v; }
    get offscreenCanvas() { return this.baker.offscreenCanvas; }
    get offscreenCtx() { return this.baker.offscreenCtx; }
    get needsBake() { return this.baker.needsBake; }
    set needsBake(v) { this.baker.needsBake = v; }

    setIconMap(map) {
        this.iconMap = map || {};
        this.isDirty = true;
    }

    setPaintToolState(tool, size) {
        this.activePaintTool = tool || "brush";
        this.activePaintSize = size || 1;
        this.isDirty = true;
    }

    invalidateBake() {
        this.baker.invalidate();
        this.isDirty = true;
    }

    screenToWorldTile(screenX, screenY) {
        return this.camera.screenToWorldTile(screenX, screenY);
    }

    setLayerStack(layers, simulationResult) {
        this.layerStack = layers;
        this.mapData = simulationResult;

        if (simulationResult?.width && simulationResult?.height) {
            if (this.camera.scale === 16 && this.camera.panX === 50) {
                this.camera.fitToViewport(this.canvas.width, this.canvas.height, simulationResult.width, simulationResult.height);
            }
        }
        this.invalidateBake();
    }

    // ------------------------------------------------------------------------
    // 视口输入交互事件监听
    // ------------------------------------------------------------------------
    bindEvents() {
        this.canvas.addEventListener("wheel", (e) => {
            e.preventDefault();
            const rect = this.canvas.getBoundingClientRect();
            const mouseX = e.clientX - rect.left;
            const mouseY = e.clientY - rect.top;

            if (this.camera.handleZoom(mouseX, mouseY, e.deltaY)) {
                this.isDirty = true;
            }
        }, { passive: false });

        this.canvas.addEventListener("mousedown", (e) => {
            const rect = this.canvas.getBoundingClientRect();
            const screenX = e.clientX - rect.left;
            const screenY = e.clientY - rect.top;
            const { tileX, tileY } = this.screenToWorldTile(screenX, screenY);

            if (e.button === 0) {
                if (!this.isSimulated) {
                    this.isPainting = true;
                    this.lastPaintTileX = tileX;
                    this.lastPaintTileY = tileY;
                    if (this.onStrokeStart) {
                        this.onStrokeStart(tileX, tileY, e.altKey ? "picker" : this.activePaintTool);
                    }
                } else {
                    this.pickTileColor(tileX, tileY);
                }
            } else if (e.button === 1 || e.button === 2) {
                this.isRightMouseDown = true;
                this.isDragging = false;
                this.dragStartX = e.clientX;
                this.dragStartY = e.clientY;
                this.lastMouseX = e.clientX;
                this.lastMouseY = e.clientY;
                e.preventDefault();
            }
        });

        window.addEventListener("mousemove", (e) => {
            if (this.isRightMouseDown) {
                const moveDist = Math.hypot(e.clientX - this.dragStartX, e.clientY - this.dragStartY);
                if (moveDist > 4) this.isDragging = true;
                if (this.isDragging) {
                    this.camera.panBy(e.clientX - this.lastMouseX, e.clientY - this.lastMouseY);
                    this.lastMouseX = e.clientX;
                    this.lastMouseY = e.clientY;
                    this.isDirty = true;
                }
            } else {
                const rect = this.canvas.getBoundingClientRect();
                const screenX = e.clientX - rect.left;
                const screenY = e.clientY - rect.top;
                const { tileX, tileY } = this.screenToWorldTile(screenX, screenY);

                if (this.isPainting && !this.isSimulated) {
                    if (this.lastPaintTileX !== tileX || this.lastPaintTileY !== tileY) {
                        if (this.onStrokeMove) {
                            this.onStrokeMove(this.lastPaintTileX, this.lastPaintTileY, tileX, tileY);
                        }
                        this.lastPaintTileX = tileX;
                        this.lastPaintTileY = tileY;
                    }
                }
                this.handleMouseMove(e);
            }
        });

        window.addEventListener("mouseup", (e) => {
            if (e.button === 0 && this.isPainting) {
                this.isPainting = false;
                this.lastPaintTileX = null;
                this.lastPaintTileY = null;
                if (this.onStrokeEnd) this.onStrokeEnd();
            } else if (e.button === 2) {
                if (this.isRightMouseDown && !this.isDragging && this.onRightClickToggleTool) {
                    this.onRightClickToggleTool();
                }
                this.isRightMouseDown = false;
                this.isDragging = false;
            } else if (e.button === 1) {
                this.isRightMouseDown = false;
                this.isDragging = false;
            }
        });

        this.canvas.addEventListener("contextmenu", (e) => e.preventDefault());
        window.addEventListener("resize", () => this.resizeCanvas());
        this.resizeCanvas();
    }

    resizeCanvas() {
        if (!this.canvas.parentElement) return;
        const rect = this.canvas.parentElement.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0) {
            this.canvas.width = rect.width;
            this.canvas.height = rect.height;
            this.isDirty = true;
        }
    }

    pickTileColor(tileX, tileY) {
        for (let i = this.layerStack.length - 1; i >= 0; i--) {
            const layer = this.layerStack[i];
            if (layer.visible && layer.grid && layer.grid[tileY] && layer.grid[tileY][tileX]) {
                const cell = layer.grid[tileY][tileX];
                const col = (cell && typeof cell === "object") ? cell.color : cell;
                if (col && col !== "empty") {
                    this.selectedTile = { x: tileX, y: tileY };
                    this.isDirty = true;
                    if (this.onSelectCallback) this.onSelectCallback(col, layer.name);
                    return;
                }
            }
        }
    }

    handleMouseMove(e) {
        if (!this.mapData) return;
        const rect = this.canvas.getBoundingClientRect();
        const { tileX, tileY } = this.screenToWorldTile(e.clientX - rect.left, e.clientY - rect.top);
        const { width, height, finalTiles, entities } = this.mapData;

        // 动态光标设置
        if (!this.isSimulated && this.activePaintTool === "select") {
            if (this.selectionEngine && (this.selectionEngine.isSelected(tileX, tileY) || this.selectionEngine.floatingPiece)) {
                this.canvas.style.cursor = "move";
            } else {
                this.canvas.style.cursor = "default";
            }
        } else if (!this.isSimulated && this.activePaintTool === "lasso") {
            this.canvas.style.cursor = "crosshair";
        } else {
            this.canvas.style.cursor = "default";
        }

        if (tileX >= 1 && tileX <= width && tileY >= 1 && tileY <= height) {
            let topColor = "虚空";
            let topTier = 0;

            for (let i = this.layerStack.length - 1; i >= 0; i--) {
                const layer = this.layerStack[i];
                if (layer.visible && layer.grid && layer.grid[tileY] && layer.grid[tileY][tileX]) {
                    const c = layer.grid[tileY][tileX];
                    if (c) {
                        topColor = (typeof c === "object") ? c.color : c;
                        topTier = (typeof c === "object") ? (c.tier || 1) : 1;
                        break;
                    }
                }
            }

            const entitiesAtTile = entities.filter(ent => Math.floor(ent.x) === tileX && Math.floor(ent.y) === tileY);

            if (!this.hoveredTile || this.hoveredTile.x !== tileX || this.hoveredTile.y !== tileY) {
                this.hoveredTile = { x: tileX, y: tileY };
                this.isDirty = true;
            }

            if (this.onHoverCallback) {
                this.onHoverCallback({
                    x: tileX,
                    y: tileY,
                    tileId: finalTiles[tileY] ? finalTiles[tileY][tileX] : 1,
                    rawColor: topColor,
                    rawTier: topTier,
                    entities: entitiesAtTile,
                });
            }
        } else if (this.hoveredTile !== null) {
            this.hoveredTile = null;
            this.isDirty = true;
            if (this.onHoverCallback) this.onHoverCallback(null);
        }
    }

    startRenderLoop() {
        const render = () => {
            if (this.isDirty || this.baker.needsBake) {
                this.draw();
                this.isDirty = false;
            }
            requestAnimationFrame(render);
        };
        requestAnimationFrame(render);
    }

    // ------------------------------------------------------------------------
    // 复合渲染流水线
    // ------------------------------------------------------------------------
    draw() {
        const { ctx, canvas } = this;
        ctx.fillStyle = "#0c0d0e";
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        if (!this.mapData || this.layerStack.length === 0) {
            ctx.fillStyle = "#555";
            ctx.font = "13px sans-serif";
            ctx.textAlign = "center";
            ctx.fillText("请在左上方批量导入 PNG 图片图层", canvas.width / 2, canvas.height / 2);
            return;
        }

        if (this.baker.needsBake) {
            this.baker.bake(this.mapData, this.layerStack, this.isSimulated);
        }

        const { width, height, entities } = this.mapData;
        const scale = this.camera.scale;

        ctx.save();
        ctx.translate(this.camera.panX, this.camera.panY);
        ctx.imageSmoothingEnabled = false;

        // 1. 贴图渲染底图
        ctx.drawImage(this.baker.offscreenCanvas, 0, 0, width, height, 0, 0, width * scale, height * scale);

        // 2. 模拟态：渲染实体
        if (this.isSimulated && entities && entities.length > 0) {
            this.renderEntities(ctx, entities, scale);
        }

        // 3. 多级自适应动态网格
        this.renderGrids(ctx, width, height, scale);

        // 4. 选区与浮动切片
        if (this.selectionEngine) {
            this.renderSelection(ctx, scale);
        }

        // 5. 画笔/悬浮光标指示框
        this.renderCursorIndicator(ctx, scale);

        // 6. 拾取地皮高亮框
        if (this.selectedTile) {
            ctx.strokeStyle = "#ec4899";
            ctx.lineWidth = 2.5;
            ctx.strokeRect((this.selectedTile.x - 1) * scale, (this.selectedTile.y - 1) * scale, scale, scale);
        }

        ctx.restore();
    }

    renderEntities(ctx, entities, scale) {
        for (let i = 0; i < entities.length; i++) {
            const ent = entities[i];
            const px = (ent.x % 1 !== 0) ? ent.x * scale : (ent.x - 1) * scale + scale / 2;
            const py = (ent.y % 1 !== 0) ? ent.y * scale : (ent.y - 1) * scale + scale / 2;

            const rawIcon = this.iconMap ? this.iconMap[ent.prefab] : null;
            let iconChar = null;
            let iconSize = 14;

            if (rawIcon) {
                if (typeof rawIcon === "object") {
                    iconChar = rawIcon.char;
                    iconSize = rawIcon.size || 14;
                } else {
                    iconChar = String(rawIcon);
                }
            }

            if (iconChar) {
                const dynamicSize = Math.max(8, Math.min(64, Math.round(iconSize * (scale / 16))));
                ctx.font = `${dynamicSize}px -apple-system, BlinkMacSystemFont, "Segoe UI Emoji", "Noto Color Emoji", sans-serif`;
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";
                ctx.shadowColor = "rgba(0, 0, 0, 0.9)";
                ctx.shadowBlur = 3;
                ctx.fillStyle = "#ffffff";
                ctx.fillText(iconChar, px, py);
                ctx.shadowBlur = 0;
            } else {
                if (ent.x % 1 !== 0 || ent.y % 1 !== 0) {
                    ctx.fillStyle = "#facc15";
                    const dotSize = Math.max(scale * 0.25, 3);
                    ctx.fillRect(px - dotSize / 2, py - dotSize / 2, dotSize, dotSize);
                } else {
                    const radius = Math.max(scale * 0.35, 3.5);
                    ctx.beginPath();
                    ctx.arc(px, py, radius, 0, Math.PI * 2);
                    ctx.fillStyle = "#38bdf8";
                    ctx.fill();
                    ctx.strokeStyle = "#ffffff";
                    ctx.lineWidth = 1.5;
                    ctx.stroke();
                }
            }
        }
    }

    renderGrids(ctx, width, height, scale) {
        if (scale >= 14) {
            ctx.strokeStyle = "rgba(255, 255, 255, 0.05)";
            ctx.lineWidth = 1;
            ctx.beginPath();
            for (let x = 0; x <= width; x++) {
                if (x % 4 !== 0) { ctx.moveTo(x * scale, 0); ctx.lineTo(x * scale, height * scale); }
            }
            for (let y = 0; y <= height; y++) {
                if (y % 4 !== 0) { ctx.moveTo(0, y * scale); ctx.lineTo(width * scale, y * scale); }
            }
            ctx.stroke();
        }

        if (scale >= 6) {
            ctx.strokeStyle = "rgba(255, 255, 255, 0.12)";
            ctx.lineWidth = 1.0;
            ctx.beginPath();
            for (let x = 0; x <= width; x += 4) {
                if (x % 16 !== 0) { ctx.moveTo(x * scale, 0); ctx.lineTo(x * scale, height * scale); }
            }
            for (let y = 0; y <= height; y += 4) {
                if (y % 16 !== 0) { ctx.moveTo(0, y * scale); ctx.lineTo(width * scale, y * scale); }
            }
            ctx.stroke();
        }

        if (scale >= 2) {
            ctx.strokeStyle = "rgba(148, 163, 184, 0.28)";
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            for (let x = 0; x <= width; x += 16) {
                ctx.moveTo(x * scale, 0); ctx.lineTo(x * scale, height * scale);
            }
            for (let y = 0; y <= height; y += 16) {
                ctx.moveTo(0, y * scale); ctx.lineTo(width * scale, y * scale);
            }
            ctx.stroke();
        }

        ctx.strokeStyle = "rgba(255, 255, 255, 0.4)";
        ctx.lineWidth = 1.5;
        ctx.strokeRect(0, 0, width * scale, height * scale);
    }

    renderSelection(ctx, scale) {
        if (this.selectionEngine.polygonPath.length > 1) {
            ctx.beginPath();
            const poly = this.selectionEngine.polygonPath;
            ctx.moveTo((poly[0].x - 0.5) * scale, (poly[0].y - 0.5) * scale);
            for (let i = 1; i < poly.length; i++) {
                ctx.lineTo((poly[i].x - 0.5) * scale, (poly[i].y - 0.5) * scale);
            }
            ctx.strokeStyle = "#38bdf8";
            ctx.lineWidth = 1.5;
            ctx.stroke();
        }

        if (this.selectionEngine.selectedPixels.size > 0) {
            const set = this.selectionEngine.selectedPixels;
            ctx.save();
            ctx.setLineDash([4, 4]);
            ctx.lineDashOffset = (Date.now() / 80) % 8;
            ctx.strokeStyle = "#ffffff";
            ctx.lineWidth = 1.5;
            ctx.shadowColor = "#000000";
            ctx.shadowBlur = 2;

            ctx.beginPath();
            set.forEach(key => {
                const [x, y] = key.split("_").map(Number);
                const x0 = (x - 1) * scale;
                const x1 = x * scale;
                const y0 = (y - 1) * scale;
                const y1 = y * scale;

                if (!set.has(`${x}_${y - 1}`)) { ctx.moveTo(x0, y0); ctx.lineTo(x1, y0); }
                if (!set.has(`${x}_${y + 1}`)) { ctx.moveTo(x0, y1); ctx.lineTo(x1, y1); }
                if (!set.has(`${x - 1}_${y}`)) { ctx.moveTo(x0, y0); ctx.lineTo(x0, y1); }
                if (!set.has(`${x + 1}_${y}`)) { ctx.moveTo(x1, y0); ctx.lineTo(x1, y1); }
            });
            ctx.stroke();
            ctx.restore();
        }

        if (this.selectionEngine.floatingPiece) {
            const { x, y, items } = this.selectionEngine.floatingPiece;
            for (const it of items) {
                const px = (x + it.dx - 1) * scale;
                const py = (y + it.dy - 1) * scale;
                if (it.cell && it.cell !== "empty") {
                    ctx.fillStyle = (typeof it.cell === 'object') ? it.cell.color : it.cell;
                    ctx.fillRect(px, py, scale, scale);
                }
            }
            ctx.save();
            ctx.setLineDash([3, 3]);
            ctx.strokeStyle = "#38bdf8";
            ctx.lineWidth = 1.5;
            items.forEach(it => {
                if (it.cell && it.cell !== "empty") {
                    ctx.strokeRect((x + it.dx - 1) * scale, (y + it.dy - 1) * scale, scale, scale);
                }
            });
            ctx.restore();
        }
    }

    renderCursorIndicator(ctx, scale) {
        if (!this.isSimulated && this.hoveredTile && (this.activePaintTool === "brush" || this.activePaintTool === "eraser")) {
            const size = this.activePaintSize || 1;
            const half = Math.floor(size / 2);
            const boxX = (this.hoveredTile.x - 1 - half) * scale;
            const boxY = (this.hoveredTile.y - 1 - half) * scale;
            const boxW = size * scale;
            const boxH = size * scale;

            ctx.fillStyle = (this.activePaintTool === "eraser") ? "rgba(239, 68, 68, 0.2)" : "rgba(56, 189, 248, 0.2)";
            ctx.fillRect(boxX, boxY, boxW, boxH);

            ctx.setLineDash([3, 3]);
            ctx.strokeStyle = (this.activePaintTool === "eraser") ? "#ef4444" : "#38bdf8";
            ctx.lineWidth = 1.5;
            ctx.strokeRect(boxX, boxY, boxW, boxH);
            ctx.setLineDash([]);
        } else if (this.hoveredTile && this.activePaintTool !== "select") {
            ctx.strokeStyle = "rgba(255, 235, 59, 0.7)";
            ctx.lineWidth = 2;
            ctx.strokeRect((this.hoveredTile.x - 1) * scale, (this.hoveredTile.y - 1) * scale, scale, scale);
        }
    }
}