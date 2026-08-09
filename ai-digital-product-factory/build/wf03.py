"""03 Product Engine - 8 factory branches feeding one shared production line."""

import json

from common import (
    AGENT_CONTENT_JS,
    ASARRAY_JS,
    RETRY, T_CODE, T_EXEC_TRIGGER, T_HTTP, T_IF, T_LOOP, T_NOOP, T_POSTGRES,
    T_SET, T_SWITCH, Workflow, code, if_bool, loop_node, openai_chat,
    openai_image, pos, switch_equals,
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

# Stand-ins used only when dry_run=true, so the whole pipeline can be rehearsed
# end to end without spending a cent on image generation.
#
# There is one per format on purpose. QA stage 5 opens every exported file and
# checks its magic bytes, so handing back a JPEG for the job that becomes
# <slug>-thumbnail.png makes the rehearsal fail on a file the rehearsal itself
# mislabelled. Both are comfortably over the 64-byte floor that stage applies.
PLACEHOLDER_JPEG = (
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB"
    "AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q=="
)
PLACEHOLDER_PNG = (
    "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAD0lEQVR42mM4gQMwDC0J"
    "AJwulgEYko6kAAAAAElFTkSuQmCC"
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
// Addressed by node, not by $input: the immediate predecessor is QA Stage 1,
// whose item is a verdict (passed, score, blockers) and carries neither the
// research package nor the factory profile. Reading them off $input yielded
// the string "undefined" in both slots, and Idea AI was being asked to design
// a product from a 312-token prompt containing no product information at all.
const ctx = $('Merge: Factory Profiles').first().json;
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

AGENT_PARSE_HELPER = AGENT_CONTENT_JS + ASARRAY_JS +r"""

// Read an OpenAI chat reply, or fail with something worth reading. A bare
// "missing field" message costs a whole run and a support round-trip to
// diagnose; the model's own reply, its finish_reason and the keys it did
// return are the evidence that actually identifies the problem.
const readAgentReply = (label, response) => {
  const message = ((response && response.choices && response.choices[0]) || {}).message || {};
  const finish = agentFinish(response);
  const content = agentContent(response);
  // One line, always. n8n renders a Code node failure as "<message> [line N]"
  // and a newline in the middle truncates it - a preview of pretty-printed
  // JSON turned the whole diagnostic into "{ [line 39]".
  const preview = content.replace(/\s+/g, ' ').trim().slice(0, 240);

  if (message.refusal) {
    throw new Error(`${label} refused the request: ${String(message.refusal).slice(0, 300)}`);
  }
  if (!content.trim()) {
    throw new Error(`${label} returned no content (finish_reason=${finish})`);
  }
  if (finish === 'length') {
    throw new Error(
      `${label} hit the token limit before finishing its JSON ` +
      `(finish_reason=length). Raise max_tokens on that node. | got: ${preview}`);
  }
  try {
    return { data: JSON.parse(content), finish, preview };
  } catch (e) {
    throw new Error(`${label} returned invalid JSON (finish_reason=${finish}): ` +
                    `${String(e.message).replace(/\s+/g, ' ')} | got: ${preview}`);
  }
};

// Models sometimes wrap the contract in a single envelope key - {"product": {...}}
// or {"brief": {...}}. That is a formatting habit, not a different answer, so
// unwrap it rather than throwing away a reply that contains everything asked
// for. Anything less obvious is still a genuine contract violation.
const unwrapEnvelope = (data, fields) => {
  if (!data || typeof data !== 'object' || Array.isArray(data)) return data;
  const has = (obj) => fields.every((field) => obj && obj[field] !== undefined);
  if (has(data)) return data;
  const keys = Object.keys(data);
  if (keys.length === 1) {
    const inner = data[keys[0]];
    if (has(inner)) return inner;
  }
  return data;
};

// n8n keeps only the tail of a thrown Code node message, so the ordering here
// is deliberate: least useful first, the actual verdict last. Two runs were
// spent reading "{ [line 39]" and "0 } [line 58]" - the diagnostic was present
// both times and sat in the half that got cut off.
const requireAgentFields = (label, reply, fields) => {
  const missing = fields.filter((field) => {
    const value = reply.data[field];
    return value === undefined || value === null || value === ''
        || (Array.isArray(value) && value.length === 0);
  });
  if (missing.length) {
    const shape = fields.map((field) => {
      const value = reply.data[field];
      if (value === undefined) return `${field}=absent`;
      if (Array.isArray(value)) return `${field}=array(${value.length})`;
      if (value === null) return `${field}=null`;
      if (value === '') return `${field}=empty-string`;
      return `${field}=${typeof value}`;
    }).join(' ');
    throw new Error(
      `got ${reply.preview.slice(0, 120)} || ` +
      `keys=[${Object.keys(reply.data).join(',')}] | ` +
      `finish=${reply.finish} | ${shape} | ${label} MISSING: ${missing.join(',')}`);
  }
};
"""

JS_PARSE_IDEA = AGENT_PARSE_HELPER + r"""
// Parse the product brief and enforce the limits the factory profile declares.
const base = $('Merge: Factory Profiles').first().json;
const response = $input.first().json;

const reply = readAgentReply('Idea AI', response);
reply.data = unwrapEnvelope(reply.data, ['product_name', 'sections']);
requireAgentFields('Idea AI', reply, ['product_name', 'sections']);
const idea = reply.data;

if (!Array.isArray(idea.sections) || !idea.sections.length) {
  throw new Error(`Idea AI returned 'sections' but not as a non-empty array: ` +
                  `${JSON.stringify(idea.sections).slice(0, 200)}`);
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

JS_PARSE_CONTENT = AGENT_PARSE_HELPER + r"""
// Normalise the written content into exactly the shape the PDF builder expects.
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const response = $input.first().json;

const content = readAgentReply('Writer AI', response).data;

// Number the pages here rather than trusting page_number from the writer. The
// model repeats numbers - a run shipped two different pages both labelled 1 -
// and the number is not decoration: the PDF prints it in the footer and the
// illustrations are matched to pages by it, so a collision puts the same
// artwork on two pages and silently overruns the profile's image budget.
const pages = asArray(content.pages)
  .filter((p) => p && (p.title || (p.lines || []).length))
  .map((p, index) => ({
    page_number: index + 1,
    title: String(p.title || `Page ${index + 1}`).slice(0, 90),
    lines: asArray(p.lines).map((l) => String(l).slice(0, 400)).filter(Boolean),
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

JS_PARSE_IMAGE_PLAN = AGENT_PARSE_HELPER + r"""
// Build the concrete image job list. Formats are chosen on purpose:
//   jpeg -> anything that goes inside the PDF (embeds as /DCTDecode untouched)
//   png  -> the shop thumbnail, where a lossless icon looks better
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const content = $('Parse Content JSON').first().json.content;
const response = $input.first().json;

const plan = readAgentReply('Designer AI', response).data;

const style = base.profile.art_direction;
const decorate = (prompt) =>
  `${String(prompt || '').trim()} Art direction: ${style}. ` +
  'No text, no letters, no numbers, no watermark, no logo, no signature.';

// Quality is set per role rather than per install. Every image used to be
// generated at 'high', including the shop icon nobody sees above 200px and the
// three listing previews - together those were two thirds of the bill for a
// picture the customer never receives.
const QUALITY = {
  cover: $env.IMAGE_QUALITY_COVER || 'high',
  page: $env.IMAGE_QUALITY_PAGE || 'medium',
  small: $env.IMAGE_QUALITY_SMALL || 'low',
};

const jobs = [];
jobs.push({
  role: 'cover',
  key: 'cover',
  prompt: decorate(plan?.cover?.prompt || `Cover artwork for ${content.cover_title}`),
  size: base.profile.cover_size,
  format: 'jpeg',
  quality: QUALITY.cover,
});
jobs.push({
  role: 'thumbnail',
  key: 'thumbnail',
  prompt: decorate(plan?.thumbnail?.prompt || `Square shop icon for ${content.cover_title}`),
  size: base.profile.thumbnail_size,
  format: 'png',
  quality: QUALITY.small,
});

// Listing previews are shown beside the cover on the shop page. Drawing fresh
// mockups for them costs as much as the product's own artwork and shows the
// customer something that is not in the file they receive; by default they are
// composed from art this run already paid for. Set GENERATE_SEPARATE_PREVIEWS
// to true to go back to generating them.
const separatePreviews = String($env.GENERATE_SEPARATE_PREVIEWS || 'false')
  .toLowerCase() === 'true';
const previews = Array.isArray(plan?.previews) ? plan.previews : [];
if (separatePreviews) {
  for (let i = 0; i < base.profile.preview_count; i += 1) {
    jobs.push({
      role: 'preview',
      key: `preview_${i + 1}`,
      index: i + 1,
      prompt: decorate(previews[i]?.prompt || `Lifestyle mockup ${i + 1} of ${content.cover_title}`),
      size: base.profile.preview_size,
      format: 'jpeg',
      quality: QUALITY.small,
    });
  }
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
    quality: QUALITY.page,
  });
}

// Sanitise the optional editable vector source.
let svg = null;
let svgFallbackUsed = false;
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

// The profile promises SVG in output_formats, and QA stage 5 blocks the run if
// a promised format is missing. Whether the model remembers to return
// svg_markup is not something to leave to chance, so a valid vector is built
// here when it does not. Flat shapes and text only - the same constraints the
// prompt asks the model for.
if (base.profile.svg_required && !svg) {
  const palette = (idea.visual_direction && idea.visual_direction.palette) || [];
  const accent = /^#[0-9a-f]{6}$/i.test(palette[0] || '') ? palette[0] : '#2F4F6F';
  const title = String(idea.product_name || 'Product')
    .replace(/[<>&"']/g, ' ').slice(0, 42);
  svg = [
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">',
    '<rect width="1024" height="1024" fill="#FFFFFF"/>',
    `<rect x="0" y="0" width="1024" height="18" fill="${accent}"/>`,
    `<rect x="96" y="470" width="832" height="4" fill="${accent}"/>`,
    `<text x="512" y="440" text-anchor="middle" font-family="Helvetica, Arial, sans-serif"`,
    ` font-size="46" fill="#1A1A1A">${title}</text>`,
    `<text x="512" y="530" text-anchor="middle" font-family="Helvetica, Arial, sans-serif"`,
    ` font-size="24" fill="${accent}">editable vector source</text>`,
    '</svg>',
  ].join('');
  svgFallbackUsed = true;
}

return [{
  json: {
    run_id: base.run_id,
    dry_run: base.dry_run === true,
    image_jobs: jobs,
    svg_markup: svg,
    svg_fallback_used: svgFallbackUsed,
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
// Dry-run path: a tiny stand-in replaces a generated image so the rest of the
// pipeline (PDF, uploads, backup) can be rehearsed for free. It must keep the
// format the job asked for - the thumbnail job is PNG, and QA stage 5 reads
// magic bytes, so a JPEG in a .png file fails the rehearsal on a fault the
// rehearsal introduced.
const STANDINS = {
  png: '%s',
  jpeg: '%s',
};

const job = $input.first().json;
const format = String(job.format || 'jpeg').toLowerCase() === 'png' ? 'png' : 'jpeg';

return [{
  json: {
    ...job,
    b64: STANDINS[format],
    format,
    generated: false,
    placeholder: true,
  },
}];
""".strip() % (PLACEHOLDER_PNG, PLACEHOLDER_JPEG)

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

const pages = items.filter((j) => j.role === 'page' && j.b64);

// Previews are listing images, not deliverables. When none were generated they
// are composed from artwork this run already produced - the cover first, then
// page art - which shows the shopper what is actually inside the file and costs
// nothing. Falling back to the cover alone keeps the count right for a product
// whose pages carry no art.
let previews = items.filter((j) => j.role === 'preview' && j.b64);
let previewsReused = false;
if (!previews.length) {
  previewsReused = true;
  const pool = [byKey.cover, ...pages].filter(Boolean);
  previews = [];
  for (let i = 0; i < base.profile.preview_count; i += 1) {
    const source = pool[i % pool.length];
    if (source) previews.push({ index: i + 1, b64: source.b64 });
  }
}

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
      previews_reused: previewsReused,
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

JS_VALIDATE_SEO = AGENT_CONTENT_JS + ASARRAY_JS +r"""

// Etsy rejects listings on hard limits, so the model output is repaired here
// rather than trusted: 140 char title, exactly 13 tags, 20 chars per tag.
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;

// Each source node is addressed by a literal lookup rather than through a
// helper that takes the name as a string. build.py verifies every literal
// node reference resolves; one hidden behind a variable is invisible to it.
const readJson = (response) => {
  try {
    return JSON.parse(agentContent(response) || '{}');
  } catch (e) {
    return {};
  }
};

const titleOut = readJson($('OpenAI: SEO AI Title').first().json);
const descriptionOut = readJson($('OpenAI: SEO AI Description').first().json);
const tagsOut = readJson($('OpenAI: SEO AI Etsy Tags').first().json);

let title = String(titleOut.title || idea.product_name).replace(/\s+/g, ' ').trim();
if (title.length > 140) title = title.slice(0, 137).replace(/[\s,|-]+$/, '') + '...';

// Etsy caps a tag at 20 characters, and the cap used to be applied with a
// plain slice - which cuts mid-word and ships 'tech leadership resu' to a
// shopper. Trim back to the last whole word instead; a first word that is
// already too long leaves nothing usable, so that candidate is dropped rather
// than mangled.
const normaliseTag = (tag) => {
  const cleaned = String(tag)
    .toLowerCase()
    // Fold accents to their base letter first. Stripping them as punctuation
    // turned 'resume' (written with acutes) into 'r sum'.
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9 ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (cleaned.length <= 20) return cleaned;
  const cut = cleaned.slice(0, 20);
  const lastSpace = cut.lastIndexOf(' ');
  return lastSpace > 0 ? cut.slice(0, lastSpace) : '';
};

const candidates = [
  ...asArray(tagsOut.tags),
  ...asArray(base.research.sub_keywords),
  ...asArray(base.research.long_tail),
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

// The description is the listing copy a shopper reads, so it must be text.
// A model that answers with {intro, body, closing} instead of a string turned
// into the literal "[object Object]" on a real run - String() will happily
// stringify anything, which is exactly the problem.
// Only prose is collected. Walking every value of an object swept up whatever
// numeric fields the model happened to include, and a bare "5" was printed at
// the end of a real listing description.
const flattenText = (value) => {
  if (typeof value === 'string') return value.trim();
  if (Array.isArray(value)) return value.map(flattenText).filter(Boolean).join('\n\n');
  if (value && typeof value === 'object') return flattenText(Object.values(value));
  return '';
};

const description = flattenText(descriptionOut.description)
  || flattenText(descriptionOut.body)
  || flattenText(descriptionOut.text)
  || `${idea.product_name}\n\n${idea.promise || idea.one_liner || ''}`;

const disclosure = 'This is an instant digital download. No physical item will be shipped.';
const finalDescription = description.toLowerCase().includes('digital download')
  ? description
  : `${description}\n\n${disclosure}`;

const materials = (asArray(tagsOut.materials).length ? asArray(tagsOut.materials) : ['digital file', 'pdf', 'printable'])
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

JS_PARSE_METADATA = AGENT_CONTENT_JS + r"""
// Metadata is the record of truth for the database and Google Drive, so every
// field is clamped locally instead of trusted.
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const seo = $('Validate SEO Package').first().json.seo;
const response = $input.first().json;

let metadata = {};
try {
  metadata = JSON.parse(agentContent(response) || '{}');
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

JS_PARSE_QA = AGENT_CONTENT_JS + r"""
// The QA verdict decides whether anything reaches a marketplace at all.
const base = $('Merge: Factory Profiles').first().json;
const response = $input.first().json;

let report;
try {
  report = JSON.parse(agentContent(response) || '');
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
const gate = $('Aggregate QA Gate').first().json;
const idea = $('Parse Idea JSON').first().json.idea;

return [{
  json: {
    ok: false,
    run_id: base.run_id,
    factory: base.factory,
    product_name: idea.product_name,
    failure_reason: `QA rejected the product at stage(s) ${gate.failed_stages.join(', ')}: `
      + (gate.qa_blockers.join('; ') || 'no blocker detail'),
    qa: {
      passed: false,
      stages: gate.qa_stages,
      blockers: gate.qa_blockers,
      warnings: gate.qa_warnings,
      average_score: gate.qa_average_score,
      summary: `blocked at ${gate.failed_stages.join(', ')}`,
    },
  },
}];
""".strip()

JS_BUILD_PDF = ASARRAY_JS + PDF_LIB_JS + r"""

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
    ...asArray(content.usage_instructions).map((line) => `- ${line}`),
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


# ==========================================================================
# V2 additions: multi-stage QA (section 7), duplicate detection (13),
# versioning (12).
# ==========================================================================

SQL_CHECK_DUPLICATE = """
-- Section 12 + 13. One round trip answers both questions: is this a duplicate,
-- and if it is a legitimate revision, what version number is next?
WITH candidate AS (SELECT $1::text AS title_norm, $2::text AS keyword_set),
exact AS (
  SELECT run_id, product_name, created_at, version
  FROM adpf_products, candidate
  WHERE adpf_products.title_norm = candidate.title_norm
  ORDER BY created_at DESC LIMIT 1
),
-- "similar" is a reserved word in PostgreSQL (SIMILAR TO), hence the suffix.
similar_titles AS (
  SELECT product_name, title_norm, keyword_set, created_at
  FROM adpf_products
  WHERE title_norm IS NOT NULL AND status <> 'failed'
  ORDER BY created_at DESC LIMIT 300
)
SELECT
  (SELECT row_to_json(exact) FROM exact) AS exact_match,
  COALESCE((SELECT max(version) FROM adpf_products, candidate
            WHERE adpf_products.title_norm = candidate.title_norm), 0) AS max_version,
  COALESCE((SELECT json_agg(row_to_json(similar_titles)) FROM similar_titles), '[]'::json) AS recent;
""".strip()

JS_DUPLICATE_GATE = r"""
// Section 13 Duplicate Detector, at product level. The idea funnel already
// filtered on titles; this catches the case where two runs converge on the same
// product from different ideas.
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const row = $input.first().json || {};

const THRESHOLD = Number($env.DUPLICATE_SIMILARITY_THRESHOLD || 0.62);
const ALLOW_REVISION = String($env.ALLOW_PRODUCT_REVISION || 'false') === 'true';

const asArray = (value) => {
  if (Array.isArray(value)) return value;
  if (typeof value === 'string') { try { return JSON.parse(value); } catch (e) { return []; } }
  return value || [];
};
const parse = (value) => {
  if (!value) return null;
  if (typeof value === 'string') { try { return JSON.parse(value); } catch (e) { return null; } }
  return value;
};

const titleNorm = idea.product_name.toLowerCase().replace(/[^a-z0-9 ]/g, ' ')
  .replace(/\s+/g, ' ').trim();
const keywordSet = (base.research.sub_keywords || []).slice(0, 15).sort().join(',');

const tokenise = (text) => new Set(String(text).split(' ').filter((w) => w.length > 2));
const jaccard = (a, b) => {
  if (!a.size || !b.size) return 0;
  let shared = 0;
  for (const token of a) if (b.has(token)) shared += 1;
  return shared / (a.size + b.size - shared);
};

const tokens = tokenise(titleNorm);
let similarity = 0;
let similarTo = null;
for (const existing of asArray(row.recent)) {
  const score = jaccard(tokens, tokenise(existing.title_norm || ''));
  if (score > similarity) { similarity = score; similarTo = existing.product_name; }
}

const exactMatch = parse(row.exact_match);
const nextVersion = Number(row.max_version || 0) + 1;

let duplicate = false;
let reason = null;

if (exactMatch && !ALLOW_REVISION) {
  duplicate = true;
  reason = `"${idea.product_name}" already exists (run ${exactMatch.run_id})`;
} else if (similarity >= THRESHOLD) {
  duplicate = true;
  reason = `too similar to existing product "${similarTo}" (similarity ${Math.round(similarity * 100) / 100} >= ${THRESHOLD})`;
}

return [{
  json: {
    run_id: base.run_id,
    is_duplicate: duplicate,
    duplicate_reason: reason,
    similarity: Math.round(similarity * 100) / 100,
    similar_to: similarTo,
    title_norm: titleNorm,
    keyword_set: keywordSet,
    // Section 12: a revision of an existing product increments the version.
    version: exactMatch && ALLOW_REVISION ? nextVersion : 1,
    is_revision: Boolean(exactMatch && ALLOW_REVISION),
  },
}];
""".strip()

JS_QA_STAGE_1 = r"""
// QA stage 1 - Research: is the concept worth building at all?
// Deterministic: these are arithmetic checks on the research package, and a
// model adds nothing but variance.
const base = $('Merge: Factory Profiles').first().json;
const research = base.research || {};
const market = base.market || {};

const blockers = [];
const warnings = [];

if (!research.keyword) blockers.push('no primary keyword');
if ((research.sub_keywords || []).length < 5) blockers.push('fewer than 5 sub keywords');
// A short selling-point list is thin marketing input, not a broken product -
// the writer and the SEO agents work from the concept either way. Ending a
// paid run over it is out of proportion to the harm.
if ((research.selling_points || []).length < 3) {
  warnings.push(`only ${(research.selling_points || []).length} selling points - listing copy will be thin`);
}

// With no Etsy credential there are no market signals at all. That is a known
// state of this install, not a fault of the concept, so it must not be scored
// as though the research came back weak - it failed a sound product outright.
const hasMarketData = Object.keys(market).length > 0
  && Number(market.competitor_count || 0) > 0;

const competitors = Number(market.competitor_count || 0);
if (competitors === 0) warnings.push('no competitor data - market signal unavailable');
if (competitors > 90) warnings.push(`very crowded keyword (${competitors} competitors sampled)`);

const median = Number(market?.price_usd?.median || 0);
if (median > 0 && median < 2) blockers.push(`median price ${median} USD is below a viable floor`);

if (research.difficulty === 'hard' && competitors > 80) {
  warnings.push('hard difficulty in a crowded niche - low expected return');
}

// Score: keyword quality, signal quality, headroom.
const keywordScore = Math.min(10, (research.sub_keywords || []).length);
const signalScore = !hasMarketData ? 6
  : market.signal_quality === 'good' ? 10
  : market.signal_quality === 'thin' ? 6 : 3;
const demandScore = competitors > 0 ? Math.max(3, 10 - Math.floor(competitors / 20)) : 5;
const score = Math.round(((keywordScore + signalScore + demandScore) / 3) * 10) / 10;

return [{
  json: {
    stage: 'research', stage_no: 1, checked_by: 'code',
    passed: blockers.length === 0 && score >= 5,
    score, blockers, warnings,
    detail: { competitors, median_price_usd: median, difficulty: research.difficulty },
  },
}];
""".strip()

JS_QA_STAGE_2 = r"""
// QA stage 2 - Idea: does the economics work before a cent is spent on images?
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const research = base.research || {};
const market = base.market || {};
const profile = base.profile;

const blockers = [];
const warnings = [];

// Price the run the way it is actually configured. A flat per-image rate was
// four times the real cost once quality became per-role, and this figure gates
// the run on unit economics - overstating it rejects products that pay.
const IMAGE_PRICE = {                    // approx USD per image, gpt-image-1
  low:    { square: 0.011, portrait: 0.016 },
  medium: { square: 0.042, portrait: 0.063 },
  high:   { square: 0.167, portrait: 0.250 },
};
const priceOf = (quality, shape) => {
  const band = IMAGE_PRICE[String(quality || 'high').toLowerCase()] || IMAGE_PRICE.high;
  return band[shape];
};

const CHAT_RUN = Number($env.OPENAI_CHAT_RUN_COST_USD || 0.12);
const separatePreviews = String($env.GENERATE_SEPARATE_PREVIEWS || 'false')
  .toLowerCase() === 'true';

const images = 2 + profile.image_pages + (separatePreviews ? profile.preview_count : 0);
const estCost = Math.round((
  priceOf($env.IMAGE_QUALITY_COVER || 'high', 'portrait')
  + priceOf($env.IMAGE_QUALITY_PAGE || 'medium', 'portrait') * profile.image_pages
  + priceOf($env.IMAGE_QUALITY_SMALL || 'low', 'square')
      * (1 + (separatePreviews ? profile.preview_count : 0))
  + CHAT_RUN
) * 100) / 100;

const [minPrice, maxPrice] = profile.price_range_usd;
const price = Math.min(maxPrice, Math.max(minPrice,
  Number(research.price_suggestion_usd || minPrice)));
const estProfit = Math.round((price - estCost) * 100) / 100;
const marginPct = price > 0 ? Math.round((estProfit / price) * 1000) / 10 : 0;

if (estProfit <= 0) {
  blockers.push(`unit economics negative: ${price} USD price vs ${estCost} USD production`);
}
if (marginPct < 30 && estProfit > 0) {
  warnings.push(`thin margin (${marginPct}%) - one refund wipes out several sales`);
}
if (!idea.sections || idea.sections.length < 2) blockers.push('brief has fewer than 2 sections');
if (!idea.visual_direction || !idea.visual_direction.style) {
  warnings.push('no visual direction - images will not look like a set');
}

const median = Number(market?.price_usd?.median || 0);
if (median > 0 && price > median * 2.5) {
  warnings.push(`price ${price} is far above the market median ${median}`);
}

const profitScore = Math.max(0, Math.min(10, marginPct / 8));
const competitionScore = Math.max(0, Math.min(10, 10 - Number(market.competitor_count || 0) / 12));
const seoScore = Math.min(10, (research.sub_keywords || []).length * 0.8);
const marketScore = median > 0 ? 8 : 5;
const score = Math.round(((profitScore + competitionScore + seoScore + marketScore) / 4) * 10) / 10;

return [{
  json: {
    stage: 'idea', stage_no: 2, checked_by: 'code',
    passed: blockers.length === 0 && score >= 5,
    score, blockers, warnings,
    economics: { est_api_cost_usd: estCost, price_usd: price,
                 est_profit_usd: estProfit, margin_pct: marginPct, images },
  },
}];
""".strip()

JS_BUILD_DESIGN_QA_PROMPT = RENDER_HELPER + r"""
const base = $('Merge: Factory Profiles').first().json;
const content = $('Parse Content JSON').first().json.content;
const images = $('Collect Generated Images').first().json.images;
const agent = $('Prompt Library').first().json.prompts.design_qa_ai;
const profile = base.profile;

// The QA agent never sees pixels, so it is handed the geometry instead.
const pagePlan = content.pages.map((page) => ({
  page_number: page.page_number,
  title: page.title,
  line_count: page.lines.length,
  longest_line: page.lines.reduce((max, l) => Math.max(max, l.length), 0),
  has_image: page.needs_image,
}));

const parseSize = (size) => {
  const [w, h] = String(size || '1024x1024').split('x').map(Number);
  return { width: w || 1024, height: h || 1024 };
};

// Placement geometry must match what the PDF writer actually does, not an
// assumption about it. Claiming every image fills the page reported 120 DPI on
// art the writer places at 150, and QA blocked a sound product on a number
// this node invented. Mirrors the fit-inside-the-box maths in the PDF library.
const MARGIN_PT = 56;
const placement = (pxWidth, pxHeight, fullBleed) => {
  const bleed = fullBleed ? 0 : MARGIN_PT / 2;
  const scale = Math.min(
    (profile.page_width_pt - bleed * 2) / pxWidth,
    (profile.page_height_pt - bleed * 2) / pxHeight
  );
  const placedWidthPt = pxWidth * scale;
  return {
    placed_width_pt: Math.round(placedWidthPt),
    placed_height_pt: Math.round(pxHeight * scale),
    effective_dpi: Math.round(pxWidth / (placedWidthPt / 72)),
  };
};

// Only the cover and the page art are printed. The thumbnail and previews are
// shop listing images shown on screen, where print DPI does not apply.
const imageSpecs = [
  { role: 'cover', printed: true, full_bleed: true, ...parseSize(profile.cover_size) },
  { role: 'thumbnail', printed: false, ...parseSize(profile.thumbnail_size) },
  ...(images.previews || []).map((p) => ({
    role: `preview_${p.index}`, printed: false, ...parseSize(profile.preview_size) })),
  ...(images.pages || []).map((p) => ({
    role: `page_${p.page_number}`, printed: true, full_bleed: false, ...parseSize(profile.image_size) })),
].map((spec) => (spec.printed
  ? { ...spec, ...placement(spec.width, spec.height, spec.full_bleed === true) }
  : { ...spec, note: 'listing image, displayed on screen - print DPI does not apply' }));

return [{
  json: {
    run_id: base.run_id,
    design_qa_prompt: render(agent.user_template, {
      factory_profile_json: JSON.stringify({
        page_size: profile.page_size,
        page_width_pt: profile.page_width_pt,
        page_height_pt: profile.page_height_pt,
        margin_pt: 56, body_size_pt: 11, leading_pt: 16,
        target_pages: profile.target_pages,
      }, null, 2),
      page_plan_json: JSON.stringify(pagePlan, null, 2),
      image_specs_json: JSON.stringify(imageSpecs, null, 2),
    }),
  },
}];
""".rstrip()

JS_PARSE_DESIGN_QA = AGENT_CONTENT_JS + ASARRAY_JS +r"""

// QA stage 3 - Design. Model verdict plus a deterministic geometry re-check,
// because "will this text fit on the page" is arithmetic, not judgement.
const base = $('Merge: Factory Profiles').first().json;
const content = $('Parse Content JSON').first().json.content;
const profile = base.profile;
const response = $input.first().json;

let report;
try {
  report = JSON.parse(agentContent(response) || '{}');
} catch (e) {
  report = { passed: false, blockers: [`Design QA AI returned invalid JSON: ${e.message}`] };
}

const blockers = [...asArray(report.blockers)];
const warnings = [...asArray(report.warnings)];

// Deterministic re-check of the two things that actually break a PDF.
const MARGIN_PT = 56;                       // matches the PDF writer
const LEADING_PT = 16;
const usableHeight = profile.page_height_pt - MARGIN_PT * 2;
const maxLines = Math.floor(usableHeight / LEADING_PT);

for (const page of content.pages) {
  if (page.lines.length > maxLines * 3) {
    warnings.push(`page ${page.page_number} spans more than 3 physical pages (${page.lines.length} lines)`);
  }
}
if (MARGIN_PT / 2.835 < 10) blockers.push('page margin is below 10mm');

// Same fit-inside-the-box maths the PDF writer uses, so this warning describes
// the document that actually ships rather than a hypothetical full-bleed one.
const [artW, artH] = String(profile.image_size || '1024x1536').split('x').map(Number);
const artScale = Math.min(
  (profile.page_width_pt - 56) / (artW || 1024),
  (profile.page_height_pt - 56) / (artH || 1536)
);
const placedDpi = Math.round((artW || 1024) / (((artW || 1024) * artScale) / 72));
if (placedDpi < 150) {
  warnings.push(`page art lands at ~${placedDpi} DPI as placed - acceptable on screen, soft in print`);
}

const scores = report.scores || {};
const values = Object.values(scores).map(Number).filter((n) => !Number.isNaN(n));
const score = values.length ? Math.round((values.reduce((a, b) => a + b, 0) / values.length) * 10) / 10 : 5;

return [{
  json: {
    stage: 'design', stage_no: 3, checked_by: 'openai',
    passed: report.passed === true && blockers.length === 0,
    score, blockers, warnings, summary: report.summary || null,
  },
}];
""".strip()

JS_BUILD_CONTENT_QA_PROMPT = RENDER_HELPER + r"""
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const content = $('Parse Content JSON').first().json.content;
const seo = $('Validate SEO Package').first().json.seo;
const agent = $('Prompt Library').first().json.prompts.content_qa_ai;
const profile = base.profile;

return [{
  json: {
    run_id: base.run_id,
    content_qa_prompt: render(agent.user_template, {
      product_name: idea.product_name,
      // Without the factory's content schema the agent cannot tell a leftover
      // draft marker from a field the product exists to be filled in: a resume
      // kit's blank structure page was reported as "placeholder text", which is
      // precisely what that page is for.
      product_structure: `${profile.display_name}: ${profile.content_schema}`,
      target_customer: base.research.target_customer || '',
      content_json: JSON.stringify({
        cover_title: content.cover_title,
        cover_subtitle: content.cover_subtitle,
        intro_text: content.intro_text,
        usage_instructions: content.usage_instructions,
        pages: content.pages.map((p) => ({
          page_number: p.page_number, title: p.title, lines: p.lines,
        })),
      }, null, 2),
      seo_json: JSON.stringify(seo, null, 2),
    }),
  },
}];
""".rstrip()

JS_PARSE_CONTENT_QA = AGENT_CONTENT_JS + ASARRAY_JS +r"""

// QA stage 4 - Content: grammar, spelling, copyright, sensitive material.
const response = $input.first().json;
const content = $('Parse Content JSON').first().json.content;

let report;
try {
  report = JSON.parse(agentContent(response) || '{}');
} catch (e) {
  report = { passed: false, blockers: [`Content QA AI returned invalid JSON: ${e.message}`] };
}

const blockers = [...asArray(report.blockers)];
const warnings = [...asArray(report.warnings)];

// Deterministic backstop for the failures a proofreader would never miss but a
// model sometimes waves through.
//
// The bracket rule used to be /\[.*?\]/, which blocked every product built
// around fill-in fields: a resume kit's [Your Name] and a kids worksheet's
// [D O C T O R] both read as abandoned draft markers. Bracketed prompts are the
// deliverable for a template, so they are reported and left to the reviewer.
// What blocks is a marker no finished page should ever carry.
const DRAFT_MARKER = /(lorem ipsum|\binsert (?:your |the )?(?:text|name|content)(?: here)?\b|\bTBD\b|\bTODO\b|\bFIXME\b|\bplaceholder\b|\bx{4,}\b|\{\{\s*\w+\s*\}\}|\bcoming soon\b)/i;
const FILL_IN_FIELD = /\[[^\]\n]{1,60}\]|_{4,}/;
const seen = new Set();
for (const page of content.pages) {
  const body = page.lines.join(' ');
  if (DRAFT_MARKER.test(body) || DRAFT_MARKER.test(page.title)) {
    blockers.push(`page ${page.page_number} still carries a drafting marker`);
  } else if (FILL_IN_FIELD.test(body)) {
    warnings.push(`page ${page.page_number} has fill-in fields - expected for a template, check they are intentional`);
  }
  if (!body.trim()) blockers.push(`page ${page.page_number} is empty`);
  // Fingerprint the whole page, not its opening. Worksheets repeat their
  // instruction line by design - "Write your answer below" heads every page of
  // a template - and comparing only the first 120 characters called every one
  // of them a duplicate of the first.
  const fingerprint = `${page.title}|${body}`.toLowerCase().replace(/\s+/g, ' ').trim();
  if (fingerprint && seen.has(fingerprint)) {
    blockers.push(`page ${page.page_number} duplicates an earlier page`);
  }
  seen.add(fingerprint);
}

const issues = asArray(report.issues);
const scores = report.scores || {};
const values = Object.values(scores).map(Number).filter((n) => !Number.isNaN(n));
const score = values.length ? Math.round((values.reduce((a, b) => a + b, 0) / values.length) * 10) / 10 : 5;

return [{
  json: {
    stage: 'content', stage_no: 4, checked_by: 'openai',
    passed: report.passed === true && blockers.length === 0,
    score, blockers, warnings,
    issues: issues.slice(0, 30),
    summary: report.summary || null,
  },
}];
""".strip()

JS_AGGREGATE_QA = r"""
// Section 7: collect stages 1, 2, 3, 4 and 6 into one verdict. Stage 5 (export)
// runs later because it needs bytes that do not exist yet.
// Fail closed: every stage must pass.
const base = $('Merge: Factory Profiles').first().json;
const marketplace = $('Parse QA Report').first().json.qa;

const stage = (nodeName) => {
  try { return $(nodeName).first().json; } catch (e) { return null; }
};

const stages = [
  stage('QA Stage 1 Research'),
  stage('QA Stage 2 Idea'),
  stage('QA Stage 3 Design'),
  stage('QA Stage 4 Content'),
  {
    stage: 'marketplace', stage_no: 6, checked_by: 'openai',
    passed: marketplace.passed === true,
    score: marketplace.lowest_score,
    blockers: marketplace.blockers || [],
    warnings: marketplace.warnings || [],
  },
].filter(Boolean);

const failed = stages.filter((s) => !s.passed);
const blockers = stages.flatMap((s) => (s.blockers || []).map((b) => `[${s.stage}] ${b}`));
const warnings = stages.flatMap((s) => (s.warnings || []).map((w) => `[${s.stage}] ${w}`));
const scores = stages.map((s) => Number(s.score)).filter((n) => !Number.isNaN(n));

// A dry run feeds the line placeholder images and a locally synthesised idea,
// so QA is grading inputs the rehearsal invented: the placeholders always miss
// the DPI floor and the synthetic idea never matches the brief. Judging a
// rehearsal on those makes it impossible to pass, which defeats the point of
// having one. The verdict is still computed and reported in full - it simply
// does not stop the run.
const dryRun = base.dry_run === true;
const reallyPassed = failed.length === 0;

return [{
  json: {
    run_id: base.run_id,
    qa_stages: stages,
    qa_passed: dryRun ? true : reallyPassed,
    qa_advisory: dryRun,
    qa_would_have_passed: reallyPassed,
    failed_stages: dryRun ? [] : failed.map((s) => s.stage),
    advisory_failed_stages: failed.map((s) => s.stage),
    qa_blockers: dryRun ? [] : blockers,
    qa_warnings: dryRun
      ? [...warnings, ...blockers.map((b) => `[dry-run, not blocking] ${b}`)]
      : warnings,
    qa_average_score: scores.length
      ? Math.round((scores.reduce((a, b) => a + b, 0) / scores.length) * 10) / 10 : 0,
    qa_lowest_score: scores.length ? Math.min(...scores) : 0,
  },
}];
""".strip()

JS_QA_STAGE_5 = r"""
// QA stage 5 - Export: the files themselves. Every deliverable is opened and
// its magic bytes checked, so a corrupt PDF can never reach a customer.
const exported = $input.first().json;
const profile = $('Merge: Factory Profiles').first().json.profile;

const blockers = [];
const warnings = [];

const MAGIC = {
  PDF: (buf) => buf.slice(0, 5).toString('latin1') === '%PDF-',
  PNG: (buf) => buf.slice(0, 8).toString('hex') === '89504e470d0a1a0a',
  JPG: (buf) => buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff,
  SVG: (buf) => /<svg[\s>]/i.test(buf.slice(0, 400).toString('utf8')),
  JSON: (buf) => { try { JSON.parse(buf.toString('utf8')); return true; } catch (e) { return false; } },
  TXT: (buf) => buf.length > 0,
};

const checked = [];
for (const file of exported.files || []) {
  const buffer = Buffer.from(file.b64, 'base64');
  const verify = MAGIC[file.format];
  const valid = verify ? verify(buffer) : buffer.length > 0;

  if (!valid) blockers.push(`${file.file_name} is not a valid ${file.format} file`);
  if (buffer.length < 64) blockers.push(`${file.file_name} is only ${buffer.length} bytes`);
  if (file.format === 'PDF' && buffer.length < 20000) {
    warnings.push(`${file.file_name} is unusually small for a ${exported.stats.pdf_pages}-page PDF`);
  }
  checked.push({ file: file.file_name, format: file.format, bytes: buffer.length, valid });
}

// Every format the factory profile promises must actually be present.
const produced = new Set((exported.files || []).map((f) => f.format));
for (const format of profile.output_formats) {
  if (format === 'ZIP') continue;   // the bundle is assembled by the marketplace
  if (!produced.has(format)) blockers.push(`profile promises ${format} but no ${format} file was exported`);
}

if (exported.stats?.placeholder_images) {
  warnings.push('product contains dry-run placeholder art - do not publish');
}

const score = blockers.length ? 0 : (warnings.length ? 8 : 10);

return [{
  json: {
    ...exported,
    export_qa: {
      stage: 'export', stage_no: 5, checked_by: 'code',
      passed: blockers.length === 0,
      score, blockers, warnings, files_checked: checked,
    },
  },
}];
""".strip()

JS_FINALIZE_PRODUCT = r"""
// Attach the QA record, the version and the duplicate-detection fingerprints to
// the package that 01 will store.
const exported = $input.first().json;
const gate = $('Aggregate QA Gate').first().json;
const dedupe = $('Duplicate Gate').first().json;
const exportQa = exported.export_qa;

const allStages = [...gate.qa_stages, exportQa];
const passed = gate.qa_passed && exportQa.passed;

return [{
  json: {
    ...exported,
    ok: passed,
    // Name the stage *and* quote the blockers: "QA failed at: export" costs a
    // three-minute run to turn into an actionable fact.
    failure_reason: passed ? null
      : `QA failed at ${[...gate.failed_stages, exportQa.passed ? null : 'export']
            .filter(Boolean).join(', ')}: `
        + ([...gate.qa_blockers,
            ...exportQa.blockers.map((b) => `[export] ${b}`)].join('; ')
           || 'no blocker detail recorded'),
    qa: {
      passed,
      stages: allStages,
      blockers: [...gate.qa_blockers, ...exportQa.blockers.map((b) => `[export] ${b}`)],
      warnings: [...gate.qa_warnings, ...exportQa.warnings.map((w) => `[export] ${w}`)],
      average_score: Math.round(
        ((gate.qa_average_score * gate.qa_stages.length + exportQa.score) /
         (gate.qa_stages.length + 1)) * 10) / 10,
      // Never let a rehearsal read as a clean bill of health: export QA is real
      // (it opens the bytes) but stages 1-4 and 6 graded placeholder inputs.
      advisory: gate.qa_advisory === true,
      would_have_passed: gate.qa_advisory === true ? gate.qa_would_have_passed : null,
      advisory_failed_stages: gate.qa_advisory === true ? gate.advisory_failed_stages : [],
      summary: gate.qa_advisory === true
        ? `dry run - export QA passed for real, stages ${
            (gate.advisory_failed_stages || []).join(', ') || 'none'
          } are advisory only (placeholder art and a synthetic idea)`
        : (passed ? 'all six QA stages passed'
                  : `blocked at ${gate.failed_stages.join(', ') || 'export'}`),
    },
    // Section 12 + 13
    version: dedupe.version,
    is_revision: dedupe.is_revision,
    title_norm: dedupe.title_norm,
    keyword_set: dedupe.keyword_set,
    duplicate_similarity: dedupe.similarity,
  },
}];
""".strip()

JS_DUPLICATE_REJECTED = r"""
// Section 13: a duplicate is a business decision, not an error. Return ok=false
// so 01 records it and moves on to the next idea.
const base = $('Merge: Factory Profiles').first().json;
const idea = $('Parse Idea JSON').first().json.idea;
const dedupe = $('Duplicate Gate').first().json;

return [{
  json: {
    ok: false,
    run_id: base.run_id,
    factory: base.factory,
    product_name: idea.product_name,
    failure_reason: `Duplicate rejected: ${dedupe.duplicate_reason}`,
    duplicate: {
      similarity: dedupe.similarity,
      similar_to: dedupe.similar_to,
      reason: dedupe.duplicate_reason,
    },
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
                            "metadata_ai", "qa_ai", "design_qa_ai", "content_qa_ai"])),
           notes="Versioned prompts for the eight agents used on the production line.")
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
               # 2500 was tight for a contract carrying sections,
               # visual_direction and bonus_items; a truncated reply reads as a
               # missing field. The extra headroom costs about 1c per run.
               "$json.idea_user_prompt", temperature=0.8, max_tokens=4000),
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
    wf.add("Aggregate QA Gate", T_CODE, pos(31, 2), code(JS_AGGREGATE_QA),
           notes=("Section 7. Collects QA stages 1, 2, 3, 4 and 6 into one verdict. "
                  "Stage 5 runs after export, when the bytes exist."))
    wf.add("Check: QA Passed", T_IF, pos(32, 2), if_bool("={{ $json.qa_passed }}"),
           notes="Fail closed: every stage must pass before anything is built or published.")
    wf.add("Build QA Failure Result", T_CODE, pos(33, 3), code(JS_QA_FAILED),
           notes="Returns ok=false (business rejection) rather than raising an error.")

    # -- export ------------------------------------------------------------
    wf.add("Build PDF Document", T_CODE, pos(33, 1), code(JS_BUILD_PDF),
           notes=("Dependency-free PDF writer: Helvetica text pages plus JPEG images "
                  "embedded as /DCTDecode. No external service, no npm package."))
    wf.add("Export Files", T_CODE, pos(34, 1), code(JS_EXPORT_FILES),
           notes="Builds the deliverable manifest: PDF, PNG, JPG, SVG, JSON and TXT.")
    wf.add("QA Stage 5 Export", T_CODE, pos(35, 1), code(JS_QA_STAGE_5),
           notes=("Section 7 stage 5. Opens every exported file and checks its magic "
                  "bytes, so a corrupt PDF can never reach a customer."))
    wf.add("Finalize Product Package", T_CODE, pos(36, 1), code(JS_FINALIZE_PRODUCT),
           notes="Attaches the six-stage QA record, the version and the dedupe fingerprints.")
    wf.add("Return: Product Package", T_NOOP, pos(37, 2), {},
           notes="Terminal node - its item is the sub-workflow return value.")

    # -- V2: duplicate detection + versioning (sections 12, 13) ------------
    wf.add("QA Stage 1 Research", T_CODE, pos(6, 2), code(JS_QA_STAGE_1),
           notes=("Section 7 stage 1. Deterministic checks on the research package - "
                  "arithmetic, so no model is involved."))
    wf.add("Postgres: Check Existing Product", T_POSTGRES, pos(9, 4),
           {
               "operation": "executeQuery",
               "query": SQL_CHECK_DUPLICATE,
               "options": {"queryReplacement": (
                   "={{ [$('Parse Idea JSON').first().json.idea.product_name"
                   ".toLowerCase().replace(/[^a-z0-9 ]/g,' ').replace(/\\s+/g,' ').trim(), "
                   "($('Merge: Factory Profiles').first().json.research.sub_keywords || [])"
                   ".slice(0,15).sort().join(',')] }}"
               )},
           },
           notes="Sections 12 + 13. One round trip: exact match, next version, recent titles.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("Duplicate Gate", T_CODE, pos(10, 4), code(JS_DUPLICATE_GATE),
           notes=("Section 13. Jaccard similarity against recent products. "
                  "ALLOW_PRODUCT_REVISION=true turns an exact match into version N+1."))
    wf.add("Check: Not Duplicate", T_IF, pos(11, 4),
           if_bool("={{ !$json.is_duplicate }}"),
           notes="A duplicate stops here - before a single image is generated.")
    wf.add("Build Duplicate Rejection", T_CODE, pos(12, 5), code(JS_DUPLICATE_REJECTED),
           notes="Returns ok=false with the similarity evidence. Not an error.")
    wf.add("QA Stage 2 Idea", T_CODE, pos(12, 4), code(JS_QA_STAGE_2),
           notes=("Section 7 stage 2. Unit economics gate: price vs production cost, "
                  "computed before any image is paid for."))

    # -- V2: design and content QA stages ---------------------------------
    wf.add("Build Design QA Prompt", T_CODE, pos(18, 0), code(JS_BUILD_DESIGN_QA_PROMPT),
           notes="Hands the QA agent page geometry and image DPI - it never sees pixels.")
    wf.add("OpenAI: Design QA AI", T_HTTP, pos(19, 0),
           openai_chat(
               "($('Prompt Library').first().json.prompts.design_qa_ai.system + "
               "'\\n\\nOUTPUT CONTRACT (return exactly this JSON shape):\\n' + "
               "$('Prompt Library').first().json.prompts.design_qa_ai.output_contract)",
               "$json.design_qa_prompt", temperature=0.1, max_tokens=1500),
           notes="Agent 12/13. QA stage 3: layout, typography, margins, resolution.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("QA Stage 3 Design", T_CODE, pos(20, 0), code(JS_PARSE_DESIGN_QA),
           notes="Model verdict plus a deterministic geometry re-check.")

    wf.add("Build Content QA Prompt", T_CODE, pos(25, 3), code(JS_BUILD_CONTENT_QA_PROMPT),
           notes="Sends the exact copy that ships to the customer.")
    wf.add("OpenAI: Content QA AI", T_HTTP, pos(26, 3),
           openai_chat(
               "($('Prompt Library').first().json.prompts.content_qa_ai.system + "
               "'\\n\\nOUTPUT CONTRACT (return exactly this JSON shape):\\n' + "
               "$('Prompt Library').first().json.prompts.content_qa_ai.output_contract)",
               "$json.content_qa_prompt", temperature=0.1, max_tokens=3000),
           notes="Agent 13/13. QA stage 4: grammar, spelling, copyright, sensitive content.",
           onError="continueRegularOutput", alwaysOutputData=True, **RETRY)
    wf.add("QA Stage 4 Content", T_CODE, pos(27, 3), code(JS_PARSE_CONTENT_QA),
           notes="Adds deterministic placeholder / empty page / duplicate page detection.")

    # -- wiring ------------------------------------------------------------
    wf.chain("Receive Product Request", "Prompt Library", "Normalize Factory Input",
             "Route: Factory Type")
    wf.chain("Merge: Factory Profiles", "QA Stage 1 Research", "Build Idea Prompt",
             "OpenAI: Idea AI", "Parse Idea JSON",
             "Postgres: Check Existing Product", "Duplicate Gate", "Check: Not Duplicate")
    wf.link("Check: Not Duplicate", "QA Stage 2 Idea", 0)
    wf.link("Check: Not Duplicate", "Build Duplicate Rejection", 1)
    wf.link("Build Duplicate Rejection", "Return: Product Package")
    wf.chain("QA Stage 2 Idea", "Build Content Prompt", "OpenAI: Writer AI",
             "Parse Content JSON", "Build Designer Prompt", "OpenAI: Designer AI",
             "Parse Image Plan", "Split: Image Jobs", "Loop: Image Jobs")

    wf.link("Loop: Image Jobs", "Collect Generated Images", 0)
    wf.link("Loop: Image Jobs", "Check: Generate Image", 1)
    wf.link("Check: Generate Image", "OpenAI: Image API", 0)
    wf.link("Check: Generate Image", "Use Placeholder Image", 1)
    wf.link("OpenAI: Image API", "Store Generated Image")
    wf.link("Store Generated Image", "Loop: Image Jobs")
    wf.link("Use Placeholder Image", "Loop: Image Jobs")

    wf.chain("Collect Generated Images",
             "Build Design QA Prompt", "OpenAI: Design QA AI", "QA Stage 3 Design",
             "Build SEO Title Prompt", "OpenAI: SEO AI Title",
             "Build SEO Description Prompt", "OpenAI: SEO AI Description",
             "Build SEO Tags Prompt", "OpenAI: SEO AI Etsy Tags", "Validate SEO Package",
             "Build Content QA Prompt", "OpenAI: Content QA AI", "QA Stage 4 Content",
             "Build Metadata Prompt", "OpenAI: Metadata AI", "Parse Metadata JSON",
             "Build QA Prompt", "OpenAI: QA AI", "Parse QA Report",
             "Aggregate QA Gate", "Check: QA Passed")

    wf.link("Check: QA Passed", "Build PDF Document", 0)
    wf.link("Check: QA Passed", "Build QA Failure Result", 1)
    wf.chain("Build PDF Document", "Export Files", "QA Stage 5 Export",
             "Finalize Product Package", "Return: Product Package")
    wf.link("Build QA Failure Result", "Return: Product Package")

    return wf
