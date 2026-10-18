"""Static API audit: every `lib.func(` and `obj:method(` used by the modules is
checked against the definitions found in a StarfallEx source tree.

  python3 tools/apicheck.py /tmp/sf-src
"""
import glob
import os
import re
import sys
from collections import defaultdict

from luaparser import ast
from luaparser.astnodes import (Call, Index, Invoke, Name, String)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SF = sys.argv[1] if len(sys.argv) > 1 else "/tmp/sf-src"


def walk(node):
    yield node
    for child in node.__dict__.values():
        if isinstance(child, list):
            for c in child:
                if isinstance(c, ast.Node):
                    yield from walk(c)
        elif isinstance(child, ast.Node):
            yield from walk(child)


def sval(n):
    if isinstance(n, String):
        return n.s.strip('"\'')
    return None


# ---------------------------------------------------------------- usage in repo
lib_calls = defaultdict(set)     # library -> funcs
methods = defaultdict(set)       # method -> example lib
file_of = {}
for f in glob.glob(os.path.join(ROOT, "src", "**", "*.lua"), recursive=True):
    tree = ast.parse(open(f).read())
    for n in walk(tree):
        if isinstance(n, Index) and isinstance(n, Name) and sval(n.idx):
            file_of[(n.value.id, sval(n.idx))] = os.path.relpath(f, ROOT)
        if isinstance(n, Call) and isinstance(n.func, Index) and isinstance(n.func.value, Name) and sval(n.func.idx):
            lib_calls[n.func.value.id].add(sval(n.func.idx))
        if isinstance(n, Invoke):
            methods[n.func.id].add(os.path.basename(f))

# ---------------------------------------------------------------- definitions
defs = defaultdict(set)
method_defs = set()
for f in glob.glob(os.path.join(SF, "**", "*.lua"), recursive=True):
    try:
        src = open(f, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    for m in re.finditer(r"function\s+([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*\(", src):
        defs[m.group(1)].add(m.group(2))
    for m in re.finditer(r"function\s+([A-Za-z_]\w*)\.([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*\(", src):
        defs[m.group(2)].add(m.group(3))       # type tables: prop.SENT.destroy
    for m in re.finditer(r"function\s+(\w+)\s*:\s*([A-Za-z_]\w*)\s*\(", src):
        method_defs.add(m.group(2))
    for m in re.finditer(r"function\s+([A-Za-z_]\w*)\.__index\s*:\s*([A-Za-z_]\w*)\s*\(", src):
        method_defs.add(m.group(2))
    for m in re.finditer(r"([A-Za-z_]\w*)\s*=\s*function\s*\(([^)]*)\)", src):
        pass

# libraries exposed in SF env (SF.RegisterLibrary("name"))
libs = set()
for f in glob.glob(os.path.join(SF, "**", "*.lua"), recursive=True):
    src = open(f, encoding="utf-8", errors="replace").read()
    libs |= set(re.findall(r'SF\.RegisterLibrary\(\s*"(\w+)"', src))
    libs |= set(re.findall(r"SF\.RegisterLibrary\(\s*'(\w+)'", src))

allowed_other = {
    # sf globals that are neither libraries nor methods
    "world", "server", "client", "render", "input", "net", "hook", "timer", "coroutine",
    "string", "table", "math", "os", "io", "debug", "bit", "utf8", "SF",
}

print("SF libraries:", " ".join(sorted(libs)))
print()
problems = 0
for lib, fns in sorted(lib_calls.items()):
    if lib not in libs:
        if lib in allowed_other:
            continue
        # locals that happen to look like libraries: report only if never a library
        print(f"? {lib}: not a registered library (calls: {', '.join(sorted(fns))})")
        problems += 1
        continue
    unknown = [fn for fn in sorted(fns) if fn not in defs.get(lib, set())]
    if unknown:
        print(f"!! {lib}: unknown {', '.join(unknown)}")
        problems += 1

print()
full = {"Vector", "Angle", "Color", "Entity", "Player", "Wirelink", "Vector/Matrix"}
all_methods = set()
for lib in libs:
    all_methods |= defs.get(lib, set())
all_methods |= defs.get("Entity", set()) | defs.get("Player", set()) | defs.get("Vector", set()) | defs.get("Angle", set())
all_methods |= method_defs
missing = sorted(m for m in methods if m not in all_methods and not m.startswith("_"))
print("methods not found in default tables:")
for m in missing:
    print(f"  {m:26s} used in {', '.join(sorted(methods[m]))}")
print("problems:", problems)
