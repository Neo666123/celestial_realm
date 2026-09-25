local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G
local AddRecipe2 = (env and env.AddRecipe2) or rawget(GLOBAL, "AddRecipe2")
local Ingredient = rawget(GLOBAL, "Ingredient")
local TECH = rawget(GLOBAL, "TECH")
local GetInventoryItemAtlas = rawget(GLOBAL, "GetInventoryItemAtlas")

local atlas = (GetInventoryItemAtlas and GetInventoryItemAtlas("rope_bridge_kit.tex")) or "images/inventoryimages3.xml"

AddRecipe2(
    "cc_moonbridge_kit",
    {
        Ingredient("moonrocknugget", 5),
        Ingredient("rope", 3),
    },
    TECH.LOST,
    {
        no_placer = true, -- 核心：禁止官方引擎自动挂载建筑放置框
        product = "cc_moonbridge_kit",
        atlas = atlas,
        image = "rope_bridge_kit.tex",
    },
    { "CHARACTER" }
)