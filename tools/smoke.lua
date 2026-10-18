-- Runs the whole chip against tools/mock.lua in both realms.
-- Called from tools/smoke.py with (newRealm, ROOT).
local newRealm, ROOT = ...

local fails, checks = 0, 0
local function try(fn, label)
    local okk, err = pcall(fn)
    if not okk then print("  ERR   " .. label .. ": " .. tostring(err)) end
    return okk, err
end
local function ok(cond, msg)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        print("  FAIL  " .. msg)
    end
end

local function readFile(path)
    local f = assert(io.open(ROOT .. "/" .. path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local main_src = readFile("infantry_tool.lua")

local function loadMain(env)
    local fn = assert(load(main_src, "@infantry_tool.lua", "t", env))
    return fn()
end

local function diffGlobals(before, after)
    local seen = {}
    for k in before:gmatch("%S+") do seen[k] = true end
    local out = {}
    for k in after:gmatch("%S+") do if not seen[k] then out[#out + 1] = k end end
    return out
end

-- ============================================================ server
print("== server realm ==")
local srv = newRealm("server")
local before = srv._keys()
local okLoad, err = pcall(loadMain, srv)
ok(okLoad, "server main failed: " .. tostring(err))
if not okLoad then print(err) return end

local leaked = diffGlobals(before, srv._keys())
ok(#leaked == 0, "server leaked globals: " .. table.concat(leaked, ", "))

local S = srv.require("src/server/core.lua")
local IT = srv.require("src/items.lua")
local CFG = srv.require("src/config.lua")
ok(CFG.fromChip == true, "chip CFG applied over src/config.lua")
ok(CFG.WEAPON_CLASS == "weapon_bugbait" and CFG.GUN_STATS.mg.name == "MG" and type(CFG.MAT) == "table",
   "chip CFG values visible to modules")
ok(type(S) == "table", "core returns S")
ok(#IT.ITEMS > 10, "item catalogue loaded (" .. #IT.ITEMS .. " items)")
ok(#IT.MDEFS >= #IT.ITEMS and #IT.ITEMS > 10, "mesh defs: " .. #IT.MDEFS .. " for " .. #IT.ITEMS .. " items")

for _, fn in ipairs({ "doPlace", "placeGun", "destroyGun", "gunSeat", "setOperator", "sendState",
                      "sendReg", "sendUnreg", "explodeAt", "spawnShell", "shellTick", "fuse",
                      "detonate", "unregister", "removeObj", "trenchCells", "trenchOverlaps",
                      "stretchWire", "removeAimed", "clearAll", "countObjs", "snd", "fireBullets" }) do
    ok(type(S[fn]) == "function", "S." .. fn .. " is a function")
end
ok(type(S.guns) == "table" and type(S.objs) == "table", "S tables")
ok(type(S.armLater) == "function", "S.armLater from sensors")
ok(type(S.sensors) == "table", "S.sensors from sensors")
ok(type(S.BOOM) == "table", "S.BOOM")

srv._tick(0.1)

-- place every item once
local V, A = srv.Vector, srv.Angle
local placed, failed = 0, {}
for i, it in ipairs(IT.ITEMS) do
  if it.kind ~= "cover" then
    local p = V(0, 0, 16 + i * 4)
    local okk, err2 = pcall(function()
        if it.kind == "gun" then
            S.doPlace(it, p, A(0, 0, 0), V(0, 0, 1), it.mountDefs and 1 or 0, 0)
        else
            S.doPlace(it, p, A(0, 0, 0), V(0, 0, 1), 0, 0)
        end
    end)
    if okk and S.countObjs() > placed then placed = placed + 1 else failed[#failed + 1] = tostring(it.name) end
    srv._tick(CFG.PLACE_COOLDOWN)
  end
end
ok(placed >= 20, "placed " .. placed .. " objects (" .. #failed .. " failed: " .. table.concat(failed, ",") .. ")")
ok(S.countObjs() > 20, "object registry: " .. S.countObjs())

-- let mines arm, timers fire, shells fall
for _ = 1, 400 do srv._tick(0.05) end
ok(#S.sensors > 0, "armed sensors: " .. #S.sensors)

-- the sensor list must not accumulate duplicates over time
local seen, dupes = {}, 0
for _, e in ipairs(S.sensors) do
    if seen[e] then dupes = dupes + 1 end
    seen[e] = true
end
ok(dupes == 0, "no duplicate sensors (" .. dupes .. ")")
ok(#S.sensors <= 64, "sensor list bounded: " .. #S.sensors)

-- fire the first gun through the seat path
local gunBase
for base in pairs(S.guns) do gunBase = base break end
if gunBase then
    local okk = pcall(function()
        S.setOperator(S.guns[gunBase], srv.player())
        S.sendMount(srv.player(), S.guns[gunBase], true)
        for _ = 1, 120 do srv._tick(1 / 30) end
    end)
    ok(okk, "gun operator + tick")
end

-- projectile + explosion paths
local okk = try(function()
    S.spawnShell(V(0, 0, 200), V(200, 0, 0), { g = 600, r = 200, d = 120, big = true }, nil, nil)
    for _ = 1, 300 do srv._tick(1 / 30) end
    S.explodeAt(V(0, 0, 20), 150, 90, true)
    local first = next(S.objs)
    if first then S.fuse(first, 0.05) end
    for _ = 1, 60 do srv._tick(1 / 30) end
end, "shells/explosions/fuse")
ok(okk, "shells / explosions / fuse")

-- fuse list: it grows on fuse() and empties after detonation
local victim
for e, o in pairs(S.objs) do
    if o.it.logic and S.BOOM[o.it.logic] then victim = e break end
end
if victim then
    S.fuse(victim, 0.05)
    ok(#S.fused > 0, "fuse list filled: " .. #S.fused)
    for _ = 1, 40 do srv._tick(0.05) end
    ok(S.objs[victim] == nil, "fused object detonated")
    ok(#S.fused == 0, "fuse list drained: " .. #S.fused)
end

-- keep the broadcast stream (it_reg / it_state) for the client realm
local serverQueue = {}
for _, msg in ipairs(srv._netq) do serverQueue[#serverQueue + 1] = msg end
for i = #srv._netq, 1, -1 do srv._netq[i] = nil end

-- command channel: place one object from a fake client
srv._tick(1.0)
local beforeCmd = S.countObjs()
local function clientCmd(it, pos)
    srv.net.start("it_cmd")
    srv.net.writeUInt(1, 4)
    srv.net.writeUInt(it.idx, 8)
    srv.net.writeVector(pos)
    srv.net.writeAngle(A(0, 0, 0))
    srv.net.writeVector(V(0, 0, 1))
    srv.net.writeUInt(0, 4)
    srv.net.writeUInt(0, 16)
    srv.net.send()
    local msg = srv._netq[#srv._netq]
    srv._deliver(msg, srv.player())
end
local okcmd, cmderr = try(function() clientCmd(IT.ITEMS[1], V(50, 50, 20)) end, "it_cmd")
if not okcmd then print("   cmd err: " .. tostring(cmderr)) end
ok(okcmd, "it_cmd placement through net")
srv._tick(0.5)
ok(S.countObjs() > beforeCmd, "net placement created an object")

-- remove / clear
local okrm = try(function()
    S.clearAll()
    srv._tick(0.2)
end, "clearAll")
ok(okrm and S.countObjs() == 0, "clearAll removed everything (" .. S.countObjs() .. " left)")

-- ============================================================ client
print("== client realm ==")
local cli = newRealm("client")
local beforeC = cli._keys()
local okc, errc = pcall(loadMain, cli)
ok(okc, "client main failed: " .. tostring(errc))
if not okc then print(errc) return end

local leakedC = diffGlobals(beforeC, cli._keys())
ok(#leakedC == 0, "client leaked globals: " .. table.concat(leakedC, ", "))

local C = cli.require("src/client/core.lua")
local MSH = cli.require("src/client/meshes.lua")
local GUNS = cli.require("src/client/guns.lua")
local BLD = cli.require("src/client/build.lua")
local HUD = cli.require("src/client/hud.lua")
ok(type(C) == "table" and C.isOwner == true, "owner detected")
ok(type(C.regOf) == "function", "C.regOf")
ok(type(MSH.meshes) == "table" and type(MSH.getMat) == "function", "meshes module")
if type(GUNS) ~= "table" then print("  guns module returned " .. type(GUNS)) end
if type(GUNS) == "table" then
  local ks = {}
  for k in pairs(GUNS) do ks[#ks + 1] = k end
  print("  guns keys: " .. table.concat(ks, ","))
end
ok(type(GUNS) == "table" and type(GUNS.tri2) == "function" and type(GUNS.bracket) == "function", "guns exports")
ok(type(GUNS.isGunning) == "function", "guns.isGunning")
if type(BLD) == "table" then
  local ks = {}
  for k in pairs(BLD) do ks[#ks + 1] = k end
  print("  build keys: " .. table.concat(ks, ","))
end
ok(type(BLD) == "table" and type(BLD.setMenu) == "function" and type(BLD.sendSimple) == "function", "build exports")
ok(type(BLD.selected) == "table", "B.selected is an item")
ok(type(BLD.plan) == "table" or BLD.plan == nil, "B.plan")
ok(HUD == true or type(HUD) == "table", "hud loaded")

-- run the client long enough to build every mesh (coroutine + budget)
for _ = 1, 600 do cli._tick(1 / 60) end
local built = 0
for _, m in pairs(MSH.meshes) do if m then built = built + 1 end end
ok(built > 10, "meshes built: " .. built .. "/" .. #IT.MDEFS)

-- replay everything the server broadcast
local delivered = 0
for _, msg in ipairs(serverQueue) do
    if cli._deliver(msg, nil) then delivered = delivered + 1 end
end
ok(delivered > 0, "server net messages delivered: " .. delivered)
for _ = 1, 240 do cli._tick(1 / 60) end
local registered, withItem = 0, 0
for _, r in pairs(C.reg) do
    registered = registered + 1
    if r.d and r.it then withItem = withItem + 1 end
end
ok(registered > 0, "registry entries: " .. registered)
ok(withItem > 0, "registry entries carry an item: " .. withItem)
ok(#C.think == 4, "client think callbacks merged: " .. #C.think)

-- open the menu, hover nothing, close it
local okMenu = pcall(function()
    BLD.setMenu(true)
    for _ = 1, 120 do cli._tick(1 / 60) end
    BLD.setMenu(false)
end)
ok(okMenu, "menu open/close")

-- hud / overlays / input hooks
local okDraw = pcall(function()
    cli.hook.run("drawhud")
    cli.hook.run("calcview", V(0, 0, 0), A(0, 0, 0), 90)
    cli.hook.run("adjustmousesensitivity")
    cli.hook.run("inputbindpressed", "+menu")
    cli.hook.run("mousewheeled", 1)
    cli.hook.run("postdrawtranslucentrenderables", 1, false)
end)
ok(okDraw, "draw/input hooks")

-- ghost + plan for every item (exercises computePlan/mountPlan/mesh runs)
local okPlan = pcall(function()
    for _, it in ipairs(IT.ITEMS) do
        BLD.selected = it
        for _ = 1, 4 do cli._tick(1 / 60) end
    end
end)
ok(okPlan, "plan for every item")

-- client sends a placement command, server must accept it
local it0 = IT.ITEMS[1]
local okSend = pcall(function()
    BLD.sendPlace(it0, { pos = V(10, 10, 30), ang = A(0, 0, 0), normal = V(0, 0, 1), lvl = 0 })
end)
ok(okSend, "client sendPlace")
local q = cli._netq
local okDeliver = pcall(function()
    for _, msg in ipairs(q) do srv._deliver(msg, srv.player()) end
end)
ok(okDeliver, "server accepted client command")

print(string.format("== %d checks, %d failed ==", checks, fails))
if fails > 0 then error(fails .. " smoke checks failed") end
