"""The read-only curation reports (08), against API fixtures.

The fixtures' photos carry GPS coordinates on purpose: no result may contain
them. People and titles in the fixtures are made up.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from homelab import secrets, tools  # noqa: E402
from homelab import exec as hexec  # noqa: E402
from homelab.adapters import http as hhttp  # noqa: E402
from homelab.domains import curation  # noqa: E402


@pytest.fixture(autouse=True)
def keys(tmp_path, monkeypatch):
    monkeypatch.setenv("TEST_MODE", "1")
    (tmp_path / "http").mkdir()
    monkeypatch.setenv("HOMELAB_HTTP_FIXTURES", str(tmp_path / "http"))
    for name in ("immich_api_key", "plex_token", "jellyfin_api_key"):
        monkeypatch.setenv(secrets.env_name(name), f"{name}-0123456789")
    secrets.forget_cache()
    hexec.RECORDED.calls.clear()
    return tmp_path / "http"


def no_gps(result: dict) -> None:
    text = json.dumps(result)
    assert "latitude" not in text and "longitude" not in text and "73.8" not in text


def test_albums_and_filters():
    r = curation.photos_albums()
    names = [a["name"] for a in r["data"]["albums"]["content"]]
    assert names == ["Family", "Their Album", "Trip to the Coast"]  # deduped, sorted
    owned = curation.photos_albums("owned")["data"]["albums"]["content"]
    assert {a["name"] for a in owned} == {"Family", "Trip to the Coast"}
    shared = curation.photos_albums("shared")["data"]["albums"]["content"]
    assert {a["name"] for a in shared} == {"Family", "Their Album"}


def test_album_profile_by_name_without_gps():
    r = curation.photos_album_profile("trip to the coast")
    p = r["data"]["profile"]["content"]
    assert p["count"] == 4 and p["people"][0] == {"name": "Person A", "pct": 75}
    assert p["places"][0] == {"place": "Panaji, India", "pct": 75}
    assert p["mix"] == {"image": 3, "video": 1}
    assert p["span"] == {"from": "2025-12-20", "to": "2025-12-23"}
    assert "Person A in 75%" in r["summary"]
    no_gps(r)


def test_album_profile_unknown_album():
    r = curation.photos_album_profile("Nope")
    assert r["status"] == "error" and r["hints"] == ["photos_albums()"]


def test_unsorted_photos_grouped_without_gps():
    r = curation.photos_unsorted("1y")
    u = r["data"]["unsorted"]["content"]
    assert u["count"] == 7 and "unknown" in {p["place"] for p in u["places"]}
    assert r["summary"].startswith("7 photos and videos in no album")
    no_gps(r)
    assert curation.photos_unsorted("soon")["status"] == "error"


def test_without_an_immich_key(monkeypatch):
    monkeypatch.setattr(secrets, "get", lambda name: None)
    r = curation.photos_albums()
    assert r["status"] == "error" and "immich_api_key" in r["hints"][0]


def test_movies_joined_by_file():
    r = curation.media_items()
    rows = {x["title"]: x for x in r["data"]["items"]["content"]}
    assert rows["Arrival"]["status"] == "matched"
    assert rows["Arrival"]["labels"] == ["Family movie night"]
    assert rows["The Thing"]["status"] == "mismatched"
    assert rows["The Thing"]["tmdb"] == {"plex": "1091", "jellyfin": "60935"}
    assert rows["Home Video 2019"]["status"] == "unmatched"
    assert rows["Paddington"]["status"] == "only_plex"
    assert rows["Moana"]["status"] == "only_jellyfin"
    assert r["data"]["counts"] == {
        "matched": 2,
        "mismatched": 1,
        "unmatched": 1,
        "only_plex": 1,
        "only_jellyfin": 1,
    }
    assert {c["id"] for c in r["checks"]} == {"media.mismatched", "media.unmatched"}


@pytest.mark.parametrize(
    "flt,titles",
    [
        ("mismatched", {"The Thing"}),
        ("unmatched", {"Home Video 2019", "Paddington", "Moana"}),
        ("unlabelled", {"Dune", "The Thing", "Home Video 2019", "Paddington", "Moana"}),
    ],
)
def test_movie_filters(flt, titles):
    rows = curation.media_items(filter=flt)["data"]["items"]["content"]
    assert {x["title"] for x in rows} == titles


def test_recent_and_limit():
    r = curation.media_items(filter="recent", limit=2)
    rows = r["data"]["items"]["content"]
    assert [x["title"] for x in rows] == ["Paddington", "Home Video 2019"]
    assert r["data"]["shown"] == 2 and r["data"]["total"] == 6


def test_only_movies_for_now():
    assert curation.media_items(library="tv")["status"] == "error"


def test_nothing_is_written(keys):
    """Reports only read: the one POST is Immich's metadata search."""
    sent = []
    real = hhttp.request

    def spy(method, url, *a, **kw):
        sent.append(method)
        return real(method, url, *a, **kw)

    import homelab.adapters.http as mod

    orig = mod.request
    mod.request = spy
    try:
        for name in ("photos_albums", "photos_unsorted", "media_items"):
            tools.call(name)
        tools.call(
            "photos_album_profile", album="Family" if False else "Trip to the Coast"
        )
    finally:
        mod.request = orig
    assert set(sent) <= {"GET", "POST"} and sent.count("POST") == 1
    assert hexec.RECORDED.calls == []
