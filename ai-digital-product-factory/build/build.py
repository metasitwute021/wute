#!/usr/bin/env python3
"""Generate every artefact of the AI Digital Product Factory.

    python3 build/build.py

Writes:
    workflows/*.json          importable n8n workflows (01-06 core, 07-10 V2)
    prompts/*.md              the OpenAI agent prompt templates
    db/schema.*.sql           PostgreSQL and SQLite schemas

The generated files are the deliverable; this script exists so the embedded
JavaScript and n8n expressions never have to be hand-escaped inside JSON.
"""

from __future__ import annotations

import importlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import prompts  # noqa: E402
import wf00  # noqa: E402  (starter smoke test)
import wf01, wf02, wf03, wf04, wf05, wf06  # noqa: E402
import wf07, wf08, wf09, wf10  # noqa: E402  (V2 modules)
from wf06 import DDL_POSTGRES, DDL_SQLITE  # noqa: E402
from schema_v2 import DDL_V2_POSTGRES, DDL_V2_SQLITE  # noqa: E402
from common import (  # noqa: E402
    CONFIG_EXEMPT_NODES, CONFIG_NODE_NAME, make_cloud_compatible,
    rename_text_agents, set_text_provider, tune_agent_retries,
)

WORKFLOWS = [
    ("00_starter_smoke_test.json", wf00.build),
    ("01_master_controller.json", wf01.build),
    ("02_research_engine.json", wf02.build),
    ("03_product_engine.json", wf03.build),
    ("04_publish_engine.json", wf04.build),
    ("05_google_drive_backup.json", wf05.build),
    ("06_database_logger.json", wf06.build),
    # Same workflow with the SQLite branch. Kept out of the default build
    # because n8n Cloud has no Execute Command node and refuses to load a
    # workflow that contains one, unreachable branch or not.
    ("06_database_logger.selfhosted.json", wf06.build_selfhosted),
    # V2 modules
    ("07_idea_factory.json", wf07.build),
    ("08_cost_and_budget.json", wf08.build),
    ("09_feedback_learning.json", wf09.build),
    ("10_dashboard.json", wf10.build),
]

TRIGGER_TYPES = {
    "n8n-nodes-base.scheduleTrigger",
    "n8n-nodes-base.webhook",
    "n8n-nodes-base.manualTrigger",
    "n8n-nodes-base.executeWorkflowTrigger",
    "n8n-nodes-base.errorTrigger",
}

# Nodes that legitimately have no inbound connection.
TERMINAL_OK = {"n8n-nodes-base.respondToWebhook"}

# n8n Cloud does not ship these. It rejects the whole workflow at load time
# with "Unrecognized node type", so an unreachable branch is not safe either.
# Files named *.selfhosted.json are exempt; they exist for that case.
CLOUD_UNSUPPORTED = {"n8n-nodes-base.executeCommand"}

# Patterns that look like a real credential, not English words that happen to
# contain them ("risk-check" is not an OpenAI key).
SECRET_PATTERNS = [
    (re.compile(r"sk-[A-Za-z0-9_\-]{20,}"), "OpenAI-style API key"),
    (re.compile(r"Bearer\s+ey[A-Za-z0-9._\-]{20,}"), "hardcoded bearer token"),
    (re.compile(r'"client_secret"\s*:\s*"[^"]{8,}"'), "OAuth client secret"),
    (re.compile(r'"refresh_token"\s*:\s*"[^"]{8,}"'), "OAuth refresh token"),
    (re.compile(r"AIza[A-Za-z0-9_\-]{30,}"), "Google API key"),
    # Newer Google keys carry an "AQ." prefix instead of "AIza".
    (re.compile(r"\bAQ\.[A-Za-z0-9_\-]{30,}"), "Google API key (AQ. form)"),
    (re.compile(r"\bxoxb-[A-Za-z0-9\-]{20,}"), "Slack bot token"),
]


def validate(document: dict, filename: str) -> list[str]:
    """Structural checks that would otherwise only surface after an import."""
    problems: list[str] = []
    names = [n["name"] for n in document["nodes"]]

    if len(names) != len(set(names)):
        problems.append("duplicate node names")

    for node in document["nodes"]:
        for field in ("name", "type", "typeVersion", "position", "parameters", "notes"):
            if field not in node:
                problems.append(f"{node.get('name', '?')}: missing '{field}'")
        if not node.get("notes"):
            problems.append(f"{node['name']}: empty comment")

    reachable = set()
    for source, outputs in document["connections"].items():
        if source not in names:
            problems.append(f"connection from unknown node '{source}'")
        for branch in outputs.get("main", []):
            for link in branch:
                if link["node"] not in names:
                    problems.append(f"'{source}' points at unknown node '{link['node']}'")
                reachable.add(link["node"])

    for node in document["nodes"]:
        if node["name"] in reachable:
            continue
        if node["type"] in TRIGGER_TYPES or node["type"] in TERMINAL_OK:
            continue
        problems.append(f"{node['name']}: orphan node (nothing connects to it)")

    blob = json.dumps(document)
    for pattern, label in SECRET_PATTERNS:
        if pattern.search(blob):
            problems.append(f"possible hardcoded credential ({label})")

    # ---- Cloud compatibility: no raw $env outside the exempt nodes --------
    # This is the invariant that makes the suite run on n8n Cloud. A single
    # leftover $env.X would reproduce the exact failure the user hit.
    env_ref = re.compile(r"\$env[.\[]")
    for node in document["nodes"]:
        if node["name"] in CONFIG_EXEMPT_NODES:
            continue
        if env_ref.search(json.dumps(node["parameters"])):
            problems.append(f"{node['name']}: raw $env reference survives cloudify")

    # Nodes are addressed by name in Code nodes and expressions - $('Name') -
    # and a rename or a typo there fails only at run time, on the node that
    # reads it. Names are data here, so they can be checked like data.
    node_ref = re.compile(r"\$\(\\?['\"]([^'\"\\]+)\\?['\"]\)")
    comment = re.compile(r"//[^\\\n]*|/\*.*?\*/", re.S)
    for node in document["nodes"]:
        source = comment.sub(" ", json.dumps(node["parameters"]))
        for ref in set(node_ref.findall(source)):
            if ref not in names:
                problems.append(f"{node['name']}: refers to $('{ref}'), which is "
                                "not a node in this workflow")

    if ".selfhosted." not in filename:
        for node in document["nodes"]:
            if node["type"] in CLOUD_UNSUPPORTED:
                problems.append(f"{node['name']}: node type unavailable on n8n Cloud "
                                f"({node['type']})")

    if CONFIG_NODE_NAME not in names and any(
        n["type"] in TRIGGER_TYPES and n["type"] != "n8n-nodes-base.errorTrigger"
        for n in document["nodes"]
    ):
        problems.append("Factory Config node missing")

    return problems


def main() -> int:
    # A node's credential type is fixed in the JSON, so the text provider is a
    # build-time choice rather than a runtime one. Both variants are generated
    # from the same source; only the agent HTTP nodes differ.
    provider = "openai"
    if "--text-provider" in sys.argv:
        provider = sys.argv[sys.argv.index("--text-provider") + 1]
    set_text_provider(provider)
    for module in (wf00, wf01, wf02, wf03, wf04, wf05, wf06, wf07, wf08, wf09, wf10):
        importlib.reload(module)

    suffix = "" if provider == "openai" else f"-{provider}"
    workflows_dir = os.path.join(ROOT, f"workflows{suffix}")
    prompts_dir = os.path.join(ROOT, "prompts")
    db_dir = os.path.join(ROOT, "db")
    for directory in (workflows_dir, prompts_dir, db_dir):
        os.makedirs(directory, exist_ok=True)

    failures = 0
    total_nodes = 0

    for filename, builder in WORKFLOWS:
        workflow = builder()
        document = tune_agent_retries(
            rename_text_agents(make_cloud_compatible(workflow.to_dict())))
        problems = validate(document, filename)
        path = os.path.join(workflows_dir, filename)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(document, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        total_nodes += len(document["nodes"])

        status = "ok" if not problems else "FAILED"
        print(f"[{status}] {filename:32s} {len(document['nodes']):3d} nodes  "
              f"{os.path.getsize(path) // 1024:4d} KB")
        for problem in problems:
            failures += 1
            print(f"         - {problem}")

    written = prompts.write_markdown(prompts_dir)
    print(f"[ok] prompts/                      {len(written)} agent templates")

    with open(os.path.join(db_dir, "schema.postgres.sql"), "w", encoding="utf-8") as fh:
        fh.write(DDL_POSTGRES + "\n\n" + DDL_V2_POSTGRES + "\n")
    with open(os.path.join(db_dir, "schema.sqlite.sql"), "w", encoding="utf-8") as fh:
        fh.write(DDL_SQLITE + "\n\n" + DDL_V2_SQLITE + "\n")
    print("[ok] db/                           2 schemas (V1 + V2)")

    print(f"\n{total_nodes} nodes generated across {len(WORKFLOWS)} workflows"
          f" (text provider: {provider})")
    if failures:
        print(f"{failures} validation problem(s) found")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
