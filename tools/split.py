#!/usr/bin/env python3
"""Build the modular Infantry Tool from tools/upstream_infantry_tool.txt.

The generated files in src/ are the source of truth and are edited by hand;
this script only records how the original 3614-line chip was cut up. Re-running
it overwrites src/.
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "upstream_infantry_tool.txt")
lines = open(SRC, encoding="utf-8").read().split("\n")


def sl(a, b):
    """1-based inclusive slice."""
    return "\n".join(lines[a - 1:b])


def dedent(text, n=4):
    pad = " " * n
    return "\n".join(ln[n:] if ln.startswith(pad) else ln for ln in text.split("\n"))


def write(path, text):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    open(full, "w", encoding="utf-8").write(text.rstrip("\n") + "\n")
    print("wrote %-28s %4d lines" % (path, text.count("\n") + 1))


# =================================================================== config
cfg = sl(40, 128) + "\n" + sl(131, 131)
names = []
for m in re.finditer(r"^local\s+([A-Za-z_][\w, ]*?)\s*=", cfg, re.M):
    for n in m.group(1).split(","):
        n = n.strip()
        if n:
            names.append(n)
cfg_return = ",\n".join("    %s = %s" % (n, n) for n in names)
write("src/config.lua", """-- Infantry Tool :: settings
-- Every tunable of the tool lives here: ranges, timings, limits, materials.
-- Nothing in this file touches the engine, so it can be read as documentation.

%s

return {
%s,
}
""" % (cfg, cfg_return))

# =================================================================== geom
geom = sl(142, 282)
geom = geom.replace("local BAG_NU, BAG_NV = 10, 5",
                    "local RES = { nu = 10, nv = 5 }   -- sandbag tessellation, see setBagRes()")
geom = geom.replace("local function bag(list, c, yaw, l, w, h)",
                    "local function bag(list, c, yaw, l, w, h)\n    local BAG_NU, BAG_NV = RES.nu, RES.nv")
geom = geom.replace("local function setBagRes",
                    "local function setBagRes")
geom_exports = ["bag", "bagRow", "bagRowY", "beam", "box", "cyl", "frustum", "hex",
                "obox", "ocyl", "ocylBasis", "primPoints", "stackH", "ybox",
                "BAG_L", "BAG_W", "BAG_H"]
write("src/geom.lua", """-- Infantry Tool :: primitive geometry
-- unit solids (box / open box / beam / frustum / cylinder) plus the sandbag
-- and stack emitters. Every mesh in the chip is built from these, and so is
-- every convex hull on the server (primPoints), which keeps the collision
-- shape and the visual mesh identical.
--
-- setBagRes() lets the client rebuild an over-budget mesh with fewer sandbag
-- segments instead of dropping it.

local V = Vector

%s

local function setBagRes(nu, nv)
    RES.nu, RES.nv = nu or 10, nv or 5
end

return {
%s,
    setBagRes = setBagRes,
}
""" % (geom, ",\n".join("    %s = %s" % (n, n) for n in geom_exports)))

# =================================================================== shared
shared = sl(133, 140) + "\n" + sl(1229, 1288)
shared_funcs = re.findall(r"^local function (\w+)", shared, re.M)
write("src/shared.lua", """-- Infantry Tool :: shared helpers
-- Small functions both realms need: aim tracing, surface classification,
-- grenade pivot maths, shell ballistics and the tripwire wire check.

local C = require("src/config.lua")

local V = Vector
local WEAPON_CLASS, LASER_RANGE = C.WEAPON_CLASS, C.LASER_RANGE
local clamp = C.clamp

%s

return {
%s,
}
""" % (shared, ",\n".join("    %s = %s" % (n, n) for n in sorted(shared_funcs))))

# =================================================================== items
items = sl(286, 1227)
items_funcs = re.findall(r"^local function (\w+)", items, re.M)
write("src/items.lua", """-- Infantry Tool :: item catalogue
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

%s

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
    gunPivot = gunPivot,
    gunSeatPos = gunSeatPos,
    mountLevelFor = mountLevelFor,
}
""" % items)

# =================================================================== server
core_srv = dedent("\n\n".join([
    sl(1292, 1414),
    sl(1458, 1530),
    sl(1567, 1785),
])) + "\n\ntimer.simple(1, function() sendState() end)\n"
core_srv = core_srv.replace("""local O = owner()
local objs = {}          -- ent -> {it, eidx, armAt, ...}
local list = {}          -- array of ents (order)
local pendingTrip = nil  -- {prop, la, n, born}
local lastPlace = 0
local guns = {}          -- base ent -> gun state
local seatBase = {}      -- seat ent -> base ent
local extraOf = {}       -- hidden extra collision prop -> main object
local fireBullets = game.bulletDamage
""", """local O = owner()
local objs = {}          -- ent -> {it, eidx, armAt, ...}
local guns = {}          -- base ent -> gun state
local seatBase = {}      -- seat ent -> base ent
local extraOf = {}       -- hidden extra collision prop -> main object
local fireBullets = game.bulletDamage

-- One table shared by every server module. Modules never import each other's
-- functions, they call S.foo(...) at run time, so the load order of the
-- modules does not matter (placeGun lives in guns.lua, doPlace calls it).
local S = {
    O = O,
    objs = objs, guns = guns, seatBase = seatBase, extraOf = extraOf,
    shells = {},          -- in-flight mortar / artillery shells
    booms = {},           -- recent mortar impacts (damage numbers)
    fused = {},           -- objects with a running fuse (walked at 10 Hz)
    pendingTrip = nil,    -- {prop, la, n, born}
    lastPlace = 0,
    timedCharges = {},    -- timed charges: filled here, beeped by sensors
}
""")
core_srv = core_srv.replace("local shells, booms = {}, {}", "local shells, booms = S.shells, S.booms")
# fuses are tracked in their own small list so the scan never walks every object
core_srv = re.sub(
    r"(?m)^([ \t]*)o\.fuseAt = timer\.curtime\(\) \+ delay[ \t]*$",
    lambda m: m.group(0) + "\n" + m.group(1) + "S.fused[#S.fused + 1] = e",
    core_srv)
core_srv = re.sub(
    r"(?m)^([ \t]*)o\.fuseAt, o\.nextBeep, o\.armAt = now \+ TIMED_FUSE, now, nil[ \t]*$",
    lambda m: m.group(0) + "\n" + m.group(1) + "S.fused[#S.fused + 1] = p",
    core_srv)
core_srv = core_srv.replace("    list[#list + 1] = p\n", "")
core_srv = core_srv.replace("    destroyGun(e)", "    if S.destroyGun then S.destroyGun(e) end")
core_srv = core_srv.replace("placeGun(it, pos, ang, lvl)", "S.placeGun(it, pos, ang, lvl)")
core_srv = core_srv.replace("if S.destroyGun then S.destroyGun(e) end", "if S.destroyGun then S.destroyGun(e) end")
core_srv = re.sub(r"\bpendingTrip\b", "S.pendingTrip", core_srv)
core_srv = re.sub(r"\blastPlace\b", "S.lastPlace", core_srv)
# cover items are a client-side conversion of an existing trench piece, never a spawn
core_srv = core_srv.replace("    S.lastPlace = now\n",
    "    if it.kind == \"cover\" or not (it.col or it.kind == \"gun\") then\n"
    "        sendState(\"This item can't be placed\") return\n"
    "    end\n"
    "    S.lastPlace = now\n")
# the S table literal must keep plain keys
core_srv = core_srv.replace("    S.pendingTrip = nil,    -- {prop, la, n, born}", "    pendingTrip = nil,    -- {prop, la, n, born}")
core_srv = core_srv.replace("    S.lastPlace = 0,", "    lastPlace = 0,")
# armed objects register themselves with the sensor scheduler once their delay is up
core_srv = core_srv.replace(
    "        snd(p, \"physics/concrete/concrete_impact_soft\" .. math.random(1, 3) .. \".wav\", 70, 100, 0.7)\n    end\n    sendState()\nend",
    "        snd(p, \"physics/concrete/concrete_impact_soft\" .. math.random(1, 3) .. \".wav\", 70, 100, 0.7)\n"
    "    end\n"
    "    if o.armAt and S.armLater then S.armLater(p, o.armAt - timer.curtime()) end\n"
    "    sendState()\nend")
core_srv = core_srv.replace(
    "    o.armAt = timer.curtime() + 1.5\n",
    "    o.armAt = timer.curtime() + 1.5\n"
    "    if S.armLater then S.armLater(p, 1.5) end\n")

guns_srv = dedent("\n\n".join([sl(1415, 1457), sl(1531, 1566), sl(1960, 2167)]))
sensors_srv = dedent("\n\n".join([sl(1786, 1959), sl(2168, 2219)]))
# traps join the armed list the moment their fuse delay runs out
sensors_srv = sensors_srv.replace(
    "        elseif o.armAt and now >= o.armAt then",
    "        elseif o.armAt and now >= o.armAt then\n            arm(e)")

# ---- rebuild it_scan: fuses in their own list, sensors through a rolling
# window, the full object sweep only on every tenth tick
_a = sensors_srv.index("            local lg = o.it.logic")
_b = sensors_srv.index("            end\n        end\n    end\nend)", _a) + len("            end")
check_body = sensors_srv[_a:_b]

_scan_start = sensors_srv.index('timer.create("it_scan", 0.1, 0, function()')
_scan_end = sensors_srv.index("\nend)", _scan_start) + len("\nend)")
old_scan = sensors_srv[_scan_start:_scan_end]
old_preamble = old_scan[:old_scan.index("    for e, o in pairs(objs) do")]

new_scan = (old_preamble.replace("    radarTick = radarTick + 1",
                                 "    radarTick = radarTick + 1")
            + """    -- running fuses: a short dedicated list, exact timing
    local fu = S.fused
    for i = #fu, 1, -1 do
        local e = fu[i]
        local o = objs[e]
        if not o or not o.fuseAt or not isValid(e) then
            table.remove(fu, i)
        elseif now >= o.fuseAt then
            table.remove(fu, i)
            detonate(e)
        elseif o.it.logic == "timed" and now >= (o.nextBeep or 0) then   -- beeps faster at the end
            o.nextBeep = now + clamp((o.fuseAt - now) / 8, 0.1, 1)
            snd(e, "buttons/blip1.wav", 80, 130, 1)
        end
    end

    -- armed sensors: rolling window, at most SENSOR_BUDGET checks per tick
    local total = #sensors
    for _ = 1, math.min(total, SENSOR_BUDGET) do
        if cursor > total then cursor = 1 end
        local e = sensors[cursor]
        cursor = cursor + 1
        local o = objs[e]
        if o and o.armed and isValid(e) and not o.fuseAt and now - (o.checked or 0) >= SENSOR_REFRESH then
            o.checked = now
""" + check_body + """
        end
    end

    -- slow tick: drop dead entries, sweep the registry
    if radarTick % 10 == 0 then
        if total > 0 then
            local w = 1
            for i = 1, #sensors do
                local e = sensors[i]
                local o = objs[e]
                if o and o.armed and isValid(e) then sensors[w] = e w = w + 1 end
            end
            for i = w, #sensors do sensors[i] = nil end
            if cursor > #sensors then cursor = 1 end
        end
        for e in pairs(objs) do if not isValid(e) then unregister(e) end end
    end
end)""")

sensors_srv = sensors_srv[:_scan_start] + new_scan + sensors_srv[_scan_end:]

# the rolling window needs its knobs
# the radar packet walks the armed list, not every object
sensors_srv = sensors_srv.replace(
    "    for e, o in pairs(objs) do\n        if isValid(e) and o.armAt and now >= o.armAt then",
    "    for _, e in ipairs(sensors) do\n        local o = objs[e]\n        if isValid(e) and o.armAt and now >= o.armAt then")
sensors_srv = sensors_srv.replace(
    "local sensors, cursor = {}, 1\nS.sensors = sensors",
    "local SENSOR_REFRESH = 0.12   -- a sensor is checked at most ~8 times a second\n"
    "local SENSOR_BUDGET = 16      -- hard cap of sensor checks per tick\n\n"
    "local sensors, cursor = {}, 1\nS.sensors = sensors")

write("src/server/core.lua", """--@server
-- Infantry Tool :: server core
-- State, object registry, placement, explosions and the command channel.
--
-- The server keeps ONE table (S) that every other server module reads and
-- writes, so the modules never import each other's functions: they call
-- S.foo(...) at run time. That removes the load-order dependency and makes
-- the split safe (placeGun lives in guns.lua, but doPlace can still call it).

local C = require("src/config.lua")
local SH = require("src/shared.lua")
local IT = require("src/items.lua")
local G = require("src/geom.lua")

local V = Vector
local HM, ARM_TIME = C.HM, C.ARM_TIME
local LASER_RANGE, MAX_OBJECTS = C.LASER_RANGE, C.MAX_OBJECTS
local PLACE_COOLDOWN, PLACE_RANGE = C.PLACE_COOLDOWN, C.PLACE_RANGE
local TIMED_FUSE, TRENCH_CELL = C.TIMED_FUSE, C.TRENCH_CELL
local USE_WIRE_EXPLOSIVE = C.USE_WIRE_EXPLOSIVE
local aimTrace, holdsTool = SH.aimTrace, SH.holdsTool
local nadeFix, nadeTransform = SH.nadeFix, SH.nadeTransform
local upFrame, wireOk = SH.upFrame, SH.wireOk
local ITEMS, MOUNT_LEVELS = IT.ITEMS, IT.MOUNT_LEVELS
local primPoints = G.primPoints

%s

-- everything the other server modules need
S.fireBullets = fireBullets
S.BOOM = BOOM
S.countObjs = countObjs
S.sendState = sendState
S.sendReg = sendReg
S.sendUnreg = sendUnreg
S.snd = snd
S.explodeAt = explodeAt
S.spawnShell = spawnShell
S.shellTick = shellTick
S.unregister = unregister
S.removeObj = removeObj
S.detonate = detonate
S.fuse = fuse
S.placeMesh = placeMesh
S.spawnExtras = spawnExtras
S.trenchCells = trenchCells
S.trenchOverlaps = trenchOverlaps
S.doPlace = doPlace
S.stretchWire = stretchWire
S.removeAimed = removeAimed
S.clearAll = clearAll

return S
""" % core_srv)

write("src/server/guns.lua", """--@server
-- Infantry Tool :: server guns
-- Seats, mounting, aiming, firing, heat/reload and the mortar camera link.
-- Everything is reached through the shared S table (see core.lua).

local C = require("src/config.lua")
local SH = require("src/shared.lua")
local IT = require("src/items.lua")
local S = require("src/server/core.lua")

local V, Angle, Color = Vector, Angle, Color
local GUN_STATS, HM = C.GUN_STATS, C.HM
local MORTAR_MIN, MORTAR_MAX, MORTAR_CAM_H = C.MORTAR_MIN, C.MORTAR_MAX, C.MORTAR_CAM_H
local MORTAR_MARKERS = C.MORTAR_MARKERS
local SEAT_MODEL, SEAT_HIDDEN = C.SEAT_MODEL, C.SEAT_HIDDEN
local clamp, mortarSolve, upFrame = SH.clamp, SH.mortarSolve, SH.upFrame
local GUN_GEO, MOUNT_LEVELS = IT.GUN_GEO, IT.MOUNT_LEVELS
local gunPivot, gunSeatPos = IT.gunPivot, IT.gunSeatPos

local O = S.O
local objs, guns, seatBase = S.objs, S.guns, S.seatBase

local countObjs, sendState, sendReg, sendUnreg = S.countObjs, S.sendState, S.sendReg, S.sendUnreg
local snd, explodeAt, spawnShell, shellTick = S.snd, S.explodeAt, S.spawnShell, S.shellTick
local unregister, removeObj, detonate, fuse = S.unregister, S.removeObj, S.detonate, S.fuse
local placeMesh, spawnExtras, trenchCells, trenchOverlaps = S.placeMesh, S.spawnExtras, S.trenchCells, S.trenchOverlaps
local doPlace, stretchWire, removeAimed, clearAll = S.doPlace, S.stretchWire, S.removeAimed, S.clearAll
local fireBullets, BOOM = S.fireBullets, S.BOOM

%s

S.sendMount = sendMount
S.setOperator = setOperator
S.destroyGun = destroyGun
S.gunSeat = gunSeat
S.placeGun = placeGun

return true
""" % guns_srv)

write("src/server/sensors.lua", """--@server
-- Infantry Tool :: sensors and world hooks
-- Mines, alarms, radars, tripwires: everything that watches the world.
--
-- The original scanned every placed object ten times a second. This keeps the
-- reaction time but bounds the cost: armed objects live in their own rolling
-- list (SENSOR_BUDGET checks per tick), timed charges beep from their own
-- list, and object validity is swept once a second instead of every tick.

local C = require("src/config.lua")
local SH = require("src/shared.lua")
local IT = require("src/items.lua")
local S = require("src/server/core.lua")

local V = Vector
local ALARM_RANGE, RADAR_RANGE = C.ALARM_RANGE, C.RADAR_RANGE
local OWNER_SAFE, SHOOTABLE, HIDE_BUGBAIT = C.OWNER_SAFE, C.SHOOTABLE, C.HIDE_BUGBAIT
local clamp, holdsTool = SH.clamp, SH.holdsTool

local O, objs, guns, seatBase, extraOf = S.O, S.objs, S.guns, S.seatBase, S.extraOf
local booms = S.booms
local countObjs, sendState, sendReg, sendUnreg = S.countObjs, S.sendState, S.sendReg, S.sendUnreg
local snd, explodeAt, spawnShell, shellTick = S.snd, S.explodeAt, S.spawnShell, S.shellTick
local unregister, removeObj, detonate, fuse = S.unregister, S.removeObj, S.detonate, S.fuse
local placeMesh, spawnExtras, trenchCells, trenchOverlaps = S.placeMesh, S.spawnExtras, S.trenchCells, S.trenchOverlaps
local doPlace, stretchWire, removeAimed, clearAll = S.doPlace, S.stretchWire, S.removeAimed, S.clearAll
local fireBullets, BOOM = S.fireBullets, S.BOOM

local SENSOR_REFRESH = 0.1
local SENSOR_BUDGET = 24
local EMIT_POINTS = 24

-- every logic that needs a proximity check
local SENSOR_LOGIC = {
    at = true, ap = true, bounce = true, ied = true, laser = true,
    alarm = true, clay = true, trip = true, decoy = true, radar = true,
}

local sensors, cursor = {}, 1
S.sensors = sensors
S.isSensor = function(logic) return SENSOR_LOGIC[logic] == true end

local function arm(e)
    local o = objs[e]
    if o and isValid(e) and not o.armed then
        o.armed = true
        sensors[#sensors + 1] = e
    end
end

local function armLater(e, delay)
    timer.simple(delay > 0 and delay or 0, function() arm(e) end)
end
S.armLater = armLater

%s

return true
""" % sensors_srv)
# =================================================================== client
client_state = ["selected", "menuOpen", "menuTab", "rot", "gridOn", "gridIdx",
                "trenchOrigin", "trenchYaw", "trenchRot", "pendingProp", "pendingStart",
                "objCount", "c4Count", "msgText", "msgUntil", "keyPrev", "waitRelease",
                "lastPlaceCl", "selectorUntil", "plan", "camIdx", "camCount"]


def to_fields(text):
    for n in client_state:
        text = re.sub(r"\b%s\b" % n, "B." + n, text)
    return re.sub(r"\bB\.B\.", "B.", text)


def drop_tail_hook(text, marker, new_name, reg=None):
    """Replace hook.add("think", ...) with a plain function + C.think entry."""
    body = text.rstrip()
    assert body.endswith("end)"), body[-80:]
    body = body[:-4] + "end"
    return body.replace('hook.add("think", "%s", function()' % marker,
                        "local function %s()" % new_name) + \
        ("\nC.think[#C.think + 1] = %s" % reg if reg else "")


# ---------------- client core -------------------------------------------------
regof_body = "\n".join(lines[2378:2388])          # inside regOf(), 2379..2388
write("src/client/core.lua", """--@client
-- Infantry Tool :: client core
-- Identity, fonts, the object registry and the single think dispatcher.
--
-- Every subsystem used to register its own "think" hook, so Starfall paid for
-- a separate hook dispatch, a separate holdsTool() weapon lookup and a separate
-- table walk per subsystem per frame. Now there is one hook, one holdsTool()
-- lookup, and subsystems push a plain function into C.think.

local SH = require("src/shared.lua")

%s

%s

local fTitle = render.createFont("Roboto", 30, 900, true)
local fMed   = render.createFont("Roboto", 21, 800, true)
local fSmall = render.createFont("Roboto", 16, 600, true)
local fCard  = render.createFont("Roboto", 18, 800, true)
local fTiny  = render.createFont("Roboto", 14, 600, true)

local C = {
    me = me,
    O = O,
    isOwner = isOwner,
    reg = reg,                   -- entIndex -> {d = mesh def, it = item, applied}
    alias = alias,               -- hidden extra collision prop -> main object index
    think = {},                  -- frame callbacks, run in registration order
    holding = false,             -- holdsTool(me), refreshed once per frame
    camViewEnt = nil,            -- owner: looking through a periscope camera
    fTitle = fTitle, fMed = fMed, fSmall = fSmall, fCard = fCard, fTiny = fTiny,
}

local holdsTool = SH.holdsTool

-- your object behind an entity (extra collision props map to their main object)
function C.regOf(e)
%s
end

hook.add("think", "it_frame", function()
    C.holding = holdsTool(me)          -- one weapon lookup per frame for everyone
    local list = C.think
    for i = 1, #list do list[i]() end
end)

return C
""" % (sl(2225, 2227), sl(2364, 2365), regof_body))

# ---------------- meshes ------------------------------------------------------
mesh_a = sl(2229, 2361)                                  # materials + builder
mesh_b = drop_tail_hook("\n".join(lines[2391:2430]),      # 2392..2430
                        "it_meshes", "meshesThink", "meshesThink")
lights = drop_tail_hook(sl(2433, 2460), "it_lights", "lightsThink", "lightsThink")
receivers = """
-- the server tells clients which mesh definition belongs to an entity
-- def 255 = alias: a hidden extra collision prop that belongs to object "main"
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
"""
mesh_all = mesh_a + "\n\n" + receivers + "\n\n" + mesh_b + "\n\n" + lights
mesh_all = re.sub(r"(?<![\w.])reg\b", "C.reg", mesh_all)
mesh_all = re.sub(r"(?<![\w.])alias\b", "C.alias", mesh_all)
mesh_all = mesh_all.replace("    BAG_NU, BAG_NV = q[1], q[2]", "        G.setBagRes(q[1], q[2])")
mesh_all = mesh_all.replace("    BAG_NU, BAG_NV = 10, 5", "    G.setBagRes(10, 5)")
# the original checks the pcall status, not the resume status -> coroutine errors were silent
mesh_all = mesh_all.replace("""            local ok, err = pcall(coroutine.resume, builder)
            if not ok then print("[Infantry Tool] mesh builder error: " .. tostring(err)) break end""",
"""            local ok, err = coroutine.resume(builder)
            if not ok then print("[Infantry Tool] mesh builder error: " .. tostring(err)) break end""")
write("src/client/meshes.lua", """--@client
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

%s

return {
    meshes = meshes,
    bounds = bounds,
    getMat = getMat,
}
""" % mesh_all)

# ---------------- guns --------------------------------------------------------
guns_cl = sl(2468, 2847)
guns_cl = guns_cl.replace("local camViewEnt = nil          -- owner: looking through a periscope camera\n", "")
guns_cl = re.sub(r"\bcamViewEnt\b", "C.camViewEnt", guns_cl)
gs = guns_cl.split("\n")
start = None
for i, ln in enumerate(gs):
    if ln.startswith('hook.add("think", "it_gunner"'):
        gs[i] = "local function gunnerThink()"
        assert gs[i + 8].strip() == "end)", gs[i + 8]
        gs[i + 8] = "end\nC.think[#C.think + 1] = gunnerThink"
    if ln.startswith('hook.add("think", "it_mortar"'):
        gs[i] = "local function mortarThink()"
        assert gs[i + 54].strip() == "end)", gs[i + 54]
        gs[i + 54] = "end\nC.think[#C.think + 1] = mortarThink"
guns_cl = "\n".join(gs)
write("src/client/guns.lua", """--@client
-- Infantry Tool :: client guns
-- Gunner HUD, scope overlay, heat/reload readout, and the mortar drone camera
-- (top-down predictive view). Runs on every client, owner or not.

local C = require("src/client/core.lua")
local CC = require("src/config.lua")
local IT = require("src/items.lua")

local V, Angle, Color = Vector, Angle, Color
local GUN_STATS, GUN_GEO = IT.GUN_STATS, IT.GUN_GEO
local ITEMS = IT.ITEMS
local MORTAR_MIN, MORTAR_MAX, MORTAR_CAM_H = CC.MORTAR_MIN, CC.MORTAR_MAX, CC.MORTAR_CAM_H
local MORTAR_MARKERS, HM = CC.MORTAR_MARKERS, CC.HM

%s

return {
    isGunning = function() return gunner ~= nil end,
    bracket = bracket,
    tri2 = tri2,
}
""" % guns_cl)

# ---------------- build (owner only) ------------------------------------------
build_body = sl(2851, 3392)
build_body = build_body.replace(sl(2851, 2863) + "\n", "")
build_body = build_body.replace("local plan = nil          -- current placement {ok, pos, ang, normal, reason, stack}\n", "")
build_body = build_body.replace("local camIdx, camCount = 0, 0\n", "")
build_body = to_fields(build_body)
build_body = re.sub(r"\bcamViewEnt\b", "C.camViewEnt", build_body)
build_body = re.sub(r"(?<![\w.])regOf\b(?!\s*=)", "C.regOf", build_body)
build_body = re.sub(r"(?<![\w.])reg\b", "C.reg", build_body)
build_body = re.sub(r"(?<![\w.])holdsTool\(me\)", "C.holding", build_body)
write("src/client/build.lua", """--@client
-- Infantry Tool :: build mode (owner only)
-- Menu state, ghosts, placement planning, input and the trench grid.
-- This file only runs on the chip owner's client.

local C = require("src/client/core.lua")
local CC = require("src/config.lua")
local SH = require("src/shared.lua")
local IT = require("src/items.lua")

local V, Angle, Color = Vector, Angle, Color
local PLACE_RANGE, PLACE_COOLDOWN, MAX_OBJECTS = CC.PLACE_RANGE, CC.PLACE_COOLDOWN, CC.MAX_OBJECTS
local PROP_GRIDS, ROT_STEP, ROT_FINE = CC.PROP_GRIDS, CC.ROT_STEP, CC.ROT_FINE
local TRENCH_CELL, KEY_MENU, KEY_MENU_BIND = CC.TRENCH_CELL, CC.KEY_MENU, CC.KEY_MENU_BIND
local KEY_ROTATE, KEY_GRID, KEY_DETONATE, KEY_CAM = CC.KEY_ROTATE, CC.KEY_GRID, CC.KEY_DETONATE, CC.KEY_CAM
local BLOCK_BUGBAIT, SELECTOR_WINDOW, HM = CC.BLOCK_BUGBAIT, CC.SELECTOR_WINDOW, CC.HM
local clamp, upFrame, surfaceAngle, aimTrace = SH.clamp, SH.upFrame, SH.surfaceAngle, SH.aimTrace
local badSurface, nadeFix, nadeTransform, wireOk = SH.badSurface, SH.nadeFix, SH.nadeTransform, SH.wireOk
local ITEMS, ITEM_BY_ID, TRENCH_VAR = IT.ITEMS, IT.ITEM_BY_ID, IT.TRENCH_VAR
local MOUNT_LEVELS, mountLevelFor, gunPivot = IT.MOUNT_LEVELS, IT.mountLevelFor, IT.gunPivot

local me = C.me

-- Owner-only UI state lives in one table so hud.lua can read it without a
-- dozen getters; every write still happens in this file.
local B = {
    selected = ITEM_BY_ID.at,
    menuOpen = false, menuTab = 1,
    rot = 0,
    gridOn = true, gridIdx = 1,
    trenchOrigin = nil, trenchYaw = 0, trenchRot = 0,
    pendingProp = nil, pendingStart = nil,
    objCount = 0, c4Count = 0,
    msgText = "", msgUntil = 0,
    keyPrev = {},
    waitRelease = false, lastPlaceCl = 0, selectorUntil = 0,
    plan = nil,                 -- current placement {ok, pos, ang, normal, reason, stack}
    camIdx = 0, camCount = 0,
}

%s

B.setMenu = setMenu
B.sendSimple = sendSimple
B.sendPlace = sendPlace

return B
""" % build_body)

# ---------------- hud (owner only) --------------------------------------------
hud_body = sl(3393, 3614)
hud_body = to_fields(hud_body)
hud_body = re.sub(r"(?<![\w.])reg\b", "C.reg", hud_body)
hud_body = hud_body.replace("if gunner then return end", "if G.isGunning() then return end")
hud_body = hud_body.replace("holdsTool(me)", "C.holding")
hud_body = hud_body.replace('"STACK on top    B.rot "', '"STACK on top    rot "')
hud_body = hud_body.replace('"  Shift+G size  R +45  B.rot "', '"  Shift+G size  R +45  rot "')
write("src/client/hud.lua", """--@client
-- Infantry Tool :: HUD and menu (owner only)
-- The spawn menu, the tool panel, rally flags, radar markers and the
-- viewmodel hider. Reads the owner state from build.lua, never writes it.

local C = require("src/client/core.lua")
local CC = require("src/config.lua")
local IT = require("src/items.lua")
local B = require("src/client/build.lua")
local G = require("src/client/guns.lua")

local V, Color = Vector, Color
local MAX_OBJECTS, PANEL_Y_FRAC, PROP_GRIDS = CC.MAX_OBJECTS, CC.PANEL_Y_FRAC, CC.PROP_GRIDS
local ROT_FINE, HIDE_BUGBAIT = CC.ROT_FINE, CC.HIDE_BUGBAIT
local CAT_NAMES, ITEMS = IT.CAT_NAMES, IT.ITEMS
local me = C.me

%s
""" % hud_body)
