-- Phase 3: bearer tokens and the audit log (docs/mcp-refactor/05).

-- One token per client. Only a SHA-256 of the token is kept: the token itself
-- is shown once, when it's created (homelab token create).
CREATE TABLE tokens (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,              -- e.g. macbook-claude
  hash TEXT NOT NULL UNIQUE,              -- sha256 hex of the token
  scopes TEXT NOT NULL,                   -- comma-separated: observe, ops, admin, curator
  toolset TEXT,                           -- NULL: every tool the scopes allow
  created_at TEXT NOT NULL,
  expires_at TEXT,                        -- NULL: no expiry
  last_used_at TEXT,
  revoked_at TEXT
);

-- Every tools/call: who, what, and what came of it. Arguments are redacted.
CREATE TABLE audit (
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL,
  client TEXT NOT NULL,                   -- token name, or stdio / cli
  tailscale_user TEXT,                    -- Tailscale-User-Login: for the record, not auth
  model TEXT,                             -- X-Homelab-Model, when a harness sends it
  tool TEXT NOT NULL,
  tier TEXT,
  args TEXT,                              -- JSON, redacted and capped
  outcome TEXT NOT NULL,                  -- the result's status, or denied / rate_limited / error
  summary TEXT,
  duration_ms INTEGER,
  job_id TEXT,
  plan_id TEXT
);
CREATE INDEX audit_ts ON audit (ts);
CREATE INDEX audit_tool ON audit (tool, ts);
