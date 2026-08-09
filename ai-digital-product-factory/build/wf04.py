"""04 Publish Engine - Etsy draft listing + Gumroad / MiriCanvas package prep."""

from common import (
    ETSY_TOKEN_NODE, etsy_token_node,
    AGENT_CONTENT_JS,
    RETRY, T_CODE, T_EXEC_TRIGGER, T_HTTP, T_IF, T_LOOP, T_NOOP, Workflow, code,
    etsy_http, if_bool, loop_node, openai_chat, pos,
)
from prompts import RENDER_HELPER, library_js


def etsy_form(method: str, url_expr: str, params: list[dict]) -> dict:
    """Etsy v3 write endpoints expect application/x-www-form-urlencoded."""
    node = etsy_http(method, url_expr)
    node["sendBody"] = True
    node["contentType"] = "form-urlencoded"
    node["specifyBody"] = "keypair"
    node["bodyParameters"] = {"parameters": params}
    return node


JS_NORMALIZE = r"""
// Unpack what 03 produced and refuse to publish anything that failed QA.
const ctx = $input.first().json;
const product = ctx.product || {};

if (product.ok !== true) {
  throw new Error(`04 Publish Engine received a product that did not pass QA: ${product.failure_reason || 'unknown'}`);
}

const files = product.files || [];
const fileByKey = Object.fromEntries(files.map((f) => [f.key, f]));

return [{
  json: {
    run_id: ctx.run_id,
    factory: ctx.factory,
    prompt_version: ctx.prompt_version,
    dry_run: ctx.dry_run === true,
    product_name: product.product_name,
    slug: product.slug,
    metadata: product.metadata,
    seo: product.seo,
    qa: product.qa,
    profile: product.profile,
    manifest: product.manifest,
    file_keys: Object.keys(fileByKey),
    listing_state: (ctx.etsy_listing_state || $env.ETSY_LISTING_STATE || 'draft').toLowerCase(),
  },
}];
""".strip()

JS_BUILD_PUBLISHER_PROMPT = RENDER_HELPER + r"""
const ctx = $input.first().json;
const agent = $('Prompt Library').first().json.prompts.publisher_ai;

return [{
  json: {
    ...ctx,
    publisher_user_prompt: render(agent.user_template, {
      metadata_json: JSON.stringify(ctx.metadata, null, 2),
      seo_json: JSON.stringify(ctx.seo, null, 2),
      qa_json: JSON.stringify(ctx.qa, null, 2),
      file_manifest: JSON.stringify(ctx.manifest, null, 2),
      factory_profile_json: JSON.stringify(ctx.profile, null, 2),
    }),
  },
}];
""".rstrip()

JS_PARSE_PUBLISHER = AGENT_CONTENT_JS + r"""
// The publisher verdict is advisory for compatibility and blocking for approval.
const ctx = $('Build Publisher Prompt').first().json;
const response = $input.first().json;

let verdict = {};
try {
  verdict = JSON.parse(agentContent(response) || '{}');
} catch (e) {
  verdict = {};
}

// Etsy state is decided by configuration, never by the model.
const listingState = ctx.listing_state === 'active' ? 'active' : 'draft';

return [{
  json: {
    ...ctx,
    publisher: {
      approved: verdict.approved !== false && ctx.qa?.passed === true,
      reason: verdict.reason || 'no reason returned',
      etsy: verdict.etsy || {},
      gumroad: verdict.gumroad || {},
      miricanvas: verdict.miricanvas || {},
    },
    listing_state: listingState,
  },
}];
""".strip()

JS_BUILD_LISTING_PAYLOAD = r"""
// Build the exact field set Etsy's createDraftListing expects. Everything is
// clamped again here because Etsy rejects the whole call on a single bad field.
const ctx = $input.first().json;
const seo = ctx.seo;
const metadata = ctx.metadata;

const tags = (seo.tags || []).slice(0, 13).map((t) => String(t).slice(0, 20));
const materials = (seo.materials || []).slice(0, 13).map((t) => String(t).slice(0, 45));

return [{
  json: {
    ...ctx,
    etsy_payload: {
      quantity: 999,
      title: String(seo.title).slice(0, 140),
      description: String(seo.description).slice(0, 12000),
      price: metadata.price_usd,
      who_made: 'i_did',
      when_made: 'made_to_order',
      taxonomy_id: Number($env.ETSY_TAXONOMY_ID || 2078),
      listing_type: 'download',
      is_supply: false,
      state: ctx.listing_state,
      tags: tags.join(','),
      materials: materials.join(','),
      should_auto_renew: false,
      is_personalizable: false,
    },
  },
}];
""".strip()

JS_ENUMERATE_IMAGES = r"""
// Etsy listing images, in display order: cover first, then the previews, then
// the thumbnail as the last slot.
const ctx = $('Build Etsy Listing Payload').first().json;
const listing = $input.first().json;
const files = $('Receive Publish Request').first().json.product.files;

const listingId = listing?.listing_id || listing?.results?.[0]?.listing_id;
if (!listingId) {
  throw new Error(`Etsy did not return a listing_id: ${JSON.stringify(listing).slice(0, 400)}`);
}

const order = ['cover_jpg', 'preview_1_jpg', 'preview_2_jpg', 'preview_3_jpg', 'thumbnail_png'];
const images = order
  .map((key) => files.find((f) => f.key === key))
  .filter(Boolean)
  .map((file, index) => ({
    run_id: ctx.run_id,
    listing_id: listingId,
    rank: index + 1,
    key: file.key,
    file_name: file.file_name,
    mime_type: file.mime_type,
    b64: file.b64,
  }));

if (!images.length) throw new Error('No listing images available to upload');
return images.map((json) => ({ json }));
""".strip()

JS_PREPARE_IMAGE_BINARY = r"""
// Convert the manifest entry into an n8n binary item for the multipart upload.
const job = $input.first().json;
return [{
  json: { listing_id: job.listing_id, rank: job.rank, key: job.key, file_name: job.file_name },
  binary: {
    data: {
      data: job.b64,
      mimeType: job.mime_type,
      fileName: job.file_name,
      fileExtension: job.file_name.split('.').pop(),
    },
  },
}];
""".strip()

JS_COLLECT_UPLOADS = r"""
// Summarise the image upload loop.
const uploads = $input.all().map((i) => i.json);
const ctx = $('Build Etsy Listing Payload').first().json;
const listingId = $('Enumerate Listing Images').first().json.listing_id;

return [{
  json: {
    ...ctx,
    etsy_listing_id: listingId,
    uploaded_images: uploads
      .map((u) => u.listing_image_id || u.results?.[0]?.listing_image_id)
      .filter(Boolean),
    uploaded_image_count: uploads.length,
  },
}];
""".strip()

JS_PREPARE_FILE_BINARY = r"""
// The actual product file the buyer downloads.
const ctx = $input.first().json;
const files = $('Receive Publish Request').first().json.product.files;
const pdf = files.find((f) => f.key === 'product_pdf');

if (!pdf) throw new Error('No product PDF found in the export manifest');

return [{
  json: { ...ctx, digital_file_name: pdf.file_name },
  binary: {
    data: {
      data: pdf.b64,
      mimeType: pdf.mime_type,
      fileName: pdf.file_name,
      fileExtension: 'pdf',
    },
  },
}];
""".strip()

JS_CHECK_GUMROAD = r"""
// Deterministic compatibility rules, then the model verdict as a veto only.
const ctx = $('Prepare Digital File Upload').first().json;
const publisher = ctx.publisher || {};
const files = $('Receive Publish Request').first().json.product.files;

const downloadable = files.filter((f) => ['PDF', 'SVG', 'PNG', 'JPG'].includes(f.format));
const reasons = [];

if (!ctx.profile.gumroad_ready) reasons.push('factory profile marks Gumroad as not applicable');
if (!downloadable.length) reasons.push('no downloadable file in the package');
if (!ctx.metadata.price_usd || ctx.metadata.price_usd < 1) reasons.push('price below the Gumroad minimum');
if (publisher.gumroad?.compatible === false) reasons.push(publisher.gumroad.reason || 'publisher agent vetoed');

return [{
  json: {
    ...ctx,
    etsy_listing_id: ctx.etsy_listing_id,
    gumroad_compatible: reasons.length === 0,
    gumroad_reasons: reasons,
    gumroad_file_count: downloadable.length,
  },
}];
""".strip()

JS_PREPARE_GUMROAD = r"""
// Prepare only - nothing is uploaded to Gumroad automatically. The manifest is
// everything a human (or a later workflow) needs to finish the listing.
const ctx = $input.first().json;
const files = $('Receive Publish Request').first().json.product.files;
const publisher = ctx.publisher || {};

const pkg = {
  platform: 'gumroad',
  status: 'prepared_not_uploaded',
  prepared_at: new Date().toISOString(),
  run_id: ctx.run_id,
  product_name: ctx.product_name,
  name: ctx.seo.title.slice(0, 100),
  description: ctx.seo.description,
  price_usd: publisher.gumroad?.suggested_price_usd || ctx.metadata.price_usd,
  currency: 'USD',
  tags: ctx.seo.tags.slice(0, 10),
  category: ctx.metadata.category,
  license: ctx.metadata.license,
  etsy_listing_id: ctx.etsy_listing_id,
  files: files
    .filter((f) => ['PDF', 'SVG', 'PNG', 'JPG'].includes(f.format))
    .map((f) => ({ file_name: f.file_name, format: f.format, bytes: f.bytes, purpose: f.purpose })),
  next_manual_steps: [
    'Review the description and price in the Gumroad dashboard',
    'Upload the files listed above from the Google Drive backup folder',
    'Publish when the Etsy listing has been reviewed',
  ],
};

return [{ json: { ...ctx, gumroad_package: pkg, gumroad_package_ready: true } }];
""".strip()

JS_SKIP_GUMROAD = r"""
// Not compatible - record why, then carry on.
const ctx = $input.first().json;
return [{
  json: {
    ...ctx,
    gumroad_package: {
      platform: 'gumroad',
      status: 'skipped',
      reasons: ctx.gumroad_reasons,
    },
    gumroad_package_ready: false,
  },
}];
""".strip()

JS_CHECK_MIRICANVAS = r"""
// MiriCanvas is only worth preparing when an editable source exists; a flattened
// PDF cannot be imported as a template.
const ctx = $input.first().json;
const publisher = ctx.publisher || {};
const files = $('Receive Publish Request').first().json.product.files;
const svg = files.find((f) => f.format === 'SVG');

const reasons = [];
if (!ctx.profile.miricanvas_ready) reasons.push('factory profile marks MiriCanvas as not applicable');
if (!svg) reasons.push('no editable SVG source in the package');
if (publisher.miricanvas?.compatible === false) {
  reasons.push(publisher.miricanvas.reason || 'publisher agent vetoed');
}

return [{
  json: {
    ...ctx,
    miricanvas_compatible: reasons.length === 0,
    miricanvas_reasons: reasons,
    miricanvas_source: svg ? svg.file_name : null,
  },
}];
""".strip()

JS_PREPARE_MIRICANVAS = r"""
// Prepare only - no automatic upload. MiriCanvas has no public write API, so
// this manifest is the hand-off for a human import.
const ctx = $input.first().json;
const files = $('Receive Publish Request').first().json.product.files;

const pkg = {
  platform: 'miricanvas',
  status: 'prepared_not_uploaded',
  prepared_at: new Date().toISOString(),
  run_id: ctx.run_id,
  template_name: ctx.product_name,
  category: ctx.metadata.category,
  canvas: {
    width_pt: ctx.profile.page_width_pt,
    height_pt: ctx.profile.page_height_pt,
    page_size: ctx.profile.page_size,
  },
  editable_source: ctx.miricanvas_source,
  assets: files
    .filter((f) => ['SVG', 'PNG', 'JPG'].includes(f.format))
    .map((f) => ({ file_name: f.file_name, format: f.format, purpose: f.purpose })),
  text_slots: (ctx.seo.tags || []).slice(0, 5),
  next_manual_steps: [
    'Import the SVG source into MiriCanvas',
    'Map the editable text slots and save as a template',
    'Keep the licence note from metadata.json in the template description',
  ],
};

return [{ json: { ...ctx, miricanvas_package: pkg, miricanvas_package_ready: true } }];
""".strip()

JS_SKIP_MIRICANVAS = r"""
const ctx = $input.first().json;
return [{
  json: {
    ...ctx,
    miricanvas_package: {
      platform: 'miricanvas',
      status: 'skipped',
      reasons: ctx.miricanvas_reasons,
    },
    miricanvas_package_ready: false,
  },
}];
""".strip()

JS_BUILD_RESULT = r"""
// Publish contract returned to 01. The prepared packages are appended to the
// file manifest so 05 backs them up to Google Drive alongside the product.
const ctx = $input.first().json;
const fileUpload = (() => {
  try { return $('Etsy: Upload Listing File').first().json; } catch (e) { return {}; }
})();

const encode = (obj) => Buffer.from(JSON.stringify(obj, null, 2), 'utf8').toString('base64');
const extraFiles = [];

if (ctx.gumroad_package_ready) {
  const payload = encode(ctx.gumroad_package);
  extraFiles.push({
    key: 'gumroad_package_json',
    file_name: 'gumroad-package.json',
    format: 'JSON',
    mime_type: 'application/json',
    purpose: 'prepared Gumroad package (not uploaded)',
    bytes: Math.round((payload.length * 3) / 4),
    b64: payload,
  });
}
if (ctx.miricanvas_package_ready) {
  const payload = encode(ctx.miricanvas_package);
  extraFiles.push({
    key: 'miricanvas_package_json',
    file_name: 'miricanvas-package.json',
    format: 'JSON',
    mime_type: 'application/json',
    purpose: 'prepared MiriCanvas package (not uploaded)',
    bytes: Math.round((payload.length * 3) / 4),
    b64: payload,
  });
}

return [{
  json: {
    ok: true,
    run_id: ctx.run_id,
    etsy_listing_id: ctx.etsy_listing_id,
    etsy_listing_state: ctx.listing_state,
    etsy_listing_url: `https://www.etsy.com/listing/${ctx.etsy_listing_id}`,
    uploaded_image_count: ctx.uploaded_image_count || 0,
    digital_file_id: fileUpload?.listing_file_id || null,
    gumroad_package_ready: ctx.gumroad_package_ready === true,
    gumroad_package: ctx.gumroad_package,
    miricanvas_package_ready: ctx.miricanvas_package_ready === true,
    miricanvas_package: ctx.miricanvas_package,
    extra_files: extraFiles,
    published_at: new Date().toISOString(),
  },
}];
""".strip()

JS_PUBLISH_FAILED = r"""
// Any Etsy failure or a publisher veto ends here with ok=false so 01 can log it.
const item = $input.first().json;
const ctx = (() => {
  try { return $('Normalize Publish Input').first().json; } catch (e) { return {}; }
})();

const error = item.error || {};
const reason = item.publisher?.approved === false
  ? `Publisher agent refused to publish: ${item.publisher.reason}`
  : (error.message || item.message || 'Etsy listing creation failed');

return [{
  json: {
    ok: false,
    run_id: ctx.run_id || item.run_id,
    product_name: ctx.product_name || null,
    failure_reason: String(reason).slice(0, 1000),
    etsy_response: error.description || null,
    failed_stage: 'publish',
  },
}];
""".strip()


def build() -> Workflow:
    wf = Workflow("04")

    wf.add("Receive Publish Request", T_EXEC_TRIGGER, pos(0, 2),
           {"inputSource": "passthrough"},
           notes="Entry point. Called by 01 with the exported product package.")
    wf.add("Prompt Library", T_CODE, pos(1, 2), code(library_js(["publisher_ai"])),
           notes="Versioned prompt for the Publisher agent.")
    wf.add("Normalize Publish Input", T_CODE, pos(2, 2), code(JS_NORMALIZE),
           notes="Refuses anything that did not pass the QA gate in 03.")

    wf.add("Build Publisher Prompt", T_CODE, pos(3, 2), code(JS_BUILD_PUBLISHER_PROMPT),
           notes="Renders the Publisher AI template.")
    wf.add("OpenAI: Publisher AI", T_HTTP, pos(4, 2),
           openai_chat(
               "($('Prompt Library').first().json.prompts.publisher_ai.system + "
               "'\\n\\nOUTPUT CONTRACT (return exactly this JSON shape):\\n' + "
               "$('Prompt Library').first().json.prompts.publisher_ai.output_contract)",
               "$json.publisher_user_prompt", temperature=0.2, max_tokens=2000),
           notes="Agent 8/8. Final policy check plus cross-platform compatibility opinion.",
           **RETRY)
    wf.add("Parse Publisher Verdict", T_CODE, pos(5, 2), code(JS_PARSE_PUBLISHER),
           notes="The listing state comes from configuration, never from the model.")
    wf.add("Check: Publisher Approved", T_IF, pos(6, 2),
           if_bool("={{ $json.publisher.approved }}"),
           notes="A veto here stops the upload entirely.")

    wf.add("Build Etsy Listing Payload", T_CODE, pos(7, 2), code(JS_BUILD_LISTING_PAYLOAD),
           notes="Clamps every Etsy field again - one bad field rejects the whole call.")
    wf.add(ETSY_TOKEN_NODE, T_HTTP, pos(7.5, 2), etsy_token_node(),
           notes="Trades the refresh token for a one-hour access token. Etsy mandates PKCE on the authorisation code flow and n8n's OAuth2 credential does not send a code_challenge, so the suite carries a refresh token instead.", **RETRY)
    wf.add(
        "Etsy: Create Draft Listing", T_HTTP, pos(8, 2),
        etsy_form(
            "POST",
            "={{ $env.ETSY_API_BASE }}/v3/application/shops/{{ $env.ETSY_SHOP_ID }}/listings",
            [
                {"name": "quantity", "value": "={{ $json.etsy_payload.quantity }}"},
                {"name": "title", "value": "={{ $json.etsy_payload.title }}"},
                {"name": "description", "value": "={{ $json.etsy_payload.description }}"},
                {"name": "price", "value": "={{ $json.etsy_payload.price }}"},
                {"name": "who_made", "value": "={{ $json.etsy_payload.who_made }}"},
                {"name": "when_made", "value": "={{ $json.etsy_payload.when_made }}"},
                {"name": "taxonomy_id", "value": "={{ $json.etsy_payload.taxonomy_id }}"},
                {"name": "type", "value": "={{ $json.etsy_payload.listing_type }}"},
                {"name": "is_supply", "value": "={{ $json.etsy_payload.is_supply }}"},
                {"name": "state", "value": "={{ $json.etsy_payload.state }}"},
                {"name": "tags", "value": "={{ $json.etsy_payload.tags }}"},
                {"name": "materials", "value": "={{ $json.etsy_payload.materials }}"},
                {"name": "should_auto_renew", "value": "={{ $json.etsy_payload.should_auto_renew }}"},
            ],
        ),
        notes=("Creates the listing as a DRAFT (state comes from ETSY_LISTING_STATE, "
               "default draft) so a human reviews before it goes live. OAuth2 credential."),
        onError="continueErrorOutput", **RETRY,
    )
    wf.add("Check: Listing Created", T_IF, pos(9, 2),
           if_bool("={{ !!($json.listing_id || $json.results) }}"),
           notes="Etsy returns listing_id on success; anything else is a failure.")

    wf.add("Enumerate Listing Images", T_CODE, pos(10, 2), code(JS_ENUMERATE_IMAGES),
           notes="Cover, previews, then thumbnail - one item per image, ranked.")
    wf.add("Loop: Listing Images", T_LOOP, pos(11, 2), loop_node(1),
           notes="Sequential upload keeps well inside Etsy's rate limits.")
    wf.add("Prepare Image Upload", T_CODE, pos(12, 3), code(JS_PREPARE_IMAGE_BINARY),
           notes="base64 manifest entry -> n8n binary for the multipart request.")
    wf.add(
        "Etsy: Upload Listing Image", T_HTTP, pos(13, 3),
        etsy_http(
            "POST",
            "={{ $env.ETSY_API_BASE }}/v3/application/shops/{{ $env.ETSY_SHOP_ID }}"
            "/listings/{{ $json.listing_id }}/images",
            multipart=[
                {"parameterType": "formBinaryData", "name": "image", "inputDataFieldName": "data"},
                {"name": "rank", "value": "={{ $json.rank }}"},
            ],
            timeout=180000,
        ),
        notes="Multipart image upload, one call per image.",
        onError="continueRegularOutput", alwaysOutputData=True, **RETRY,
    )
    wf.add("Collect Image Uploads", T_CODE, pos(12, 2), code(JS_COLLECT_UPLOADS),
           notes="Summarises the loop and carries the listing id forward.")

    wf.add("Prepare Digital File Upload", T_CODE, pos(13, 2), code(JS_PREPARE_FILE_BINARY),
           notes="The PDF the buyer actually downloads, as binary.")
    wf.add(
        "Etsy: Upload Listing File", T_HTTP, pos(14, 2),
        etsy_http(
            "POST",
            "={{ $env.ETSY_API_BASE }}/v3/application/shops/{{ $env.ETSY_SHOP_ID }}"
            "/listings/{{ $json.etsy_listing_id }}/files",
            multipart=[
                {"parameterType": "formBinaryData", "name": "file", "inputDataFieldName": "data"},
                {"name": "name", "value": "={{ $json.digital_file_name }}"},
                {"name": "rank", "value": "1"},
            ],
            timeout=300000,
        ),
        notes="Attaches the digital download to the listing.",
        onError="continueRegularOutput", alwaysOutputData=True, **RETRY,
    )

    wf.add("Check Gumroad Compatibility", T_CODE, pos(15, 2), code(JS_CHECK_GUMROAD),
           notes="Deterministic rules first; the Publisher agent can only veto.")
    wf.add("Check: Gumroad Compatible", T_IF, pos(16, 2),
           if_bool("={{ $json.gumroad_compatible }}"),
           notes="Compatible products get a prepared package - never an automatic upload.")
    wf.add("Prepare Gumroad Package", T_CODE, pos(17, 1), code(JS_PREPARE_GUMROAD),
           notes="Builds gumroad-package.json. PREPARE ONLY, no API call to Gumroad.")
    wf.add("Skip Gumroad Package", T_CODE, pos(17, 3), code(JS_SKIP_GUMROAD),
           notes="Records why Gumroad was skipped so the reason is auditable.")

    wf.add("Check MiriCanvas Compatibility", T_CODE, pos(18, 2), code(JS_CHECK_MIRICANVAS),
           notes="Requires an editable SVG source - a flat PDF is not importable.")
    wf.add("Check: MiriCanvas Compatible", T_IF, pos(19, 2),
           if_bool("={{ $json.miricanvas_compatible }}"),
           notes="Same rule as Gumroad: prepare only.")
    wf.add("Prepare MiriCanvas Package", T_CODE, pos(20, 1), code(JS_PREPARE_MIRICANVAS),
           notes="Builds miricanvas-package.json. PREPARE ONLY, no upload.")
    wf.add("Skip MiriCanvas Package", T_CODE, pos(20, 3), code(JS_SKIP_MIRICANVAS),
           notes="Records why MiriCanvas was skipped.")

    wf.add("Merge: Package Preparation", T_NOOP, pos(21, 2), {},
           notes="Join point for both compatibility branches.")
    wf.add("Build Publish Result", T_CODE, pos(22, 2), code(JS_BUILD_RESULT),
           notes="Publish contract for 01, plus the package files for the Drive backup.")
    wf.add("Return: Publish Result", T_NOOP, pos(23, 2), {},
           notes="Terminal node - its item is the sub-workflow return value.")
    wf.add("Build Publish Failure", T_CODE, pos(22, 4), code(JS_PUBLISH_FAILED),
           notes="Turns a veto or an Etsy error into ok=false with a readable reason.")

    # -- wiring ------------------------------------------------------------
    wf.chain("Receive Publish Request", "Prompt Library", "Normalize Publish Input",
             "Build Publisher Prompt", "OpenAI: Publisher AI", "Parse Publisher Verdict",
             "Check: Publisher Approved")
    wf.link("Check: Publisher Approved", "Build Etsy Listing Payload", 0)
    wf.link("Check: Publisher Approved", "Build Publish Failure", 1)

    wf.link("Build Etsy Listing Payload", ETSY_TOKEN_NODE)
    wf.link(ETSY_TOKEN_NODE, "Etsy: Create Draft Listing")
    wf.link("Etsy: Create Draft Listing", "Check: Listing Created", 0)
    wf.link("Etsy: Create Draft Listing", "Build Publish Failure", 1)
    wf.link("Check: Listing Created", "Enumerate Listing Images", 0)
    wf.link("Check: Listing Created", "Build Publish Failure", 1)

    wf.link("Enumerate Listing Images", "Loop: Listing Images")
    wf.link("Loop: Listing Images", "Collect Image Uploads", 0)
    wf.link("Loop: Listing Images", "Prepare Image Upload", 1)
    wf.link("Prepare Image Upload", "Etsy: Upload Listing Image")
    wf.link("Etsy: Upload Listing Image", "Loop: Listing Images")

    wf.chain("Collect Image Uploads", "Prepare Digital File Upload",
             "Etsy: Upload Listing File", "Check Gumroad Compatibility",
             "Check: Gumroad Compatible")
    wf.link("Check: Gumroad Compatible", "Prepare Gumroad Package", 0)
    wf.link("Check: Gumroad Compatible", "Skip Gumroad Package", 1)
    wf.link("Prepare Gumroad Package", "Check MiriCanvas Compatibility")
    wf.link("Skip Gumroad Package", "Check MiriCanvas Compatibility")

    wf.link("Check MiriCanvas Compatibility", "Check: MiriCanvas Compatible")
    wf.link("Check: MiriCanvas Compatible", "Prepare MiriCanvas Package", 0)
    wf.link("Check: MiriCanvas Compatible", "Skip MiriCanvas Package", 1)
    wf.link("Prepare MiriCanvas Package", "Merge: Package Preparation")
    wf.link("Skip MiriCanvas Package", "Merge: Package Preparation")

    wf.chain("Merge: Package Preparation", "Build Publish Result", "Return: Publish Result")
    wf.link("Build Publish Failure", "Return: Publish Result")

    return wf
