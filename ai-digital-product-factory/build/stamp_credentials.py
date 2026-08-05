#!/usr/bin/env python3
"""Stamp credential *references* into the generated workflows.

    python3 build/stamp_credentials.py credentials.map.json [outdir]

n8n stores a credential on a node as a pointer - {"id": ..., "name": ...} - and
keeps the secret itself in its own encrypted store. Importing a workflow that
carries only the pointer therefore leaks nothing, while saving the user from
selecting the same credential by hand on every node (03 alone has twelve).

The map file holds pointers only. Anything in it that looks like an actual
secret is rejected, because the output of this script is a file the user sends
around and may well commit.

Map format:

    {
      "openAiApi":            {"id": "aBc123", "name": "OpenAI account"},
      "postgres":             {"id": "dEf456", "name": "Postgres account 2"},
      "googleDriveOAuth2Api": {"id": "gHi789", "name": "Google Drive account"},
      "oAuth2Api":            {"id": "jKl012", "name": "Etsy OAuth2"}
    }

Types absent from the map are left untouched, so a partial map is fine - that
is the normal case while Etsy and Drive are still unconfigured.

The same map may carry a "workflows" section. n8n Cloud assigns its own id when
a workflow is imported and ignores the one in the file, which breaks every
Execute Workflow node in 01 with "Workflow does not exist". Listing the real
ids repairs those pointers:

    "workflows": {"02": "kJ8mQp2xY9vLzN4a", "03": "...", ...}

Keys are the two-digit workflow numbers; only the ones present are rewritten.
"""

from __future__ import annotations

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# Node type -> credential type, for nodes that declare it structurally.
STATIC_TYPES = {
    "n8n-nodes-base.postgres": "postgres",
    "n8n-nodes-base.googleDrive": "googleDriveOAuth2Api",
}

# A pointer is an id and a display name. Reject anything shaped like a secret.
SECRET_SHAPED = re.compile(
    r"sk-[A-Za-z0-9_\-]{20,}|ey[A-Za-z0-9._\-]{30,}|AIza[A-Za-z0-9_\-]{30,}"
)
ALLOWED_MAP_KEYS = {"id", "name"}


def credential_type_of(node: dict) -> str | None:
    """Which credential this node needs, or None if it needs none."""
    if node["type"] in STATIC_TYPES:
        return STATIC_TYPES[node["type"]]
    if node["type"] != "n8n-nodes-base.httpRequest":
        return None
    params = node.get("parameters", {})
    auth = params.get("authentication")
    if auth == "predefinedCredentialType":
        return params.get("nodeCredentialType")
    if auth == "genericCredentialType":
        return params.get("genericAuthType")
    return None


def load_map(path: str) -> tuple[dict, dict]:
    with open(path, encoding="utf-8") as fh:
        raw = json.load(fh)
    if not isinstance(raw, dict):
        raise SystemExit("map file must be a JSON object")
    workflow_ids = raw.pop("workflows", {})
    if not isinstance(workflow_ids, dict):
        raise SystemExit("'workflows' must be an object of {number: id}")
    for cred_type, pointer in raw.items():
        if not isinstance(pointer, dict):
            raise SystemExit(f"{cred_type}: expected an object with id and name")
        extra = set(pointer) - ALLOWED_MAP_KEYS
        if extra:
            raise SystemExit(
                f"{cred_type}: unexpected key(s) {sorted(extra)}. This file takes "
                "pointers only (id, name) - never the secret itself."
            )
        if not pointer.get("id"):
            raise SystemExit(f"{cred_type}: missing 'id'")
        blob = json.dumps(pointer)
        if SECRET_SHAPED.search(blob):
            raise SystemExit(
                f"{cred_type}: value looks like a real credential. Put the "
                "credential's id here, not its key."
            )
    return raw, workflow_ids


def main() -> int:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    pointers, workflow_ids = load_map(sys.argv[1])
    outdir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "dist")
    os.makedirs(outdir, exist_ok=True)

    # WF_ID maps "02" -> the id baked into the file; invert it so a node's
    # current target can be traced back to which workflow it means.
    sys.path.insert(0, HERE)
    from common import WF_ID  # noqa: E402

    by_baked_id = {baked: number for number, baked in WF_ID.items()}

    source_dir = os.path.join(ROOT, "workflows")
    total_stamped = 0
    total_retargeted = 0
    unmapped: dict[str, int] = {}

    for filename in sorted(os.listdir(source_dir)):
        if not filename.endswith(".json"):
            continue
        with open(os.path.join(source_dir, filename), encoding="utf-8") as fh:
            document = json.load(fh)

        stamped = 0
        retargeted = 0
        for node in document["nodes"]:
            if node["type"] == "n8n-nodes-base.executeWorkflow":
                target = node["parameters"].get("workflowId", {})
                number = by_baked_id.get(target.get("value"))
                if number and number in workflow_ids:
                    target["value"] = workflow_ids[number]
                    retargeted += 1
                continue

            cred_type = credential_type_of(node)
            if not cred_type:
                continue
            if cred_type not in pointers:
                unmapped[cred_type] = unmapped.get(cred_type, 0) + 1
                continue
            node["credentials"] = {cred_type: dict(pointers[cred_type])}
            stamped += 1

        with open(os.path.join(outdir, filename), "w", encoding="utf-8") as fh:
            json.dump(document, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        total_stamped += stamped
        total_retargeted += retargeted
        extra = f", {retargeted:2d} sub-workflow link(s) retargeted" if retargeted else ""
        print(f"[ok] {filename:36s} {stamped:2d} node(s) stamped{extra}")

    print(f"\n{total_stamped} credential reference(s) and {total_retargeted} "
          f"sub-workflow link(s) written to {outdir}/")
    for cred_type, count in sorted(unmapped.items()):
        print(f"  note: {count} node(s) need '{cred_type}' - not in the map, "
              "left for the user to select")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
