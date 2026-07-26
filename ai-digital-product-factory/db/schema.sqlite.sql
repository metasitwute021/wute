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

-- V2 tables for SQLite. The V2 workflows (07-10) target PostgreSQL; this schema
-- exists so a SQLite deployment can still record ideas, costs and QA results.
CREATE TABLE IF NOT EXISTS adpf_ideas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  idea_uid TEXT NOT NULL UNIQUE, run_id TEXT NOT NULL, batch_id TEXT,
  title TEXT NOT NULL, title_norm TEXT NOT NULL, category TEXT NOT NULL,
  factory TEXT NOT NULL, target_customer TEXT, keywords TEXT,
  demand_score REAL DEFAULT 0, competition_score REAL DEFAULT 0,
  trend_score REAL DEFAULT 0, seo_score REAL DEFAULT 0, profit_score REAL DEFAULT 0,
  difficulty_score REAL DEFAULT 0, evergreen_score REAL DEFAULT 0,
  diversity_score REAL DEFAULT 0, saturation_penalty REAL DEFAULT 0,
  est_price_usd REAL, est_api_cost_usd REAL, est_profit_usd REAL, est_margin_pct REAL,
  difficulty TEXT, lifecycle TEXT,
  idea_score REAL DEFAULT 0, final_score REAL DEFAULT 0, rank_in_batch INTEGER,
  stage TEXT NOT NULL DEFAULT 'generated', rejected_reason TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS adpf_costs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL, stage TEXT, provider TEXT NOT NULL DEFAULT 'openai',
  model TEXT, kind TEXT NOT NULL, calls INTEGER DEFAULT 1,
  input_units INTEGER DEFAULT 0, output_units INTEGER DEFAULT 0,
  cost_usd REAL NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS adpf_budget (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  scope TEXT NOT NULL, period_key TEXT NOT NULL,
  limit_usd REAL NOT NULL, spent_usd REAL NOT NULL DEFAULT 0,
  runs INTEGER NOT NULL DEFAULT 0, blocked INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (scope, period_key)
);

CREATE TABLE IF NOT EXISTS adpf_qa_results (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL, stage TEXT NOT NULL, stage_no INTEGER NOT NULL,
  passed INTEGER NOT NULL, score REAL, blockers TEXT, warnings TEXT,
  checked_by TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS adpf_sales (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  marketplace TEXT NOT NULL, listing_id TEXT NOT NULL, run_id TEXT,
  product_name TEXT, category TEXT,
  views INTEGER DEFAULT 0, clicks INTEGER DEFAULT 0, favorites INTEGER DEFAULT 0,
  sales INTEGER DEFAULT 0, revenue_usd REAL DEFAULT 0, conversion_rate REAL,
  collected_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (marketplace, listing_id, collected_at)
);
