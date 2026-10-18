-- Mock StarfallEx/GLua environment, just enough to run the Infantry Tool
-- modules outside GMod. Used by tools/smoke.py. Not shipped to players.
local ROOT = ...

-- ============================================================ math types
local V = {}
V.__index = V
local ang                 -- forward declaration (V:getAngle uses it)
local function vec(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__unm = function(a) return vec(-a.x, -a.y, -a.z) end
V.__mul = function(a, b)
    if type(a) == "number" then return vec(a * b.x, a * b.y, a * b.z) end
    if type(b) == "number" then return vec(a.x * b, a.y * b, a.z * b) end
    return vec(a.x * b.x, a.y * b.y, a.z * b.z)
end
V.__div = function(a, b)
    if type(b) == "number" then return vec(a.x / b, a.y / b, a.z / b) end
    return vec(a.x / b.x, a.y / b.y, a.z / b.z)
end
V.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
V.__tostring = function(a) return string.format("(%g %g %g)", a.x, a.y, a.z) end
function V:getLength() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
function V:getLengthSqr() return self.x * self.x + self.y * self.y + self.z * self.z end
function V:getDistance(o) return (self - o):getLength() end
function V:getNormalized() local l = self:getLength() if l == 0 then return vec() end return self / l end
function V:dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:cross(o) return vec(self.y * o.z - self.z * o.y, self.z * o.x - self.x * o.z, self.x * o.y - self.y * o.x) end
function V:getAngle() return ang(0, math.deg(math.atan(self.y, self.x)), 0) end
function V:getAngleEx() return self:getAngle() end
function V:toScreen() return { x = 100, y = 100, visible = true } end

local A = {}
A.__index = A
function ang(p, y, r) return setmetatable({ p = p or 0, y = y or 0, r = r or 0 }, A) end
A.__add = function(a, b) return ang(a.p + b.p, a.y + b.y, a.r + b.r) end
A.__sub = function(a, b) return ang(a.p - b.p, a.y - b.y, a.r - b.r) end
function A:getForward()
    local p, y = math.rad(self.p), math.rad(self.y)
    return vec(math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), -math.sin(p))
end
function A:getRight() local y = math.rad(self.y) return vec(-math.sin(y), math.cos(y), 0) end
function A:getUp()
    local p, y = math.rad(self.p), math.rad(self.y)
    return vec(math.sin(p) * math.cos(y), math.sin(p) * math.sin(y), math.cos(p))
end

local function color(r, g, b, a) return { r = r or 255, g = g or 255, b = b or 255, a = a or 255 } end

-- ============================================================ entities
local E = {}
E.__index = E
local nextIdx = 1
local function ent(class, pos)
    local e = setmetatable({ class = class, pos = pos or vec(), angles = ang(), idx = nextIdx }, E)
    nextIdx = nextIdx + 1
    return e
end
function E:getPos() return self.pos end
function E:getAngles() return self.angles end
function E:setPos(p) self.pos = p end
function E:setAngles(a) self.angles = a end
function E:setLocalAngles(a) self.angles = a end
function E:setLocalPos(p) self.pos = p end
function E:getForward() return self.angles:getForward() end
function E:getRight() return self.angles:getRight() end
function E:getUp() return self.angles:getUp() end
function E:getClass() return self.class end
function E:entIndex() return self.idx end
function E:isValid() return true end
function E:remove() self.removed = true end
function E:isPlayer() return self.class == "player" end
function E:isNPC() return self.class == "npc" end
function E:isVehicle() return self.class == "vehicle" or self.class == "prop_vehicle_prisoner_pod" end
function E:isAlive() return true end
function E:inVehicle() return false end
function E:getVehicle() return nil end
function E:getDriver() return self.driver end
function E:setNoDraw() end
function E:setSolid() end
function E:setColor() end
function E:setMaterial() end
function E:setModel() end
function E:setParent(p) self.parent = p end
function E:getParent() return self.parent end
function E:setMesh() end
function E:setMeshMaterial() end
function E:setRenderBounds() end
function E:getVelocity() return vec() end
function E:getMass() return 100 end
function E:getPhysicsObject()
    return {
        enableMotion = function() end, wake = function() end, setVelocity = function() end,
        getMass = function() return 100 end, isValid = function() return true end,
    }
end
function E:getWirelink() return setmetatable({}, { __newindex = function() end }) end
function E:emitSound() end
function E:getShootPos() return self.pos + vec(0, 0, 64) end
function E:getAimVector() return vec(1, 0, 0) end
function E:getEyeAngles() return ang(0, 0, 0) end
function E:keyDown() return false end
function E:getActiveWeapon() return E.weapon end
function E:getViewModel() return E.vm end
function E:obbMins() return vec(-10, -10, 0) end
function E:obbMaxs() return vec(10, 10, 20) end
function E:obbCenterW() return self.pos + vec(0, 0, 10) end
function E:obbCenter() return vec(0, 0, 10) end
function E:localToWorld(p) return self.pos + p end
function E:worldToLocal(p) return p - self.pos end
function E:toScreen() return { x = 100, y = 100, visible = true } end
function E:setTrails() end
E.weapon, E.vm = ent("weapon_bugbait", vec()), ent("viewmodel", vec())

-- ============================================================ env pieces
local function newRealm(name)
    local env = {}
    local realmRequireCache = {}
    local timers, simples, hooks = {}, {}, {}
    local now, rtime = 0, 0
    local pendingNet = {}

    local ownerPly = ent("player", vec(0, 0, 0))
    local chip = ent("starfall_processor", vec(0, 0, 0))

    env._G = env
    env.Vector, env.Angle, env.Color = vec, ang, color
    env.isValid = function(e) return type(e) == "table" and not e.removed end
    env._byIdx = {}
    env.entity = function(i) return env._byIdx[i] end
    env.player = function() return ownerPly end
    env.owner = function() return ownerPly end
    env.chip = function() return chip end
    env.cpuUsed = function() return 0 end
    env.cpuMax = function() return 0.01 end
    env.enableHud = function() end
    env.MASK = { SOLID = 1, SOLID_BRUSHONLY = 2, SHOT = 3, OPAQUE = 4 }
    env.KEY = { Q = 32, R = 33, G = 34, X = 35, B = 36, W = 37, A = 38, S = 39, D = 40 }
    env.MOUSE = { MOUSE1 = 101, MOUSE2 = 102, MOUSE3 = 103, MOUSE4 = 104, MOUSE5 = 105 }
    env.IN_KEY = { ATTACK = 201, ATTACK2 = 202, RELOAD = 203, FORWARD = 204, BACK = 205,
                   MOVELEFT = 206, MOVERIGHT = 207, JUMP = 208, WALK = 209, DUCK = 210 }
    env.TEXT_ALIGN = { LEFT = 0, CENTER = 1, RIGHT = 2 }
    env.bit = { band = function(a, b)
        local r, m = 0, 1
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then r = r + m end
            a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
        end
        return r
    end }
    -- standard library, plus the GLua/SF additions the chip uses
    local mlib = {}
    for k, v in pairs(math) do mlib[k] = v end
    mlib.atan2 = function(y, x) return math.atan(y, x) end
    mlib.round = function(v, d) local m = 10 ^ (d or 0) return math.floor(v * m + 0.5) / m end
    mlib.rand = function(a, b) return a end
    mlib.angleDifference = function(a, b) return ((a - b + 180) % 360) - 180 end
    env.math = mlib
    env.string, env.table, env.coroutine, env.os = string, table, coroutine, os
    env.print, env.tostring, env.tonumber, env.type = print, tostring, tonumber, type
    env.pairs, env.ipairs, env.next, env.select = pairs, ipairs, next, select
    env.pcall, env.error, env.assert, env.xpcall = pcall, error, assert, xpcall
    env.setmetatable, env.getmetatable = setmetatable, getmetatable
    env.rawget, env.rawset, env.rawequal = rawget, rawset, rawequal
    env.unpack = table.unpack
    env.load, env.loadstring = load, load
    env.coroutine = coroutine

    -- ---------------------------------------------------------- timer
    env.timer = {
        curtime = function() return now end,
        realtime = function() return rtime end,
        frametime = function() return 1 / 60 end,
        create = function(id, delay, reps, fn) timers[id] = { t = now + delay, d = delay, reps = reps, fn = fn, left = reps or 1 } end,
        simple = function(delay, fn) simples[#simples + 1] = { t = now + delay, fn = fn } end,
        remove = function(id) timers[id] = nil end,
        exists = function(id) return timers[id] ~= nil end,
    }

    -- ---------------------------------------------------------- hook
    env.hook = {}
    function env.hook.add(name, id, fn) hooks[name] = hooks[name] or {} hooks[name][id] = fn end
    function env.hook.run(name, ...)
        local t = hooks[name]
        if not t then return end
        local out
        for _, fn in pairs(t) do out = fn(...) end
        return out
    end

    -- ---------------------------------------------------------- net
    local netq, netcur = {}, nil
    local readers = {}
    env.net = {
        receive = function(name, fn) readers[name] = fn end,
        start = function(name) netcur = { name = name, data = {} } end,
        writeUInt = function(v, bits)
            assert(type(v) == "number", "writeUInt got " .. type(v) .. " for " .. tostring(netcur and netcur.name))
            assert(v >= 0, "writeUInt negative value")
            if bits and bits < 32 then assert(v < 2 ^ bits, "writeUInt overflow: " .. v .. " > " .. (2 ^ bits - 1)) end
            netcur.data[#netcur.data + 1] = { "u", v }
        end,
        writeString = function(s) assert(type(s) == "string", "writeString got " .. type(s)) netcur.data[#netcur.data + 1] = { "s", s } end,
        writeBool = function(b) assert(type(b) == "boolean", "writeBool got " .. type(b)) netcur.data[#netcur.data + 1] = { "b", b } end,
        writeVector = function(v) assert(getmetatable(v) == V, "writeVector got " .. type(v)) netcur.data[#netcur.data + 1] = { "v", v } end,
        writeAngle = function(a) assert(getmetatable(a) == A, "writeAngle got " .. type(a)) netcur.data[#netcur.data + 1] = { "a", a } end,
        writeEntity = function(e) netcur.data[#netcur.data + 1] = { "e", e } end,
        send = function(to) netq[#netq + 1] = { name = netcur.name, data = netcur.data, to = to } netcur = nil end,
    }
    env._netq = netq
    env._readers = readers
    function env._deliver(msg, ply)
        local fn = readers[msg.name]
        if not fn then return false, "no receiver for " .. msg.name end
        local pos = 1
        local function pop(kind)
            local item = msg.data[pos]
            assert(item, "read past end of " .. msg.name)
            assert(item[1] == kind, "type mismatch in " .. msg.name .. ": want " .. kind .. " got " .. item[1])
            pos = pos + 1
            return item[2]
        end
        env.net.readUInt = function() return pop("u") end
        env.net.readString = function() return pop("s") end
        env.net.readBool = function() return pop("b") end
        env.net.readVector = function() return pop("v") end
        env.net.readAngle = function() return pop("a") end
        env.net.readEntity = function() return pop("e") end
        fn(0, ply)
        return true
    end

    -- ---------------------------------------------------------- render / input
    local r = {}
    for _, fn in ipairs({ "setFont", "setRGBA", "setColor", "setMaterial", "drawRect", "drawCircle",
        "drawFilledCircle", "drawSimpleText", "draw3DLine", "drawPoly", "drawTexturedRect",
        "drawText", "setCullMode" }) do r[fn] = function() end end
    r.createFont = function(f, s) assert(type(f) == "string" and type(s) == "number") return { f = f, s = s } end
    r.getResolution = function() return 1920, 1080 end
    env.render = r

    env.input = {
        isKeyDown = function() return false end,
        isMouseDown = function() return false end,
        isShiftDown = function() return false end,
        getCursorPos = function() return 100, 100 end,
        enableCursor = function() end,
        lookupBinding = function() return nil end,
    }

    env.material = { load = function(p) assert(type(p) == "string") return { getName = function() return p end } end }
    env.mesh = { createFromTable = function(verts, threaded)
        assert(#verts % 3 == 0, "mesh vertex count not a multiple of 3: " .. #verts)
        assert(#verts <= 65535, "mesh too big: " .. #verts)
        for i = 1, math.min(#verts, 30) do
            local v = verts[i]
            assert(type(v) == "table" and v.pos and v.normal and v.u and v.v, "bad vertex " .. i)
        end
        if threaded and coroutine.isyieldable() then coroutine.yield() end
        return { verts = #verts }
    end }

    local function spawnEnt(class, pos)
        local e = ent(class, pos)
        table.insert(env._ents, e)
        env._byIdx[e.idx] = e
        return e
    end
    env._ents = {}
    env._spawnEnt = spawnEnt

    env.hologram = {
        canSpawn = function() return true end,
        hologramsLeft = function() return 50 end,
        create = function(pos, a, model, scale)
            assert(getmetatable(pos) == V, "hologram.create pos")
            assert(getmetatable(a) == A, "hologram.create angle")
            assert(type(model) == "string", "hologram.create model")
            return spawnEnt("starfall_hologram", pos)
        end,
    }
    env.prop = {
        canSpawn = function() return true end,
        createCustom = function(pos, a, conv, frozen)
            assert(type(conv) == "table", "createCustom convexes")
            assert(#conv > 0, "createCustom: zero convexes")
            assert(#conv <= 10, "createCustom: " .. #conv .. " convexes (max 10)")
            for _, c in ipairs(conv) do
                assert(type(c) == "table" and #c >= 4, "convex has " .. #c .. " points")
                for _, p in ipairs(c) do assert(getmetatable(p) == V, "convex point is not a Vector") end
            end
            return spawnEnt("starfall_prop", pos)
        end,
        createSeat = function(pos, a, model, frozen) return spawnEnt("prop_vehicle_prisoner_pod", pos) end,
        createSent = function(pos, a, class, frozen, data) return spawnEnt(class, pos) end,
        create = function(pos, a, model, frozen) return spawnEnt("prop_physics", pos) end,
    }
    env.trace = { line = function(a, b, filter, mask)
        return { Hit = false, HitPos = b, HitNormal = vec(0, 0, 1), Fraction = 1, Entity = nil,
                 HitWorld = false, HitSky = false, StartSolid = false }
    end }
    env.find = { inSphere = function() return {} end }
    env.game = {
        bulletDamage = function() end, blastDamage = function() end,
        canFireBullets = function() return true end, bulletsLeft = function() return 999 end,
    }
    env.effect = { create = function() end }
    env.light = { create = function(pos, size, bright, col)
        assert(getmetatable(pos) == V, "light.create pos")
        assert(type(size) == "number" and type(bright) == "number", "light.create size/brightness")
        return { setPos = function() end, draw = function() end, destroy = function() end }
    end }
    env.localToWorld = function(p, a, o, oa)
        return o + oa:getForward() * p.x + oa:getRight() * p.y + vec(0, 0, p.z), a
    end
    env.worldToLocal = function(p, a, o, oa)
        local d = p - o
        return vec(d:dot(oa:getForward()), d:dot(oa:getRight()), d.z), a
    end
    env.SERVER, env.CLIENT = name == "server", name == "client"

    -- ---------------------------------------------------------- require
    env.require = function(path)
        if realmRequireCache[path] ~= nil then return realmRequireCache[path] end
        local f = assert(io.open(ROOT .. "/" .. path, "rb"), "include not found: " .. path)
        local src = f:read("*a")
        f:close()
        local first = src:match("^%-%-@(%w+)")
        if first == "server" and name ~= "server" then error("client tried to load server module " .. path) end
        if first == "client" and name ~= "client" then error("server tried to load client module " .. path) end
        local fn, err = load(src, "@" .. path, "t", env)
        assert(fn, err)
        realmRequireCache[path] = true
        local ret = fn()
        realmRequireCache[path] = ret or true
        return ret
    end

    -- ---------------------------------------------------------- driver
    function env._tick(dt)
        dt = dt or 1 / 60
        now, rtime = now + dt, rtime + dt
        env.hook.run("think")
        local i = 1
        while i <= #simples do
            if simples[i].t <= now then
                local s = table.remove(simples, i)
                s.fn()
            else
                i = i + 1
            end
        end
        for _, t in pairs(timers) do
            if t.left == 0 then
                while t.t <= now do t.t = t.t + t.d t.fn() end
            else
                while t.left > 0 and t.t <= now do
                    t.t = t.t + t.d
                    t.left = t.left - 1
                    t.fn()
                end
            end
        end
    end

    function env._keys()
        local t = {}
        for k in pairs(env) do if k:sub(1, 1) ~= "_" then t[#t + 1] = k end end
        table.sort(t)
        return table.concat(t, " ")
    end

    return env
end

return newRealm
