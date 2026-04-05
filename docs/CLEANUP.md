# 🧹 Code Cleanup Specification

**hakuna_mateti · home-server repo**

> Recommendations based on a review of `CLAUDE.md`, `README.md`, `ADMIN-GUIDE.md`, `scripts/README.md`, `docs/DIAGNOSTICS.md`, `.pre-commit-config.yaml`, and the repo file tree.
>
> Organised by priority. Nothing here changes runtime behaviour — these are structure, consistency, and hygiene fixes only.

---

## Priority Key

| Label | Meaning |
|---|---|
| 🔴 HIGH | Broken or actively misleading — fix before any new work |
| 🟡 MEDIUM | Inconsistency that will compound as the repo grows |
| 🟢 LOW | Polish and future-proofing |

---

## 🔴 HIGH — Broken Links in README.md

### Problem

`README.md` links to files that don't exist at the paths specified:

| Link in README.md | Actual file location | Status |
|---|---|---|
| `docs/QUICKSTART.md` | `README-QUICKSTART.md` (root) | ❌ broken |
| `docs/ENVIRONMENT.md` | `ENVIRONMENT.md` (root) | ❌ broken |
| `docs/SETUP.md` | unknown — not visible in file tree | ❌ broken or missing |

### Fix

Two options — pick one and apply consistently:

**Option A (preferred):** Move the root-level files into `docs/` to match where README points.
```
mv README-QUICKSTART.md docs/QUICKSTART.md
mv ENVIRONMENT.md docs/ENVIRONMENT.md
```

**Option B:** Update the README links to point to the actual file locations.
```markdown
<!-- change these in README.md -->
[Quick Start Guide](README-QUICKSTART.md)
[Environment Variables](ENVIRONMENT.md)
```

Also update `CLAUDE.md` which references `docs/ENVIRONMENT.md` in its environment variables section.

---

## 🔴 HIGH — LaunchD Naming Convention Violated in MCP Spec

### Problem

`CLAUDE.md` defines a clear LaunchD naming convention:
```
io.homelab.{service}.plist
```

All existing plists follow this: `io.homelab.powermgmt`, `io.homelab.storage`, `io.homelab.compose.immich`.

The MCP build spec (`docs/MCP.md`) uses `com.hakuna.mcp.plist` — breaking the convention before the file is even created.

### Fix

Rename in the spec and use this name when creating the file:
```
launchd/io.homelab.mcp.plist
```

Label inside the plist:
```xml
<key>Label</key>
<string>io.homelab.mcp</string>
```

Update `docs/MCP.md` accordingly before implementation begins.

---

## 🔴 HIGH — `coldstore` vs `Archive` Naming Ambiguity

### Problem

`CLAUDE.md` storage table lists the HDD tier as `coldstore / Archive` with mount point `/Volumes/Archive` — two names for the same thing with no canonical choice declared.

This matters because diagnostic scripts, LaunchD plists, and documentation each pick one or the other inconsistently. The MCP `check_storage` tool will surface whichever name the underlying scripts use, which may differ from what you type in chat.

### Fix

Pick one name and enforce it everywhere. Recommendation: **`coldstore`** (consistent with `faststore`/`warmstore` pattern), with mount at `/Volumes/coldstore`.

If the volume is already formatted as `Archive` and renaming the mount is disruptive, keep `/Volumes/Archive` as the mount point but update all documentation and script comments to refer to it as `coldstore` with a note that the volume label is `Archive` for historical reasons.

Update `CLAUDE.md` storage table:

```markdown
| `coldstore` | HDD RAID | `/Volumes/Archive` | Cold archive storage |
```
Remove the `/ Archive` ambiguity from the Name column.

---

## 🟡 MEDIUM — Root-Level Doc Sprawl

### Problem

Five guide-level markdown files sit at the repo root:

```
README.md
README-QUICKSTART.md
ADMIN-GUIDE.md
USER-GUIDE.md
USER-SETUP-GUIDE.md
ENVIRONMENT.md
```

Meanwhile `docs/` exists and already contains all the technical docs. The root is doing double-duty as both an entry point and a doc dump.

### Fix

Keep `README.md` at root — it's the GitHub landing page and should stay there. Move everything else into `docs/`:

```
docs/
  QUICKSTART.md        ← was README-QUICKSTART.md
  ENVIRONMENT.md       ← was ENVIRONMENT.md (root)
  ADMIN-GUIDE.md       ← was ADMIN-GUIDE.md (root)
  USER-GUIDE.md        ← was USER-GUIDE.md (root)
  USER-SETUP-GUIDE.md  ← was USER-SETUP-GUIDE.md (root)
  DIAGNOSTICS.md       ← already here
  AUTOMATION.md        ← already here
  MCP.md               ← new (from MCP build spec)
  CLEANUP.md           ← this file
  PLEX.md
  IMMICH.md
  TAILSCALE.md
  STORAGE.md
  SETUP.md
```

Update all cross-links in `README.md` and `CLAUDE.md` after the move.

---

## 🟡 MEDIUM — `core/health_check.sh` Overlaps with `diagnostics/`

### Problem

There are two separate health-checking systems:

- `scripts/core/health_check.sh` — described as "system health validation, manual troubleshooting"
- `diagnostics/` — 16 scripts doing comprehensive health checks

The scripts README describes `core/health_check.sh` as a standalone tool, but `diagnostics/run_all.sh` almost certainly covers the same ground in more depth. This creates confusion about which to run and risks the two drifting out of sync.

### Fix

Audit what `scripts/core/health_check.sh` does vs `diagnostics/run_all.sh`. Three outcomes are possible:

1. **`core/health_check.sh` is a subset** → deprecate it, update `CLAUDE.md` to point to `diagnostics/` as the canonical health check
2. **It checks something `diagnostics/` doesn't** → add that check to `diagnostics/` as a new script, then remove the core one
3. **They're identical** → remove `core/health_check.sh` outright

---

## 🟡 MEDIUM — Script Count in CLAUDE.md Will Drift

### Problem

`CLAUDE.md` states: *"The codebase is **39 shell scripts**"*. This is a hardcoded number. Every time a script is added or removed, this becomes stale and misleads anyone (including Claude Code) reading it.

### Fix

Replace the hardcoded count with a command that produces the live count:

```markdown
The codebase contains shell scripts organised in 7 modules. To get a current count:
\`\`\`bash
find scripts/ diagnostics/ -name "*.sh" | wc -l
\`\`\`
```

Or if you want to keep a number, add a CI step that fails if the count in `CLAUDE.md` doesn't match `find scripts/ -name "*.sh" | wc -l`.

---

## 🟡 MEDIUM — Jellyfin Inconsistency Between CLAUDE.md and README.md

### Problem

`CLAUDE.md` lists Jellyfin as a first-class service:
> **Jellyfin** — native/Docker media streaming via Tailscale

`README.md` makes no mention of Jellyfin. Plex is the headliner; Jellyfin doesn't appear in the "What You Get" section, the Quick Start, or the post-setup URLs.

This means anyone reading the README doesn't know Jellyfin is available, and Claude Code working from `CLAUDE.md` knows about it but can't find it referenced in user-facing docs.

### Fix

Either:
- Add Jellyfin to `README.md` as a secondary media service alongside Plex, with its access URL
- Or if Jellyfin is optional/experimental, mark it as such in `CLAUDE.md` and add a note to `docs/SETUP.md`

---

## 🟡 MEDIUM — `services/immich/` vs `scripts/services/` Namespace Collision

### Problem

The repo has two different `services` concepts at different levels:

```
services/immich/          ← Docker Compose config (root level)
scripts/services/         ← scripts module (deploys Plex, Jellyfin, Immich)
```

These are different things but share the same name. Someone reading the CLAUDE.md module architecture sees `services/` and might look in the wrong place.

### Fix

Rename the root-level Docker Compose directory to clarify its purpose:
```
services/immich/  →  compose/immich/
```

Update all references in:
- `scripts/services/` scripts that reference the compose file path
- `CLAUDE.md` module architecture section
- `docs/IMMICH.md`
- LaunchD plists that reference the compose file

---

## 🟡 MEDIUM — Pre-commit Hook Versions Are Stale

### Problem

`.pre-commit-config.yaml` pins:
```yaml
- repo: https://github.com/shellcheck-py/shellcheck-py
  rev: v0.9.0.6        # released 2023

- repo: https://github.com/pre-commit/pre-commit-hooks
  rev: v4.4.0          # released 2022
```

Both are significantly behind current releases. Stale hook versions mean newer shellcheck rules aren't being applied.

### Fix

```bash
pre-commit autoupdate
```

Run this, review the diff, commit the updated `.pre-commit-config.yaml`. Do this periodically (e.g. add a note to the weekly update checker in `scripts/automation/`).

---

## 🟡 MEDIUM — No Test Coverage for `diagnostics/`

### Problem

`tests/` covers `scripts/` (BATS unit tests, security tests, Python tests). There is no test coverage for any of the 16 `diagnostics/` scripts.

The MCP server will call these scripts in production. If a script has a broken path, bad exit code handling, or produces unexpected output format, the MCP tool will silently return garbage.

### Fix

Add a `tests/diagnostics/` directory with a minimal BATS test per script that:
1. Runs the script in `TEST_MODE=1`
2. Asserts it exits 0 under normal conditions
3. Asserts output contains expected keywords (e.g. `check_tailscale.sh` output should contain "Tailscale")

This doesn't need to be comprehensive — just enough to catch broken scripts before they surface as broken MCP tools.

```bash
# tests/diagnostics/test_diagnostics.bats (example)
@test "check_tailscale exits cleanly" {
    run bash diagnostics/check_tailscale.sh
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # 1 = not connected, still valid run
    [[ "$output" == *"Tailscale"* ]]
}
```

---

## 🟢 LOW — `web/` Directory Is Undocumented

### Problem

There's a `web/` directory in the repo. The README mentions a "Server Dashboard" but gives no URL, no description of what's in `web/`, and no setup instructions.

### Fix

Add a `docs/DASHBOARD.md` (or section in `docs/SETUP.md`) that explains:
- What `web/` contains
- How to start it
- What URL it's served on
- Whether it depends on any other service

---

## 🟢 LOW — `README-QUICKSTART.md` Naming Is Non-Standard

### Problem

The file is named `README-QUICKSTART.md` with a `README-` prefix that suggests it should be at root, while all other guide-level docs (ADMIN-GUIDE, USER-GUIDE) don't use that prefix. It's an inconsistent naming artifact.

### Fix

Covered by the root doc sprawl fix above — renaming to `docs/QUICKSTART.md` resolves both issues at once.

---

## 🟢 LOW — `mcp/server.py` Should Use `io.homelab.*` in Its Server Name

### Problem

`mcp/server.py` registers the server as:
```python
app = Server("hakuna-health")
```

While this is a cosmetic name (what Claude Desktop shows), it's inconsistent with the `io.homelab.*` namespace used for LaunchD and the broader homelab identity.

### Fix

```python
app = Server("io.homelab.mcp")
```

This also makes it easier to identify in Claude Desktop logs if you're ever running multiple MCP servers.

---

## 🟢 LOW — `CLAUDE.md` Doesn't Mention `diagnostics/` Module

### Problem

`CLAUDE.md` defines the module architecture for `scripts/` clearly. But `diagnostics/` — a sibling directory with 16 scripts — is not mentioned in the module architecture section at all. It's only referenced obliquely in the testing section.

### Fix

Add `diagnostics/` to the module architecture section in `CLAUDE.md`:

```
diagnostics/    → health checks and observability (no dependencies on scripts/)
```

And note the relationship: diagnostics scripts are standalone — they do not source from `scripts/core/` or any other module. They use raw CLI tools directly. This is intentional so they can run even if the scripts module tree is broken.

---

## Summary

| # | Issue | Priority | Effort |
|---|---|---|---|
| 1 | Broken links in README.md | 🔴 HIGH | Low — just fix paths |
| 2 | LaunchD naming violation in MCP spec | 🔴 HIGH | Low — update spec before build |
| 3 | `coldstore` vs `Archive` ambiguity | 🔴 HIGH | Medium — touches docs + scripts |
| 4 | Root-level doc sprawl | 🟡 MEDIUM | Medium — move files + update links |
| 5 | `core/health_check.sh` overlaps with `diagnostics/` | 🟡 MEDIUM | Medium — requires audit first |
| 6 | Hardcoded script count in CLAUDE.md | 🟡 MEDIUM | Low — one-line change |
| 7 | Jellyfin inconsistency | 🟡 MEDIUM | Low — docs only |
| 8 | `services/` namespace collision | 🟡 MEDIUM | High — path changes across scripts |
| 9 | Stale pre-commit hook versions | 🟡 MEDIUM | Low — `pre-commit autoupdate` |
| 10 | No test coverage for `diagnostics/` | 🟡 MEDIUM | Medium — new BATS tests |
| 11 | `web/` undocumented | 🟢 LOW | Low — add a doc section |
| 12 | `README-QUICKSTART.md` naming | 🟢 LOW | Covered by #4 |
| 13 | MCP server name inconsistency | 🟢 LOW | Trivial — one-line change |
| 14 | `diagnostics/` missing from CLAUDE.md architecture | 🟢 LOW | Low — add one line |

---

## Recommended Sequence

Do these in order to avoid compounding the fixes:

1. Fix broken links (#1) — unblocks anyone trying to follow the README right now
2. Fix LaunchD naming in MCP spec (#2) — must happen before `io.homelab.mcp.plist` is created
3. Resolve `coldstore`/`Archive` naming (#3) — do this before writing MCP diagnostic tools that reference storage names
4. Consolidate root docs into `docs/` (#4) — do this as a single PR, update all cross-links at once
5. Audit `core/health_check.sh` vs `diagnostics/` (#5) — do after #4 so docs are stable
6. Everything else in any order
