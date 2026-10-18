-- Infantry Tool :: item catalogue
-- Every placeable object is declared here: name, category, cost, colour,
-- collision run and mesh run. The server only ever consumes the collision
-- run (it.col / it.mountCol), the client only the mesh run (it.mesh / it.gun),
-- so both sides stay in sync by construction.

local C = require("src/config.lua")
local G = require("src/geom.lua")

local V = Vector
local HM = C.HM
local TRENCH_CELL, TRENCH_WIDTH, TRENCH_DEPTH = C.TRENCH_CELL, C.TRENCH_WIDTH, C.TRENCH_DEPTH
local TRENCH_SPILL, TRENCH_FIRE_STEP, ROOF_Z = C.TRENCH_SPILL, C.TRENCH_FIRE_STEP, C.ROOF_Z
local TIMED_FUSE, GUN_STATS = C.TIMED_FUSE, C.GUN_STATS

local box, obox, ybox, beam, frustum, hex = G.box, G.obox, G.ybox, G.beam, G.frustum, G.hex
local cyl, ocyl, ocylBasis = G.cyl, G.ocyl, G.ocylBasis
local bag, bagRow, bagRowY, BAG_L, BAG_W, BAG_H = G.bag, G.bagRow, G.bagRowY, G.BAG_L, G.BAG_W, G.BAG_H
local stackH, primPoints = G.stackH, G.primPoints

local CAT_NAMES = { "MINES", "GEAR", "TURRETS", "TRENCHES", "FORTS", "OBSTACLES" }
-- kind: mesh (custom prop) | gun (custom prop + hologram + seat) | tripwire
-- place: surface (align to surface) | upright (yaw only) | trench (trench grid)
-- stack = height of the top surface -> other stackable items snap onto it
local ITEMS = {}
local function item(t) ITEMS[#ITEMS + 1] = t t.idx = #ITEMS return t end

local C_OLIVE, C_TAN, C_STEEL, C_CONC, C_DIRT = Color(95, 105, 65), Color(190, 170, 120), Color(110, 110, 115), Color(175, 172, 165), Color(150, 125, 95)
local C_WOOD, C_GUN = Color(150, 115, 80), Color(70, 72, 68)

item{ id = "at", cat = 1, name = "AT Mine", desc = "Vehicles only, big blast", kind = "mesh", mat = "metal", color = C_OLIVE,
    place = "surface", logic = "at",
    col = function(l) cyl(l, V(0, 0, 0), 14, 5, 12) end,
    vis = function(l) cyl(l, V(0, 0, 0), 14, 4, 20) cyl(l, V(0, 0, 4), 11, 1.5, 20) cyl(l, V(0, 0, 5.5), 4, 2, 12) end }

item{ id = "ap", cat = 1, name = "AP Mine", desc = "Infantry, small blast", kind = "mesh", mat = "metal", color = Color(80, 85, 60),
    place = "surface", logic = "ap",
    col = function(l) cyl(l, V(0, 0, 0), 5, 3, 8) end,
    vis = function(l) cyl(l, V(0, 0, 0), 5, 2.5, 14) cyl(l, V(0, 0, 2.5), 1.5, 1.5, 8) end }

item{ id = "bounce", cat = 1, name = "Bounding Mine", desc = "Jumps up, then blasts", kind = "mesh", mat = "metal", color = Color(85, 90, 70),
    place = "surface", logic = "bounce",
    col = function(l) cyl(l, V(0, 0, 0), 5.5, 7, 8) end,
    vis = function(l)
        cyl(l, V(0, 0, 0), 5.5, 6, 14) cyl(l, V(0, 0, 6), 1.2, 1.5, 8)
        for k = 0, 2 do
            local a = k * math.pi * 2 / 3
            ocyl(l, V(math.cos(a) * 1.6, math.sin(a) * 1.6, 6), V(math.cos(a) * 2.2, math.sin(a) * 2.2, 10), 0.35, 6)
        end
    end }

item{ id = "trip", cat = 1, name = "Tripwire", desc = "LMB nade, LMB wire end", kind = "tripwire",
    model = "models/weapons/w_grenade.mdl", place = "surface", logic = "trip" }

item{ id = "clay", cat = 1, name = "Claymore", desc = "Directional mine", kind = "mesh", mat = "plain", color = C_OLIVE,
    place = "upright", faceAway = true, logic = "clay",
    col = function(l) box(l, V(-2, -6, 2), V(2, 6, 11)) end,
    vis = function(l)
        ybox(l, V(0, 0, 7), 0, 1.4, 3, 4) ybox(l, V(-0.6, 4.6, 7), -25, 1.4, 2, 4) ybox(l, V(-0.6, -4.6, 7), 25, 1.4, 2, 4)
        obox(l, V(-1, 3.5, 2), V(1, 0, 0), V(0, 1, 0), V(0, 0, 1), 0.4, 0.4, 2.5)
        obox(l, V(-1, -3.5, 2), V(1, 0, 0), V(0, 1, 0), V(0, 0, 1), 0.4, 0.4, 2.5)
    end }

item{ id = "c4", cat = 1, name = "C4", desc = "Remote, X = boom", kind = "mesh", mat = "plain", color = C_TAN,
    place = "surface", logic = "c4",
    col = function(l) box(l, V(-6, -3.5, 0), V(6, 3.5, 3)) end,
    vis = function(l) box(l, V(-6, -3.5, 0), V(6, 3.5, 2.6)) box(l, V(-2, -2, 2.6), V(2.5, 2, 3.6)) end }

item{ id = "laser", cat = 1, name = "Laser Mine", desc = "Wall, red beam trigger", kind = "mesh", mat = "metal", color = Color(70, 75, 70),
    place = "surface", logic = "laser",
    col = function(l) box(l, V(-5, -3.5, 0), V(5, 3.5, 5)) end,
    vis = function(l)
        box(l, V(-5, -3.5, 0), V(5, 3.5, 4.5))
        ocyl(l, V(0, 0, 4.5), V(0, 0, 6), 1.6, 12)                         -- emitter
        ocyl(l, V(0, 0, 6), V(0, 0, 6.4), 1.0, 12)
        box(l, V(-4.5, -3, 4.5), V(-2.5, -1, 5.2))                         -- arm light
        box(l, V(-6, -1, 0), V(-5, 1, 1)) box(l, V(5, -1, 0), V(6, 1, 1)) -- screw tabs
    end }

item{ id = "ied", cat = 1, name = "IED", desc = "Buried, all targets, huge", kind = "mesh", mat = "dirt", color = Color(105, 88, 62),
    place = "surface", logic = "ied",
    col = function(l) box(l, V(-14, -14, 0), V(14, 14, 5)) end,
    vis = function(l)
        frustum(l, 0, 0, 0, 16, 14, 9, 8, 4)                               -- dirt mound
        box(l, V(-6, -5, 3.6), V(6, 5, 4.6))                               -- pressure plate
        ocyl(l, V(6, 3, 4), V(14, 9, 0.5), 0.35, 6)                        -- wires
        ocyl(l, V(6, -2, 4), V(15, -8, 0.5), 0.35, 6)
        cyl(l, V(-9, 7, 2), 2.2, 3, 10)                                    -- shell nose sticking out
    end }

item{ id = "timed", cat = 1, name = "Timed Charge", desc = "R = timer, RMB = defuse", kind = "mesh", mat = "plain", color = Color(120, 45, 40),
    place = "surface", logic = "timed",
    col = function(l) box(l, V(-7, -4.5, 0), V(7, 4.5, 4)) end,
    vis = function(l)
        for k = -1, 1 do ocyl(l, V(-7, k * 3, 2), V(7, k * 3, 2), 1.5, 10) end   -- 3 sticks
        box(l, V(-2, -4.6, 0.5), V(2, 4.6, 3.5))                            -- tape
        box(l, V(-3.5, -2.5, 3.5), V(3.5, 2.5, 5))                          -- timer box
        ocyl(l, V(3.5, 1.5, 4.2), V(8, 4, 1), 0.3, 6) ocyl(l, V(3.5, -1.5, 4.2), V(8, -4, 1), 0.3, 6)
    end }

-- ---------------- GEAR ----------------
item{ id = "radar", cat = 2, name = "Recon Radar", desc = "Enemies on your HUD", kind = "mesh", mat = "metal", color = Color(100, 110, 95),
    place = "upright", faceAway = true, logic = "radar", grid = true,
    col = function(l) box(l, V(-12, -12, 0), V(12, 12, 60)) end,
    vis = function(l)
        for k = 0, 2 do
            local a = k * math.pi * 2 / 3
            ocyl(l, V(0, 0, 36), V(math.cos(a) * 18, math.sin(a) * 18, 0), 0.9, 8)
        end
        cyl(l, V(0, 0, 34), 3, 6, 10)
        box(l, V(-6, -5, 40), V(6, 5, 48))                                 -- electronics box
        ocyl(l, V(0, 0, 48), V(0, 0, 52), 1.2, 8)
        local dn = V(1, 0, 0.5):getNormalized()
        ocyl(l, V(0, 0, 53), V(0, 0, 53) + dn * 1.5, 13, 18)              -- dish
        ocyl(l, V(0, 0, 53) + dn * 1.5, V(0, 0, 53) + dn * 2.5, 9, 18)
        ocyl(l, V(0, 0, 53) + dn * 2.5, V(0, 0, 53) + dn * 12, 0.5, 6)   -- feed horn
        ocyl(l, V(0, 0, 53) + dn * 12, V(0, 0, 53) + dn * 14, 1.4, 8)
    end }
item{ id = "alarm", cat = 2, name = "Motion Alarm", desc = "Siren + HUD alert", kind = "mesh", mat = "plain", color = Color(70, 75, 65),
    place = "surface", logic = "alarm",
    col = function(l) box(l, V(-4, -4, 0), V(4, 4, 7)) end,
    vis = function(l)
        box(l, V(-4, -4, 0), V(4, 4, 6))
        ocyl(l, V(4, 0, 3), V(5.2, 0, 3), 1.8, 12)                         -- lens
        ocyl(l, V(5.2, 0, 3), V(5.6, 0, 3), 1.2, 12)
        cyl(l, V(-2, 2, 6), 1.2, 1.5, 8)                                   -- siren
        ocyl(l, V(-2, -2.5, 6), V(-2, -2.5, 16), 0.25, 6)                  -- antenna
    end }
item{ id = "light", cat = 2, name = "Field Light", desc = "Lamp, lights the area", kind = "mesh", mat = "metal", color = Color(120, 118, 100),
    place = "upright", faceAway = true, logic = "light", grid = true,
    col = function(l) box(l, V(-10, -10, 0), V(10, 10, 104)) end,
    vis = function(l)
        for k = 0, 2 do
            local a = k * math.pi * 2 / 3 + 0.5
            ocyl(l, V(0, 0, 30), V(math.cos(a) * 20, math.sin(a) * 20, 0), 0.9, 8)
        end
        cyl(l, V(0, 0, 0), 1.4, 96, 8)                                     -- pole
        box(l, V(-6, -9, 96), V(6, 9, 102))                                -- lamp head
        box(l, V(-5, -8, 94.5), V(5, 8, 96))                               -- glass
        box(l, V(-1, -10, 98), V(1, 10, 100))                              -- bracket
        box(l, V(-3, -3, 20), V(3, 3, 28))                                 -- battery box
    end }

item{ id = "cam", cat = 2, name = "Periscope Cam", desc = "B = look through cams", kind = "mesh", mat = "metal", color = Color(80, 85, 78),
    place = "upright", faceAway = true, logic = "cam", grid = true,
    col = function(l) box(l, V(-10, -10, 0), V(10, 10, 50)) end,
    vis = function(l)
        for k = 0, 2 do
            local a = k * math.pi * 2 / 3 + 1
            ocyl(l, V(0, 0, 38), V(math.cos(a) * 16, math.sin(a) * 16, 0), 0.8, 8)
        end
        cyl(l, V(0, 0, 36), 2.5, 5, 10)
        box(l, V(-7, -4.5, 41), V(7, 4.5, 50))                             -- camera body
        ocyl(l, V(7, 0, 45.5), V(11, 0, 45.5), 3, 14)                      -- lens
        ocyl(l, V(11, 0, 45.5), V(11.6, 0, 45.5), 2.2, 14)
        box(l, V(-4, -1, 50), V(-2, 1, 58))                                -- antenna
    end }

item{ id = "flag", cat = 2, name = "Rally Flag", desc = "Waypoint on your HUD", kind = "mesh", mat = "plain", color = Color(170, 45, 40),
    place = "upright", faceAway = true, logic = "flag",
    col = function(l) box(l, V(-3, -3, 0), V(3, 3, 112)) end,
    vis = function(l)
        cyl(l, V(0, 0, 0), 1.1, 112, 8)
        cyl(l, V(0, 0, 112), 2, 2, 8)
        local q = {}
        local N = 10
        for i = 0, N - 1 do                                                -- waving cloth
            local x0, x1 = 1 + i * 4, 1 + (i + 1) * 4
            local y0, y1 = math.sin(i * 0.8) * 3 * i / N, math.sin((i + 1) * 0.8) * 3 * (i + 1) / N
            q[#q + 1] = { V(x0, y0, 84), V(x1, y1, 84), V(x1, y1, 108), V(x0, y0, 108) }
        end
        l[#l + 1] = { t = "quads", q = q }
        box(l, V(-8, -8, 0), V(8, 8, 3))
    end }

-- ---------------- manned guns: base (custom prop) + gun part (hologram) ----------------
-- geo: pivot = gun hologram position on the base, muzzle / eye in gun space, seat in base space
-- trench mount: the gun stands on a post next to a trench wall, barrel just over the parapet bags,
-- the gunner sits inside the trench on 2 ammo boxes
local GUN_GEO = {
    mg     = { pivot = V(0, 0, 30), muzzle = V(49, 0, 0.5), eye = V(-26, 0, 9),  seat = V(-40, 0, 14) },
    sniper = { pivot = V(0, 0, 30), muzzle = V(50, 0, 0),   eye = V(-22, 0, 10), seat = V(-44, 0, 14) },
    atgun  = { pivot = V(0, 0, 30), muzzle = V(84, 0, 0),   eye = V(-36, 0, 13), seat = V(-62, 0, 14) },
    mortar = { pivot = V(0, 0, 8),  muzzle = V(47, 0, 0),   eye = V(-40, 0, 40), seat = V(-40, 0, 14) },
    flak   = { pivot = V(0, 0, 36), muzzle = V(62, 5, 1),   muzzle2 = V(62, -5, 1), eye = V(-28, 0, 12), seat = V(-46, 0, 14) },
}
-- gun mounts: the gun stands on a post of one of these pivot heights (behind a wall / in a trench / on a deck)
local MOUNT_LEVELS = { 42, 54, 64, TRENCH_DEPTH + 14, 140 }
local MOUNT_TRENCH = 4
local MOUNT_FRONT = 8
local function mountLevelFor(P)
    if P <= 36 then return 0 end
    for k, h in ipairs(MOUNT_LEVELS) do if h >= P - 2 then return k end end
    return #MOUNT_LEVELS
end
local function mountSeatZ(P) return math.max(14, P - 46) end
local function gunPivot(gun, lvl) return (lvl and lvl > 0) and V(0, 0, MOUNT_LEVELS[lvl]) or GUN_GEO[gun].pivot end
local function gunSeatPos(gun, lvl)
    local s = GUN_GEO[gun].seat
    if not s then return nil end
    return (lvl and lvl > 0) and V(s.x, 0, mountSeatZ(MOUNT_LEVELS[lvl])) or s
end
do
local function ammoStool(l, x, z0)
    z0 = z0 or 0
    box(l, V(x - 8, -9, z0), V(x + 8, 9, z0 + 13))
    box(l, V(x - 8.5, -9.5, z0 + 13), V(x + 8.5, 9.5, z0 + 14))
    box(l, V(x - 2, -10, z0 + 6), V(x + 2, -9, z0 + 9)) box(l, V(x - 2, 9, z0 + 6), V(x + 2, 10, z0 + 9))
end
-- post of height P (pivot) + a stack of ammo boxes as the gunner seat
local function mountPost(l, seatX, P)
    local sz = mountSeatZ(P)
    box(l, V(-4, -4, 0), V(4, 4, P - 11))                      -- post
    box(l, V(-10, -10, 0), V(10, 10, 3))                       -- foot plate
    local bz = math.min(30, P - 14)
    beam(l, V(0, 0, bz), V(9, 0, 3), 1, 1) beam(l, V(0, 0, bz), V(-9, 0, 3), 1, 1)
    beam(l, V(0, 0, bz), V(0, 9, 3), 1, 1) beam(l, V(0, 0, bz), V(0, -9, 3), 1, 1)
    cyl(l, V(0, 0, P - 9), 3, 5, 12)                           -- swivel
    cyl(l, V(0, 0, P - 11), 4.5, 2, 12)
    local z, k = 0, 0
    while z < sz - 14 - 0.5 do                                 -- crate stack under the seat
        local z1 = math.min(z + 20, sz - 14)
        local o = (k % 2 == 0) and 0 or 1
        box(l, V(seatX - 10 + o, -11 + o, z), V(seatX + 10 - o, 11 - o, z1 - 0.4))
        box(l, V(seatX - 10.5 + o, -4, z + 2), V(seatX + 10.5 - o, 4, z1 - 2))
        z, k = z1, k + 1
    end
    ammoStool(l, seatX, sz - 14)
end
local function mountCol(seatX, P)
    return function(l)
        box(l, V(-6, -6, 0), V(6, 6, P - 6))
        box(l, V(seatX - 10, -11, 0), V(seatX + 10, 11, mountSeatZ(P)))
    end
end
local function mountable(it, seatX)
    it.mountVis, it.mountCol = {}, {}
    for k, P in ipairs(MOUNT_LEVELS) do
        it.mountVis[k] = function(l) mountPost(l, seatX, P) end
        it.mountCol[k] = mountCol(seatX, P)
    end
    return it
end
local function mgPart(l)
    box(l, V(-16, -3, -3), V(6, 3, 4))                         -- receiver
    box(l, V(-12, -3.2, 4), V(2, 3.2, 5.4))                    -- feed cover
    ocyl(l, V(6, 0, 0.5), V(28, 0, 0.5), 2.4, 12)              -- barrel jacket
    ocyl(l, V(28, 0, 0.5), V(46, 0, 0.5), 1.1, 10)             -- barrel
    ocyl(l, V(45, 0, 0.5), V(49, 0, 0.5), 1.7, 10)             -- muzzle
    box(l, V(40, -0.4, 1.6), V(41.5, 0.4, 5))                  -- front sight
    box(l, V(-7, -1.2, 5.4), V(-5.5, 1.2, 7))                  -- rear sight
    box(l, V(-17.5, -3, -3), V(-16, 3, 3))                     -- back plate
    ocyl(l, V(-19, -2.5, -3), V(-19, -2.5, 3), 0.8, 8)         -- spade grips
    ocyl(l, V(-19, 2.5, -3), V(-19, 2.5, 3), 0.8, 8)
    box(l, V(-19, -2.5, -0.6), V(-17.5, 2.5, 0.6))
    box(l, V(-8, 3, -9), V(4, 9, 2))                           -- ammo box
    box(l, V(-6, 3, 1), V(2, 3.6, 3.5))                        -- belt
    box(l, V(-3, -1.5, -6), V(3, 1.5, -3))                     -- mount
end
local function mgBase(l)
    cyl(l, V(0, 0, 23), 3, 5, 12)                              -- hub
    cyl(l, V(0, 0, 21), 4.5, 2, 12)
    ocyl(l, V(0, 0, 22), V(28, 0, 0), 1.2, 8)                  -- tripod legs
    ocyl(l, V(0, 0, 22), V(-18, 17, 0), 1.2, 8)
    ocyl(l, V(0, 0, 22), V(-18, -17, 0), 1.2, 8)
    ammoStool(l, -40)
end
local function sniperPart(l)
    box(l, V(-34, -1.6, -4), V(-14, 1.6, 1.5))                 -- stock
    box(l, V(-30, -1.4, 1.5), V(-18, 1.4, 3))                  -- cheek rest
    box(l, V(-14, -1.8, -2), V(6, 1.8, 2))                     -- receiver
    box(l, V(-6, -1.2, -6), V(-1, 1.2, -2))                    -- magazine
    box(l, V(-12, -0.4, -4.5), V(-8, 0.4, -2))                 -- trigger guard
    ocyl(l, V(6, 0, 0), V(44, 0, 0), 0.9, 10)                  -- barrel
    box(l, V(44, -1.3, -1), V(50, 1.3, 1))                     -- muzzle brake
    ocyl(l, V(-10, 0, 4), V(10, 0, 4), 1.3, 12)                -- scope
    ocyl(l, V(10, 0, 4), V(14, 0, 4), 2, 12)
    ocyl(l, V(-13, 0, 4), V(-10, 0, 4), 1.8, 12)
    box(l, V(-6, -0.8, 1.6), V(-4, 0.8, 2.9)) box(l, V(4, -0.8, 1.6), V(6, 0.8, 2.9))
    box(l, V(-1, 1.8, 0.5), V(1, 3.5, 1.5))                    -- bolt handle
end
local function sniperBase(l)
    bag(l, V(14, -7, 0), 0, 26, 15, 10) bag(l, V(14, 7, 0), 0, 26, 15, 10)
    bag(l, V(14, 0, 9), 0, 26, 15, 10)
    ocyl(l, V(20, 0, 26), V(24, 6, 18.5), 0.7, 8)              -- bipod resting on the bags
    ocyl(l, V(20, 0, 26), V(24, -6, 18.5), 0.7, 8)
    cyl(l, V(0, 0, 22), 2.5, 7, 10)                            -- swivel post
    box(l, V(-3, -6, 18), V(3, 6, 22))
    ammoStool(l, -44)
end
item{ id = "mg", cat = 3, name = "Machine Gun", desc = "Manned, E to use", kind = "gun", gun = "mg",
    mat = "metal", color = C_GUN, place = "upright", faceAway = true,
    col = function(l) box(l, V(-16, -16, 0), V(16, 16, 22)) box(l, V(-48, -9, 0), V(-32, 9, 14)) end,
    vis = mgBase, part = mgPart }
mountable(ITEMS[#ITEMS], -40)
item{ id = "sniper", cat = 3, name = "Sniper Rifle", desc = "Manned, scope, E", kind = "gun", gun = "sniper",
    mat = "metal", color = Color(90, 85, 70), place = "upright", faceAway = true,
    col = function(l) box(l, V(-4, -15, 0), V(28, 15, 20)) box(l, V(-52, -9, 0), V(-36, 9, 14)) end,
    vis = sniperBase, part = sniperPart }
mountable(ITEMS[#ITEMS], -44)

-- anti-tank gun (shield + wheels)
local function atPart(l)
    box(l, V(8, -26, -16), V(10, 26, 9))                       -- shield
    box(l, V(8, -26, 9), V(10, -5, 18)) box(l, V(8, 5, 9), V(10, 26, 18))
    box(l, V(10, -27, -16), V(13, -25, 18)) box(l, V(10, 25, -16), V(13, 27, 18))
    ocyl(l, V(0, 0, 0), V(78, 0, 0), 2.2, 12)                  -- barrel
    ocyl(l, V(76, 0, 0), V(84, 0, 0), 3.4, 10)                 -- muzzle brake
    ocyl(l, V(-6, 0, -4.5), V(40, 0, -4.5), 2.6, 10)           -- recuperator
    box(l, V(-22, -5, -5), V(0, 5, 5))                         -- breech
    box(l, V(-28, -1, -2), V(-22, 1, 2))
    box(l, V(-8, 6, 3), V(2, 8, 7))                            -- sight
    ocyl(l, V(-2, 8, 5), V(-10, 8, 5), 1, 8)
end
local function atBase(l)
    ocyl(l, V(0, -30, 14), V(0, 30, 14), 1.8, 8)               -- axle
    ocyl(l, V(0, -31, 14), V(0, -25, 14), 14, 16)              -- wheels
    ocyl(l, V(0, 25, 14), V(0, 31, 14), 14, 16)
    ocyl(l, V(0, -32, 14), V(0, -31, 14), 4, 10) ocyl(l, V(0, 31, 14), V(0, 32, 14), 4, 10)
    beam(l, V(0, -8, 14), V(-74, -28, 1), 2, 2.5)              -- split trails
    beam(l, V(0, 8, 14), V(-74, 28, 1), 2, 2.5)
    box(l, V(-78, -32, 0), V(-70, -24, 3)) box(l, V(-78, 24, 0), V(-70, 32, 3))
    cyl(l, V(0, 0, 14), 5, 10, 12)                             -- mount
    box(l, V(-6, -6, 24), V(6, 6, 26))
    ammoStool(l, -62)
end
item{ id = "atgun", cat = 3, name = "AT Gun", desc = "Manned, 1 shell + blast", kind = "gun", gun = "atgun",
    mat = "metal", color = Color(80, 88, 70), place = "upright", faceAway = true, grid = true,
    col = function(l) box(l, V(-20, -32, 0), V(14, 32, 28)) box(l, V(-70, -9, 0), V(-54, 9, 14)) end,
    vis = atBase, part = atPart }
mountable(ITEMS[#ITEMS], -62)

-- mortar (indirect fire)
local function mortarPart(l)
    ocyl(l, V(-4, 0, 0), V(44, 0, 0), 3.2, 14)                 -- tube
    ocyl(l, V(44, 0, 0), V(47, 0, 0), 3.8, 14)
    ocyl(l, V(-7, 0, 0), V(-4, 0, 0), 3.7, 12)                 -- breech cap
    ocyl(l, V(24, 0, 0), V(27, 0, 0), 4, 12)                   -- collar
    box(l, V(6, -1.5, 3.2), V(14, 1.5, 6.5))                   -- sight
    box(l, V(10, -0.5, 6.5), V(12, 0.5, 9))
end
local function mortarBase(l)
    cyl(l, V(0, 0, 0), 15, 3, 18)                              -- baseplate
    cyl(l, V(0, 0, 3), 4.5, 5, 12)                             -- socket
    for k = 0, 3 do                                            -- stiffening ribs on the baseplate
        local a = k * math.pi / 2 + math.pi / 4
        box(l, V(math.cos(a) * 6 - 1, math.sin(a) * 6 - 1, 3), V(math.cos(a) * 13 + 1, math.sin(a) * 13 + 1, 4.5))
    end
    box(l, V(-30, 14, 0), V(-12, 30, 9))                       -- shell crate
    for k = 0, 3 do ocyl(l, V(-27 + k * 4.5, 22, 9), V(-27 + k * 4.5, 22, 20), 1.6, 8) end
    ammoStool(l, -40)
end
item{ id = "mortar", cat = 3, name = "Mortar", desc = "Drone cam, wheel = angle", kind = "gun", gun = "mortar",
    mat = "plain", color = Color(112, 120, 82), partMat = "plain", partColor = Color(86, 112, 60), place = "upright", faceAway = true, grid = true,
    col = function(l) cyl(l, V(0, 0, 0), 15, 8, 10) box(l, V(-48, -9, 0), V(-32, 9, 14)) end,
    vis = mortarBase, part = mortarPart }

-- twin anti-air gun
local function flakPart(l)
    box(l, V(-14, -9, -5), V(10, 9, 5))                        -- receiver
    for sy = -1, 1, 2 do
        ocyl(l, V(10, sy * 5, 1), V(56, sy * 5, 1), 1.3, 10)   -- barrels
        ocyl(l, V(10, sy * 5, 1), V(24, sy * 5, 1), 2.4, 10)   -- jackets
        ocyl(l, V(55, sy * 5, 1), V(62, sy * 5, 1), 2, 10)     -- flash hiders
        box(l, V(-10, sy * 9, -6), V(4, sy * 15, 6))           -- ammo boxes
    end
    box(l, V(4, -22, -12), V(6, -3, 6)) box(l, V(4, 3, -12), V(6, 22, 6))   -- shield
    for k = 0, 7 do                                            -- ring sight
        local a1, a2 = k * math.pi / 4, (k + 1) * math.pi / 4
        beam(l, V(20, math.cos(a1) * 6, 13 + math.sin(a1) * 6), V(20, math.cos(a2) * 6, 13 + math.sin(a2) * 6), 0.3, 0.3)
    end
    box(l, V(19.5, -0.3, 5), V(20.5, 0.3, 7))
    box(l, V(-22, -8, -2), V(-14, -6, 0)) box(l, V(-22, 6, -2), V(-14, 8, 0))   -- handles
end
local function flakBase(l)
    cyl(l, V(0, 0, 0), 18, 4, 18)                              -- pedestal
    cyl(l, V(0, 0, 4), 5, 24, 12)
    cyl(l, V(0, 0, 28), 9, 3, 14)
    box(l, V(-5, -10, 31), V(5, 10, 33))
    ammoStool(l, -46)
end
item{ id = "flak", cat = 3, name = "Flak 2x", desc = "Manned AA, blast hits", kind = "gun", gun = "flak",
    mat = "metal", color = Color(90, 92, 84), place = "upright", faceAway = true, grid = true,
    col = function(l) cyl(l, V(0, 0, 0), 18, 32, 10) box(l, V(-54, -9, 0), V(-38, 9, 14)) end,
    vis = flakBase, part = flakPart }
mountable(ITEMS[#ITEMS], -46)

end
-- ---------------- PROPS ----------------
local function hedgehog(l, beamHalf, thick)
    local up = V(0, 0, 1)
    local s3, s23 = 1 / math.sqrt(3), math.sqrt(2 / 3)
    local zc = beamHalf * s3 + 1
    for k = 0, 2 do
        local a = math.rad(k * 120)
        local e = up * s3 + V(math.cos(a), math.sin(a), 0) * s23
        local p1 = e:cross(up):getNormalized()
        local p2 = e:cross(p1):getNormalized()
        obox(l, V(0, 0, zc), e, p1, p2, beamHalf, thick, thick)
    end
end
item{ id = "hog", cat = 6, name = "Czech Hedgehog", desc = "Anti-tank obstacle", kind = "mesh", mat = "metal", color = C_STEEL,
    place = "upright",
    col = function(l) hedgehog(l, 56, 4) end,
    vis = function(l) hedgehog(l, 56, 4) end }

item{ id = "teeth", cat = 6, name = "Dragon's Teeth", desc = "Concrete AT pyramid", kind = "mesh", mat = "concrete", color = C_CONC,
    place = "upright", grid = true,
    col = function(l) frustum(l, 0, 0, 0, 20, 20, 6, 6, 42) end }

local TRENCH_VAR = {}        -- TRENCH_VAR[shape][cover] = item
do
-- ---------------- trench pieces ----------------
-- One cell = TRENCH_CELL. Channel along X (width TRENCH_WIDTH). Each closed side has a wall:
--   inner vertical face (wood posts) -> flat parapet with sandbags (TRENCH_DEPTH high)
--   -> outer earth slope down to the ground, TRENCH_SPILL beyond the cell (walkable)
-- camo net: sagging rope grid + leaf patches (visual only, bullets and players pass through)
local function camoNet(l, x0, x1, y0, y1, z, sag)
    local q = {}
    local nx, ny = 16, 8
    local function P(u, v) return V(x0 + (x1 - x0) * u, y0 + (y1 - y0) * v, z - sag * (1 - (2 * u - 1) ^ 2) * (1 - (2 * v - 1) ^ 2)) end
    local t = 0.5
    for j = 0, ny do
        for i = 0, nx - 1 do
            local a, b = P(i / nx, j / ny), P((i + 1) / nx, j / ny)
            q[#q + 1] = { a - V(0, t, 0), b - V(0, t, 0), b + V(0, t, 0), a + V(0, t, 0) }
        end
    end
    for i = 0, nx do
        for j = 0, ny - 1 do
            local a, b = P(i / nx, j / ny), P(i / nx, (j + 1) / ny)
            q[#q + 1] = { a - V(t, 0, 0), b - V(t, 0, 0), b + V(t, 0, 0), a + V(t, 0, 0) }
        end
    end
    local seed = 12345
    local function rnd() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end
    for _ = 1, 90 do                                                   -- leaf patches
        local c = P(rnd(), rnd()) - V(0, 0, 0.4)
        local sz, a = 4 + rnd() * 6, rnd() * math.pi
        local d1 = V(math.cos(a), math.sin(a), 0) * sz
        local d2 = V(-math.sin(a), math.cos(a), 0) * (sz * 0.6)
        q[#q + 1] = { c - d1 - d2, c + d1 - d2 + V(0, 0, rnd() * 2 - 1), c + d1 + d2, c - d1 + d2 + V(0, 0, rnd() * 2 - 1) }
    end
    l[#l + 1] = { t = "quads", q = q }
end

-- cover: "open" | "net" (camo net on poles) | "roof" (plank roof, firing slit under it) | "closed" (roof, no slits)
local function trenchShape(kind, vis, cover)
    local l_
    local h   = TRENCH_CELL / 2
    local ch  = TRENCH_WIDTH / 2        -- channel half width
    local tw  = 12                      -- parapet top width
    local H   = TRENCH_DEPTH
    local out = h + TRENCH_SPILL        -- slope foot
    local Z0  = -8                      -- dig a bit into the ground
    local c   = ch + tw
    local RZ  = H + ROOF_Z
    local closed = cover == "closed"
    local WT  = closed and RZ or H      -- closed: the walls go up to the roof (no slit)
    local function M(axis, u, v, z) if axis == "x" then return V(u, v, z) else return V(v, u, z) end end
    local function hx(axis, a0, a1, b0, b1, z0, z1)
        hex(l_, { M(axis, a0, b0, z0), M(axis, a1, b0, z0), M(axis, a1, b1, z0), M(axis, a0, b1, z0),
                  M(axis, a0, b0, z1), M(axis, a1, b0, z1), M(axis, a1, b1, z1), M(axis, a0, b1, z1) })
    end
    local function wall(axis, a0, a1, s)
        local b0, b1 = math.min(s * ch, s * c), math.max(s * ch, s * c)
        hx(axis, a0, a1, b0, b1, Z0, WT)                                    -- core
        local i, o = s * c, s * out                                          -- outer slope
        hex(l_, { M(axis, a0, i, Z0), M(axis, a1, i, Z0), M(axis, a1, o, Z0), M(axis, a0, o, Z0),
                  M(axis, a0, i, H),  M(axis, a1, i, H),  M(axis, a1, o, 0),  M(axis, a0, o, 0) })
        if vis then
            for row = 0, closed and 3 or 0 do                              -- round sandbags on the parapet
                local u = a0 + 11 + ((row % 2 == 1) and 11 or 0)
                while u + 11 <= a1 + 0.1 do
                    bag(l_, M(axis, u, s * (ch + tw / 2), H - 1 + row * 7), axis == "x" and 0 or 90, 22, 12, 8)
                    u = u + 22
                end
            end
            local u = a0 + 12
            while u <= a1 - 8 do                                            -- wooden posts on the inner face
                local p0, p1 = math.min(s * ch, s * (ch - 2)), math.max(s * ch, s * (ch - 2))
                hx(axis, u - 2, u + 2, p0, p1, 0, WT)
                u = u + 46
            end
        end
    end
    local function pillar(x0, x1, y0, y1) box(l_, V(x0, y0, Z0), V(x1, y1, WT)) end
    local function filler(sx, sy)
        hex(l_, { V(sx * out, sy * out, Z0), V(sx * c, sy * out, Z0), V(sx * c, sy * c, Z0), V(sx * out, sy * c, Z0),
                  V(sx * out, sy * out, 0),  V(sx * c, sy * out, 0),  V(sx * c, sy * c, H),  V(sx * out, sy * c, 0) })
    end
    local walls = {}
    return function(l)
        l_ = l
        if kind == "straight" or kind == "exit" then
            wall("x", -h, h, 1) wall("x", -h, h, -1) walls = { py = true, ny = true }
            if kind == "straight" and TRENCH_FIRE_STEP then
                box(l, V(-h, -ch, Z0), V(h, -ch + 22, 18))
            end
            if kind == "exit" then
                hex(l, { V(-h, 4, Z0), V(h, 4, Z0), V(h, ch, Z0), V(-h, ch, Z0),
                         V(-h, 4, 0),  V(h, 4, H),  V(h, ch, H),  V(-h, ch, 0) })
            end
        elseif kind == "corner" then
            wall("x", -h, h, -1) wall("y", -h, h, -1) walls = { ny = true, nx = true }
            pillar(ch, h, ch, h)
            filler(-1, -1)
        elseif kind == "tee" then
            wall("x", -h, h, -1) walls = { ny = true }
            pillar(-h, -ch, ch, h) pillar(ch, h, ch, h)
        elseif kind == "cross" then
            pillar(-h, -ch, -h, -ch) pillar(ch, h, -h, -ch) pillar(-h, -ch, ch, h) pillar(ch, h, ch, h)
        elseif kind == "end" then
            wall("x", -h, h, 1) wall("x", -h, h, -1) wall("y", -h, h, -1) walls = { py = true, ny = true, nx = true }
            filler(-1, -1) filler(-1, 1)
        end
        local d = ch + 6                                                    -- 4 posts stand on walls / pillars
        if cover == "net" and vis then
            for sx = -1, 1, 2 do for sy = -1, 1, 2 do
                box(l, V(sx * d - 1.5, sy * d - 1.5, H), V(sx * d + 1.5, sy * d + 1.5, H + 46))
            end end
            camoNet(l, -h - 4, h + 4, -h - 4, h + 4, H + 46, 16)
        elseif cover == "roof" or closed then
            if not vis then box(l, V(-h, -h, RZ), V(h, h, RZ + 4)) return end
            local x = -h
            while x < h - 1 do                                              -- planks over the whole cell
                box(l, V(x + 0.6, -h, RZ), V(math.min(x + 15, h) - 0.6, h, RZ + 3))
                x = x + 15
            end
            for s = -1, 1, 2 do                                             -- beams
                box(l, V(-h, s * d - 3, RZ - 6), V(h, s * d + 3, RZ))
                box(l, V(s * d - 3, -h, RZ - 7), V(s * d + 3, h, RZ - 6))
            end
            for sx = -1, 1, 2 do for sy = -1, 1, 2 do
                box(l, V(sx * d - 2.5, sy * d - 2.5, H), V(sx * d + 2.5, sy * d + 2.5, RZ - 6))
            end end
            if walls.py then bagRow(l, -h, h, c - 4, RZ + 3, 1) end          -- bags on the roof over the walls
            if walls.ny then bagRow(l, -h, h, -c + 4, RZ + 3, 1) end
            if walls.nx then bagRowY(l, -h + 22, h - 22, -c + 4, RZ + 3, 1) end
        end
    end
end

-- 2x2 trench shelter: sits on the trench grid (4 cells), doors line up with trench channels
-- doors = list of sides with a door ("nx" / "px"), the door is in the cell row y = -CELL/2
local SHELTER_IN = TRENCH_CELL - 36
local function shelterShape(doors, vis, cover)
    return function(l)
        local B, H, tw, Z0 = TRENCH_CELL, TRENCH_DEPTH, 12, -8
        local S, ch = SHELTER_IN, TRENCH_WIDTH / 2
        local c = S + tw
        local out = B + TRENCH_SPILL
        local RZ = H + ROOF_Z
        local closed = cover == "closed"
        local WT = closed and RZ or H
        local DY = -B / 2
        local door = {}
        for _, k in ipairs(doors) do door[k] = true end
        local function M(axis, u, v, z) if axis == "x" then return V(u, v, z) else return V(v, u, z) end end
        local function seg(axis, s, u0, u1, f0, f1, t0, t1)               -- wall core + outer slope piece
            local b0, b1 = math.min(s * S, s * c), math.max(s * S, s * c)
            hex(l, { M(axis, u0, b0, Z0), M(axis, u1, b0, Z0), M(axis, u1, b1, Z0), M(axis, u0, b1, Z0),
                     M(axis, u0, b0, WT), M(axis, u1, b0, WT), M(axis, u1, b1, WT), M(axis, u0, b1, WT) })
            local i, o = s * c, s * out
            t0, t1 = t0 or u0, t1 or u1                                    -- top edge of the slope (door side: stops at the trench wall)
            hex(l, { M(axis, f0, i, Z0), M(axis, f1, i, Z0), M(axis, f1, o, Z0), M(axis, f0, o, Z0),
                     M(axis, t0, i, H),  M(axis, t1, i, H),  M(axis, f1, o, 0),  M(axis, f0, o, 0) })
            if vis then
                for row = 0, closed and 3 or 0 do
                    local u = u0 + 11 + ((row % 2 == 1) and 11 or 0)
                    while u + 11 <= u1 + 0.1 do
                        bag(l, M(axis, u, s * (S + tw / 2), H - 1 + row * 7), axis == "x" and 0 or 90, 22, 12, 8)
                        u = u + 22
                    end
                end
                local u = u0 + 14
                while u <= u1 - 10 do
                    local p0, p1 = math.min(s * S, s * (S - 2)), math.max(s * S, s * (S - 2))
                    hex(l, { M(axis, u - 2, p0, 0), M(axis, u + 2, p0, 0), M(axis, u + 2, p1, 0), M(axis, u - 2, p1, 0),
                             M(axis, u - 2, p0, WT), M(axis, u + 2, p0, WT), M(axis, u + 2, p1, WT), M(axis, u - 2, p1, WT) })
                    u = u + 45
                end
            end
        end
        -- door passage cheek: continues the adjoining trench's wall core from the cell edge (B) to the
        -- shelter wall (c), full wall height -> no hole between the trench and the shelter roof
        local function cheek(axis, s, u0, u1)
            local v0, v1 = math.min(s * c, s * B), math.max(s * c, s * B)
            hex(l, { M(axis, u0, v0, Z0), M(axis, u1, v0, Z0), M(axis, u1, v1, Z0), M(axis, u0, v1, Z0),
                     M(axis, u0, v0, WT), M(axis, u1, v0, WT), M(axis, u1, v1, WT), M(axis, u0, v1, WT) })
            if vis then
                for row = 0, closed and 3 or 0 do
                    bag(l, M(axis, (u0 + u1) / 2, s * (c + B) / 2, H - 1 + row * 7), axis == "x" and 90 or 0, 22, 12, 8)
                end
            end
        end
        local function side(axis, s, hasDoor)
            if not hasDoor then seg(axis, s, -c, c, -out, out) return end
            local e0, e1 = DY - ch, DY + ch                                -- door opening
            local k0, k1 = e0 - tw, e1 + tw                                -- outer faces of the trench walls
            seg(axis, s, -c, e0, -out, k0, -c, k0)
            seg(axis, s, e1, c, k1, out, k1, c)
            cheek(axis, s, k0, e0) cheek(axis, s, e1, k1)
        end
        side("x", 1, false) side("x", -1, false)                          -- +Y / -Y walls
        side("y", 1, door.px) side("y", -1, door.nx)                      -- +X / -X walls (doors)
        if door.px then box(l, V(-S, S - 22, Z0), V(S, S, 18))            -- fire step
        else box(l, V(S - 22, -S, Z0), V(S, S, 18)) end
        if cover == "net" and vis then
            local d = S + 6
            for sx = -1, 1, 2 do for sy = -1, 1, 2 do
                box(l, V(sx * d - 1.5, sy * d - 1.5, H), V(sx * d + 1.5, sy * d + 1.5, H + 50))
            end end
            box(l, V(-1.5, -1.5, 0), V(1.5, 1.5, H + 44))
            camoNet(l, -B - 4, B + 4, -B - 4, B + 4, H + 50, 10)
        elseif cover == "roof" or closed then
            if not vis then box(l, V(-B, -B, RZ), V(B, B, RZ + 4)) return end
            local x = -B
            while x < B - 1 do
                box(l, V(x + 0.6, -B, RZ), V(math.min(x + 16, B) - 0.6, B, RZ + 3))
                x = x + 16
            end
            local d = S + 6
            for _, y in ipairs({ -d, 0, d }) do box(l, V(-B, y - 3, RZ - 6), V(B, y + 3, RZ)) end
            for sx = -1, 1, 2 do
                box(l, V(sx * 78 - 3, -3, 0), V(sx * 78 + 3, 3, RZ - 6))   -- 2 posts in the middle
                for sy = -1, 1, 2 do
                    box(l, V(sx * d - 2.5, sy * d - 2.5, H), V(sx * d + 2.5, sy * d + 2.5, RZ - 6))
                end
            end
            bagRow(l, -B, B, c - 4, RZ + 3, 1) bagRow(l, -B, B, -c + 4, RZ + 3, 1)
        end
    end
end

-- walls = closed sides (px = +X, py = +Y, nx = -X, ny = -Y) -> guns can be mounted on them
local function W(...) local t = {} for _, k in ipairs({ ... }) do t[k] = true end return t end
local COVERS = { { "open", "" }, { "net", "camo net" }, { "roof", "roof + slits" }, { "closed", "closed" } }
for _, t in ipairs({ { "straight", "Trench: straight", "Fire step one side", W("py", "ny") },
                     { "corner", "Trench: corner", "Forward + left", W("ny", "nx") },
                     { "tee", "Trench: T", "Three ways", W("ny") }, { "cross", "Trench: cross", "Four ways", W() },
                     { "end", "Trench: end", "Dead end", W("py", "ny", "nx") },
                     { "exit", "Trench: exit", "Ramp up and out", W("ny"), nocover = true },
                     { "sh1", "Shelter 2x2", "1 door into a trench", W("px", "py", "ny", "nx"), doors = { "nx" } },
                     { "sh2", "Shelter 2x2 pass", "2 doors, trench through", W("py", "ny", "px", "nx"), doors = { "nx", "px" } } }) do
    TRENCH_VAR[t[1]] = {}
    for ci, cv in ipairs(COVERS) do
        if ci == 1 or not t.nocover then
            local big = t.doors ~= nil
            item{ id = "tr_" .. t[1] .. (ci > 1 and ("_" .. cv[1]) or ""), cat = 4, hidden = ci > 1,
                name = t[2] .. (ci > 1 and (", " .. cv[2]) or ""), desc = t[3], kind = "mesh", mat = "dirt", color = C_DIRT,
                place = "trench", size = big and 2 or 1, shape = t[1], cover = cv[1],
                col = big and shelterShape(t.doors, false, cv[1]) or trenchShape(t[1], false, cv[1]),
                vis = big and shelterShape(t.doors, true, cv[1]) or trenchShape(t[1], true, cv[1]),
                walls = cv[1] ~= "closed" and t[4] or nil,
                inner = big and SHELTER_IN or TRENCH_WIDTH / 2, span = big and (SHELTER_IN - 20) or TRENCH_CELL / 2 }
            TRENCH_VAR[t[1]][cv[1]] = ITEMS[#ITEMS]
        end
    end
end
-- cover tools: click a placed trench piece -> it is swapped for the covered version
for ci, cv in ipairs(COVERS) do
    item{ id = "cov_" .. cv[1], cat = 4, kind = "cover", cover = cv[1],
        name = ({ "Cover: remove", "Cover: camo net", "Cover: roof+slits", "Cover: closed" })[ci],
        desc = ({ "Open trench again", "Net on poles", "Planks, firing slit", "Roof, no holes" })[ci] }
end

end
do
-- ---------------- sandbags (round, stackable) ----------------
-- mnt = where guns can mount on a fortification: faces { o = wall centre, d = side the gun stands on, half, span }
local function FW(top, list, P)
    local f = {}
    for _, t in ipairs(list) do f[#f + 1] = { o = V(t[1], t[2], 0), d = V(t[3], t[4], 0), half = t[5], span = t[6] } end
    return { top = top, faces = f, P = P }
end
local function FW2(top, ox, oy, alongX, half, span)        -- both sides of a straight wall
    if alongX then return { ox, oy, 0, 1, half, span }, { ox, oy, 0, -1, half, span } end
    return { ox, oy, 1, 0, half, span }, { ox, oy, -1, 0, half, span }
end
item{ id = "bags", cat = 5, name = "Sandbags: wall", desc = "3 rows, stackable", kind = "mesh", mat = "fabric", color = C_TAN,
    place = "upright", grid = true, stack = stackH(3), mnt = FW(stackH(3), { FW2(0, 0, 0, true, 7, 44) }),
    col = function(l) box(l, V(-44, -7, 0), V(44, 7, stackH(3))) end,
    vis = function(l) bagRow(l, -44, 44, 0, 0, 3) end }

item{ id = "bags_low", cat = 5, name = "Sandbags: low", desc = "1 row, stackable", kind = "mesh", mat = "fabric", color = C_TAN,
    place = "upright", grid = true, stack = stackH(1), mnt = FW(stackH(1), { FW2(0, 0, 0, true, 7, 44) }),
    col = function(l) box(l, V(-44, -7, 0), V(44, 7, stackH(1))) end,
    vis = function(l) bagRow(l, -44, 44, 0, 0, 1) end }

local ARC_R, ARC_DEG = 128, 45
item{ id = "bags_arc", cat = 5, name = "Sandbags: arc", desc = "45 deg, 8 = ring", kind = "mesh", mat = "fabric", color = C_TAN,
    place = "upright", faceAway = true, stack = stackH(3),
    mnt = (function()
        local t = {}
        for k = -1, 1 do
            local r = math.rad(k * ARC_DEG / 3)
            local cx, cy, nx, ny = -ARC_R + ARC_R * math.cos(r), ARC_R * math.sin(r), math.cos(r), math.sin(r)
            t[#t + 1] = { cx, cy, -nx, -ny, 7, 14 } t[#t + 1] = { cx, cy, nx, ny, 7, 14 }
        end
        return FW(stackH(3), t)
    end)(),
    col = function(l)
        local seg = ARC_DEG / 3
        for k = -1, 1 do
            local a = k * seg
            local r = math.rad(a)
            ybox(l, V(-ARC_R + ARC_R * math.cos(r), ARC_R * math.sin(r), stackH(3) / 2), a + 90,
                 ARC_R * math.sin(math.rad(seg / 2)) + 1, 7, stackH(3) / 2)
        end
    end,
    vis = function(l)
        local step = math.deg(BAG_L / ARC_R)
        for row = 0, 2 do
            local a = -ARC_DEG / 2 + step * 0.5 + ((row % 2 == 1) and step * 0.5 or 0)
            while a <= ARC_DEG / 2 - step * 0.5 + 0.01 do
                local r = math.rad(a)
                bag(l, V(-ARC_R + ARC_R * math.cos(r), ARC_R * math.sin(r), row * (BAG_H - 1)), a + 90, BAG_L, BAG_W, BAG_H)
                a = a + step
            end
        end
    end }

item{ id = "bags_corner", cat = 5, name = "Sandbags: corner", desc = "L shape, stackable", kind = "mesh", mat = "fabric", color = C_TAN,
    place = "upright", grid = true, stack = stackH(3),
    mnt = (function()
        local a, b = FW2(0, 26, 0, true, 7, 30)
        local c, d = FW2(0, 0, 40, false, 7, 30)
        return FW(stackH(3), { a, b, c, d })
    end)(),
    col = function(l) box(l, V(-7, -7, 0), V(59, 7, stackH(3))) box(l, V(-7, 7, 0), V(7, 73, stackH(3))) end,
    vis = function(l) bagRow(l, -7, 59, 0, 0, 3) bagRowY(l, 7, 73, 0, 0, 3) end }

item{ id = "nest", cat = 5, name = "MG Nest", desc = "Sandbag half ring", kind = "mesh", mat = "fabric", color = C_TAN,
    place = "upright", faceAway = true, stack = stackH(4),
    mnt = (function()
        local t = {}
        for k = -2, 2 do
            local f = Angle(0, k * 36, 0):getForward()
            t[#t + 1] = { f.x * 52, f.y * 52, -f.x, -f.y, 7, 15 } t[#t + 1] = { f.x * 52, f.y * 52, f.x, f.y, 7, 15 }
        end
        return FW(stackH(4), t)
    end)(),
    col = function(l)
        for k = -2, 2 do
            local a = k * 36
            local f = Angle(0, a, 0):getForward()
            ybox(l, f * 52 + V(0, 0, stackH(4) / 2), a + 90, 17, 7, stackH(4) / 2)
        end
    end,
    vis = function(l)
        for row = 0, 3 do
            for k = -6, 6 do
                local a = k * 15 + ((row % 2 == 1) and 7.5 or 0)
                if math.abs(a) <= 92 then
                    local f = Angle(0, a, 0):getForward()
                    bag(l, f * 52 + V(0, 0, row * (BAG_H - 1)), a + 90, 15, 13, 8)
                end
            end
        end
    end }

local function wireCoil(l, len, r)
    local q = {}
    local turns, seg = math.floor(len / 7), 10
    local thick = 0.35
    local prev
    for i = 0, turns * seg do
        local t = i / (turns * seg)
        local a = i / seg * math.pi * 2
        local p = V(-len / 2 + len * t, math.cos(a) * r, r + math.sin(a) * r)
        if prev then
            local d = (p - prev):getNormalized()
            local side = d:cross(V(0, 0, 1)):getNormalized() * thick
            local upv = d:cross(side):getNormalized() * thick
            q[#q + 1] = { prev - side, p - side, p + side, prev + side }
            q[#q + 1] = { prev - upv, p - upv, p + upv, prev + upv }
        end
        prev = p
    end
    l[#l + 1] = { t = "quads", q = q }
end
item{ id = "wire", cat = 6, name = "Barbed Wire", desc = "Concertina, 128", kind = "mesh", mat = "plain", color = Color(90, 90, 85),
    place = "upright", grid = true,
    col = function(l) box(l, V(-64, -16, 0), V(64, 16, 34)) end,
    vis = function(l)
        wireCoil(l, 128, 16)
        box(l, V(-66, -1, 0), V(-64, 1, 36)) box(l, V(64, -1, 0), V(66, 1, 36))
    end }

-- Jersey barrier: concrete road block
item{ id = "jersey", cat = 6, name = "Jersey Barrier", desc = "Concrete road block", kind = "mesh", mat = "concrete", color = C_CONC,
    place = "upright", grid = true, mnt = FW(32, { FW2(0, 0, 0, false, 12, 56) }),
    col = function(l)
        hex(l, { V(-12, -60, 0), V(12, -60, 0), V(12, 60, 0), V(-12, 60, 0), V(-7.5, -60, 12), V(7.5, -60, 12), V(7.5, 60, 12), V(-7.5, 60, 12) })
        hex(l, { V(-7.5, -60, 12), V(7.5, -60, 12), V(7.5, 60, 12), V(-7.5, 60, 12), V(-4, -60, 32), V(4, -60, 32), V(4, 60, 32), V(-4, 60, 32) })
    end,
    vis = function(l)
        box(l, V(-12, -60, 0), V(12, 60, 3))
        hex(l, { V(-12, -60, 3), V(12, -60, 3), V(12, 60, 3), V(-12, 60, 3), V(-7.5, -60, 12), V(7.5, -60, 12), V(7.5, 60, 12), V(-7.5, 60, 12) })
        hex(l, { V(-7.5, -60, 12), V(7.5, -60, 12), V(7.5, 60, 12), V(-7.5, 60, 12), V(-4, -60, 32), V(4, -60, 32), V(4, 60, 32), V(-4, 60, 32) })
        box(l, V(-12.2, -40, 0), V(12.2, -32, 2.5)) box(l, V(-12.2, 32, 0), V(12.2, 40, 2.5))   -- lifting slots
    end }

do
-- ---------------- watchtower ----------------
-- 128x128 platform at 196, railing 42 high. Stairs = a steep wall of small blocks, every row sticks out
-- a bit (rise 16.3 < step size 18, so you just walk up). Step collision lives in 2 extra hidden
-- custom props (a prop can only have 10 convexes).
local TW_P, TW_T, TW_R = 64, 196, 42
local TW_STEPS, TW_RUN, TW_Y0, TW_Y1 = 12, 9, 16, 60
local function stepX(k) return -TW_P - TW_RUN * (TW_STEPS - k + 1) end     -- front edge of step k
local function towerSteps(k0, k1)
    return function(l)
        for k = k0, k1 do
            box(l, V(stepX(k), TW_Y0, TW_T * (k - 1) / TW_STEPS), V(-TW_P, TW_Y1, TW_T * k / TW_STEPS))
        end
    end
end
local function towerShape(vis)
    return function(l)
        local P, T, R = TW_P, TW_T, TW_R
        local lh = 52
        for sx = -1, 1, 2 do for sy = -1, 1, 2 do                                  -- 4 legs
            box(l, V(sx * lh - 4, sy * lh - 4, 0), V(sx * lh + 4, sy * lh + 4, T - 8))
        end end
        box(l, V(-P, -P, T - 8), V(P, P, T))                                      -- platform
        box(l, V(P - 3, -P, T), V(P, P, T + R))                                   -- railings
        box(l, V(-P, P - 3, T), V(P - 3, P, T + R))
        box(l, V(-P, -P, T), V(P - 3, -P + 3, T + R))
        box(l, V(-P, -P + 3, T), V(-P + 3, TW_Y0 - 4, T + R))                     -- (opening for the stairs)
        if not vis then return end
        -- block stairs: every row = bricks with gaps, sticking out 1.5 past the collision
        local BW = 11
        for k = 1, TW_STEPS do
            local z0, z1 = T * (k - 1) / TW_STEPS, T * k / TW_STEPS
            local x0 = stepX(k)
            local off = (k % 2 == 0) and BW / 2 or 0
            local y = TW_Y0 - off
            while y < TW_Y1 - 0.5 do
                local ya, yb = math.max(y, TW_Y0), math.min(y + BW, TW_Y1)
                if yb - ya > 1 then
                    box(l, V(x0 - 1.5, ya + 0.35, z0 + 0.35), V(x0 + TW_RUN, yb - 0.35, z1 - 0.35))
                end
                y = y + BW
            end
            if x0 + TW_RUN < -P - 0.5 then                                         -- the body of the row behind
                box(l, V(x0 + TW_RUN, TW_Y0 + 0.5, z0), V(-P, TW_Y1 - 0.5, z1))
            end
        end
        -- cross braces between the legs
        for s = -1, 1, 2 do
            beam(l, V(-lh, s * lh, 8), V(lh, s * lh, T - 16), 1.5, 2)
            beam(l, V(lh, s * lh, 8), V(-lh, s * lh, T - 16), 1.5, 2)
            beam(l, V(s * lh, -lh, 8), V(s * lh, lh, T - 16), 1.5, 2)
            beam(l, V(s * lh, lh, 8), V(s * lh, -lh, T - 16), 1.5, 2)
        end
        -- roof on 4 posts
        for sx = -1, 1, 2 do for sy = -1, 1, 2 do
            box(l, V(sx * (P - 4) - 2, sy * (P - 4) - 2, T + R), V(sx * (P - 4) + 2, sy * (P - 4) + 2, T + 104))
        end end
        frustum(l, 0, 0, T + 104, P + 14, P + 14, 6, 6, 34)
    end
end
item{ id = "tower", cat = 5, name = "Watchtower", desc = "Block stairs + rail", kind = "mesh", mat = "wood", color = C_WOOD,
    place = "upright", faceAway = true,
    col = function(l) towerShape(false)(l) towerSteps(1, TW_STEPS)(l) end, vis = towerShape(true),
    mnt = { deck = TW_T, half = TW_P - 22, P = TW_R + 12 } }

end
-- ---------------- pillbox ----------------
local PB_X, PB_Y, PB_H, PB_T = 80, 72, 84, 14
local function pillboxCol(l)
    local X, Y, H, t = PB_X, PB_Y, PB_H, PB_T
    box(l, V(X - t, -Y, 0), V(X, Y, 54))             -- front wall under the firing slit
    box(l, V(X - t, -Y, 68), V(X, Y, H))             -- front wall over the slit (slit 54..68 = eye height)
    box(l, V(-X, -Y, 0), V(X - t, -Y + t, H))        -- sides
    box(l, V(-X, Y - t, 0), V(X - t, Y, H))
    box(l, V(-X, -Y + t, 0), V(-X + t, -26, H))      -- back with a door
    box(l, V(-X, 26, 0), V(-X + t, Y - t, H))
    box(l, V(-X - 6, -Y - 6, H), V(X + 6, Y + 6, H + 12))   -- roof slab
end
item{ id = "bunker", cat = 5, name = "Pillbox", desc = "Concrete, firing slit", kind = "mesh", mat = "concrete", color = C_CONC,
    place = "upright", faceAway = true,
    mnt = FW(54, { { PB_X - PB_T, 0, -1, 0, 0, PB_Y - PB_T - 18 } }, 64),     -- inside, barrel through the slit
    col = pillboxCol,
    vis = function(l)
        pillboxCol(l)
        bagRowY(l, -PB_Y, PB_Y, PB_X - 2, PB_H + 12, 1)                    -- bags on the roof edge
        bagRow(l, -PB_X, PB_X - 12, -PB_Y + 4, PB_H + 12, 1)
        bagRow(l, -PB_X, PB_X - 12, PB_Y - 4, PB_H + 12, 1)
    end }

item{ id = "twall", cat = 5, name = "T-Wall", desc = "Concrete blast wall", kind = "mesh", mat = "concrete", color = C_CONC,
    place = "upright", grid = true, mnt = FW(128, { FW2(0, 0, 0, true, 28, 28) }),
    col = function(l) box(l, V(-32, -28, 0), V(32, 28, 10)) box(l, V(-32, -7, 10), V(32, 7, 128)) end,
    vis = function(l)
        box(l, V(-32, -28, 0), V(32, 28, 10)) box(l, V(-32, -7, 10), V(32, 7, 124))
        frustum(l, 0, 0, 124, 32, 7, 31, 5, 4)
        ocyl(l, V(-20, 0, 128), V(-20, 0, 132), 2, 8) ocyl(l, V(20, 0, 128), V(20, 0, 132), 2, 8)
    end }

item{ id = "logs", cat = 5, name = "Log Barricade", desc = "Logs on X frames", kind = "mesh", mat = "wood", color = C_WOOD,
    place = "upright", grid = true, mnt = FW(40, { FW2(0, 0, 0, true, 18, 58) }),
    col = function(l) box(l, V(-64, -16, 0), V(64, 16, 40)) end,
    vis = function(l)
        for k = 0, 2 do
            local z = 6.5 + k * 12.5
            ocyl(l, V(-66, (k == 1) and 1 or -1, z), V(66, (k == 1) and -1 or 1, z), 6.5, 10)
        end
        for _, x in ipairs({ -52, 52 }) do
            ocyl(l, V(x, -18, 0), V(x, 18, 44), 3.5, 8)
            ocyl(l, V(x, 18, 0), V(x, -18, 44), 3.5, 8)
        end
    end }

item{ id = "crate", cat = 5, name = "Supply Crate", desc = "Wood box, stackable", kind = "mesh", mat = "wood", color = C_WOOD,
    place = "upright", grid = true, stack = 30,
    mnt = (function() local a, b = FW2(0, 0, 0, false, 20, 14) local c, d = FW2(0, 0, 0, true, 16, 18) return FW(30, { a, b, c, d }) end)(),
    col = function(l) box(l, V(-20, -16, 0), V(20, 16, 30)) end,
    vis = function(l)
        box(l, V(-19, -15, 0.5), V(19, 15, 29.5))
        for sx = -1, 1, 2 do for sy = -1, 1, 2 do
            box(l, V(sx * 20 - 1.5, sy * 16 - 1.5, 0), V(sx * 20 + 1.5, sy * 16 + 1.5, 30))
        end end
        for _, z in ipairs({ 0, 27 }) do
            box(l, V(-20, -16, z), V(20, -14.5, z + 3)) box(l, V(-20, 14.5, z), V(20, 16, z + 3))
            box(l, V(-20, -16, z), V(-18.5, 16, z + 3)) box(l, V(18.5, -16, z), V(20, 16, z + 3))
        end
        beam(l, V(-18, -15.6, 3), V(18, -15.6, 27), 1.5, 0.6)
        beam(l, V(-18, 15.6, 3), V(18, 15.6, 27), 1.5, 0.6)
    end }

-- Hesco barrier: 2 wire-mesh cells filled with earth, stackable
local HESCO_H = 52
item{ id = "hesco", cat = 5, name = "Hesco Barrier", desc = "2 earth cells, stackable", kind = "mesh", mat = "fabric", color = Color(175, 160, 120),
    place = "upright", grid = true, stack = HESCO_H, mnt = FW(HESCO_H, { FW2(0, 0, 0, false, 24, 46) }),
    col = function(l) box(l, V(-24, -48, 0), V(24, 48, HESCO_H)) end,
    vis = function(l)
        box(l, V(-23.5, -47.5, 0), V(23.5, 47.5, HESCO_H - 1))
        frustum(l, 0, -24, HESCO_H - 1, 22, 22, 15, 15, 3) frustum(l, 0, 24, HESCO_H - 1, 22, 22, 15, 15, 3)
        for _, y in ipairs({ -48, 0, 48 }) do for sx = -1, 1, 2 do
            box(l, V(sx * 24 - 0.8, y - 0.8, 0), V(sx * 24 + 0.8, y + 0.8, HESCO_H))
        end end
        for z = 0, HESCO_H, HESCO_H / 4 do
            for sx = -1, 1, 2 do box(l, V(sx * 24 - 0.5, -48, z - 0.4), V(sx * 24 + 0.5, 48, z + 0.4)) end
            for sy = -1, 1, 2 do box(l, V(-24, sy * 48 - 0.5, z - 0.4), V(24, sy * 48 + 0.5, z + 0.4)) end
        end
    end }

end
local ITEM_BY_ID = {}
for _, it in ipairs(ITEMS) do ITEM_BY_ID[it.id] = it end

-- mesh definitions: one per mesh/gun item + one per gun part (hologram)
local MDEFS = {}
local function mdef(key, fn, mat, it)
    MDEFS[#MDEFS + 1] = { key = key, fn = fn, mat = mat, it = it }
    MDEFS[#MDEFS].idx = #MDEFS
    return #MDEFS
end
for _, it in ipairs(ITEMS) do
    if it.kind == "mesh" or it.kind == "gun" then it.mdef = mdef(it.id, it.vis or it.col, it.mat, it) end
    if it.kind == "gun" then
        it.gdef = mdef(it.id .. ":gun", it.part, it.partMat or "metal", nil)
        if it.mountVis then
            it.mountDefs = {}
            for k, fn in ipairs(it.mountVis) do it.mountDefs[k] = mdef(it.id .. ":m" .. k, fn, it.mat, it) end
        end
    end
end

return {
    CAT_NAMES = CAT_NAMES,
    ITEMS = ITEMS,
    ITEM_BY_ID = ITEM_BY_ID,
    MDEFS = MDEFS,
    TRENCH_VAR = TRENCH_VAR,
    GUN_STATS = GUN_STATS,
    GUN_GEO = GUN_GEO,
    MOUNT_LEVELS = MOUNT_LEVELS,
    MOUNT_TRENCH = MOUNT_TRENCH,
    MOUNT_FRONT = MOUNT_FRONT,
    C_GUN = C_GUN,
    gunPivot = gunPivot,
    gunSeatPos = gunSeatPos,
    mountLevelFor = mountLevelFor,
}
