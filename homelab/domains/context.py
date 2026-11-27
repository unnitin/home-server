"""docs_search and runbook_get: the docs, the topology and the operating guide."""

from __future__ import annotations

from homelab import config
from homelab import result as R
from homelab.context import docs, topology

GUIDE = config.REPO / "homelab_mcp" / "instructions.md"


def guide() -> str:
    return GUIDE.read_text(encoding="utf-8")


def docs_search(query: str, limit: int = 5) -> dict:
    hits = docs.INDEX.search(query, limit)
    return R.make(
        [],
        {"query": query, "hits": hits},
        summary=f"{len(hits)} doc sections for {query!r}"
        + (f"; best: {hits[0]['topic']}" if hits else ""),
        hints=[f"runbook_get(topic='{hits[0]['topic']}')"] if hits else [],
    )


def runbook_get(topic: str) -> dict:
    if topic == "operating-guide":
        return R.make(
            [], {"topic": topic, "text": guide()}, summary="The operating guide"
        )
    if topic == "topology":
        return R.make(
            [], {"topic": topic, "text": topology.text()}, summary="The topology"
        )
    sections = docs.INDEX.sections()
    if topic in sections:
        s = sections[topic]
        return R.make(
            [], {"topic": topic, "title": s.title, "text": s.text}, summary=s.title
        )
    in_doc = [
        {"topic": s.topic, "title": s.title}
        for s in sections.values()
        if s.doc == topic
    ]
    if in_doc:
        return R.make(
            [],
            {"doc": topic, "sections": in_doc},
            summary=f"{topic}: {len(in_doc)} sections; ask for one by its topic",
        )
    names = sorted({s.doc for s in sections.values()})
    return R.error(
        f"no runbook {topic!r}",
        hints=["docs_search(query=...) finds the right section"],
        data={"docs": ["operating-guide", "topology", *names]},
    )
