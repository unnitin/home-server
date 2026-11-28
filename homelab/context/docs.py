"""The repo's operational docs as runbooks: split by `##` heading, searchable.

An in-memory SQLite FTS5 index, built on first use and rebuilt when a doc
changes (by mtime). No embeddings, so nothing depends on a model provider,
and full-text search is plenty for about twenty docs (04).
"""

from __future__ import annotations

import re
import sqlite3
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from homelab import config

SOURCES = ["docs/*.md", "diagnostics/README.md"]
SKIP = {"FUTURE-EXTENSIONS.md", "CLEANUP.md"}  # plans and history, not runbooks
MAX_SECTION = 6000


@dataclass(frozen=True)
class Section:
    topic: str  # doc/section-slug
    doc: str
    title: str
    text: str


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def doc_name(path: Path) -> str:
    return "diagnostics" if path.parent.name == "diagnostics" else slug(path.stem)


def files() -> list[Path]:
    out: list[Path] = []
    for pattern in SOURCES:
        out += [p for p in sorted(config.REPO.glob(pattern)) if p.name not in SKIP]
    return out


def split(path: Path) -> list[Section]:
    doc = doc_name(path)
    text = path.read_text(encoding="utf-8", errors="replace")
    parts = re.split(r"^## +", text, flags=re.M)
    head = parts[0].strip()
    out = []
    if head:
        title = head.splitlines()[0].lstrip("# ").strip() or doc
        out.append(Section(f"{doc}/intro", doc, title, head[:MAX_SECTION]))
    seen: set[str] = set()
    for part in parts[1:]:
        title, _, body = part.partition("\n")
        title = re.sub(r"[*_`]", "", title).strip()
        key = slug(title) or "section"
        while key in seen:
            key += "-2"
        seen.add(key)
        out.append(
            Section(f"{doc}/{key}", doc, title, f"## {part.strip()}"[:MAX_SECTION])
        )
    return out


class Index:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._mtimes: dict[Path, float] = {}
        self._sections: dict[str, Section] = {}
        self._db: Optional[sqlite3.Connection] = None

    def _current(self) -> dict[Path, float]:
        return {p: p.stat().st_mtime for p in files()}

    def _build(self) -> None:
        mtimes = self._current()
        if self._db is not None and mtimes == self._mtimes:
            return
        db = sqlite3.connect(":memory:", check_same_thread=False)
        db.execute("CREATE VIRTUAL TABLE docs USING fts5 (topic, title, text)")
        sections: dict[str, Section] = {}
        for path in mtimes:
            for s in split(path):
                sections[s.topic] = s
                db.execute(
                    "INSERT INTO docs VALUES (?, ?, ?)", (s.topic, s.title, s.text)
                )
        self._db, self._sections, self._mtimes = db, sections, mtimes

    def sections(self) -> dict[str, Section]:
        with self._lock:
            self._build()
            return dict(self._sections)

    def search(self, query: str, limit: int = 5) -> list[dict[str, str]]:
        words = re.findall(r"[A-Za-z0-9]+", query.lower())
        if not words:
            return []
        q = " OR ".join(f'"{w}"' for w in words[:12])
        with self._lock:
            self._build()
            assert self._db is not None
            rows = self._db.execute(
                "SELECT topic, title, snippet(docs, 2, '[', ']', '…', 24) "
                "FROM docs WHERE docs MATCH ? "
                "ORDER BY bm25(docs, 1.0, 4.0, 1.0) LIMIT ?",
                (q, max(1, min(limit, 20))),
            ).fetchall()
        return [
            {"topic": t, "title": title, "snippet": snip} for t, title, snip in rows
        ]


INDEX = Index()
