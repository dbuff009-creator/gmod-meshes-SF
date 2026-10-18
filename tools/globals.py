#!/usr/bin/env python3
"""Find cross-module name leaks.

The original chip was one file: a function declared `local` anywhere was visible
to the whole file. After the split, a module that forgot to import such a name
silently gets a nil global -- and the failure shows up only at run time
("attempt to call a nil value", "Font does not exist").

This script collects every top-level `local NAME` of every module, then reports
names a module reads but neither declares nor imports.

Usage: python3 tools/globals.py
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BUILTIN_PREFIX = {
    "print", "pairs", "ipairs", "type", "tostring", "tonumber", "error", "assert",
    "pcall", "xpcall", "select", "unpack", "setmetatable", "getmetatable", "rawget",
    "rawset", "rawequal", "next", "table", "string", "math", "coroutine", "os",
    "io", "debug", "bit", "utf8", "require", "dofile", "load", "loadstring",
    "collectgarbage", "newproxy", "module", "setfenv", "getfenv", "gcinfo",
}

# Starfall / GMod globals that modules are allowed to read without import.
GLOBALS = {
    "Vector", "Angle", "Color", "Matrix", "IsValid", "isValid", "isvector",
    "isangle", "ismatrix", "isstring", "isnumber", "istable", "isfunction",
    "isbool", "isentity", "isPlayer", "isNPC", "isVehicle", "isWeapon",
    "isEffect", "isPhysObj", "timer", "net", "hook", "render", "input",
    "material", "mesh", "hologram", "prop", "light", "sound", "trace", "find",
    "game", "effect", "constraint", "ents", "player", "owner", "entity",
    "SERVER", "CLIENT", "SF", "MASK", "MOUSE", "KEY", "TEXT_ALIGN", "TOP",
    "BOTTOM", "LEFT", "RIGHT", "CENTER", "MATERIAL", "RENDERGROUP", "COLLISION_GROUP",
    "CHANNEL", "SOUND", "TEAM", "STENCIL", "BLEND", "SURFACE", "HUD", "NOTIFY",
    "TASK", "MOVETYPE", "SIM", "OBS_MODE", "IN", "MOUSE_FIRST", "MOUSE_LAST",
    "MOUSE_LEFT", "MOUSE_RIGHT", "DAMAGE", "CLASS", "WIRE", "SCHED", "FILL",
    "VISIBLE", "SOLID", "SHOT", "OPAQUE", "SPECIAL", "ALL", "WAIT", "GM",
    "LocalPlayer", "cvars", "console", "util", "file", "http", "sql", "physenv",
    "Stencil", "holograms", "sounds", "clamp", "lerp", "Color", "table",
}

LOCAL = re.compile(r"^local\s+([A-Za-z_][\w, ]*?)\s*(?:=|$)")
FUNCTION = re.compile(r"^local\s+function\s+([A-Za-z_]\w*)")
IMPORT = re.compile(r"^local\s+([A-Za-z_][\w]*(?:\s*,\s*[A-Za-z_]\w*)*)\s*=\s*([A-Za-z_][\w.]*)")
READ = re.compile(r"(?<![\w.:])([A-Z][A-Za-z_]\w*|[a-z_][\w]*)(?![\w(])|(?<![\w.:])([A-Za-z_]\w*)\s*\(")


def top_locals(src, any_indent=False):
    """Locals of a file; by default only file-level ones (column 0)."""
    names = set()
    for line in src.splitlines():
        if not any_indent and line[:1] in (" ", "\t"):
            continue
        stripped = line.strip()
        if not stripped.startswith("local") and not stripped.startswith("function"):
            continue
        m = re.match(r"(?:local\s+)?function\s+([A-Za-z_]\w*)", stripped)
        if m:
            names.add(m.group(1))
            continue
        m = re.match(r"local\s+([A-Za-z_][\w,\s]*?)\s*(?:=|$)", stripped)
        if m:
            for part in m.group(1).split(","):
                part = part.strip()
                if re.fullmatch(r"[A-Za-z_]\w*", part):
                    names.add(part)
    return names


def strip_comments_strings(src):
    out, i, n = [], 0, len(src)
    while i < n:
        two = src[i:i + 2]
        if two == "--":
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if two == "[[" or src[i:i + 3] == "--[[":
            j = src.find("]]", i)
            i = n if j < 0 else j + 2
            continue
        ch = src[i]
        if ch in "\"'":
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == ch or src[j] == "\n":
                    break
                j += 1
            i = j + 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def main():
    files = sorted(glob.glob(os.path.join(ROOT, "src", "*", "*.lua")) +
                   glob.glob(os.path.join(ROOT, "src", "*.lua")))
    sources = {os.path.relpath(f, ROOT): open(f, encoding="utf-8").read() for f in files}
    declared = {path: top_locals(src) for path, src in sources.items()}      # file-level only
    own_all = {path: top_locals(src, any_indent=True) for path, src in sources.items()}

    problems = 0
    for path, src in sources.items():
        body = strip_comments_strings(src)
        own = own_all[path]
        imported = set()
        for line in src.splitlines():
            m = IMPORT.match(line)
            if m:
                for part in m.group(1).split(","):
                    imported.add(part.strip())
        missing = {}
        for m in READ.finditer(body):
            name = m.group(1) or m.group(2)
            if not name or len(name) < 3 or name in own or name in imported:
                continue
            after = body[m.end():m.end() + 3].lstrip()
            if after.startswith("=") and not after.startswith("=="):
                continue        # table key or assignment target, not a read
            if name in BUILTIN_PREFIX or name in GLOBALS:
                continue
            # only interesting when another module declares it as a top-level local
            owners = [p for p, names in declared.items() if p != path and name in names]
            if owners:
                missing[name] = owners
        if missing:
            problems += len(missing)
            print(f"{path}:")
            for name, owners in sorted(missing.items()):
                print(f"   {name}  (declared in {', '.join(owners)})")
    print(f"cross-module leaks: {problems}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
