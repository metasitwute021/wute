-- ==========================================================================
-- Planner Factory - schema
-- Run this whole file in the Supabase SQL editor. Safe to run again later.
-- ==========================================================================

-- One row per attempt to build a planner, successful or not.
CREATE TABLE IF NOT EXISTS planner_runs (
    id              BIGSERIAL PRIMARY KEY,
    run_id          TEXT        NOT NULL UNIQUE,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at     TIMESTAMPTZ,
    status          TEXT        NOT NULL DEFAULT 'running',
    stage           TEXT,
    niche           TEXT,
    product_name    TEXT,
    prompt_version  TEXT,
    dry_run         BOOLEAN     NOT NULL DEFAULT false,
    error_message   TEXT,
    CONSTRAINT planner_runs_status CHECK (
        status IN ('running', 'succeeded', 'failed', 'rejected'))
);

CREATE INDEX IF NOT EXISTS planner_runs_started_idx ON planner_runs (started_at DESC);
CREATE INDEX IF NOT EXISTS planner_runs_status_idx  ON planner_runs (status);

-- One row per finished planner. A run that fails QA never gets one.
CREATE TABLE IF NOT EXISTS planner_products (
    id              BIGSERIAL PRIMARY KEY,
    run_id          TEXT        NOT NULL REFERENCES planner_runs (run_id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    product_name    TEXT        NOT NULL,
    slug            TEXT        NOT NULL,
    niche           TEXT,
    search_phrase   TEXT,
    keywords        JSONB       NOT NULL DEFAULT '[]'::jsonb,
    page_count      INTEGER     NOT NULL,
    link_count      INTEGER     NOT NULL DEFAULT 0,
    pdf_bytes       BIGINT      NOT NULL,
    drive_file_id   TEXT,
    listing_title   TEXT,
    listing_tags    JSONB       NOT NULL DEFAULT '[]'::jsonb,
    price_usd       NUMERIC(8,2)
);

CREATE INDEX IF NOT EXISTS planner_products_run_idx  ON planner_products (run_id);
-- Two planners with the same slug are the same product; the factory checks
-- this before spending anything on images.
CREATE UNIQUE INDEX IF NOT EXISTS planner_products_slug_idx ON planner_products (slug);

-- One row per Etsy listing attempt.
CREATE TABLE IF NOT EXISTS planner_listings (
    id                BIGSERIAL PRIMARY KEY,
    run_id            TEXT        NOT NULL REFERENCES planner_runs (run_id),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    etsy_listing_id   BIGINT,
    state             TEXT,
    url               TEXT,
    images_uploaded   INTEGER     NOT NULL DEFAULT 0,
    file_uploaded     BOOLEAN     NOT NULL DEFAULT false,
    error_message     TEXT
);

CREATE INDEX IF NOT EXISTS planner_listings_run_idx ON planner_listings (run_id);

-- What each run cost, so the bill is a number rather than a surprise.
CREATE TABLE IF NOT EXISTS planner_costs (
    id            BIGSERIAL PRIMARY KEY,
    run_id        TEXT        NOT NULL REFERENCES planner_runs (run_id),
    recorded_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    kind          TEXT        NOT NULL,
    detail        TEXT,
    units         INTEGER     NOT NULL DEFAULT 1,
    usd           NUMERIC(10,4) NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS planner_costs_run_idx ON planner_costs (run_id);
