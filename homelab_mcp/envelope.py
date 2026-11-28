"""The result envelope every structured tool returns (02-architecture.md).

    {"status", "summary", "data", "checks", "hints", "truncated", "job_id"}

Built from the JSON Lines a diagnostic prints with DIAG_FORMAT=json
(diagnostics/diag_lib.sh). Pure functions with no MCP SDK dependency, so they
can be tested and reused on their own.
"""

from __future__ import annotations

import json
import re
from typing import Any, Iterable

SUMMARY_MAX = 199  # the contract: under 200 characters
RESULT_MAX_BYTES = 8192  # hard cap per result; longer results are truncated

# Worst first. A diagnostic's summary status maps onto the envelope's.
_RANK = {"fail": 0, "error": 1, "warn": 2, "ok": 3}

_REDACTIONS = [
    # X-Plex-Token=..., ?X-Plex-Token=...
    (re.compile(r"(?i)(x-plex-token[=:]\s*)[^\s&\"']+"), r"\1[redacted]"),
    # Authorization: Bearer ..., bearer tokens anywhere
    (re.compile(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]+"), r"\1[redacted]"),
    # KEY=value for anything that looks like a secret
    (
        re.compile(
            r"(?i)\b([A-Z0-9_]*(?:PASSWORD|SECRET|TOKEN|API_KEY|APIKEY)[A-Z0-9_]*)"
            r"(\s*[=:]\s*)[^\s\"']+"
        ),
        r"\1\2[redacted]",
    ),
    # x-api-key: ...
    (re.compile(r"(?i)(x-api-key[=:]\s*)[^\s\"']+"), r"\1[redacted]"),
]


def redact(text: str) -> str:
    """Remove API keys, Plex tokens, passwords and bearer tokens from text."""
    for pattern, replacement in _REDACTIONS:
        text = pattern.sub(replacement, text)
    return text


def parse_stream(stdout: str) -> tuple[list[dict], int]:
    """Parse DIAG_FORMAT=json output into records; also count unparsable lines."""
    records: list[dict] = []
    bad = 0
    for line in stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            bad += 1
            continue
        if isinstance(record, dict) and "type" in record:
            records.append(record)
        else:
            bad += 1
    return records, bad


def _shorten(text: str, limit: int) -> str:
    return text if len(text) <= limit else text[: limit - 1] + "…"


def _component_summaries(records: Iterable[dict]) -> dict[str, dict[str, Any]]:
    """Combine summary records per component (a component may run 2 scripts)."""
    out: dict[str, dict[str, Any]] = {}
    for r in records:
        if r.get("type") != "summary":
            continue
        comp = r.get("component", "unknown")
        cur = out.setdefault(
            comp, {"status": "ok", "passed": 0, "warnings": 0, "failures": 0}
        )
        status = r.get("status", "error")
        if status == "unknown":
            status = "warn"  # a diagnostic that ran no checks proves nothing
        if _RANK.get(status, 1) < _RANK.get(cur["status"], 1):
            cur["status"] = status
        for key in ("passed", "warnings", "failures"):
            cur[key] += int(r.get(key, 0))
    return out


def build(
    records: list[dict],
    *,
    verbose: bool = False,
    errors: Iterable[str] = (),
    hints: Iterable[str] = (),
    data: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """The envelope for a set of diagnostic records.

    errors: problems running the diagnostics themselves (a timeout, a script
    that printed no summary); each makes the result an error unless a check
    already failed.
    """
    errors = [redact(e) for e in errors]
    checks = [
        {
            "id": r.get("id", ""),
            "status": r.get("status", "fail"),
            "message": redact(str(r.get("message", ""))),
            "component": r.get("component", ""),
        }
        for r in records
        if r.get("type") == "check"
    ]
    components = _component_summaries(records)

    status = "ok"
    for comp in components.values():
        if _RANK[comp["status"]] < _RANK[status]:
            status = comp["status"]
    if errors and _RANK[status] > _RANK["error"]:
        status = "error"
    if not components and not errors:
        status = "error"
        errors = ["no diagnostic results"]

    failing = [c for c in checks if c["status"] == "fail"]
    warning = [c for c in checks if c["status"] == "warn"]
    if failing:
        head = f"{len(failing)} failing"
        if warning:
            head += f", {len(warning)} warnings"
        detail = "; ".join(c["message"] for c in failing[:2])
    elif errors:
        head, detail = "Error", "; ".join(errors[:2])
    elif warning:
        head = f"{len(warning)} warnings"
        detail = "; ".join(c["message"] for c in warning[:2])
    else:
        head, detail = f"All {len(checks)} checks passed", ""
    summary = _shorten(f"{head}: {detail}" if detail else head, SUMMARY_MAX)

    shown = checks if verbose else [c for c in checks if c["status"] != "ok"]
    # Failures first, then warnings, so a cap or a truncation drops the least
    # important checks.
    shown.sort(key=lambda c: _RANK.get(c["status"], 1))
    envelope: dict[str, Any] = {
        "status": status,
        "summary": summary,
        "data": {"components": components, **(data or {})},
        "checks": shown,
        "hints": list(hints),
        "truncated": False,
        "job_id": None,
    }
    if errors:
        envelope["data"]["errors"] = errors
    if status != "ok" and not verbose and not envelope["hints"]:
        for comp, info in components.items():
            if info["status"] != "ok" and comp != "all":
                envelope["hints"].append(
                    f"health_check(component='{comp}', verbose=true)"
                )
    return cap(envelope)


def cap(envelope: dict[str, Any], limit: int = RESULT_MAX_BYTES) -> dict[str, Any]:
    """Drop checks from the end until the JSON fits in limit bytes."""

    def size() -> int:
        return len(json.dumps(envelope, ensure_ascii=False).encode())

    while size() > limit and envelope["checks"]:
        envelope["checks"].pop()
        envelope["truncated"] = True
    if envelope["truncated"]:
        envelope["hints"] = envelope["hints"][:3] + [
            "Results were truncated; ask for one component at a time"
        ]
    return envelope


def render_text(envelope: dict[str, Any]) -> str:
    """A compact text form for clients that ignore structured content."""
    lines = [f"{envelope['status'].upper()}: {envelope['summary']}"]
    for c in envelope["checks"]:
        lines.append(f"- [{c['status']}] {c['component']}: {c['message']}")
    for h in envelope["hints"]:
        lines.append(f"hint: {h}")
    if envelope["truncated"]:
        lines.append("(truncated)")
    return "\n".join(lines)
