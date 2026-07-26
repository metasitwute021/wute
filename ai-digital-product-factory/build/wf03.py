"""03 Product Engine - 8 factory branches feeding one shared production line."""

import json

from common import (
    RETRY, T_CODE, T_EXEC_TRIGGER, T_HTTP, T_IF, T_LOOP, T_NOOP, T_SET, T_SWITCH,
    Workflow, code, if_bool, loop_node, openai_chat, openai_image, pos,
    switch_equals,
)
from js_pdf import PDF_LIB_JS
from prompts import RENDER_HELPER, library_js

# --------------------------------------------------------------------------
# Factory profiles. Each branch of the Switch sets one of these; everything
# downstream is shared, so adding a 9th factory is a Switch rule + one Set node.
# --------------------------------------------------------------------------
FACTORIES = [
    {
        "factory_key": "planner",
        "display_name": "Planner Factory",
        "page_size": "A4 portrait",
        "page_width_pt": 595.28,
        "page_height_pt": 841.89,
        "target_pages": 24,
        "image_pages": 4,
        "image_size": "1024x1536",
        "cover_size": "1024x1536",
        "thumbnail_size": "1024x1024",
        "preview_size": "1024x1024",
        "preview_count": 3,
        "output_formats": ["PDF", "PNG", "JPG", "JSON", "TXT"],
        "svg_required": False,
        "content_schema": (
            "A dated-agnostic planner: cover, how-to-use page, then repeating "
            "spreads (monthly overview, weekly layout, daily focus, habit "
            "tracker, notes). Every page must have printable structure "
            "described in lines, e.g. column headers and row labels."
        ),
        "art_direction": "calm minimal stationery, soft neutral palette, generous white space",
        "etsy_taxonomy_hint": "Paper & Party Supplies > Paper > Calendars & Planners",
        "price_range_usd": [4, 15],
        "gumroad_ready": True,
        "miricanvas_ready": False,
    },
    {
        "factory_key": "printable",
        "display_name": "Printable Factory",
        "page_size": "US Letter portrait",
        "page_width_pt": 612,
        "page_height_pt": 792,
        "target_pages": 12,
        "image_pages": 3,
        "image_size": "1024x1536",
        "cover_size": "1024x1536",
        "thumbnail_size": "1024x1024",
        "preview_size": "1024x1024",
        "preview_count": 3,
        "output_formats": ["PDF", "PNG", "JPG", "JSON", "TXT"],
        "svg_required": False,
        "content_schema": (
            "A focused printable pack: cover, instructions, then standalone "
            "print-and-use sheets (checklists, trackers, worksheets). Each sheet "
            "must work on its own without the others."
        ),
        "art_direction": "clean editorial layout, one accent colour, high print contrast",
        "etsy_taxonomy_hint": "Paper & Party Supplies > Paper > Stationery",
        "price_range_usd": [3, 12],
        "gumroad_ready": True,
        "miricanvas_ready": False,
    },
    {
        "factory_key": "canva",
        "display_name": "Canva Factory",
        "page_size": "A4 portrait",
        "page_width_pt": 595.28,
        "page_height_pt": 841.89,
        "target_pages": 10,
        "image_pages": 3,
        "image_size": "1024x1536",
        "cover_size": "1024x1536",
        "thumbnail_size": "1024x1024",
        "preview_size": "1024x1024",
        "preview_count": 3,
        "output_formats": ["PDF", "PNG", "JPG", "SVG", "JSON", "TXT"],
        "svg_required": True,
        "content_schema": (
            "An editable template kit: cover, brand/style guide page, then "
            "template pages. Every template page must list its editable text "
            "slots and recommended image slots so it can be rebuilt in an "
            "editor. Include a page describing the licence and edit workflow."
        ),
        "art_direction": "modern brandable template look, flat vector shapes, two-colour system",
        "etsy_taxonomy_hint": "Craft Supplies & Tools > Digital > Templates",
        "price_range_usd": [6, 24],
        "gumroad_ready": True,
        "miricanvas_ready": True,
    },
    {
        "factory_key": "wallart",
        "display_name": "Wall Art Factory",
        "page_size": "2:3 portrait print",
        "page_width_pt": 576,
        "page_height_pt": 864,
        "target_pages": 8,
        "image_pages": 6,
        "image_size": "1024x1536",
        "cover_size": "1024x1536",
        "thumbnail_size": "1024x1024",
        "preview_size": "1536x1024",
        "preview_count": 3,
        "output_formats": ["PDF", "PNG", "JPG", "JSON", "TXT"],
        "svg_required": False,
        "content_schema": (
            "A wall art set: cover, a short printing/sizing guide (2:3, 3:4, "
            "4:5, ISO ratios), then one page per artwork with a title and a "
            "two-line description. Text pages stay minimal - the art carries it."
        ),
        "art_direction": "gallery-ready fine art print, cohesive palette across the set",
        "etsy_taxonomy_hint": "Art & Collectibles > Prints > Digital Prints",
        "price_range_usd": [5, 20],
        "gumroad_ready": True,
        "miricanvas_ready": False,
    },
    {
        "factory_key": "resume",
        "display_name": "Resume Factory",
        "page_size": "US Letter portrait",
        "page_width_pt": 612,
        "page_height_pt": 792,
        "target_pages": 8,
        "image_pages": 1,
        "image_size": "1024x1536",
        "cover_size": "1024x1536",
        "thumbnail_size": "1024x1024",
        "preview_size": "1024x1024",
        "preview_count": 3,
        "output_formats": ["PDF", "PNG", "JPG", "SVG", "JSON", "TXT"],
        "svg_required": True,
        "content_schema": (
            "A resume kit: cover, ATS rules page, a filled example resume, a "
            "blank structure page, a matching cover-letter page, and a page of "
            "action verbs plus a tailoring checklist. Sample content must be "
            "realistic but clearly fictional."
        ),
        "art_direction": "professional typographic layout, single accent rule, no decoration",
        "etsy_taxonomy_hint": "Paper & Party Supplies > Paper > Stationery > Design & Templates",
        "price_range_usd": [5, 18],
        "gumroad_ready": True,
        "miricanvas_ready": True,
    },
    {
        "factory_key": "spreadsheet",
        "display_name": "Spreadsheet Factory",
        "page_size": "A4 landscape",
        "page_width_pt": 841.89,
        "page_height_pt": 595.28,
        "target_pages": 10,
        "image_pages": 2,
        "image_size": "1536x1024",
        "cover_size": "1024x1536",
        "thumbnail_size": "1024x1024",
        "preview_size": "1536x1024",
        "preview_count": 3,
        "output_formats": ["PDF", "PNG", "JPG", "JSON", "TXT"],
        "svg_required": False,
        "content_schema": (
            "A spreadsheet system delivered as documentation plus a printable "
            "companion: cover, setup guide, one page per sheet listing exact "
            "column headers, data types and the formulas to paste, then a "
            "worked example and a troubleshooting page. Formulas must be plain "
            "text and valid in both Google Sheets and Excel."
        ),
        "art_direction": "data-dashboard aesthetic, muted chart palette, tidy grid",
        "etsy_taxonomy_hint": "Craft Supplies & Tools > Digital > Templates",
        "price_range_usd": [5, 22],
        "gumroad_ready": True,
        "miricanvas_ready": False,
    },
    {
        "factory_key": "kids",
        "display_name": "Kids Factory",
        "page_size": "US Letter portrait",
        "page_width_pt": 612,
        "page_height_pt": 792,
        "target_pages": 16,
        "image_pages": 8,
        "image_size": "1024x1536",
        "cover_size": "1024x1536",
        "thumbnail_size": "1024x1024",
        "preview_size": "1024x1024",
        "preview_count": 3,
        "output_formats": ["PDF", "PNG", "JPG", "SVG", "JSON", "TXT"],
        "svg_required": True,
        "content_schema": (
            "An age-appropriate activity pack for ages 3-8: cover, a parent "
            "guide page, then activity pages (tracing, counting, matching, "
            "colouring, simple mazes). Instructions are one short sentence in "
            "plain language. Absolutely no licensed characters and nothing that "
            "could frighten a small child."
        ),
        "art_direction": "friendly rounded shapes, bright but soft palette, thick clean outlines",
        "etsy_taxonomy_hint": "Toys & Games > Games & Puzzles > Educational Games",
        "price_range_usd": [3, 12],
        "gumroad_ready": True,
        "miricanvas_ready": True,
    },
    {
        "factory_key": "svg",
        "display_name": "SVG Factory",
        "page_size": "Square preview sheet",
        "page_width_pt": 612,
        "page_height_pt": 612,
        "target_pages": 6,
        "image_pages": 4,
        "image_size": "1024x1024",
        "cover_size": "1024x1024",
        "thumbnail_size": "1024x1024",
        "preview_size": "1024x1024",
        "preview_count": 3,
        "output_formats": ["SVG", "PDF", "PNG", "JPG", "JSON", "TXT"],
        "svg_required": True,
        "content_schema": (
            "A cut-file bundle: cover, a machine compatibility page (Cricut, "
            "Silhouette, ScanNCut), a sizing/weeding tips page, then one page "
            "per design with usage ideas. The SVG source is the actual product, "
            "so keep the text pages short and practical."
        ),
        "art_direction": "bold flat vector silhouettes, closed paths, no gradients, no thin strokes",
        "etsy_taxonomy_hint": "Craft Supplies & Tools > Digital > Cut Files",
        "price_range_usd": [3, 14],
        "gumroad_ready": True,
        "miricanvas_ready": True,
    },
]

FACTORY_KEYS = [f["factory_key"] for f in FACTORIES]

# 1x1 grey JPEG. Used only when dry_run=true so the whole pipeline can be
# rehearsed end to end without spending a cent on image generation.
PLACEHOLDER_JPEG = (
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB"
    "AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q=="
)

# --------------------------------------------------------------------------
# Code node sources
# --------------------------------------------------------------------------
JS_NORMALIZE = r"""
// Entry contract check. 03 refuses to run without a research package, because
// every downstream prompt is grounded in it.
const ctx = $input.first().json;
const research = ctx.research || {};

if (!research.keyword || !research.product_type) {
  throw new Error('03 Product Engine requires a research package with keyword and product_type');
}

return [{
  json: {
    run_id: ctx.run_id,
    factory: String(ctx.factory || research.product_type).toLowerCase().trim(),
    prompt_version: ctx.prompt_version || $env.PROMPT_VERSION || 'v1.0.0',
    dry_run: ctx.dry_run === true,
    research,
    market: ctx.market || {},
    created_at: new Date().toISOString(),
  },
}];
""".strip()

JS_BUILD_IDEA_PROMPT = RENDER_HELPER + r"""
const ctx = $input.first().json;
const agent = $('Prompt Library').first().json.prompts.idea_ai;

return [{
  json: {
    run_id: ctx.run_id,
    factory: ctx.factory,
    idea_user_prompt: render(agent.user_template, {
      research_json: JSON.stringify(ctx.research, null, 2),
      factory_profile_json: JSON.stringify(ctx.profile, null, 2),
    }),
  },
}];
""".rstrip()

JS_PARSE_IDEA = r"""
// Parse the product brief and enforce the limits the factory profile declares.
const base = $('Merge: Factory Profiles').first().json;
const response = $input.first().json;

let idea;
try {
  idea = JSON.parse(response?.choices?.[0]?.message?.content || '');
} catch (e) {
  throw new Error(`Idea AI returned invalid JSON: ${e.message}`);
}

if (!idea.product_name || !Array.isArray(idea.sections) || !idea.sections.length) {
  throw new Error('Idea AI output is missing product_name or sections');
}

idea.product_name = String(idea.product_name).replace(/\s+/g, ' ').trim().slice(0, 60);
idea.slug = idea.product_name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
idea.estimated_total_pages = Math.min(
  base.profile.target_pages + 4,
  Number(idea.estimated_total_pages) || base.profile.target_pages
);

return [{ json: { run_id: base.run_id, factory: base.factory, idea } }];
""".strip()

JS_BUILD_CONTENT_PROMPT = RENDER_HELPER + r"""
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const agent = $('Prompt Library').first().json.prompts.writer_ai;

return [{
  json: {
    run_id: base.run_id,
    content_user_prompt: render(agent.user_template, {
      idea_json: JSON.stringify(idea, null, 2),
      factory_profile_json: JSON.stringify(base.profile, null, 2),
      content_schema: base.profile.content_schema,
    }) + `\n\nHard requirement: produce ${base.profile.target_pages} content pages.`,
  },
}];
""".rstrip()

JS_PARSE_CONTENT = r"""
// Normalise the written content into exactly the shape the PDF builder expects.
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const response = $input.first().json;

let content;
try {
  content = JSON.parse(response?.choices?.[0]?.message?.content || '');
} catch (e) {
  throw new Error(`Writer AI returned invalid JSON: ${e.message}`);
}

const pages = (content.pages || [])
  .filter((p) => p && (p.title || (p.lines || []).length))
  .map((p, index) => ({
    page_number: Number(p.page_number) || index + 1,
    title: String(p.title || `Page ${index + 1}`).slice(0, 90),
    lines: (p.lines || []).map((l) => String(l).slice(0, 400)).filter(Boolean),
    needs_image: p.needs_image === true,
  }));

if (!pages.length) {
  throw new Error('Writer AI produced no usable pages');
}

// Cap how many pages get their own illustration - images are the expensive part.
let imageBudget = base.profile.image_pages;
for (const page of pages) {
  if (page.needs_image && imageBudget > 0) { imageBudget -= 1; }
  else { page.needs_image = false; }
}

return [{
  json: {
    run_id: base.run_id,
    content: {
      cover_title: String(content.cover_title || idea.product_name).slice(0, 70),
      cover_subtitle: String(content.cover_subtitle || idea.one_liner || '').slice(0, 120),
      intro_text: content.intro_text || '',
      usage_instructions: content.usage_instructions || [],
      credits: content.credits || 'Created with the AI Digital Product Factory',
      pages,
    },
    word_count: pages.reduce((sum, p) => sum + p.lines.join(' ').split(/\s+/).length, 0),
  },
}];
""".strip()

JS_BUILD_DESIGNER_PROMPT = RENDER_HELPER + r"""
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const content = $('Parse Content JSON').first().json.content;
const agent = $('Prompt Library').first().json.prompts.designer_ai;

const imagePages = content.pages
  .filter((p) => p.needs_image)
  .map((p) => ({ page_number: p.page_number, title: p.title, gist: (p.lines[0] || '').slice(0, 160) }));

return [{
  json: {
    run_id: base.run_id,
    designer_user_prompt: render(agent.user_template, {
      idea_json: JSON.stringify(idea, null, 2),
      image_page_list: JSON.stringify(imagePages, null, 2),
      factory_profile_json: JSON.stringify(
        { art_direction: base.profile.art_direction, page_size: base.profile.page_size },
        null,
        2
      ),
      svg_required: String(base.profile.svg_required),
    }),
  },
}];
""".rstrip()

JS_PARSE_IMAGE_PLAN = r"""
// Build the concrete image job list. Formats are chosen on purpose:
//   jpeg -> anything that goes inside the PDF (embeds as /DCTDecode untouched)
//   png  -> the shop thumbnail, where a lossless icon looks better
const base = $('Merge: Factory Profiles').first().json;
const content = $('Parse Content JSON').first().json.content;
const response = $input.first().json;

let plan;
try {
  plan = JSON.parse(response?.choices?.[0]?.message?.content || '');
} catch (e) {
  throw new Error(`Designer AI returned invalid JSON: ${e.message}`);
}

const style = base.profile.art_direction;
const decorate = (prompt) =>
  `${String(prompt || '').trim()} Art direction: ${style}. ` +
  'No text, no letters, no numbers, no watermark, no logo, no signature.';

const jobs = [];
jobs.push({
  role: 'cover',
  key: 'cover',
  prompt: decorate(plan?.cover?.prompt || `Cover artwork for ${content.cover_title}`),
  size: base.profile.cover_size,
  format: 'jpeg',
});
jobs.push({
  role: 'thumbnail',
  key: 'thumbnail',
  prompt: decorate(plan?.thumbnail?.prompt || `Square shop icon for ${content.cover_title}`),
  size: base.profile.thumbnail_size,
  format: 'png',
});

const previews = Array.isArray(plan?.previews) ? plan.previews : [];
for (let i = 0; i < base.profile.preview_count; i += 1) {
  jobs.push({
    role: 'preview',
    key: `preview_${i + 1}`,
    index: i + 1,
    prompt: decorate(previews[i]?.prompt || `Lifestyle mockup ${i + 1} of ${content.cover_title}`),
    size: base.profile.preview_size,
    format: 'jpeg',
  });
}

const pagePrompts = new Map(
  (Array.isArray(plan?.pages) ? plan.pages : []).map((p) => [Number(p.page_number), p.prompt])
);
for (const page of content.pages.filter((p) => p.needs_image)) {
  jobs.push({
    role: 'page',
    key: `page_${page.page_number}`,
    page_number: page.page_number,
    prompt: decorate(pagePrompts.get(page.page_number) || page.title),
    size: base.profile.image_size,
    format: 'jpeg',
  });
}

// Sanitise the optional editable vector source.
let svg = null;
if (base.profile.svg_required && typeof plan?.svg_markup === 'string') {
  svg = plan.svg_markup
    .replace(/<\?xml[\s\S]*?\?>/gi, '')
    .replace(/<!DOCTYPE[\s\S]*?>/gi, '')
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<foreignObject[\s\S]*?<\/foreignObject>/gi, '')
    .replace(/\son\w+\s*=\s*"[^"]*"/gi, '')
    .replace(/\son\w+\s*=\s*'[^']*'/gi, '')
    .replace(/(href|xlink:href)\s*=\s*"(?!#)[^"]*"/gi, '')
    .trim();
  if (!/^<svg[\s>]/i.test(svg)) svg = null;
}

return [{
  json: {
    run_id: base.run_id,
    dry_run: base.dry_run === true,
    image_jobs: jobs,
    svg_markup: svg,
    image_job_count: jobs.length,
  },
}];
""".strip()

JS_SPLIT_JOBS = r"""
// Fan the job list out into one item per image so the loop can process them
// one at a time (and so a single failure cannot take the batch down).
const ctx = $input.first().json;
return ctx.image_jobs.map((job, index) => ({
  json: { ...job, job_index: index, total_jobs: ctx.image_jobs.length, dry_run: ctx.dry_run },
}));
""".strip()

JS_PLACEHOLDER = r"""
// Dry-run path: a 1x1 JPEG stands in for a generated image so the rest of the
// pipeline (PDF, uploads, backup) can be rehearsed for free.
const job = $input.first().json;
return [{
  json: {
    ...job,
    b64: '%s',
    format: 'jpeg',
    generated: false,
    placeholder: true,
  },
}];
""".strip() % PLACEHOLDER_JPEG

JS_STORE_IMAGE = r"""
// Attach the generated bytes to the job. A failed generation is recorded rather
// than thrown, so one bad prompt does not destroy an otherwise good product.
const job = $('Loop: Image Jobs').first().json;
const response = $input.first().json;
const b64 = response?.data?.[0]?.b64_json || null;

return [{
  json: {
    ...job,
    b64,
    generated: Boolean(b64),
    placeholder: false,
    bytes: b64 ? Math.round((b64.length * 3) / 4) : 0,
    error: b64 ? null : (response?.error?.message || 'image generation returned no data'),
  },
}];
""".strip()

JS_COLLECT_IMAGES = r"""
// Regroup every finished job into a single addressable image set.
const base = $('Merge: Factory Profiles').first().json;
const plan = $('Parse Image Plan').first().json;
const items = $input.all().map((i) => i.json).filter((j) => j && j.key);

const byKey = {};
for (const job of items) {
  if (job.b64) byKey[job.key] = job;
}

const failed = items.filter((j) => !j.b64).map((j) => ({ key: j.key, error: j.error }));
if (!byKey.cover || !byKey.thumbnail) {
  throw new Error(
    'Image generation failed for the cover or thumbnail: ' + JSON.stringify(failed)
  );
}

const previews = items.filter((j) => j.role === 'preview' && j.b64);
const pages = items.filter((j) => j.role === 'page' && j.b64);

return [{
  json: {
    run_id: base.run_id,
    images: {
      cover: { b64: byKey.cover.b64, format: 'jpeg' },
      thumbnail: { b64: byKey.thumbnail.b64, format: 'png' },
      previews: previews.map((p) => ({ index: p.index, b64: p.b64, format: 'jpeg' })),
      pages: pages.map((p) => ({ page_number: p.page_number, b64: p.b64, format: 'jpeg' })),
    },
    svg_markup: plan.svg_markup || null,
    image_stats: {
      requested: plan.image_job_count,
      generated: items.filter((j) => j.b64).length,
      failed,
      placeholder: items.some((j) => j.placeholder),
    },
  },
}];
""".strip()

JS_FILE_MANIFEST_HELPER = r"""
// Planned deliverables, used by the SEO / metadata / QA prompts before the
// bytes actually exist.
const plannedFiles = (base, idea, images) => {
  const files = [
    { name: `${idea.slug}.pdf`, format: 'PDF', purpose: 'main product file' },
    { name: `${idea.slug}-thumbnail.png`, format: 'PNG', purpose: 'shop thumbnail' },
    { name: `${idea.slug}-cover.jpg`, format: 'JPG', purpose: 'listing cover image' },
    { name: 'metadata.json', format: 'JSON', purpose: 'machine readable product record' },
    { name: 'description.txt', format: 'TXT', purpose: 'marketplace description' },
  ];
  (images?.previews || []).forEach((p) => files.push({
    name: `${idea.slug}-preview-${p.index}.jpg`, format: 'JPG', purpose: 'listing preview',
  }));
  if (base.profile.svg_required) {
    files.push({ name: `${idea.slug}.svg`, format: 'SVG', purpose: 'editable vector source' });
  }
  return files;
};
"""

JS_BUILD_SEO_TITLE = RENDER_HELPER + JS_FILE_MANIFEST_HELPER + r"""
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const images = $('Collect Generated Images').first().json.images;
const agent = $('Prompt Library').first().json.prompts.seo_ai;

return [{
  json: {
    run_id: base.run_id,
    seo_user_prompt: render(agent.user_template, {
      seo_task: 'title',
      research_json: JSON.stringify(base.research, null, 2),
      idea_json: JSON.stringify(idea, null, 2),
      file_manifest: JSON.stringify(plannedFiles(base, idea, images), null, 2),
    }),
  },
}];
""".rstrip()

JS_BUILD_SEO_DESCRIPTION = RENDER_HELPER + JS_FILE_MANIFEST_HELPER + r"""
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const content = $('Parse Content JSON').first().json.content;
const images = $('Collect Generated Images').first().json.images;
const agent = $('Prompt Library').first().json.prompts.seo_ai;

return [{
  json: {
    run_id: base.run_id,
    seo_user_prompt: render(agent.user_template, {
      seo_task: 'description',
      research_json: JSON.stringify(base.research, null, 2),
      idea_json: JSON.stringify({ ...idea, page_count: content.pages.length }, null, 2),
      file_manifest: JSON.stringify(plannedFiles(base, idea, images), null, 2),
    }),
  },
}];
""".rstrip()

JS_BUILD_SEO_TAGS = RENDER_HELPER + JS_FILE_MANIFEST_HELPER + r"""
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const images = $('Collect Generated Images').first().json.images;
const agent = $('Prompt Library').first().json.prompts.seo_ai;

return [{
  json: {
    run_id: base.run_id,
    seo_user_prompt: render(agent.user_template, {
      seo_task: 'tags',
      research_json: JSON.stringify(base.research, null, 2),
      idea_json: JSON.stringify(idea, null, 2),
      file_manifest: JSON.stringify(plannedFiles(base, idea, images), null, 2),
    }) + '\nCandidate keywords you may reuse: ' +
      (base.research.sub_keywords || []).join(', '),
  },
}];
""".rstrip()

JS_VALIDATE_SEO = r"""
// Etsy rejects listings on hard limits, so the model output is repaired here
// rather than trusted: 140 char title, exactly 13 tags, 20 chars per tag.
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;

const readJson = (nodeName) => {
  try {
    return JSON.parse($(nodeName).first().json?.choices?.[0]?.message?.content || '{}');
  } catch (e) {
    return {};
  }
};

const titleOut = readJson('OpenAI: SEO AI Title');
const descriptionOut = readJson('OpenAI: SEO AI Description');
const tagsOut = readJson('OpenAI: SEO AI Etsy Tags');

let title = String(titleOut.title || idea.product_name).replace(/\s+/g, ' ').trim();
if (title.length > 140) title = title.slice(0, 137).replace(/[\s,|-]+$/, '') + '...';

const normaliseTag = (tag) => String(tag)
  .toLowerCase()
  .replace(/[^a-z0-9 ]/g, ' ')
  .replace(/\s+/g, ' ')
  .trim()
  .slice(0, 20)
  .trim();

const candidates = [
  ...(tagsOut.tags || []),
  ...(base.research.sub_keywords || []),
  ...(base.research.long_tail || []),
  base.research.keyword,
  base.factory,
];

const tags = [];
for (const candidate of candidates) {
  const tag = normaliseTag(candidate);
  if (tag && tag.length >= 3 && !tags.includes(tag)) tags.push(tag);
  if (tags.length === 13) break;
}
while (tags.length < 13) tags.push(normaliseTag(`${base.factory} download ${tags.length}`));

const description = String(descriptionOut.description || '').trim() ||
  `${idea.product_name}\n\n${idea.promise || idea.one_liner || ''}`;

const disclosure = 'This is an instant digital download. No physical item will be shipped.';
const finalDescription = description.toLowerCase().includes('digital download')
  ? description
  : `${description}\n\n${disclosure}`;

const materials = (tagsOut.materials || ['digital file', 'pdf', 'printable'])
  .map(normaliseTag)
  .filter(Boolean)
  .slice(0, 13);

return [{
  json: {
    run_id: base.run_id,
    seo: {
      title,
      title_length: title.length,
      description: finalDescription,
      tags,
      materials,
      primary_keyword: base.research.keyword,
    },
    seo_warnings: [
      title.length > 140 ? 'title truncated' : null,
      (tagsOut.tags || []).length !== 13 ? 'tag list repaired locally' : null,
    ].filter(Boolean),
  },
}];
""".strip()

JS_BUILD_METADATA_PROMPT = RENDER_HELPER + JS_FILE_MANIFEST_HELPER + r"""
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const seo = $('Validate SEO Package').first().json.seo;
const images = $('Collect Generated Images').first().json.images;
const agent = $('Prompt Library').first().json.prompts.metadata_ai;

return [{
  json: {
    run_id: base.run_id,
    metadata_user_prompt: render(agent.user_template, {
      research_json: JSON.stringify(base.research, null, 2),
      idea_json: JSON.stringify(idea, null, 2),
      seo_json: JSON.stringify(seo, null, 2),
      file_manifest: JSON.stringify(plannedFiles(base, idea, images), null, 2),
      factory_profile_json: JSON.stringify(base.profile, null, 2),
    }),
  },
}];
""".rstrip()

JS_PARSE_METADATA = r"""
// Metadata is the record of truth for the database and Google Drive, so every
// field is clamped locally instead of trusted.
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const seo = $('Validate SEO Package').first().json.seo;
const response = $input.first().json;

let metadata = {};
try {
  metadata = JSON.parse(response?.choices?.[0]?.message?.content || '{}');
} catch (e) {
  metadata = {};
}

const [minPrice, maxPrice] = base.profile.price_range_usd;
const suggested = Number(metadata.price_usd) || Number(base.research.price_suggestion_usd) || minPrice;
const price = Math.round(Math.min(maxPrice, Math.max(minPrice, suggested)) * 100) / 100;

return [{
  json: {
    run_id: base.run_id,
    metadata: {
      product_name: idea.product_name,
      slug: idea.slug,
      factory: base.factory,
      category: metadata.category || base.research.category || 'Digital Downloads',
      taxonomy_hint: metadata.taxonomy_hint || base.profile.etsy_taxonomy_hint,
      price_usd: price,
      currency: 'USD',
      keywords: seo.tags,
      tags: seo.tags,
      compatibility: {
        gumroad: base.profile.gumroad_ready && metadata?.compatibility?.gumroad !== false,
        miricanvas: base.profile.miricanvas_ready && metadata?.compatibility?.miricanvas !== false,
        notes: metadata?.compatibility?.notes || 'derived from the factory profile',
      },
      license: metadata.license || 'Personal use only. Commercial resale of the file is not permitted.',
      prompt_version: base.prompt_version,
      generated_at: new Date().toISOString(),
    },
  },
}];
""".strip()

JS_BUILD_QA_PROMPT = RENDER_HELPER + JS_FILE_MANIFEST_HELPER + r"""
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const content = $('Parse Content JSON').first().json.content;
const seo = $('Validate SEO Package').first().json.seo;
const metadata = $('Parse Metadata JSON').first().json.metadata;
const images = $('Collect Generated Images').first().json.images;
const agent = $('Prompt Library').first().json.prompts.qa_ai;

// The QA agent reviews the copy, never the image bytes.
const reviewableContent = {
  cover_title: content.cover_title,
  cover_subtitle: content.cover_subtitle,
  page_count: content.pages.length,
  pages: content.pages.map((p) => ({ page_number: p.page_number, title: p.title, lines: p.lines })),
  usage_instructions: content.usage_instructions,
};

return [{
  json: {
    run_id: base.run_id,
    qa_user_prompt: render(agent.user_template, {
      idea_json: JSON.stringify(idea, null, 2),
      content_json: JSON.stringify(reviewableContent, null, 2),
      seo_json: JSON.stringify(seo, null, 2),
      metadata_json: JSON.stringify(metadata, null, 2),
      file_manifest: JSON.stringify(plannedFiles(base, idea, images), null, 2),
    }),
  },
}];
""".rstrip()

JS_PARSE_QA = r"""
// The QA verdict decides whether anything reaches a marketplace at all.
const base = $('Merge: Factory Profiles').first().json;
const response = $input.first().json;

let report;
try {
  report = JSON.parse(response?.choices?.[0]?.message?.content || '');
} catch (e) {
  report = {
    passed: false,
    blockers: [`QA AI returned invalid JSON: ${e.message}`],
    scores: {},
    warnings: [],
    summary: 'QA response could not be parsed',
  };
}

const scores = report.scores || {};
const lowest = Object.values(scores).length ? Math.min(...Object.values(scores).map(Number)) : 0;
const blockers = report.blockers || [];

// Local re-check: never rely solely on the model to enforce hard limits.
const seo = $('Validate SEO Package').first().json.seo;
if (seo.title.length > 140) blockers.push('title exceeds 140 characters');
if (seo.tags.length !== 13) blockers.push(`tag count is ${seo.tags.length}, expected 13`);
if (seo.tags.some((t) => t.length > 20)) blockers.push('a tag exceeds 20 characters');

const passed = report.passed === true && blockers.length === 0 && lowest >= 7;

return [{
  json: {
    run_id: base.run_id,
    qa: { ...report, passed, blockers, lowest_score: lowest },
  },
}];
""".strip()

JS_QA_FAILED = r"""
// Business rejection, not a technical error: return ok=false so 01 logs it and
// stops cleanly instead of raising a workflow exception.
const base = $('Merge: Factory Profiles').first().json;
const qa = $('Parse QA Report').first().json.qa;
const idea = $('Parse Idea JSON').first().json.idea;

return [{
  json: {
    ok: false,
    run_id: base.run_id,
    factory: base.factory,
    product_name: idea.product_name,
    failure_reason: `QA gate rejected the product: ${(qa.blockers || []).join('; ') || qa.summary}`,
    qa,
  },
}];
""".strip()

JS_BUILD_PDF = PDF_LIB_JS + r"""

// ---------------------------------------------------------------------------
// Assemble the product PDF from the written content and the generated art.
// ---------------------------------------------------------------------------
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const content = $('Parse Content JSON').first().json.content;
const imageSet = $('Collect Generated Images').first().json.images;
const metadata = $('Parse Metadata JSON').first().json.metadata;

const pageImages = new Map((imageSet.pages || []).map((p) => [Number(p.page_number), p.b64]));
const footerLabel = `${idea.product_name} - ${metadata.license}`;

const pdfPages = [];

// 1. Cover
pdfPages.push({ type: 'image', jpeg_base64: imageSet.cover.b64, full_bleed: true });
pdfPages.push({
  type: 'text',
  cover: true,
  title: content.cover_title,
  subtitle: content.cover_subtitle,
  lines: [
    '',
    content.intro_text || '',
    '',
    ...(content.usage_instructions || []).map((line) => `- ${line}`),
  ].filter((l) => l !== undefined),
  footer: footerLabel,
});

// 2. Body
for (const page of content.pages) {
  pdfPages.push({
    type: 'text',
    title: page.title,
    lines: page.lines,
    footer: `${footerLabel} | page ${page.page_number}`,
  });
  const art = pageImages.get(page.page_number);
  if (art) {
    pdfPages.push({
      type: 'image',
      jpeg_base64: art,
      caption: page.title,
      footer: `${footerLabel} | page ${page.page_number}`,
    });
  }
}

// 3. Colophon
pdfPages.push({
  type: 'text',
  title: 'Licence and credits',
  lines: [
    metadata.license,
    '',
    content.credits,
    '',
    `Product: ${metadata.product_name}`,
    `Category: ${metadata.category}`,
    `Prompt version: ${metadata.prompt_version}`,
    `Generated: ${metadata.generated_at}`,
  ],
  footer: footerLabel,
});

const result = buildPdf({
  width: base.profile.page_width_pt,
  height: base.profile.page_height_pt,
  pages: pdfPages,
  info: {
    title: metadata.product_name,
    subject: base.research.keyword,
    keywords: (metadata.tags || []).join(', '),
  },
});

return [{
  json: {
    run_id: base.run_id,
    pdf_base64: result.buffer.toString('base64'),
    pdf_bytes: result.buffer.length,
    pdf_page_count: result.page_count,
  },
}];
""".rstrip()

JS_EXPORT_FILES = r"""
// Final packaging step: every deliverable becomes an entry in one manifest,
// carrying its own base64 payload. Downstream workflows (04 Etsy upload,
// 05 Drive backup) turn the entries they need into binary at the last moment,
// which keeps the data intact across every Code node hop.
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const content = $('Parse Content JSON').first().json.content;
const collected = $('Collect Generated Images').first().json;
const seo = $('Validate SEO Package').first().json.seo;
const metadata = $('Parse Metadata JSON').first().json.metadata;
const qa = $('Parse QA Report').first().json.qa;
const pdf = $input.first().json;
const prompts = $('Prompt Library').first().json.prompts;

const slug = idea.slug;
const files = [];
const addFile = (key, name, format, mime, b64, purpose) => {
  if (!b64) return;
  files.push({
    key, file_name: name, format, mime_type: mime, purpose,
    bytes: Math.round((b64.length * 3) / 4), b64,
  });
};
const encode = (text) => Buffer.from(String(text), 'utf8').toString('base64');

// --- PDF / images ---------------------------------------------------------
addFile('product_pdf', `${slug}.pdf`, 'PDF', 'application/pdf', pdf.pdf_base64, 'main product file');
addFile('cover_jpg', `${slug}-cover.jpg`, 'JPG', 'image/jpeg', collected.images.cover.b64, 'listing cover image');
addFile('thumbnail_png', `${slug}-thumbnail.png`, 'PNG', 'image/png', collected.images.thumbnail.b64, 'shop thumbnail');
for (const preview of collected.images.previews || []) {
  addFile(`preview_${preview.index}_jpg`, `${slug}-preview-${preview.index}.jpg`, 'JPG',
    'image/jpeg', preview.b64, 'listing preview image');
}

// --- editable vector source (only for the factories that declare it) ------
if (base.profile.svg_required && collected.svg_markup) {
  addFile('source_svg', `${slug}.svg`, 'SVG', 'image/svg+xml', encode(collected.svg_markup),
    'editable vector source');
}

// --- text / json side-car files ------------------------------------------
const seoJson = {
  title: seo.title,
  description: seo.description,
  tags: seo.tags,
  materials: seo.materials,
  primary_keyword: seo.primary_keyword,
  sub_keywords: base.research.sub_keywords,
  long_tail: base.research.long_tail || [],
  difficulty: base.research.difficulty,
  market: base.market || {},
};

const promptMd = [
  `# Prompt record - ${metadata.product_name}`,
  '',
  `- Run id: ${base.run_id}`,
  `- Factory: ${base.profile.display_name}`,
  `- Prompt version: ${metadata.prompt_version}`,
  `- Model (text): ${$env.OPENAI_MODEL_TEXT || 'gpt-4.1'}`,
  `- Model (image): ${$env.OPENAI_MODEL_IMAGE || 'gpt-image-1'}`,
  '',
  '## Agents used',
  ...Object.values(prompts).map((a) => `- **${a.title}** (\`${a.id}\`): ${a.purpose}`),
  '',
  '## Research concept',
  '```json',
  JSON.stringify(base.research, null, 2),
  '```',
  '',
  '## Product brief',
  '```json',
  JSON.stringify(idea, null, 2),
  '```',
  '',
  '## Image prompts',
  '```json',
  JSON.stringify($('Parse Image Plan').first().json.image_jobs.map(
    (j) => ({ key: j.key, size: j.size, format: j.format, prompt: j.prompt })
  ), null, 2),
  '```',
  '',
  '## QA verdict',
  '```json',
  JSON.stringify(qa, null, 2),
  '```',
].join('\n');

addFile('metadata_json', 'metadata.json', 'JSON', 'application/json',
  encode(JSON.stringify({ ...metadata, qa_summary: qa.summary, files_planned: files.length }, null, 2)),
  'machine readable product record');
addFile('description_txt', 'description.txt', 'TXT', 'text/plain', encode(seo.description),
  'marketplace description');
addFile('seo_json', 'SEO.json', 'JSON', 'application/json', encode(JSON.stringify(seoJson, null, 2)),
  'seo research record');
addFile('prompt_md', 'Prompt.md', 'TXT', 'text/markdown', encode(promptMd),
  'reproducibility record');
addFile('content_json', 'content.json', 'JSON', 'application/json',
  encode(JSON.stringify(content, null, 2)), 'source content of the product');

const formats = [...new Set(files.map((f) => f.format))];

return [{
  json: {
    ok: true,
    run_id: base.run_id,
    factory: base.factory,
    profile: base.profile,
    product_name: metadata.product_name,
    slug,
    metadata,
    seo,
    qa,
    research: base.research,
    files,
    manifest: files.map(({ b64, ...rest }) => rest),
    formats,
    stats: {
      pdf_pages: pdf.pdf_page_count,
      pdf_bytes: pdf.pdf_bytes,
      content_pages: content.pages.length,
      images: collected.image_stats,
      total_bytes: files.reduce((sum, f) => sum + f.bytes, 0),
      placeholder_images: collected.image_stats.placeholder === true,
    },
    exported_at: new Date().toISOString(),
  },
}];
""".strip()


def _profile_set_params(profile: dict) -> dict:
    """Set node that stamps one factory profile onto the running item."""
    payload = json.dumps({"profile": profile}, ensure_ascii=False, indent=2)
    return {"mode": "raw", "jsonOutput": payload, "includeOtherFields": True, "options": {}}


def build() -> Workflow:
    wf = Workflow("03")

    wf.add("Receive Product Request", T_EXEC_TRIGGER, pos(0, 3),
           {"inputSource": "passthrough"},
           notes="Entry point. Called by 01 with the run context + research package.")
    wf.add("Prompt Library", T_CODE, pos(1, 3),
           code(library_js(["idea_ai", "writer_ai", "designer_ai", "seo_ai",
                            "metadata_ai", "qa_ai"])),
           notes="Versioned prompts for the six agents used on the production line.")
    wf.add("Normalize Factory Input", T_CODE, pos(2, 3), code(JS_NORMALIZE),
           notes="Validates the research contract and resolves the factory key.")

    wf.add("Route: Factory Type", T_SWITCH, pos(3, 3),
           switch_equals("={{ $json.factory }}", FACTORY_KEYS),
           notes="One output per factory. The fallback output keeps unknown keys alive as printables.")

    # -- the eight factory branches ---------------------------------------
    for index, profile in enumerate(FACTORIES):
        name = f"Factory Profile: {profile['display_name'].replace(' Factory', '')}"
        wf.add(
            name, T_SET, pos(4, index), _profile_set_params(profile),
            notes=(
                f"{profile['display_name']}: {profile['page_size']}, "
                f"{profile['target_pages']} pages, formats "
                f"{'/'.join(profile['output_formats'])}"
                f"{', editable SVG source' if profile['svg_required'] else ''}."
            ),
        )
        wf.link("Route: Factory Type", name, index)

    fallback = dict(FACTORIES[1])
    fallback["factory_key"] = "printable"
    fallback["display_name"] = "Printable Factory (fallback)"
    wf.add("Factory Profile: Fallback", T_SET, pos(4, 8), _profile_set_params(fallback),
           notes="Unknown factory keys degrade to the printable profile instead of failing.")
    wf.link("Route: Factory Type", "Factory Profile: Fallback", len(FACTORIES))

    wf.add("Merge: Factory Profiles", T_NOOP, pos(5, 3), {},
           notes="Single join point - everything after this is shared by all 8 factories.")
    for profile in FACTORIES:
        wf.link(f"Factory Profile: {profile['display_name'].replace(' Factory', '')}",
                "Merge: Factory Profiles")
    wf.link("Factory Profile: Fallback", "Merge: Factory Profiles")

    # -- idea + content ----------------------------------------------------
    wf.add("Build Idea Prompt", T_CODE, pos(6, 3), code(JS_BUILD_IDEA_PROMPT),
           notes="Renders the Idea AI template from research + factory profile.")
    wf.add("OpenAI: Idea AI", T_HTTP, pos(7, 3),
           openai_chat(
               "($('Prompt Library').first().json.prompts.idea_ai.system + "
               "'\\n\\nOUTPUT CONTRACT (return exactly this JSON shape):\\n' + "
               "$('Prompt Library').first().json.prompts.idea_ai.output_contract)",
               "$json.idea_user_prompt", temperature=0.8, max_tokens=2500),
           notes="Agent 2/8. Turns the market concept into a buildable product brief.",
           **RETRY)
    wf.add("Parse Idea JSON", T_CODE, pos(8, 3), code(JS_PARSE_IDEA),
           notes="Validates the brief and clamps name/slug/page count to the profile.")

    wf.add("Build Content Prompt", T_CODE, pos(9, 3), code(JS_BUILD_CONTENT_PROMPT),
           notes="Renders the Writer AI template with the factory content schema.")
    wf.add("OpenAI: Writer AI", T_HTTP, pos(10, 3),
           openai_chat(
               "($('Prompt Library').first().json.prompts.writer_ai.system + "
               "'\\n\\nOUTPUT CONTRACT (return exactly this JSON shape):\\n' + "
               "$('Prompt Library').first().json.prompts.writer_ai.output_contract)",
               "$json.content_user_prompt", temperature=0.7, max_tokens=8000),
           notes="Agent 3/8. Writes the page-by-page copy that is typeset into the PDF.",
           **RETRY)
    wf.add("Parse Content JSON", T_CODE, pos(11, 3), code(JS_PARSE_CONTENT),
           notes="Normalises pages and caps how many of them get their own illustration.")

    # -- images ------------------------------------------------------------
    wf.add("Build Designer Prompt", T_CODE, pos(12, 3), code(JS_BUILD_DESIGNER_PROMPT),
           notes="Renders the Designer AI template (image plan + optional SVG source).")
    wf.add("OpenAI: Designer AI", T_HTTP, pos(13, 3),
           openai_chat(
               "($('Prompt Library').first().json.prompts.designer_ai.system + "
               "'\\n\\nOUTPUT CONTRACT (return exactly this JSON shape):\\n' + "
               "$('Prompt Library').first().json.prompts.designer_ai.output_contract)",
               "$json.designer_user_prompt", temperature=0.9, max_tokens=4000),
           notes="Agent 4/8. Authors every image prompt and the sanitised SVG markup.",
           **RETRY)
    wf.add("Parse Image Plan", T_CODE, pos(14, 3), code(JS_PARSE_IMAGE_PLAN),
           notes=("Builds the image job list (cover/thumbnail/previews/pages) and strips "
                  "scripts and external references out of the SVG."))
    wf.add("Split: Image Jobs", T_CODE, pos(15, 3), code(JS_SPLIT_JOBS),
           notes="One item per image so a single failure cannot take the batch down.")
    wf.add("Loop: Image Jobs", T_LOOP, pos(16, 3), loop_node(1),
           notes="Sequential generation: output 1 = next job, output 0 = all jobs done.")
    wf.add("Check: Generate Image", T_IF, pos(17, 4),
           if_bool("={{ !$json.dry_run }}"),
           notes="dry_run=true swaps in a placeholder so rehearsals cost nothing.")
    wf.add("OpenAI: Image API", T_HTTP, pos(18, 4),
           openai_image("$json.prompt", "$json.size", "$json.format"),
           notes=("Agent 4/8 (image call). JPEG for anything that lands in the PDF, "
                  "PNG for the thumbnail."),
           onError="continueRegularOutput", alwaysOutputData=True,
           retryOnFail=True, maxTries=3, waitBetweenTries=8000)
    wf.add("Store Generated Image", T_CODE, pos(19, 4), code(JS_STORE_IMAGE),
           notes="Attaches the bytes to the job; records the error instead of throwing.")
    wf.add("Use Placeholder Image", T_CODE, pos(18, 5), code(JS_PLACEHOLDER),
           notes="1x1 JPEG stand-in for dry runs.")
    wf.add("Collect Generated Images", T_CODE, pos(17, 3), code(JS_COLLECT_IMAGES),
           notes="Regroups the finished jobs; aborts only if cover or thumbnail is missing.")

    # -- SEO ---------------------------------------------------------------
    wf.add("Build SEO Title Prompt", T_CODE, pos(18, 2), code(JS_BUILD_SEO_TITLE),
           notes="SEO AI in 'title' mode.")
    wf.add("OpenAI: SEO AI Title", T_HTTP, pos(19, 2),
           openai_chat(
               "($('Prompt Library').first().json.prompts.seo_ai.system + "
               "'\\n\\nOUTPUT CONTRACT (return exactly this JSON shape):\\n' + "
               "$('Prompt Library').first().json.prompts.seo_ai.output_contract)",
               "$json.seo_user_prompt", temperature=0.6, max_tokens=600),
           notes="Agent 5/8. Etsy title, keyword-front-loaded, max 140 characters.",
           **RETRY)
    wf.add("Build SEO Description Prompt", T_CODE, pos(20, 2), code(JS_BUILD_SEO_DESCRIPTION),
           notes="SEO AI in 'description' mode.")
    wf.add("OpenAI: SEO AI Description", T_HTTP, pos(21, 2),
           openai_chat(
               "($('Prompt Library').first().json.prompts.seo_ai.system + "
               "'\\n\\nOUTPUT CONTRACT (return exactly this JSON shape):\\n' + "
               "$('Prompt Library').first().json.prompts.seo_ai.output_contract)",
               "$json.seo_user_prompt", temperature=0.6, max_tokens=1500),
           notes="Agent 5/8. Five-paragraph description including the digital download notice.",
           **RETRY)
    wf.add("Build SEO Tags Prompt", T_CODE, pos(22, 2), code(JS_BUILD_SEO_TAGS),
           notes="SEO AI in 'tags' mode, seeded with the researched keywords.")
    wf.add("OpenAI: SEO AI Etsy Tags", T_HTTP, pos(23, 2),
           openai_chat(
               "($('Prompt Library').first().json.prompts.seo_ai.system + "
               "'\\n\\nOUTPUT CONTRACT (return exactly this JSON shape):\\n' + "
               "$('Prompt Library').first().json.prompts.seo_ai.output_contract)",
               "$json.seo_user_prompt", temperature=0.5, max_tokens=800),
           notes="Agent 5/8. Exactly 13 Etsy tags plus the materials list.",
           **RETRY)
    wf.add("Validate SEO Package", T_CODE, pos(24, 2), code(JS_VALIDATE_SEO),
           notes="Repairs the SEO output locally against Etsy's hard limits (140 / 13 / 20).")

    # -- metadata + QA -----------------------------------------------------
    wf.add("Build Metadata Prompt", T_CODE, pos(25, 2), code(JS_BUILD_METADATA_PROMPT),
           notes="Renders the Metadata AI template.")
    wf.add("OpenAI: Metadata AI", T_HTTP, pos(26, 2),
           openai_chat(
               "($('Prompt Library').first().json.prompts.metadata_ai.system + "
               "'\\n\\nOUTPUT CONTRACT (return exactly this JSON shape):\\n' + "
               "$('Prompt Library').first().json.prompts.metadata_ai.output_contract)",
               "$json.metadata_user_prompt", temperature=0.2, max_tokens=1500),
           notes="Agent 6/8. Produces the canonical metadata record.",
           **RETRY)
    wf.add("Parse Metadata JSON", T_CODE, pos(27, 2), code(JS_PARSE_METADATA),
           notes="Clamps price to the factory range and derives platform compatibility.")

    wf.add("Build QA Prompt", T_CODE, pos(28, 2), code(JS_BUILD_QA_PROMPT),
           notes="Renders the QA AI template with the full reviewable payload.")
    wf.add("OpenAI: QA AI", T_HTTP, pos(29, 2),
           openai_chat(
               "($('Prompt Library').first().json.prompts.qa_ai.system + "
               "'\\n\\nOUTPUT CONTRACT (return exactly this JSON shape):\\n' + "
               "$('Prompt Library').first().json.prompts.qa_ai.output_contract)",
               "$json.qa_user_prompt", temperature=0.1, max_tokens=2000),
           notes="Agent 7/8. Strict compliance gate before anything is published.",
           **RETRY)
    wf.add("Parse QA Report", T_CODE, pos(30, 2), code(JS_PARSE_QA),
           notes="Adds deterministic Etsy limit checks on top of the model verdict.")
    wf.add("Check: QA Passed", T_IF, pos(31, 2), if_bool("={{ $json.qa.passed }}"),
           notes="Fail closed: a rejected product never reaches the Publish Engine.")
    wf.add("Build QA Failure Result", T_CODE, pos(32, 3), code(JS_QA_FAILED),
           notes="Returns ok=false (business rejection) rather than raising an error.")

    # -- export ------------------------------------------------------------
    wf.add("Build PDF Document", T_CODE, pos(32, 1), code(JS_BUILD_PDF),
           notes=("Dependency-free PDF writer: Helvetica text pages plus JPEG images "
                  "embedded as /DCTDecode. No external service, no npm package."))
    wf.add("Export Files", T_CODE, pos(33, 1), code(JS_EXPORT_FILES),
           notes="Builds the deliverable manifest: PDF, PNG, JPG, SVG, JSON and TXT.")
    wf.add("Return: Product Package", T_NOOP, pos(34, 2), {},
           notes="Terminal node - its item is the sub-workflow return value.")

    # -- wiring ------------------------------------------------------------
    wf.chain("Receive Product Request", "Prompt Library", "Normalize Factory Input",
             "Route: Factory Type")
    wf.chain("Merge: Factory Profiles", "Build Idea Prompt", "OpenAI: Idea AI",
             "Parse Idea JSON", "Build Content Prompt", "OpenAI: Writer AI",
             "Parse Content JSON", "Build Designer Prompt", "OpenAI: Designer AI",
             "Parse Image Plan", "Split: Image Jobs", "Loop: Image Jobs")

    wf.link("Loop: Image Jobs", "Collect Generated Images", 0)
    wf.link("Loop: Image Jobs", "Check: Generate Image", 1)
    wf.link("Check: Generate Image", "OpenAI: Image API", 0)
    wf.link("Check: Generate Image", "Use Placeholder Image", 1)
    wf.link("OpenAI: Image API", "Store Generated Image")
    wf.link("Store Generated Image", "Loop: Image Jobs")
    wf.link("Use Placeholder Image", "Loop: Image Jobs")

    wf.chain("Collect Generated Images", "Build SEO Title Prompt", "OpenAI: SEO AI Title",
             "Build SEO Description Prompt", "OpenAI: SEO AI Description",
             "Build SEO Tags Prompt", "OpenAI: SEO AI Etsy Tags", "Validate SEO Package",
             "Build Metadata Prompt", "OpenAI: Metadata AI", "Parse Metadata JSON",
             "Build QA Prompt", "OpenAI: QA AI", "Parse QA Report", "Check: QA Passed")

    wf.link("Check: QA Passed", "Build PDF Document", 0)
    wf.link("Check: QA Passed", "Build QA Failure Result", 1)
    wf.chain("Build PDF Document", "Export Files", "Return: Product Package")
    wf.link("Build QA Failure Result", "Return: Product Package")

    return wf
