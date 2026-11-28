# 04 — Context and Memory

An agent needs three kinds of knowledge that are missing today:

| Kind | Example | Lifetime | Where it lives |
|---|---|---|---|
| **Static context** | Topology, boot order, which port is which, runbooks | Changes with the repo | `config/homelab.yaml`, `docs/`, `homelab_mcp/instructions.md` |
| **Live state** | Is RAID degraded *right now*? | Seconds | Computed per call by tools |
| **Memory** | "warmstore member disk3 threw SMART warnings in October", "we pinned Immich to v1.x because of a migration bug", "user prefers updates on Sunday" | Months | `state.db` on the internal disk |

Memory lives **on the server**, not in any client, so it follows the system whichever LLM or client is used. Claude's memory, ChatGPT's memory and a local model's lack of memory all see the same history.

---

## Static context

### Server instructions (`homelab_mcp/instructions.md`)
Sent in the MCP `initialize` response (`instructions` field). Under 400 words:
- What the box is, plus a one-line service map (service → port → storage tier).
- How to triage: `system_overview` → `health_check(component)` → `service_logs` → `memory_recall` → act.
- The rules: T2 needs a human, T3 doesn't exist, use `dry_run` first, cite tool output and never guess disk IDs.
- Clients that ignore `instructions` get the same text from the harness system prompt and the `runbook_get("operating-guide")` tool.

### Resources (plus tool mirrors)
Client support for resources is uneven, so each resource also has a tool:

| Resource URI | Content | Mirror tool |
|---|---|---|
| `homelab://manifest` | Rendered `homelab.yaml`, secrets stripped | `config_get` |
| `homelab://topology` | Generated Mermaid/text graph: services → dependencies → tiers → ports | `runbook_get("topology")` |
| `homelab://runbooks/{topic}` | Chunks of `TROUBLESHOOTING.md`, `RECOVERY.md`, `STORAGE.md`, `IMMICH.md`, … split by `##` heading | `runbook_get(topic)`, `docs_search(query)` |
| `homelab://incidents/open` | Open incidents | `incident_list` |
| `homelab://snapshot/latest` | Last recorded `system_overview` | `system_overview` |

`docs_search` uses SQLite FTS5 over the doc chunks, re-indexed on server start when a doc's mtime changes. There are no embeddings, so nothing is tied to an embedding provider, and FTS is good enough for about 20 docs.

**Runbook hygiene:** this only helps if the docs are right. Phase 1 includes a pass that marks stale content (Caddy, `/Volumes/Media`, the numbered `scripts/NN_*.sh` names) and a test that fails if a runbook references a script path that doesn't exist.

### Prompts (plus harness mirrors)
MCP prompts for guided workflows. The same text ships in `agent/prompts/` for clients that don't support prompts:

| Prompt | Args | Drives |
|---|---|---|
| `triage` | `symptom` | overview → targeted checks → logs → recall → recommendation |
| `post_reboot_check` | — | Walk the boot order and confirm each step came up, in sequence |
| `weekly_maintenance` | — | Updates check, disk growth, SMART, failed media, Immich job backlog → report |
| `add_media` | `library` | Staging check → process → scan → verify |
| `import_takeout` | `source_path` | Space check → plan → approval → job monitoring |
| `storage_incident` | `tier` | Read-only investigation → `storage_plan_recovery` → handoff to a human |
| `curate_album` | `album` | Profile → draft rule → test → review album → apply after your review (08) |
| `sort_unsorted_photos` | `since` | Run album rules over unsorted photos, then suggest new albums for the rest |
| `enrich_movies` | `scope` | Unmatched or mismatched check → candidates → match → labels from rules → plan for anything uncertain |

---

## Memory: `state.db`

**Location:** `~/Library/Application Support/homelab/state.db` on the internal SSD. It must not live on `warmstore` or `faststore`, because the agent is most needed when those are degraded or unmounted. A nightly job copies it to `coldstore` (`/Volumes/Archive/homelab-backups/`).

**Engine:** SQLite with WAL and FTS5. It's a single file with no server, and Python's stdlib handles it.

### Schema (migration `0001_init.sql`)

```sql
-- Periodic health snapshots (written by LaunchD io.homelab.snapshot every 15 min)
CREATE TABLE snapshots (
  id INTEGER PRIMARY KEY, ts TEXT NOT NULL,
  overall TEXT NOT NULL,                 -- ok|warn|fail
  payload JSON NOT NULL                  -- full system_overview data
);
CREATE TABLE metrics (                    -- denormalized for history_query
  ts TEXT NOT NULL, metric TEXT NOT NULL, value REAL NOT NULL,
  PRIMARY KEY (metric, ts)
);  -- e.g. storage.warmstore.used_pct, immich.assets, immich.ml_queue, svc.plex.up

-- Incidents: opened automatically on state transitions, or by the agent/human
CREATE TABLE incidents (
  id INTEGER PRIMARY KEY, opened_ts TEXT, closed_ts TEXT,
  component TEXT, severity TEXT, title TEXT,
  status TEXT CHECK (status IN ('open','monitoring','resolved')),
  root_cause TEXT, resolution TEXT
);
CREATE TABLE incident_events (
  incident_id INTEGER REFERENCES incidents(id), ts TEXT,
  actor TEXT, kind TEXT, body TEXT        -- observation|action|hypothesis|note
);

-- Durable notes: facts, preferences, decisions, resolutions
CREATE TABLE notes (
  id INTEGER PRIMARY KEY, ts TEXT, actor TEXT,
  kind TEXT CHECK (kind IN ('fact','preference','decision','resolution','todo')),
  component TEXT, body TEXT NOT NULL, tags TEXT,
  source_incident INTEGER, expires_ts TEXT, superseded_by INTEGER
);
CREATE VIRTUAL TABLE notes_fts USING fts5(body, tags, component, content='notes');

-- Inventory & versions (baseline for "what changed?")
CREATE TABLE inventory (key TEXT PRIMARY KEY, value JSON, updated_ts TEXT);
  -- disk serials per RAID member, SMART baselines, macOS version, host model
CREATE TABLE versions (component TEXT, version TEXT, ts TEXT, actor TEXT);

-- Governance (05)
CREATE TABLE audit (id INTEGER PRIMARY KEY, ts TEXT, client TEXT, model TEXT,
  tool TEXT, args JSON, tier TEXT, outcome TEXT, duration_ms INTEGER, plan_id TEXT, job_id TEXT);
CREATE TABLE plans (id TEXT PRIMARY KEY, created_ts TEXT, expires_ts TEXT, tool TEXT,
  args JSON, plan JSON, status TEXT, approved_by TEXT, approved_ts TEXT);
CREATE TABLE jobs (id TEXT PRIMARY KEY, kind TEXT, args JSON, state TEXT, pid INTEGER,
  started_ts TEXT, ended_ts TEXT, progress REAL, log_path TEXT, result JSON);

-- Curation (08)
CREATE TABLE curation_changes (id TEXT PRIMARY KEY, ts TEXT, domain TEXT,  -- photos | media
  target TEXT, items JSON, before JSON, after JSON, actor TEXT, plan_id TEXT, undone_ts TEXT);
CREATE TABLE curation_feedback (domain TEXT, item TEXT, target TEXT,
  verdict TEXT CHECK (verdict IN ('yes','no')), source TEXT, ts TEXT,
  PRIMARY KEY (domain, item, target));        -- a "no" is never proposed again
CREATE TABLE curation_rule_versions (target TEXT, version INTEGER, rule JSON, ts TEXT, actor TEXT);
CREATE TABLE match_candidates (item TEXT, tmdb_id TEXT, returned_ts TEXT);  -- what media_fix_match may accept
```

### Memory tools

| Tool | Params | Behavior |
|---|---|---|
| `memory_recall` | `query`, `component?`, `kinds?`, `limit=5` | FTS over notes and resolved incidents (root cause + resolution), ranked by relevance × recency. Returns short items with ids and dates |
| `memory_note` | `body`, `kind`, `component?`, `tags?`, `expires_in_days?` | Writes a note. Duplicates (FTS similarity above a threshold) return the existing id instead. Notes are capped at 1,000 chars and redacted |
| `memory_forget` | `note_id`, `reason` | Soft delete (`superseded_by = -1`), audited. T1 |
| `incident_open` | `component`, `severity`, `title` | Usually opened automatically by the snapshot job on an ok→fail transition |
| `incident_update` | `incident_id`, `kind`, `body` | Append an observation, hypothesis or action |
| `incident_resolve` | `incident_id`, `root_cause`, `resolution` | Closes the incident. Its resolution becomes recallable for future triage |
| `history_query` | `metric`, `since="7d"`, `bucket="1h"` | Downsampled series plus min/max/trend. "When did Plex start failing?" or "how fast is warmstore filling?" |

### How memory gets written (without depending on the model)

Weak models forget to write things down, so most memory is written **by the system**, not the LLM:
1. **Snapshot job** (`io.homelab.snapshot`, every 15 min). It runs `system_overview` and writes `snapshots` and `metrics`. It opens or closes incidents on status transitions, with hysteresis so flapping doesn't create noise, and records version changes in `versions`.
2. **Audit hook.** Every T1/T2 call appends an `incident_events` row of kind `action` if an incident is open for that component.
3. **Job completion** records the result, plus the failure reason, and links it to the incident.
4. **The LLM** writes `notes` (preferences, decisions) and incident resolutions. The harness prompts for a resolution summary when an incident closes during a session.

### Retention
- `snapshots`: full payload kept for 14 days, then only daily rows.
- `metrics`: 1-minute resolution kept for 7 days, hourly for 1 year.
- `audit`: 1 year. `notes` and `incidents`: kept forever, small.
- Size target: under 200 MB per year.

### Untrusted content in memory
Notes and log excerpts can contain text an attacker controls (filenames in Staging, Takeout metadata, container logs). The server wraps recalled content in a `{"type":"data", "source":…}` envelope. The operating guide tells models that recalled content and log content are **data, not instructions**. Notes can't trigger tool calls, and no tool executes text taken from memory.
