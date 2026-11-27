-- Phase 3: long-running jobs (docs/mcp-refactor/05, "Long-running jobs").
-- Each job runs under its own supervisor process (python3 -m homelab job-run),
-- detached from the MCP server, so it survives a server restart.

CREATE TABLE jobs (
  id TEXT PRIMARY KEY,                    -- j-20261127-101500-ab12
  kind TEXT NOT NULL,                     -- media_process, logs_collect …
  tool TEXT,                              -- the tool call that started it
  args TEXT,                              -- JSON, redacted: the tool's arguments
  argv TEXT NOT NULL,                     -- JSON list, checked by homelab.exec again before it runs
  lock TEXT,                              -- one job at a time per lock (config/policy.yaml)
  state TEXT NOT NULL CHECK (state IN ('queued', 'running', 'done', 'failed', 'cancelled', 'lost')),
  requested_by TEXT,                      -- token name, or cli
  created_at TEXT NOT NULL,
  started_at TEXT,
  ended_at TEXT,
  timeout_s INTEGER NOT NULL,
  pid INTEGER,                            -- the supervisor
  exit_code INTEGER,
  progress REAL,                          -- 0-100, from "::progress N" lines
  stage TEXT,                             -- from "::stage NAME" lines
  log_path TEXT NOT NULL,
  result TEXT,                            -- JSON from a "::result {…}" line, if any
  error TEXT
);
CREATE INDEX jobs_state ON jobs (state, created_at);
