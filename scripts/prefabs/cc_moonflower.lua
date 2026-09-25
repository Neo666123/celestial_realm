local assets =
{
    -- 借用月蛾与蝴蝶的基础动画文件
Asset("ANIM", "anim/moon_tree_petal.zip"),
}

local prefabs =
{
    "moonbutterfly",
    "moon_tree_blossom",
}

local function onpickedfn(inst, picker)
    local pos = inst:GetPosition()

    if picker ~= nil and picker.components.sanity ~= nil then
        -- 采摘恢复少量理智（或根据月岛特性扣除/启蒙）
        picker.components.sanity:DoDelta(TUNING.SANITY_TINY)
    end

    TheWorld:PushEvent("plantkilled", { doer = picker, pos = pos })
end

local function fn()
    local inst = CreateEntity()

    -- 1. 基础网络和实体组件
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    -- 2. 设置月树花/月蛾的外观与微光
    inst.AnimState:SetBank("moon_tree_petal")
    inst.AnimState:SetBuild("moon_tree_petal")
    inst.AnimState:PlayAnimation("idle")
    inst.AnimState:SetRayTestOnBB(true)

    -- 标签（注意：不要加普通 "flower" 标签，防止原版刷新普通蝴蝶干扰）

    inst:AddTag("cattoy")

    inst.entity:SetPristine()

    -- 客服端分离：网络同步结束前，只执行客户端代码
    if not TheWorld.ismastersim then
        return inst
    end

    -- 3. 可检查组件
    inst:AddComponent("inspectable")

    -- 4. 采集组件
    inst:AddComponent("pickable")
    inst.components.pickable.picksound = "dontstarve/wilson/pickup_plants"
    inst.components.pickable:SetUp("moon_tree_blossom", 10)
    inst.components.pickable.onpickedfn = onpickedfn
    inst.components.pickable.remove_when_picked = true
    inst.components.pickable.quickpick = true

    -- 5. 生成月亮蝴蝶（核心：通过 childspawner 赋予它刷新月蝶的能力）
    inst:AddComponent("childspawner")
    inst.components.childspawner.childname = "moonbutterfly"
    inst.components.childspawner:SetRegenPeriod(TUNING.TOTAL_DAY_TIME / 2) -- 刷新恢复CD
    inst.components.childspawner:SetSpawnPeriod(10)                       -- 尝试刷出的间隔
    inst.components.childspawner:SetMaxChildren(2)                        -- 这朵花最大维持月蝶数量
    inst.components.childspawner:StartSpawning()

    -- 6. 环境交互（可燃、可作祟等）
    MakeSmallBurnable(inst)
    MakeSmallPropagator(inst)
    MakeHauntableIgnite(inst)

    return inst
end

return Prefab("cc_moonflower", fn, assets, prefabs)