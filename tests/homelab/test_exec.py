"""homelab/exec.py: the allowlist, TEST_MODE fixtures, timeouts and cleaning.

Nothing here runs a real system command: TEST_MODE=1 is set for every test,
except the ones that run a harmless script the test writes itself.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from homelab import exec as hexec  # noqa: E402


@pytest.fixture(autouse=True)
def test_mode(monkeypatch, tmp_path):
    monkeypatch.setenv("TEST_MODE", "1")
    monkeypatch.setenv("HOMELAB_EXEC_FIXTURES", str(tmp_path / "fixtures"))
    (tmp_path / "fixtures").mkdir()
    hexec.RECORDED.calls.clear()
    return tmp_path / "fixtures"


# --- the allowlist ----------------------------------------------------------------

ALLOWED = [
    ["diskutil", "appleRAID", "list", "-plist"],
    ["diskutil", "info", "-plist", "/Volumes/faststore"],
    ["diskutil", "apfs", "list", "-plist"],
    ["diskutil", "list", "-plist", "external"],
    ["launchctl", "print", "gui/501/io.homelab.plex"],
    ["launchctl", "print-disabled", "gui/501"],
    ["launchctl", "list"],
    ["pmset", "-g", "custom"],
    ["tailscale", "status", "--json"],
    ["tailscale", "serve", "status", "--json"],
    ["docker", "compose", "-f", "services/immich/docker-compose.yml", "ps"],
    ["docker", "compose", "--project-directory=services/immich", "logs", "--tail=5"],
    ["docker", "ps", "--format", "json"],
    ["brew", "outdated", "--json=v2"],
    ["security", "find-generic-password", "-s", "homelab", "-a", "plex_token", "-w"],
    ["smartctl", "-a", "--json", "/dev/disk5"],
    ["sysctl", "-n", "kern.boottime"],
    ["sw_vers", "-productVersion"],
    ["ps", "-o", "etime=", "-p", "123"],
    ["bash", "diagnostics/check_storage.sh"],
    ["bash", str(REPO / "diagnostics" / "check_raid_status.sh")],
]


@pytest.mark.parametrize("argv", ALLOWED, ids=lambda a: " ".join(a)[:60])
def test_read_only_uses_are_allowed(argv):
    hexec.check(argv)


# The destructive storage commands (T3) and anything that changes state.
REFUSED = [
    ["diskutil", "eraseDisk", "APFS", "x", "disk5"],
    ["diskutil", "eraseVolume", "APFS", "x", "disk9s1"],
    ["diskutil", "appleRAID", "create", "mirror", "faststore", "APFS", "disk4"],
    ["diskutil", "appleRAID", "delete", "disk8"],
    ["diskutil", "appleRAID", "remove", "disk5s2", "disk8"],
    ["diskutil", "appleRAID", "add", "member", "disk5", "disk8"],
    ["diskutil", "partitionDisk", "disk5", "1", "GPT", "APFS", "x", "100%"],
    ["diskutil", "unmount", "/Volumes/faststore"],
    ["diskutil", "mount", "disk9s1"],
    ["diskutil", "rename", "Archive", "coldstore"],
    ["launchctl", "bootout", "gui/501/io.homelab.plex"],
    ["launchctl", "kickstart", "-k", "gui/501/io.homelab.plex"],
    ["launchctl", "disable", "gui/501/io.homelab.colima"],
    ["pmset", "-a", "sleep", "0"],
    ["tailscale", "serve", "reset"],
    ["tailscale", "funnel", "443", "on"],
    ["tailscale", "up"],
    ["docker", "compose", "-f", "x.yml", "down"],
    ["docker", "compose", "-f", "x.yml", "up", "-d"],
    ["docker", "rm", "-f", "immich_server"],
    ["docker", "exec", "immich_postgres", "psql"],
    ["docker", "compose", "--weird", "ps"],
    ["brew", "upgrade"],
    ["brew", "services", "restart", "x"],
    ["security", "add-generic-password", "-s", "homelab"],
    ["security", "delete-generic-password", "-s", "homelab"],
    ["smartctl", "-t", "long", "/dev/disk5"],
    ["smartctl", "-s", "off", "/dev/disk5"],
    ["sysctl", "-w", "kern.maxfiles=1"],
    ["sysctl", "kern.maxfiles=1"],
    ["bash", "-c", "rm -rf /"],
    ["bash", "scripts/storage/format_and_mount.sh"],
    ["bash", "scripts/storage/create_ssd_raid.sh"],
    ["bash", "diagnostics/../scripts/storage/format_and_mount.sh"],
    ["bash", "setup/setup_flags.sh"],
    ["bash", "scripts/core/health_check.sh"],  # only diagnostics/, in Phase 2
    ["bash", "diagnostics/no_such_script.sh"],
    ["rm", "-rf", "/Volumes/faststore"],
    ["sh", "-c", "true"],
    ["/usr/sbin/diskutil", "list"],  # a path, not a name from the allowlist
    ["python3", "-c", "print(1)"],
    ["ps", "aux"],
    ["ps", "-o", "command", "-p", "1;rm"],
]


@pytest.mark.parametrize("argv", REFUSED, ids=lambda a: " ".join(a)[:60])
def test_everything_else_is_refused(argv):
    with pytest.raises(hexec.ExecRefused):
        hexec.check(argv)


@pytest.mark.parametrize("argv", REFUSED[:6], ids=lambda a: " ".join(a)[:60])
def test_run_refuses_before_looking_for_a_fixture(argv, test_mode):
    with pytest.raises(hexec.ExecRefused):
        hexec.run(argv)
    assert hexec.RECORDED.calls == []


@pytest.mark.parametrize("bad", ["diskutil list", b"diskutil list", [], ()])
def test_a_shell_string_or_empty_argv_is_refused(bad):
    with pytest.raises(hexec.ExecRefused):
        hexec.check(bad)


def test_t3_scripts_are_refused_wherever_they_appear():
    for name in (
        "create_ssd_raid.sh",
        "create_nvme_raid.sh",
        "create_hdd_raid.sh",
        "delete_raid.sh",
        "format_and_mount.sh",
        "preclean_disks.sh",
        "cleanup_disks.sh",
        "rebuild_storage.sh",
    ):
        with pytest.raises(hexec.ExecRefused):
            hexec.check(["launchctl", "print", name])


def test_the_pattern_matches_the_repos_t3_scripts_and_nothing_else():
    names = {p.name for p in (REPO / "scripts").rglob("*.sh")}
    t3 = {n for n in names if hexec.T3_SCRIPT.search(n)}
    assert t3 == {
        "cleanup_disks.sh",
        "create_hdd_raid.sh",
        "create_nvme_raid.sh",
        "create_ssd_raid.sh",
        "format_and_mount.sh",
        "preclean_disks.sh",
        "rebuild_storage.sh",
    }


def test_programs_are_found_at_fixed_paths_only():
    for name, paths in hexec.PROGRAMS.items():
        assert paths and all(p.startswith("/") for p in paths), name
    assert set(hexec.PROGRAMS) == set(hexec.RULES)


# --- TEST_MODE fixtures -------------------------------------------------------------


def test_test_mode_returns_the_json_fixture(test_mode):
    key = hexec.fixture_key(["diskutil", "appleRAID", "list", "-plist"])
    assert key == "diskutil_appleRAID_list_-plist"
    (test_mode / f"{key}.json").write_text(
        json.dumps({"rc": 3, "stdout": "out", "stderr": "err"})
    )
    r = hexec.run(["diskutil", "appleRAID", "list", "-plist"])
    assert (r.rc, r.stdout, r.stderr, r.ok) == (3, "out", "err", False)
    assert hexec.RECORDED.calls == [("diskutil", "appleRAID", "list", "-plist")]


def test_an_out_fixture_is_stdout_with_exit_0(test_mode):
    (test_mode / "launchctl_list.out").write_text("PID\tStatus\tLabel\n")
    r = hexec.run(["launchctl", "list"])
    assert r.ok and r.stdout.startswith("PID")


def test_a_missing_fixture_is_an_error_that_names_the_file():
    with pytest.raises(hexec.FixtureMissing, match="launchctl_print_gui_7_nothing"):
        hexec.run(["launchctl", "print", "gui/7/nothing"])


def test_a_repo_path_is_keyed_relative_to_the_repo():
    absolute = hexec.fixture_key(["bash", str(REPO / "diagnostics/check_storage.sh")])
    assert absolute == hexec.fixture_key(["bash", "diagnostics/check_storage.sh"])
    assert absolute == "bash_diagnostics_check_storage.sh"


def test_a_long_key_is_shortened_but_stays_unique():
    a = hexec.fixture_key(["launchctl", "print", "x" * 200])
    b = hexec.fixture_key(["launchctl", "print", "x" * 199 + "y"])
    assert len(a) <= 120 and a != b


def test_the_committed_fixtures_are_valid():
    for path in hexec.FIXTURES.glob("*.json"):
        data = json.loads(path.read_text())
        assert set(data) <= {"rc", "stdout", "stderr", "timed_out"}, path.name


# --- really running (a script this test writes; no system command) ----------------


@pytest.fixture
def real_bash(monkeypatch, tmp_path):
    """Run for real, with diagnostics/ pointed at a temporary folder."""
    monkeypatch.delenv("TEST_MODE")
    diag = tmp_path / "diagnostics"
    diag.mkdir()
    monkeypatch.setattr(hexec, "DIAGNOSTICS", diag)

    def write(name, body):
        script = diag / name
        script.write_text("#!/usr/bin/env bash\n" + body)
        script.chmod(0o755)
        return str(script)

    return write


def test_output_is_captured_and_ansi_stripped(real_bash):
    script = real_bash("colors.sh", 'printf "\\033[32mOK\\033[0m\\n"; echo e >&2')
    r = hexec.run(["bash", script])
    assert (r.rc, r.stdout, r.stderr) == (0, "OK\n", "e\n")


def test_the_child_gets_no_color_a_fixed_path_and_the_manifest(real_bash):
    script = real_bash(
        "env.sh", 'echo "$NO_COLOR|$PATH|${HOMELAB_TIER_FASTSTORE_MOUNT:-}"'
    )
    r = hexec.run(["bash", script])
    no_color, path, mount = r.stdout.strip().split("|")
    assert no_color == "1" and path == hexec.SAFE_PATH
    assert mount == "/Volumes/faststore"


def test_a_caller_set_manifest_value_wins(real_bash, monkeypatch):
    monkeypatch.setenv("HOMELAB_TIER_FASTSTORE_MOUNT", "/tmp/x")
    script = real_bash("env.sh", 'echo "$HOMELAB_TIER_FASTSTORE_MOUNT"')
    assert hexec.run(["bash", script]).stdout.strip() == "/tmp/x"


def test_a_timeout_kills_the_program_and_its_children(real_bash, tmp_path):
    marker = tmp_path / "survived"
    script = real_bash("slow.sh", f'(sleep 3; touch "{marker}") & sleep 30\n')
    r = hexec.run(["bash", script], timeout=0.5)
    assert r.timed_out and r.rc == 124 and not r.ok
    import time

    time.sleep(3.5)
    assert not marker.exists(), "a child outlived the timeout"


def test_a_missing_program_is_rc_127_not_an_exception(monkeypatch):
    monkeypatch.delenv("TEST_MODE")
    monkeypatch.setitem(hexec.PROGRAMS, "colima", ("/nonexistent/colima",))
    r = hexec.run(["colima", "status"])
    assert r.rc == 127 and "not installed" in r.stderr
    assert not hexec.available("colima")


def test_non_utf8_output_does_not_raise(real_bash):
    script = real_bash("bytes.sh", "printf '\\xff\\xfe ok\\n'")
    assert "ok" in hexec.run(["bash", script]).stdout


def test_the_environment_is_not_shared_with_os_environ(real_bash):
    before = dict(os.environ)
    hexec.child_env({"X": "1"})
    assert dict(os.environ) == before
