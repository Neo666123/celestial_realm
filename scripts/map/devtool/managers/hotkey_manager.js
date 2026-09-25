/**
 * managers/hotkey_manager.js
 * 专职全局快捷键分发 (Space / B / X / E / Q / F / 1~9 / H / V / Ctrl+C / Ctrl+V / Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z)
 */

export class HotkeyManager {
    constructor(callbacks) {
        this.cb = callbacks || {};
        this.lastFPressTime = 0;
        this.lastQPressTime = 0;
        this.bindEvents();
    }

    bindEvents() {
        window.addEventListener("keydown", (e) => {
            const tag = document.activeElement ? document.activeElement.tagName : "";
            if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;

            const key = e.key.toLowerCase();

            // 1. 空格键：启停模拟
            if (e.code === "Space") {
                e.preventDefault();
                if (this.cb.onToggleSimulate) this.cb.onToggleSimulate();
                return;
            }

            // 2. 撤回：Ctrl + Z (且未按 Shift)
            if ((e.ctrlKey || e.metaKey) && key === "z" && !e.shiftKey) {
                e.preventDefault();
                if (this.cb.onUndo) this.cb.onUndo();
                return;
            }

            // 3. 重做：Ctrl + Y 或 Ctrl + Shift + Z
            if (((e.ctrlKey || e.metaKey) && key === "y") || ((e.ctrlKey || e.metaKey) && key === "z" && e.shiftKey)) {
                e.preventDefault();
                if (this.cb.onRedo) this.cb.onRedo();
                return;
            }

            if (this.cb.isSimulated && this.cb.isSimulated()) return;

            // 4. 工具切换
            if (key === "b" && this.cb.onSelectTool) this.cb.onSelectTool("brush");
            if (key === "x" && this.cb.onSelectTool) this.cb.onSelectTool("eraser");
            if (key === "e" && this.cb.onSelectTool) this.cb.onSelectTool("select");

            // 5. 双击 Q 取消选区 / 单击 Q 切换套索
            if (key === "q") {
                const now = Date.now();
                if (now - this.lastQPressTime < 320) {
                    if (this.cb.onClearSelection) this.cb.onClearSelection();
                } else {
                    if (this.cb.onSelectTool) this.cb.onSelectTool("lasso");
                }
                this.lastQPressTime = now;
            }

            // 6. 双击 F 全选区灌色 / 单击 F 切换油漆桶
            if (key === "f") {
                const now = Date.now();
                if (now - this.lastFPressTime < 350) {
                    if (this.cb.onDoubleFillSelection) this.cb.onDoubleFillSelection();
                } else {
                    if (this.cb.onSelectTool) this.cb.onSelectTool("bucket");
                }
                this.lastFPressTime = now;
            }

            // 7. 数字键 1 ~ 9 调整画笔尺寸
            if (e.key >= "1" && e.key <= "9" && this.cb.onSetSize) {
                this.cb.onSetSize(parseInt(e.key, 10));
            }

            // 8. 选区剪切板与变形
            if ((e.ctrlKey || e.metaKey) && key === "c" && this.cb.onCopy) this.cb.onCopy();
            if ((e.ctrlKey || e.metaKey) && key === "v" && this.cb.onPaste) this.cb.onPaste();
            if (e.key === "Enter" && this.cb.onCommitFloating) this.cb.onCommitFloating();
            if (key === "h" && this.cb.onFlipH) this.cb.onFlipH();
            if (key === "v" && this.cb.onFlipV) this.cb.onFlipV();
            if ((e.key === "Delete" || e.key === "Backspace") && this.cb.onDeleteSelected) this.cb.onDeleteSelected();
        });

        window.addEventListener("keyup", (e) => {
            if (e.key === "Alt" && this.cb.onAltRelease) {
                this.cb.onAltRelease();
            }
        });
    }
}