#!/usr/bin/env python3
"""Judge a Phase 0 rehearsal from its output folder.

  evaluate.py RUN_DIR

Reads RUN_DIR/vm/{1-documents,2-after-reboot}/summary.json and the guard
reports, prints one line per check, writes RUN_DIR/result.json, and exits 1
if any required check failed.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

# Jobs that can't succeed in a macOS VM, and why.
EXPECTED_IN_VM = {
    "io.homelab.colima": "macOS VMs can't run nested VMs, so no Colima/Docker",
    "io.homelab.compose.immich": "needs Docker (see io.homelab.colima)",
}
# Jobs that fail on the mini too, for a known reason outside Phase 0. Shown,
# not judged, so a rehearsal measures the deploy.
KNOWN = {
    "io.homelab.media.watcher": "D21, warmstore is offline so it cannot make folders",
}
BLOCKED = {126: "permission denied (D19)", 127: "command not found"}


def load(path: Path) -> dict[str, Any] | None:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def guard_ok(path: Path) -> bool | None:
    if not path.exists():
        return None
    return "RESULT: OK" in path.read_text()


def evaluate(run: Path) -> tuple[list[dict[str, Any]], bool]:
    checks: list[dict[str, Any]] = []

    def check(name: str, ok: bool | None, detail: str, required: bool = True) -> None:
        checks.append({"check": name, "ok": ok, "detail": detail, "required": required})

    before = load(run / "vm/1-documents/summary.json")
    after = load(run / "vm/2-after-reboot/summary.json")
    if before is None or after is None:
        check("reports present", False, "missing summary.json from the VM")
        return checks, False

    blocked_before = sorted(
        label for label, j in before["jobs"].items() if j["status"] == 126
    )
    check(
        "D19 reproduced with repo in ~/Documents",
        bool(blocked_before),
        (
            f"{len(blocked_before)} jobs exited 126"
            if blocked_before
            else "no job hit 126"
        ),
        required=False,
    )

    for label, job in sorted(after["jobs"].items()):
        status = job["status"]
        if label in EXPECTED_IN_VM:
            check(
                label,
                None,
                f"exit {status}: expected in a VM, {EXPECTED_IN_VM[label]}",
                required=False,
            )
        elif status in BLOCKED:
            check(label, False, f"exit {status}: {BLOCKED[status]}")
        elif label in KNOWN and status != 0:
            check(label, None, f"exit {status}: known, {KNOWN[label]}", required=False)
        else:
            state = "running" if job["pid"] else "not running"
            check(label, status == 0, f"exit {status}, {state}")

    check(
        "MCP answers initialize on 127.0.0.1:18765",
        after.get("mcp_initialize_http") == "200",
        f"HTTP {after.get('mcp_initialize_http')}",
    )
    check(
        "Plex answers",
        after.get("plex_identity_http") == "200",
        f"HTTP {after.get('plex_identity_http')}",
    )
    check(
        "Jellyfin healthy",
        after.get("jellyfin_health") == "Healthy",
        repr(after.get("jellyfin_health")),
    )
    if (
        after.get("plex_movies") is not None
        or after.get("jellyfin_wizard_done") is not None
    ):
        check(
            "Plex backup restored",
            (after.get("plex_movies") or 0) > 0,
            f"{after.get('plex_movies')} movies in the restored database, "
            f"sections {after.get('plex_sections')}",
        )
        check(
            "Jellyfin config restored",
            after.get("jellyfin_wizard_done") is True,
            f"setup wizard done: {after.get('jellyfin_wizard_done')}, "
            f"version {after.get('jellyfin_version')}, "
            f"{after.get('jellyfin_series')} series",
        )
    check(
        "Immich database folder still 0700",
        after.get("immich_database_mode") == "700",
        f"mode {after.get('immich_database_mode')}",
    )
    vm_guard = guard_ok(run / "vm-guard.txt")
    check(
        "VM faststore unchanged by deploy and boot",
        vm_guard,
        "data_guard verify inside the VM",
    )
    host_guard = guard_ok(run / "host-guard.txt")
    if host_guard is not None:
        check("Host real data unchanged", host_guard, "data_guard verify on the mini")

    passed = all(c["ok"] for c in checks if c["required"])
    return checks, passed


def main() -> int:
    run = Path(sys.argv[1])
    checks, passed = evaluate(run)
    mark = {True: "PASS", False: "FAIL", None: "----"}
    for c in checks:
        opt = "" if c["required"] else " (info)"
        print(f"{mark[c['ok']]}  {c['check']}{opt}: {c['detail']}")
    print(f"\nREHEARSAL: {'PASS' if passed else 'FAIL'}  ({run})")
    (run / "result.json").write_text(
        json.dumps({"passed": passed, "checks": checks}, indent=2)
    )
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
