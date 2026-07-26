"""02 Research Engine - Etsy market analysis + Research AI product concept."""

from common import (
    RETRY, T_CODE, T_EXEC_TRIGGER, T_HTTP, T_IF, T_NOOP, Workflow, code,
    etsy_http, if_bool, openai_chat, pos,
)
from prompts import RENDER_HELPER, library_js

JS_NORMALIZE = r"""
// Decide what to research. The master controller may pass a seed keyword; when it
// does not, each factory has a sensible default search phrase.
const FACTORY_SEEDS = {
  planner: 'digital planner printable',
  printable: 'printable wall planner',
  canva: 'canva template editable',
  wallart: 'printable wall art set',
  resume: 'resume template modern',
  spreadsheet: 'budget spreadsheet template',
  kids: 'kids printable activity',
  svg: 'svg cut file bundle',
};

const ctx = $input.first().json;
const factory = String(ctx.factory || 'printable').toLowerCase();
const seed = (ctx.seed_keyword || '').trim() || FACTORY_SEEDS[factory] || 'printable digital download';

return [{
  json: {
    ...ctx,
    factory,
    search_keyword: seed,
    etsy_api_base: ctx.etsy_api_base || $env.ETSY_API_BASE,
    researched_at: new Date().toISOString(),
  },
}];
""".strip()

JS_AGGREGATE = r"""
// Turn the raw Etsy responses into compact, quantified market signals. Sending
// 100 full listings to the model is wasteful and noisy - sending aggregates is
// cheaper and produces far more grounded answers.
const ctx = $('Normalize Research Input').first().json;

const safe = (nodeName, path) => {
  try {
    const json = $(nodeName).first().json;
    return path(json) || [];
  } catch (e) {
    return [];
  }
};

const listings = safe('Etsy: Search Active Listings', (j) => j.results);
const taxonomy = safe('Etsy: Fetch Taxonomy Nodes', (j) => j.results);

const STOPWORDS = new Set([
  'the', 'and', 'for', 'with', 'your', 'you', 'this', 'that', 'from', 'set',
  'pack', 'pdf', 'png', 'digital', 'download', 'instant', 'printable', 'file',
  'files', 'template', 'templates', 'a', 'of', 'to', 'in', 'on', 'by',
]);

const prices = [];
const tagCount = new Map();
const titleCount = new Map();
let totalSales = 0;
let withSales = 0;

for (const listing of listings) {
  const amount = listing?.price?.amount;
  const divisor = listing?.price?.divisor || 100;
  if (typeof amount === 'number' && divisor) prices.push(amount / divisor);

  if (typeof listing?.num_favorers === 'number') {
    totalSales += listing.num_favorers;
    withSales += 1;
  }

  for (const tag of listing?.tags || []) {
    const key = String(tag).toLowerCase().trim();
    if (key) tagCount.set(key, (tagCount.get(key) || 0) + 1);
  }

  for (const word of String(listing?.title || '').toLowerCase().split(/[^a-z0-9]+/)) {
    if (word.length < 3 || STOPWORDS.has(word)) continue;
    titleCount.set(word, (titleCount.get(word) || 0) + 1);
  }
}

const top = (map, n) => [...map.entries()]
  .sort((a, b) => b[1] - a[1])
  .slice(0, n)
  .map(([value, count]) => ({ value, count }));

prices.sort((a, b) => a - b);
const percentile = (p) => (prices.length ? prices[Math.min(prices.length - 1, Math.floor(prices.length * p))] : null);
const round2 = (n) => (n === null ? null : Math.round(n * 100) / 100);

const signals = {
  search_keyword: ctx.search_keyword,
  factory: ctx.factory,
  competitor_count: listings.length,
  price_usd: {
    min: round2(prices[0] ?? null),
    p25: round2(percentile(0.25)),
    median: round2(percentile(0.5)),
    p75: round2(percentile(0.75)),
    max: round2(prices[prices.length - 1] ?? null),
  },
  average_favourites: withSales ? Math.round(totalSales / withSales) : null,
  top_tags: top(tagCount, 25),
  top_title_words: top(titleCount, 25),
  etsy_categories: taxonomy
    .filter((n) => /craft|paper|party|art|digital|home/i.test(n?.name || ''))
    .slice(0, 25)
    .map((n) => ({ id: n.id, name: n.name, level: n.level })),
  sample_titles: listings.slice(0, 15).map((l) => String(l?.title || '').slice(0, 120)),
  signal_quality: listings.length >= 20 ? 'good' : (listings.length ? 'thin' : 'unavailable'),
};

return [{ json: { ...ctx, market: signals } }];
""".strip()

JS_BUILD_RESEARCH_PROMPT = RENDER_HELPER + r"""
const ctx = $input.first().json;
const agent = $('Prompt Library').first().json.prompts.research_ai;

const userPrompt = render(agent.user_template, {
  factory: ctx.factory,
  run_id: ctx.run_id,
  seed_keyword: ctx.search_keyword,
  market_signals_json: JSON.stringify(ctx.market, null, 2),
});

return [{ json: { ...ctx, research_user_prompt: userPrompt } }];
""".rstrip()

JS_PARSE_RESEARCH = r"""
// Parse + validate the model output against the fixed research contract. The
// node never throws: an invalid answer is routed to the deterministic fallback
// instead of killing the whole run.
const REQUIRED = [
  'product_type', 'category', 'target_customer', 'keyword',
  'sub_keywords', 'difficulty', 'selling_points',
];

const ctx = $('Build Research Prompt').first().json;
const response = $input.first().json;

let research = null;
const errors = [];

try {
  const content = response?.choices?.[0]?.message?.content;
  if (!content) throw new Error('OpenAI returned an empty completion');
  research = JSON.parse(content);
} catch (e) {
  errors.push(`parse: ${e.message}`);
}

if (research) {
  for (const key of REQUIRED) {
    if (research[key] === undefined || research[key] === null || research[key] === '') {
      errors.push(`missing field: ${key}`);
    }
  }
  if (!Array.isArray(research.sub_keywords) || research.sub_keywords.length < 5) {
    errors.push('sub_keywords must contain at least 5 entries');
  }
  if (!Array.isArray(research.selling_points) || research.selling_points.length < 3) {
    errors.push('selling_points must contain at least 3 entries');
  }
  if (!['easy', 'medium', 'hard'].includes(String(research.difficulty || '').toLowerCase())) {
    errors.push('difficulty must be easy, medium or hard');
  }
}

return [{
  json: {
    ...ctx,
    research,
    valid: errors.length === 0,
    validation_errors: errors,
    openai_usage: response?.usage || null,
  },
}];
""".strip()

JS_FALLBACK = r"""
// Deterministic safety net so a bad completion degrades the run instead of
// failing it. Built purely from the aggregated Etsy signals.
const ctx = $input.first().json;
const market = ctx.market || {};
const tags = (market.top_tags || []).map((t) => t.value);
const words = (market.top_title_words || []).map((t) => t.value);

const keyword = (ctx.search_keyword || 'printable digital download').toLowerCase();
const subKeywords = [...new Set([...tags, ...words])]
  .filter((t) => t.length <= 20)
  .slice(0, 13);

return [{
  json: {
    ...ctx,
    research: {
      product_type: ctx.factory,
      category: 'Digital Downloads',
      target_customer: 'Etsy shoppers looking for an instant, ready-to-print digital file',
      keyword,
      sub_keywords: subKeywords.length ? subKeywords : [keyword],
      difficulty: (market.competitor_count || 0) > 60 ? 'hard' : 'medium',
      selling_points: [
        'Instant download - no waiting and no shipping',
        'Print at home or at any print shop',
        'Clean, modern layout that works on every device',
      ],
      price_suggestion_usd: market?.price_usd?.median || 5,
      market_gap: 'Fallback concept generated from marketplace aggregates only',
      rejected_ideas: [],
    },
    valid: true,
    used_fallback: true,
    fallback_reason: (ctx.validation_errors || []).join('; ') || 'model output rejected',
  },
}];
""".strip()

JS_BUILD_SEO_PROMPT = RENDER_HELPER + r"""
const ctx = $input.first().json;
const agent = $('Prompt Library').first().json.prompts.seo_ai;

const userPrompt = render(agent.user_template, {
  seo_task: 'keywords',
  research_json: JSON.stringify(ctx.research, null, 2),
  idea_json: '(not generated yet - this is the research stage)',
  file_manifest: '(not generated yet - this is the research stage)',
});

return [{ json: { ...ctx, seo_user_prompt: userPrompt } }];
""".rstrip()

JS_BUILD_OUTPUT = r"""
// Final research contract returned to 01 Master Controller.
const ctx = $('Build Keyword Expansion Prompt').first().json;
const response = $input.first().json;

let expansion = {};
try {
  expansion = JSON.parse(response?.choices?.[0]?.message?.content || '{}');
} catch (e) {
  expansion = {};
}

const research = ctx.research || {};
const clean = (list) => [...new Set(
  (list || [])
    .map((s) => String(s).toLowerCase().replace(/[^a-z0-9 ]/g, '').trim())
    .filter((s) => s && s.length <= 20)
)];

const subKeywords = clean([...(research.sub_keywords || []), ...(expansion.sub_keywords || [])]).slice(0, 15);

return [{
  json: {
    ok: true,
    run_id: ctx.run_id,
    factory: ctx.factory,
    prompt_version: ctx.prompt_version,
    used_fallback: ctx.used_fallback === true,
    research: {
      product_type: research.product_type,
      category: research.category,
      target_customer: research.target_customer,
      keyword: String(research.keyword || ctx.search_keyword).toLowerCase(),
      sub_keywords: subKeywords,
      difficulty: String(research.difficulty || 'medium').toLowerCase(),
      selling_points: research.selling_points || [],
      price_suggestion_usd: research.price_suggestion_usd || ctx.market?.price_usd?.median || 5,
      market_gap: research.market_gap || null,
      long_tail: clean(expansion.long_tail || []).slice(0, 15),
    },
    market: ctx.market || {},
    researched_at: ctx.researched_at,
  },
}];
""".strip()


def build() -> Workflow:
    wf = Workflow("02")

    wf.add("Receive Research Request", T_EXEC_TRIGGER, pos(0, 1),
           {"inputSource": "passthrough"},
           notes="Entry point. Called by 01 Master Controller with the run context.")
    wf.add("Prompt Library", T_CODE, pos(1, 1),
           code(library_js(["research_ai", "seo_ai"])),
           notes="Versioned prompts for the two agents used in this workflow.")
    wf.add("Normalize Research Input", T_CODE, pos(2, 1), code(JS_NORMALIZE),
           notes="Resolves the search keyword (explicit seed or per-factory default).")

    wf.add(
        "Etsy: Search Active Listings", T_HTTP, pos(3, 1),
        etsy_http(
            "GET",
            "={{ $env.ETSY_API_BASE }}/v3/application/listings/active"
            "?limit=100&sort_on=score&sort_order=desc"
            "&keywords={{ encodeURIComponent($json.search_keyword) }}",
        ),
        notes=(
            "Live competitor sample for the target keyword. Degrades gracefully: "
            "on error the run continues with whatever signals are available."
        ),
        onError="continueRegularOutput", alwaysOutputData=True, **RETRY,
    )
    wf.add(
        "Etsy: Fetch Taxonomy Nodes", T_HTTP, pos(4, 1),
        etsy_http("GET", "={{ $env.ETSY_API_BASE }}/v3/application/seller-taxonomy/nodes"),
        notes="Official Etsy category tree, used to ground the category suggestion.",
        onError="continueRegularOutput", alwaysOutputData=True, **RETRY,
    )
    wf.add("Aggregate Etsy Market Signals", T_CODE, pos(5, 1), code(JS_AGGREGATE),
           notes="Price percentiles, tag/keyword frequency, competitor count, category hints.")
    wf.add("Build Research Prompt", T_CODE, pos(6, 1), code(JS_BUILD_RESEARCH_PROMPT),
           notes="Renders the Research AI user template with the aggregated signals.")

    wf.add(
        "OpenAI: Research AI", T_HTTP, pos(7, 1),
        openai_chat(
            "($('Prompt Library').first().json.prompts.research_ai.system + "
            "'\\n\\nOUTPUT CONTRACT (return exactly this JSON shape):\\n' + "
            "$('Prompt Library').first().json.prompts.research_ai.output_contract)",
            "$json.research_user_prompt",
            temperature=0.6,
            max_tokens=2000,
        ),
        notes="Agent 1/8. Chat Completions with response_format=json_object. OpenAI credential only.",
        **RETRY,
    )
    wf.add("Parse Research JSON", T_CODE, pos(8, 1), code(JS_PARSE_RESEARCH),
           notes="Validates the 7 required contract fields. Never throws - sets valid=false.")
    wf.add("Check: Research Valid", T_IF, pos(9, 1), if_bool("={{ $json.valid }}"),
           notes="Valid output continues; anything else falls back to the deterministic concept.")
    wf.add("Research Fallback Concept", T_CODE, pos(9, 2), code(JS_FALLBACK),
           notes="Safety net built from Etsy aggregates so a bad completion only degrades the run.")

    wf.add("Build Keyword Expansion Prompt", T_CODE, pos(10, 1), code(JS_BUILD_SEO_PROMPT),
           notes="Renders the SEO AI template in 'keywords' mode.")
    wf.add(
        "OpenAI: SEO AI Keyword Expansion", T_HTTP, pos(11, 1),
        openai_chat(
            "($('Prompt Library').first().json.prompts.seo_ai.system + "
            "'\\n\\nOUTPUT CONTRACT (return exactly this JSON shape):\\n' + "
            "$('Prompt Library').first().json.prompts.seo_ai.output_contract)",
            "$json.seo_user_prompt",
            temperature=0.5,
            max_tokens=1200,
        ),
        notes="Agent 5/8 (keywords mode). Expands the concept into Etsy-safe long-tail phrases.",
        onError="continueRegularOutput", alwaysOutputData=True, **RETRY,
    )
    wf.add("Build Research Output", T_CODE, pos(12, 1), code(JS_BUILD_OUTPUT),
           notes="Emits the fixed research contract consumed by 03 Product Engine.")
    wf.add("Return: Research Package", T_NOOP, pos(13, 1), {},
           notes="Terminal node - its item is the sub-workflow return value.")

    wf.chain(
        "Receive Research Request", "Prompt Library", "Normalize Research Input",
        "Etsy: Search Active Listings", "Etsy: Fetch Taxonomy Nodes",
        "Aggregate Etsy Market Signals", "Build Research Prompt",
        "OpenAI: Research AI", "Parse Research JSON", "Check: Research Valid",
    )
    wf.link("Check: Research Valid", "Build Keyword Expansion Prompt", 0)
    wf.link("Check: Research Valid", "Research Fallback Concept", 1)
    wf.link("Research Fallback Concept", "Build Keyword Expansion Prompt")
    wf.chain(
        "Build Keyword Expansion Prompt", "OpenAI: SEO AI Keyword Expansion",
        "Build Research Output", "Return: Research Package",
    )

    return wf
