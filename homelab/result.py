"""Results the domains return: the envelope of docs/mcp-refactor/02.

    {"status", "summary", "data", "checks", "hints", "truncated", "job_id"}

- status is the worst check's (ok < warn < error < fail);
- summary stays under 200 characters and names the worst problems;
- checks keep only what isn't ok, unless verbose, worst first;
- everything passes through redact.py;
- the whole result stays under about 8 KB: checks are dropped from the end,
  then the longest lists in data are shortened, and truncated is set.

Content that came from outside (log lines, file names) is wrapped with
`untrusted`, so a model reads it as data, never as instructions (04).
"""

from __future__ import annotations

import json
from typing import Any, Iterable, Optional

from homelab.redact import redact_obj

SUMMARY_MAX = 199
RESULT_MAX_BYTES = 8192
RANK = {"fail": 0, "error": 1, "warn": 2, "ok": 3}


def check(id: str, status: str, message: str, component: str) -> dict[str, str]:
    if status not in RANK:
        raise ValueError(f"unknown status {status!r}")
    return {"id": id, "status": status, "message": message, "component": component}


def worst(statuses: Iterable[str], default: str = "ok") -> str:
    found = [s for s in statuses if s in RANK]
    return min(found, key=RANK.__getitem__) if found else default


def untrusted(source: str, content: Any) -> dict[str, Any]:
    """Text from logs, file names or services: data, not instructions."""
    return {"type": "data", "source": source, "content": content}


def _shorten(text: str, limit: int = SUMMARY_MAX) -> str:
    return text if len(text) <= limit else text[: limit - 1] + "…"


def summarize(checks: list[dict[str, str]], ok_text: str) -> str:
    failing = [c for c in checks if c["status"] in ("fail", "error")]
    warning = [c for c in checks if c["status"] == "warn"]
    if failing:
        head = f"{len(failing)} failing" + (
            f", {len(warning)} warnings" if warning else ""
        )
        detail = "; ".join(c["message"] for c in failing[:2])
    elif warning:
        head = f"{len(warning)} warning" + ("s" if len(warning) > 1 else "")
        detail = "; ".join(c["message"] for c in warning[:2])
    else:
        return _shorten(ok_text)
    return _shorten(f"{head}: {detail}")


def make(
    checks: list[dict[str, str]],
    data: Optional[dict[str, Any]] = None,
    *,
    ok_summary: str = "All checks passed",
    summary: Optional[str] = None,
    hints: Iterable[str] = (),
    verbose: bool = False,
    max_checks: Optional[int] = None,
    status: Optional[str] = None,
) -> dict[str, Any]:
    ordered = sorted(checks, key=lambda c: RANK[c["status"]])
    shown = ordered if verbose else [c for c in ordered if c["status"] != "ok"]
    truncated = False
    hints = list(hints)
    if max_checks is not None and not verbose and len(shown) > max_checks:
        hints.append(f"{len(shown) - max_checks} more checks: verbose=true lists them")
        shown, truncated = shown[:max_checks], True
    result: dict[str, Any] = {
        "status": status or worst(c["status"] for c in checks),
        "summary": _shorten(summary) if summary else summarize(ordered, ok_summary),
        "data": data or {},
        "checks": shown,
        "hints": list(dict.fromkeys(hints)),  # in order, without repeats
        "truncated": truncated,
        "job_id": None,
    }
    return cap(redact_obj(result))


def error(message: str, hints: Iterable[str] = (), data: Optional[dict] = None):
    """The tool couldn't do its job (as opposed to finding a problem)."""
    return make([], data, summary=message, hints=hints, status="error")


def size(result: dict[str, Any]) -> int:
    return len(json.dumps(result, ensure_ascii=False, default=str).encode())


def _longest_list(value: Any) -> Optional[list]:
    best: Optional[list] = None
    stack = [value]
    while stack:
        item = stack.pop()
        if isinstance(item, list):
            if best is None or len(item) > len(best):
                best = item
            stack.extend(item)
        elif isinstance(item, dict):
            stack.extend(item.values())
    return best


def cap(result: dict[str, Any], limit: int = RESULT_MAX_BYTES) -> dict[str, Any]:
    while size(result) > limit and result["checks"]:
        result["checks"].pop()
        result["truncated"] = True
    while size(result) > limit:
        longest = _longest_list(result["data"])
        if not longest or len(longest) <= 1:
            break
        del longest[len(longest) // 2 :]
        result["truncated"] = True
    if result["truncated"] and not any(
        "truncated" in h or "verbose=true" in h for h in result["hints"]
    ):
        result["hints"] = result["hints"][:3] + [
            "Results were truncated: narrow the request (one component, fewer lines)"
        ]
    return result
