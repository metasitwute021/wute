"""10 Dashboard - V2 section 19.

A webhook that answers "what is this factory doing right now" in one page:
queue, output, cost, budget, ROI, sales, errors, factory status, trend status.

    GET /webhook/adpf-dashboard             -> HTML page
    GET /webhook/adpf-dashboard?format=json -> the same numbers as JSON

All figures come from one SQL round trip; the page is static HTML with no
external assets, so it renders inside a corporate network or an iframe.
"""

from common import (
    RETRY, T_CODE, T_IF, T_NOOP, T_POSTGRES, T_RESPOND, T_WEBHOOK, Workflow,
    code, if_bool, pos,
)

SQL_DASHBOARD = """
-- Everything the dashboard shows, in one query. Each CTE answers exactly one
-- card, which keeps the query readable and each number traceable.
WITH today AS (SELECT current_date AS d, to_char(now(), 'YYYY-MM') AS m),
queue AS (
  SELECT count(*)::int AS waiting,
         count(*) FILTER (WHERE stage = 'top5')::int AS ready_to_build
  FROM adpf_ideas WHERE stage IN ('top5', 'top20')
),
ideas AS (
  SELECT count(*)::int AS total,
         count(*) FILTER (WHERE created_at >= (SELECT d FROM today))::int AS today,
         count(*) FILTER (WHERE stage = 'rejected')::int AS rejected,
         round(avg(final_score)::numeric, 1) AS avg_score
  FROM adpf_ideas
),
products AS (
  SELECT count(*)::int AS total,
         count(*) FILTER (WHERE status = 'completed')::int AS completed,
         count(*) FILTER (WHERE status = 'failed')::int AS failed,
         count(*) FILTER (WHERE status = 'running')::int AS running,
         count(*) FILTER (WHERE etsy_listing_id IS NOT NULL)::int AS uploaded,
         count(*) FILTER (WHERE created_at >= (SELECT d FROM today))::int AS today
  FROM adpf_products
),
cost AS (
  SELECT round(COALESCE(sum(cost_usd), 0)::numeric, 2) AS total_usd,
         round(COALESCE(sum(cost_usd) FILTER (WHERE created_at >= (SELECT d FROM today)), 0)::numeric, 2) AS today_usd,
         round(COALESCE(sum(cost_usd) FILTER (WHERE kind = 'image'), 0)::numeric, 2) AS image_usd,
         round(COALESCE(sum(cost_usd) FILTER (WHERE kind = 'chat'), 0)::numeric, 2) AS chat_usd
  FROM adpf_costs
),
budget AS (
  SELECT
    (SELECT limit_usd FROM adpf_budget WHERE scope = 'daily'
       AND period_key = to_char((SELECT d FROM today), 'YYYY-MM-DD')) AS daily_limit,
    (SELECT spent_usd FROM adpf_budget WHERE scope = 'daily'
       AND period_key = to_char((SELECT d FROM today), 'YYYY-MM-DD')) AS daily_spent,
    (SELECT limit_usd FROM adpf_budget WHERE scope = 'monthly'
       AND period_key = (SELECT m FROM today)) AS monthly_limit,
    (SELECT spent_usd FROM adpf_budget WHERE scope = 'monthly'
       AND period_key = (SELECT m FROM today)) AS monthly_spent
),
roi AS (
  SELECT round(COALESCE(sum(revenue_usd), 0)::numeric, 2) AS revenue_usd,
         round(COALESCE(sum(api_cost_usd), 0)::numeric, 2) AS cost_usd,
         round(COALESCE(sum(profit_usd), 0)::numeric, 2)  AS profit_usd,
         round(avg(roi_pct)::numeric, 1) AS avg_roi_pct,
         count(*) FILTER (WHERE profit_usd > 0)::int AS profitable
  FROM adpf_products WHERE api_cost_usd > 0
),
sales AS (
  SELECT COALESCE(sum(s.sales), 0)::int AS sales,
         COALESCE(sum(s.views), 0)::int AS views,
         COALESCE(sum(s.favorites), 0)::int AS favorites,
         round(COALESCE(sum(s.revenue_usd), 0)::numeric, 2) AS revenue_usd
  FROM (
    SELECT DISTINCT ON (marketplace, listing_id) *
    FROM adpf_sales ORDER BY marketplace, listing_id, collected_at DESC
  ) s
),
errors AS (
  SELECT count(*)::int AS total,
         count(*) FILTER (WHERE created_at >= (SELECT d FROM today))::int AS today
  FROM adpf_events WHERE level = 'error'
),
recent_errors AS (
  SELECT run_id, op, left(message, 160) AS message, created_at
  FROM adpf_events WHERE level = 'error' ORDER BY created_at DESC LIMIT 8
),
factories AS (
  SELECT COALESCE(p.factory, 'unknown') AS factory,
         count(*)::int AS products,
         count(*) FILTER (WHERE p.status = 'completed')::int AS completed,
         count(*) FILTER (WHERE p.status = 'failed')::int AS failed,
         max(p.created_at) AS last_run,
         COALESCE(max(t.priority), 3) AS priority
  FROM adpf_products p
  LEFT JOIN adpf_category_targets t ON t.factory = p.factory
  GROUP BY 1 ORDER BY products DESC
),
categories AS (
  SELECT t.category, t.target_pct, t.priority,
         COALESCE(c.products, 0)::int AS products,
         CASE WHEN (SELECT total FROM products) > 0
              THEN round((COALESCE(c.products, 0)::numeric / (SELECT total FROM products)) * 100, 1)
              ELSE 0 END AS actual_pct
  FROM adpf_category_targets t
  LEFT JOIN (SELECT category, count(*) AS products FROM adpf_products GROUP BY 1) c
    ON c.category = t.category
  ORDER BY t.target_pct DESC
),
trends AS (
  SELECT keyword, category, period_key, demand_score, trend_score, sales
  FROM adpf_trends ORDER BY observed_at DESC, trend_score DESC LIMIT 10
),
ab AS (
  SELECT test_uid, element, variant, views, sales, status
  FROM adpf_ab_tests WHERE status = 'running' ORDER BY started_at DESC LIMIT 10
)
SELECT
  (SELECT row_to_json(queue)    FROM queue)    AS queue,
  (SELECT row_to_json(ideas)    FROM ideas)    AS ideas,
  (SELECT row_to_json(products) FROM products) AS products,
  (SELECT row_to_json(cost)     FROM cost)     AS cost,
  (SELECT row_to_json(budget)   FROM budget)   AS budget,
  (SELECT row_to_json(roi)      FROM roi)      AS roi,
  (SELECT row_to_json(sales)    FROM sales)    AS sales,
  (SELECT row_to_json(errors)   FROM errors)   AS errors,
  COALESCE((SELECT json_agg(row_to_json(recent_errors)) FROM recent_errors), '[]'::json) AS recent_errors,
  COALESCE((SELECT json_agg(row_to_json(factories))     FROM factories), '[]'::json)     AS factories,
  COALESCE((SELECT json_agg(row_to_json(categories))    FROM categories), '[]'::json)    AS categories,
  COALESCE((SELECT json_agg(row_to_json(trends))        FROM trends), '[]'::json)        AS trends,
  COALESCE((SELECT json_agg(row_to_json(ab))            FROM ab), '[]'::json)            AS ab_tests;
""".strip()

JS_BUILD_DATA = r"""
// Normalise the single dashboard row. Every value gets a safe default so an
// empty database renders a zeroed page instead of an error.
const query = $('Trigger: Dashboard Webhook').first().json.query || {};
const row = $input.first().json || {};

const obj = (value, fallback) => {
  if (!value) return fallback;
  if (typeof value === 'string') { try { return JSON.parse(value); } catch (e) { return fallback; } }
  return value;
};
const arr = (value) => {
  const parsed = obj(value, []);
  return Array.isArray(parsed) ? parsed : [];
};
const num = (value) => (value === null || value === undefined ? 0 : Number(value));

const budget = obj(row.budget, {});
const dailyLimit = num(budget.daily_limit) || Number($env.BUDGET_DAILY_USD || 20);
const monthlyLimit = num(budget.monthly_limit) || Number($env.BUDGET_MONTHLY_USD || 300);
const dailySpent = num(budget.daily_spent);
const monthlySpent = num(budget.monthly_spent);

const products = obj(row.products, {});
const errors = obj(row.errors, {});
const completed = num(products.completed);
const failed = num(products.failed);
const attempts = completed + failed;

const data = {
  generated_at: new Date().toISOString(),
  format: String(query.format || 'html').toLowerCase(),
  queue: obj(row.queue, { waiting: 0, ready_to_build: 0 }),
  ideas: obj(row.ideas, { total: 0, today: 0, rejected: 0, avg_score: 0 }),
  products: {
    total: num(products.total), completed, failed,
    running: num(products.running), uploaded: num(products.uploaded),
    today: num(products.today),
    success_rate: attempts ? Math.round((completed / attempts) * 1000) / 10 : null,
  },
  cost: obj(row.cost, { total_usd: 0, today_usd: 0, image_usd: 0, chat_usd: 0 }),
  budget: {
    daily_limit_usd: dailyLimit, daily_spent_usd: dailySpent,
    daily_remaining_usd: Math.round((dailyLimit - dailySpent) * 100) / 100,
    daily_used_pct: dailyLimit ? Math.round((dailySpent / dailyLimit) * 1000) / 10 : 0,
    monthly_limit_usd: monthlyLimit, monthly_spent_usd: monthlySpent,
    monthly_remaining_usd: Math.round((monthlyLimit - monthlySpent) * 100) / 100,
    monthly_used_pct: monthlyLimit ? Math.round((monthlySpent / monthlyLimit) * 1000) / 10 : 0,
  },
  roi: obj(row.roi, { revenue_usd: 0, cost_usd: 0, profit_usd: 0, avg_roi_pct: null, profitable: 0 }),
  sales: obj(row.sales, { sales: 0, views: 0, favorites: 0, revenue_usd: 0 }),
  errors: { total: num(errors.total), today: num(errors.today) },
  recent_errors: arr(row.recent_errors),
  factories: arr(row.factories),
  categories: arr(row.categories),
  trends: arr(row.trends),
  ab_tests: arr(row.ab_tests),
};

// Traffic light for the whole factory, so the page answers "is it healthy"
// before anyone reads a single number.
const budgetTight = data.budget.daily_used_pct >= 90 || data.budget.monthly_used_pct >= 90;
data.status = data.errors.today > 3 || budgetTight ? 'attention'
  : (data.products.running > 0 ? 'running' : 'idle');
data.status_reason = data.errors.today > 3 ? `${data.errors.today} errors today`
  : (budgetTight ? 'budget nearly exhausted' : null);

return [{ json: data }];
""".strip()

JS_RENDER_HTML = r"""
// Self-contained HTML: no CDN, no fonts, no scripts fetched from anywhere.
// It renders identically inside a locked-down network or an iframe.
const d = $input.first().json;

const esc = (value) => String(value === null || value === undefined ? '' : value)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const money = (n) => `$${Number(n || 0).toFixed(2)}`;
const int = (n) => Number(n || 0).toLocaleString('en-US');
const pct = (n) => (n === null || n === undefined ? '-' : `${Number(n).toFixed(1)}%`);

const card = (label, value, sub, tone) => `
  <div class="card${tone ? ' ' + tone : ''}">
    <div class="label">${esc(label)}</div>
    <div class="value">${value}</div>
    ${sub ? `<div class="sub">${sub}</div>` : ''}
  </div>`;

const bar = (usedPct, tone) => `
  <div class="bar"><span class="${tone}" style="width:${Math.min(100, Math.max(0, usedPct))}%"></span></div>`;

const table = (headers, rows) => `
  <div class="scroll"><table>
    <thead><tr>${headers.map((h) => `<th>${esc(h)}</th>`).join('')}</tr></thead>
    <tbody>${rows.length
      ? rows.map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join('')}</tr>`).join('')
      : `<tr><td colspan="${headers.length}" class="empty">no data yet</td></tr>`}
    </tbody>
  </table></div>`;

const stars = (priority) => '*'.repeat(Math.max(1, Math.min(5, Number(priority) || 3)));

const budgetTone = (used) => (used >= 90 ? 'bad' : used >= 70 ? 'warn' : 'good');

const html = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AI Digital Product Factory - Dashboard</title>
<style>
  :root{--bg:#f6f8fa;--panel:#fff;--ink:#1b1f24;--muted:#6b7580;--line:#e3e8ee;
        --good:#2f855a;--warn:#b7791f;--bad:#c53030;--accent:#2f6f4f}
  @media (prefers-color-scheme:dark){
    :root{--bg:#14181d;--panel:#1c2229;--ink:#e6edf3;--muted:#9aa5b1;--line:#2b333c;
          --good:#68d391;--warn:#f6ad55;--bad:#fc8181;--accent:#68d391}}
  *{box-sizing:border-box}
  body{margin:0;padding:24px;background:var(--bg);color:var(--ink);
       font:14px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
  header{display:flex;flex-wrap:wrap;gap:12px;align-items:baseline;
         justify-content:space-between;margin-bottom:20px}
  h1{font-size:20px;margin:0}
  h2{font-size:15px;margin:28px 0 10px;color:var(--muted);
     text-transform:uppercase;letter-spacing:.06em}
  .pill{padding:3px 10px;border-radius:999px;font-size:12px;font-weight:600}
  .pill.running{background:rgba(47,133,90,.15);color:var(--good)}
  .pill.idle{background:rgba(107,117,128,.15);color:var(--muted)}
  .pill.attention{background:rgba(197,48,48,.15);color:var(--bad)}
  .grid{display:grid;gap:12px;grid-template-columns:repeat(auto-fit,minmax(170px,1fr))}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px}
  .card.bad{border-color:var(--bad)} .card.warn{border-color:var(--warn)}
  .label{font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted)}
  .value{font-size:24px;font-weight:650;margin-top:4px;font-variant-numeric:tabular-nums}
  .sub{font-size:12px;color:var(--muted);margin-top:4px}
  .bar{height:6px;border-radius:3px;background:var(--line);overflow:hidden;margin-top:8px}
  .bar span{display:block;height:100%}
  .bar .good{background:var(--good)} .bar .warn{background:var(--warn)} .bar .bad{background:var(--bad)}
  .scroll{overflow-x:auto;background:var(--panel);border:1px solid var(--line);border-radius:10px}
  table{width:100%;border-collapse:collapse;font-size:13px}
  th,td{padding:8px 12px;text-align:left;border-bottom:1px solid var(--line);white-space:nowrap}
  th{font-size:11px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted)}
  tr:last-child td{border-bottom:0}
  td.empty{color:var(--muted);text-align:center;white-space:normal}
  .num{text-align:right;font-variant-numeric:tabular-nums}
  footer{margin-top:28px;font-size:12px;color:var(--muted)}
</style></head><body>

<header>
  <h1>AI Digital Product Factory</h1>
  <div>
    <span class="pill ${d.status}">${esc(d.status)}${d.status_reason ? ' - ' + esc(d.status_reason) : ''}</span>
  </div>
</header>

<h2>Pipeline</h2>
<div class="grid">
  ${card('Queue', int(d.queue.ready_to_build), `${int(d.queue.waiting)} ideas shortlisted`)}
  ${card('Ideas generated', int(d.ideas.total), `${int(d.ideas.today)} today · avg score ${d.ideas.avg_score ?? '-'}`)}
  ${card('Products created', int(d.products.completed), `${int(d.products.today)} today · ${int(d.products.running)} running`)}
  ${card('Uploaded to Etsy', int(d.products.uploaded), `success rate ${pct(d.products.success_rate)}`)}
  ${card('Errors', int(d.errors.today), `${int(d.errors.total)} all time`, d.errors.today > 3 ? 'bad' : '')}
</div>

<h2>Money</h2>
<div class="grid">
  ${card('API cost today', money(d.cost.today_usd), `${money(d.cost.total_usd)} all time`)}
  ${card('Daily budget', money(d.budget.daily_remaining_usd) + ' left',
         `${money(d.budget.daily_spent_usd)} of ${money(d.budget.daily_limit_usd)}` +
         bar(d.budget.daily_used_pct, budgetTone(d.budget.daily_used_pct)),
         d.budget.daily_used_pct >= 90 ? 'bad' : d.budget.daily_used_pct >= 70 ? 'warn' : '')}
  ${card('Monthly budget', money(d.budget.monthly_remaining_usd) + ' left',
         `${money(d.budget.monthly_spent_usd)} of ${money(d.budget.monthly_limit_usd)}` +
         bar(d.budget.monthly_used_pct, budgetTone(d.budget.monthly_used_pct)),
         d.budget.monthly_used_pct >= 90 ? 'bad' : d.budget.monthly_used_pct >= 70 ? 'warn' : '')}
  ${card('Revenue', money(d.roi.revenue_usd), `${int(d.sales.sales)} sales · ${int(d.sales.views)} views`)}
  ${card('Profit', money(d.roi.profit_usd), `ROI ${pct(d.roi.avg_roi_pct)} · ${int(d.roi.profitable)} profitable`,
         Number(d.roi.profit_usd) < 0 ? 'bad' : '')}
  ${card('Cost split', money(d.cost.image_usd) + ' img', `${money(d.cost.chat_usd)} chat`)}
</div>

<h2>Factory status</h2>
${table(['Factory', 'Priority', 'Products', 'Completed', 'Failed', 'Last run'],
  d.factories.map((f) => [
    esc(f.factory), stars(f.priority),
    `<span class="num">${int(f.products)}</span>`,
    `<span class="num">${int(f.completed)}</span>`,
    `<span class="num">${int(f.failed)}</span>`,
    esc(String(f.last_run || '').slice(0, 16).replace('T', ' ')),
  ]))}

<h2>Category balance</h2>
${table(['Category', 'Target', 'Actual', 'Products', 'Gap'],
  d.categories.map((c) => {
    const gap = Number(c.target_pct) - Number(c.actual_pct);
    const tone = gap > 5 ? 'good' : gap < -5 ? 'bad' : '';
    return [
      esc(c.category), pct(c.target_pct), pct(c.actual_pct),
      `<span class="num">${int(c.products)}</span>`,
      `<span class="num" style="color:var(--${tone || 'muted'})">${gap > 0 ? '+' : ''}${gap.toFixed(1)}%</span>`,
    ];
  }))}

<h2>Trend memory</h2>
${table(['Keyword', 'Period', 'Demand', 'Trend', 'Sales'],
  d.trends.map((t) => [
    esc(t.keyword), esc(t.period_key),
    `<span class="num">${Number(t.demand_score || 0).toFixed(0)}</span>`,
    `<span class="num">${Number(t.trend_score || 0).toFixed(0)}</span>`,
    `<span class="num">${int(t.sales)}</span>`,
  ]))}

<h2>Running A/B tests</h2>
${table(['Test', 'Element', 'Variant', 'Views', 'Sales'],
  d.ab_tests.map((t) => [
    esc(t.test_uid), esc(t.element), esc(t.variant),
    `<span class="num">${int(t.views)}</span>`,
    `<span class="num">${int(t.sales)}</span>`,
  ]))}

<h2>Recent errors</h2>
${table(['When', 'Run', 'Stage', 'Message'],
  d.recent_errors.map((e) => [
    esc(String(e.created_at || '').slice(0, 16).replace('T', ' ')),
    esc(e.run_id), esc(e.op), esc(e.message),
  ]))}

<footer>Generated ${esc(d.generated_at)} · add <code>?format=json</code> for the raw numbers</footer>
</body></html>`;

return [{ json: { html, ...d } }];
""".strip()


def build() -> Workflow:
    wf = Workflow("10")

    wf.add("Trigger: Dashboard Webhook", T_WEBHOOK, pos(0, 1),
           {
               "httpMethod": "GET",
               "path": "adpf-dashboard",
               "responseMode": "responseNode",
               "options": {},
           },
           notes=("GET /webhook/adpf-dashboard. Put a Header Auth credential on this node "
                  "before exposing it - it reveals cost and revenue."))
    wf.add("Postgres: Load Dashboard Metrics", T_POSTGRES, pos(1, 1),
           {"operation": "executeQuery", "query": SQL_DASHBOARD, "options": {}},
           notes="Section 19. Every card on the page comes from this single round trip.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("Build Dashboard Data", T_CODE, pos(2, 1), code(JS_BUILD_DATA),
           notes=("Safe defaults everywhere, so an empty database renders a zeroed page "
                  "instead of an error. Also derives the overall traffic light."))
    wf.add("Check: JSON Requested", T_IF, pos(3, 1),
           if_bool("={{ $json.format === 'json' }}"),
           notes="?format=json returns the numbers; anything else returns the page.")
    wf.add("Render Dashboard HTML", T_CODE, pos(4, 2), code(JS_RENDER_HTML),
           notes="Self-contained HTML: no CDN, no external fonts, light and dark aware.")
    wf.add("Respond: Dashboard HTML", T_RESPOND, pos(5, 2),
           {
               "respondWith": "text",
               "responseBody": "={{ $json.html }}",
               "options": {"responseHeaders": {"entries": [
                   {"name": "content-type", "value": "text/html; charset=utf-8"},
                   {"name": "cache-control", "value": "no-store"},
               ]}},
           },
           notes="Returns the rendered page to the browser.")
    wf.add("Respond: Dashboard JSON", T_RESPOND, pos(5, 0),
           {
               "respondWith": "json",
               "responseBody": "={{ JSON.stringify($json) }}",
               "options": {},
           },
           notes="Machine-readable output for monitoring or another dashboard.")
    wf.add("Dashboard Served", T_NOOP, pos(6, 1), {},
           notes="Terminal node - keeps both response branches on one canvas end point.")

    wf.chain("Trigger: Dashboard Webhook", "Postgres: Load Dashboard Metrics",
             "Build Dashboard Data", "Check: JSON Requested")
    wf.link("Check: JSON Requested", "Respond: Dashboard JSON", 0)
    wf.link("Check: JSON Requested", "Render Dashboard HTML", 1)
    wf.link("Render Dashboard HTML", "Respond: Dashboard HTML")
    wf.link("Respond: Dashboard HTML", "Dashboard Served")
    wf.link("Respond: Dashboard JSON", "Dashboard Served")

    return wf
