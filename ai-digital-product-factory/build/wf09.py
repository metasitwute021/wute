"""09 Feedback Learning - V2 sections 14, 15, 16, 17, 21, 22.

Closes the loop: collect what the marketplace actually did with the products,
write it back, and let it change what gets made next.

    upload -> collect -> learn -> improve prompt -> create again

Prompt changes are proposed, stored and scored, but a new prompt version starts
inactive. A model rewriting its own instructions unattended is how a factory
quietly drifts into producing junk; a human flips the switch.
"""

from common import (
    RETRY, T_CODE, T_EXEC_TRIGGER, T_HTTP, T_IF, T_LOOP, T_NOOP, T_POSTGRES,
    T_SCHEDULE, Workflow, code, etsy_http, if_bool, loop_node, openai_chat, pos,
)
from prompts import RENDER_HELPER, library_js

JS_NORMALIZE = r"""
// Runs on a schedule or on demand. The window governs both what is measured and
// how much weight a conclusion deserves.
const input = $input.first() ? $input.first().json : {};
const windowDays = Math.max(1, Math.min(365, Number(input.window_days || $env.LEARNING_WINDOW_DAYS || 30)));

return [{
  json: {
    run_id: input.run_id || `learn-${new Date().toISOString().slice(0, 10)}`,
    window_days: windowDays,
    window: `last ${windowDays} days`,
    marketplace: input.marketplace || 'etsy',
    prompt_version: $env.PROMPT_VERSION || 'v1.0.0',
    dry_run: input.dry_run === true,
    started_at: new Date().toISOString(),
  },
}];
""".strip()

SQL_ACTIVE_LISTINGS = """
-- Everything with a live listing id, newest first. Section 22: marketplace is
-- carried through so performance is never averaged across platforms.
SELECT run_id, product_name, category, etsy_listing_id AS listing_id,
       'etsy'::text AS marketplace, price_usd, api_cost_usd, prompt_version
FROM adpf_products
WHERE etsy_listing_id IS NOT NULL
  AND status = 'completed'
  AND created_at >= now() - ($1 || ' days')::interval
ORDER BY created_at DESC
LIMIT 200;
""".strip()

JS_AGGREGATE_RECEIPTS = r"""
// Section 17: fold the shop receipts into per-listing sales and revenue.
// One call for the whole shop beats one call per listing.
const ctx = $('Normalize Learning Input').first().json;
const response = $input.first().json || {};
const receipts = response.results || [];

const byListing = new Map();
for (const receipt of receipts) {
  for (const tx of receipt.transactions || []) {
    const key = String(tx.listing_id || '');
    if (!key) continue;
    const row = byListing.get(key) || { sales: 0, revenue_usd: 0 };
    const amount = tx?.price?.amount;
    const divisor = tx?.price?.divisor || 100;
    row.sales += Number(tx.quantity || 1);
    row.revenue_usd += typeof amount === 'number' ? (amount / divisor) * Number(tx.quantity || 1) : 0;
    byListing.set(key, row);
  }
}

return [{
  json: {
    ...ctx,
    receipts_seen: receipts.length,
    sales_by_listing: Object.fromEntries(
      [...byListing.entries()].map(([k, v]) => [k, {
        sales: v.sales, revenue_usd: Math.round(v.revenue_usd * 100) / 100,
      }])
    ),
  },
}];
""".strip()

JS_SPLIT_LISTINGS = r"""
// One item per listing for the stats loop.
const listings = $('Postgres: Load Active Listings').all()
  .map((i) => i.json)
  .filter((row) => row && row.listing_id);

if (!listings.length) return [{ json: { no_listings: true } }];
return listings.map((json) => ({ json }));
""".strip()

JS_PARSE_LISTING_STATS = r"""
// Section 17: views / favourites from the listing, sales from the receipts map.
const listing = $('Loop: Listings').first().json;
const stats = $('Aggregate Receipts').first().json;
const response = $input.first().json || {};

const detail = response.listing_id ? response : (response.results?.[0] || {});
const sold = stats.sales_by_listing?.[String(listing.listing_id)] || { sales: 0, revenue_usd: 0 };

const views = Number(detail.views || 0);
const favorites = Number(detail.num_favorers || 0);
// Etsy does not expose a click metric on this endpoint; favourites are the
// closest available proxy and are stored as such rather than invented.
const conversion = views > 0 ? Math.round((sold.sales / views) * 100000) / 1000 : 0;

return [{
  json: {
    marketplace: listing.marketplace,
    listing_id: String(listing.listing_id),
    run_id: listing.run_id,
    product_name: listing.product_name,
    category: listing.category,
    prompt_version: listing.prompt_version,
    views,
    clicks: favorites,
    favorites,
    sales: sold.sales,
    revenue_usd: sold.revenue_usd,
    conversion_rate: conversion,
  },
}];
""".strip()

JS_COLLECT_SALES = r"""
// Pack every measured listing into one array for a single bulk upsert.
const ctx = $('Normalize Learning Input').first().json;
const rows = $input.all().map((i) => i.json).filter((r) => r && r.listing_id);
const collectedAt = new Date().toISOString();

return [{
  json: {
    ...ctx,
    collected_at: collectedAt,
    listing_count: rows.length,
    rows_json: JSON.stringify(rows.map((r) => ({ ...r, collected_at: collectedAt }))),
    totals: {
      views: rows.reduce((s, r) => s + r.views, 0),
      favorites: rows.reduce((s, r) => s + r.favorites, 0),
      sales: rows.reduce((s, r) => s + r.sales, 0),
      revenue_usd: Math.round(rows.reduce((s, r) => s + r.revenue_usd, 0) * 100) / 100,
    },
  },
}];
""".strip()

SQL_UPSERT_SALES = """
-- Section 17 + 22. One snapshot per listing per collection run, so the history
-- is a time series rather than a single mutable row.
INSERT INTO adpf_sales (marketplace, listing_id, run_id, product_name, category,
                        views, clicks, favorites, sales, revenue_usd,
                        conversion_rate, collected_at)
SELECT x.marketplace, x.listing_id, x.run_id, x.product_name, x.category,
       x.views, x.clicks, x.favorites, x.sales, x.revenue_usd,
       x.conversion_rate, x.collected_at
FROM json_populate_recordset(NULL::adpf_sales, $1::json) AS x
ON CONFLICT (marketplace, listing_id, collected_at) DO UPDATE SET
  views = EXCLUDED.views, clicks = EXCLUDED.clicks, favorites = EXCLUDED.favorites,
  sales = EXCLUDED.sales, revenue_usd = EXCLUDED.revenue_usd,
  conversion_rate = EXCLUDED.conversion_rate
RETURNING id;
""".strip()

SQL_PERFORMANCE = """
-- Everything the Learning agent needs, in one round trip. Each sub-query takes
-- the latest snapshot per listing so a product measured ten times is not
-- counted ten times.
WITH latest AS (
  SELECT DISTINCT ON (marketplace, listing_id)
         marketplace, listing_id, run_id, product_name, category,
         views, favorites, sales, revenue_usd, conversion_rate
  FROM adpf_sales
  WHERE collected_at >= now() - ($1 || ' days')::interval
  ORDER BY marketplace, listing_id, collected_at DESC
),
joined AS (
  SELECT l.*, p.prompt_version, p.api_cost_usd, p.factory
  FROM latest l LEFT JOIN adpf_products p ON p.run_id = l.run_id
),
by_category AS (
  SELECT category,
         count(*)::int                         AS products,
         sum(views)::int                       AS views,
         sum(favorites)::int                   AS favorites,
         sum(sales)::int                       AS sales,
         round(sum(revenue_usd)::numeric, 2)   AS revenue_usd,
         round(sum(COALESCE(api_cost_usd, 0))::numeric, 2) AS cost_usd,
         round(avg(conversion_rate)::numeric, 3)           AS avg_conversion
  FROM joined GROUP BY category ORDER BY revenue_usd DESC
),
by_marketplace AS (
  SELECT marketplace, count(*)::int AS listings, sum(sales)::int AS sales,
         round(sum(revenue_usd)::numeric, 2) AS revenue_usd,
         round(avg(conversion_rate)::numeric, 3) AS avg_conversion
  FROM joined GROUP BY marketplace
),
by_prompt AS (
  SELECT COALESCE(prompt_version, 'unknown') AS prompt_version,
         count(*)::int AS products, sum(sales)::int AS sales,
         round(sum(revenue_usd)::numeric, 2) AS revenue_usd,
         round(avg(conversion_rate)::numeric, 3) AS avg_conversion
  FROM joined GROUP BY 1 ORDER BY revenue_usd DESC
),
winners AS (
  SELECT product_name, category, views, favorites, sales, revenue_usd, conversion_rate
  FROM joined ORDER BY revenue_usd DESC, sales DESC LIMIT 10
),
losers AS (
  SELECT product_name, category, views, favorites, sales, revenue_usd, conversion_rate
  FROM joined WHERE views > 20 ORDER BY sales ASC, views DESC LIMIT 10
),
ab AS (
  SELECT test_uid, element, variant, variant_value, views, favorites, sales,
         revenue_usd, status, started_at
  FROM adpf_ab_tests WHERE status = 'running' ORDER BY started_at
)
SELECT
  COALESCE((SELECT json_agg(row_to_json(by_category))    FROM by_category), '[]'::json)    AS categories,
  COALESCE((SELECT json_agg(row_to_json(by_marketplace)) FROM by_marketplace), '[]'::json) AS marketplaces,
  COALESCE((SELECT json_agg(row_to_json(by_prompt))      FROM by_prompt), '[]'::json)      AS prompts,
  COALESCE((SELECT json_agg(row_to_json(winners))        FROM winners), '[]'::json)        AS winners,
  COALESCE((SELECT json_agg(row_to_json(losers))         FROM losers), '[]'::json)         AS losers,
  COALESCE((SELECT json_agg(row_to_json(ab))             FROM ab), '[]'::json)             AS ab_tests,
  (SELECT count(*) FROM joined)::int AS sample_size;
""".strip()

JS_EVALUATE_AB = r"""
// Section 21: decide running A/B tests. Deliberately conservative - a test is
// only called when both arms have enough traffic and the gap is not noise.
const ctx = $('Normalize Learning Input').first().json;
const row = $input.first().json || {};

const asArray = (value) => {
  if (Array.isArray(value)) return value;
  if (typeof value === 'string') { try { return JSON.parse(value); } catch (e) { return []; } }
  return value || [];
};

const MIN_VIEWS = Number($env.AB_MIN_VIEWS_PER_ARM || 200);
const MIN_LIFT = Number($env.AB_MIN_RELATIVE_LIFT || 0.20);

const tests = asArray(row.ab_tests);
const grouped = new Map();
for (const arm of tests) {
  const list = grouped.get(arm.test_uid) || [];
  list.push(arm);
  grouped.set(arm.test_uid, list);
}

const decisions = [];
for (const [testUid, arms] of grouped) {
  const a = arms.find((x) => x.variant === 'A');
  const b = arms.find((x) => x.variant === 'B');
  if (!a || !b) continue;

  const rate = (arm) => (arm.views > 0 ? arm.sales / arm.views : 0);
  const rateA = rate(a);
  const rateB = rate(b);

  if (a.views < MIN_VIEWS || b.views < MIN_VIEWS) {
    decisions.push({ test_uid: testUid, element: a.element, decision: 'keep_running',
                     reason: `needs ${MIN_VIEWS} views per arm (A=${a.views}, B=${b.views})` });
    continue;
  }

  const lift = rateA > 0 ? (rateB - rateA) / rateA : (rateB > 0 ? 1 : 0);
  if (Math.abs(lift) < MIN_LIFT) {
    decisions.push({ test_uid: testUid, element: a.element, decision: 'no_difference',
                     winner: 'A', reason: `relative lift ${Math.round(lift * 1000) / 10}% is inside the noise band` });
  } else {
    decisions.push({
      test_uid: testUid, element: a.element,
      decision: 'winner', winner: lift > 0 ? 'B' : 'A',
      reason: `variant ${lift > 0 ? 'B' : 'A'} converts ${Math.abs(Math.round(lift * 1000) / 10)}% better`,
      winning_value: lift > 0 ? b.variant_value : a.variant_value,
    });
  }
}

return [{
  json: {
    ...ctx,
    performance: {
      categories: asArray(row.categories),
      marketplaces: asArray(row.marketplaces),
      prompts: asArray(row.prompts),
      winners: asArray(row.winners),
      losers: asArray(row.losers),
      sample_size: Number(row.sample_size || 0),
    },
    ab_decisions: decisions,
    ab_concluded: decisions.filter((d) => d.decision !== 'keep_running'),
  },
}];
""".strip()

JS_BUILD_LEARNING_PROMPT = RENDER_HELPER + r"""
const ctx = $input.first().json;
const agent = $('Prompt Library').first().json.prompts.learning_ai;
const perf = ctx.performance;

return [{
  json: {
    ...ctx,
    learning_user_prompt: render(agent.user_template, {
      window: ctx.window,
      sample_size: perf.sample_size,
      category_performance_json: JSON.stringify(perf.categories, null, 2),
      prompt_performance_json: JSON.stringify(perf.prompts, null, 2),
      winners_json: JSON.stringify(perf.winners, null, 2),
      losers_json: JSON.stringify(perf.losers, null, 2),
      ab_results_json: JSON.stringify(ctx.ab_concluded, null, 2),
    }),
  },
}];
""".rstrip()

JS_PARSE_LEARNING = r"""
// Section 14 + 15. The report is stored; it never edits a live prompt by itself.
const ctx = $('Build Learning Prompt').first().json;
const response = $input.first().json;

let report;
try {
  report = JSON.parse(response?.choices?.[0]?.message?.content || '{}');
} catch (e) {
  report = { verdict: 'no_change', findings: [`Learning AI returned invalid JSON: ${e.message}`] };
}

const sample = ctx.performance.sample_size;
const MIN_SAMPLE = Number($env.LEARNING_MIN_SAMPLE || 15);

// Guard rail: a confident-sounding recommendation off 3 products is worthless.
const adequate = sample >= MIN_SAMPLE && report.sample_adequate !== false;
const recommendations = adequate ? (report.recommendations || []) : [];

const nextVersion = (() => {
  const current = String(ctx.prompt_version || 'v1.0.0');
  const parts = current.replace(/^v/, '').split('.').map(Number);
  if (parts.length !== 3 || parts.some(Number.isNaN)) return 'v1.0.1';
  return `v${parts[0]}.${parts[1]}.${parts[2] + 1}`;
})();

return [{
  json: {
    ...ctx,
    learning: {
      verdict: adequate ? (report.verdict || 'no_change') : 'no_change',
      sample_adequate: adequate,
      sample_size: sample,
      findings: report.findings || [],
      recommendations,
      category_advice: report.category_advice || [],
      next_ab_tests: report.next_ab_tests || [],
      proposed_prompt_version: recommendations.length ? nextVersion : null,
      blocked_reason: adequate ? null
        : `sample of ${sample} products is below the minimum of ${MIN_SAMPLE}`,
    },
  },
}];
""".strip()

SQL_UPDATE_PROMPT_STATS = """
-- Section 15: score the prompt version that actually produced the results, and
-- register any proposed successor as INACTIVE pending human approval.
WITH stats AS (
  SELECT COALESCE(p.prompt_version, 'unknown') AS prompt_version,
         count(*)::int AS runs,
         count(*) FILTER (WHERE p.status = 'completed')::int AS successes,
         COALESCE(sum(s.sales), 0)::int AS sales_sum,
         COALESCE(sum(s.revenue_usd), 0)::numeric AS revenue_usd
  FROM adpf_products p
  LEFT JOIN LATERAL (
    SELECT sales, revenue_usd FROM adpf_sales s2
    WHERE s2.run_id = p.run_id ORDER BY collected_at DESC LIMIT 1
  ) s ON true
  WHERE p.created_at >= now() - ($1 || ' days')::interval
  GROUP BY 1
), upserted AS (
  INSERT INTO adpf_prompt_versions (prompt_version, agent, runs, successes,
                                    sales_sum, revenue_usd, success_rate, avg_sales, active)
  SELECT prompt_version, 'all', runs, successes, sales_sum, revenue_usd,
         CASE WHEN runs > 0 THEN round((successes::numeric / runs) * 100, 2) ELSE NULL END,
         CASE WHEN runs > 0 THEN round(sales_sum::numeric / runs, 2) ELSE NULL END,
         true
  FROM stats
  ON CONFLICT (prompt_version, agent) DO UPDATE SET
    runs = EXCLUDED.runs, successes = EXCLUDED.successes,
    sales_sum = EXCLUDED.sales_sum, revenue_usd = EXCLUDED.revenue_usd,
    success_rate = EXCLUDED.success_rate, avg_sales = EXCLUDED.avg_sales,
    updated_at = now()
  RETURNING id
), proposed AS (
  INSERT INTO adpf_prompt_versions (prompt_version, agent, active, notes)
  SELECT $2, 'proposed', false, $3
  WHERE $2 IS NOT NULL AND $2 <> ''
  ON CONFLICT (prompt_version, agent) DO UPDATE SET notes = EXCLUDED.notes, updated_at = now()
  RETURNING id
)
SELECT (SELECT count(*) FROM upserted) AS versions_scored,
       (SELECT count(*) FROM proposed) AS proposals_stored;
""".strip()

SQL_UPSERT_TRENDS = """
-- Section 16: trend memory. One row per keyword per month, so next quarter's
-- research can ask "did this sell last time it was in season".
INSERT INTO adpf_trends (keyword, category, period_type, period_key,
                         demand_score, trend_score, sales, observed_at)
SELECT x.keyword, x.category, x.period_type, x.period_key,
       x.demand_score, x.trend_score, x.sales, now()
FROM json_populate_recordset(NULL::adpf_trends, $1::json) AS x
ON CONFLICT (keyword, period_type, period_key) DO UPDATE SET
  demand_score = EXCLUDED.demand_score,
  trend_score  = EXCLUDED.trend_score,
  sales        = adpf_trends.sales + EXCLUDED.sales,
  observed_at  = now()
RETURNING id;
""".strip()

JS_BUILD_TRENDS = r"""
// Section 16: turn this window's measured performance into trend rows.
const ctx = $('Parse Learning Report').first().json;
const now = new Date();
const monthKey = now.toISOString().slice(0, 7);

const rows = (ctx.performance.categories || []).map((category) => {
  const sales = Number(category.sales || 0);
  const views = Number(category.views || 0);
  // Demand from raw attention, trend from how well that attention converted.
  const demand = Math.max(0, Math.min(100, Math.log10(views + 1) * 25));
  const trend = Math.max(0, Math.min(100, Number(category.avg_conversion || 0) * 2000));
  return {
    keyword: String(category.category || 'unknown').toLowerCase().slice(0, 120),
    category: category.category,
    period_type: 'monthly',
    period_key: monthKey,
    demand_score: Math.round(demand * 100) / 100,
    trend_score: Math.round(trend * 100) / 100,
    sales,
  };
});

return [{ json: { ...ctx, trend_rows: rows.length, rows_json: JSON.stringify(rows) } }];
""".strip()

JS_CHECK_AB = r"""
// Section 21: is there a concluded test to replace, or none running at all?
const ctx = $('Build Trend Rows').first().json;
const learning = ctx.learning;
const suggestions = learning.next_ab_tests || [];
const concluded = ctx.ab_concluded || [];

const shouldStart = suggestions.length > 0 || concluded.some((d) => d.decision === 'winner');
const winner = ctx.performance.winners?.[0] || null;

return [{
  json: {
    ...ctx,
    start_new_ab_test: shouldStart && Boolean(winner) && !ctx.dry_run,
    ab_target: winner,
    ab_element: suggestions[0]?.element || 'title',
    ab_hypothesis: suggestions[0]?.hypothesis || 'challenge the current best performer',
  },
}];
""".strip()

JS_BUILD_AB_PROMPT = RENDER_HELPER + r"""
const ctx = $input.first().json;
const agent = $('Prompt Library').first().json.prompts.ab_test_ai;
const target = ctx.ab_target || {};

return [{
  json: {
    ...ctx,
    ab_user_prompt: render(agent.user_template, {
      element: ctx.ab_element,
      control_value: String(target.product_name || ''),
      product_name: target.product_name || '',
      category: target.category || '',
      keywords: '',
      price_range: '3-25 USD',
      prior_results: JSON.stringify(ctx.ab_concluded || [], null, 2),
    }),
  },
}];
""".rstrip()

JS_PARSE_AB = r"""
// Store both arms so the next learning run can compare like with like.
const ctx = $('Build AB Test Prompt').first().json;
const response = $input.first().json;
const target = ctx.ab_target || {};

let variant;
try {
  variant = JSON.parse(response?.choices?.[0]?.message?.content || '{}');
} catch (e) {
  variant = {};
}

const testUid = `ab-${ctx.ab_element}-${Date.now().toString(36)}`;
const rows = [
  { test_uid: testUid, run_id: target.run_id || null, marketplace: 'etsy',
    listing_id: String(target.listing_id || ''), element: ctx.ab_element,
    variant: 'A', variant_value: String(target.product_name || ''), status: 'running' },
  { test_uid: testUid, run_id: target.run_id || null, marketplace: 'etsy',
    listing_id: String(target.listing_id || ''), element: ctx.ab_element,
    variant: 'B', variant_value: String(variant.variant_b || ''), status: 'running' },
];

return [{
  json: {
    ...ctx,
    ab_test: {
      test_uid: testUid,
      element: ctx.ab_element,
      hypothesis: variant.hypothesis || ctx.ab_hypothesis,
      variant_b: variant.variant_b || null,
      expected_metric: variant.expected_metric || 'conversion',
      min_sample: Number(variant.min_sample || $env.AB_MIN_VIEWS_PER_ARM || 200),
    },
    rows_json: JSON.stringify(rows),
  },
}];
""".strip()

SQL_SAVE_AB = """
INSERT INTO adpf_ab_tests (test_uid, run_id, marketplace, listing_id, element,
                           variant, variant_value, status)
SELECT x.test_uid, x.run_id, x.marketplace, x.listing_id, x.element,
       x.variant, x.variant_value, x.status
FROM json_populate_recordset(NULL::adpf_ab_tests, $1::json) AS x
ON CONFLICT (test_uid, variant) DO UPDATE SET
  variant_value = EXCLUDED.variant_value, status = EXCLUDED.status
RETURNING id;
""".strip()

JS_SKIP_AB = r"""
// Nothing worth testing this cycle - record why and carry on.
const ctx = $input.first().json;
return [{ json: { ...ctx, ab_test: null, ab_skipped_reason: ctx.dry_run
  ? 'dry run' : 'no concluded test and no suggestion worth acting on' } }];
""".strip()

JS_BUILD_REPORT = r"""
// Section 14: the learning report - what was measured, what it means, what
// changes are proposed, and what is being tested next.
const ctx = $input.first().json;
const sales = $('Collect Sales Data').first().json;

return [{
  json: {
    ok: true,
    run_id: ctx.run_id,
    window: ctx.window,
    collected: {
      listings: sales.listing_count,
      views: sales.totals.views,
      favorites: sales.totals.favorites,
      sales: sales.totals.sales,
      revenue_usd: sales.totals.revenue_usd,
    },
    performance: ctx.performance,
    learning: ctx.learning,
    ab_decisions: ctx.ab_decisions,
    new_ab_test: ctx.ab_test || null,
    ab_skipped_reason: ctx.ab_skipped_reason || null,
    trend_rows_written: ctx.trend_rows,
    // Prompt changes are never applied automatically - this is the hand-off.
    action_required: (ctx.learning.recommendations || []).length
      ? `Review ${ctx.learning.recommendations.length} prompt recommendation(s) and activate ${ctx.learning.proposed_prompt_version} if you agree`
      : null,
    finished_at: new Date().toISOString(),
  },
}];
""".strip()


def build() -> Workflow:
    wf = Workflow("09")

    wf.add("Trigger: Weekly Learning", T_SCHEDULE, pos(0, 0),
           {"rule": {"interval": [{"field": "cronExpression", "expression": "0 4 * * 1"}]}},
           notes="Monday 04:00. Learning needs a week of traffic to say anything useful.")
    wf.add("Receive Learning Request", T_EXEC_TRIGGER, pos(0, 2),
           {"inputSource": "passthrough"},
           notes="Also callable on demand from 01 or by hand.")
    wf.add("Prompt Library", T_CODE, pos(1, 1), code(library_js(["learning_ai", "ab_test_ai"])),
           notes="Versioned prompts for the Learning and A/B Test agents.")
    wf.add("Normalize Learning Input", T_CODE, pos(2, 1), code(JS_NORMALIZE),
           notes="Resolves the measurement window (default 30 days).")

    wf.add("Postgres: Load Active Listings", T_POSTGRES, pos(3, 1),
           {
               "operation": "executeQuery",
               "query": SQL_ACTIVE_LISTINGS,
               "options": {"queryReplacement": "={{ [String($json.window_days)] }}"},
           },
           notes="Every completed product with a live Etsy listing id inside the window.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)

    wf.add("Etsy: Get Shop Receipts", T_HTTP, pos(4, 1),
           etsy_http("GET",
                     "={{ $env.ETSY_API_BASE }}/v3/application/shops/{{ $env.ETSY_SHOP_ID }}"
                     "/receipts?limit=100&was_paid=true"),
           notes="Section 17. One shop-wide call instead of one call per listing.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("Aggregate Receipts", T_CODE, pos(5, 1), code(JS_AGGREGATE_RECEIPTS),
           notes="Folds transactions into sales and revenue per listing id.")

    wf.add("Split: Listings", T_CODE, pos(6, 1), code(JS_SPLIT_LISTINGS),
           notes="One item per listing for the stats loop.")
    wf.add("Loop: Listings", T_LOOP, pos(7, 1), loop_node(1),
           notes="Sequential so the Etsy rate limit is never approached.")
    wf.add("Etsy: Get Listing Stats", T_HTTP, pos(8, 2),
           etsy_http("GET",
                     "={{ $env.ETSY_API_BASE }}/v3/application/listings/{{ $json.listing_id }}"),
           notes="Views and favourites for one listing.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("Parse Listing Stats", T_CODE, pos(9, 2), code(JS_PARSE_LISTING_STATS),
           notes=("Combines listing views/favourites with the receipt-derived sales. "
                  "Etsy exposes no click metric here, so favourites stand in and are labelled."))
    wf.add("Collect Sales Data", T_CODE, pos(8, 1), code(JS_COLLECT_SALES),
           notes="Packs every measured listing into one array for a single bulk upsert.")

    wf.add("Postgres: Upsert Sales", T_POSTGRES, pos(9, 1),
           {
               "operation": "executeQuery",
               "query": SQL_UPSERT_SALES,
               "options": {"queryReplacement": "={{ [$json.rows_json] }}"},
           },
           notes="Section 17 + 22. One snapshot row per listing per collection run.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)

    wf.add("Postgres: Load Performance", T_POSTGRES, pos(10, 1),
           {
               "operation": "executeQuery",
               "query": SQL_PERFORMANCE,
               "options": {"queryReplacement": (
                   "={{ [String($('Normalize Learning Input').first().json.window_days)] }}"
               )},
           },
           notes="Category / marketplace / prompt performance, winners, losers, running A/B tests.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("Evaluate A/B Tests", T_CODE, pos(11, 1), code(JS_EVALUATE_AB),
           notes=("Section 21. A test is only called with enough views per arm and a lift "
                  "outside the noise band."))

    wf.add("Build Learning Prompt", T_CODE, pos(12, 1), code(JS_BUILD_LEARNING_PROMPT),
           notes="Renders the Learning AI template with the measured numbers.")
    wf.add("OpenAI: Learning AI", T_HTTP, pos(13, 1),
           openai_chat(
               "($('Prompt Library').first().json.prompts.learning_ai.system + "
               "'\\n\\nOUTPUT CONTRACT (return exactly this JSON shape):\\n' + "
               "$('Prompt Library').first().json.prompts.learning_ai.output_contract)",
               "$json.learning_user_prompt", temperature=0.3, max_tokens=3000),
           notes="Agent 10/13. Proposes concrete prompt edits grounded in the numbers.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("Parse Learning Report", T_CODE, pos(14, 1), code(JS_PARSE_LEARNING),
           notes=("Section 15. Recommendations are discarded when the sample is too small - "
                  "a confident answer off 3 products is worse than no answer."))

    wf.add("Postgres: Update Prompt Stats", T_POSTGRES, pos(15, 1),
           {
               "operation": "executeQuery",
               "query": SQL_UPDATE_PROMPT_STATS,
               "options": {"queryReplacement": (
                   "={{ [String($json.window_days), $json.learning.proposed_prompt_version || '', "
                   "JSON.stringify($json.learning.recommendations || []).slice(0, 4000)] }}"
               )},
           },
           notes=("Section 15. Scores the version that shipped and registers any successor "
                  "as INACTIVE - a human activates it."),
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)

    wf.add("Build Trend Rows", T_CODE, pos(16, 1), code(JS_BUILD_TRENDS),
           notes="Section 16. Converts this window's performance into monthly trend rows.")
    wf.add("Postgres: Upsert Trends", T_POSTGRES, pos(17, 1),
           {
               "operation": "executeQuery",
               "query": SQL_UPSERT_TRENDS,
               "options": {"queryReplacement": "={{ [$json.rows_json] }}"},
           },
           notes="Section 16. Trend memory, accumulating sales per keyword per month.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)

    wf.add("Check: Start A/B Test", T_IF, pos(18, 1),
           if_bool("={{ $json.start_new_ab_test }}"),
           notes="Only start a new test when one concluded or the report asked for one.")
    wf.add("Decide A/B Test", T_CODE, pos(17, 2), code(JS_CHECK_AB),
           notes="Section 21. Picks the element and the control listing to challenge.")
    wf.add("Build AB Test Prompt", T_CODE, pos(19, 0), code(JS_BUILD_AB_PROMPT),
           notes="Renders the A/B Test AI template for the chosen element.")
    wf.add("OpenAI: A/B Test AI", T_HTTP, pos(20, 0),
           openai_chat(
               "($('Prompt Library').first().json.prompts.ab_test_ai.system + "
               "'\\n\\nOUTPUT CONTRACT (return exactly this JSON shape):\\n' + "
               "$('Prompt Library').first().json.prompts.ab_test_ai.output_contract)",
               "$json.ab_user_prompt", temperature=0.8, max_tokens=1200),
           notes="Agent 11/13. Writes the challenger variant, changing exactly one thing.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("Parse AB Variant", T_CODE, pos(21, 0), code(JS_PARSE_AB),
           notes="Builds both arms so the next run compares like with like.")
    wf.add("Postgres: Save AB Test", T_POSTGRES, pos(22, 0),
           {
               "operation": "executeQuery",
               "query": SQL_SAVE_AB,
               "options": {"queryReplacement": "={{ [$json.rows_json] }}"},
           },
           notes="Section 21. Registers variant A and B as running.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("Skip A/B Test", T_CODE, pos(19, 2), code(JS_SKIP_AB),
           notes="Records why no test was started this cycle.")

    wf.add("Build Learning Report", T_CODE, pos(23, 1), code(JS_BUILD_REPORT),
           notes="Section 14. The cycle report, including the human action required.")
    wf.add("Return: Learning Report", T_NOOP, pos(24, 1), {},
           notes="Terminal node - its item is the sub-workflow return value.")

    # -- wiring ------------------------------------------------------------
    wf.link("Trigger: Weekly Learning", "Prompt Library")
    wf.link("Receive Learning Request", "Prompt Library")
    wf.chain("Prompt Library", "Normalize Learning Input", "Postgres: Load Active Listings",
             "Etsy: Get Shop Receipts", "Aggregate Receipts", "Split: Listings",
             "Loop: Listings")
    wf.link("Loop: Listings", "Collect Sales Data", 0)
    wf.link("Loop: Listings", "Etsy: Get Listing Stats", 1)
    wf.link("Etsy: Get Listing Stats", "Parse Listing Stats")
    wf.link("Parse Listing Stats", "Loop: Listings")

    wf.chain("Collect Sales Data", "Postgres: Upsert Sales", "Postgres: Load Performance",
             "Evaluate A/B Tests", "Build Learning Prompt", "OpenAI: Learning AI",
             "Parse Learning Report", "Postgres: Update Prompt Stats",
             "Build Trend Rows", "Postgres: Upsert Trends", "Decide A/B Test",
             "Check: Start A/B Test")
    wf.link("Check: Start A/B Test", "Build AB Test Prompt", 0)
    wf.link("Check: Start A/B Test", "Skip A/B Test", 1)
    wf.chain("Build AB Test Prompt", "OpenAI: A/B Test AI", "Parse AB Variant",
             "Postgres: Save AB Test", "Build Learning Report")
    wf.link("Skip A/B Test", "Build Learning Report")
    wf.link("Build Learning Report", "Return: Learning Report")

    return wf
