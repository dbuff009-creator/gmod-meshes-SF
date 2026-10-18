-- Infantry Tool :: primitive geometry
-- unit solids (box / open box / beam / frustum / cylinder) plus the sandbag
-- and stack emitters. Every mesh in the chip is built from these, and so is
-- every convex hull on the server (primPoints), which keeps the collision
-- shape and the visual mesh identical.
--
-- setBagRes() lets the client rebuild an over-budget mesh with fewer sandbag
-- segments instead of dropping it.

local V = Vector

-- ============================ GEOMETRY (shared) ============================
-- prims: {t="hex", p={8 corners: bottom 1-4, top 5-8}} | {t="cyl", c=bottomCenter, r, h, n}
--        {t="ocyl", a, b, r, n} (cylinder between two points) | {t="quads", q={{a,b,c,d}...}}
--        {t="sq", q={{a,b,c,d, na,nb,nc,nd}...}} (smooth quads with vertex normals, visual only)
local function hex(list, p) list[#list + 1] = { t = "hex", p = p } end

local function box(list, mn, mx)
    hex(list, {
        V(mn.x, mn.y, mn.z), V(mx.x, mn.y, mn.z), V(mx.x, mx.y, mn.z), V(mn.x, mx.y, mn.z),
        V(mn.x, mn.y, mx.z), V(mx.x, mn.y, mx.z), V(mx.x, mx.y, mx.z), V(mn.x, mx.y, mx.z),
    })
end

-- oriented box: center c, axes ax/ay/az (unit), half sizes hx/hy/hz
local function obox(list, c, ax, ay, az, hx, hy, hz)
    local function P(sx, sy, sz) return c + ax * (sx * hx) + ay * (sy * hy) + az * (sz * hz) end
    hex(list, { P(-1, -1, -1), P(1, -1, -1), P(1, 1, -1), P(-1, 1, -1), P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1) })
end

-- box rotated by yaw around Z (for arcs)
local function ybox(list, c, yaw, hx, hy, hz)
    local a = Angle(0, yaw, 0)
    obox(list, c, a:getForward(), -a:getRight(), V(0, 0, 1), hx, hy, hz)
end

-- beam box between two points (planks, braces)
local function beam(list, a, b, hw, hh)
    local d = b - a
    local len = d:getLength()
    local f = d / len
    local s = f:cross(math.abs(f.z) < 0.95 and V(0, 0, 1) or V(1, 0, 0)):getNormalized()
    local u = s:cross(f):getNormalized()
    obox(list, (a + b) / 2, f, s, u, len / 2, hw, hh)
end

-- frustum: base bx*by at z0, top tx*ty at z0+h
local function frustum(list, cx, cy, z0, bx, by, tx, ty, h)
    hex(list, {
        V(cx - bx, cy - by, z0), V(cx + bx, cy - by, z0), V(cx + bx, cy + by, z0), V(cx - bx, cy + by, z0),
        V(cx - tx, cy - ty, z0 + h), V(cx + tx, cy - ty, z0 + h), V(cx + tx, cy + ty, z0 + h), V(cx - tx, cy + ty, z0 + h),
    })
end

local function cyl(list, c, r, h, n) list[#list + 1] = { t = "cyl", c = c, r = r, h = h, n = n or 12 } end
local function ocyl(list, a, b, r, n) list[#list + 1] = { t = "ocyl", a = a, b = b, r = r, n = n or 10 } end

local function ocylBasis(a, b)
    local d = (b - a):getNormalized()
    local e1 = d:cross(math.abs(d.z) < 0.9 and V(0, 0, 1) or V(1, 0, 0)):getNormalized()
    local e2 = d:cross(e1):getNormalized()
    return e1, e2
end

-- ROUND sandbag: superellipsoid pillow with smooth normals (visual only)
local RES = { nu = 10, nv = 5 }   -- sandbag tessellation, see setBagRes()
local function spow(v, e) if v < 0 then return -((-v) ^ e) end return v ^ e end
local function bag(list, c, yaw, l, w, h)
    local BAG_NU, BAG_NV = RES.nu, RES.nv
    local an = Angle(0, yaw, 0)
    local ax, ay, az = an:getForward(), -an:getRight(), V(0, 0, 1)
    local A, B, C = l * 0.5, w * 0.5, h * 0.5
    local E1, E2 = 0.55, 0.32        -- vertical / plan squareness (1 = ellipsoid, -> 0 = box)
    local P, N = {}, {}
    for j = 0, BAG_NV do
        local v = -math.pi / 2 + math.pi * j / BAG_NV
        local cv, sv = math.cos(v), math.sin(v)
        if j == 0 or j == BAG_NV then cv = 0 end
        P[j], N[j] = {}, {}
        for i = 0, BAG_NU - 1 do
            local u = math.pi * 2 * i / BAG_NU + math.pi / BAG_NU
            local cu, su = math.cos(u), math.sin(u)
            local x = A * spow(cv, E1) * spow(cu, E2)
            local y = B * spow(cv, E1) * spow(su, E2)
            local z = C * spow(sv, E1)
            P[j][i] = c + ax * x + ay * y + az * (z + C)
            local nx = spow(cv, 2 - E1) * spow(cu, 2 - E2) / A
            local ny = spow(cv, 2 - E1) * spow(su, 2 - E2) / B
            local nz = spow(sv, 2 - E1) / C
            local n = ax * nx + ay * ny + az * nz
            if n:getLength() < 1e-6 then n = az * (sv < 0 and -1 or 1) end
            N[j][i] = n:getNormalized()
        end
    end
    local q = {}
    for j = 0, BAG_NV - 1 do
        for i = 0, BAG_NU - 1 do
            local i2 = (i + 1) % BAG_NU
            q[#q + 1] = { P[j][i], P[j][i2], P[j + 1][i2], P[j + 1][i], N[j][i], N[j][i2], N[j + 1][i2], N[j + 1][i] }
        end
    end
    list[#list + 1] = { t = "sq", q = q }
end

-- row(s) of sandbags along X from x0 to x1 at y, layer count (bricked)
local BAG_L, BAG_W, BAG_H = 22, 13, 8
local function bagRow(list, x0, x1, y, z, layers)
    for k = 0, layers - 1 do
        local off = (k % 2 == 1) and BAG_L * 0.5 or 0
        local x = x0 + BAG_L * 0.5 + off
        while x + BAG_L * 0.5 <= x1 + 0.1 do
            bag(list, V(x, y, z + k * (BAG_H - 1)), 0, BAG_L, BAG_W, BAG_H)
            x = x + BAG_L
        end
    end
end
local function bagRowY(list, y0, y1, x, z, layers)
    for k = 0, layers - 1 do
        local off = (k % 2 == 1) and BAG_L * 0.5 or 0
        local y = y0 + BAG_L * 0.5 + off
        while y + BAG_L * 0.5 <= y1 + 0.1 do
            bag(list, V(x, y, z + k * (BAG_H - 1)), 90, BAG_L, BAG_W, BAG_H)
            y = y + BAG_L
        end
    end
end
local function stackH(layers) return layers * (BAG_H - 1) + 1 end

-- convex point list for a prim (server collision)
local function primPoints(pr)
    if pr.t == "hex" then return pr.p end
    if pr.t == "cyl" then
        local pts = {}
        for i = 0, pr.n - 1 do
            local a = i / pr.n * math.pi * 2
            local x, y = math.cos(a) * pr.r, math.sin(a) * pr.r
            pts[#pts + 1] = pr.c + V(x, y, 0)
            pts[#pts + 1] = pr.c + V(x, y, pr.h)
        end
        return pts
    end
    if pr.t == "ocyl" then
        local e1, e2 = ocylBasis(pr.a, pr.b)
        local pts = {}
        for i = 0, pr.n - 1 do
            local a = i / pr.n * math.pi * 2
            local o = e1 * (math.cos(a) * pr.r) + e2 * (math.sin(a) * pr.r)
            pts[#pts + 1] = pr.a + o
            pts[#pts + 1] = pr.b + o
        end
        return pts
    end
end

local function setBagRes(nu, nv)
    RES.nu, RES.nv = nu or 10, nv or 5
end

return {
    bag = bag,
    bagRow = bagRow,
    bagRowY = bagRowY,
    beam = beam,
    box = box,
    cyl = cyl,
    frustum = frustum,
    hex = hex,
    obox = obox,
    ocyl = ocyl,
    ocylBasis = ocylBasis,
    primPoints = primPoints,
    stackH = stackH,
    ybox = ybox,
    BAG_L = BAG_L,
    BAG_W = BAG_W,
    BAG_H = BAG_H,
    setBagRes = setBagRes,
}
