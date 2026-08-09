"""Shared helpers for building the AI Digital Product Factory n8n workflows.

Every workflow JSON under ``workflows/`` is generated from Python so that the
embedded JavaScript (Code nodes) and n8n expressions never have to be escaped
by hand.  Run ``python3 build/build.py`` after editing anything here.
"""

from __future__ import annotations

import json
import os

# --------------------------------------------------------------------------
# Stable workflow ids.  n8n keeps the "id" field on import when it is free,
# which lets the Execute Workflow nodes in 01 resolve their targets.
# --------------------------------------------------------------------------
WF_ID = {
    "00": "ADPF00STARTERTEST",
    "01": "ADPF01MASTERCONTROL",
    "02": "ADPF02RESEARCHENGN",
    "03": "ADPF03PRODUCTENGIN",
    "04": "ADPF04PUBLISHENGIN",
    "05": "ADPF05DRIVEBACKUPX",
    "06": "ADPF06DATABASELOGX",
    # V2 modules
    "07": "ADPF07IDEAFACTORY",
    "08": "ADPF08COSTBUDGETX",
    "09": "ADPF09FEEDBACKLRN",
    "10": "ADPF10DASHBOARDXX",
}

WF_NAME = {
    "00": "ADPF 00 Starter Smoke Test",
    "01": "ADPF 01 Master Controller",
    "02": "ADPF 02 Research Engine",
    "03": "ADPF 03 Product Engine",
    "04": "ADPF 04 Publish Engine",
    "05": "ADPF 05 Google Drive Backup",
    "06": "ADPF 06 Database Logger",
    "07": "ADPF 07 Idea Factory",
    "08": "ADPF 08 Cost and Budget",
    "09": "ADPF 09 Feedback Learning",
    "10": "ADPF 10 Dashboard",
}

PROMPT_VERSION = "v1.0.0"

# Node type constants -------------------------------------------------------
T_SCHEDULE = ("n8n-nodes-base.scheduleTrigger", 1.2)
T_WEBHOOK = ("n8n-nodes-base.webhook", 2)
T_MANUAL = ("n8n-nodes-base.manualTrigger", 1)
T_EXEC_TRIGGER = ("n8n-nodes-base.executeWorkflowTrigger", 1.1)
T_EXEC_WF = ("n8n-nodes-base.executeWorkflow", 1.2)
T_ERROR_TRIGGER = ("n8n-nodes-base.errorTrigger", 1)
T_CODE = ("n8n-nodes-base.code", 2)
T_SET = ("n8n-nodes-base.set", 3.4)
T_IF = ("n8n-nodes-base.if", 2.2)
T_SWITCH = ("n8n-nodes-base.switch", 3.2)
T_HTTP = ("n8n-nodes-base.httpRequest", 4.2)
T_NOOP = ("n8n-nodes-base.noOp", 1)
T_LOOP = ("n8n-nodes-base.splitInBatches", 3)
T_STOP = ("n8n-nodes-base.stopAndError", 1)
T_POSTGRES = ("n8n-nodes-base.postgres", 2.5)
T_EXEC_CMD = ("n8n-nodes-base.executeCommand", 1)
T_GDRIVE = ("n8n-nodes-base.googleDrive", 3)
T_RESPOND = ("n8n-nodes-base.respondToWebhook", 1.1)

COL = 300
ROW = 190


# Injected into every Code node that consumes a list from a model reply.
ASARRAY_JS = """
// Coerce a model-supplied value into an array. The contract says these fields
// are arrays; models answer with a bare string, a comma-joined string or an
// object of values often enough that `x || []` is not a guard at all - it only
// catches null, and a run died on "(tagsOut.tags || []) is not iterable".
// Interpreting the answer beats discarding it: the content is usually right,
// only its container is wrong.
const asArray = (value) => {
  if (Array.isArray(value)) return value;
  if (value === null || value === undefined || value === '') return [];
  if (typeof value === 'string') {
    return value.includes('\\n') || value.includes(',')
      ? value.split(/[,\\n]/).map((s) => s.trim()).filter(Boolean)
      : [value.trim()];
  }
  if (typeof value === 'object') return Object.values(value).flatMap(asArray);
  return [value];
};
""".strip()


# Injected wherever a model reply is read. Keeps the parsers provider-agnostic.
AGENT_CONTENT_JS = """
// One reader for both providers. OpenAI answers with choices[].message.content,
// Gemini with candidates[].content.parts[].text - and a build can target either,
// so every parser in this repo would otherwise need two code paths.
const agentContent = (response) => {
  const openai = response && response.choices && response.choices[0]
    && response.choices[0].message;
  if (openai && typeof openai.content === 'string') return openai.content;
  if (openai && openai.refusal) return '';
  const gemini = response && response.candidates && response.candidates[0];
  if (gemini && gemini.content && Array.isArray(gemini.content.parts)) {
    return gemini.content.parts.map((p) => p && p.text).filter(Boolean).join('');
  }
  return '';
};

// Token counts, normalised to the OpenAI field names the cost tracker records.
const agentUsage = (response) => {
  if (response && response.usage) return response.usage;
  const m = response && response.usageMetadata;
  if (!m) return null;
  return {
    prompt_tokens: m.promptTokenCount || 0,
    completion_tokens: m.candidatesTokenCount || 0,
    total_tokens: m.totalTokenCount || 0,
  };
};

// finish_reason / finishReason, same idea.
const agentFinish = (response) => {
  const openai = response && response.choices && response.choices[0];
  if (openai && openai.finish_reason) return openai.finish_reason;
  const gemini = response && response.candidates && response.candidates[0];
  if (gemini && gemini.finishReason) return String(gemini.finishReason).toLowerCase();
  return 'unknown';
};
""".strip()



def tune_agent_retries(document: dict) -> dict:
    """Back off long enough to outlast a per-minute quota.

    The default is three tries five seconds apart, which is right for a flaky
    connection and useless against a rate limit measured per minute - a free
    Gemini key answers 429 and every retry lands inside the same window. Only
    the header-authenticated agent nodes are touched.
    """
    for node in document["nodes"]:
        if node["type"] != "n8n-nodes-base.httpRequest":
            continue
        if node["parameters"].get("genericAuthType") != "httpHeaderAuth":
            continue
        node["retryOnFail"] = True
        node["maxTries"] = 5
        node["waitBetweenTries"] = 20000
    return document


def rename_text_agents(document: dict) -> dict:
    """Rename the switched agent nodes so the canvas says what it calls.

    A node labelled "OpenAI: Writer AI" that posts to Gemini is a trap for
    whoever opens the workflow next. Only nodes actually switched are renamed -
    the image node keeps its name because it really is OpenAI - and every
    $('OpenAI: ...') reference in the Code nodes and expressions is rewritten
    with it, since those lookups are by name and would otherwise break.
    """
    renames = {}
    for node in document["nodes"]:
        if node["type"] != "n8n-nodes-base.httpRequest":
            continue
        if node["parameters"].get("genericAuthType") != "httpHeaderAuth":
            continue
        if not node["name"].startswith("OpenAI: "):
            continue
        renames[node["name"]] = "Gemini: " + node["name"][len("OpenAI: "):]

    if not renames:
        return document

    blob = json.dumps(document, ensure_ascii=False)
    for old, new in renames.items():
        blob = blob.replace(json.dumps(old)[1:-1], json.dumps(new)[1:-1])
    return json.loads(blob)

def pos(col: float, row: float = 0):
    """Grid position helper so the imported canvas stays readable.

    Half steps are allowed for a node inserted between two existing ones; n8n
    wants whole numbers, so the result is rounded rather than left as a float.
    """
    return [round(col * COL), round(row * ROW)]


class Workflow:
    """Tiny builder that guarantees valid n8n JSON (nodes + connections)."""

    def __init__(self, key: str, tags=None, error_workflow: str | None = None):
        self.key = key
        self.id = WF_ID[key]
        self.name = WF_NAME[key]
        self.nodes: list[dict] = []
        self.connections: dict = {}
        self.tags = tags or ["ai-digital-product-factory"]
        self.error_workflow = error_workflow

    # -- nodes -------------------------------------------------------------
    def add(self, name, node_type, position, params=None, notes="", **extra):
        type_name, type_version = node_type
        if any(n["name"] == name for n in self.nodes):
            raise ValueError(f"duplicate node name: {name}")
        if not notes:
            raise ValueError(f"node '{name}' is missing its comment/notes")
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

    # -- connections -------------------------------------------------------
    def link(self, source, target, source_output=0, target_input=0):
        slot = self.connections.setdefault(source, {"main": []})["main"]
        while len(slot) <= source_output:
            slot.append([])
        slot[source_output].append(
            {"node": target, "type": "main", "index": target_input}
        )

    def chain(self, *names):
        for a, b in zip(names, names[1:]):
            self.link(a, b)

    # -- output ------------------------------------------------------------
    def to_dict(self):
        settings = {
            "executionOrder": "v1",
            "saveManualExecutions": True,
            "saveExecutionProgress": True,
            "saveDataErrorExecution": "all",
            "saveDataSuccessExecution": "all",
            "executionTimeout": 3600,
            "timezone": "Asia/Bangkok",
        }
        if self.error_workflow:
            settings["errorWorkflow"] = self.error_workflow
        return {
            "name": self.name,
            "id": self.id,
            "active": False,
            "nodes": self.nodes,
            "connections": self.connections,
            "settings": settings,
            "pinData": {},
            "staticData": None,
            "meta": {"instanceId": "ai-digital-product-factory"},
            "tags": [{"name": t} for t in self.tags],
            "versionId": PROMPT_VERSION,
        }

    def write(self, out_dir, filename):
        path = os.path.join(out_dir, filename)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(self.to_dict(), fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        return path


def _node_id(wf_key: str, name: str) -> str:
    slug = "".join(c.lower() if c.isalnum() else "-" for c in name)
    while "--" in slug:
        slug = slug.replace("--", "-")
    return f"adpf{wf_key}-{slug.strip('-')}"


# --------------------------------------------------------------------------
# Reusable parameter factories
# --------------------------------------------------------------------------
RETRY = {"retryOnFail": True, "maxTries": 3, "waitBetweenTries": 5000}


def code(js: str, mode: str = "runOnceForAllItems") -> dict:
    return {"mode": mode, "jsCode": js}


# Which provider the text agents call. Set at build time by build.py, because a
# node's credential type is fixed in the JSON and cannot be switched by an
# expression - one provider per generated file, not per run.
TEXT_PROVIDER = "openai"


def set_text_provider(name: str) -> None:
    global TEXT_PROVIDER
    if name not in ("openai", "gemini"):
        raise ValueError(f"unknown text provider: {name}")
    TEXT_PROVIDER = name


def gemini_chat(
    system_expr: str,
    user_expr: str,
    *,
    json_mode: bool = True,
    temperature: float = 0.7,
    max_tokens: int = 2500,
) -> dict:
    """HTTP Request node params for Gemini generateContent.

    Auth is a generic Header Auth credential carrying ``x-goog-api-key``. n8n's
    own Gemini credential type varies by version, and a header credential is
    available on every install and every plan - one fewer thing to be wrong
    about on a machine this repo cannot inspect.

    Gemini has no ``system`` role: the instruction goes in systemInstruction,
    which is the documented equivalent and keeps the prompt library unchanged.
    """
    config = (
        f"temperature: {temperature}, maxOutputTokens: {max_tokens}"
        + (", responseMimeType: 'application/json'" if json_mode else "")
    )
    body = (
        "={{ JSON.stringify({ "
        f"systemInstruction: {{ parts: [{{ text: {system_expr} }}] }}, "
        f"contents: [{{ role: 'user', parts: [{{ text: {user_expr} }}] }}], "
        f"generationConfig: {{ {config} }} "
        "}) }}"
    )
    url = (
        "={{ ($env.GEMINI_API_BASE || 'https://generativelanguage.googleapis.com') "
        "+ '/v1beta/models/' + ($env.GEMINI_MODEL_TEXT || 'gemini-2.5-flash') "
        "+ ':generateContent' }}"
    )
    return {
        "method": "POST",
        "url": url,
        "authentication": "genericCredentialType",
        "genericAuthType": "httpHeaderAuth",
        "sendBody": True,
        "specifyBody": "json",
        "jsonBody": body,
        "options": {"timeout": 180000},
    }



ETSY_TOKEN_NODE = "Etsy: Access Token"


def etsy_token_node() -> dict:
    """HTTP Request node params that trade the refresh token for an access token.

    Etsy access tokens last an hour; refresh tokens last ninety days and Etsy
    returns a fresh one on every exchange. The reply is read by the node after
    this one, which folds the access token into cfg so every Etsy call in the
    run - and in any sub-workflow it starts - can read it.
    """
    body = (
        "={{ 'grant_type=refresh_token&client_id=' "
        "+ encodeURIComponent($env.ETSY_API_KEY) "
        "+ '&refresh_token=' + encodeURIComponent($env.ETSY_REFRESH_TOKEN) }}"
    )
    return {
        "method": "POST",
        "url": "={{ $env.ETSY_API_BASE }}/v3/public/oauth/token",
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

def openai_chat(
    system_expr: str,
    user_expr: str,
    *,
    json_mode: bool = True,
    temperature: float = 0.7,
    max_tokens: int = 2500,
    model_env: str = "OPENAI_MODEL_TEXT",
    model_default: str = "gpt-4.1",
) -> dict:
    """HTTP Request node params for a text agent call.

    Named for the default provider and kept as the single entry point every
    builder already uses, so switching providers touches this file only. Auth
    uses a credential either way - no key is ever stored in the workflow JSON.
    """
    if TEXT_PROVIDER == "gemini":
        return gemini_chat(system_expr, user_expr, json_mode=json_mode,
                           temperature=temperature, max_tokens=max_tokens)
    response_format = (
        "response_format: { type: 'json_object' }, " if json_mode else ""
    )
    body = (
        "={{ JSON.stringify({ "
        f"model: $env.{model_env} || '{model_default}', "
        f"temperature: {temperature}, "
        f"max_tokens: {max_tokens}, "
        f"{response_format}"
        "messages: [ "
        f"{{ role: 'system', content: {system_expr} }}, "
        f"{{ role: 'user', content: {user_expr} }} "
        "] }) }}"
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


def openai_image(prompt_expr: str, size_expr: str, fmt_expr: str) -> dict:
    """HTTP Request node params for POST /v1/images/generations."""
    body = (
        "={{ JSON.stringify({ "
        "model: $env.OPENAI_MODEL_IMAGE || 'gpt-image-1', "
        f"prompt: {prompt_expr}, "
        f"size: {size_expr}, "
        f"output_format: {fmt_expr}, "
        # Per job, not per install. A shop thumbnail and a printable page
        # do not deserve the same spend, and quality is where the money
        # in this pipeline actually goes.
        "quality: $json.quality || $env.OPENAI_IMAGE_QUALITY || 'high', "
        "n: 1 }) }}"
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


def etsy_http(method: str, url_expr: str, *, body_expr: str | None = None,
              multipart: list[dict] | None = None, timeout: int = 120000) -> dict:
    """HTTP Request node params for the Etsy Open API v3.

    Etsy needs both the OAuth2 bearer token *and* the app key header, so the
    key is read from an environment variable instead of being hardcoded.
    """
    params = {
        "method": method,
        "url": url_expr,
        # No n8n credential: Etsy mandates PKCE on the authorisation code flow
        # and n8n's generic OAuth2 credential does not send a code_challenge, so
        # connecting it simply fails. The suite holds a refresh token instead
        # and exchanges it for an access token at the start of each run - which
        # also means one fewer credential to create and keep in step.
        "authentication": "none",
        "sendHeaders": True,
        "headerParameters": {
            "parameters": [
                {"name": "x-api-key", "value": "={{ $env.ETSY_API_KEY }}"},
                # Read from the exchange node in this same workflow rather than
                # from cfg: the token is minted during the run, and Factory
                # Config has already produced its item by then.
                {"name": "Authorization",
                 "value": ("={{ 'Bearer ' + $('" + ETSY_TOKEN_NODE +
                           "').first().json.access_token }}")},
            ]
        },
        "options": {"timeout": timeout},
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


def drive_http(method: str, url_expr: str, *, body_expr: str | None = None) -> dict:
    """HTTP Request node params for the Google Drive REST API (OAuth2)."""
    params = {
        "method": method,
        "url": url_expr,
        "authentication": "predefinedCredentialType",
        "nodeCredentialType": "googleDriveOAuth2Api",
        "options": {"timeout": 60000},
    }
    if body_expr is not None:
        params["sendBody"] = True
        params["specifyBody"] = "json"
        params["jsonBody"] = body_expr
    return params


def if_bool(expr: str) -> dict:
    return {
        "conditions": {
            "options": {
                "caseSensitive": True,
                "leftValue": "",
                "typeValidation": "loose",
                "version": 2,
            },
            "conditions": [
                {
                    "id": "cond-1",
                    "leftValue": expr,
                    "rightValue": "",
                    "operator": {
                        "type": "boolean",
                        "operation": "true",
                        "singleValue": True,
                    },
                }
            ],
            "combinator": "and",
        },
        "looseTypeValidation": True,
        "options": {},
    }


def switch_equals(left_expr: str, keys: list[str], fallback: str | None = "extra") -> dict:
    rules = []
    for idx, key in enumerate(keys):
        rules.append(
            {
                "conditions": {
                    "options": {
                        "caseSensitive": False,
                        "leftValue": "",
                        "typeValidation": "loose",
                        "version": 2,
                    },
                    "conditions": [
                        {
                            "id": f"rule-{idx}",
                            "leftValue": left_expr,
                            "rightValue": key,
                            "operator": {"type": "string", "operation": "equals"},
                        }
                    ],
                    "combinator": "and",
                },
                "renameOutput": True,
                "outputKey": key,
            }
        )
    options = {}
    if fallback:
        options = {"fallbackOutput": fallback, "renameFallbackOutput": "fallback"}
    return {"rules": {"values": rules}, "looseTypeValidation": True, "options": options}


def exec_workflow(key: str, wait: bool = True) -> dict:
    return {
        "workflowId": {
            "__rl": True,
            "value": WF_ID[key],
            "mode": "id",
            "cachedResultName": WF_NAME[key],
        },
        "mode": "once",
        "options": {"waitForSubWorkflow": wait},
    }


def loop_node(batch_size: int = 1) -> dict:
    return {"batchSize": batch_size, "options": {"reset": False}}


# ==========================================================================
# Cloud compatibility: the Factory Config node.
#
# n8n Cloud cannot set environment variables, so `$env.X` (which the first
# version of this suite used everywhere) fails there. Every workflow now gets
# a `Factory Config` Code node right after its trigger that resolves every
# setting once, in this order:
#
#     cfg passed in from the parent workflow   (so you edit 01 only)
#   > n8n Variables ($vars)                    (Cloud UI, plan-dependent)
#   > environment variables ($env)             (self-hosted)
#   > the DEFAULTS below                       (always present)
#
# Everything downstream reads $('Factory Config').first().json.cfg.X, which
# `make_cloud_compatible` rewrites mechanically from the legacy $env.X form.
# ==========================================================================
CONFIG_DEFAULTS: dict = {
    # OpenAI
    "OPENAI_MODEL_TEXT": "gpt-4.1",
    # Text agents when the suite is built with --text-provider gemini. Images
    # stay on OpenAI either way; nothing here changes that.
    "GEMINI_API_BASE": "https://generativelanguage.googleapis.com",
    # An alias, not a pinned version. Google retires a specific model name
    # for new projects without warning - gemini-2.5-flash returned 404 with
    # "no longer available to new users" on a key issued the same day - and
    # the -latest aliases are what that churn is meant to be absorbed by.
    "GEMINI_MODEL_TEXT": "gemini-flash-latest",
    "OPENAI_MODEL_IMAGE": "gpt-image-1",
    "OPENAI_IMAGE_QUALITY": "high",
    # Per-role image quality. The cover is the picture a shopper decides on, so
    # it stays at the top setting; page art is printed but sits behind the
    # cover; the thumbnail is an icon. Raising these raises the bill roughly
    # four-fold per step, so they are the first thing to reach for.
    "IMAGE_QUALITY_COVER": "high",
    "IMAGE_QUALITY_PAGE": "medium",
    "IMAGE_QUALITY_SMALL": "low",
    # Listing previews reuse art already generated for this product. Set to
    # true to have the model draw separate mockups instead.
    "GENERATE_SEPARATE_PREVIEWS": "false",
    "PROMPT_VERSION": "v1.0.0",
    # Etsy - empty means "not configured yet"; the run then skips publishing
    "ETSY_API_BASE": "https://openapi.etsy.com",
    "ETSY_API_KEY": "",
    # Obtained once with the Etsy Auth Helper workflow. Etsy requires PKCE,
    # which n8n's generic OAuth2 credential does not perform, so the suite
    # carries a refresh token and mints its own access token per run.
    "ETSY_REFRESH_TOKEN": "",
    "ETSY_SHOP_ID": "",
    "ETSY_LISTING_STATE": "draft",
    "ETSY_TAXONOMY_ID": 2078,
    # Google Drive
    "GDRIVE_ROOT_FOLDER_ID": "root",
    # Database
    "DB_TYPE": "postgres",
    "DB_SQLITE_PATH": "/home/node/.n8n/adpf.db",
    # Factory behaviour
    "FACTORY_ROTATION": "planner,printable,canva,wallart,resume,spreadsheet,kids,svg",
    "ALERT_WEBHOOK_URL": "",
    # V2 - idea factory
    # 120 ideas still fills the 50 -> 20 -> 5 funnel with room to reject;
    # 200 mainly bought more requests, which a free tier charges for in
    # quota rather than money.
    "IDEA_TARGET_COUNT": 120,
    "IDEA_BATCH_SIZE": 40,
    "DUPLICATE_SIMILARITY_THRESHOLD": 0.62,
    "ALLOW_PRODUCT_REVISION": "false",
    # V2 - budget
    "BUDGET_DAILY_USD": 20,
    "BUDGET_MONTHLY_USD": 300,
    "BUDGET_RUN_RESERVE_USD": 3,
    "OPENAI_IMAGE_UNIT_COST_USD": 0.19,
    "OPENAI_CHAT_RUN_COST_USD": 0.12,
    "OPENAI_PRICE_OVERRIDE_JSON": "{}",
    # V2 - learning
    "LEARNING_WINDOW_DAYS": 30,
    "LEARNING_MIN_SAMPLE": 15,
    "AB_MIN_VIEWS_PER_ARM": 200,
    "AB_MIN_RELATIVE_LIFT": 0.20,
}

CONFIG_NODE_NAME = "Factory Config"

# Nodes that are allowed to keep raw $env/$vars access: the config node itself
# (it is the resolver) and the global error handler in 01, which runs on the
# Error Trigger path where Factory Config has not executed.
CONFIG_EXEMPT_NODES = {CONFIG_NODE_NAME, "Format Global Error"}


def _factory_config_js() -> str:
    defaults = json.dumps(CONFIG_DEFAULTS, ensure_ascii=False, indent=2)
    return (
        "// =====================================================================\n"
        "// FACTORY CONFIG - ศูนย์รวมค่าตั้งค่าของโรงงานทั้งหมด\n"
        "//\n"
        "// วิธีแก้ค่า (เลือกอย่างใดอย่างหนึ่ง):\n"
        "//   1. แก้ตัวเลข/ข้อความใน DEFAULTS ข้างล่างนี้ตรง ๆ (ง่ายสุด ใช้ได้ทุกแพลน)\n"
        "//   2. หรือตั้งใน n8n Variables (Settings > Variables) ชื่อเดียวกัน - จะทับ DEFAULTS\n"
        "//   3. หรือตั้ง environment variable (เฉพาะ self-hosted) - จะทับ DEFAULTS เช่นกัน\n"
        "//\n"
        "// แก้ที่ workflow 01 ตัวเดียวพอ: sub-workflow ทุกตัวรับ cfg ต่อจากแม่อัตโนมัติ\n"
        "// =====================================================================\n"
        f"const DEFAULTS = {defaults};\n"
        "\n"
        "const first = $input.first();\n"
        "const incoming = first && first.json ? first.json : {};\n"
        "const parentCfg = incoming.cfg && typeof incoming.cfg === 'object' ? incoming.cfg : {};\n"
        "\n"
        "// ทั้ง $vars และ $env อาจไม่มีอยู่เลย (n8n Cloud) - แตะผ่าน try เท่านั้น\n"
        "const readVars = (key) => {\n"
        "  try {\n"
        "    if (typeof $vars !== 'undefined' && $vars[key] !== undefined && $vars[key] !== '') {\n"
        "      return $vars[key];\n"
        "    }\n"
        "  } catch (e) { /* Variables not available on this plan */ }\n"
        "  return undefined;\n"
        "};\n"
        "const readEnv = (key) => {\n"
        "  try {\n"
        "    if (typeof $env !== 'undefined' && $env[key] !== undefined && $env[key] !== '') {\n"
        "      return $env[key];\n"
        "    }\n"
        "  } catch (e) { /* env access blocked or not present */ }\n"
        "  return undefined;\n"
        "};\n"
        "\n"
        "const cfg = {};\n"
        "const sources = {};\n"
        "for (const key of Object.keys(DEFAULTS)) {\n"
        "  if (parentCfg[key] !== undefined) { cfg[key] = parentCfg[key]; sources[key] = 'parent'; continue; }\n"
        "  const fromVars = readVars(key);\n"
        "  if (fromVars !== undefined) { cfg[key] = fromVars; sources[key] = 'variables'; continue; }\n"
        "  const fromEnv = readEnv(key);\n"
        "  if (fromEnv !== undefined) { cfg[key] = fromEnv; sources[key] = 'env'; continue; }\n"
        "  cfg[key] = DEFAULTS[key]; sources[key] = 'default';\n"
        "}\n"
        "\n"
        "return $input.all().map((item) => ({\n"
        "  json: { ...item.json, cfg, cfg_sources: sources },\n"
        "  binary: item.binary,\n"
        "}));\n"
    )


_ENV_REF = None  # compiled lazily to avoid importing re at module import in n8n docs


def make_cloud_compatible(document: dict) -> dict:
    """Insert the Factory Config node and rewrite every ``$env.X`` reference.

    Rewiring: every normal trigger (schedule/webhook/manual/executeWorkflow)
    now feeds Factory Config, which feeds the triggers' original first node.
    The Error Trigger path is left untouched - Factory Config has not run
    there, so its handler keeps its own safe inline reads.
    """
    import re as _re

    global _ENV_REF
    if _ENV_REF is None:
        _ENV_REF = _re.compile(r"\$env\.([A-Z][A-Z0-9_]*)")

    nodes = document["nodes"]
    connections = document["connections"]
    names = {n["name"] for n in nodes}

    if CONFIG_NODE_NAME in names:
        raise ValueError("Factory Config already present - cloudify ran twice?")

    # ---- 1. rewrite $env.X -> $('Factory Config').first().json.cfg.X ------
    replacement = f"$('{CONFIG_NODE_NAME}').first().json.cfg.\\1"
    for node in nodes:
        if node["name"] in CONFIG_EXEMPT_NODES:
            continue
        blob = json.dumps(node["parameters"], ensure_ascii=False)
        new_blob = _ENV_REF.sub(replacement, blob)
        if new_blob != blob:
            node["parameters"] = json.loads(new_blob)

    # ---- 2. find the trigger edges to rewire -------------------------------
    rewire_types = {
        "n8n-nodes-base.scheduleTrigger",
        "n8n-nodes-base.webhook",
        "n8n-nodes-base.manualTrigger",
        "n8n-nodes-base.executeWorkflowTrigger",
    }
    trigger_nodes = [n for n in nodes if n["type"] in rewire_types]
    if not trigger_nodes:
        return document

    targets = set()
    for trigger in trigger_nodes:
        for branch in connections.get(trigger["name"], {}).get("main", []):
            for link in branch:
                targets.add(link["node"])
    if len(targets) != 1:
        raise ValueError(
            f"{document['name']}: triggers feed {len(targets)} different nodes "
            f"({sorted(targets)}) - Factory Config insertion needs exactly one"
        )
    (first_node,) = targets

    # ---- 3. insert the node and rewire -------------------------------------
    anchor = min((n["position"] for n in trigger_nodes), key=lambda p: p[0])
    config_node = {
        "parameters": {"mode": "runOnceForAllItems", "jsCode": _factory_config_js()},
        "id": f"adpf-{document['id'].lower()}-factory-config",
        "name": CONFIG_NODE_NAME,
        "type": "n8n-nodes-base.code",
        "typeVersion": 2,
        "position": [anchor[0] + 150, anchor[1] - 130],
        "notes": (
            "แก้ค่าตั้งค่าทั้งหมดที่ DEFAULTS ในโค้ดของ node นี้ (ดับเบิลคลิกเข้ามาแก้ได้เลย) "
            "รองรับ n8n Cloud - ไม่ต้องใช้ environment variable. "
            "Order: parent cfg > Variables > env > defaults."
        ),
        "notesInFlow": True,
    }
    nodes.insert(1, config_node)

    for trigger in trigger_nodes:
        connections[trigger["name"]] = {
            "main": [[{"node": CONFIG_NODE_NAME, "type": "main", "index": 0}]]
        }
    connections[CONFIG_NODE_NAME] = {
        "main": [[{"node": first_node, "type": "main", "index": 0}]]
    }
    return document
