#!/usr/bin/env python3
"""Refresh the CFG block inside infantry_tool.lua from src/config.lua.

The chip carries its own settings table so the numbers can be tuned right in
the Starfall editor, without editing the repository.  The block is built from
the declarations in src/config.lua (the module still keeps the defaults), and
the chip applies it over the required config table before any module loads --
require() caches that table, so every module sees the overrides.

Usage: python3 tools/make_chip.py [--check]
  --check   only report whether the chip is in sync, do not write
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHIP = os.path.join(ROOT, "infantry_tool.lua")
CONFIG = os.path.join(ROOT, "src", "config.lua")

BEGIN = "-- >>> CFG-BEGIN"
END = "-- <<< CFG-END"


def split_comment(text):
    """Split a declaration value from its trailing `--` comment."""
    depth, quote, i = 0, None, 0
    while i < len(text):
        ch = text[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "-" and text[i:i + 2] == "--" and depth == 0:
            comment = text[i:].splitlines()[0].strip()
            return text[:i].rstrip(), "  " + comment
        elif ch == "-" and text[i:i + 2] == "--" and depth > 0:
            nl = text.find("\n", i)
            if nl < 0:
                break
            i = nl
            continue
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        i += 1
    return text, ""


def declarations(src):
    """Top-level `local NAME = expr` declarations: name -> (expr, comment)."""
    out, order = {}, []
    lines = src.splitlines()
    i = 0
    while i < len(lines):
        m = re.match(r"^local\s+([A-Za-z_]\w*)\s*=\s*(.*)$", lines[i])
        if not m:
            i += 1
            continue
        name, rest = m.group(1), m.group(2)
        chunk = [rest]
        depth = rest.count("{") - rest.count("}")
        while depth > 0 and i + 1 < len(lines):
            i += 1
            chunk.append(lines[i])
            depth += lines[i].count("{") - lines[i].count("}")
        text = "\n".join(chunk)
        text, comment = split_comment(text)
        out[name] = (text.rstrip(), comment)
        order.append(name)
        i += 1
    return out, order


def return_order(src):
    """Keys of the `return { NAME = NAME, ... }` table, in source order."""
    body = src[src.index("return {"):]
    body = body[: body.index("\n}")]
    return re.findall(r"^\s*([A-Za-z_]\w*)\s*=", body, re.M)


def build_block(src):
    decls, _ = declarations(src)
    keys = return_order(src)
    missing = [k for k in keys if k not in decls]
    if missing:
        raise SystemExit("no declaration for: " + ", ".join(missing))
    width = max(len(k) for k in keys)
    lines = []
    for key in keys:
        expr, comment = decls[key]
        pad = " " * (width - len(key) + 1)
        if "\n" in expr:
            head, *rest = expr.splitlines()
            expr = "\n".join([head] + ["    " + ln for ln in rest])
        lines.append(f"    {key}{pad}= {expr}," + comment)
    return "\n".join(lines)


def main():
    check = "--check" in sys.argv
    src = open(CONFIG, encoding="utf-8").read()
    block = build_block(src)

    chip = open(CHIP, encoding="utf-8").read()
    if BEGIN not in chip or END not in chip:
        print("markers not found in infantry_tool.lua")
        return 1

    head, rest = chip.split(BEGIN, 1)
    current, tail = rest.split(END, 1)
    current = current.split("\n", 1)[1].rstrip("\n") if "\n" in current else ""

    if current.strip() == block.strip():
        print("chip CFG is in sync")
        return 0
    if check:
        print("chip CFG is OUT of sync with src/config.lua")
        return 1

    open(CHIP, "w", encoding="utf-8").write(head + BEGIN + "\n" + block + "\n" + END + tail)
    print(f"chip CFG updated: {len(block.splitlines())} lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
