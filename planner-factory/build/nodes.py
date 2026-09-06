"""n8n node construction. One place that knows how n8n JSON is shaped.

The workflows are generated rather than hand-edited so the JavaScript inside
Code nodes never has to be escaped by hand inside JSON, and so a rename or a
new setting is a one-line change instead of a search across megabytes of JSON.
"""

from __future__ import annotations

import json
import os

# --------------------------------------------------------------------------
# Node types. The version numbers matter: n8n refuses to load a node whose
# typeVersion it does not recognise, and silently changes behaviour between
# versions of the same node.
# --------------------------------------------------------------------------
T_MANUAL = ("n8n-nodes-base.manualTrigger", 1)
T_SCHEDULE = ("n8n-nodes-base.scheduleTrigger", 1.2)
T_WEBHOOK = ("n8n-nodes-base.webhook", 2)
T_ERROR_TRIGGER = ("n8n-nodes-base.errorTrigger", 1)
T_CODE = ("n8n-nodes-base.code", 2)
T_SET = ("n8n-nodes-base.set", 3.4)
T_IF = ("n8n-nodes-base.if", 2.2)
T_HTTP = ("n8n-nodes-base.httpRequest", 4.2)
T_NOOP = ("n8n-nodes-base.noOp", 1)
T_LOOP = ("n8n-nodes-base.splitInBatches", 3)
T_POSTGRES = ("n8n-nodes-base.postgres", 2.5)
T_RESPOND = ("n8n-nodes-base.respondToWebhook", 1.1)

# n8n Cloud does not ship these, and it rejects the entire workflow at load
# time - not just the branch - with "Unrecognized node type".
CLOUD_UNSUPPORTED = {"n8n-nodes-base.executeCommand"}

RETRY = {"retryOnFail": True, "maxTries": 3, "waitBetweenTries": 5000}

COL, ROW = 260, 190


def pos(col: float, row: float = 0) -> list[int]:
    """Grid position so the imported canvas is readable instead of a pile."""
    return [round(col * COL), round(row * ROW)]


def code(js: str, mode: str = "runOnceForAllItems") -> dict:
    return {"mode": mode, "jsCode": js}


class Workflow:
    """Builder that guarantees valid n8n JSON (nodes plus connections)."""

    def __init__(self, key: str, name: str):
        self.key = key
        self.name = name
        self.nodes: list[dict] = []
        self.connections: dict = {}

    def add(self, name, node_type, position, params=None, notes="", **extra):
        type_name, type_version = node_type
        if any(n["name"] == name for n in self.nodes):
            raise ValueError(f"duplicate node name: {name}")
        if not notes:
            # Every node carries a comment. This is enforced rather than
            # encouraged because an uncommented generated node is unreadable
            # in the n8n canvas, where the user actually meets it.
            raise ValueError(f"node '{name}' is missing its comment")
        node = {
            "parameters": params or {},
            "id": _node_id(self.key, name),
            "name": name,
            "type": type_name,
            "typeVersion": type_version,
            "position": position,
            "notes": notes,
            "notesInFlow": True,
        }
        node.update(extra)
        self.nodes.append(node)
        return name

    def link(self, source, target, source_output=0, target_input=0):
        slot = self.connections.setdefault(source, {"main": []})["main"]
        while len(slot) <= source_output:
            slot.append([])
        slot[source_output].append({"node": target, "type": "main", "index": target_input})

    def chain(self, *names):
        for a, b in zip(names, names[1:]):
            self.link(a, b)

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "active": False,
            "nodes": self.nodes,
            "connections": self.connections,
            "settings": {
                "executionOrder": "v1",
                "saveManualExecutions": True,
                "saveExecutionProgress": True,
                "saveDataErrorExecution": "all",
                "saveDataSuccessExecution": "all",
                "executionTimeout": 3600,
                "timezone": "Asia/Bangkok",
            },
            "pinData": {},
            "staticData": None,
            "meta": {"instanceId": "planner-factory"},
            "tags": [{"name": "planner-factory"}],
        }


def _node_id(key: str, name: str) -> str:
    slug = "".join(c.lower() if c.isalnum() else "-" for c in name)
    while "--" in slug:
        slug = slug.replace("--", "-")
    return f"pf{key}-{slug.strip('-')}"


# --------------------------------------------------------------------------
# Settings
#
# n8n Cloud has no environment variables and Variables are plan-dependent, so
# the single source of truth is a Code node the user can open and edit. Order:
# Variables > env > the defaults below.
# --------------------------------------------------------------------------
CONFIG_NODE = "Planner Config"

CONFIG_DEFAULTS: dict = {
    # ---- OpenAI ----------------------------------------------------------
    "OPENAI_MODEL_TEXT": "gpt-4.1",
    "OPENAI_MODEL_IMAGE": "gpt-image-1",
    # Quality is where the money goes: each step up is roughly four times the
    # price. The cover is what a shopper decides on, so it stays high; the
    # section art sits inside the file; the shop thumbnail is an icon.
    "IMAGE_QUALITY_COVER": "high",
    "IMAGE_QUALITY_SECTION": "medium",
    "IMAGE_QUALITY_THUMB": "low",

    # ---- what to build ---------------------------------------------------
    # Blank year means undated: the buyer writes the dates, and the product
    # does not become worthless every January. Set a year (e.g. 2027) to print
    # real calendars instead.
    "PLANNER_YEAR": "",
    "WEEK_STARTS_MONDAY": "true",
    # A4 portrait. Letter is 612 x 792 if you sell mainly to the US.
    "PAGE_WIDTH_PT": 595.28,
    "PAGE_HEIGHT_PT": 841.89,
    "SECTION_ART_COUNT": 2,

    # ---- Etsy ------------------------------------------------------------
    "ETSY_API_BASE": "https://openapi.etsy.com",
    "ETSY_API_KEY": "",
    # Etsy mandates PKCE on the authorisation-code flow and n8n's generic
    # OAuth2 credential does not send a code_challenge, so it simply cannot
    # connect. The factory holds a refresh token instead and mints an access
    # token per run. Get one with the "Etsy Connect" workflow.
    "ETSY_REFRESH_TOKEN": "",
    "ETSY_SHOP_ID": "",
    # Etsy rejects a listing with the wrong taxonomy, and the right id is not
    # guessable - "Etsy Connect" looks it up for you. Empty stops publishing
    # with a clear message rather than filing the planner under the wrong shelf.
    "ETSY_TAXONOMY_ID": "",
    "ETSY_LISTING_STATE": "draft",
    "ETSY_PRICE_USD": 12,
    "ETSY_QUANTITY": 999,

    # ---- Google Drive ----------------------------------------------------
    "GDRIVE_FOLDER_ID": "",

    # ---- housekeeping ----------------------------------------------------
    "ALERT_WEBHOOK_URL": "",
    "PROMPT_VERSION": "planner-v1",
}

CONFIG_EXEMPT = {CONFIG_NODE, "Format Error"}


def config_js() -> str:
    """The Planner Config Code node body."""
    defaults = json.dumps(CONFIG_DEFAULTS, ensure_ascii=False, indent=2)
    return f"""// =====================================================================
// PLANNER CONFIG - แก้ค่าตั้งค่าทั้งหมดได้ที่นี่ที่เดียว
//
// ดับเบิลคลิก node นี้ แล้วแก้ตัวเลข/ข้อความใน DEFAULTS ข้างล่างได้เลย
// (หรือจะตั้งใน n8n Variables / environment variable ชื่อเดียวกันก็ได้ - จะทับ DEFAULTS)
//
// ค่าที่ต้องใส่ก่อนขายจริง: ETSY_API_KEY, ETSY_REFRESH_TOKEN, ETSY_SHOP_ID,
// ETSY_TAXONOMY_ID  (หาได้จาก workflow "Etsy Connect")
// =====================================================================
const DEFAULTS = {defaults};

const first = $input.first();
const incoming = first && first.json ? first.json : {{}};

// ทั้ง $vars และ $env อาจไม่มีอยู่เลยบน n8n Cloud - แตะผ่าน try เท่านั้น
const read = (source, key) => {{
  try {{
    const bag = source === 'vars' ? $vars : $env;
    if (typeof bag !== 'undefined' && bag[key] !== undefined && bag[key] !== '') {{
      return bag[key];
    }}
  }} catch (e) {{ /* not available on this plan */ }}
  return undefined;
}};

const cfg = {{}};
const sources = {{}};
for (const key of Object.keys(DEFAULTS)) {{
  const fromVars = read('vars', key);
  if (fromVars !== undefined) {{ cfg[key] = fromVars; sources[key] = 'variables'; continue; }}
  const fromEnv = read('env', key);
  if (fromEnv !== undefined) {{ cfg[key] = fromEnv; sources[key] = 'env'; continue; }}
  cfg[key] = DEFAULTS[key]; sources[key] = 'default';
}}

return [{{ json: {{ ...incoming, cfg, cfg_sources: sources }} }}];
"""


def cfg(key: str) -> str:
    """Expression fragment reading one setting."""
    return f"$('{CONFIG_NODE}').first().json.cfg.{key}"


# --------------------------------------------------------------------------
# HTTP node factories. No API key is ever written into a workflow file:
# OpenAI and Drive use n8n credentials, Etsy reads its key from the config
# node, which the user fills in themselves.
# --------------------------------------------------------------------------
def openai_chat(system_expr: str, user_expr: str, *, temperature: float = 0.7,
                max_tokens: int = 4000, json_mode: bool = True) -> dict:
    response_format = "response_format: { type: 'json_object' }, " if json_mode else ""
    body = (
        "={{ JSON.stringify({ "
        f"model: {cfg('OPENAI_MODEL_TEXT')} || 'gpt-4.1', "
        f"temperature: {temperature}, max_tokens: {max_tokens}, {response_format}"
        f"messages: [ {{ role: 'system', content: {system_expr} }}, "
        f"{{ role: 'user', content: {user_expr} }} ] }}) }}"
    )
    return {
        "method": "POST",
        "url": "https://api.openai.com/v1/chat/completions",
        "authentication": "predefinedCredentialType",
        "nodeCredentialType": "openAiApi",
        "sendBody": True,
        "specifyBody": "json",
        "jsonBody": body,
        "options": {"timeout": 180000},
    }


def openai_image(prompt_expr: str, size_expr: str, quality_expr: str) -> dict:
    """POST /v1/images/generations, always as JPEG.

    JPEG because a JPEG byte stream is a valid PDF image stream as-is; PNG
    would have to be inflated and re-filtered inside a Code node.
    """
    body = (
        "={{ JSON.stringify({ "
        f"model: {cfg('OPENAI_MODEL_IMAGE')} || 'gpt-image-1', "
        f"prompt: {prompt_expr}, size: {size_expr}, "
        f"quality: {quality_expr}, output_format: 'jpeg', n: 1 }}) }}"
    )
    return {
        "method": "POST",
        "url": "https://api.openai.com/v1/images/generations",
        "authentication": "predefinedCredentialType",
        "nodeCredentialType": "openAiApi",
        "sendBody": True,
        "specifyBody": "json",
        "jsonBody": body,
        "options": {"timeout": 300000},
    }


ETSY_TOKEN_NODE = "Etsy: Access Token"


def etsy_token() -> dict:
    """Trade the ninety-day refresh token for a one-hour access token."""
    body = (
        "={{ 'grant_type=refresh_token&client_id=' "
        f"+ encodeURIComponent({cfg('ETSY_API_KEY')}) "
        f"+ '&refresh_token=' + encodeURIComponent({cfg('ETSY_REFRESH_TOKEN')}) }}}}"
    )
    return {
        "method": "POST",
        "url": "={{ " + cfg("ETSY_API_BASE") + " }}/v3/public/oauth/token",
        "authentication": "none",
        "sendHeaders": True,
        "headerParameters": {"parameters": [
            {"name": "Content-Type", "value": "application/x-www-form-urlencoded"},
        ]},
        "sendBody": True,
        "contentType": "raw",
        "rawContentType": "application/x-www-form-urlencoded",
        "body": body,
        "options": {"timeout": 30000},
    }


def etsy_http(method: str, url_expr: str, *, body_expr: str | None = None,
              multipart: list[dict] | None = None, token_from: str = ETSY_TOKEN_NODE,
              timeout: int = 120000) -> dict:
    """Etsy Open API v3 needs the app key header *and* the bearer token."""
    params = {
        "method": method,
        "url": url_expr,
        "authentication": "none",
        "sendHeaders": True,
        "headerParameters": {"parameters": [
            {"name": "x-api-key", "value": "={{ " + cfg("ETSY_API_KEY") + " }}"},
            {"name": "Authorization",
             "value": "={{ 'Bearer ' + $('" + token_from + "').first().json.access_token }}"},
        ]},
        "options": {"timeout": timeout, "response": {"response": {"neverError": False}}},
    }
    if multipart is not None:
        params["contentType"] = "multipart-form-data"
        params["sendBody"] = True
        params["bodyParameters"] = {"parameters": multipart}
    elif body_expr is not None:
        params["sendBody"] = True
        params["specifyBody"] = "json"
        params["jsonBody"] = body_expr
    return params


def drive_upload(name_expr: str, mime_expr: str, binary_property: str) -> dict:
    """Google Drive upload via the n8n node, which handles the OAuth dance."""
    return {
        "name": name_expr,
        "driveId": {"__rl": True, "mode": "list", "value": "My Drive"},
        "folderId": {"__rl": True, "mode": "id", "value": "={{ " + cfg("GDRIVE_FOLDER_ID") + " }}"},
        "inputDataFieldName": binary_property,
        "options": {},
    }


def if_true(expr: str) -> dict:
    """An IF node that branches on a boolean expression."""
    return {
        "conditions": {
            "options": {"caseSensitive": True, "leftValue": "", "typeValidation": "loose",
                        "version": 2},
            "conditions": [{
                "id": "cond",
                "leftValue": expr,
                "rightValue": "",
                "operator": {"type": "boolean", "operation": "true", "singleValue": True},
            }],
            "combinator": "and",
        },
        "looseTypeValidation": True,
        "options": {},
    }


def postgres_query(sql: str) -> dict:
    """A raw query node.

    n8n only evaluates ``{{ }}`` in a field that starts with ``=``; without the
    prefix the braces are sent to PostgreSQL as literal text and the insert
    fails with a syntax error that names a column nobody wrote.
    """
    return {
        "operation": "executeQuery",
        "query": ("=" + sql) if "{{" in sql else sql,
        "options": {},
    }


def loop(batch_size: int = 1) -> dict:
    return {"batchSize": batch_size, "options": {"reset": False}}


def write_workflow(document: dict, out_dir: str, filename: str) -> str:
    path = os.path.join(out_dir, filename)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(document, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    return path
