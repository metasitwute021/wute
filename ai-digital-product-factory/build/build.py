#!/usr/bin/env python3
"""Generate every artefact of the AI Digital Product Factory.

    python3 build/build.py

Writes:
    workflows/0[1-6]_*.json   importable n8n workflows
    prompts/*.md              the eight OpenAI agent prompt templates
    db/schema.*.sql           PostgreSQL and SQLite schemas

The generated files are the deliverable; this script exists so the embedded
JavaScript and n8n expressions never have to be hand-escaped inside JSON.
"""

from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import prompts  # noqa: E402
import wf01, wf02, wf03, wf04, wf05, wf06  # noqa: E402
from wf06 import DDL_POSTGRES, DDL_SQLITE  # noqa: E402

WORKFLOWS = [
    ("01_master_controller.json", wf01.build),
    ("02_research_engine.json", wf02.build),
    ("03_product_engine.json", wf03.build),
    ("04_publish_engine.json", wf04.build),
    ("05_google_drive_backup.json", wf05.build),
    ("06_database_logger.json", wf06.build),
]

TRIGGER_TYPES = {
    "n8n-nodes-base.scheduleTrigger",
    "n8n-nodes-base.webhook",
    "n8n-nodes-base.manualTrigger",
    "n8n-nodes-base.executeWorkflowTrigger",
    "n8n-nodes-base.errorTrigger",
}

SECRET_MARKERS = ("sk-", "Bearer ey", "client_secret", "refresh_token")


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
        if node["type"] in TRIGGER_TYPES:
            continue
        problems.append(f"{node['name']}: orphan node (nothing connects to it)")

    blob = json.dumps(document)
    for marker in SECRET_MARKERS:
        if marker in blob:
            problems.append(f"possible hardcoded secret marker: {marker}")

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
        workflow = builder()
        document = workflow.to_dict()
        problems = validate(document, filename)
        path = workflow.write(workflows_dir, filename)
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
        fh.write(DDL_POSTGRES + "\n")
    with open(os.path.join(db_dir, "schema.sqlite.sql"), "w", encoding="utf-8") as fh:
        fh.write(DDL_SQLITE + "\n")
    print("[ok] db/                           2 schemas")

    print(f"\n{total_nodes} nodes generated across {len(WORKFLOWS)} workflows")
    if failures:
        print(f"{failures} validation problem(s) found")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
