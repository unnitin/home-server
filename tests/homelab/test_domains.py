"""The domains behind the T0 tools, on a fake mini (fakes.py).

TEST_MODE=1: nothing runs and nothing is sent. Each test sets up the state it
needs (a tier gone, a service down, a mapping missing) and checks the result
a client would get: status, summary, checks and data.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fakes import REPO, Mini, Tier  # noqa: E402

from homelab import result as R  # noqa: E402
from homelab import tools  # noqa: E402
from homelab.adapters import launchd  # noqa: E402
from homelab.domains import health, logs, network, services, storage  # noqa: E402
from homelab.domains import system  # noqa: E402


@pytest.fixture
def mini(tmp_path, monkeypatch):
    monkeypatch.setattr(launchd, "domain", lambda: "gui/501")
    box = Mini()

    def install():
        box.install(tmp_path, monkeypatch)
        return box

    box.ready = install
    return box


def ids(result, status=None):
    return [
        c["id"] for c in result["checks"] if status is None or c["status"] == status
    ]


# --- result envelope ------------------------------------------------------------------


def test_the_envelope_shape_and_limits():
    checks = [R.check(f"x.{i}", "warn", "m" * 300, "x") for i in range(100)]
    r = R.make(checks, {"rows": list(range(5000))})
    assert list(r) == [
        "status",
        "summary",
        "data",
        "checks",
        "hints",
        "truncated",
        "job_id",
    ]
    assert r["status"] == "warn" and len(r["summary"]) < 200
    assert R.size(r) <= R.RESULT_MAX_BYTES and r["truncated"]


def test_the_envelope_redacts_everything():
    r = R.make(
        [R.check("a", "fail", "X-Plex-Token=abcd12345678", "a")],
        {"k": "Bearer abcdefghijkl"},
    )
    assert "abcd12345678" not in json.dumps(r) and "abcdefghijkl" not in json.dumps(r)


def test_ok_checks_are_hidden_unless_verbose():
    checks = [R.check("a", "ok", "fine", "a"), R.check("b", "fail", "bad", "b")]
    assert ids(R.make(checks)) == ["b"]
    assert ids(R.make(checks, verbose=True)) == ["b", "a"]  # worst first


# --- storage --------------------------------------------------------------------------


def test_a_healthy_box(mini):
    mini.ready()
    r = storage.status()
    assert r["status"] == "ok", r["checks"]
    t = r["data"]["tiers"]["faststore"]
    assert t["mounted"] and t["raid"]["status"] == "Online"
    assert t["usage"]["used_pct"] == 40.0 and t["raid"]["members"][0]["smart"]["passed"]


def test_warmstore_as_on_the_mini_today(mini):
    """Set not assembled, one half seen as an orphan, one disk unreadable (D21)."""
    mini.tiers["warmstore"] = Tier(mounted=False, set_status="", members=[])
    mini.orphans = ["disk6s2"]
    mini.unreadable = ["disk7"]
    mini.ready()
    r = storage.status()
    assert r["status"] == "fail"
    assert "storage.warmstore.mounted" in ids(r, "fail")
    assert {"storage.orphan.disk6s2", "storage.unreadable.disk7"} <= set(ids(r, "warn"))
    assert "storage_plan_recovery(tier='warmstore')" in r["hints"]
    assert r["data"]["loose"] == {
        "orphan_members": ["disk6s2"],
        "unreadable_disks": ["disk7"],
    }


def test_loose_disks_are_not_blamed_on_a_healthy_tier(mini):
    mini.tiers["warmstore"] = Tier(mounted=False, set_status="", members=[])
    mini.orphans = ["disk6s2"]
    mini.ready()
    assert storage.status("faststore")["status"] == "ok"
    assert "storage.orphan.disk6s2" in ids(storage.status("warmstore"), "warn")


def test_an_unmounted_archive_is_a_warning_not_a_failure(mini):
    mini.tiers["coldstore"] = Tier(mounted=False, set_status="", members=[])
    mini.ready()
    r = storage.status()
    assert r["status"] == "warn" and "storage.coldstore.mounted" in ids(r, "warn")


def test_usage_thresholds(mini):
    mini.tiers["faststore"].used_pct = 85  # warn 80, crit 90
    mini.tiers["warmstore"].used_pct = 96  # warn 85, crit 95
    mini.ready()
    r = storage.status()
    assert "storage.faststore.usage" in ids(r, "warn")
    assert "storage.warmstore.usage" in ids(r, "fail")


def test_a_degraded_mirror_and_a_failing_disk(mini):
    mini.tiers["faststore"] = Tier(
        set_status="Degraded", members=[("disk4s2", "Online"), ("disk5s2", "Failed")]
    )
    mini.smart_fail = {"disk5"}
    mini.ready()
    r = storage.status("faststore")
    assert {"storage.faststore.raid", "storage.faststore.smart.disk5"} <= set(
        ids(r, "fail")
    )
    assert "disk5s2 Failed" in json.dumps(r["checks"])


def test_a_rebuilding_member_is_a_warning(mini):
    mini.tiers["faststore"] = Tier(
        set_status="Degraded",
        members=[("disk4s2", "Online"), ("disk5s2", "Rebuilding")],
    )
    mini.ready()
    r = storage.status("faststore")
    assert "storage.faststore.raid" in ids(r, "warn")


def test_an_unknown_tier_is_an_error(mini):
    mini.ready()
    assert storage.status("archive")["status"] == "error"


# --- recovery plans -------------------------------------------------------------------


def test_nothing_to_recover_on_a_healthy_tier(mini):
    mini.ready()
    r = storage.plan_recovery("faststore")
    assert r["status"] == "ok" and r["data"]["steps"] == []


def test_a_plan_for_a_set_that_will_not_assemble(mini):
    mini.tiers["warmstore"] = Tier(mounted=False, set_status="", members=[])
    mini.orphans, mini.unreadable = ["disk6s2"], ["disk7"]
    mini.tiers["coldstore"] = Tier(mounted=False, set_status="", members=[])
    mini.ready()
    r = storage.plan_recovery("warmstore")
    d = r["data"]
    assert r["status"] == "fail" and not d["rebuild_needed"]
    text = json.dumps(d)
    assert "disk6s2" in text and "disk7" in text
    effects = {s["effect"] for s in d["steps"]}
    assert effects <= {
        "read-only",
        "none",
    }, "nothing that writes for a set that won't assemble"
    assert d["prechecks"][0]["status"] == "warn"  # no backup reachable (D23)
    assert any("diskutil eraseDisk" in n for n in d["never"])


def test_a_plan_for_a_degraded_mirror_names_the_set_and_warns(mini):
    mini.tiers["faststore"] = Tier(
        set_status="Degraded", members=[("disk4s2", "Online"), ("disk5s2", "Failed")]
    )
    mini.ready()
    d = storage.plan_recovery("faststore")["data"]
    assert d["rebuild_needed"]
    repair = [s for s in d["steps"] if "repairMirror" in s["command"]]
    assert repair and repair[0]["effect"].startswith("data loss")
    assert "disk20" in repair[0]["command"]  # the set's own id, from diskutil
    assert d["prechecks"][0]["status"] == "ok"  # coldstore is mounted


def test_the_planner_runs_nothing_that_changes_a_disk(mini):
    from homelab import exec as hexec

    mini.tiers["faststore"] = Tier(
        set_status="Degraded", members=[("disk4s2", "Online"), ("disk5s2", "Failed")]
    )
    mini.ready()
    hexec.RECORDED.calls.clear()
    storage.plan_recovery("faststore")
    programs = {c[0] for c in hexec.RECORDED.calls}
    assert programs <= {"diskutil", "smartctl"}
    assert all(
        c[1] in ("appleRAID", "list", "info") or c[0] == "smartctl"
        for c in hexec.RECORDED.calls
    )


# --- services -------------------------------------------------------------------------


def test_every_service_up(mini):
    mini.ready()
    r = services.status()
    states = {n: v["state"] for n, v in r["data"]["services"].items()}
    assert set(states.values()) <= {"up", "off"}, r["checks"]
    assert states["tailscale"] in ("up", "off")
    assert r["data"]["services"]["plex"]["uptime_s"] == ((2 * 24 + 3) * 60 + 4) * 60 + 5


def test_a_service_whose_health_url_fails_is_down(mini):
    mini.http_down = {"jellyfin"}
    mini.ready()
    r = services.status("jellyfin")
    assert r["status"] == "fail" and r["data"]["state"] == "down"
    assert "service_logs(service='jellyfin')" in r["hints"]


def test_a_held_job_with_the_service_running_anyway(mini):
    """Colima on the mini today: its job is held, Docker answers."""
    mini.held = {"io.homelab.colima"}
    mini.ready()
    v = services.status("colima")["data"]
    assert v["state"] == "up" and v["job"]["held"]


def test_a_held_job_with_nothing_running(mini):
    mini.held = {"io.homelab.media.watcher"}
    mini.ready()
    r = services.status("media_watcher")
    assert r["data"]["state"] == "held" and r["status"] == "warn"


def test_up_but_its_tier_is_missing_is_degraded(mini):
    mini.tiers["warmstore"] = Tier(mounted=False, set_status="", members=[])
    mini.ready()
    r = services.status("plex")
    assert r["data"]["state"] == "degraded"
    assert "service.plex.depends" in ids(r, "warn")


def test_containers_down(mini):
    mini.containers_bad = {"immich-server"}
    mini.ready()
    r = services.status("immich")
    assert r["data"]["state"] == "down" and "immich-server exited" in json.dumps(
        r["checks"]
    )


def test_docker_down(mini):
    mini.docker_down = True
    mini.ready()
    r = services.docker_containers()
    assert r["status"] == "fail" and "Docker daemon" in r["summary"]


def test_a_process_without_a_health_url_is_judged_by_its_port(mini):
    mini.not_listening = {18765}
    mini.ready()
    r = services.status("mcp")
    assert r["data"]["state"] == "down" and "18765" in r["summary"]


def test_launchd_jobs_lists_every_job(mini):
    mini.jobs["io.homelab.updatecheck"]["last_exit"] = 1
    mini.held = {"io.homelab.colima"}
    mini.ready()
    r = services.launchd_jobs()
    assert len(r["data"]["jobs"]) == len(fakes_m().boot_order)
    assert {"launchd.updatecheck", "launchd.colima"} <= set(ids(r, "warn"))


def fakes_m():
    from fakes import M

    return M


# --- logs -----------------------------------------------------------------------------


@pytest.fixture
def job_logs(tmp_path, monkeypatch):
    files = {}

    def fake(label):
        out = tmp_path / f"{label}.out"
        files[label] = out
        return {"stdout": out} if out.exists() else {}

    monkeypatch.setattr(logs, "job_logs", fake)
    return lambda label, text: (tmp_path / f"{label}.out").write_text(text)


def test_service_logs_tail_redact_and_mark_untrusted(mini, job_logs):
    mini.ready()
    job_logs(
        "io.homelab.plex",
        "".join(f"line {i}\n" for i in range(1000))
        + "GET /x?X-Plex-Token=abcd12345678\n",
    )
    r = logs.service_logs("plex", lines=5)
    (src,) = r["data"]["logs"]
    assert src["type"] == "data" and len(src["content"]) == 5
    assert src["content"][-1].endswith("X-Plex-Token=[REDACTED]")


def test_service_logs_grep_is_plain_text(mini, job_logs):
    mini.ready()
    job_logs("io.homelab.plex", "ok\nERROR one\n(.*)+ not a regex\nerror two\n")
    r = logs.service_logs("plex", grep="error")
    assert r["data"]["logs"][0]["content"] == ["ERROR one", "error two"]
    r = logs.service_logs("plex", grep="(.*)+")
    assert r["data"]["logs"][0]["content"] == ["(.*)+ not a regex"]


def test_service_logs_caps_lines_and_reports_missing_logs(mini, job_logs):
    mini.ready()
    assert logs.service_logs("landing")["status"] == "error"


def test_tail_reads_only_the_end_of_a_big_file(tmp_path):
    big = tmp_path / "big.log"
    big.write_text("x" * 5_000_000 + "\nlast\n")
    assert logs.tail(big, 1) == ["last"]


def test_logs_search(mini, job_logs, monkeypatch):
    mini.ready()
    job_logs("io.homelab.plex", "boot\nwarmstore not mounted\n")
    monkeypatch.setattr(
        logs,
        "log_files",
        lambda m: {
            "launchd": [Path(logs.job_logs("io.homelab.plex")["stdout"])],
            "modules": [],
        },
    )
    r = logs.logs_search("WARMSTORE", since="1h")
    assert r["data"]["matches"]["content"][0]["line"] == "warmstore not mounted"
    assert logs.logs_search("ab")["status"] == "error"
    assert logs.logs_search("abc", since="soon")["status"] == "error"


def test_job_log_paths_come_from_the_plist_templates():
    paths = logs.job_logs("io.homelab.media.watcher")
    assert paths["stdout"].name == "homelab-media-watcher.out"


# --- network, tailscale, power, config ------------------------------------------------


def test_check_port_is_local_only():
    assert network.check_port(22, host="192.168.1.1")["status"] == "error"
    assert network.check_port(22, host="example.com")["status"] == "error"


def test_check_port_open_and_closed():
    import socket

    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        s.listen()
        port = s.getsockname()[1]
        assert network.check_port(port, host="127.0.0.1")["data"]["open"]
    assert not network.check_port(port, host="127.0.0.1")["data"]["open"]


def test_check_port_names_the_owner():
    r = network.check_port(1, host="127.0.0.1")
    assert r["data"]["service"] is None
    assert network._owner(fakes_m(), 32400) == "plex"
    assert network._owner(fakes_m(), 8765) == "mcp (tailnet)"


def test_tailscale_as_the_manifest_says(mini):
    mini.ready()
    r = network.tailscale_status()
    assert r["status"] == "ok" and all(mp["served"] for mp in r["data"]["mappings"])
    assert r["data"]["peers"] == {"total": 2, "online": 1}


def test_tailscale_missing_mapping_and_funnel(mini):
    mini.serve_missing = {8765}
    mini.funnel = {443}
    mini.ready()
    r = network.tailscale_status()
    assert {"tailscale.serve.8765", "tailscale.funnel.443"} <= set(ids(r, "fail"))


def test_power_profile(mini):
    mini.pmset = {"sleep": "10", "womp": "0", "autorestart": "0"}
    mini.ready()
    r = system.power_status()
    assert "power.sleep" in ids(r, "fail") and "power.womp" in ids(r, "warn")
    assert any("autorestart" in h for h in r["hints"])


def test_config_get():
    r = system.config_get("power")
    assert list(r["data"]) == ["power"] and r["data"]["power"]["sleep"] == 0
    assert system.config_get("secrets")["status"] == "error"
    assert R.size(system.config_get()) <= R.RESULT_MAX_BYTES


# --- overview and the registry --------------------------------------------------------


def test_overview_of_a_healthy_box_is_small_and_ok(mini):
    mini.ready()
    r = health.overview()
    assert r["status"] == "ok", r["checks"]
    assert R.size(r) < 2048 and r["summary"].startswith("All good")


def test_overview_of_the_mini_today(mini):
    mini.tiers["warmstore"] = Tier(mounted=False, set_status="", members=[])
    mini.tiers["coldstore"] = Tier(mounted=False, set_status="", members=[])
    mini.orphans, mini.unreadable = ["disk6s2"], ["disk7"]
    mini.held = {
        "io.homelab.colima",
        "io.homelab.media.watcher",
        "io.homelab.compose.immich",
    }
    mini.ready()
    r = health.overview()
    assert r["status"] == "fail" and "warmstore" in r["summary"]
    assert len(r["checks"]) <= health.MAX_CHECKS and R.size(r) < 2048
    assert r["data"]["services"]["plex"] == "degraded"
    assert r["hints"][0] == "storage_plan_recovery(tier='warmstore')"


def test_a_crashing_tool_returns_an_error_envelope(monkeypatch):
    def boom(**kw):
        raise RuntimeError("kaboom")

    monkeypatch.setitem(tools.TOOLS, "power_status", boom)
    r = tools.call("power_status")
    assert r["status"] == "error" and "kaboom" in r["summary"]


def test_every_tool_is_registered_with_a_t0_name():
    import re

    for name in tools.TOOLS:
        assert re.fullmatch(r"[a-z][a-z0-9_]{0,63}", name)
    assert (REPO / "homelab" / "tools.py").exists()
