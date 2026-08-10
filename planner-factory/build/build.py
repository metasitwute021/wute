#!/usr/bin/env python3
"""Generate every artefact of the Planner Factory.

    python3 build/build.py

Writes:
    workflows/*.json   importable n8n workflows
    prompts/*.md       readable copies of the agent prompts
    db/schema.sql      the PostgreSQL schema

The generated files are the deliverable. This script exists so the JavaScript
inside Code nodes never has to be hand-escaped inside JSON, and so a structural
mistake is caught here rather than by n8n after an import.
"""

from __future__ import annotations

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import prompts  # noqa: E402
import wf_etsy  # noqa: E402
import wf_factory  # noqa: E402
from nodes import CLOUD_UNSUPPORTED, CONFIG_EXEMPT, CONFIG_NODE  # noqa: E402
from schema import DDL  # noqa: E402

WORKFLOWS = [
    ("01_planner_factory.json", wf_factory.build),
    ("02_etsy_connect.json", wf_etsy.build),
]

TRIGGER_TYPES = {
    "n8n-nodes-base.scheduleTrigger",
    "n8n-nodes-base.webhook",
    "n8n-nodes-base.manualTrigger",
    "n8n-nodes-base.errorTrigger",
}

# A node that legitimately has no inbound connection.
TERMINAL_OK = {"n8n-nodes-base.respondToWebhook"}

# Patterns that look like a real credential rather than an English word that
# happens to contain them. The build fails rather than committing a key.
SECRET_PATTERNS = [
    (re.compile(r"sk-[A-Za-z0-9_\-]{20,}"), "OpenAI-style API key"),
    (re.compile(r"Bearer\s+ey[A-Za-z0-9._\-]{20,}"), "hardcoded bearer token"),
    (re.compile(r'"client_secret"\s*:\s*"[^"]{8,}"'), "OAuth client secret"),
    (re.compile(r'"refresh_token"\s*:\s*"[^"]{8,}"'), "OAuth refresh token"),
    (re.compile(r"AIza[A-Za-z0-9_\-]{30,}"), "Google API key"),
    (re.compile(r"\bAQ\.[A-Za-z0-9_\-]{30,}"), "Google API key (AQ. form)"),
    (re.compile(r"\bxoxb-[A-Za-z0-9\-]{20,}"), "Slack bot token"),
]


def validate(document: dict) -> list[str]:
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
        if node["type"] in CLOUD_UNSUPPORTED:
            problems.append(f"{node['name']}: n8n Cloud does not ship "
                            f"{node['type']}, and it refuses the whole workflow")

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
    for pattern, sort in SECRET_PATTERNS:
        if pattern.search(blob):
            problems.append(f"possible hardcoded credential ({sort})")

    # Only the config node itself and the error handler may read $env/$vars
    # directly; everything else must go through the config node, because n8n
    # Cloud has no environment variables at all.
    env_ref = re.compile(r"\$(?:env|vars)[.\[]")
    for node in document["nodes"]:
        if node["name"] in CONFIG_EXEMPT:
            continue
        if env_ref.search(json.dumps(node["parameters"])):
            problems.append(f"{node['name']}: reads $env/$vars directly instead "
                            f"of going through {CONFIG_NODE}")

    if CONFIG_NODE not in names:
        problems.append(f"{CONFIG_NODE} node missing")

    # Nodes are addressed by name in Code nodes - $('Name') - and a typo there
    # fails only at run time, on the node that reads it.
    node_ref = re.compile(r"\$\(\\?['\"]([^'\"\\]+)\\?['\"]\)")
    comment = re.compile(r"//[^\\\n]*|/\*.*?\*/", re.S)
    for node in document["nodes"]:
        source = comment.sub(" ", json.dumps(node["parameters"]))
        for ref in set(node_ref.findall(source)):
            if ref not in names:
                problems.append(f"{node['name']}: refers to $('{ref}'), which is "
                                "not a node in this workflow")

    return problems


def main() -> int:
    workflows_dir = os.path.join(ROOT, "workflows")
    prompts_dir = os.path.join(ROOT, "prompts")
    db_dir = os.path.join(ROOT, "db")
    for directory in (workflows_dir, prompts_dir, db_dir):
        os.makedirs(directory, exist_ok=True)

    failures = 0
    total_nodes = 0

    for filename, builder in WORKFLOWS:
        document = builder()
        problems = validate(document)
        path = os.path.join(workflows_dir, filename)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(document, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        total_nodes += len(document["nodes"])

        status = "ok" if not problems else "FAILED"
        print(f"[{status}] {filename:28s} {len(document['nodes']):3d} nodes  "
              f"{os.path.getsize(path) // 1024:4d} KB")
        for problem in problems:
            failures += 1
            print(f"         - {problem}")

    written = prompts.write_markdown(prompts_dir)
    print(f"[ok] prompts/                  {len(written)} agent templates")

    with open(os.path.join(db_dir, "schema.sql"), "w", encoding="utf-8") as fh:
        fh.write(DDL + "\n")
    print("[ok] db/schema.sql             4 tables")

    print(f"\n{total_nodes} nodes across {len(WORKFLOWS)} workflows")
    if failures:
        print(f"{failures} validation problem(s) found")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
