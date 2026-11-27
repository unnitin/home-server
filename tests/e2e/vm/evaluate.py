#!/usr/bin/env python3
"""Judge a deploy rehearsal (Phase 0 onward) from its output folder.

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

    mcp_code = after.get("mcp_initialize_http")
    check(  # from Phase 3 a request needs a token: 401 without one is an answer
        "MCP answers initialize on 127.0.0.1:18765",
        mcp_code in ("200", "401"),
        f"HTTP {mcp_code}" + (" (token required)" if mcp_code == "401" else ""),
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
    p3 = load(run / "vm" / "phase3" / "phase3.json")
    if p3 is not None:
        evaluate_phase3(p3, check)
    p2 = load(run / "vm" / "phase2" / "phase2.json")
    if p2 is not None:
        evaluate_phase2(p2, check)
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


PHASE2_TOOLS = {
    "system_overview",
    "storage_status",
    "storage_plan_recovery",
    "service_status",
    "history_query",
    "incident_list",
    "memory_recall",
    "memory_note",
    "docs_search",
    "runbook_get",
    "media_items",
}


def evaluate_phase2(p2: dict[str, Any], check) -> None:
    """The Phase 2 acceptance, as measured inside the VM (guest/phase2_checks.sh)."""
    check(
        "Snapshot job wrote the state database",
        p2.get("snapshots_by_job", 0) >= 1,
        f"{p2.get('snapshots_by_job')} snapshots before the checks",
    )
    check(
        "Snapshot job runs every 15 minutes",
        p2.get("job_interval_900"),
        "launchctl print: run interval = 900 seconds",
    )
    mcp = p2.get("mcp") or {}
    missing = PHASE2_TOOLS - set(mcp.get("tools") or [])
    check(
        "MCP serves the Phase 2 tools",
        bool(mcp) and not missing,
        f"{len(mcp.get('tools') or [])} tools"
        + (f", missing {sorted(missing)}" if missing else ""),
    )
    calls = mcp.get("calls") or {}
    broken = sorted(
        n
        for n, c in calls.items()
        if c.get("is_error") or c.get("status") in (None, "error")
    )
    check(
        "Phase 2 tools answer with envelopes",
        bool(calls) and not broken,
        "all answered" if not broken else f"errors: {broken}",
    )
    overview = calls.get("system_overview") or {}
    check(
        "system_overview under 2 KB",
        0 < (overview.get("bytes") or 0) < 2048,
        f"{overview.get('bytes')} bytes",
        required=False,
    )
    check(
        "Instructions and context served",
        (mcp.get("instructions_words") or 0) > 0
        and "homelab://topology" in (mcp.get("resources") or [])
        and "triage" in (mcp.get("prompts") or []),
        f"{mcp.get('instructions_words')} words, {len(mcp.get('resources') or [])} "
        f"resources, {len(mcp.get('prompts') or [])} prompts",
    )
    rows = {r["id"]: r for r in p2.get("incidents") or []}
    opened = [rows.get(i) for i in p2.get("opened") or []]
    fast = [r for r in opened if r and r["component"] == "faststore"]
    check(
        "Unmounting faststore opens an incident",
        p2.get("unmounted") and bool(fast),
        f"unmounted: {p2.get('unmounted')}, opened: "
        + ", ".join(f"#{r['id']} {r['title']}" for r in opened if r),
    )
    resolved = set(p2.get("resolved") or [])
    check(
        "Remounting resolves it",
        p2.get("remounted") and bool(fast) and all(r["id"] in resolved for r in fast),
        f"remounted: {p2.get('remounted')}, resolved: {sorted(resolved)}",
    )
    check(
        "History answers from the snapshots",
        (p2.get("history_samples") or 0) >= 2,
        f"{p2.get('history_samples')} samples of storage.faststore.mounted",
    )


T1_PROBED = {
    "service_restart",
    "service_start",
    "media_process",
    "power_ensure",
    "logs_collect",
    "memory_note",
}


def _job_state(block: dict) -> str:
    return (((block or {}).get("job") or {}).get("job") or {}).get("state", "")


def _int(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return -1


def evaluate_phase3(p3: dict[str, Any], check) -> None:
    """The Phase 3 acceptance, as measured inside the VM (guest/phase3_checks.sh)."""
    check(
        "A request without a token is refused",
        p3.get("no_token_http") == "401",
        f"HTTP {p3.get('no_token_http')}",
    )
    sc = p3.get("scopes") or {}
    obs, ops = sc.get("observe") or {}, sc.get("ops") or {}
    obs_restart = obs.get("restart_default") or {}
    check(
        "An observe token sees no T1 tool and can't call one",
        bool(obs.get("tools"))
        and not obs.get("t1_seen")
        and obs_restart.get("is_error"),
        f"{len(obs.get('tools') or [])} tools, T1 seen: {obs.get('t1_seen')}, "
        f"restart refused: {obs_restart.get('is_error')}",
    )
    ops_restart = ops.get("restart_default") or {}
    check(
        "An ops token sees the actions, and they default to a dry run",
        set(ops.get("t1_seen") or []) == T1_PROBED
        and (ops_restart.get("data") or {}).get("dry_run") is True,
        f"T1 seen: {len(ops.get('t1_seen') or [])}/{len(T1_PROBED)}, default: "
        f"{(ops_restart.get('data') or {}).get('dry_run')}",
    )
    jf = p3.get("jellyfin") or {}
    check(
        "service_restart restarts Jellyfin",
        _job_state(jf) == "done"
        and jf.get("pid_before") not in (None, "")
        and jf.get("pid_after") not in (None, "", jf.get("pid_before"))
        and "Healthy" in (jf.get("health") or ""),
        f"job {_job_state(jf) or 'none'}, PID {jf.get('pid_before')} -> "
        f"{jf.get('pid_after')}, health {jf.get('health')!r}",
    )
    px = p3.get("plex") or {}
    check(
        "A job survives an MCP server restart",
        _job_state(px) == "done" and px.get("identity_http") == "200",
        f"Plex restart job {_job_state(px) or 'none'} after kickstart -k of the "
        f"server, Plex HTTP {px.get('identity_http')}",
    )
    rows = (((p3.get("audit") or {}).get("data") or {}).get("calls")) or []
    clients = {r.get("client") for r in rows}
    denied = [r for r in rows if r.get("outcome") == "denied"]
    check(
        "Every call is audited, refused ones too",
        {"rehearsal-observe", "rehearsal-ops"} <= clients and bool(denied),
        f"{len(rows)} rows, clients {sorted(c for c in clients if c)}, "
        f"{len(denied)} denied",
    )
    su = p3.get("sudoers") or {}
    check(
        "The sudo rule installs and allows pmset only",
        su.get("install_rc") == 0
        and su.get("check_rc") == 0
        and su.get("diskutil_allowed") is False
        and su.get("other_value_allowed") is False,
        f"install {su.get('install_rc')}, check {su.get('check_rc')}, diskutil "
        f"allowed: {su.get('diskutil_allowed')}, other pmset value allowed: "
        f"{su.get('other_value_allowed')}",
    )
    pw = p3.get("power") or {}
    dry = (pw.get("dry") or {}).get("data") or {}
    check(
        "power_ensure puts a drifted setting back",
        "displaysleep" in (dry.get("drift") or {})
        and (pw.get("run") or {}).get("status") == "ok"
        and pw.get("displaysleep_after") == "1",
        f"drift {sorted(dry.get('drift') or [])}, run "
        f"{(pw.get('run') or {}).get('status')}, displaysleep now "
        f"{pw.get('displaysleep_after')}",
    )
    bundle = p3.get("bundle") or {}
    result = ((bundle.get("job") or {}).get("job") or {}).get("result") or {}
    check(
        "logs_collect builds a bundle",
        _job_state(bundle) == "done",
        f"job {_job_state(bundle) or 'none'}"
        + (f", {(result.get('content') or {}).get('bytes')} bytes" if result else ""),
    )
    runs = p3.get("runs") or {}
    steady = all(
        _int(a) > 0 and _int(a) == _int(b)
        for a, b in (runs.get("plex", [None, None]), runs.get("jellyfin", [None, None]))
    )
    check(
        "Plex and Jellyfin jobs stay in the foreground (D32)",
        steady,
        f"runs over the checks: plex {runs.get('plex')}, "
        f"jellyfin {runs.get('jellyfin')}",
    )


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
