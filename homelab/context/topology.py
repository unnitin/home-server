"""The topology as text, from the manifest: services, ports, tiers, tailnet."""

from __future__ import annotations

from homelab import config


def text(m: config.Manifest | None = None) -> str:
    m = m or config.load()
    tailnet = {mp.service: mp.https for mp in m.remote_access.tailscale_serve}
    lines = ["# Topology (from config/homelab.yaml)", "", "## Storage tiers"]
    for name, t in m.storage.tiers.items():
        lines.append(f"- {name}: {t.mount} ({t.media}, {t.raid}) — {t.use}")
    lines += ["", "## Services, in boot order"]
    for name in m.boot_order:
        s = m.services[name]
        bits = [s.kind, s.launchd]
        if s.ports:
            bits.append("port " + ", ".join(map(str, s.ports)))
        if s.listen:
            bits.append(f"listens {s.listen}")
        if name in tailnet:
            bits.append(f"tailnet :{tailnet[name]}")
        if s.depends_on:
            bits.append("needs " + ", ".join(s.depends_on))
        if s.optional:
            bits.append("optional")
        lines.append(f"- {name}: " + "; ".join(bits))
    media_root = m.storage.tiers[m.media.tier].mount
    lines += ["", "## Media", f"- libraries on {m.media.tier}:"]
    for lib, cfg in m.media.libraries.items():
        lines.append(
            f"  - {lib}: {media_root}/{cfg.dir} "
            f"(staging {media_root}/{m.media.staging}/{cfg.staging})"
        )
    lines.append(f"- failed files: {media_root}/{m.media.failed}/<date>/")
    photos = m.storage.tiers[m.photos.tier].mount
    lines += ["", "## Photos", f"- Immich library: {photos}/{m.photos.library}"]
    return "\n".join(lines)
