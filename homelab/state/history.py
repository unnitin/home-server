"""history_query: a metric's series from the snapshots, downsampled, with its range
and trend, and when it last crossed a threshold."""

from __future__ import annotations

import re
import sqlite3
from datetime import datetime, timezone
from typing import Any, Optional

MAX_POINTS = 120
UNITS = {"m": 60, "h": 3600, "d": 86400, "w": 604800, "y": 31536000}


def seconds(text: str) -> int:
    m = re.fullmatch(r"(\d+)\s*([mhdwy])", text.strip())
    if not m:
        raise ValueError(
            f"use a number and m, h, d, w or y, like 30m, 7d, 1y: {text!r}"
        )
    return int(m.group(1)) * UNITS[m.group(2)]


def _epoch(ts: str) -> float:
    return (
        datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")
        .replace(tzinfo=timezone.utc)
        .timestamp()
    )


def _iso(epoch: float) -> str:
    return datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def metrics(conn: sqlite3.Connection) -> list[str]:
    return [
        r[0]
        for r in conn.execute("SELECT DISTINCT metric FROM metrics ORDER BY metric")
    ]


def query(
    conn: sqlite3.Connection,
    metric: str,
    since: str = "7d",
    bucket: str = "1h",
    above: Optional[float] = None,
    below: Optional[float] = None,
    now: Optional[float] = None,
) -> dict[str, Any]:
    now = now or datetime.now(timezone.utc).timestamp()
    window, step = seconds(since), seconds(bucket)
    start = _iso(now - window)
    rows = conn.execute(
        "SELECT ts, value FROM metrics WHERE metric=? AND ts>=? ORDER BY ts",
        (metric, start),
    ).fetchall()
    out: dict[str, Any] = {"metric": metric, "since": since, "samples": len(rows)}
    if not rows:
        return out
    while window / step > MAX_POINTS:
        step *= 2
    buckets: dict[int, list[float]] = {}
    for ts, value in rows:
        buckets.setdefault(int(_epoch(ts) // step), []).append(value)
    out["bucket_s"] = step
    out["points"] = [
        {
            "ts": _iso(b * step),
            "avg": round(sum(v) / len(v), 2),
            "min": min(v),
            "max": max(v),
        }
        for b, v in sorted(buckets.items())
    ]
    values = [v for _, v in rows]
    out["min"], out["max"] = min(values), max(values)
    out["first"], out["last"] = {"ts": rows[0][0], "value": rows[0][1]}, {
        "ts": rows[-1][0],
        "value": rows[-1][1],
    }
    span_days = (_epoch(rows[-1][0]) - _epoch(rows[0][0])) / 86400
    if span_days >= 0.04 and len(rows) > 1:  # an hour or more: a slope means something
        xs = [(_epoch(t) - _epoch(rows[0][0])) / 86400 for t, _ in rows]
        mx, my = sum(xs) / len(xs), sum(values) / len(values)
        var = sum((x - mx) ** 2 for x in xs)
        slope = (
            sum((x - mx) * (y - my) for x, y in zip(xs, values)) / var if var else 0.0
        )
        out["trend_per_day"] = round(slope, 3)
    for name, threshold, crossed in (
        ("above", above, lambda v, t: v > t),
        ("below", below, lambda v, t: v < t),
    ):
        if threshold is None:
            continue
        hits = [(t, v) for t, v in rows if crossed(v, threshold)]
        out[name] = {
            "threshold": threshold,
            "now": crossed(rows[-1][1], threshold),
            "last": {"ts": hits[-1][0], "value": hits[-1][1]} if hits else None,
            "first": {"ts": hits[0][0], "value": hits[0][1]} if hits else None,
            "samples": len(hits),
        }
    return out


def days_until(
    conn: sqlite3.Connection, metric: str, limit: float = 100.0, window: str = "14d"
) -> Optional[float]:
    """At the recent trend, days until the metric reaches `limit` (None: not rising)."""
    q = query(conn, metric, since=window, bucket="1d")
    slope = q.get("trend_per_day")
    if not slope or slope <= 0 or "last" not in q:
        return None
    return round((limit - q["last"]["value"]) / slope, 1)
