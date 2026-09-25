/**
 * managers/simulation_manager.js
 * 纯仿真业务服务
 * 职责：负责合并图层 Lua 规则、提取实体图标集、调用 rules_engine 进行整图模拟解算
 */

import { ExecuteSimulation } from "../core/rules_engine.js";

const DEFAULT_TILE_MAP = {
    IMPASSABLE: 1, DIRT: 2, SAVANNA: 3, GRASS: 4, FOREST: 5,
    MARSH: 6, ROCKY: 7, PEBBLEBEACH: 41, CC_BLACKGOLD: 41,
    SHELLBEACH: 42, CC_METEOR: 42, METEOR: 43
};

export class SimulationManager {
    constructor() {
        this.simulationResultCache = null;
    }

    getMergedRulesForLayer(layer) {
        if (!layer || !layer.luaList || layer.luaList.length === 0) return {};
        const merged = {};
        for (const item of layer.luaList) {
            if (item.rules) {
                for (const [col, conf] of Object.entries(item.rules)) {
                    merged[col] = conf;
                }
            }
        }
        return merged;
    }

    extractActiveIconMap(layerStack) {
        const iconMap = {};
        (layerStack || []).forEach(l => {
            const rules = this.getMergedRulesForLayer(l);
            for (const col in rules) {
                const conf = rules[col];
                const t1 = (conf && conf.tiers && conf.tiers[1]) ? conf.tiers[1] : conf;
                if (t1 && t1.icons) {
                    for (const name in t1.icons) {
                        if (t1.icons[name]) iconMap[name] = t1.icons[name];
                    }
                }
            }
        });
        return iconMap;
    }

    runSimulation(layerStack, seed = 12345) {
        if (!layerStack || layerStack.length === 0) {
            this.simulationResultCache = null;
            return null;
        }

        const { width, height } = layerStack[0];
        const activeLayers = layerStack.filter(l => l.visible).map(l => ({
            name: l.name,
            grid: l.grid,
            config: this.getMergedRulesForLayer(l),
        }));

        this.simulationResultCache = ExecuteSimulation({
            width,
            height,
            layers: activeLayers,
            seed: seed,
            impassableTile: 1,
            resolveTile: (name) => {
                return typeof name === "number" ? name : (DEFAULT_TILE_MAP[String(name).toUpperCase()] || 2);
            }
        });

        return this.simulationResultCache;
    }
}