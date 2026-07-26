-- AI Digital Product Factory - SQLite schema
CREATE TABLE IF NOT EXISTS adpf_products (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id          TEXT NOT NULL UNIQUE,
  factory         TEXT,
  product_name    TEXT,
  category        TEXT,
  keywords        TEXT,
  marketplace     TEXT,
  drive_folder_id TEXT,
  etsy_listing_id TEXT,
  prompt_version  TEXT,
  status          TEXT NOT NULL DEFAULT 'running',
  error_log       TEXT,
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS adpf_products_status_idx   ON adpf_products (status);
CREATE INDEX IF NOT EXISTS adpf_products_category_idx ON adpf_products (category);
CREATE INDEX IF NOT EXISTS adpf_products_created_idx  ON adpf_products (created_at DESC);

CREATE TABLE IF NOT EXISTS adpf_events (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id     TEXT NOT NULL,
  op         TEXT NOT NULL,
  level      TEXT NOT NULL DEFAULT 'info',
  message    TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS adpf_events_run_idx ON adpf_events (run_id, created_at DESC);
