#!/usr/bin/env python3
"""Report names a module reads but never declares locally and never imports.

Catches the classic multi-file mistake: a function moved to another module but
still called by its bare name. Whitelisted names are engine globals.
"""
import glob
import os
import sys

from luaparser import ast
from luaparser.astnodes import (Assign, Call, Field, Forin, Fornum, Function, Index,
                                LocalAssign, LocalFunction, Name, Node, Table)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

GLOBALS = set("""
SERVER CLIENT _G
Vector Angle Color Vector2 Matrix
isValid entity player owner chip
net hook timer render input material mesh hologram prop trace find game effect light sound
bit coroutine string table math os io debug utf8 require dofile load loadstring print
tostring tonumber type pairs ipairs next select pcall xpcall error assert unpack
setmetatable getmetatable rawget rawset rawequal
cpuUsed cpuMax enableHud
MASK KEY MOUSE IN_KEY TEXT_ALIGN
localToWorld worldToLocal
Color HSVToColor
""".split())


def walk(n):
    yield n
    for k, v in n.__dict__.items():
        if k.startswith("_"):
            continue
        if isinstance(v, list):
            for c in v:
                if isinstance(c, Node):
                    yield from walk(c)
        elif isinstance(v, Node):
            yield from walk(v)


def declared(tree):
    names = set()
    for n in walk(tree):
        if isinstance(n, LocalAssign):
            names |= {t.id for t in n.targets if isinstance(t, Name)}
        elif isinstance(n, LocalFunction):
            names.add(n.name.id)
        elif isinstance(n, Function) and isinstance(n.name, Name):
            names.add(n.name.id)
        elif isinstance(n, Fornum):
            names.add(n.target.id)
        elif isinstance(n, Forin):
            names |= {t.id for t in n.targets if isinstance(t, Name)}
        elif isinstance(n, Function):
            names |= {a.id for a in (n.args or []) if isinstance(a, Name)}
    return names


def is_target(n, parent):
    """True when this Name is written to (assignment target, param, table key)."""
    if parent is None:
        return False
    if isinstance(parent, (Assign, LocalAssign)) and any(t is n for t in parent.targets):
        return True
    if isinstance(parent, LocalFunction) and parent.name is n:
        return True
    if isinstance(parent, Function):
        if parent.name is n:
            return True
        if any(a is n for a in (parent.args or [])):
            return True
    if isinstance(parent, Fornum) and parent.target is n:
        return True
    if isinstance(parent, Forin) and any(t is n for t in parent.targets):
        return True
    if isinstance(parent, Field) and parent.key is n:
        return True
    if isinstance(parent, Index) and parent.idx is n:
        return True          # field name, not a variable
    return False


def used(tree):
    out = {}

    def rec(n, parent):
        if isinstance(n, Name):
            if not is_target(n, parent):
                out[n.id] = out.get(n.id, 0) + 1
            return
        for k, v in n.__dict__.items():
            if k.startswith("_"):
                continue
            if isinstance(v, list):
                for c in v:
                    if isinstance(c, Node):
                        rec(c, n)
            elif isinstance(v, Node):
                rec(v, n)

    rec(tree, None)
    return out


def globals_written(tree):
    bad = []
    for n in walk(tree):
        if isinstance(n, Assign):
            for t in n.targets:
                if isinstance(t, Name) and getattr(t, "ctx", None) == "Store":
                    bad.append(t.id)
    return bad


bad_files = 0
for f in sorted(glob.glob(os.path.join(ROOT, "src", "**", "*.lua"), recursive=True)):
    tree = ast.parse(open(f).read())
    loc, us = declared(tree), used(tree)
    miss = sorted(k for k in us if k not in loc and k not in GLOBALS)
    gw = globals_written(tree)
    if miss or gw:
        bad_files += 1
        rel = os.path.relpath(f, ROOT)
        if miss:
            print(f"{rel}: missing local/import: {', '.join(miss)}")
        if gw:
            print(f"{rel}: writes globals: {', '.join(sorted(set(gw)))}")
print("files with problems:", bad_files)
sys.exit(1 if bad_files else 0)
