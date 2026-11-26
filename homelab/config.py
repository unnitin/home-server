"""Load, validate and render the manifest, config/homelab.yaml.

The manifest is the single source of truth for storage tiers, services, ports,
LaunchD labels, health endpoints, tailnet mappings and media paths
(docs/mcp-refactor/02-architecture.md). Per-machine overrides in
config/homelab.local.yaml are merged over it.

Bash never parses YAML. `render` writes what bash reads:
- config/homelab.env: flat HOMELAB_* variables, committed, sourced by
  scripts/core/environment.sh and diagnostics/diag_lib.sh;
- config/tailscale_serve.txt: the tailnet mappings, committed, read by
  apply_tailscale_serve.sh and check_remote_access.sh;
- config/homelab.local.env: only the values the local overrides change
  (gitignored; written only when homelab.local.yaml exists).
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Literal, Optional

import yaml
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

REPO = Path(__file__).resolve().parents[1]
CONFIG_DIR = REPO / "config"
MANIFEST = "homelab.yaml"
LOCAL_MANIFEST = "homelab.local.yaml"
ENV_FILE = "homelab.env"
LOCAL_ENV_FILE = "homelab.local.env"
SERVE_FILE = "tailscale_serve.txt"

NAME = re.compile(r"^[a-z][a-z0-9_]*$")
LABEL = re.compile(r"^io\.homelab\.[a-z0-9]+(\.[a-z0-9]+)*$")


class Strict(BaseModel):
    """Unknown keys are errors, so a typo in the manifest fails loudly."""

    model_config = ConfigDict(extra="forbid")


def relative_dir(value: str) -> str:
    """A folder inside a tier or the repo: relative, no '..'."""
    if not value or value.startswith("/") or ".." in value.split("/"):
        raise ValueError(f"must be a relative path without '..': {value!r}")
    return value


class Host(Strict):
    name: str
    repo_root: Literal["auto"] = "auto"


class Tier(Strict):
    mount: str
    media: Literal["nvme", "ssd", "hdd"]
    raid: Literal["mirror", "stripe", "none"]
    warn_pct: int = Field(85, ge=1, le=100)
    crit_pct: int = Field(95, ge=1, le=100)
    use: str = ""

    @field_validator("mount")
    @classmethod
    def under_volumes(cls, value: str) -> str:
        if not re.fullmatch(r"/Volumes/[A-Za-z0-9_-]+", value):
            raise ValueError(f"a tier mounts at /Volumes/<name>: {value!r}")
        return value

    @model_validator(mode="after")
    def thresholds(self) -> "Tier":
        if self.warn_pct >= self.crit_pct:
            raise ValueError("warn_pct must be below crit_pct")
        return self


class Storage(Strict):
    state_dir: str
    log_root: str
    launchd_log_dir: str
    tiers: dict[str, Tier]


class Health(Strict):
    http: Optional[str] = None
    expect: int = 200
    cmd: Optional[list[str]] = None

    @model_validator(mode="after")
    def one_probe(self) -> "Health":
        if (self.http is None) == (self.cmd is None):
            raise ValueError("health needs exactly one of http or cmd")
        return self


class Resources(Strict):
    """A VM's size, e.g. the Colima VM that runs Docker."""

    cpu: int = Field(ge=1)
    memory_gb: int = Field(ge=1)
    disk_gb: int = Field(ge=10)


class Service(Strict):
    kind: Literal["job", "runtime", "compose", "native_app", "process", "daemon"]
    launchd: str
    ports: list[int] = []
    health: Optional[Health] = None
    depends_on: list[str] = []
    app: Optional[str] = None
    compose_dir: Optional[str] = None
    version_env: Optional[str] = None
    listen: Optional[str] = None
    optional: bool = False
    resources: Optional[Resources] = None
    data_tier: Optional[str] = None  # the tier that holds the app's own data
    data_dir: Optional[str] = None  # that data's folder on the tier

    @field_validator("data_dir")
    @classmethod
    def data_dir_relative(cls, value: Optional[str]) -> Optional[str]:
        return None if value is None else relative_dir(value)

    @field_validator("launchd")
    @classmethod
    def label(cls, value: str) -> str:
        if not LABEL.match(value):
            raise ValueError(f"LaunchD labels are io.homelab.<name>: {value!r}")
        return value

    @field_validator("compose_dir")
    @classmethod
    def compose_dir_relative(cls, value: Optional[str]) -> Optional[str]:
        return None if value is None else relative_dir(value)

    @field_validator("listen")
    @classmethod
    def host_port(cls, value: Optional[str]) -> Optional[str]:
        if value is not None and not re.fullmatch(r"[0-9.]+:[0-9]{2,5}", value):
            raise ValueError(f"listen is <ip>:<port>: {value!r}")
        return value

    @model_validator(mode="after")
    def kind_fields(self) -> "Service":
        if self.kind == "compose" and not self.compose_dir:
            raise ValueError("a compose service needs compose_dir")
        if self.kind == "native_app" and not self.app:
            raise ValueError("a native_app service needs app")
        if (self.data_tier is None) != (self.data_dir is None):
            raise ValueError("data_tier and data_dir go together")
        return self

    def all_ports(self) -> list[int]:
        """Ports the service listens on, its loopback `listen` port included."""
        extra = [int(self.listen.rsplit(":", 1)[1])] if self.listen else []
        return self.ports + extra


class ServeMapping(Strict):
    https: int
    target: str
    service: str

    @field_validator("target")
    @classmethod
    def local_target(cls, value: str) -> str:
        if not re.fullmatch(r"http://(localhost|127\.0\.0\.1):[0-9]{2,5}", value):
            raise ValueError(f"serve targets are local http URLs: {value!r}")
        return value

    def target_port(self) -> int:
        return int(self.target.rsplit(":", 1)[1])


class RemoteAccess(Strict):
    tailscale_serve: list[ServeMapping]


class Library(Strict):
    dir: str
    staging: str

    @field_validator("dir", "staging")
    @classmethod
    def relative(cls, value: str) -> str:
        return relative_dir(value)


class Media(Strict):
    tier: str
    staging: str
    failed: str
    libraries: dict[str, Library]

    @field_validator("staging", "failed")
    @classmethod
    def relative(cls, value: str) -> str:
        return relative_dir(value)


class Photos(Strict):
    tier: str
    library: str
    takeout_downloads: str
    takeout_work_dir: str

    @field_validator("library", "takeout_downloads", "takeout_work_dir")
    @classmethod
    def relative(cls, value: str) -> str:
        return relative_dir(value)


class Manifest(Strict):
    host: Host
    storage: Storage
    services: dict[str, Service]
    boot_order: list[str]
    remote_access: RemoteAccess
    media: Media
    photos: Photos

    @model_validator(mode="after")
    def consistent(self) -> "Manifest":
        tiers, services = self.storage.tiers, self.services
        for name in [*tiers, *services, *self.media.libraries]:
            if not NAME.match(name):
                raise ValueError(f"names are lower_snake_case: {name!r}")
        if sorted(self.boot_order) != sorted(services):
            raise ValueError("boot_order must list every service exactly once")
        for name, svc in services.items():
            if svc.data_tier is not None and svc.data_tier not in tiers:
                raise ValueError(f"{name}.data_tier is not a storage tier")
            for dep in svc.depends_on:
                if dep not in services and dep not in tiers:
                    raise ValueError(f"{name} depends on unknown {dep!r}")
        labels = [svc.launchd for svc in services.values()]
        if len(set(labels)) != len(labels):
            raise ValueError("LaunchD labels must be unique")
        ports = [p for svc in services.values() for p in svc.all_ports()]
        if len(set(ports)) != len(ports):
            raise ValueError("two services claim the same port")
        serve = self.remote_access.tailscale_serve
        if len({m.https for m in serve}) != len(serve):
            raise ValueError("two tailnet mappings use the same https port")
        for m in serve:
            if m.service not in services:
                raise ValueError(f"tailnet mapping for unknown service {m.service!r}")
            if m.target_port() not in services[m.service].all_ports():
                raise ValueError(
                    f"tailnet :{m.https} targets port {m.target_port()}, "
                    f"which {m.service} doesn't listen on"
                )
        for section, tier in (("media", self.media.tier), ("photos", self.photos.tier)):
            if tier not in tiers:
                raise ValueError(f"{section}.tier is not a storage tier: {tier!r}")
        return self


# --- loading -----------------------------------------------------------------


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    """Override wins; dicts merge key by key, anything else is replaced."""
    merged = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def read_yaml(path: Path) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        raise ValueError(f"{path} must hold a mapping")
    return data


def load(config_dir: Path = CONFIG_DIR, local: bool = True) -> Manifest:
    """The manifest, with config/homelab.local.yaml merged over it if present."""
    data = read_yaml(config_dir / MANIFEST)
    local_path = config_dir / LOCAL_MANIFEST
    if local and local_path.exists():
        data = deep_merge(data, read_yaml(local_path))
    return Manifest.model_validate(data)


# --- rendering ---------------------------------------------------------------


def env_key(*parts: str) -> str:
    return "HOMELAB_" + "_".join(re.sub(r"[^A-Za-z0-9]", "_", p).upper() for p in parts)


def sh_quote(value: str) -> str:
    """Double-quoted for bash; a leading ~/ becomes $HOME/ (no user path is written)."""

    def escape(text: str) -> str:
        for ch in ("\\", '"', "$", "`"):
            text = text.replace(ch, "\\" + ch)
        return text

    if value.startswith("~/"):
        return '"$HOME/' + escape(value[2:]) + '"'
    return '"' + escape(value) + '"'


def env_items(m: Manifest) -> list[tuple[str, str]]:
    """Every value bash may need, as (HOMELAB_* name, value), in a stable order."""
    items: list[tuple[str, str]] = [
        (env_key("host", "name"), m.host.name),
        (env_key("state", "dir"), m.storage.state_dir),
        (env_key("log", "root"), m.storage.log_root),
        (env_key("launchd", "log", "dir"), m.storage.launchd_log_dir),
        (env_key("tiers"), " ".join(m.storage.tiers)),
    ]
    for name, tier in m.storage.tiers.items():
        items += [
            (env_key("tier", name, "mount"), tier.mount),
            (env_key("tier", name, "media"), tier.media),
            (env_key("tier", name, "raid"), tier.raid),
            (env_key("tier", name, "warn", "pct"), str(tier.warn_pct)),
            (env_key("tier", name, "crit", "pct"), str(tier.crit_pct)),
            (env_key("tier", name, "use"), tier.use),
        ]
    items += [
        (env_key("services"), " ".join(m.boot_order)),
        (
            env_key("launchd", "services"),
            " ".join(
                m.services[s].launchd.removeprefix("io.homelab.") for s in m.boot_order
            ),
        ),
    ]
    for name in m.boot_order:
        svc = m.services[name]
        items += [
            (env_key("svc", name, "kind"), svc.kind),
            (env_key("svc", name, "launchd"), svc.launchd),
            (env_key("svc", name, "ports"), " ".join(map(str, svc.ports))),
        ]
        if svc.health and svc.health.http:
            items += [
                (env_key("svc", name, "health", "url"), svc.health.http),
                (env_key("svc", name, "health", "expect"), str(svc.health.expect)),
            ]
        if svc.resources:
            items += [
                (env_key("svc", name, "cpu"), str(svc.resources.cpu)),
                (env_key("svc", name, "memory", "gb"), str(svc.resources.memory_gb)),
                (env_key("svc", name, "disk", "gb"), str(svc.resources.disk_gb)),
            ]
        if svc.data_tier and svc.data_dir:
            data = f"{m.storage.tiers[svc.data_tier].mount}/{svc.data_dir}"
            items += [
                (env_key("svc", name, "data", "tier"), svc.data_tier),
                (env_key("svc", name, "data", "dir"), data),
            ]
        for field in ("app", "compose_dir", "version_env", "listen"):
            value = getattr(svc, field)
            if value is not None:
                items.append((env_key("svc", name, field), value))
    root = m.storage.tiers[m.media.tier].mount
    items += [
        (env_key("media", "root"), root),
        (env_key("media", "staging"), f"{root}/{m.media.staging}"),
        (env_key("media", "failed"), f"{root}/{m.media.failed}"),
        (env_key("media", "libraries"), " ".join(m.media.libraries)),
    ]
    for name, lib in m.media.libraries.items():
        items += [
            (env_key("media", name, "dir"), f"{root}/{lib.dir}"),
            (
                env_key("media", name, "staging"),
                f"{root}/{m.media.staging}/{lib.staging}",
            ),
        ]
    photos = m.storage.tiers[m.photos.tier].mount
    items += [
        (env_key("photos", "library"), f"{photos}/{m.photos.library}"),
        (env_key("takeout", "downloads"), f"{photos}/{m.photos.takeout_downloads}"),
        (env_key("takeout", "work", "dir"), f"{photos}/{m.photos.takeout_work_dir}"),
    ]
    return items


ENV_HEADER = """\
# Generated from config/homelab.yaml by `python3 -m homelab config render`.
# Don't edit: change the manifest, re-render, and commit both.
# Sourced by scripts/core/environment.sh and diagnostics/diag_lib.sh.
"""

LOCAL_ENV_HEADER = """\
# Generated from config/homelab.local.yaml by `python3 -m homelab config render`.
# Only the values the local overrides change. Sourced after homelab.env.
"""

SERVE_HEADER = """\
# Tailnet HTTPS mappings (tailscale serve). Generated from config/homelab.yaml
# (remote_access.tailscale_serve) by `python3 -m homelab config render`: edit
# the manifest, not this file. Applied by
# scripts/infrastructure/apply_tailscale_serve.sh and verified by
# diagnostics/check_remote_access.sh.
#
# Serve only, never Funnel: these are reachable from tailnet devices, not the internet.
#
# https_port  backend                  service
"""


def render_env(items: list[tuple[str, str]], header: str = ENV_HEADER) -> str:
    return header + "".join(f"{key}={sh_quote(value)}\n" for key, value in items)


def render_serve(m: Manifest) -> str:
    rows = (
        f"{s.https:<14}{s.target:<25}{s.service}\n"
        for s in m.remote_access.tailscale_serve
    )
    return SERVE_HEADER + "".join(rows)


def outputs(config_dir: Path = CONFIG_DIR) -> dict[Path, str]:
    """Every generated file and the text it should hold."""
    base = load(config_dir, local=False)
    files = {
        config_dir / ENV_FILE: render_env(env_items(base)),
        config_dir / SERVE_FILE: render_serve(base),
    }
    if (config_dir / LOCAL_MANIFEST).exists():
        before = dict(env_items(base))
        changed = [(k, v) for k, v in env_items(load(config_dir)) if before.get(k) != v]
        files[config_dir / LOCAL_ENV_FILE] = render_env(changed, LOCAL_ENV_HEADER)
    return files


def stale(config_dir: Path = CONFIG_DIR) -> list[Path]:
    """Generated files whose contents don't match the manifest."""
    return [
        path
        for path, text in outputs(config_dir).items()
        if not path.exists() or path.read_text(encoding="utf-8") != text
    ]


def write(config_dir: Path = CONFIG_DIR) -> list[Path]:
    """Write every stale generated file; returns the ones written."""
    written = []
    for path, text in outputs(config_dir).items():
        if not path.exists() or path.read_text(encoding="utf-8") != text:
            path.write_text(text, encoding="utf-8")
            written.append(path)
    return written
