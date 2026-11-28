"""Curation reports, read-only (08): how big the job is before anything is written.

- photos_albums, photos_album_profile, photos_unsorted (Immich);
- media_items: Plex and Jellyfin joined by file path, each movie matched,
  unmatched or mismatched by TMDB id.

Photo results carry ids, dates, city and country, people's and album names,
never GPS coordinates or images. Everything a server or a person wrote (titles,
names) comes back as data, not instructions.
"""

from __future__ import annotations

from collections import Counter
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from homelab import result as R
from homelab.adapters import immich_api, jellyfin_api, plex_api
from homelab.adapters.service_api import ApiError

TOP = 8


def _api_error(err: ApiError, key_hint: str) -> dict:
    hints = [key_hint] if "secrets set" in str(err) else []
    return R.error(str(err), hints)


IMMICH_KEY = "homelab secrets set immich_api_key (an admin's key, or your own)"


def photos_albums(filter: str = "all") -> dict:
    try:
        albums = immich_api.albums()
    except ApiError as err:
        return _api_error(err, IMMICH_KEY)
    if filter == "owned":
        albums = [a for a in albums if a.owned]
    elif filter == "shared":
        albums = [a for a in albums if a.shared]
    rows = [
        {
            "id": a.id,
            "name": a.name,
            "photos": a.assets,
            "from": a.start,
            "to": a.end,
            "shared": a.shared,
        }
        for a in albums
    ]
    return R.make(
        [],
        {"albums": R.untrusted("immich", rows)},
        summary=f"{len(rows)} albums, {sum(a.assets for a in albums)} photos in them",
        hints=["photos_album_profile(album=<id or name>)"] if rows else [],
    )


def _find_album(album: str) -> Optional[immich_api.Album]:
    for a in immich_api.albums():
        if album in (a.id, a.name) or album.lower() == a.name.lower():
            return a
    return None


def _month(ts: str) -> str:
    return ts[:7] if len(ts) >= 7 else "unknown"


def profile_of(assets: list[immich_api.Asset]) -> dict[str, Any]:
    n = len(assets) or 1
    people = Counter(p for a in assets for p in a.people)
    places = Counter(
        ", ".join(x for x in (a.city, a.country) if x) or "unknown" for a in assets
    )
    months = Counter(_month(a.taken) for a in assets)
    kinds = Counter(a.type.lower() for a in assets)
    dates = sorted(a.taken[:10] for a in assets if a.taken)
    return {
        "count": len(assets),
        "people": [
            {"name": k, "pct": round(100 * v / n)} for k, v in people.most_common(TOP)
        ],
        "places": [
            {"place": k, "pct": round(100 * v / n)} for k, v in places.most_common(TOP)
        ],
        "months": [{"month": k, "count": v} for k, v in sorted(months.items())][-24:],
        "mix": dict(kinds),
        "span": {"from": dates[0], "to": dates[-1]} if dates else None,
    }


def photos_album_profile(album: str) -> dict:
    try:
        found = _find_album(album)
        if found is None:
            return R.error(f"no album {album!r}", ["photos_albums()"])
        meta, assets = immich_api.album_assets(found.id)
    except ApiError as err:
        return _api_error(err, IMMICH_KEY)
    prof = profile_of(assets)
    lead = []
    if prof["people"]:
        lead.append(f"{prof['people'][0]['name']} in {prof['people'][0]['pct']}%")
    if prof["places"]:
        lead.append(f"{prof['places'][0]['place']} {prof['places'][0]['pct']}%")
    return R.make(
        [],
        {"album": found.name, "id": found.id, "profile": R.untrusted("immich", prof)},
        summary=f"{found.name}: {prof['count']} items"
        + (f"; {', '.join(lead)}" if lead else ""),
    )


def photos_unsorted(since: str = "30d") -> dict:
    from homelab.state.history import seconds

    try:
        window = seconds(since)
    except ValueError as err:
        return R.error(str(err))
    after = (datetime.now(timezone.utc) - timedelta(seconds=window)).strftime(
        "%Y-%m-%dT%H:%M:%S.000Z"
    )
    try:
        assets = immich_api.not_in_album(after)
    except ApiError as err:
        return _api_error(err, IMMICH_KEY)
    prof = profile_of(assets)
    capped = len(assets) >= 1000
    return R.make(
        [],
        {
            "since": since,
            "capped_at_1000": capped,
            "unsorted": R.untrusted("immich", prof),
        },
        summary=f"{len(assets)}{'+' if capped else ''} photos and videos in no album "
        f"from the last {since}",
    )


# --- movies -------------------------------------------------------------------------


def _movie_section() -> Optional[str]:
    for s in plex_api.sections(counts=False):
        if s.type == "movie":
            return s.key
    return None


def join_movies(
    plex: list[plex_api.Movie], jelly: list[jellyfin_api.Movie]
) -> list[dict[str, Any]]:
    by_path = {j.path: j for j in jelly}
    rows, seen = [], set()
    for p in plex:
        j = next((by_path[f] for f in p.files if f in by_path), None)
        if j:
            seen.add(j.path)
        if j is None:
            status = "only_plex"
        elif not p.tmdb or not j.tmdb or not p.matched:
            status = "unmatched"
        elif p.tmdb != j.tmdb:
            status = "mismatched"
        else:
            status = "matched"
        rows.append(
            {
                "title": p.title,
                "year": p.year,
                "file": p.files[0] if p.files else "",
                "status": status,
                "tmdb": {"plex": p.tmdb, "jellyfin": j.tmdb if j else None},
                "labels": list(p.labels),
                "added_at": p.added_at,
            }
        )
    for j in jelly:
        if j.path not in seen:
            rows.append(
                {
                    "title": j.title,
                    "year": j.year,
                    "file": j.path,
                    "status": "only_jellyfin" if j.tmdb else "unmatched",
                    "tmdb": {"plex": None, "jellyfin": j.tmdb},
                    "labels": list(j.tags),
                    "added_at": None,
                }
            )
    return rows


def media_items(library: str = "movies", filter: str = "all", limit: int = 50) -> dict:
    if library != "movies":
        return R.error("only movies are joined so far; TV comes with Phase 6")
    try:
        section = _movie_section()
        if section is None:
            return R.error("Plex has no movie library")
        plex = plex_api.movies(section)
    except ApiError as err:
        return _api_error(err, "homelab secrets import-plex")
    try:
        jelly = jellyfin_api.movies()
    except ApiError as err:
        return _api_error(err, "homelab secrets set jellyfin_api_key")
    rows = join_movies(plex, jelly)
    counts = Counter(r["status"] for r in rows)
    if filter == "unmatched":
        rows = [
            r
            for r in rows
            if r["status"] in ("unmatched", "only_plex", "only_jellyfin")
        ]
    elif filter == "mismatched":
        rows = [r for r in rows if r["status"] == "mismatched"]
    elif filter == "unlabelled":
        rows = [r for r in rows if not r["labels"]]
    elif filter == "recent":
        rows = sorted(rows, key=lambda r: r["added_at"] or 0, reverse=True)
    limit = max(1, min(int(limit), 200))
    checks = []
    if counts["mismatched"]:
        checks.append(
            R.check(
                "media.mismatched",
                "warn",
                f"{counts['mismatched']} movies matched to different TMDB ids "
                "on Plex and Jellyfin",
                "media",
            )
        )
    unmatched = counts["unmatched"] + counts["only_plex"] + counts["only_jellyfin"]
    if unmatched:
        checks.append(
            R.check(
                "media.unmatched",
                "warn",
                f"{unmatched} movies unmatched or on one server only",
                "media",
            )
        )
    return R.make(
        checks,
        {
            "counts": dict(counts),
            "filter": filter,
            "items": R.untrusted("plex+jellyfin", rows[:limit]),
            "shown": min(limit, len(rows)),
            "total": len(rows),
        },
        ok_summary=f"All {len(rows)} movies matched to the same TMDB id on both "
        "servers",
    )
