--@client
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

-- ---------------- GUNNER (any player sitting in one of the guns) ----------------
local gunner = nil       -- {hidx, it, g, geo}
local gst = { ammo = 0, heat = 0, flags = 0, prog = 0 }
local zoomLvl, z2Prev = 0, false

net.receive("it_mnt", function()
    zoomLvl = 0
    if net.readBool() then
        local hidx, ii = net.readUInt(16), net.readUInt(8)
        local it = ITEMS[ii]
        if it and it.gun then
            gunner = { hidx = hidx, it = it, g = GUN_STATS[it.gun], geo = GUN_GEO[it.gun] }
            gst.ammo, gst.heat, gst.flags, gst.prog = gunner.g.mag, 0, 0, 0
            return
        end
    end
    gunner = nil
end)
net.receive("it_gst", function()
    gst.ammo = net.readUInt(8)
    gst.heat = net.readUInt(8) / 255
    gst.flags = net.readUInt(3)
    gst.prog = net.readUInt(8) / 255
end)

local function gunHolo()
    if not gunner or gunner.hidx == 0 then return nil end
    local h = entity(gunner.hidx)
    return isValid(h) and h or nil
end

local hiddenHolo = nil
local function hideGunModel(h)
    if hiddenHolo == h then return end
    if isValid(hiddenHolo) then pcall(hiddenHolo.setNoDraw, hiddenHolo, false) end
    hiddenHolo = h
    if isValid(h) then pcall(h.setNoDraw, h, true) end
end
local function gunnerThink()
    if gunner and not me:inVehicle() then gunner = nil zoomLvl = 0 end
    if not gunner then hideGunModel(nil) return end
    local z = me:keyDown(IN_KEY.ATTACK2)
    if z and not z2Prev then zoomLvl = (zoomLvl + 1) % (#gunner.g.zoom + 1) end
    z2Prev = z
    -- sniper: the rifle model (scope tube) is hidden for you while zoomed, so it never blocks the view
    hideGunModel((gunner.it.gun == "sniper" and zoomLvl > 0) and gunHolo() or nil)
end
C.think[#C.think + 1] = gunnerThink

-- ---------------- MORTAR (idea from "Mortar Predictive"): top-down drone camera ----------------
-- WASD fly, Space up, Alt / Ctrl down, Shift fast; wheel / RMB / R = tube angle; LMB = fire at the crosshair
local drawMortarHud, bracket
do
local mcam = nil
local mdmg = {}
net.receive("it_mdmg", function()
    local p, a = net.readVector(), net.readUInt(12)
    mdmg[#mdmg + 1] = { pos = p, a = a, t = timer.realtime() }
end)
local function mortarAim()
    local tr = trace.line(mcam.pos, mcam.pos - V(0, 0, 60000), { me }, MASK.SHOT)
    return tr.HitPos
end
local function edge(key, field)
    local d = me:keyDown(key)
    local hit = d and not mcam[field]
    mcam[field] = d
    return hit
end
local function mortarThink()
    local h = gunHolo()
    if not h or not gunner.g.mortar then mcam = nil return end
    local now = timer.realtime()
    if not mcam then
        mcam = { pos = h:getPos() + V(0, 0, MORTAR_CAM_H), yaw = h:getAngles().y, pitch = 45, last = now, nextSend = 0,
                 a = true, r2 = true, rl = true, impacts = {} }
    end
    local dt = math.min(now - mcam.last, 0.1)
    mcam.last = now
    local ya = Angle(0, mcam.yaw, 0)
    local f, r = ya:getForward(), ya:getRight()
    local mv = V(0, 0, 0)
    if me:keyDown(IN_KEY.FORWARD) then mv = mv + f end
    if me:keyDown(IN_KEY.BACK) then mv = mv - f end
    if me:keyDown(IN_KEY.MOVERIGHT) then mv = mv + r end
    if me:keyDown(IN_KEY.MOVELEFT) then mv = mv - r end
    local up = 0
    if me:keyDown(IN_KEY.JUMP) then up = 1 end
    if me:keyDown(IN_KEY.WALK) or me:keyDown(IN_KEY.DUCK) then up = -1 end
    local gz = mortarAim().z
    local hgt = math.max(mcam.pos.z - gz, 50)
    local speed = clamp(hgt * 1.1, 350, 5000) * (me:keyDown(IN_KEY.SPEED) and 3 or 1)
    if mv:getLength() > 0 then mv = mv:getNormalized() end
    local np = mcam.pos + (mv * speed + V(0, 0, up * speed * 0.8)) * dt
    local base = h:getPos()
    local d = V(np.x - base.x, np.y - base.y, 0)
    if d:getLength() > MORTAR_MAX then np = V(base.x, base.y, np.z) + d:getNormalized() * MORTAR_MAX end
    np = V(np.x, np.y, clamp(np.z, gz + 120, gz + 8000))
    local tr = trace.line(mcam.pos, np, { me }, MASK.SOLID_BRUSHONLY)
    if tr.Hit and not tr.StartSolid then np = tr.HitPos + tr.HitNormal * 24 end
    mcam.pos = np

    if edge(IN_KEY.ATTACK2, "r2") then mcam.pitch = (mcam.pitch >= 85) and 20 or (mcam.pitch + 5) end
    if edge(IN_KEY.RELOAD, "rl") then mcam.pitch = (mcam.pitch <= 20) and 85 or (mcam.pitch - 5) end
    local tgt = mortarAim()
    if edge(IN_KEY.ATTACK, "a") then
        local _, _, t, D = mortarSolve(base, tgt, mcam.pitch, gunner.g.mortar.g)
        if t and D >= MORTAR_MIN and D <= MORTAR_MAX and bit.band(gst.flags, 1) == 0 and gst.ammo > 0 then
            net.start("it_mfire")
            net.writeVector(tgt)
            net.writeUInt(mcam.pitch, 7)
            net.send()
            mcam.impacts[#mcam.impacts + 1] = { pos = tgt, t = now + t }
        end
    end
    if now >= mcam.nextSend then                                     -- camera -> server (PVS + tube aim), 10 Hz
        mcam.nextSend = now + 0.1
        net.start("it_mcam")
        net.writeVector(mcam.pos)
        net.writeUInt(mcam.pitch, 7)
        net.writeVector(tgt)
        net.send()
    end
end
C.think[#C.think + 1] = mortarThink
pcall(hook.add, "mousewheeled", "it_mwheel", function(delta)
    if mcam then mcam.pitch = clamp(mcam.pitch + (delta > 0 and 5 or -5), 20, 85) end
end)

function bracket(x, y, w, h, l)
    render.drawRect(x, y, l, 2) render.drawRect(x, y, 2, l)
    render.drawRect(x + w - l, y, l, 2) render.drawRect(x + w - 2, y, 2, l)
    render.drawRect(x, y + h - 2, l, 2) render.drawRect(x, y + h - l, 2, l)
    render.drawRect(x + w - l, y + h - 2, l, 2) render.drawRect(x + w - 2, y + h - l, 2, l)
end
function drawMortarHud(W, H, h)
    if not mcam then return end
    local now = timer.realtime()
    local g = gunner.g
    local base = h:getPos()
    local tgt = mortarAim()
    local _, v0, t, D = mortarSolve(base, tgt, mcam.pitch, g.mortar.g)
    D = D or 0
    local reloading = bit.band(gst.flags, 1) ~= 0
    local status, sc
    if D < MORTAR_MIN then status, sc = "TOO CLOSE", Color(255, 70, 60)
    elseif D > MORTAR_MAX then status, sc = "OUT OF RANGE", Color(255, 70, 60)
    elseif not t then status, sc = "TOO HIGH - raise the angle", Color(255, 150, 60)
    elseif reloading then status, sc = "RELOADING", Color(255, 210, 90)
    else status, sc = "READY", Color(120, 255, 120) end
    render.setMaterial()
    -- drone frame
    render.setRGBA(255, 255, 255, 120)
    bracket(40, 40, W - 80, H - 80, 60)
    if math.floor(now * 2) % 2 == 0 then render.setRGBA(255, 40, 40, 230) render.drawFilledCircle(70, 72, 7) end
    render.setFont(fMed)
    render.setRGBA(255, 255, 255, 230)
    render.drawSimpleText(86, 72, "MORTAR DRONE", TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
    -- crosshair + blast radius on the ground
    local cx, cy = W / 2, H / 2
    local sp, se = tgt:toScreen(), (tgt + V(g.mortar.r, 0, 0)):toScreen()
    local rp = math.max(8, math.sqrt((se.x - sp.x) ^ 2 + (se.y - sp.y) ^ 2))
    render.setRGBA(sc.r, sc.g, sc.b, 230)
    render.drawCircle(cx, cy, rp) render.drawCircle(cx, cy, rp + 1)
    render.drawRect(cx - 30, cy, 22, 2) render.drawRect(cx + 9, cy, 22, 2)
    render.drawRect(cx, cy - 30, 2, 22) render.drawRect(cx, cy + 9, 2, 22)
    render.drawFilledCircle(cx + 1, cy + 1, 2)
    render.setFont(fMed)
    render.drawSimpleText(cx, cy + rp + 22, status, TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
    -- mortar position
    local mp = base:toScreen()
    if mp.visible then
        render.setRGBA(120, 200, 255, 220)
        render.drawRect(mp.x - 6, mp.y - 6, 12, 2) render.drawRect(mp.x - 6, mp.y + 4, 12, 2)
        render.drawRect(mp.x - 6, mp.y - 6, 2, 12) render.drawRect(mp.x + 4, mp.y - 6, 2, 12)
        render.setFont(fTiny)
        render.drawSimpleText(mp.x, mp.y - 16, "MORTAR", TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
    end
    -- players / NPCs the camera can see
    if MORTAR_MARKERS then
        if now >= (mcam.markT or 0) then
            mcam.markT = now + 0.3
            local list = {}
            local ok, found = pcall(find.inSphere, tgt, 3500)
            if ok and found then
                for _, e in ipairs(found) do
                    if isValid(e) and e ~= me and ((e:isPlayer() and e:isAlive()) or e:isNPC()) then
                        local c = e:obbCenterW()
                        local vt = trace.line(mcam.pos, c, { me }, MASK.SHOT)
                        if not vt.Hit or vt.Entity == e or vt.Fraction > 0.98 then list[#list + 1] = e end
                    end
                end
            end
            mcam.marks = list
        end
        render.setFont(fTiny)
        for _, e in ipairs(mcam.marks or {}) do
            if isValid(e) then
                local c = e:obbCenterW()
                local s2 = c:toScreen()
                if s2.visible then
                    local veh = e:isPlayer() and e:inVehicle()
                    if veh then render.setRGBA(255, 160, 40, 240) else render.setRGBA(255, 60, 60, 240) end
                    local k = 7
                    render.drawRect(s2.x - k, s2.y - k, 2 * k, 2) render.drawRect(s2.x - k, s2.y + k - 2, 2 * k, 2)
                    render.drawRect(s2.x - k, s2.y - k, 2, 2 * k) render.drawRect(s2.x + k - 2, s2.y - k, 2, 2 * k)
                    render.drawSimpleText(s2.x, s2.y - 16, string.format("%.0f m", V(c.x - base.x, c.y - base.y, 0):getLength() * 0.01905),
                        TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
                end
            end
        end
    end
    -- shells in the air: impact point + countdown
    render.setFont(fSmall)
    for i = #mcam.impacts, 1, -1 do
        local im = mcam.impacts[i]
        if now > im.t + 0.5 then table.remove(mcam.impacts, i)
        else
            local s2 = im.pos:toScreen()
            if s2.visible then
                render.setRGBA(255, 220, 90, 200)
                render.drawCircle(s2.x, s2.y, 10)
                render.drawSimpleText(s2.x, s2.y - 20, string.format("%.1f", math.max(0, im.t - now)), TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
            end
        end
    end
    -- damage numbers
    render.setFont(fMed)
    for i = #mdmg, 1, -1 do
        local dn = mdmg[i]
        local age = now - dn.t
        if age > 2.5 then table.remove(mdmg, i)
        else
            local s2 = (dn.pos + V(0, 0, 30 + age * 40)):toScreen()
            if s2.visible then
                render.setRGBA(255, 80, 60, math.floor(255 * (1 - age / 2.5)))
                render.drawSimpleText(s2.x, s2.y, "-" .. dn.a, TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
            end
        end
    end
    -- info panel
    local x, y = 60, 110
    render.setRGBA(0, 0, 0, 150)
    render.drawRect(x, y, 260, 150)
    render.setFont(fSmall)
    render.setRGBA(255, 255, 255, 230)
    render.drawSimpleText(x + 12, y + 16, "ANGLE  " .. mcam.pitch .. " deg", TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
    render.drawSimpleText(x + 12, y + 38, string.format("RANGE  %.0f m", D * 0.01905), TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
    render.drawSimpleText(x + 12, y + 60, t and string.format("FLIGHT  %.1f s", t) or "FLIGHT  -", TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
    render.drawSimpleText(x + 12, y + 82, string.format("ALT  %.0f m", math.max(0, mcam.pos.z - tgt.z) * 0.01905), TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
    render.drawSimpleText(x + 12, y + 104, string.format("MAX  %.0f m   MIN  %.0f m", MORTAR_MAX * 0.01905, MORTAR_MIN * 0.01905), TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
    render.setRGBA(40, 40, 40, 255) render.drawRect(x + 12, y + 124, 236, 10)
    if reloading then render.setRGBA(230, 200, 90, 255) render.drawRect(x + 12, y + 124, 236 * gst.prog, 10)
    else render.setRGBA(120, 255, 120, 255) render.drawRect(x + 12, y + 124, 236, 10) end
    render.setRGBA(255, 255, 255, 200)
    render.drawSimpleText(W / 2, H - 70, "WASD fly   Space / Alt height   Shift fast   Wheel / RMB / R angle   LMB fire   E leave",
        TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
end

hook.add("calcview", "it_gunview", function(pos, ang, fov)
    if mcam and gunner then
        mcam.yaw = ang.y
        return { origin = mcam.pos, angles = Angle(90, ang.y, 0), fov = 90, drawviewer = true, zfar = 80000 }
    end
    if C.camViewEnt and not gunner then
        if isValid(C.camViewEnt) then
            return { origin = C.camViewEnt:localToWorld(V(12, 0, 45.5)), angles = ang, fov = 80, drawviewer = true }
        end
        C.camViewEnt = nil
    end
    local h = gunHolo()
    if not h or gunner.g.ownView then return end
    -- zoomed sniper: camera sits just in front of the scope lens -> no part of the model can block the view
    local eye = (gunner.it.gun == "sniper" and zoomLvl > 0) and V(15, 0, 4) or gunner.geo.eye
    return { origin = h:localToWorld(eye), angles = ang,
             fov = zoomLvl > 0 and gunner.g.zoom[zoomLvl] or fov, drawviewer = false }
end)

end
hook.add("adjustmousesensitivity", "it_gunsens", function()
    if gunner and zoomLvl > 0 then return gunner.g.zoom[zoomLvl] / 75 end
end)

local function tri2(a, b, c)
    render.drawPoly({ a, b, c })
    render.drawPoly({ a, c, b })   -- the other winding (DrawPoly culls one of them)
end
local function scopeOverlay(W, H)
    local cx, cy, R = W / 2, H / 2, H * 0.47
    render.setMaterial()
    render.setRGBA(0, 0, 0, 255)
    render.drawRect(0, 0, cx - R + 1, H)
    render.drawRect(cx + R - 1, 0, W - cx - R + 2, H)
    render.drawRect(cx - R, 0, R * 2, cy - R + 1)
    render.drawRect(cx - R, cy + R - 1, R * 2, H - cy - R + 2)
    local N = 12
    for q = 0, 3 do
        local sx, sy = (q == 0 or q == 3) and 1 or -1, (q < 2) and 1 or -1
        local corner = { x = cx + sx * R, y = cy + sy * R }
        for k = 0, N - 1 do
            local a1, a2 = k / N * math.pi / 2, (k + 1) / N * math.pi / 2
            tri2(corner, { x = cx + sx * R * math.cos(a1), y = cy + sy * R * math.sin(a1) },
                         { x = cx + sx * R * math.cos(a2), y = cy + sy * R * math.sin(a2) })
        end
    end
    -- reticle: thick outer posts + thin center cross + mil dots
    render.drawRect(cx - R, cy - 2, R - 40, 4)
    render.drawRect(cx + 40, cy - 2, R - 40, 4)
    render.drawRect(cx - 2, cy + 40, 4, R - 40)
    render.drawRect(cx - 2, cy - R, 4, R - 40)
    render.drawRect(cx - 40, cy, 80, 1)
    render.drawRect(cx, cy - 40, 1, 80)
    for k = 1, 4 do
        render.drawFilledCircle(cx + k * 9, cy, 1.6) render.drawFilledCircle(cx - k * 9, cy, 1.6)
        render.drawFilledCircle(cx, cy + k * 9, 1.6)
    end
end

hook.add("drawhud", "it_gunhud", function()
    local h = gunHolo()
    if not h then return end
    local W, H = render.getResolution()
    local g, geo = gunner.g, gunner.geo
    local mz = h:localToWorld(geo.muzzle)
    if g.mortar then drawMortarHud(W, H, h) return end
    local tr = trace.line(mz, mz + h:getForward() * 30000, { h }, MASK.SHOT)
    local sp = tr.HitPos:toScreen()
    local scoped = gunner.it.gun == "sniper" and zoomLvl > 0
    if scoped then scopeOverlay(W, H) end

    -- where the barrel really points (the gun lags behind your view a bit)
    if sp.visible then
        render.setMaterial()
        if scoped then
            render.setRGBA(255, 40, 40, 230)
            render.drawFilledCircle(sp.x, sp.y, 2.5)
        else
            local busy = bit.band(gst.flags, 3) ~= 0
            if busy then render.setRGBA(255, 90, 60, 230) else render.setRGBA(120, 255, 120, 230) end
            render.drawCircle(sp.x, sp.y, 9)
            render.drawRect(sp.x - 18, sp.y, 9, 1) render.drawRect(sp.x + 10, sp.y, 9, 1)
            render.drawRect(sp.x, sp.y - 18, 1, 9) render.drawRect(sp.x, sp.y + 10, 1, 9)
            render.drawFilledCircle(sp.x, sp.y, 1.5)
        end
    end

    -- panel
    local pw, ph = 380, 92
    local x, y = W / 2 - pw / 2, H - ph - 40
    render.setRGBA(0, 0, 0, 165)
    render.drawRect(x, y, pw, ph)
    render.setFont(fMed)
    render.setRGBA(170, 220, 130, 255)
    render.drawSimpleText(x + 12, y + 16, g.name .. (zoomLvl > 0 and ("  x" .. math.round(75 / g.zoom[zoomLvl], 1)) or ""), TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
    render.setRGBA(255, 255, 255, 230)
    render.drawSimpleText(x + pw - 12, y + 16, "AMMO " .. gst.ammo .. " / " .. g.mag, TEXT_ALIGN.RIGHT, TEXT_ALIGN.CENTER)
    render.setFont(fSmall)
    render.setRGBA(220, 220, 220, 220)
    render.drawSimpleText(x + pw - 12, y + 40, string.format("%.0f m", tr.HitPos:getDistance(mz) * 0.01905), TEXT_ALIGN.RIGHT, TEXT_ALIGN.CENTER)
    local bx, by, bw = x + 12, y + 34, 220
    local status
    if bit.band(gst.flags, 1) ~= 0 then
        status = "RELOADING"
        render.setRGBA(40, 40, 40, 255) render.drawRect(bx, by, bw, 10)
        render.setRGBA(230, 200, 90, 255) render.drawRect(bx, by, bw * gst.prog, 10)
    elseif g.heatPer > 0 then
        render.setRGBA(40, 40, 40, 255) render.drawRect(bx, by, bw, 10)
        local over = bit.band(gst.flags, 2) ~= 0
        render.setRGBA(255, math.floor(220 * (1 - gst.heat)), 50, 255) render.drawRect(bx, by, bw * math.min(gst.heat, 1), 10)
        if over then status = "OVERHEAT" end
    elseif bit.band(gst.flags, 4) ~= 0 then
        status = "BOLT"
    end
    if status then
        render.setRGBA(255, 120, 90, 255)
        render.drawSimpleText(bx + bw + 10, by + 5, status, TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
    end
    render.setRGBA(255, 255, 255, 200)
    render.drawSimpleText(x + 12, y + 70, "LMB fire   RMB zoom   R reload   E leave", TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
end)


return {
    isGunning = function() return gunner ~= nil end,
    bracket = bracket,
    tri2 = tri2,
}
