#!/usr/bin/env python3
"""Check Starfall preprocessor directives the way StarfallEx itself does.

The preprocessor does not parse comments: it runs

    string.gmatch(code, "(%-%-@(%w+)([^\\r\\n]*))")

over the raw text, so a directive-looking comment is executed for real.  That
is how a doc header once produced

    Conflicting realm directives --@server/--@client/--@shared

and a stray "--@include lines above" inside a comment added a bogus include.

This script flags:
  * unknown directives,
  * any directive that is not the first token of its line (comments/strings),
  * conflicting or repeated realm directives,
  * malformed includes, duplicate include names, missing local files.

Usage: python3 tools/directives.py [repo root]
"""
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DIRECTIVE = re.compile(r"--@(\w+)([^\r\n]*)")
REALMS = ("server", "client", "shared")
NO_ARG = ("server", "client", "shared", "superuser", "owneronly")
KNOWN = set(NO_ARG) | {"name", "author", "include", "includedata", "includedir",
                       "model", "precachemodel", "clientmain"}
MAX_HEADER = 20   # directives are allowed only in the header block


def check_file(path, rel):
    problems = []
    realm, seen_names = None, {}
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    lines = text.splitlines()
    for m in DIRECTIVE.finditer(text):
        name, args = m.group(1), m.group(2).strip()
        line_no = text.count("\n", 0, m.start()) + 1
        line = lines[line_no - 1]
        col = m.start() - (text.rfind("\n", 0, m.start()) + 1)
        if name not in KNOWN:
            problems.append(f"{rel}:{line_no}: unknown directive --@{name}")
            continue
        if line[:col].strip():
            problems.append(
                f"{rel}:{line_no}: --@{name} is not at the start of the line "
                f"(the preprocessor will still execute it): {line.strip()[:70]}")
        if line_no > MAX_HEADER:
            problems.append(f"{rel}:{line_no}: --@{name} outside the header block")
        if name in REALMS:
            if args:
                problems.append(f"{rel}:{line_no}: --@{name} takes no arguments")
            if realm and realm != name:
                problems.append(
                    f"{rel}:{line_no}: conflicting realm directives "
                    f"--@{realm} and --@{name}")
            realm = name
        elif name in ("name", "author", "model", "precachemodel", "clientmain",
                      "includedir"):
            if not args:
                problems.append(f"{rel}:{line_no}: --@{name} needs an argument")
        elif name in ("include", "includedata"):
            mm = re.match(r"^(.+?)\s+as\s+(\S+)$", args)
            if not mm:
                problems.append(
                    f"{rel}:{line_no}: bad include, expected "
                    f"'--@include <url|path> as <name>': {args[:70]}")
                continue
            target, as_name = mm.group(1), mm.group(2)
            if as_name in seen_names:
                problems.append(f"{rel}:{line_no}: duplicate include name {as_name}")
            seen_names[as_name] = line_no
            if not re.match(r"^https?://", target):
                local = os.path.join(ROOT, target)
                if not os.path.exists(local):
                    problems.append(f"{rel}:{line_no}: include target missing: {target}")
            elif name == "include" and "raw.githubusercontent.com" not in target:
                problems.append(f"{rel}:{line_no}: include URL not on raw.githubusercontent")
        elif name in ("superuser", "owneronly") and args:
            problems.append(f"{rel}:{line_no}: --@{name} takes no arguments")
    return problems, realm, seen_names


def main():
    main_file = os.path.join(ROOT, "infantry_tool.lua")
    problems = []
    if not os.path.exists(main_file):
        print("infantry_tool.lua not found")
        return 1

    p, realm, includes = check_file(main_file, "infantry_tool.lua")
    problems += p
    if realm != "shared":
        problems.append(f"infantry_tool.lua: expected --@shared, got {realm}")

    expected = ["src/config.lua", "src/geom.lua", "src/shared.lua", "src/items.lua",
                "src/server/core.lua", "src/server/guns.lua", "src/server/sensors.lua",
                "src/client/core.lua", "src/client/meshes.lua", "src/client/guns.lua",
                "src/client/build.lua", "src/client/hud.lua"]
    for name in expected:
        if name not in includes:
            problems.append(f"infantry_tool.lua: no include for {name}")
            continue
        path = os.path.join(ROOT, name)
        if not os.path.exists(path):
            problems.append(f"infantry_tool.lua: {name} does not exist in the repo")
            continue
        p, r, _ = check_file(path, name)
        problems += p
        want = "server" if name.startswith("src/server/") else (
            "client" if name.startswith("src/client/") else None)
        if want and r != want:
            problems.append(f"{name}: expected --@{want}, got {r or 'no realm directive'}")

    for name in includes:
        if name not in expected:
            problems.append(f"infantry_tool.lua: unexpected include {name}")

    for line in problems:
        print(" ", line)
    print(f"directives: {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
