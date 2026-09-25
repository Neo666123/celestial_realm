/**
 * image_loader.js
 * 图像解析、Alpha分档量化、色号统计与 RLE / Lua 编解码模块
 */

export const DATA_SCHEMA_VERSION = 1;
export const DATA_COORDINATE_SYSTEM = "pixel_grid_1based";
export const DATA_CELL_FORMAT = "color_tier";
export const DATA_ENCODING = "rle_palette";

// 离散 Alpha 档位区间量化 (完全对齐 Python 版，兼容 PS 0, 7, 5, 2 快捷键)
export const ALPHA_TIERS = [
    { tier: 1, min: 235, max: 255, restore: 255 }, // Tier 1: PS 100% (240~255) -> 还原 255
    { tier: 2, min: 165, max: 234, restore: 191 }, // Tier 2: PS 75%  (170~239) -> 还原 191
    { tier: 3, min: 95,  max: 164, restore: 128 }, // Tier 3: PS 50%  (100~169) -> 还原 128
    { tier: 4, min: 15,  max: 94,  restore: 64  }, // Tier 4: PS 25%  (15~99)   -> 还原 64
];

export function quantizeAlpha(a) {
    if (a < 15) return { tier: 0, restoreA: 0 };
    for (let i = 0; i < ALPHA_TIERS.length; i++) {
        const item = ALPHA_TIERS[i];
        if (a >= item.min && a <= item.max) {
            return { tier: item.tier, restoreA: item.restore };
        }
    }
    return { tier: 4, restoreA: 64 };
}

export function rgbToHex(r, g, b) {
    const h = ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
    return `#${h.toLowerCase()}`;
}

export function hexToRgb(hexStr) {
    const cleanHex = hexStr.replace(/^#/, "");
    return {
        r: parseInt(cleanHex.substring(0, 2), 16),
        g: parseInt(cleanHex.substring(2, 4), 16),
        b: parseInt(cleanHex.substring(4, 6), 16),
    };
}

/**
 * 从浏览器端 Image / Blob / File 源加载 ImageData
 */
export async function loadImageDataFromSource(source) {
    let img;
    if (source instanceof ImageData) {
        return source;
    } else if (source instanceof HTMLImageElement) {
        img = source;
    } else if (source instanceof Blob || source instanceof File) {
        const url = URL.createObjectURL(source);
        img = await new Promise((resolve, reject) => {
            const image = new Image();
            image.onload = () => {
                URL.revokeObjectURL(url);
                resolve(image);
            };
            image.onerror = (err) => {
                URL.revokeObjectURL(url);
                reject(err);
            };
            image.src = url;
        });
    } else {
        throw new Error("不支持的图像输入源类型");
    }

    const canvas = document.createElement("canvas");
    canvas.width = img.width;
    canvas.height = img.height;
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    ctx.drawImage(img, 0, 0);
    return ctx.getImageData(0, 0, img.width, img.height);
}

/**
 * 解析 ImageData 生成网格数据、唯一色号与 RLE 压缩包
 */
export function parseImageLayer(imageData) {
    const { width, height, data } = imageData;
    const paletteMap = new Map();
    paletteMap.set("NONE_0", 0);
    const paletteList = [null];
    let nextId = 1;

    const runs = [];
    let currId = null;
    let currLen = 0;

    // 1-based 像素网格
    const grid = Array.from({ length: height + 1 }, () => new Array(width + 1).fill(null));
    const stats = {};
    const uniqueColorsSet = new Set();

    let ptr = 0;
    for (let y = 1; y <= height; y++) {
        for (let x = 1; x <= width; x++) {
            const r = data[ptr];
            const g = data[ptr + 1];
            const b = data[ptr + 2];
            const a = data[ptr + 3];
            ptr += 4;

            const { tier } = quantizeAlpha(a);
            let key = "NONE_0";
            let hexColor = null;

            if (tier !== 0) {
                hexColor = rgbToHex(r, g, b);
                key = `${hexColor}_${tier}`;
                grid[y][x] = { color: hexColor, tier };

                uniqueColorsSet.add(hexColor);
                stats[hexColor] = (stats[hexColor] || 0) + 1;
            }

            if (!paletteMap.has(key)) {
                paletteMap.set(key, nextId);
                paletteList.push(tier === 0 ? null : { color: hexColor, tier });
                nextId++;
            }

            const cid = paletteMap.get(key);
            if (cid === currId) {
                currLen++;
            } else {
                if (currId !== null) {
                    runs.push(`${currId}:${currLen}`);
                }
                currId = cid;
                currLen = 1;
            }
        }
    }

    if (currId !== null) {
        runs.push(`${currId}:${currLen}`);
    }

    const rleString = runs.join(";");

    // 组装格式化 Palette 代码行
    const paletteLines = ["            [0] = nil, -- 虚空 / 透明"];
    for (let i = 1; i < paletteList.length; i++) {
        const item = paletteList[i];
        paletteLines.push(`            [${i}] = { color = "${item.color}", tier = ${item.tier} },`);
    }

    return {
        width,
        height,
        grid,
        rleString,
        paletteList,
        paletteString: paletteLines.join("\n"),
        stats,
        uniqueColors: Array.from(uniqueColorsSet),
    };
}

/**
 * 构建单层地图 Lua 文件字符串 (对标 Python build_single_layer_lua)
 */
export function buildSingleLayerLua(width, height, paletteStr, rleString) {
    return `-- Generated by mapgen (Single Layer)
local map_data = {
    schema_version = ${DATA_SCHEMA_VERSION},
    coordinate_system = "${DATA_COORDINATE_SYSTEM}",
    cell_format = "${DATA_CELL_FORMAT}",
    encoding = "${DATA_ENCODING}",
    width = ${width},
    height = ${height},
    total_pixels = ${width * height},
    palette = {
${paletteStr}
    },
    rle_data = "${rleString}",
}

function map_data:Unpack()
    local grid = {}
    for y = 1, self.height do
        grid[y] = {}
    end
    local cur_x, cur_y = 1, 1
    for id_str, count_str in string.gmatch(self.rle_data, "(%d+):(%d+)") do
        local id = tonumber(id_str)
        local count = tonumber(count_str)
        local item = self.palette[id]
        local cell = item and { color = item.color, tier = item.tier } or nil
        for _ = 1, count do
            grid[cur_y][cur_x] = cell
            cur_x = cur_x + 1
            if cur_x > self.width then
                cur_x = 1
                cur_y = cur_y + 1
            end
        end
    end
    return grid
end

return map_data
`;
}

/**
 * 构建双层蓝图 Lua 文件字符串 (对标 Python build_blueprint_lua)
 * layersData 结构: { ground: { paletteString, rleString }, prefab: { paletteString, rleString } }
 */
export function buildBlueprintLua(width, height, layersData) {
    const layerEntries = [];
    for (const lName in layersData) {
        const item = layersData[lName];
        layerEntries.push(`        ${lName} = {
            palette = {
${item.paletteString}
            },
            rle_data = "${item.rleString}",
        },`);
    }

    return `-- Generated by mapgen (Dual-Layer Blueprint Package)
local blueprint_data = {
    schema_version = ${DATA_SCHEMA_VERSION},
    coordinate_system = "${DATA_COORDINATE_SYSTEM}",
    cell_format = "${DATA_CELL_FORMAT}",
    encoding = "${DATA_ENCODING}",
    width = ${width},
    height = ${height},
    total_pixels = ${width * height},
    is_blueprint = true,
    layers = {
${layerEntries.join("\n")}
    },
}

function blueprint_data:Unpack()
    local result = {}
    for layer_name, layer_info in pairs(self.layers) do
        local grid = {}
        for y = 1, self.height do
            grid[y] = {}
        end
        local cur_x, cur_y = 1, 1
        for id_str, count_str in string.gmatch(layer_info.rle_data, "(%d+):(%d+)") do
            local id = tonumber(id_str)
            local count = tonumber(count_str)
            local item = layer_info.palette[id]
            local cell = item and { color = item.color, tier = item.tier } or nil
            for _ = 1, count do
                grid[cur_y][cur_x] = cell
                cur_x = cur_x + 1
                if cur_x > self.width then
                    cur_x = 1
                    cur_y = cur_y + 1
                end
            end
        end
        result[layer_name] = grid
    end
    return result
end

return blueprint_data
`;
}

/**
 * 解码 RLE 字符串为 1-based 像素网格
 */
export function unpackRleGrid(width, height, paletteList, rleString) {
    const grid = Array.from({ length: height + 1 }, () => new Array(width + 1).fill(null));
    let curX = 1;
    let curY = 1;

    const tokens = rleString.split(";");
    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i].trim();
        if (!token) continue;
        const [idStr, countStr] = token.split(":");
        const id = parseInt(idStr, 10);
        const count = parseInt(countStr, 10);
        const cell = paletteList[id] ? { color: paletteList[id].color, tier: paletteList[id].tier } : null;

        for (let k = 0; k < count; k++) {
            if (curY <= height && curX <= width) {
                grid[curY][curX] = cell;
            }
            curX++;
            if (curX > width) {
                curX = 1;
                curY++;
            }
        }
    }
    return grid;
}