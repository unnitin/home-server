"""HTTP for health probes and service APIs: localhost only, short timeouts.

Under TEST_MODE=1 nothing is sent: each request returns a recorded response
from tests/fixtures/http/ (or the folders in HOMELAB_HTTP_FIXTURES), keyed by
method, port and path (`fixture_key`). A request with no fixture is an error.
"""

from __future__ import annotations

import json
import os
import re
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional
from urllib.parse import urlsplit

from homelab.exec import FixtureMissing, test_mode

LOCAL = {"localhost", "127.0.0.1", "::1"}
FIXTURES = Path(__file__).resolve().parents[2] / "tests" / "fixtures" / "http"


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


def fixture_key(method: str, url: str) -> str:
    parts = urlsplit(url)
    raw = f"{method} {parts.port or 80}{parts.path}"
    if parts.query:
        raw += f"?{parts.query}"
    return re.sub(r"[^A-Za-z0-9.-]+", "_", raw).strip("_")[:150]


def _fixture(method: str, url: str) -> Response:
    key = fixture_key(method, url)
    extra = os.environ.get("HOMELAB_HTTP_FIXTURES", "")
    folders = [Path(d) for d in extra.split(os.pathsep) if d] + [FIXTURES]
    for folder in folders:
        path = folder / f"{key}.json"
        if path.exists():
            rec = json.loads(path.read_text(encoding="utf-8"))
            body = rec.get("body")
            if "json" in rec:
                body = json.dumps(rec["json"])
            return Response(
                url,
                rec.get("status"),
                (body or "").encode(),
                error=rec.get("error", ""),
            )
    raise FixtureMissing(f"TEST_MODE: no HTTP fixture {key}.json for {method} {url}")


def request(
    method: str,
    url: str,
    headers: Optional[dict[str, str]] = None,
    body: Optional[Any] = None,
    timeout: float = 5,
    max_bytes: int = 5_000_000,
) -> Response:
    if urlsplit(url).hostname not in LOCAL:
        raise NotLocal(f"not a local URL: {url}")
    if test_mode():
        return _fixture(method, url)
    data = None
    headers = dict(headers or {})
    if body is not None:
        data = json.dumps(body).encode()
        headers.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
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


def get(
    url: str, headers: Optional[dict[str, str]] = None, timeout: float = 5
) -> Response:
    return request("GET", url, headers=headers, timeout=timeout)


def post_json(
    url: str, body: Any, headers: Optional[dict[str, str]] = None, timeout: float = 10
) -> Response:
    """A POST that only reads, such as Immich's search endpoints."""
    return request("POST", url, headers=headers, body=body, timeout=timeout)
