--@name Infantry Tool
--@author SF KB
--@shared
--@include https://raw.githubusercontent.com/dbuff009-creator/gmod-meshes-SF/main/src/config.lua as src/config.lua
--@include https://raw.githubusercontent.com/dbuff009-creator/gmod-meshes-SF/main/src/geom.lua as src/geom.lua
--@include https://raw.githubusercontent.com/dbuff009-creator/gmod-meshes-SF/main/src/shared.lua as src/shared.lua
--@include https://raw.githubusercontent.com/dbuff009-creator/gmod-meshes-SF/main/src/items.lua as src/items.lua
--@include https://raw.githubusercontent.com/dbuff009-creator/gmod-meshes-SF/main/src/server/core.lua as src/server/core.lua
--@include https://raw.githubusercontent.com/dbuff009-creator/gmod-meshes-SF/main/src/server/guns.lua as src/server/guns.lua
--@include https://raw.githubusercontent.com/dbuff009-creator/gmod-meshes-SF/main/src/server/sensors.lua as src/server/sensors.lua
--@include https://raw.githubusercontent.com/dbuff009-creator/gmod-meshes-SF/main/src/client/core.lua as src/client/core.lua
--@include https://raw.githubusercontent.com/dbuff009-creator/gmod-meshes-SF/main/src/client/meshes.lua as src/client/meshes.lua
--@include https://raw.githubusercontent.com/dbuff009-creator/gmod-meshes-SF/main/src/client/guns.lua as src/client/guns.lua
--@include https://raw.githubusercontent.com/dbuff009-creator/gmod-meshes-SF/main/src/client/build.lua as src/client/build.lua
--@include https://raw.githubusercontent.com/dbuff009-creator/gmod-meshes-SF/main/src/client/hud.lua as src/client/hud.lua

--[[
    INFANTRY TOOL - modular build

    A soldier's build tool on weapon_bugbait: mines, C4, manned guns, trenches,
    fortifications, obstacles and a field menu, all spawned by the chip.

    This file only pulls the modules in. Every module is fetched at compile time
    by the include lines above, then loaded with require(). Because the
    included files declare their own realm (server, client or shared), a server
    never compiles the client half and a client never compiles the server half.
    Keep this comment free of directive-looking text: the preprocessor scans
    comments too, and any at-sign directive inside one is treated for real.

    Layout (repository path == include name):
      src/config.lua          default settings (the CFG block below overrides them)
      src/geom.lua            primitive geometry + convex hull points
      src/shared.lua          helpers used by both realms
      src/items.lua           the whole item catalogue
      src/server/core.lua     state, registry, placement, explosions, commands
      src/server/guns.lua     seats, aiming, firing, mortar ballistics
      src/server/sensors.lua  mines, alarms, radar, world hooks
      src/client/core.lua     identity, fonts, registry, one think dispatcher
      src/client/meshes.lua   mesh building and applying, field lights
      src/client/guns.lua     gunner HUD, scope, mortar camera
      src/client/build.lua    ghost, placement, input, grid (owner only)
      src/client/hud.lua      menu and HUD (owner only)

    Permissions Starfall may ask for (depending on the server's permission
    addon): hologram.create / setRenderProperty, entities.setRenderProperty /
    setSolid, prop.create / createCustom / createSeat, mesh, material.load,
    light.create, health, input, render.hud, render.calcview,
    render.adjustmousesensitivity, game.bulletDamage, game.blastDamage,
    effect.create, net, timer.
]]

-- ============================ SETTINGS ============================
-- Everything tunable lives here, in the chip itself: ranges, timings, limits,
-- gun stats, materials. The block is applied over src/config.lua before any
-- module loads, so editing a number here is enough -- no repository edits.
-- Delete a line to fall back to the module default. Whole tables (GUN_STATS,
-- MAT, ...) are replaced, so keep them complete.

local CFG = {
-- >>> CFG-BEGIN
    WEAPON_CLASS       = "weapon_bugbait",
    KEY_MENU_BIND      = "+menu",  -- Q: blocked spawn menu bind while holding the tool
    KEY_ROTATE         = KEY.R,
    KEY_GRID           = KEY.G,
    KEY_DETONATE       = KEY.X,
    KEY_MENU           = KEY.Q,  -- raw key for the menu (works even when the cursor has focus)
    PLACE_RANGE        = 300,
    MAX_OBJECTS        = 0,  -- 0 = no limit of your own (SF server limits: props, prop burst 4/s, custom prop vertices)
    PLACE_COOLDOWN     = 0.3,  -- props spawn burst is 4/s
    ARM_TIME           = 2,  -- mines arm after this
    OWNER_SAFE         = false,  -- true = your own mines ignore you
    SHOOTABLE          = true,  -- mines / C4 / claymore explode when shot
    USE_WIRE_EXPLOSIVE = true,  -- gmod_wire_explosive (as in your missile), else game.blastDamage
    TIMED_FUSE         = 15,  -- timed charge countdown
    LASER_RANGE        = 400,  -- laser mine beam length
    RADAR_RANGE        = 1600,  -- recon radar: enemies inside this radius are shown on your HUD
    ALARM_RANGE        = 260,  -- motion alarm detection radius (needs line of sight)
    KEY_CAM            = KEY.B,  -- periscope cameras: B = next camera / off
    MORTAR_MIN         = 400,  -- min target distance
    MORTAR_MAX         = 9000,  -- max target / camera distance from the mortar
    MORTAR_CAM_H       = 900,  -- drone camera start height over the mortar
    MORTAR_MARKERS     = true,  -- show players / NPCs the drone camera can see
    TRENCH_CELL        = 192,  -- trench grid cell
    TRENCH_WIDTH       = 96,  -- channel width (inside)
    TRENCH_DEPTH       = 72,  -- parapet height: standing player is covered, fire step lets you shoot over
    TRENCH_SPILL       = 60,  -- outer earth slope beyond the cell (walkable, so you can climb onto it)
    TRENCH_FIRE_STEP   = true,  -- 18-unit step along one wall of straight pieces
    ROOF_Z             = 26,  -- plank roof height over the parapet (the gap is a firing slit)
    MESH_TWO_SIDED     = false,  -- true = draw every face from both sides (2x triangles; only if things look inside-out)
    MESH_CPU           = 0.35,  -- share of the CPU quota per frame used to build meshes
    PROP_GRIDS         = { 32, 16, 64, 8 },  -- prop grid sizes (Shift+G cycles), grid aligns to your nearest object
    ROT_STEP           = 45,  -- R / Shift+R
    ROT_FINE           = 15,  -- free rotation of the very first trench (before the grid exists)
    SEAT_MODEL         = "models/nova/airboat_seat.mdl",
    SEAT_HIDDEN        = true,  -- the gunner sits on the ammo box of the gun model
    GUN_STATS          = {
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
    },
    BLOCK_BUGBAIT      = true,
    HIDE_BUGBAIT       = true,  -- hide the bug viewmodel / world model
    SELECTOR_WINDOW    = 3,
    PANEL_Y_FRAC       = 0.55,
    MAT                = {
        metal    = "phoenix_storms/metalset_1-2",
        concrete = "phoenix_storms/concrete0",
        dirt     = "models/props_wasteland/dirtwall001a",
        fabric   = "models/props_c17/furniturefabric003a",
        wood     = "models/props_wasteland/wood_fence01a",
        plain    = "models/debug/debugwhite",
    },
    HM                 = "models/starfall/holograms/",
-- <<< CFG-END
}
do
    local defaults = require("src/config.lua")
    for k, v in pairs(CFG) do defaults[k] = v end
    defaults.fromChip = true          -- the modules all see this same table
end

if SERVER then
    require("src/server/core.lua")
    require("src/server/guns.lua")
    require("src/server/sensors.lua")
    return
end

local C = require("src/client/core.lua")
require("src/client/meshes.lua")
require("src/client/guns.lua")

-- Menu, ghosts and the owner panel only exist on the owner's client.
-- Everything else (meshes, field lights, gunner view) runs on every client.
if C.isOwner then
    require("src/client/build.lua")
    require("src/client/hud.lua")
end
