/**
 * ui/viewport_baker.js
 * 专职离线纹理烘焙器：压平多图层位图、计算虚空遮蔽与着色
 */

export class ViewportBaker {
    constructor() {
        this.offscreenCanvas = document.createElement("canvas");
        this.offscreenCtx = this.offscreenCanvas.getContext("2d");
        this.needsBake = true;

        this.TILE_COLORS = {
            1: "#0c0d0e",
            2: "#4e5959",
            3: "#bfa37c",
            4: "#4ade80",
            5: "#15803d",
            6: "#334155",
            7: "#94a3b8",
            41: "#80761c",
            42: "#9bb2b3",
            43: "#76a88c",
            44: "#518468",
        };
    }

    invalidate() {
        this.needsBake = true;
    }

    bake(mapData, layerStack, isSimulated) {
        if (!mapData || !mapData.width || !mapData.height) return;
        const { width, height } = mapData;

        if (this.offscreenCanvas.width !== width || this.offscreenCanvas.height !== height) {
            this.offscreenCanvas.width = width;
            this.offscreenCanvas.height = height;
        }

        const octx = this.offscreenCtx;
        octx.fillStyle = "#0c0d0e";
        octx.fillRect(0, 0, width, height);

        if (!isSimulated) {
            // 编辑模式：自底向上绘制，遇到挖空地皮实心覆盖下层，切穿透底
            for (let i = 0; i < layerStack.length; i++) {
                const layer = layerStack[i];
                if (!layer.visible || !layer.grid) continue;

                octx.globalAlpha = layer.opacity !== undefined ? layer.opacity : 1.0;
                for (let y = 1; y <= height; y++) {
                    const row = layer.grid[y];
                    if (!row) continue;
                    for (let x = 1; x <= width; x++) {
                        const cell = row[x];
                        const col = (typeof cell === "object") ? cell?.color : cell;
                        if (col && col !== "empty") {
                            const cfg = layer.config && (layer.config[col] || layer.config[col.toLowerCase()]);
                            const isVoid = (col === "void" || col === "挖空") ||
                                (cfg && (cfg.rule === "挖空" || cfg.rule === "挖空地皮" || cfg.tile === "挖空" || cfg.is_void));

                            if (isVoid) {
                                octx.fillStyle = "#0c0d0e";
                                octx.fillRect(x - 1, y - 1, 1, 1);
                            } else {
                                octx.fillStyle = col;
                                octx.fillRect(x - 1, y - 1, 1, 1);
                            }
                        }
                    }
                }
            }
            octx.globalAlpha = 1.0;
        } else {
            // 模拟模式：以最终解算 finalTiles 为绝对物理标准
            if (mapData.finalTiles) {
                const finalTiles = mapData.finalTiles;
                const simulatedColors = mapData.simulatedColors;

                for (let y = 1; y <= height; y++) {
                    const row = finalTiles[y];
                    if (!row) continue;
                    for (let x = 1; x <= width; x++) {
                        const tid = row[x] || 1;
                        if (tid === 1) {
                            octx.fillStyle = "#0c0d0e";
                            octx.fillRect(x - 1, y - 1, 1, 1);
                        } else {
                            let landColor = simulatedColors && simulatedColors[y] && simulatedColors[y][x];
                            if (!landColor || landColor === "#0c0d0e") {
                                for (let i = layerStack.length - 1; i >= 0; i--) {
                                    const layer = layerStack[i];
                                    if (!layer.visible || !layer.grid) continue;
                                    const cell = layer.grid[y] && layer.grid[y][x];
                                    const col = (typeof cell === "object") ? cell?.color : cell;
                                    if (col && col !== "empty" && col !== "void" && col !== "挖空") {
                                        landColor = col;
                                        break;
                                    }
                                }
                            }
                            octx.fillStyle = landColor || this.TILE_COLORS[tid] || "#76a88c";
                            octx.fillRect(x - 1, y - 1, 1, 1);
                        }
                    }
                }
            }
        }

        this.needsBake = false;
    }
}