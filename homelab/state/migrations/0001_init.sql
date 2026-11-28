-- Phase 2: history, incidents, memory, inventory (docs/mcp-refactor/04).
-- Governance (audit, plans, jobs) arrives with Phase 3, curation with Phase 6,
-- each in its own migration.

-- Health snapshots, written by io.homelab.snapshot every 15 minutes
CREATE TABLE snapshots (
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL,                       -- UTC, ISO 8601
  overall TEXT NOT NULL,                  -- ok | warn | fail | error
  payload TEXT NOT NULL                   -- JSON: what the snapshot saw
);
CREATE INDEX snapshots_ts ON snapshots (ts);

-- One number per metric per snapshot, for history_query
CREATE TABLE metrics (
  ts TEXT NOT NULL,
  metric TEXT NOT NULL,                   -- e.g. storage.warmstore.used_pct
  value REAL NOT NULL,
  PRIMARY KEY (metric, ts)
);

-- Incidents: opened and resolved by the snapshot job, or by a person or agent
CREATE TABLE incidents (
  id INTEGER PRIMARY KEY,
  key TEXT,                               -- the check id that opened it, if any
  opened_ts TEXT NOT NULL,
  closed_ts TEXT,
  component TEXT NOT NULL,
  severity TEXT NOT NULL CHECK (severity IN ('fail', 'warn')),
  title TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('open', 'monitoring', 'resolved')),
  root_cause TEXT,
  resolution TEXT
);
CREATE INDEX incidents_open ON incidents (status, key);

CREATE TABLE incident_events (
  incident_id INTEGER NOT NULL REFERENCES incidents (id),
  ts TEXT NOT NULL,
  actor TEXT NOT NULL,                    -- snapshot | cli | mcp
  kind TEXT NOT NULL CHECK (kind IN ('observation', 'action', 'hypothesis', 'note')),
  body TEXT NOT NULL
);

-- Durable notes: facts, preferences, decisions, resolutions, todos
CREATE TABLE notes (
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL,
  actor TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('fact', 'preference', 'decision', 'resolution', 'todo')),
  component TEXT,
  body TEXT NOT NULL,
  tags TEXT,
  source_incident INTEGER,
  expires_ts TEXT,
  superseded_by INTEGER                   -- -1: forgotten
);
CREATE VIRTUAL TABLE notes_fts USING fts5 (body, tags, component, content='notes', content_rowid='id');
CREATE TRIGGER notes_ai AFTER INSERT ON notes BEGIN
  INSERT INTO notes_fts (rowid, body, tags, component) VALUES (new.id, new.body, new.tags, new.component);
END;
CREATE TRIGGER notes_ad AFTER DELETE ON notes BEGIN
  INSERT INTO notes_fts (notes_fts, rowid, body, tags, component) VALUES ('delete', old.id, old.body, old.tags, old.component);
END;
CREATE TRIGGER notes_au AFTER UPDATE OF body, tags, component ON notes BEGIN
  INSERT INTO notes_fts (notes_fts, rowid, body, tags, component) VALUES ('delete', old.id, old.body, old.tags, old.component);
  INSERT INTO notes_fts (rowid, body, tags, component) VALUES (new.id, new.body, new.tags, new.component);
END;

-- What the box is made of, and what versions ran when ("what changed?")
CREATE TABLE inventory (key TEXT PRIMARY KEY, value TEXT, updated_ts TEXT);
CREATE TABLE versions (component TEXT NOT NULL, version TEXT NOT NULL, ts TEXT NOT NULL, actor TEXT NOT NULL);
CREATE INDEX versions_component ON versions (component, ts);
