#!/usr/bin/env python3
"""Prove that sandbox or deploy work did not modify real homelab data.

  data_guard.py snapshot OUT.json [--root PATH ...] [--mode-dir PATH ...]
  data_guard.py verify BEFORE.json AFTER.json

Take a snapshot before touching anything (a VM rehearsal, a deploy, a
container experiment), another one afterwards, and `verify` the pair.

Read-only by construction: it only lstat()s files under the guarded roots and
reads the backups it hashes. The one file it writes, the manifest, is refused
if it would land inside a guarded root.

`verify` sorts every difference into one of three buckets:
  expected   - churn the running services cause on their own: new nightly
               backups, live database files, new phone uploads
  review     - legitimate in principle but worth a human look: a backup that
               rotated out, an original removed after the trash was emptied
  unexpected - anything else; verify exits 1
"""

from __future__ import annotations

import argparse
import fnmatch
import glob
import hashlib
import json
import os
import socket
import stat
import sys
import time
from pathlib import Path
from typing import Any

FASTSTORE = os.environ.get("DATA_GUARD_FASTSTORE", "/Volumes/faststore")
DEFAULT_ROOTS = [
    f"{FASTSTORE}/immich/upload",
    f"{FASTSTORE}/immich/library",
    f"{FASTSTORE}/immich/profile",
    f"{FASTSTORE}/immich/backups",
    f"{FASTSTORE}/immich-database-copy-*",
    f"{FASTSTORE}/plex/metadata/Plug-in Support/Databases",
    f"{FASTSTORE}/jellyfin/config",
    f"{FASTSTORE}/takeout-downloads",
    f"{FASTSTORE}/tmp/takeout-processed",
]
# Directories whose mode and owner matter even though their contents are live
# (Postgres refuses to start if its data directory is not 0700/0750).
DEFAULT_MODE_DIRS = [
    f"{FASTSTORE}/immich",
    f"{FASTSTORE}/immich/database",
    f"{FASTSTORE}/plex",
    f"{FASTSTORE}/jellyfin",
]
SKIP_NAMES = {".DS_Store", ".fseventsd", ".Spotlight-V100", ".Trashes"}
# Churn-only subtrees of the Jellyfin config directory.
JELLYFIN_SKIP = ("cache/", "log/", "data/ScheduledTasks/")
HASH_GLOBS = [
    "immich-db-backup-*.sql.gz",
    "com.plexapp.plugins.library*.db-20*",
    "pre-restore-*/*",
]
# (change kind, glob on root-relative path, glob on root path)
EXPECTED_RULES = [
    ("added", "*", "*/immich/upload"),
    ("added", "immich-db-backup-*", "*/immich/backups"),
    ("added", "com.plexapp.plugins.library*.db-20*", "*/Databases"),
    ("changed", "com.plexapp.plugins.library*.db", "*/Databases"),
    ("changed", "com.plexapp.plugins.library*.db-wal", "*/Databases"),
    ("changed", "com.plexapp.plugins.library*.db-shm", "*/Databases"),
    ("changed", "data/jellyfin.db*", "*/jellyfin/config"),
    ("added", "data/jellyfin.db-*", "*/jellyfin/config"),
    ("removed", "data/jellyfin.db-*", "*/jellyfin/config"),
    ("changed", "data/splashscreen.png", "*/jellyfin/config"),
    ("added", "metadata/*", "*/jellyfin/config"),
    ("changed", "metadata/*", "*/jellyfin/config"),
]
REVIEW_RULES = [
    ("removed", "immich-db-backup-*", "*/immich/backups"),
    ("removed", "com.plexapp.plugins.library*.db-20*", "*/Databases"),
    ("removed", "*", "*/immich/upload"),
]


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(4 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def expand(paths: list[str]) -> list[str]:
    """Expand globs; keep literal paths even when missing (recorded as such)."""
    out: list[str] = []
    for p in paths:
        hits = sorted(glob.glob(p)) if glob.has_magic(p) else [p]
        out.extend(hits)
    return out


def scan_root(root: str, do_hash: bool) -> dict[str, Any]:
    out: dict[str, Any] = {"exists": False, "files": {}, "dirs": {}, "errors": []}
    if not os.path.isdir(root):
        return out
    out["exists"] = True
    is_jellyfin = root.rstrip("/").endswith("jellyfin/config")
    for dirpath, dirnames, filenames in os.walk(
        root, onerror=lambda e: out["errors"].append(str(e))
    ):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_NAMES)
        rel_dir = os.path.relpath(dirpath, root)
        rel_dir = "" if rel_dir == "." else rel_dir + "/"
        if is_jellyfin and rel_dir.startswith(JELLYFIN_SKIP):
            dirnames[:] = []
            continue
        try:
            out["dirs"][rel_dir or "."] = stat.S_IMODE(os.lstat(dirpath).st_mode)
        except OSError as exc:
            out["errors"].append(str(exc))
        for name in filenames:
            if name in SKIP_NAMES or name.startswith("._"):
                continue
            full = os.path.join(dirpath, name)
            rel = rel_dir + name
            try:
                st = os.lstat(full)
            except OSError as exc:
                out["errors"].append(str(exc))
                continue
            entry: dict[str, Any] = {
                "size": st.st_size,
                "mtime_ns": st.st_mtime_ns,
                "mode": stat.S_IMODE(st.st_mode),
                "ino": st.st_ino,
            }
            if (
                do_hash
                and stat.S_ISREG(st.st_mode)
                and any(fnmatch.fnmatch(rel, g) for g in HASH_GLOBS)
            ):
                try:
                    entry["sha256"] = sha256(full)
                except OSError as exc:
                    out["errors"].append(str(exc))
            out["files"][rel] = entry
    return out


def inside(path: str, root: str) -> bool:
    real, base = os.path.realpath(path), os.path.realpath(root)
    return real == base or real.startswith(base + os.sep)


def snapshot(
    out_path: str, roots: list[str], mode_dirs: list[str], do_hash: bool
) -> int:
    roots, mode_dirs = expand(roots), expand(mode_dirs)
    for root in roots + mode_dirs:
        if inside(out_path, root):
            print(f"refusing: manifest {out_path} is inside guarded {root}")
            return 2
    started = time.time()
    manifest: dict[str, Any] = {
        "created": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "host": socket.gethostname(),
        "roots": {},
        "mode_dirs": {},
    }
    for root in roots:
        r = manifest["roots"][root] = scan_root(root, do_hash)
        size = sum(f["size"] for f in r["files"].values())
        print(
            f"{root}: {len(r['files'])} files, {size / 1e9:.1f} GB"
            + (f", {len(r['errors'])} errors" if r["errors"] else "")
            + ("" if r["exists"] else " (missing)")
        )
    for d in mode_dirs:
        try:
            st = os.lstat(d)
            manifest["mode_dirs"][d] = [stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid]
        except OSError:
            manifest["mode_dirs"][d] = None
    Path(out_path).write_text(json.dumps(manifest))
    print(f"wrote {out_path} in {time.time() - started:.0f}s")
    return 0


def classify(kind: str, rel: str, root: str) -> str:
    for rules, label in ((EXPECTED_RULES, "expected"), (REVIEW_RULES, "review")):
        for k, pat, root_pat in rules:
            if (
                k == kind
                and fnmatch.fnmatch(rel, pat)
                and fnmatch.fnmatch(root, root_pat)
            ):
                return label
    return "unexpected"


def compare(before: dict[str, Any], after: dict[str, Any]) -> dict[str, list[str]]:
    buckets: dict[str, list[str]] = {"expected": [], "review": [], "unexpected": []}

    def add(kind: str, rel: str, root: str, detail: str = "") -> None:
        buckets[classify(kind, rel, root)].append(f"{kind:8} {root}/{rel}{detail}")

    for root, b in before["roots"].items():
        a = after["roots"].get(root)
        if a is None:
            buckets["unexpected"].append(f"unscanned {root} (not in after snapshot)")
            continue
        if b["exists"] and not a["exists"]:
            buckets["unexpected"].append(f"missing  {root} (whole root gone)")
            continue
        for rel, bf in b["files"].items():
            af = a["files"].get(rel)
            if af is None:
                add("removed", rel, root)
                continue
            diffs = []
            if af["size"] != bf["size"]:
                diffs.append(f"size {bf['size']}->{af['size']}")
            if af["mtime_ns"] != bf["mtime_ns"]:
                diffs.append("mtime")
            if af["mode"] != bf["mode"]:
                diffs.append(f"mode {bf['mode']:o}->{af['mode']:o}")
            if "sha256" in bf and af.get("sha256") not in (None, bf["sha256"]):
                diffs.append("sha256")
            if diffs:
                add("changed", rel, root, " (" + ", ".join(diffs) + ")")
        for rel in sorted(a["files"].keys() - b["files"].keys()):
            add("added", rel, root)
        for rel, bmode in b["dirs"].items():
            amode = a["dirs"].get(rel)
            if amode is not None and amode != bmode:
                buckets["unexpected"].append(
                    f"dirmode  {root}/{rel} {bmode:o}->{amode:o}"
                )
    for d, bm in before.get("mode_dirs", {}).items():
        am = after.get("mode_dirs", {}).get(d)
        if bm != am:
            buckets["unexpected"].append(f"dirmode  {d} {bm}->{am}")
    return buckets


def verify(before_path: str, after_path: str) -> int:
    before = json.loads(Path(before_path).read_text())
    after = json.loads(Path(after_path).read_text())
    buckets = compare(before, after)
    print(f"before: {before['created']}  after: {after['created']}")
    for label in ("unexpected", "review", "expected"):
        items = sorted(buckets[label])
        print(f"\n== {label}: {len(items)}")
        for line in items[:50]:
            print("  " + line)
        if len(items) > 50:
            print(f"  ... and {len(items) - 50} more")
    if buckets["unexpected"]:
        print("\nRESULT: FAIL - unexpected changes to guarded data")
        return 1
    print("\nRESULT: OK - no unexpected changes to guarded data")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("snapshot", help="record the current state")
    s.add_argument("out")
    s.add_argument("--root", action="append", dest="roots")
    s.add_argument("--mode-dir", action="append", dest="mode_dirs")
    s.add_argument("--no-hash", action="store_true")
    v = sub.add_parser("verify", help="compare two snapshots")
    v.add_argument("before")
    v.add_argument("after")
    args = ap.parse_args(argv)
    if args.cmd == "snapshot":
        roots = args.roots or DEFAULT_ROOTS
        mode_dirs = args.mode_dirs if args.mode_dirs is not None else []
        if not args.roots and args.mode_dirs is None:
            mode_dirs = DEFAULT_MODE_DIRS
        return snapshot(args.out, roots, mode_dirs, not args.no_hash)
    return verify(args.before, args.after)


if __name__ == "__main__":
    sys.exit(main())
