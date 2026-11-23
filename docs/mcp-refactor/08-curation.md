# 08 — Curation: Immich Albums and Movie Metadata

**Goal:** agents sort photos into your existing Immich albums (plus tags, new-album suggestions and archiving screenshots) and add or fix metadata for every movie in Plex and Jellyfin, both for new arrivals and for what's already there.

Versions running on the mini when this was written: Immich 2.1.0 (smart search, face recognition, reverse geocoding and duplicate detection all enabled), Plex 1.42.2, Jellyfin 10.11.2. The adapters target these, checked against each project's published API spec, and are re-checked on upgrade.

The tools are listed in [03-tool-catalog.md](03-tool-catalog.md#curation-tools-design-in-08-curationmd).

---

## Principles

1. **Local signals do the seeing, the model decides.** Immich already runs CLIP smart search, face recognition and reverse geocoding on the mini. Plex and Jellyfin already search TMDB. The model works from those signals as text, so curation works with text-only and small local models. Showing the model actual images is optional.
2. **Facts come from providers, judgment from the model.** A model's memory of release years, cast lists and plots is unreliable. Factual fields come from the servers' own metadata search. The model chooses between candidates and adds household organization: albums, tags, labels and collections. The server enforces this (see Safeguards).
3. **Propose, review, apply.** Changes land in a review area first: a private review album in Immich, or a plan listing the changes for movies. Real albums and matched movies change only after you approve.
4. **Rules do the repetitive work.** When a proposal is good, the model can save it as a rule. For an album that's people, places, dates and search phrases. For a movie label it's rating and genre conditions. Rules run on new items every night or at ingest without any LLM, and the model only handles what the rules can't decide.
5. **Everything is undoable.** Every applied change is recorded with its before and after values, and nothing is ever deleted.

---

## Photos: sorting into existing albums

### What the agent works from
`photos_album_profile` computes what an album's photos have in common, which gives three kinds of evidence:

| Signal | Comes from | Good for |
|---|---|---|
| People | Immich face recognition | "School events", "Grandparents" |
| Place and time | Photo dates + Immich's reverse geocoding | Trips and events ("Goa Dec 2025") |
| Visual theme | Immich smart search with phrases the model writes, narrowed by people, place and date filters | "Sunsets", "Diwali", "Receipts" |

### The flow
1. **Profile and draft.** The model reads the album's profile and drafts a rule, e.g. "photos with Aarav, taken in Goa between 20 and 28 Dec 2025".
2. **Test the rule against what's already in the album.** `curation_rule_test` reports how many of the album's current photos the rule would have found, and how many new photos it would add. A search phrase that ranks the album's own photos near the top is a good phrase, and one that doesn't is dropped. For smart search, the cutoff is set where known album photos stop showing up in the results. This estimates precision without anyone labelling data.
3. **Fill a review album.** `photos_propose` puts the candidates into a private album named `Review: Goa Dec 2025` and records why each photo was picked.
4. **You review in the Immich app.** Open the review album on your phone and remove anything wrong. Immich's own interface is the review screen, so nothing new has to be built.
5. **Apply.** `review_apply` creates a plan to add what's left to the real album. After you approve, the photos are added, and the ones you removed are recorded as "no" and never proposed for that album again.
6. **Optionally keep the rule.** With `auto_apply` on, new uploads that match go straight into the album, for private albums only and capped per night. With it off, they collect in the review album for your next look.

### Beyond albums
- **Unsorted photos:** every album's rule is run against photos that are in no album, and each photo goes to its best album. Photos that match no rule clearly stay unsorted.
- **New album suggestions:** unsorted photos are clustered by time and place ("12 days in Goa, 340 photos") into `Review: New …` albums.
- **Tags:** Receipts, Documents, Screenshots and similar, found with smart-search phrases.
- **Archive:** screenshots and receipts moved out of the timeline. This needs approval because it hides photos.
- **Descriptions:** empty descriptions filled in. This needs a model that can see images, running on the mini itself (see Privacy).
- **Not included:** deleting or trashing photos (including resolving duplicates), deleting albums, sharing albums or creating share links, and naming or merging people. The agent can *report* duplicates and frequently seen unnamed faces for you to handle in Immich.

### Privacy (decided)
- Tools return photo IDs, dates, city and country, people's names and album names. They never return GPS coordinates or the image itself.
- **Photos never leave the mini.** The thumbnail tools (`photos_view`, `photos_describe`) exist only on a second, local-only listener (stdio, or `127.0.0.1:18766`, which `tailscale serve` never maps). A model that should see photos has to run on the mini, and the nightly `local-curator` run does. No client elsewhere on the tailnet, and no cloud model, can get a thumbnail.
- People's names and places are still personal data. If you don't want a cloud model to see them, run curation with a local model, which works without vision too.
- **Curation is per Immich user.** Each person who wants it creates their own restricted Immich key, which the server keeps in the Keychain under their name. Each curator token is bound to one Immich user and uses only that user's key, so it sees only that user's library and the albums shared with them, and Immich enforces the same boundary. Rules, review albums and feedback are kept per user.

---

## Movies: metadata for everything in Plex and Jellyfin

### Why it's needed
- **Files get the wrong year today.** `process_movie.sh` takes the last 4-digit number in a filename as the year, so quality tags win. I tested it: `Dune.2021.2160p.WEB-DL.mkv` is filed as `Dune 2021 (2160)`, and `Blade.Runner.2049.2017.1080p…` as `Blade Runner 2049 2017 (1080)`. Plex and Jellyfin then match badly or not at all. Phase 0 fixes the parser (D18).
- **The two servers match independently** and can disagree about the same file. Remakes are the classic case.
- **Household organization** ("Kids", "Family movie night", "Diwali", per-person picks) isn't something a metadata provider knows.

### One identity across both servers
Both servers read the same files, so the control plane joins their items by file path and compares the TMDB ID each server assigned:
- Matched on both, same ID: nothing to do.
- Unmatched on one or both: `media_match_candidates` → the model picks → `media_fix_match` applies the same ID on both servers.
- Matched to different IDs: the model explains the conflict and the fix becomes a plan for you to approve.

Candidates come from each server's own match search (Plex's Fix Match, Jellyfin's Identify), so no extra account is needed. A free TMDB API key is optional. It would let the processor identify a file *before* filing it.

### New movies (at ingest)
```
watcher → processor (fixed parser) → library scan → media_enrich
```
1. Wait until both servers list the new file.
2. Run a deterministic check: matched on both, same TMDB ID, and the year agrees with the filename. If it all passes, apply saved rules (labels, collections) and log the change. No LLM is involved.
3. If anything is off, the curation agent investigates and creates a plan, e.g. "match `Dune 2021 (2160)` to *Dune* (2021), TMDB 438631, on both servers, and rename the folder to carry the ID". You get a push notification.
4. **Renames that embed the ID** (`Dune (2021) {tmdb-438631}`) apply only to items under 24 hours old that have never been played, so no watch history is lost. Plex documents `{tmdb-…}` in folder names and Jellyfin documents `[tmdbid-…]`. Which form, or whether both together, works on Plex 1.42 and Jellyfin 10.11 is the first thing Phase 6 verifies. If neither works for both, matching stays API-only.

### Movies already in the libraries (backfill)
`media_items(filter=unmatched)` and `media_items(filter=mismatched)` give the work list. `media_enrich(scope=backfill)` runs the same checks as a job in batches, with one plan per batch of uncertain items.

### What the agent may write

| Field | Matched items | Items no provider matched (home videos, rare films) |
|---|---|---|
| Match (TMDB ID) | Only an ID the server just returned as a candidate. Re-matching needs approval | — |
| Title, year, summary | No, these come from the provider | Yes, based on what you tell it |
| Labels, collections, sort title | Yes. Adding needs no approval, removing does | Yes |
| Content rating | Always needs approval | Always needs approval |
| `Toddler` (allow-list label, below) | Only if it meets the label's rules, and always needs approval. Removing needs none | Never through the agent. You add it yourself |

Edited fields are locked so a metadata refresh doesn't undo them. The lock is recorded so it can be released later.

### The toddler profile (decided)

A 2-year-old should only ever see what a parent has picked. So this is an **allow-list that fails closed**, not a rating ceiling. A mistake leaves something out instead of letting something in.

- **Her own profile:** a Plex managed user and a Jellyfin user, used only on her devices.
- **Allow-list:** her profile shows only items labelled `Toddler`. In Plex that's *Allow only labels* on the Movies and TV libraries, and in Jellyfin *Allow items with tags*. A new movie stays invisible to her until it gets the label.
- **Rating cap as a second lock:** Plex limited to G / TV-Y. Jellyfin set to a maximum parental rating of G, with unrated items blocked.
- **What the agent may do with the label:**
  - Propose it only for items rated G (films) or TV-Y (shows), or the equivalent in your metadata region. Never for unrated items, and never if any genre is Horror, Thriller, Crime, War or Mystery.
  - Every addition needs a parent's approval, every time. No rule may auto-apply it.
  - Removing it needs no approval, because that's the safe direction.
  - The approval message shows the rating, genres, runtime and summary. The agent may add cautionary notes, such as a frightening scene it knows of, but it can never argue that something is safe. Your approval decides.
- **Home videos** are unrated, so the agent can't label them. You add the label directly in Plex or Jellyfin to the ones you want her to see.
- **Setting up the profile** is a manual step, because the agent can never change users or parental controls (03, T3). Phase 6 writes `docs/PARENTAL-CONTROLS.md` with the exact settings.
- **TV shows** carry the same label. Until TV curation exists, you label shows by hand.

The label name is generic on purpose. Nothing committed to the repo names the child.

TV shows can follow the same pattern later. The tools take a `library` parameter so they don't need redesigning.

---

## Rules file: `config/curation.yaml`

It's gitignored because it holds people's names and album names. It's written only through approved plans (`curation_rule_save`), and every version is kept in `state.db`.

```yaml
photos:                                  # per Immich user
  <immich user>:
    albums:
      "Goa Dec 2025":
        match: { places: [Goa], taken: [2025-12-20, 2025-12-28] }
        auto_apply: true
      "School events":
        match: { people_all: [<person>], queries: ["school stage performance", "classroom"], top: 300 }
        auto_apply: false
    tags:
      Receipts: { queries: ["a paper receipt", "an invoice"], top: 500 }

movies:                                  # household-wide: both servers share the libraries
  labels:
    "Family movie night": { when: { rating_max: PG-13, genres_any: [Family, Comedy, Adventure] } }
    # Toddler isn't a rule. It's defined in homelab.yaml (curation.media.access_labels)
    # and can only be proposed, never auto-applied.
```

---

## Safeguards (enforced by the server)

- **The Immich key is restricted by Immich itself.** Immich API keys can be limited to chosen permissions. This key gets read, thumbnail view, album creation (for review albums), adding and removing album photos, tags and asset updates. It gets no delete, sharing, share-link, user or admin permissions. The adapter also uses asset updates only for descriptions and archive, and removes photos only from review albums or when undoing its own changes.
- **Plex and Jellyfin tokens can't be narrowed** this way, so the adapters implement only the endpoints the tools need: listing, match search, apply match, field edits, labels, collections and refresh. There's no generic "call the Plex or Jellyfin API" tool, and a test asserts the endpoint allowlist. The Plex adapter builds on python-plexapi.
- **Shared albums:** any addition becomes a plan that needs approval.
- **Caps:** at most 20 photos per direct add and 200 per album per night through auto-apply. Only one curation job runs per album or library at a time.
- **Access-gating fields:** adding an allow-list label (`curation.media.access_labels`) or changing a content rating always needs approval. The server refuses an access label outright on items that don't meet its rules, so approval can't override them.
- **Facts come from providers:** `media_fix_match` accepts only IDs the server returned as candidates for that item within the last hour. Title, year and summary are writable only on items no provider matched.
- **Untrusted text is data:** release names, TMDB overviews (anyone can edit TMDB), EXIF descriptions, album names from other Immich users, and text a vision model reads in a photo. None of it can widen what a tool is allowed to do.

---

## How it runs

| Run | What happens | What it can change |
|---|---|---|
| Nightly (`io.homelab.curate`) | `homelab curate run` (rules engine), then optionally `homelab-agent run curate_leftovers --profile local-curator` | The engine applies `auto_apply` rules within caps. The agent fills review albums and creates plans |
| At ingest | processor → library scan → `media_enrich` job | Applies saved rules. Anything uncertain becomes a plan |
| Interactive | "sort last month's photos", "fix the metadata on the new movies" | Same tools, same approvals |

---

## Model requirements

- Text-only models are enough. Vision is used only for descriptions and for tie-breaks between albums.
- The eval suite (06) adds curation scenarios:
  - remakes (*Dune* 1984 vs 2021)
  - a foreign title
  - a `1080p` release name
  - a filename that tries to get the Toddler label added (expect no `media_label` call)
  - a PG-rated film proposed for Toddler (expect a refusal)
  - an addition to a shared album (expect a plan, not a change)
  - photo proposal precision against a labelled fixture library

  A model profile is cleared for curation only if it passes these.
