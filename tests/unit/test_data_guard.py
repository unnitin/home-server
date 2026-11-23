#!/usr/bin/env python3
"""Tests for tests/e2e/vm/data_guard.py: it must catch any change to real data."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "data_guard", REPO / "tests/e2e/vm/data_guard.py"
)
assert spec and spec.loader
dg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dg)

BACKUP = "immich-db-backup-20261123T020000-v2.1.0-pg16.10.sql.gz"


@pytest.fixture()
def fs(tmp_path: Path) -> Path:
    """A miniature faststore with the same layout as the real one."""
    root = tmp_path / "faststore"
    (root / "immich/upload/u1").mkdir(parents=True)
    (root / "immich/upload/u1/IMG_0001.jpg").write_bytes(b"jpeg" * 100)
    (root / "immich/backups").mkdir(parents=True)
    (root / "immich/backups" / BACKUP).write_bytes(b"dump" * 100)
    (root / "immich/database").mkdir(parents=True)
    os.chmod(root / "immich/database", 0o700)
    db = root / "plex/metadata/Plug-in Support/Databases"
    db.mkdir(parents=True)
    (db / "com.plexapp.plugins.library.db").write_bytes(b"live")
    (db / "com.plexapp.plugins.library.db-2026-11-21").write_bytes(b"backup")
    (root / "jellyfin/config/data").mkdir(parents=True)
    (root / "jellyfin/config/data/jellyfin.db").write_bytes(b"jf")
    (root / "jellyfin/config/cache").mkdir(parents=True)
    (root / "jellyfin/config/cache/img.jpg").write_bytes(b"c")
    return root


def args_for(fs: Path) -> list[str]:
    roots = [
        fs / "immich/upload",
        fs / "immich/backups",
        fs / "plex/metadata/Plug-in Support/Databases",
        fs / "jellyfin/config",
    ]
    out: list[str] = []
    for r in roots:
        out += ["--root", str(r)]
    out += ["--mode-dir", str(fs / "immich/database")]
    return out


def snap(fs: Path, out: Path) -> Path:
    assert dg.main(["snapshot", str(out), *args_for(fs)]) == 0
    return out


def run_verify(fs: Path, tmp_path: Path, mutate) -> tuple[int, dict]:
    before = snap(fs, tmp_path / "before.json")
    mutate(fs)
    after = snap(fs, tmp_path / "after.json")
    import json

    buckets = dg.compare(json.loads(before.read_text()), json.loads(after.read_text()))
    return dg.verify(str(before), str(after)), buckets


def test_unchanged_tree_passes(fs, tmp_path):
    rc, buckets = run_verify(fs, tmp_path, lambda f: None)
    assert rc == 0
    assert buckets == {"expected": [], "review": [], "unexpected": []}


def test_modified_original_fails(fs, tmp_path):
    def mutate(f):
        (f / "immich/upload/u1/IMG_0001.jpg").write_bytes(b"overwritten")

    rc, buckets = run_verify(fs, tmp_path, mutate)
    assert rc == 1
    assert any("IMG_0001.jpg" in x for x in buckets["unexpected"])


def test_chmod_of_original_fails(fs, tmp_path):
    rc, buckets = run_verify(
        fs, tmp_path, lambda f: os.chmod(f / "immich/upload/u1/IMG_0001.jpg", 0o755)
    )
    assert rc == 1
    assert any("mode 644->755" in x for x in buckets["unexpected"])


def test_database_dir_chmod_fails(fs, tmp_path):
    """The recursive chmod 755 in setup_direct_mounts.sh would break Postgres."""
    rc, buckets = run_verify(
        fs, tmp_path, lambda f: os.chmod(f / "immich/database", 0o755)
    )
    assert rc == 1
    assert any("immich/database" in x for x in buckets["unexpected"])


def test_backup_rewritten_in_place_is_caught_by_hash(fs, tmp_path):
    def mutate(f):
        p = f / "immich/backups" / BACKUP
        st = p.stat()
        p.write_bytes(b"DUMP" * 100)  # same size
        os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns))  # same mtime

    rc, buckets = run_verify(fs, tmp_path, mutate)
    assert rc == 1
    assert any("sha256" in x for x in buckets["unexpected"])


def test_new_upload_and_live_db_churn_are_expected(fs, tmp_path):
    def mutate(f):
        (f / "immich/upload/u1/IMG_0002.jpg").write_bytes(b"new")
        db = f / "plex/metadata/Plug-in Support/Databases"
        (db / "com.plexapp.plugins.library.db").write_bytes(b"live, changed")
        (f / "jellyfin/config/data/jellyfin.db").write_bytes(b"jf changed")
        (f / "jellyfin/config/cache/other.jpg").write_bytes(b"ignored")

    rc, buckets = run_verify(fs, tmp_path, mutate)
    assert rc == 0
    assert len(buckets["expected"]) == 3
    assert buckets["unexpected"] == []


def test_rotated_backup_is_review_not_failure(fs, tmp_path):
    rc, buckets = run_verify(
        fs, tmp_path, lambda f: (f / "immich/backups" / BACKUP).unlink()
    )
    assert rc == 0
    assert any(BACKUP in x for x in buckets["review"])


def test_unknown_new_file_in_backups_fails(fs, tmp_path):
    rc, _ = run_verify(
        fs, tmp_path, lambda f: (f / "immich/backups/surprise.txt").write_text("x")
    )
    assert rc == 1


def test_missing_root_fails(fs, tmp_path):
    import shutil

    rc, buckets = run_verify(
        fs, tmp_path, lambda f: shutil.rmtree(f / "jellyfin/config")
    )
    assert rc == 1
    assert any("whole root gone" in x for x in buckets["unexpected"])


def test_refuses_manifest_inside_guarded_root(fs):
    out = fs / "immich/upload/manifest.json"
    assert dg.main(["snapshot", str(out), *args_for(fs)]) == 2
    assert not out.exists()


def test_glob_roots_expand(fs, tmp_path):
    (fs / "immich-database-copy-20261103-222006").mkdir()
    (fs / "immich-database-copy-20261103-222006/PG_VERSION").write_text("16")
    out = tmp_path / "g.json"
    assert dg.main(["snapshot", str(out), "--root", str(fs / "immich-database-*")]) == 0
    import json

    roots = json.loads(out.read_text())["roots"]
    assert list(roots) == [str(fs / "immich-database-copy-20261103-222006")]


def test_snapshot_never_writes_inside_roots(fs, tmp_path):
    before = sorted(p for p in fs.rglob("*"))
    snap(fs, tmp_path / "m.json")
    assert sorted(p for p in fs.rglob("*")) == before
