#!/usr/bin/env python3
"""The manifest (config/homelab.yaml), its generated files, and their fit with the repo.

- The committed manifest validates, and config/homelab.env and
  config/tailscale_serve.txt match it (re-render when this fails).
- It agrees with the rest of the repo: LaunchD templates, configure_launchd.sh's
  job list, the Immich compose folder.
- The validator refuses the mistakes that would break a boot.
- homelab.env sources in bash, writes no user path, and local overrides only
  change what they name.
"""

from __future__ import annotations

import copy
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

pytest.importorskip("pydantic")
pytest.importorskip("yaml")
import yaml  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from homelab import cli, config  # noqa: E402

BASE = config.read_yaml(REPO / "config" / "homelab.yaml")


def env_of(path: Path, home: str = "/home/test") -> dict[str, str]:
    """What bash sees after sourcing an env file."""
    out = subprocess.run(
        ["bash", "-c", 'set -a; . "$1"; env', "_", str(path)],
        capture_output=True,
        text=True,
        check=True,
        env={"HOME": home, "PATH": "/usr/bin:/bin"},
    ).stdout
    return dict(
        line.split("=", 1) for line in out.splitlines() if line.startswith("HOMELAB_")
    )


@pytest.fixture
def config_dir(tmp_path: Path) -> Path:
    """A copy of config/ to render into."""
    d = tmp_path / "config"
    shutil.copytree(REPO / "config", d)
    for name in (config.LOCAL_MANIFEST, config.LOCAL_ENV_FILE):
        (d / name).unlink(missing_ok=True)
    return d


# --- the committed manifest ---------------------------------------------------


def test_the_manifest_validates():
    m = config.load(local=False)
    assert set(m.storage.tiers) == {"faststore", "warmstore", "coldstore"}


def test_generated_files_are_current():
    stale = [
        str(p.relative_to(REPO))
        for p in config.stale()
        if p.name != config.LOCAL_ENV_FILE
    ]
    assert not stale, f"re-render: python3 -m homelab config render ({stale})"


def test_tier_mounts_follow_the_decided_names():
    m = config.load(local=False)
    assert {n: t.mount for n, t in m.storage.tiers.items()} == {
        "faststore": "/Volumes/faststore",
        "warmstore": "/Volumes/warmstore",
        "coldstore": "/Volumes/coldstore",  # decided 2026-11-26 (D25), not Archive
    }


def test_media_paths_are_kebab_case():
    env = dict(config.env_items(config.load(local=False)))
    paths = [v for k, v in env.items() if k.startswith("HOMELAB_MEDIA_") and "/" in v]
    assert paths
    for path in paths:
        assert re.fullmatch(r"/Volumes/[a-z]+(/[a-z0-9-]+)*", path), path


# --- agreement with the rest of the repo -------------------------------------------


def test_every_launchd_template_is_a_service_and_back():
    labels = {s.launchd for s in config.load(local=False).services.values()}
    templates = {p.stem for p in (REPO / "launchd").glob("io.homelab.*.plist")}
    assert labels == templates


def test_configure_launchd_installs_jobs_in_boot_order():
    text = (REPO / "scripts/automation/configure_launchd.sh").read_text()
    block = re.search(r"^SERVICES=\((.*?)^\)", text, re.S | re.M).group(1)
    listed = re.findall(r'^\s*"([^"]+)"', block, re.M)
    env = dict(config.env_items(config.load(local=False)))
    assert listed == env["HOMELAB_LAUNCHD_SERVICES"].split()


def test_compose_dirs_exist():
    for name, svc in config.load(local=False).services.items():
        if svc.compose_dir:
            assert (REPO / svc.compose_dir / "docker-compose.yml").is_file(), name


def test_serve_file_parses_the_way_apply_tailscale_serve_reads_it():
    rows = [
        line.split()
        for line in (REPO / "config/tailscale_serve.txt").read_text().splitlines()
        if line.strip() and not line.startswith("#")
    ]
    m = config.load(local=False)
    assert rows == [
        [str(s.https), s.target, s.service] for s in m.remote_access.tailscale_serve
    ]


# --- what the validator refuses ------------------------------------------------------


def broken(change) -> dict:
    data = copy.deepcopy(BASE)
    change(data)
    return data


REFUSED = {
    "unknown key": lambda d: d["storage"].update(cache_dir="/tmp"),
    "service missing from boot_order": lambda d: d["boot_order"].remove("plex"),
    "service twice in boot_order": lambda d: d["boot_order"].append("plex"),
    "two services on one port": lambda d: d["services"]["landing"].update(
        ports=[32400]
    ),
    "tailnet mapping to a port nobody listens on": lambda d: d["remote_access"][
        "tailscale_serve"
    ][0].update(target="http://localhost:9999"),
    "tailnet mapping exposed beyond loopback": lambda d: d["remote_access"][
        "tailscale_serve"
    ][0].update(target="http://192.168.1.5:8080"),
    "tier outside /Volumes": lambda d: d["storage"]["tiers"]["coldstore"].update(
        mount="/Users/someone/archive"
    ),
    "'..' in a media folder": lambda d: d["media"]["libraries"]["movies"].update(
        dir="../movies"
    ),
    "warn not below crit": lambda d: d["storage"]["tiers"]["faststore"].update(
        warn_pct=95
    ),
    "dependency on nothing": lambda d: d["services"]["plex"].update(depends_on=["nas"]),
    "label outside io.homelab": lambda d: d["services"]["mcp"].update(
        launchd="com.example.mcp"
    ),
    "compose service without a folder": lambda d: d["services"]["immich"].pop(
        "compose_dir"
    ),
}


@pytest.mark.parametrize("case", sorted(REFUSED))
def test_the_validator_refuses(case):
    with pytest.raises(ValueError):
        config.Manifest.model_validate(broken(REFUSED[case]))


# --- homelab.env -----------------------------------------------------------------


def test_homelab_env_sources_in_bash():
    env = env_of(REPO / "config/homelab.env", home="/home/test")
    assert env["HOMELAB_STATE_DIR"] == "/home/test/Library/Application Support/homelab"
    assert env["HOMELAB_MEDIA_TV_DIR"] == "/Volumes/warmstore/tv-shows"
    assert env["HOMELAB_SVC_PLEX_APP"] == "Plex Media Server"
    assert env["HOMELAB_LAUNCHD_SERVICES"].split()[0] == "storage"


def test_homelab_env_names_no_user_path():
    assert "/Users/" not in (REPO / "config/homelab.env").read_text()


def test_quoting_survives_shell_characters(tmp_path):
    tricky = 'a "quoted" $HOME `cmd` back\\slash'
    path = tmp_path / "t.env"
    path.write_text(config.render_env([("HOMELAB_TRICKY", tricky)]))
    assert env_of(path)["HOMELAB_TRICKY"] == tricky


# --- local overrides and the CLI ------------------------------------------------------


def test_local_overrides_change_only_what_they_name(config_dir):
    (config_dir / config.LOCAL_MANIFEST).write_text(
        yaml.safe_dump(
            {"storage": {"tiers": {"warmstore": {"mount": "/Volumes/media2"}}}}
        )
    )
    files = config.outputs(config_dir)
    base = files[config_dir / config.ENV_FILE]
    assert (
        base == (REPO / "config/homelab.env").read_text()
    )  # the committed base is untouched
    local = config_dir / config.LOCAL_ENV_FILE
    (config_dir / config.ENV_FILE).write_text(base)
    local.write_text(files[local])
    keys = set(env_of(local))
    assert "HOMELAB_TIER_WARMSTORE_MOUNT" in keys and "HOMELAB_MEDIA_TV_DIR" in keys
    assert "HOMELAB_TIER_FASTSTORE_MOUNT" not in keys
    assert env_of(local)["HOMELAB_MEDIA_TV_DIR"] == "/Volumes/media2/tv-shows"


def test_render_check_fails_on_a_stale_file_and_render_fixes_it(config_dir, capsys):
    (config_dir / config.ENV_FILE).write_text("# hand edit\n")
    argv = ["--config-dir", str(config_dir), "config", "render"]
    assert cli.main(argv + ["--check"]) == 1
    assert "stale" in capsys.readouterr().out
    assert cli.main(argv) == 0
    assert cli.main(argv + ["--check"]) == 0


def test_get_prints_a_section_as_json(capsys):
    assert cli.main(["config", "get", "media"]) == 0
    assert json.loads(capsys.readouterr().out)["tier"] == "warmstore"


def test_a_broken_manifest_is_reported_not_raised(config_dir, capsys):
    (config_dir / config.MANIFEST).write_text(
        yaml.safe_dump(broken(REFUSED["unknown key"]))
    )
    assert cli.main(["--config-dir", str(config_dir), "config", "validate"]) == 2
    assert "homelab:" in capsys.readouterr().err
