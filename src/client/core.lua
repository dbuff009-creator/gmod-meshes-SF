--@client
-- Infantry Tool :: client core
-- Identity, fonts, the object registry and the single think dispatcher.
--
-- Every subsystem used to register its own "think" hook, so Starfall paid for
-- a separate hook dispatch, a separate holdsTool() weapon lookup and a separate
-- table walk per subsystem per frame. Now there is one hook, one holdsTool()
-- lookup, and subsystems push a plain function into C.think.

local SH = require("src/shared.lua")

local me = player()
local O = owner()
local isOwner = me == O

local reg = {}
local alias = {}            -- hidden extra collision prop -> main object index

local fTitle = render.createFont("Roboto", 30, 900, true)
local fMed   = render.createFont("Roboto", 21, 800, true)
local fSmall = render.createFont("Roboto", 16, 600, true)
local fCard  = render.createFont("Roboto", 18, 800, true)
local fTiny  = render.createFont("Roboto", 14, 600, true)

local C = {
    me = me,
    O = O,
    isOwner = isOwner,
    reg = reg,                   -- entIndex -> {d = mesh def, it = item, applied}
    alias = alias,               -- hidden extra collision prop -> main object index
    think = {},                  -- frame callbacks, run in registration order
    holding = false,             -- holdsTool(me), refreshed once per frame
    camViewEnt = nil,            -- owner: looking through a periscope camera
    fTitle = fTitle, fMed = fMed, fSmall = fSmall, fCard = fCard, fTiny = fTiny,
}

local holdsTool = SH.holdsTool

-- your object behind an entity (extra collision props map to their main object)
function C.regOf(e)
    if not isValid(e) then return nil end
    local idx = e:entIndex()
    if alias[idx] then
        idx = alias[idx]
        e = entity(idx)
        if not isValid(e) then return nil end
    end
    local r = reg[idx]
    if not r or not r.it then return nil end
    return e, r.it
end

hook.add("think", "it_frame", function()
    C.holding = holdsTool(me)          -- one weapon lookup per frame for everyone
    local list = C.think
    for i = 1, #list do list[i]() end
end)

return C
