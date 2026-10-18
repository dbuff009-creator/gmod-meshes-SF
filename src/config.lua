-- Infantry Tool :: settings
-- Every tunable of the tool lives here: ranges, timings, limits, materials.
-- Nothing in this file touches the engine, so it can be read as documentation.

-- ============================ SETTINGS ============================
local WEAPON_CLASS   = "weapon_bugbait"
local KEY_MENU_BIND  = "+menu"          -- Q: blocked spawn menu bind while holding the tool
local KEY_ROTATE     = KEY.R
local KEY_GRID       = KEY.G
local KEY_DETONATE   = KEY.X
local KEY_MENU       = KEY.Q             -- raw key for the menu (works even when the cursor has focus)

local PLACE_RANGE    = 300
local MAX_OBJECTS    = 0                -- 0 = no limit of your own (SF server limits: props, prop burst 4/s, custom prop vertices)
local PLACE_COOLDOWN = 0.3              -- props spawn burst is 4/s
local ARM_TIME       = 2                -- mines arm after this
local OWNER_SAFE     = false            -- true = your own mines ignore you
local SHOOTABLE      = true             -- mines / C4 / claymore explode when shot
local USE_WIRE_EXPLOSIVE = true         -- gmod_wire_explosive (as in your missile), else game.blastDamage
local TIMED_FUSE     = 15               -- timed charge countdown
local LASER_RANGE    = 400              -- laser mine beam length
local RADAR_RANGE    = 1600             -- recon radar: enemies inside this radius are shown on your HUD
local ALARM_RANGE    = 260              -- motion alarm detection radius (needs line of sight)
local KEY_CAM        = KEY.B            -- periscope cameras: B = next camera / off
-- mortar (drone camera, idea + ballistics from "Mortar Predictive")
local MORTAR_MIN     = 400              -- min target distance
local MORTAR_MAX     = 9000             -- max target / camera distance from the mortar
local MORTAR_CAM_H   = 900              -- drone camera start height over the mortar
local MORTAR_MARKERS = true             -- show players / NPCs the drone camera can see

local TRENCH_CELL    = 192              -- trench grid cell
local TRENCH_WIDTH   = 96               -- channel width (inside)
local TRENCH_DEPTH   = 72               -- parapet height: standing player is covered, fire step lets you shoot over
local TRENCH_SPILL   = 60               -- outer earth slope beyond the cell (walkable, so you can climb onto it)
local TRENCH_FIRE_STEP = true           -- 18-unit step along one wall of straight pieces
local ROOF_Z         = 26               -- plank roof height over the parapet (the gap is a firing slit)
local MESH_TWO_SIDED = false            -- true = draw every face from both sides (2x triangles; only if things look inside-out)
local MESH_CPU       = 0.35             -- share of the CPU quota per frame used to build meshes
local PROP_GRIDS     = { 32, 16, 64, 8 } -- prop grid sizes (Shift+G cycles), grid aligns to your nearest object
local ROT_STEP       = 45               -- R / Shift+R
local ROT_FINE       = 15               -- free rotation of the very first trench (before the grid exists)

-- manned guns
local SEAT_MODEL     = "models/nova/airboat_seat.mdl"
local SEAT_HIDDEN    = true             -- the gunner sits on the ammo box of the gun model
local GUN_STATS = {
    mg     = { name = "MG", rate = 0.1, dmg = 9, spread = 0.02, mag = 100, reload = 3.5, auto = true,
               heatPer = 0.028, cool = 0.12,               -- ~60 rounds of continuous fire -> overheat
               yaw = 75, up = 30, down = 18, turn = 240,    -- arc (deg), turn speed (deg/s)
               force = 3, zoom = { 50 },
               snd = "weapons/ar2/fire1.wav", pitch = 72, lvl = 110, flash = 2, tracer = "Tracer", tracerEvery = 2,
               rel1 = "weapons/ar2/ar2_magout.wav", rel2 = "weapons/ar2/ar2_magin.wav" },
    sniper = { name = "SNIPER", rate = 1.4, dmg = 95, spread = 0.0005, mag = 5, reload = 3.2, auto = false,
               heatPer = 0, cool = 1,
               yaw = 55, up = 25, down = 20, turn = 200,
               force = 20, zoom = { 20, 7 },
               snd = "npc/sniper/sniper1.wav", pitch = 100, lvl = 140, flash = 6, tracer = "AirboatGunHeavyTracer", tracerEvery = 1,
               bolt = "weapons/shotgun/shotgun_cock.wav",
               rel1 = "weapons/357/357_reload1.wav", rel2 = "weapons/357/357_reload4.wav" },
    -- one shell, armour piercing + blast at the hit point
    atgun  = { name = "AT GUN", rate = 1, dmg = 100, spread = 0.001, mag = 1, reload = 3, auto = false,
               heatPer = 0, cool = 1, yaw = 35, up = 15, down = 8, turn = 50, force = 60, zoom = { 30, 12 },
               blast = { r = 150, d = 250 },
               snd = "weapons/357/357_fire2.wav", pitch = 45, lvl = 150, flash = 5, tracer = "AirboatGunHeavyTracer", tracerEvery = 1,
               rel1 = "physics/metal/metal_box_impact_hard1.wav", rel2 = "weapons/shotgun/shotgun_cock.wav" },
    -- indirect fire: drone camera, fixed tube angle (wheel / RMB), speed computed for the target
    mortar = { name = "MORTAR", mortar = { g = 600, r = 280, d = 200 }, ownView = true,
               rate = 1, dmg = 0, spread = 0, mag = 1, reload = 3, auto = false,
               heatPer = 0, cool = 1, yaw = 180, up = 85, down = -20, turn = 90, force = 0, zoom = {},
               snd = "weapons/mortar/mortar_fire1.wav", pitch = 100, lvl = 120, flash = 1,
               rel1 = "physics/metal/metal_canister_impact_soft1.wav", rel2 = "weapons/shotgun/shotgun_cock.wav" },
    -- twin anti-air: fast, small blast on every hit (air vehicles), high elevation
    flak   = { name = "FLAK 2x", rate = 0.12, dmg = 11, spread = 0.015, mag = 80, reload = 4.5, auto = true, twin = true,
               heatPer = 0.018, cool = 0.14, yaw = 120, up = 80, down = 10, turn = 160, force = 4, zoom = { 40 },
               blast = { r = 90, d = 22, small = true },
               snd = "weapons/ar2/fire1.wav", pitch = 55, lvl = 120, flash = 2, tracer = "Tracer", tracerEvery = 1,
               rel1 = "weapons/ar2/ar2_magout.wav", rel2 = "weapons/ar2/ar2_magin.wav" },
}

local BLOCK_BUGBAIT  = true
local HIDE_BUGBAIT   = true             -- hide the bug viewmodel / world model
local SELECTOR_WINDOW = 3
local PANEL_Y_FRAC   = 0.55

-- materials (if one is missing on your server it falls back to debugwhite + color)
local MAT = {
    metal    = "phoenix_storms/metalset_1-2",
    concrete = "phoenix_storms/concrete0",
    dirt     = "models/props_wasteland/dirtwall001a",
    fabric   = "models/props_c17/furniturefabric003a",
    wood     = "models/props_wasteland/wood_fence01a",
    plain    = "models/debug/debugwhite",
}
local HM = "models/starfall/holograms/"

return {
    WEAPON_CLASS = WEAPON_CLASS,
    KEY_MENU_BIND = KEY_MENU_BIND,
    KEY_ROTATE = KEY_ROTATE,
    KEY_GRID = KEY_GRID,
    KEY_DETONATE = KEY_DETONATE,
    KEY_MENU = KEY_MENU,
    PLACE_RANGE = PLACE_RANGE,
    MAX_OBJECTS = MAX_OBJECTS,
    PLACE_COOLDOWN = PLACE_COOLDOWN,
    ARM_TIME = ARM_TIME,
    OWNER_SAFE = OWNER_SAFE,
    SHOOTABLE = SHOOTABLE,
    USE_WIRE_EXPLOSIVE = USE_WIRE_EXPLOSIVE,
    TIMED_FUSE = TIMED_FUSE,
    LASER_RANGE = LASER_RANGE,
    RADAR_RANGE = RADAR_RANGE,
    ALARM_RANGE = ALARM_RANGE,
    KEY_CAM = KEY_CAM,
    MORTAR_MIN = MORTAR_MIN,
    MORTAR_MAX = MORTAR_MAX,
    MORTAR_CAM_H = MORTAR_CAM_H,
    MORTAR_MARKERS = MORTAR_MARKERS,
    TRENCH_CELL = TRENCH_CELL,
    TRENCH_WIDTH = TRENCH_WIDTH,
    TRENCH_DEPTH = TRENCH_DEPTH,
    TRENCH_SPILL = TRENCH_SPILL,
    TRENCH_FIRE_STEP = TRENCH_FIRE_STEP,
    ROOF_Z = ROOF_Z,
    MESH_TWO_SIDED = MESH_TWO_SIDED,
    MESH_CPU = MESH_CPU,
    PROP_GRIDS = PROP_GRIDS,
    ROT_STEP = ROT_STEP,
    ROT_FINE = ROT_FINE,
    SEAT_MODEL = SEAT_MODEL,
    SEAT_HIDDEN = SEAT_HIDDEN,
    GUN_STATS = GUN_STATS,
    BLOCK_BUGBAIT = BLOCK_BUGBAIT,
    HIDE_BUGBAIT = HIDE_BUGBAIT,
    SELECTOR_WINDOW = SELECTOR_WINDOW,
    PANEL_Y_FRAC = PANEL_Y_FRAC,
    MAT = MAT,
    HM = HM,
}
