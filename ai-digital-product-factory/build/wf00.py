"""00 Starter Smoke Test - the first workflow to run on a fresh install.

Deliberately depends on NOTHING except n8n itself:

  * no PostgreSQL
  * no Etsy account
  * no Google Drive
  * OpenAI is optional (set test_openai=false to skip it)

What it proves, in order:

  1. n8n runs a Code node at all
  2. configuration resolves via the Factory Config node (n8n Cloud OK)
  3. the OpenAI credential works and JSON mode returns parseable output
  4. the dependency-free PDF engine produces a real, openable file

If this workflow is green, every hard prerequisite of the factory is in place
and the remaining work is only credentials for Etsy / Drive / Postgres.
"""

from common import (
    AGENT_CONTENT_JS,
    T_CODE, T_HTTP, T_IF, T_MANUAL, T_NOOP, Workflow, code, if_bool,
    openai_chat, pos,
)
from js_pdf import PDF_LIB_JS

JS_CHECK_SETUP = r"""
// STEP 1+2 - can this instance resolve its configuration?
// Works on n8n Cloud and self-hosted alike: settings come from the Factory
// Config node (parent cfg > Variables > env > built-in defaults), so nothing
// here depends on environment variables existing.
const item = $input.first().json;
const cfg = item.cfg || {};
const sources = item.cfg_sources || {};

const cfgReady = Object.keys(cfg).length > 0;

const GROUPS = {
  'OpenAI (needed to generate anything)': ['OPENAI_MODEL_TEXT', 'OPENAI_MODEL_IMAGE'],
  'Etsy (needed only to publish)': ['ETSY_API_BASE', 'ETSY_API_KEY', 'ETSY_SHOP_ID'],
  'Google Drive (needed only to back up)': ['GDRIVE_ROOT_FOLDER_ID'],
  'Database (needed for workflows 06-10)': ['DB_TYPE'],
  'Factory settings': ['PROMPT_VERSION', 'FACTORY_ROTATION'],
};

const report = {};
for (const [group, keys] of Object.entries(GROUPS)) {
  report[group] = keys.map((key) => {
    const value = cfg[key];
    const isSet = value !== undefined && value !== null && String(value).trim() !== '';
    return {
      key,
      set: isSet,
      source: sources[key] || 'default',
      value: key.includes('KEY') || key.includes('SECRET')
        ? (isSet ? '(set, hidden)' : null)
        : (isSet ? String(value) : null),
    };
  });
}

const blockers = [];
if (!cfgReady) {
  blockers.push('Factory Config produced no settings - is the node connected before this one?');
}

return [{
  json: {
    step: 'check-setup',
    cfg_ready: cfgReady,
    env_report: report,
    blockers,
    // Flip to false to test the PDF engine without spending anything on OpenAI.
    test_openai: item.test_openai !== false && blockers.length === 0,
    product_title: item.product_title || 'My First Test Product',
    checked_at: new Date().toISOString(),
  },
}];
""".strip()

JS_BUILD_PROMPT = r"""
// STEP 2 - the smallest possible real request. A few hundred tokens, so a
// mistyped API key costs a fraction of a cent to discover.
const ctx = $input.first().json;

return [{
  json: {
    ...ctx,
    system_prompt:
      'You are a setup test. Reply with valid JSON only, nothing else.',
    user_prompt:
      'Write one short marketing line for a printable product called "' +
      ctx.product_title + '". ' +
      'Answer exactly: {"tagline": "...", "three_words": ["...","...","..."]}',
  },
}];
""".strip()

JS_PARSE_REPLY = AGENT_CONTENT_JS + r"""
// STEP 3 - did OpenAI answer, and is the answer parseable JSON?
// Both halves matter: a working key that returns prose would break every
// downstream workflow, so the parse is part of the test.
const ctx = $('Build Test Prompt').first().json;
const response = $input.first().json;

const problems = [];
let parsed = null;

const content = agentContent(response);
if (response?.error) {
  problems.push(`OpenAI error: ${response.error.message || JSON.stringify(response.error)}`);
} else if (!content) {
  problems.push('OpenAI returned no content - check the credential and your account credit');
} else {
  try {
    parsed = JSON.parse(content);
  } catch (e) {
    problems.push(`OpenAI replied but not with JSON: ${e.message}`);
  }
}

const usage = response?.usage || {};
// Rough cost at gpt-4.1 list price, just so the number is not a mystery.
const costUsd = ((usage.prompt_tokens || 0) / 1e6) * 2
  + ((usage.completion_tokens || 0) / 1e6) * 8;

return [{
  json: {
    ...ctx,
    openai_ok: problems.length === 0,
    openai_problems: problems,
    openai_reply: parsed,
    openai_usage: {
      prompt_tokens: usage.prompt_tokens || 0,
      completion_tokens: usage.completion_tokens || 0,
      approx_cost_usd: Math.round(costUsd * 1e6) / 1e6,
    },
  },
}];
""".strip()

JS_SKIP_OPENAI = r"""
// OpenAI was skipped on purpose - carry on to the PDF test.
const ctx = $input.first().json;
return [{
  json: {
    ...ctx,
    openai_ok: null,
    openai_problems: [],
    openai_reply: null,
    openai_skipped: true,
    skip_reason: ctx.blockers.length
      ? 'blocked: ' + ctx.blockers.join('; ')
      : 'test_openai was set to false',
  },
}];
""".strip()

JS_BUILD_PDF = PDF_LIB_JS + r"""

// ---------------------------------------------------------------------------
// STEP 4 - build a real PDF with the same writer the product line uses.
// No npm package, no external service: if this node is green, the factory can
// produce sellable files on this machine.
// ---------------------------------------------------------------------------
const ctx = $input.first().json;
const reply = ctx.openai_reply || {};

const envLines = [];
for (const [group, keys] of Object.entries(ctx.env_report)) {
  envLines.push(group);
  for (const entry of keys) {
    envLines.push(`   ${entry.set ? '[OK]  ' : '[--]  '}${entry.key}` +
      (entry.value ? ` = ${entry.value}` : '') +
      (entry.source && entry.source !== 'default' ? `  (from ${entry.source})` : ''));
  }
  envLines.push('');
}

const pages = [
  {
    type: 'text',
    cover: true,
    title: 'Setup test passed',
    subtitle: ctx.product_title,
    lines: [
      '',
      'If you can read this page, the following all work on this machine:',
      '',
      '- n8n executes Code nodes',
      `- configuration resolves (Cloud-compatible): ${ctx.cfg_ready ? 'YES' : 'NO'}`,
      `- OpenAI credential: ${ctx.openai_ok === null ? 'skipped' : (ctx.openai_ok ? 'YES' : 'FAILED')}`,
      '- the PDF engine produces a real file (this document)',
      '',
      reply.tagline ? `OpenAI wrote: "${reply.tagline}"` : '',
      Array.isArray(reply.three_words) ? `Keywords: ${reply.three_words.join(', ')}` : '',
      '',
      `Generated: ${new Date().toISOString()}`,
    ].filter((line) => line !== ''),
    footer: 'AI Digital Product Factory - setup test',
  },
  {
    type: 'text',
    title: 'Environment report',
    lines: envLines,
    footer: 'AI Digital Product Factory - setup test',
  },
  {
    type: 'text',
    title: 'What to do next',
    lines: [
      '1. Add the Postgres credential, then run workflow 06 once.',
      '   Send: {"op":"run_start","run_id":"test-1","status":"running"}',
      '',
      '2. Add the OpenAI credential (if you have not), then run workflow 02.',
      '   Send: {"run_id":"test-2","factory":"printable"}',
      '',
      '3. Run workflow 01 with {"factory":"printable","dry_run":true}.',
      '   Images become 1x1 placeholders, so the rehearsal is nearly free.',
      '',
      '4. Only after all three are green, run a real product.',
      '   {"factory":"resume","dry_run":false} is the cheapest one.',
      '',
      'Etsy and Google Drive are needed only for steps 3 and 4.',
      'Everything before that runs without them.',
    ],
    footer: 'AI Digital Product Factory - setup test',
  },
];

const result = buildPdf({
  width: 595.28,
  height: 841.89,
  pages,
  info: { title: 'ADPF setup test', subject: 'installation check' },
});

const base64 = result.buffer.toString('base64');

return [{
  json: {
    ...ctx,
    pdf_pages: result.page_count,
    pdf_bytes: result.buffer.length,
    pdf_ok: result.buffer.length > 1000
      && result.buffer.slice(0, 5).toString('latin1') === '%PDF-',
  },
  // Attaching it as binary means the file is downloadable straight from the
  // n8n output panel - no database and no Drive needed to see the result.
  binary: {
    data: {
      data: base64,
      mimeType: 'application/pdf',
      fileName: 'adpf-setup-test.pdf',
      fileExtension: 'pdf',
    },
  },
}];
""".rstrip()

JS_SUMMARY = r"""
// The verdict, in the shape of a checklist a human can read at a glance.
const ctx = $input.first().json;

const checks = [
  { name: '1. n8n runs Code nodes', ok: true,
    detail: 'this node executed' },
  { name: '2. Configuration resolves', ok: ctx.cfg_ready,
    detail: ctx.cfg_ready
      ? 'ok - settings come from the Factory Config node (works on n8n Cloud)'
      : 'Factory Config did not run before Check Setup' },
  { name: '3. OpenAI credential works',
    ok: ctx.openai_ok === null ? null : ctx.openai_ok,
    detail: ctx.openai_ok === null ? (ctx.skip_reason || 'skipped')
      : (ctx.openai_ok ? `ok, cost about $${ctx.openai_usage.approx_cost_usd}`
                       : ctx.openai_problems.join('; ')) },
  { name: '4. PDF engine works', ok: ctx.pdf_ok,
    detail: ctx.pdf_ok ? `${ctx.pdf_pages} pages, ${ctx.pdf_bytes} bytes`
                       : 'PDF was not produced' },
];

const failed = checks.filter((c) => c.ok === false);
const skipped = checks.filter((c) => c.ok === null);

const missing = [];
for (const [group, keys] of Object.entries(ctx.env_report)) {
  const absent = keys.filter((k) => !k.set).map((k) => k.key);
  if (absent.length) missing.push(`${group}: ${absent.join(', ')}`);
}

return [{
  json: {
    ok: failed.length === 0,
    verdict: failed.length === 0
      ? (skipped.length ? 'PASSED (some checks skipped)' : 'PASSED - n8n is ready')
      : `FAILED - ${failed.length} check(s) need attention`,
    checks,
    failed: failed.map((c) => `${c.name}: ${c.detail}`),
    env_still_missing: missing,
    next_step: failed.length === 0
      ? 'Add the Postgres credential and run workflow 06 with {"op":"run_start","run_id":"test-1","status":"running"}'
      : 'Fix the failed check above, then run this workflow again',
    download: 'The test PDF is attached to the previous node - open the Binary tab to download it',
    finished_at: new Date().toISOString(),
  },
  binary: $input.first().binary,
}];
""".strip()


def build() -> Workflow:
    wf = Workflow("00")

    wf.add("Trigger: Manual Run", T_MANUAL, pos(0, 1), {},
           notes=("Press 'Test workflow'. Optionally pin input data with "
                  '{"test_openai": false} to skip the paid call.'))
    wf.add("Check Setup", T_CODE, pos(1, 1), code(JS_CHECK_SETUP),
           notes=("Step 1+2. Reports which environment variables are set and whether "
                  "$env is readable at all. Never throws - it produces a report."))
    wf.add("Check: Test OpenAI", T_IF, pos(2, 1), if_bool("={{ $json.test_openai }}"),
           notes="Skips the paid call when env access is broken or test_openai=false.")

    wf.add("Build Test Prompt", T_CODE, pos(3, 0), code(JS_BUILD_PROMPT),
           notes="The smallest useful request - a mistyped key costs a fraction of a cent.")
    wf.add("OpenAI: Connection Test", T_HTTP, pos(4, 0),
           openai_chat("$json.system_prompt", "$json.user_prompt",
                       temperature=0.7, max_tokens=200),
           notes=("Uses the OpenAI credential, exactly like the real workflows. "
                  "Errors are captured, not thrown, so the report still renders."),
           onError="continueRegularOutput", alwaysOutputData=True,
           retryOnFail=True, maxTries=2, waitBetweenTries=3000)
    wf.add("Parse OpenAI Reply", T_CODE, pos(5, 0), code(JS_PARSE_REPLY),
           notes=("Step 3. Checks the key works AND that JSON mode parses - a key that "
                  "returns prose would break every downstream workflow."))
    wf.add("Skip OpenAI Test", T_CODE, pos(3, 2), code(JS_SKIP_OPENAI),
           notes="Records why the call was skipped and continues to the PDF test.")

    wf.add("Build Test PDF", T_CODE, pos(6, 1), code(JS_BUILD_PDF),
           notes=("Step 4. Same dependency-free PDF writer the product line uses. "
                  "The file is attached as binary - download it from the output panel."))
    wf.add("Build Setup Report", T_CODE, pos(7, 1), code(JS_SUMMARY),
           notes="Four checks with pass/fail and the exact next step.")
    wf.add("Setup Test Finished", T_NOOP, pos(8, 1), {},
           notes="Terminal node. Green here means n8n is ready for the real workflows.")

    wf.chain("Trigger: Manual Run", "Check Setup", "Check: Test OpenAI")
    wf.link("Check: Test OpenAI", "Build Test Prompt", 0)
    wf.link("Check: Test OpenAI", "Skip OpenAI Test", 1)
    wf.chain("Build Test Prompt", "OpenAI: Connection Test", "Parse OpenAI Reply")
    wf.link("Parse OpenAI Reply", "Build Test PDF")
    wf.link("Skip OpenAI Test", "Build Test PDF")
    wf.chain("Build Test PDF", "Build Setup Report", "Setup Test Finished")

    return wf
