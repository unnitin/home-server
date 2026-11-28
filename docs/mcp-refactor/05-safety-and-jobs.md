# 05 — Safety, Auth, Audit, Jobs, Secrets

Different LLMs follow instructions to very different degrees, and any of them can be prompt-injected through a log line or a filename. So **every safety property is enforced by the server**, and nothing depends on the system prompt.

## Risk tiers (`config/policy.yaml`)

```yaml
tiers:
  T0: { approval: none }                       # observe
  T1: { approval: none, dry_run_default: true, rate_limit: "10/min" }
  T2: { approval: out_of_band, plan_ttl: 15m }
  T3: { exposed: false }                       # enforced in code too

tools:                                         # every registered tool must appear here (test-enforced)
  system_overview: T0
  service_restart: T1
  updates_apply: T2
  photos_album_add: T1          # see escalate
  review_apply: T2
  # ...

locks:                                         # one mutation per resource at a time
  service:{name}: exclusive
  media: exclusive
  immich: exclusive        # updates_apply(immich) and photos_import_takeout can't overlap

guards:                                        # preconditions checked before T1/T2 run
  service_restart:immich: [ "storage.faststore.mounted", "service.colima.up" ]
  photos_import_takeout:  [ "storage.faststore.free_gb >= estimate * 1.3" ]
  updates_apply:immich:   [ "photos_backup_db.completed_within(24h)" ]

escalate:                                      # T1 calls that become T2 plans when any condition holds (08)
  photos_album_add: [ "album.shared", "count > curation.photos.direct_add_max" ]
  media_label:      [ "label in curation.media.access_labels" ]
  media_fix_match:  [ "item.already_matched" ]
  media_edit:       [ "field == content_rating", "field.has_value" ]
```

Startup fails if any registered tool is missing from `policy.yaml`, or if a T3-listed name is registered.

## Authentication and network exposure

**Requirement:** any of your tailnet devices can reach the server at `https://<mini>.<tailnet>.ts.net:8765/mcp`. Nothing else can: not the home LAN, and never the public internet.

**How (fixes D7):**
- The server listens on `127.0.0.1:18765` only, so the LAN has no path to it.
- `tailscale serve --bg --https=8765 http://127.0.0.1:18765` publishes it on the tailnet. Immich, Plex and the landing page are already reached this way. It's **Serve, never Funnel**, so it isn't on the internet.
- The internal and tailnet ports differ on purpose. `start_plex_safe.sh` and `start_jellyfin_safe.sh` both switch serve off for their own port while the app starts, which suggests that sharing one port number between serve and a backend has caused trouble on this machine.
- Tailscale issues and renews the HTTPS certificate (HTTPS is already enabled on the tailnet for Immich and Plex). The `~/.config/tailscale` cert files and the in-process TLS code go away.
- `tailscale serve` adds `Tailscale-User-Login` / `Tailscale-User-Name` headers. These identify the person behind the device and go into the audit log. They're for the record, not for authentication: any local process could set them on a loopback request, so the bearer token stays the lock.

**Keeping the mapping in place (fixes D17):** a `--bg` serve mapping survives reboots on its own. What removes it today is `enable_landing.sh`'s `tailscale serve reset` at every login. So:
- `remote_access.tailscale_serve` in the manifest becomes the only list of tailnet mappings, MCP included.
- `enable_landing.sh` stops resetting and only starts the landing page.
- One reconcile step adds missing mappings without touching the others. Like `enable_landing.sh` today, it adds an app's mapping only once the app answers, so it doesn't fight the Plex and Jellyfin start scripts. It's a bash script in Phase 0, `homelab serve apply` plus the `tailscale_serve_reconcile` tool later. It runs at boot after the services start, and on demand.
- `check_tailscale.sh` / `tailscale_status` compare the live mappings with the manifest, so "is the MCP reachable over the tailnet?" is answered by a check, not a guess.

**Narrowing who on the tailnet:** if family devices share the tailnet for Immich and Plex, add a tailnet ACL (grant) that allows `tcp:8765` on the mini only from your own user or devices. The ACL is the outer fence, and the bearer token is the lock.

**Bearer tokens, one per client:** `homelab token create --name macbook-claude --scopes ops` writes a hashed token to `state.db`. The client passes `Authorization: Bearer …`. Requests without a token are rejected.

| Scope | Tools visible | Typical client |
|---|---|---|
| `observe` | T0 core | Local small model, dashboards |
| `ops` | T0 + T1 | Day-to-day assistant |
| `admin` | T0 + T1 + T2 | Human-supervised sessions |
| `curator` | Curation tools at T0–T2 (T2 still needs your approval) + `memory_recall`, `job_status`, `plan_status` | Photo and movie curation, interactive or nightly (08) |

Visibility is filtered at `tools/list`, and the call is re-checked at `tools/call`. For stdio use on the Mac mini itself, the scope comes from an env var, defaulting to `observe`.

Tokens also carry `photo_access: metadata | thumbnails`, defaulting to `metadata`. **Decided: photos never leave the mini.** `photos_view` and `photos_describe` are registered only on a second, local-only listener (stdio, or `127.0.0.1:18766`, which `tailscale serve` never maps), and `thumbnails` tokens work only there. So no tailnet client and no cloud model can receive a photo, whatever its token says.

Curator tokens are also bound to one Immich user (`immich_user`), and the server calls Immich with that user's own key (08).

## Approvals for T2 (model-agnostic human-in-the-loop)

```
LLM ──updates_apply(target=immich)──► server
                                       ├─ builds plan (versions, backup step, rollback)
                                       ├─ stores plan {id, ttl 15m, status: pending}
                                       ├─ notifies human out-of-band (code never sent to the LLM)
◄── {status: approval_required, plan_id, summary, expires_at}

Human approves via ONE of:
  • harness UI: agent/ intercepts approval_required, shows the plan, asks y/N  (06-harness.md)
  • push: ntfy/Pushover notification with Approve/Reject action → POST /approve/{plan_id} (Tailscale-identified)
  • CLI on any tailnet device: `homelab plan approve <plan_id>`

LLM ──plan_execute(plan_id)──► server checks status==approved && !expired && args unchanged → runs (usually as a job)
```

- The LLM never sees an approval secret, so it can't approve its own plan. This doesn't rely on MCP elicitation, which most clients don't support yet.
- A plan is bound to a hash of its exact args. If the args change, a new plan is required.
- Approvals record who approved (Tailscale identity) and are audited.
- `approval_mode: local_only` lets T2 run without approval only for the stdio transport with `HOMELAB_ADMIN=1`, i.e. a human at the keyboard.

## Sudo

Several operations need root: `tailscale serve`, `mkdir` under `/Volumes`, `pmset`. Don't give the server process general sudo. Instead:
- Add `/etc/sudoers.d/homelab` with `NOPASSWD` for **exact argv patterns only**, e.g. `/opt/homebrew/bin/tailscale serve --bg --https=* http://localhost:*` and `/usr/bin/pmset -a sleep 0`.
- `exec.py` checks every sudo call against the same patterns before running it.
- `diskutil` gets no sudo rules at all, so the T3 boundary is enforced by the OS as well.
- `setup/` installs the sudoers file with `visudo -c` validation behind a separate confirmation.

## Audit

Every `tools/call` writes an `audit` row: client token name, Tailscale user, model name (if the harness sends `X-Homelab-Model`), tool, redacted args, tier, outcome, duration, plan/job ids. The row is mirrored as JSONL to `/Volumes/warmstore/logs/mcp/audit.jsonl` (when warmstore is mounted) for `logs_search`. `audit_recent` exposes it to the agent ("what did we change last night?").

## Long-running jobs

Problem: takeout imports (hours), image pulls (minutes), media processing and log bundles all outlast the ~60 s tool timeout most clients enforce.

**Job runner (`homelab/jobs.py`):**
- `jobs.start(kind, argv, lock, timeout)` spawns a detached subprocess with its own process group. Output goes to `log_root/jobs/{job_id}.log`. A row goes in `jobs`, and the call returns `job_id` immediately.
- Progress: a script can print `::progress 42.5` or `::stage extracting` lines. The runner parses them, and the takeout importer and processor get a few such lines added.
- It survives server restarts. On startup the runner reconciles `running` rows against live PIDs and marks orphans `failed(lost)`.
- Concurrency: the lock keys from `policy.yaml` are enforced, and at most 2 jobs run at once by default. The Mac mini also runs Plex transcoding and Immich ML.
- On completion it sends a push notification (optional) and appends an incident event.
- The tool returns `{status: "pending", job_id, hints: ["Call job_status(job_id) in ~60s"]}`.

## Secrets

- `IMMICH_API_KEY`, `PLEX_TOKEN` and `JELLYFIN_API_KEY` live in the **macOS Keychain** (`security add-generic-password -s homelab -a immich_api_key`). `adapters/secrets.py` reads them, falling back to `services/immich/.env` / env vars for tests.
- No tool returns a secret, and `config_get` strips `secret:` references. The redaction filter (`homelab/redact.py`) runs on every result and every audit row, with patterns for known key formats, `X-Plex-Token=`, `Bearer `, `password=` and the literal values of loaded secrets.
- `services/immich/.env.bak` exists locally (it's gitignored through `*.bak`). Tools must never read `.env*` files directly. Only `secrets.py` does.

## Prompt-injection surface

| Untrusted input | Reaches model via | Mitigation |
|---|---|---|
| Filenames in Staging | `media_staging_list` | Returned as JSON strings, length-capped, control chars stripped |
| Container/app logs | `service_logs`, `logs_search` | Wrapped as `data`. Line-capped and redacted |
| Takeout JSON metadata | job logs | Same |
| Notes written by an earlier (possibly injected) session | `memory_recall` | Wrapped as `data`, with actor + date shown. Notes can't change policy |
| Tool args from the LLM | every tool | Enums wherever possible. Paths are validated against manifest roots (no `..`, must sit under an allowed root). No shell strings, ever (fixes D13) |
| Release names, TMDB overviews, EXIF descriptions, album names from other Immich users, text a vision model reads in a photo | curation tools | Returned as data. Can't widen what a tool may do: match IDs must come from the server's own candidate list, and access labels and shared albums always need approval (08) |

The structural guarantee is that even a fully compromised model with an `admin` token can't destroy data: T3 doesn't exist in the server, `diskutil` has no sudo rule, and T2 needs a human.
