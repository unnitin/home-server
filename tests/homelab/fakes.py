"""A fake mini for domain tests: every command and HTTP answer, as fixtures.

`Mini` starts healthy (all three tiers mounted on healthy mirrors, every
service up, the tailnet as the manifest says). A test changes what it needs,
then `install()` writes the fixtures to the test's folders.
"""

from __future__ import annotations

import json
import plistlib
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from homelab import config  # noqa: E402
from homelab import exec as hexec  # noqa: E402
from homelab.adapters import diskutil  # noqa: E402
from homelab.adapters import http as hhttp  # noqa: E402

M = config.load()
UID_DOMAIN = "gui/501"
TB = 1_000_000_000_000


@dataclass
class Tier:
    mounted: bool = True
    set_status: str = "Online"
    members: list[tuple[str, str]] = field(default_factory=list)
    used_pct: float = 40.0


@dataclass
class Mini:
    tiers: dict[str, Tier] = field(default_factory=dict)
    jobs: dict[str, dict] = field(default_factory=dict)  # label -> fields
    held: set[str] = field(default_factory=set)
    http_down: set[str] = field(default_factory=set)  # service names
    not_listening: set[int] = field(default_factory=set)
    containers_bad: set[str] = field(default_factory=set)
    docker_down: bool = False
    serve_missing: set[int] = field(default_factory=set)
    funnel: set[int] = field(default_factory=set)
    tailnet_up: bool = True
    pmset: dict[str, str] = field(default_factory=dict)
    smart_fail: set[str] = field(default_factory=set)
    orphans: list[str] = field(default_factory=list)
    unreadable: list[str] = field(default_factory=list)

    def __post_init__(self):
        disk = 4
        for name in M.storage.tiers:
            self.tiers.setdefault(
                name,
                Tier(
                    members=[
                        (f"disk{disk}s2", "Online"),
                        (f"disk{disk + 1}s2", "Online"),
                    ]
                ),
            )
            disk += 2
        for name in M.boot_order:
            svc = M.services[name]
            self.jobs.setdefault(
                svc.launchd,
                {"state": "running", "pid": 100 + len(self.jobs), "last_exit": 0},
            )
        self.pmset = {
            **{k: str(v) for k, v in M.power.model_dump().items()},
            "autorestart": "1",
            **self.pmset,
        }

    # --- writing fixtures ----------------------------------------------------------

    def install(self, tmp: Path, monkeypatch) -> None:
        ex, ht = tmp / "exec", tmp / "http"
        ex.mkdir(exist_ok=True)
        ht.mkdir(exist_ok=True)
        monkeypatch.setenv("TEST_MODE", "1")
        monkeypatch.setenv("HOMELAB_EXEC_FIXTURES", str(ex))
        monkeypatch.setenv("HOMELAB_HTTP_FIXTURES", str(ht))
        from homelab import secrets

        for name in ("immich_api_key", "plex_token", "jellyfin_api_key"):
            monkeypatch.setenv(secrets.env_name(name), f"{name}-0123456789")
        secrets.forget_cache()
        self._ex, self._ht = ex, ht
        self._disks()
        self._launchd()
        self._services()
        self._tailscale()
        self._system()
        usage = {
            M.storage.tiers[n].mount: diskutil.Usage(
                total=2 * TB, free=int(2 * TB * (1 - t.used_pct / 100))
            )
            for n, t in self.tiers.items()
        }
        monkeypatch.setattr(diskutil, "usage", lambda vol: usage[vol.mount])

    def cmd(self, argv: list[str], stdout: str = "", rc: int = 0) -> None:
        key = hexec.fixture_key(argv)
        (self._ex / f"{key}.json").write_text(json.dumps({"rc": rc, "stdout": stdout}))

    def get(self, url: str, status, body: str = "") -> None:
        key = hhttp.fixture_key("GET", url)
        rec = {"status": status, "body": body}
        if status is None:
            rec["error"] = "Connection refused"
        (self._ht / f"{key}.json").write_text(json.dumps(rec))

    def _disks(self) -> None:
        sets, parts = [], {}
        for n, (name, t) in enumerate(self.tiers.items()):
            mount = M.storage.tiers[name].mount
            set_dev = f"disk{20 + n}"
            if t.set_status:
                sets.append(
                    {
                        "Name": name,
                        "BSD Name": set_dev,
                        "Status": t.set_status,
                        "Level": "Mirror",
                        "Size": 2 * TB,
                        "Members": [
                            {"BSD Name": dev, "MemberStatus": st}
                            for dev, st in t.members
                        ],
                    }
                )
            for dev, _ in t.members:
                parts.setdefault(dev.rsplit("s", 1)[0], []).append(dev)
            if t.mounted:
                info = {
                    "MountPoint": mount,
                    "VolumeName": name,
                    "DeviceIdentifier": f"disk{30 + n}s1",
                    "FilesystemType": "apfs",
                    "APFSPhysicalStores": [{"APFSPhysicalStore": set_dev}]
                    if t.set_status
                    else [],
                }
                self.cmd(
                    ["diskutil", "info", "-plist", mount], plistlib.dumps(info).decode()
                )
            else:
                self.cmd(
                    ["diskutil", "info", "-plist", mount],
                    plistlib.dumps({"Error": True}).decode(),
                    rc=1,
                )
            for dev, _ in t.members:
                whole = dev.rsplit("s", 1)[0]
                smart = {
                    "smart_status": {"passed": whole not in self.smart_fail},
                    "temperature": {"current": 40},
                    "power_on_time": {"hours": 100},
                    "nvme_smart_health_information_log": {
                        "percentage_used": 1,
                        "media_errors": 0,
                    },
                }
                self.cmd(
                    ["smartctl", "-a", "--json", f"/dev/{whole}"], json.dumps(smart)
                )
        for dev in self.orphans:
            parts.setdefault(dev.rsplit("s", 1)[0], []).append(dev)
        disks = [
            {
                "DeviceIdentifier": whole,
                "Content": "GUID_partition_scheme",
                "Size": 2 * TB,
                "Partitions": [
                    {"DeviceIdentifier": d, "Content": "Apple_RAID", "Size": 2 * TB}
                    for d in devs
                ],
            }
            for whole, devs in sorted(parts.items())
        ] + [
            {
                "DeviceIdentifier": d,
                "Content": "FDisk_partition_scheme",
                "Size": 2 * TB,
                "Partitions": [
                    {"DeviceIdentifier": f"{d}s1", "Content": "0xEE", "Size": 1}
                ],
            }
            for d in self.unreadable
        ]
        self.cmd(
            ["diskutil", "appleRAID", "list", "-plist"],
            plistlib.dumps({"AppleRAIDSets": sets}).decode(),
        )
        self.cmd(
            ["diskutil", "list", "-plist", "external"],
            plistlib.dumps({"AllDisksAndPartitions": disks}).decode(),
        )

    def _launchd(self) -> None:
        disabled = "".join(
            f'\t\t"{label}" => {"disabled" if label in self.held else "enabled"}\n'
            for label in self.jobs
        )
        self.cmd(
            ["launchctl", "print-disabled", UID_DOMAIN],
            f"disabled services = {{\n{disabled}\t}}\n",
        )
        for label, j in self.jobs.items():
            if label in self.held or j.get("loaded") is False:
                self.cmd(["launchctl", "print", f"{UID_DOMAIN}/{label}"], "", rc=113)
                continue
            text = (
                f"{UID_DOMAIN}/{label} = {{\n\tstate = {j['state']}\n"
                + (f"\tpid = {j['pid']}\n" if j.get("pid") else "")
                + f"\truns = {j.get('runs', 1)}\n\tlast exit code = {j['last_exit']}\n"
                + "\tproperties = keepalive | runatload\n}\n"
            )
            self.cmd(["launchctl", "print", f"{UID_DOMAIN}/{label}"], text)

    def _services(self) -> None:
        for name, svc in M.services.items():
            if svc.health and svc.health.http:
                down = name in self.http_down
                body = "ok"
                if svc.health.http.endswith("/identity"):  # Plex: its version too
                    body = json.dumps({"MediaContainer": {"version": "1.42.2.10156"}})
                self.get(svc.health.http, None if down else svc.health.expect, body)
            if svc.health and svc.health.cmd:
                self.cmd(list(svc.health.cmd), "ok", rc=1 if self.docker_down else 0)
            for port in svc.all_ports():
                pid = 0 if port in self.not_listening else 1000 + port
                self.cmd(
                    ["lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN", "-t"],
                    f"{pid}\n" if pid else "",
                    rc=1 if not pid else 0,
                )
                if pid:
                    self.cmd(["ps", "-o", "etime=", "-p", str(pid)], "2-03:04:05\n")
            if svc.kind == "compose" and svc.compose_dir:
                compose = str(REPO / svc.compose_dir / "docker-compose.yml")
                argv = [
                    "docker",
                    "compose",
                    "-f",
                    compose,
                    "ps",
                    "-a",
                    "--format",
                    "json",
                ]
                if self.docker_down:
                    self.cmd(argv, "Cannot connect to the Docker daemon", rc=1)
                    continue
                names = ["immich-db", "immich-ml", "immich-redis", "immich-server"]
                rows = [
                    {
                        "Name": c,
                        "Service": c,
                        "State": "exited" if c in self.containers_bad else "running",
                        "Health": "" if c == "immich-redis" else "healthy",
                        "Status": "Up 2 days",
                        "Image": f"img/{c}",
                        "ExitCode": 0,
                    }
                    for c in names
                ]
                self.cmd(argv, "\n".join(json.dumps(r) for r in rows))
                inspect = [
                    {
                        "Name": f"/{c}",
                        "RestartCount": 0,
                        "State": {"StartedAt": "2026-11-25T00:00:00Z"},
                    }
                    for c in names
                ]
                self.cmd(["docker", "inspect", *sorted(names)], json.dumps(inspect))

    def _tailscale(self) -> None:
        status = {
            "BackendState": "Running" if self.tailnet_up else "Stopped",
            "Version": "1.104.4-x",
            "Self": {
                "Online": self.tailnet_up,
                "DNSName": "mini.example.ts.net.",
                "TailscaleIPs": ["100.64.0.1"],
            },
            "TailscaleIPs": ["100.64.0.1"],
            "Peer": {"a": {"Online": True}, "b": {"Online": False}},
            "CertDomains": ["mini.example.ts.net"],
            "Health": [],
        }
        self.cmd(["tailscale", "status", "--json"], json.dumps(status))
        web = {
            f"mini.example.ts.net:{mp.https}": {"Handlers": {"/": {"Proxy": mp.target}}}
            for mp in M.remote_access.tailscale_serve
            if mp.https not in self.serve_missing
        }
        serve = {
            "Web": web,
            "AllowFunnel": {f"mini.example.ts.net:{p}": True for p in self.funnel},
        }
        self.cmd(["tailscale", "serve", "status", "--json"], json.dumps(serve))

    def _system(self) -> None:
        lines = "System-wide power settings:\nCurrently in use:\n" + "".join(
            f" {k:<20} {v}\n" for k, v in self.pmset.items()
        )
        self.cmd(["pmset", "-g"], lines)
        self.cmd(
            ["sysctl", "-n", "kern.boottime"], "{ sec = 1000, usec = 0 } Thu Jan  1\n"
        )
        self.cmd(["sw_vers", "-productVersion"], "15.8.2\n")
