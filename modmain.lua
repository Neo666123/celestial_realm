local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G

PrefabFiles = {
    "celestial_rift",
    "test_cat",
    "spider_plus",
    "celestial_roguelike_collision",
    "celestial_roguelike_door",
    "portal_entrance",
    "portal_exit",
    "inventory_vault",
    "shadeling_worm",
    "shadeling_bomb_worm",
    "snow_grass",
    "short_grass",
    "cc_memory",
    "cc_coalruin",
    "cc_memscrap",
    "cc_brigdepost",
    "cc_pots",
    "cc_coalruin",
    "cc_moonhound_mound",
    "cc_petrifiedtree",
    "cc_coal",
    "potshard"

}

Assets = {
    Asset("ANIM", "anim/new_atk.zip"),
    Asset("ANIM", "anim/status_starblight.zip"),
    Asset("ANIM", "anim/vault_portal.zip"),
    Asset("ANIM", "anim/white_grass.zip"),
}

-- 1. 调试与调参中心
modimport("scripts/devtools/core/inspector_registry.lua")
modimport("scripts/devtools/tuning/spider_inspector_tuning.lua")
modimport("scripts/devtools/dev_inspector_setup.lua")
modimport("scripts/devtools/tuning/shadeling_worm_tuning.lua")
modimport("scripts/devtools/tuning/shadeling_bomb_worm_tuning.lua")

-- 2. 世界生成管线
local CelestialEngine = require("map/celestial_engine")
if CelestialEngine and CelestialEngine.Init then
    CelestialEngine.Init(env)
end
modimport("scripts/map/rift_world_setup.lua")

-- 3. 道具
modimport("scripts/portals/portal_setup.lua")
modimport("scripts/player/tech/cc_techfilter.lua")
modimport("scripts/recipes.lua")
modimport("scripts/vanilla_patches.lua")

-- 4. 玩家 3C 输入控制器与侵蚀 HUD
modimport("scripts/player/actions/grass_interaction_controller.lua")
modimport("scripts/player/actions/custom_combat_controller.lua")
modimport("scripts/player/ui/starblight_ui_setup.lua")
modimport("scripts/trench_jump_test.lua")
modimport("scripts/cc_tuning.lua")
-- 5. 挂载世界级肉鸽管理器
AddPrefabPostInit("world", function(inst)
    if not (GLOBAL.TheWorld and GLOBAL.TheWorld.ismastersim) then return end
    inst:AddComponent("celestial_roguelike_manager")
end)


local STRINGS = rawget(GLOBAL, "STRINGS")
if STRINGS and STRINGS.NAMES then
    STRINGS.NAMES.CC_BRIGDEPOST      = "桥桩"
    STRINGS.NAMES.CC_BRIGDEPOST_ITEM = "桥桩套件"
    STRINGS.RECIPE_DESC = STRINGS.RECIPE_DESC or {}
    STRINGS.RECIPE_DESC.CC_BRIGDEPOST_ITEM = "在悬崖边设立索桥桩基，两岸各设一根即可架桥。"
    STRINGS.NAMES.CC_POT_NORMAL = "远古陶罐"
    STRINGS.NAMES.CC_POT_BRIDGE = "神秘的远古陶罐"
    STRINGS.NAMES.CC_POT_WOOD   = "沉重的远古陶罐"

    STRINGS.CHARACTERS.GENERIC.DESCRIBE.CC_BRIGDEPOST = {
        BUILT = "桥梁已经稳稳架设好了。",
        READY = "对岸已经对齐，可以投入石头开始架桥了！",
        NEED_PAIR = "还需要在正对岸也设立一根桥桩才能连接。",
    }
    STRINGS.NAMES.CC_MEMSCRAP        = "零碎的记忆"
end
--[[【项目规范：数据驱动与运行时 Inspector 调参架构】

严禁在逻辑内部硬编码手感数值：

严禁在 StateGraph、Brain、Task 或组件内部将位移速度、动画帧时序、技能冷却、判定盒尺寸、寻路半径等写死为局部常量（Upvalues）。

所有影响动作手感与战斗节奏的数值，必须提取至独立的配置表（Table）中，命名统一采用 Unity 风格的驼峰命名（如 chargeCooldown、dashSpeed、orbitRadius）。

参数必须接入全局注册中心：

模块初始化时，必须将该配置表注册至全局调试单例 InspectorRegistry 中，格式为：

Lua
local MyModuleSettings = {
    dashSpeed = 12.0,
    attackPeriod = 0.5,
}
local InspectorRegistry = rawget(GLOBAL, "InspectorRegistry")
if InspectorRegistry then
    InspectorRegistry:Register("MyModuleSettings", MyModuleSettings)
end
注册名称即为后续可视化层级树面板（Inspector Tree）的一级折叠目录名。

严格遵守内存引用直读机制：

逻辑运行时（StateGraph 的 onupdate、timeline 或 Brain 的决策节点），必须直接通过配置表引用实时读取最新值（如 MyModuleSettings.dashSpeed），禁止在局部变量中缓存死静态数值。

必须确保在外部通过修改该 Table 的字段时，实体在下一个执行帧无需重启世界即可实时生效。

动画状态机（SG）后摇与硬直放行规范：

若参数包含超快攻速（如低 attackPeriod），状态机必须在有效伤害判定帧发出后（通过 TimeEvent）主动移除 busy 状态标签（inst.sg:RemoveStateTag("busy")），以允许外部事件取消收招后摇，严禁因未播完动画而吞掉下一次指令。

严格遵循环境安全原则：

读取引擎全局对象必须使用 rawget(GLOBAL, "KEY")，模块内部临时变量显式声明为 local，禁止隐式污染全局环境。]]