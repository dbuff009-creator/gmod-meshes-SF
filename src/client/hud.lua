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
    render.drawRect(px, py, pw, ph)
    render.setRGBA(120, 160, 90, 255)
    render.drawRect(px, py, pw, 3)
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
        render.drawRect(tx, ty, tw, th)
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
            render.drawRect(x, y, CARD_W, CARD_H)
            local c = it.color or Color(160, 160, 160)
            render.setRGBA(c.r, c.g, c.b, 255)
            render.drawRect(x + 7, y + 8, 8, CARD_H - 16)
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
    render.drawRect(bx, by, 180, 38)
    render.setFont(fMed)
    render.setRGBA(255, 255, 255, 255)
    render.drawSimpleText(bx + 90, by + 19, "CLEAR ALL", TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
    if click and hovC then sendSimple(5) end

    local hx = px + pw - 200
    local hovX = inside(mx, my, hx, by, 180, 38)
    render.setRGBA(hovX and 90 or 60, hovX and 90 or 60, hovX and 90 or 60, 255)
    render.drawRect(hx, by, 180, 38)
    render.setRGBA(255, 255, 255, 255)
    render.drawSimpleText(hx + 90, by + 19, "CLOSE", TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
    render.setFont(fSmall)
    render.setRGBA(200, 200, 200, 180)
    render.drawSimpleText(px + pw / 2, by + 19, "Q / RMB / click outside - close", TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
    if click and hovX then setMenu(false) end
end
end

-- rally flags: waypoint markers (always on, also without the tool)
hook.add("drawhud", "it_flags", function()
    if G.isGunning() then return end
    render.setFont(fSmall)
    for idx, r in pairs(C.reg) do
        if r.it and r.it.logic == "flag" then
            local e = entity(idx)
            if isValid(e) then
                local p = e:localToWorld(V(0, 0, 122))
                local sp = p:toScreen()
                if sp.visible then
                    render.setRGBA(255, 70, 60, 230)
                    render.drawFilledCircle(sp.x, sp.y, 5)
                    render.drawRect(sp.x - 1, sp.y + 5, 2, 10)
                    render.setRGBA(255, 255, 255, 230)
                    render.drawSimpleText(sp.x, sp.y - 16, string.format("RALLY  %.0f m", p:getDistance(me:getPos()) * 0.01905),
                        TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
                end
            end
        end
    end
end)

hook.add("drawhud", "it_hud", function()
    if not C.holding then return end
    local W, H = render.getResolution()
    if B.menuOpen then drawMenu(W, H) return end
    if camViewEnt then
        render.setRGBA(0, 0, 0, 160)
        render.drawRect(W / 2 - 150, 30, 300, 40)
        render.setFont(fMed)
        render.setRGBA(255, 255, 255, 240)
        render.drawSimpleText(W / 2, 50, "CAM " .. B.camIdx .. " / " .. B.camCount .. "    B = next / off", TEXT_ALIGN.CENTER, TEXT_ALIGN.CENTER)
        render.setRGBA(255, 255, 255, 150)
        bracket(W / 2 - 200, H / 2 - 120, 400, 240, 40)
        render.drawRect(W / 2 - 10, H / 2, 20, 1) render.drawRect(W / 2, H / 2 - 10, 1, 20)
    end

    local x, y = W - 350, H * PANEL_Y_FRAC
    render.setRGBA(0, 0, 0, 155)
    render.drawRect(x, y, 330, 150)
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
    local l1 = "LMB place   RMB remove   R rotate   Q menu"
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
