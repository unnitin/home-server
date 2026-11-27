"""HTTP for health probes and service APIs: localhost only, short timeouts."""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Optional
from urllib.parse import urlsplit

LOCAL = {"localhost", "127.0.0.1", "::1"}


class NotLocal(ValueError):
    """Only services on the mini itself are called."""


@dataclass(frozen=True)
class Response:
    url: str
    status: Optional[int]  # None: no answer at all
    body: bytes = b""
    elapsed_ms: int = 0
    error: str = ""

    @property
    def ok(self) -> bool:
        return self.status is not None and 200 <= self.status < 300

    def json(self) -> Any:
        return json.loads(self.body.decode("utf-8", errors="replace"))


def get(
    url: str,
    headers: Optional[dict[str, str]] = None,
    timeout: float = 5,
    max_bytes: int = 5_000_000,
) -> Response:
    if urlsplit(url).hostname not in LOCAL:
        raise NotLocal(f"not a local URL: {url}")
    req = urllib.request.Request(url, headers=headers or {})
    started = time.monotonic()

    def elapsed() -> int:
        return int((time.monotonic() - started) * 1000)

    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310
            return Response(url, resp.status, resp.read(max_bytes), elapsed())
    except urllib.error.HTTPError as err:
        return Response(url, err.code, err.read(max_bytes), elapsed())
    except (urllib.error.URLError, OSError, TimeoutError) as err:
        reason = getattr(err, "reason", err)
        return Response(url, None, b"", elapsed(), str(reason)[:200])
