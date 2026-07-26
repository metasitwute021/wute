"""08 Cost and Budget - V2 sections 8, 9, 10.

Three operations behind one entry point:

  record_cost   append an API call to adpf_costs (called after every AI stage)
  check_budget  answer "may this run start?" from real spend, not an estimate
  rollup        recompute a product's cost / profit / margin / ROI

The provider column is generic so a future provider needs no migration, but the
only provider these workflows ever write is ``openai`` - the project is
OpenAI-only by requirement.
"""

from common import (
    RETRY, T_CODE, T_EXEC_TRIGGER, T_NOOP, T_POSTGRES, T_SWITCH, Workflow, code,
    pos, switch_equals,
)

JS_NORMALIZE = r"""
// Price table in USD. Overridable per-model without touching the workflow, so a
// price change is an environment edit, not a redeploy.
//   chat  : USD per 1M tokens  [input, output]
//   image : USD per image
const CHAT_PRICES = {
  'gpt-4.1':      [2.00, 8.00],
  'gpt-4.1-mini': [0.40, 1.60],
  'gpt-4o':       [2.50, 10.00],
  'gpt-4o-mini':  [0.15, 0.60],
};
const IMAGE_PRICE_USD = Number($env.OPENAI_IMAGE_UNIT_COST_USD || 0.19);

const readOverride = () => {
  try { return JSON.parse($env.OPENAI_PRICE_OVERRIDE_JSON || '{}'); } catch (e) { return {}; }
};

const rec = $input.first().json || {};
const op = ['record_cost', 'check_budget', 'rollup'].includes(rec.op) ? rec.op : 'record_cost';

const now = new Date();
const dayKey = now.toISOString().slice(0, 10);
const monthKey = now.toISOString().slice(0, 7);

const usage = rec.usage || {};
const kind = usage.kind || rec.kind || 'chat';
const model = rec.model ||
  (kind === 'image' ? ($env.OPENAI_MODEL_IMAGE || 'gpt-image-1')
                    : ($env.OPENAI_MODEL_TEXT || 'gpt-4.1'));

const overrides = readOverride();
let costUsd = 0;
let inputUnits = 0;
let outputUnits = 0;
let calls = Number(rec.calls || 1);

if (kind === 'image') {
  inputUnits = Number(usage.images || rec.images || calls) || 1;
  calls = inputUnits;
  const unit = Number(overrides[model]) || IMAGE_PRICE_USD;
  costUsd = inputUnits * unit;
} else {
  inputUnits = Number(usage.prompt_tokens || 0);
  outputUnits = Number(usage.completion_tokens || 0);
  const price = overrides[model] || CHAT_PRICES[model] || CHAT_PRICES['gpt-4.1'];
  costUsd = (inputUnits / 1e6) * price[0] + (outputUnits / 1e6) * price[1];
}

if (!rec.run_id) throw new Error('08 Cost and Budget requires a run_id');

return [{
  json: {
    op,
    run_id: rec.run_id,
    stage: rec.stage || 'unknown',
    provider: 'openai',
    model,
    kind,
    calls,
    input_units: inputUnits,
    output_units: outputUnits,
    cost_usd: Math.round(costUsd * 1e6) / 1e6,
    day_key: dayKey,
    month_key: monthKey,
    daily_limit_usd: Number($env.BUDGET_DAILY_USD || 20),
    monthly_limit_usd: Number($env.BUDGET_MONTHLY_USD || 300),
    // A run is refused when the remaining budget cannot cover this much.
    reserve_usd: Number(rec.reserve_usd || $env.BUDGET_RUN_RESERVE_USD || 3),
  },
}];
""".strip()

SQL_INSERT_COST = """
-- Section 9: append the call, then fold it into both budget periods in the
-- same statement so a crash cannot leave the two out of step.
WITH inserted AS (
  INSERT INTO adpf_costs (run_id, stage, provider, model, kind, calls,
                          input_units, output_units, cost_usd)
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
  RETURNING id, cost_usd
), day_budget AS (
  INSERT INTO adpf_budget (scope, period_key, limit_usd, spent_usd)
  VALUES ('daily', $10, $12, (SELECT cost_usd FROM inserted))
  ON CONFLICT (scope, period_key) DO UPDATE
    SET spent_usd = adpf_budget.spent_usd + (SELECT cost_usd FROM inserted),
        limit_usd = EXCLUDED.limit_usd,
        updated_at = now()
  RETURNING spent_usd, limit_usd
), month_budget AS (
  INSERT INTO adpf_budget (scope, period_key, limit_usd, spent_usd)
  VALUES ('monthly', $11, $13, (SELECT cost_usd FROM inserted))
  ON CONFLICT (scope, period_key) DO UPDATE
    SET spent_usd = adpf_budget.spent_usd + (SELECT cost_usd FROM inserted),
        limit_usd = EXCLUDED.limit_usd,
        updated_at = now()
  RETURNING spent_usd, limit_usd
)
SELECT (SELECT id FROM inserted)                AS cost_id,
       (SELECT cost_usd FROM inserted)          AS cost_usd,
       (SELECT spent_usd FROM day_budget)       AS daily_spent,
       (SELECT limit_usd FROM day_budget)       AS daily_limit,
       (SELECT spent_usd FROM month_budget)     AS monthly_spent,
       (SELECT limit_usd FROM month_budget)     AS monthly_limit;
""".strip()

SQL_CHECK_BUDGET = """
-- Section 10: spend is recomputed from adpf_costs rather than trusted from the
-- running total, so a lost update can never quietly unlock more budget.
WITH day_spend AS (
  SELECT COALESCE(sum(cost_usd), 0) AS spent
  FROM adpf_costs WHERE created_at >= $1::date AND created_at < ($1::date + INTERVAL '1 day')
), month_spend AS (
  SELECT COALESCE(sum(cost_usd), 0) AS spent
  FROM adpf_costs WHERE to_char(created_at, 'YYYY-MM') = $2
), day_row AS (
  INSERT INTO adpf_budget (scope, period_key, limit_usd, spent_usd)
  VALUES ('daily', $1, $3, (SELECT spent FROM day_spend))
  ON CONFLICT (scope, period_key) DO UPDATE
    SET limit_usd = EXCLUDED.limit_usd,
        spent_usd = (SELECT spent FROM day_spend),
        updated_at = now()
  RETURNING limit_usd, spent_usd
), month_row AS (
  INSERT INTO adpf_budget (scope, period_key, limit_usd, spent_usd)
  VALUES ('monthly', $2, $4, (SELECT spent FROM month_spend))
  ON CONFLICT (scope, period_key) DO UPDATE
    SET limit_usd = EXCLUDED.limit_usd,
        spent_usd = (SELECT spent FROM month_spend),
        updated_at = now()
  RETURNING limit_usd, spent_usd
)
SELECT (SELECT limit_usd FROM day_row)   AS daily_limit,
       (SELECT spent_usd FROM day_row)   AS daily_spent,
       (SELECT limit_usd FROM month_row) AS monthly_limit,
       (SELECT spent_usd FROM month_row) AS monthly_spent,
       (SELECT count(*) FROM adpf_products
         WHERE created_at >= $1::date AND created_at < ($1::date + INTERVAL '1 day')) AS runs_today;
""".strip()

SQL_ROLLUP = """
-- Section 8: fold the measured API cost and the measured revenue into the
-- product row, so ROI is one column read instead of a join at report time.
WITH cost AS (
  SELECT COALESCE(sum(cost_usd), 0) AS api_cost FROM adpf_costs WHERE run_id = $1
), revenue AS (
  SELECT COALESCE(max(revenue_usd), 0) AS revenue, COALESCE(max(sales), 0) AS sales
  FROM adpf_sales WHERE run_id = $1
)
UPDATE adpf_products p SET
  api_cost_usd = (SELECT api_cost FROM cost),
  revenue_usd  = (SELECT revenue FROM revenue),
  profit_usd   = (SELECT revenue FROM revenue) - (SELECT api_cost FROM cost),
  margin_pct   = CASE WHEN (SELECT revenue FROM revenue) > 0
                      THEN round((((SELECT revenue FROM revenue) - (SELECT api_cost FROM cost))
                             / (SELECT revenue FROM revenue) * 100)::numeric, 2)
                      ELSE NULL END,
  roi_pct      = CASE WHEN (SELECT api_cost FROM cost) > 0
                      THEN round((((SELECT revenue FROM revenue) - (SELECT api_cost FROM cost))
                             / (SELECT api_cost FROM cost) * 100)::numeric, 2)
                      ELSE NULL END,
  updated_at   = now()
WHERE p.run_id = $1
RETURNING p.run_id, p.api_cost_usd, p.revenue_usd, p.profit_usd, p.margin_pct, p.roi_pct;
""".strip()

JS_EVALUATE_BUDGET = r"""
// Section 10: the gate 01 consults before spending anything on a new run.
const ctx = $('Normalize Cost Request').first().json;
const row = $input.first().json || {};

const num = (value, fallback) => (value === null || value === undefined ? fallback : Number(value));

const dailyLimit = num(row.daily_limit, ctx.daily_limit_usd);
const dailySpent = num(row.daily_spent, 0);
const monthlyLimit = num(row.monthly_limit, ctx.monthly_limit_usd);
const monthlySpent = num(row.monthly_spent, 0);

const dailyRemaining = Math.round((dailyLimit - dailySpent) * 100) / 100;
const monthlyRemaining = Math.round((monthlyLimit - monthlySpent) * 100) / 100;
const remaining = Math.min(dailyRemaining, monthlyRemaining);

const reasons = [];
if (dailyRemaining < ctx.reserve_usd) reasons.push(`daily budget exhausted (${dailyRemaining} USD left, need ${ctx.reserve_usd})`);
if (monthlyRemaining < ctx.reserve_usd) reasons.push(`monthly budget exhausted (${monthlyRemaining} USD left, need ${ctx.reserve_usd})`);

return [{
  json: {
    ok: true,
    op: 'check_budget',
    run_id: ctx.run_id,
    allowed: reasons.length === 0,
    block_reason: reasons.join('; ') || null,
    daily: { limit_usd: dailyLimit, spent_usd: Math.round(dailySpent * 100) / 100,
             remaining_usd: dailyRemaining,
             used_pct: dailyLimit ? Math.round((dailySpent / dailyLimit) * 1000) / 10 : 0 },
    monthly: { limit_usd: monthlyLimit, spent_usd: Math.round(monthlySpent * 100) / 100,
               remaining_usd: monthlyRemaining,
               used_pct: monthlyLimit ? Math.round((monthlySpent / monthlyLimit) * 1000) / 10 : 0 },
    remaining_usd: remaining,
    runs_today: Number(row.runs_today || 0),
    checked_at: new Date().toISOString(),
  },
}];
""".strip()

JS_BUILD_RESULT = r"""
// One result shape for all three operations.
const ctx = $('Normalize Cost Request').first().json;
const row = $input.first().json || {};

return [{
  json: {
    ok: true,
    op: ctx.op,
    run_id: ctx.run_id,
    stage: ctx.stage,
    provider: ctx.provider,
    model: ctx.model,
    kind: ctx.kind,
    cost_usd: ctx.op === 'record_cost' ? ctx.cost_usd : null,
    cost_id: row.cost_id || null,
    daily_spent_usd: row.daily_spent !== undefined ? Number(row.daily_spent) : null,
    monthly_spent_usd: row.monthly_spent !== undefined ? Number(row.monthly_spent) : null,
    roi: ctx.op === 'rollup' ? {
      api_cost_usd: Number(row.api_cost_usd || 0),
      revenue_usd: Number(row.revenue_usd || 0),
      profit_usd: Number(row.profit_usd || 0),
      margin_pct: row.margin_pct === null ? null : Number(row.margin_pct),
      roi_pct: row.roi_pct === null ? null : Number(row.roi_pct),
    } : null,
    written_at: new Date().toISOString(),
  },
}];
""".strip()


def build() -> Workflow:
    wf = Workflow("08")

    wf.add("Receive Cost Request", T_EXEC_TRIGGER, pos(0, 1),
           {"inputSource": "passthrough"},
           notes="Entry point. op = record_cost | check_budget | rollup.")
    wf.add("Normalize Cost Request", T_CODE, pos(1, 1), code(JS_NORMALIZE),
           notes=("Section 9. Turns an OpenAI usage block into USD using a price table "
                  "that can be overridden by environment variable."))
    wf.add("Route: Cost Operation", T_SWITCH, pos(2, 1),
           switch_equals("={{ $json.op }}", ["record_cost", "check_budget", "rollup"],
                         fallback=None),
           notes="Three operations, three branches.")

    wf.add("Postgres: Insert Cost", T_POSTGRES, pos(3, 0),
           {
               "operation": "executeQuery",
               "query": SQL_INSERT_COST,
               "options": {"queryReplacement": (
                   "={{ [$json.run_id, $json.stage, $json.provider, $json.model, $json.kind, "
                   "$json.calls, $json.input_units, $json.output_units, $json.cost_usd, "
                   "$json.day_key, $json.month_key, $json.daily_limit_usd, "
                   "$json.monthly_limit_usd] }}"
               )},
           },
           notes="Section 9 + 10. Records the call and folds it into both budget periods atomically.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)

    wf.add("Postgres: Read Budget", T_POSTGRES, pos(3, 2),
           {
               "operation": "executeQuery",
               "query": SQL_CHECK_BUDGET,
               "options": {"queryReplacement": (
                   "={{ [$json.day_key, $json.month_key, $json.daily_limit_usd, "
                   "$json.monthly_limit_usd] }}"
               )},
           },
           notes="Section 10. Recomputes spend from adpf_costs - the running total is never trusted.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("Evaluate Budget", T_CODE, pos(4, 2), code(JS_EVALUATE_BUDGET),
           notes="Returns allowed=false with a reason when either period is exhausted.")

    wf.add("Postgres: Rollup ROI", T_POSTGRES, pos(3, 3),
           {
               "operation": "executeQuery",
               "query": SQL_ROLLUP,
               "options": {"queryReplacement": "={{ [$json.run_id] }}"},
           },
           notes="Section 8. Writes cost, revenue, profit, margin and ROI onto the product row.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)

    wf.add("Build Cost Result", T_CODE, pos(5, 1), code(JS_BUILD_RESULT),
           notes="Normalises all three branches into one result shape.")
    wf.add("Return: Cost Result", T_NOOP, pos(6, 1), {},
           notes="Terminal node - its item is the sub-workflow return value.")

    wf.chain("Receive Cost Request", "Normalize Cost Request", "Route: Cost Operation")
    wf.link("Route: Cost Operation", "Postgres: Insert Cost", 0)
    wf.link("Route: Cost Operation", "Postgres: Read Budget", 1)
    wf.link("Route: Cost Operation", "Postgres: Rollup ROI", 2)
    wf.link("Postgres: Insert Cost", "Build Cost Result")
    wf.link("Postgres: Read Budget", "Evaluate Budget")
    wf.link("Evaluate Budget", "Return: Cost Result")
    wf.link("Postgres: Rollup ROI", "Build Cost Result")
    wf.link("Build Cost Result", "Return: Cost Result")

    return wf
