--@client
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
local MOUNT_TRENCH, MOUNT_FRONT = IT.MOUNT_TRENCH, IT.MOUNT_FRONT
local M = require("src/client/meshes.lua")
local meshes, bounds, getMat = M.meshes, M.bounds, M.getMat

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
    fuse = CC.TIMED_FUSE,       -- timed charge timer (R / Shift+R)
}
local FUSES = { 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 300 }
B.FUSES = FUSES


net.receive("it_state", function()
    local has = net.readBool()
    B.pendingProp, B.pendingStart = nil, nil
    if has then
        net.readEntity(function(e) if isValid(e) then B.pendingProp = e end end)
        B.pendingStart = net.readVector()
    end
    B.objCount = net.readUInt(16)
    B.c4Count = net.readUInt(8)
    local m = net.readString()
    if m ~= "" then B.msgText, B.msgUntil = m, timer.realtime() + 2.5 end
end)

local function say(m) B.msgText, B.msgUntil = m, timer.realtime() + 2.5 end

local function pressedOnce(key)
    local isMouse = key >= MOUSE.MOUSE1 and key <= MOUSE.MOUSE5
    local down = isMouse and input.isMouseDown(key) or input.isKeyDown(key)
    local first = down and not B.keyPrev[key]
    B.keyPrev[key] = down
    return first, down
end

local function setMenu(open)
    B.menuOpen = open
    pcall(input.enableCursor, open)
    if not open then B.waitRelease = true end
end

-- toggled by the bind AND by the raw key: after clicking in the menu the game panel takes
-- keyboard focus and the "+menu" bind is not fired anymore, the raw key still is
local lastToggle = 0
local function toggleMenu()
    local t = timer.realtime()
    if t - lastToggle < 0.25 then return end
    lastToggle = t
    setMenu(not B.menuOpen)
end

hook.add("think", "it_menukey", function()
    local q = pressedOnce(KEY_MENU)
    if not C.holding or C.flagEdit then return end
    if q then toggleMenu() end
end)

-- block the bugbait attack + use Q for our menu
hook.add("inputbindpressed", "it_binds", function(bind)
    if C.flagEdit then return true end          -- typing a flag name: no movement, no binds
    if not C.holding then return end
    local b = string.lower(bind)
    if string.find(b, "invnext", 1, true) or string.find(b, "invprev", 1, true) or string.find(b, "slot", 1, true) then
        B.selectorUntil = timer.realtime() + SELECTOR_WINDOW
        return
    end
    if b == KEY_MENU_BIND then
        toggleMenu()
        return true
    end
    if BLOCK_BUGBAIT and string.find(b, "+attack", 1, true) then
        if timer.realtime() < B.selectorUntil and not B.menuOpen then B.selectorUntil = 0 return end
        return true
    end
end)

-- ghost holograms (item body + gun part + tripwire)
local ghost = hologram.create(V(), Angle(), HM .. "box.mdl")
local ghostGun = hologram.create(V(), Angle(), HM .. "box.mdl")
local ghostWire = hologram.create(V(), Angle(), HM .. "cylinder.mdl")
if ghost then ghost:setNoDraw(true) end
if ghostGun then ghostGun:setNoDraw(true) end
if ghostWire then ghostWire:setNoDraw(true) end
local ghostItem = nil
local ghostFix = nil

local function meshOnHolo(h, di, matKey)
    if not meshes[di] then return false end
    h:setModel(HM .. "box.mdl")
    h:setMesh(meshes[di])
    local mat = getMat(matKey)
    if mat then h:setMeshMaterial(mat) end
    local b = bounds[di]
    h:setRenderBounds(b[1], b[2])
    return true
end

local ghostKey = nil
local function setGhostItem(it, lvl)
    lvl = lvl or 0
    local key = it.idx * 8 + lvl
    if not ghost or ghostKey == key then return end
    ghostItem, ghostKey = it, key
    ghostFix = nil
    pcall(function()
        if it.mdef then
            local di = (lvl > 0 and it.mountDefs and it.mountDefs[lvl]) or it.mdef
            if not meshOnHolo(ghost, di, it.mat) then ghostItem, ghostKey = nil, nil end      -- mesh not built yet, retry
            if it.gdef and ghostGun and not meshOnHolo(ghostGun, it.gdef, "metal") then ghostItem, ghostKey = nil, nil end
        else
            ghost:setMesh(nil)
            ghost:setModel(it.model)
            if it.kind == "tripwire" then ghostFix = nadeFix(ghost) end
        end
    end)
end

local function snapGrid(v, g) return math.round(v / g) * g end

-- trench grid cells covered by a piece (1 cell or 2x2 shelter, centre on a grid corner)
local function cellsOf(pos, ang, size)
    if (size or 1) < 2 then return { pos } end
    local f, r, h = ang:getForward(), ang:getRight(), TRENCH_CELL / 2
    return { pos + f * h + r * h, pos + f * h - r * h, pos - f * h + r * h, pos - f * h - r * h }
end
-- your trench pieces that overlap these cells -> list of { e, it }
local function trenchOverlaps(pos, ang, size)
    local mine, hit = cellsOf(pos, ang, size), {}
    for idx, r in pairs(C.reg) do
        if r.it and r.it.place == "trench" then
            local e = entity(idx)
            if isValid(e) then
                local found = false
                for _, a in ipairs(cellsOf(e:getPos(), e:getAngles(), r.it.size)) do
                    for _, b in ipairs(mine) do
                        if (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 < 1600 and math.abs(a.z - b.z) < 100 then found = true end
                    end
                end
                if found then hit[#hit + 1] = { e = e, it = r.it } end
            end
        end
    end
    return hit
end

-- prop grid frame: aligned to your nearest grid object (so walls line up), else the world grid
local function propFrame(hit)
    local best, bd = nil, 300
    for idx, r in pairs(C.reg) do
        if r.it and r.it.grid then
            local e = entity(idx)
            if isValid(e) then
                local ep = e:getPos()
                local d = math.sqrt((ep.x - hit.x) ^ 2 + (ep.y - hit.y) ^ 2)
                if d < bd and math.abs(ep.z - hit.z) < 120 then best, bd = e, d end
            end
        end
    end
    if best then return best:getPos(), best:getAngles().y, true end
    return V(0, 0, 0), 0, false
end
local function snapAngle(a, step) return math.round(a / step) * step end

local function groundAt(p)
    local tr = trace.line(p + V(0, 0, 80), p - V(0, 0, 400), { me }, MASK.SOLID)
    return tr.Hit and tr.HitPos or nil
end

-- stackable item aimed at another stackable object -> snap exactly on top of it
local function stackTarget(tr, it)
    if not it.stack then return nil end
    local e, tit = C.regOf(tr.Entity)
    if not e or not tit.stack then return nil end
    return e, tit
end

-- gun aimed at one of your trenches / fortifications -> mount B.plan: fills p.pos / p.ang / p.lvl, returns true
--   trench / shelter: post next to the wall you look towards, barrel just over the parapet
--   walls (bags, hesco, logs, crates, T-wall, nest, pillbox...): behind the wall on your side, post height = wall + 12
--   watchtower: on the deck, post over the railing
local function mountPlan(it, tr, eyeYaw, p)
    local te, tit = C.regOf(tr.Entity)
    if not te then return false end
    local mortar = it.gun == "mortar"
    local ta = te:getAngles()
    if tit.place == "trench" then
        if mortar then return false end
        if not tit.walls then
            if tit.cover == "closed" then
                p.ok, p.reason = false, "Closed - no firing slits"
                p.pos, p.ang = tr.HitPos, Angle(0, eyeYaw, 0)
                return true
            end
            return false
        end
        local k = math.round(((eyeYaw - ta.y) % 360) / 90) % 4          -- 0 +X, 1 +Y, 2 -X, 3 -Y
        local d = Angle(0, k * 90, 0):getForward()
        local side = V(-d.y, d.x, 0)
        local lp = te:worldToLocal(tr.HitPos)
        local along = clamp(lp:dot(side), -(tit.span - 30), tit.span - 30)
        local lpos = d * (tit.inner - MOUNT_FRONT) + side * along
        p.pos = te:localToWorld(V(lpos.x, lpos.y, 0))
        p.ang = Angle(0, ta.y + k * 90, 0)
        p.normal = te:getUp()
        p.lvl, p.mountName = MOUNT_TRENCH, "TRENCH MOUNT - faces the wall you look at"
        if not tit.walls[({ "px", "py", "nx", "ny" })[k + 1]] then p.ok, p.reason = false, "No trench wall that way" end
        return true
    end
    local m = tit.mnt
    if not m then return false end
    if m.deck then
        local lp = te:worldToLocal(tr.HitPos)
        if lp.z < m.deck - 10 then return false end
        p.pos = te:localToWorld(V(clamp(lp.x, -m.half, m.half), clamp(lp.y, -m.half, m.half), m.deck))
        p.ang = Angle(0, eyeYaw, 0)
        p.normal = te:getUp()
        p.lvl = mortar and 0 or mountLevelFor(m.P)
        p.mountName = "TOWER DECK"
        return true
    end
    local lp, le = te:worldToLocal(tr.HitPos), te:worldToLocal(me:getShootPos())
    local best, bs, ba
    for _, f in ipairs(m.faces) do
        local ax = V(-f.d.y, f.d.x, 0)
        local along = clamp((lp.x - f.o.x) * ax.x + (lp.y - f.o.y) * ax.y, -f.span, f.span)
        local qx, qy = f.o.x + ax.x * along, f.o.y + ax.y * along
        local score = math.sqrt((lp.x - qx) ^ 2 + (lp.y - qy) ^ 2)
        if (le.x - f.o.x) * f.d.x + (le.y - f.o.y) * f.d.y <= 0 then score = score + 1000 end   -- you are not on that side
        if not best or score < bs then best, bs, ba = f, score, along end
    end
    if not best then return false end
    local ax = V(-best.d.y, best.d.x, 0)
    local P0 = m.P or (m.top + 12)
    local function at(back)
        local lpos = best.o + best.d * (best.half + back) + ax * ba
        local wp = te:localToWorld(V(lpos.x, lpos.y, 0))
        local topZ = te:localToWorld(V(lpos.x, lpos.y, P0)).z
        local g = trace.line(V(wp.x, wp.y, topZ), V(wp.x, wp.y, topZ - 400), { te, me }, MASK.SOLID)
        local gz = g.Hit and g.HitPos.z or wp.z
        return V(wp.x, wp.y, gz), topZ - gz
    end
    local pos, P = at(14)
    local lvl = mortar and 0 or mountLevelFor(P)
    if lvl == 0 then pos = at(30) end
    p.pos, p.lvl = pos, lvl
    p.ang = Angle(0, ta.y + math.deg(math.atan2(-best.d.y, -best.d.x)), 0)
    p.normal = V(0, 0, 1)
    p.mountName = lvl > 0 and ("WALL MOUNT - post " .. MOUNT_LEVELS[lvl]) or "BEHIND COVER"
    if not mortar and P > MOUNT_LEVELS[#MOUNT_LEVELS] + 14 then p.ok, p.reason = false, "Too high for a gun" end
    return true
end

local function computePlan(it)
    local eyeYaw = me:getEyeAngles().y
    if it.kind == "tripwire" and isValid(B.pendingProp) and B.pendingStart then
        local tr = aimTrace(me, PLACE_RANGE + 600, { B.pendingProp })
        local ok, len = wireOk(B.pendingStart, tr.HitPos, { B.pendingProp, me })
        ok = ok and not badSurface(tr)
        return { wire = true, ok = ok, a = B.pendingStart, b = tr.HitPos, normal = tr.HitNormal, len = len,
                 reason = ok and nil or (len > 600 and "Too long" or "Can't hook the wire here") }
    end
    local tr = aimTrace(me, PLACE_RANGE)
    if not tr.Hit or tr.HitSky then return { ok = false, reason = "Aim at a surface" } end
    if it.kind == "cover" then                       -- swap a placed trench piece for its covered version
        local te, tit = C.regOf(tr.Entity)
        if not te or tit.place ~= "trench" then return { ok = false, reason = "Aim at your trench piece" } end
        local v = TRENCH_VAR[tit.shape] and TRENCH_VAR[tit.shape][it.cover]
        if not v then return { ok = false, reason = "This piece can't get a cover" } end
        return { ok = v ~= tit, reason = (v == tit) and "Already like this" or nil, pos = te:getPos(), ang = te:getAngles(),
                 normal = te:getUp(), replace = te:entIndex(), show = v }
    end
    local n = tr.HitNormal
    local p = { ok = true, normal = n, pos = tr.HitPos }
    if badSurface(tr) then p.ok, p.reason = false, "Not on players / vehicles" end
    if MAX_OBJECTS > 0 and B.objCount >= MAX_OBJECTS then p.ok, p.reason = false, "Object limit" end

    if it.kind == "gun" and mountPlan(it, tr, eyeYaw, p) then return p end

    if it.place == "surface" then
        p.ang = surfaceAngle(n, eyeYaw + 180 + B.rot)
    elseif it.place == "upright" then
        local te, tit = stackTarget(tr, it)
        if te then
            local ta = te:getAngles()
            p.pos = te:localToWorld(V(0, 0, tit.stack))
            p.ang = Angle(0, ta.y + B.rot, 0)
            p.normal = te:getUp()
            p.stack = true
            return p
        end
        if n.z < 0.6 then p.ok, p.reason = false, "Needs flat ground" end
        local pos = tr.HitPos
        local face = eyeYaw + (it.faceAway and 0 or 180)
        if B.gridOn and it.grid then
            -- snap position to the grid of the nearest object, yaw: 90 deg steps towards you + R (45)
            local fo, fy, aligned = propFrame(pos)
            local G = PROP_GRIDS[B.gridIdx]
            local fa = Angle(0, fy, 0)
            local lp = worldToLocal(pos, Angle(), fo, fa)
            local wp = localToWorld(V(snapGrid(lp.x, G), snapGrid(lp.y, G), 0), Angle(), fo, fa)
            local g = groundAt(V(wp.x, wp.y, pos.z))
            pos = g or V(wp.x, wp.y, pos.z)
            p.ang = Angle(0, fy + snapAngle(face - fy, 90) + B.rot, 0)
            p.grid = { o = fo, yaw = fy, g = G, aligned = aligned }
        else
            p.ang = Angle(0, face + B.rot, 0)
        end
        p.pos = pos
    elseif it.place == "trench" then
        -- aiming at one of your trenches: take its grid (so you can continue / change old trenches)
        local hitE, hit = C.regOf(tr.Entity)
        if hitE and hit.place == "trench" then
            local ey = hitE:getAngles().y
            local ep = cellsOf(hitE:getPos(), hitE:getAngles(), hit.size)[1]      -- a cell centre
            local aligned = false
            if B.trenchOrigin then
                local lp = worldToLocal(ep, Angle(), B.trenchOrigin, Angle(0, B.trenchYaw, 0))
                aligned = math.abs(lp.x - snapGrid(lp.x, TRENCH_CELL)) < 4 and math.abs(lp.y - snapGrid(lp.y, TRENCH_CELL)) < 4
                    and math.abs(math.angleDifference(ey, snapAngle(ey - B.trenchYaw, 90) + B.trenchYaw)) < 2
            end
            if not aligned then
                B.trenchOrigin, B.trenchYaw = ep, ey
                say("Trench grid taken from the trench")
            end
            n = V(0, 0, 1)
        end
        if n.z < 0.7 then p.ok, p.reason = false, "Needs flat ground" end
        if not B.trenchOrigin then
            p.ang = Angle(0, B.trenchYaw, 0)
        else
            local ga = Angle(0, B.trenchYaw, 0)
            local lp = worldToLocal(tr.HitPos, Angle(), B.trenchOrigin, ga)
            local h2 = (it.size == 2) and TRENCH_CELL / 2 or 0             -- 2x2: centre on a grid corner
            local cx, cy = snapGrid(lp.x - h2, TRENCH_CELL) + h2, snapGrid(lp.y - h2, TRENCH_CELL) + h2
            local wp = localToWorld(V(cx, cy, 0), Angle(), B.trenchOrigin, ga)
            local g = groundAt(V(wp.x, wp.y, tr.HitPos.z))
            p.pos = g or V(wp.x, wp.y, tr.HitPos.z)
            p.ang = Angle(0, B.trenchYaw + B.trenchRot * 90, 0)
            p.cell = { cx, cy }
            local ov = trenchOverlaps(p.pos, p.ang, it.size)
            local old, oit = ov[1] and ov[1].e, ov[1] and ov[1].it
            if #ov == 1 and (oit.size or 1) == (it.size or 1)
                and (old:getPos().x - p.pos.x) ^ 2 + (old:getPos().y - p.pos.y) ^ 2 < 900 then
                -- REPLACE the piece in this cell (keeps the exact position)
                p.pos = old:getPos()
                p.replace = old:entIndex()
                if oit == it and math.abs(math.angleDifference(old:getAngles().y, p.ang.y)) < 2 then
                    p.ok, p.reason = false, "Same piece - R to turn / pick another"
                end
            elseif #ov > 0 then
                p.ok, p.reason = false, "Cells taken (remove the pieces first)"
            end
        end
    end
    return p
end

local function sendPlace(it, p)
    net.start("it_cmd")
    net.writeUInt(1, 4)
    net.writeUInt(it.idx, 8)
    net.writeVector(p.pos)
    net.writeAngle(p.ang or Angle())
    net.writeVector(p.normal or V(0, 0, 1))
    net.writeUInt(p.lvl or 0, 4)
    net.writeUInt(p.replace or 0, 16)
    net.writeUInt(it.logic == "timed" and B.fuse or 0, 9)
    net.send()
end
local function sendSimple(act)
    net.start("it_cmd")
    net.writeUInt(act, 4)
    net.send()
end

-- hud.lua calls this after its own cursor UI (flag editor) closes
function B.uiClosed() B.waitRelease = true end

local function okColor(ok, a) return ok and Color(80, 255, 80, a) or Color(255, 60, 60, a) end
local function hideGhosts()
    if ghost then ghost:setNoDraw(true) end
    if ghostGun then ghostGun:setNoDraw(true) end
    if ghostWire then ghostWire:setNoDraw(true) end
end

hook.add("think", "it_input", function()
    local has = C.holding
    if not has then
        C.camViewEnt, B.camIdx = nil, 0
        if B.menuOpen then setMenu(false) end
        hideGhosts()
        B.plan = nil
        return
    end
    local lmb, lmbDown = pressedOnce(MOUSE.MOUSE1)
    local rmb = pressedOnce(MOUSE.MOUSE2)
    local rotP = pressedOnce(KEY_ROTATE)
    local gridP = pressedOnce(KEY_GRID)
    local detP = pressedOnce(KEY_DETONATE)
    local camP = pressedOnce(KEY_CAM)
    if B.waitRelease then
        if not lmbDown then B.waitRelease = false end
        lmb = false
    end
    if B.menuOpen or C.flagEdit or timer.realtime() < B.selectorUntil then
        hideGhosts()
        return
    end

    local shift = input.isShiftDown()
    if rotP then
        if B.selected.place == "trench" then
            if B.trenchOrigin then B.trenchRot = (B.trenchRot + (shift and -1 or 1)) % 4
            else B.trenchYaw = B.trenchYaw + (shift and -ROT_FINE or ROT_FINE) end
        elseif B.selected.logic == "timed" then        -- timed charge: R = timer
            local k = 1
            for i, f in ipairs(FUSES) do if f <= B.fuse then k = i end end
            k = shift and (k - 2) % #FUSES + 1 or k % #FUSES + 1
            B.fuse = FUSES[k]
            say("Timer " .. B.fuse .. " s")
        else
            B.rot = B.rot + (shift and -ROT_STEP or ROT_STEP)
        end
    end
    if gridP then
        if shift and B.selected.place == "trench" then B.trenchOrigin = nil B.trenchRot = 0 say("Trench grid reset")
        elseif shift then
            B.gridIdx = B.gridIdx % #PROP_GRIDS + 1
            B.gridOn = true
            say("Grid " .. PROP_GRIDS[B.gridIdx])
        else B.gridOn = not B.gridOn say(B.gridOn and "Grid ON" or "Grid OFF") end
    end
    if detP then sendSimple(4) end
    if camP then                                     -- periscope cameras: next / off
        local list = {}
        for idx, r in pairs(C.reg) do
            if r.it and r.it.logic == "cam" and isValid(entity(idx)) then list[#list + 1] = idx end
        end
        table.sort(list)
        if #list == 0 then say("No cameras placed") B.camIdx = 0
        else B.camIdx = (B.camIdx + 1) % (#list + 1) end
        C.camViewEnt = B.camIdx > 0 and entity(list[B.camIdx]) or nil
        B.camCount = #list
    end
    if rmb then sendSimple(3) end

    B.plan = computePlan(B.selected)
    local showIt = B.plan.show or B.selected
    if showIt.kind ~= "cover" then setGhostItem(showIt, B.plan.lvl) end

    -- ghost visuals
    if B.plan.wire then
        if ghost then ghost:setNoDraw(true) end
        if ghostGun then ghostGun:setNoDraw(true) end
        if ghostWire and B.plan.len and B.plan.len > 1 then
            ghostWire:setNoDraw(false)
            ghostWire:setPos((B.plan.a + B.plan.b) / 2)
            ghostWire:setAngles(upFrame(B.plan.b - B.plan.a))
            ghostWire:setSize(V(0.6, 0.6, B.plan.len))
            ghostWire:setColor(okColor(B.plan.ok, 200))
        end
    else
        if ghostWire then ghostWire:setNoDraw(true) end
        if ghost and B.plan.pos and ghostItem == showIt then
            ghost:setNoDraw(false)
            if B.selected.kind == "tripwire" and ghostFix then
                local pp, pa = nadeTransform(ghostFix, B.plan.pos + B.plan.normal * (ghostFix.half + 0.3), upFrame(B.plan.normal))
                ghost:setPos(pp) ghost:setAngles(pa)
            else
                ghost:setPos(B.plan.pos)
                ghost:setAngles(B.plan.ang)
            end
            ghost:setColor(okColor(B.plan.ok, 130))
            if ghostGun then
                if B.selected.kind == "gun" then
                    local gp, ga = localToWorld(gunPivot(B.selected.gun, B.plan.lvl), Angle(), B.plan.pos, B.plan.ang)
                    ghostGun:setNoDraw(false)
                    ghostGun:setPos(gp) ghostGun:setAngles(ga)
                    ghostGun:setColor(okColor(B.plan.ok, 130))
                else
                    ghostGun:setNoDraw(true)
                end
            end
        else
            if ghost then ghost:setNoDraw(true) end
            if ghostGun then ghostGun:setNoDraw(true) end
        end
    end

    if lmb then
        local nowR = timer.realtime()
        if nowR - B.lastPlaceCl < PLACE_COOLDOWN then return end
        if not B.plan.ok then say(B.plan.reason or "Not allowed") return end
        B.lastPlaceCl = nowR
        if B.plan.wire then
            net.start("it_cmd")
            net.writeUInt(2, 4)
            net.writeVector(B.plan.b)
            net.writeVector(B.plan.normal)
            net.send()
        else
            if B.selected.place == "trench" and not B.trenchOrigin then
                B.trenchOrigin = B.plan.pos
                B.trenchRot = 0
            end
            sendPlace(B.plan.show or B.selected, B.plan)
        end
    end
end)

-- trench grid lines around the ghost
hook.add("postdrawtranslucentrenderables", "it_grid", function(depth, sky)
    if sky or not B.plan or not B.plan.pos or not C.holding or B.menuOpen then return end
    if B.plan.grid then
        -- prop grid: 9 x 9 lines around the ghost, in the frame of the aligned object
        local gd = B.plan.grid
        local fa = Angle(0, gd.yaw, 0)
        local c = worldToLocal(B.plan.pos, Angle(), gd.o, fa)
        local G, N = gd.g, 4
        local z = B.plan.pos.z + 1
        if gd.aligned then render.setColor(Color(120, 220, 255, 120)) else render.setColor(Color(255, 255, 255, 70)) end
        for i = -N, N do
            local a1 = localToWorld(V(c.x + i * G, c.y - N * G, 0), Angle(), gd.o, fa)
            local a2 = localToWorld(V(c.x + i * G, c.y + N * G, 0), Angle(), gd.o, fa)
            local b1 = localToWorld(V(c.x - N * G, c.y + i * G, 0), Angle(), gd.o, fa)
            local b2 = localToWorld(V(c.x + N * G, c.y + i * G, 0), Angle(), gd.o, fa)
            render.draw3DLine(V(a1.x, a1.y, z), V(a2.x, a2.y, z), false)
            render.draw3DLine(V(b1.x, b1.y, z), V(b2.x, b2.y, z), false)
        end
        return
    end
    if B.selected.place ~= "trench" or not B.trenchOrigin or not B.plan.cell then return end
    local ga = Angle(0, B.trenchYaw, 0)
    local h = TRENCH_CELL / 2
    local z = B.plan.pos.z + 2
    render.setColor(Color(255, 220, 120, 140))
    for i = -2, 2 do
        for j = -2, 2 do
            local cx, cy = B.plan.cell[1] + i * TRENCH_CELL, B.plan.cell[2] + j * TRENCH_CELL
            local c1 = localToWorld(V(cx - h, cy - h, 0), Angle(), B.trenchOrigin, ga)
            local c2 = localToWorld(V(cx + h, cy - h, 0), Angle(), B.trenchOrigin, ga)
            local c3 = localToWorld(V(cx + h, cy + h, 0), Angle(), B.trenchOrigin, ga)
            c1, c2, c3 = V(c1.x, c1.y, z), V(c2.x, c2.y, z), V(c3.x, c3.y, z)
            render.draw3DLine(c1, c2, false)
            render.draw3DLine(c2, c3, false)
        end
    end
end)


B.setMenu = setMenu
B.sendSimple = sendSimple
B.sendPlace = sendPlace

return B
