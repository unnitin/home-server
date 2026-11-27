"""The safety policy, config/policy.yaml (docs/mcp-refactor/05).

Which tier each tool is in, what each token scope may see and call, the locks
that serialize changes, and the names that are never exposed (T3). The server
checks its registered tools against it at startup (`check_registered`) and
refuses to start on any mismatch, and checks every call against it.

Read like the manifest: from the YAML when PyYAML is installed, else from the
committed config/policy.json (`homelab config render` writes it).
"""

from __future__ import annotations

import re
import string
from functools import lru_cache
from pathlib import Path
from typing import Any, Iterable, Literal, Optional, Union

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from homelab import config
from homelab.exec import T3_SCRIPT

POLICY_FILE = "policy.yaml"
POLICY_JSON = "policy.json"

Tier = Literal["T0", "T1", "T2"]
TIER_ORDER = ("T0", "T1", "T2")
RATE = re.compile(r"^(\d+)/(s|sec|min|h)$")
SECONDS = {"s": 1, "sec": 1, "min": 60, "h": 3600}


class PolicyError(Exception):
    """The policy file is invalid, or doesn't match the registered tools."""


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


class TierRule(Strict):
    approval: Literal["none", "out_of_band"]
    dry_run_default: bool = False
    rate_limit: Optional[str] = None
    plan_ttl: Optional[str] = None

    @field_validator("rate_limit")
    @classmethod
    def rate_format(cls, value: Optional[str]) -> Optional[str]:
        if value is not None and not RATE.match(value):
            raise ValueError(f"rate_limit {value!r}: write it like 10/min")
        return value


class Scope(Strict):
    tiers: list[Tier]
    only: Optional[list[str]] = None  # only these tools, within those tiers


class ToolRule(Strict):
    tier: Tier
    lock: Optional[str] = None  # e.g. "service:{service}": one at a time per key


class Jobs(Strict):
    max_running: int = Field(2, ge=1, le=8)


class Policy(Strict):
    version: Literal[1]
    tiers: dict[Tier, TierRule]
    scopes: dict[str, Scope]
    toolsets: dict[str, list[str]] = Field(default_factory=dict)
    jobs: Jobs = Field(default_factory=Jobs)
    never: list[str] = Field(default_factory=list)
    tools: dict[str, Union[Tier, ToolRule]]

    @field_validator("tools")
    @classmethod
    def normalize(cls, value: dict[str, Any]) -> dict[str, Any]:
        return {
            name: ToolRule(tier=rule) if isinstance(rule, str) else rule
            for name, rule in value.items()
        }

    @model_validator(mode="after")
    def consistent(self) -> "Policy":
        problems = []
        for name, rule in self.rules().items():
            if is_never(name, self.never):
                problems.append(f"{name}: a name that's never exposed (T3)")
            if rule.tier not in self.tiers:
                problems.append(f"{name}: tier {rule.tier} isn't defined")
            if rule.lock:
                fields = [f for _, f, _, _ in string.Formatter().parse(rule.lock) if f]
                if any(not re.fullmatch(r"[a-z_]+", f) for f in fields):
                    problems.append(f"{name}: lock {rule.lock!r}: fields are names")
        for scope_name, scope in self.scopes.items():
            for tool in scope.only or []:
                if tool not in self.tools:
                    problems.append(f"scope {scope_name}: unknown tool {tool}")
        for set_name, names in self.toolsets.items():
            for tool in names:
                if tool not in self.tools:
                    problems.append(f"toolset {set_name}: unknown tool {tool}")
        if problems:
            raise ValueError("; ".join(problems))
        return self

    def rules(self) -> dict[str, ToolRule]:
        return self.tools  # type: ignore[return-value]  # normalized above

    def tier(self, tool: str) -> Optional[str]:
        rule = self.rules().get(tool)
        return rule.tier if rule else None

    def visible(
        self, tool: str, scopes: Iterable[str], toolset: Optional[str] = None
    ) -> bool:
        """Whether a token with these scopes (and toolset) may see and call tool."""
        tier = self.tier(tool)
        if tier is None or is_never(tool, self.never):
            return False
        if toolset and tool not in self.toolsets.get(toolset, []):
            return False
        for name in scopes:
            scope = self.scopes.get(name)
            if scope is None or tier not in scope.tiers:
                continue
            if scope.only is None or tool in scope.only:
                return True
        return False

    def lock_key(self, tool: str, args: dict[str, Any]) -> Optional[str]:
        rule = self.rules().get(tool)
        if not rule or not rule.lock:
            return None
        return rule.lock.format(**{k: str(v) for k, v in args.items()})

    def rate_limit(self, tier: str) -> Optional[tuple[int, int]]:
        """(calls, per seconds) for a tier, or None."""
        rule = self.tiers.get(tier)  # type: ignore[call-overload]
        if not rule or not rule.rate_limit:
            return None
        m = RATE.match(rule.rate_limit)
        assert m  # validated
        return int(m.group(1)), SECONDS[m.group(2)]

    def dry_run_default(self, tier: str) -> bool:
        rule = self.tiers.get(tier)  # type: ignore[call-overload]
        return bool(rule and rule.dry_run_default)


def is_never(name: str, never: Iterable[str] = ()) -> bool:
    """A T3 name: in the policy's `never` list, or a destructive storage command."""
    return name in set(never) or T3_SCRIPT.search(name) is not None


def read(config_dir: Path = config.CONFIG_DIR) -> dict[str, Any]:
    if config.have_yaml():
        return config.read_yaml(config_dir / POLICY_FILE)
    return config.read_json(config_dir / POLICY_JSON)


def parse(data: dict[str, Any]) -> Policy:
    try:
        return Policy.model_validate(data)
    except ValueError as err:
        raise PolicyError(f"config/{POLICY_FILE}: {err}") from err


@lru_cache(maxsize=4)
def load(config_dir: Path = config.CONFIG_DIR) -> Policy:
    return parse(read(config_dir))


def render(config_dir: Path = config.CONFIG_DIR) -> str:
    """config/policy.json, from the YAML."""
    data = config.read_yaml(config_dir / POLICY_FILE)
    parse(data)  # never render an invalid policy
    return config.render_json(data)


def check_registered(names: Iterable[str], pol: Optional[Policy] = None) -> None:
    """Raise PolicyError unless the registered tools and the policy agree."""
    pol = pol or load()
    registered = set(names)
    listed = set(pol.tools)
    problems = []
    for name in sorted(registered):
        if is_never(name, pol.never):
            problems.append(f"{name} is registered but is never exposed (T3)")
    missing = sorted(registered - listed)
    if missing:
        problems.append(f"registered but not in the policy: {', '.join(missing)}")
    stale = sorted(listed - registered)
    if stale:
        problems.append(f"in the policy but not registered: {', '.join(stale)}")
    if problems:
        raise PolicyError(
            f"config/{POLICY_FILE} doesn't match the server: " + "; ".join(problems)
        )
