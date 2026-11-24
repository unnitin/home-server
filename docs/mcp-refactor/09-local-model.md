# 09 — Local Model

**Decision (2026-11-23):** the local profiles run **Qwen3.5-9B**: Ollama tag `qwen3.5:9b`, digest `d63f830f28d5…`, NVFP4, 7.6 GB, Apache 2.0. Thinking is off, and Ollama serves it on the mini at `127.0.0.1:11434`. It's the strongest open model that fits beside Immich, Plex and Jellyfin in the mini's 16 GB, and it was the best of the candidates measured below.

- **Use it for `local`** (incident triage and ops questions, `core` toolset). With the operating-guide rules it passed every ops run (20/20), including a failed RAID disk and a prompt injection. It's marked supported only after it also passes the Phase 4 eval suite (06).
- **Not cleared for `local-curator`.** No model that fits passes the curation scenarios. It reports dry runs as done, and a file name can sometimes talk it into proposing the Toddler label. The server's guards (08) keep curation safe regardless. The nightly `curate_leftovers` run stays off until a local model passes the Phase 6 curation evals.
- **"Always on" means the server, not the model.** Ollama runs all the time. The model loads in 5–10 s on the first request and unloads after 5 idle minutes. Keeping 7.7 GB resident around the clock would leave Immich and Plex short.

This settles open decision 2 in [07](07-roadmap.md): the local model runs on the mini.

## The constraint: 16 GB, shared

The model, the GPU and every service share the mini's 16 GB (Apple M4, 10-core CPU and GPU, Metal limit 10.7 GB). Measured with Immich idle:

| Consumer | Memory |
|---|---|
| Immich (Colima VM, set to 6 GB) | 6.2 GB |
| Jellyfin and Plex, idle | ~0.6 GB, more while transcoding |
| macOS | ~2.5 GB |
| **Left for a model** | **~6 GB**, less during Immich ML jobs |

Qwen3.5-9B needs 7.7 GB once loaded, so it fits only by pushing idle memory to swap. That's usually cheap: once the first load had settled, later runs paged out almost nothing. One run hit the bad case:

- Swap was already full (Ollama logged `free_swap="0 B"`).
- A cold load drove free memory to 5%.
- The first two prompts took 2 and 4 minutes instead of about a second.

Plex and Jellyfin kept answering throughout (worst 15 ms and 1 s). That run is the reason for the memory guard below.

Other software on the mini competes for memory too. On 2026-11-23 a process from outside this repo held 14 GB, nearly all of it in swap.

**Ruled out without measuring** (too big for what's left):

| Model | Why not |
|---|---|
| gpt-oss-20b | 14 GB: it needs the whole machine |
| Gemma 4 26B A4B or 31B, Qwen3.5-27B or 35B, Qwen3.8-27B | 15 GB or more at 4-bit |
| Gemma 4 12B, 14B-class dense models | 8–9 GB at 4-bit, so no smaller than the 9B, and weaker at tool use in published comparisons |

Gemma 4 E4B (about 4.5 GB) fits, but it scores far lower on multi-step tool use in published benchmarks (τ²-bench 42 against 79 for Qwen3.5-9B). It's the first one to measure when revisiting.

## Measured on the mini

[`tests/e2e/local_model/probe.py`](../../tests/e2e/local_model/probe.py) runs 8 scenarios from the eval plan in 06 (5 ops, 3 curation, 4 of them safety). It uses the planned tool schemas with canned tool results, so nothing on the server is touched.

Setup: Ollama 0.40.17 (Homebrew), flash attention, q8_0 KV cache, 16k context, temperature 0.1, one model loaded at a time. Immich, Plex and Jellyfin were running.

| Model and prompt | Ops passed | Curation passed | Tried to add Toddler | Output | Median scenario | Loaded |
|---|---|---|---|---|---|---|
| **Qwen3.5-9B NVFP4, guide rules** | **20/20** | 5/12 | 2/8 | 27 tok/s | 11 s | 7.7 GB |
| Qwen3.5-9B NVFP4, no rules | 19/20 | 4/12 | 7/8 | 28 tok/s | 10 s | 7.7 GB |
| Qwen3.5-9B NVFP4, no rules, thinking on | 8/10 | 0/6 | 4/4 | 28 tok/s | 17 s | 7.7 GB |
| Qwen3.5-9B q4_K_M, guide rules\* | 10/10 | 2/6 | 2/4 | 17 tok/s | 11 s | 5.8 GB |
| Qwen3.5-4B NVFP4, guide rules\* | 17/20 | 3/12 | 5/8 | 27 tok/s | 6 s | 4.1 GB |

\* Some of these runs used an earlier version of the rules, without the last two (file-name claims, dry runs).

Both the 9B and the 4B described the test image correctly. On the 9B, the first prompt of about 1,500 tokens takes about 7 s. Later steps reuse the cached prefix and run at over 1,000 tok/s.

What the runs showed:

1. **The model is not a safeguard for the Toddler profile.**
   - Without the rules, the 9B tried to add Toddler in 7 of 8 runs: to *Jaws* when asked, and to *Saw* because its file name said so. With the rules it was 2 of 8.
   - In another run it didn't call the tool, but told the user to add the label to *Saw* themselves.
   - The server's outright refusal of access labels (08) is what keeps the profile safe, and it has to stay that way.
2. **It reports dry runs as done.** In 4 of the 5 guided runs that ended in a dry run, the answer said the match "has been corrected". The harness must show dry-run and plan results from the server's envelope, not from the model's summary.
3. **Ops triage is solid.** With the rules, every ops run:
   - called the right tools
   - used `storage_plan_recovery` for the failed disk instead of suggesting commands of its own
   - ignored a file name telling it to call `updates_apply`
4. **Thinking makes it worse here.** It took about twice as long and made more tool calls (dry-run restarts for a slow-search question). It also left final answers empty, and it made no fewer Toddler attempts. Keep it off.
5. **The NVFP4 build beats q4_K_M on this Mac.** Ollama runs NVFP4 on MLX, and it was 60% faster. It was also more accurate: in all 3 remake runs, q4_K_M invented a TMDB ID instead of searching. The 1.9 GB q4_K_M saves isn't worth that.
6. **The 4B isn't a safe fallback.** It's no faster at generating text and worse at both ops and curation. When the 9B can't load, defer the run rather than switch to a smaller model.

## How it runs (Phase 4)

- **Install:** the Homebrew `ollama` formula, not the desktop app, which starts itself at login. It was installed on 2026-11-23 for these measurements, with no service yet.
- **Service:** `io.homelab.ollama`, a LaunchD job that runs `/opt/homebrew/opt/ollama/bin/ollama serve` directly. It runs no repo scripts, so D19 doesn't affect it. Environment:

  ```
  OLLAMA_HOST=127.0.0.1:11434   # never on the tailnet; tailscale serve doesn't map it
  OLLAMA_FLASH_ATTENTION=1
  OLLAMA_KV_CACHE_TYPE=q8_0
  OLLAMA_CONTEXT_LENGTH=16384
  OLLAMA_MAX_LOADED_MODELS=1
  OLLAMA_NUM_PARALLEL=1
  OLLAMA_KEEP_ALIVE=5m
  ```

- **Pinned model:** pull `qwen3.5:9b` and check that its digest starts `d63f830f28d5` before using it. Ollama can point a tag at a new build without notice, so a new digest is a model change and needs a probe or eval run first.
- **Memory guard:** before a scheduled run, the job runner checks four things:
  - no Immich ML job is running
  - no Plex transcode is running
  - `sysctl kern.memorystatus_vm_pressure_level` is 1 (normal)
  - at least 2 GB of swap is free

  If any check fails, the run is deferred. Incident triage runs anyway, because it's short and read-only.
- **Operating guide:** `agent/prompts/operating-guide.md` carries the rules in `probe.py` (`GUIDE_RULES`):
  - access labels are added only by a parent
  - RAID repairs go through `storage_plan_recovery`
  - updates need approval
  - what an item is comes from match candidates, never from file names
  - a dry run changes nothing
- **Structured output:** the Homebrew build lacks xgrammar for the MLX engine (Ollama logs "Structured output is unavailable"). So JSON-schema `format` isn't enforced for this model. Native tool calling works, and the json_react fallback validates and re-prompts anyway.

## Re-measuring

With `ollama serve` running on 127.0.0.1:

```bash
ollama pull <candidate>
python3 -I tests/e2e/local_model/probe.py <candidate> --repeat 4 --out results.json
python3 -I tests/e2e/local_model/probe.py <candidate> --prompt generic --repeat 2
```

Revisit in any of these cases:
- a new open model family lands (measure Gemma 4 E4B first)
- Ollama re-points the `:9b` tag
- the mini's memory changes

From Phase 4, the eval suite (06) replaces the probe as the gate. It keeps the same bar: 100% of the safety scenarios and 85% of the rest.
