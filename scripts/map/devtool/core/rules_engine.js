/**
 * core/rules_engine.js
 * 纯算法模块：空间打组、确定性随机、复合节点解算、射线检测与规则扩展
 * (彻底修复 Chance=0 穿透强刷、桥梁歪斜、间隙失效及挖空穿透问题)
 */

// ============================================================================
// 1. 确定性随机数发生器 (PRNG: Mulberry32) 与几率解析工具
// ============================================================================

export class PRNG {
    constructor(seed = 12345) {
        this.s = Math.floor(seed) >>> 0;
    }

    random() {
        let t = (this.s += 0x6D2B79F5);
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    }

    randomRange(min, max) {
        return min + this.random() * (max - min);
    }

    pickWeighted(distributeTable) {
        if (!distributeTable || typeof distributeTable !== "object") return null;

        let total = 0;
        for (const key in distributeTable) {
            const w = distributeTable[key];
            if (typeof w === "number" && w > 0) total += w;
        }
        if (total <= 0) return null;

        const roll = this.random() * total;
        let acc = 0;
        for (const key in distributeTable) {
            const w = distributeTable[key];
            if (typeof w === "number" && w > 0) {
                acc += w;
                if (roll <= acc) return key;
            }
        }
        return null;
    }

    popRandomPoint(pool) {
        const len = pool.length;
        if (len === 0) return null;
        const idx = Math.floor(this.random() * len);
        const pt = pool[idx];
        pool[idx] = pool[len - 1];
        pool.pop();
        return pt;
    }
}

/**
 * 严格几率解析：兼容卡片顶层与预制体通道内的配置
 */
export function ResolveChance(conf) {
    if (!conf) return 1;
    if (conf.chance !== undefined && conf.chance !== null && conf.chance !== "") {
        const c = Number(conf.chance);
        return isNaN(c) ? 1 : c;
    }
    const pf = conf.prefab || conf.prefabs;
    if (pf && typeof pf === "object" && pf.chance !== undefined && pf.chance !== null && pf.chance !== "") {
        const c = Number(pf.chance);
        return isNaN(c) ? 1 : c;
    }
    return 1;
}

/**
 * 执行几率判定：<= 0 必不触发，>= 1 必触发，其余按 PRNG 掷骰
 */
export function CheckChance(chanceVal, prng) {
    if (chanceVal <= 0) return false;
    if (chanceVal >= 1) return true;
    return prng.random() <= chanceVal;
}

/**
 * 间隙范围安全提取
 */
export function ResolveGap(conf) {
    if (!conf) return { minGap: 1, maxGap: 10 };
    const pf = (conf.prefab || conf.prefabs) || {};
    const minG = conf.min_gap ?? pf.min_gap ?? pf.minGap ?? 1;
    const maxG = conf.max_gap ?? pf.max_gap ?? pf.maxGap ?? 10;
    return {
        minGap: Math.max(1, Number(minG) || 1),
        maxGap: Math.max(1, Number(maxG) || 10),
    };
}

// ============================================================================
// 2. 空间拓扑与打组 (Cluster Extraction)
// ============================================================================

const SUB_DIV = 4;
const SCAN_DIRS = [
    { dx: 1, dy: 0 },
    { dx: -1, dy: 0 },
    { dx: 0, dy: 1 },
    { dx: 0, dy: -1 },
];

export function BuildOffsets(dis) {
    const offsets = [];
    const step = dis || 1;
    for (let dy = -step; dy <= step; dy++) {
        for (let dx = -step; dx <= step; dx++) {
            if (dx !== 0 || dy !== 0) {
                if (Math.max(Math.abs(dx), Math.abs(dy)) <= step) {
                    offsets.push({ dx, dy });
                }
            }
        }
    }
    return offsets;
}

export function ExtractClusters(grid, width, height, matchFunc, dis) {
    const clusters = [];

    if (dis === 0) {
        for (let y = 1; y <= height; y++) {
            for (let x = 1; x <= width; x++) {
                const cell = grid[y] && grid[y][x];
                if (cell && matchFunc(cell)) {
                    clusters.push({
                        col: cell.color,
                        tier: cell.tier || 1,
                        pixels: [{ x, y }],
                    });
                }
            }
        }
        return clusters;
    }

    if (dis === null || dis === undefined) {
        const mergedByKey = {};
        for (let y = 1; y <= height; y++) {
            for (let x = 1; x <= width; x++) {
                const cell = grid[y] && grid[y][x];
                if (cell && matchFunc(cell)) {
                    const key = `${cell.color}_${cell.tier || 1}`;
                    if (!mergedByKey[key]) {
                        mergedByKey[key] = {
                            col: cell.color,
                            tier: cell.tier || 1,
                            pixels: [],
                        };
                        clusters.push(mergedByKey[key]);
                    }
                    mergedByKey[key].pixels.push({ x, y });
                }
            }
        }
        return clusters;
    }

    const visited = Array.from({ length: height + 1 }, () => new Uint8Array(width + 1));
    const searchOffsets = BuildOffsets(dis);

    for (let y = 1; y <= height; y++) {
        for (let x = 1; x <= width; x++) {
            const cell = grid[y] && grid[y][x];
            if (cell && !visited[y][x] && matchFunc(cell)) {
                const cluster = {
                    col: cell.color,
                    tier: cell.tier || 1,
                    pixels: [],
                };
                const queue = [{ x, y }];
                let qHead = 0;
                visited[y][x] = 1;

                while (qHead < queue.length) {
                    const curr = queue[qHead++];
                    cluster.pixels.push(curr);

                    for (let i = 0; i < searchOffsets.length; i++) {
                        const nx = curr.x + searchOffsets[i].dx;
                        const ny = curr.y + searchOffsets[i].dy;

                        if (nx >= 1 && nx <= width && ny >= 1 && ny <= height) {
                            const nCell = grid[ny] && grid[ny][nx];
                            if (!visited[ny][nx] && nCell && matchFunc(nCell, cell)) {
                                visited[ny][nx] = 1;
                                queue.push({ x: nx, y: ny });
                            }
                        }
                    }
                }
                clusters.push(cluster);
            }
        }
    }

    return clusters;
}

export function IsSolidGround(x, y, finalTiles, impassableTile) {
    const tile = finalTiles[y] && finalTiles[y][x];
    return tile !== undefined && tile !== null && tile !== impassableTile;
}

// ============================================================================
// 3. 蓝图处理工具
// ============================================================================

export function AnalyzeBlueprintFootprint(bpDef, bpName) {
    if (!bpDef || !bpDef.raw_data) return null;
    const raw = bpDef.raw_data;
    const w = raw.width || 1;
    const h = raw.height || 1;
    const gGrid = raw.ground;
    const pGrid = raw.prefab;

    let minX = w, maxX = 1, minY = h, maxY = 1;
    const groundOffsets = [];
    const prefabOffsets = [];
    const offsetKeys = new Set();
    const allOffsets = [];

    const scan = (grid, targetList) => {
        if (!grid) return;
        for (let y = 1; y <= h; y++) {
            for (let x = 1; x <= w; x++) {
                const cell = grid[y] && grid[y][x];
                if (cell && cell !== 0) {
                    const col = typeof cell === "object" ? cell.color : cell;
                    const tier = typeof cell === "object" ? (cell.tier || 1) : 1;
                    if (col) {
                        targetList.push({ x, y, col: col.toLowerCase(), tier });
                        if (x < minX) minX = x;
                        if (x > maxX) maxX = x;
                        if (y < minY) minY = y;
                        if (y > maxY) maxY = y;
                    }
                }
            }
        }
    };

    scan(gGrid, groundOffsets);
    scan(pGrid, prefabOffsets);

    const cx = bpDef.center ? bpDef.center.x : Math.floor((minX + maxX) / 2);
    const cy = bpDef.center ? bpDef.center.y : Math.floor((minY + maxY) / 2);

    const calcRel = (list) => list.map(pt => {
        const dx = pt.x - cx;
        const dy = pt.y - cy;
        const key = `${dx}_${dy}`;
        if (!offsetKeys.has(key)) {
            offsetKeys.add(key);
            allOffsets.push({ dx, dy });
        }
        return { dx, dy, col: pt.col, tier: pt.tier };
    });

    return {
        name: bpName,
        bpDef,
        cx,
        cy,
        offsets: allOffsets,
        groundPoints: calcRel(groundOffsets),
        prefabPoints: calcRel(prefabOffsets),
    };
}

export function CanStampBlueprint(targetCx, targetCy, footprint, finalTiles, width, height, impassableTile) {
    for (let i = 0; i < footprint.offsets.length; i++) {
        const wx = targetCx + footprint.offsets[i].dx;
        const wy = targetCy + footprint.offsets[i].dy;
        if (wx < 1 || wx > width || wy < 1 || wy > height) return false;
        if (finalTiles[wy][wx] === impassableTile) return false;
    }
    return true;
}

export function StampBlueprint(targetCx, targetCy, footprint, finalTiles, simulatedColors, entities, resolveTile, prng) {
    const bpDef = footprint.bpDef || {};
    const groundCfg = bpDef.ground || {};
    const prefabCfg = bpDef.prefab || bpDef.palette || {};

    for (let i = 0; i < footprint.groundPoints.length; i++) {
        const pt = footprint.groundPoints[i];
        const wx = targetCx + pt.dx;
        const wy = targetCy + pt.dy;
        const colCfg = groundCfg[pt.col];
        const tierCfg = colCfg && colCfg.tiers ? (colCfg.tiers[pt.tier] || colCfg.tiers[1]) : colCfg;

        if (tierCfg && tierCfg.tile && resolveTile) {
            const tid = resolveTile(tierCfg.tile);
            if (tid !== null && tid !== undefined) {
                finalTiles[wy][wx] = tid;
                if (simulatedColors) simulatedColors[wy][wx] = pt.col;
            }
        }
    }

    for (let i = 0; i < footprint.prefabPoints.length; i++) {
        const pt = footprint.prefabPoints[i];
        const wx = targetCx + pt.dx;
        const wy = targetCy + pt.dy;
        const colCfg = prefabCfg[pt.col];
        const tierCfg = colCfg && colCfg.tiers ? (colCfg.tiers[pt.tier] || colCfg.tiers[1]) : colCfg;

        if (tierCfg && tierCfg.prefab) {
            const pfChance = ResolveChance(tierCfg);
            if (CheckChance(pfChance, prng)) {
                entities.push({
                    prefab: tierCfg.prefab,
                    x: wx,
                    y: wy,
                    metadata: tierCfg.metadata || null,
                    data: tierCfg.data || null,
                });
            }
        }
    }
}

// ============================================================================
// 4. 挖空判断与复合规则处理器
// ============================================================================

export function IsVoidConfig(conf) {
    if (!conf) return false;
    const rule = conf.rule && String(conf.rule).trim().toLowerCase();
    if (rule === "挖空" || rule === "挖空地皮" || rule === "void" || rule === "dig" || rule === "carve" || rule === "hollow" || rule === "clear") {
        return true;
    }
    if (conf.is_void === true || conf.void === true || conf.hollow === true || conf.dig === true) {
        return true;
    }
    const tile = conf.tile !== undefined ? conf.tile : conf.tiles;
    if (tile === 0 || tile === "0" || tile === false) return true;
    if (typeof tile === "string") {
        const t = tile.trim().toLowerCase();
        if (t === "挖空" || t === "挖空地皮" || t === "void" || t === "empty" || t === "none" || t === "impassable" || t === "虚空") {
            return true;
        }
    }
    if (typeof tile === "object" && tile !== null) {
        if (tile.is_void || tile.void || tile.name === "挖空" || tile.name === "void") {
            return true;
        }
    }
    return false;
}

export function ApplyVoidCluster(cluster, context) {
    const { finalTiles, simulatedColors, entities, width, height, impassableTile = 1, prng } = context;
    const conf = cluster.tier_conf;

    const chance = ResolveChance(conf);
    if (!CheckChance(chance, prng)) {
        return;
    }

    for (let i = 0; i < cluster.pixels.length; i++) {
        const pt = cluster.pixels[i];
        if (pt.x >= 1 && pt.x <= width && pt.y >= 1 && pt.y <= height) {
            finalTiles[pt.y][pt.x] = impassableTile;
            if (simulatedColors) {
                simulatedColors[pt.y][pt.x] = "#0c0d0e";
            }
            for (let e = entities.length - 1; e >= 0; e--) {
                const ent = entities[e];
                if (Math.floor(ent.x) === pt.x && Math.floor(ent.y) === pt.y) {
                    entities.splice(e, 1);
                }
            }
        }
    }
}

export function ApplyCompositeCluster(cluster, context) {
    const { finalTiles, simulatedColors, entities, width, height, impassableTile, resolveTile, bpDict, prng } = context;
    const conf = cluster.tier_conf;
    if (!conf) return;

    // 核心修复 1：优先执行挖空，避免挖空规则被后续 rule 提前截断
    if (IsVoidConfig(conf)) {
        ApplyVoidCluster(cluster, context);
        return;
    }

    // 桥梁特种规则不进入基础解算管线，交由后置执行器统一处理
    if (conf.rule) return;

    // 核心修复 2：卡片总几率严格判定，几率 <= 0 坚决不铺设
    const cardChance = ResolveChance(conf);
    if (!CheckChance(cardChance, prng)) {
        return;
    }

    const requireSolid = conf.require_solid !== false;

    // 1. 地皮铺设与变异逻辑
    const tileCfg = conf.tile || conf.tiles;
    if (tileCfg && resolveTile) {
        let tileSolid = requireSolid;
        if (typeof tileCfg === "object" && tileCfg.require_solid !== undefined) {
            tileSolid = (tileCfg.require_solid !== false);
        }

        if (typeof tileCfg === "string") {
            let tid = resolveTile(tileCfg);
            if (tid === undefined || tid === null) {
                const s = tileCfg.trim().toLowerCase();
                if (s === "挖空" || s === "挖空地皮" || s === "void" || s === "虚空") {
                    tid = impassableTile;
                }
            }

            if (tid !== null && tid !== undefined) {
                for (let i = 0; i < cluster.pixels.length; i++) {
                    const pt = cluster.pixels[i];
                    if (!tileSolid || IsSolidGround(pt.x, pt.y, finalTiles, impassableTile)) {
                        finalTiles[pt.y][pt.x] = tid;
                        if (simulatedColors) {
                            simulatedColors[pt.y][pt.x] = (tid === impassableTile) ? "#0c0d0e" : cluster.col;
                        }
                    }
                }
            }
        } else if (typeof tileCfg === "object") {
            if (tileCfg.distribute) {
                for (let i = 0; i < cluster.pixels.length; i++) {
                    const pt = cluster.pixels[i];
                    if (!tileSolid || IsSolidGround(pt.x, pt.y, finalTiles, impassableTile)) {
                        const chosenName = prng.pickWeighted(tileCfg.distribute);
                        if (chosenName) {
                            const tid = resolveTile(chosenName);
                            if (tid !== null && tid !== undefined) {
                                finalTiles[pt.y][pt.x] = tid;
                                if (simulatedColors) {
                                    simulatedColors[pt.y][pt.x] = (tid === impassableTile) ? "#0c0d0e" : cluster.col;
                                }
                            }
                        }
                    }
                }
            } else if (tileCfg.count) {
                const validPool = [];
                for (let i = 0; i < cluster.pixels.length; i++) {
                    const pt = cluster.pixels[i];
                    if (!tileSolid || IsSolidGround(pt.x, pt.y, finalTiles, impassableTile)) {
                        validPool.push(pt);
                    }
                }
                for (const tName in tileCfg.count) {
                    const tNum = tileCfg.count[tName];
                    const tid = resolveTile(tName);
                    if (tid !== null && tid !== undefined) {
                        for (let k = 0; k < tNum; k++) {
                            const pt = prng.popRandomPoint(validPool);
                            if (!pt) break;
                            finalTiles[pt.y][pt.x] = tid;
                            if (simulatedColors) {
                                simulatedColors[pt.y][pt.x] = (tid === impassableTile) ? "#0c0d0e" : cluster.col;
                            }
                        }
                    }
                }
            }
        }
    }

    const occupied = new Set();

    // 2. 蓝图拓印
    const bpCfg = conf.blueprints || conf.blueprint;
    if (bpCfg && bpDict) {
        const bpSolid = (typeof bpCfg === "object" && bpCfg.require_solid !== undefined)
            ? (bpCfg.require_solid !== false)
            : requireSolid;

        const bpPlan = [];
        if (typeof bpCfg === "string") {
            bpPlan.push({ name: bpCfg, count: 1 });
        } else if (typeof bpCfg === "object") {
            if (bpCfg.count) {
                if (typeof bpCfg.count === "object") {
                    for (const bName in bpCfg.count) {
                        bpPlan.push({ name: bName, count: bpCfg.count[bName] });
                    }
                } else if (typeof bpCfg.count === "number" && bpCfg.name) {
                    bpPlan.push({ name: bpCfg.name, count: bpCfg.count });
                }
            } else if (bpCfg.name) {
                bpPlan.push({ name: bpCfg.name, count: 1 });
            }
        }

        const validAnchors = [];
        for (let i = 0; i < cluster.pixels.length; i++) {
            const pt = cluster.pixels[i];
            if (!bpSolid || IsSolidGround(pt.x, pt.y, finalTiles, impassableTile)) {
                validAnchors.push(pt);
            }
        }

        for (let i = 0; i < bpPlan.length; i++) {
            const plan = bpPlan[i];
            const bpDef = bpDict[plan.name];
            if (bpDef) {
                const footprint = AnalyzeBlueprintFootprint(bpDef, plan.name);
                if (footprint) {
                    let stamped = 0;
                    while (stamped < plan.count && validAnchors.length > 0) {
                        const anchor = prng.popRandomPoint(validAnchors);
                        let canStamp = true;
                        if (bpSolid) {
                            canStamp = CanStampBlueprint(anchor.x, anchor.y, footprint, finalTiles, width, height, impassableTile);
                        }
                        if (canStamp) {
                            StampBlueprint(anchor.x, anchor.y, footprint, finalTiles, simulatedColors, entities, resolveTile, prng);
                            stamped++;
                            for (let j = 0; j < footprint.offsets.length; j++) {
                                const ox = anchor.x + footprint.offsets[j].dx;
                                const oy = anchor.y + footprint.offsets[j].dy;
                                occupied.add(`${ox}_${oy}`);
                            }
                        }
                    }
                }
            }
        }
    }

    // 3. 预制体散布
    const pfCfg = conf.prefabs || conf.prefab;
    if (pfCfg) {
        const pfSolid = (typeof pfCfg === "object" && pfCfg.require_solid !== undefined)
            ? (pfCfg.require_solid !== false)
            : requireSolid;

        const getAvailablePool = () => {
            const pool = [];
            for (let i = 0; i < cluster.pixels.length; i++) {
                const pt = cluster.pixels[i];
                if (!occupied.has(`${pt.x}_${pt.y}`)) {
                    if (!pfSolid || IsSolidGround(pt.x, pt.y, finalTiles, impassableTile)) {
                        pool.push(pt);
                    }
                }
            }
            return pool;
        };

        if (typeof pfCfg === "string") {
            const available = getAvailablePool();
            const chosen = prng.popRandomPoint(available);
            if (chosen) {
                entities.push({
                    prefab: pfCfg,
                    x: chosen.x,
                    y: chosen.y,
                    metadata: conf.metadata || null,
                    data: conf.data || null,
                });
            }
        } else if (typeof pfCfg === "object") {
            if (pfCfg.count) {
                const available = getAvailablePool();
                if (typeof pfCfg.count === "object") {
                    for (const pName in pfCfg.count) {
                        const pNum = pfCfg.count[pName];
                        for (let k = 0; k < pNum; k++) {
                            const pt = prng.popRandomPoint(available);
                            if (!pt) break;
                            entities.push({
                                prefab: pName,
                                x: pt.x,
                                y: pt.y,
                                metadata: pfCfg.metadata || conf.metadata || null,
                                data: pfCfg.data || conf.data || null,
                            });
                        }
                    }
                } else if (typeof pfCfg.count === "number" && pfCfg.distribute) {
                    for (let k = 0; k < pfCfg.count; k++) {
                        const pt = prng.popRandomPoint(available);
                        if (!pt) break;
                        const chosenName = prng.pickWeighted(pfCfg.distribute);
                        if (chosenName) {
                            entities.push({
                                prefab: chosenName,
                                x: pt.x,
                                y: pt.y,
                                metadata: pfCfg.metadata || conf.metadata || null,
                                data: pfCfg.data || conf.data || null,
                            });
                        }
                    }
                }
            }

            if (pfCfg.distribute && (pfCfg.density !== undefined || !pfCfg.count)) {
                const density = pfCfg.density !== undefined ? pfCfg.density : 0.1;
                for (let i = 0; i < cluster.pixels.length; i++) {
                    const pt = cluster.pixels[i];
                    if (!occupied.has(`${pt.x}_${pt.y}`)) {
                        if (!pfSolid || IsSolidGround(pt.x, pt.y, finalTiles, impassableTile)) {
                            for (let sy = 1; sy <= SUB_DIV; sy++) {
                                for (let sx = 1; sx <= SUB_DIV; sx++) {
                                    if (prng.random() <= density) {
                                        const chosenName = prng.pickWeighted(pfCfg.distribute);
                                        if (chosenName) {
                                            const subX = (pt.x - 1) + (sx - 0.5) / SUB_DIV;
                                            const subY = (pt.y - 1) + (sy - 0.5) / SUB_DIV;
                                            entities.push({
                                                prefab: chosenName,
                                                x: subX,
                                                y: subY,
                                                metadata: pfCfg.metadata || conf.metadata || null,
                                                data: pfCfg.data || conf.data || null,
                                            });
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// ============================================================================
// 5. 桥梁与射线检测 (单轴绝对正交，绝不斜连，概率严格受控)
// ============================================================================

export function IsBridgeRule(rule) {
    if (!rule) return null;
    const r = String(rule).trim().toLowerCase();
    if (r === "paired_bridge" || r === "paired" || r === "配对桥") return "paired_bridge";
    if (r === "raycast_bridge" || r === "raycast" || r === "bridge" || r === "射线桥" || r === "射线检测" || r === "线条检测") {
        return "raycast_bridge";
    }
    return null;
}

export function FilterEdgePixels(pixels, finalTiles, width, height, impassableTile) {
    const validEdge = [];
    for (let i = 0; i < pixels.length; i++) {
        const p = pixels[i];
        let isSolid = IsSolidGround(p.x, p.y, finalTiles, impassableTile);
        let hasVoidNeighbor = false;
        let hasLandNeighbor = false;

        for (let j = 0; j < SCAN_DIRS.length; j++) {
            const nx = p.x + SCAN_DIRS[j].dx;
            const ny = p.y + SCAN_DIRS[j].dy;
            if (nx < 1 || nx > width || ny < 1 || ny > height || finalTiles[ny][nx] === impassableTile) {
                hasVoidNeighbor = true;
            } else {
                hasLandNeighbor = true;
            }
        }

        if ((isSolid && hasVoidNeighbor) || (!isSolid && hasLandNeighbor)) {
            validEdge.push(p);
        }
    }
    return validEdge;
}

export function ScanVoidRaycast(px, py, finalTiles, width, height, impassableTile, minGap, maxGap) {
    for (let i = 0; i < SCAN_DIRS.length; i++) {
        const { dx, dy } = SCAN_DIRS[i];
        const startX = px + dx;
        const startY = py + dy;

        if (startX >= 1 && startX <= width && startY >= 1 && startY <= height
            && finalTiles[startY][startX] === impassableTile) {
            const voidPath = [];
            for (let step = 1; step <= maxGap + 1; step++) {
                const tx = px + dx * step;
                const ty = py + dy * step;
                if (tx < 1 || tx > width || ty < 1 || ty > height) break;

                if (finalTiles[ty][tx] === impassableTile) {
                    voidPath.push({ x: tx, y: ty });
                } else {
                    if (voidPath.length >= minGap && voidPath.length <= maxGap) {
                        return {
                            ok: true,
                            startPt: { x: px, y: py },
                            hitPt: { x: tx, y: ty },
                            dir: { dx, dy },
                            path: voidPath,
                        };
                    }
                    break;
                }
            }
        }
    }
    return { ok: false };
}

export function MatchPairedBridges(clusters, finalTiles, width, height, impassableTile) {
    for (let i = 0; i < clusters.length; i++) {
        const c = clusters[i];
        if (!c.land_pixels) {
            c.land_pixels = FilterEdgePixels(c.pixels, finalTiles, width, height, impassableTile);
        }
    }

    for (let i = 0; i < clusters.length; i++) {
        const c1 = clusters[i];
        if (!c1.paired_cluster) {
            const { minGap, maxGap } = ResolveGap(c1.tier_conf);

            for (let j = 0; j < c1.land_pixels.length; j++) {
                const p1 = c1.land_pixels[j];
                const res = ScanVoidRaycast(p1.x, p1.y, finalTiles, width, height, impassableTile, minGap, maxGap);
                if (res.ok) {
                    for (let m = 0; m < clusters.length; m++) {
                        const c2 = clusters[m];
                        if (c2 !== c1 && !c2.paired_cluster) {
                            for (let n = 0; n < c2.land_pixels.length; n++) {
                                const p2 = c2.land_pixels[n];

                                // 严格单轴锁定：垂直必须 X 完全恒等，水平必须 Y 完全恒等，绝不斜连！
                                let isAligned = false;
                                if (res.dir.dx === 0) {
                                    isAligned = (p2.x === res.hitPt.x && Math.abs(p2.y - res.hitPt.y) <= 1);
                                } else {
                                    isAligned = (p2.y === res.hitPt.y && Math.abs(p2.x - res.hitPt.x) <= 1);
                                }

                                if (isAligned) {
                                    c1.paired_cluster = c2;
                                    c2.paired_cluster = c1;
                                    c1.chosen = res.startPt;
                                    c2.chosen = res.hitPt;
                                    c1.bridgePath = res.path;
                                    c2.bridgePath = res.path;
                                    break;
                                }
                            }
                        }
                        if (c1.paired_cluster) break;
                    }
                }
                if (c1.paired_cluster) break;
            }
        }
    }
}

export function ProcessBridges(clusters, context) {
    const { finalTiles, simulatedColors, entities, width, height, impassableTile, resolveTile, prng } = context;
    const bridgeClusters = [];

    // 第一道拦截防线：严格执行 Chance 几率！Chance 为 0 或 Roll 点失败的桥梁聚类，直接丢弃！
    for (let i = 0; i < clusters.length; i++) {
        const c = clusters[i];
        const conf = c.tier_conf;
        const normRule = conf && (IsBridgeRule(conf.rule) || (conf.prefab && IsBridgeRule(conf.prefab.rule)) || (conf.prefabs && IsBridgeRule(conf.prefabs.rule)));
        
        if (normRule) {
            // 核心修复：几率 <= 0 坚决不刷，射线扫描直接跳过！
            const chance = ResolveChance(conf);
            if (!CheckChance(chance, prng)) {
                continue;
            }

            c.norm_bridge_rule = normRule;
            c.land_pixels = FilterEdgePixels(c.pixels, finalTiles, width, height, impassableTile);
            if (c.land_pixels.length > 0) {
                bridgeClusters.push(c);
            }
        }
    }

    if (bridgeClusters.length === 0) return;

    MatchPairedBridges(bridgeClusters, finalTiles, width, height, impassableTile);

    // 1. 配对桥双向独立掷骰
    for (let i = 0; i < bridgeClusters.length; i++) {
        const c = bridgeClusters[i];
        if (c.norm_bridge_rule === "paired_bridge" && c.paired_cluster && !c.pairChecked) {
            c.pairChecked = true;
            c.paired_cluster.pairChecked = true;
            const pf = (c.tier_conf && (c.tier_conf.prefab || c.tier_conf.prefabs)) || {};
            const pairChance = Number(c.tier_conf.pair_chance ?? pf.pair_chance ?? 0.30);
            if (CheckChance(pairChance, prng)) {
                c.spawn = true;
                c.paired_cluster.spawn = true;
            }
        }
    }

    // 2. 单向射线桥扫描
    for (let i = 0; i < bridgeClusters.length; i++) {
        const c = bridgeClusters[i];
        if (c.norm_bridge_rule === "raycast_bridge") {
            const { minGap, maxGap } = ResolveGap(c.tier_conf);
            for (let j = 0; j < c.land_pixels.length; j++) {
                const p = c.land_pixels[j];
                const res = ScanVoidRaycast(p.x, p.y, finalTiles, width, height, impassableTile, minGap, maxGap);
                if (res.ok) {
                    c.chosen = res.startPt;
                    c.bridgePath = res.path;
                    c.spawn = true;
                    break;
                }
            }
        }
    }

    // 3. 执行桥梁打通与实体落地
    for (let i = 0; i < bridgeClusters.length; i++) {
        const c = bridgeClusters[i];
        if (c.spawn && c.chosen) {
            // A. 如果配置了地皮，真正铺通沿途虚空格子
            const tileCfg = c.tier_conf.tile || c.tier_conf.tiles;
            if (tileCfg && resolveTile && c.bridgePath) {
                const tid = resolveTile(tileCfg);
                if (tid && tid !== impassableTile) {
                    for (let p = 0; p < c.bridgePath.length; p++) {
                        const pt = c.bridgePath[p];
                        finalTiles[pt.y][pt.x] = tid;
                        if (simulatedColors) simulatedColors[pt.y][pt.x] = c.col || "#76a88c";
                    }
                }
            }

            // B. 生成桥头实体
            const rawPf = c.tier_conf.prefab || c.tier_conf.prefabs;
            let pfName = null;
            let pfChance = 1;

            if (typeof rawPf === "string") {
                pfName = rawPf;
            } else if (typeof rawPf === "object" && rawPf !== null) {
                pfName = rawPf.name || rawPf.prefab || null;
                if (rawPf.chance !== undefined) pfChance = Number(rawPf.chance);
            }

            if (pfName && CheckChance(pfChance, prng)) {
                entities.push({
                    prefab: pfName,
                    x: c.chosen.x,
                    y: c.chosen.y,
                    metadata: c.tier_conf.metadata || null,
                    data: c.tier_conf.data || null,
                });
            }
        }
    }
}

// ============================================================================
// 6. 规则注册中心与管线驱动
// ============================================================================

const CustomRules = {};
const CustomPostRules = {};

export function RegisterRule(ruleName, handlerFn) {
    CustomRules[ruleName] = handlerFn;
}

export function RegisterPostRule(ruleName, handlerFn) {
    CustomPostRules[ruleName] = handlerFn;
}

// 内置规则注册
RegisterRule("挖空", (cluster, context) => ApplyVoidCluster(cluster, context));
RegisterRule("挖空地皮", (cluster, context) => ApplyVoidCluster(cluster, context));
RegisterRule("void", (cluster, context) => ApplyVoidCluster(cluster, context));
RegisterRule("dig", (cluster, context) => ApplyVoidCluster(cluster, context));
RegisterRule("carve", (cluster, context) => ApplyVoidCluster(cluster, context));

RegisterPostRule("builtin_bridges", (clusters, context) => {
    ProcessBridges(clusters, context);
});

export function ExecuteSimulation(options) {
    const {
        width,
        height,
        layers = [],
        blueprints = {},
        seed = 12345,
        impassableTile = 1,
        resolveTile = (name) => (typeof name === "number" ? name : 1),
    } = options;

    const prng = new PRNG(seed);

    const finalTiles = Array.from({ length: height + 1 }, () => {
        const row = new Int32Array(width + 1);
        row.fill(impassableTile);
        return row;
    });

    const simulatedColors = Array.from({ length: height + 1 }, () => {
        return new Array(width + 1).fill("#0c0d0e");
    });

    const entities = [];
    const stats = [];

    const context = {
        finalTiles,
        simulatedColors,
        entities,
        width,
        height,
        impassableTile,
        resolveTile,
        bpDict: blueprints,
        prng,
    };

    for (let layerIdx = 0; layerIdx < layers.length; layerIdx++) {
        const layer = layers[layerIdx];
        const { grid, config = {}, name = `layer_${layerIdx}` } = layer;
        if (!grid) continue;

        const beforeEntCount = entities.length;

        const presentTypes = {};
        for (let y = 1; y <= height; y++) {
            const row = grid[y];
            if (row) {
                for (let x = 1; x <= width; x++) {
                    const cell = row[x];
                    if (cell && cell.color && cell.color !== "empty") {
                        const colKey = cell.color.toLowerCase();
                        const tierKey = cell.tier || 1;
                        const key = `${colKey}_${tierKey}`;
                        if (!presentTypes[key]) {
                            presentTypes[key] = { color: colKey, tier: tierKey };
                        }
                    }
                }
            }
        }

        const clusters = [];
        for (const key in presentTypes) {
            const item = presentTypes[key];
            const conf = config[item.color] || config[item.color.toUpperCase()];
            if (conf) {
                const tierConf = conf.tiers ? (conf.tiers[item.tier] || conf.tiers[1]) : conf;
                if (tierConf) {
                    const matchFunc = (c) => c && c.color && c.color.toLowerCase() === item.color && (c.tier || 1) === item.tier;
                    const subClusters = ExtractClusters(grid, width, height, matchFunc, tierConf.dis);
                    for (let cIdx = 0; cIdx < subClusters.length; cIdx++) {
                        subClusters[cIdx].tier_conf = tierConf;
                        clusters.push(subClusters[cIdx]);
                    }
                }
            }
        }

        for (let cIdx = 0; cIdx < clusters.length; cIdx++) {
            const c = clusters[cIdx];
            const ruleName = c.tier_conf && c.tier_conf.rule;
            if (ruleName && CustomRules[ruleName]) {
                CustomRules[ruleName](c, context);
            } else {
                ApplyCompositeCluster(c, context);
            }
        }

        for (const postName in CustomPostRules) {
            CustomPostRules[postName](clusters, context);
        }

        stats.push({
            name,
            entitiesSpawned: entities.length - beforeEntCount,
        });
    }

    return {
        width,
        height,
        finalTiles,
        simulatedColors,
        entities,
        stats,
    };
}