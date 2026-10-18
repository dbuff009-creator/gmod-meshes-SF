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
    by the --@include lines above, then loaded with require(). Because the
    included files carry --@server / --@client / --@shared, a server never
    compiles the client half and a client never compiles the server half.

    Layout (repository path == include name):
      src/config.lua          settings: ranges, timings, limits, materials
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
