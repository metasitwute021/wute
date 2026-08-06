"""07 Idea Factory - V2 sections 1-6.

Generates 100-500 ideas, scores them deterministically, checks them against
what the shop already sells, applies portfolio diversity, and funnels
500 -> 50 -> 20 -> 5.

Design decision: the model GENERATES ideas and estimates raw market signals.
Every score is then computed in code. A model that both invents and ranks its
own ideas cannot be audited, drifts between runs, and quietly rewards whatever
it happened to write first.
"""

from common import (
    AGENT_CONTENT_JS,
    ASARRAY_JS,
    RETRY, T_CODE, T_EXEC_TRIGGER, T_HTTP, T_IF, T_LOOP, T_NOOP, T_POSTGRES,
    Workflow, code, if_bool, loop_node, openai_chat, pos,
)
from prompts import RENDER_HELPER, library_js

# --------------------------------------------------------------------------
# Scoring weights. Kept in one place so a change is one diff and one number.
# --------------------------------------------------------------------------
WEIGHTS_JS = r"""
// Section 2 - Idea Score (0-100). Positive weights reward, negative punish.
const IDEA_WEIGHTS = {
  demand: 0.25,        // market demand
  competition: -0.20,  // crowded is bad
  trend: 0.15,
  seo: 0.15,           // seo potential
  profit: 0.20,        // profit potential
  production: -0.05,   // estimated production cost
  difficulty: -0.10,
  evergreen: 0.10,     // evergreen value
};

// Section 5 - Final Score. Portfolio effects are applied on top of Idea Score.
const FINAL_WEIGHTS = {
  idea: 0.70,
  diversity: 0.20,     // section 4 bonus for under-represented categories
  saturation: -0.25,   // section 3 penalty for crowded shelves
};
"""

JS_NORMALIZE = r"""
// Entry point. target_count is clamped to the 100-500 band the spec requires.
const ctx = $input.first().json;
const research = ctx.research || {};

if (!research.keyword) {
  throw new Error('07 Idea Factory requires a research package');
}

const requested = Number(ctx.idea_count || $env.IDEA_TARGET_COUNT || 200);
const target = Math.max(100, Math.min(500, Math.round(requested)));
// Batch size is capped at 40 by the token budget, not by taste. A free-tier
// quota counts requests per minute, so eight small batches trip it where
// three large ones do not - and 8000 output tokens covers 40 ideas.
const batchSize = Math.max(10, Math.min(40, Number($env.IDEA_BATCH_SIZE || 40)));

return [{
  json: {
    run_id: ctx.run_id,
    factory: ctx.factory,
    factory_locked: ctx.factory_locked === true,
    prompt_version: ctx.prompt_version || $env.PROMPT_VERSION || 'v1.0.0',
    dry_run: ctx.dry_run === true,
    research,
    market: ctx.market || {},
    target_count: target,
    batch_size: batchSize,
    batch_count: Math.ceil(target / batchSize),
    started_at: new Date().toISOString(),
  },
}];
""".strip()

SQL_INVENTORY = """
-- Section 3 Inventory Checker: everything the shop already holds, in one round
-- trip. Counts drive saturation, the title/keyword lists drive de-duplication.
WITH totals AS (
  SELECT count(*)::int AS total FROM adpf_products WHERE status <> 'failed'
),
per_category AS (
  SELECT COALESCE(category, 'Uncategorised') AS category,
         count(*)::int AS products,
         COALESCE(sum(sales_count), 0)::int AS sales
  FROM (
    SELECT p.category, p.run_id,
           COALESCE((SELECT max(s.sales) FROM adpf_sales s WHERE s.run_id = p.run_id), 0) AS sales_count
    FROM adpf_products p WHERE p.status <> 'failed'
  ) x GROUP BY 1
),
recent_titles AS (
  SELECT COALESCE(title_norm, lower(product_name)) AS title_norm,
         product_name, category, keyword_set
  FROM adpf_products
  WHERE product_name IS NOT NULL
  ORDER BY created_at DESC LIMIT 400
),
pending AS (
  SELECT title_norm, category FROM adpf_ideas
  WHERE stage IN ('top50','top20','top5') ORDER BY created_at DESC LIMIT 400
)
SELECT
  (SELECT total FROM totals) AS total_products,
  COALESCE((SELECT json_agg(row_to_json(per_category)) FROM per_category), '[]'::json) AS categories,
  COALESCE((SELECT json_agg(row_to_json(recent_titles)) FROM recent_titles), '[]'::json) AS existing,
  COALESCE((SELECT json_agg(row_to_json(pending)) FROM pending), '[]'::json) AS pending_ideas,
  COALESCE((SELECT json_agg(row_to_json(t)) FROM adpf_category_targets t), '[]'::json) AS targets;
""".strip()

JS_PARSE_INVENTORY = r"""
// Section 3 + 4: turn the inventory snapshot into saturation levels and the
// category shopping list the idea generator should aim at.
const ctx = $('Normalize Idea Input').first().json;
const row = $input.first().json || {};

const asArray = (value) => {
  if (Array.isArray(value)) return value;
  if (typeof value === 'string') { try { return JSON.parse(value); } catch (e) { return []; } }
  return value ? value : [];
};

const total = Number(row.total_products || 0);
const categories = asArray(row.categories);
const existing = asArray(row.existing);
const pending = asArray(row.pending_ideas);
const targets = asArray(row.targets);

const targetByCategory = new Map(targets.map((t) => [t.category, Number(t.target_pct)]));
const countByCategory = new Map(categories.map((c) => [c.category, Number(c.products)]));

// Actual vs target share, per category the shop cares about.
const balance = [];
const universe = new Set([...targetByCategory.keys(), ...countByCategory.keys()]);
for (const category of universe) {
  const count = countByCategory.get(category) || 0;
  const actualPct = total ? (count * 100) / total : 0;
  const targetPct = targetByCategory.has(category) ? targetByCategory.get(category) : 0;
  balance.push({
    category,
    products: count,
    actual_pct: Math.round(actualPct * 10) / 10,
    target_pct: targetPct,
    gap_pct: Math.round((targetPct - actualPct) * 10) / 10,
    // 0 = empty shelf, 1 = at target, >1 = overstocked
    saturation: targetPct > 0 ? actualPct / targetPct : (count ? 2 : 0),
  });
}
balance.sort((a, b) => b.gap_pct - a.gap_pct);

const wanted = balance.filter((b) => b.gap_pct > 2).map((b) => b.category);
const crowded = balance.filter((b) => b.saturation > 1.15).map((b) => b.category);

return [{
  json: {
    ...ctx,
    inventory: {
      total_products: total,
      balance,
      wanted_categories: wanted.length ? wanted : balance.slice(0, 3).map((b) => b.category),
      crowded_categories: crowded,
      existing_titles: existing.map((e) => e.title_norm).filter(Boolean),
      existing_records: existing,
      pending_titles: pending.map((p) => p.title_norm).filter(Boolean),
    },
  },
}];
""".strip()

JS_SPLIT_BATCHES = r"""
// One item per generation batch. Batching keeps each completion inside a sane
// token budget and means a single bad batch does not lose the whole pool.
const ctx = $input.first().json;
const batches = [];
let remaining = ctx.target_count;

for (let i = 0; i < ctx.batch_count; i += 1) {
  const size = Math.min(ctx.batch_size, remaining);
  remaining -= size;
  batches.push({
    batch_index: i + 1,
    batch_id: `${ctx.run_id}-b${String(i + 1).padStart(2, '0')}`,
    batch_size: size,
    dry_run: ctx.dry_run,
  });
}

return batches.filter((b) => b.batch_size > 0).map((json) => ({ json }));
""".strip()

JS_BUILD_BATCH_PROMPT = RENDER_HELPER + r"""
const ctx = $('Parse Inventory Snapshot').first().json;
const batch = $input.first().json;
const agent = $('Prompt Library').first().json.prompts.idea_generator_ai;

// Rotate the "avoid" list so later batches see the titles earlier batches made,
// which is what actually stops the model repeating itself across a 500-idea run.
let produced = [];
try {
  produced = $('Collect Raw Ideas').all().map((i) => i.json.title_norm);
} catch (e) {
  produced = [];
}

const avoid = [...ctx.inventory.existing_titles, ...ctx.inventory.pending_titles, ...produced]
  .slice(-180);

return [{
  json: {
    ...batch,
    idea_user_prompt: render(agent.user_template, {
      research_json: JSON.stringify(ctx.research, null, 2),
      market_json: JSON.stringify(ctx.market, null, 2),
      wanted_categories: ctx.inventory.wanted_categories.join(', ') || '(none - shop is balanced)',
      crowded_categories: ctx.inventory.crowded_categories.join(', ') || '(none)',
      existing_titles: avoid.join('\n') || '(none yet)',
      batch_size: batch.batch_size,
      batch_id: batch.batch_id,
    }),
  },
}];
""".rstrip()

JS_PARSE_BATCH = AGENT_CONTENT_JS + ASARRAY_JS +r"""

// Normalise one generated batch. A malformed batch is dropped, not fatal.
const FACTORIES = ['planner','printable','canva','wallart','resume','spreadsheet','kids','svg'];
const batch = $('Loop: Idea Batches').first().json;
const response = $input.first().json;

const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, Number(n) || 0));
const normTitle = (t) => String(t).toLowerCase().replace(/[^a-z0-9 ]/g, ' ')
  .replace(/\s+/g, ' ').trim();

let ideas = [];
try {
  const parsed = JSON.parse(agentContent(response) || '{}');
  ideas = Array.isArray(parsed.ideas) ? parsed.ideas : [];
} catch (e) {
  ideas = [];
}

const usage = response?.usage || {};

const rows = ideas
  .filter((idea) => idea && idea.title)
  .map((idea, index) => {
    const factory = FACTORIES.includes(String(idea.factory || '').toLowerCase())
      ? String(idea.factory).toLowerCase() : 'printable';
    const title = String(idea.title).replace(/\s+/g, ' ').trim().slice(0, 60);
    return {
      idea_uid: `${batch.batch_id}-${String(index + 1).padStart(3, '0')}`,
      batch_id: batch.batch_id,
      title,
      title_norm: normTitle(title),
      category: String(idea.category || 'Digital Downloads').slice(0, 80),
      factory,
      target_customer: String(idea.target_customer || '').slice(0, 300),
      keywords: asArray(idea.keywords).map((k) => String(k).toLowerCase().trim())
        .filter(Boolean).slice(0, 15),
      demand_score: clamp(idea.demand_score, 0, 100),
      competition_score: clamp(idea.competition_score, 0, 100),
      trend_score: clamp(idea.trend_score, 0, 100),
      seo_score: clamp(idea.seo_score, 0, 100),
      est_price_usd: Math.round(clamp(idea.est_price_usd, 1, 500) * 100) / 100,
      difficulty: ['easy','medium','hard'].includes(String(idea.difficulty).toLowerCase())
        ? String(idea.difficulty).toLowerCase() : 'medium',
      lifecycle: String(idea.lifecycle).toLowerCase() === 'seasonal' ? 'seasonal' : 'evergreen',
      angle: String(idea.angle || '').slice(0, 300),
      tokens_in: usage.prompt_tokens || 0,
      tokens_out: usage.completion_tokens || 0,
    };
  });

return rows.length ? rows.map((json) => ({ json })) : [{ json: { empty_batch: true, batch_id: batch.batch_id } }];
""".strip()

JS_PLACEHOLDER_BATCH = r"""
// dry_run: synthesise a batch locally so the funnel, scoring and database
// writes can be rehearsed without spending anything.
const batch = $input.first().json;
const ctx = $('Parse Inventory Snapshot').first().json;
const FACTORIES = ['planner','printable','canva','wallart','resume','spreadsheet','kids','svg'];
const base = ctx.research.keyword || 'printable';

return Array.from({ length: batch.batch_size }, (_, i) => {
  const factory = FACTORIES[i % FACTORIES.length];
  const title = `${base} ${factory} concept ${batch.batch_index}-${i + 1}`;
  return {
    json: {
      idea_uid: `${batch.batch_id}-${String(i + 1).padStart(3, '0')}`,
      batch_id: batch.batch_id,
      title,
      title_norm: title.toLowerCase(),
      category: ctx.research.category || 'Digital Downloads',
      factory,
      target_customer: ctx.research.target_customer || 'dry run',
      keywords: (ctx.research.sub_keywords || []).slice(0, 8),
      demand_score: 40 + ((i * 7) % 55),
      competition_score: 20 + ((i * 11) % 60),
      trend_score: 30 + ((i * 13) % 60),
      seo_score: 35 + ((i * 17) % 55),
      est_price_usd: 4 + (i % 12),
      difficulty: ['easy','medium','hard'][i % 3],
      lifecycle: i % 4 === 0 ? 'seasonal' : 'evergreen',
      angle: 'dry run placeholder',
      tokens_in: 0, tokens_out: 0, placeholder: true,
    },
  };
});
""".strip()

JS_COLLECT_IDEAS = r"""
// Merge every batch, drop exact duplicates produced across batches.
const items = $input.all().map((i) => i.json).filter((j) => j && j.title && !j.empty_batch);
const seen = new Set();
const unique = [];

for (const idea of items) {
  if (seen.has(idea.title_norm)) continue;
  seen.add(idea.title_norm);
  unique.push(idea);
}

if (!unique.length) throw new Error('Idea generation produced no usable ideas');
return unique.map((json) => ({ json }));
""".strip()

JS_SCORE_IDEAS = WEIGHTS_JS + r"""

// ---------------------------------------------------------------------------
// Sections 2-5: every score below is computed here, in code, from the raw
// signals the model estimated. Nothing about the ranking is left to the model.
// ---------------------------------------------------------------------------
const ctx = $('Parse Inventory Snapshot').first().json;
const ideas = $input.all().map((i) => i.json);
const inventory = ctx.inventory;

const DIFFICULTY_SCORE = { easy: 15, medium: 50, hard: 85 };

// Production cost model: image calls dominate, so cost tracks the factory.
const IMAGE_COUNT = {
  planner: 9, printable: 8, canva: 8, wallart: 11,
  resume: 6, spreadsheet: 7, kids: 13, svg: 9,
};
const IMAGE_UNIT_USD = Number($env.OPENAI_IMAGE_UNIT_COST_USD || 0.19);
const CHAT_RUN_USD = Number($env.OPENAI_CHAT_RUN_COST_USD || 0.12);

const saturationByCategory = new Map(
  inventory.balance.map((b) => [b.category, b])
);

// Token-set similarity against what the shop already has (section 13 support).
const tokenise = (text) => new Set(String(text).split(' ').filter((w) => w.length > 2));
const existingTokens = inventory.existing_records.map((r) => ({
  title_norm: r.title_norm || '',
  tokens: tokenise(r.title_norm || ''),
  category: r.category,
}));

const jaccard = (a, b) => {
  if (!a.size || !b.size) return 0;
  let shared = 0;
  for (const token of a) if (b.has(token)) shared += 1;
  return shared / (a.size + b.size - shared);
};

const scored = ideas.map((idea) => {
  const images = IMAGE_COUNT[idea.factory] || 8;
  const apiCost = Math.round((images * IMAGE_UNIT_USD + CHAT_RUN_USD) * 10000) / 10000;
  const profitUsd = Math.round((idea.est_price_usd - apiCost) * 100) / 100;
  const marginPct = idea.est_price_usd > 0
    ? Math.round((profitUsd / idea.est_price_usd) * 1000) / 10 : 0;

  // Profit potential on a 0-100 scale: $0 margin -> 0, $20 net -> 100.
  const profitScore = Math.max(0, Math.min(100, (profitUsd / 20) * 100));
  // Production cost on a 0-100 scale where 100 = expensive.
  const productionScore = Math.max(0, Math.min(100, (apiCost / 3) * 100));
  const difficultyScore = DIFFICULTY_SCORE[idea.difficulty] ?? 50;
  const evergreenScore = idea.lifecycle === 'evergreen' ? 100 : 45;

  // ---- Section 2: Idea Score -------------------------------------------
  const rawIdea =
    IDEA_WEIGHTS.demand * idea.demand_score +
    IDEA_WEIGHTS.competition * idea.competition_score +
    IDEA_WEIGHTS.trend * idea.trend_score +
    IDEA_WEIGHTS.seo * idea.seo_score +
    IDEA_WEIGHTS.profit * profitScore +
    IDEA_WEIGHTS.production * productionScore +
    IDEA_WEIGHTS.difficulty * difficultyScore +
    IDEA_WEIGHTS.evergreen * evergreenScore;

  // Weights sum to +0.85 / -0.35, so the raw range is -35..85. Map onto 0-100.
  const ideaScore = Math.max(0, Math.min(100, ((rawIdea + 35) / 120) * 100));

  // ---- Section 3: inventory saturation ---------------------------------
  const balance = saturationByCategory.get(idea.category);
  const saturation = balance ? balance.saturation : 0;
  // 0 when the shelf is empty, 100 when it is at double the target share.
  const saturationPenalty = Math.max(0, Math.min(100, saturation * 50));

  // ---- Section 4: diversity controller ---------------------------------
  // Reward a category that is below its target share, punish one above it.
  const gap = balance ? balance.gap_pct : 5;
  const diversityScore = Math.max(0, Math.min(100, 50 + gap * 4));

  // ---- Section 13 support: similarity to existing products -------------
  const tokens = tokenise(idea.title_norm);
  let similarity = 0;
  let similarTo = null;
  for (const existing of existingTokens) {
    const score = jaccard(tokens, existing.tokens);
    if (score > similarity) { similarity = score; similarTo = existing.title_norm; }
  }

  // ---- Section 5: Final Score ------------------------------------------
  const rawFinal =
    FINAL_WEIGHTS.idea * ideaScore +
    FINAL_WEIGHTS.diversity * diversityScore +
    FINAL_WEIGHTS.saturation * saturationPenalty;
  const finalScore = Math.max(0, Math.min(100, ((rawFinal + 25) / 115) * 100));

  const round = (n) => Math.round(n * 100) / 100;

  return {
    ...idea,
    profit_score: round(profitScore),
    difficulty_score: difficultyScore,
    evergreen_score: evergreenScore,
    production_score: round(productionScore),
    diversity_score: round(diversityScore),
    saturation_penalty: round(saturationPenalty),
    est_api_cost_usd: apiCost,
    est_profit_usd: profitUsd,
    est_margin_pct: marginPct,
    similarity_to_existing: round(similarity),
    similar_to: similarTo,
    idea_score: round(ideaScore),
    final_score: round(finalScore),
  };
});

scored.sort((a, b) => b.final_score - a.final_score);
return scored.map((json, index) => ({ json: { ...json, rank_in_batch: index + 1 } }));
""".lstrip()

JS_DUPLICATE_DETECTOR = r"""
// Section 13 Duplicate Detector. Two gates: similarity against what already
// exists, and similarity between the surviving ideas themselves.
const THRESHOLD = Number($env.DUPLICATE_SIMILARITY_THRESHOLD || 0.62);
const ideas = $input.all().map((i) => i.json);

const tokenise = (text) => new Set(String(text).split(' ').filter((w) => w.length > 2));
const jaccard = (a, b) => {
  if (!a.size || !b.size) return 0;
  let shared = 0;
  for (const token of a) if (b.has(token)) shared += 1;
  return shared / (a.size + b.size - shared);
};

const kept = [];
const keptTokens = [];

for (const idea of ideas) {
  if (idea.similarity_to_existing >= THRESHOLD) {
    idea.stage = 'rejected';
    idea.rejected_reason =
      `duplicate of existing product "${idea.similar_to}" (similarity ${idea.similarity_to_existing})`;
    kept.push(idea);
    continue;
  }

  const tokens = tokenise(idea.title_norm);
  let worst = 0;
  let against = null;
  for (let i = 0; i < keptTokens.length; i += 1) {
    const score = jaccard(tokens, keptTokens[i].tokens);
    if (score > worst) { worst = score; against = keptTokens[i].title; }
  }

  if (worst >= THRESHOLD) {
    idea.stage = 'rejected';
    idea.rejected_reason = `near-duplicate of "${against}" in this batch (similarity ${Math.round(worst * 100) / 100})`;
  } else {
    idea.stage = 'generated';
    keptTokens.push({ tokens, title: idea.title });
  }
  kept.push(idea);
}

return kept.map((json) => ({ json }));
""".strip()

JS_SELECT_FUNNEL = r"""
// Section 6: 500 -> 50 -> 20 -> 5.
// Each narrowing adds a constraint rather than just cutting deeper, otherwise
// the top 5 is always the same category.
const ctx = $('Parse Inventory Snapshot').first().json;
const all = $input.all().map((i) => i.json);
let alive = all.filter((idea) => idea.stage !== 'rejected')
  .sort((a, b) => b.final_score - a.final_score);

// A named factory is an instruction, not a hint. Ideas are generated across
// every factory and ranked on score alone, so without this the request is
// silently overruled - and the factories differ in cost, so being handed a
// 13-image kids pack when a 6-image resume kit was asked for doubles the bill.
// "auto" leaves the choice open, which is what the daily rotation wants.
let factory_override_reason = null;
if (ctx.factory_locked && ctx.factory) {
  const matching = alive.filter((idea) => idea.factory === ctx.factory);
  if (matching.length) {
    alive = matching;
  } else {
    factory_override_reason =
      `no idea scored for the requested factory "${ctx.factory}" - ` +
      'fell back to the whole pool';
  }
}

const stageOf = new Map();

// Top 50: pure score.
const top50 = alive.slice(0, 50);
top50.forEach((idea) => stageOf.set(idea.idea_uid, 'top50'));

// Top 20: at most 4 per category, so one hot niche cannot take the whole list.
const perCategory = new Map();
const top20 = [];
for (const idea of top50) {
  const count = perCategory.get(idea.category) || 0;
  if (count >= 4) continue;
  perCategory.set(idea.category, count + 1);
  top20.push(idea);
  if (top20.length === 20) break;
}
top20.forEach((idea) => stageOf.set(idea.idea_uid, 'top20'));

// Top 5: at most 2 per category, and at least one idea from a wanted category
// if one survived - this is where the Category Balancer actually bites.
const wanted = new Set(ctx.inventory.wanted_categories);
const perCategory5 = new Map();
const top5 = [];

const take = (idea) => {
  const count = perCategory5.get(idea.category) || 0;
  if (count >= 2) return false;
  if (top5.some((x) => x.idea_uid === idea.idea_uid)) return false;
  perCategory5.set(idea.category, count + 1);
  top5.push(idea);
  return true;
};

const wantedCandidate = top20.find((idea) => wanted.has(idea.category));
if (wantedCandidate) take(wantedCandidate);
for (const idea of top20) {
  if (top5.length === 5) break;
  take(idea);
}
top5.forEach((idea) => stageOf.set(idea.idea_uid, 'top5'));

const decorated = all.map((idea) => ({
  ...idea,
  stage: idea.stage === 'rejected' ? 'rejected' : (stageOf.get(idea.idea_uid) || 'generated'),
  factory_locked_to: ctx.factory_locked ? ctx.factory : null,
  factory_override_reason,
}));

return decorated.map((json) => ({ json }));
""".strip()

JS_BUILD_ROWS = r"""
// Flatten every idea into one JSON array for a single bulk insert. Inserting
// 500 rows one at a time would be 500 round trips.
const ideas = $input.all().map((i) => i.json);
const ctx = $('Parse Inventory Snapshot').first().json;

const rows = ideas.map((idea) => ({
  idea_uid: idea.idea_uid,
  run_id: ctx.run_id,
  batch_id: idea.batch_id,
  title: idea.title,
  title_norm: idea.title_norm,
  category: idea.category,
  factory: idea.factory,
  target_customer: idea.target_customer,
  keywords: (idea.keywords || []).join(','),
  demand_score: idea.demand_score,
  competition_score: idea.competition_score,
  trend_score: idea.trend_score,
  seo_score: idea.seo_score,
  profit_score: idea.profit_score,
  difficulty_score: idea.difficulty_score,
  evergreen_score: idea.evergreen_score,
  diversity_score: idea.diversity_score,
  saturation_penalty: idea.saturation_penalty,
  est_price_usd: idea.est_price_usd,
  est_api_cost_usd: idea.est_api_cost_usd,
  est_profit_usd: idea.est_profit_usd,
  est_margin_pct: idea.est_margin_pct,
  difficulty: idea.difficulty,
  lifecycle: idea.lifecycle,
  idea_score: idea.idea_score,
  final_score: idea.final_score,
  rank_in_batch: idea.rank_in_batch,
  stage: idea.stage,
  rejected_reason: idea.rejected_reason || null,
}));

return [{ json: { run_id: ctx.run_id, rows_json: JSON.stringify(rows), row_count: rows.length } }];
""".strip()

SQL_BULK_INSERT = """
-- One statement, any number of ideas: the rows arrive as a JSON array and are
-- expanded server side.
INSERT INTO adpf_ideas (
  idea_uid, run_id, batch_id, title, title_norm, category, factory,
  target_customer, keywords, demand_score, competition_score, trend_score,
  seo_score, profit_score, difficulty_score, evergreen_score, diversity_score,
  saturation_penalty, est_price_usd, est_api_cost_usd, est_profit_usd,
  est_margin_pct, difficulty, lifecycle, idea_score, final_score,
  rank_in_batch, stage, rejected_reason
)
SELECT
  x.idea_uid, x.run_id, x.batch_id, x.title, x.title_norm, x.category, x.factory,
  x.target_customer, x.keywords, x.demand_score, x.competition_score, x.trend_score,
  x.seo_score, x.profit_score, x.difficulty_score, x.evergreen_score, x.diversity_score,
  x.saturation_penalty, x.est_price_usd, x.est_api_cost_usd, x.est_profit_usd,
  x.est_margin_pct, x.difficulty, x.lifecycle, x.idea_score, x.final_score,
  x.rank_in_batch, x.stage, x.rejected_reason
FROM json_populate_recordset(NULL::adpf_ideas, $1::json) AS x
ON CONFLICT (idea_uid) DO UPDATE SET
  stage = EXCLUDED.stage,
  final_score = EXCLUDED.final_score,
  rejected_reason = EXCLUDED.rejected_reason,
  updated_at = now();
""".strip()

JS_BUILD_OUTPUT = r"""
// Contract returned to 01: the shortlist plus enough numbers to explain it.
const ctx = $('Parse Inventory Snapshot').first().json;
const ideas = $('Select Idea Funnel').all().map((i) => i.json);

const byStage = (stage) => ideas.filter((idea) => idea.stage === stage);
const top5 = byStage('top5').sort((a, b) => b.final_score - a.final_score);
const rejected = byStage('rejected');

const slim = (idea) => ({
  idea_uid: idea.idea_uid,
  title: idea.title,
  category: idea.category,
  factory: idea.factory,
  target_customer: idea.target_customer,
  keywords: idea.keywords,
  difficulty: idea.difficulty,
  lifecycle: idea.lifecycle,
  est_price_usd: idea.est_price_usd,
  est_api_cost_usd: idea.est_api_cost_usd,
  est_profit_usd: idea.est_profit_usd,
  est_margin_pct: idea.est_margin_pct,
  scores: {
    demand: idea.demand_score, competition: idea.competition_score,
    trend: idea.trend_score, seo: idea.seo_score, profit: idea.profit_score,
    difficulty: idea.difficulty_score, evergreen: idea.evergreen_score,
    diversity: idea.diversity_score, saturation: idea.saturation_penalty,
  },
  idea_score: idea.idea_score,
  final_score: idea.final_score,
});

const tokensIn = ideas.reduce((sum, i) => sum + (i.tokens_in || 0), 0);
const tokensOut = ideas.reduce((sum, i) => sum + (i.tokens_out || 0), 0);

return [{
  json: {
    ok: top5.length > 0,
    run_id: ctx.run_id,
    prompt_version: ctx.prompt_version,
    top_ideas: top5.map(slim),
    selected_idea: top5.length ? slim(top5[0]) : null,
    funnel: {
      generated: ideas.length,
      after_duplicate_filter: ideas.length - rejected.length,
      top50: byStage('top50').length + byStage('top20').length + top5.length,
      top20: byStage('top20').length + top5.length,
      top5: top5.length,
      rejected: rejected.length,
    },
    rejected_examples: rejected.slice(0, 10).map((i) => ({
      title: i.title, reason: i.rejected_reason,
    })),
    inventory: {
      total_products: ctx.inventory.total_products,
      wanted_categories: ctx.inventory.wanted_categories,
      crowded_categories: ctx.inventory.crowded_categories,
      balance: ctx.inventory.balance,
    },
    usage: { prompt_tokens: tokensIn, completion_tokens: tokensOut, kind: 'chat' },
    generated_at: new Date().toISOString(),
  },
}];
""".strip()


def build() -> Workflow:
    wf = Workflow("07")

    wf.add("Receive Idea Request", T_EXEC_TRIGGER, pos(0, 2),
           {"inputSource": "passthrough"},
           notes="Entry point. Called by 01 with the run context and research package.")
    wf.add("Prompt Library", T_CODE, pos(1, 2), code(library_js(["idea_generator_ai"])),
           notes="Versioned prompt for the Idea Generator agent.")
    wf.add("Normalize Idea Input", T_CODE, pos(2, 2), code(JS_NORMALIZE),
           notes="Clamps the requested idea count into the 100-500 band and plans the batches.")

    wf.add("Postgres: Load Inventory", T_POSTGRES, pos(3, 2),
           {"operation": "executeQuery", "query": SQL_INVENTORY, "options": {}},
           notes=("Section 3. One round trip for product counts, category mix, recent "
                  "titles and the pending idea queue."),
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("Parse Inventory Snapshot", T_CODE, pos(4, 2), code(JS_PARSE_INVENTORY),
           notes=("Sections 3 + 4 + 18. Computes saturation per category and the "
                  "wanted/crowded lists that steer generation."))

    wf.add("Split: Idea Batches", T_CODE, pos(5, 2), code(JS_SPLIT_BATCHES),
           notes="Section 1. One item per batch of ~25 ideas.")
    wf.add("Loop: Idea Batches", T_LOOP, pos(6, 2), loop_node(1),
           notes="Sequential batches so later prompts can avoid earlier titles.")
    wf.add("Check: Generate Ideas", T_IF, pos(7, 3), if_bool("={{ !$json.dry_run }}"),
           notes="dry_run synthesises ideas locally instead of calling OpenAI.")
    wf.add("Build Idea Batch Prompt", T_CODE, pos(8, 3), code(JS_BUILD_BATCH_PROMPT),
           notes="Feeds the avoid-list (existing + pending + already generated) into the prompt.")
    wf.add("OpenAI: Idea Generator AI", T_HTTP, pos(9, 3),
           openai_chat(
               "($('Prompt Library').first().json.prompts.idea_generator_ai.system + "
               "'\\n\\nOUTPUT CONTRACT (return exactly this JSON shape):\\n' + "
               "$('Prompt Library').first().json.prompts.idea_generator_ai.output_contract)",
               "$json.idea_user_prompt", temperature=1.0, max_tokens=8000),
           notes=("Agent 9/13. High temperature on purpose: this call is a generator, "
                  "and the scoring engine filters afterwards."),
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("Parse Idea Batch", T_CODE, pos(10, 3), code(JS_PARSE_BATCH),
           notes="Clamps every score to 0-100 and normalises the factory key. Bad batch = dropped.")
    wf.add("Synthesize Idea Batch", T_CODE, pos(8, 4), code(JS_PLACEHOLDER_BATCH),
           notes="dry_run stand-in so the funnel and database writes can be rehearsed free.")
    wf.add("Collect Raw Ideas", T_CODE, pos(7, 2), code(JS_COLLECT_IDEAS),
           notes="Merges all batches and drops exact title collisions between them.")

    wf.add("Score Ideas", T_CODE, pos(8, 1), code(JS_SCORE_IDEAS),
           notes=("Sections 2 + 5. Every sub-score computed in code from the model's raw "
                  "signals - reproducible and auditable, unlike letting the model rank itself."))
    wf.add("Duplicate Detector", T_CODE, pos(9, 1), code(JS_DUPLICATE_DETECTOR),
           notes=("Section 13. Jaccard similarity against existing products and within "
                  "the batch. Over threshold = rejected with a reason."))
    wf.add("Select Idea Funnel", T_CODE, pos(10, 1), code(JS_SELECT_FUNNEL),
           notes=("Section 6. 500 -> 50 (score) -> 20 (max 4/category) -> 5 (max 2/category "
                  "and at least one under-represented category)."))

    wf.add("Build Idea Rows", T_CODE, pos(11, 1), code(JS_BUILD_ROWS),
           notes="Packs every idea into one JSON array for a single bulk insert.")
    wf.add("Postgres: Save Idea Pool", T_POSTGRES, pos(12, 1),
           {
               "operation": "executeQuery",
               "query": SQL_BULK_INSERT,
               "options": {"queryReplacement": "={{ [$json.rows_json] }}"},
           },
           notes="Bulk insert via json_populate_recordset - one statement for 100-500 rows.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("Build Idea Output", T_CODE, pos(13, 1), code(JS_BUILD_OUTPUT),
           notes="Returns the shortlist, the funnel counts and the portfolio picture.")
    wf.add("Return: Idea Package", T_NOOP, pos(14, 1), {},
           notes="Terminal node - its item is the sub-workflow return value.")

    # -- wiring ------------------------------------------------------------
    wf.chain("Receive Idea Request", "Prompt Library", "Normalize Idea Input",
             "Postgres: Load Inventory", "Parse Inventory Snapshot",
             "Split: Idea Batches", "Loop: Idea Batches")
    wf.link("Loop: Idea Batches", "Collect Raw Ideas", 0)
    wf.link("Loop: Idea Batches", "Check: Generate Ideas", 1)
    wf.link("Check: Generate Ideas", "Build Idea Batch Prompt", 0)
    wf.link("Check: Generate Ideas", "Synthesize Idea Batch", 1)
    wf.chain("Build Idea Batch Prompt", "OpenAI: Idea Generator AI", "Parse Idea Batch")
    wf.link("Parse Idea Batch", "Loop: Idea Batches")
    wf.link("Synthesize Idea Batch", "Loop: Idea Batches")

    wf.chain("Collect Raw Ideas", "Score Ideas", "Duplicate Detector",
             "Select Idea Funnel", "Build Idea Rows", "Postgres: Save Idea Pool",
             "Build Idea Output", "Return: Idea Package")

    return wf
