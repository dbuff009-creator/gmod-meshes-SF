#!/usr/bin/env python3
"""Run tools/smoke.lua with lupa (a real Lua 5.4)."""
import os
import sys
import lupa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L = lupa.LuaRuntime(unpack_returned_tuples=True)

mk = L.eval("function(src, root) return assert(load(src, '@tools/mock.lua'))(root) end")(
    open(os.path.join(ROOT, "tools", "mock.lua")).read(), ROOT)

run = L.eval("function(src, mk, root) return assert(load(src, '@tools/smoke.lua'))(mk, root) end")
run(open(os.path.join(ROOT, "tools", "smoke.lua")).read(), mk, ROOT)
print("SMOKE OK")
