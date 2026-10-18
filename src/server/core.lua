--@server
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

local O = owner()
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

pcall(enableHud, O, true)

local function countObjs()
    local n = 0
    for e in pairs(objs) do if isValid(e) then n = n + 1 end end
    return n
end

local function sendState(msg)
    local p = S.pendingTrip and isValid(S.pendingTrip.prop) and S.pendingTrip or nil
    local c4 = 0
    for e, o in pairs(objs) do if isValid(e) and o.it.logic == "c4" then c4 = c4 + 1 end end
    net.start("it_state")
    net.writeBool(p ~= nil)
    if p then net.writeEntity(p.prop) net.writeVector(p.prop:localToWorld(p.la)) end
    net.writeUInt(math.min(countObjs(), 65535), 16)
    net.writeUInt(c4, 8)
    net.writeString(msg or "")
    net.send(O)
end

-- tell clients which mesh definition to put on an entity
-- def 255 = alias: a hidden extra collision prop that belongs to object "main"
local function sendReg(eidx, def, target, main)
    net.start("it_reg")
    net.writeUInt(eidx, 16)
    net.writeUInt(def, 8)
    if def == 255 then net.writeUInt(main or 0, 16) end
    if target then net.send(target) else net.send() end
end
local function sendUnreg(eidx)
    net.start("it_unreg")
    net.writeUInt(eidx, 16)
    net.send()
end

local function snd(ent, path, lvl, pitch, vol)
    if isValid(ent) then pcall(ent.emitSound, ent, path, lvl or 75, pitch or 100, vol or 1) end
end

local function explodeAt(pos, radius, damage, big, noProp)
    local done = false
    if USE_WIRE_EXPLOSIVE and not noProp and prop.canSpawn() then
        done = pcall(function()
            local ent = prop.createSent(pos, Angle(), "gmod_wire_explosive", true, {
                damage = damage, radius = radius, removeafter = true,
                Model = "models/bull/gates/logic_nano.mdl",
            })
            ent:setSolid(false)
            ent:setNoDraw(true)
            ent:getWirelink()["Detonate"] = 1
        end)
    end
    if not done then pcall(game.blastDamage, pos, radius, damage) end
    if big then pcall(effect.create, "HelicopterMegaBomb", { origin = pos }, true) end
    pcall(effect.create, "Explosion", { origin = pos, magnitude = big and 300 or 100, scale = big and 3 or 1.3, radius = radius }, true)
    local gtr = trace.line(pos + V(0, 0, 10), pos - V(0, 0, 150), nil, MASK.SOLID_BRUSHONLY)
    if gtr.Hit then pcall(effect.create, "ThumperDust", { origin = gtr.HitPos, scale = big and 700 or 250 }, true) end
end

-- ---------------- flying shells (mortar + artillery): simple ballistic sim ----------------
local shells, booms = S.shells, S.booms
local function spawnShell(pos, vel, sp, ignore, op)
    local sh = { pos = pos, vel = vel, sp = sp, ignore = ignore, born = timer.curtime(), op = op }
    if hologram.canSpawn() then
        local h = hologram.create(pos, upFrame(vel), HM .. "cylinder.mdl")
        if h then
            pcall(h.setSize, h, V(4, 4, 15))
            pcall(h.setColor, h, Color(60, 66, 52))
            pcall(h.setTrails, h, 28, 0, 4, "trails/smoke", Color(225, 225, 225))   -- white smoke trail
            sh.holo = h
        end
    end
    shells[#shells + 1] = sh
end
local function shellTick(now, dt)
    for i = #shells, 1, -1 do
        local sh = shells[i]
        local g = sh.sp.g
        local np = sh.pos + sh.vel * dt - V(0, 0, 0.5 * g * dt * dt)   -- exact ballistic step
        local nv = sh.vel - V(0, 0, g * dt)
        local tr = trace.line(sh.pos, np, sh.ignore and { sh.ignore } or nil, MASK.SHOT)
        local inSky = tr.HitSky or tr.StartSolid                   -- above the skybox: keep flying
        if (tr.Hit and not inSky) or now - sh.born > 40 then
            table.remove(shells, i)
            local hp = tr.HitPos + tr.HitNormal * 4
            local hh = sh.holo
            if isValid(hh) then                                     -- keep the holo a moment: trail fades, sound plays
                pcall(function() hh:setPos(hp) hh:setNoDraw(true) end)
                timer.simple(3, function() if isValid(hh) then hh:remove() end end)
            end
            if tr.Hit and not inSky then
                explodeAt(hp, sh.sp.r, sh.sp.d, sh.sp.big, true)
                snd(hh, "weapons/mortar/mortar_explode" .. math.random(1, 3) .. ".wav", 140, math.random(95, 105), 1)
                if sh.op then booms[#booms + 1] = { pos = hp, t = now, r = sh.sp.r, op = sh.op } end
            end
        else
            sh.pos, sh.vel = np, nv
            if isValid(sh.holo) then
                pcall(function() sh.holo:setPos(np) sh.holo:setAngles(upFrame(nv)) end)
                if not sh.whistled and nv.z < 0 then
                    local ahead = trace.line(np, np + nv * 1.2, nil, MASK.SOLID_BRUSHONLY)
                    if ahead.Hit and not ahead.StartSolid then
                        sh.whistled = true
                        snd(sh.holo, "weapons/mortar/mortar_shell_incomming1.wav", 140, math.random(95, 105), 1)
                    end
                end
            end
        end
    end
end

-- ---------------- manned guns: mount / unmount ----------------

local function unregister(e)
    local o = objs[e]
    if not o then return end
    objs[e] = nil
    if o.wire and isValid(o.wire) then o.wire:remove() end
    if o.anchor and isValid(o.anchor) then o.anchor:remove() end
    if o.extras then
        for _, x in ipairs(o.extras) do
            extraOf[x] = nil
            if isValid(x) then x:remove() end
        end
    end
    if S.destroyGun then S.destroyGun(e) end
    if o.eidx then sendUnreg(o.eidx) end
end

local function removeObj(e)
    unregister(e)
    if isValid(e) then e:remove() end
    sendState()
end

local BOOM = {
    at   = { r = 350, d = 600, big = true },
    ap   = { r = 140, d = 110 },
    trip = { r = 260, d = 200 },
    clay = { r = 180, d = 170, fwd = 70 },
    bounce = { r = 230, d = 160 },
    c4   = { r = 300, d = 350, big = true },
    laser = { r = 220, d = 190 },
    ied  = { r = 330, d = 360, big = true },
    timed = { r = 320, d = 330, big = true },
}

local function detonate(e)
    local o = objs[e]
    if not o or not isValid(e) then return end
    local b = BOOM[o.it.logic]
    if not b then removeObj(e) return end
    local pos = e:obbCenterW()
    if b.fwd then pos = pos + e:getForward() * b.fwd end
    removeObj(e)
    explodeAt(pos, b.r, b.d, b.big)
end

local function fuse(e, delay, sound)
    local o = objs[e]
    if not o or o.fuseAt then return end
    o.fuseAt = timer.curtime() + delay
    S.fused[#S.fused + 1] = e
    if sound then snd(e, sound, 80, 100, 1) end
    if o.wire and isValid(o.wire) then o.wire:remove() o.wire = nil end
end

-- ---------------- placement ----------------
local function placeMesh(it, pos, ang, colFn)
    local col = {}
    ;(colFn or it.col)(col)
    local convexes, rest = {}, {}                -- a prop holds 10 convexes, the rest -> hidden extra props
    for i, pr in ipairs(col) do
        local k = math.floor((i - 1) / 10)
        if k == 0 then
            convexes[#convexes + 1] = primPoints(pr)
        else
            rest[k] = rest[k] or {}
            rest[k][#rest[k] + 1] = primPoints(pr)
        end
    end
    local ok, p = pcall(prop.createCustom, pos, ang, convexes, true)
    if not ok or not isValid(p) then return nil, tostring(p) end
    -- the prop itself is invisible (alpha 0) for everyone: every client puts the mesh on it or on its
    -- own clientside hologram (meshes.lua). The RGB stays = the tint the clients copy.
    local c = it.color or Color(255, 255, 255)
    pcall(p.setColor, p, Color(c.r, c.g, c.b, 0))
    return p, nil, rest
end


local function spawnExtras(p, o, chunks)
    if not chunks or #chunks == 0 then return end
    o.extras = {}
    local function nextOne(i, tries)
        if not isValid(p) or objs[p] ~= o or i > #chunks then return end
        if not prop.canSpawn() then
            if tries < 40 then timer.simple(0.3, function() nextOne(i, tries + 1) end) end
            return
        end
        local ok, x = pcall(prop.createCustom, p:getPos(), p:getAngles(), chunks[i], true)
        if ok and isValid(x) then
            pcall(x.setNoDraw, x, true)
            o.extras[#o.extras + 1] = x
            extraOf[x] = p
            sendReg(x:entIndex(), 255, nil, o.eidx)
            timer.simple(0.27, function() nextOne(i + 1, 0) end)
        elseif tries < 10 then
            timer.simple(0.5, function() nextOne(i, tries + 1) end)
        else
            sendState("Extra collision failed: " .. string.sub(tostring(x), 1, 50))
        end
    end
    timer.simple(0.27, function() nextOne(1, 0) end)
end

-- trench grid cells covered by a piece (1 or 2x2)
local function trenchCells(pos, ang, size)
    if (size or 1) < 2 then return { pos } end
    local f, r, h = ang:getForward(), ang:getRight(), TRENCH_CELL / 2
    return { pos + f * h + r * h, pos + f * h - r * h, pos - f * h + r * h, pos - f * h - r * h }
end
local function trenchOverlaps(pos, ang, it)
    local mine, hit = trenchCells(pos, ang, it.size), {}
    for e, o in pairs(objs) do
        if isValid(e) and o.it.place == "trench" then
            local found = false
            for _, a in ipairs(trenchCells(e:getPos(), e:getAngles(), o.it.size)) do
                for _, b in ipairs(mine) do
                    if a:getDistance(b) < 40 then found = true end
                end
            end
            if found then hit[#hit + 1] = e end
        end
    end
    return hit
end

local function doPlace(it, pos, ang, normal, lvl, rep, opt)
    local now = timer.curtime()
    if now - S.lastPlace < PLACE_COOLDOWN * 0.8 then return end
    if MAX_OBJECTS > 0 and countObjs() >= MAX_OBJECTS then sendState("Object limit: " .. MAX_OBJECTS) return end
    if not prop.canSpawn() then sendState("Prop limit, wait") return end
    if pos:getDistance(O:getShootPos()) > PLACE_RANGE + 200 then sendState("Too far") return end
    if it.place == "trench" then
        local ov = trenchOverlaps(pos, ang, it)
        -- replacing an existing trench piece / adding a cover: same footprint -> remove the old one first
        if rep and rep > 0 and #ov == 1 and ov[1]:entIndex() == rep and (objs[ov[1]].it.size or 1) == (it.size or 1) then
            unregister(ov[1])
            ov[1]:remove()
        elseif #ov > 0 then
            sendState("Cell is taken") return
        end
    end
    if it.kind == "cover" or not (it.col or it.kind == "gun" or it.kind == "tripwire") then
        sendState("This item can't be placed") return
    end
    S.lastPlace = now

    if it.kind == "tripwire" then
        if S.pendingTrip then return end
        local ok, p = pcall(prop.create, pos + normal * 4, upFrame(normal), it.model, true)
        if not ok or not isValid(p) then sendState("Can't create grenade") return end
        local fix = nadeFix(p)
        local center = pos + normal * (fix.half + 0.3)
        local pp, pa = nadeTransform(fix, center, upFrame(normal))
        pcall(function() p:setPos(pp) p:setAngles(pa) end)
        local tr = trace.line(pos + normal * 2, pos - normal * 4, { p, O })
        if isValid(tr.Entity) and not tr.HitWorld then pcall(p.setParent, p, tr.Entity) end
        objs[p] = { it = it, n = normal, la = p:worldToLocal(center + normal * fix.half) }
        S.pendingTrip = { prop = p, la = objs[p].la, n = normal, born = now }
        snd(p, "weapons/slam/mine_mode.wav", 70, 110, 0.8)
        sendState()
        return
    end

    local p, err, rest
    if it.kind == "gun" then p, err, rest = S.placeGun(it, pos, ang, lvl) else p, err, rest = placeMesh(it, pos, ang) end
    if not p then sendState("Spawn failed: " .. string.sub(err or "?", 1, 60)) return end
    local trap = it.logic and BOOM[it.logic] ~= nil
    local o = { it = it, eidx = p:entIndex(), armAt = trap and (now + ARM_TIME) or nil,
                mdef = (it.kind == "gun" and lvl > 0 and it.mountDefs) and it.mountDefs[lvl] or it.mdef }
    objs[p] = o
    sendReg(o.eidx, o.mdef)
    spawnExtras(p, o, rest)
    local s = guns[p]
    if s and s.hidx then sendReg(s.hidx, it.gdef) end
    if it.logic == "laser" then                                -- red beam along the mine's up axis
        local a, up = p:getPos() + p:getUp() * 5, p:getUp()
        local tr = trace.line(a, a + up * LASER_RANGE, { p, O }, MASK.SHOT)
        o.beamLen = math.max(LASER_RANGE * tr.Fraction, 12)
        if hologram.canSpawn() then
            local w = hologram.create(a + up * (o.beamLen / 2), upFrame(up), HM .. "cylinder.mdl")
            if w then
                pcall(w.setSize, w, V(0.3, 0.3, o.beamLen))
                pcall(w.setColor, w, Color(255, 30, 20, 170))
                pcall(w.setMaterial, w, "models/debug/debugwhite")
                pcall(w.setParent, w, p)
                o.wire = w
            end
        end
    elseif it.logic == "timed" then
        local fuseT = (opt and opt >= 3) and math.min(opt, 300) or TIMED_FUSE     -- timer chosen with R on the client
        o.fuseAt, o.nextBeep, o.armAt = now + fuseT, now, nil
        S.fused[#S.fused + 1] = p
    end
    if it.logic == "alarm" or it.logic == "radar" then
        o.armAt = now + 1
        snd(p, "buttons/blip1.wav", 70, 120, 0.8)
    elseif it.logic == "timed" then
        snd(p, "weapons/c4/c4_plant.wav", 75, 100, 1)
    elseif trap then
        snd(p, "weapons/slam/mine_mode.wav", 70, 100, 0.7)
        timer.simple(ARM_TIME, function() if isValid(p) and objs[p] then snd(p, "buttons/blip1.wav", 65, 140, 0.6) end end)
    else
        snd(p, "physics/concrete/concrete_impact_soft" .. math.random(1, 3) .. ".wav", 70, 100, 0.7)
    end
    if o.armAt and S.armLater then S.armLater(p, o.armAt - timer.curtime()) end
    sendState()
end

local function stretchWire(b, hitNormal)
    local pt = S.pendingTrip
    if not pt or not isValid(pt.prop) then S.pendingTrip = nil sendState() return end
    local p = pt.prop
    local a = p:localToWorld(pt.la)
    local ok, len = wireOk(a, b, { p, O })
    if not ok then sendState(len > 600 and "Too long" or (len < 24 and "Too short" or "Something is in the way")) return end
    local o = objs[p]
    o.b = b
    o.armAt = timer.curtime() + 1.5
    if S.armLater then S.armLater(p, 1.5) end
    local dir = (b - a) / len
    if hologram.canSpawn() then
        local w = hologram.create((a + b) / 2, upFrame(dir), HM .. "cylinder.mdl")
        if w then w:setSize(V(0.35, 0.35, len)) w:setColor(Color(80, 80, 70)) w:setParent(p) o.wire = w end
    end
    if hologram.canSpawn() then
        local an = hologram.create(b + hitNormal * 1.5, upFrame(hitNormal), HM .. "cylinder.mdl")
        if an then an:setSize(V(0.8, 0.8, 3)) an:setColor(Color(120, 115, 100)) o.anchor = an end
    end
    S.pendingTrip = nil
    snd(p, "weapons/slam/mine_mode.wav", 70, 90, 0.8)
    sendState()
end

local function removeAimed()
    if S.pendingTrip then
        local p = S.pendingTrip.prop
        S.pendingTrip = nil
        if isValid(p) then removeObj(p) end
        sendState("Cancelled")
        return
    end
    local tr = aimTrace(O, PLACE_RANGE + 200)
    local e = tr.Entity
    if isValid(e) and seatBase[e] then e = seatBase[e] end
    if isValid(e) and extraOf[e] then e = extraOf[e] end
    if isValid(e) and objs[e] then
        if objs[e].fuseAt and objs[e].it.logic ~= "timed" then return end   -- timed charge can be defused
        snd(e, "buttons/lever7.wav", 70, 110, 0.8)
        removeObj(e)
        sendState("Removed")
    else
        sendState("Look at your object")
    end
end

local function clearAll()
    S.pendingTrip = nil
    for e in pairs(objs) do
        unregister(e)
        if isValid(e) then e:remove() end
    end
    for k in pairs(objs) do objs[k] = nil end      -- clear IN PLACE: guns/sensors hold this same table
    for i = #S.fused, 1, -1 do S.fused[i] = nil end
    sendState("All removed")
end

-- ---------------- commands ----------------
-- 1 place(item, pos, ang, normal) 2 wire(pos, normal) 3 remove 4 detonate 5 clear all
net.receive("it_cmd", function(len, ply)
    if ply ~= O then return end
    local act = net.readUInt(4)
    if act == 5 then clearAll() return end
    if act == 4 then
        local k = 0
        for e, o in pairs(objs) do
            if isValid(e) and o.it.logic == "c4" and not o.fuseAt then
                k = k + 1
                fuse(e, 0.05 + k * 0.08, "buttons/button17.wav")
            end
        end
        if k == 0 then sendState("No C4 placed") end
        return
    end
    if not holdsTool(O) then return end
    if act == 1 then
        local idx = net.readUInt(8)
        local pos, ang, n = net.readVector(), net.readAngle(), net.readVector()
        local lvl = net.readUInt(4)
        local rep = net.readUInt(16)
        local opt = net.readUInt(9)                                   -- timed charge: fuse seconds
        local it = ITEMS[idx]
        if it and it.kind ~= "cover" then
            if it.kind ~= "gun" or not it.mountDefs or lvl > #MOUNT_LEVELS then lvl = 0 end
            doPlace(it, pos, ang, n, lvl, rep, opt)
        end
    elseif act == 2 then
        local b, n = net.readVector(), net.readVector()
        stretchWire(b, n)
    elseif act == 3 then
        removeAimed()
    end
end)

-- rally flag: name + colour from the owner (E on the flag), the flag itself is tinted
net.receive("it_flag", function(len, ply)
    if ply ~= O then return end
    local idx = net.readUInt(16)
    local name = string.sub(net.readString(), 1, 20)
    local col = Color(net.readUInt(8), net.readUInt(8), net.readUInt(8))
    local e = entity(idx)
    local o = isValid(e) and objs[e]
    if not o or o.it.logic ~= "flag" then return end
    o.label, o.lcol = name, col
    pcall(e.setColor, e, Color(col.r, col.g, col.b, 0))     -- alpha 0: clients copy the RGB to the mesh
end)

-- ---------------- triggers ----------------

timer.simple(1, function() sendState() end)


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
