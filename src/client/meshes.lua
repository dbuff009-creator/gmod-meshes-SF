--@client
-- Infantry Tool :: meshes
-- Builds one mesh per item definition inside a coroutine (the builder yields
-- whenever the CPU budget is used) and applies it to the custom props the
-- server registered. Also owns the field lights.

local C = require("src/client/core.lua")
local CC = require("src/config.lua")
local G = require("src/geom.lua")
local IT = require("src/items.lua")

local V = Vector
local MESH_TWO_SIDED, MESH_CPU, HM = CC.MESH_TWO_SIDED, CC.MESH_CPU, CC.HM
local MAT = CC.MAT
local MDEFS = IT.MDEFS
local ocylBasis = G.ocylBasis

-- ---------------- materials + meshes (every client) ----------------
local getMat, builder
local meshes, bounds = {}, {}
do
local mats = {}
function getMat(key)
    if mats[key] ~= nil then return mats[key] end
    local ok, m = pcall(material.load, MAT[key] or MAT.plain)
    if not ok or not m then ok, m = pcall(material.load, MAT.plain) end
    mats[key] = ok and m or false
    return mats[key]
end

local UV = 1 / 48
-- one triangle (both windings). na/nb/nc = optional smooth vertex normals
-- GMod front face = clockwise seen from outside (SF's obj loader reverses the CCW obj order).
-- Solid parts (known outside via center / vertex normals) get ONE side -> half the triangles;
-- thin parts without an inside (nets, flag cloth) stay two-sided.
local function emitTri(out, a, b, c, center, na, nb, nc)
    local raw = (b - a):cross(c - a)
    if raw:getLength() < 1e-6 then return end
    local n = raw:getNormalized()
    if center and n:dot(a - center) < 0 then n = -n end
    if na and n:dot(na + nb + nc) < 0 then n = -n end
    local ax, ay, az = math.abs(n.x), math.abs(n.y), math.abs(n.z)
    local function vert(p, vn)
        local u, v
        if az >= ax and az >= ay then u, v = p.x * UV, p.y * UV
        elseif ax >= ay then u, v = p.y * UV, -p.z * UV
        else u, v = p.x * UV, -p.z * UV end
        return { pos = p, normal = vn or n, u = u, v = v }
    end
    local oriented = center ~= nil or na ~= nil
    if MESH_TWO_SIDED or not oriented or n:dot(raw) < 0 then
        out[#out + 1] = vert(a, na) out[#out + 1] = vert(b, nb) out[#out + 1] = vert(c, nc)
    end
    if MESH_TWO_SIDED or not oriented or n:dot(raw) > 0 then
        out[#out + 1] = vert(a, na) out[#out + 1] = vert(c, nc) out[#out + 1] = vert(b, nb)
    end
end
local function emitQuad(out, a, b, c, d, center)
    emitTri(out, a, b, c, center)
    emitTri(out, a, c, d, center)
end

local HEX_FACES = { { 1, 4, 3, 2 }, { 5, 6, 7, 8 }, { 1, 2, 6, 5 }, { 2, 3, 7, 6 }, { 3, 4, 8, 7 }, { 4, 1, 5, 8 } }
local function primTris(out, pr, mins, maxs)
    local function grow(p)
        mins.x, mins.y, mins.z = math.min(mins.x, p.x), math.min(mins.y, p.y), math.min(mins.z, p.z)
        maxs.x, maxs.y, maxs.z = math.max(maxs.x, p.x), math.max(maxs.y, p.y), math.max(maxs.z, p.z)
    end
    if pr.t == "hex" then
        local c = V()
        for _, p in ipairs(pr.p) do c = c + p grow(p) end
        c = c / 8
        for _, f in ipairs(HEX_FACES) do emitQuad(out, pr.p[f[1]], pr.p[f[2]], pr.p[f[3]], pr.p[f[4]], c) end
    elseif pr.t == "cyl" then
        local c = pr.c + V(0, 0, pr.h / 2)
        local top, bot = pr.c + V(0, 0, pr.h), pr.c
        grow(pr.c - V(pr.r, pr.r, 0)) grow(pr.c + V(pr.r, pr.r, pr.h))
        for i = 0, pr.n - 1 do
            local a1, a2 = i / pr.n * math.pi * 2, (i + 1) / pr.n * math.pi * 2
            local o1, o2 = V(math.cos(a1) * pr.r, math.sin(a1) * pr.r, 0), V(math.cos(a2) * pr.r, math.sin(a2) * pr.r, 0)
            emitQuad(out, bot + o1, bot + o2, top + o2, top + o1, c)
            emitTri(out, top, top + o1, top + o2, c)
            emitTri(out, bot, bot + o2, bot + o1, c)
        end
    elseif pr.t == "ocyl" then
        local e1, e2 = ocylBasis(pr.a, pr.b)
        local c = (pr.a + pr.b) / 2
        for i = 0, pr.n - 1 do
            local a1, a2 = i / pr.n * math.pi * 2, (i + 1) / pr.n * math.pi * 2
            local o1 = e1 * (math.cos(a1) * pr.r) + e2 * (math.sin(a1) * pr.r)
            local o2 = e1 * (math.cos(a2) * pr.r) + e2 * (math.sin(a2) * pr.r)
            emitQuad(out, pr.a + o1, pr.a + o2, pr.b + o2, pr.b + o1, c)
            emitTri(out, pr.b, pr.b + o1, pr.b + o2, c)
            emitTri(out, pr.a, pr.a + o2, pr.a + o1, c)
            grow(pr.a + o1) grow(pr.b + o1)
        end
    elseif pr.t == "quads" then
        for _, q in ipairs(pr.q) do
            emitQuad(out, q[1], q[2], q[3], q[4], nil)
            grow(q[1]) grow(q[3])
        end
    elseif pr.t == "sq" then
        for _, q in ipairs(pr.q) do
            emitTri(out, q[1], q[2], q[3], nil, q[5], q[6], q[7])
            emitTri(out, q[1], q[3], q[4], nil, q[5], q[7], q[8])
            grow(q[1]) grow(q[3])
        end
    end
end

-- meshes are built in a coroutine: big meshes (nest, trenches) never hit the CPU quota
local function cpuBusy() return cpuUsed() > cpuMax() * (MESH_CPU + 0.1) end

local function buildMesh(d)
    local verts, mins, maxs
    -- one mesh can hold max 65535 vertices: too big -> rebuild with rounder-but-cheaper sandbags
    for _, q in ipairs({ { 10, 5 }, { 8, 4 }, { 6, 3 } }) do
            G.setBagRes(q[1], q[2])
        local prims = {}
        d.fn(prims)
        verts = {}
        mins, maxs = V(1e9, 1e9, 1e9), V(-1e9, -1e9, -1e9)
        for _, pr in ipairs(prims) do
            primTris(verts, pr, mins, maxs)
            if cpuBusy() then coroutine.yield() end
        end
        if #verts <= 65535 then break end
    end
    G.setBagRes(10, 5)
    if #verts > 65535 then
        meshes[d.idx] = false
        print("[Infantry Tool] mesh too big for " .. d.key .. ": " .. #verts .. " vertices")
        return
    end
    local ok, m = pcall(mesh.createFromTable, verts, true)
    if ok and m then
        meshes[d.idx] = m
        bounds[d.idx] = { mins - V(2, 2, 2), maxs + V(2, 2, 2) }
    else
        meshes[d.idx] = false
        print("[Infantry Tool] mesh failed for " .. d.key .. ": " .. tostring(type(m) == "table" and (m.message or m.msg) or m))
    end
end
builder = coroutine.create(function()
    for _, d in ipairs(MDEFS) do
        buildMesh(d)
        coroutine.yield()
    end
end)
end


-- the server tells clients which mesh definition belongs to an entity
-- def 255 = C.alias: a hidden extra collision prop that belongs to object "main"
net.receive("it_reg", function()
    local idx, di = net.readUInt(16), net.readUInt(8)
    if di == 255 then C.alias[idx] = net.readUInt(16) return end
    local d = MDEFS[di]
    if d then C.reg[idx] = { d = d, it = d.it, applied = nil } end
end)
net.receive("it_unreg", function()
    local idx = net.readUInt(16)
    C.reg[idx] = nil
    for k, v in pairs(C.alias) do if v == idx then C.alias[k] = nil end end
end)


local function applyMesh(e, d)
    local m = meshes[d.idx]
    if not m then return false end
    local ok = pcall(function()
        e:setMesh(m)
        local mat = getMat(d.mat)
        if mat then e:setMeshMaterial(mat) end
        local b = bounds[d.idx]
        e:setRenderBounds(b[1], b[2])
    end)
    return ok
end

local nextApply = 0
local function meshesThink()
    if coroutine.status(builder) ~= "dead" then
        -- mesh.createFromTable(threaded) yields every 100 vertices -> resume MANY times per frame
        -- until this frame's CPU budget is used (was 1 resume per frame = very slow).
        -- NOTE: SF coroutine.resume is NOT protected and returns the yielded values (no ok flag)
        local budget = cpuMax() * MESH_CPU
        local n = 0
        while coroutine.status(builder) ~= "dead" and cpuUsed() < budget and n < 2000 do
            n = n + 1
            local ok, err = pcall(coroutine.resume, builder)   -- SF resume is NOT protected and has no ok flag
            if not ok then print("[Infantry Tool] mesh builder error: " .. tostring(err)) break end
        end
        return
    end
    local now = timer.realtime()
    if now < nextApply then return end
    nextApply = now + 0.5
    for idx, r in pairs(C.reg) do
        local e = entity(idx)
        if isValid(e) and r.applied ~= e then
            local c = e:getClass()
            if (c == "starfall_prop" or c == "starfall_hologram") and applyMesh(e, r.d) then r.applied = e end
        end
    end
end
C.think[#C.think + 1] = meshesThink

-- ---------------- field lights (every client; needs light.create permission on that client) ----------------
local lights = {}
local function lightsThink()
    for idx, L in pairs(lights) do
        if not C.reg[idx] then
            if L then pcall(L.destroy, L) end
            lights[idx] = nil
        end
    end
    for idx, r in pairs(C.reg) do
        if r.it and r.it.logic == "light" then
            local e = entity(idx)
            if isValid(e) then
                local pos = e:localToWorld(V(0, 0, 90))
                local L = lights[idx]
                if L == nil then
                    local ok, x = pcall(light.create, pos, 900, 3.5, Color(255, 228, 180))
                    L = ok and x or false
                    lights[idx] = L
                end
                if L then
                    pcall(L.setPos, L, pos)
                    pcall(L.draw, L)
                end
            end
        end
    end
end
C.think[#C.think + 1] = lightsThink

return {
    meshes = meshes,
    bounds = bounds,
    getMat = getMat,
}
