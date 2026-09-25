/**
 * ui/ui_layers.js
 * Photoshop 风格图层栈：
 * 纯粹的图层堆叠管理，恢复完整的图层名显示宽度与双击重命名
 */

let draggedData = null;

const TIER_ALPHA_RESTORE = {
    1: 255,
    2: 191,
    3: 128,
    4: 64,
};

export function exportLayerAsPNG(layer) {
    if (!layer || !layer.grid || !layer.width || !layer.height) {
        alert("图层数据不完整，无法导出 PNG");
        return;
    }
    const canvas = document.createElement("canvas");
    canvas.width = layer.width;
    canvas.height = layer.height;
    const ctx = canvas.getContext("2d");
    const imgData = ctx.createImageData(layer.width, layer.height);
    const data = imgData.data;

    for (let y = 1; y <= layer.height; y++) {
        const row = layer.grid[y];
        if (!row) continue;
        for (let x = 1; x <= layer.width; x++) {
            const cell = row[x];
            const col = typeof cell === "object" ? cell?.color : cell;
            const tier = typeof cell === "object" ? (cell?.tier || 1) : 1;

            if (col && col !== "empty" && col.startsWith("#")) {
                const hex = col.replace("#", "");
                const r = parseInt(hex.substring(0, 2), 16) || 0;
                const g = parseInt(hex.substring(2, 4), 16) || 0;
                const b = parseInt(hex.substring(4, 6), 16) || 0;
                const a = TIER_ALPHA_RESTORE[tier] !== undefined ? TIER_ALPHA_RESTORE[tier] : 255;

                const idx = ((y - 1) * layer.width + (x - 1)) * 4;
                data[idx] = r;
                data[idx + 1] = g;
                data[idx + 2] = b;
                data[idx + 3] = a;
            }
        }
    }

    ctx.putImageData(imgData, 0, 0);
    const a = document.createElement("a");
    a.href = canvas.toDataURL("image/png");
    a.download = `${layer.name || "layer"}.png`;
    a.click();
}

export function renderLayerStackUI(container, layerStack, unassignedLua, activeIndex, selectedIndices, callbacks) {
    container.innerHTML = "";

    const safe = callbacks || {
        onSelectLayer: () => {},
        onChange: () => {},
        onOpacityChange: () => {},
        onMoveLua: () => {},
        onDeleteLua: () => {},
        onAddBlankLayer: () => {},
        onMergeLayers: () => {},
    };

    const selSet = new Set(selectedIndices || [activeIndex]);

    // 0. 工具条
    const toolBar = document.createElement("div");
    toolBar.style.cssText = "display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;";

    const canMerge = selSet.size >= 2;
    toolBar.innerHTML = `
        <button class="btn-secondary btn-sm btn-merge-layers" style="font-size: 11px; padding: 2px 8px; ${canMerge ? 'background: #0284c7; color: #fff;' : 'opacity: 0.4; cursor: not-allowed;'}" ${canMerge ? '' : 'disabled'}>
            🔀 合并选中图层 (${selSet.size})
        </button>
        <button class="btn-secondary btn-sm btn-add-layer" style="font-size: 11px; padding: 2px 8px;">+ 新建空白图层</button>
    `;

    toolBar.querySelector(".btn-add-layer").onclick = () => safe.onAddBlankLayer();
    if (canMerge) {
        toolBar.querySelector(".btn-merge-layers").onclick = () => safe.onMergeLayers();
    }
    container.appendChild(toolBar);

    // 1. 待分配 Lua 缓冲池
    const poolBox = document.createElement("div");
    poolBox.className = "unassigned-lua-box";
    poolBox.style.cssText = "background: #17191d; border: 1px dashed #3a3f4a; border-radius: 5px; padding: 8px; margin-bottom: 10px;";

    const poolHeader = document.createElement("div");
    poolHeader.style.cssText = "font-size: 11px; font-weight: 600; color: #94a3b8; margin-bottom: 6px; display: flex; justify-content: space-between;";
    poolHeader.innerHTML = `<span>📂 待分配 Lua 配置池 (${unassignedLua.length})</span><span style="font-size: 10px; color: #64748b;">拖拽至图层进行绑定</span>`;
    poolBox.appendChild(poolHeader);

    const poolList = document.createElement("div");
    poolList.style.cssText = "display: flex; flex-direction: column; gap: 4px; min-height: 28px;";

    if (unassignedLua.length === 0) {
        poolList.innerHTML = `<div style="font-size: 11px; color: #475569; text-align: center; padding: 4px;">暂无闲置 Lua 配置</div>`;
    } else {
        unassignedLua.forEach((item, lIdx) => {
            const el = createLuaBadge(item, { from: "unassigned", luaIdx: lIdx }, safe);
            poolList.appendChild(el);
        });
    }

    poolBox.ondragover = (e) => {
        if (draggedData && draggedData.type === "LUA") {
            e.preventDefault();
            poolBox.style.borderColor = "#3b82f6";
            poolBox.style.background = "#1e2430";
        }
    };
    poolBox.ondragleave = () => {
        poolBox.style.borderColor = "#3a3f4a";
        poolBox.style.background = "#17191d";
    };
    poolBox.ondrop = (e) => {
        e.preventDefault();
        poolBox.style.borderColor = "#3a3f4a";
        poolBox.style.background = "#17191d";
        if (draggedData && draggedData.type === "LUA" && draggedData.from !== "unassigned") {
            safe.onMoveLua(draggedData, { to: "unassigned" });
        }
    };

    poolBox.appendChild(poolList);
    container.appendChild(poolBox);

    // 2. 主图层列表
    for (let idx = layerStack.length - 1; idx >= 0; idx--) {
        const layer = layerStack[idx];
        layer.luaList = layer.luaList || [];

        const isSelected = selSet.has(idx);
        const isActive = (idx === activeIndex);

        const item = document.createElement("div");
        item.className = "layer-item" + (isSelected ? " selected" : "") + (isActive ? " active" : "");

        const header = document.createElement("div");
        header.style.cssText = "display: flex; align-items: center; gap: 6px; width: 100%;";
        header.draggable = true;
        header.style.cursor = "grab";

        // 去掉下拉框，恢复图层名的完整展示宽度
        header.innerHTML = `
            <span class="drag-handle" style="color:#6b7280; font-size:12px; cursor:grab; user-select:none;">☰</span>
            <span class="btn-toggle-vis" style="cursor:pointer; font-size:13px;" title="显隐">${layer.visible ? "👁️" : "🕶️"}</span>
            <span class="layer-name" style="flex:1; font-size:12px; font-weight:600; color:#f3f4f6; cursor:pointer; text-overflow:ellipsis; overflow:hidden; white-space:nowrap;" title="双击重命名">${layer.name}</span>
            <input type="range" class="layer-opacity" min="0" max="1" step="0.05" value="${layer.opacity}" style="width:45px; cursor:pointer;" title="透明度" draggable="false">
            <button class="btn-secondary btn-sm btn-export-png" style="padding:1px 5px; font-size:10px;" title="导出PNG">💾</button>
            <button class="btn-danger btn-sm btn-del" style="padding:1px 5px;">×</button>
        `;

        const opacityInput = header.querySelector(".layer-opacity");
        const btnToggleVis = header.querySelector(".btn-toggle-vis");
        const btnExportPNG = header.querySelector(".btn-export-png");
        const btnDel = header.querySelector(".btn-del");
        const layerNameEl = header.querySelector(".layer-name");

        layerNameEl.onclick = (e) => {
            safe.onSelectLayer(idx, { shiftKey: e.shiftKey, ctrlKey: (e.ctrlKey || e.metaKey) });
        };

        // 丝滑双击重命名
        layerNameEl.ondblclick = (e) => {
            e.stopPropagation();
            const oldName = layer.name;
            const ipt = document.createElement("input");
            ipt.type = "text";
            ipt.value = oldName;
            ipt.style.cssText = "flex: 1; font-size: 11px; background: #111; color: #fff; border: 1px solid #3b82f6; padding: 1px 4px; border-radius: 3px; min-width: 60px;";

            const finishRename = () => {
                const newName = ipt.value.trim();
                layer.name = newName || oldName;
                layer.fileBaseName = layer.name;
                safe.onChange();
            };

            ipt.onkeydown = (ev) => {
                if (ev.key === "Enter") finishRename();
                if (ev.key === "Escape") safe.onChange();
            };
            ipt.onblur = finishRename;

            layerNameEl.replaceWith(ipt);
            ipt.focus();
            ipt.select();
        };

        btnToggleVis.onclick = (e) => {
            e.stopPropagation();
            layer.visible = !layer.visible;
            safe.onChange();
        };

        opacityInput.oninput = (e) => {
            layer.opacity = parseFloat(e.target.value);
            safe.onOpacityChange();
        };

        btnExportPNG.onclick = (e) => {
            e.stopPropagation();
            exportLayerAsPNG(layer);
        };

        btnDel.onclick = (e) => {
            e.stopPropagation();
            layerStack.splice(idx, 1);
            let nextIdx = activeIndex;
            if (nextIdx >= layerStack.length) nextIdx = layerStack.length - 1;
            safe.onSelectLayer(nextIdx, { shiftKey: false, ctrlKey: false });
            safe.onChange();
        };

        const disableHeaderDrag = () => { header.draggable = false; };
        const enableHeaderDrag = () => { header.draggable = true; };

        opacityInput.addEventListener("mouseenter", disableHeaderDrag);
        opacityInput.addEventListener("mouseleave", enableHeaderDrag);
        opacityInput.addEventListener("pointerdown", (e) => { disableHeaderDrag(); e.stopPropagation(); });
        opacityInput.addEventListener("mousedown", (e) => { disableHeaderDrag(); e.stopPropagation(); });

        btnToggleVis.addEventListener("mouseenter", disableHeaderDrag);
        btnToggleVis.addEventListener("mouseleave", enableHeaderDrag);
        btnExportPNG.addEventListener("mouseenter", disableHeaderDrag);
        btnExportPNG.addEventListener("mouseleave", enableHeaderDrag);
        btnDel.addEventListener("mouseenter", disableHeaderDrag);
        btnDel.addEventListener("mouseleave", enableHeaderDrag);

        header.ondragstart = (e) => {
            if (e.target.tagName === "INPUT" || e.target.tagName === "BUTTON") {
                e.preventDefault();
                return;
            }
            draggedData = { type: "LAYER", index: idx };
            e.dataTransfer.effectAllowed = "move";
            item.style.opacity = "0.4";
        };

        header.ondragend = () => {
            item.style.opacity = "1.0";
            draggedData = null;
            enableHeaderDrag();
        };

        item.appendChild(header);

        // 挂载的 Lua 插槽
        const subSlot = document.createElement("div");
        subSlot.style.cssText = "width: 100%; padding: 4px 6px; background: #121417; border: 1px solid #23272f; border-radius: 4px;";

        const subTitle = document.createElement("div");
        subTitle.style.cssText = "font-size: 10px; color: #60a5fa; margin-bottom: 4px; display: flex; justify-content: space-between;";
        subTitle.innerHTML = `<span>挂载的 Lua 规则 (${layer.luaList.length})</span>`;
        subSlot.appendChild(subTitle);

        const luaListBox = document.createElement("div");
        luaListBox.style.cssText = "display: flex; flex-direction: column; gap: 3px; min-height: 22px;";

        if (layer.luaList.length === 0) {
            luaListBox.innerHTML = `<div style="font-size: 10px; color: #4b5563; text-align: center; padding: 2px;">无配置 (拖入 Lua 文件至此处)</div>`;
        } else {
            layer.luaList.forEach((luaItem, lIdx) => {
                const el = createLuaBadge(luaItem, { from: "layer", layerIdx: idx, luaIdx: lIdx }, safe);
                luaListBox.appendChild(el);
            });
        }
        subSlot.appendChild(luaListBox);

        subSlot.ondragover = (e) => {
            if (draggedData && draggedData.type === "LUA") {
                e.preventDefault();
                e.stopPropagation();
                subSlot.style.borderColor = "#3b82f6";
                subSlot.style.background = "#1b2331";
            }
        };
        subSlot.ondragleave = (e) => {
            e.stopPropagation();
            subSlot.style.borderColor = "#23272f";
            subSlot.style.background = "#121417";
        };
        subSlot.ondrop = (e) => {
            e.preventDefault();
            e.stopPropagation();
            subSlot.style.borderColor = "#23272f";
            subSlot.style.background = "#121417";
            if (draggedData && draggedData.type === "LUA") {
                safe.onMoveLua(draggedData, { to: "layer", targetLayerIdx: idx });
            }
        };

        item.ondragover = (e) => {
            if (draggedData && draggedData.type === "LAYER" && draggedData.index !== idx) {
                e.preventDefault();
                item.style.borderTop = "2px solid #3b82f6";
            }
        };
        item.ondragleave = () => { item.style.borderTop = ""; };
        item.ondrop = (e) => {
            e.preventDefault();
            item.style.borderTop = "";
            if (draggedData && draggedData.type === "LAYER" && draggedData.index !== idx) {
                const [moved] = layerStack.splice(draggedData.index, 1);
                layerStack.splice(idx, 0, moved);
                safe.onSelectLayer(idx, { shiftKey: false, ctrlKey: false });
                safe.onChange();
            }
        };

        item.appendChild(subSlot);
        container.appendChild(item);
    }
}

function createLuaBadge(item, meta, safe) {
    const el = document.createElement("div");
    el.draggable = true;
    el.style.cssText = "display: flex; align-items: center; justify-content: space-between; background: #22262e; border: 1px solid #323843; border-radius: 3px; padding: 2px 6px; font-size: 11px; cursor: grab;";

    const ruleCount = item.rules ? Object.keys(item.rules).length : 0;

    el.innerHTML = `
        <div style="display: flex; align-items: center; gap: 4px; overflow: hidden;">
            <span style="font-size: 10px;">📜</span>
            <span style="color: #e2e8f0; font-family: monospace; text-overflow: ellipsis; overflow: hidden; white-space: nowrap; max-width: 160px;" title="${item.name}">${item.name}</span>
            <span style="background: #1e3a5f; color: #93c5fd; padding: 0 4px; border-radius: 2px; font-size: 9px;">${ruleCount}条</span>
        </div>
        <span class="btn-del-lua" style="color: #94a3b8; font-weight: bold; cursor: pointer; padding: 0 3px;" title="移除此配置">×</span>
    `;

    el.querySelector(".btn-del-lua").onclick = (e) => {
        e.stopPropagation();
        safe.onDeleteLua(meta);
    };

    el.ondragstart = (e) => {
        e.stopPropagation();
        draggedData = { type: "LUA", ...meta };
        e.dataTransfer.effectAllowed = "move";
        el.style.opacity = "0.3";
    };

    el.ondragend = (e) => {
        e.stopPropagation();
        el.style.opacity = "1.0";
        draggedData = null;
    };

    return el;
}