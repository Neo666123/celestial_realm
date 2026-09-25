local rawget = rawget
local GLOBAL = rawget(_G, "GLOBAL") or _G
local CreateEntity = rawget(GLOBAL, "CreateEntity")
local Prefab = rawget(GLOBAL, "Prefab")
local COLLISION = rawget(GLOBAL, "COLLISION")

local MESH_POINTS = {
    {-23, 6}, {-22, 7}, {-20, 7}, {-19, 8}, {-19, 18}, {-18, 19},
    {-8, 19}, {-7, 20}, {-7, 22}, {-6, 23}, {6, 23}, {7, 22},
    {7, 20}, {8, 19}, {18, 19}, {19, 18}, {19, 8}, {20, 7},
    {22, 7}, {23, 6}, {23, -6}, {22, -7}, {20, -7}, {19, -8},
    {19, -18}, {18, -19}, {8, -19}, {7, -20}, {7, -22}, {6, -23},
    {-6, -23}, {-7, -22}, {-7, -20}, {-8, -19}, {-18, -19}, {-19, -18},
    {-19, -8}, {-20, -7}, {-22, -7}, {-23, -6},
}

local function AddPlane(triangles, x0, y0, z0, x1, y1, z1)
    table.insert(triangles, x0); table.insert(triangles, y0); table.insert(triangles, z0)
    table.insert(triangles, x0); table.insert(triangles, y1); table.insert(triangles, z0)
    table.insert(triangles, x1); table.insert(triangles, y0); table.insert(triangles, z1)
    table.insert(triangles, x1); table.insert(triangles, y0); table.insert(triangles, z1)
    table.insert(triangles, x0); table.insert(triangles, y1); table.insert(triangles, z0)
    table.insert(triangles, x1); table.insert(triangles, y1); table.insert(triangles, z1)
end

local function BuildPhysicsMesh(points)
    local triangles = {}
    local total = #points
    local v0 = points[total]
    for index = 1, total do
        local v1 = points[index]
        AddPlane(triangles, v0[1], 0, v0[2], v1[1], 10, v1[2])
        v0 = v1
    end
    return triangles
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddNetwork()
    inst.entity:AddPhysics()

    inst.Physics:SetMass(0)
    inst.Physics:SetCollisionGroup(COLLISION.CHARACTERS)
    inst.Physics:SetCollisionMask(COLLISION.CHARACTERS)
    inst.Physics:SetTriangleMesh(BuildPhysicsMesh(MESH_POINTS))

    inst:AddTag("NOBLOCK")
    inst:AddTag("ignorewalkableplatforms")
    inst:AddTag("staysthroughvirtualrooms")

    inst.entity:SetPristine()

    local TheWorld = rawget(GLOBAL, "TheWorld")
    if not TheWorld or not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false
    return inst
end

return Prefab("celestial_roguelike_collision", fn)