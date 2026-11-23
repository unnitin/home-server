#!/usr/bin/env bash
# Record the state of the homelab jobs and services in the VM.
# Runs INSIDE the VM, as the logged-in user.
#
#   report.sh PHASE OUT_DIR [REPO]
#
# Writes OUT_DIR/PHASE/{summary.json,launchctl.txt,run_all.txt,...}.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert_vm.sh
source "$HERE/assert_vm.sh" || exit 3

PHASE="${1:?usage: report.sh PHASE OUT_DIR [REPO]}"
OUT="${2:?usage: report.sh PHASE OUT_DIR [REPO]}/$PHASE"
REPO="${3:-}"
mkdir -p "$OUT"
export NO_COLOR=1 TERM="${TERM:-dumb}"

launchctl list | awk 'NR == 1 || /io\.homelab\./' >"$OUT/launchctl.txt"
for label in $(awk '/io\.homelab\./ {print $3}' "$OUT/launchctl.txt"); do
    {
        echo "== $label"
        launchctl print "gui/$(id -u)/$label" 2>&1 |
            grep -E "state =|last exit code|runs =|program =|path =" || true
    } >>"$OUT/jobs.txt"
done
for f in /tmp/homelab-*.out /tmp/homelab-*.err; do
    [[ -f "$f" ]] && tail -n 40 "$f" >"$OUT/log-$(basename "$f")"
done

http_code() { curl -s -o /dev/null -m 10 -w '%{http_code}' "$@" || true; }

MCP_INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"rehearsal","version":"0"}}}'
mcp_http=$(http_code -X POST http://127.0.0.1:18765/mcp \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' -d "$MCP_INIT")
plex_http=$(http_code http://127.0.0.1:32400/identity)
jellyfin_health=$(curl -s -m 10 http://127.0.0.1:8096/health 2>/dev/null || true)
curl -s -m 10 http://127.0.0.1:8096/System/Info/Public >"$OUT/jellyfin-info.json" 2>/dev/null || true

PSQL="/Applications/Plex Media Server.app/Contents/MacOS/Plex SQLite"
PDB="/Volumes/faststore/plex/metadata/Plug-in Support/Databases/com.plexapp.plugins.library.db"
plex_movies="" plex_sections=""
# Read the restored database directly: the HTTP API needs a sign-in token,
# which a sandbox Plex never gets.
plex_q() { perl -e 'alarm shift; exec @ARGV' 60 "$PSQL" "file:$PDB?mode=ro" "$1" 2>/dev/null || true; }
if [[ -x "$PSQL" && -f "$PDB" ]]; then
    plex_movies=$(plex_q "select count(*) from metadata_items where metadata_type=1;")
    plex_sections=$(plex_q "select group_concat(name, '|') from library_sections;")
fi
JDB=/Volumes/faststore/jellyfin/config/data/jellyfin.db
jellyfin_series=""
if [[ -f "$JDB" ]]; then
    jellyfin_series=$(perl -e 'alarm shift; exec @ARGV' 60 sqlite3 "file:$JDB?mode=ro" \
        "select count(*) from BaseItems where Type like '%.Series';" 2>/dev/null || true)
fi

if [[ -n "$REPO" && -x "$REPO/diagnostics/run_all.sh" ]]; then
    (cd "$REPO" && perl -e 'alarm shift; exec @ARGV' 300 bash diagnostics/run_all.sh) >"$OUT/run_all.txt" 2>&1 || true
fi

mount | grep -E '/Volumes/' >"$OUT/mounts.txt" || true
db_mode=$(stat -f '%Lp' /Volumes/faststore/immich/database 2>/dev/null || echo missing)
warm=$(stat -f '%Sp %Su' /Volumes/warmstore 2>/dev/null || echo missing)

/opt/homebrew/bin/python3.11 - "$OUT" "$PHASE" "$mcp_http" "$plex_http" "$jellyfin_health" \
    "$plex_movies" "$plex_sections" "$jellyfin_series" "$db_mode" "$warm" <<'PY'
import json, pathlib, sys
(out, phase, mcp, plex, jf_health, plex_movies, plex_sections, jf_series, db_mode,
 warm) = sys.argv[1:]
jobs = {}
for line in pathlib.Path(out, "launchctl.txt").read_text().splitlines()[1:]:
    pid, status, label = line.split(None, 2)
    jobs[label] = {"pid": None if pid == "-" else int(pid), "status": int(status)}
summary = {
    "phase": phase,
    "jobs": jobs,
    "mcp_initialize_http": mcp,
    "plex_identity_http": plex,
    "jellyfin_health": jf_health.strip(),
    "plex_movies": int(plex_movies) if plex_movies.strip().isdigit() else None,
    "plex_sections": [s for s in plex_sections.strip().split("|") if s],
    "jellyfin_series": int(jf_series) if jf_series.strip().isdigit() else None,
    "immich_database_mode": db_mode,
    "warmstore_folder": warm,
}
info = pathlib.Path(out, "jellyfin-info.json")
try:
    j = json.loads(info.read_text())
    summary["jellyfin_version"] = j.get("Version")
    summary["jellyfin_wizard_done"] = j.get("StartupWizardCompleted")
except Exception:
    pass
pathlib.Path(out, "summary.json").write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
PY
