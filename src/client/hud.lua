--@client
-- Infantry Tool :: HUD and menu (owner only)
-- The spawn menu, the tool panel, rally flags, radar markers and the
-- viewmodel hider. Reads the owner state from build.lua, never writes it.

local C = require("src/client/core.lua")
local CC = require("src/config.lua")
local IT = require("src/items.lua")
local B = require("src/client/build.lua")
local G = require("src/client/guns.lua")

local V, Color = Vector, Color
local MAX_OBJECTS, PANEL_Y_FRAC, PROP_GRIDS = CC.MAX_OBJECTS, CC.PANEL_Y_FRAC, CC.PROP_GRIDS
local ROT_FINE, HIDE_BUGBAIT = CC.ROT_FINE, CC.HIDE_BUGBAIT
local CAT_NAMES, ITEMS = IT.CAT_NAMES, IT.ITEMS
local me = C.me
local fTitle, fMed, fSmall, fCard, fTiny = C.fTitle, C.fMed, C.fSmall, C.fCard, C.fTiny
local setMenu, sendSimple = B.setMenu, B.sendSimple
local bracket, tri2 = G.bracket, G.tri2

-- ---------------- HUD + menu ----------------
local drawMenu
do
local CARD_W, CARD_H, CARD_GAP, CARD_COLS = 181, 64, 9, 4
local mousePrev, rmousePrev = false, false

local function inside(mx, my, x, y, w, h) return mx >= x and mx <= x + w and my >= y and my <= y + h end

function drawMenu(W, H)
    local mx, my = input.getCursorPos()
    local down = input.isMouseDown(MOUSE.MOUSE1)
    local click = down and not mousePrev
    mousePrev = down
    local rdown = input.isMouseDown(MOUSE.MOUSE2)
    local rclick = rdown and not rmousePrev
    rmousePrev = rdown

    local pw, ph = 800, 640
    local px, py = (W - pw) / 2, (H - ph) / 2
    -- RMB anywhere or LMB outside the panel closes the menu
    if rclick or (click and not inside(mx, my, px, py, pw, ph)) then
        setMenu(false)
        return
    end
    render.setRGBA(10, 14, 10, 225)
    render.drawRectFast(px, py, pw, ph)
    render.setRGBA(120, 160, 90, 255)
    render.drawRectFast(px, py, pw, 3)
    render.setFont(fTitle)
    render.setRGBA(200, 230, 170, 255)
    render.drawSimpleText(px + 20, py + 30, "INFANTRY TOOL", TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
    render.setFont(fSmall)
    render.setRGBA(200, 200, 200, 200)
    render.drawSimpleText(px + pw - 20, py + 30, B.objCount .. (MAX_OBJECTS > 0 and (" / " .. MAX_OBJECTS) or "") .. " objects", TEXT_ALIGN.RIGHT, TEXT_ALIGN.CENTER)

    -- tabs
    for i, name in ipairs(CAT_NAMES) do
        local tw = math.floor((pw - 40 - (#CAT_NAMES - 1) * 6) / #CAT_NAMES)
        local tx, ty, th = px + 20 + (i - 1) * (tw + 6), py + 58, 36
        local hov = inside(mx, my, tx, ty, tw, th)
        if B.menuTab == i then render.setRGBA(120, 160, 90, 255) elseif hov then render.setRGBA(70, 90, 60, 255) else render.setRGBA(40, 50, 36, 255) end
        render.drawRectFast(tx, ty, tw, th)
        render.setFont(fMed)
        render.setRGBA(255, 255, 255, 255)
        render.drawSimpleText(tx + tw / 2, ty + th / 2, name, TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
        if click and hov then B.menuTab = i end
    end

    -- item cards (4 columns)
    local col, row = 0, 0
    local cx0, cy0 = px + 20, py + 108
    for _, it in ipairs(ITEMS) do
        if it.cat == B.menuTab and not it.hidden then
            local x = cx0 + col * (CARD_W + CARD_GAP)
            local y = cy0 + row * (CARD_H + CARD_GAP)
            local hov = inside(mx, my, x, y, CARD_W, CARD_H)
            if B.selected == it then render.setRGBA(90, 130, 70, 255) elseif hov then render.setRGBA(60, 75, 52, 255) else render.setRGBA(32, 40, 30, 255) end
            render.drawRectFast(x, y, CARD_W, CARD_H)
            local c = it.color or Color(160, 160, 160)
            render.setRGBA(c.r, c.g, c.b, 255)
            render.drawRectFast(x + 7, y + 8, 8, CARD_H - 16)
            render.setFont(fCard)
            render.setRGBA(255, 255, 255, 255)
            render.drawSimpleText(x + 22, y + 21, it.name, TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
            render.setFont(fTiny)
            render.setRGBA(190, 200, 180, 220)
            render.drawSimpleText(x + 22, y + 45, it.desc or "", TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
            if click and hov then
                B.selected = it
                B.rot = 0
                if it.place == "trench" and not B.trenchOrigin then
                    B.trenchYaw = math.round(me:getEyeAngles().y / ROT_FINE) * ROT_FINE
                end
                setMenu(false)
                return
            end
            col = col + 1
            if col >= CARD_COLS then col, row = 0, row + 1 end
        end
    end

    -- bottom buttons
    local bx, by = px + 20, py + ph - 56
    local hovC = inside(mx, my, bx, by, 180, 38)
    render.setRGBA(hovC and 190 or 140, 40, 40, 255)
    render.drawRectFast(bx, by, 180, 38)
    render.setFont(fMed)
    render.setRGBA(255, 255, 255, 255)
    render.drawSimpleText(bx + 90, by + 19, "CLEAR ALL", TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
    if click and hovC then sendSimple(5) end

    local hx = px + pw - 200
    local hovX = inside(mx, my, hx, by, 180, 38)
    render.setRGBA(hovX and 90 or 60, hovX and 90 or 60, hovX and 90 or 60, 255)
    render.drawRectFast(hx, by, 180, 38)
    render.setRGBA(255, 255, 255, 255)
    render.drawSimpleText(hx + 90, by + 19, "CLOSE", TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
    render.setFont(fSmall)
    render.setRGBA(200, 200, 200, 180)
    render.drawSimpleText(px + pw / 2, by + 19, "Q / RMB / click outside - close", TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
    if click and hovX then setMenu(false) end
end
end

-- ---------------- rally flags ----------------
-- waypoint markers (always on, also without the tool) + E on a flag = name / colour editor
do
local FLAG_NAMES = { "RALLY", "ALPHA", "BRAVO", "CHARLIE", "DELTA", "HQ", "AMMO", "MEDIC" }
local FLAG_COLS = {
    Color(255, 70, 60), Color(255, 160, 40), Color(250, 230, 60), Color(90, 220, 80),
    Color(60, 200, 230), Color(70, 110, 255), Color(190, 90, 255), Color(240, 240, 240),
}
local NAME_MAX = 16
local flagInfo = {}            -- ent index -> {name, col}
C.flagInfo = flagInfo
local ed = nil                 -- open editor {idx, name, col}
local keyPrev, mPrev, rPrev, usePrev = {}, true, true, false

-- typed characters: digits, letters, minus, space
local CHARS = {}
for i = 0, 9 do CHARS[i + 1] = tostring(i) end
for i = 0, 25 do CHARS[11 + i] = string.char(65 + i) end
CHARS[62], CHARS[49], CHARS[65] = "-", "-", " "
local K_ENTER, K_PADENTER, K_BACK, K_ESC = 64, 51, 66, 70

local function info(idx)
    return flagInfo[idx] or { name = "RALLY", col = FLAG_COLS[1] }
end

local function closeEditor(save)
    if not ed then return end
    if save then
        local name = string.trim(ed.name)
        if name == "" then name = "RALLY" end
        flagInfo[ed.idx] = { name = name, col = ed.col }
        net.start("it_flag")
        net.writeUInt(ed.idx, 16)
        net.writeString(name)
        net.writeUInt(ed.col.r, 8) net.writeUInt(ed.col.g, 8) net.writeUInt(ed.col.b, 8)
        net.send()
    end
    ed = nil
    C.flagEdit = nil
    pcall(input.enableCursor, false)
    B.uiClosed()
end

local function openEditor(idx)
    local fi = info(idx)
    ed = { idx = idx, name = fi.name, col = fi.col }
    C.flagEdit = true
    keyPrev, mPrev, rPrev = {}, true, true          -- the E / mouse already held must not count
    for code in pairs(CHARS) do keyPrev[code] = input.isKeyDown(code) end
    pcall(input.enableCursor, true)
end

-- the flag the player looks at: direct hit, else the flag closest to the aim line
local function aimedFlag()
    local eye, dir = me:getShootPos(), me:getAimVector()
    local tr = me:getEyeTrace()
    if tr and isValid(tr.Entity) and tr.HitPos:getDistance(eye) < 220 then
        local idx = tr.Entity:entIndex()
        local r = C.reg[idx]
        if r and r.it and r.it.logic == "flag" then return idx end
    end
    local best, bestD = nil, 0.97
    for idx, r in pairs(C.reg) do
        if r.it and r.it.logic == "flag" then
            local e = entity(idx)
            if isValid(e) then
                local p = e:localToWorld(V(0, 0, 60))
                local d = p - eye
                local L = d:getLength()
                if L < 220 then
                    local dot = d:getNormalized():dot(dir)
                    if dot > bestD then best, bestD = idx, dot end
                end
            end
        end
    end
    return best
end

hook.add("think", "it_flagedit", function()
    local use = me:keyDown(IN_KEY.USE)
    local useEdge = use and not usePrev
    usePrev = use
    if not ed then
        if useEdge and not B.menuOpen and not G.isGunning() and not me:inVehicle() then
            local idx = aimedFlag()
            if idx then openEditor(idx) end
        end
        return
    end
    if not isValid(entity(ed.idx)) or not C.reg[ed.idx] then closeEditor(false) return end
    for code, ch in pairs(CHARS) do
        local d = input.isKeyDown(code)
        if d and not keyPrev[code] and #ed.name < NAME_MAX then ed.name = ed.name .. ch end
        keyPrev[code] = d
    end
    local function edge(code)
        local d = input.isKeyDown(code)
        local e = d and not keyPrev[code]
        keyPrev[code] = d
        return e
    end
    if edge(K_BACK) then ed.name = string.sub(ed.name, 1, -2) end
    if edge(K_ENTER) or edge(K_PADENTER) then closeEditor(true) return end
    if edge(K_ESC) then closeEditor(false) return end
end)

local function inside(mx, my, x, y, w, h) return mx >= x and mx <= x + w and my >= y and my <= y + h end

local function drawEditor(W, H)
    local mx, my = input.getCursorPos()
    local down = input.isMouseDown(MOUSE.MOUSE1)
    local click = down and not mPrev
    mPrev = down
    local rdown = input.isMouseDown(MOUSE.MOUSE2)
    local rclick = rdown and not rPrev
    rPrev = rdown
    if rclick then closeEditor(false) return end

    local pw, ph = 460, 330
    local px, py = (W - pw) / 2, (H - ph) / 2
    render.setRGBA(10, 14, 10, 230)
    render.drawRectFast(px, py, pw, ph)
    render.setRGBA(ed.col.r, ed.col.g, ed.col.b, 255)
    render.drawRectFast(px, py, pw, 3)
    render.setFont(fTitle)
    render.setRGBA(200, 230, 170, 255)
    render.drawSimpleText(px + 20, py + 28, "RALLY FLAG", TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)

    -- name field
    local fx, fy, fw, fh = px + 20, py + 52, pw - 40, 40
    render.setRGBA(30, 36, 28, 255)
    render.drawRectFast(fx, fy, fw, fh)
    render.setRGBA(ed.col.r, ed.col.g, ed.col.b, 255)
    render.drawRectFast(fx, fy + fh - 2, fw, 2)
    render.setFont(fMed)
    render.setRGBA(255, 255, 255, 255)
    local caret = (math.floor(timer.realtime() * 2) % 2 == 0) and "_" or ""
    render.drawSimpleText(fx + 10, fy + fh / 2, ed.name .. caret, TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)

    -- preset names
    render.setFont(fSmall)
    local bw, bh = (fw - 3 * 6) / 4, 28
    for i, n in ipairs(FLAG_NAMES) do
        local cx = fx + ((i - 1) % 4) * (bw + 6)
        local cy = py + 104 + math.floor((i - 1) / 4) * (bh + 6)
        local hov = inside(mx, my, cx, cy, bw, bh)
        if ed.name == n then render.setRGBA(90, 130, 70, 255) elseif hov then render.setRGBA(60, 75, 52, 255) else render.setRGBA(36, 44, 32, 255) end
        render.drawRectFast(cx, cy, bw, bh)
        render.setRGBA(255, 255, 255, 240)
        render.drawSimpleText(cx + bw / 2, cy + bh / 2, n, TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
        if click and hov then ed.name = n end
    end

    -- colour swatches
    local sw = (fw - 7 * 8) / 8
    local sy = py + 184
    for i, c in ipairs(FLAG_COLS) do
        local cx = fx + (i - 1) * (sw + 8)
        local hov = inside(mx, my, cx, sy, sw, 34)
        local sel = ed.col.r == c.r and ed.col.g == c.g and ed.col.b == c.b
        if sel or hov then
            render.setRGBA(255, 255, 255, sel and 255 or 120)
            render.drawRectFast(cx - 3, sy - 3, sw + 6, 40)
        end
        render.setRGBA(c.r, c.g, c.b, 255)
        render.drawRectFast(cx, sy, sw, 34)
        if click and hov then ed.col = c end
    end

    -- OK / CANCEL
    local by = py + ph - 62
    local okW = (fw - 10) / 2
    local hovOk = inside(mx, my, fx, by, okW, 38)
    local hovNo = inside(mx, my, fx + okW + 10, by, okW, 38)
    render.setRGBA(hovOk and 100 or 70, hovOk and 160 or 120, hovOk and 80 or 60, 255)
    render.drawRectFast(fx, by, okW, 38)
    render.setRGBA(hovNo and 90 or 60, hovNo and 90 or 60, hovNo and 90 or 60, 255)
    render.drawRectFast(fx + okW + 10, by, okW, 38)
    render.setFont(fMed)
    render.setRGBA(255, 255, 255, 255)
    render.drawSimpleText(fx + okW / 2, by + 19, "OK", TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
    render.drawSimpleText(fx + okW * 1.5 + 10, by + 19, "CANCEL", TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
    render.setFont(fTiny)
    render.setRGBA(200, 200, 200, 180)
    render.drawSimpleText(px + pw / 2, py + ph - 12, "type the name   ENTER ok   BACKSPACE erase   RMB / ESC cancel", TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
    if click and hovOk then closeEditor(true) return end
    if click and hovNo then closeEditor(false) return end
end

hook.add("drawhud", "it_flags", function()
    pcall(render.setColorModulation, 1, 1, 1) pcall(render.setBlend, 1)   -- world tint leaks into HUD quads
    if ed then
        local W, H = render.getResolution()
        drawEditor(W, H)
        return
    end
    if G.isGunning() then return end
    render.setFont(fSmall)
    local myPos = me:getPos()
    for idx, r in pairs(C.reg) do
        if r.it and r.it.logic == "flag" then
            local e = entity(idx)
            if isValid(e) then
                local p = e:localToWorld(V(0, 0, 122))
                local sp = p:toScreen()
                if sp.visible then
                    local fi = info(idx)
                    local c = fi.col
                    render.setRGBA(0, 0, 0, 160)
                    render.drawFilledCircle(sp.x, sp.y, 7)
                    render.setRGBA(c.r, c.g, c.b, 235)
                    render.drawFilledCircle(sp.x, sp.y, 5)
                    render.drawRectFast(sp.x - 1, sp.y + 5, 2, 10)
                    render.setRGBA(255, 255, 255, 230)
                    render.drawSimpleText(sp.x, sp.y - 16, string.format("%s  %.0f m", fi.name, p:getDistance(myPos) * 0.01905),
                        TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
                    if p:getDistance(myPos) < 260 and not B.menuOpen then
                        render.setFont(fTiny)
                        render.setRGBA(220, 220, 220, 170)
                        render.drawSimpleText(sp.x, sp.y - 32, "E - edit", TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
                        render.setFont(fSmall)
                    end
                end
            end
        end
    end
end)
end

hook.add("drawhud", "it_hud", function()
    pcall(render.setColorModulation, 1, 1, 1) pcall(render.setBlend, 1)   -- world tint leaks into HUD quads
    if not C.holding then return end
    local W, H = render.getResolution()
    if B.menuOpen then drawMenu(W, H) return end
    if C.camViewEnt then
        render.setRGBA(0, 0, 0, 160)
        render.drawRectFast(W / 2 - 150, 30, 300, 40)
        render.setFont(fMed)
        render.setRGBA(255, 255, 255, 240)
        render.drawSimpleText(W / 2, 50, "CAM " .. B.camIdx .. " / " .. B.camCount .. "    B = next / off", TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
        render.setRGBA(255, 255, 255, 150)
        bracket(W / 2 - 200, H / 2 - 120, 400, 240, 40)
        render.drawRectFast(W / 2 - 10, H / 2, 20, 1) render.drawRectFast(W / 2, H / 2 - 10, 1, 20)
    end

    local x, y = W - 350, H * PANEL_Y_FRAC
    render.setRGBA(0, 0, 0, 155)
    render.drawRectFast(x, y, 330, 150)
    render.setFont(fMed)
    render.setRGBA(170, 220, 130, 255)
    render.drawSimpleText(x + 12, y + 16, "INFANTRY TOOL", TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
    render.setRGBA(255, 255, 255, 220)
    render.drawSimpleText(x + 318, y + 16, B.objCount .. (MAX_OBJECTS > 0 and ("/" .. MAX_OBJECTS) or ""), TEXT_ALIGN.RIGHT, TEXT_ALIGN.CENTER)

    render.setFont(fTitle)
    if B.plan and B.plan.ok then render.setRGBA(120, 255, 120, 255) else render.setRGBA(255, 120, 120, 255) end
    render.drawSimpleText(x + 12, y + 46, B.selected.name, TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)

    render.setFont(fSmall)
    render.setRGBA(255, 255, 255, 210)
    local l1 = "LMB place   RMB remove   R " .. (B.selected.logic == "timed" and "timer" or "rotate") .. "   Q menu"
    if B.selected.kind == "tripwire" and isValid(B.pendingProp) then l1 = "LMB stretch wire   RMB cancel" end
    render.drawSimpleText(x + 12, y + 76, l1, TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
    local l2
    if B.selected.place == "trench" then
        if B.plan and B.plan.replace then l2 = "REPLACE this piece   R turn"
        else l2 = B.trenchOrigin and "Aim at a trench = change it   Shift+G new grid" or "First trench sets the grid (R = turn)" end
    elseif B.plan and B.plan.stack then
        l2 = "STACK on top    rot " .. (B.rot % 360)
    elseif B.selected.kind == "cover" then
        l2 = "Click a trench piece / shelter to change it"
    elseif B.selected.kind == "gun" then
        l2 = (B.plan and B.plan.mountName) or "Aim at a trench / fort wall / tower deck to mount"
    elseif B.selected.logic == "timed" then
        l2 = "TIMER " .. B.fuse .. " s     R +   Shift+R -"
    else
        l2 = "G grid " .. (B.gridOn and PROP_GRIDS[B.gridIdx] or "OFF") .. (B.plan and B.plan.grid and B.plan.grid.aligned and " (aligned)" or "")
            .. "  Shift+G size  R +45  rot " .. (B.rot % 360)
    end
    render.drawSimpleText(x + 12, y + 98, l2, TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
    if B.c4Count > 0 then
        render.setRGBA(255, 190, 90, 255)
        render.drawSimpleText(x + 12, y + 118, "X - detonate C4 (" .. B.c4Count .. ")", TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
    end
    local m = (timer.realtime() < B.msgUntil) and B.msgText or (B.plan and not B.plan.ok and B.plan.reason) or nil
    if m then
        render.setRGBA(255, 220, 120, 255)
        render.drawSimpleText(x + 12, y + 138, m, TEXT_ALIGN.LEFT, TEXT_ALIGN.CENTER)
    end
end)

-- recon radar / motion alarm markers (always, also without the tool in hand)
local radarPts, radarT = {}, 0
net.receive("it_radar", function()
    local n = net.readUInt(6)
    radarPts = {}
    for i = 1, n do radarPts[i] = net.readVector() end
    radarT = timer.realtime()
end)
hook.add("drawhud", "it_radarhud", function()
    pcall(render.setColorModulation, 1, 1, 1) pcall(render.setBlend, 1)   -- world tint leaks into HUD quads
    if #radarPts == 0 or timer.realtime() - radarT > 1.6 then return end
    render.setFont(fTiny)
    local eye = me:getShootPos()
    for _, p in ipairs(radarPts) do
        local sp = (p + V(0, 0, 76)):toScreen()
        if sp.visible then
            render.setMaterial()
            render.setRGBA(255, 60, 50, 220)
            tri2({ x = sp.x, y = sp.y - 8 }, { x = sp.x + 7, y = sp.y }, { x = sp.x, y = sp.y + 8 })
            tri2({ x = sp.x, y = sp.y - 8 }, { x = sp.x - 7, y = sp.y }, { x = sp.x, y = sp.y + 8 })
            render.setRGBA(255, 210, 200, 230)
            render.drawSimpleText(sp.x, sp.y - 16, string.format("%.0fm", p:getDistance(eye) * 0.01905), TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
        end
    end
end)

-- hide the bug viewmodel
local vmHidden = nil
hook.add("think", "it_vm", function()
    local want = HIDE_BUGBAIT and C.holding
    if want == vmHidden then return end
    vmHidden = want
    pcall(function()
        local vm = me:getViewModel()
        if isValid(vm) then vm:setNoDraw(want) end
    end)
end)
