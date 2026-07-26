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
    "01": "ADPF01MASTERCONTROL",
    "02": "ADPF02RESEARCHENGN",
    "03": "ADPF03PRODUCTENGIN",
    "04": "ADPF04PUBLISHENGIN",
    "05": "ADPF05DRIVEBACKUPX",
    "06": "ADPF06DATABASELOGX",
}

WF_NAME = {
    "01": "ADPF 01 Master Controller",
    "02": "ADPF 02 Research Engine",
    "03": "ADPF 03 Product Engine",
    "04": "ADPF 04 Publish Engine",
    "05": "ADPF 05 Google Drive Backup",
    "06": "ADPF 06 Database Logger",
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

COL = 300
ROW = 190


def pos(col: int, row: int = 0):
    """Grid position helper so the imported canvas stays readable."""
    return [col * COL, row * ROW]


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
    """HTTP Request node params for POST /v1/chat/completions.

    Auth uses the built-in ``openAiApi`` credential, so no key is ever stored
    inside the workflow JSON.
    """
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
        "quality: $env.OPENAI_IMAGE_QUALITY || 'high', "
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
        "authentication": "genericCredentialType",
        "genericAuthType": "oAuth2Api",
        "sendHeaders": True,
        "headerParameters": {
            "parameters": [
                {"name": "x-api-key", "value": "={{ $env.ETSY_API_KEY }}"}
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
