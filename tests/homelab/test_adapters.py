"""The adapters, against output recorded on the mini (tests/fixtures/exec/).

TEST_MODE=1 throughout: exec.py runs nothing and serves the fixtures. Cases
the mini doesn't show today (a degraded set, a rebuilding member, Funnel on)
come from fixtures each test writes.
"""

from __future__ import annotations

import json
import plistlib
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from homelab import exec as hexec  # noqa: E402
from homelab.adapters import brew, diskutil, docker, launchd  # noqa: E402
from homelab.adapters import system, tailscale  # noqa: E402
from homelab.adapters import http as hhttp  # noqa: E402


@pytest.fixture(autouse=True)
def test_mode(monkeypatch, tmp_path):
    monkeypatch.setenv("TEST_MODE", "1")
    extra = tmp_path / "fixtures"
    extra.mkdir()
    monkeypatch.setenv("HOMELAB_EXEC_FIXTURES", str(extra))
    monkeypatch.setattr(launchd, "domain", lambda: "gui/501")
    return extra


def write_plist(folder: Path, argv: list[str], data: dict, rc: int = 0) -> None:
    text = plistlib.dumps(data).decode()
    key = hexec.fixture_key(argv)
    (folder / f"{key}.json").write_text(json.dumps({"rc": rc, "stdout": text}))


# --- diskutil -------------------------------------------------------------------------


def test_raid_sets_as_recorded():
    (fast,) = diskutil.raid_sets()
    assert (fast.name, fast.device, fast.status, fast.level) == (
        "faststore",
        "disk8",
        "Online",
        "Mirror",
    )
    assert [m.device for m in fast.members] == ["disk7s2", "disk6s2"]
    assert [m.disk for m in fast.members] == ["disk7", "disk6"]
    assert fast.healthy


def test_a_degraded_set_with_a_rebuilding_member(test_mode):
    write_plist(
        test_mode,
        ["diskutil", "appleRAID", "list", "-plist"],
        {
            "AppleRAIDSets": [
                {
                    "Name": "warmstore",
                    "BSD Name": "disk10",
                    "Status": "Degraded",
                    "Level": "Mirror",
                    "Size": 10,
                    "Members": [
                        {"BSD Name": "disk4s2", "MemberStatus": "Online"},
                        {
                            "BSD Name": "disk5s2",
                            "MemberStatus": "Rebuilding",
                            "RebuildProgress": "42%",
                        },
                    ],
                }
            ]
        },
    )
    (s,) = diskutil.raid_sets()
    assert s.status == "Degraded" and not s.healthy
    assert s.members[1].status == "Rebuilding" and s.members[1].progress == "42%"


def test_a_mounted_volume_and_its_store():
    vol = diskutil.volume("/Volumes/faststore")
    assert vol is not None
    assert (vol.name, vol.device, vol.fs, vol.stores) == (
        "faststore",
        "disk9s1",
        "apfs",
        ("disk8",),
    )


def test_an_unmounted_tier_is_none_even_if_its_folder_exists():
    """warmstore's folder exists on the mini (D21, D31); diskutil says no."""
    assert diskutil.volume("/Volumes/warmstore") is None
    assert diskutil.volume("/Volumes/coldstore") is None


def test_a_volume_mounted_somewhere_else_is_not_this_mount(test_mode):
    write_plist(
        test_mode,
        ["diskutil", "info", "-plist", "/Volumes/x"],
        {"MountPoint": "/Volumes/x 1", "DeviceIdentifier": "disk9s1"},
    )
    assert diskutil.volume("/Volumes/x") is None


def test_usage_comes_from_the_mount(tmp_path):
    vol = diskutil.Volume(mount=str(tmp_path), name="t", device="disk0", fs="apfs")
    u = diskutil.usage(vol)
    assert u.total > 0 and 0 <= u.free <= u.total and 0 <= u.used_pct <= 100


def test_the_orphan_member_and_the_unreadable_disk():
    """The mini today: warmstore's set isn't assembled (D21)."""
    sets, disks = diskutil.raid_sets(), diskutil.external_disks()
    assert [p.device for p in diskutil.orphan_members(sets, disks)] == ["disk5s2"]
    assert [d.device for d in diskutil.unreadable_disks(disks)] == ["disk4"]


def test_unreadable_diskutil_output_is_an_error(test_mode):
    (test_mode / "diskutil_appleRAID_list_-plist.out").write_text("garbage")
    with pytest.raises(diskutil.DiskutilError):
        diskutil.raid_sets()


def test_a_diskutil_timeout_is_an_error(test_mode):
    key = hexec.fixture_key(["diskutil", "appleRAID", "list", "-plist"])
    (test_mode / f"{key}.json").write_text(json.dumps({"rc": 124, "timed_out": True}))
    with pytest.raises(diskutil.DiskutilError, match="timed out"):
        diskutil.raid_sets()


# --- launchd --------------------------------------------------------------------------


def test_a_running_keepalive_job():
    j = launchd.job("io.homelab.plex")
    assert j.loaded and j.running and not j.failed and not j.held
    assert (j.state, j.pid, j.last_exit, j.runs, j.keepalive) == (
        "running",
        23179,
        0,
        282,
        True,
    )


def test_a_held_job_is_disabled_and_not_loaded():
    j = launchd.job("io.homelab.colima")
    assert j.disabled
    # colima is held on the mini but was loaded when recorded; either way it's disabled
    assert j.held == (not j.loaded)


def test_an_unknown_job_is_not_loaded():
    j = launchd.job("io.homelab.nonexistent")
    assert not j.loaded and not j.running and j.last_exit is None


def test_print_disabled():
    held = launchd.disabled()
    assert held["io.homelab.colima"] and held["io.homelab.media.watcher"]
    assert held["io.homelab.plex"] is False


def test_parse_print_never_exited_and_interval():
    text = (
        "gui/501/io.homelab.updatecheck = {\n\tstate = not running\n"
        "\truns = 3\n\tlast exit code = 1\n\trun interval = 86400 seconds\n"
        "\tproperties = runatload\n}\n"
    )
    j = launchd.parse_print("io.homelab.updatecheck", text)
    assert j.failed and j.interval == 86400 and not j.keepalive and j.pid is None
    j = launchd.parse_print("x", "\tlast exit code = (never exited)\n")
    assert j.last_exit is None and not j.failed


def test_nested_blocks_do_not_override_top_level_keys():
    text = "\tstate = running\n\tpid = 5\n\tenvironment = {\n\t\tstate = bogus\n\t}\n"
    assert launchd.parse_print("x", text).state == "running"


# --- tailscale ------------------------------------------------------------------------


def test_tailscale_status_has_counts_not_peer_names():
    s = tailscale.status()
    assert s.connected and s.dns_name == "mini.example.ts.net"
    assert s.ips[0] == "100.64.0.1" and s.version.count(".") == 2
    assert s.peers == 5 and s.peers_online == 3
    assert "device-0" not in repr(s)


def test_serve_mappings_and_no_drift_against_the_manifest():
    live = tailscale.serve()
    assert [m.https for m in live] == [443, 2283, 8096, 8765, 32400]
    wanted = {
        443: "http://localhost:8080",
        2283: "http://localhost:2283",
        32400: "http://localhost:32400",
        8096: "http://localhost:8096",
        8765: "http://127.0.0.1:18765",
    }
    assert tailscale.drift(live, wanted).clean


def test_drift_finds_missing_wrong_extra_and_funnel():
    live = [
        tailscale.Mapping(443, "http://localhost:9999"),
        tailscale.Mapping(5000, "http://localhost:5000", funnel=True),
    ]
    d = tailscale.drift(live, {443: "http://localhost:8080", 8765: "http://x:1"})
    assert d.missing == (8765,) and d.extra == (5000,) and d.funnel == (5000,)
    assert d.wrong == ((443, "http://localhost:9999", "http://localhost:8080"),)
    assert not d.clean


def test_funnel_is_read_from_allow_funnel(test_mode):
    data = {
        "Web": {
            "h.ts.net:443": {"Handlers": {"/": {"Proxy": "http://localhost:8080"}}}
        },
        "AllowFunnel": {"h.ts.net:443": True},
    }
    (test_mode / "tailscale_serve_status_--json.out").write_text(json.dumps(data))
    assert tailscale.serve() == [tailscale.Mapping(443, "http://localhost:8080", True)]


def test_tailscale_not_running(test_mode):
    (test_mode / "tailscale_status_--json.json").write_text(
        json.dumps({"rc": 1, "stderr": "failed to connect to local Tailscale"})
    )
    s = tailscale.status()
    assert s.installed and not s.connected


# --- docker, brew, system -------------------------------------------------------------


def test_compose_project_as_recorded():
    p = docker.compose_ps(REPO / "services/immich/docker-compose.yml")
    assert p.runtime and len(p.containers) == 4
    by = {c.service: c for c in p.containers}
    assert by["immich-server"].ok and by["immich-server"].health == "healthy"
    assert by["redis"].ok and by["redis"].health == ""  # no healthcheck is fine
    assert all(c.restarts == 0 and c.started for c in p.containers)


def test_compose_when_the_runtime_is_down(test_mode):
    key = hexec.fixture_key(
        [
            "docker",
            "compose",
            "-f",
            str(REPO / "services/immich/docker-compose.yml"),
            "ps",
            "-a",
            "--format",
            "json",
        ]
    )
    (test_mode / f"{key}.json").write_text(
        json.dumps({"rc": 1, "stderr": "Cannot connect to the Docker daemon"})
    )
    p = docker.compose_ps(REPO / "services/immich/docker-compose.yml")
    assert not p.runtime and "Docker daemon" in p.error


def test_brew_outdated():
    out = brew.outdated()
    names = {o.name for o in out}
    assert {"colima", "docker"} <= names
    assert {o.name for o in out if o.cask} == {"jellyfin", "plex-media-server"}
    assert all(o.installed and o.current for o in out)


def test_power_settings_and_what_keeps_the_mini_awake():
    p = system.pmset()
    assert (p["sleep"], p["disksleep"], p["displaysleep"]) == ("0", "0", "1")
    assert system.sleep_preventers() == ["screensharingd", "caffeinate"]


def test_uptime_and_version():
    assert system.uptime_s(now=1793764777 + 3600) == 3600
    assert system.macos_version() == "15.8.2"


def test_smart_nvme_and_a_usb_bridge_that_cannot():
    s = system.smart("disk6")
    assert s.supported and s.passed and s.temperature_c == 41 and s.media_errors == 0
    s = system.smart("disk5")
    assert not s.supported and "not supported" in s.message.lower()


# --- http -----------------------------------------------------------------------------


@pytest.mark.parametrize(
    "url", ["http://example.com/", "https://api.github.com/x", "http://192.168.1.2:80/"]
)
def test_http_is_localhost_only(url):
    with pytest.raises(hhttp.NotLocal):
        hhttp.get(url)


def test_http_no_answer_is_a_response_not_an_exception(monkeypatch):
    monkeypatch.delenv("TEST_MODE")
    r = hhttp.get("http://127.0.0.1:9/", timeout=1)  # discard port: nothing listens
    assert r.status is None and not r.ok and r.error
