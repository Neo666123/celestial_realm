/**
 * ui/viewport_camera.js
 * 专职相机系统：处理视口缩放、平移、自适应居中与屏幕/世界坐标双向换算
 */

export class ViewportCamera {
    constructor({ minScale = 2, maxScale = 128, initialScale = 16 } = {}) {
        this.scale = initialScale;
        this.minScale = minScale;
        this.maxScale = maxScale;
        this.panX = 50;
        this.panY = 50;
    }

    /**
     * 屏幕坐标转世界瓦片坐标 (1-based)
     */
    screenToWorldTile(screenX, screenY) {
        return {
            tileX: Math.floor((screenX - this.panX) / this.scale) + 1,
            tileY: Math.floor((screenY - this.panY) / this.scale) + 1,
        };
    }

    /**
     * 以鼠标所在屏幕坐标为中心进行定点等比缩放
     */
    handleZoom(mouseX, mouseY, deltaY) {
        const zoomFactor = deltaY < 0 ? 1.15 : 0.85;
        const newScale = Math.min(Math.max(this.scale * zoomFactor, this.minScale), this.maxScale);

        if (newScale !== this.scale) {
            this.panX = mouseX - (mouseX - this.panX) * (newScale / this.scale);
            this.panY = mouseY - (mouseY - this.panY) * (newScale / this.scale);
            this.scale = newScale;
            return true;
        }
        return false;
    }

    /**
     * 平移视口
     */
    panBy(dx, dy) {
        this.panX += dx;
        this.panY += dy;
    }

    /**
     * 自动缩放并居中适配地图尺寸
     */
    fitToViewport(canvasWidth, canvasHeight, mapWidth, mapHeight) {
        if (!mapWidth || !mapHeight || canvasWidth <= 0 || canvasHeight <= 0) return;
        const fitScale = Math.min((canvasWidth - 80) / mapWidth, (canvasHeight - 80) / mapHeight);
        this.scale = Math.max(Math.floor(fitScale), 4);
        this.panX = Math.floor((canvasWidth - mapWidth * this.scale) / 2);
        this.panY = Math.floor((canvasHeight - mapHeight * this.scale) / 2);
    }
}