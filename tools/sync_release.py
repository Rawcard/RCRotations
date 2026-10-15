#!/usr/bin/env python3
"""Helpers for the nightly WoWSims sync (.github/workflows/sync-wowsims.yml).

    python3 tools/sync_release.py guard OLD_SIMDATA NEW_SIMDATA REPORT_JSON
        Exit 0 if the update is safe to release automatically, 1 if it needs a
        human look (prints why). Safe means: no rotation disappeared and
        nothing came through unsupported.

    python3 tools/sync_release.py bump SIMS_SHA
        Bump the patch version in both TOCs, add a VERSION.txt entry for the
        WoWSims commit, and print the new version.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOCS = [ROOT / "RCRotations.toc", ROOT / "RCRotations_Camelot.toc"]


def rotations(path):
    text = Path(path).read_text(encoding="utf-8") if Path(path).exists() else ""
    return set(re.findall(r'file = "([^"]+)"', text))


def guard(old_path, new_path, report_path):
    old, new = rotations(old_path), rotations(new_path)
    report = json.loads(Path(report_path).read_text(encoding="utf-8"))
    problems = []
    lost = sorted(old - new)
    if lost:
        problems.append("rotations removed: " + ", ".join(lost))
    if report.get("unsupported", 0) > 0:
        problems.append("%d unsupported conditions/actions" % report["unsupported"])
    if not new:
        problems.append("no rotations generated")
    if problems:
        print("needs review: " + "; ".join(problems))
        return 1
    added = sorted(new - old)
    print("safe to release" + (" (new: %s)" % ", ".join(added) if added else ""))
    return 0


def bump(sims_sha):
    version = None
    for toc in TOCS:
        text = toc.read_text(encoding="utf-8")
        m = re.search(r"^## Version: (\d+)\.(\d+)\.(\d+)", text, re.M)
        if not m:
            raise SystemExit("no version in " + toc.name)
        major, minor, patch = (int(x) for x in m.groups())
        version = "%d.%d.%d" % (major, minor, patch + 1)
        text = text[: m.start()] + "## Version: " + version + text[m.end():]
        toc.write_text(text, encoding="utf-8")
    vfile = ROOT / "VERSION.txt"
    old = vfile.read_text(encoding="utf-8")
    lines = old.split("\n", 1)
    rest = lines[1] if len(lines) > 1 else ""
    entry = (
        "%s\n\n# %s\n\nRotations updated from WoWSims (wowsims/mop@%s). Automatic release.\n\n"
        % (version, version, sims_sha[:10])
    )
    vfile.write_text(entry + rest.lstrip("\n"), encoding="utf-8")
    print(version)
    return 0


if __name__ == "__main__":
    if len(sys.argv) >= 5 and sys.argv[1] == "guard":
        sys.exit(guard(sys.argv[2], sys.argv[3], sys.argv[4]))
    if len(sys.argv) >= 3 and sys.argv[1] == "bump":
        sys.exit(bump(sys.argv[2]))
    print(__doc__)
    sys.exit(2)
