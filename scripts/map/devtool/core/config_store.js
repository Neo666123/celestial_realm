/**
 * core/config_store.js
 * 配置管理仓库：
 * 纯净解析 Lua 与导出，完全基于单个色块的属性（dis / require_solid / chance / tile / prefab）
 */

export class ConfigStore {
    constructor() {
        this.layerConfigs = new Map();
    }

    getRules(layerName) {
        if (!this.layerConfigs.has(layerName)) {
            this.layerConfigs.set(layerName, {});
        }
        return this.layerConfigs.get(layerName);
    }

    setRules(layerName, rules) {
        this.layerConfigs.set(layerName, rules || {});
    }

    setRule(layerName, colorHex, rule) {
        const rules = this.getRules(layerName);
        rules[colorHex.toLowerCase()] = rule;
    }

    removeRule(layerName, colorHex) {
        const rules = this.getRules(layerName);
        delete rules[colorHex.toLowerCase()];
    }

    findMissingColors(uniqueColors, layerName) {
        const rules = this.getRules(layerName);
        return (uniqueColors || []).filter(c => !rules[c.toLowerCase()]);
    }

    extractBlock(str, startIndex) {
        let openBraces = 0;
        let start = -1;
        for (let i = startIndex; i < str.length; i++) {
            if (str[i] === '{') {
                if (openBraces === 0) start = i;
                openBraces++;
            } else if (str[i] === '}') {
                openBraces--;
                if (openBraces === 0) {
                    return { content: str.substring(start + 1, i), endIndex: i };
                }
            }
        }
        return null;
    }

    parseLuaDict(dictStr) {
        const result = {};
        const kvRegex = /\[?["']?([^"'=\[\],\s]+)["']?\]?\s*=\s*([0-9.]+)/g;
        let m;
        while ((m = kvRegex.exec(dictStr)) !== null) {
            result[m[1]] = parseFloat(m[2]);
        }
        return result;
    }

    parseArbitraryLuaTable(tableStr) {
        const res = {};
        const strRegex = /\[?["']?([a-zA-Z0-9_]+)["']?\]?\s*=\s*["']([^"']+)["']/g;
        let m;
        while ((m = strRegex.exec(tableStr)) !== null) res[m[1]] = m[2];

        const numRegex = /\[?["']?([a-zA-Z0-9_]+)["']?\]?\s*=\s*([0-9.]+)/g;
        while ((m = numRegex.exec(tableStr)) !== null) {
            if (res[m[1]] === undefined) res[m[1]] = parseFloat(m[2]);
        }

        const boolRegex = /\[?["']?([a-zA-Z0-9_]+)["']?\]?\s*=\s*(true|false)/g;
        while ((m = boolRegex.exec(tableStr)) !== null) {
            res[m[1]] = (m[2] === "true");
        }
        return res;
    }

    importLuaConfig(luaCode, layerName) {
        const rules = this.getRules(layerName);
        let count = 0;

        const colorRegex = /\[["']([^"']+)["']\]\s*=/g;
        let match;

        while ((match = colorRegex.exec(luaCode)) !== null) {
            const rawCol = match[1];
            if (!rawCol.includes("#") && rawCol.length !== 6 && rawCol.length !== 8) continue;

            const col = (rawCol.startsWith("#") ? rawCol : "#" + rawCol).toLowerCase();
            const blockData = this.extractBlock(luaCode, match.index);
            if (!blockData) continue;

            const block = blockData.content;
            const ruleObj = {
                tiers: {
                    1: {
                        dis: 1,
                        chance: 1.0,
                        require_solid: true,
                    }
                }
            };
            const tier1 = ruleObj.tiers[1];

            const disMatch = block.match(/dis\s*=\s*([0-9]+|nil)/);
            if (disMatch) tier1.dis = disMatch[1] === "nil" ? null : parseInt(disMatch[1], 10);

            const chanceMatch = block.match(/chance\s*=\s*([0-9.]+)/);
            if (chanceMatch) tier1.chance = parseFloat(chanceMatch[1]);

            const solidMatch = block.match(/require_solid\s*=\s*(true|false)/);
            if (solidMatch) tier1.require_solid = (solidMatch[1] === "true");

            const ruleMatch = block.match(/rule\s*=\s*["']([^"']+)["']/);
            if (ruleMatch) {
                tier1.rule = ruleMatch[1];
                const pfStr = block.match(/prefab\s*=\s*["']([^"']+)["']/);
                tier1.prefab = pfStr ? pfStr[1] : "cc_brigdepost";

                const minGap = block.match(/min_gap\s*=\s*([0-9]+)/);
                const maxGap = block.match(/max_gap\s*=\s*([0-9]+)/);
                const pairChance = block.match(/pair_chance\s*=\s*([0-9.]+)/);
                if (minGap) tier1.min_gap = parseInt(minGap[1], 10);
                if (maxGap) tier1.max_gap = parseInt(maxGap[1], 10);
                if (pairChance) tier1.pair_chance = parseFloat(pairChance[1]);
            }

            const tileStrMatch = block.match(/tile\s*=\s*["']([^"']+)["']/);
            if (tileStrMatch) {
                tier1.tile = tileStrMatch[1];
            } else {
                const tileIdx = block.indexOf("tile =");
                if (tileIdx !== -1) {
                    const tb = this.extractBlock(block, tileIdx);
                    if (tb) {
                        tier1.tile = {};
                        if (tb.content.includes("distribute")) tier1.tile.distribute = this.parseLuaDict(tb.content);
                        if (tb.content.includes("count")) tier1.tile.count = this.parseLuaDict(tb.content);
                    }
                }
            }

            const bpStrMatch = block.match(/blueprint\s*=\s*["']([^"']+)["']/);
            if (bpStrMatch) {
                tier1.blueprint = bpStrMatch[1];
            } else {
                const bpIdx = block.indexOf("blueprints =");
                if (bpIdx !== -1) {
                    const bpb = this.extractBlock(block, bpIdx);
                    if (bpb) {
                        const nameM = bpb.content.match(/name\s*=\s*["']([^"']+)["']/);
                        const countM = bpb.content.match(/count\s*=\s*([0-9]+)/);
                        tier1.blueprints = {
                            name: nameM ? nameM[1] : "",
                            count: countM ? parseInt(countM[1], 10) : 1
                        };
                    }
                }
            }

            if (!tier1.rule) {
                const pfStrMatch = block.match(/prefab\s*=\s*["']([^"']+)["']/);
                if (pfStrMatch) {
                    tier1.prefab = pfStrMatch[1];
                } else {
                    const pfIdx = block.indexOf("prefab =");
                    if (pfIdx !== -1) {
                        const pfb = this.extractBlock(block, pfIdx);
                        if (pfb) {
                            tier1.prefab = {};
                            const denM = pfb.content.match(/density\s*=\s*([0-9.]+)/);
                            if (denM) tier1.prefab.density = parseFloat(denM[1]);
                            if (pfb.content.includes("distribute")) tier1.prefab.distribute = this.parseLuaDict(pfb.content);
                            if (pfb.content.includes("count")) tier1.prefab.count = this.parseLuaDict(pfb.content);
                        }
                    }
                }
            }

            const dataIdx = block.indexOf("data =");
            if (dataIdx !== -1) {
                const dt = this.extractBlock(block, dataIdx);
                if (dt) tier1.data = this.parseArbitraryLuaTable(dt.content);
            }

            const rotMatch = block.match(/rotation\s*=\s*([0-9.]+)/);
            if (rotMatch) tier1.rotation = parseFloat(rotMatch[1]);
            const sceMatch = block.match(/scenario\s*=\s*["']([^"']+)["']/);
            if (sceMatch) tier1.scenario = sceMatch[1];
            const skinMatch = block.match(/skinname\s*=\s*["']([^"']+)["']/);
            if (skinMatch) tier1.skinname = skinMatch[1];

            rules[col] = ruleObj;
            count++;
        }

        return count;
    }

    exportToLua(layerName) {
        const rules = this.getRules(layerName);
        let lua = `-- Generated by Celestial Editor for layer: ${layerName}\n`;
        lua += `local Config_${layerName} = {\n`;
        lua += `    schema_version = 1,\n`;
        lua += `    unknown_color_policy = "warn",\n`;
        lua += `    reserved_colors = {},\n\n`;

        for (const [col, conf] of Object.entries(rules)) {
            const tier1 = (conf.tiers && conf.tiers[1]) ? conf.tiers[1] : conf;
            lua += `    ["${col.toLowerCase()}"] = {\n`;
            lua += `        tiers = {\n`;
            lua += `            [1] = {\n`;

            lua += `                dis = ${tier1.dis !== null && tier1.dis !== undefined ? tier1.dis : "nil"},\n`;
            if (tier1.chance !== undefined && tier1.chance !== 1.0) {
                lua += `                chance = ${tier1.chance},\n`;
            }
            if (tier1.require_solid !== undefined) {
                lua += `                require_solid = ${tier1.require_solid},\n`;
            }

            if (tier1.tile) {
                if (typeof tier1.tile === "string") {
                    lua += `                tile = "${tier1.tile}",\n`;
                } else if (typeof tier1.tile === "object") {
                    lua += `                tile = {\n`;
                    if (tier1.tile.distribute) {
                        lua += `                    distribute = {\n`;
                        for (const [t, w] of Object.entries(tier1.tile.distribute)) {
                            lua += `                        ["${t}"] = ${w},\n`;
                        }
                        lua += `                    },\n`;
                    }
                    if (tier1.tile.count) {
                        lua += `                    count = {\n`;
                        for (const [t, c] of Object.entries(tier1.tile.count)) {
                            lua += `                        ["${t}"] = ${c},\n`;
                        }
                        lua += `                    },\n`;
                    }
                    lua += `                },\n`;
                }
            }

            if (tier1.blueprint) {
                lua += `                blueprint = "${tier1.blueprint}",\n`;
            } else if (tier1.blueprints) {
                lua += `                blueprints = {\n`;
                lua += `                    name = "${tier1.blueprints.name || ""}",\n`;
                lua += `                    count = ${tier1.blueprints.count || 1},\n`;
                lua += `                },\n`;
            }

            if (tier1.prefab && !tier1.rule) {
                if (typeof tier1.prefab === "string") {
                    lua += `                prefab = "${tier1.prefab}",\n`;
                } else if (typeof tier1.prefab === "object") {
                    lua += `                prefab = {\n`;
                    if (tier1.prefab.count) {
                        lua += `                    count = {\n`;
                        for (const [p, c] of Object.entries(tier1.prefab.count)) {
                            lua += `                        ["${p}"] = ${c},\n`;
                        }
                        lua += `                    },\n`;
                    }
                    if (tier1.prefab.distribute) {
                        lua += `                    distribute = {\n`;
                        for (const [p, w] of Object.entries(tier1.prefab.distribute)) {
                            lua += `                        ["${p}"] = ${w},\n`;
                        }
                        lua += `                    },\n`;
                        if (tier1.prefab.density !== undefined) {
                            lua += `                    density = ${tier1.prefab.density},\n`;
                        }
                    }
                    lua += `                },\n`;
                }
            }

            if (tier1.rule) {
                lua += `                rule = "${tier1.rule}",\n`;
                lua += `                prefab = "${tier1.prefab || "cc_brigdepost"}",\n`;
                if (tier1.min_gap !== undefined) lua += `                min_gap = ${tier1.min_gap},\n`;
                if (tier1.max_gap !== undefined) lua += `                max_gap = ${tier1.max_gap},\n`;
                if (tier1.pair_chance !== undefined) lua += `                pair_chance = ${tier1.pair_chance},\n`;
            }

            if (tier1.data && typeof tier1.data === "object" && Object.keys(tier1.data).length > 0) {
                lua += `                data = {\n`;
                for (const [dk, dv] of Object.entries(tier1.data)) {
                    const formattedVal = typeof dv === "string" ? `"${dv}"` : dv;
                    lua += `                    ["${dk}"] = ${formattedVal},\n`;
                }
                lua += `                },\n`;
            }

            if (tier1.rotation !== undefined) lua += `                rotation = ${tier1.rotation},\n`;
            if (tier1.scenario) lua += `                scenario = "${tier1.scenario}",\n`;
            if (tier1.skinname) lua += `                skinname = "${tier1.skinname}",\n`;

            lua += `            },\n`;
            lua += `        },\n`;
            lua += `    },\n`;
        }

        lua += `}\n\nreturn Config_${layerName}\n`;
        return lua;
    }
}

export default ConfigStore;