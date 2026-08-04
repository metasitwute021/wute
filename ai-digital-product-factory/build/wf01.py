"""01 Master Controller - triggers, factory routing, orchestration, error handling."""

from common import (
    RETRY, T_CODE, T_ERROR_TRIGGER, T_EXEC_WF, T_HTTP, T_IF, T_MANUAL, T_NOOP,
    T_SCHEDULE, T_STOP, T_WEBHOOK, Workflow, code, exec_workflow, if_bool, pos,
)

JS_INIT_CONTEXT = r"""
// Normalise the three trigger shapes (schedule / webhook / manual) into a single
// run context object that every downstream workflow can rely on.
const now = new Date();
const incoming = $input.first() ? $input.first().json : {};
const body = incoming.body || incoming.query || incoming;

const rand = Math.random().toString(36).slice(2, 8);
const stamp = now.toISOString().slice(0, 10).replace(/-/g, '');
const runId = body.run_id || `adpf-${stamp}-${rand}`;

return [{
  json: {
    // cfg comes from the Factory Config node and rides along the whole run,
    // so every sub-workflow inherits the settings edited here in 01.
    cfg: incoming.cfg || {},
    run_id: runId,
    started_at: now.toISOString(),
    trigger_source: $execution.mode || 'trigger',
    requested_factory: String(body.factory || body.product_factory || 'auto').toLowerCase().trim(),
    seed_keyword: String(body.seed_keyword || body.keyword || '').trim(),
    dry_run: body.dry_run === true || String(body.dry_run).toLowerCase() === 'true',
    prompt_version: $env.PROMPT_VERSION || 'v1.0.0',
    marketplace: 'etsy',
    status: 'running',
    stage: 'init',
  },
}];
""".strip()

JS_VALIDATE_ENV = r"""
// Assess what this instance can do - it never throws any more. Cloud installs
// have no environment variables, and a missing Etsy key should mean "build the
// product but skip publishing", not a dead run.
const ctx = $input.first().json;
const cfg = $('Factory Config').first().json.cfg;

const etsyMissing = ['ETSY_API_KEY', 'ETSY_SHOP_ID']
  .filter((key) => !cfg[key] || String(cfg[key]).trim() === '');
const etsyConfigured = etsyMissing.length === 0;

const warnings = [];
if (!etsyConfigured) {
  warnings.push(
    'Etsy is not configured yet (' + etsyMissing.join(', ') + ') - ' +
    'the run will produce the product and record it, but skip publishing and backup.'
  );
}

return [{
  json: {
    ...ctx,
    stage: 'validate-config',
    env_warnings: warnings,
    etsy_configured: etsyConfigured,
    skip_publish: !etsyConfigured,
    etsy_api_base: cfg.ETSY_API_BASE,
    etsy_shop_id: cfg.ETSY_SHOP_ID,
    db_type: String(cfg.DB_TYPE || 'postgres').toLowerCase(),
    etsy_listing_state: String(cfg.ETSY_LISTING_STATE || 'draft').toLowerCase(),
  },
}];
""".strip()

JS_SELECT_FACTORY = r"""
// Pick which product factory runs. An explicit request always wins; "auto"
// rotates deterministically through the enabled factories so an unattended daily
// schedule covers the whole catalogue instead of hammering one niche.
const FACTORIES = [
  'planner', 'printable', 'canva', 'wallart',
  'resume', 'spreadsheet', 'kids', 'svg',
];

const ctx = $input.first().json;
let factory = ctx.requested_factory;

if (!factory || factory === 'auto') {
  const rotation = String($env.FACTORY_ROTATION || FACTORIES.join(','))
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter((s) => FACTORIES.includes(s));
  const pool = rotation.length ? rotation : FACTORIES;
  const dayIndex = Math.floor(Date.now() / 86400000);
  factory = pool[dayIndex % pool.length];
}

if (!FACTORIES.includes(factory)) {
  throw new Error(
    `Unknown product factory "${factory}". Expected one of: ${FACTORIES.join(', ')}`
  );
}

return [{ json: { ...ctx, factory, stage: 'factory-selected' } }];
""".strip()

JS_PREPARE_RUN_LOG = r"""
// Shape the payload for the 06 Database Logger sub-workflow (op = run_start).
const ctx = $input.first().json;
return [{
  json: {
    op: 'run_start',
    run_id: ctx.run_id,
    factory: ctx.factory,
    product_name: null,
    category: null,
    keywords: [],
    marketplace: ctx.marketplace,
    drive_folder_id: null,
    etsy_listing_id: null,
    prompt_version: ctx.prompt_version,
    status: 'running',
    error_log: null,
  },
}];
""".strip()

JS_RESTORE_CONTEXT = r"""
// The Execute Workflow node replaces the item with the sub-workflow output, so
// the run context is restored from the node that produced it.
const ctx = $('Select Product Factory').first().json;
const logResult = $input.first() ? $input.first().json : {};
return [{ json: { ...ctx, stage: 'research', run_log_id: logResult.record_id || null } }];
""".strip()

JS_PREPARE_BUDGET_CHECK = r"""
// V2 section 10: ask 08 whether there is budget before spending anything.
const ctx = $input.first().json;
return [{
  json: {
    op: 'check_budget',
    run_id: ctx.run_id,
    stage: 'preflight',
    reserve_usd: Number($env.BUDGET_RUN_RESERVE_USD || 3),
  },
}];
""".strip()

JS_AFTER_BUDGET = r"""
// Carry the budget verdict alongside the restored run context.
const ctx = $('Select Product Factory').first().json;
const budget = $input.first().json;
return [{
  json: {
    ...ctx,
    budget: {
      allowed: budget.allowed !== false,
      block_reason: budget.block_reason || null,
      daily_remaining_usd: budget.daily?.remaining_usd ?? null,
      monthly_remaining_usd: budget.monthly?.remaining_usd ?? null,
    },
    // A blocked run is a controlled stop, not a crash.
    failure_reason: budget.allowed === false
      ? `Budget manager stopped the run: ${budget.block_reason}` : null,
  },
}];
""".strip()

JS_COMPOSE_IDEA = r"""
// V2 sections 1-6: hand the research package to the Idea Factory.
const ctx = $('Restore Run Context').first().json;
const research = $input.first().json;
return [{
  json: {
    ...ctx,
    stage: 'ideas',
    research: research.research || research,
    market: research.market || {},
    idea_count: Number(ctx.idea_count || $env.IDEA_TARGET_COUNT || 200),
  },
}];
""".strip()

JS_COMPOSE_PRODUCT = r"""
// Contract for 03 Product Engine. V2: the research package is now narrowed by
// the Idea Factory, so the product is built from the winning idea rather than
// from the raw research concept.
const ctx = $('Restore Run Context').first().json;
const ideaResult = $input.first().json;
const research = $('Compose Idea Request').first().json.research;
const selected = ideaResult.selected_idea;

if (!selected) {
  throw new Error('Idea Factory returned no shortlisted idea');
}

return [{
  json: {
    ...ctx,
    stage: 'product',
    // The winning idea overrides the generic concept: its title, category and
    // customer are what the whole production line will build against.
    factory: selected.factory || ctx.factory,
    idea_uid: selected.idea_uid,
    research: {
      ...research,
      product_type: selected.factory,
      category: selected.category,
      target_customer: selected.target_customer || research.target_customer,
      keyword: (selected.keywords && selected.keywords[0]) || research.keyword,
      sub_keywords: selected.keywords && selected.keywords.length
        ? selected.keywords : research.sub_keywords,
      price_suggestion_usd: selected.est_price_usd || research.price_suggestion_usd,
      difficulty: selected.difficulty || research.difficulty,
      idea_title: selected.title,
    },
    market: $('Compose Idea Request').first().json.market,
    idea: selected,
    idea_funnel: ideaResult.funnel,
  },
}];
""".strip()

JS_PREPARE_ROLLUP = r"""
// V2 section 8: fold the measured API cost into the product row so ROI is one
// column read, not a join at report time.
const ctx = $('Restore Run Context').first().json;
return [{ json: { op: 'rollup', run_id: ctx.run_id, stage: 'finalise' } }];
""".strip()

JS_PREPARE_VERSION = r"""
// V2 section 12: append-only version history.
const ctx = $('Restore Run Context').first().json;
const product = $('Compose Publish Request').first().json.product;

return [{
  json: {
    op: 'product_version',
    run_id: ctx.run_id,
    product_name: product.product_name,
    version: Number(product.version || 1),
    prompt_version: ctx.prompt_version,
    change_note: product.is_revision
      ? `revision of an existing product (similarity ${product.duplicate_similarity})`
      : 'initial version',
    qa_score: product.qa?.average_score ?? null,
  },
}];
""".strip()

JS_COMPOSE_PUBLISH = r"""
// Contract for 04 Publish Engine: everything 03 produced plus the run context.
const ctx = $('Restore Run Context').first().json;
const product = $input.first().json;
return [{
  json: {
    ...ctx,
    stage: 'publish',
    research: $('Compose Product Request').first().json.research,
    product,
  },
}];
""".strip()

JS_COMPOSE_BACKUP = r"""
// Contract for 05 Google Drive Backup. Runs only after Etsy accepted the draft
// listing, so the backup folder always mirrors something that really exists.
const ctx = $('Restore Run Context').first().json;
const publish = $input.first().json;
const product = $('Compose Publish Request').first().json.product;
return [{
  json: {
    ...ctx,
    stage: 'backup',
    research: $('Compose Product Request').first().json.research,
    product,
    publish,
  },
}];
""".strip()

JS_PREPARE_RECORD = r"""
// Final database record for a successful run (op = product_upsert).
const ctx = $('Restore Run Context').first().json;
const product = $('Compose Publish Request').first().json.product;
const publish = $('Compose Backup Request').first().json.publish;
const backup = $input.first().json;
const meta = product.metadata || {};

return [{
  json: {
    op: 'product_upsert',
    run_id: ctx.run_id,
    factory: ctx.factory,
    product_name: meta.product_name || product.product_name || 'unknown-product',
    category: meta.category || (product.research && product.research.category) || null,
    keywords: meta.keywords || meta.tags || [],
    marketplace: [
      'etsy',
      publish.gumroad_package_ready ? 'gumroad-prepared' : null,
      publish.miricanvas_package_ready ? 'miricanvas-prepared' : null,
    ].filter(Boolean).join(','),
    // V2: fingerprints for duplicate detection and the version number
    idea_uid: ctx.idea_uid || null,
    version: product.version || 1,
    title_norm: product.title_norm || null,
    keyword_set: product.keyword_set || null,
    price_usd: meta.price_usd || null,
    drive_folder_id: backup.drive_folder_id || null,
    etsy_listing_id: publish.etsy_listing_id || null,
    prompt_version: ctx.prompt_version,
    status: 'completed',
    error_log: null,
  },
}];
""".strip()

JS_SUCCESS_SUMMARY = r"""
// Human readable summary; also the webhook response body.
const ctx = $('Restore Run Context').first().json;
const record = $('Prepare Product Record').first().json;
const backup = $('Run: Drive Backup').first().json;
const publish = $('Compose Backup Request').first().json.publish;
const started = new Date(ctx.started_at).getTime();

return [{
  json: {
    ok: true,
    run_id: ctx.run_id,
    factory: ctx.factory,
    product_name: record.product_name,
    etsy_listing_id: publish.etsy_listing_id || null,
    etsy_listing_state: ctx.etsy_listing_state,
    drive_folder_id: backup.drive_folder_id || null,
    drive_folder_path: backup.drive_folder_path || null,
    gumroad_package_ready: publish.gumroad_package_ready === true,
    miricanvas_package_ready: publish.miricanvas_package_ready === true,
    duration_seconds: Math.round((Date.now() - started) / 1000),
    finished_at: new Date().toISOString(),
    status: 'completed',
    // V2
    idea_funnel: (() => { try { return $('Compose Product Request').first().json.idea_funnel; }
                          catch (e) { return null; } })(),
    qa_stages: (() => { try {
      return ($('Compose Publish Request').first().json.product.qa?.stages || [])
        .map((s) => ({ stage: s.stage, passed: s.passed, score: s.score }));
    } catch (e) { return []; } })(),
    roi: (() => { try { return $('Run: Cost Rollup').first().json.roi; }
                  catch (e) { return null; } })(),
    budget_remaining_usd: ctx.budget?.daily_remaining_usd ?? null,
  },
}];
""".strip()

JS_PREPARE_RECORD_NO_PUBLISH = r"""
// Etsy is not configured: record the finished product in the database anyway,
// so nothing that was paid for is ever lost, then end the run cleanly.
const ctx = $('Restore Run Context').first().json;
const product = $input.first().json;
const meta = product.metadata || {};

return [{
  json: {
    op: 'product_upsert',
    run_id: ctx.run_id,
    factory: ctx.factory,
    product_name: meta.product_name || product.product_name || 'unknown-product',
    category: meta.category || null,
    keywords: meta.keywords || meta.tags || [],
    marketplace: 'none (etsy not configured)',
    drive_folder_id: null,
    etsy_listing_id: null,
    prompt_version: ctx.prompt_version,
    status: 'completed_no_publish',
    error_log: null,
  },
}];
""".strip()

JS_NO_PUBLISH_SUMMARY = r"""
// Success without publishing. The files live in this execution's output of
// 03 Product Engine - open Run: Product Engine's output to download them.
const ctx = $('Restore Run Context').first().json;
const product = $('Check: Etsy Configured').first().json;
const started = new Date(ctx.started_at).getTime();

return [{
  json: {
    ok: true,
    status: 'completed_without_publish',
    run_id: ctx.run_id,
    factory: ctx.factory,
    product_name: product.product_name,
    note: 'Etsy is not configured - the product was built and recorded, ' +
      'but not published. Add ETSY_API_KEY and ETSY_SHOP_ID in the Factory ' +
      'Config node of workflow 01 to enable publishing.',
    files_produced: (product.manifest || []).map((f) => ({
      file_name: f.file_name, format: f.format, bytes: f.bytes,
    })),
    where_to_download: "open this execution > node 'Run: Product Engine' > output > files[].b64",
    qa_passed: product.qa ? product.qa.passed : null,
    duration_seconds: Math.round((Date.now() - started) / 1000),
    finished_at: new Date().toISOString(),
  },
}];
""".strip()

JS_BUILD_ERROR = r"""
// Single funnel for every failed stage. Keeps one error shape for the database,
// the alert webhook and the final Stop And Error message.
const item = $input.first().json;
const ctx = (() => {
  try { return $('Select Product Factory').first().json; } catch (e) { return {}; }
})();

const rawError = item.error || item.__error || {};
const message =
  item.failure_reason ||
  rawError.message ||
  (typeof rawError === 'string' ? rawError : '') ||
  item.message ||
  'Unknown failure';

return [{
  json: {
    op: 'error_log',
    ok: false,
    run_id: ctx.run_id || item.run_id || 'unknown-run',
    factory: ctx.factory || item.factory || null,
    stage: item.failed_stage || item.stage || 'unknown',
    product_name: item.product_name || null,
    category: item.category || null,
    keywords: [],
    marketplace: 'etsy',
    drive_folder_id: null,
    etsy_listing_id: item.etsy_listing_id || null,
    prompt_version: ctx.prompt_version || $env.PROMPT_VERSION || 'v1.0.0',
    status: 'failed',
    error_log: JSON.stringify({
      stage: item.failed_stage || item.stage || 'unknown',
      message: String(message).slice(0, 4000),
      details: rawError.description || rawError.stack || null,
      at: new Date().toISOString(),
    }),
    error_message: String(message).slice(0, 500),
  },
}];
""".strip()

JS_GLOBAL_ERROR = r"""
// Catches crashes that escape the per-stage handling above (for example an
// expression error). Wired to the Error Trigger, so Factory Config has NOT run
// on this path - settings are read defensively here, never via the config node.
const readSetting = (key, fallback) => {
  try { if (typeof $vars !== 'undefined' && $vars[key]) return $vars[key]; } catch (err) {}
  try { if (typeof $env !== 'undefined' && $env[key]) return $env[key]; } catch (err) {}
  return fallback;
};

const e = $input.first().json;
const execution = e.execution || {};
const workflow = e.workflow || {};

return [{
  json: {
    op: 'error_log',
    run_id: `crash-${execution.id || Date.now()}`,
    factory: null,
    product_name: null,
    category: null,
    keywords: [],
    marketplace: 'etsy',
    drive_folder_id: null,
    etsy_listing_id: null,
    prompt_version: readSetting('PROMPT_VERSION', 'v1.0.0'),
    status: 'crashed',
    error_log: JSON.stringify({
      workflow: workflow.name || null,
      execution_id: execution.id || null,
      execution_url: execution.url || null,
      node: execution.lastNodeExecuted || null,
      message: (execution.error && execution.error.message) || 'unhandled workflow error',
      at: new Date().toISOString(),
    }),
  },
}];
""".strip()


def _stage_marker(stage: str) -> dict:
    """Set node that tags which stage blew up before the shared error funnel."""
    return {
        "mode": "raw",
        "jsonOutput": '={{ JSON.stringify({ ...$json, failed_stage: "%s" }) }}' % stage,
        "options": {},
    }


def build() -> Workflow:
    wf = Workflow("01")
    wf.error_workflow = None

    # ---- triggers --------------------------------------------------------
    wf.add(
        "Trigger: Daily Schedule", T_SCHEDULE, pos(0, 0),
        {"rule": {"interval": [{"field": "cronExpression", "expression": "0 3 * * *"}]}},
        notes="Unattended production run, 03:00 Asia/Bangkok. Disable while testing.",
    )
    wf.add(
        "Trigger: Webhook Run", T_WEBHOOK, pos(0, 1),
        {
            "httpMethod": "POST",
            "path": "ai-digital-product-factory",
            "responseMode": "lastNode",
            "options": {},
        },
        notes=(
            "On-demand run. POST {factory, seed_keyword, dry_run}. "
            "Protect with a Header Auth credential before exposing it publicly."
        ),
    )
    wf.add(
        "Trigger: Manual Run", T_MANUAL, pos(0, 2), {},
        notes="Manual execution from the n8n editor for smoke tests.",
    )

    # ---- setup -----------------------------------------------------------
    wf.add("Init Run Context", T_CODE, pos(1, 1), code(JS_INIT_CONTEXT),
           notes="Builds run_id and normalises the payload of all three triggers.")
    wf.add("Validate Environment", T_CODE, pos(2, 1), code(JS_VALIDATE_ENV),
           notes="Guard clause: aborts immediately when required env vars are missing.")
    wf.add("Select Product Factory", T_CODE, pos(3, 1), code(JS_SELECT_FACTORY),
           notes="Explicit factory wins, otherwise rotate deterministically per day.")
    # -- V2 section 10: budget gate before anything is spent ---------------
    wf.add("Prepare Budget Check", T_CODE, pos(3, 2), code(JS_PREPARE_BUDGET_CHECK),
           notes="V2 section 10. Asks 08 whether today's and this month's budget allow a run.")
    wf.add("Run: Budget Check", T_EXEC_WF, pos(3, 3), exec_workflow("08"),
           notes="Calls 08 Cost and Budget, op=check_budget.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("Apply Budget Verdict", T_CODE, pos(3, 4), code(JS_AFTER_BUDGET),
           notes="Restores the run context and attaches the budget verdict.")
    wf.add("Check: Budget OK", T_IF, pos(3, 5),
           if_bool("={{ $json.budget.allowed }}"),
           notes="Budget exhausted stops the run here - a controlled stop, not a crash.")

    wf.add("Prepare Run Start Log", T_CODE, pos(4, 1), code(JS_PREPARE_RUN_LOG),
           notes="Payload for 06 Database Logger, op=run_start.")
    wf.add(
        "Log: Run Started", T_EXEC_WF, pos(5, 1), exec_workflow("06"),
        notes="Writes the run row before any expensive work happens.",
        onError="continueRegularOutput", alwaysOutputData=True, **RETRY,
    )
    wf.add("Restore Run Context", T_CODE, pos(6, 1), code(JS_RESTORE_CONTEXT),
           notes="Execute Workflow replaces the item - restore the run context here.")

    # ---- stage 02 --------------------------------------------------------
    wf.add(
        "Run: Research Engine", T_EXEC_WF, pos(7, 1), exec_workflow("02"),
        notes="Calls 02 Research Engine. Error output (2nd) goes to the error funnel.",
        onError="continueErrorOutput", **RETRY,
    )
    wf.add("Check: Research OK", T_IF, pos(8, 1), if_bool("={{ $json.ok }}"),
           notes="Research must return ok=true and a complete concept contract.")

    # -- V2 sections 1-6: idea funnel between research and production ------
    wf.add("Compose Idea Request", T_CODE, pos(8, 0), code(JS_COMPOSE_IDEA),
           notes="V2. Input contract for 07 Idea Factory.")
    wf.add("Run: Idea Factory", T_EXEC_WF, pos(9, 0), exec_workflow("07"),
           notes="Calls 07 Idea Factory: 100-500 ideas scored and funnelled to a top 5.",
           onError="continueErrorOutput", **RETRY)
    wf.add("Check: Ideas OK", T_IF, pos(10, 0), if_bool("={{ $json.ok }}"),
           notes="False when no idea survived scoring, dedupe and the category balancer.")

    wf.add("Compose Product Request", T_CODE, pos(9, 1), code(JS_COMPOSE_PRODUCT),
           notes="Input contract for 03 Product Engine, built from the winning idea.")

    # ---- stage 03 --------------------------------------------------------
    wf.add(
        "Run: Product Engine", T_EXEC_WF, pos(10, 1), exec_workflow("03"),
        notes="Calls 03 Product Engine (generation + QA gate + file export).",
        onError="continueErrorOutput", **RETRY,
    )
    wf.add("Check: Product OK", T_IF, pos(11, 1), if_bool("={{ $json.ok }}"),
           notes="False when the QA agent rejected the product - nothing gets published.")
    # -- Cloud path: no Etsy yet -> build + record, skip publish/backup -----
    wf.add("Check: Etsy Configured", T_IF, pos(12, 0),
           if_bool("={{ !$('Validate Environment').first().json.skip_publish }}"),
           notes=("Etsy keys missing = build the product and record it, but skip "
                  "publishing and backup instead of failing the run."))
    wf.add("Prepare Record (No Publish)", T_CODE, pos(13, -1),
           code(JS_PREPARE_RECORD_NO_PUBLISH),
           notes="Records the finished product even though it was not published.")
    wf.add("Save: Record (No Publish)", T_EXEC_WF, pos(14, -1), exec_workflow("06"),
           notes="Calls 06 Database Logger, op=product_upsert, status=completed_no_publish.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("Build No-Publish Summary", T_CODE, pos(15, -1), code(JS_NO_PUBLISH_SUMMARY),
           notes="Success summary that tells the user exactly where to download the files.")

    wf.add("Compose Publish Request", T_CODE, pos(12, 1), code(JS_COMPOSE_PUBLISH),
           notes="Input contract for 04 Publish Engine.")

    # ---- stage 04 --------------------------------------------------------
    wf.add(
        "Run: Publish Engine", T_EXEC_WF, pos(13, 1), exec_workflow("04"),
        notes="Calls 04 Publish Engine. Creates an Etsy DRAFT listing only.",
        onError="continueErrorOutput", **RETRY,
    )
    wf.add("Check: Publish OK", T_IF, pos(14, 1), if_bool("={{ $json.ok }}"),
           notes="Backup only runs once Etsy accepted the listing.")
    wf.add("Compose Backup Request", T_CODE, pos(15, 1), code(JS_COMPOSE_BACKUP),
           notes="Input contract for 05 Google Drive Backup.")

    # ---- stage 05 / 06 ---------------------------------------------------
    wf.add(
        "Run: Drive Backup", T_EXEC_WF, pos(16, 1), exec_workflow("05"),
        notes="Calls 05 Google Drive Backup (idempotent folder tree + file upload).",
        onError="continueErrorOutput", **RETRY,
    )
    # -- V2 sections 8 + 12: ROI rollup and version history ----------------
    wf.add("Prepare Cost Rollup", T_CODE, pos(17, 0), code(JS_PREPARE_ROLLUP),
           notes="V2 section 8. Asks 08 to fold measured API cost into the product row.")
    wf.add("Run: Cost Rollup", T_EXEC_WF, pos(18, 0), exec_workflow("08"),
           notes="Calls 08 Cost and Budget, op=rollup. Never blocks the run.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("Prepare Version Record", T_CODE, pos(19, 0), code(JS_PREPARE_VERSION),
           notes="V2 section 12. Append-only version history for this product.")
    wf.add("Save: Product Version", T_EXEC_WF, pos(20, 0), exec_workflow("06"),
           notes="Calls 06 Database Logger, op=product_version.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)

    wf.add("Prepare Product Record", T_CODE, pos(17, 1), code(JS_PREPARE_RECORD),
           notes="Final database row: ids, marketplace flags, prompt version, status.")
    wf.add(
        "Save: Product Record", T_EXEC_WF, pos(18, 1), exec_workflow("06"),
        notes="Calls 06 Database Logger, op=product_upsert.",
        onError="continueRegularOutput", alwaysOutputData=True, **RETRY,
    )
    wf.add("Build Success Summary", T_CODE, pos(19, 1), code(JS_SUCCESS_SUMMARY),
           notes="Run summary, also returned as the webhook response body.")
    wf.add("Respond: Run Finished", T_NOOP, pos(20, 1), {},
           notes="Terminal node of the happy path.")

    # ---- error funnel ----------------------------------------------------
    stages = [
        ("Stage Failed: Budget", "budget", 5),
        ("Stage Failed: Research", "research", 8),
        ("Stage Failed: Ideas", "ideas", 10),
        ("Stage Failed: Product", "product", 11),
        ("Stage Failed: Publish", "publish", 14),
        ("Stage Failed: Backup", "backup", 17),
    ]
    from common import T_SET
    for name, stage, column in stages:
        wf.add(name, T_SET, pos(column, 3), _stage_marker(stage),
               notes=f"Tags the failure with stage={stage} for the shared error funnel.")

    wf.add("Build Error Payload", T_CODE, pos(18, 3), code(JS_BUILD_ERROR),
           notes="Normalises any stage failure into one error record shape.")
    wf.add(
        "Log: Error To Database", T_EXEC_WF, pos(19, 3), exec_workflow("06"),
        notes="Calls 06 Database Logger, op=error_log. Never blocks the alert below.",
        onError="continueRegularOutput", alwaysOutputData=True, **RETRY,
    )
    wf.add(
        "Notify: Alert Webhook", T_HTTP, pos(20, 3),
        {
            "method": "POST",
            "url": "={{ $env.ALERT_WEBHOOK_URL || 'https://localhost/disabled' }}",
            "sendBody": True,
            "specifyBody": "json",
            "jsonBody": (
                "={{ JSON.stringify({ text: '[ADPF] run ' + "
                "$('Build Error Payload').first().json.run_id + ' failed at stage ' + "
                "$('Build Error Payload').first().json.stage + ': ' + "
                "$('Build Error Payload').first().json.error_message }) }}"
            ),
            "options": {"timeout": 15000},
        },
        notes="Optional Slack/Discord alert. Silently skipped when ALERT_WEBHOOK_URL is unset.",
        onError="continueRegularOutput", alwaysOutputData=True,
        retryOnFail=True, maxTries=2, waitBetweenTries=3000,
    )
    wf.add(
        "Stop On Fatal Error", T_STOP, pos(21, 3),
        {
            "errorMessage": (
                "={{ 'ADPF run ' + $('Build Error Payload').first().json.run_id + "
                "' failed at stage ' + $('Build Error Payload').first().json.stage + "
                "': ' + $('Build Error Payload').first().json.error_message }}"
            )
        },
        notes="Marks the execution as failed so n8n retries/alerts behave correctly.",
    )

    # ---- global crash handler -------------------------------------------
    wf.add("Trigger: Workflow Error Handler", T_ERROR_TRIGGER, pos(18, 5), {},
           notes="Set this workflow as the Error Workflow of 02-06 to capture crashes.")
    wf.add("Format Global Error", T_CODE, pos(19, 5), code(JS_GLOBAL_ERROR),
           notes="Converts the n8n error payload into the standard error record.")
    wf.add(
        "Log: Global Error", T_EXEC_WF, pos(20, 5), exec_workflow("06"),
        notes="Persists crashes that escaped the per-stage handling.",
        onError="continueRegularOutput", alwaysOutputData=True,
    )

    # ---- wiring ----------------------------------------------------------
    for trigger in ("Trigger: Daily Schedule", "Trigger: Webhook Run", "Trigger: Manual Run"):
        wf.link(trigger, "Init Run Context")

    wf.chain(
        "Init Run Context", "Validate Environment", "Select Product Factory",
        "Prepare Budget Check", "Run: Budget Check", "Apply Budget Verdict",
        "Check: Budget OK",
    )
    wf.link("Check: Budget OK", "Prepare Run Start Log", 0)
    wf.link("Check: Budget OK", "Stage Failed: Budget", 1)
    wf.chain(
        "Prepare Run Start Log", "Log: Run Started", "Restore Run Context",
        "Run: Research Engine",
    )
    wf.link("Run: Research Engine", "Check: Research OK", 0)
    wf.link("Run: Research Engine", "Stage Failed: Research", 1)
    wf.link("Check: Research OK", "Compose Idea Request", 0)
    wf.link("Check: Research OK", "Stage Failed: Research", 1)

    wf.link("Compose Idea Request", "Run: Idea Factory")
    wf.link("Run: Idea Factory", "Check: Ideas OK", 0)
    wf.link("Run: Idea Factory", "Stage Failed: Ideas", 1)
    wf.link("Check: Ideas OK", "Compose Product Request", 0)
    wf.link("Check: Ideas OK", "Stage Failed: Ideas", 1)

    wf.link("Compose Product Request", "Run: Product Engine")
    wf.link("Run: Product Engine", "Check: Product OK", 0)
    wf.link("Run: Product Engine", "Stage Failed: Product", 1)
    wf.link("Check: Product OK", "Check: Etsy Configured", 0)
    wf.link("Check: Product OK", "Stage Failed: Product", 1)
    wf.link("Check: Etsy Configured", "Compose Publish Request", 0)
    wf.link("Check: Etsy Configured", "Prepare Record (No Publish)", 1)
    wf.chain("Prepare Record (No Publish)", "Save: Record (No Publish)",
             "Build No-Publish Summary", "Respond: Run Finished")

    wf.link("Compose Publish Request", "Run: Publish Engine")
    wf.link("Run: Publish Engine", "Check: Publish OK", 0)
    wf.link("Run: Publish Engine", "Stage Failed: Publish", 1)
    wf.link("Check: Publish OK", "Compose Backup Request", 0)
    wf.link("Check: Publish OK", "Stage Failed: Publish", 1)

    wf.link("Compose Backup Request", "Run: Drive Backup")
    wf.link("Run: Drive Backup", "Prepare Product Record", 0)
    wf.link("Run: Drive Backup", "Stage Failed: Backup", 1)
    wf.chain(
        "Prepare Product Record", "Save: Product Record",
        "Prepare Cost Rollup", "Run: Cost Rollup",
        "Prepare Version Record", "Save: Product Version",
        "Build Success Summary", "Respond: Run Finished",
    )

    for name, _stage, _col in stages:
        wf.link(name, "Build Error Payload")
    wf.chain(
        "Build Error Payload", "Log: Error To Database",
        "Notify: Alert Webhook", "Stop On Fatal Error",
    )
    wf.chain("Trigger: Workflow Error Handler", "Format Global Error", "Log: Global Error")

    return wf
