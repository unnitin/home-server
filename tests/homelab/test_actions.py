"""The T1 actions (homelab/domains/actions.py), on the fake mini.

Tiers live under tmp_path, commands and HTTP answers are fixtures, and job
submission is captured instead of run: no test quits Plex, maps a port or
touches /Volumes, whichever machine it runs on.
"""

from __future__ import annotations

import inspect
import json
import tarfile
from pathlib import Path

import pytest
from fakes import REPO, Mini  # noqa: E402

from homelab import config, jobs, tools
from homelab import exec as hexec
from homelab.adapters import diskutil, launchd
from homelab.adapters import http as hhttp
from homelab.domains import actions


@pytest.fixture
def box(tmp_path, monkeypatch):
    monkeypatch.setattr(launchd, "domain", lambda: "gui/501")
    real = config.load()
    m = real.model_copy(deep=True)
    mounted = {}
    for name, tier in m.storage.tiers.items():
        tier.mount = str(tmp_path / "vol" / name)
        Path(tier.mount).mkdir(parents=True)
        mounted[tier.mount] = True
    monkeypatch.setattr(config, "load", lambda *a, **k: m)

    def volume(mount):
        if not mounted.get(mount):
            return None
        return diskutil.Volume(mount=mount, name="v", device="disk9s1", fs="apfs")

    mini = Mini()
    mini.install(tmp_path, monkeypatch)
    monkeypatch.setattr(diskutil, "volume", volume)
    submitted = []

    def submit(kind, argv, **kw):
        hexec.check(argv)  # what the real submit refuses, this refuses
        submitted.append({"kind": kind, "argv": argv, **kw})
        return {
            "id": f"j-20261127-000000-{len(submitted):04x}",
            "kind": kind,
            "state": "queued",
            "progress": None,
            "stage": None,
            "requested_by": kw.get("requested_by"),
            "created_at": "2026-11-27T00:00:00Z",
            "started_at": None,
            "ended_at": None,
            "exit_code": None,
            "error": None,
        }

    monkeypatch.setattr(jobs, "submit", submit)
    hexec.RECORDED.calls.clear()
    b = type("Box", (), {})()
    b.m, b.mini, b.mounted, b.submitted, b.tmp = m, mini, mounted, submitted, tmp_path
    b.media_root = Path(m.storage.tiers[m.media.tier].mount)

    def unmount(tier):
        mounted[m.storage.tiers[tier].mount] = False

    def http(method, url, status, body=None):
        rec = {"status": status}
        if body is not None:
            rec["json"] = body
        key = hhttp.fixture_key(method, url)
        (tmp_path / "http" / f"{key}.json").write_text(json.dumps(rec))

    b.unmount, b.http = unmount, http
    return b


ACTING = ("kickstart", "--bg", "restart", "start", "sudo")


def acted() -> list:
    """Calls that would have changed something."""
    return [c for c in hexec.RECORDED.calls if any(word in c for word in ACTING)]


def test_every_action_is_a_dry_run_by_default():
    for name, fn in tools.ACTIONS.items():
        assert inspect.signature(fn).parameters["dry_run"].default is True, name


@pytest.mark.parametrize(
    "name,args",
    [
        ("service_restart", {"service": "plex"}),
        ("service_restart", {"service": "immich"}),
        ("service_restart", {"service": "landing"}),
        ("launchd_kickstart", {"label": "io.homelab.snapshot"}),
        ("media_process", {}),
        ("library_scan", {}),
        ("tailscale_serve_reconcile", {}),
        ("logs_collect", {}),
    ],
)
def test_a_dry_run_changes_nothing_and_returns_the_plan(box, name, args):
    box.mini.serve_missing = {8765}
    box.mini.install(box.tmp, pytest.MonkeyPatch())
    box.http("GET", "http://127.0.0.1:18765", 401)
    res = tools.call(name, **args)
    assert res["status"] in ("ok", "warn"), res
    assert res["data"].get("dry_run") is True and res["data"]["plan"], res
    assert "dry_run=false" in " ".join(res["hints"])
    assert acted() == [] and box.submitted == []


# --- services ----------------------------------------------------------------------


def test_restarting_a_native_app_is_a_job_on_its_service_lock(box):
    res = actions.service_restart("plex", dry_run=False)
    assert res["status"] == "pending" and res["job_id"]
    (job,) = box.submitted
    assert job["argv"][1].endswith("scripts/services/restart_native_app.sh")
    assert job["argv"][2:] == ["plex"] and job["lock"] == "service:plex"


def test_a_restart_is_refused_when_a_tier_it_needs_is_missing(box):
    box.unmount("warmstore")
    res = actions.service_restart("plex")
    assert res["status"] == "fail" and res["data"]["refused"]
    assert any(
        c["id"] == "guard.warmstore.mounted" and c["status"] == "fail"
        for c in res["checks"]
    )
    assert box.submitted == []


@pytest.mark.parametrize(
    "service,why",
    [
        ("mcp", "can't restart itself"),
        ("tailscale", "carries this connection"),
        ("colima", "Docker VM"),
    ],
)
def test_some_services_are_never_restarted_from_here(box, service, why):
    res = actions.service_restart(service, dry_run=False)
    assert res["status"] == "fail" and why in res["summary"]
    assert acted() == [] and box.submitted == []


def test_containers_restart_with_compose_restart_never_up(box):
    actions.service_restart("immich", dry_run=False)
    (job,) = box.submitted
    assert (
        job["argv"][:3] == ["docker", "compose", "-f"] and job["argv"][-1] == "restart"
    )


def test_immich_restart_needs_colima_up(box):
    box.mini.docker_down = True
    box.mini.install(box.tmp, pytest.MonkeyPatch())
    res = actions.service_restart("immich")
    assert res["status"] == "fail"
    assert any(c["id"] == "guard.colima.up" for c in res["checks"])


def test_a_job_service_restarts_with_kickstart_k(box):
    argv = ["launchctl", "kickstart", "-k", "gui/501/io.homelab.landing"]
    box.mini.cmd(argv)
    res = actions.service_restart("landing", dry_run=False)
    assert res["status"] == "ok", res
    assert tuple(argv) in hexec.RECORDED.calls


def test_a_held_job_is_never_started(box):
    box.mini.held = {"io.homelab.media.watcher"}
    box.mini.install(box.tmp, pytest.MonkeyPatch())
    res = actions.service_restart("media_watcher", dry_run=False)
    assert res["status"] == "fail" and "held" in res["summary"]
    res = actions.launchd_kickstart("io.homelab.media.watcher", dry_run=False)
    assert res["status"] == "fail" and "held" in res["summary"]
    assert acted() == []


def test_start_does_nothing_for_a_service_that_is_up(box):
    res = actions.service_start("jellyfin", dry_run=False)
    assert res["data"]["already_up"] and box.submitted == []


def test_start_runs_the_start_script_for_a_native_app_that_is_down(box):
    box.mini.http_down = {"jellyfin"}
    box.mini.install(box.tmp, pytest.MonkeyPatch())
    res = actions.service_start("jellyfin", dry_run=False)
    assert res["status"] == "pending"
    assert box.submitted[0]["argv"][1].endswith("start_jellyfin_safe.sh")


def test_kickstart_refuses_the_mcp_server(box):
    res = actions.launchd_kickstart("io.homelab.mcp", dry_run=False)
    assert res["status"] == "fail" and acted() == []


def test_kickstart_runs_a_periodic_job_now(box):
    box.mini.jobs["io.homelab.snapshot"] = {"state": "not running", "last_exit": 0}
    box.mini.install(box.tmp, pytest.MonkeyPatch())
    argv = ["launchctl", "kickstart", "gui/501/io.homelab.snapshot"]
    box.mini.cmd(argv)
    res = actions.launchd_kickstart("io.homelab.snapshot", dry_run=False)
    assert res["status"] == "ok" and tuple(argv) in hexec.RECORDED.calls


# --- media -------------------------------------------------------------------------


def stage(box, rel: str) -> Path:
    path = box.media_root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"x")
    return path


def test_media_process_needs_the_media_tier(box):
    box.unmount(box.m.media.tier)
    res = actions.media_process(dry_run=False)
    assert res["status"] == "fail" and box.submitted == []


def test_media_process_counts_what_waits_and_runs_one_job_on_the_media_lock(box):
    stage(box, "staging/movies/Dune.2021.2160p.mkv")
    dry = actions.media_process("movies")
    assert dry["data"]["waiting"] == {"movies": 1}
    res = actions.media_process("movies", dry_run=False)
    (job,) = box.submitted
    assert job["argv"][-1] == "--movies-only" and job["lock"] == "media"
    assert res["status"] == "pending"


def test_retry_moves_failed_files_back_and_queues_processing(box):
    f = stage(box, "staging/failed/20261126/Some.Movie.2020.mkv")
    dry = actions.media_retry_failed("movies")
    assert f.exists() and dry["data"]["plan"] and box.submitted == []
    res = actions.media_retry_failed("movies", dry_run=False)
    assert res["status"] == "pending" and res["data"]["moved"] == 1
    assert not f.exists()
    assert (box.media_root / "staging/movies/Some.Movie.2020.mkv").exists()
    assert box.submitted[0]["argv"][-1] == "--movies-only"


def test_retry_never_overwrites_a_file_in_staging(box):
    stage(box, "staging/failed/20261126/Same.mkv")
    stage(box, "staging/movies/Same.mkv")
    res = actions.media_retry_failed("movies", dry_run=False)
    assert res["data"]["moved"] == 0
    assert (box.media_root / "staging/failed/20261126/Same.mkv").exists()


def test_retry_is_refused_while_a_media_job_runs(box):
    stage(box, "staging/failed/20261126/A.mkv")
    lock = jobs.try_lock("res-media")
    try:
        res = actions.media_retry_failed("movies", dry_run=False)
    finally:
        lock.close()
    assert res["status"] == "fail" and "running" in res["summary"]
    assert (box.media_root / "staging/failed/20261126/A.mkv").exists()


def test_a_library_scan_is_refused_without_the_media_tier(box):
    """Plex and Jellyfin may drop items they can't find: never scan empty folders."""
    box.unmount(box.m.media.tier)
    res = actions.library_scan(dry_run=False)
    assert res["status"] == "fail"
    assert any(c["id"] == f"guard.{box.m.media.tier}.mounted" for c in res["checks"])


def test_a_library_scan_asks_both_servers(box):
    box.http("GET", "http://localhost:32400/library/sections/all/refresh", 200)
    box.http("POST", "http://localhost:8096/Library/Refresh", 204)
    res = actions.library_scan(dry_run=False)
    assert res["status"] == "ok" and res["data"]["started"] == ["plex", "jellyfin"]


def test_an_immich_job_starts_with_force_only_for_all(box):
    box.http("PUT", "http://localhost:2283/api/jobs/smartSearch", 200, {})
    res = actions.photos_run_job("smartSearch", dry_run=False)
    assert res["status"] == "ok"
    assert actions.photos_run_job("deleteEverything")["status"] == "error"


# --- tailnet, storage, power, logs ---------------------------------------------------


def test_serve_reconcile_maps_only_whats_missing_and_never_removes(box):
    box.mini.serve_missing = {8765}
    box.mini.install(box.tmp, pytest.MonkeyPatch())
    box.http("GET", "http://127.0.0.1:18765", 401)
    argv = ["tailscale", "serve", "--bg", "--https=8765", "http://127.0.0.1:18765"]
    box.mini.cmd(argv)
    res = actions.tailscale_serve_reconcile(dry_run=False)
    assert res["status"] == "ok" and res["data"]["changed"] == [8765], res
    served = [c for c in hexec.RECORDED.calls if "--bg" in c]
    assert served == [tuple(argv)]


def test_serve_reconcile_skips_a_backend_that_is_down(box):
    box.mini.serve_missing = {8765}
    box.mini.install(box.tmp, pytest.MonkeyPatch())
    box.http("GET", "http://127.0.0.1:18765", None)
    res = actions.tailscale_serve_reconcile(dry_run=False)
    assert res["data"]["changed"] == [] and acted() == []


def test_funnel_is_reported_not_left_quiet(box):
    box.mini.funnel = {443}
    box.mini.install(box.tmp, pytest.MonkeyPatch())
    res = actions.tailscale_serve_reconcile()
    assert res["status"] == "fail"
    assert any(c["id"] == "serve.443.funnel" for c in res["checks"])


def test_layout_reports_what_the_script_would_create(box):
    script = str(REPO / "scripts" / "storage" / "setup_direct_mounts.sh")
    box.mini.cmd(
        ["bash", script, "--dry-run"],
        "[INFO]  10:00:00 Would create /Volumes/warmstore/movies (mode 755)\n",
    )
    res = actions.storage_ensure_layout()
    assert res["data"]["folders"] == [
        {"path": "/Volumes/warmstore/movies", "mode": "755"}
    ]


def test_power_ensure_sets_only_the_drifted_setting(box):
    box.mini.pmset["sleep"] = "10"
    box.mini.install(box.tmp, pytest.MonkeyPatch())
    dry = actions.power_ensure()
    assert dry["data"]["drift"] == {"sleep": {"now": "10", "want": "0"}}
    argv = ["sudo", "-n", "/usr/bin/pmset", "-a", "sleep", "0"]
    (box.tmp / "exec" / f"{hexec.fixture_key(argv)}.json").write_text(
        json.dumps({"rc": 1, "stderr": "sudo: a password is required"})
    )
    res = actions.power_ensure(dry_run=False)
    assert res["status"] == "fail" and "install_sudoers" in " ".join(res["hints"])
    assert [c for c in hexec.RECORDED.calls if c[:1] == ("sudo",)] == [tuple(argv)]


def test_power_ensure_does_nothing_when_settings_match(box):
    res = actions.power_ensure(dry_run=False)
    assert res["status"] == "ok" and acted() == []


def test_logs_collect_runs_the_bundle_as_a_job(box):
    res = actions.logs_collect("12h", dry_run=False)
    assert res["status"] == "pending"
    assert box.submitted[0]["argv"] == [
        "python",
        "-m",
        "homelab",
        "bundle",
        "--since",
        "12h",
    ]
    assert actions.logs_collect("forever")["status"] == "error"


def test_the_bundle_is_redacted(box, tmp_path):
    from homelab import bundle

    logs = tmp_path / "launchd-logs"
    logs.mkdir()
    (logs / "homelab-plex.out").write_text("token X-Plex-Token=abcdef1234567890\n")
    res = bundle.build("1d", out_dir=tmp_path / "bundles", log_dir=logs)
    with tarfile.open(res["path"]) as tar:
        names = tar.getnames()
        text = (
            tar.extractfile(next(n for n in names if n.endswith("homelab-plex.out")))
            .read()
            .decode()
        )
    assert "abcdef1234567890" not in text
    assert any(n.endswith("system_overview.json") for n in names)
