--@server
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
local C_GUN = IT.C_GUN
local gunPivot, gunSeatPos = IT.gunPivot, IT.gunSeatPos

local O = S.O
local objs, guns, seatBase = S.objs, S.guns, S.seatBase

local countObjs, sendState, sendReg, sendUnreg = S.countObjs, S.sendState, S.sendReg, S.sendUnreg
local snd, explodeAt, spawnShell, shellTick = S.snd, S.explodeAt, S.spawnShell, S.shellTick
local unregister, removeObj, detonate, fuse = S.unregister, S.removeObj, S.detonate, S.fuse
local placeMesh, spawnExtras, trenchCells, trenchOverlaps = S.placeMesh, S.spawnExtras, S.trenchCells, S.trenchOverlaps
local doPlace, stretchWire, removeAimed, clearAll = S.doPlace, S.stretchWire, S.removeAimed, S.clearAll
local fireBullets, BOOM = S.fireBullets, S.BOOM

local function sendMount(ply, s, on)
    net.start("it_mnt")
    net.writeBool(on)
    if on then
        net.writeUInt(s.hidx or 0, 16)
        net.writeUInt(s.it.idx, 8)
    end
    net.send(ply)
end

local function setOperator(s, op)
    if s.op == op then return end
    if isValid(s.op) then
        if s.viewSet then pcall(s.op.setViewEntity, s.op) end
        pcall(sendMount, s.op, s, false)
        if s.op ~= O then pcall(enableHud, s.op, false) end
    end
    s.viewSet = false
    if isValid(s.camHolo) then s.camHolo:remove() end
    s.camHolo = nil
    s.op = op
    if op then
        -- a player sitting in a vehicle of the chip owner may get the HUD (calcview / scope / crosshair)
        if op ~= O then pcall(enableHud, op, true) end
        pcall(sendMount, op, s, true)
        s.nextSend = 0
        s.rPrev, s.aPrev = true, true
    end
end

local function destroyGun(e)
    local s = guns[e]
    if not s then return end
    guns[e] = nil
    setOperator(s, nil)
    if s.seat then
        seatBase[s.seat] = nil
        if isValid(s.seat) then s.seat:remove() end
    end
    if s.hidx then sendUnreg(s.hidx) end
    if isValid(s.holo) then s.holo:remove() end
end


local function gunSeat(base, s)
    if not isValid(base) or guns[base] ~= s or isValid(s.seat) then return end
    s.tries = s.tries + 1
    if s.tries > 20 then return end
    if not prop.canSpawn() then timer.simple(0.5, function() gunSeat(base, s) end) return end
    local ok, seat = pcall(prop.createSeat, base:localToWorld(s.seatPos), base:getAngles() + Angle(0, -90, 0), SEAT_MODEL, true)
    if not ok or not isValid(seat) then timer.simple(1, function() gunSeat(base, s) end) return end
    s.seat = seat
    seatBase[seat] = base
    if SEAT_HIDDEN then pcall(seat.setNoDraw, seat, true) end
end

local function placeGun(it, pos, ang, lvl)
    local base, err, rest = placeMesh(it, pos, ang, (lvl > 0 and it.mountCol) and it.mountCol[lvl] or nil)
    if not base then return nil, err end
    local g, geo = GUN_STATS[it.gun], GUN_GEO[it.gun]
    local s = { it = it, g = g, geo = geo, yaw = 0, pitch = 0, ammo = g.mag, heat = 0, nextFire = 0, tries = 0, shots = 0,
                pivot = gunPivot(it.gun, lvl), seatPos = gunSeatPos(it.gun, lvl), lvl = lvl }
    if hologram.canSpawn() then
        local h = hologram.create(base:localToWorld(s.pivot), base:getAngles(), HM .. "box.mdl")
        if h then
            pcall(h.setColor, h, it.partColor or it.color or C_GUN)
            h:setParent(base)
            s.holo, s.hidx = h, h:entIndex()
        end
    end
    guns[base] = s
    if g.mortar then
        s.pitch, s.mpitch = -45, 45
        if isValid(s.holo) then pcall(s.holo.setLocalAngles, s.holo, Angle(-45, 0, 0)) end
    end
    if s.seatPos then timer.simple(0.35, function() gunSeat(base, s) end) end
    return base, nil, rest
end

-- hidden extra collision props (convexes 11+), spawned one by one (prop burst 4/s)

local function approach(cur, target, step)
    if math.abs(target - cur) <= step then return target end
    return cur + (target > cur and step or -step)
end

local function afterShot(h, g, s, now)
    if g.bolt then
        timer.simple(0.45, function() if isValid(h) then snd(h, g.bolt, 70, 100, 0.9) end end)
    end
    if s.ammo <= 0 then
        s.reloadAt = now + g.reload
        snd(h, g.rel1, 70, 100, 1)
    end
end

local function gunShoot(base, s, now)
    local g, h = s.g, s.holo
    if game.canFireBullets and not game.canFireBullets(g.dmg, 1) then return end   -- SF bullet burst budget
    local ml = s.geo.muzzle
    if g.twin then
        s.side = not s.side
        if s.side then ml = s.geo.muzzle2 end
    end
    local muzzle = h:localToWorld(ml)
    local dir = h:getForward()
    local hitPos
    local ok = pcall(fireBullets, muzzle, dir, g.dmg, 1, g.force, 30000, V(g.spread, g.spread, 0), 0, base,
        function(att, tr) hitPos = tr.HitPos end)
    if not ok then s.nextFire = now + 0.25 return end
    s.ammo = s.ammo - 1
    s.heat = s.heat + g.heatPer
    s.nextFire = now + g.rate
    s.shots = s.shots + 1
    snd(h, g.snd, g.lvl, g.pitch + math.random(-4, 4), 1)
    pcall(effect.create, "MuzzleFlash", { origin = muzzle, angles = h:getAngles(), flags = g.flash }, true)
    if s.shots % g.tracerEvery == 0 then
        pcall(effect.create, g.tracer, { start = muzzle, origin = hitPos or (muzzle + dir * 8000), scale = 9000 }, true)
    end
    if not g.blast then
        pcall(effect.create, "RifleShellEject", { origin = h:localToWorld(V(-4, 3, 2)), angles = h:getAngles() + Angle(0, 90, 0) }, true)
    end
    -- explosive rounds (AT gun / flak): blast where the round hit (not right at the muzzle)
    if g.blast and hitPos and hitPos:getDistance(muzzle) > 120 then
        if g.blast.small then
            pcall(game.blastDamage, hitPos, g.blast.r, g.blast.d)
            pcall(effect.create, "Explosion", { origin = hitPos, magnitude = 1, scale = 0.5, radius = g.blast.r, flags = 4 }, true)
        else
            explodeAt(hitPos, g.blast.r, g.blast.d, false, true)
        end
    end
    afterShot(h, g, s, now)
end

local function aimAt(base, s, worldPos, dt)
    local g = s.g
    local d = base:worldToLocal(worldPos) - s.pivot
    local ty = clamp(math.deg(math.atan2(d.y, d.x)), -g.yaw, g.yaw)
    local tp = clamp(-math.deg(math.atan2(d.z, math.sqrt(d.x * d.x + d.y * d.y))), -g.up, g.down)
    return ty, tp
end
local function turnTo(s, ty, tp, dt)
    local g, h = s.g, s.holo
    local ny, np = approach(s.yaw, ty, g.turn * dt), approach(s.pitch, tp, g.turn * dt)
    if math.abs(ny - s.yaw) > 0.01 or math.abs(np - s.pitch) > 0.01 then
        s.yaw, s.pitch = ny, np
        h:setLocalAngles(Angle(s.pitch, s.yaw, 0))
    end
end

-- mortar: fixed tube angle (gunner picks it), muzzle speed solved for the target point (from the drone camera)
local function mortarFire(base, s, target, pitch, now)
    local g, h = s.g, s.holo
    if not isValid(h) or s.reloadAt or s.ammo <= 0 or now < s.nextFire then return end
    pitch = clamp(pitch, 20, 85)
    local piv = base:localToWorld(s.pivot)
    local D = V(target.x - piv.x, target.y - piv.y, 0):getLength()
    if D < MORTAR_MIN or D > MORTAR_MAX + 60 then return end
    local dir = mortarSolve(piv, target, pitch, g.mortar.g)
    if not dir then return end
    local muzzle = piv + dir * s.geo.muzzle.x
    local dir2, v0 = mortarSolve(muzzle, target, pitch, g.mortar.g)
    if not dir2 then return end
    local ld = base:worldToLocal(piv + dir2) - base:worldToLocal(piv)
    s.yaw, s.pitch = math.deg(math.atan2(ld.y, ld.x)), -pitch
    pcall(h.setLocalAngles, h, Angle(s.pitch, s.yaw, 0))
    spawnShell(muzzle, dir2 * v0, g.mortar, base, s.op)
    s.ammo = s.ammo - 1
    s.nextFire = now + g.rate
    snd(h, g.snd, g.lvl, g.pitch + math.random(-4, 4), 1)
    pcall(effect.create, "MuzzleFlash", { origin = muzzle, angles = dir2:getAngle(), flags = g.flash }, true)
    pcall(effect.create, "ThumperDust", { origin = base:getPos(), scale = 120 }, true)
    afterShot(h, g, s, now)
end

local function gunTick(base, s, now, dt)
    local g, h = s.g, s.holo
    local op = isValid(s.seat) and s.seat:getDriver() or nil
    if not isValid(op) then op = nil end
    setOperator(s, op)

    -- cooling / reload progress run even without a gunner
    s.heat = math.max(0, s.heat - g.cool * dt)
    if s.over and s.heat <= 0.35 then s.over = false end
    if s.reloadAt and now >= s.reloadAt then
        s.reloadAt = nil
        s.ammo = g.mag
        snd(h, g.rel2, 70, 100, 1)
    end
    if not op or not isValid(h) then return end

    if g.mortar then                                                -- tube follows the drone crosshair
        if s.mtarget then
            local d = base:worldToLocal(s.mtarget) - s.pivot
            turnTo(s, math.deg(math.atan2(d.y, d.x)), -(s.mpitch or 45), dt)
        end
        s.aPrev, s.rPrev = true, true
    else

    -- aim at what the gunner looks at (limited arc + turn speed)
    local eye, aim = op:getShootPos(), op:getAimVector()
    local tr = trace.line(eye, eye + aim * 30000, { op, base, s.seat }, MASK.SHOT)
    local d = base:worldToLocal(tr.HitPos) - s.pivot
    if d:getLength() < 60 then d = base:worldToLocal(base:getPos() + aim) end
    local ty = clamp(math.deg(math.atan2(d.y, d.x)), -g.yaw, g.yaw)
    local tp = clamp(-math.deg(math.atan2(d.z, math.sqrt(d.x * d.x + d.y * d.y))), -g.up, g.down)
    turnTo(s, ty, tp, dt)

    -- reload (R)
    local r = op:keyDown(IN_KEY.RELOAD)
    if r and not s.rPrev and not s.reloadAt and s.ammo < g.mag then
        s.reloadAt = now + g.reload
        snd(h, g.rel1, 70, 100, 1)
    end
    s.rPrev = r

    -- fire (LMB)
    local a = op:keyDown(IN_KEY.ATTACK)
    local pressed = a and not s.aPrev
    s.aPrev = a
    if a and (g.auto or pressed) and now >= s.nextFire and not s.reloadAt and not s.over then
        if s.ammo > 0 then
            gunShoot(base, s, now)
            if s.heat >= 1 then
                s.over = true
                snd(h, "ambient/gas/steam2.wav", 75, 110, 0.8)
            end
        elseif pressed then
            snd(h, "weapons/pistol/pistol_empty.wav", 65, 100, 1)
        end
    end
    end

    -- HUD state for the gunner, 10 Hz
    if now >= (s.nextSend or 0) then
        s.nextSend = now + 0.1
        net.start("it_gst")
        net.writeUInt(clamp(s.ammo, 0, 255), 8)
        net.writeUInt(clamp(math.floor(s.heat * 255), 0, 255), 8)
        net.writeUInt((s.reloadAt and 1 or 0) + (s.over and 2 or 0) + ((now < s.nextFire) and 4 or 0), 3)
        net.writeUInt(s.reloadAt and clamp(math.floor((1 - (s.reloadAt - now) / g.reload) * 255), 0, 255) or 0, 8)
        net.send(op)
    end
end

local lastGunT = timer.curtime()
hook.add("think", "it_guns", function()
    local now = timer.curtime()
    local dt = math.min(now - lastGunT, 0.2)
    lastGunT = now
    for base, s in pairs(guns) do
        if isValid(base) then gunTick(base, s, now, dt) end
    end
    shellTick(now, dt)
end)

-- mortar drone camera: client -> server (camera position for PVS, tube angle, crosshair point)
local function mortarOf(ply)
    for base, s in pairs(guns) do
        if s.op == ply and s.g.mortar and isValid(base) then return base, s end
    end
end
local camNext = {}
net.receive("it_mcam", function(len, ply)
    local cam, pitch, tgt = net.readVector(), net.readUInt(7), net.readVector()
    local now = timer.curtime()
    if (camNext[ply] or 0) > now then return end
    camNext[ply] = now + 0.08
    local base, s = mortarOf(ply)
    if not s then return end
    local bp = base:getPos()
    local d = V(cam.x - bp.x, cam.y - bp.y, 0)
    if d:getLength() > MORTAR_MAX + 300 then cam = bp + d:getNormalized() * MORTAR_MAX + V(0, 0, cam.z - bp.z) end
    s.cam, s.mpitch, s.mtarget = cam, clamp(pitch, 20, 85), tgt
    if not isValid(s.camHolo) and hologram.canSpawn() then
        s.camHolo = hologram.create(cam, Angle(), HM .. "box.mdl", V(0.1, 0.1, 0.1))
        if s.camHolo then pcall(s.camHolo.setNoDraw, s.camHolo, true) end
    end
    if isValid(s.camHolo) then
        pcall(s.camHolo.setPos, s.camHolo, cam)
        if not s.viewSet then s.viewSet = pcall(ply.setViewEntity, ply, s.camHolo) end   -- server sends what the camera sees
    end
end)
net.receive("it_mfire", function(len, ply)
    local tgt, pitch = net.readVector(), net.readUInt(7)
    local base, s = mortarOf(ply)
    if s then mortarFire(base, s, tgt, pitch, timer.curtime()) end
end)


S.sendMount = sendMount
S.setOperator = setOperator
S.destroyGun = destroyGun
S.gunSeat = gunSeat
S.placeGun = placeGun

return true
