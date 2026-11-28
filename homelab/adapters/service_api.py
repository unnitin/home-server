"""The shared client behind the Immich, Plex and Jellyfin API adapters.

Its base URL and secret name come from the manifest (`services.<name>.api`).
A call that needs the secret, made while the secret isn't set, raises
SecretMissing, which names the command that sets it: tools say what to do,
not just that it failed.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Optional

from homelab import secrets
from homelab.adapters import http


class ApiError(Exception):
    """The service answered badly, or not at all."""


class SecretMissing(ApiError):
    def __init__(self, service: str, secret: str):
        super().__init__(
            f"{service}: no API secret set (run: homelab secrets set {secret})"
        )
        self.service, self.secret = service, secret


class SecretRejected(ApiError):
    def __init__(self, service: str, secret: str, status: int):
        super().__init__(
            f"{service}: the API rejected the secret (HTTP {status}); "
            f"replace it: homelab secrets set {secret}"
        )
        self.service, self.secret = service, secret


@dataclass
class Client:
    service: str
    base: str
    secret: str
    auth_headers: Callable[[str], dict[str, str]]
    timeout: float = 5

    @classmethod
    def for_service(
        cls, name: str, auth_headers: Callable[[str], dict[str, str]]
    ) -> "Client":
        from homelab import config

        svc = config.load().services[name]
        if svc.api is None:
            raise ApiError(f"{name} has no api in the manifest")
        return cls(name, svc.api.base, svc.api.secret, auth_headers)

    def has_secret(self) -> bool:
        return secrets.get(self.secret) is not None

    def _headers(self, public: bool) -> dict[str, str]:
        headers = {"Accept": "application/json"}
        if not public:
            value = secrets.get(self.secret)
            if value is None:
                raise SecretMissing(self.service, self.secret)
            headers.update(self.auth_headers(value))
        return headers

    def _check(self, r: http.Response) -> Any:
        if r.status is None:
            raise ApiError(f"{self.service}: no answer ({r.error})")
        if r.status in (401, 403):
            raise SecretRejected(self.service, self.secret, r.status)
        if not r.ok:
            raise ApiError(f"{self.service}: HTTP {r.status} from {r.url}")
        try:
            return r.json()
        except ValueError as err:
            raise ApiError(f"{self.service}: not JSON from {r.url}") from err

    def get(self, path: str, public: bool = False) -> Any:
        r = http.get(self.base + path, self._headers(public), timeout=self.timeout)
        return self._check(r)

    def post(self, path: str, body: Any, public: bool = False) -> Any:
        r = http.post_json(
            self.base + path, body, self._headers(public), timeout=self.timeout * 2
        )
        return self._check(r)

    def act(self, method: str, path: str, body: Any = None) -> int:
        """A request that changes something (T1 actions: a library scan, an
        Immich job). Returns the HTTP status; the body, often empty, is ignored."""
        r = http.request(
            method,
            self.base + path,
            headers=self._headers(False),
            body=body,
            timeout=self.timeout * 2,
        )
        if r.status is None:
            raise ApiError(f"{self.service}: no answer ({r.error})")
        if r.status in (401, 403):
            raise SecretRejected(self.service, self.secret, r.status)
        if not r.ok:
            raise ApiError(f"{self.service}: HTTP {r.status} from {method} {r.url}")
        return r.status


def optional(fn: Callable[[], Any]) -> tuple[Optional[Any], Optional[str]]:
    """(result, None) or (None, the reason), for reports that go on without it."""
    try:
        return fn(), None
    except ApiError as err:
        return None, str(err)
