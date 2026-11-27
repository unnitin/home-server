"""Secrets and the Immich, Plex and Jellyfin API adapters.

TEST_MODE=1: no request is sent and no Keychain is read. Responses come from
tests/fixtures/http/; secrets from HOMELAB_SECRET_* variables.
"""

from __future__ import annotations

import json
import plistlib
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from homelab import cli, redact, secrets  # noqa: E402
from homelab import exec as hexec  # noqa: E402
from homelab.adapters import http as hhttp  # noqa: E402
from homelab.adapters import immich_api, jellyfin_api, plex_api  # noqa: E402
from homelab.adapters.service_api import (  # noqa: E402
    ApiError,
    SecretMissing,
    SecretRejected,
)

KEYS = {"immich_api_key": "imm-0123456789", "plex_token": "plx-0123456789"}
KEYS["jellyfin_api_key"] = "jf-0123456789ab"


@pytest.fixture(autouse=True)
def test_mode(monkeypatch, tmp_path):
    monkeypatch.setenv("TEST_MODE", "1")
    for folder in ("exec", "http"):
        (tmp_path / folder).mkdir()
    monkeypatch.setenv("HOMELAB_EXEC_FIXTURES", str(tmp_path / "exec"))
    monkeypatch.setenv("HOMELAB_HTTP_FIXTURES", str(tmp_path / "http"))
    for name, value in KEYS.items():
        monkeypatch.setenv(secrets.env_name(name), value)
    secrets.forget_cache()
    return tmp_path


def http_fixture(folder: Path, method: str, url: str, status: int, data=None):
    rec = {"status": status, "json": data} if data is not None else {"status": status}
    (folder / "http" / f"{hhttp.fixture_key(method, url)}.json").write_text(
        json.dumps(rec)
    )


# --- secrets --------------------------------------------------------------------------


def test_a_secret_from_the_environment_is_registered_for_redaction():
    assert secrets.get("plex_token") == KEYS["plex_token"]
    assert redact.redact(f"echoed {KEYS['plex_token']}") == f"echoed {redact.MASK}"


def test_a_secret_from_the_keychain(monkeypatch, test_mode):
    monkeypatch.delenv(secrets.env_name("plex_token"))
    argv = ["security", "find-generic-password", "-s", "homelab", "-a", "plex_token"]
    (test_mode / "exec" / f"{hexec.fixture_key(argv + ['-w'])}.out").write_text(
        "from-keychain-123\n"
    )
    assert secrets.get("plex_token") == "from-keychain-123"


def test_a_secret_missing_from_the_keychain_is_none(monkeypatch, test_mode):
    monkeypatch.delenv(secrets.env_name("plex_token"))
    argv = ["security", "find-generic-password", "-s", "homelab"]
    argv += ["-a", "plex_token", "-w"]
    (test_mode / "exec" / f"{hexec.fixture_key(argv)}.json").write_text(
        json.dumps({"rc": 44, "stderr": "could not be found"})
    )
    assert secrets.get("plex_token") is None


def test_secrets_are_never_written_in_test_mode():
    with pytest.raises(RuntimeError, match="TEST_MODE"):
        secrets.store("plex_token", "x" * 12)


@pytest.mark.parametrize("bad", ["Plex", "a-b", "../x", ""])
def test_secret_names_are_checked(bad):
    with pytest.raises(ValueError):
        secrets.get(bad)


def test_plex_token_from_preferences(monkeypatch, tmp_path):
    prefs = tmp_path / "plex.plist"
    prefs.write_bytes(plistlib.dumps({"PlexOnlineToken": "tok-abcdefgh"}))
    monkeypatch.setattr(secrets, "PLEX_PREFS", prefs)
    assert secrets.plex_token_from_preferences() == "tok-abcdefgh"
    prefs.write_bytes(plistlib.dumps({}))
    assert secrets.plex_token_from_preferences() is None


def test_secrets_list_names_the_manifests_secrets_and_never_values(capsys):
    assert cli.main(["secrets", "list"]) == 0
    out = capsys.readouterr().out
    for name in KEYS:
        assert name in out
    assert not any(v in out for v in KEYS.values())


def test_secrets_set_refuses_an_unknown_name(capsys):
    assert cli.main(["secrets", "set", "nope"]) == 2


# --- the shared client ----------------------------------------------------------------


def test_a_missing_secret_names_the_command_that_sets_it(monkeypatch):
    monkeypatch.delenv(secrets.env_name("jellyfin_api_key"))
    monkeypatch.setattr(secrets, "get", lambda name: None)
    with pytest.raises(SecretMissing, match="homelab secrets set jellyfin_api_key"):
        jellyfin_api.counts()


def test_a_rejected_secret_says_to_replace_it(test_mode):
    http_fixture(test_mode, "GET", "http://localhost:8096/Items/Counts", 401)
    with pytest.raises(SecretRejected, match="replace it"):
        jellyfin_api.counts()


def test_a_public_call_needs_no_secret(monkeypatch):
    monkeypatch.setattr(secrets, "get", lambda name: None)
    assert jellyfin_api.version() == "10.11.2"


def test_no_answer_is_an_api_error(test_mode):
    (test_mode / "http" / "GET_2283_api_server_version.json").write_text(
        json.dumps({"status": None, "error": "Connection refused"})
    )
    with pytest.raises(ApiError, match="no answer"):
        immich_api.version()


def test_the_auth_header_carries_the_secret_and_the_url_does_not(monkeypatch):
    seen = {}

    def fake_get(url, headers=None, timeout=5):
        seen.update(url=url, headers=headers)
        return hhttp.Response(url, 200, b'{"MediaContainer": {"Directory": []}}')

    monkeypatch.setattr(hhttp, "get", fake_get)
    plex_api.sections()
    assert seen["headers"]["X-Plex-Token"] == KEYS["plex_token"]
    assert KEYS["plex_token"] not in seen["url"]
    monkeypatch.setattr(
        hhttp,
        "get",
        lambda url, headers=None, timeout=5: (
            seen.update(h=headers) or hhttp.Response(url, 200, b"{}")
        ),
    )
    jellyfin_api.counts()
    assert (
        seen["h"]["Authorization"] == f'MediaBrowser Token="{KEYS["jellyfin_api_key"]}"'
    )


# --- Immich ---------------------------------------------------------------------------


def test_immich_version_stats_and_queues():
    assert immich_api.version() == "2.1.0"
    s = immich_api.statistics()
    assert (s.photos, s.videos, s.users) == (41250, 1830, 2)
    assert "Person" not in repr(s)  # totals only, never people's names
    q = {x.name: x for x in immich_api.queues()}
    assert q["smartSearch"].backlog == 121 and q["smartSearch"].is_active
    assert q["faceDetection"].failed == 3 and q["thumbnailGeneration"].backlog == 0


# --- Plex -----------------------------------------------------------------------------


def test_plex_sections_with_counts_and_recent_items():
    assert plex_api.version().startswith("1.42.")
    secs = {s.title: s for s in plex_api.sections()}
    assert secs["Movies"].items == 412 and secs["TV Shows"].items == 37
    assert secs["Movies"].paths == ("/Volumes/warmstore/movies",)
    recent = plex_api.recently_added()
    assert recent[0].title == "Arrival" and recent[1].title == "Some Show: Pilot"


# --- Jellyfin -------------------------------------------------------------------------


def test_jellyfin_counts_libraries_and_last_scan():
    assert jellyfin_api.counts() == {
        "movie": 410,
        "series": 37,
        "episode": 1210,
        "boxset": 4,
    }
    libs = {lib.name: lib for lib in jellyfin_api.libraries()}
    assert libs["Shows"].paths == ("/Volumes/warmstore/tv-shows",)
    scan = jellyfin_api.last_scan()
    assert scan.status == "Completed" and scan.ended.startswith("2026-11-27")


# --- http fixtures --------------------------------------------------------------------


def test_http_in_test_mode_never_sends_and_names_a_missing_fixture():
    with pytest.raises(hexec.FixtureMissing, match="GET_8096_nothing.json"):
        hhttp.get("http://localhost:8096/nothing")


def test_the_committed_http_fixtures_are_valid():
    for path in hhttp.FIXTURES.glob("*.json"):
        rec = json.loads(path.read_text())
        assert set(rec) <= {"status", "json", "body", "error"}, path.name
