"""homelab/redact.py: secrets never leave in a result."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from homelab import redact  # noqa: E402

M = redact.MASK
# Built from parts so the repo's private-key hook doesn't flag this test.
PEM = "-----{} OPENSSH PRIVATE KEY-----"
KEY_BLOCK = PEM.format("BEGIN") + "\nAAAA\n" + PEM.format("END")

CASES = [
    (
        "GET /library/sections?X-Plex-Token=abcd1234efgh HTTP/1.1",
        f"GET /library/sections?X-Plex-Token={M} HTTP/1.1",
    ),
    ('PlexOnlineToken="zzzzyyyyxxxx"', f'PlexOnlineToken="{M}"'),
    ("x-api-key: 0123456789abcdef", f"x-api-key: {M}"),
    ("Authorization: Bearer hl_abcdefghijklmnop", f"Authorization: Bearer {M}"),
    ("IMMICH_DB_PASSWORD=s3cr3tpass", f"IMMICH_DB_PASSWORD={M}"),
    ("DB_PASSWORD: hunter22", f"DB_PASSWORD: {M}"),
    ('{"apiKey": "k-123456789"}', f'{{"apiKey": "{M}"}}'),
    ('{"api_key":"k-123456789"}', f'{{"api_key":"{M}"}}'),
    (
        'Authorization: MediaBrowser Client="x", Token="0f0f0f0f0f0f"',
        f'Authorization: MediaBrowser Client="x", Token="{M}"',
    ),
    ("X-Emby-Token=aaaabbbbcccc&x=1", f"X-Emby-Token={M}&x=1"),
    ("key tskey-auth-kAbCdEf123456-XYZ", f"key {M}"),
    ("a\n" + KEY_BLOCK + "\nb", f"a\n{M}\nb"),
]


@pytest.mark.parametrize("raw,clean", CASES, ids=[c[0][:30] for c in CASES])
def test_known_secret_shapes_are_masked(raw, clean):
    assert redact.redact(raw) == clean


@pytest.mark.parametrize(
    "text",
    [
        "Immich healthy; 3 containers up",
        "token count: 1234",
        "faststore 81% used (warn at 80%)",
        "io.homelab.plex last exit 0",
        "password reset not needed",
    ],
)
def test_ordinary_text_is_untouched(text):
    assert redact.redact(text) == text


def test_a_registered_secret_is_removed_anywhere(monkeypatch):
    monkeypatch.setattr(redact, "_KNOWN", set())
    redact.register("Q9x8w7v6u5")
    assert redact.redact("curl ...Q9x8w7v6u5... done") == f"curl ...{M}... done"


def test_short_values_are_not_registered(monkeypatch):
    monkeypatch.setattr(redact, "_KNOWN", set())
    redact.register("abc")
    assert redact.redact("abc def") == "abc def"


def test_redact_obj_walks_structures_and_masks_secret_keys():
    data = {
        "summary": "ok X-Plex-Token=abcd1234efgh",
        "token": "plain-looking-value",
        "items": [{"api_key": "zzz"}, ("Bearer abcdefghijkl",)],
        "count": 3,
    }
    clean = redact.redact_obj(data)
    assert clean["summary"] == f"ok X-Plex-Token={M}"
    assert clean["token"] == M and clean["items"][0]["api_key"] == M
    assert clean["items"][1] == (f"Bearer {M}",)
    assert clean["count"] == 3
