"""The Planner Factory: one workflow, trigger to Etsy listing.

Deliberately a single workflow. The previous system split the work across
eleven, and every import reassigned their ids, so half the failures were
"Workflow does not exist" rather than anything to do with planners.
"""

from __future__ import annotations

import json

from js_pdf import PDF_LIB_JS
from nodes import (
    CONFIG_NODE, ETSY_TOKEN_NODE, RETRY, T_CODE, T_ERROR_TRIGGER, T_HTTP, T_IF,
    T_LOOP, T_MANUAL, T_NOOP, T_POSTGRES, T_SCHEDULE, Workflow, cfg, code,
    etsy_http, etsy_token, if_true, loop, openai_chat, openai_image, pos,
    postgres_query,
)
from prompts import library_js

# A 1x1 grey JPEG, used only when dry_run is on so the whole pipeline can be
# rehearsed - including the PDF writer - without paying for images.
DRY_RUN_JPEG = (
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB"
    "AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q=="
)

MONTHS = ["January", "February", "March", "April", "May", "June",
          "July", "August", "September", "October", "November", "December"]

# --------------------------------------------------------------------------
# Small pieces of JavaScript shared by several nodes.
# --------------------------------------------------------------------------
HELPERS_JS = r"""
// Read the assistant's reply out of an OpenAI chat completion, and fail with
// something a human can act on rather than "cannot read property of
// undefined" thirty lines later.
function agentText(response) {
  const choice = response && response.choices && response.choices[0];
  if (!choice) {
    const err = response && response.error;
    throw new Error('The model returned no choices' +
      (err ? `: ${err.message || JSON.stringify(err).slice(0, 200)}` : ''));
  }
  if (choice.finish_reason === 'length') {
    throw new Error('The model ran out of output tokens mid-answer. ' +
      'Raise max_tokens on this node, or ask for fewer sections.');
  }
  const text = choice.message && choice.message.content;
  if (!text || !String(text).trim()) throw new Error('The model returned an empty message');
  return String(text);
}

// Parse JSON that may arrive fenced in ```json ... ``` despite json_mode.
function agentJson(response, what) {
  const text = agentText(response);
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const body = (fenced ? fenced[1] : text).trim();
  try {
    return JSON.parse(body);
  } catch (e) {
    throw new Error(`${what}: the reply was not valid JSON (${e.message}). ` +
      `First 200 characters: ${body.slice(0, 200)}`);
  }
}

// Coerce a field the model may have answered with a string, an array or an
// object into an array of strings.
function asArray(value) {
  if (Array.isArray(value)) return value.map((v) => (typeof v === 'string' ? v : v));
  if (value === null || value === undefined || value === '') return [];
  if (typeof value === 'string') {
    return value.split(/[\n,]+/).map((s) => s.trim()).filter(Boolean);
  }
  if (typeof value === 'object') return Object.values(value).flatMap((v) => asArray(v));
  return [String(value)];
}

function require_(object, fields, what) {
  const missing = fields.filter((f) => {
    const v = object ? object[f] : undefined;
    return v === undefined || v === null || v === '' ||
      (Array.isArray(v) && v.length === 0);
  });
  if (missing.length) {
    throw new Error(`${what} is missing: ${missing.join(', ')}. ` +
      `Got these keys instead: ${Object.keys(object || {}).join(', ') || '(none)'}`);
  }
}

function slugify(text) {
  return String(text).toLowerCase().normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 60);
}

// Etsy rejects a tag over 20 characters, so a long phrase is cut back to its
// last whole word rather than mid-syllable ("tech leadership resu").
function toTag(text) {
  let tag = String(text).toLowerCase().normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9 ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (tag.length <= 20) return tag;
  tag = tag.slice(0, 20);
  const cut = tag.lastIndexOf(' ');
  return (cut > 6 ? tag.slice(0, cut) : tag).trim();
}
"""

JS_START = r"""
// Open the run: assign an id, read the request, and decide what mode we are in.
const cfg = $('""" + CONFIG_NODE + r"""').first().json.cfg;
const input = $input.first().json || {};

// A manual run passes nothing; a scheduled one passes nothing either. Both
// are real runs unless the caller explicitly asked for a rehearsal.
const dryRun = String(input.dry_run) === 'true';

const year = String(cfg.PLANNER_YEAR || '').trim();
if (year && !/^\d{4}$/.test(year)) {
  throw new Error(`PLANNER_YEAR must be four digits or empty (undated). Got "${year}".`);
}

const etsyReady = Boolean(String(cfg.ETSY_API_KEY || '').trim())
  && Boolean(String(cfg.ETSY_REFRESH_TOKEN || '').trim())
  && Boolean(String(cfg.ETSY_SHOP_ID || '').trim())
  && Boolean(String(cfg.ETSY_TAXONOMY_ID || '').trim());

const warnings = [];
if (!etsyReady) {
  warnings.push('Etsy is not configured (need ETSY_API_KEY, ETSY_REFRESH_TOKEN, ' +
    'ETSY_SHOP_ID and ETSY_TAXONOMY_ID). The planner will still be built and saved.');
}
if (!String(cfg.GDRIVE_FOLDER_ID || '').trim()) {
  warnings.push('GDRIVE_FOLDER_ID is empty, so the finished files are not backed up.');
}

return [{
  json: {
    run_id: `pf-${new Date().toISOString().replace(/[^0-9]/g, '').slice(0, 14)}-` +
            Math.random().toString(36).slice(2, 8),
    started_at: new Date().toISOString(),
    dry_run: dryRun,
    requested_niche: input.niche || null,
    planner_year: year || null,
    week_starts_monday: String(cfg.WEEK_STARTS_MONDAY) !== 'false',
    page_width_pt: Number(cfg.PAGE_WIDTH_PT) || 595.28,
    page_height_pt: Number(cfg.PAGE_HEIGHT_PT) || 841.89,
    section_art_count: Math.max(0, Math.min(4, Number(cfg.SECTION_ART_COUNT) || 2)),
    etsy_ready: etsyReady,
    publish: etsyReady && !dryRun,
    warnings,
    stage: 'start',
  },
}];
"""

JS_CONCEPT_PROMPT = r"""
// Build the user half of the concept prompt.
const run = $('Start Run').first().json;
const prompts = $('Prompt Library').first().json.prompts;

const asked = run.requested_niche
  ? `The shop owner asked specifically for this niche: "${run.requested_niche}". ` +
    'Use it unless it breaks one of the rules, in which case pick the closest niche that does not.'
  : 'No niche was requested. Choose one you think is underserved.';

// Slugs already made, so the concept agent does not propose the same product
// a second time. Empty on a fresh database, which is fine.
const madeBefore = ($('Recent Products').all() || [])
  .map((item) => item.json.product_name)
  .filter(Boolean);

const avoid = madeBefore.length
  ? `This shop has already published these, so choose something clearly different:\n- ${madeBefore.join('\n- ')}`
  : 'This shop has not published anything yet.';

return [{
  json: {
    ...run,
    stage: 'concept',
    concept_prompt: [asked, '', avoid, '', prompts.concept.contract].join('\n'),
  },
}];
"""

JS_PARSE_CONCEPT = HELPERS_JS + r"""
// Validate the concept before any money is spent on images.
const run = $('Build Concept Prompt').first().json;
const concept = agentJson($input.first().json, 'Concept agent');

require_(concept, ['niche', 'product_name', 'one_liner', 'buyer', 'search_phrase',
                   'keywords', 'extra_sections'], 'The concept');

const sections = asArray(concept.extra_sections).length
  ? concept.extra_sections
  : [];
const clean = (Array.isArray(sections) ? sections : [])
  .filter((s) => s && s.title)
  .map((s) => ({
    title: String(s.title).trim().slice(0, 40),
    kind: String(s.kind || 'lined').toLowerCase() === 'grid' ? 'grid' : 'lined',
    purpose: String(s.purpose || '').trim(),
  }));

// Six is the line between "a niche" and "a colour scheme" - the concept
// prompt says so, and this is where that promise is kept.
if (clean.length < 6) {
  throw new Error(
    `The concept only proposed ${clean.length} extra sections; a planner needs at ` +
    `least 6 beyond the twelve months. Sections offered: ` +
    `${clean.map((s) => s.title).join(', ') || '(none)'}`);
}

const year = run.planner_year;
const named = JSON.stringify(concept).match(/\b(19|20)\d{2}\b/);
if (!year && named) {
  throw new Error(
    `This is an undated planner but the concept names a year (${named[0]}). ` +
    `A dated product stops selling in January; rerun, or set PLANNER_YEAR.`);
}

const keywords = [...new Set(asArray(concept.keywords)
  .map((k) => toTag(k)).filter((k) => k.length >= 3))];
if (keywords.length < 8) {
  throw new Error(`Only ${keywords.length} usable keywords survived cleaning; ` +
    `Etsy needs 13 tags. Raw list: ${JSON.stringify(concept.keywords).slice(0, 200)}`);
}

const productName = String(concept.product_name).trim();
return [{
  json: {
    ...run,
    stage: 'concept-ok',
    concept: {
      ...concept,
      product_name: productName,
      slug: slugify(productName),
      keywords,
      extra_sections: clean.slice(0, 10),
    },
  },
}];
"""

JS_DUPLICATE_CHECK = r"""
// Refuse to rebuild something the shop already sells. Cheap here; expensive
// after the images have been generated.
const ctx = $('Parse Concept').first().json;
const existing = ($('Recent Products').all() || [])
  .map((item) => String(item.json.slug || ''))
  .filter(Boolean);

if (existing.includes(ctx.concept.slug)) {
  throw new Error(
    `"${ctx.concept.product_name}" already exists (slug ${ctx.concept.slug}). ` +
    `Run again to get a different concept, or pass a niche explicitly.`);
}
return [{ json: { ...ctx, stage: 'concept-unique' } }];
"""

JS_WRITER_PROMPT = r"""
const ctx = $('Check Duplicate').first().json;
const prompts = $('Prompt Library').first().json.prompts;
const c = ctx.concept;

const brief = [
  `Niche: ${c.niche}`,
  `Product: ${c.product_name}`,
  `Buyer: ${c.buyer}`,
  `Their problem: ${c.buyer_problem || '(not stated)'}`,
  `Tone: ${c.tone || 'calm, practical'}`,
  '',
  'The planner has twelve month pages (the calendar grids are drawn for you)',
  'and these extra sections, in this order:',
  ...c.extra_sections.map((s, i) => `${i + 1}. ${s.title} (${s.kind}) - ${s.purpose}`),
  '',
  'Write "sections" with one entry per extra section above, in the same order,',
  'with the same titles. For kind=grid give columns and rows; for kind=lined',
  'give prompts.',
  '',
  prompts.writer.contract,
].join('\n');

return [{ json: { ...ctx, stage: 'writing', writer_prompt: brief } }];
"""

JS_PARSE_WRITER = HELPERS_JS + r"""
// Turn the writer's reply into the exact page list the PDF writer needs.
// Structure is decided here, in code - the model only supplied words.
const ctx = $('Build Writer Prompt').first().json;
const content = agentJson($input.first().json, 'Writer agent');
require_(content, ['cover_title', 'welcome_lines', 'month_prompts', 'sections'],
         'The written content');

const MONTHS = """ + json.dumps(MONTHS) + r""";

// Draft markers are the one defect a buyer sees on page one. This looks for
// leftovers from the model, not for the template's own fill-in blanks.
const MARKERS = [
  /\bTODO\b/i, /\bFIXME\b/i, /lorem ipsum/i, /\bplaceholder\b/i,
  /\bcoming soon\b/i, /\bXXXX+\b/, /\{\{\s*\w+\s*\}\}/, /\[insert [^\]]*\]/i,
];
const scanned = [];
const scan = (text, where) => {
  const value = String(text || '');
  for (const marker of MARKERS) {
    const hit = value.match(marker);
    if (hit) scanned.push(`${where}: "${hit[0]}" in "${value.slice(0, 80)}"`);
  }
};

const welcome = asArray(content.welcome_lines);
welcome.forEach((line, i) => scan(line, `welcome line ${i + 1}`));

// ---- month prompts: exactly twelve, whatever the model returned ----------
const byMonth = new Map();
for (const entry of (Array.isArray(content.month_prompts) ? content.month_prompts : [])) {
  const n = Number(entry && entry.month);
  if (n >= 1 && n <= 12) byMonth.set(n, asArray(entry.prompts).slice(0, 2));
}
const missing = MONTHS.map((_, i) => i + 1).filter((n) => !(byMonth.get(n) || []).length);
if (missing.length > 3) {
  throw new Error(
    `The writer supplied prompts for only ${12 - missing.length} of 12 months. ` +
    `Missing: ${missing.map((n) => MONTHS[n - 1]).join(', ')}`);
}
// A handful of gaps are filled from the months that were written, rather than
// failing a run that is otherwise complete.
const pool = [...byMonth.values()].flat();
for (const n of missing) byMonth.set(n, [pool[n % pool.length] || 'What matters most this month?']);
for (const [n, list] of byMonth) list.forEach((p, i) => scan(p, `${MONTHS[n - 1]} prompt ${i + 1}`));

// ---- sections ------------------------------------------------------------
const wanted = ctx.concept.extra_sections;
const written = Array.isArray(content.sections) ? content.sections : [];
const sections = wanted.map((want, index) => {
  const match = written.find(
    (s) => s && String(s.title || '').toLowerCase().trim() === want.title.toLowerCase().trim()
  ) || written[index] || {};
  const kind = String(match.kind || want.kind).toLowerCase() === 'grid' ? 'grid' : 'lined';
  const columns = asArray(match.columns).map((c) => String(c).slice(0, 14));
  const prompts = asArray(match.prompts);
  scan(match.intro, `section "${want.title}" intro`);
  asArray(match.instructions).forEach((l, i) => scan(l, `section "${want.title}" line ${i + 1}`));
  prompts.forEach((p, i) => scan(p, `section "${want.title}" prompt ${i + 1}`));

  // A grid with no columns is not a grid. Rather than shipping an empty
  // table, it degrades to a lined page, which always works.
  if (kind === 'grid' && columns.length < 2) {
    return { title: want.title, kind: 'lined', intro: String(match.intro || ''),
             instructions: asArray(match.instructions),
             prompts: prompts.length ? prompts : [`Use this page for ${want.title.toLowerCase()}.`] };
  }
  return {
    title: want.title,
    kind,
    intro: String(match.intro || ''),
    instructions: asArray(match.instructions),
    columns: columns.slice(0, 8),
    row_labels: asArray(match.row_labels).slice(0, 8),
    rows: Math.min(20, Math.max(8, Number(match.rows) || 12)),
    prompts: prompts.slice(0, 5),
  };
});

if (scanned.length) {
  throw new Error(`Draft markers left in the copy - this cannot ship:\n- ` +
                  scanned.slice(0, 6).join('\n- '));
}

return [{
  json: {
    ...ctx,
    stage: 'written',
    content: {
      cover_title: String(content.cover_title).trim(),
      cover_subtitle: String(content.cover_subtitle || ctx.concept.one_liner).trim(),
      welcome_title: String(content.welcome_title || 'How to use this planner').trim(),
      welcome_lines: welcome,
      month_prompts: MONTHS.map((_, i) => byMonth.get(i + 1) || []),
      sections,
      credits: String(content.credits || '').trim(),
    },
  },
}];
"""

JS_ART_PROMPT = r"""
const ctx = $('Parse Writer').first().json;
const prompts = $('Prompt Library').first().json.prompts;
const c = ctx.concept;

return [{
  json: {
    ...ctx,
    stage: 'art-direction',
    art_prompt: [
      `Planner: ${c.product_name}`,
      `Niche: ${c.niche}`,
      `Buyer: ${c.buyer}`,
      `Palette direction from the concept: ${c.colour_direction || 'calm neutrals'}`,
      `Number of section dividers needed: ${ctx.section_art_count}`,
      '',
      prompts.art.contract,
    ].join('\n'),
  },
}];
"""

JS_PARSE_ART = HELPERS_JS + r"""
// Check the art direction before it reaches the image model, because a prompt
// that asks for lettering produces an unusable image and still costs money.
const ctx = $('Build Art Prompt').first().json;
const art = agentJson($input.first().json, 'Art agent');
require_(art, ['cover_prompt', 'thumbnail_prompt'], 'The art direction');

// Words that mean "draw type". Checked against the prompt we are about to
// send, not against the picture we get back, because by then it is paid for.
const TYPE_WORDS = /\b(text|typography|lettering|letters?|words?|title|caption|label(?:s|led)?|font|handwriting|calligraphy|monogram|signature|numbers?|dates?|calendar grid|planner page|mockup)\b/i;
const NEGATED = /\b(no|without|avoid|never|free of|excluding)\b[^.]{0,40}$/i;

const check = (prompt, where) => {
  const value = String(prompt || '');
  if (!value.trim()) throw new Error(`${where} is empty`);
  for (const sentence of value.split(/(?<=[.;])\s+/)) {
    const hit = sentence.match(TYPE_WORDS);
    if (!hit) continue;
    // "no text, no lettering" is the instruction we want, not a violation.
    if (NEGATED.test(sentence.slice(0, hit.index))) continue;
    throw new Error(
      `${where} asks the image model for type, which it renders badly and which ` +
      `gets the product rejected: "${sentence.trim().slice(0, 120)}"`);
  }
  return value.trim();
};

const sectionPrompts = asArray(art.section_prompts);
const wanted = ctx.section_art_count;
while (sectionPrompts.length < wanted) {
  sectionPrompts.push(sectionPrompts[sectionPrompts.length - 1] || art.cover_prompt);
}

const suffix = ' No text, no letters, no numbers, no words anywhere in the image.';
return [{
  json: {
    ...ctx,
    stage: 'art-ready',
    art: {
      palette: String(art.palette || ''),
      cover_prompt: check(art.cover_prompt, 'cover_prompt') + suffix,
      thumbnail_prompt: check(art.thumbnail_prompt, 'thumbnail_prompt') + suffix,
      section_prompts: sectionPrompts.slice(0, wanted)
        .map((p, i) => check(p, `section_prompts[${i}]`) + suffix),
    },
  },
}];
"""

JS_IMAGE_JOBS = r"""
// One item per image to generate, so the loop below can be a plain loop and
// the cost is visible as a row count rather than hidden in a branch.
const ctx = $('Parse Art').first().json;
const cfg = $('""" + CONFIG_NODE + r"""').first().json.cfg;

const jobs = [
  { role: 'cover', prompt: ctx.art.cover_prompt, size: '1024x1536',
    quality: cfg.IMAGE_QUALITY_COVER || 'high' },
  { role: 'thumbnail', prompt: ctx.art.thumbnail_prompt, size: '1024x1024',
    quality: cfg.IMAGE_QUALITY_THUMB || 'low' },
];
ctx.art.section_prompts.forEach((prompt, index) => {
  jobs.push({ role: `section_${index + 1}`, prompt, size: '1024x1536',
              quality: cfg.IMAGE_QUALITY_SECTION || 'medium' });
});

return jobs.map((job) => ({ json: { ...job, run_id: ctx.run_id, dry_run: ctx.dry_run } }));
"""

JS_DRY_IMAGE = r"""
// Rehearsal mode: hand back a real (tiny) JPEG so every later step - including
// the PDF writer - runs exactly as it would on a paid run.
const job = $input.first().json;
return [{ json: { ...job, b64: '""" + DRY_RUN_JPEG + r"""', dry: true } }];
"""

JS_COLLECT_IMAGE = r"""
// The image endpoint answers with data[0].b64_json. Anything else is an error
// worth surfacing here, next to the job that caused it.
const job = $('Loop Images').first().json;
const response = $input.first().json;
const b64 = response && response.data && response.data[0] && response.data[0].b64_json;
if (!b64) {
  throw new Error(`No image came back for "${job.role}": ` +
                  JSON.stringify(response).slice(0, 300));
}
return [{ json: { ...job, b64 } }];
"""

JS_GATHER_IMAGES = r"""
// Fold every generated image into one item keyed by role.
const ctx = $('Parse Art').first().json;
const images = {};
for (const item of $input.all()) {
  if (item.json && item.json.role && item.json.b64) images[item.json.role] = item.json.b64;
}
const expected = ['cover', 'thumbnail',
  ...ctx.art.section_prompts.map((_, i) => `section_${i + 1}`)];
const missing = expected.filter((role) => !images[role]);
if (missing.length) throw new Error(`Missing generated images: ${missing.join(', ')}`);

return [{ json: { ...ctx, stage: 'art-done', images } }];
"""

JS_BUILD_PDF = PDF_LIB_JS + r"""

// ---------------------------------------------------------------------------
// Assemble the planner. Every structural decision is made here, in code.
// ---------------------------------------------------------------------------
const ctx = $('Gather Images').first().json;
const content = ctx.content;
const images = ctx.images;
const MONTHS = """ + json.dumps(MONTHS) + r""";

const year = ctx.planner_year ? Number(ctx.planner_year) : null;
const footerLabel = `${ctx.concept.product_name} - personal use`;

// ---- navigation ------------------------------------------------------------
// Twelve month tabs plus Contents is thirteen, which is the most a tab strip
// can carry legibly. The extra sections are reachable from the contents page.
const tabs = [{ label: 'Contents', anchor: 'contents' }].concat(
  MONTHS.map((name, index) => ({ label: name.slice(0, 3), anchor: `m${index + 1}` })));

const contentsRows = MONTHS.map((name, index) => ({
  label: year ? `${name} ${year}` : name,
  anchor: `m${index + 1}`,
})).concat(content.sections.map((section, index) => ({
  label: section.title,
  anchor: `s${index + 1}`,
})));

// Derived from the writer's geometry: title block, subtitle, margins and a
// 1.7x row pitch. Cross-checked by the dropped-row guard at the end.
const rowsPerContentsPage = Math.max(8, Math.floor((ctx.page_height_pt - 200) / 29));

const pages = [];

// 1. Cover: full-bleed art, then the title page.
pages.push({ type: 'image', jpeg_base64: images.cover, full_bleed: true });
pages.push({
  type: 'text', cover: true, anchor: 'cover',
  title: content.cover_title,
  subtitle: content.cover_subtitle,
  lines: ['', ctx.concept.one_liner, ''],
  footer: footerLabel,
});

// 2. How to use.
pages.push({
  type: 'text', anchor: 'welcome',
  title: content.welcome_title,
  lines: content.welcome_lines,
  footer: footerLabel,
});

// 3. Contents, spilling onto as many sheets as it needs.
for (let row = 0; row < contentsRows.length; row += rowsPerContentsPage) {
  const first = row === 0;
  pages.push({
    type: 'text',
    title: first ? 'Contents' : 'Contents (continued)',
    subtitle: first ? 'Tap a line to jump. The tabs on the right work from every page.' : undefined,
    anchor: first ? 'contents' : undefined,
    index: contentsRows.slice(row, row + rowsPerContentsPage),
    footer: footerLabel,
  });
}

// 4. Twelve months. The grid is computed, not written.
MONTHS.forEach((name, index) => {
  pages.push({
    type: 'month',
    title: year ? `${name} ${year}` : name,
    subtitle: year ? undefined : 'Undated - write your own dates',
    anchor: `m${index + 1}`,
    month_number: index + 1,
    year,
    week_starts_monday: ctx.week_starts_monday,
    side_title: 'This month',
    side_lines: content.month_prompts[index],
    footer: `${footerLabel} | ${name}`,
  });
});

// 5. Section dividers and the extra sections.
const dividers = Object.keys(images).filter((role) => role.startsWith('section_')).sort();
content.sections.forEach((section, index) => {
  // Dividers are spread evenly through the sections rather than stacked at
  // the front, so the file reads as chapters.
  const every = Math.max(1, Math.ceil(content.sections.length / (dividers.length || 1)));
  if (dividers.length && index % every === 0) {
    const art = images[dividers[Math.min(dividers.length - 1, Math.floor(index / every))]];
    if (art) pages.push({ type: 'image', jpeg_base64: art, caption: section.title,
                          footer: footerLabel });
  }
  const base = {
    anchor: `s${index + 1}`,
    title: section.title,
    subtitle: section.intro || undefined,
    footer: `${footerLabel} | ${section.title}`,
  };
  if (section.kind === 'grid') {
    pages.push({ ...base, type: 'grid', lines: section.instructions,
                 columns: section.columns, rows: section.rows,
                 row_labels: section.row_labels });
  } else {
    pages.push({ ...base, type: 'lined', lines: section.prompts,
                 lines_per_prompt: 3 });
  }
});

// 6. Licence.
pages.push({
  type: 'text', title: 'Licence',
  lines: [
    'This planner is licensed for personal use by the buyer.',
    '',
    'You may print it as often as you like for yourself and your household,',
    'and use it in any app that opens a PDF.',
    '',
    'You may not resell, redistribute, or share the file, and you may not sell',
    'anything made by exporting or tracing its pages.',
    '',
    content.credits,
  ].filter((line) => line !== undefined),
  footer: footerLabel,
});

const result = buildPdf({
  width: ctx.page_width_pt,
  height: ctx.page_height_pt,
  tabs,
  pages,
  info: {
    title: ctx.concept.product_name,
    subject: ctx.concept.niche,
    keywords: ctx.concept.keywords.join(', '),
  },
});

// The two failures that are invisible in the data and obvious to a buyer.
if (result.link_count < 12) {
  throw new Error(`Only ${result.link_count} working links in the PDF ` +
    `(${result.broken_links} dropped). The tabs are the product.`);
}
if (result.dropped_index_rows) {
  throw new Error(`${result.dropped_index_rows} contents rows did not fit on the page. ` +
    `rowsPerContentsPage (${rowsPerContentsPage}) is too high for a ${ctx.page_height_pt}pt sheet.`);
}

return [{
  json: {
    ...ctx,
    stage: 'pdf-built',
    pdf: {
      base64: result.buffer.toString('base64'),
      bytes: result.buffer.length,
      page_count: result.page_count,
      link_count: result.link_count,
    },
  },
}];
"""

JS_QA = r"""
// The last gate before anything is published. Everything here is checkable
// arithmetic - no model is asked whether its own work is good.
const ctx = $('Build PDF').first().json;
const problems = [];
const pdf = ctx.pdf;

const buffer = Buffer.from(pdf.base64, 'base64');
if (buffer.slice(0, 8).toString('latin1').indexOf('%PDF-') !== 0) {
  problems.push('the PDF does not start with a PDF header');
}
if (buffer.slice(-1024).toString('latin1').indexOf('%%EOF') === -1) {
  problems.push('the PDF has no end-of-file marker');
}

// Twelve months, a contents page and a cover is 15 sheets before any extras.
if (pdf.page_count < 20) {
  problems.push(`only ${pdf.page_count} pages - a planner this thin will be returned`);
}
if (pdf.bytes < 40000) {
  problems.push(`the file is only ${pdf.bytes} bytes, which means the art is missing`);
}
if (ctx.content.sections.length < 6) {
  problems.push(`only ${ctx.content.sections.length} extra sections survived writing`);
}

// Every month must be reachable: twelve tabs on every page is the whole
// difference between this and a stack of printables.
if (pdf.link_count < ctx.pdf.page_count) {
  problems.push(`${pdf.link_count} links across ${pdf.page_count} pages - ` +
    'the tab strip is not on every page');
}

const shortPrompts = ctx.content.month_prompts
  .map((list, index) => ({ index, list }))
  .filter((m) => !m.list.length);
if (shortPrompts.length) {
  problems.push(`months with no prompt: ${shortPrompts.map((m) => m.index + 1).join(', ')}`);
}

if (problems.length) {
  throw new Error('QA rejected this planner:\n- ' + problems.join('\n- '));
}

return [{ json: { ...ctx, stage: 'qa-passed', qa: { passed: true, checks: 7 } } }];
"""

JS_LISTING_PROMPT = r"""
const ctx = $('QA Gate').first().json;
const prompts = $('Prompt Library').first().json.prompts;
const c = ctx.concept;

return [{
  json: {
    ...ctx,
    stage: 'listing',
    listing_prompt: [
      `Product: ${c.product_name}`,
      `Niche: ${c.niche}`,
      `Buyer: ${c.buyer}`,
      `Their problem: ${c.buyer_problem || '(not stated)'}`,
      `They would search: ${c.search_phrase}`,
      `Keyword ideas: ${c.keywords.join(', ')}`,
      '',
      `The finished file: a ${ctx.pdf.page_count}-page undated PDF planner with`,
      `twelve tabbed month calendars, a tappable contents page, and these sections:`,
      ...ctx.content.sections.map((s) => `- ${s.title}`),
      '',
      'It is a digital download. Nothing is posted.',
      '',
      prompts.listing.contract,
    ].join('\n'),
  },
}];
"""

JS_PARSE_LISTING = HELPERS_JS + r"""
// Etsy rejects a bad listing after the upload, so the rules are enforced here.
const ctx = $('Build Listing Prompt').first().json;
const listing = agentJson($input.first().json, 'Listing agent');
require_(listing, ['title', 'description', 'tags'], 'The listing');

let title = String(listing.title).replace(/\s+/g, ' ').trim();
if (title.length > 140) title = title.slice(0, 140).replace(/\s+\S*$/, '');
if (/\b[A-Z]{4,}\b/.test(title)) {
  throw new Error(`The listing title shouts, which Etsy penalises: "${title}"`);
}

// Thirteen tags, each at most twenty characters, no duplicates. Topped up
// from the concept keywords rather than failing when the model is short.
const seen = new Set();
const tags = [];
for (const raw of asArray(listing.tags).concat(ctx.concept.keywords)) {
  const tag = toTag(raw);
  if (tag.length < 3 || seen.has(tag)) continue;
  seen.add(tag);
  tags.push(tag);
  if (tags.length === 13) break;
}
if (tags.length < 13) {
  throw new Error(`Only ${tags.length} usable tags after cleaning; Etsy wants 13. ` +
    `From: ${JSON.stringify(listing.tags).slice(0, 200)}`);
}

const description = String(listing.description).trim();
if (description.length < 300) {
  throw new Error(`The description is ${description.length} characters; ` +
    'a listing that short does not convert.');
}
if (/<[a-z/][^>]*>/i.test(description)) {
  throw new Error('The description contains HTML, which Etsy shows as raw tags.');
}

const cfgPrice = Number($('""" + CONFIG_NODE + r"""').first().json.cfg.ETSY_PRICE_USD);
const modelPrice = Number(listing.price_usd);
const price = Number.isFinite(cfgPrice) && cfgPrice > 0
  ? cfgPrice
  : (Number.isFinite(modelPrice) ? Math.min(30, Math.max(5, modelPrice)) : 12);

return [{
  json: {
    ...ctx,
    stage: 'listing-ready',
    listing: {
      title,
      description: description + '\n\nThis is a digital download. Nothing will be ' +
        'posted to you. You will receive the file(s) immediately after purchase.',
      tags,
      materials: asArray(listing.materials).map((m) => toTag(m)).filter(Boolean).slice(0, 13),
      price_usd: price,
    },
  },
}];
"""

JS_ETSY_DRAFT = r"""
// The listing body. Etsy wants price as a number and tags as a comma string.
const ctx = $('Parse Listing').first().json;
const cfg = $('""" + CONFIG_NODE + r"""').first().json.cfg;

return [{
  json: {
    ...ctx,
    stage: 'publishing',
    etsy_body: {
      quantity: Number(cfg.ETSY_QUANTITY) || 999,
      title: ctx.listing.title,
      description: ctx.listing.description,
      price: Number(ctx.listing.price_usd),
      who_made: 'i_did',
      when_made: 'made_to_order',
      taxonomy_id: Number(cfg.ETSY_TAXONOMY_ID),
      listing_type: 'download',
      // A draft is reviewable before it goes live; set ETSY_LISTING_STATE to
      // 'active' once you trust the output.
      state: String(cfg.ETSY_LISTING_STATE || 'draft').toLowerCase(),
      tags: ctx.listing.tags.join(','),
      materials: ctx.listing.materials.join(','),
      should_auto_renew: false,
      is_supply: false,
      is_personalizable: false,
    },
  },
}];
"""

JS_ETSY_UPLOADS = r"""
// One item per upload: the shop images first, then the file itself.
const ctx = $('Prepare Etsy Draft').first().json;
const created = $input.first().json;
const listingId = created && (created.listing_id || created.results?.[0]?.listing_id);
if (!listingId) {
  throw new Error('Etsy created no listing id. Reply was: ' +
    JSON.stringify(created).slice(0, 300));
}

const uploads = [
  { kind: 'image', rank: 1, role: 'cover', b64: ctx.images.cover,
    name: `${ctx.concept.slug}-cover.jpg` },
  { kind: 'image', rank: 2, role: 'thumbnail', b64: ctx.images.thumbnail,
    name: `${ctx.concept.slug}-thumb.jpg` },
];
Object.keys(ctx.images)
  .filter((role) => role.startsWith('section_'))
  .sort()
  .forEach((role, index) => {
    uploads.push({ kind: 'image', rank: 3 + index, role, b64: ctx.images[role],
                   name: `${ctx.concept.slug}-${role}.jpg` });
  });
uploads.push({ kind: 'file', rank: 1, role: 'pdf', b64: ctx.pdf.base64,
               name: `${ctx.concept.slug}.pdf` });

return uploads.map((upload) => ({
  json: { ...upload, listing_id: listingId, run_id: ctx.run_id },
}));
"""

JS_UPLOAD_BINARY = r"""
// Etsy takes multipart uploads, so each item needs its bytes as binary.
const job = $input.first().json;
const buffer = Buffer.from(job.b64, 'base64');
return [{
  json: { ...job, b64: undefined },
  binary: {
    upload: await this.helpers.prepareBinaryData(
      buffer, job.name, job.kind === 'file' ? 'application/pdf' : 'image/jpeg'),
  },
}];
"""

JS_FINISH = r"""
// One summary item: what was made, what it cost, and where it went.
const ctx = $('QA Gate').first().json;
const listing = $('Parse Listing').first().json.listing || null;
// Read the decision, not the publish branch: on a run that skipped Etsy, the
// upload nodes never executed and $('Collect Uploads') would throw.
const published = $('Start Run').first().json.publish === true;

return [{
  json: {
    run_id: ctx.run_id,
    status: 'succeeded',
    stage: 'done',
    dry_run: ctx.dry_run,
    product_name: ctx.concept.product_name,
    slug: ctx.concept.slug,
    niche: ctx.concept.niche,
    search_phrase: ctx.concept.search_phrase,
    keywords: ctx.concept.keywords,
    page_count: ctx.pdf.page_count,
    link_count: ctx.pdf.link_count,
    pdf_bytes: ctx.pdf.bytes,
    sections: ctx.content.sections.map((s) => s.title),
    listing_title: listing ? listing.title : null,
    listing_tags: listing ? listing.tags : [],
    price_usd: listing ? listing.price_usd : null,
    published,
    warnings: ctx.warnings,
    finished_at: new Date().toISOString(),
  },
}];
"""

JS_FORMAT_ERROR = r"""
// The Error Trigger path. Planner Config has not run here, so nothing is read
// from it - this node only has the failure to work with.
const error = $input.first().json;
const execution = error.execution || {};
const trigger = error.trigger || {};

// n8n keeps only the tail of a long message, so the useful part goes first.
const message = String(execution.error?.message || trigger.error?.message || 'unknown error');
return [{
  json: {
    status: 'failed',
    failed_node: execution.lastNodeExecuted || null,
    message: message.slice(0, 900),
    workflow: error.workflow?.name || 'Planner Factory',
    execution_url: execution.url || null,
    failed_at: new Date().toISOString(),
  },
}];
"""


def build() -> dict:
    wf = Workflow("01", "Planner Factory")

    # -- entry ------------------------------------------------------------
    wf.add("Run Manually", T_MANUAL, pos(0, 0), {},
           notes="กดปุ่มนี้เพื่อสร้าง planner หนึ่งเล่ม")
    wf.add("Weekly Schedule", T_SCHEDULE, pos(0, 1),
           {"rule": {"interval": [{"field": "weeks", "triggerAtDay": [1],
                                   "triggerAtHour": 9}]}},
           notes="สร้างอัตโนมัติสัปดาห์ละเล่ม (ปิดไว้ก่อน - เปิดเมื่อพอใจผลลัพธ์แล้ว)")
    wf.add(CONFIG_NODE, T_CODE, pos(1, 0.5), code(_config_body()),
           notes="ค่าตั้งค่าทั้งหมดอยู่ที่นี่ - ดับเบิลคลิกเพื่อแก้ (Etsy, ราคา, ขนาดหน้า, ปี)")
    wf.add("Prompt Library", T_CODE, pos(2, 0.5), code(library_js()),
           notes="คำสั่งของ AI ทั้ง 4 ตัว แก้ข้อความได้ที่นี่ที่เดียว")
    wf.add("Start Run", T_CODE, pos(3, 0.5), code(JS_START),
           notes="ตั้ง run_id, ตรวจว่า Etsy/Drive ตั้งค่าครบไหม, และตัดสินว่าจะ publish หรือไม่")

    wf.add("Log Run Start", T_POSTGRES, pos(3.5, 0.5),
           postgres_query(
               "INSERT INTO planner_runs (run_id, status, stage, dry_run, prompt_version) "
               "VALUES ('{{ $json.run_id }}', 'running', 'start', "
               "{{ $json.dry_run }}, "
               "'{{ $('Prompt Library').first().json.prompt_version }}') "
               "ON CONFLICT (run_id) DO NOTHING;"),
           notes="เปิดรอบในฐานข้อมูล - planner_products อ้างถึงแถวนี้ จึงต้องมีก่อน",
           onError="continueRegularOutput")

    wf.link("Run Manually", CONFIG_NODE)
    wf.link("Weekly Schedule", CONFIG_NODE)
    wf.chain(CONFIG_NODE, "Prompt Library", "Start Run", "Log Run Start")

    # -- concept ----------------------------------------------------------
    wf.add("Recent Products", T_POSTGRES, pos(4, 0.5),
           postgres_query(
               "SELECT slug, product_name FROM planner_products "
               "ORDER BY created_at DESC LIMIT 40;"),
           notes="รายชื่อสินค้าที่เคยทำแล้ว - ใช้กันสร้างซ้ำ (ถ้ายังไม่มีตารางจะว่าง)",
           alwaysOutputData=True, onError="continueRegularOutput")
    wf.add("Build Concept Prompt", T_CODE, pos(5, 0.5), code(JS_CONCEPT_PROMPT),
           notes="ประกอบโจทย์ให้ AI ตัวที่ 1 พร้อมรายการสินค้าเดิมที่ห้ามซ้ำ")
    wf.add("AI: Concept", T_HTTP, pos(6, 0.5),
           openai_chat("$('Prompt Library').first().json.prompts.concept.system",
                       "$json.concept_prompt", temperature=0.9, max_tokens=2000),
           notes="AI 1/4 - เลือก niche และตั้งชื่อสินค้า", **RETRY)
    wf.add("Parse Concept", T_CODE, pos(7, 0.5), code(JS_PARSE_CONCEPT),
           notes="ตรวจ concept: ต้องมี section อย่างน้อย 6, keyword 8+, ห้ามมีปี")
    wf.add("Check Duplicate", T_CODE, pos(8, 0.5), code(JS_DUPLICATE_CHECK),
           notes="หยุดทันทีถ้าเคยทำสินค้าชื่อนี้แล้ว (ก่อนจ่ายค่าภาพ)")

    wf.chain("Log Run Start", "Recent Products", "Build Concept Prompt",
             "AI: Concept", "Parse Concept", "Check Duplicate")

    # -- writing ----------------------------------------------------------
    wf.add("Build Writer Prompt", T_CODE, pos(9, 0.5), code(JS_WRITER_PROMPT),
           notes="บอก AI ว่าต้องเขียนอะไรบ้าง (12 เดือน + section ตามที่ concept กำหนด)")
    wf.add("AI: Writer", T_HTTP, pos(10, 0.5),
           openai_chat("$('Prompt Library').first().json.prompts.writer.system",
                       "$json.writer_prompt", temperature=0.7, max_tokens=6000),
           notes="AI 2/4 - เขียนข้อความทั้งเล่ม (ไม่แตะ layout)", **RETRY)
    wf.add("Parse Writer", T_CODE, pos(11, 0.5), code(JS_PARSE_WRITER),
           notes="แปลงข้อความเป็นโครงหน้า + ตรวจคำค้างแบบ TODO/placeholder")

    wf.chain("Check Duplicate", "Build Writer Prompt", "AI: Writer", "Parse Writer")

    # -- art --------------------------------------------------------------
    wf.add("Build Art Prompt", T_CODE, pos(12, 0.5), code(JS_ART_PROMPT),
           notes="ประกอบโจทย์ให้ AI ออกแบบภาพ")
    wf.add("AI: Art Direction", T_HTTP, pos(13, 0.5),
           openai_chat("$('Prompt Library').first().json.prompts.art.system",
                       "$json.art_prompt", temperature=0.8, max_tokens=1500),
           notes="AI 3/4 - เขียน prompt ภาพ (ยังไม่เสียค่าภาพ)", **RETRY)
    wf.add("Parse Art", T_CODE, pos(14, 0.5), code(JS_PARSE_ART),
           notes="กันไม่ให้ prompt สั่งวาดตัวหนังสือ - ภาพที่มีตัวอักษรใช้ไม่ได้และเสียเงินฟรี")

    wf.chain("Parse Writer", "Build Art Prompt", "AI: Art Direction", "Parse Art")

    # -- images -----------------------------------------------------------
    wf.add("Image Jobs", T_CODE, pos(15, 0.5), code(JS_IMAGE_JOBS),
           notes="แตกเป็นงานละ 1 ภาพ: ปก + thumbnail + ภาพคั่น")
    wf.add("Loop Images", T_LOOP, pos(16, 0.5), loop(1),
           notes="วนสร้างทีละภาพ - ถ้าพังจะรู้ว่าพังที่ภาพไหน")
    wf.add("Is Dry Run?", T_IF, pos(17, 1), if_true("={{ $json.dry_run }}"),
           notes="โหมดซ้อม: ข้ามการเรียก OpenAI (ไม่เสียเงิน)")
    wf.add("Placeholder Image", T_CODE, pos(18, 1.6), code(JS_DRY_IMAGE),
           notes="ภาพจำลองสำหรับโหมดซ้อม - ทำให้ทุกขั้นตอนหลังจากนี้ทำงานจริง")
    wf.add("OpenAI: Image", T_HTTP, pos(18, 0.4),
           openai_image("$json.prompt", "$json.size", "$json.quality"),
           notes="AI 4/4 - สร้างภาพจริง (นี่คือขั้นที่เสียเงินมากที่สุด)", **RETRY)
    wf.add("Collect Image", T_CODE, pos(19, 0.4), code(JS_COLLECT_IMAGE),
           notes="ดึง base64 ออกจากคำตอบ และบอกชัดว่าภาพไหนพัง")
    wf.add("Gather Images", T_CODE, pos(18, -0.6), code(JS_GATHER_IMAGES),
           notes="รวมภาพทั้งหมดเป็นก้อนเดียว + ตรวจว่าครบทุกบทบาท")

    wf.chain("Parse Art", "Image Jobs", "Loop Images")
    wf.link("Loop Images", "Gather Images", 0)       # done branch
    wf.link("Loop Images", "Is Dry Run?", 1)         # per-item branch
    wf.link("Is Dry Run?", "Placeholder Image", 0)
    wf.link("Is Dry Run?", "OpenAI: Image", 1)
    wf.link("OpenAI: Image", "Collect Image")
    wf.link("Collect Image", "Loop Images")
    wf.link("Placeholder Image", "Loop Images")

    # -- build + QA -------------------------------------------------------
    wf.add("Build PDF", T_CODE, pos(19, -0.6), code(JS_BUILD_PDF),
           notes="ประกอบ PDF ทั้งเล่ม: ปก, สารบัญกดได้, ปฏิทิน 12 เดือน, section, ใบอนุญาต")
    wf.add("QA Gate", T_CODE, pos(20, -0.6), code(JS_QA),
           notes="ด่านสุดท้าย - ตรวจด้วยตัวเลขล้วน ไม่ถาม AI ว่างานตัวเองดีไหม")

    wf.chain("Gather Images", "Build PDF", "QA Gate")

    # -- listing copy -----------------------------------------------------
    wf.add("Build Listing Prompt", T_CODE, pos(21, -0.6), code(JS_LISTING_PROMPT),
           notes="ประกอบโจทย์เขียนหน้าขาย Etsy จากไฟล์ที่ทำเสร็จจริง")
    wf.add("AI: Listing", T_HTTP, pos(22, -0.6),
           openai_chat("$('Prompt Library').first().json.prompts.listing.system",
                       "$json.listing_prompt", temperature=0.7, max_tokens=2500),
           notes="เขียนชื่อสินค้า คำอธิบาย และ 13 tags", **RETRY)
    wf.add("Parse Listing", T_CODE, pos(23, -0.6), code(JS_PARSE_LISTING),
           notes="บังคับกติกา Etsy: title <=140, tag 13 อัน อันละ <=20 ตัวอักษร, ห้าม HTML")

    wf.chain("QA Gate", "Build Listing Prompt", "AI: Listing", "Parse Listing")

    # -- publish ----------------------------------------------------------
    wf.add("Should Publish?", T_IF, pos(24, -0.6),
           if_true("={{ $('Start Run').first().json.publish }}"),
           notes="ยิงขึ้น Etsy เฉพาะเมื่อตั้งค่าครบและไม่ใช่โหมดซ้อม")
    wf.add(ETSY_TOKEN_NODE, T_HTTP, pos(25, -1.2), etsy_token(),
           notes="แลก refresh token เป็น access token (Etsy บังคับ PKCE จึงใช้วิธีนี้)",
           **RETRY)
    wf.add("Prepare Etsy Draft", T_CODE, pos(26, -1.2), code(JS_ETSY_DRAFT),
           notes="ประกอบข้อมูลสินค้าตามรูปแบบที่ Etsy ต้องการ")
    wf.add("Etsy: Create Listing", T_HTTP, pos(27, -1.2),
           etsy_http("POST",
                     "={{ " + cfg("ETSY_API_BASE") + " }}/v3/application/shops/{{ "
                     + cfg("ETSY_SHOP_ID") + " }}/listings",
                     body_expr="={{ JSON.stringify($json.etsy_body) }}"),
           notes="สร้างรายการขาย (state=draft เพื่อให้ตรวจก่อนเปิดจริง)", **RETRY)
    wf.add("Plan Uploads", T_CODE, pos(28, -1.2), code(JS_ETSY_UPLOADS),
           notes="แตกเป็นงานอัปโหลด: ภาพร้านทุกใบ + ไฟล์ PDF")
    wf.add("Loop Uploads", T_LOOP, pos(29, -1.2), loop(1),
           notes="อัปโหลดทีละไฟล์ - Etsy จำกัดขนาดและจำนวนต่อครั้ง")
    wf.add("To Binary", T_CODE, pos(30, -0.8), code(JS_UPLOAD_BINARY),
           notes="แปลง base64 เป็นไฟล์จริงสำหรับอัปโหลดแบบ multipart")
    wf.add("Is File?", T_IF, pos(31, -0.8),
           if_true("={{ $json.kind === 'file' }}"),
           notes="ไฟล์ PDF กับภาพร้านใช้คนละ endpoint")
    wf.add("Etsy: Upload File", T_HTTP, pos(32, -0.4),
           etsy_http("POST",
                     "={{ " + cfg("ETSY_API_BASE") + " }}/v3/application/shops/{{ "
                     + cfg("ETSY_SHOP_ID") + " }}/listings/{{ $json.listing_id }}/files",
                     multipart=[
                         {"parameterType": "formBinaryData", "name": "file",
                          "inputDataFieldName": "upload"},
                         {"name": "name", "value": "={{ $json.name }}"},
                         {"name": "rank", "value": "={{ $json.rank }}"},
                     ]),
           notes="อัปโหลดไฟล์ที่ผู้ซื้อจะได้รับ", **RETRY)
    wf.add("Etsy: Upload Image", T_HTTP, pos(32, -1.2),
           etsy_http("POST",
                     "={{ " + cfg("ETSY_API_BASE") + " }}/v3/application/shops/{{ "
                     + cfg("ETSY_SHOP_ID") + " }}/listings/{{ $json.listing_id }}/images",
                     multipart=[
                         {"parameterType": "formBinaryData", "name": "image",
                          "inputDataFieldName": "upload"},
                         {"name": "rank", "value": "={{ $json.rank }}"},
                     ]),
           notes="อัปโหลดภาพที่แสดงในหน้าร้าน", **RETRY)
    wf.add("Collect Uploads", T_NOOP, pos(33, -1.2), {},
           notes="จุดรวมผลอัปโหลด")

    wf.link("Parse Listing", "Should Publish?")
    wf.link("Should Publish?", ETSY_TOKEN_NODE, 0)
    wf.chain(ETSY_TOKEN_NODE, "Prepare Etsy Draft", "Etsy: Create Listing",
             "Plan Uploads", "Loop Uploads")
    wf.link("Loop Uploads", "Collect Uploads", 0)
    wf.link("Loop Uploads", "To Binary", 1)
    wf.link("To Binary", "Is File?")
    wf.link("Is File?", "Etsy: Upload File", 0)
    wf.link("Is File?", "Etsy: Upload Image", 1)
    wf.link("Etsy: Upload File", "Loop Uploads")
    wf.link("Etsy: Upload Image", "Loop Uploads")

    # -- finish -----------------------------------------------------------
    wf.add("Summarise Run", T_CODE, pos(34, -0.6), code(JS_FINISH),
           notes="สรุปผลรอบนี้: ได้สินค้าอะไร กี่หน้า ลิงก์กี่จุด ขึ้น Etsy หรือยัง")
    wf.add("Save Product", T_POSTGRES, pos(35, -0.6),
           postgres_query(
               "INSERT INTO planner_products "
               "(run_id, product_name, slug, niche, search_phrase, keywords, "
               " page_count, link_count, pdf_bytes, listing_title, listing_tags, price_usd) "
               "VALUES ('{{ $json.run_id }}', '{{ $json.product_name.replace(/'/g, \"''\") }}', "
               "'{{ $json.slug }}', '{{ ($json.niche || '').replace(/'/g, \"''\") }}', "
               "'{{ ($json.search_phrase || '').replace(/'/g, \"''\") }}', "
               "'{{ JSON.stringify($json.keywords) }}'::jsonb, "
               "{{ $json.page_count }}, {{ $json.link_count }}, {{ $json.pdf_bytes }}, "
               "'{{ ($json.listing_title || '').replace(/'/g, \"''\") }}', "
               "'{{ JSON.stringify($json.listing_tags) }}'::jsonb, "
               "{{ $json.price_usd || 'NULL' }}) "
               "ON CONFLICT (slug) DO NOTHING;"),
           notes="บันทึกสินค้าลงฐานข้อมูล - ใช้กันสร้างซ้ำในรอบถัดไป",
           onError="continueRegularOutput")

    wf.link("Should Publish?", "Summarise Run", 1)
    wf.link("Collect Uploads", "Summarise Run")
    wf.link("Summarise Run", "Save Product")

    # -- errors -----------------------------------------------------------
    wf.add("On Error", T_ERROR_TRIGGER, pos(0, 3), {},
           notes="รับทุกความล้มเหลวของ workflow นี้")
    wf.add("Format Error", T_CODE, pos(1, 3), code(JS_FORMAT_ERROR),
           notes="เรียบเรียงข้อความ error ให้อ่านรู้เรื่อง (n8n เก็บเฉพาะท้ายข้อความ)")
    wf.add("Log Failure", T_POSTGRES, pos(2, 3),
           postgres_query(
               "UPDATE planner_runs SET status = 'failed', finished_at = now(), "
               "error_message = '{{ $json.message.replace(/'/g, \"''\") }}' "
               "WHERE status = 'running';"),
           notes="ปิดรอบที่ค้างอยู่ให้เป็น failed",
           onError="continueRegularOutput")
    wf.chain("On Error", "Format Error", "Log Failure")

    return wf.to_dict()


def _config_body() -> str:
    from nodes import config_js
    return config_js()
