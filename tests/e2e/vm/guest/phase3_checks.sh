#!/usr/bin/env bash
# Phase 3 checks, INSIDE the VM, after the deploy and reboot (before Phase 2's,
# which stop Plex and Jellyfin):
#   - a request without a token gets 401; an observe token sees no T1 tool and
#     can't call one; an ops token sees them; an action's default is a dry run;
#   - service_restart restarts Jellyfin for real (its PID changes, it answers);
#   - a Plex restart job survives `launchctl kickstart -k` of the MCP server;
#   - every call is in the audit log, refused ones too;
#   - the scoped sudo rule installs (visudo); without a password only its pmset
#     commands run (diskutil and other pmset uses still ask for one); and
#     power_ensure puts a drifted setting back with it;
#   - logs_collect builds a bundle;
#   - D32: the Plex and Jellyfin jobs don't relaunch while the apps run.
#
#   VM_PASSWORD=… phase3_checks.sh REPO OUT_DIR
#
# Writes OUT_DIR/phase3/phase3.json. Uses the base image's public password for
# sudo; this is a disposable VM.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert_vm.sh
source "$HERE/assert_vm.sh" || exit 3

REPO="${1:?usage: phase3_checks.sh REPO OUT_DIR}"
OUT="${2:?usage: phase3_checks.sh REPO OUT_DIR}/phase3"
mkdir -p "$OUT"
PY=/opt/homebrew/bin/python3.11
URL=http://127.0.0.1:18765/mcp
UIDN=$(id -u)
PW="${VM_PASSWORD:-admin}"
cd "$REPO" || exit 1

runs() { launchctl print "gui/$UIDN/io.homelab.$1" 2>/dev/null | awk -F' = ' '/^\truns = /{print $2; exit}'; }
pid_on() { lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null | head -1; }
mcp() { "$PY" "$HERE/mcp_actions.py" "$@"; }
code() { curl -s -o /dev/null -m 10 -w '%{http_code}' "$@" || true; }

plex_runs_0=$(runs plex); jelly_runs_0=$(runs jellyfin)
started=$(date +%s)

OBS=$("$PY" -m homelab token create rehearsal-observe --scope observe | awk '/hlk_/ {print $1}')
OPS=$("$PY" -m homelab token create rehearsal-ops --scope ops | awk '/hlk_/ {print $1}')
no_token=$(code -X POST "$URL" -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' -d '{}')

mcp scopes "$URL" "$OBS" "$OPS" >"$OUT/scopes.json" 2>"$OUT/scopes.err"

# A real restart: Jellyfin
jelly_pid_0=$(pid_on 8096)
mcp call "$URL" "$OPS" service_restart '{"service": "jellyfin", "dry_run": false}' \
    >"$OUT/jellyfin-restart.json" 2>&1
job=$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1])).get("job_id") or "")' "$OUT/jellyfin-restart.json")
[[ -n "$job" ]] && mcp wait "$URL" "$OPS" "$job" 240 >"$OUT/jellyfin-job.json" 2>&1
jelly_pid_1=$(pid_on 8096)
jelly_health=$(curl -s -m 10 http://127.0.0.1:8096/health || true)

# A job that outlives the server: restart Plex, then restart the MCP server
mcp call "$URL" "$OPS" service_restart '{"service": "plex", "dry_run": false}' \
    >"$OUT/plex-restart.json" 2>&1
pjob=$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1])).get("job_id") or "")' "$OUT/plex-restart.json")
sleep 2
launchctl kickstart -k "gui/$UIDN/io.homelab.mcp" >"$OUT/mcp-kickstart.txt" 2>&1
for _ in $(seq 1 30); do [[ "$(code "$URL")" == 401 ]] && break; sleep 2; done
[[ -n "$pjob" ]] && mcp wait "$URL" "$OPS" "$pjob" 300 >"$OUT/plex-job.json" 2>&1
plex_http=$(code http://127.0.0.1:32400/identity)
"$PY" -m homelab jobs >"$OUT/jobs.txt" 2>&1

# The scoped sudo rule, and power_ensure with it
printf '%s\n' "$PW" | sudo -S -p '' pmset -a displaysleep 7 >/dev/null 2>&1
# shellcheck disable=SC2024  # the output file is the user's, on purpose
printf '%s\n' "$PW" | sudo -S -p '' env SUDO_USER="$(id -un)" \
    bash scripts/core/install_sudoers.sh --yes >"$OUT/sudoers-install.txt" 2>&1
sudoers_rc=$?
sudo -k
"$PY" -m homelab sudoers check >"$OUT/sudoers-check.txt" 2>&1
sudoers_check_rc=$?
# What runs WITHOUT a password: try read-only commands outside the rule.
# (`sudo -n -l CMD` would say yes for anything an admin may run with one.)
if sudo -n /usr/sbin/diskutil list >/dev/null 2>&1; then diskutil_allowed=true; else diskutil_allowed=false; fi
if sudo -n /usr/bin/pmset -g >/dev/null 2>&1; then other_value_allowed=true; else other_value_allowed=false; fi
mcp call "$URL" "$OPS" power_ensure '{}' >"$OUT/power-dry.json" 2>&1
mcp call "$URL" "$OPS" power_ensure '{"dry_run": false}' >"$OUT/power-run.json" 2>&1
displaysleep=$(pmset -g | awk '$1 == "displaysleep" {print $2}')

# A log bundle
mcp call "$URL" "$OPS" logs_collect '{"since": "1d", "dry_run": false}' >"$OUT/bundle.json" 2>&1
bjob=$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1])).get("job_id") or "")' "$OUT/bundle.json")
[[ -n "$bjob" ]] && mcp wait "$URL" "$OPS" "$bjob" 180 >"$OUT/bundle-job.json" 2>&1

mcp call "$URL" "$OPS" storage_ensure_layout '{}' >"$OUT/layout-dry.json" 2>&1
mcp audit "$URL" "$OPS" rehearsal-observe >"$OUT/audit-observe.json" 2>&1
mcp audit "$URL" "$OPS" rehearsal-ops >"$OUT/audit-ops.json" 2>&1

# D32: give the watchers time to show themselves, then count runs again
elapsed=$(( $(date +%s) - started ))
(( elapsed < 200 )) && sleep $(( 200 - elapsed ))
plex_runs_1=$(runs plex); jelly_runs_1=$(runs jellyfin)

"$PY" - "$OUT" <<PY
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])

def load(name):
    try:
        return json.loads((out / name).read_text())
    except Exception:
        return None

summary = {
    "no_token_http": "$no_token",
    "scopes": load("scopes.json"),
    "jellyfin": {"pid_before": "$jelly_pid_0", "pid_after": "$jelly_pid_1",
                 "health": "$jelly_health", "call": load("jellyfin-restart.json"),
                 "job": load("jellyfin-job.json")},
    "plex": {"call": load("plex-restart.json"), "job": load("plex-job.json"),
             "identity_http": "$plex_http",
             "mcp_restarted": (out / "mcp-kickstart.txt").exists()},
    "sudoers": {"install_rc": int("$sudoers_rc" or 1), "check_rc": int("$sudoers_check_rc" or 1),
                "diskutil_allowed": "$diskutil_allowed" == "true",
                "other_value_allowed": "$other_value_allowed" == "true"},
    "power": {"dry": load("power-dry.json"), "run": load("power-run.json"),
              "displaysleep_after": "$displaysleep"},
    "bundle": {"call": load("bundle.json"), "job": load("bundle-job.json")},
    "layout_dry": load("layout-dry.json"),
    "audit": {"observe": load("audit-observe.json"), "ops": load("audit-ops.json")},
    "runs": {"plex": ["$plex_runs_0", "$plex_runs_1"],
             "jellyfin": ["$jelly_runs_0", "$jelly_runs_1"]},
}
(out / "phase3.json").write_text(json.dumps(summary, indent=2))
print(json.dumps({k: v for k, v in summary.items() if k != "audit"}, indent=2)[:4000])
PY
