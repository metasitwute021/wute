"""V2 database schema - idea pool, cost/budget, learning, A/B testing, QA.

PostgreSQL is required for the V2 modules (07-10): they use window functions,
CTEs and JSONB. Workflows 01-06 still run on SQLite if that is all you have.

Design notes
------------
* Every score is stored, not just the final one, so a decision can be replayed
  and audited months later.
* ``adpf_costs.provider`` is deliberately generic. Only ``openai`` is ever
  written by these workflows (the project is OpenAI-only by requirement); the
  column exists so a future provider does not need a migration.
* Similarity/duplicate detection stores hashes and token sets rather than the
  full text, which keeps the table small and the comparison cheap.
"""

DDL_V2_POSTGRES = """
-- ---------------------------------------------------------------------------
-- 1-6  Idea pool: generation, scoring, inventory, diversity, selection
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS adpf_ideas (
  id                 BIGSERIAL PRIMARY KEY,
  idea_uid           TEXT        NOT NULL UNIQUE,
  run_id             TEXT        NOT NULL,
  batch_id           TEXT,
  title              TEXT        NOT NULL,
  title_norm         TEXT        NOT NULL,
  category           TEXT        NOT NULL,
  factory            TEXT        NOT NULL,
  target_customer    TEXT,
  keywords           TEXT,
  -- raw signals (0-100 each)
  demand_score       NUMERIC(5,2) NOT NULL DEFAULT 0,
  competition_score  NUMERIC(5,2) NOT NULL DEFAULT 0,
  trend_score        NUMERIC(5,2) NOT NULL DEFAULT 0,
  seo_score          NUMERIC(5,2) NOT NULL DEFAULT 0,
  profit_score       NUMERIC(5,2) NOT NULL DEFAULT 0,
  difficulty_score   NUMERIC(5,2) NOT NULL DEFAULT 0,
  evergreen_score    NUMERIC(5,2) NOT NULL DEFAULT 0,
  -- portfolio adjustments
  diversity_score    NUMERIC(5,2) NOT NULL DEFAULT 0,
  saturation_penalty NUMERIC(5,2) NOT NULL DEFAULT 0,
  -- economics
  est_price_usd      NUMERIC(8,2),
  est_api_cost_usd   NUMERIC(8,4),
  est_profit_usd     NUMERIC(8,2),
  est_margin_pct     NUMERIC(5,2),
  difficulty         TEXT,
  lifecycle          TEXT,        -- evergreen | seasonal
  -- results
  idea_score         NUMERIC(5,2) NOT NULL DEFAULT 0,
  final_score        NUMERIC(5,2) NOT NULL DEFAULT 0,
  rank_in_batch      INTEGER,
  stage              TEXT        NOT NULL DEFAULT 'generated',
                                 -- generated|top50|top20|top5|produced|rejected
  rejected_reason    TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS adpf_ideas_stage_idx    ON adpf_ideas (stage, final_score DESC);
CREATE INDEX IF NOT EXISTS adpf_ideas_category_idx ON adpf_ideas (category);
CREATE INDEX IF NOT EXISTS adpf_ideas_run_idx      ON adpf_ideas (run_id);
CREATE INDEX IF NOT EXISTS adpf_ideas_titlenorm_idx ON adpf_ideas (title_norm);

-- ---------------------------------------------------------------------------
-- 9  API cost tracker  (provider column is generic; only 'openai' is written)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS adpf_costs (
  id           BIGSERIAL PRIMARY KEY,
  run_id       TEXT        NOT NULL,
  stage        TEXT,                       -- research|idea|product|publish|learning
  provider     TEXT        NOT NULL DEFAULT 'openai',
  model        TEXT,
  kind         TEXT        NOT NULL,       -- chat | image | embedding | other
  calls        INTEGER     NOT NULL DEFAULT 1,
  input_units  BIGINT      NOT NULL DEFAULT 0,   -- prompt tokens / images
  output_units BIGINT      NOT NULL DEFAULT 0,   -- completion tokens
  cost_usd     NUMERIC(10,6) NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS adpf_costs_run_idx  ON adpf_costs (run_id);
CREATE INDEX IF NOT EXISTS adpf_costs_date_idx ON adpf_costs (created_at DESC);

-- ---------------------------------------------------------------------------
-- 10  Budget manager
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS adpf_budget (
  id          BIGSERIAL PRIMARY KEY,
  scope       TEXT        NOT NULL,        -- daily | monthly
  period_key  TEXT        NOT NULL,        -- 2026-07-26 | 2026-07
  limit_usd   NUMERIC(10,2) NOT NULL,
  spent_usd   NUMERIC(10,4) NOT NULL DEFAULT 0,
  runs        INTEGER     NOT NULL DEFAULT 0,
  blocked     BOOLEAN     NOT NULL DEFAULT false,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT adpf_budget_period_key UNIQUE (scope, period_key)
);

-- ---------------------------------------------------------------------------
-- 8   ROI  (kept beside the product row so a single query answers "did it pay")
-- 11  Factory priority
-- 12  Product versioning
-- 13  Duplicate detection hashes
-- ---------------------------------------------------------------------------
ALTER TABLE adpf_products ADD COLUMN IF NOT EXISTS idea_uid        TEXT;
ALTER TABLE adpf_products ADD COLUMN IF NOT EXISTS version         INTEGER NOT NULL DEFAULT 1;
ALTER TABLE adpf_products ADD COLUMN IF NOT EXISTS priority        INTEGER NOT NULL DEFAULT 3;
ALTER TABLE adpf_products ADD COLUMN IF NOT EXISTS title_norm      TEXT;
ALTER TABLE adpf_products ADD COLUMN IF NOT EXISTS content_hash    TEXT;
ALTER TABLE adpf_products ADD COLUMN IF NOT EXISTS keyword_set     TEXT;
ALTER TABLE adpf_products ADD COLUMN IF NOT EXISTS api_cost_usd    NUMERIC(10,4) DEFAULT 0;
ALTER TABLE adpf_products ADD COLUMN IF NOT EXISTS price_usd       NUMERIC(8,2);
ALTER TABLE adpf_products ADD COLUMN IF NOT EXISTS revenue_usd     NUMERIC(10,2) DEFAULT 0;
ALTER TABLE adpf_products ADD COLUMN IF NOT EXISTS profit_usd      NUMERIC(10,2) DEFAULT 0;
ALTER TABLE adpf_products ADD COLUMN IF NOT EXISTS margin_pct      NUMERIC(6,2);
ALTER TABLE adpf_products ADD COLUMN IF NOT EXISTS roi_pct         NUMERIC(8,2);
ALTER TABLE adpf_products ADD COLUMN IF NOT EXISTS revision_date   TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS adpf_products_titlenorm_idx ON adpf_products (title_norm);
CREATE INDEX IF NOT EXISTS adpf_products_hash_idx      ON adpf_products (content_hash);

CREATE TABLE IF NOT EXISTS adpf_product_versions (
  id             BIGSERIAL PRIMARY KEY,
  run_id         TEXT        NOT NULL,
  product_name   TEXT,
  version        INTEGER     NOT NULL,
  prompt_version TEXT,
  change_note    TEXT,
  qa_score       NUMERIC(5,2),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS adpf_product_versions_run_idx ON adpf_product_versions (run_id, version);

-- ---------------------------------------------------------------------------
-- 7   Multi-stage QA results
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS adpf_qa_results (
  id         BIGSERIAL PRIMARY KEY,
  run_id     TEXT        NOT NULL,
  stage      TEXT        NOT NULL,   -- research|idea|design|content|export|marketplace
  stage_no   INTEGER     NOT NULL,
  passed     BOOLEAN     NOT NULL,
  score      NUMERIC(5,2),
  blockers   TEXT,
  warnings   TEXT,
  checked_by TEXT,                   -- code | openai
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS adpf_qa_run_idx ON adpf_qa_results (run_id, stage_no);

-- ---------------------------------------------------------------------------
-- 15  Prompt evolution
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS adpf_prompt_versions (
  id             BIGSERIAL PRIMARY KEY,
  prompt_version TEXT        NOT NULL,
  agent          TEXT        NOT NULL,
  body_hash      TEXT,
  runs           INTEGER     NOT NULL DEFAULT 0,
  successes      INTEGER     NOT NULL DEFAULT 0,
  qa_score_sum   NUMERIC(12,2) NOT NULL DEFAULT 0,
  sales_sum      INTEGER     NOT NULL DEFAULT 0,
  revenue_usd    NUMERIC(12,2) NOT NULL DEFAULT 0,
  success_rate   NUMERIC(5,2),
  avg_qa_score   NUMERIC(5,2),
  avg_sales      NUMERIC(8,2),
  active         BOOLEAN     NOT NULL DEFAULT true,
  notes          TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT adpf_prompt_versions_key UNIQUE (prompt_version, agent)
);

-- ---------------------------------------------------------------------------
-- 16  Trend memory
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS adpf_trends (
  id           BIGSERIAL PRIMARY KEY,
  keyword      TEXT        NOT NULL,
  category     TEXT,
  period_type  TEXT        NOT NULL,   -- monthly | seasonal | evergreen | declining
  period_key   TEXT        NOT NULL,   -- 2026-07 | Q3 | all
  demand_score NUMERIC(5,2),
  trend_score  NUMERIC(5,2),
  competitors  INTEGER,
  median_price NUMERIC(8,2),
  sales        INTEGER     NOT NULL DEFAULT 0,
  observed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT adpf_trends_key UNIQUE (keyword, period_type, period_key)
);

CREATE INDEX IF NOT EXISTS adpf_trends_keyword_idx ON adpf_trends (keyword, observed_at DESC);

-- ---------------------------------------------------------------------------
-- 17 + 22  Sales learning, per marketplace
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS adpf_sales (
  id              BIGSERIAL PRIMARY KEY,
  marketplace     TEXT        NOT NULL,   -- etsy|gumroad|creative_market|shopify|...
  listing_id      TEXT        NOT NULL,
  run_id          TEXT,
  product_name    TEXT,
  category        TEXT,
  views           INTEGER     NOT NULL DEFAULT 0,
  clicks          INTEGER     NOT NULL DEFAULT 0,
  favorites       INTEGER     NOT NULL DEFAULT 0,
  sales           INTEGER     NOT NULL DEFAULT 0,
  revenue_usd     NUMERIC(10,2) NOT NULL DEFAULT 0,
  conversion_rate NUMERIC(6,3),
  collected_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT adpf_sales_key UNIQUE (marketplace, listing_id, collected_at)
);

CREATE INDEX IF NOT EXISTS adpf_sales_listing_idx ON adpf_sales (marketplace, listing_id);
CREATE INDEX IF NOT EXISTS adpf_sales_run_idx     ON adpf_sales (run_id);

-- ---------------------------------------------------------------------------
-- 21  A/B testing engine
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS adpf_ab_tests (
  id            BIGSERIAL PRIMARY KEY,
  test_uid      TEXT        NOT NULL,
  run_id        TEXT,
  marketplace   TEXT        NOT NULL DEFAULT 'etsy',
  listing_id    TEXT,
  element       TEXT        NOT NULL,   -- title|thumbnail|description|price|tags
  variant       TEXT        NOT NULL,   -- A | B
  variant_value TEXT,
  views         INTEGER     NOT NULL DEFAULT 0,
  favorites     INTEGER     NOT NULL DEFAULT 0,
  sales         INTEGER     NOT NULL DEFAULT 0,
  revenue_usd   NUMERIC(10,2) NOT NULL DEFAULT 0,
  status        TEXT        NOT NULL DEFAULT 'running',  -- running|won|lost|stopped
  started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at      TIMESTAMPTZ,
  CONSTRAINT adpf_ab_key UNIQUE (test_uid, variant)
);

CREATE INDEX IF NOT EXISTS adpf_ab_status_idx ON adpf_ab_tests (status, element);

-- ---------------------------------------------------------------------------
-- 18  Category balancer targets
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS adpf_category_targets (
  category    TEXT PRIMARY KEY,
  factory     TEXT,
  target_pct  NUMERIC(5,2) NOT NULL,
  priority    INTEGER     NOT NULL DEFAULT 3,   -- 5 = highest (section 11)
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO adpf_category_targets (category, factory, target_pct, priority) VALUES
  ('Planner',     'planner',     35, 5),
  ('Printable',   'printable',   30, 5),
  ('Teacher',     'kids',        15, 4),
  ('Wall Art',    'wallart',     10, 3),
  ('Spreadsheet', 'spreadsheet',  5, 3),
  ('Resume',      'resume',       5, 3)
ON CONFLICT (category) DO NOTHING;
""".strip()


DDL_V2_SQLITE = """
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
""".strip()
