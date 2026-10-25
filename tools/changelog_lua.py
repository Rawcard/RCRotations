#!/usr/bin/env python3
"""Write Changelog.lua (the in-game "What's new" popup) from VERSION.txt.

  python3 tools/changelog_lua.py          write it
  python3 tools/changelog_lua.py --check  exit 1 if Changelog.lua is out of date

Keeps the newest few versions. Run it after editing VERSION.txt; the tests
check it's up to date.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEEP = 3


def parse(text):
    versions = []
    for line in text.splitlines():
        m = re.match(r"^#\s+(\d+\.\d+\.\d+)\s*$", line)
        if m:
            versions.append({"version": m.group(1), "items": []})
            continue
        if not versions:
            continue
        items = versions[-1]["items"]
        if line.startswith("- "):
            items.append(line[2:].strip())
        elif line.startswith("  ") and items and line.strip():
            items[-1] += " " + line.strip()
        elif line.strip() and not line.startswith("#"):
            items.append(line.strip())
    return versions


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def notable(versions):
    """Leave out the automatic nightly releases (only "Rotations updated from
    WoWSims"), so they don't pop the window up again."""
    return [v for v in versions if not (len(v["items"]) == 1 and v["items"][0].startswith("Rotations updated from WoWSims"))]


def render(versions):
    out = ["-- Generated from VERSION.txt by tools/changelog_lua.py. Don't edit by hand.",
           "local addonName, ns = ...", "ns.CHANGELOG = {"]
    for v in notable(versions)[:KEEP]:
        out.append("\t{")
        out.append("\t\tversion = %s," % lua_str(v["version"]))
        out.append("\t\titems = {")
        for item in v["items"]:
            out.append("\t\t\t%s," % lua_str(item))
        out.append("\t\t},")
        out.append("\t},")
    out.append("}")
    return "\n".join(out) + "\n"


def main():
    text = open(os.path.join(ROOT, "VERSION.txt"), encoding="utf-8").read()
    want = render(parse(text))
    path = os.path.join(ROOT, "Changelog.lua")
    if "--check" in sys.argv:
        have = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
        if have != want:
            print("Changelog.lua is out of date: run python3 tools/changelog_lua.py")
            sys.exit(1)
        return
    with open(path, "w", encoding="utf-8") as f:
        f.write(want)
    print("wrote Changelog.lua")


if __name__ == "__main__":
    main()
