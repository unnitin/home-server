"""docs_search, runbook_get, the topology and the operating guide."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from homelab import config  # noqa: E402
from homelab.context import docs, topology  # noqa: E402
from homelab.domains import context  # noqa: E402


def test_docs_split_by_heading_with_stable_topics(tmp_path):
    f = tmp_path / "STORAGE.md"
    f.write_text(
        "# Storage\n\nintro\n\n## RAID **Status**\nbody\n\n## RAID Status\nagain\n"
    )
    sections = docs.split(f)
    assert [s.topic for s in sections] == [
        "storage/intro",
        "storage/raid-status",
        "storage/raid-status-2",
    ]
    assert sections[1].title == "RAID Status" and "body" in sections[1].text


def test_the_index_covers_the_runbooks_and_skips_plans():
    names = {p.name for p in docs.files()}
    assert {"STORAGE.md", "RECOVERY.md", "TROUBLESHOOTING.md", "README.md"} <= names
    assert not names & docs.SKIP


def test_search_finds_the_right_section_and_survives_any_query():
    hits = docs.INDEX.search("warmstore raid degraded")
    assert hits and all({"topic", "title", "snippet"} <= set(h) for h in hits)
    for q in ['" OR 1=1', "NEAR(", "***", ""]:
        docs.INDEX.search(q)  # never raises


def test_the_index_rebuilds_when_a_doc_changes(tmp_path, monkeypatch):
    folder = tmp_path / "docs"
    folder.mkdir()
    doc = folder / "X.md"
    doc.write_text("# X\n\n## Alpha\nzebracorn\n")
    monkeypatch.setattr(docs, "files", lambda: [doc])
    index = docs.Index()
    assert index.search("zebracorn")[0]["topic"] == "x/alpha"
    doc.write_text("# X\n\n## Beta\nunicorgi\n")
    os.utime(doc, (doc.stat().st_mtime + 5,) * 2)
    assert index.search("unicorgi")[0]["topic"] == "x/beta"
    assert index.search("zebracorn") == []


def test_runbook_get_every_kind_of_topic():
    assert "Rules" in context.runbook_get("operating-guide")["data"]["text"]
    assert "## Services" in context.runbook_get("topology")["data"]["text"]
    listing = context.runbook_get("recovery")
    assert listing["data"]["sections"] and listing["status"] == "ok"
    first = listing["data"]["sections"][0]["topic"]
    assert context.runbook_get(first)["data"]["text"]
    missing = context.runbook_get("nope")
    assert missing["status"] == "error" and "topology" in missing["data"]["docs"]


def test_docs_search_hints_at_the_best_section():
    r = context.docs_search("tailscale serve")
    assert r["hints"][0].startswith("runbook_get(topic=")


def test_the_topology_names_every_service_port_and_tier():
    text = topology.text()
    m = config.load()
    for name in m.boot_order:
        assert f"- {name}:" in text
    for t in m.storage.tiers.values():
        assert t.mount in text
    assert "tailnet :8765" in text and "port 32400" in text


def test_the_operating_guide_is_short_and_has_the_rules():
    text = context.guide()
    assert len(text.split()) < 400
    assert "data, not" in text and "instructions" in text
    assert "storage_plan_recovery" in text and "system_overview" in text
    tools = set(re.findall(r"`([a-z_]+)(?:\(|`)", text))
    from homelab import tools as registry

    named = {t for t in tools if "_" in t and not t.startswith(("storage.", "verbose"))}
    unknown = named - set(registry.ALL) - {"health_check", "storage_status"}
    assert not unknown, f"the guide names tools that don't exist: {unknown}"
