local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G
local AddPlayerPostInit = (env and env.AddPlayerPostInit) or rawget(GLOBAL, "AddPlayerPostInit")

local function IsAllowedMemoryContainer(inst)
    if not inst then return false end
    return inst.prefab == "dragonflychest" or inst:HasTag("cc_memory_chest")
end

local function IsMemoryItem(item)
    if not item then return false end
    return item:HasTag("cc_memory_item")
        or item:HasTag("cc_memory")
        or item:HasTag("cc_memscrap")
        or item.prefab == "cc_memory"
        or item.prefab == "cc_memscrap"
        or (item.prefab and string.sub(item.prefab, 1, 6) == "cc_mem")
end

-- 1. 服务端与客户端类原型拦截（覆盖全局所有容器，包括模组箱子与背包）
local Container = rawget(GLOBAL, "require")("components/container")
local ContainerReplica = rawget(GLOBAL, "require")("components/container_replica")

if Container then
    local old_CanTake = Container.CanTakeItemInSlot
    Container.CanTakeItemInSlot = function(self, item, slot)
        if IsMemoryItem(item) and not IsAllowedMemoryContainer(self.inst) then
            return false
        end
        if old_CanTake then
            return old_CanTake(self, item, slot)
        end
        return true
    end

    local old_Prioritize = Container.ShouldPrioritizeContainer
    Container.ShouldPrioritizeContainer = function(self, item)
        if IsMemoryItem(item) and not IsAllowedMemoryContainer(self.inst) then
            return false
        end
        if old_Prioritize then
            return old_Prioritize(self, item)
        end
        return false
    end
end

if ContainerReplica then
    local old_CanTake_Replica = ContainerReplica.CanTakeItemInSlot
    ContainerReplica.CanTakeItemInSlot = function(self, item, slot)
        if IsMemoryItem(item) and not IsAllowedMemoryContainer(self.inst) then
            return false
        end
        if old_CanTake_Replica then
            return old_CanTake_Replica(self, item, slot)
        end
        return true
    end
end

-- 2. 死亡结算：零碎记忆彻底蒸发清零，蓝图记忆安全留存
AddPlayerPostInit(function(inst)
    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not TheWorld or not TheWorld.ismastersim then
        return
    end

    local inventory = inst.components and inst.components.inventory
    if inventory then
        local old_DropEverything = inventory.DropEverything
        inventory.DropEverything = function(inv, ondeath, keepequip)
            if ondeath then
                local scraps = inv:FindItems(function(item)
                    return item:HasTag("cc_memscrap")
                end)
                for _, scrap in ipairs(scraps) do
                    local removed = inv:RemoveItem(scrap, true)
                    if removed then
                        removed:Remove()
                    end
                end
            end
            return old_DropEverything(inv, ondeath, keepequip)
        end
    end
end)