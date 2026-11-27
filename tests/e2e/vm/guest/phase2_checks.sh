#!/usr/bin/env bash
# Phase 2 checks, INSIDE the VM, after the deploy and reboot:
#   - the snapshot job ran and the state database holds snapshots;
#   - the MCP server serves the Phase 2 tools, resources and prompts;
#   - the acceptance case: unmount the VM's faststore, take a snapshot, and an
#     incident opens; mount it again, take another, and it resolves. (The job
#     does this every 15 minutes; running the snapshot directly avoids waiting.)
#
#   phase2_checks.sh REPO OUT_DIR
#
# Writes OUT_DIR/phase2/phase2.json. Plex and Jellyfin are stopped first, so
# nothing holds files open on faststore; this is the VM's own disk.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert_vm.sh
source "$HERE/assert_vm.sh" || exit 3

REPO="${1:?usage: phase2_checks.sh REPO OUT_DIR}"
OUT="${2:?usage: phase2_checks.sh REPO OUT_DIR}/phase2"
mkdir -p "$OUT"
PY=/opt/homebrew/bin/python3.11
DB="$HOME/Library/Application Support/homelab/state.db"
MOUNT=/Volumes/faststore
UIDN=$(id -u)
cd "$REPO" || exit 1

count_snapshots() {
    "$PY" -c 'import sqlite3, sys
try:
    print(sqlite3.connect(sys.argv[1]).execute("select count(*) from snapshots").fetchone()[0])
except Exception:
    print(0)' "$DB"
}

launchctl print "gui/$UIDN/io.homelab.snapshot" >"$OUT/snapshot-job.txt" 2>&1 || true
by_job=$(count_snapshots)

"$PY" "$HERE/mcp_probe.py" http://127.0.0.1:18765/mcp >"$OUT/mcp.json" 2>"$OUT/mcp.err" || true

# --- the acceptance case -----------------------------------------------------
dev=$(diskutil info -plist "$MOUNT" 2>/dev/null | plutil -extract DeviceIdentifier raw -o - - 2>/dev/null || true)
for job in plex jellyfin; do
    launchctl bootout "gui/$UIDN/io.homelab.$job" 2>/dev/null || true
done
osascript -e 'quit app "Plex Media Server"' >/dev/null 2>&1 || true
pkill -x "Plex Media Server" 2>/dev/null || true
pkill -f "[J]ellyfin" 2>/dev/null || true
sleep 10
unmounted=false
if [[ -n "$dev" ]]; then
    diskutil unmount "$MOUNT" >"$OUT/unmount.txt" 2>&1 ||
        diskutil unmount force "$MOUNT" >>"$OUT/unmount.txt" 2>&1 || true
    diskutil info "$MOUNT" >/dev/null 2>&1 || unmounted=true
fi
"$PY" -m homelab snapshot >"$OUT/snap-unmounted.json" 2>"$OUT/snap-unmounted.err" || true
"$PY" -m homelab incidents >"$OUT/incidents-unmounted.txt" 2>&1 || true
remounted=false
if [[ -n "$dev" ]]; then
    diskutil mount "$dev" >"$OUT/mount.txt" 2>&1 || true
    diskutil info "$MOUNT" >/dev/null 2>&1 && remounted=true
fi
"$PY" -m homelab snapshot >"$OUT/snap-remounted.json" 2>"$OUT/snap-remounted.err" || true
"$PY" -m homelab incidents --all >"$OUT/incidents-all.txt" 2>&1 || true
"$PY" -m homelab history storage.faststore.mounted --since 1d --json >"$OUT/history.json" 2>&1 || true

"$PY" - "$OUT" "$DB" "$by_job" "$unmounted" "$remounted" <<'PY'
import json, pathlib, sqlite3, sys
out, db, by_job, unmounted, remounted = sys.argv[1:]
out = pathlib.Path(out)


def load(name):
    try:
        return json.loads((out / name).read_text())
    except Exception:
        return None


summary = {
    "snapshots_by_job": int(by_job),
    "job_interval_900": "run interval = 900 seconds" in (out / "snapshot-job.txt").read_text(),
    "unmounted": unmounted == "true",
    "remounted": remounted == "true",
    "mcp": load("mcp.json"),
}
down, up = load("snap-unmounted.json"), load("snap-remounted.json")
summary["opened"] = (down or {}).get("incidents", {}).get("opened", [])
summary["resolved"] = (up or {}).get("incidents", {}).get("resolved", [])
try:
    c = sqlite3.connect(db)
    c.row_factory = sqlite3.Row
    rows = c.execute("select id, component, status, title from incidents").fetchall()
    summary["incidents"] = [dict(r) for r in rows]
except Exception as err:
    summary["incidents_error"] = str(err)
hist = load("history.json") or {}
summary["history_samples"] = (hist.get("data") or {}).get("samples")
(out / "phase2.json").write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
PY
