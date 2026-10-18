--@server
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

local VEH_PAT = { "vehicle", "glide", "lvs", "lfs", "simfphys", "tank", "wac", "apc" }
local function isVehicleLike(e)
    if seatBase[e] or extraOf[e] then return false end         -- our own gun seats / stairs
    if e:isPlayer() then
        local v = e:getVehicle()
        if isValid(v) and seatBase[v] then return false end
        return e:inVehicle()
    end
    if e:isVehicle() then return true end
    local c = e:getClass()
    for _, k in ipairs(VEH_PAT) do if string.find(c, k, 1, true) then return true end end
    if c == "prop_physics" or c == "starfall_prop" then
        if objs[e] then return false end
        local ok, m = pcall(function() return e:getPhysicsObject():getMass() end)
        return ok and m and m >= 500 and e:getVelocity():getLength() > 20
    end
    return false
end
local function isInfantry(e)
    if e:isPlayer() then return e:isAlive() and not e:inVehicle() and not (OWNER_SAFE and e == O) end
    return e:isNPC()
end
local function visible(a, e, self)
    local tr = trace.line(a, e:obbCenterW(), { self }, MASK.SHOT)
    return not tr.Hit or tr.Entity == e
end

-- artillery strike around a beacon
-- recon radar + motion alarm targets -> owner HUD
local radarPrev, radarTick = 0, 0
local function sendRadar(now)
    local pts, seen = {}, {}
    local function add(t)
        if not seen[t] and #pts < 24 then seen[t] = true pts[#pts + 1] = t:getPos() end
    end
    for _, e in ipairs(sensors) do
        local o = objs[e]
        if isValid(e) and o.armAt and now >= o.armAt then
            if o.it.logic == "radar" then
                for _, t in ipairs(find.inSphere(e:getPos(), RADAR_RANGE)) do
                    if isValid(t) and t ~= O and ((t:isPlayer() and t:isAlive()) or t:isNPC()) then add(t) end
                end
            elseif o.it.logic == "alarm" and o.alarmT and isValid(o.alarmT) and now < (o.alarmUntil or 0) then
                add(o.alarmT)
            end
        end
    end
    if #pts == 0 and radarPrev == 0 then return end
    radarPrev = #pts
    net.start("it_radar")
    net.writeUInt(#pts, 6)
    for _, v in ipairs(pts) do net.writeVector(v) end
    net.send(O)
end

timer.create("it_scan", 0.1, 0, function()
    local now = timer.curtime()
    radarTick = radarTick + 1
    if radarTick % 5 == 0 then sendRadar(now) end
    if pendingTrip and (not isValid(pendingTrip.prop) or now - pendingTrip.born > 60) then
        local p = pendingTrip.prop
        pendingTrip = nil
        if isValid(p) then removeObj(p) end
    end
    -- running fuses: a short dedicated list, exact timing
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
            local lg = o.it.logic
            local pos = e:getPos()
            if lg == "at" then
                for _, t in ipairs(find.inSphere(pos + e:getUp() * 20, 75)) do
                    if t ~= e and isValid(t) and isVehicleLike(t) then fuse(e, 0.05, "buttons/button16.wav") break end
                end
            elseif lg == "ap" then
                for _, t in ipairs(find.inSphere(pos, 42)) do
                    if isValid(t) and isInfantry(t) then fuse(e, 0.25, "buttons/button16.wav") break end
                end
            elseif lg == "bounce" then
                for _, t in ipairs(find.inSphere(pos, 64)) do
                    if isValid(t) and isInfantry(t) then
                        fuse(e, 0.45, "weapons/grenade/tick1.wav")
                        pcall(function()                                -- jumps up, explodes in the air
                            local ph = e:getPhysicsObject()
                            ph:enableMotion(true) ph:wake()
                            ph:setVelocity(e:getUp() * 270)
                        end)
                        break
                    end
                end
            elseif lg == "ied" then
                for _, t in ipairs(find.inSphere(pos + e:getUp() * 10, 58)) do
                    if t ~= e and isValid(t) and (isInfantry(t) or isVehicleLike(t)) then fuse(e, 0.15, "buttons/button16.wav") break end
                end
            elseif lg == "laser" and o.beamLen then
                local up = e:getUp()
                local a = e:getPos() + up * 5
                local filter = { e }
                if OWNER_SAFE then filter[#filter + 1] = O end
                local tr = trace.line(a, a + up * (o.beamLen - 2), filter, MASK.SHOT)
                local t = tr.Entity
                if tr.Hit and not tr.HitWorld and isValid(t) and not objs[t] and not extraOf[t] then
                    fuse(e, 0.12, "buttons/button16.wav")
                end
            elseif lg == "decoy" then                               -- fake gunfire bursts
                if now >= (o.nextDecoy or 0) then
                    local kinds = { { "weapons/ar2/fire1.wav", 0.1, 8 }, { "weapons/smg1/smg1_fire1.wav", 0.08, 10 },
                                    { "weapons/357/357_fire2.wav", 0.7, 3 }, { "weapons/pistol/pistol_fire2.wav", 0.28, 5 } }
                    local k = kinds[math.random(1, #kinds)]
                    local n = math.random(math.max(1, k[3] - 4), k[3])
                    o.nextDecoy = now + n * k[2] + math.rand(2, 6)
                    for j = 0, n - 1 do
                        timer.simple(j * k[2] * math.rand(0.85, 1.2), function()
                            if isValid(e) and objs[e] then snd(e, k[1], 100, math.random(94, 106), 1) end
                        end)
                    end
                end
            elseif lg == "alarm" then
                if now >= (o.nextAlarm or 0) then
                    local eye = pos + e:getUp() * 4
                    for _, t in ipairs(find.inSphere(pos, ALARM_RANGE)) do
                        if isValid(t) and t ~= O and isInfantry(t) and visible(eye, t, e) then
                            o.nextAlarm, o.alarmT, o.alarmUntil = now + 6, t, now + 4
                            snd(e, "ambient/alarms/klaxon1.wav", 100, 100, 1)
                            sendState("ALARM! Motion at a sensor")
                            break
                        end
                    end
                end
            elseif lg == "clay" then
                local fwd = e:getForward()
                for _, t in ipairs(find.inSphere(pos, 220)) do
                    if isValid(t) and isInfantry(t) then
                        local d = t:obbCenterW() - pos
                        if fwd:dot(d:getNormalized()) > 0.64 and visible(pos + V(0, 0, 8), t, e) then
                            fuse(e, 0.1, "buttons/button16.wav")
                            break
                        end
                    end
                end
            elseif lg == "trip" and o.b then
                local a = e:localToWorld(o.la)
                local d = o.b - a
                local len = d:getLength()
                if len > 650 then
                    fuse(e, 0.7, "weapons/grenade/tick1.wav")
                else
                    local filter = { e }
                    local par = e:getParent()
                    if isValid(par) then filter[#filter + 1] = par end
                    if OWNER_SAFE then filter[#filter + 1] = O end
                    local tr = trace.line(a, a + d * ((len - 3) / len), filter, MASK.SOLID)
                    if tr.Hit and not tr.HitWorld and isValid(tr.Entity) then
                        fuse(e, 0.7, "weapons/grenade/tick1.wav")
                        pcall(function()
                            e:setParent()
                            local ph = e:getPhysicsObject()
                            ph:enableMotion(true) ph:wake()
                            ph:setVelocity(o.n * 230 + V(0, 0, 120))
                        end)
                    end
                end
            end
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
end)

-- ---------------- manned guns: aim, fire, reload, heat ----------------

hook.add("EntityTakeDamage", "it_shoot", function(target, attacker, inflictor, amount)
    local o = objs[target]
    if SHOOTABLE and o and o.it.logic and BOOM[o.it.logic] and not o.fuseAt then fuse(target, 0.1) end
    -- mortar hit -> damage number for the mortar gunner
    if #booms > 0 and isValid(target) and (target:isPlayer() or target:isNPC()) and (amount or 0) > 0 then
        local now, c = timer.curtime(), target:obbCenterW()
        for i = #booms, 1, -1 do
            local b = booms[i]
            if now - b.t > 0.6 then
                table.remove(booms, i)
            elseif isValid(b.op) and c:getDistance(b.pos) < b.r + 90 then
                net.start("it_mdmg")
                net.writeVector(c)
                net.writeUInt(clamp(math.floor(amount + 0.5), 0, 4095), 12)
                net.send(b.op)
                break
            end
        end
    end
end)

hook.add("OnEntityCreated", "it_kill_bait", function(ent)
    if not isValid(ent) or ent:getClass() ~= "npc_grenade_bugbait" then return end
    if not isValid(O) or ent:getPos():getDistance(O:getShootPos()) > 200 then return end
    pcall(function() ent:remove() end)
end)

if HIDE_BUGBAIT then
    local hidden = setmetatable({}, { __mode = "k" })
    timer.create("it_hide_bait", 0.5, 0, function()
        if not holdsTool(O) then return end
        local w = O:getActiveWeapon()
        if hidden[w] then return end
        hidden[w] = true
        pcall(function() w:setNoDraw(true) end)
    end)
end

-- late joiners get the mesh registry
hook.add("ClientInitialized", "it_sync", function(ply)
    for e, o in pairs(objs) do
        if isValid(e) and o.eidx and o.mdef then
            sendReg(o.eidx, o.mdef, ply)
            local s = guns[e]
            if s and s.hidx then sendReg(s.hidx, o.it.gdef, ply) end
            for _, x in ipairs(o.extras or {}) do
                if isValid(x) then sendReg(x:entIndex(), 255, ply, o.eidx) end
            end
        end
    end
end)


return true
