"""05 Google Drive Backup - idempotent folder tree + file upload."""

from common import (
    RETRY, T_CODE, T_EXEC_TRIGGER, T_GDRIVE, T_HTTP, T_IF, T_LOOP, T_NOOP,
    Workflow, code, drive_http, if_bool, loop_node, pos,
)

FOLDER_MIME = "application/vnd.google-apps.folder"

JS_BUILD_PLAN = r"""
// Work out the backup destination:
//   AI Digital Product Factory / Etsy / <Category> / <Product Name>
// Folder names are sanitised because they end up inside a Drive query string.
const ctx = $input.first().json;
const product = ctx.product || {};
const publish = ctx.publish || {};
const metadata = product.metadata || {};

const clean = (value, fallback) => String(value || fallback)
  .replace(/[\\/:*?"<>|']/g, ' ')
  .replace(/[\x00-\x1f]/g, '')
  .replace(/\s+/g, ' ')
  .trim()
  .slice(0, 120) || fallback;

return [{
  json: {
    run_id: ctx.run_id,
    factory: ctx.factory,
    prompt_version: ctx.prompt_version,
    product_name: metadata.product_name || product.product_name,
    category: metadata.category || 'Uncategorised',
    etsy_listing_id: publish.etsy_listing_id || null,
    folder_names: {
      root: 'AI Digital Product Factory',
      marketplace: 'Etsy',
      category: clean(metadata.category, 'Uncategorised'),
      product: clean(metadata.product_name || product.product_name, `product-${ctx.run_id}`),
    },
    parent_root: $env.GDRIVE_ROOT_FOLDER_ID || 'root',
    folder_ids: {},
  },
}];
""".strip()


def _resolve_js(level_key: str, previous_node: str) -> str:
    return (
        "// Both branches land here: an existing folder from the search, or the\n"
        "// folder that was just created. One shape out either way.\n"
        "const plan = $('%s').first().json;\n"
        "const found = $input.first().json;\n"
        "const id = found?.files?.[0]?.id || found?.id;\n\n"
        "if (!id) {\n"
        "  throw new Error('Could not resolve the Google Drive folder for level: %s');\n"
        "}\n\n"
        "return [{ json: { ...plan, folder_ids: { ...plan.folder_ids, %s: id }, "
        "current_parent: id } }];\n"
        % (previous_node, level_key, level_key)
    )


JS_ENUMERATE_FILES = r"""
// One item per file to back up. The product export, the prepared marketplace
// packages and a workflow log all land in the same product folder.
const plan = $('Resolve Product Folder').first().json;
const ctx = $('Receive Backup Request').first().json;
const product = ctx.product || {};
const publish = ctx.publish || {};

const files = [...(product.files || []), ...(publish.extra_files || [])];

// Workflow log: what ran, what it cost, what came out.
const log = [
  `AI Digital Product Factory - workflow log`,
  `====================================================`,
  `Run id           : ${ctx.run_id}`,
  `Factory          : ${ctx.factory}`,
  `Product          : ${plan.product_name}`,
  `Category         : ${plan.category}`,
  `Prompt version   : ${ctx.prompt_version}`,
  `Started at       : ${ctx.started_at}`,
  `Backed up at     : ${new Date().toISOString()}`,
  ``,
  `Etsy listing id  : ${publish.etsy_listing_id || 'n/a'}`,
  `Etsy state       : ${publish.etsy_listing_state || 'n/a'}`,
  `Etsy images      : ${publish.uploaded_image_count || 0}`,
  `Gumroad package  : ${publish.gumroad_package_ready ? 'prepared' : 'skipped'}`,
  `MiriCanvas pkg   : ${publish.miricanvas_package_ready ? 'prepared' : 'skipped'}`,
  ``,
  `PDF pages        : ${product.stats?.pdf_pages ?? 'n/a'}`,
  `Content pages    : ${product.stats?.content_pages ?? 'n/a'}`,
  `Images generated : ${product.stats?.images?.generated ?? 'n/a'} / ${product.stats?.images?.requested ?? 'n/a'}`,
  `Placeholder art  : ${product.stats?.placeholder_images ? 'YES (dry run)' : 'no'}`,
  `Total bytes      : ${product.stats?.total_bytes ?? 'n/a'}`,
  `QA summary       : ${product.qa?.summary || 'n/a'}`,
  ``,
  `Files`,
  `-----`,
  ...files.map((f) => `- ${f.file_name} (${f.format}, ${f.bytes} bytes) - ${f.purpose}`),
].join('\n');

const all = [
  ...files,
  {
    key: 'workflow_log_txt',
    file_name: 'workflow-log.txt',
    format: 'TXT',
    mime_type: 'text/plain',
    purpose: 'run log',
    b64: Buffer.from(log, 'utf8').toString('base64'),
  },
];

return all.map((file, index) => ({
  json: {
    ...file,
    upload_index: index + 1,
    upload_total: all.length,
    parent_folder_id: plan.folder_ids.product,
  },
}));
""".strip()

JS_PREPARE_UPLOAD = r"""
// Manifest entry -> binary item for the Google Drive node.
const file = $input.first().json;
return [{
  json: {
    file_name: file.file_name,
    parent_folder_id: file.parent_folder_id,
    key: file.key,
    format: file.format,
  },
  binary: {
    data: {
      data: file.b64,
      mimeType: file.mime_type,
      fileName: file.file_name,
      fileExtension: (file.file_name.split('.').pop() || 'bin'),
    },
  },
}];
""".strip()

JS_COLLECT_UPLOADS = r"""
// Backup contract returned to 01.
const plan = $('Resolve Product Folder').first().json;
const uploads = $input.all().map((i) => i.json).filter((u) => u && (u.id || u.fileId));

return [{
  json: {
    ok: true,
    run_id: plan.run_id,
    drive_folder_id: plan.folder_ids.product,
    drive_folder_path: [
      plan.folder_names.root,
      plan.folder_names.marketplace,
      plan.folder_names.category,
      plan.folder_names.product,
    ].join('/'),
    drive_folder_ids: plan.folder_ids,
    uploaded_files: uploads.map((u) => ({
      id: u.id || u.fileId,
      name: u.name || u.file_name,
      web_link: u.webViewLink || null,
    })),
    uploaded_file_count: uploads.length,
    backed_up_at: new Date().toISOString(),
  },
}];
""".strip()


def _find_url(name_expr: str, parent_expr: str) -> str:
    """Drive files.list query that is exact, scoped to one parent, and safe."""
    query = (
        "\"name='\" + " + name_expr + " + \"' and mimeType='" + FOLDER_MIME + "' and '\" + "
        + parent_expr + " + \"' in parents and trashed=false\""
    )
    return (
        "=https://www.googleapis.com/drive/v3/files"
        "?q={{ encodeURIComponent(" + query + ") }}"
        "&fields=files(id,name)&pageSize=1"
        "&supportsAllDrives=true&includeItemsFromAllDrives=true"
    )


def _create_body(name_expr: str, parent_expr: str) -> str:
    return (
        "={{ JSON.stringify({ name: " + name_expr + ", mimeType: '" + FOLDER_MIME + "', "
        "parents: [" + parent_expr + "] }) }}"
    )


# (label, level key, node that currently holds the plan, parent field on it)
LEVELS = [
    ("Root Folder", "root", "Build Backup Plan", "parent_root"),
    ("Marketplace Folder", "marketplace", "Resolve Root Folder", "folder_ids.root"),
    ("Category Folder", "category", "Resolve Marketplace Folder", "folder_ids.marketplace"),
    ("Product Folder", "product", "Resolve Category Folder", "folder_ids.category"),
]


def build() -> Workflow:
    wf = Workflow("05")

    wf.add("Receive Backup Request", T_EXEC_TRIGGER, pos(0, 2),
           {"inputSource": "passthrough"},
           notes="Entry point. Called by 01 only after Etsy accepted the listing.")
    wf.add("Build Backup Plan", T_CODE, pos(1, 2), code(JS_BUILD_PLAN),
           notes="Resolves and sanitises the four folder names of the backup path.")

    column = 2
    for label, key, plan_node, parent_field in LEVELS:
        # Always address the plan through the node that holds it: the IF and the
        # search node both replace $json with a Drive API response.
        ref = f"$('{plan_node}').first().json"
        name_expr = f"{ref}.folder_names.{key}"
        parent_expr = f"{ref}.{parent_field}"

        find_name = f"Drive: Find {label}"
        check_name = f"Check: {label} Exists"
        create_name = f"Drive: Create {label}"
        resolve_name = f"Resolve {label}"

        wf.add(find_name, T_HTTP, pos(column, 2),
               drive_http("GET", _find_url(name_expr, parent_expr)),
               notes=f"Look for '{key}' under its parent. Makes the backup idempotent.",
               **RETRY)
        wf.add(check_name, T_IF, pos(column + 1, 2),
               if_bool("={{ ($json.files || []).length > 0 }}"),
               notes="Reuse the existing folder instead of creating a duplicate.")
        wf.add(create_name, T_HTTP, pos(column + 1, 3),
               drive_http(
                   "POST",
                   "=https://www.googleapis.com/drive/v3/files"
                   "?supportsAllDrives=true&fields=id,name",
                   body_expr=_create_body(name_expr, parent_expr),
               ),
               notes=f"Create the '{key}' folder on first run. Google Drive OAuth2 credential.",
               **RETRY)
        wf.add(resolve_name, T_CODE, pos(column + 2, 2),
               code(_resolve_js(key, plan_node)),
               notes="Normalises both branches into one folder id for the next level.")

        wf.link(find_name, check_name)
        wf.link(check_name, resolve_name, 0)
        wf.link(check_name, create_name, 1)
        wf.link(create_name, resolve_name)
        column += 3

    wf.link("Receive Backup Request", "Build Backup Plan")
    wf.link("Build Backup Plan", "Drive: Find Root Folder")
    wf.link("Resolve Root Folder", "Drive: Find Marketplace Folder")
    wf.link("Resolve Marketplace Folder", "Drive: Find Category Folder")
    wf.link("Resolve Category Folder", "Drive: Find Product Folder")

    wf.add("Enumerate Backup Files", T_CODE, pos(column, 2), code(JS_ENUMERATE_FILES),
           notes=("Product PDF, cover, thumbnail, previews, metadata.json, description.txt, "
                  "Prompt.md, SEO.json, source files, prepared packages and the workflow log."))
    wf.add("Loop: Upload Files", T_LOOP, pos(column + 1, 2), loop_node(1),
           notes="Sequential uploads keep memory flat and stay inside Drive quotas.")
    wf.add("Prepare Upload Binary", T_CODE, pos(column + 2, 3), code(JS_PREPARE_UPLOAD),
           notes="base64 manifest entry -> binary for the Google Drive node.")
    wf.add(
        "Drive: Upload File", T_GDRIVE, pos(column + 3, 3),
        {
            "resource": "file",
            "operation": "upload",
            "inputDataFieldName": "data",
            "name": "={{ $json.file_name }}",
            "driveId": {"__rl": True, "value": "My Drive", "mode": "list",
                        "cachedResultName": "My Drive"},
            "folderId": {"__rl": True, "value": "={{ $json.parent_folder_id }}", "mode": "id"},
            "options": {},
        },
        notes="Native Google Drive node, OAuth2 credential. Uploads into the product folder.",
        **RETRY,
    )
    wf.add("Collect Drive File Ids", T_CODE, pos(column + 2, 2), code(JS_COLLECT_UPLOADS),
           notes="Backup contract for 01: folder id, folder path and every uploaded file id.")
    wf.add("Return: Backup Result", T_NOOP, pos(column + 3, 2), {},
           notes="Terminal node - its item is the sub-workflow return value.")

    wf.link("Resolve Product Folder", "Enumerate Backup Files")
    wf.link("Enumerate Backup Files", "Loop: Upload Files")
    wf.link("Loop: Upload Files", "Collect Drive File Ids", 0)
    wf.link("Loop: Upload Files", "Prepare Upload Binary", 1)
    wf.link("Prepare Upload Binary", "Drive: Upload File")
    wf.link("Drive: Upload File", "Loop: Upload Files")
    wf.link("Collect Drive File Ids", "Return: Backup Result")

    return wf
