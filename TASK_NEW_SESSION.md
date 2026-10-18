# ЗАДАЧА ДЛЯ НОВОЙ СЕССИИ

В чат приложены два файла:

* `repo_update.patch` — 6 готовых коммитов поверх `be10e68` (разбиение чипа на
  модули, фикс директив, фикс `pendingTrip`, настройки `CFG` в чипе, фикс
  импортов после разбиения и инструменты проверки). Проверено: патч ложится
  чисто, после него `smoke.py` = 68 checks / 0 failed, `directives.py` = 0.
* этот файл — подробности на случай конфликтов.

## Что сделать

```bash
git fetch origin
git checkout -B arena/patch-apply origin/main
git am --3way repo_update.patch        # если конфликт: решай в пользу патча
python3 tools/directives.py            # 0 problems
python3 tools/make_chip.py --check     # in sync
python3 tools/smoke.py                 # 68 checks, 0 failed
git push -u origin arena/patch-apply
```

Открыть PR в `main`. В описании: «модульный чип, фикс директив препроцессора,
настройки в чипе (CFG), фикс импортов между модулями (Font does not exist),
инструменты проверки».

Если `git am` конфликтует — не мучайся: просто примени содержимое патча как
финальное состояние файлов (`git checkout --theirs` / перезапись файлов), тесты
должны пройти, коммит один.

---

# ЗАДАЧА ДЛЯ НОВОЙ СЕССИИ: убрать временный шим и починить импорты в модулях

Репозиторий `dbuff009-creator/gmod-meshes-SF`, ветка `main`.

## Контекст

Чип `infantry_tool.lua` уже исправлен (нет конфликта `--@` директив, есть блок
настроек `CFG`) и в конце публикует временный шим:

```lua
local function shim()
    ...
end
shim()
```

Шим нужен потому, что после разбиения монолита на модули часть имён осталась
доступной только как глобальные. Из-за этого в игре падало:

    Hook 'drawhud' errored with: SF:src/client/hud.lua:125: Font does not exist.

Полный список «протечек»: `fTitle, fMed, fSmall, fCard, fTiny, setMenu,
sendSimple, bracket, tri2, me, mortarSolve, meshes, bounds, getMat, C_GUN`.

## Что сделать

1. Добавить отсутствующие импорты в 5 модулей (точные вставки ниже).
2. Удалить из `infantry_tool.lua` функцию `shim()` и её вызов.
3. Добавить `tools/globals.py` (ниже) — он находит именно такие забытые имена.
4. В `tools/mock.lua` сделать шрифты строгими, как в Starfall (ниже) — тогда
   `tools/smoke.py` ловит этот баг.
5. В `tools/smoke.lua` разрешить имена шима в проверке утёкших глобалов
   (ниже), либо, если шим удалён, наоборот — убрать список `SHIM`.
6. Прогнать: `python3 tools/globals.py` (0), `python3 tools/directives.py` (0),
   `python3 tools/make_chip.py --check` (in sync), `python3 tools/smoke.py`
   (68 checks, 0 failed). Закоммитить в ветку `arena/...`, открыть PR в `main`.

## Вставки в модули

### src/client/hud.lua

После строки `local me = C.me` добавить:

```lua
local fTitle, fMed, fSmall, fCard, fTiny = C.fTitle, C.fMed, C.fSmall, C.fCard, C.fTiny
local setMenu, sendSimple = B.setMenu, B.sendSimple
local bracket, tri2 = G.bracket, G.tri2
```

### src/client/guns.lua

После строки `local MORTAR_MARKERS, HM = CC.MORTAR_MARKERS, CC.HM` добавить:

```lua
local me = C.me
local SH = require("src/shared.lua")
local mortarSolve = SH.mortarSolve
local fTitle, fMed, fSmall, fCard, fTiny = C.fTitle, C.fMed, C.fSmall, C.fCard, C.fTiny
```

### src/client/build.lua

После строки `local MOUNT_LEVELS, mountLevelFor, gunPivot = IT.MOUNT_LEVELS, IT.mountLevelFor, IT.gunPivot` добавить:

```lua
local MOUNT_TRENCH, MOUNT_FRONT = IT.MOUNT_TRENCH, IT.MOUNT_FRONT
local M = require("src/client/meshes.lua")
local meshes, bounds, getMat = M.meshes, M.bounds, M.getMat
```

### src/server/guns.lua

После строки `local GUN_GEO, MOUNT_LEVELS = IT.GUN_GEO, IT.MOUNT_LEVELS` добавить:

```lua
local C_GUN = IT.C_GUN
```

### src/items.lua

В таблице `return { ... }` после `MOUNT_FRONT = MOUNT_FRONT,` добавить:

```lua
    C_GUN = C_GUN,
```

## tools/mock.lua: строгие шрифты

Заменить блок

```lua
    for _, fn in ipairs({ "setFont", "setRGBA", "setColor", "setMaterial", "drawRect", "drawCircle",
        "drawFilledCircle", "drawSimpleText", "draw3DLine", "drawPoly", "drawTexturedRect",
        "drawText", "setCullMode" }) do r[fn] = function() end end
    r.createFont = function(f, s) assert(type(f) == "string" and type(s) == "number") return { f = f, s = s } end
```

на

```lua
    for _, fn in ipairs({ "setRGBA", "setColor", "setMaterial", "drawRect", "drawCircle",
        "drawFilledCircle", "drawSimpleText", "draw3DLine", "drawPoly", "drawTexturedRect",
        "drawText", "setCullMode" }) do r[fn] = function() end end
    -- fonts behave like Starfall's: createFont returns a registered name and
    -- setFont throws on anything else (this is what "Font does not exist" is)
    local fonts = { Default = true, DebugFixed = true, DebugFixedSmall = true,
        Trebuchet18 = true, Trebuchet24 = true, ChatFont = true, TargetID = true }
    r.createFont = function(f, s)
        assert(type(f) == "string" and type(s) == "number", "createFont(font, size)")
        local name = string.format("sf_font_%s_%d", f, s)
        fonts[name] = true
        return name
    end
    r.setFont = function(f) assert(fonts[f], "Font does not exist.") r._font = f end
```

## tools/smoke.lua: список шима

Перед строкой `local leaked = diffGlobals(before, srv._keys())` добавить:

```lua
-- the chip's temporary compatibility shim publishes a few names as globals;
-- drop SHIM from this list (and the shim from the chip) once the modules on
-- main import them properly
local SHIM = {
    C_GUN = true, mortarSolve = true, meshes = true, bounds = true, getMat = true,
    fTitle = true, fMed = true, fSmall = true, fCard = true, fTiny = true,
    me = true, bracket = true, tri2 = true, setMenu = true, sendSimple = true,
}
local function realLeaks(list)
    local out = {}
    for _, k in ipairs(list) do if not SHIM[k] then out[#out + 1] = k end end
    return out
end
```

и заменить

```lua
local leaked = diffGlobals(before, srv._keys())
```

на

```lua
local leaked = realLeaks(diffGlobals(before, srv._keys()))
```

а

```lua
local leakedC = diffGlobals(beforeC, cli._keys())
```

на

```lua
local leakedC = realLeaks(diffGlobals(beforeC, cli._keys()))
```

Если шим из чипа удалён (пункт 2), то `SHIM` можно оставить пустым
(`local SHIM = {}`) — проверка станет строгой.

## Нынешний infantry_tool.lua (с шимом, для справки)

```lua
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
    C_GUN = require("src/items.lua").C_GUN or Color(70, 72, 68)
    return
end

local C = require("src/client/core.lua")
require("src/client/meshes.lua")
require("src/client/guns.lua")

-- Compatibility shim for the modules currently on main: a handful of names
-- used to be file-locals of the monolithic chip and are still read as globals
-- by hud.lua / guns.lua / build.lua (fonts, mesh cache, menu helpers). It is
-- harmless once the modules are updated -- remove it after that update.
local function shim()
    local SH = require("src/shared.lua")
    mortarSolve = SH.mortarSolve
    local M = require("src/client/meshes.lua")
    meshes, bounds, getMat = M.meshes, M.bounds, M.getMat
    fTitle, fMed, fSmall, fCard, fTiny = C.fTitle, C.fMed, C.fSmall, C.fCard, C.fTiny
    me = C.me
    local G = require("src/client/guns.lua")
    bracket, tri2 = G.bracket, G.tri2
    if C.isOwner then
        local B = require("src/client/build.lua")
        setMenu, sendSimple = B.setMenu, B.sendSimple
    end
end

-- Menu, ghosts and the owner panel only exist on the owner's client.
-- Everything else (meshes, field lights, gunner view) runs on every client.
if C.isOwner then
    require("src/client/build.lua")
    require("src/client/hud.lua")
end

shim()
```

## tools/globals.py

```python
#!/usr/bin/env python3
"""Find cross-module name leaks.

The original chip was one file: a function declared `local` anywhere was visible
to the whole file. After the split, a module that forgot to import such a name
silently gets a nil global -- and the failure shows up only at run time
("attempt to call a nil value", "Font does not exist").

This script collects every top-level `local NAME` of every module, then reports
names a module reads but neither declares nor imports.

Usage: python3 tools/globals.py
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BUILTIN_PREFIX = {
    "print", "pairs", "ipairs", "type", "tostring", "tonumber", "error", "assert",
    "pcall", "xpcall", "select", "unpack", "setmetatable", "getmetatable", "rawget",
    "rawset", "rawequal", "next", "table", "string", "math", "coroutine", "os",
    "io", "debug", "bit", "utf8", "require", "dofile", "load", "loadstring",
    "collectgarbage", "newproxy", "module", "setfenv", "getfenv", "gcinfo",
}

# Starfall / GMod globals that modules are allowed to read without import.
GLOBALS = {
    "Vector", "Angle", "Color", "Matrix", "IsValid", "isValid", "isvector",
    "isangle", "ismatrix", "isstring", "isnumber", "istable", "isfunction",
    "isbool", "isentity", "isPlayer", "isNPC", "isVehicle", "isWeapon",
    "isEffect", "isPhysObj", "timer", "net", "hook", "render", "input",
    "material", "mesh", "hologram", "prop", "light", "sound", "trace", "find",
    "game", "effect", "constraint", "ents", "player", "owner", "entity",
    "SERVER", "CLIENT", "SF", "MASK", "MOUSE", "KEY", "TEXT_ALIGN", "TOP",
    "BOTTOM", "LEFT", "RIGHT", "CENTER", "MATERIAL", "RENDERGROUP", "COLLISION_GROUP",
    "CHANNEL", "SOUND", "TEAM", "STENCIL", "BLEND", "SURFACE", "HUD", "NOTIFY",
    "TASK", "MOVETYPE", "SIM", "OBS_MODE", "IN", "MOUSE_FIRST", "MOUSE_LAST",
    "MOUSE_LEFT", "MOUSE_RIGHT", "DAMAGE", "CLASS", "WIRE", "SCHED", "FILL",
    "VISIBLE", "SOLID", "SHOT", "OPAQUE", "SPECIAL", "ALL", "WAIT", "GM",
    "LocalPlayer", "cvars", "console", "util", "file", "http", "sql", "physenv",
    "Stencil", "holograms", "sounds", "clamp", "lerp", "Color", "table",
}

LOCAL = re.compile(r"^local\s+([A-Za-z_][\w, ]*?)\s*(?:=|$)")
FUNCTION = re.compile(r"^local\s+function\s+([A-Za-z_]\w*)")
IMPORT = re.compile(r"^local\s+([A-Za-z_][\w]*(?:\s*,\s*[A-Za-z_]\w*)*)\s*=\s*([A-Za-z_][\w.]*)")
READ = re.compile(r"(?<![\w.:])([A-Z][A-Za-z_]\w*|[a-z_][\w]*)(?![\w(])|(?<![\w.:])([A-Za-z_]\w*)\s*\(")


def top_locals(src, any_indent=False):
    """Locals of a file; by default only file-level ones (column 0)."""
    names = set()
    for line in src.splitlines():
        if not any_indent and line[:1] in (" ", "\t"):
            continue
        stripped = line.strip()
        if not stripped.startswith("local") and not stripped.startswith("function"):
            continue
        m = re.match(r"(?:local\s+)?function\s+([A-Za-z_]\w*)", stripped)
        if m:
            names.add(m.group(1))
            continue
        m = re.match(r"local\s+([A-Za-z_][\w,\s]*?)\s*(?:=|$)", stripped)
        if m:
            for part in m.group(1).split(","):
                part = part.strip()
                if re.fullmatch(r"[A-Za-z_]\w*", part):
                    names.add(part)
    return names


def strip_comments_strings(src):
    out, i, n = [], 0, len(src)
    while i < n:
        two = src[i:i + 2]
        if two == "--":
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if two == "[[" or src[i:i + 3] == "--[[":
            j = src.find("]]", i)
            i = n if j < 0 else j + 2
            continue
        ch = src[i]
        if ch in "\"'":
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == ch or src[j] == "\n":
                    break
                j += 1
            i = j + 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def main():
    files = sorted(glob.glob(os.path.join(ROOT, "src", "*", "*.lua")) +
                   glob.glob(os.path.join(ROOT, "src", "*.lua")))
    sources = {os.path.relpath(f, ROOT): open(f, encoding="utf-8").read() for f in files}
    declared = {path: top_locals(src) for path, src in sources.items()}      # file-level only
    own_all = {path: top_locals(src, any_indent=True) for path, src in sources.items()}

    problems = 0
    for path, src in sources.items():
        body = strip_comments_strings(src)
        own = own_all[path]
        imported = set()
        for line in src.splitlines():
            m = IMPORT.match(line)
            if m:
                for part in m.group(1).split(","):
                    imported.add(part.strip())
        missing = {}
        for m in READ.finditer(body):
            name = m.group(1) or m.group(2)
            if not name or len(name) < 3 or name in own or name in imported:
                continue
            after = body[m.end():m.end() + 3].lstrip()
            if after.startswith("=") and not after.startswith("=="):
                continue        # table key or assignment target, not a read
            if name in BUILTIN_PREFIX or name in GLOBALS:
                continue
            # only interesting when another module declares it as a top-level local
            owners = [p for p, names in declared.items() if p != path and name in names]
            if owners:
                missing[name] = owners
        if missing:
            problems += len(missing)
            print(f"{path}:")
            for name, owners in sorted(missing.items()):
                print(f"   {name}  (declared in {', '.join(owners)})")
    print(f"cross-module leaks: {problems}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
```
