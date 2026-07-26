"""06 Database Logger - one statement per operation, PostgreSQL or SQLite."""

import json

from common import (
    RETRY, T_CODE, T_EXEC_CMD, T_EXEC_TRIGGER, T_NOOP, T_POSTGRES, T_SWITCH,
    Workflow, code, pos, switch_equals,
)
from schema_v2 import DDL_V2_POSTGRES, DDL_V2_SQLITE

# --------------------------------------------------------------------------
# Schema. Also written to db/schema.postgres.sql and db/schema.sqlite.sql.
# --------------------------------------------------------------------------
DDL_POSTGRES = """
-- AI Digital Product Factory - PostgreSQL schema
CREATE TABLE IF NOT EXISTS adpf_products (
  id              BIGSERIAL PRIMARY KEY,
  run_id          TEXT        NOT NULL UNIQUE,
  factory         TEXT,
  product_name    TEXT,
  category        TEXT,
  keywords        TEXT,
  marketplace     TEXT,
  drive_folder_id TEXT,
  etsy_listing_id TEXT,
  prompt_version  TEXT,
  status          TEXT        NOT NULL DEFAULT 'running',
  error_log       TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS adpf_products_status_idx   ON adpf_products (status);
CREATE INDEX IF NOT EXISTS adpf_products_category_idx ON adpf_products (category);
CREATE INDEX IF NOT EXISTS adpf_products_created_idx  ON adpf_products (created_at DESC);

CREATE TABLE IF NOT EXISTS adpf_events (
  id         BIGSERIAL PRIMARY KEY,
  run_id     TEXT        NOT NULL,
  op         TEXT        NOT NULL,
  level      TEXT        NOT NULL DEFAULT 'info',
  message    TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS adpf_events_run_idx ON adpf_events (run_id, created_at DESC);
""".strip()

DDL_SQLITE = """
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
""".strip()

# One parameterised statement covers all four operations: upsert the product row
# (never clobbering a value with NULL) and append an event.
SQL_POSTGRES = """
WITH product AS (
  INSERT INTO adpf_products (
    run_id, factory, product_name, category, keywords, marketplace,
    drive_folder_id, etsy_listing_id, prompt_version, status, error_log
  )
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
  ON CONFLICT (run_id) DO UPDATE SET
    factory         = COALESCE(EXCLUDED.factory, adpf_products.factory),
    product_name    = COALESCE(EXCLUDED.product_name, adpf_products.product_name),
    category        = COALESCE(EXCLUDED.category, adpf_products.category),
    keywords        = COALESCE(NULLIF(EXCLUDED.keywords, ''), adpf_products.keywords),
    marketplace     = COALESCE(NULLIF(EXCLUDED.marketplace, ''), adpf_products.marketplace),
    drive_folder_id = COALESCE(EXCLUDED.drive_folder_id, adpf_products.drive_folder_id),
    etsy_listing_id = COALESCE(EXCLUDED.etsy_listing_id, adpf_products.etsy_listing_id),
    prompt_version  = COALESCE(EXCLUDED.prompt_version, adpf_products.prompt_version),
    status          = EXCLUDED.status,
    error_log       = COALESCE(EXCLUDED.error_log, adpf_products.error_log),
    updated_at      = now()
  RETURNING id
), event AS (
  INSERT INTO adpf_events (run_id, op, level, message)
  VALUES ($1, $12, $13, $14)
  RETURNING id
)
SELECT (SELECT id FROM product) AS product_id, (SELECT id FROM event) AS event_id;
""".strip()

SQL_QA_RESULT = """
-- Section 7: one row per QA stage, so a rejection can be traced to the stage
-- and the reason months later.
INSERT INTO adpf_qa_results (run_id, stage, stage_no, passed, score,
                             blockers, warnings, checked_by)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING id;
""".strip()

SQL_PRODUCT_VERSION = """
-- Section 12: append-only version history for a product.
INSERT INTO adpf_product_versions (run_id, product_name, version, prompt_version,
                                   change_note, qa_score)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING id;
""".strip()

JS_BUILD_SQL = (
    "const CORE_SQL = " + json.dumps(SQL_POSTGRES) + ";\n"
    "const QA_SQL = " + json.dumps(SQL_QA_RESULT) + ";\n"
    "const VERSION_SQL = " + json.dumps(SQL_PRODUCT_VERSION) + ";\n\n"
) + r"""
// Dispatcher: validate the record, then emit the statement and parameters for
// the requested operation. Both dialects are prepared up front; the DB_TYPE
// switch below decides which one actually runs.
const CORE_OPS = ['run_start', 'product_upsert', 'status_update', 'error_log'];
const V2_OPS = ['qa_result', 'product_version'];

const rec = $input.first().json || {};
const requested = String(rec.op || 'product_upsert');
const op = CORE_OPS.includes(requested) || V2_OPS.includes(requested)
  ? requested : 'product_upsert';

if (!rec.run_id) throw new Error('06 Database Logger requires a run_id');

const dbType = String($env.DB_TYPE || 'postgres').toLowerCase();

// --- SQLite has no parameter binding through the CLI, so escape by hand. ---
const q = (value) => {
  if (value === null || value === undefined) return 'NULL';
  if (typeof value === 'number') return String(value);
  if (typeof value === 'boolean') return value ? '1' : '0';
  return "'" + String(value)
    .replace(/'/g, "''")
    .replace(/\r/g, '')
    .replace(/^ADPFSQL$/gm, 'ADPF_SQL') + "'";
};

let pgSql = '';
let values = [];
let sqliteSql = '';

// -------------------------------------------------------------------------
// Section 7: multi-stage QA result
// -------------------------------------------------------------------------
if (op === 'qa_result') {
  const STAGE_NO = { research: 1, idea: 2, design: 3, content: 4, export: 5, marketplace: 6 };
  const stage = String(rec.stage || 'content').toLowerCase();
  values = [
    rec.run_id,
    stage,
    Number(rec.stage_no || STAGE_NO[stage] || 0),
    rec.passed === true,
    rec.score === undefined || rec.score === null ? null : Number(rec.score),
    Array.isArray(rec.blockers) ? rec.blockers.join(' | ') : (rec.blockers || null),
    Array.isArray(rec.warnings) ? rec.warnings.join(' | ') : (rec.warnings || null),
    rec.checked_by || 'code',
  ];
  pgSql = QA_SQL;
  sqliteSql = 'INSERT INTO adpf_qa_results (run_id, stage, stage_no, passed, score, blockers, warnings, checked_by) VALUES ('
    + values.map(q).join(', ') + ");\nSELECT 'ok' AS result;";

// -------------------------------------------------------------------------
// Section 12: product version history
// -------------------------------------------------------------------------
} else if (op === 'product_version') {
  values = [
    rec.run_id,
    rec.product_name || null,
    Number(rec.version || 1),
    rec.prompt_version || null,
    rec.change_note || null,
    rec.qa_score === undefined || rec.qa_score === null ? null : Number(rec.qa_score),
  ];
  pgSql = VERSION_SQL;
  // The V2 version table is PostgreSQL-only; on SQLite this degrades to an event.
  sqliteSql = "INSERT INTO adpf_events (run_id, op, level, message) VALUES ("
    + [rec.run_id, 'product_version', 'info',
       `version ${values[2]} of ${values[1]} (prompt ${values[3]})`].map(q).join(', ')
    + ");\nSELECT 'ok' AS result;";

// -------------------------------------------------------------------------
// Core ops: one universal upsert + event append
// -------------------------------------------------------------------------
} else {
  const keywords = Array.isArray(rec.keywords) ? rec.keywords.join(',') : (rec.keywords || '');
  const level = op === 'error_log' ? 'error' : 'info';
  const status = rec.status || (op === 'error_log' ? 'failed' : 'running');
  const message = op === 'error_log'
    ? String(rec.error_log || rec.error_message || 'unspecified error').slice(0, 4000)
    : `${op}: ${rec.product_name || rec.factory || rec.run_id}`;

  values = [
    rec.run_id,
    rec.factory || null,
    rec.product_name || null,
    rec.category || null,
    keywords,
    rec.marketplace || '',
    rec.drive_folder_id || null,
    rec.etsy_listing_id ? String(rec.etsy_listing_id) : null,
    rec.prompt_version || null,
    status,
    rec.error_log || null,
    op,
    level,
    message,
  ];
  pgSql = CORE_SQL;

  sqliteSql = [
    'INSERT INTO adpf_products (',
    '  run_id, factory, product_name, category, keywords, marketplace,',
    '  drive_folder_id, etsy_listing_id, prompt_version, status, error_log, updated_at',
    ') VALUES (',
    '  ' + values.slice(0, 11).map(q).join(', ') + ", datetime('now')",
    ') ON CONFLICT(run_id) DO UPDATE SET',
    '  factory         = COALESCE(excluded.factory, adpf_products.factory),',
    '  product_name    = COALESCE(excluded.product_name, adpf_products.product_name),',
    '  category        = COALESCE(excluded.category, adpf_products.category),',
    "  keywords        = COALESCE(NULLIF(excluded.keywords, ''), adpf_products.keywords),",
    "  marketplace     = COALESCE(NULLIF(excluded.marketplace, ''), adpf_products.marketplace),",
    '  drive_folder_id = COALESCE(excluded.drive_folder_id, adpf_products.drive_folder_id),',
    '  etsy_listing_id = COALESCE(excluded.etsy_listing_id, adpf_products.etsy_listing_id),',
    '  prompt_version  = COALESCE(excluded.prompt_version, adpf_products.prompt_version),',
    '  status          = excluded.status,',
    '  error_log       = COALESCE(excluded.error_log, adpf_products.error_log),',
    "  updated_at      = datetime('now');",
    'INSERT INTO adpf_events (run_id, op, level, message) VALUES ('
      + [values[0], values[11], values[12], values[13]].map(q).join(', ') + ');',
    "SELECT 'ok' AS result, (SELECT id FROM adpf_products WHERE run_id = "
      + q(values[0]) + ') AS product_id;',
  ].join('\n');
}

return [{
  json: {
    op,
    run_id: rec.run_id,
    status: rec.status || 'running',
    db_type: dbType,
    pg_sql: pgSql,
    pg_params: values,
    sqlite_sql: sqliteSql,
  },
}];
""".strip()

JS_BUILD_RESULT = r"""
// One result shape whichever engine ran.
const ctx = $('Build SQL Statement').first().json;
const raw = $input.first().json || {};

const stdout = String(raw.stdout || '');
const failed = Boolean(raw.stderr) || raw.exitCode > 0;

return [{
  json: {
    ok: !failed,
    op: ctx.op,
    run_id: ctx.run_id,
    status: ctx.status,
    engine: ctx.db_type,
    record_id: raw.product_id || raw.id || null,
    event_id: raw.event_id || null,
    stdout: stdout ? stdout.slice(0, 500) : null,
    error: failed ? String(raw.stderr || 'database command failed').slice(0, 500) : null,
    written_at: new Date().toISOString(),
  },
}];
""".strip()


def _sqlite_command(sql_expr: str) -> str:
    """Quoted heredoc: the shell performs no expansion on the SQL body."""
    return (
        "={{ \"sqlite3 '\" + ($env.DB_SQLITE_PATH || '/home/node/.n8n/adpf.db') + "
        "\"' <<'ADPFSQL'\\n\" + " + sql_expr + " + \"\\nADPFSQL\" }}"
    )


def build() -> Workflow:
    wf = Workflow("06")

    wf.add("Receive DB Request", T_EXEC_TRIGGER, pos(0, 1),
           {"inputSource": "passthrough"},
           notes="Entry point. op = run_start | product_upsert | status_update | error_log.")
    wf.add("Build SQL Statement", T_CODE, pos(1, 1), code(JS_BUILD_SQL),
           notes=("Validates the record and prepares both dialects: parameter array for "
                  "PostgreSQL, fully escaped SQL text for the SQLite CLI."))
    wf.add("Route: Database Type", T_SWITCH, pos(2, 1),
           switch_equals("={{ ($env.DB_TYPE || 'postgres').toLowerCase() }}",
                         ["postgres", "sqlite"]),
           notes="DB_TYPE decides the engine. Anything unknown falls back to PostgreSQL.")

    # -- PostgreSQL branch (native node) -----------------------------------
    wf.add("Postgres: Ensure Schema", T_POSTGRES, pos(3, 0),
           {"operation": "executeQuery",
            "query": DDL_POSTGRES + "\n\n" + DDL_V2_POSTGRES, "options": {}},
           notes=("Idempotent DDL for the V1 and V2 tables, so a fresh database "
                  "bootstraps itself on the first run."),
           **RETRY)
    wf.add("Postgres: Write Record", T_POSTGRES, pos(4, 0),
           {
               "operation": "executeQuery",
               "query": "={{ $('Build SQL Statement').first().json.pg_sql }}",
               "options": {"queryReplacement": "={{ $('Build SQL Statement').first().json.pg_params }}"},
           },
           notes=("Single parameterised statement: upsert the product row (NULLs never "
                  "clobber existing values) and append an event."),
           **RETRY)

    # -- SQLite branch (CLI, self-hosted n8n only) -------------------------
    wf.add("SQLite: Ensure Schema", T_EXEC_CMD, pos(3, 2),
           {"command": _sqlite_command(json.dumps(DDL_SQLITE + "\n" + DDL_V2_SQLITE))},
           notes="Requires the sqlite3 CLI on the n8n host. Self-hosted deployments only.",
           **RETRY)
    wf.add("SQLite: Write Record", T_EXEC_CMD, pos(4, 2),
           {"command": _sqlite_command("$('Build SQL Statement').first().json.sqlite_sql")},
           notes="Same upsert + event insert, escaped in the Build SQL Statement node.",
           **RETRY)

    wf.add("Build DB Result", T_CODE, pos(5, 1), code(JS_BUILD_RESULT),
           notes="Normalises the PostgreSQL row and the CLI stdout into one result shape.")
    wf.add("Return: DB Result", T_NOOP, pos(6, 1), {},
           notes="Terminal node - its item is the sub-workflow return value.")

    wf.link("Receive DB Request", "Build SQL Statement")
    wf.link("Build SQL Statement", "Route: Database Type")
    wf.link("Route: Database Type", "Postgres: Ensure Schema", 0)
    wf.link("Route: Database Type", "SQLite: Ensure Schema", 1)
    wf.link("Route: Database Type", "Postgres: Ensure Schema", 2)
    wf.link("Postgres: Ensure Schema", "Postgres: Write Record")
    wf.link("SQLite: Ensure Schema", "SQLite: Write Record")
    wf.link("Postgres: Write Record", "Build DB Result")
    wf.link("SQLite: Write Record", "Build DB Result")
    wf.link("Build DB Result", "Return: DB Result")

    return wf
