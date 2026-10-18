-- Infantry Tool :: shared helpers
-- Small functions both realms need: aim tracing, surface classification,
-- grenade pivot maths, shell ballistics and the tripwire wire check.

local C = require("src/config.lua")

local V = Vector
local WEAPON_CLASS, LASER_RANGE = C.WEAPON_CLASS, C.LASER_RANGE


local function clamp(v, a, b) return v < a and a or (v > b and b or v) end

local function holdsTool(ply)
    if not isValid(ply) or not ply:isAlive() or ply:inVehicle() then return false end
    local w = ply:getActiveWeapon()
    return isValid(w) and w:getClass() == WEAPON_CLASS
end
-- ============================ PLACEMENT HELPERS (shared) ============================
local function upFrame(n) return n:getAngle() + Angle(90, 0, 0) end

-- angle with UP = n and forward as close as possible to yaw
local function surfaceAngle(n, yaw)
    local f0 = Angle(0, yaw, 0):getForward()
    local f = f0 - n * f0:dot(n)
    if f:getLength() < 0.01 then f = n:cross(V(0, 1, 0)) end
    return f:getNormalized():getAngleEx(n)
end

local function aimTrace(ply, range, filter)
    local eye = ply:getShootPos()
    local f = { ply }
    if filter then for _, e in ipairs(filter) do f[#f + 1] = e end end
    return trace.line(eye, eye + ply:getAimVector() * range, f, MASK.SHOT), eye
end

local function badSurface(tr)
    if not tr.Hit or tr.HitSky then return true end
    local e = tr.Entity
    return isValid(e) and (e:isPlayer() or e:isNPC() or e:isVehicle())
end

-- mortar: fixed tube angle, solve the muzzle speed: D*tan(th) - g/2*t^2 = dz, D = v*cos(th)*t
local function mortarSolve(from, to, pitchDeg, g)
    local dx, dy = to.x - from.x, to.y - from.y
    local D = math.sqrt(dx * dx + dy * dy)
    if D < 1 then return nil end
    local th = math.rad(pitchDeg)
    local k = D * math.tan(th) - (to.z - from.z)
    if k <= 0 then return nil end
    local t = math.sqrt(2 * k / g)
    local c = math.cos(th)
    return V(dx / D * c, dy / D * c, math.sin(th)), D / (t * c), t, D
end

-- grenade model fix (w_ models have offset origin / arbitrary axes)
local function nadeFix(ent)
    local mn, mx = ent:obbMins(), ent:obbMaxs()
    local sz, c = mx - mn, (mn + mx) * 0.5
    local rot, half
    if sz.z >= sz.x and sz.z >= sz.y then rot, half = Angle(0, 0, 0), sz.z * 0.5
    elseif sz.x >= sz.y then rot, half = Angle(-90, 0, 0), sz.x * 0.5
    else rot, half = Angle(0, 0, 90), sz.y * 0.5 end
    return { rot = rot, c = c, half = half }
end
local function nadeTransform(fix, center, frame)
    local _, ang = localToWorld(V(), fix.rot, V(), frame)
    local off = localToWorld(fix.c, Angle(), V(), ang)
    return center - off, ang
end

local function wireOk(a, b, ignore)
    local d = b - a
    local len = d:getLength()
    if len < 24 or len > 600 then return false, len end
    local tr = trace.line(a, b - d / len * 3, ignore, MASK.SOLID)
    return not tr.Hit, len
end

return {
    aimTrace = aimTrace,
    badSurface = badSurface,
    clamp = clamp,
    holdsTool = holdsTool,
    mortarSolve = mortarSolve,
    nadeFix = nadeFix,
    nadeTransform = nadeTransform,
    surfaceAngle = surfaceAngle,
    upFrame = upFrame,
    wireOk = wireOk,
}
