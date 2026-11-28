# MCP Refactor Plan — Overview

**Status:** Proposal (2026-11-22) · **Supersedes:** the "read-only, no auth" constraints in [`docs/MCP.md`](../MCP.md) once Phase 3 lands

**Goal:** Make every routine operation of the home server (health checks, troubleshooting, service control, media processing, photo imports, updates, log collection, and curating photos and movie metadata) possible through one MCP server. Any LLM should be able to drive it (Claude, GPT, Gemini, or a local model on the Mac mini through Ollama) without a human SSH-ing in. Disk-destroying operations stay human-only.

| Doc | Covers |
|---|---|
| [01-assessment.md](01-assessment.md) | What exists today, what's broken, what blocks an agent |
| [02-architecture.md](02-architecture.md) | Target layering, manifest, repo layout, structured-output contract |
| [03-tool-catalog.md](03-tool-catalog.md) | Every MCP tool: name, params, tier, backing implementation |
| [04-context-and-memory.md](04-context-and-memory.md) | Resources, prompts, runbooks, state DB, memory tools |
| [05-safety-and-jobs.md](05-safety-and-jobs.md) | Risk tiers, approvals, auth, audit, long-running jobs, secrets |
| [06-harness.md](06-harness.md) | LLM-agnostic agent harness, model profiles, evals |
| [07-roadmap.md](07-roadmap.md) | Phased delivery, with acceptance criteria per phase |
| [08-curation.md](08-curation.md) | Agents sorting photos into Immich albums and adding metadata to movies in Plex and Jellyfin |
| [09-local-model.md](09-local-model.md) | Which local model runs on the mini, how it was measured, and what it's cleared for |

---

## The short version

1. **Fix the foundations first.** Today's MCP server wraps 16 diagnostic scripts. Several of them are broken or stale (see 01). The server listens on `0.0.0.0` with no auth, so anyone on the home LAN can reach it, not only devices on the tailnet. All of that has to be fixed before any tool can change anything.
2. **One source of truth.** Add `config/homelab.yaml`, a manifest of storage tiers, services, ports, LaunchD labels, health endpoints and media paths. Today those values are hardcoded in many separate places and have already drifted apart (`/Volumes/Media` vs `warmstore`, `Staging/TV Shows` vs `staging/tv-shows`). Bash, Python, plists and the MCP server all read the manifest.
3. **Structured output everywhere.** Diagnostics gain a JSON mode, and tools return `{status, checks[], summary}` instead of 200 lines of ANSI-colored text. A JSON summary is the biggest single improvement for weaker and local models.
4. **Three layers:** a thin **MCP server** (transport, auth, policy, audit) → a **Python control plane** (`homelab/`, typed domain functions and adapters) → **executors** (the existing bash scripts plus CLIs and HTTP APIs). LaunchD, humans and the MCP server all call the same entrypoints.
5. **The server enforces safety, not the prompt.** Each tool has a risk tier. Tier 2 changes need out-of-band human approval. Tier 3 operations (RAID, erase) are never exposed. Every call is audited. Long operations run as jobs.
6. **Memory lives on the server, so it works with any LLM.** It's a SQLite DB on the *internal* disk, never on the RAID it diagnoses. It holds health snapshots, incidents, notes and the audit trail, and is reached through tools, not through any one client's memory feature.
7. **The harness is thin and model-agnostic.** A small `agent/` CLI uses LiteLLM to talk to any provider and the official MCP client SDK. It adds toolset profiles, approval interception, auto-recall and a multi-model eval suite. The server also stays usable from off-the-shelf MCP clients.
8. **Curation.** Agents sort photos into existing Immich albums (plus tags, new-album suggestions and archiving) and add or fix metadata for every movie in Plex and Jellyfin. Immich's own ML and the servers' metadata search do the seeing and supply the facts. The model decides, you approve, and rules you've approved handle new items automatically.

## Design principles

- **Reachable from the tailnet, and only from the tailnet.** Any of your tailnet devices reaches the server at `https://<mini>.<tailnet>.ts.net:8765/mcp`. The home LAN can't reach it, and it's never on the public internet (Tailscale Serve, never Funnel). See 05.
- **Portable over clever.** Use only MCP features every client supports: tools, plus text and structured content. Resources and prompts are mirrored as tools, because client support for them is uneven. Don't depend on sampling or elicitation.
- **Flat schemas.** Tool names match `^[a-z][a-z0-9_]{0,63}$`, which OpenAI and Gemini both accept, so no dots. Params are primitives, enums or arrays of IDs, with no `oneOf`/`$ref`/deep nesting.
- **Small default surface.** A local 8–14B model sees about 12 tools, a frontier model sees all of them. Visibility is filtered on the server by token scope.
- **One action, one implementation.** No logic is duplicated between bash and Python. Python orchestrates and parses, and bash keeps what must run before Python exists (bootstrap, boot-time LaunchD).
- **Diagnostics stay standalone.** `diagnostics/` must still run when everything else is broken, so it reads the generated env file with fallbacks and never imports `homelab/`.
- **Destructive ≠ automatable.** RAID create/delete, erase and preclean never get an MCP tool. The agent can *plan* a rebuild, and a human runs it.
