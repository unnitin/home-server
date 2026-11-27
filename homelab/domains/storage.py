"""Storage tiers: mounted, RAID state, members, SMART, usage; and recovery plans.

`status` answers storage_status. `plan_recovery` answers storage_plan_recovery:
a plan for a person to carry out. Nothing here changes a disk, and every disk
identifier it names comes from diskutil's own output, never a guess.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from typing import Any, Optional

from homelab import config
from homelab import result as R
from homelab.adapters import diskutil, system

GB = 1_000_000_000


def required_tiers(m: config.Manifest) -> set[str]:
    """Tiers a service needs: anything else (coldstore today) is an archive."""
    needed = {m.media.tier, m.photos.tier}
    for svc in m.services.values():
        needed.update(d for d in svc.depends_on if d in m.storage.tiers)
        if svc.data_tier:
            needed.add(svc.data_tier)
    return needed


def _set_for(tier: str, vol: Optional[diskutil.Volume], sets: list[diskutil.RaidSet]):
    if vol is not None:
        for s in sets:
            if s.device in vol.stores:
                return s
    return next((s for s in sets if s.name == tier), None)


def _smart(disks: list[str]) -> dict[str, system.Smart]:
    if not disks:
        return {}
    with ThreadPoolExecutor(max_workers=min(4, len(disks))) as pool:
        return dict(zip(disks, pool.map(system.smart, disks)))


def survey(smart: bool = True) -> dict[str, Any]:
    """Everything diskutil says, once: sets, volumes, usage, loose members."""
    m = config.load()
    sets = diskutil.raid_sets()
    disks = diskutil.external_disks()
    vols = {name: diskutil.volume(t.mount) for name, t in m.storage.tiers.items()}
    member_disks = sorted({mem.disk for s in sets for mem in s.members})
    return {
        "manifest": m,
        "sets": sets,
        "disks": disks,
        "volumes": vols,
        "usage": {n: diskutil.usage(v) for n, v in vols.items() if v is not None},
        "orphans": diskutil.orphan_members(sets, disks),
        "unreadable": diskutil.unreadable_disks(disks),
        "smart": _smart(member_disks) if smart else {},
    }


def _smart_view(s: Optional[system.Smart]) -> Optional[dict[str, Any]]:
    if s is None:
        return None
    if not s.supported:
        return {"supported": False}
    return {
        "passed": s.passed,
        "temperature_c": s.temperature_c,
        "power_on_hours": s.power_on_hours,
        "wear_pct": s.percentage_used,
        "media_errors": s.media_errors,
    }


def tier_report(name: str, sv: dict[str, Any]) -> tuple[dict[str, Any], list[dict]]:
    m: config.Manifest = sv["manifest"]
    tier = m.storage.tiers[name]
    vol = sv["volumes"][name]
    rset = _set_for(name, vol, sv["sets"])
    required = name in required_tiers(m)
    checks: list[dict] = []
    view: dict[str, Any] = {
        "mount": tier.mount,
        "mounted": vol is not None,
        "use": tier.use,
        "required": required,
    }
    if vol is None:
        status = "fail" if required else "warn"
        why = "needed by services" if required else "the archive"
        checks.append(
            R.check(
                f"storage.{name}.mounted",
                status,
                f"{name} is not mounted ({why})",
                name,
            )
        )
    else:
        view["device"] = vol.device
        checks.append(
            R.check(
                f"storage.{name}.mounted",
                "ok",
                f"{name} mounted from {vol.device}",
                name,
            )
        )
        u = sv["usage"][name]
        view["usage"] = {
            "total_gb": round(u.total / GB),
            "free_gb": round(u.free / GB),
            "used_pct": u.used_pct,
            "warn_pct": tier.warn_pct,
            "crit_pct": tier.crit_pct,
        }
        level = (
            "fail"
            if u.used_pct >= tier.crit_pct
            else "warn"
            if u.used_pct >= tier.warn_pct
            else "ok"
        )
        checks.append(
            R.check(
                f"storage.{name}.usage",
                level,
                f"{name} {u.used_pct:g}% used ({round(u.free / GB)} GB free)",
                name,
            )
        )
    if rset is None:
        if tier.raid != "none":
            status = "warn" if vol is not None or not required else "fail"
            msg = (
                f"{name} is mounted but not from a RAID set"
                if vol is not None
                else f"no RAID set named {name} is assembled"
            )
            checks.append(R.check(f"storage.{name}.raid", status, msg, name))
        view["raid"] = None
    else:
        members = []
        for mem in rset.members:
            smart = _smart_view(sv["smart"].get(mem.disk))
            members.append(
                {"device": mem.device, "status": mem.status, "smart": smart}
                | ({"rebuild": mem.progress} if mem.progress else {})
            )
            if smart and smart.get("passed") is False:
                checks.append(
                    R.check(
                        f"storage.{name}.smart.{mem.disk}",
                        "fail",
                        f"{mem.disk} ({name}) fails its SMART health check",
                        name,
                    )
                )
            elif smart and smart.get("media_errors"):
                checks.append(
                    R.check(
                        f"storage.{name}.smart.{mem.disk}",
                        "warn",
                        f"{mem.disk} ({name}) reports {smart['media_errors']} "
                        "media errors",
                        name,
                    )
                )
        view["raid"] = {
            "set": rset.name,
            "device": rset.device,
            "status": rset.status,
            "level": rset.level,
            "members": members,
        }
        rebuilding = [m_ for m_ in rset.members if m_.status == "Rebuilding"]
        bad = [m_ for m_ in rset.members if m_.status not in ("Online", "Rebuilding")]
        if rset.healthy:
            status, msg = "ok", f"{name} RAID {rset.status}, {len(members)} members"
        elif rebuilding and not bad:
            progress = rebuilding[0].progress or "in progress"
            status, msg = "warn", f"{name} RAID rebuilding ({progress})"
        else:
            detail = ", ".join(f"{x.device} {x.status}" for x in bad) or rset.status
            status, msg = "fail", f"{name} RAID {rset.status}: {detail}"
        checks.append(R.check(f"storage.{name}.raid", status, msg, name))
    return view, checks


def loose_checks(sv: dict[str, Any]) -> list[dict]:
    """Disks that belong to no assembled set: often a missing tier's halves."""
    checks = []
    for p in sv["orphans"]:
        checks.append(
            R.check(
                f"storage.orphan.{p.device}",
                "warn",
                f"{p.device} is a RAID member no assembled set claims",
                "storage",
            )
        )
    for d in sv["unreadable"]:
        checks.append(
            R.check(
                f"storage.unreadable.{d.device}",
                "warn",
                f"{d.device} has no readable partition map",
                "storage",
            )
        )
    return checks


def status(tier: str = "all", verbose: bool = False, smart: bool = True) -> dict:
    try:
        sv = survey(smart=smart)
    except diskutil.DiskutilError as err:
        return R.error(f"diskutil failed: {err}", ["health_check(component='raid')"])
    m: config.Manifest = sv["manifest"]
    names = list(m.storage.tiers) if tier == "all" else [tier]
    if any(n not in m.storage.tiers for n in names):
        return R.error(
            f"unknown tier {tier!r}; use one of all, {', '.join(m.storage.tiers)}"
        )
    tiers, checks, hints = {}, [], []
    for name in names:
        view, tier_checks = tier_report(name, sv)
        tiers[name] = view
        checks += tier_checks
        if any(c["status"] == "fail" for c in tier_checks):
            hints.append(f"storage_plan_recovery(tier='{name}')")
    # Loose disks belong to no tier we can name: show them for the whole box, or
    # for a tier that's missing (they may be its halves), not for a healthy one.
    missing = any(not tiers[n]["mounted"] or not tiers[n]["raid"] for n in names)
    loose = loose_checks(sv) if tier == "all" or missing else []
    checks += loose
    data: dict[str, Any] = {"tiers": tiers}
    if loose:
        data["loose"] = {
            "orphan_members": [p.device for p in sv["orphans"]],
            "unreadable_disks": [d.device for d in sv["unreadable"]],
        }
    mounted = sum(1 for t in tiers.values() if t["mounted"])
    return R.make(
        checks,
        data,
        ok_summary=f"All {len(tiers)} tiers mounted and healthy"
        if mounted == len(tiers)
        else f"{mounted} of {len(tiers)} tiers mounted",
        hints=hints,
        verbose=verbose,
    )


# --- recovery plans (read-only) ------------------------------------------------

NEVER = [
    "diskutil eraseDisk / eraseVolume / partitionDisk on any member or candidate disk",
    "diskutil appleRAID delete on the set",
    "First Aid repairs or initializing a disk that holds the only copy of its data",
]


def _step(command: str, effect: str, why: str) -> dict[str, str]:
    return {"command": command, "effect": effect, "why": why}


def plan_recovery(tier: str) -> dict:
    """What a person should check and do for a missing or degraded tier."""
    try:
        sv = survey(smart=True)
    except diskutil.DiskutilError as err:
        return R.error(f"diskutil failed: {err}")
    m: config.Manifest = sv["manifest"]
    if tier not in m.storage.tiers:
        return R.error(
            f"unknown tier {tier!r}; use one of {', '.join(m.storage.tiers)}"
        )
    view, tier_checks = tier_report(tier, sv)
    vol = sv["volumes"][tier]
    rset = _set_for(tier, vol, sv["sets"])
    diagnosis: list[str] = []
    steps: list[dict[str, str]] = [
        _step(
            "diskutil appleRAID list",
            "read-only",
            "see every set, its status and its members as macOS sees them now",
        ),
        _step("diskutil list external", "read-only", "see every attached disk"),
    ]

    archive = "coldstore" if "coldstore" in m.storage.tiers else None
    backup_ok = archive is not None and archive != tier and sv["volumes"].get(archive)
    prechecks = [
        {
            "check": "an independent copy of the data is reachable",
            "status": "ok" if backup_ok else "warn",
            "detail": (
                f"{archive} is mounted: confirm it holds a current copy before "
                "anything that changes a disk"
                if backup_ok
                else "no backup tier is mounted (D23): make a copy of anything "
                "readable before changing any disk"
            ),
        }
    ]

    if vol is not None and (rset is None or rset.healthy):
        diagnosis.append(f"{tier} is mounted and its RAID set is healthy")
        return R.make(
            [],
            {"tier": tier, "diagnosis": diagnosis, "steps": [], "prechecks": prechecks},
            summary=f"{tier}: nothing to recover",
        )

    if rset is not None and any(x.status == "Rebuilding" for x in rset.members):
        diagnosis.append(f"the {rset.name} set ({rset.device}) is rebuilding")
        steps.append(
            _step(
                "diskutil appleRAID list",
                "read-only",
                "repeat to follow progress; leave the disks connected and powered",
            )
        )
        rebuild_needed = False
    elif rset is not None:
        bad = [x for x in rset.members if x.status != "Online"]
        good = [x for x in rset.members if x.status == "Online"]
        diagnosis.append(
            f"the {rset.name} set ({rset.device}) is {rset.status}: "
            + ", ".join(f"{x.device} {x.status}" for x in bad)
        )
        for x in bad:
            steps.append(
                _step(
                    f"smartctl -a /dev/{x.disk}",
                    "read-only",
                    f"is {x.disk} failing, or was it only disconnected?",
                )
            )
        rebuild_needed = bool(good) and rset.level.lower() == "mirror"
        if rebuild_needed:
            steps.append(
                _step(
                    f"diskutil appleRAID repairMirror {rset.device} <replacement disk>",
                    "data loss on the replacement disk",
                    "rebuild the mirror onto a disk you've checked holds nothing "
                    "you need; only after the pre-checks pass",
                )
            )
        if vol is None:
            steps.append(
                _step(
                    f"diskutil list {rset.device}",
                    "read-only",
                    "find the volume on the set, then: diskutil mount <volume>",
                )
            )
    else:
        rebuild_needed = False
        orphans = [p.device for p in sv["orphans"]]
        unreadable = [d.device for d in sv["unreadable"]]
        diagnosis.append(f"no RAID set named {tier} is assembled")
        if orphans:
            diagnosis.append(
                "RAID members no assembled set claims: " + ", ".join(orphans)
            )
        if unreadable:
            diagnosis.append(
                "disks without a readable partition map: " + ", ".join(unreadable)
            )
        if not orphans and not unreadable:
            diagnosis.append("no candidate disk is attached at all")
        steps += [
            _step(
                "(by hand) check each enclosure's power and cable, then reconnect it",
                "none",
                "a mirror with one healthy member normally assembles degraded; "
                "a set that doesn't appear usually means a member isn't seen",
            ),
            _step(
                "diskutil appleRAID list",
                "read-only",
                "after reconnecting: does the set assemble, even degraded?",
            ),
        ]
        for d in unreadable:
            steps.append(
                _step(
                    f"diskutil info {d}",
                    "read-only",
                    f"what macOS knows about {d}; don't repair or initialize it: "
                    "its data may be the only copy",
                )
            )
        steps.append(
            _step(
                "(stop) ask for help before anything that writes to a disk",
                "none",
                "recovering a set that won't assemble needs a person who can "
                "see the disks; no command here is safe to guess",
            )
        )
    return R.make(
        [c for c in tier_checks if c["status"] != "ok"],
        {
            "tier": tier,
            "diagnosis": diagnosis,
            "prechecks": prechecks,
            "rebuild_needed": rebuild_needed,
            "steps": [dict(n=i + 1, **s) for i, s in enumerate(steps)],
            "never": NEVER,
            "note": "This tool only plans: a person runs these commands. "
            "Nothing here changes a disk.",
        },
        summary=f"{tier}: " + "; ".join(diagnosis)[:180],
        status="warn" if vol is not None else "fail",
    )
