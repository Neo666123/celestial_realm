/**
 * ui/ui_toolbar.js
 * 纯净顶栏工具条组件 (集成 🧩 扩展插件悬浮窗开关按钮)
 */

export function renderToolbar(container, paintEngine, callbacks) {
    container.innerHTML = "";

    const safe = callbacks || {
        onToolChange: () => {},
        onColorChange: () => {},
        onSizeChange: () => {},
        onTogglePlugins: () => {},
    };

    const isSimulated = !!container.dataset.simulated;

    const bar = document.createElement("div");
    bar.className = "paint-toolbar";
    bar.style.cssText = `
        display: flex;
        align-items: center;
        gap: 8px;
        background: rgba(22, 24, 28, 0.94);
        border: 1px solid #374151;
        padding: 5px 12px;
        border-radius: 24px;
        box-shadow: 0 4px 16px rgba(0,0,0,0.5);
        backdrop-filter: blur(8px);
        pointer-events: auto;
        user-select: none;
        ${isSimulated ? 'opacity: 0.45; filter: grayscale(0.8);' : ''}
    `;

    // 1. 工具按钮组
    const toolGroup = document.createElement("div");
    toolGroup.style.cssText = "display: flex; gap: 3px; align-items: center;";

    const tools = [
        { id: "brush", icon: "🖌️", label: "画笔 (B)" },
        { id: "eraser", icon: "🧹", label: "橡皮 (X)" },
        { id: "select", icon: "✥", label: "选择/移动 (E)" },
        { id: "lasso", icon: "➰", label: "套索 (Q)" },
        { id: "bucket", icon: "🪣", label: "填充 (F/双击全填选区)" },
        { id: "picker", icon: "💧", label: "吸管 (Alt)" },
    ];

    tools.forEach(t => {
        const btn = document.createElement("button");
        const isActive = (paintEngine.currentTool === t.id);
        btn.className = `btn-sm ${isActive ? 'btn-active' : 'btn-secondary'}`;
        btn.innerHTML = `<span>${t.icon}</span>`;
        btn.title = t.label;
        btn.style.cssText = `padding: 3px 8px; border-radius: 12px; font-size: 12px; ${isActive ? 'background: #2563eb; color: #fff;' : ''}`;
        btn.disabled = isSimulated;

        btn.onclick = () => {
            if (isSimulated) return;
            paintEngine.setTool(t.id);
            safe.onToolChange(t.id);
            renderToolbar(container, paintEngine, callbacks);
        };
        toolGroup.appendChild(btn);
    });
    bar.appendChild(toolGroup);

    bar.appendChild(createDivider());

    // 2. 尺寸调节
    const sizeBox = document.createElement("div");
    sizeBox.style.cssText = "display: flex; align-items: center; gap: 4px; font-size: 11px; color: #94a3b8;";
    sizeBox.innerHTML = `
        <span style="font-size: 10px;">尺寸:</span>
        <button class="btn-secondary btn-sm btn-size-dec" style="padding: 1px 5px; border-radius: 8px;" ${isSimulated ? 'disabled' : ''}>-</button>
        <span class="size-val" style="font-family: monospace; font-weight: 700; color: #60a5fa; width: 14px; text-align: center;">${paintEngine.brushSize}</span>
        <button class="btn-secondary btn-sm btn-size-inc" style="padding: 1px 5px; border-radius: 8px;" ${isSimulated ? 'disabled' : ''}>+</button>
    `;

    sizeBox.querySelector(".btn-size-dec").onclick = () => {
        if (isSimulated) return;
        paintEngine.setSize(paintEngine.brushSize - 1);
        safe.onSizeChange(paintEngine.brushSize);
        renderToolbar(container, paintEngine, callbacks);
    };

    sizeBox.querySelector(".btn-size-inc").onclick = () => {
        if (isSimulated) return;
        paintEngine.setSize(paintEngine.brushSize + 1);
        safe.onSizeChange(paintEngine.brushSize);
        renderToolbar(container, paintEngine, callbacks);
    };
    bar.appendChild(sizeBox);

    bar.appendChild(createDivider());

    // 3. 当前色拾色器
    const colorBox = document.createElement("div");
    colorBox.style.cssText = "display: flex; align-items: center; gap: 5px;";
    colorBox.innerHTML = `
        <input type="color" class="tb-color-picker" value="${paintEngine.currentColor}" style="width: 20px; height: 20px; border: none; padding: 0; background: none; cursor: pointer;" title="修改画笔颜色" ${isSimulated ? 'disabled' : ''}>
        <input type="text" class="tb-hex-input" value="${paintEngine.currentColor}" style="width: 65px; font-family: monospace; font-size: 11px; text-align: center; padding: 2px 4px;" title="回车修改色号" ${isSimulated ? 'disabled' : ''}>
    `;

    const hexIpt = colorBox.querySelector(".tb-hex-input");
    const colPick = colorBox.querySelector(".tb-color-picker");

    const updateColor = (hex) => {
        if (!hex || isSimulated) return;
        const clean = (hex.startsWith("#") ? hex : "#" + hex).toLowerCase();
        paintEngine.setColor(clean);
        safe.onColorChange(clean);
        renderToolbar(container, paintEngine, callbacks);
    };

    hexIpt.onkeydown = (e) => { if (e.key === "Enter") updateColor(hexIpt.value); };
    hexIpt.onblur = () => updateColor(hexIpt.value);
    colPick.onchange = (e) => updateColor(e.target.value);
    bar.appendChild(colorBox);

    bar.appendChild(createDivider());

    // 4. 工程色板抽屉
    const paletteDrawer = document.createElement("div");
    paletteDrawer.style.cssText = "display: flex; align-items: center; gap: 4px; max-width: 200px; overflow-x: auto; padding: 2px 0;";

    const usedColors = extractProjectColors(callbacks.layerStack);
    if (usedColors.length === 0) {
        paletteDrawer.innerHTML = `<span style="font-size: 10px; color: #64748b;">暂无工程色</span>`;
    } else {
        usedColors.forEach(col => {
            const isCur = (col.toLowerCase() === paintEngine.currentColor.toLowerCase());
            const dot = document.createElement("div");
            dot.style.cssText = `
                width: 15px;
                height: 15px;
                border-radius: 3px;
                background: ${col};
                cursor: pointer;
                flex-shrink: 0;
                border: 1px solid ${isCur ? '#ffffff' : 'rgba(255,255,255,0.2)'};
                box-shadow: ${isCur ? '0 0 5px #38bdf8' : 'none'};
                transition: transform 0.1s;
            `;
            dot.title = `点击切换画笔色: ${col}`;
            dot.onmouseenter = () => { dot.style.transform = "scale(1.2)"; };
            dot.onmouseleave = () => { dot.style.transform = "scale(1.0)"; };
            dot.onclick = () => {
                if (isSimulated) return;
                updateColor(col);
            };
            paletteDrawer.appendChild(dot);
        });
    }
    bar.appendChild(paletteDrawer);

    bar.appendChild(createDivider());

    // 5. Photoshop 风格扩展插件入口按钮
    const btnExt = document.createElement("button");
    btnExt.className = "btn-secondary btn-sm";
    btnExt.style.cssText = "padding: 3px 8px; border-radius: 12px; font-size: 11px; background: #334155; color: #38bdf8;";
    btnExt.innerHTML = `<span>🧩 插件</span>`;
    btnExt.title = "打开扩展插件悬浮窗口";
    btnExt.onclick = () => safe.onTogglePlugins();
    bar.appendChild(btnExt);

    if (isSimulated) {
        const tip = document.createElement("span");
        tip.style.cssText = "font-size: 10px; color: #f59e0b; margin-left: 4px; font-weight: 600;";
        tip.innerText = "🔒 模拟中(Space可切换)";
        bar.appendChild(tip);
    }

    container.appendChild(bar);
}

function createDivider() {
    const d = document.createElement("div");
    d.style.cssText = "width: 1px; height: 16px; background: #374151; margin: 0 2px;";
    return d;
}

function extractProjectColors(layerStack) {
    if (!layerStack) return [];
    const set = new Set();
    layerStack.forEach(l => {
        if (l.uniqueColors) {
            l.uniqueColors.forEach(c => {
                if (c && c.startsWith("#")) set.add(c.toLowerCase());
            });
        }
    });
    return Array.from(set);
}