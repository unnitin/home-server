"""Disks, RAID sets and volumes, from `diskutil … -plist` (read-only).

Only diskutil decides whether a volume is mounted (D22, D25, D31): a folder
under /Volumes proves nothing. Usage numbers are read with statvfs, and only
from a mount diskutil reports, so an empty mount-point folder is never
measured as if it were the volume.
"""

from __future__ import annotations

import os
import plistlib
import re
from dataclasses import dataclass, field
from typing import Any, Optional

from homelab import exec as hexec


@dataclass(frozen=True)
class Member:
    device: str  # e.g. disk6s2
    status: str  # Online, Degraded, Rebuilding, Failed, Offline …
    progress: Optional[str] = None  # rebuild progress, when diskutil gives one

    @property
    def disk(self) -> str:
        """The whole disk: disk6s2 -> disk6."""
        return re.sub(r"s\d+$", "", self.device)


@dataclass(frozen=True)
class RaidSet:
    name: str
    device: str  # the set's own disk, e.g. disk8
    status: str  # Online, Degraded, Offline …
    level: str
    size: int
    members: tuple[Member, ...] = ()
    rebuild: str = ""  # Manual or Automatic

    @property
    def healthy(self) -> bool:
        return self.status == "Online" and all(
            m.status == "Online" for m in self.members
        )


@dataclass(frozen=True)
class Volume:
    mount: str
    name: str
    device: str
    fs: str
    stores: tuple[str, ...] = ()  # APFS physical stores, e.g. ("disk8",)


@dataclass(frozen=True)
class Usage:
    total: int
    free: int

    @property
    def used(self) -> int:
        return self.total - self.free

    @property
    def used_pct(self) -> float:
        return round(100.0 * self.used / self.total, 1) if self.total else 0.0


@dataclass(frozen=True)
class Partition:
    device: str
    content: str
    size: int
    name: str = ""


@dataclass(frozen=True)
class Disk:
    device: str
    scheme: str
    size: int
    partitions: tuple[Partition, ...] = field(default_factory=tuple)


class DiskutilError(Exception):
    """diskutil failed in a way that says nothing about the disks."""


def _plist(argv: list[str], timeout: float = 30) -> Optional[dict[str, Any]]:
    """diskutil's plist output, or None when diskutil says the target isn't there."""
    r = hexec.run(argv, timeout=timeout)
    if r.timed_out:
        raise DiskutilError(f"{' '.join(argv)} timed out")
    try:
        data = plistlib.loads(r.stdout.encode())
    except Exception as err:  # plistlib raises several types
        if r.rc != 0:
            return None
        raise DiskutilError(f"{' '.join(argv)}: unreadable output ({err})") from err
    if r.rc != 0 or "Error" in data:
        return None
    return data


def raid_sets() -> list[RaidSet]:
    data = _plist(["diskutil", "appleRAID", "list", "-plist"]) or {}
    sets = []
    for s in data.get("AppleRAIDSets", []):
        members = tuple(
            Member(
                device=m.get("BSD Name", "?"),
                status=m.get("MemberStatus", "Unknown"),
                progress=m.get("RebuildProgress") or m.get("Progress"),
            )
            for m in s.get("Members", [])
        )
        sets.append(
            RaidSet(
                name=s.get("Name", ""),
                device=s.get("BSD Name", ""),
                status=s.get("Status", "Unknown"),
                level=s.get("Level", ""),
                size=int(s.get("Size", 0)),
                members=members,
                rebuild=s.get("Rebuild", ""),
            )
        )
    return sets


def info(target: str) -> Optional[dict[str, Any]]:
    """`diskutil info -plist TARGET`, or None if diskutil doesn't know it."""
    return _plist(["diskutil", "info", "-plist", target])


def volume(mount: str) -> Optional[Volume]:
    """The volume mounted at `mount`, or None. Asks diskutil, never the folder."""
    data = info(mount)
    if not data or data.get("MountPoint") != mount:
        return None
    stores = tuple(
        s.get("APFSPhysicalStore", "") for s in data.get("APFSPhysicalStores", [])
    )
    return Volume(
        mount=mount,
        name=data.get("VolumeName", ""),
        device=data.get("DeviceIdentifier", ""),
        fs=data.get("FilesystemType", ""),
        stores=tuple(s for s in stores if s),
    )


def usage(vol: Volume) -> Usage:
    """Size and free space of a mounted volume (statvfs on its mount point)."""
    st = os.statvfs(vol.mount)
    return Usage(total=st.f_blocks * st.f_frsize, free=st.f_bavail * st.f_frsize)


def external_disks() -> list[Disk]:
    data = _plist(["diskutil", "list", "-plist", "external"]) or {}
    disks = []
    for d in data.get("AllDisksAndPartitions", []):
        parts = tuple(
            Partition(
                device=p.get("DeviceIdentifier", ""),
                content=p.get("Content", ""),
                size=int(p.get("Size", 0)),
                name=p.get("VolumeName", "") or "",
            )
            for p in d.get("Partitions", [])
        )
        disks.append(
            Disk(
                device=d.get("DeviceIdentifier", ""),
                scheme=d.get("Content", ""),
                size=int(d.get("Size", 0)),
                partitions=parts,
            )
        )
    return disks


def orphan_members(sets: list[RaidSet], disks: list[Disk]) -> list[Partition]:
    """Apple_RAID partitions that no assembled set claims: a set's lost half."""
    claimed = {m.device for s in sets for m in s.members}
    return [
        p
        for d in disks
        for p in d.partitions
        if p.content == "Apple_RAID" and p.device not in claimed
    ]


def unreadable_disks(disks: list[Disk]) -> list[Disk]:
    """External disks with no usable partition map (e.g. a lone 0xEE entry)."""
    return [
        d
        for d in disks
        if d.scheme not in ("GUID_partition_scheme", "Apple_APFS", "")
        and not any(p.content.startswith("Apple_") for p in d.partitions)
        and d.scheme != "Apple_APFS_Container"
    ]
