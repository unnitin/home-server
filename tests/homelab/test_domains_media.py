"""media_staging_list, media_library_stats, photos_stats and updates_check.

TEST_MODE=1: API answers come from tests/fixtures/http/, commands from
tests/fixtures/exec/. Staging lives in a temporary folder standing in for the
media tier; diskutil is asked about it through a stub.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from homelab import config, secrets  # noqa: E402
from homelab.adapters import diskutil  # noqa: E402
from homelab.adapters import http as hhttp  # noqa: E402
from homelab.domains import media, photos, updates  # noqa: E402

KEYS = {"plex_token": "plx-0123456789", "jellyfin_api_key": "jf-0123456789ab"}
KEYS["immich_api_key"] = "imm-0123456789"


@pytest.fixture
def box(tmp_path, monkeypatch):
    """The manifest with its tiers under tmp_path, all mounted, keys set."""
    monkeypatch.setenv("TEST_MODE", "1")
    (tmp_path / "http").mkdir()
    (tmp_path / "exec").mkdir()
    monkeypatch.setenv("HOMELAB_HTTP_FIXTURES", str(tmp_path / "http"))
    monkeypatch.setenv("HOMELAB_EXEC_FIXTURES", str(tmp_path / "exec"))
    for name, value in KEYS.items():
        monkeypatch.setenv(secrets.env_name(name), value)
    secrets.forget_cache()
    real = config.load()
    m = real.model_copy(deep=True)
    mounted = {}
    for name, tier in m.storage.tiers.items():
        tier.mount = str(tmp_path / name)
        Path(tier.mount).mkdir()
        mounted[tier.mount] = True
    for module in (media, photos, updates):
        monkeypatch.setattr(module.config, "load", lambda: m)

    def volume(mount):
        if not mounted.get(mount):
            return None
        return diskutil.Volume(mount=mount, name="v", device="disk9s1", fs="apfs")

    monkeypatch.setattr(diskutil, "volume", volume)
    monkeypatch.setattr(
        diskutil, "usage", lambda vol: diskutil.Usage(total=10**12, free=6 * 10**11)
    )
    box = type("Box", (), {})()
    box.m, box.tmp, box.mounted, box.real = m, tmp_path, mounted, real
    box.media_root = Path(m.storage.tiers[m.media.tier].mount)

    def http_fixture(key, status, data=None):
        rec = {"status": status}
        if data is not None:
            rec["json"] = data
        (tmp_path / "http" / f"{key}.json").write_text(json.dumps(rec))

    box.http = http_fixture
    return box


def touch(path: Path, age_h: float = 0, size: int = 10) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"x" * size)
    t = time.time() - age_h * 3600
    os.utime(path, (t, t))


# --- staging --------------------------------------------------------------------------


def test_staging_when_the_media_tier_is_gone(box):
    box.mounted[str(box.media_root)] = False
    r = media.staging_list()
    assert r["status"] == "fail" and "not mounted" in r["summary"]


def test_staging_lists_waiting_and_stuck_files(box):
    staging = box.media_root / box.m.media.staging
    touch(staging / "movies" / "Arrival (2016).mkv", age_h=1)
    touch(staging / "tv-shows" / "Show.S01E02.mkv", age_h=30)
    touch(staging / "tv-shows" / ".DS_Store", age_h=30)
    r = media.staging_list()
    libs = r["data"]["libraries"]
    assert libs["movies"]["waiting"] == 1 and libs["tv"]["waiting"] == 1
    assert libs["tv"]["files"]["type"] == "data"  # file names are untrusted
    assert [c["id"] for c in r["checks"]] == ["media.staging.tv"]


def test_staging_lists_failed_files_by_date(box):
    touch(box.media_root / box.m.media.failed / "20261126" / "bad.mkv")
    r = media.staging_list(library="movies")
    assert r["data"]["failed"]["content"][0] == {
        "name": "bad.mkv",
        "mb": 0.0,
        "age_h": 0.0,
        "date": "20261126",
    }
    assert "media.failed" in [c["id"] for c in r["checks"]]


def test_staging_unknown_library(box):
    assert media.staging_list(library="music")["status"] == "error"


# --- libraries ------------------------------------------------------------------------


def test_library_stats_with_keys(box):
    """The fixtures' folders are /Volumes/warmstore/...: point the tier back there."""
    box.m.storage.tiers[box.m.media.tier].mount = box.real.storage.tiers[
        box.m.media.tier
    ].mount
    box.mounted[box.real.storage.tiers[box.m.media.tier].mount] = True
    r = media.library_stats()
    assert r["status"] == "ok", r["checks"]
    plex = {s["title"]: s for s in r["data"]["plex"]["sections"]}
    assert plex["Movies"]["items"] == 412
    assert r["data"]["jellyfin"]["counts"]["movie"] == 410
    assert r["data"]["plex"]["recently_added"]["type"] == "data"
    assert "412 movies" in r["summary"]


def test_library_stats_flags_folders_outside_the_manifest(box):
    r = media.library_stats()  # the tier moved, the servers' folders didn't
    assert {"media.plex.paths", "media.jellyfin.paths"} <= {
        c["id"] for c in r["checks"]
    }


def test_library_stats_without_keys_says_how_to_add_them(box, monkeypatch):
    monkeypatch.setattr(secrets, "get", lambda name: None)
    r = media.library_stats()
    assert r["status"] == "warn"
    assert any("import-plex" in h for h in r["hints"])
    assert any("jellyfin_api_key" in h for h in r["hints"])


def test_a_failed_jellyfin_scan(box):
    box.http(
        "GET_8096_ScheduledTasks",
        200,
        [
            {
                "Key": "RefreshLibrary",
                "State": "Idle",
                "LastExecutionResult": {"Status": "Failed", "EndTimeUtc": "x"},
            }
        ],
    )
    r = media.library_stats()
    assert "media.jellyfin.scan" in [c["id"] for c in r["checks"]]


# --- photos ---------------------------------------------------------------------------


def test_photos_stats(box):
    r = photos.stats()
    lib = r["data"]["library"]
    assert (lib["photos"], lib["videos"], lib["users"]) == (41250, 1830, 2)
    assert r["data"]["queues"]["smartSearch"]["backlog"] == 121
    assert "photos.queue.faceDetection" in [c["id"] for c in r["checks"]]
    assert r["data"]["tier"]["used_pct"] == 40.0
    assert "Person" not in json.dumps(r)


def test_photos_without_a_key(box, monkeypatch):
    monkeypatch.setattr(secrets, "get", lambda name: None)
    r = photos.stats()
    assert r["status"] == "warn" and r["data"]["version"] == "2.1.0"
    assert any("immich_api_key" in h for h in r["hints"])


def test_photos_when_immich_is_down(box):
    box.http("GET_2283_api_server_version", None)
    r = photos.stats()
    assert r["status"] == "fail"


def test_photos_tier_missing(box):
    box.mounted[box.m.storage.tiers[box.m.photos.tier].mount] = False
    assert "photos.tier" in [c["id"] for c in photos.stats()["checks"]]


# --- updates --------------------------------------------------------------------------


GITHUB = "GET_1_github_immich-app_immich_releases_latest"


def test_updates_current_immich(box):
    box.http(GITHUB, 200, {"tag_name": "v2.1.0"})
    r = updates.check()
    assert r["data"]["immich"] == {
        "running": "2.1.0",
        "image_tag": "v2.1.0",
        "latest": "v2.1.0",
    }
    assert "updates.immich" not in [c["id"] for c in r["checks"]]
    assert {"colima", "docker"} <= {w["name"] for w in r["data"]["homebrew"]["watched"]}


def test_updates_a_major_immich_release(box):
    box.http(GITHUB, 200, {"tag_name": "v3.0.1"})
    r = updates.check()
    msg = next(c["message"] for c in r["checks"] if c["id"] == "updates.immich")
    assert "v3.0.1" in msg and "major" in msg and r["data"]["immich"]["major_change"]


def test_updates_github_unreachable_is_unknown_not_an_error(box):
    box.http(GITHUB, None)
    r = updates.check()
    assert r["data"]["immich"]["latest"] is None and r["status"] != "error"


def test_updates_an_unpinned_immich(box, monkeypatch):
    box.http(GITHUB, 200, {"tag_name": "v2.1.0"})
    monkeypatch.setattr(updates, "_immich_tag", lambda m: "release")
    assert "updates.immich.pin" in [c["id"] for c in updates.check()["checks"]]


def test_the_github_lookup_never_sends_anything_in_test_mode(box):
    box.http(GITHUB, 200, {"tag_name": "v9"})
    from homelab.adapters import releases

    assert releases.latest("immich") == "v9"
    assert (
        hhttp.fixture_key(
            "GET", "http://localhost:1/github/immich-app/immich/releases/latest"
        )
        == GITHUB
    )
